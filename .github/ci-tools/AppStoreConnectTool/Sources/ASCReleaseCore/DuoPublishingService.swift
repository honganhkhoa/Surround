import Foundation

public enum DuoExecutionFailure: Error, LocalizedError {
    case rejected(String)
    case uncertain(String)
    case drift(String)
    case persistence(String)
    case restored(String)

    public var errorDescription: String? {
        switch self {
        case .rejected(let s): return "Request rejected: \(s)"
        case .uncertain(let s): return "Recovery requires read-only inspection: \(s)"
        case .drift(let s): return "Remote drift: \(s)"
        case .persistence(let s): return "Journal persistence failed: \(s)"
        case .restored(let s): return "Replacement failed; verified original content/order restored: \(s)"
        }
    }
}

public struct DuoRemotePlacement: Codable, Equatable, Sendable {
    public let id: String
    public let imageID: String
    public let group: String
    public let placementType: String
    public let state: String

    public init(id: String, imageID: String, group: String, placementType: String = "APP_SCREENSHOT", state: String) {
        self.id = id; self.imageID = imageID; self.group = group
        self.placementType = placementType; self.state = state
    }

    static func parse(_ resource: JSONValue) throws -> DuoRemotePlacement {
        guard resource["type"] == .string("appAssetLibraryPlacements"),
              let id = resource["id"]?.stringValue,
              resource["relationships"]?["image"]?["data"]?["type"] == .string("appAssetLibraryImages"),
              let image = resource["relationships"]?["image"]?["data"]?["id"]?.stringValue,
              let group = resource["attributes"]?["placementGroup"]?.stringValue,
              let type = resource["attributes"]?["placementType"]?.stringValue,
              let state = resource["attributes"]?["state"]?.stringValue else {
            throw DuoExecutionFailure.drift("Placement response is incomplete")
        }
        return DuoRemotePlacement(id: try duoIdentifier(id), imageID: try duoIdentifier(image), group: group, placementType: type, state: state)
    }
}

public struct DuoPublishImage: Codable, Equatable, Sendable {
    public let position: Int
    public let path: String
    public let fileName: String
    public let byteCount: Int
    public let sha256: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let specID: String
    public let origin: JSONValue

    public init(position: Int, path: String, fileName: String, byteCount: Int, sha256: String,
                pixelWidth: Int, pixelHeight: Int, specID: String, origin: JSONValue) {
        self.position = position; self.path = path; self.fileName = fileName; self.byteCount = byteCount
        self.sha256 = sha256; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
        self.specID = specID; self.origin = origin
    }
}

/// A group bound by an admitted selected publisher handoff with actual target IDs.
/// A plan-only record cannot be decoded as this executable contract.
public struct DuoPublishSet: Codable, Equatable, Sendable {
    public let version: String
    public let bundleID: String
    public let appID: String
    public let assetLibraryID: String
    public let versionID: String
    public let localizationID: String
    public let locale: String
    public let sourceManifestSHA256: String
    public let catalog: [JSONValue]
    public let images: [DuoPublishImage]
    public let reviewedBaseline: [DuoRemotePlacement]
    public let compatibilityBaseline: DuoCompatibilityBaseline?

    public init(version: String, bundleID: String, appID: String, assetLibraryID: String, versionID: String,
                localizationID: String, locale: String, sourceManifestSHA256: String, catalog: [JSONValue],
                images: [DuoPublishImage], reviewedBaseline: [DuoRemotePlacement],
                compatibilityBaseline: DuoCompatibilityBaseline? = nil) {
        self.version = version; self.bundleID = bundleID; self.appID = appID; self.assetLibraryID = assetLibraryID
        self.versionID = versionID; self.localizationID = localizationID; self.locale = locale
        self.sourceManifestSHA256 = sourceManifestSHA256; self.catalog = catalog
        self.images = images; self.reviewedBaseline = reviewedBaseline
        self.compatibilityBaseline = compatibilityBaseline
    }

    public func digest() throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return FileIO.sha256(try encoder.encode(self))
    }
}

func duoIdentifier(_ id: String) throws -> String {
    guard id != ".", id != "..", id.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
        throw ReleaseToolError.validation("Unsafe or missing Duo resource identifier")
    }
    return id
}

/// Tests inject an in-memory service or transport. Offline planning and dry runs
/// never invoke the concrete service's network methods.
public protocol DuoPublishingService {
    func withPhase<T>(_ phase: ASCRequestPhase, _ operation: () throws -> T) rethrows -> T
    func verifyEditableTarget(_ set: DuoPublishSet) throws
    func verifyEditableTargets(_ sets: [DuoPublishSet]) throws
    func verifyEditableState(_ set: DuoPublishSet) throws
    func placements(localizationID: String, group: String) throws -> [DuoRemotePlacement]
    func image(id: String) throws -> JSONValue
    func send(_ request: DuoAssetLibraryRequest) throws -> JSONValue?
    func upload(_ operation: UploadOperation, bytes: Data) throws
    func download(_ url: URL) throws -> Data
    func legacyDuoSet(localizationID: String) throws -> RemoteScreenshotSet?
    func placementReadback(localizationID: String, group: String) throws -> DuoPlacementReadback
}

/// One fresh compound response. Included resources are evidence for this read,
/// never an image cache carried over from a previous placement request.
public struct DuoPlacementReadback {
    public let placements: [DuoRemotePlacement]
    public let images: [String: JSONValue]

    public init(placements: [DuoRemotePlacement], images: [String: JSONValue] = [:]) {
        self.placements = placements; self.images = images
    }
}

public extension DuoPublishingService {
    func withPhase<T>(_ phase: ASCRequestPhase, _ operation: () throws -> T) rethrows -> T { try operation() }
    func verifyEditableTargets(_ sets: [DuoPublishSet]) throws { for set in sets { try verifyEditableTarget(set) } }
    func verifyEditableState(_ set: DuoPublishSet) throws { try verifyEditableTarget(set) }
    func placementReadback(localizationID: String, group: String) throws -> DuoPlacementReadback {
        DuoPlacementReadback(placements: try placements(localizationID: localizationID, group: group))
    }
    func legacyDuoSet(localizationID: String) throws -> RemoteScreenshotSet? {
        throw ReleaseToolError.validation("This service has no legacy Duo compatibility reader")
    }
}

public final class ASCDuoPublishingService: DuoPublishingService {
    private let client: ASCAPIClient
    public init(client: ASCAPIClient) { self.client = client }
    public func withPhase<T>(_ phase: ASCRequestPhase, _ operation: () throws -> T) rethrows -> T {
        try client.withPhase(phase, operation)
    }

    public func verifyEditableTarget(_ set: DuoPublishSet) throws {
        try verifyEditableTargets([set])
    }

    public func verifyEditableTargets(_ sets: [DuoPublishSet]) throws {
        guard let set = sets.first else { return }
        guard sets.allSatisfy({ $0.appID == set.appID && $0.bundleID == set.bundleID &&
            $0.assetLibraryID == set.assetLibraryID && $0.versionID == set.versionID && $0.version == set.version }) else {
            throw DuoExecutionFailure.drift("Target verification cannot combine different apps or versions")
        }
        let app = try client.request(method: "GET", path: "/v1/apps/\(duoIdentifier(set.appID))")?["data"]
        let library = try client.request(method: "GET", path: "/v1/apps/\(set.appID)/assetLibrary")?["data"]
        let versions = try client.list(path: "/v1/apps/\(set.appID)/appStoreVersions", query: [
            URLQueryItem(name: "filter[platform]", value: "IOS"), URLQueryItem(name: "limit", value: "200")])
        let target = versions.filter { $0["id"] == .string(set.versionID) }
        guard app?["type"] == .string("apps"), app?["id"] == .string(set.appID),
              app?["attributes"]?["bundleId"] == .string(set.bundleID),
              library?["type"] == .string("appAssetLibraries"), library?["id"] == .string(set.assetLibraryID),
              target.count == 1, target[0]["type"] == .string("appStoreVersions"),
              target[0]["attributes"]?["versionString"] == .string(set.version),
              target[0]["attributes"]?["platform"] == .string("IOS"),
              target[0]["attributes"]?["appVersionState"] == .string("PREPARE_FOR_SUBMISSION") else {
            throw DuoExecutionFailure.drift("App/library/target no longer matches the editable reviewed version")
        }
        let locales = try client.list(path: "/v1/appStoreVersions/\(duoIdentifier(set.versionID))/appStoreVersionLocalizations",
                                      query: [URLQueryItem(name: "limit", value: "200")])
        for set in sets {
            guard locales.filter({ $0["type"] == .string("appStoreVersionLocalizations") && $0["id"] == .string(set.localizationID) &&
                $0["attributes"]?["locale"] == .string(set.locale) }).count == 1 else {
                throw DuoExecutionFailure.drift("Target localization no longer belongs to the reviewed version")
            }
        }
    }

    /// The executor calls this only after this invocation has verified the full
    /// app/library/version/localization binding. Resource IDs and ownership are
    /// checked again at the final boundary and at every new invocation.
    public func verifyEditableState(_ set: DuoPublishSet) throws {
        let target = try client.request(method: "GET", path: "/v1/appStoreVersions/\(duoIdentifier(set.versionID))")?["data"]
        guard target?["type"] == .string("appStoreVersions"), target?["id"] == .string(set.versionID),
              target?["attributes"]?["versionString"] == .string(set.version),
              target?["attributes"]?["platform"] == .string("IOS"),
              target?["attributes"]?["appVersionState"] == .string("PREPARE_FOR_SUBMISSION") else {
            throw DuoExecutionFailure.drift("Reviewed version is no longer editable")
        }
        if let app = target?["relationships"]?["app"]?["data"],
           app["id"] != .string(set.appID) || app["type"] != .string("apps") {
            throw DuoExecutionFailure.drift("Reviewed version belongs to a different app")
        }
    }

    public func placements(localizationID: String, group: String) throws -> [DuoRemotePlacement] {
        try placementReadback(localizationID: localizationID, group: group).placements
    }

    public func placementReadback(localizationID: String, group: String) throws -> DuoPlacementReadback {
        var path: String? = "/v1/appStoreVersionLocalizations/\(try duoIdentifier(localizationID))/placements"
        var query = [
            URLQueryItem(name: "filter[placementType]", value: "APP_SCREENSHOT"),
            URLQueryItem(name: "filter[placementGroup]", value: group),
            URLQueryItem(name: "sort", value: "placementGroupPosition"),
            URLQueryItem(name: "include", value: "image"), URLQueryItem(name: "limit", value: "200")
        ]
        var rows: [DuoRemotePlacement] = [], images: [String: JSONValue] = [:]
        while let current = path {
            guard let document = try client.request(method: "GET", path: current, query: query),
                  let data = document["data"]?.arrayValue else {
                throw DuoExecutionFailure.drift("Missing placement compound response")
            }
            rows += try data.map(DuoRemotePlacement.parse)
            for resource in document["included"]?.arrayValue ?? [] where resource["type"] == .string("appAssetLibraryImages") {
                guard let id = resource["id"]?.stringValue, resource["attributes"]?.objectValue != nil else {
                    throw DuoExecutionFailure.drift("Incomplete included image resource")
                }
                _ = try duoIdentifier(id)
                if let previous = images[id], previous != resource {
                    throw DuoExecutionFailure.drift("Conflicting included image resources")
                }
                images[id] = resource
            }
            if let next = document["links"]?["next"], next != .null {
                guard let link = next.stringValue else { throw DuoExecutionFailure.drift("Malformed placement pagination") }
                path = link // ASCAPIClient validates same-origin before attaching credentials.
            } else { path = nil }
            query = []
        }
        guard Set(rows.map(\.id)).count == rows.count else {
            throw DuoExecutionFailure.drift("Duplicate placement rows across pages")
        }
        let referenced = Set(rows.map(\.imageID))
        return DuoPlacementReadback(placements: rows, images: images.filter { referenced.contains($0.key) })
    }

    public func image(id: String) throws -> JSONValue {
        guard let image = try client.request(method: "GET", path: "/v1/appAssetLibraryImages/\(duoIdentifier(id))")?["data"],
              image["id"] == .string(id), image["type"] == .string("appAssetLibraryImages") else {
            throw DuoExecutionFailure.drift("Image resource disappeared")
        }
        return image
    }

    public func legacyDuoSet(localizationID: String) throws -> RemoteScreenshotSet? {
        let sets = try client.list(path: "/v1/appStoreVersionLocalizations/\(duoIdentifier(localizationID))/appScreenshotSets",
                                  query: [URLQueryItem(name: "limit", value: "200")])
            .filter { $0["attributes"]?["screenshotDisplayType"] == .string("APP_IPHONE_DUO") }
        guard sets.count <= 1 else { throw DuoExecutionFailure.drift("Multiple legacy Duo compatibility sets") }
        guard let set = sets.first, let id = set["id"]?.stringValue else { return nil }
        let raw = try client.list(path: "/v1/appScreenshotSets/\(duoIdentifier(id))/appScreenshots",
                                  query: [URLQueryItem(name: "limit", value: "200")])
        let images = try raw.map { row -> RemoteScreenshot in
            guard row["type"] == .string("appScreenshots"), let imageID = row["id"]?.stringValue,
                  let attributes = row["attributes"]?.objectValue else {
                throw DuoExecutionFailure.drift("Malformed legacy Duo compatibility image")
            }
            return RemoteScreenshot(id: try duoIdentifier(imageID), fileName: attributes["fileName"]?.stringValue,
                checksum: attributes["sourceFileChecksum"]?.stringValue, attributes: attributes)
        }
        return RemoteScreenshotSet(id: id, displayType: "APP_IPHONE_DUO", screenshots: images)
    }

    public func send(_ request: DuoAssetLibraryRequest) throws -> JSONValue? {
        guard try allowedMutation(request) else {
            throw ReleaseToolError.validation("Duo executor cannot mutate this resource")
        }
        do {
            return try client.request(method: request.method, path: request.path, body: request.body == .null ? nil : request.body,
                                      retryPolicy: .singleAttempt, reportHTTPStatus: true)
        } catch let error as ASCHTTPResponseError where (400..<500).contains(error.statusCode) && ![408, 429].contains(error.statusCode) {
            throw DuoExecutionFailure.rejected(error.localizedDescription)
        } catch {
            // A network/5xx/decode error may follow an executed mutation.
            throw DuoExecutionFailure.uncertain("\(request.method) \(request.path) did not return a known result")
        }
    }

    private func allowedMutation(_ request: DuoAssetLibraryRequest) throws -> Bool {
        let path = request.path.split(separator: "/").map(String.init)
        guard request.path == "/" + path.joined(separator: "/") else { return false }
        if request.method == "DELETE" {
            return path.count == 3 && path[0] == "v1" && path[1] == "appAssetLibraryPlacements" &&
                (try? duoIdentifier(path[2])) != nil && request.body == .null
        }
        if request.method == "PATCH" {
            guard path.count == 3, path[0] == "v1", path[1] == "appAssetLibraryImages",
                  (try? duoIdentifier(path[2])) != nil else { return false }
            return request.body == .object(["data": .object(["type": .string("appAssetLibraryImages"),
                "id": .string(path[2]), "attributes": .object(["uploaded": .bool(true)])])])
        }
        guard request.method == "POST", request.body.objectValue?.keys.sorted() == ["data"],
              let data = request.body["data"], data.objectValue?.keys.sorted() == ["attributes", "relationships", "type"],
              let attributes = data["attributes"], let relationships = data["relationships"] else { return false }
        func relation(_ value: JSONValue?, type: String) -> Bool {
            guard value?.objectValue?.keys.sorted() == ["data"], let data = value?["data"],
                  data.objectValue?.keys.sorted() == ["id", "type"], data["type"] == .string(type),
                  let id = data["id"]?.stringValue else { return false }
            return (try? duoIdentifier(id)) != nil
        }
        switch request.path {
        case "/v1/appAssetLibraryImages":
            return data["type"] == .string("appAssetLibraryImages") &&
                attributes.objectValue?.keys.sorted() == ["category", "fileName", "fileSize"] &&
                attributes["category"] == .string("APP_SCREENSHOTS_AND_PREVIEWS") &&
                (attributes["fileSize"]?.intValue ?? 0) > 0 &&
                attributes["fileName"]?.stringValue?.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*\.png$"#, options: .regularExpression) != nil &&
                relationships.objectValue?.keys.sorted() == ["assetLibrary"] && relation(relationships["assetLibrary"], type: "appAssetLibraries")
        case "/v1/appAssetLibraryPlacements":
            return data["type"] == .string("appAssetLibraryPlacements") &&
                attributes.objectValue?.keys.sorted() == ["placementGroup", "placementType"] &&
                attributes["placementType"] == .string("APP_SCREENSHOT") && attributes["placementGroup"]?.stringValue?.isEmpty == false &&
                relationships.objectValue?.keys.sorted() == ["appStoreVersionLocalization", "image"] &&
                relation(relationships["appStoreVersionLocalization"], type: "appStoreVersionLocalizations") &&
                relation(relationships["image"], type: "appAssetLibraryImages")
        case "/v1/appAssetLibraryPlacementOrderingRequests":
            guard let ordered = relationships["orderedPlacements"]?["data"]?.arrayValue,
                  (1...10).contains(ordered.count), Set(ordered.compactMap { $0["id"]?.stringValue }).count == ordered.count else { return false }
            return data["type"] == .string("appAssetLibraryPlacementOrderingRequests") &&
                attributes.objectValue?.keys.sorted() == ["placementGroup"] && attributes["placementGroup"]?.stringValue?.isEmpty == false &&
                relationships.objectValue?.keys.sorted() == ["appStoreVersionLocalization", "orderedPlacements"] &&
                relationships["orderedPlacements"]?.objectValue?.keys.sorted() == ["data"] &&
                ordered.allSatisfy { relation(.object(["data": $0]), type: "appAssetLibraryPlacements") } &&
                relation(relationships["appStoreVersionLocalization"], type: "appStoreVersionLocalizations")
        default: return false
        }
    }

    public func upload(_ operation: UploadOperation, bytes: Data) throws {
        do { try client.upload(operation: operation, fileData: bytes, retryPolicy: .singleAttempt) }
        catch { throw DuoExecutionFailure.uncertain("An upload operation did not return a known result; signed URL/headers are not journaled") }
    }
    public func download(_ url: URL) throws -> Data { try client.download(url: url) }
}
