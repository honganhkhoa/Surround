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
        let appInfos = try loadAppInfos(appId: appId)
        let appInfo = appInfos.target ?? appInfos.source

        let fingerprint = try Self.fingerprint(
            appId: appId,
            bundleId: release.bundleId,
            platform: release.platform,
            requestedVersion: release.version,
            targetVersion: target,
            sourceVersion: source,
            appInfo: appInfo,
            sourceAppInfo: appInfos.source,
            targetAppInfo: appInfos.target
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
            appInfo: appInfo,
            sourceAppInfo: appInfos.source,
            targetAppInfo: appInfos.target
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
            appInfo: snapshot.appInfo,
            sourceAppInfo: snapshot.sourceAppInfo,
            targetAppInfo: snapshot.targetAppInfo
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

    private struct AppInfoSummary {
        let id: String
        let state: String?
    }

    private struct AppInfoPair {
        let source: RemoteAppInfo?
        let target: RemoteAppInfo?
    }

    private struct IncludedResourceKey: Hashable {
        let type: String
        let id: String
    }

    private struct ResourceLinkage: Hashable {
        let type: String
        let id: String
    }

    private func loadAppInfos(appId: String) throws -> AppInfoPair {
        let rawInfos = try client.list(
            path: "/v1/apps/\(appId)/appInfos",
            query: [URLQueryItem(name: "limit", value: "200")]
        )
        let parsed: [AppInfoSummary] = try rawInfos.map {
            guard let id = $0["id"]?.stringValue,
                  let attributes = $0["attributes"]?.objectValue else {
                throw ReleaseToolError.api("Malformed appInfos resource")
            }
            return AppInfoSummary(
                id: id,
                state: (attributes["state"] ?? attributes["appStoreState"])?.stringValue
            )
        }

        let drafts = parsed.filter { $0.state == "PREPARE_FOR_SUBMISSION" }
        guard drafts.count <= 1 else {
            throw ReleaseToolError.validation(
                "App Store Connect returned multiple draft App Info resources"
            )
        }
        let liveStates = Set(["READY_FOR_DISTRIBUTION", "READY_FOR_SALE"])
        let live = parsed.filter { liveStates.contains($0.state ?? "") }
        guard live.count <= 1 else {
            throw ReleaseToolError.validation(
                "App Store Connect returned multiple live App Info resources"
            )
        }

        return AppInfoPair(
            source: try live.first.map(loadAppInfo),
            target: try drafts.first.map(loadAppInfo)
        )
    }

    private func loadAppInfo(_ summary: AppInfoSummary) throws -> RemoteAppInfo {
        let includedRelationshipNames = [
            "ageRatingDeclaration",
            "appInfoLocalizations",
            "primaryCategory",
            "primarySubcategoryOne",
            "primarySubcategoryTwo",
            "secondaryCategory",
            "secondarySubcategoryOne",
            "secondarySubcategoryTwo",
        ]
        let response = try client.request(
            method: "GET",
            path: "/v1/appInfos/\(summary.id)",
            query: [
                URLQueryItem(
                    name: "include",
                    value: includedRelationshipNames.joined(separator: ",")
                ),
                URLQueryItem(name: "limit[appInfoLocalizations]", value: "50"),
            ]
        )
        guard let responseObject = response?.objectValue,
              let resource = responseObject["data"]?.objectValue,
              resource["id"]?.stringValue == summary.id,
              let attributes = resource["attributes"]?.objectValue,
              let relationships = resource["relationships"]?.objectValue else {
            throw ReleaseToolError.api("Malformed appInfos detail resource \(summary.id)")
        }

        let detailState = (attributes["state"] ?? attributes["appStoreState"])?.stringValue
        guard detailState == summary.state else {
            throw ReleaseToolError.remoteDrift(
                "App Info \(summary.id) state changed while the snapshot was captured"
            )
        }

        var includedResources: [IncludedResourceKey: [String: JSONValue]] = [:]
        for included in responseObject["included"]?.arrayValue ?? [] {
            guard let object = included.objectValue,
                  let type = object["type"]?.stringValue,
                  let id = object["id"]?.stringValue else {
                throw ReleaseToolError.api("Malformed included App Info resource")
            }
            let key = IncludedResourceKey(type: type, id: id)
            guard includedResources.updateValue(object, forKey: key) == nil else {
                throw ReleaseToolError.api(
                    "Duplicate included App Info resource \(type)/\(id)"
                )
            }
        }

        let localizationLinkages = try toManyLinkages(
            relationship: "appInfoLocalizations",
            relationships: relationships
        )
        guard Set(localizationLinkages).count == localizationLinkages.count else {
            throw ReleaseToolError.api(
                "App Info \(summary.id) contains duplicate localization linkages"
            )
        }
        let localizations = try localizationLinkages.map { linkage -> RemoteAppInfoLocalization in
            guard let included = includedResources[
                IncludedResourceKey(type: linkage.type, id: linkage.id)
            ], let localizationAttributes = included["attributes"]?.objectValue,
               let locale = localizationAttributes["locale"]?.stringValue else {
                throw ReleaseToolError.api(
                    "App Info \(summary.id) is missing included localization \(linkage.id)"
                )
            }
            return RemoteAppInfoLocalization(
                id: linkage.id,
                locale: locale,
                attributes: localizationAttributes
            )
        }.sorted {
            if $0.locale != $1.locale { return $0.locale < $1.locale }
            return $0.id < $1.id
        }
        guard Set(localizations.map(\.locale)).count == localizations.count else {
            throw ReleaseToolError.api(
                "App Info \(summary.id) contains duplicate localization locales"
            )
        }

        let primaryCategory = try toOneLinkage(
            relationship: "primaryCategory",
            relationships: relationships
        )
        let primarySubcategoryOne = try toOneLinkage(
            relationship: "primarySubcategoryOne",
            relationships: relationships
        )
        let primarySubcategoryTwo = try toOneLinkage(
            relationship: "primarySubcategoryTwo",
            relationships: relationships
        )
        let secondaryCategory = try toOneLinkage(
            relationship: "secondaryCategory",
            relationships: relationships
        )
        let secondarySubcategoryOne = try toOneLinkage(
            relationship: "secondarySubcategoryOne",
            relationships: relationships
        )
        let secondarySubcategoryTwo = try toOneLinkage(
            relationship: "secondarySubcategoryTwo",
            relationships: relationships
        )
        let categoryLinkages: [(String, ResourceLinkage?)] = [
            ("primaryCategory", primaryCategory),
            ("primarySubcategoryOne", primarySubcategoryOne),
            ("primarySubcategoryTwo", primarySubcategoryTwo),
            ("secondaryCategory", secondaryCategory),
            ("secondarySubcategoryOne", secondarySubcategoryOne),
            ("secondarySubcategoryTwo", secondarySubcategoryTwo),
        ]
        for (name, linkage) in categoryLinkages {
            guard let linkage else { continue }
            guard includedResources[
                IncludedResourceKey(type: linkage.type, id: linkage.id)
            ] != nil else {
                throw ReleaseToolError.api(
                    "App Info \(summary.id) is missing included \(name) \(linkage.id)"
                )
            }
        }

        let ageRatingLinkage = try toOneLinkage(
            relationship: "ageRatingDeclaration",
            relationships: relationships
        )
        let ageRatingAttributes: [String: JSONValue]
        if let ageRatingLinkage {
            guard let included = includedResources[
                IncludedResourceKey(type: ageRatingLinkage.type, id: ageRatingLinkage.id)
            ], let includedAttributes = included["attributes"]?.objectValue else {
                throw ReleaseToolError.api(
                    "App Info \(summary.id) is missing its included age rating declaration"
                )
            }
            ageRatingAttributes = includedAttributes
        } else {
            ageRatingAttributes = [:]
        }

        return RemoteAppInfo(
            id: summary.id,
            state: detailState,
            localizations: localizations,
            details: RemoteAppInfoDetails(
                attributes: Self.nonStateAttributes(attributes),
                primaryCategoryId: primaryCategory?.id,
                primarySubcategoryOneId: primarySubcategoryOne?.id,
                primarySubcategoryTwoId: primarySubcategoryTwo?.id,
                secondaryCategoryId: secondaryCategory?.id,
                secondarySubcategoryOneId: secondarySubcategoryOne?.id,
                secondarySubcategoryTwoId: secondarySubcategoryTwo?.id,
                ageRatingDeclarationId: ageRatingLinkage?.id,
                ageRatingDeclarationAttributes: ageRatingAttributes
            )
        )
    }

    private func toOneLinkage(
        relationship name: String,
        relationships: [String: JSONValue]
    ) throws -> ResourceLinkage? {
        guard let relationship = relationships[name]?.objectValue,
              let data = relationship["data"] else {
            throw ReleaseToolError.api("App Info relationship \(name) has no linkage data")
        }
        if case .null = data { return nil }
        guard let object = data.objectValue,
              let type = object["type"]?.stringValue,
              let id = object["id"]?.stringValue else {
            throw ReleaseToolError.api("App Info relationship \(name) has malformed linkage data")
        }
        return ResourceLinkage(type: type, id: id)
    }

    private func toManyLinkages(
        relationship name: String,
        relationships: [String: JSONValue]
    ) throws -> [ResourceLinkage] {
        guard let relationship = relationships[name]?.objectValue,
              let data = relationship["data"]?.arrayValue else {
            throw ReleaseToolError.api("App Info relationship \(name) has malformed linkage data")
        }
        return try data.map { value in
            guard let object = value.objectValue,
                  let type = object["type"]?.stringValue,
                  let id = object["id"]?.stringValue else {
                throw ReleaseToolError.api(
                    "App Info relationship \(name) has malformed resource linkage"
                )
            }
            return ResourceLinkage(type: type, id: id)
        }
    }

    private static func fingerprint(
        appId: String,
        bundleId: String,
        platform: String,
        requestedVersion: String,
        targetVersion: RemoteVersion?,
        sourceVersion: RemoteVersion?,
        appInfo: RemoteAppInfo?,
        sourceAppInfo: RemoteAppInfo?,
        targetAppInfo: RemoteAppInfo?
    ) throws -> String {
        let payload = FingerprintPayload(
            appId: appId,
            bundleId: bundleId,
            platform: platform,
            requestedVersion: requestedVersion,
            targetVersion: sanitize(targetVersion),
            sourceVersion: sanitize(sourceVersion),
            appInfo: sanitize(appInfo),
            sourceAppInfo: sanitize(sourceAppInfo),
            targetAppInfo: sanitize(targetAppInfo)
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
        let sourceAppInfo: RemoteAppInfo?
        let targetAppInfo: RemoteAppInfo?
    }

    private static func sanitize(_ appInfo: RemoteAppInfo?) -> RemoteAppInfo? {
        appInfo.map { info in
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
                },
                details: info.details.map { details in
                    RemoteAppInfoDetails(
                        attributes: nonStateAttributes(details.attributes),
                        primaryCategoryId: details.primaryCategoryId,
                        primarySubcategoryOneId: details.primarySubcategoryOneId,
                        primarySubcategoryTwoId: details.primarySubcategoryTwoId,
                        secondaryCategoryId: details.secondaryCategoryId,
                        secondarySubcategoryOneId: details.secondarySubcategoryOneId,
                        secondarySubcategoryTwoId: details.secondarySubcategoryTwoId,
                        ageRatingDeclarationId: details.ageRatingDeclarationId,
                        ageRatingDeclarationAttributes: details.ageRatingDeclarationAttributes
                    )
                }
            )
        }
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

    private static func nonStateAttributes(
        _ attributes: [String: JSONValue]
    ) -> [String: JSONValue] {
        attributes.filter { !["state", "appStoreState"].contains($0.key) }
    }
}
