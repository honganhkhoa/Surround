import XCTest
@testable import ASCReleaseCore

final class SnapshotPreflightTests: XCTestCase {
    func testNewLanguageRequiresSubtitle() throws {
        var appMetadata = validAppMetadata
        appMetadata.removeValue(forKey: "subtitle")

        try assertNewLanguageRejected(
            versionMetadata: validVersionMetadata,
            appMetadata: appMetadata,
            missing: "appMetadata.subtitle"
        )
    }

    func testNewLanguageRequiresKeywords() throws {
        var versionMetadata = validVersionMetadata
        versionMetadata["keywords"] = .string(" \n ")

        try assertNewLanguageRejected(
            versionMetadata: versionMetadata,
            appMetadata: validAppMetadata,
            missing: "versionMetadata.keywords"
        )
    }

    func testNewLanguageRequiresPrivacyPolicyURL() throws {
        var appMetadata = validAppMetadata
        appMetadata.removeValue(forKey: "privacyPolicyUrl")

        try assertNewLanguageRejected(
            versionMetadata: validVersionMetadata,
            appMetadata: appMetadata,
            missing: "appMetadata.privacyPolicyUrl"
        )
    }

    func testNewLanguageRequiresName() throws {
        var appMetadata = validAppMetadata
        appMetadata.removeValue(forKey: "name")

        try assertNewLanguageRejected(
            versionMetadata: validVersionMetadata,
            appMetadata: appMetadata,
            missing: "appMetadata.name"
        )
    }

    func testNewLanguageRequiresDescriptionAndSupportURL() throws {
        let release = makeRelease(
            versionMetadata: [
                "whatsNew": .string("New"),
                "keywords": .string("바둑,게임"),
            ],
            appMetadata: validAppMetadata
        )

        XCTAssertThrowsError(try SnapshotPreflight.validate(
            release: release,
            snapshot: makeSnapshot()
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("versionMetadata.description"))
            XCTAssertTrue(error.localizedDescription.contains("versionMetadata.supportUrl"))
        }
    }

    func testNewLanguageAcceptsCompleteRequiredMetadata() throws {
        let release = makeRelease(
            versionMetadata: validVersionMetadata,
            appMetadata: validAppMetadata
        )

        XCTAssertNoThrow(try SnapshotPreflight.validate(
            release: release,
            snapshot: makeSnapshot()
        ))
    }

    func testNewLanguageRejectsNullMetadataOnExistingDraftResources() throws {
        let release = makeRelease(
            versionMetadata: ["whatsNew": .string("New")],
            appMetadata: ["name": .string("Surround 바둑")]
        )

        XCTAssertThrowsError(try SnapshotPreflight.validate(
            release: release,
            snapshot: makeSnapshot(
                targetAttributes: [
                    "description": .string("Description"),
                    "keywords": .null,
                    "supportUrl": .string("https://example.com/support"),
                ],
                appInfoAttributes: [
                    "locale": .string(locale),
                    "name": .string("Surround 바둑"),
                    "subtitle": .null,
                    "privacyPolicyUrl": .null,
                ]
            )
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("appMetadata.subtitle"))
            XCTAssertTrue(error.localizedDescription.contains("versionMetadata.keywords"))
            XCTAssertTrue(error.localizedDescription.contains("appMetadata.privacyPolicyUrl"))
        }
    }

    func testNewLanguageAcceptsRequiredMetadataFromReviewedDraft() throws {
        let release = makeRelease(
            versionMetadata: ["whatsNew": .string("New")],
            appMetadata: [:]
        )

        XCTAssertNoThrow(try SnapshotPreflight.validate(
            release: release,
            snapshot: makeSnapshot(
                targetAttributes: [
                    "description": .string("Description"),
                    "keywords": .string("바둑,게임"),
                    "supportUrl": .string("https://example.com/support"),
                ],
                appInfoAttributes: [
                    "locale": .string(locale),
                    "name": .string("Surround 바둑"),
                    "subtitle": .string("온라인 바둑 클라이언트"),
                    "privacyPolicyUrl": .string("https://example.com/privacy"),
                ]
            )
        ))
    }

    func testNewLanguageExplicitNullDoesNotFallBackToReviewedDraft() throws {
        var versionMetadata = validVersionMetadata
        versionMetadata["keywords"] = .null
        var appMetadata = validAppMetadata
        appMetadata["subtitle"] = .null

        XCTAssertThrowsError(try SnapshotPreflight.validate(
            release: makeRelease(
                versionMetadata: versionMetadata,
                appMetadata: appMetadata
            ),
            snapshot: makeSnapshot(
                targetAttributes: validVersionMetadata,
                appInfoAttributes: validAppMetadata
            )
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("versionMetadata.keywords"))
            XCTAssertTrue(error.localizedDescription.contains("appMetadata.subtitle"))
        }
    }

    func testReleasedLanguageCanInheritMetadata() throws {
        let release = makeRelease(
            versionMetadata: ["whatsNew": .string("New")],
            appMetadata: [:]
        )

        XCTAssertNoThrow(try SnapshotPreflight.validate(
            release: release,
            snapshot: makeSnapshot(
                sourceHasLocale: true,
                appInfoAttributes: ["locale": .string(locale)]
            )
        ))
    }

    private let locale = "ko-KR"

    private var validVersionMetadata: [String: JSONValue] {
        [
            "whatsNew": .string("New"),
            "description": .string("Description"),
            "keywords": .string("바둑,게임"),
            "supportUrl": .string("https://example.com/support"),
        ]
    }

    private var validAppMetadata: [String: JSONValue] {
        [
            "name": .string("Surround 바둑"),
            "subtitle": .string("온라인 바둑 클라이언트"),
            "privacyPolicyUrl": .string("https://example.com/privacy"),
        ]
    }

    private func assertNewLanguageRejected(
        versionMetadata: [String: JSONValue],
        appMetadata: [String: JSONValue],
        missing: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let release = makeRelease(
            versionMetadata: versionMetadata,
            appMetadata: appMetadata
        )

        XCTAssertThrowsError(try SnapshotPreflight.validate(
            release: release,
            snapshot: makeSnapshot()
        ), file: file, line: line) { error in
            XCTAssertTrue(
                error.localizedDescription.contains(missing),
                "Unexpected error: \(error)",
                file: file,
                line: line
            )
        }
    }

    private func makeRelease(
        versionMetadata: [String: JSONValue],
        appMetadata: [String: JSONValue]
    ) -> NormalizedRelease {
        NormalizedRelease(
            version: "2.1",
            bundleId: "com.example.App",
            platform: "IOS",
            sourceReleasePath: "/release.json",
            sourceDigest: "source",
            localizations: [NormalizedLocaleRelease(
                appStoreLocale: locale,
                screenshotConfiguration: "ko-KR",
                whatsNew: "New",
                versionMetadata: versionMetadata,
                appMetadata: appMetadata,
                sourceFiles: [:]
            )],
            versionMetadata: [:]
        )
    }

    private func makeSnapshot(
        sourceHasLocale: Bool = false,
        targetAttributes: [String: JSONValue] = [:],
        appInfoAttributes: [String: JSONValue]? = nil
    ) throws -> RemoteSnapshot {
        let versionLocalization = RemoteLocalization(
            id: "version-locale",
            locale: locale,
            attributes: targetAttributes.merging(["locale": .string(locale)]) { _, value in value },
            screenshotSets: []
        )
        let target = RemoteVersion(
            id: "version",
            versionString: "2.1",
            state: "PREPARE_FOR_SUBMISSION",
            attributes: ["versionString": .string("2.1")],
            localizations: [versionLocalization]
        )
        let sourceLocalization = RemoteLocalization(
            id: "source-locale",
            locale: locale,
            attributes: ["locale": .string(locale)],
            screenshotSets: []
        )
        let source = RemoteVersion(
            id: "source",
            versionString: "2.0",
            state: "READY_FOR_DISTRIBUTION",
            attributes: ["versionString": .string("2.0")],
            localizations: sourceHasLocale ? [sourceLocalization] : []
        )
        let appInfoLocalizations = appInfoAttributes.map {
            [RemoteAppInfoLocalization(
                id: "app-info-locale",
                locale: locale,
                attributes: $0
            )]
        } ?? []
        let appInfo = RemoteAppInfo(
            id: "app-info",
            state: "PREPARE_FOR_SUBMISSION",
            localizations: appInfoLocalizations
        )
        let draft = RemoteSnapshot(
            capturedAt: "now",
            fingerprint: "",
            appId: "app",
            bundleId: "com.example.App",
            platform: "IOS",
            requestedVersion: "2.1",
            targetVersion: target,
            sourceVersion: source,
            appInfo: appInfo
        )
        return RemoteSnapshot(
            capturedAt: draft.capturedAt,
            fingerprint: try SnapshotService.fingerprint(snapshot: draft),
            appId: draft.appId,
            bundleId: draft.bundleId,
            platform: draft.platform,
            requestedVersion: draft.requestedVersion,
            targetVersion: draft.targetVersion,
            sourceVersion: draft.sourceVersion,
            appInfo: draft.appInfo
        )
    }
}
