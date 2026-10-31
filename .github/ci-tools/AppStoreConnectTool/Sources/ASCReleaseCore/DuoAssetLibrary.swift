import Foundation

/// Runtime Asset Library identifiers are deliberately separate from legacy
/// appScreenshotSets display enums. This inspector has GET-only operations.
public enum DuoAssetLibraryRouting {
    public static func resolve(catalog: [JSONValue]) throws -> JSONValue {
        func one(_ rows: [JSONValue], _ label: String) throws -> JSONValue {
            guard rows.count == 1 else {
                throw ReleaseToolError.validation("Expected one ordinary Duo \(label); found \(rows.count)")
            }
            return rows[0]
        }
        let attributes = try one(catalog, "reference catalog")["attributes"]
        guard let attributes else { throw ReleaseToolError.validation("Missing reference attributes") }
        let group = try one((attributes["placementProfileGroups"]?.arrayValue ?? []).filter {
            $0["platform"]?.stringValue == "IPHONE_APP_STORE" &&
                $0["displayClassId"]?.stringValue == "IPHONE_DUO"
        }, "placement group")
        guard let groupID = group["placementProfileGroupId"]?.stringValue, !groupID.isEmpty else {
            throw ReleaseToolError.validation("Duo group has no runtime identifier")
        }
        let type = try one((attributes["placementTypes"]?.arrayValue ?? []).filter {
            $0["placementTypeId"]?.stringValue == "APP_SCREENSHOT"
        }, "screenshot placement type")
        guard type["acceptsAssetCategories"]?.arrayValue?.contains(.string("APP_SCREENSHOTS_AND_PREVIEWS")) == true else {
            throw ReleaseToolError.validation("Ordinary screenshots do not accept the expected asset category")
        }
        let mapping = try one((type["specMappings"]?.arrayValue ?? []).filter {
            $0["placementGroupId"]?.stringValue == groupID
        }, "specification mapping")
        guard let rawIDs = mapping["specs"]?.arrayValue, !rawIDs.isEmpty,
              rawIDs.allSatisfy({ $0.stringValue?.isEmpty == false }) else {
            throw ReleaseToolError.validation("Every Duo specification ID must be a nonempty string")
        }
        let ids = rawIDs.map { $0.stringValue! }
        guard Set(ids).count == ids.count else {
            throw ReleaseToolError.validation("Duo specification IDs are missing or duplicated")
        }
        let feature = try one((attributes["features"]?.arrayValue ?? []).filter {
            $0["featureId"]?.stringValue == "APP_STORE_VERSIONS"
        }, "version feature")
        let policy = try one((feature["placementPolicies"]?.arrayValue ?? []).filter {
            $0["placementType"]?.stringValue == "APP_SCREENSHOT"
        }, "placement policy")
        let limit = try one((policy["groupLimits"]?.arrayValue ?? []).filter {
            $0["groupIds"]?.arrayValue?.contains(.string(groupID)) == true
        }, "per-group limit")
        guard let maximum = limit["maxCount"]?.intValue, maximum > 0 else {
            throw ReleaseToolError.validation("Duo group limit is invalid")
        }
        var specs: [JSONValue] = []
        for id in ids {
            let spec = try one((attributes["imageSpecs"]?.arrayValue ?? []).filter {
                $0["specId"]?.stringValue == id
            }, "image specification")
            guard spec["alphaAllowed"] == .bool(false),
                  spec["compatiblePlacementTypes"]?.arrayValue?.contains(.string("APP_SCREENSHOT")) == true,
                  spec["fileExtensions"]?.arrayValue?.contains(.string(".png")) == true,
                  let width = spec["dimensions"]?["minWidth"]?.intValue,
                  let height = spec["dimensions"]?["minHeight"]?.intValue,
                  width > 0, height > 0,
                  spec["dimensions"]?["maxWidth"]?.intValue == width,
                  spec["dimensions"]?["maxHeight"]?.intValue == height else {
                throw ReleaseToolError.validation("Duo PNG specification is incomplete or not an exact opaque size")
            }
            specs.append(.object(["specId": .string(id), "pixelWidth": .number(Double(width)),
                                  "pixelHeight": .number(Double(height)), "alphaAllowed": .bool(false)]))
        }
        for size in [(1398, 2034), (2853, 2007)] {
            guard specs.contains(where: { $0["pixelWidth"]?.intValue == size.0 && $0["pixelHeight"]?.intValue == size.1 }) else {
                throw ReleaseToolError.validation("Catalog does not support the selected native Duo sizes")
            }
        }
        return .object([
            "transport": .string("asset-library"), "platform": .string("IPHONE_APP_STORE"),
            "displayClass": .string("IPHONE_DUO"), "placementType": .string("APP_SCREENSHOT"),
            "placementGroup": .string(groupID), "category": .string("APP_SCREENSHOTS_AND_PREVIEWS"),
            "maxCountPerGroupAndLocalization": .number(Double(maximum)), "imageSpecs": .array(specs),
            "legacyScreenshotDisplayType": .null, "uploadAcceptanceVerified": .bool(false),
            "storefrontPresentationVerified": .bool(false), "publisherMutationAdapterAvailable": .bool(false),
        ])
    }
}

public final class DuoAssetLibraryInspector {
    private let client: ASCAPIClient
    public init(client: ASCAPIClient) { self.client = client }

    private func identifier(_ value: JSONValue) throws -> String {
        guard let id = value["id"]?.stringValue,
              id != ".", id != "..",
              id.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw ReleaseToolError.api("Missing or unsafe resource identifier")
        }
        return id
    }

    public func capture(bundleId: String, version: String) throws -> JSONValue {
        let catalog = try client.list(path: "/v1/appAssetLibraryRefData")
        let routing = try DuoAssetLibraryRouting.resolve(catalog: catalog)
        let apps = try client.list(path: "/v1/apps", query: [
            URLQueryItem(name: "filter[bundleId]", value: bundleId), URLQueryItem(name: "limit", value: "2")
        ])
        guard apps.count == 1 else { throw ReleaseToolError.api("Expected one app for the configured bundle") }
        let appID = try identifier(apps[0])
        guard let library = try client.request(method: "GET", path: "/v1/apps/\(appID)/assetLibrary"),
              let resource = library["data"] else { throw ReleaseToolError.api("App Asset Library is unavailable") }
        let libraryID = try identifier(resource)
        let versions = try client.list(path: "/v1/apps/\(appID)/appStoreVersions", query: [
            URLQueryItem(name: "filter[platform]", value: "IOS"), URLQueryItem(name: "limit", value: "200")
        ])
        let target = versions.filter { $0["attributes"]?["versionString"]?.stringValue == version }
        guard target.count <= 1 else { throw ReleaseToolError.api("Ambiguous target version") }
        var locales: [JSONValue] = []
        if let target = target.first {
            let targetID = try identifier(target)
            let rows = try client.list(path: "/v1/appStoreVersions/\(targetID)/appStoreVersionLocalizations", query: [URLQueryItem(name: "limit", value: "200")])
            for row in rows {
                let id = try identifier(row)
                let placements = try client.list(path: "/v1/appStoreVersionLocalizations/\(id)/placements", query: [
                    URLQueryItem(name: "filter[placementType]", value: "APP_SCREENSHOT"),
                    URLQueryItem(name: "filter[placementGroup]", value: routing["placementGroup"]!.stringValue!),
                    URLQueryItem(name: "sort", value: "placementGroupPosition"), URLQueryItem(name: "include", value: "image"),
                    URLQueryItem(name: "limit", value: "200")
                ])
                locales.append(.object(["localizationId": .string(id), "locale": row["attributes"]?["locale"] ?? .null,
                                        "orderedPlacements": .array(placements)]))
            }
        }
        return .object([
            "purpose": .string("duo-asset-library-readonly-inspection"),
            "capturedAt": .string(ISO8601DateFormatter.releaseTool.string(from: Date())),
            "bundleId": .string(bundleId), "requestedVersion": .string(version),
            "appId": .string(appID), "assetLibraryId": .string(libraryID),
            "routing": routing, "catalogResources": .array(catalog),
            "targetVersion": target.first ?? .null, "localizations": .array(locales),
            "requestMethods": .array([.string("GET")]), "remoteMutationsPerformed": .bool(false),
            "perAppAssetLibraryReadable": .bool(true), "uploadAcceptanceVerified": .bool(false),
        ])
    }
}
