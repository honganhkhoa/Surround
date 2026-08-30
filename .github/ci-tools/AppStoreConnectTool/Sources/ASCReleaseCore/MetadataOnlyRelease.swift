import Darwin
import Foundation

public enum MetadataOnlyManifestBuilder {
    public static let mode = "metadata-only"

    private static let versionLocaleMetadataKeys = [
        "description", "keywords", "marketingUrl", "promotionalText", "supportUrl",
    ]
    public static func build(
        releaseURL: URL,
        configurationURL: URL,
        remoteSnapshotURL: URL,
        expectedSourceVersion: String,
        outputURL: URL,
        reviewHTMLURL: URL
    ) throws -> PublishManifest {
        let release = try ManifestBuilder.decode(NormalizedRelease.self, at: releaseURL)
        let configuration = try LocaleConfiguration.load(from: configurationURL)
        let snapshot = try ManifestBuilder.decode(RemoteSnapshot.self, at: remoteSnapshotURL)
        try SnapshotPreflight.validate(release: release, snapshot: snapshot)

        let captureMetadata: JSONValue = .object([
            "expectedScreenshotCount": .number(0),
            "expectedSourceVersion": .string(expectedSourceVersion),
            "mode": .string(mode),
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
        let generatedAt = ISO8601DateFormatter.releaseTool.string(from: Date())
        let draft = PublishManifest(
            schemaVersion: 1,
            generatedAt: generatedAt,
            release: release,
            remoteSnapshot: snapshot,
            remoteFingerprint: snapshot.fingerprint,
            captureMetadata: captureMetadata,
            localizations: localizations,
            manifestDigest: ""
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifest = PublishManifest(
            schemaVersion: 1,
            generatedAt: generatedAt,
            release: release,
            remoteSnapshot: snapshot,
            remoteFingerprint: snapshot.fingerprint,
            captureMetadata: captureMetadata,
            localizations: localizations,
            manifestDigest: FileIO.sha256(try encoder.encode(draft))
        )
        try verify(
            manifest,
            configuration: configuration,
            expectedSourceVersion: expectedSourceVersion
        )
        try FileIO.writeJSON(manifest, to: outputURL)
        try FileIO.write(
            data: Data(reviewHTML(manifest: manifest).utf8),
            to: reviewHTMLURL
        )
        return manifest
    }

    public static func verify(
        _ manifest: PublishManifest,
        configuration: LocaleConfiguration,
        expectedSourceVersion: String
    ) throws {
        try ManifestBuilder.verify(manifest)
        try ReleaseValidator.validateVersion(expectedSourceVersion)
        let release = manifest.release
        let snapshot = manifest.remoteSnapshot

        guard expectedSourceVersion != release.version else {
            throw ReleaseToolError.validation(
                "Metadata-only source version must differ from the target version"
            )
        }
        guard let metadata = manifest.captureMetadata.objectValue,
              Set(metadata.keys) == Set([
                "expectedScreenshotCount", "expectedSourceVersion", "mode", "screenshotsManaged",
              ]),
              metadata["mode"] == .string(mode),
              metadata["screenshotsManaged"] == .bool(false),
              metadata["expectedScreenshotCount"]?.intValue == 0,
              manifest.localizations.allSatisfy({ $0.screenshotSets.isEmpty }) else {
            throw ReleaseToolError.validation(
                "Metadata-only manifest must explicitly manage zero screenshots"
            )
        }
        guard metadata["expectedSourceVersion"] == .string(expectedSourceVersion) else {
            throw ReleaseToolError.validation(
                "Confirmed source version does not match the reviewed manifest"
            )
        }
        guard configuration.bundleId == release.bundleId,
              configuration.platform == release.platform,
              snapshot.bundleId == release.bundleId,
              snapshot.platform == release.platform,
              snapshot.requestedVersion == release.version else {
            throw ReleaseToolError.validation(
                "Metadata-only locale configuration, release, and snapshot identities differ"
            )
        }
        guard release.versionMetadata.isEmpty else {
            throw ReleaseToolError.validation(
                "What's-New-only release must not patch version-wide metadata"
            )
        }
        let configuredLocales = Set(configuration.localizations.map(\.appStoreLocale))
        let releaseLocales = Set(release.localizations.map(\.appStoreLocale))
        guard configuredLocales == releaseLocales,
              release.localizations.count == configuredLocales.count else {
            throw ReleaseToolError.validation(
                "Metadata-only release must contain exactly the configured locale set"
            )
        }
        for locale in release.localizations {
            guard locale.appMetadata.isEmpty,
                  Set(locale.versionMetadata.keys) == Set(["whatsNew"]),
                  locale.versionMetadata["whatsNew"] == .string(locale.whatsNew) else {
                throw ReleaseToolError.validation(
                    "Metadata-only release may patch only whatsNew for \(locale.appStoreLocale)"
                )
            }
        }
        guard let source = snapshot.sourceVersion,
              source.versionString == expectedSourceVersion,
              ["READY_FOR_DISTRIBUTION", "READY_FOR_SALE"].contains(source.state ?? "") else {
            throw ReleaseToolError.validation(
                "Reviewed source must be live version \(expectedSourceVersion)"
            )
        }
        try validateConfiguredVersion(
            source,
            release: release,
            configuration: configuration,
            context: "reviewed source \(expectedSourceVersion)"
        )
        guard let sourceAppInfo = snapshot.sourceAppInfo,
              ["READY_FOR_DISTRIBUTION", "READY_FOR_SALE"].contains(
                sourceAppInfo.state ?? ""
              ), sourceAppInfo.details != nil else {
            throw ReleaseToolError.validation(
                "Metadata-only review requires a fresh, complete live App Info capture"
            )
        }
        try validateAppInfoLocales(
            sourceAppInfo,
            release: release,
            configuration: configuration,
            context: "reviewed live App Info"
        )
        if snapshot.targetVersion == nil {
            guard snapshot.targetAppInfo == nil,
                  snapshot.appInfo?.id == sourceAppInfo.id else {
                throw ReleaseToolError.remoteDrift(
                    "A draft App Info exists without the reviewed target version"
                )
            }
        } else {
            try validateInheritedTarget(
                snapshot: snapshot,
                release: release,
                configuration: configuration,
                expectedSourceVersion: expectedSourceVersion
            )
        }
    }

    static func validateSourceUnchanged(
        live: RemoteSnapshot,
        reviewed: RemoteSnapshot,
        expectedSourceVersion: String
    ) throws {
        guard live.appId == reviewed.appId,
              live.bundleId == reviewed.bundleId,
              live.platform == reviewed.platform,
              live.requestedVersion == reviewed.requestedVersion,
              let actual = live.sourceVersion,
              let expected = reviewed.sourceVersion,
              let actualAppInfo = live.sourceAppInfo,
              let expectedAppInfo = reviewed.sourceAppInfo,
              actualAppInfo.details != nil,
              expectedAppInfo.details != nil,
              actual.versionString == expectedSourceVersion,
              versionProjection(
                actual,
                includeIDs: true,
                includeWhatsNew: true,
                includeVersionIdentity: true
              ) == versionProjection(
                expected,
                includeIDs: true,
                includeWhatsNew: true,
                includeVersionIdentity: true
              ), appInfoProjection(
                actualAppInfo,
                includeIDs: true,
                includeState: true
              ) == appInfoProjection(
                expectedAppInfo,
                includeIDs: true,
                includeState: true
              ) else {
            throw ReleaseToolError.remoteDrift(
                "Released source \(expectedSourceVersion) changed after review"
            )
        }
    }

    static func validateInheritedTarget(
        snapshot: RemoteSnapshot,
        release: NormalizedRelease,
        configuration: LocaleConfiguration,
        expectedSourceVersion: String
    ) throws {
        guard let source = snapshot.sourceVersion,
              source.versionString == expectedSourceVersion else {
            throw ReleaseToolError.remoteDrift(
                "Live source version is not reviewed version \(expectedSourceVersion)"
            )
        }
        guard let target = snapshot.targetVersion,
              target.versionString == release.version,
              target.state == "PREPARE_FOR_SUBMISSION" else {
            throw ReleaseToolError.validation(
                "Target \(release.version) is not an editable draft"
            )
        }
        try validateConfiguredVersion(
            source,
            release: release,
            configuration: configuration,
            context: "source \(source.versionString)"
        )
        try validateConfiguredVersion(
            target,
            release: release,
            configuration: configuration,
            context: "target \(target.versionString)"
        )

        // App Store Connect copies inherited assets into new resources. Their
        // IDs differ, so preservation is proven by the ordered asset content.
        guard versionProjection(
            target,
            includeIDs: false,
            includeWhatsNew: false,
            includeVersionIdentity: false
        ) == versionProjection(
            source,
            includeIDs: false,
            includeWhatsNew: false,
            includeVersionIdentity: false
        ) else {
            throw ReleaseToolError.remoteDrift(
                "Target metadata or screenshots do not exactly inherit source \(expectedSourceVersion)"
            )
        }
        guard let sourceAppInfo = snapshot.sourceAppInfo,
              let targetAppInfo = snapshot.targetAppInfo,
              sourceAppInfo.details != nil,
              targetAppInfo.details != nil,
              ["READY_FOR_DISTRIBUTION", "READY_FOR_SALE"].contains(
                sourceAppInfo.state ?? ""
              ), targetAppInfo.state == "PREPARE_FOR_SUBMISSION",
              snapshot.appInfo?.id == targetAppInfo.id else {
            throw ReleaseToolError.validation("Draft App Info is missing")
        }
        try validateAppInfoLocales(
            sourceAppInfo,
            release: release,
            configuration: configuration,
            context: "source App Info"
        )
        try validateAppInfoLocales(
            targetAppInfo,
            release: release,
            configuration: configuration,
            context: "target App Info"
        )
        guard appInfoProjection(
            targetAppInfo,
            includeIDs: false,
            includeState: false
        ) == appInfoProjection(
            sourceAppInfo,
            includeIDs: false,
            includeState: false
        ) else {
            throw ReleaseToolError.remoteDrift(
                "Draft App Info metadata differs from the reviewed source App Info"
            )
        }
    }

    static func validateConfiguredVersion(
        _ version: RemoteVersion,
        release: NormalizedRelease,
        configuration: LocaleConfiguration,
        context: String
    ) throws {
        let expectedLocales = Set(configuration.localizations.map(\.appStoreLocale))
        let actualLocales = Set(version.localizations.map(\.locale))
        guard actualLocales == expectedLocales,
              version.localizations.count == expectedLocales.count else {
            throw ReleaseToolError.validation(
                "\(context) locale set must exactly match the configured release locales"
            )
        }

        let expectedTypes = Set(configuration.screenshotFamilies.map(\.displayType))
        for locale in version.localizations {
            let actualTypes = Set(locale.screenshotSets.map(\.displayType))
            guard actualTypes == expectedTypes,
                  locale.screenshotSets.count == configuration.screenshotFamilies.count else {
                throw ReleaseToolError.validation(
                    "\(context) \(locale.locale) screenshot families differ from the configured set"
                )
            }
            for family in configuration.screenshotFamilies {
                guard let set = locale.screenshotSets.first(where: {
                    $0.displayType == family.displayType
                }), set.screenshots.count == family.expectedCount else {
                    throw ReleaseToolError.validation(
                        "\(context) \(locale.locale)/\(family.displayType) must contain "
                            + "\(family.expectedCount) screenshots"
                    )
                }
                for screenshot in set.screenshots {
                    guard screenshot.fileName?.isEmpty == false,
                          screenshot.checksum?.isEmpty == false,
                          screenshotIsComplete(screenshot) else {
                        throw ReleaseToolError.validation(
                            "\(context) \(locale.locale)/\(family.displayType) contains an "
                                + "incomplete screenshot or one without a file name/checksum"
                        )
                    }
                }
            }
        }
    }

    static func validateAppInfoLocales(
        _ info: RemoteAppInfo,
        release: NormalizedRelease,
        configuration: LocaleConfiguration,
        context: String
    ) throws {
        let expected = Set(configuration.localizations.map(\.appStoreLocale))
        guard expected == Set(release.localizations.map(\.appStoreLocale)),
              expected == Set(info.localizations.map(\.locale)),
              info.localizations.count == expected.count else {
            throw ReleaseToolError.validation(
                "\(context) App Info locale set is incomplete or changed"
            )
        }
    }

    static func versionProjection(
        _ version: RemoteVersion,
        includeIDs: Bool,
        includeWhatsNew: Bool,
        includeVersionIdentity: Bool
    ) -> JSONValue {
        var root: [String: JSONValue] = [
            "versionAttributes": objectProjection(
                version.attributes,
                keys: ["platform", "copyright", "releaseType"]
            ),
            "localizations": .array(version.localizations.sorted { $0.locale < $1.locale }.map {
                locale in
                var keys = versionLocaleMetadataKeys
                if includeWhatsNew { keys.append("whatsNew") }
                var object: [String: JSONValue] = [
                    "locale": .string(locale.locale),
                    "metadata": objectProjection(locale.attributes, keys: keys),
                    "screenshotSets": screenshotSetsProjection(
                        locale.screenshotSets,
                        includeIDs: includeIDs
                    ),
                ]
                if includeIDs { object["id"] = .string(locale.id) }
                return .object(object)
            }),
        ]
        if includeVersionIdentity {
            root["id"] = .string(version.id)
            root["versionString"] = .string(version.versionString)
            root["state"] = version.state.map(JSONValue.string) ?? .null
        }
        return .object(root)
    }

    static func appInfoProjection(
        _ info: RemoteAppInfo,
        includeIDs: Bool,
        includeState: Bool
    ) -> JSONValue {
        guard let details = info.details else { return .null }
        var ageRating: [String: JSONValue] = [
            "present": .bool(details.ageRatingDeclarationId != nil),
            "attributes": .object(details.ageRatingDeclarationAttributes),
        ]
        if includeIDs {
            ageRating["id"] = details.ageRatingDeclarationId.map(JSONValue.string) ?? .null
        }
        var root: [String: JSONValue] = [
            "attributes": .object(details.attributes),
            "categories": .object([
                "primaryCategory": details.primaryCategoryId.map(JSONValue.string) ?? .null,
                "primarySubcategoryOne": details.primarySubcategoryOneId.map(JSONValue.string)
                    ?? .null,
                "primarySubcategoryTwo": details.primarySubcategoryTwoId.map(JSONValue.string)
                    ?? .null,
                "secondaryCategory": details.secondaryCategoryId.map(JSONValue.string) ?? .null,
                "secondarySubcategoryOne": details.secondarySubcategoryOneId.map(JSONValue.string)
                    ?? .null,
                "secondarySubcategoryTwo": details.secondarySubcategoryTwoId.map(JSONValue.string)
                    ?? .null,
            ]),
            "ageRatingDeclaration": .object(ageRating),
            "localizations": .array(info.localizations.sorted { $0.locale < $1.locale }.map {
                locale in
                var object: [String: JSONValue] = [
                    "locale": .string(locale.locale),
                    "metadata": .object(locale.attributes),
                ]
                if includeIDs { object["id"] = .string(locale.id) }
                return .object(object)
            }),
        ]
        if includeIDs {
            root["id"] = .string(info.id)
        }
        if includeState {
            root["state"] = info.state.map(JSONValue.string) ?? .null
        }
        return .object(root)
    }

    static func digest(_ value: JSONValue) throws -> String {
        FileIO.sha256(try FileIO.canonicalData(value))
    }

    private static func objectProjection(
        _ attributes: [String: JSONValue],
        keys: [String]
    ) -> JSONValue {
        .object(Dictionary(uniqueKeysWithValues: keys.map {
            ($0, attributes[$0] ?? .null)
        }))
    }

    private static func screenshotSetsProjection(
        _ sets: [RemoteScreenshotSet],
        includeIDs: Bool
    ) -> JSONValue {
        .array(sets.sorted { $0.displayType < $1.displayType }.map { set in
            var object: [String: JSONValue] = [
                "displayType": .string(set.displayType),
                "screenshots": .array(set.screenshots.map { screenshot in
                    var item: [String: JSONValue] = [
                        "fileName": screenshot.fileName.map(JSONValue.string) ?? .null,
                        "checksum": screenshot.checksum.map {
                            .string($0.lowercased())
                        } ?? .null,
                        "complete": .bool(screenshotIsComplete(screenshot)),
                    ]
                    if includeIDs { item["id"] = .string(screenshot.id) }
                    return .object(item)
                }),
            ]
            if includeIDs { object["id"] = .string(set.id) }
            return .object(object)
        })
    }

    private static func screenshotIsComplete(_ screenshot: RemoteScreenshot) -> Bool {
        screenshot.attributes["assetDeliveryState"]?["state"]?.stringValue == "COMPLETE"
    }

    private static func reviewHTML(manifest: PublishManifest) -> String {
        let source = manifest.remoteSnapshot.sourceVersion
        let screenshotCount = source?.localizations.flatMap(\.screenshotSets)
            .flatMap(\.screenshots).count ?? 0
        let action = manifest.remoteSnapshot.targetVersion == nil
            ? "Create version \(manifest.release.version) from released version "
                + "\(source?.versionString ?? "unknown")"
            : "Update existing editable version \(manifest.release.version)"
        var rows = ""
        for locale in manifest.localizations {
            let notes = locale.versionMetadata["whatsNew"]?.stringValue ?? ""
            rows += "<tr><td><code>\(escape(locale.appStoreLocale))</code></td>"
            rows += "<td>\(escape(notes))</td><td><code>whatsNew</code></td></tr>"
        }
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Metadata-only App Store release \(escape(manifest.release.version))</title>
        <style>
        body{font:15px -apple-system,BlinkMacSystemFont,sans-serif;margin:24px;color:#202124}
        table{border-collapse:collapse;width:100%}th,td{border:1px solid #ddd;padding:10px;text-align:left;vertical-align:top}
        .scope{background:#f5f5f7;padding:16px;border-radius:8px}code{overflow-wrap:anywhere}
        </style></head><body>
        <h1>Metadata-only App Store release \(escape(manifest.release.version))</h1>
        <div class="scope"><strong>Reviewed mutation scope</strong><ul>
        <li>\(escape(action))</li>
        <li>Patch exactly <code>whatsNew</code> for \(manifest.localizations.count) locales</li>
        <li>Patch no App Info or other version-localized fields</li>
        <li>Reuse and verify \(screenshotCount) inherited screenshots; manage zero screenshots</li>
        <li>Upload/select no build and create no App Review submission</li>
        </ul></div>
        <p>Remote fingerprint: <code>\(escape(manifest.remoteFingerprint))</code><br>
        Manifest digest: <code>\(escape(manifest.manifestDigest))</code></p>
        <table><thead><tr><th>Locale</th><th>What’s New</th><th>Only patched key</th></tr></thead>
        <tbody>\(rows)</tbody></table>
        </body></html>
        """
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

struct MetadataOnlyJournalOperation: Codable, Equatable {
    var status: String
    var resourceId: String?
    var startedAt: String
    var completedAt: String?
    var detail: String?
}

struct MetadataOnlyPublishJournal: Codable, Equatable {
    var schemaVersion = 1
    var manifestDigest: String
    var version: String
    var expectedSourceVersion: String
    var startedAt: String
    var completedAt: String?
    var versionCreation: MetadataOnlyJournalOperation?
    var localePatches: [String: MetadataOnlyJournalOperation]
    var targetVersionId: String?
    var targetBaselineDigest: String?
    var appInfoId: String?
    var appInfoBaselineDigest: String?
    var initialWhatsNew: [String: JSONValue]
    var targetLocalizationIds: [String: String]
}

final class MetadataOnlyReleaseLock {
    private static let registryLock = NSLock()
    private static var heldIdentities = Set<String>()

    private let descriptor: Int32
    private let identity: String
    private(set) var isReleased = false

    init(
        bundleId: String,
        platform: String,
        version: String,
        lockRoot: URL? = nil
    ) throws {
        let identity = [bundleId.lowercased(), platform.uppercased(), version]
            .joined(separator: "\u{0}")
        let digest = FileIO.sha256(Data(identity.utf8))
        self.identity = digest
        guard Self.claim(identity: digest) else {
            throw ReleaseToolError.validation(
                "Another metadata-only publisher is already working on "
                    + "\(bundleId) \(platform) \(version)"
            )
        }
        var identityClaimed = true
        defer {
            if identityClaimed { Self.unclaim(identity: digest) }
        }
        let directory = lockRoot ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("surround-app-store-release-locks", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            guard Darwin.chmod(directory.path, S_IRWXU) == 0 else {
                throw ReleaseToolError.file(
                    "Could not secure metadata-only lock directory \(directory.path)"
                )
            }
        } catch let error as ReleaseToolError {
            throw error
        } catch {
            throw ReleaseToolError.file(
                "Could not create metadata-only lock directory: \(error.localizedDescription)"
            )
        }

        let path = directory.appendingPathComponent("\(digest).lock").path
        let opened = Darwin.open(
            path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard opened >= 0 else {
            throw ReleaseToolError.file("Could not open metadata-only release lock \(path)")
        }
        guard Darwin.lockf(opened, F_TLOCK, 0) == 0 else {
            let lockError = errno
            Darwin.close(opened)
            if lockError == EACCES || lockError == EAGAIN {
                throw ReleaseToolError.validation(
                    "Another metadata-only publisher is already working on "
                        + "\(bundleId) \(platform) \(version)"
                )
            }
            throw ReleaseToolError.file("Could not acquire metadata-only release lock \(path)")
        }
        descriptor = opened
        identityClaimed = false

        _ = Darwin.ftruncate(descriptor, 0)
        _ = Darwin.lseek(descriptor, 0, SEEK_SET)
        let marker = Data(
            "pid=\(ProcessInfo.processInfo.processIdentifier) bundle=\(bundleId) "
                .appending("platform=\(platform) version=\(version)\n").utf8
        )
        marker.withUnsafeBytes { bytes in
            _ = Darwin.write(descriptor, bytes.baseAddress, bytes.count)
        }
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        _ = Darwin.lseek(descriptor, 0, SEEK_SET)
        _ = Darwin.lockf(descriptor, F_ULOCK, 0)
        Darwin.close(descriptor)
        Self.unclaim(identity: identity)
    }

    deinit { release() }

    private static func claim(identity: String) -> Bool {
        registryLock.lock()
        defer { registryLock.unlock() }
        return heldIdentities.insert(identity).inserted
    }

    private static func unclaim(identity: String) {
        registryLock.lock()
        heldIdentities.remove(identity)
        registryLock.unlock()
    }
}

public final class MetadataOnlyPublisher {
    private let client: ASCAPIClient
    private let journalURL: URL
    private let configuration: LocaleConfiguration
    private let expectedSourceVersion: String
    private let snapshotProvider: (NormalizedRelease) throws -> RemoteSnapshot
    private let sleeper: (TimeInterval) -> Void

    public init(
        client: ASCAPIClient,
        journalURL: URL,
        configuration: LocaleConfiguration,
        expectedSourceVersion: String,
        snapshotProvider: ((NormalizedRelease) throws -> RemoteSnapshot)? = nil,
        sleeper: @escaping (TimeInterval) -> Void = Thread.sleep
    ) {
        self.client = client
        self.journalURL = journalURL
        self.configuration = configuration
        self.expectedSourceVersion = expectedSourceVersion
        self.snapshotProvider = snapshotProvider ?? { release in
            try SnapshotService(client: client).capture(release: release)
        }
        self.sleeper = sleeper
    }

    public func publish(
        manifest: PublishManifest,
        confirmedVersion: String,
        confirmedManifestDigest: String
    ) throws {
        guard confirmedVersion == manifest.release.version else {
            throw ReleaseToolError.validation(
                "--confirm-version must exactly match \(manifest.release.version)"
            )
        }
        guard confirmedManifestDigest == manifest.manifestDigest else {
            throw ReleaseToolError.validation(
                "--confirm-manifest-digest must exactly match \(manifest.manifestDigest)"
            )
        }
        try MetadataOnlyManifestBuilder.verify(
            manifest,
            configuration: configuration,
            expectedSourceVersion: expectedSourceVersion
        )
        let releaseLock = try MetadataOnlyReleaseLock(
            bundleId: manifest.release.bundleId,
            platform: manifest.release.platform,
            version: manifest.release.version
        )
        defer { releaseLock.release() }

        var journal = try loadOrCreateJournal(manifest: manifest)
        var live = try snapshotProvider(manifest.release)
        try writeEvidenceOnce(live, named: "initial-live-snapshot.json")
        let hasMutationJournal = journal.versionCreation != nil || !journal.localePatches.isEmpty
        if !hasMutationJournal, live.fingerprint != manifest.remoteFingerprint {
            throw ReleaseToolError.remoteDrift(
                "Run prepare-metadata-only again; live state changed after review"
            )
        }
        try MetadataOnlyManifestBuilder.validateSourceUnchanged(
            live: live,
            reviewed: manifest.remoteSnapshot,
            expectedSourceVersion: expectedSourceVersion
        )

        if manifest.remoteSnapshot.targetVersion == nil {
            if live.targetVersion == nil {
                if let operation = journal.versionCreation {
                    throw ReleaseToolError.remoteDrift(
                        "Version creation is journaled as \(operation.status), but the target is absent; "
                            + "do not retry the POST automatically"
                    )
                }
                journal.versionCreation = MetadataOnlyJournalOperation(
                    status: "pending",
                    startedAt: now(),
                    detail: "POST /v1/appStoreVersions; no automatic ambiguous retry"
                )
                try persist(journal)
                guard let source = live.sourceVersion else {
                    throw ReleaseToolError.remoteDrift(
                        "Live source version disappeared before version creation"
                    )
                }
                let createdID = try createVersion(manifest: manifest, source: source)
                journal.versionCreation?.status = "posted"
                journal.versionCreation?.resourceId = createdID
                try persist(journal)
                live = try waitForInheritedTarget(
                    manifest: manifest,
                    expectedTargetID: createdID
                )
            } else {
                guard let operation = journal.versionCreation else {
                    throw ReleaseToolError.remoteDrift(
                        "Target appeared after review without a journaled create operation"
                    )
                }
                if let recordedID = operation.resourceId,
                   live.targetVersion?.id != recordedID {
                    throw ReleaseToolError.remoteDrift(
                        "Journaled version ID differs from the live target"
                    )
                }
                live = try waitForInheritedTarget(
                    manifest: manifest,
                    expectedTargetID: operation.resourceId
                )
            }
            journal.versionCreation?.status = "complete"
            journal.versionCreation?.resourceId = live.targetVersion?.id
            journal.versionCreation?.completedAt = now()
            try persist(journal)
            try writeEvidenceOnce(live, named: "post-create-snapshot.json")
        } else {
            guard live.targetVersion?.id == manifest.remoteSnapshot.targetVersion?.id else {
                throw ReleaseToolError.remoteDrift("Reviewed target version was replaced")
            }
        }

        try establishTargetBaseline(snapshot: live, manifest: manifest, journal: &journal)
        guard let target = live.targetVersion else {
            throw ReleaseToolError.remoteDrift("Target disappeared before localized patching")
        }
        let liveLocales = Dictionary(uniqueKeysWithValues: target.localizations.map {
            ($0.locale, $0)
        })

        for releaseLocale in manifest.release.localizations {
            let locale = releaseLocale.appStoreLocale
            guard case let .string(notes)? = releaseLocale.versionMetadata["whatsNew"],
                  let localization = liveLocales[locale],
                  journal.targetLocalizationIds[locale] == localization.id,
                  let initial = journal.initialWhatsNew[locale] else {
                throw ReleaseToolError.remoteDrift(
                    "Missing reviewed target state for locale \(locale)"
                )
            }
            let current = localization.attributes["whatsNew"] ?? .null
            let desired = JSONValue.string(notes)
            if current == desired {
                if journal.localePatches[locale]?.status != "complete" {
                    journal.localePatches[locale] = MetadataOnlyJournalOperation(
                        status: "complete",
                        resourceId: localization.id,
                        startedAt: now(),
                        completedAt: now(),
                        detail: "adopted exact read-back value; no PATCH needed"
                    )
                    try persist(journal)
                }
                continue
            }
            if journal.localePatches[locale]?.status == "complete" {
                throw ReleaseToolError.remoteDrift(
                    "Completed What's New changed for \(locale)"
                )
            }
            guard current == initial else {
                throw ReleaseToolError.remoteDrift(
                    "Unreviewed What's New drift for \(locale)"
                )
            }
            let before = try fetchLocalizationAttributes(id: localization.id)
            guard versionMetadataProjection(before)
                == versionMetadataProjection(localization.attributes),
                  (before["whatsNew"] ?? .null) == initial else {
                throw ReleaseToolError.remoteDrift(
                    "Localization \(locale) changed immediately before PATCH"
                )
            }
            journal.localePatches[locale] = MetadataOnlyJournalOperation(
                status: "pending",
                resourceId: localization.id,
                startedAt: journal.localePatches[locale]?.startedAt ?? now(),
                detail: "PATCH exactly appStoreVersionLocalizations.whatsNew"
            )
            try persist(journal)
            try patchWhatsNew(id: localization.id, notes: notes)
            let after = try fetchLocalizationAttributes(id: localization.id)
            guard after["whatsNew"] == desired,
                  versionMetadataProjection(after) == versionMetadataProjection(before) else {
                throw ReleaseToolError.api(
                    "Read-back mismatch or collateral metadata change for \(locale)"
                )
            }
            journal.localePatches[locale]?.status = "complete"
            journal.localePatches[locale]?.completedAt = now()
            try persist(journal)
        }

        let final = try snapshotProvider(manifest.release)
        try MetadataOnlyManifestBuilder.validateSourceUnchanged(
            live: final,
            reviewed: manifest.remoteSnapshot,
            expectedSourceVersion: expectedSourceVersion
        )
        try establishTargetBaseline(snapshot: final, manifest: manifest, journal: &journal)
        guard let finalTarget = final.targetVersion else {
            throw ReleaseToolError.api("Target disappeared during final read-back")
        }
        for locale in manifest.release.localizations {
            guard let actual = finalTarget.localizations.first(where: {
                $0.locale == locale.appStoreLocale
            }), actual.attributes["whatsNew"] == locale.versionMetadata["whatsNew"],
                  journal.localePatches[locale.appStoreLocale]?.status == "complete" else {
                throw ReleaseToolError.api(
                    "Final What's New read-back failed for \(locale.appStoreLocale)"
                )
            }
        }
        try FileIO.writeJSON(
            final,
            to: journalURL.deletingLastPathComponent()
                .appendingPathComponent("final-snapshot.json")
        )
        journal.completedAt = now()
        try persist(journal)
    }

    private func loadOrCreateJournal(
        manifest: PublishManifest
    ) throws -> MetadataOnlyPublishJournal {
        if FileManager.default.fileExists(atPath: journalURL.path) {
            let journal = try ManifestBuilder.decode(
                MetadataOnlyPublishJournal.self,
                at: journalURL
            )
            guard journal.schemaVersion == 1,
                  journal.manifestDigest == manifest.manifestDigest,
                  journal.version == manifest.release.version,
                  journal.expectedSourceVersion == expectedSourceVersion else {
                throw ReleaseToolError.validation(
                    "Journal belongs to a different reviewed metadata-only manifest"
                )
            }
            return journal
        }
        let journal = MetadataOnlyPublishJournal(
            manifestDigest: manifest.manifestDigest,
            version: manifest.release.version,
            expectedSourceVersion: expectedSourceVersion,
            startedAt: now(),
            localePatches: [:],
            initialWhatsNew: [:],
            targetLocalizationIds: [:]
        )
        try persist(journal)
        return journal
    }

    private func establishTargetBaseline(
        snapshot: RemoteSnapshot,
        manifest: PublishManifest,
        journal: inout MetadataOnlyPublishJournal
    ) throws {
        try MetadataOnlyManifestBuilder.validateInheritedTarget(
            snapshot: snapshot,
            release: manifest.release,
            configuration: configuration,
            expectedSourceVersion: expectedSourceVersion
        )
        guard let target = snapshot.targetVersion,
              let appInfo = snapshot.targetAppInfo else {
            throw ReleaseToolError.remoteDrift("Target or draft App Info disappeared")
        }
        let targetDigest = try MetadataOnlyManifestBuilder.digest(
            MetadataOnlyManifestBuilder.versionProjection(
                target,
                includeIDs: true,
                includeWhatsNew: false,
                includeVersionIdentity: true
            )
        )
        let appInfoDigest = try MetadataOnlyManifestBuilder.digest(
            MetadataOnlyManifestBuilder.appInfoProjection(
                appInfo,
                includeIDs: true,
                includeState: true
            )
        )
        let localizationIDs = Dictionary(uniqueKeysWithValues: target.localizations.map {
            ($0.locale, $0.id)
        })
        let initialWhatsNew = Dictionary(uniqueKeysWithValues: target.localizations.map {
            ($0.locale, $0.attributes["whatsNew"] ?? .null)
        })

        if let expectedTargetID = journal.targetVersionId {
            guard expectedTargetID == target.id,
                  journal.targetBaselineDigest == targetDigest,
                  journal.appInfoId == appInfo.id,
                  journal.appInfoBaselineDigest == appInfoDigest,
                  journal.targetLocalizationIds == localizationIDs else {
                throw ReleaseToolError.remoteDrift(
                    "Target resources, non-What's-New metadata, or screenshots changed after baseline"
                )
            }
        } else {
            journal.targetVersionId = target.id
            journal.targetBaselineDigest = targetDigest
            journal.appInfoId = appInfo.id
            journal.appInfoBaselineDigest = appInfoDigest
            journal.targetLocalizationIds = localizationIDs
            journal.initialWhatsNew = initialWhatsNew
            try persist(journal)
        }
    }

    private func waitForInheritedTarget(
        manifest: PublishManifest,
        expectedTargetID: String?,
        attempts: Int = 30
    ) throws -> RemoteSnapshot {
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                let snapshot = try snapshotProvider(manifest.release)
                try MetadataOnlyManifestBuilder.validateSourceUnchanged(
                    live: snapshot,
                    reviewed: manifest.remoteSnapshot,
                    expectedSourceVersion: expectedSourceVersion
                )
                if let expectedTargetID, snapshot.targetVersion?.id != expectedTargetID {
                    throw ReleaseToolError.remoteDrift(
                        "Created target version resource ID changed"
                    )
                }
                try MetadataOnlyManifestBuilder.validateInheritedTarget(
                    snapshot: snapshot,
                    release: manifest.release,
                    configuration: configuration,
                    expectedSourceVersion: expectedSourceVersion
                )
                return snapshot
            } catch {
                lastError = error
                if attempt + 1 < attempts { sleeper(2) }
            }
        }
        throw ReleaseToolError.api(
            "Target inheritance did not settle safely: "
                + (lastError?.localizedDescription ?? "unknown error")
        )
    }

    private func createVersion(
        manifest: PublishManifest,
        source: RemoteVersion
    ) throws -> String {
        var attributes: [String: JSONValue] = [
            "versionString": .string(manifest.release.version),
            "platform": .string(manifest.release.platform),
        ]
        if let copyright = source.attributes["copyright"], copyright != .null {
            attributes["copyright"] = copyright
        }
        let body: JSONValue = .object([
            "data": .object([
                "type": .string("appStoreVersions"),
                "attributes": .object(attributes),
                "relationships": .object([
                    "app": .object([
                        "data": .object([
                            "type": .string("apps"),
                            "id": .string(manifest.remoteSnapshot.appId),
                        ]),
                    ]),
                ]),
            ]),
        ])
        let response = try client.request(
            method: "POST",
            path: "/v1/appStoreVersions",
            body: body,
            retryPolicy: .singleAttempt
        )
        guard let id = response?["data"]?["id"]?.stringValue else {
            throw ReleaseToolError.api(
                "Create-version response did not contain a resource ID"
            )
        }
        return id
    }

    private func fetchLocalizationAttributes(id: String) throws -> [String: JSONValue] {
        let response = try client.request(
            method: "GET",
            path: "/v1/appStoreVersionLocalizations/\(id)"
        )
        guard response?["data"]?["id"]?.stringValue == id,
              let attributes = response?["data"]?["attributes"]?.objectValue else {
            throw ReleaseToolError.api(
                "Could not read back version localization \(id)"
            )
        }
        return attributes
    }

    private func patchWhatsNew(id: String, notes: String) throws {
        let body: JSONValue = .object([
            "data": .object([
                "type": .string("appStoreVersionLocalizations"),
                "id": .string(id),
                "attributes": .object(["whatsNew": .string(notes)]),
            ]),
        ])
        _ = try client.request(
            method: "PATCH",
            path: "/v1/appStoreVersionLocalizations/\(id)",
            body: body,
            retryPolicy: .singleAttempt
        )
    }

    private func versionMetadataProjection(_ attributes: [String: JSONValue]) -> JSONValue {
        .object(Dictionary(uniqueKeysWithValues: [
            "description", "keywords", "marketingUrl", "promotionalText", "supportUrl",
        ].map { ($0, attributes[$0] ?? .null) }))
    }

    private func writeEvidenceOnce<T: Encodable>(_ value: T, named name: String) throws {
        let output = journalURL.deletingLastPathComponent().appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: output.path) else { return }
        try FileIO.writeJSON(value, to: output)
    }

    private func persist(_ journal: MetadataOnlyPublishJournal) throws {
        try FileIO.writeJSON(journal, to: journalURL)
    }

    private func now() -> String {
        ISO8601DateFormatter.releaseTool.string(from: Date())
    }
}
