import Foundation

public struct DuoImageAsset: Codable, Equatable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    public let templateSHA256: String

    static func read(_ value: JSONValue) throws -> (Self, URL) {
        guard let width = value["width"]?.intValue, let height = value["height"]?.intValue,
              width > 0, height > 0,
              let template = (value["templateUrl"] ?? value["template"])?.stringValue else {
            throw DuoExecutionFailure.drift("Missing cross-view image asset identity")
        }
        let expanded = template.replacingOccurrences(of: "{w}", with: String(width))
            .replacingOccurrences(of: "{h}", with: String(height))
            .replacingOccurrences(of: "{c}", with: "").replacingOccurrences(of: "{f}", with: "png")
        guard let url = URL(string: expanded), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else {
            throw DuoExecutionFailure.drift("Cross-view rendition is not supported HTTPS")
        }
        return (Self(width: width, height: height, templateSHA256: FileIO.sha256(Data(template.utf8))), url)
    }
}

public struct DuoLegacyImage: Codable, Equatable, Sendable {
    public let id: String
    public let fileName: String
    public let byteCount: Int
    public let checksum: String?
    public let asset: DuoImageAsset

    static func read(_ value: RemoteScreenshot, allowProcessing: Bool = false) throws -> Self {
        let state = value.attributes["assetDeliveryState"]?["state"]?.stringValue ?? ""
        guard state == "COMPLETE" || (allowProcessing && ["AWAITING_UPLOAD", "UPLOAD_COMPLETE", "PROCESSING"].contains(state)) else {
            throw DuoExecutionFailure.drift("Legacy Duo row is failed or has an unknown delivery state")
        }
        guard let name = value.fileName, let size = value.attributes["fileSize"]?.intValue, size > 0,
              let raw = value.attributes["imageAsset"] else {
            throw DuoExecutionFailure.drift("Legacy Duo row has no provable image identity")
        }
        return Self(id: try duoIdentifier(value.id), fileName: name, byteCount: size,
            checksum: value.checksum?.lowercased(), asset: try DuoImageAsset.read(raw).0)
    }
}

public struct DuoLegacyView: Codable, Equatable, Sendable {
    public let setID: String?
    public let images: [DuoLegacyImage]

    static func read(_ set: RemoteScreenshotSet?, allowProcessing: Bool = false) throws -> Self {
        guard let set else { return Self(setID: nil, images: []) }
        guard set.displayType == "APP_IPHONE_DUO", set.screenshots.count <= 10,
              Set(set.screenshots.map(\.id)).count == set.screenshots.count else {
            throw DuoExecutionFailure.drift("Duplicate or foreign legacy Duo projection")
        }
        return Self(setID: try duoIdentifier(set.id), images: try set.screenshots.map { try DuoLegacyImage.read($0, allowProcessing: allowProcessing) })
    }
}

public struct DuoContentProof: Codable, Equatable, Sendable {
    public let imageID: String
    public let fileName: String
    public let byteCount: Int
    public let asset: DuoImageAsset
    public let pixelSHA256: String
}

public struct DuoCompatibilityBaseline: Codable, Equatable, Sendable {
    public let policy: String
    public let legacy: DuoLegacyView
    public let placements: [DuoRemotePlacement]
    public let content: [DuoContentProof]
    public static let policyName = "single-duo-writer-both-views-content-v1"

    func validate() throws {
        guard policy == Self.policyName, placements.count <= 10,
              placements.count == content.count, content.count == legacy.images.count,
              (legacy.images.isEmpty || legacy.setID != nil),
              Set(legacy.images.map(\.id)).count == legacy.images.count,
              Set(placements.map(\.id)).count == placements.count,
              placements.allSatisfy({ $0.placementType == "APP_SCREENSHOT" &&
                  ["ACTIVE", "PARENT_PREPARE_FOR_SUBMISSION"].contains($0.state) }),
              Set(placements.map(\.group)).count <= 1 else {
            throw DuoExecutionFailure.drift("Malformed Duo cross-view baseline")
        }
        for (index, row) in placements.enumerated() {
            let proof = content[index], image = legacy.images[index]
            guard row.imageID == proof.imageID, image.fileName == proof.fileName,
                  image.byteCount == proof.byteCount, image.asset == proof.asset,
                  proof.pixelSHA256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
                throw DuoExecutionFailure.drift("Duo cross-view baseline content is not bound to its graph")
            }
        }
    }
}

struct DuoExpectedContent {
    let fileName: String
    let byteCount: Int
    let width: Int
    let height: Int
    let pixels: String
    let checksum: String?
    let pinnedAsset: DuoImageAsset?
    let pinnedLegacyID: String?
}

func duoSameGraph(_ lhs: [DuoRemotePlacement], _ rhs: [DuoRemotePlacement]) -> Bool {
    lhs.map(\.id) == rhs.map(\.id) && lhs.map(\.imageID) == rhs.map(\.imageID) &&
        lhs.map(\.group) == rhs.map(\.group) && lhs.map(\.placementType) == rhs.map(\.placementType)
}

private func duoEligibleGraph(_ rows: [DuoRemotePlacement], group: String) -> Bool {
    rows.count <= 10 && Set(rows.map(\.id)).count == rows.count && rows.allSatisfy {
        $0.group == group && $0.placementType == "APP_SCREENSHOT" &&
            ["ACTIVE", "PARENT_PREPARE_FOR_SUBMISSION"].contains($0.state)
    }
}

/// A single Asset Library writer with a mandatory, content-based legacy readback.
/// Polling a known previous projection never authorizes another mutation.
final class DuoCompatibilityVerifier {
    let service: DuoPublishingService
    let localizationID: String
    let group: String
    let attempts: Int
    let sleeper: (TimeInterval) -> Void
    private var pixelCache: [DuoImageAsset: String] = [:]

    init(service: DuoPublishingService, localizationID: String, group: String,
         attempts: Int, sleeper: @escaping (TimeInterval) -> Void) {
        self.service = service; self.localizationID = localizationID; self.group = group
        self.attempts = max(1, attempts); self.sleeper = sleeper
    }

    private func pixels(_ asset: DuoImageAsset, url: URL) throws -> String {
        if let cached = pixelCache[asset] { return cached }
        let data = try service.download(url)
        let decoded = try ImageValidation.decodePNG(data, context: "Duo compatibility rendition")
        guard decoded.pixelWidth == asset.width, decoded.pixelHeight == asset.height else {
            throw DuoExecutionFailure.drift("Duo compatibility rendition has the wrong native dimensions")
        }
        let sha = try ImageValidation.pixelSHA256(data, context: "Duo compatibility rendition")
        pixelCache[asset] = sha
        return sha
    }

    func prove(graph: [DuoRemotePlacement], expected: [DuoExpectedContent],
               previous: DuoCompatibilityBaseline?) throws -> DuoCompatibilityBaseline {
        guard graph.count == expected.count else { throw DuoExecutionFailure.drift("Missing expected Duo graph content") }
        for attempt in 0..<attempts {
            // A template URL is not an immutable revision. Only the two reads
            // within this attempt may share decoded content; every barrier reads anew.
            pixelCache.removeAll(keepingCapacity: true)
            let before = try service.placements(localizationID: localizationID, group: group)
            guard duoEligibleGraph(before, group: group), duoSameGraph(before, graph) else { throw DuoExecutionFailure.drift("Duo graph changed around compatibility readback") }
            let rawLegacy = try service.legacyDuoSet(localizationID: localizationID)
            let legacy = try DuoLegacyView.read(rawLegacy, allowProcessing: true)
            let complete = rawLegacy?.screenshots.allSatisfy {
                $0.attributes["assetDeliveryState"]?["state"] == .string("COMPLETE")
            } ?? true
            if let previous, !duoSameGraph(previous.placements, graph), legacy == previous.legacy {
                if attempt + 1 < attempts { sleeper(2); continue }
                throw DuoExecutionFailure.uncertain("Legacy Duo view still shows the proven previous graph; no mutation is replayed")
            }
            guard legacy.images.count == graph.count else {
                throw DuoExecutionFailure.drift("Legacy Duo view contains unknown or missing rows")
            }
            if let previous, duoSameGraph(previous.placements, graph), legacy != previous.legacy {
                throw DuoExecutionFailure.drift("Stable Duo graph has a changed legacy resource identity")
            }
            var content: [DuoContentProof] = []
            for (index, row) in graph.enumerated() {
                let wanted = expected[index], old = legacy.images[index]
                let raw = try service.image(id: row.imageID)
                guard raw["id"] == .string(row.imageID), let attributes = raw["attributes"],
                      attributes["category"] == .string("APP_SCREENSHOTS_AND_PREVIEWS"),
                      let state = attributes["state"]?.stringValue,
                      ["PREPARE_FOR_SUBMISSION", "APPROVED", "ACCEPTED"].contains(state),
                      attributes["fileName"] == .string(wanted.fileName),
                      attributes["fileSize"]?.intValue == wanted.byteCount,
                      let imageAsset = attributes["imageAsset"] else {
                    throw DuoExecutionFailure.drift("Duo library image changed outside its known upload/baseline")
                }
                let asset = try DuoImageAsset.read(imageAsset)
                guard asset.0.width == wanted.width, asset.0.height == wanted.height,
                      wanted.pinnedAsset == nil || wanted.pinnedAsset == asset.0,
                      old.asset == asset.0, old.fileName == wanted.fileName, old.byteCount == wanted.byteCount,
                      wanted.pinnedLegacyID == nil || wanted.pinnedLegacyID == old.id,
                      wanted.checksum == nil || old.checksum == nil || wanted.checksum == old.checksum else {
                    throw DuoExecutionFailure.drift("Duo views have different image identities, content metadata or order")
                }
                let pixelSHA = try pixels(asset.0, url: asset.1)
                guard pixelSHA == wanted.pixels else {
                    throw DuoExecutionFailure.drift("Duo readback pixels differ from the exact owned content")
                }
                content.append(DuoContentProof(imageID: row.imageID, fileName: wanted.fileName,
                    byteCount: wanted.byteCount, asset: asset.0, pixelSHA256: pixelSHA))
            }
            let after = try service.placements(localizationID: localizationID, group: group)
            let rawAfter = try service.legacyDuoSet(localizationID: localizationID)
            let legacyAfter = try DuoLegacyView.read(rawAfter, allowProcessing: true)
            guard duoEligibleGraph(after, group: group), duoSameGraph(after, before), legacyAfter == legacy else {
                throw DuoExecutionFailure.drift("Duo views changed during compatibility readback")
            }
            let afterComplete = rawAfter?.screenshots.allSatisfy {
                $0.attributes["assetDeliveryState"]?["state"] == .string("COMPLETE")
            } ?? true
            guard complete && afterComplete else {
                if attempt + 1 < attempts { sleeper(2); continue }
                throw DuoExecutionFailure.uncertain("Known owned Duo rows remain processing; no further mutation is permitted")
            }
            let result = DuoCompatibilityBaseline(policy: DuoCompatibilityBaseline.policyName,
                legacy: legacy, placements: graph, content: content)
            try result.validate()
            return result
        }
        throw DuoExecutionFailure.uncertain("Duo compatibility proof is unresolved")
    }
}

/// GET-only evidence. URLs, headers, credentials and downloaded PNGs are not retained.
public enum DuoCompatibilityInspector {
    public static func capture(snapshot: RemoteSnapshot, snapshotSHA256: String,
                               inspection: JSONValue, inspectionSHA256: String,
                               service: DuoPublishingService,
                               progress: ((Int, Int) -> Void)? = nil) throws -> JSONValue {
        let versions = [snapshot.sourceVersion, snapshot.targetVersion].compactMap { $0 }
        guard inspection["remoteMutationsPerformed"] == .bool(false),
              inspection["requestMethods"] == .array([.string("GET")]),
              inspection["appId"] == .string(snapshot.appId),
              inspection["bundleId"] == .string(snapshot.bundleId),
              let versionID = inspection["targetVersion"]?["id"]?.stringValue,
              let version = versions.first(where: { $0.id == versionID }),
              inspection["requestedVersion"] == .string(version.versionString),
              let group = inspection["routing"]?["placementGroup"]?.stringValue else {
            throw ReleaseToolError.validation("Compatibility inspection needs the exact existing version and GET-only baseline")
        }
        var rows: [JSONValue] = []
        for (index, locale) in version.localizations.enumerated() {
            let sets = locale.screenshotSets.filter { $0.displayType == "APP_IPHONE_DUO" }
            guard sets.count <= 1 else { throw DuoExecutionFailure.drift("Multiple legacy Duo views") }
            let legacy = try DuoLegacyView.read(sets.first)
            let inspected = (inspection["localizations"]?.arrayValue ?? []).filter { $0["locale"] == .string(locale.locale) }
            guard inspected.count == 1, inspected[0]["localizationId"] == .string(locale.id),
                  let raw = inspected[0]["orderedPlacements"]?.arrayValue else {
                throw DuoExecutionFailure.drift("Compatibility locale identity differs")
            }
            let placements = try raw.map(DuoRemotePlacement.parse)
            let before = try service.placements(localizationID: locale.id, group: group)
            guard duoEligibleGraph(before, group: group), before == placements, legacy.images.count == placements.count,
                  try DuoLegacyView.read(service.legacyDuoSet(localizationID: locale.id)) == legacy else {
                throw DuoExecutionFailure.drift("Cross-view baseline count or placement graph changed")
            }
            var proofs: [DuoContentProof] = []
            for (position, row) in placements.enumerated() {
                let cloud = try service.image(id: row.imageID)
                guard cloud["id"] == .string(row.imageID), cloud["type"] == .string("appAssetLibraryImages"),
                      let attributes = cloud["attributes"], attributes["category"] == .string("APP_SCREENSHOTS_AND_PREVIEWS"),
                      ["APPROVED", "ACCEPTED", "PREPARE_FOR_SUBMISSION"].contains(attributes["state"]?.stringValue ?? ""),
                      let imageAsset = attributes["imageAsset"],
                      attributes["fileName"] == .string(legacy.images[position].fileName),
                      attributes["fileSize"]?.intValue == legacy.images[position].byteCount else {
                    throw DuoExecutionFailure.drift("Cross-view file metadata differs")
                }
                let asset = try DuoImageAsset.read(imageAsset)
                guard asset.0 == legacy.images[position].asset else {
                    throw DuoExecutionFailure.drift("Cross-view image asset identity differs")
                }
                let legacyRaw = sets[0].screenshots[position].attributes["imageAsset"]!
                let legacyURL = try DuoImageAsset.read(legacyRaw).1
                let libraryPNG = try service.download(asset.1), legacyPNG = try service.download(legacyURL)
                for bytes in [libraryPNG, legacyPNG] {
                    let decoded = try ImageValidation.decodePNG(bytes, context: "cross-view native-size rendition")
                    guard decoded.pixelWidth == asset.0.width, decoded.pixelHeight == asset.0.height else {
                        throw DuoExecutionFailure.drift("Cross-view rendition is not the recorded native size")
                    }
                }
                let libraryPixels = try ImageValidation.pixelSHA256(libraryPNG, context: "library cross-view baseline")
                let legacyPixels = try ImageValidation.pixelSHA256(legacyPNG, context: "legacy cross-view baseline")
                guard libraryPixels == legacyPixels else { throw DuoExecutionFailure.drift("Cross-view decoded pixels differ") }
                proofs.append(DuoContentProof(imageID: row.imageID, fileName: legacy.images[position].fileName,
                    byteCount: legacy.images[position].byteCount, asset: asset.0, pixelSHA256: libraryPixels))
            }
            guard try service.placements(localizationID: locale.id, group: group) == before,
                  try DuoLegacyView.read(service.legacyDuoSet(localizationID: locale.id)) == legacy else {
                throw DuoExecutionFailure.drift("Placement graph changed during cross-view content proof")
            }
            let baseline = DuoCompatibilityBaseline(policy: DuoCompatibilityBaseline.policyName,
                legacy: legacy, placements: placements, content: proofs)
            let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(baseline))
            rows.append(.object(["locale": .string(locale.locale), "localizationID": .string(locale.id), "baseline": value]))
            progress?(index + 1, version.localizations.count)
        }
        return .object(["schemaVersion": .number(1), "mode": .string("duo-cross-view-readonly-proof"),
            "capturedAt": .string(ISO8601DateFormatter.releaseTool.string(from: Date())),
            "snapshotSHA256": .string(snapshotSHA256), "inspectionSHA256": .string(inspectionSHA256),
            "snapshotFingerprint": .string(snapshot.fingerprint),
            "appID": .string(snapshot.appId), "bundleID": .string(snapshot.bundleId),
            "version": .string(version.versionString), "versionID": .string(version.id),
            "policy": .string(DuoCompatibilityBaseline.policyName), "locales": .array(rows),
            "requestMethods": .array([.string("GET")]), "remoteMutationsPerformed": .bool(false),
            "writePropagationProven": .bool(false)])
    }
}
