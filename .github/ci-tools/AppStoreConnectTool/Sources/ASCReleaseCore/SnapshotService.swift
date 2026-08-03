import Foundation

public final class SnapshotService {
    private let client: ASCAPIClient

    public init(client: ASCAPIClient) { self.client = client }

    public func capture(release: NormalizedRelease) throws -> RemoteSnapshot {
        let apps = try client.list(path: "/v1/apps", query: [
            URLQueryItem(name: "filter[bundleId]", value: release.bundleId),
            URLQueryItem(name: "limit", value: "2"),
        ])
        guard apps.count == 1, let appId = apps[0]["id"]?.stringValue else {
            throw ReleaseToolError.api(
                "Expected exactly one app for bundleId \(release.bundleId); found \(apps.count)"
            )
        }

        let rawVersions = try client.list(path: "/v1/apps/\(appId)/appStoreVersions", query: [
            URLQueryItem(name: "filter[platform]", value: release.platform),
            URLQueryItem(name: "limit", value: "200"),
        ])
        let summaries = try rawVersions.map(parseVersionSummary)
        let targetSummary = summaries.first { $0.versionString == release.version }
        if targetSummary == nil,
           let otherDraft = summaries.first(where: { $0.state == "PREPARE_FOR_SUBMISSION" }) {
            throw ReleaseToolError.validation(
                "App Store Connect already has editable version \(otherDraft.versionString); cannot safely prepare \(release.version)"
            )
        }
        let sourceSummary = selectSourceVersion(summaries)
        let target = try targetSummary.map(loadVersion)
        let source: RemoteVersion?
        if sourceSummary?.id == targetSummary?.id { source = target }
        else { source = try sourceSummary.map(loadVersion) }
        let appInfo = try loadAppInfo(appId: appId)

        let fingerprint = try Self.fingerprint(
            appId: appId,
            bundleId: release.bundleId,
            platform: release.platform,
            requestedVersion: release.version,
            targetVersion: target,
            sourceVersion: source,
            appInfo: appInfo
        )
        return RemoteSnapshot(
            capturedAt: ISO8601DateFormatter.releaseTool.string(from: Date()),
            fingerprint: fingerprint,
            appId: appId,
            bundleId: release.bundleId,
            platform: release.platform,
            requestedVersion: release.version,
            targetVersion: target,
            sourceVersion: source,
            appInfo: appInfo
        )
    }

    public static func fingerprint(snapshot: RemoteSnapshot) throws -> String {
        try fingerprint(
            appId: snapshot.appId,
            bundleId: snapshot.bundleId,
            platform: snapshot.platform,
            requestedVersion: snapshot.requestedVersion,
            targetVersion: snapshot.targetVersion,
            sourceVersion: snapshot.sourceVersion,
            appInfo: snapshot.appInfo
        )
    }

    private struct VersionSummary {
        let id: String
        let versionString: String
        let state: String?
        let attributes: [String: JSONValue]
    }

    private func parseVersionSummary(_ value: JSONValue) throws -> VersionSummary {
        guard let id = value["id"]?.stringValue,
              let attributes = value["attributes"]?.objectValue,
              let versionString = attributes["versionString"]?.stringValue else {
            throw ReleaseToolError.api("Malformed appStoreVersions resource")
        }
        return VersionSummary(
            id: id,
            versionString: versionString,
            state: (attributes["appVersionState"] ?? attributes["appStoreState"])?.stringValue,
            attributes: attributes
        )
    }

    private func selectSourceVersion(_ versions: [VersionSummary]) -> VersionSummary? {
        let liveStates = Set(["READY_FOR_SALE", "READY_FOR_DISTRIBUTION"])
        let live = versions.filter { liveStates.contains($0.state ?? "") }
        if let newestLive = live.max(by: { versionLess($0.versionString, $1.versionString) }) {
            return newestLive
        }
        return nil
    }

    private func versionLess(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r }
        }
        return lhs < rhs
    }

    private func loadVersion(_ summary: VersionSummary) throws -> RemoteVersion {
        let rawLocalizations = try client.list(
            path: "/v1/appStoreVersions/\(summary.id)/appStoreVersionLocalizations",
            query: [URLQueryItem(name: "limit", value: "200")]
        )
        var localizations: [RemoteLocalization] = []
        for raw in rawLocalizations {
            guard let id = raw["id"]?.stringValue,
                  let attributes = raw["attributes"]?.objectValue,
                  let locale = attributes["locale"]?.stringValue else {
                throw ReleaseToolError.api("Malformed appStoreVersionLocalizations resource")
            }
            let rawSets = try client.list(
                path: "/v1/appStoreVersionLocalizations/\(id)/appScreenshotSets",
                query: [URLQueryItem(name: "limit", value: "200")]
            )
            var sets: [RemoteScreenshotSet] = []
            for rawSet in rawSets {
                guard let setId = rawSet["id"]?.stringValue,
                      let setAttributes = rawSet["attributes"]?.objectValue,
                      let displayType = setAttributes["screenshotDisplayType"]?.stringValue else {
                    throw ReleaseToolError.api("Malformed appScreenshotSets resource")
                }
                let rawScreenshots = try client.list(
                    path: "/v1/appScreenshotSets/\(setId)/appScreenshots",
                    query: [URLQueryItem(name: "limit", value: "200")]
                )
                let screenshots = try rawScreenshots.map { item -> RemoteScreenshot in
                    guard let screenshotId = item["id"]?.stringValue,
                          let screenshotAttributes = item["attributes"]?.objectValue else {
                        throw ReleaseToolError.api("Malformed appScreenshots resource")
                    }
                    return RemoteScreenshot(
                        id: screenshotId,
                        fileName: screenshotAttributes["fileName"]?.stringValue,
                        checksum: screenshotAttributes["sourceFileChecksum"]?.stringValue,
                        attributes: screenshotAttributes
                    )
                }
                sets.append(RemoteScreenshotSet(
                    id: setId,
                    displayType: displayType,
                    screenshots: screenshots
                ))
            }
            localizations.append(RemoteLocalization(
                id: id,
                locale: locale,
                attributes: attributes,
                screenshotSets: sets.sorted { $0.displayType < $1.displayType }
            ))
        }
        return RemoteVersion(
            id: summary.id,
            versionString: summary.versionString,
            state: summary.state,
            attributes: summary.attributes,
            localizations: localizations.sorted { $0.locale < $1.locale }
        )
    }

    private func loadAppInfo(appId: String) throws -> RemoteAppInfo? {
        let rawInfos = try client.list(
            path: "/v1/apps/\(appId)/appInfos",
            query: [URLQueryItem(name: "limit", value: "200")]
        )
        let parsed: [(id: String, state: String?, attributes: [String: JSONValue])] = try rawInfos.map {
            guard let id = $0["id"]?.stringValue,
                  let attributes = $0["attributes"]?.objectValue else {
                throw ReleaseToolError.api("Malformed appInfos resource")
            }
            return (id, (attributes["state"] ?? attributes["appStoreState"])?.stringValue, attributes)
        }
        guard let selected = parsed.first(where: { $0.state == "PREPARE_FOR_SUBMISSION" })
            ?? parsed.first(where: { ["READY_FOR_DISTRIBUTION", "READY_FOR_SALE"].contains($0.state ?? "") })
            else { return nil }
        let rawLocalizations = try client.list(
            path: "/v1/appInfos/\(selected.id)/appInfoLocalizations",
            query: [URLQueryItem(name: "limit", value: "200")]
        )
        let localizations = try rawLocalizations.map { item -> RemoteAppInfoLocalization in
            guard let id = item["id"]?.stringValue,
                  let attributes = item["attributes"]?.objectValue,
                  let locale = attributes["locale"]?.stringValue else {
                throw ReleaseToolError.api("Malformed appInfoLocalizations resource")
            }
            return RemoteAppInfoLocalization(id: id, locale: locale, attributes: attributes)
        }.sorted { $0.locale < $1.locale }
        return RemoteAppInfo(
            id: selected.id,
            state: selected.state,
            localizations: localizations
        )
    }

    private static func fingerprint(
        appId: String,
        bundleId: String,
        platform: String,
        requestedVersion: String,
        targetVersion: RemoteVersion?,
        sourceVersion: RemoteVersion?,
        appInfo: RemoteAppInfo?
    ) throws -> String {
        let payload = FingerprintPayload(
            appId: appId,
            bundleId: bundleId,
            platform: platform,
            requestedVersion: requestedVersion,
            targetVersion: sanitize(targetVersion),
            sourceVersion: sanitize(sourceVersion),
            appInfo: appInfo.map { info in
                RemoteAppInfo(
                    id: info.id,
                    state: info.state,
                    localizations: info.localizations.map {
                        RemoteAppInfoLocalization(
                            id: $0.id,
                            locale: $0.locale,
                            attributes: filter($0.attributes, keys: [
                                "locale", "name", "subtitle", "privacyPolicyUrl", "privacyChoicesUrl",
                                "privacyPolicyText",
                            ])
                        )
                    }
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return FileIO.sha256(try encoder.encode(payload))
    }

    private struct FingerprintPayload: Codable {
        let appId: String
        let bundleId: String
        let platform: String
        let requestedVersion: String
        let targetVersion: RemoteVersion?
        let sourceVersion: RemoteVersion?
        let appInfo: RemoteAppInfo?
    }

    private static func sanitize(_ version: RemoteVersion?) -> RemoteVersion? {
        version.map { version in
            RemoteVersion(
                id: version.id,
                versionString: version.versionString,
                state: version.state,
                attributes: filter(version.attributes, keys: [
                    "versionString", "platform", "appVersionState", "appStoreState", "copyright", "releaseType",
                ]),
                localizations: version.localizations.map { localization in
                    RemoteLocalization(
                        id: localization.id,
                        locale: localization.locale,
                        attributes: filter(localization.attributes, keys: [
                            "locale", "description", "keywords", "marketingUrl", "promotionalText",
                            "supportUrl", "whatsNew",
                        ]),
                        screenshotSets: localization.screenshotSets.map { set in
                            RemoteScreenshotSet(
                                id: set.id,
                                displayType: set.displayType,
                                screenshots: set.screenshots.map { screenshot in
                                    RemoteScreenshot(
                                        id: screenshot.id,
                                        fileName: screenshot.fileName,
                                        checksum: screenshot.checksum,
                                        attributes: filter(screenshot.attributes, keys: [
                                            "fileName", "fileSize", "sourceFileChecksum", "assetDeliveryState",
                                        ])
                                    )
                                }
                            )
                        }
                    )
                }
            )
        }
    }

    private static func filter(
        _ attributes: [String: JSONValue],
        keys: Set<String>
    ) -> [String: JSONValue] {
        attributes.filter { keys.contains($0.key) }
    }
}
