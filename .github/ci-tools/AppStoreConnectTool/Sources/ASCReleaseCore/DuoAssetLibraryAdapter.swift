import Foundation

/// Offline request serialization only. This type has no API client or executor.
/// Image/placement creation, upload, processing and reconciliation remain
/// separately authorized publisher work; producing a plan grants none of them.
public struct DuoAssetLibraryRequest: Codable, Equatable, Sendable {
    public let method: String
    public let path: String
    public let body: JSONValue
}

public struct DuoAssetLibraryAdapter: Sendable {
    public let routing: JSONValue
    public let assetLibraryID: String

    public init(catalog: [JSONValue], assetLibraryID: String) throws {
        routing = try DuoAssetLibraryRouting.resolve(catalog: catalog)
        self.assetLibraryID = try Self.identifier(assetLibraryID)
    }

    private static func identifier(_ value: String) throws -> String {
        guard value != ".", value != "..",
              value.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw ReleaseToolError.validation("Unsafe or missing Asset Library resource identifier")
        }
        return value
    }

    private func relation(_ type: String, _ id: String) throws -> JSONValue {
        .object(["data": .object(["type": .string(type), "id": .string(try Self.identifier(id))])])
    }

    public func reserveImage(fileName: String, fileSize: Int) throws -> DuoAssetLibraryRequest {
        guard fileSize > 0,
              fileName.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*\.png$"#, options: .regularExpression) != nil else {
            throw ReleaseToolError.validation("Reservation requires a PNG basename and positive file size")
        }
        return DuoAssetLibraryRequest(method: "POST", path: "/v1/appAssetLibraryImages", body: .object([
            "data": .object(["type": .string("appAssetLibraryImages"),
                "attributes": .object(["fileName": .string(fileName), "fileSize": .number(Double(fileSize)),
                                       "category": .string("APP_SCREENSHOTS_AND_PREVIEWS")]),
                "relationships": .object(["assetLibrary": try relation("appAssetLibraries", assetLibraryID)])])
        ]))
    }

    public func commitImage(imageID: String) throws -> DuoAssetLibraryRequest {
        let id = try Self.identifier(imageID)
        return DuoAssetLibraryRequest(method: "PATCH", path: "/v1/appAssetLibraryImages/\(id)", body: .object([
            "data": .object(["type": .string("appAssetLibraryImages"), "id": .string(id),
                             "attributes": .object(["uploaded": .bool(true)])])
        ]))
    }

    public func placeProcessedImage(_ image: JSONValue, expectedSpecID: String, localizationID: String) throws -> DuoAssetLibraryRequest {
        guard image["type"] == .string("appAssetLibraryImages"), let imageID = image["id"]?.stringValue,
              image["attributes"]?["state"] == .string("PREPARE_FOR_SUBMISSION"),
              image["attributes"]?["category"] == .string("APP_SCREENSHOTS_AND_PREVIEWS"),
              image["attributes"]?["specId"] == .string(expectedSpecID),
              routing["imageSpecs"]?.arrayValue?.filter({ $0["specId"] == .string(expectedSpecID) }).count == 1 else {
            throw ReleaseToolError.validation("Placement requires a processed image with its intended catalog specification")
        }
        return DuoAssetLibraryRequest(method: "POST", path: "/v1/appAssetLibraryPlacements", body: .object([
            "data": .object(["type": .string("appAssetLibraryPlacements"),
                "attributes": .object(["placementType": .string("APP_SCREENSHOT"),
                                       "placementGroup": routing["placementGroup"]!]),
                "relationships": .object([
                    "image": try relation("appAssetLibraryImages", imageID),
                    "appStoreVersionLocalization": try relation("appStoreVersionLocalizations", localizationID)])])
        ]))
    }

    public func orderPlacements(_ ids: [String], localizationID: String) throws -> DuoAssetLibraryRequest {
        try orderingRequest(ids, expectedCount: 10, localizationID: localizationID)
    }

    /// Rollback orders the entire sealed baseline, which may contain fewer than
    /// ten cards. Empty baselines are verified empty without an ordering POST.
    public func orderRestoredPlacements(_ ids: [String], baselineCount: Int, localizationID: String) throws -> DuoAssetLibraryRequest {
        guard (1...10).contains(baselineCount) else {
            throw ReleaseToolError.validation("Nonempty rollback ordering needs the sealed baseline count")
        }
        return try orderingRequest(ids, expectedCount: baselineCount, localizationID: localizationID)
    }

    private func orderingRequest(_ ids: [String], expectedCount: Int, localizationID: String) throws -> DuoAssetLibraryRequest {
        guard ids.count == expectedCount, Set(ids).count == ids.count,
              ids.count <= routing["maxCountPerGroupAndLocalization"]!.intValue! else {
            throw ReleaseToolError.validation("Duo ordering requires all ten unique placements within the shared group limit")
        }
        let ordered = try ids.map { id in
            JSONValue.object(["type": .string("appAssetLibraryPlacements"), "id": .string(try Self.identifier(id))])
        }
        return DuoAssetLibraryRequest(method: "POST", path: "/v1/appAssetLibraryPlacementOrderingRequests", body: .object([
            "data": .object(["type": .string("appAssetLibraryPlacementOrderingRequests"),
                "attributes": .object(["placementGroup": routing["placementGroup"]!]),
                "relationships": .object(["orderedPlacements": .object(["data": .array(ordered)]),
                    "appStoreVersionLocalization": try relation("appStoreVersionLocalizations", localizationID)])])
        ]))
    }
}

public enum DuoAssetLibraryPlanBuilder {
    /// Binds an already reviewed import to a fresh read-only routing snapshot.
    /// Does not replace the full private import verifier or make a publish manifest.
    public static func build(
        inspectionURL: URL, expectedInspectionSHA256: String, importURL: URL, expectedImportSHA256: String,
        expectedSelectionSHA256: String
    ) throws -> JSONValue {
        func require(_ condition: Bool, _ reason: String) throws {
            guard condition else { throw ReleaseToolError.validation(reason) }
        }
        func json(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: data) }
        let importData = try Data(contentsOf: importURL)
        try require(FileIO.sha256(importData) == expectedImportSHA256, "Selected import hash differs from review")
        let envelope = try json(importData)
        try require(envelope["schemaVersion"] == .number(1) && envelope["mode"] == .string("selected-import") &&
                    envelope["publishable"] == .bool(false) && envelope["selectionSHA256"] == .string(expectedSelectionSHA256),
                    "Plan requires the exact unpromoted selected import")
        let root = importURL.deletingLastPathComponent().standardizedFileURL
        func retainedURL(_ relative: String) throws -> URL {
            let url = root.appendingPathComponent(relative).standardizedFileURL
            try require(!relative.hasPrefix("/") && url.path.hasPrefix(root.path + "/") &&
                        url.resolvingSymlinksInPath() == url, "Imported input escapes its retained root or uses a symlink")
            return url
        }
        guard let bindings = envelope["sourceBindings"]?.arrayValue,
              let originalSelection = envelope["selectionOriginalPath"]?.stringValue else {
            throw ReleaseToolError.validation("Selected import is missing its original selection binding")
        }
        let selectionBindings = bindings.filter { $0["originalPath"] == .string(originalSelection) &&
            $0["sha256"] == .string(expectedSelectionSHA256) }
        try require(selectionBindings.count == 1, "Selection binding is missing or ambiguous")
        guard let retainedSelection = selectionBindings[0]["retainedPath"]?.stringValue else {
            throw ReleaseToolError.validation("Missing retained selection path")
        }
        let selectionData = try Data(contentsOf: retainedURL(retainedSelection))
        try require(FileIO.sha256(selectionData) == expectedSelectionSHA256, "Retained selection changed")
        let selection = try json(selectionData)
        var bindingKeys = Set<String>()
        for binding in bindings {
            guard let original = binding["originalPath"]?.stringValue,
                  let sha = binding["sha256"]?.stringValue, let path = binding["retainedPath"]?.stringValue,
                  let size = binding["bytes"]?.intValue else {
                throw ReleaseToolError.validation("Incomplete retained source binding")
            }
            try require(bindingKeys.insert(original + ":" + sha).inserted, "Duplicate retained source binding")
            let bytes = try Data(contentsOf: retainedURL(path))
            try require(bytes.count == size && FileIO.sha256(bytes) == sha, "Retained source binding changed")
        }
        let inspectionData = try Data(contentsOf: inspectionURL)
        try require(FileIO.sha256(inspectionData) == expectedInspectionSHA256, "Inspection hash differs from review")
        let inspection = try json(inspectionData)
        try require(inspection["purpose"] == .string("duo-asset-library-readonly-inspection") &&
                    inspection["perAppAssetLibraryReadable"] == .bool(true) &&
                    inspection["remoteMutationsPerformed"] == .bool(false) &&
                    inspection["requestedVersion"] == selection["releaseVersion"], "Inspection does not match the selected release")
        guard let catalog = inspection["catalogResources"]?.arrayValue,
              let libraryID = inspection["assetLibraryId"]?.stringValue else {
            throw ReleaseToolError.validation("Inspection has no verified app library/catalog")
        }
        let adapter = try DuoAssetLibraryAdapter(catalog: catalog, assetLibraryID: libraryID)
        try require(adapter.routing == inspection["routing"], "Inspection routing differs from its catalog")
        guard let configRef = selection["localeMappingSource"], let configPath = configRef["path"]?.stringValue,
              let configSHA = configRef["sha256"]?.stringValue else {
            throw ReleaseToolError.validation("Missing selected locale configuration reference")
        }
        let releaseRoot = URL(fileURLWithPath: originalSelection).deletingLastPathComponent().deletingLastPathComponent()
        let originalConfig = releaseRoot.appendingPathComponent(configPath).standardizedFileURL.path
        let configBindings = bindings.filter { $0["originalPath"] == .string(originalConfig) && $0["sha256"] == .string(configSHA) }
        try require(configBindings.count == 1, "Locale configuration binding is missing or ambiguous")
        guard let retainedConfig = configBindings[0]["retainedPath"]?.stringValue else {
            throw ReleaseToolError.validation("Missing retained locale configuration")
        }
        let config = try json(Data(contentsOf: retainedURL(retainedConfig)))
        try require(config["bundleId"] == inspection["bundleId"] && config["bundleId"] != nil,
                    "Inspection belongs to another app")
        let target = inspection["targetVersion"] ?? .null
        if target != .null {
            try require(target["attributes"]?["appVersionState"] == .string("PREPARE_FOR_SUBMISSION") &&
                        target["attributes"]?["versionString"] == selection["releaseVersion"] &&
                        target["attributes"]?["platform"] == .string("IOS"), "Existing target version is not the editable selected iOS release")
        } else {
            try require(inspection["localizations"] == .array([]), "Absent target cannot supply localization IDs")
        }
        guard let configurations = selection["screenshotConfigurationOrder"]?.arrayValue,
              let selected = selection["images"]?.arrayValue,
              let cards = envelope["cards"]?.arrayValue,
              let localeRows = selection["locales"]?.arrayValue,
              let limits = selection["qualificationLimits"] else {
            throw ReleaseToolError.validation("Incomplete selected lineup")
        }
        try require(envelope["qualificationLimits"] == limits &&
                    selection["selectedFramedImageCount"]?.intValue == cards.count &&
                    selected.count == cards.count &&
                    cards.count == configurations.count * 30 && Set(configurations.compactMap(\.stringValue)).count == configurations.count,
                    "Selected scope or qualifications changed")
        let configuredMappings = config["localizations"]?.arrayValue ?? []
        try require(configuredMappings.map { $0["screenshotConfiguration"] } == configurations.map(Optional.some) &&
                    localeRows.count == configuredMappings.count &&
                    Set(configuredMappings.compactMap { $0["appStoreLocale"]?.stringValue }).count == configuredMappings.count &&
                    Set(localeRows.compactMap { $0["appStoreLocale"]?.stringValue }).count == localeRows.count,
                    "Selected locales must exactly match the configured locale bijection")
        var plannedLocales: [JSONValue] = []
        let encoder = JSONEncoder()
        for configuration in configurations {
            guard let name = configuration.stringValue else { throw ReleaseToolError.validation("Invalid locale configuration") }
            let mapping = localeRows.filter { $0["screenshotConfiguration"] == configuration }
            try require(mapping.count == 1, "Selected locale mapping is missing or ambiguous")
            guard let store = mapping[0]["appStoreLocale"], store.stringValue != nil else {
                throw ReleaseToolError.validation("Selected mapping has no App Store locale")
            }
            let configured = (config["localizations"]?.arrayValue ?? []).filter { $0["screenshotConfiguration"] == configuration }
            try require(configured.count == 1 && configured[0]["appStoreLocale"] == store, "Selected locale differs from captured configuration")
            let localCards = cards.filter { $0["screenshotConfiguration"] == configuration && $0["family"] == .string("iphone-duo-profile") }
            try require(localCards.map { $0["position"]?.intValue } == Array(1...10).map(Optional.some) &&
                        localCards.count <= adapter.routing["maxCountPerGroupAndLocalization"]!.intValue!,
                        "Duo must retain ten ordered cards within one shared group")
            var images: [JSONValue] = []
            for card in localCards {
                let matches = selected.filter { $0["screenshotConfiguration"] == configuration &&
                    $0["family"] == .string("iphone-duo-profile") && $0["position"] == card["position"] }
                try require(matches.count == 1 && card["appStoreLocale"] == store && matches[0]["appStoreLocale"] == store,
                            "Wrong selected Duo locale or slot")
                guard let asset = card["assets"]?["screenshots"], let relative = asset["importedPath"]?.stringValue,
                      let sha = asset["sha256"]?.stringValue, let sizes = asset["dimensions"]?.arrayValue,
                      sizes.count == 2, let width = sizes[0].intValue, let height = sizes[1].intValue,
                      let origin = card["origin"] else { throw ReleaseToolError.validation("Incomplete Duo card") }
                try require(matches[0]["assets"]?["screenshots"]?["sha256"] == .string(sha) &&
                            matches[0]["assets"]?["screenshots"]?["dimensions"] == .array(sizes), "Duo image differs from selection")
                let url = try retainedURL(relative)
                try require(relative == "screenshots/\(name)/iphone-duo-profile/\(url.lastPathComponent)" &&
                            matches[0]["outputFile"] == .string(url.lastPathComponent), "Wrong Duo image path")
                let bytes = try Data(contentsOf: url)
                try require(FileIO.sha256(bytes) == sha, "Selected Duo image bytes changed")
                try ImageValidation.validateScreenshot(bytes, pixelWidth: width, pixelHeight: height, context: relative)
                let specs = adapter.routing["imageSpecs"]!.arrayValue!.filter {
                    $0["pixelWidth"]?.intValue == width && $0["pixelHeight"]?.intValue == height
                }
                try require(specs.count == 1, "Selected Duo image has no unique catalog specification")
                let rawSpecs = catalog.first?["attributes"]?["imageSpecs"]?.arrayValue ?? []
                let raw = rawSpecs.filter { $0["specId"] == specs[0]["specId"] }
                try require(raw.count == 1 && raw[0]["mimeTypes"]?.arrayValue?.contains(.string("image/png")) == true &&
                            (raw[0]["maxFileSize"]?.intValue ?? 0) >= bytes.count, "Duo image exceeds its catalog MIME/file-size constraints")
                let reservation = try json(encoder.encode(adapter.reserveImage(fileName: url.lastPathComponent, fileSize: bytes.count)))
                images.append(.object(["position": card["position"]!, "asset": asset, "origin": origin,
                    "reservationDependencyKey": .string("\(store.stringValue!):\(card["position"]!.intValue!):\(sha)"),
                    "selectedCard": card,
                    "catalogImageSpecification": raw[0], "reservationRequest": reservation,
                    "imageId": .null, "placementId": .null]))
            }
            let remoteLocales = (inspection["localizations"]?.arrayValue ?? []).filter { $0["locale"] == store }
            try require(remoteLocales.count <= 1, "Ambiguous target localization")
            plannedLocales.append(.object(["appStoreLocale": store, "screenshotConfiguration": configuration,
                "appStoreVersionLocalizationId": remoteLocales.first?["localizationId"] ?? .null,
                "sharedPlacementGroup": adapter.routing["placementGroup"]!, "images": .array(images),
                "ordering": .string("One orderedPlacements array in positions1–10 after actual placement IDs are returned; no per-image position field")]))
        }
        return .object(["schemaVersion": .number(1), "mode": .string("offline-duo-placement-plan"),
            "publishable": .bool(false), "remoteMutationsPerformed": .bool(false),
            "planOnly": .bool(true), "networkExecutorIncluded": .bool(false), "publicationReady": .bool(false),
            "offlineRequestAdapterAvailable": .bool(true), "publisherMutationExecutorAvailable": .bool(false),
            "uploadAcceptanceVerified": .bool(false), "storefrontPresentationVerified": .bool(false),
            "historicalCaptureQualificationChanged": .bool(false),
            "selectedImportSHA256": .string(expectedImportSHA256), "selectionSHA256": .string(expectedSelectionSHA256),
            "inspectionSHA256": .string(FileIO.sha256(inspectionData)), "inspectionCapturedAt": inspection["capturedAt"] ?? .null,
            "bundleId": inspection["bundleId"] ?? .null, "version": inspection["requestedVersion"]!,
            "assetLibraryId": .string(libraryID), "routing": adapter.routing, "targetVersion": target,
            "qualificationLimits": limits, "localizations": .array(plannedLocales),
            "unresolvedExecutionSteps": .array([
                .string("Separately authorized editable target/localizations, image reservation and returned uploadOperations"),
                .string("Commit uploaded:true without legacy checksum fields; poll image state/stateDetails"),
                .string("Place processed images with real returned IDs; order once per group/localization and read back"),
                .string("Publisher reconciliation, backups, journal/recovery and explicit reviewed publication approval")])])
    }
}
