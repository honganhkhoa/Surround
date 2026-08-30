import CryptoKit
import Foundation
import XCTest
@testable import ASCReleaseCore

final class MetadataOnlyReleaseTests: XCTestCase {
    func testPublisherAcceptsInheritedAssetsWithNewIDsAndUsesOnlyNarrowWrites() throws {
        try withTemporaryDirectory { directory in
            let fixture = try makeFixture()
            var localizationReadCount = 0
            let transport = MetadataOnlyMockTransport { request in
                let method = request.httpMethod ?? ""
                let path = request.url?.path ?? ""
                switch (method, path) {
                case ("POST", "/v1/appStoreVersions"):
                    let body = try self.body(request)
                    let attributes = try XCTUnwrap(
                        body["data"]?["attributes"]?.objectValue
                    )
                    XCTAssertEqual(Set(attributes.keys), Set([
                        "versionString", "platform", "copyright",
                    ]))
                    XCTAssertNil(attributes["releaseType"])
                    XCTAssertEqual(attributes["versionString"], .string("2.2.1"))
                    XCTAssertEqual(attributes["platform"], .string("IOS"))
                    XCTAssertEqual(attributes["copyright"], .string("2026 Example"))
                    XCTAssertEqual(
                        body["data"]?["relationships"]?["app"]?["data"]?["id"],
                        .string("app")
                    )
                    return .json(.object(["data": .object([
                        "type": .string("appStoreVersions"),
                        "id": .string("target-version"),
                    ])]))
                case ("GET", "/v1/appStoreVersionLocalizations/target-locale"):
                    localizationReadCount += 1
                    let attributes = localizationReadCount == 1
                        ? fixture.created.targetVersion!.localizations[0].attributes
                        : fixture.final.targetVersion!.localizations[0].attributes
                    return .json(.object(["data": .object([
                        "type": .string("appStoreVersionLocalizations"),
                        "id": .string("target-locale"),
                        "attributes": .object(attributes),
                    ])]))
                case ("PATCH", "/v1/appStoreVersionLocalizations/target-locale"):
                    let body = try self.body(request)
                    let attributes = try XCTUnwrap(
                        body["data"]?["attributes"]?.objectValue
                    )
                    XCTAssertEqual(attributes, ["whatsNew": .string("New notes")])
                    XCTAssertEqual(body["data"]?["id"], .string("target-locale"))
                    return TransportResponse(data: Data(), statusCode: 204)
                default:
                    XCTFail("Unexpected request \(method) \(path)")
                    return TransportResponse(data: Data(), statusCode: 500)
                }
            }
            let journalURL = directory.appendingPathComponent("metadata-only-journal.json")
            let publisher = MetadataOnlyPublisher(
                client: makeClient(transport),
                journalURL: journalURL,
                configuration: fixture.configuration,
                expectedSourceVersion: "2.2",
                snapshotProvider: MetadataOnlySnapshotSequence([
                    fixture.baseline, fixture.created, fixture.final,
                ]).next,
                sleeper: { _ in }
            )

            try publisher.publish(
                manifest: fixture.manifest,
                confirmedVersion: "2.2.1",
                confirmedManifestDigest: fixture.manifest.manifestDigest
            )

            let writes = transport.requests.filter { $0.httpMethod != "GET" }
            XCTAssertEqual(writes.map { "\($0.httpMethod!) \($0.url!.path)" }, [
                "POST /v1/appStoreVersions",
                "PATCH /v1/appStoreVersionLocalizations/target-locale",
            ])
            XCTAssertFalse(transport.requests.contains {
                $0.url?.path.contains("Screenshot") == true
                    || $0.url?.path.contains("Preview") == true
                    || $0.url?.path.contains("appInfo") == true
            })
            let journal = try ManifestBuilder.decode(
                MetadataOnlyPublishJournal.self,
                at: journalURL
            )
            XCTAssertEqual(journal.versionCreation?.status, "complete")
            XCTAssertEqual(journal.localePatches["en-US"]?.status, "complete")
            XCTAssertNotNil(journal.completedAt)
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("post-create-snapshot.json").path
            ))
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("final-snapshot.json").path
            ))
        }
    }

    func testAmbiguousVersionCreateIsJournaledAndNeverBlindlyRetried() throws {
        try withTemporaryDirectory { directory in
            let fixture = try makeFixture()
            let firstTransport = MetadataOnlyMockTransport { request in
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v1/appStoreVersions")
                return .json(.object(["errors": .array([.object([
                    "detail": .string("ambiguous failure"),
                ])])]), status: 503)
            }
            let journalURL = directory.appendingPathComponent("metadata-only-journal.json")
            let firstPublisher = MetadataOnlyPublisher(
                client: makeClient(firstTransport),
                journalURL: journalURL,
                configuration: fixture.configuration,
                expectedSourceVersion: "2.2",
                snapshotProvider: MetadataOnlySnapshotSequence([fixture.baseline]).next,
                sleeper: { _ in }
            )
            XCTAssertThrowsError(try firstPublisher.publish(
                manifest: fixture.manifest,
                confirmedVersion: "2.2.1",
                confirmedManifestDigest: fixture.manifest.manifestDigest
            ))
            XCTAssertEqual(firstTransport.requests.count, 1)
            let pending = try ManifestBuilder.decode(
                MetadataOnlyPublishJournal.self,
                at: journalURL
            )
            XCTAssertEqual(pending.versionCreation?.status, "pending")

            let retryTransport = MetadataOnlyMockTransport { request in
                XCTFail("Ambiguous create must not be replayed: \(request.url?.path ?? "")")
                return TransportResponse(data: Data(), statusCode: 500)
            }
            let retryPublisher = MetadataOnlyPublisher(
                client: makeClient(retryTransport),
                journalURL: journalURL,
                configuration: fixture.configuration,
                expectedSourceVersion: "2.2",
                snapshotProvider: MetadataOnlySnapshotSequence([fixture.baseline]).next,
                sleeper: { _ in }
            )
            XCTAssertThrowsError(try retryPublisher.publish(
                manifest: fixture.manifest,
                confirmedVersion: "2.2.1",
                confirmedManifestDigest: fixture.manifest.manifestDigest
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("do not retry"))
            }
            XCTAssertTrue(retryTransport.requests.isEmpty)
        }
    }

    func testAmbiguousWhatsNewPatchIsSentOnceAndRemainsPending() throws {
        try withTemporaryDirectory { directory in
            let fixture = try makeFixture()
            var patchCount = 0
            let transport = MetadataOnlyMockTransport { request in
                switch (request.httpMethod ?? "", request.url?.path ?? "") {
                case ("POST", "/v1/appStoreVersions"):
                    return .json(.object(["data": .object([
                        "type": .string("appStoreVersions"),
                        "id": .string("target-version"),
                    ])]))
                case ("GET", "/v1/appStoreVersionLocalizations/target-locale"):
                    return .json(.object(["data": .object([
                        "type": .string("appStoreVersionLocalizations"),
                        "id": .string("target-locale"),
                        "attributes": .object(
                            fixture.created.targetVersion!.localizations[0].attributes
                        ),
                    ])]))
                case ("PATCH", "/v1/appStoreVersionLocalizations/target-locale"):
                    patchCount += 1
                    return .json(.object(["errors": .array([.object([
                        "detail": .string("ambiguous failure"),
                    ])])]), status: 503)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "") \(request.url?.path ?? "")")
                    return TransportResponse(data: Data(), statusCode: 500)
                }
            }
            let journalURL = directory.appendingPathComponent("metadata-only-journal.json")
            let publisher = MetadataOnlyPublisher(
                client: makeClient(transport, maxRetries: 3),
                journalURL: journalURL,
                configuration: fixture.configuration,
                expectedSourceVersion: "2.2",
                snapshotProvider: MetadataOnlySnapshotSequence([
                    fixture.baseline, fixture.created,
                ]).next,
                sleeper: { _ in }
            )

            XCTAssertThrowsError(try publisher.publish(
                manifest: fixture.manifest,
                confirmedVersion: "2.2.1",
                confirmedManifestDigest: fixture.manifest.manifestDigest
            ))
            XCTAssertEqual(patchCount, 1)
            let journal = try ManifestBuilder.decode(
                MetadataOnlyPublishJournal.self,
                at: journalURL
            )
            XCTAssertEqual(journal.localePatches["en-US"]?.status, "pending")
        }
    }

    func testManifestRequiresExactWhatsNewOnlyScopeAndConfirmations() throws {
        let fixture = try makeFixture()
        try MetadataOnlyManifestBuilder.verify(
            fixture.manifest,
            configuration: fixture.configuration,
            expectedSourceVersion: "2.2"
        )

        let expandedReleaseLocale = NormalizedLocaleRelease(
            appStoreLocale: "en-US",
            screenshotConfiguration: "en-US",
            whatsNew: "New notes",
            versionMetadata: [
                "whatsNew": .string("New notes"),
                "description": .string("Unreviewed expansion"),
            ],
            appMetadata: [:],
            sourceFiles: [:]
        )
        let expandedRelease = NormalizedRelease(
            version: "2.2.1",
            bundleId: "com.example.App",
            platform: "IOS",
            sourceReleasePath: "/release.json",
            sourceDigest: "source",
            localizations: [expandedReleaseLocale],
            versionMetadata: [:]
        )
        let expandedManifest = try manifest(
            release: expandedRelease,
            snapshot: fixture.baseline
        )
        XCTAssertThrowsError(try MetadataOnlyManifestBuilder.verify(
            expandedManifest,
            configuration: fixture.configuration,
            expectedSourceVersion: "2.2"
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("only whatsNew"))
        }

        XCTAssertThrowsError(try MetadataOnlyManifestBuilder.verify(
            fixture.manifest,
            configuration: fixture.configuration,
            expectedSourceVersion: "2.1"
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("source version"))
        }
    }

    func testInheritedTargetRejectsAppInfoCategoryAndAgeRatingDrift() throws {
        let fixture = try makeFixture()
        let sourceAppInfo = try XCTUnwrap(fixture.created.sourceAppInfo)
        let cases = [
            appInfo(
                id: "draft-info",
                localeID: "draft-app-locale",
                draft: true,
                primaryCategoryId: "sports"
            ),
            appInfo(
                id: "draft-info",
                localeID: "draft-app-locale",
                draft: true,
                gambling: true
            ),
        ]
        for targetAppInfo in cases {
            let snapshot = try snapshot(
                release: fixture.manifest.release,
                target: try XCTUnwrap(fixture.created.targetVersion),
                source: try XCTUnwrap(fixture.created.sourceVersion),
                sourceAppInfo: sourceAppInfo,
                targetAppInfo: targetAppInfo
            )
            XCTAssertThrowsError(try MetadataOnlyManifestBuilder.validateInheritedTarget(
                snapshot: snapshot,
                release: fixture.manifest.release,
                configuration: fixture.configuration,
                expectedSourceVersion: "2.2"
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("App Info metadata differs"))
            }
        }
    }

    func testMetadataOnlyManifestRejectsLegacyAppInfoWithoutInheritanceDetails() throws {
        let fixture = try makeFixture()
        let complete = try XCTUnwrap(fixture.baseline.sourceAppInfo)
        let legacy = RemoteAppInfo(
            id: complete.id,
            state: complete.state,
            localizations: complete.localizations
        )
        let snapshot = try snapshot(
            release: fixture.manifest.release,
            target: nil,
            source: try XCTUnwrap(fixture.baseline.sourceVersion),
            sourceAppInfo: legacy,
            targetAppInfo: nil
        )
        let manifest = try manifest(release: fixture.manifest.release, snapshot: snapshot)
        XCTAssertThrowsError(try MetadataOnlyManifestBuilder.verify(
            manifest,
            configuration: fixture.configuration,
            expectedSourceVersion: "2.2"
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("fresh, complete live App Info"))
        }
    }

    func testGenericPublisherRejectsMetadataOnlyManifestBeforeSnapshotOrMutation() throws {
        try withTemporaryDirectory { directory in
            let fixture = try makeFixture()
            let transport = MetadataOnlyMockTransport { request in
                XCTFail("Generic publisher must not access API: \(request.url?.path ?? "")")
                return TransportResponse(data: Data(), statusCode: 500)
            }
            let publisher = try Publisher(
                client: makeClient(transport),
                journalURL: directory.appendingPathComponent("generic-journal.json"),
                manifest: fixture.manifest,
                snapshotProvider: { _ in
                    XCTFail("Generic publisher must not take a snapshot")
                    return fixture.baseline
                },
                sleeper: { _ in }
            )
            XCTAssertThrowsError(try publisher.publish(
                manifest: fixture.manifest,
                confirmedVersion: "2.2.1"
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("dedicated metadata-only"))
            }
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }

    func testPublisherRequiresExactVersionAndDigestBeforeReadingLiveState() throws {
        try withTemporaryDirectory { directory in
            let fixture = try makeFixture()
            let transport = MetadataOnlyMockTransport { request in
                XCTFail("Confirmation failure must not access API: \(request.url?.path ?? "")")
                return TransportResponse(data: Data(), statusCode: 500)
            }
            let publisher = MetadataOnlyPublisher(
                client: makeClient(transport),
                journalURL: directory.appendingPathComponent("metadata-only-journal.json"),
                configuration: fixture.configuration,
                expectedSourceVersion: "2.2",
                snapshotProvider: { _ in
                    XCTFail("Confirmation failure must not take a snapshot")
                    return fixture.baseline
                },
                sleeper: { _ in }
            )

            XCTAssertThrowsError(try publisher.publish(
                manifest: fixture.manifest,
                confirmedVersion: "2.2.2",
                confirmedManifestDigest: fixture.manifest.manifestDigest
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("--confirm-version"))
            }
            XCTAssertThrowsError(try publisher.publish(
                manifest: fixture.manifest,
                confirmedVersion: "2.2.1",
                confirmedManifestDigest: String(repeating: "0", count: 64)
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("--confirm-manifest-digest"))
            }
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }

    func testReleaseLockSerializesTargetAcrossHandoffsAndReusesPersistentFile() throws {
        try withTemporaryDirectory { directory in
            let lockRoot = directory.appendingPathComponent("locks", isDirectory: true)
            let first = try MetadataOnlyReleaseLock(
                bundleId: "com.example.App",
                platform: "IOS",
                version: "2.2.1",
                lockRoot: lockRoot
            )
            XCTAssertThrowsError(try MetadataOnlyReleaseLock(
                bundleId: "COM.EXAMPLE.APP",
                platform: "ios",
                version: "2.2.1",
                lockRoot: lockRoot
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("already working"))
            }

            let otherVersion = try MetadataOnlyReleaseLock(
                bundleId: "com.example.App",
                platform: "IOS",
                version: "2.2.2",
                lockRoot: lockRoot
            )
            otherVersion.release()
            first.release()

            // Advisory lock files intentionally persist. Reacquiring the same
            // release after the owner exits proves crash residue is harmless.
            let reacquired = try MetadataOnlyReleaseLock(
                bundleId: "com.example.App",
                platform: "IOS",
                version: "2.2.1",
                lockRoot: lockRoot
            )
            reacquired.release()
        }
    }

    private struct Fixture {
        let configuration: LocaleConfiguration
        let manifest: PublishManifest
        let baseline: RemoteSnapshot
        let created: RemoteSnapshot
        let final: RemoteSnapshot
    }

    private func makeFixture() throws -> Fixture {
        let configuration = LocaleConfiguration(
            bundleId: "com.example.App",
            localizations: [LocaleMapping(
                appStoreLocale: "en-US",
                screenshotConfiguration: "en-US"
            )],
            screenshotFamilies: [ScreenshotFamily(
                name: "iphone",
                directory: "iphone",
                displayType: "APP_IPHONE_67",
                expectedCount: 1,
                pixelWidth: 1_320,
                pixelHeight: 2_868
            )]
        )
        let releaseLocale = NormalizedLocaleRelease(
            appStoreLocale: "en-US",
            screenshotConfiguration: "en-US",
            whatsNew: "New notes",
            versionMetadata: ["whatsNew": .string("New notes")],
            appMetadata: [:],
            sourceFiles: [:]
        )
        let release = NormalizedRelease(
            version: "2.2.1",
            bundleId: "com.example.App",
            platform: "IOS",
            sourceReleasePath: "/release.json",
            sourceDigest: "source",
            localizations: [releaseLocale],
            versionMetadata: [:]
        )
        let sourceScreenshot = screenshot(id: "source-shot")
        let sourceLocale = RemoteLocalization(
            id: "source-locale",
            locale: "en-US",
            attributes: versionLocaleAttributes(whatsNew: .string("Old notes")),
            screenshotSets: [RemoteScreenshotSet(
                id: "source-set",
                displayType: "APP_IPHONE_67",
                screenshots: [sourceScreenshot]
            )]
        )
        let source = RemoteVersion(
            id: "source-version",
            versionString: "2.2",
            state: "READY_FOR_DISTRIBUTION",
            attributes: [
                "versionString": .string("2.2"),
                "platform": .string("IOS"),
                "releaseType": .string("AFTER_APPROVAL"),
                "copyright": .string("2026 Example"),
            ],
            localizations: [sourceLocale]
        )
        let sourceAppInfo = appInfo(id: "source-info", localeID: "source-app-locale", draft: false)
        let baseline = try snapshot(
            release: release,
            target: nil,
            source: source,
            sourceAppInfo: sourceAppInfo,
            targetAppInfo: nil
        )

        let targetLocaleBefore = RemoteLocalization(
            id: "target-locale",
            locale: "en-US",
            attributes: versionLocaleAttributes(whatsNew: .null),
            screenshotSets: [RemoteScreenshotSet(
                id: "target-set",
                displayType: "APP_IPHONE_67",
                screenshots: [screenshot(id: "target-shot")]
            )]
        )
        let targetBefore = targetVersion(locale: targetLocaleBefore)
        let draftAppInfo = appInfo(id: "draft-info", localeID: "draft-app-locale", draft: true)
        let created = try snapshot(
            release: release,
            target: targetBefore,
            source: source,
            sourceAppInfo: sourceAppInfo,
            targetAppInfo: draftAppInfo
        )
        let targetLocaleAfter = RemoteLocalization(
            id: targetLocaleBefore.id,
            locale: targetLocaleBefore.locale,
            attributes: versionLocaleAttributes(whatsNew: .string("New notes")),
            screenshotSets: targetLocaleBefore.screenshotSets
        )
        let final = try snapshot(
            release: release,
            target: targetVersion(locale: targetLocaleAfter),
            source: source,
            sourceAppInfo: sourceAppInfo,
            targetAppInfo: draftAppInfo
        )
        return Fixture(
            configuration: configuration,
            manifest: try manifest(release: release, snapshot: baseline),
            baseline: baseline,
            created: created,
            final: final
        )
    }

    private func manifest(
        release: NormalizedRelease,
        snapshot: RemoteSnapshot
    ) throws -> PublishManifest {
        let capture: JSONValue = .object([
            "expectedScreenshotCount": .number(0),
            "expectedSourceVersion": .string("2.2"),
            "mode": .string("metadata-only"),
            "screenshotsManaged": .bool(false),
        ])
        let localizations = release.localizations.map {
            ManifestLocale(
                appStoreLocale: $0.appStoreLocale,
                versionMetadata: $0.versionMetadata,
                appMetadata: $0.appMetadata,
                screenshotSets: []
            )
        }
        let draft = PublishManifest(
            schemaVersion: 1,
            generatedAt: "now",
            release: release,
            remoteSnapshot: snapshot,
            remoteFingerprint: snapshot.fingerprint,
            captureMetadata: capture,
            localizations: localizations,
            manifestDigest: ""
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return PublishManifest(
            schemaVersion: 1,
            generatedAt: "now",
            release: release,
            remoteSnapshot: snapshot,
            remoteFingerprint: snapshot.fingerprint,
            captureMetadata: capture,
            localizations: localizations,
            manifestDigest: FileIO.sha256(try encoder.encode(draft))
        )
    }

    private func snapshot(
        release: NormalizedRelease,
        target: RemoteVersion?,
        source: RemoteVersion,
        sourceAppInfo: RemoteAppInfo,
        targetAppInfo: RemoteAppInfo?
    ) throws -> RemoteSnapshot {
        let appInfo = targetAppInfo ?? sourceAppInfo
        let draft = RemoteSnapshot(
            capturedAt: "now",
            fingerprint: "",
            appId: "app",
            bundleId: release.bundleId,
            platform: release.platform,
            requestedVersion: release.version,
            targetVersion: target,
            sourceVersion: source,
            appInfo: appInfo,
            sourceAppInfo: sourceAppInfo,
            targetAppInfo: targetAppInfo
        )
        return RemoteSnapshot(
            capturedAt: draft.capturedAt,
            fingerprint: try SnapshotService.fingerprint(snapshot: draft),
            appId: draft.appId,
            bundleId: draft.bundleId,
            platform: draft.platform,
            requestedVersion: draft.requestedVersion,
            targetVersion: target,
            sourceVersion: source,
            appInfo: appInfo,
            sourceAppInfo: sourceAppInfo,
            targetAppInfo: targetAppInfo
        )
    }

    private func targetVersion(locale: RemoteLocalization) -> RemoteVersion {
        RemoteVersion(
            id: "target-version",
            versionString: "2.2.1",
            state: "PREPARE_FOR_SUBMISSION",
            attributes: [
                "versionString": .string("2.2.1"),
                "platform": .string("IOS"),
                "releaseType": .string("AFTER_APPROVAL"),
                "copyright": .string("2026 Example"),
            ],
            localizations: [locale]
        )
    }

    private func versionLocaleAttributes(whatsNew: JSONValue) -> [String: JSONValue] {
        [
            "locale": .string("en-US"),
            "description": .string("Description"),
            "keywords": .string("go"),
            "marketingUrl": .string("https://example.com"),
            "promotionalText": .string("Promotion"),
            "supportUrl": .string("https://example.com/support"),
            "whatsNew": whatsNew,
        ]
    }

    private func appInfo(
        id: String,
        localeID: String,
        draft: Bool,
        primaryCategoryId: String = "games",
        gambling: Bool = false
    ) -> RemoteAppInfo {
        RemoteAppInfo(
            id: id,
            state: draft ? "PREPARE_FOR_SUBMISSION" : "READY_FOR_DISTRIBUTION",
            localizations: [RemoteAppInfoLocalization(
                id: localeID,
                locale: "en-US",
                attributes: [
                    "locale": .string("en-US"),
                    "name": .string("Example"),
                    "subtitle": .string("Play Go"),
                    "privacyPolicyUrl": .string("https://example.com/privacy"),
                ]
            )],
            details: RemoteAppInfoDetails(
                attributes: [
                    "appStoreAgeRating": .string("FOUR_PLUS"),
                    "kidsAgeBand": .null,
                ],
                primaryCategoryId: primaryCategoryId,
                primarySubcategoryOneId: "board",
                primarySubcategoryTwoId: nil,
                secondaryCategoryId: nil,
                secondarySubcategoryOneId: nil,
                secondarySubcategoryTwoId: nil,
                ageRatingDeclarationId: draft ? "draft-rating" : "source-rating",
                ageRatingDeclarationAttributes: [
                    "gambling": .bool(gambling),
                    "unrestrictedWebAccess": .bool(false),
                ]
            )
        )
    }

    private func screenshot(id: String) -> RemoteScreenshot {
        let attributes: [String: JSONValue] = [
            "fileName": .string("01.png"),
            "sourceFileChecksum": .string("0123456789abcdef0123456789abcdef"),
            "assetDeliveryState": .object(["state": .string("COMPLETE")]),
        ]
        return RemoteScreenshot(
            id: id,
            fileName: "01.png",
            checksum: "0123456789abcdef0123456789abcdef",
            attributes: attributes
        )
    }

    private func body(_ request: URLRequest) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(request.httpBody))
    }

    private func makeClient(
        _ transport: MetadataOnlyMockTransport,
        maxRetries: Int = 0
    ) -> ASCAPIClient {
        ASCAPIClient(
            credentials: ASCCredentials(
                keyId: "KEY",
                issuerId: "00000000-0000-0000-0000-000000000000",
                privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation
            ),
            baseURL: URL(string: "https://api.example")!,
            transport: transport,
            maxRetries: maxRetries
        )
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetadataOnlyReleaseTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}

private final class MetadataOnlySnapshotSequence {
    private let snapshots: [RemoteSnapshot]
    private var index = 0

    init(_ snapshots: [RemoteSnapshot]) { self.snapshots = snapshots }

    func next(_: NormalizedRelease) throws -> RemoteSnapshot {
        guard !snapshots.isEmpty else {
            throw ReleaseToolError.api("No mocked metadata-only snapshot")
        }
        defer { index += 1 }
        return snapshots[min(index, snapshots.count - 1)]
    }
}

private final class MetadataOnlyMockTransport: HTTPTransport, @unchecked Sendable {
    private let handler: (URLRequest) throws -> TransportResponse
    private(set) var requests: [URLRequest] = []

    init(_ handler: @escaping (URLRequest) throws -> TransportResponse) {
        self.handler = handler
    }

    func send(_ request: URLRequest) throws -> TransportResponse {
        requests.append(request)
        return try handler(request)
    }
}

private extension TransportResponse {
    static func json(_ value: JSONValue, status: Int = 200) -> TransportResponse {
        TransportResponse(
            data: (try? JSONEncoder().encode(value)) ?? Data(),
            statusCode: status,
            headers: ["content-type": "application/json"]
        )
    }
}
