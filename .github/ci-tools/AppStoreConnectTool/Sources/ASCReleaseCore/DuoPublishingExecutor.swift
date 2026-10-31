import Foundation

/// Per-localization execution for an admitted, digest-confirmed selected handoff.
/// Historical capture limitations remain recorded independently of admission.
public final class DuoPublishingExecutor {
    private let set: DuoPublishSet
    private let adapter: DuoAssetLibraryAdapter
    private let service: DuoPublishingService
    private let file: DuoJournalFile
    private var journal: DuoExecutionJournal
    private let attempts: Int
    private let sleeper: (TimeInterval) -> Void
    private let backupWriter: (Data, URL) throws -> Void
    private let compatibilityVerifier: DuoCompatibilityVerifier?
    private var localPixelCache: [String: String] = [:]

    public init(set: DuoPublishSet, journalURL: URL, service: DuoPublishingService,
                pollAttempts: Int = 120, compatibilityPollAttempts: Int = 12,
                sleeper: @escaping (TimeInterval) -> Void = Thread.sleep,
                journalWriter: ((Data, URL) throws -> Void)? = nil,
                backupWriter: ((Data, URL) throws -> Void)? = nil) throws {
        self.set = set; self.service = service; self.attempts = max(1, pollAttempts); self.sleeper = sleeper
        self.backupWriter = backupWriter ?? DuoJournalFile.writeNewDataDurably
        let resolvedAdapter = try DuoAssetLibraryAdapter(catalog: set.catalog, assetLibraryID: set.assetLibraryID)
        adapter = resolvedAdapter
        compatibilityVerifier = set.compatibilityBaseline.map { _ in
            DuoCompatibilityVerifier(service: service, localizationID: set.localizationID,
                group: resolvedAdapter.routing["placementGroup"]!.stringValue!,
                attempts: compatibilityPollAttempts, sleeper: sleeper)
        }
        file = try DuoJournalFile(url: journalURL, writer: journalWriter)
        let digest = try set.digest()
        if FileManager.default.fileExists(atPath: journalURL.path) {
            journal = try ManifestBuilder.decode(DuoExecutionJournal.self, at: journalURL)
            guard journal.schemaVersion == 1, journal.setDigest == digest, journal.version == set.version,
                  journal.rollbackStrategy == "verified-png-backup-reupload-v1" else {
                throw ReleaseToolError.validation("Duo journal belongs to a different reviewed set or recovery strategy")
            }
        } else {
            journal = DuoExecutionJournal(setDigest: digest, version: set.version,
                rollbackStrategy: "verified-png-backup-reupload-v1", activeBaseline: set.reviewedBaseline,
                activeCompatibility: set.compatibilityBaseline, compatibilityCheckpoint: set.compatibilityBaseline)
            try file.save(journal)
        }
        if let baseline = set.compatibilityBaseline {
            try baseline.validate()
            guard baseline.placements == set.reviewedBaseline,
                  let active = journal.activeCompatibility, let checkpoint = journal.compatibilityCheckpoint else {
                throw ReleaseToolError.validation("Dual-view publishing cannot adopt a journal without its reviewed content proof")
            }
            try active.validate(); try checkpoint.validate()
            guard duoSameGraph(active.placements, journal.activeBaseline) else {
                throw ReleaseToolError.validation("Duo active baseline and compatibility proof differ")
            }
        }
    }

    /// GET-only remote reconciliation before the aggregate publisher may write.
    /// Known readbacks may update the local journal; an offline dry run never calls this.
    func preflight(allowRollbackProof: Bool = false) throws {
        for image in set.images { _ = try validatedBytes(image) }
        try service.verifyEditableTarget(set)
        if journal.phase == "complete" {
            try requireExactGroup(journal.completedPlacements)
            for image in set.images { _ = try processedImage(id: try reservedID("desired:\(image.position)"), file: image) }
            try proveCompatibility(try group())
            return
        }
        guard ["preparing", "switching", "rollingBack", "rolledBack"].contains(journal.phase) else {
            throw DuoExecutionFailure.uncertain("Unknown Duo journal phase before aggregate publishing")
        }
        guard journal.phase != "rollingBack" || allowRollbackProof else {
            throw DuoExecutionFailure.uncertain("Pending Duo rollback must finish before other aggregate writes")
        }
        try sealAndVerifyBackup()
        for image in set.images { try preflightStagedImage(image, key: "desired:\(image.position)") }
        for backup in journal.backups {
            try preflightStagedImage(backup.file, key: "restore:\(journal.epoch):\(backup.file.position)")
        }
        if ["switching", "rollingBack"].contains(journal.phase) {
            try reconcilePendingPlacementCreates()
            for stage in ["switch", "restore"] {
                let key = "\(stage):\(journal.epoch):order"
                guard let pending = latest(key), ["intent", "uncertain", "responseKnown"].contains(pending.status) else { continue }
                let current = try group()
                let count = stage == "switch" ? set.images.count : journal.backups.count
                let ids: [String]
                if stage == "restore" {
                    ids = journal.activeBaseline.enumerated().compactMap { index, old in
                        current.contains(where: { $0.id == old.id && $0.imageID == old.imageID })
                            ? old.id : latest("restore:\(journal.epoch):place:\(index + 1)")?.resourceID
                    }
                } else {
                    ids = (1...max(1, count)).prefix(count).compactMap { latest("switch:\(journal.epoch):place:\($0)")?.resourceID }
                }
                guard ids.count == count, current.map(\.id) == ids else {
                    throw DuoExecutionFailure.uncertain("Pending ordering has no exact whole-group readback before aggregate writes")
                }
                journal.expectedGraph = current
                try entry(key, "verified", digest: pending.requestDigest)
            }
            try guardOwnedGraph()
        } else {
            try requireExactGroup(journal.activeBaseline)
            try proveCompatibility(try group())
        }
        let keys = Set(journal.entries.map(\.key))
        guard keys.allSatisfy({ key in
            latest(key).map { ["verified", "rejected"].contains($0.status) } ?? false
        }) else {
            throw DuoExecutionFailure.uncertain("Unresolved Duo reservation/upload intent stops aggregate writes")
        }
    }

    private func preflightStagedImage(_ image: DuoPublishImage, key: String) throws {
        guard let reservation = latest(key + ":reserve") else { return }
        guard ["verified", "responseKnown"].contains(reservation.status), let id = reservation.resourceID else {
            throw DuoExecutionFailure.uncertain("Pending reservation has no exact known image identity")
        }
        let raw = try basicImage(id, file: image)
        if reservation.status != "verified" {
            try entry(key + ":reserve", "verified", digest: reservation.requestDigest, id: id)
        }
        let upload = latest(key + ":upload"), commit = latest(key + ":commit")
        guard raw["attributes"]?["state"] != .string("PREPARE_FOR_SUBMISSION") || commit != nil else {
            throw DuoExecutionFailure.drift("Staged image was committed outside this journal")
        }
        if commit?.status == "verified" || [upload, commit].contains(where: {
            $0.map { ["intent", "uncertain", "responseKnown"].contains($0.status) } ?? false
        }) {
            _ = try processedImage(id: id, file: image)
            for suffix in [":upload", ":commit"] {
                if let pending = latest(key + suffix), ["intent", "uncertain", "responseKnown"].contains(pending.status) {
                    try entry(key + suffix, "verified", digest: pending.requestDigest, id: id)
                }
            }
        } else {
            guard raw["attributes"]?["state"] == .string("AWAITING_UPLOAD") else {
                throw DuoExecutionFailure.drift("Staged image no longer matches its uncommitted journal state")
            }
        }
    }

    public func publish(confirmedVersion: String, confirmedSetDigest: String) throws {
        guard confirmedVersion == set.version, try set.digest() == confirmedSetDigest,
              set.sourceManifestSHA256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
              set.images.map(\.position) == Array(1...10), set.reviewedBaseline.count <= 10 else {
            throw ReleaseToolError.validation("Duo execution requires the exact reviewed version, set digest and ten-image order")
        }
        for id in [set.appID, set.assetLibraryID, set.versionID, set.localizationID] { _ = try duoIdentifier(id) }
        for image in set.images { _ = try validatedBytes(image) }
        try service.verifyEditableTarget(set)
        if journal.phase == "complete" {
            try requireExactGroup(journal.completedPlacements)
            for image in set.images { _ = try processedImage(id: try reservedID("desired:\(image.position)"), file: image) }
            try proveCompatibility(try group())
            return
        }
        if journal.phase == "rollingBack" {
            try rollback()
            throw DuoExecutionFailure.restored("An interrupted rollback completed; review its checkpoint before resuming the same set")
        }
        if journal.phase == "rolledBack" {
            try requireExactGroup(journal.activeBaseline)
            journal.epoch += 1; journal.phase = "preparing"; try save()
        }
        if journal.phase == "preparing" { try proveCompatibility(try group()) }
        try sealAndVerifyBackup()
        var desiredImages: [Int: String] = [:]
        for image in set.images { desiredImages[image.position] = try stage(image, key: "desired:\(image.position)") }
        if journal.phase == "preparing" {
            try requireExactGroup(journal.activeBaseline)
            try verifyBaselineImageIdentities()
            journal.expectedGraph = journal.activeBaseline
            journal.phase = "switching"; try save()
        }
        guard journal.phase == "switching" else { throw DuoExecutionFailure.uncertain("Unknown journal phase") }
        do {
            try reconcilePendingPlacementCreates()
            try guardOwnedGraph()
            let orderKey = "switch:\(journal.epoch):order"
            if let previous = latest(orderKey), previous.status != "rejected" {
                let ids = try set.images.map { image -> String in
                    guard let id = latest("switch:\(journal.epoch):place:\(image.position)")?.resourceID else {
                        throw DuoExecutionFailure.uncertain("An ordering intent has incomplete placement identities")
                    }
                    return id
                }
                try order(ids, key: orderKey, baselineCount: nil)
                try finish(ids: ids, desiredImages: desiredImages)
                return
            }
            for old in journal.activeBaseline {
                try remove(old.id, key: "switch:\(journal.epoch):delete:\(old.id)")
            }
            var ids: [String] = []
            for image in set.images {
                let cloud = try processedImage(id: desiredImages[image.position]!, file: image)
                let request = try adapter.placeProcessedImage(cloud, expectedSpecID: image.specID, localizationID: set.localizationID)
                let key = "switch:\(journal.epoch):place:\(image.position)"
                let id = try createPlacement(key: key, request: request, imageID: desiredImages[image.position]!)
                ids.append(id)
            }
            try order(ids, key: "switch:\(journal.epoch):order", baselineCount: nil)
            try finish(ids: ids, desiredImages: desiredImages)
        } catch let failure as DuoExecutionFailure {
            guard case .rejected = failure else { throw failure }
            journal.phase = "rollingBack"; try save()
            do { try rollback() }
            catch { throw DuoExecutionFailure.uncertain("Replacement failed and rollback is incomplete; retained journal/backup must be inspected") }
            throw DuoExecutionFailure.restored(failure.localizedDescription)
        }
    }

    private var groupID: String { adapter.routing["placementGroup"]!.stringValue! }
    private func finish(ids: [String], desiredImages: [Int: String]) throws {
        let current = try group()
        guard current.map(\.id) == ids, current.map(\.imageID) == set.images.map({ desiredImages[$0.position]! }) else {
            throw DuoExecutionFailure.uncertain("Final Duo order/image readback does not match the reviewed set")
        }
        for image in set.images { _ = try processedImage(id: desiredImages[image.position]!, file: image) }
        try proveCompatibility(current)
        journal.completedPlacements = current; journal.phase = "complete"; try save()
    }
    private func save() throws { try file.save(journal) }
    private func latest(_ key: String) -> DuoExecutionEntry? { journal.entries.last { $0.key == key } }
    private func entry(_ key: String, _ status: String, digest: String, id: String? = nil) throws {
        journal.entries.append(DuoExecutionEntry(key: key, status: status, requestDigest: digest, resourceID: id))
        try save()
    }
    private func digest<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return FileIO.sha256(try encoder.encode(value))
    }
    private func verify(_ key: String) throws {
        guard let previous = latest(key) else { throw DuoExecutionFailure.uncertain("Missing mutation intent") }
        if previous.status != "verified" { try entry(key, "verified", digest: previous.requestDigest, id: previous.resourceID) }
    }

    /// No mutation is retried after an unknown result unless an exact GET
    /// readback proves that operation's known resource or intended whole order.
    private func mutate(_ key: String, request: DuoAssetLibraryRequest,
                        reconcile: () throws -> (Bool, String?), expectsID: String? = nil) throws -> String? {
        let hash = try digest(request)
        if let previous = latest(key) {
            guard previous.requestDigest == hash else { throw DuoExecutionFailure.drift("Journaled request changed") }
            if ["verified", "responseKnown"].contains(previous.status) { return previous.resourceID }
            if ["intent", "uncertain"].contains(previous.status) {
                let (matches, id) = try reconcile()
                guard matches else { throw DuoExecutionFailure.uncertain("Unresolved operation \(key); no POST replay was attempted") }
                try entry(key, "verified", digest: hash, id: id); return id
            }
        }
        try entry(key, "intent", digest: hash)
        do {
            let response = try service.send(request)
            var id: String?
            if let type = expectsID {
                guard response?["data"]?["type"] == .string(type), let value = response?["data"]?["id"]?.stringValue else {
                    throw DuoExecutionFailure.uncertain("Create response did not identify its resource")
                }
                id = try duoIdentifier(value)
            }
            try entry(key, "responseKnown", digest: hash, id: id)
            return id
        } catch let failure as DuoExecutionFailure {
            if case .persistence = failure { throw failure }
            let status: String
            if case .rejected = failure { status = "rejected" } else { status = "uncertain" }
            try entry(key, status, digest: hash)
            throw failure
        } catch {
            try entry(key, "uncertain", digest: hash)
            throw DuoExecutionFailure.uncertain("Mutation did not return a known result")
        }
    }

    private func rawSpec(_ id: String) throws -> JSONValue {
        let rows = (set.catalog.first?["attributes"]?["imageSpecs"]?.arrayValue ?? []).filter { $0["specId"] == .string(id) }
        guard rows.count == 1, adapter.routing["imageSpecs"]?.arrayValue?.contains(where: { $0["specId"] == .string(id) }) == true else {
            throw ReleaseToolError.validation("Duo image has no unique reviewed catalog specification")
        }
        return rows[0]
    }
    private func validatedBytes(_ image: DuoPublishImage) throws -> Data {
        let url = URL(fileURLWithPath: image.path).standardizedFileURL
        let spec = try rawSpec(image.specID)
        guard url.resolvingSymlinksInPath() == url, url.lastPathComponent == image.fileName,
              spec["dimensions"]?["minWidth"]?.intValue == image.pixelWidth,
              spec["dimensions"]?["minHeight"]?.intValue == image.pixelHeight,
              spec["mimeTypes"]?.arrayValue?.contains(.string("image/png")) == true else {
            throw ReleaseToolError.validation("Duo image path or specification changed")
        }
        let data = try Data(contentsOf: url)
        guard data.count == image.byteCount, FileIO.sha256(data) == image.sha256,
              data.count <= (spec["maxFileSize"]?.intValue ?? 0) else {
            throw ReleaseToolError.validation("Duo image bytes differ from the reviewed manifest")
        }
        try ImageValidation.validateScreenshot(data, pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight, context: image.fileName)
        return data
    }
    private func group() throws -> [DuoRemotePlacement] {
        let rows = try service.placements(localizationID: set.localizationID, group: groupID)
        guard rows.count <= 10, Set(rows.map(\.id)).count == rows.count,
              rows.allSatisfy({ $0.group == groupID && $0.placementType == "APP_SCREENSHOT" &&
                  ["ACTIVE", "PARENT_PREPARE_FOR_SUBMISSION"].contains($0.state) }) else {
            throw DuoExecutionFailure.drift("Duo group contains duplicate, processing, failed or foreign placements")
        }
        return rows
    }
    private func sameBindings(_ lhs: [DuoRemotePlacement], _ rhs: [DuoRemotePlacement]) -> Bool {
        lhs.map(\.id) == rhs.map(\.id) && lhs.map(\.imageID) == rhs.map(\.imageID)
    }
    private func requireExactGroup(_ expected: [DuoRemotePlacement]) throws {
        try service.verifyEditableTarget(set)
        guard sameBindings(try group(), expected) else { throw DuoExecutionFailure.drift("Reviewed ordered Duo baseline changed") }
    }
    private func imageIdentity(_ image: JSONValue) throws -> JSONValue {
        guard image["type"] == .string("appAssetLibraryImages"), let id = image["id"]?.stringValue,
              let attrs = image["attributes"], attrs["category"] == .string("APP_SCREENSHOTS_AND_PREVIEWS"),
              let name = attrs["fileName"], let size = attrs["fileSize"], let spec = attrs["specId"],
              let state = attrs["state"], let width = attrs["imageAsset"]?["width"], let height = attrs["imageAsset"]?["height"] else {
            throw DuoExecutionFailure.drift("Original image metadata is incomplete")
        }
        return .object(["id": .string(id), "fileName": name, "fileSize": size, "specId": spec,
                        "category": .string("APP_SCREENSHOTS_AND_PREVIEWS"), "state": state, "width": width, "height": height])
    }
    private func verifyBaselineImageIdentities() throws {
        for old in journal.activeBaseline {
            let raw = try service.image(id: old.imageID)
            guard raw["id"] == .string(old.imageID), try imageIdentity(raw) == journal.activeImageIdentities[old.imageID] else {
                throw DuoExecutionFailure.drift("Original cloud image identity changed")
            }
        }
    }

    private func sealAndVerifyBackup() throws {
        if let sealed = journal.backupDigest {
            guard try digest(journal.backups) == sealed, journal.backups.count == journal.activeBaseline.count else {
                throw DuoExecutionFailure.drift("Sealed Duo backup changed")
            }
            for backup in journal.backups { _ = try validatedBytes(backup.file) }
            if journal.phase == "preparing" { try requireExactGroup(journal.activeBaseline); try verifyBaselineImageIdentities() }
            return
        }
        try requireExactGroup(journal.activeBaseline)
        let directory = file.url.deletingLastPathComponent().appendingPathComponent("duo-backup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try DuoJournalFile.syncDirectory(directory.deletingLastPathComponent())
        var backups: [DuoBackupImage] = [], identities: [String: JSONValue] = [:]
        for (index, old) in journal.activeBaseline.enumerated() {
            let cloud = try service.image(id: old.imageID), identity = try imageIdentity(cloud)
            guard cloud["id"] == .string(old.imageID), let specID = identity["specId"]?.stringValue, let width = identity["width"]?.intValue,
                  let height = identity["height"]?.intValue,
                  let template = (cloud["attributes"]?["imageAsset"]?["templateUrl"] ?? cloud["attributes"]?["imageAsset"]?["template"])?.stringValue else {
                throw DuoExecutionFailure.drift("Cannot seal original Duo image content")
            }
            let source = template.replacingOccurrences(of: "{w}", with: String(width)).replacingOccurrences(of: "{h}", with: String(height))
                .replacingOccurrences(of: "{c}", with: "").replacingOccurrences(of: "{f}", with: "png")
            guard let url = URL(string: source), url.scheme == "https", url.user == nil, url.password == nil else {
                throw DuoExecutionFailure.drift("Original image backup URL is not a supported HTTPS resource")
            }
            let data = try ImageValidation.removingOpaqueAlphaChannel(from: service.download(url), context: "original Duo backup")
            let name = "backup-\(index + 1).png", path = directory.appendingPathComponent(name)
            let image = DuoPublishImage(position: index + 1, path: path.path, fileName: name, byteCount: data.count,
                sha256: FileIO.sha256(data), pixelWidth: width, pixelHeight: height, specID: specID,
                origin: .object(["kind": .string("remote-PNG-content-backup"), "originalImageID": .string(old.imageID)]))
            try backupWriter(data, path); _ = try validatedBytes(image)
            backups.append(DuoBackupImage(originalPlacement: old, originalImageIdentity: identity, file: image)); identities[old.imageID] = identity
        }
        try requireExactGroup(journal.activeBaseline)
        journal.backups = backups; journal.activeImageIdentities = identities; journal.backupDigest = try digest(backups); try save()
    }

    private func reservedID(_ key: String) throws -> String {
        guard let id = latest(key + ":reserve")?.resourceID else { throw DuoExecutionFailure.uncertain("No known reserved image ID") }
        return id
    }
    private func basicImage(_ id: String, file image: DuoPublishImage) throws -> JSONValue {
        let raw = try service.image(id: id)
        guard raw["id"] == .string(id), raw["type"] == .string("appAssetLibraryImages"),
              raw["attributes"]?["category"] == .string("APP_SCREENSHOTS_AND_PREVIEWS"),
              raw["attributes"]?["fileName"] == .string(image.fileName), raw["attributes"]?["fileSize"]?.intValue == image.byteCount else {
            throw DuoExecutionFailure.drift("Journaled image ID no longer matches its uploaded file")
        }
        return raw
    }
    private func processedImage(id: String, file image: DuoPublishImage) throws -> JSONValue {
        for index in 0..<attempts {
            let raw = try basicImage(id, file: image)
            if raw["attributes"]?["state"] == .string("PREPARE_FOR_SUBMISSION") {
                guard raw["attributes"]?["specId"] == .string(image.specID),
                      raw["attributes"]?["imageAsset"]?["width"]?.intValue == image.pixelWidth,
                      raw["attributes"]?["imageAsset"]?["height"]?.intValue == image.pixelHeight else {
                    throw DuoExecutionFailure.rejected("Processed image does not match the intended Duo specification")
                }
                return raw
            }
            if raw["attributes"]?["state"] == .string("FAILED") { throw DuoExecutionFailure.rejected("Duo image processing failed") }
            if index + 1 < attempts { sleeper(5) }
        }
        throw DuoExecutionFailure.uncertain("Duo image processing did not finish within the bounded poll")
    }

    private func stage(_ image: DuoPublishImage, key: String) throws -> String {
        let bytes = try validatedBytes(image), reserveKey = key + ":reserve"
        let reservation = try adapter.reserveImage(fileName: image.fileName, fileSize: image.byteCount)
        guard let id = try mutate(reserveKey, request: reservation, reconcile: { (false, nil) }, expectsID: "appAssetLibraryImages") else {
            throw DuoExecutionFailure.uncertain("Reservation did not identify an image")
        }
        var raw = try basicImage(id, file: image); try verify(reserveKey)
        let uploadKey = key + ":upload"
        if latest(uploadKey)?.status != "verified" {
            if let pending = latest(uploadKey), ["intent", "uncertain"].contains(pending.status) {
                _ = try processedImage(id: id, file: image)
                try entry(uploadKey, "verified", digest: pending.requestDigest, id: id)
            } else {
                guard raw["attributes"]?["state"] == .string("AWAITING_UPLOAD"),
                      let rows = raw["attributes"]?["uploadOperations"]?.arrayValue, !rows.isEmpty else {
                    throw DuoExecutionFailure.drift("Image processed without this journal's upload intent, or fresh upload operations are missing")
                }
                let operations = try rows.map(UploadOperation.parse).sorted { $0.offset < $1.offset }
                var end = 0
                for operation in operations {
                    guard operation.offset == end, operation.length > 0, operation.length <= bytes.count - end,
                          operation.method == "PUT", let url = URL(string: operation.url), url.scheme == "https" else {
                        throw DuoExecutionFailure.rejected("Upload operations must cover the exact image without gaps or overlaps")
                    }
                    end += operation.length
                }
                guard end == bytes.count else { throw DuoExecutionFailure.rejected("Upload operations do not cover the reviewed image") }
                let hash = try digest(.object(["imageID": .string(id), "sha256": .string(image.sha256), "bytes": .number(Double(bytes.count))]) as JSONValue)
                try entry(uploadKey, "intent", digest: hash, id: id)
                do {
                    for operation in operations { try service.upload(operation, bytes: bytes) }
                    try entry(uploadKey, "verified", digest: hash, id: id)
                } catch {
                    try entry(uploadKey, "uncertain", digest: hash, id: id)
                    throw DuoExecutionFailure.uncertain("Upload outcome is unresolved; URLs/headers were not persisted")
                }
            }
        }
        raw = try basicImage(id, file: image)
        let commitKey = key + ":commit", commit = try adapter.commitImage(imageID: id)
        if raw["attributes"]?["state"] == .string("PREPARE_FOR_SUBMISSION") {
            guard latest(commitKey) != nil else { throw DuoExecutionFailure.drift("Image was committed outside this journal") }
            _ = try processedImage(id: id, file: image)
            try entry(commitKey, "verified", digest: digest(commit), id: id)
        } else {
            _ = try mutate(commitKey, request: commit, reconcile: { [self] in
                _ = try processedImage(id: id, file: image); return (true, id)
            })
            _ = try processedImage(id: id, file: image); try verify(commitKey)
        }
        return id
    }

    private func remove(_ id: String, key: String) throws {
        try guardOwnedGraph()
        let request = DuoAssetLibraryRequest(method: "DELETE", path: "/v1/appAssetLibraryPlacements/\(try duoIdentifier(id))", body: .null)
        _ = try mutate(key, request: request, reconcile: { [self] in (!(try group()).contains { $0.id == id }, nil) })
        let current = try group()
        guard !current.contains(where: { $0.id == id }) else { throw DuoExecutionFailure.uncertain("Deleted placement is still visible") }
        guard let expected = journal.expectedGraph, sameBindings(current, expected.filter({ $0.id != id })) else {
            throw DuoExecutionFailure.drift("A survivor was reordered or changed during deletion")
        }
        journal.expectedGraph = current
        try verify(key)
        try proveCompatibility(current)
    }
    private func createPlacement(key: String, request: DuoAssetLibraryRequest, imageID: String) throws -> String {
        try guardOwnedGraph()
        guard let id = try mutate(key, request: request, reconcile: { [self] in
            let matches = try group().filter { $0.imageID == imageID }
            guard matches.count <= 1 else { throw DuoExecutionFailure.drift("Ambiguous created placement") }
            return (matches.count == 1, matches.first?.id)
        }, expectsID: "appAssetLibraryPlacements") else { throw DuoExecutionFailure.uncertain("No placement ID returned") }
        let current = try group()
        guard current.contains(where: { $0.id == id && $0.imageID == imageID }) else {
            throw DuoExecutionFailure.uncertain("Created placement has no exact readback")
        }
        guard let expected = journal.expectedGraph, sameBindings(current.filter({ $0.id != id }), expected.filter({ $0.id != id })) else {
            throw DuoExecutionFailure.drift("Existing placements were reordered during creation")
        }
        journal.expectedGraph = current
        try verify(key)
        try proveCompatibility(current)
        return id
    }
    private func order(_ ids: [String], key: String, baselineCount: Int?) throws {
        try guardOwnedGraph()
        let request = try baselineCount.map { try adapter.orderRestoredPlacements(ids, baselineCount: $0, localizationID: set.localizationID) }
            ?? adapter.orderPlacements(ids, localizationID: set.localizationID)
        _ = try mutate(key, request: request, reconcile: { [self] in ((try group()).map(\.id) == ids, nil) })
        let current = try group()
        guard current.map(\.id) == ids else { throw DuoExecutionFailure.uncertain("Whole-group ordering readback failed") }
        journal.expectedGraph = current
        try verify(key)
        try proveCompatibility(current)
    }

    private func ownedPlacementImages() throws -> [String: String] {
        var result: [String: String] = [:]
        for prefix in ["switch:\(journal.epoch):place:", "restore:\(journal.epoch):place:"] {
            let keys = Set(journal.entries.filter { $0.key.hasPrefix(prefix) }.map(\.key))
            for key in keys {
                guard let id = latest(key)?.resourceID, let position = Int(key.dropFirst(prefix.count)) else { continue }
                let upload = prefix.hasPrefix("switch") ? "desired:\(position)" : "restore:\(journal.epoch):\(position)"
                result[id] = try reservedID(upload)
            }
        }
        return result
    }
    private func reconcilePendingPlacementCreates() throws {
        let keys = Set(journal.entries.filter { $0.key.hasPrefix("switch:\(journal.epoch):place:") ||
            $0.key.hasPrefix("restore:\(journal.epoch):place:") }.map(\.key))
        for key in keys {
            guard let pending = latest(key), ["intent", "uncertain", "responseKnown"].contains(pending.status),
                  let position = Int(key.split(separator: ":").last!) else { continue }
            let upload = key.hasPrefix("switch") ? "desired:\(position)" : "restore:\(journal.epoch):\(position)"
            let imageID = try reservedID(upload), matches = try group().filter { $0.imageID == imageID }
            guard matches.count == 1, pending.resourceID == nil || pending.resourceID == matches[0].id else {
                throw DuoExecutionFailure.uncertain("Pending placement create has no unique exact image-ID/resource-ID readback")
            }
            let current = try group()
            guard let expected = journal.expectedGraph,
                  sameBindings(current.filter({ $0.id != matches[0].id }), expected.filter({ $0.id != matches[0].id })) else {
                throw DuoExecutionFailure.drift("Known placements reordered around an unresolved create")
            }
            journal.expectedGraph = current
            try entry(key, "verified", digest: pending.requestDigest, id: matches[0].id)
        }
    }
    private func guardOwnedGraph() throws {
        try service.verifyEditableTarget(set)
        let current = try group()
        let pendingDeletes = Set(journal.entries.filter {
            $0.key.hasPrefix("switch:\(journal.epoch):delete:") || $0.key.hasPrefix("restore:\(journal.epoch):remove:")
        }.map(\.key))
        for key in pendingDeletes {
            guard let pending = latest(key), ["intent", "uncertain", "responseKnown"].contains(pending.status),
                  let id = key.split(separator: ":").last.map(String.init) else { continue }
            guard !current.contains(where: { $0.id == id }) else {
                throw DuoExecutionFailure.uncertain("Pending deletion has no confirmed absent-resource readback")
            }
            guard let expected = journal.expectedGraph, sameBindings(current, expected.filter({ $0.id != id })) else {
                throw DuoExecutionFailure.drift("Known placements reordered around an unresolved deletion")
            }
            journal.expectedGraph = current
            try entry(key, "verified", digest: pending.requestDigest)
        }
        let owned = try ownedPlacementImages()
        let pendingOrder = ["switch:\(journal.epoch):order", "restore:\(journal.epoch):order"].contains { key in
            latest(key).map { ["intent", "uncertain", "responseKnown"].contains($0.status) } ?? false
        }
        guard let expectedGraph = journal.expectedGraph, sameBindings(current, expectedGraph) || pendingOrder else {
            throw DuoExecutionFailure.drift("The ordered group changed outside this journal")
        }
        let original = Dictionary(uniqueKeysWithValues: journal.activeBaseline.map { ($0.id, $0.imageID) })
        let removed = Set(journal.entries.filter { ($0.key.hasPrefix("switch:\(journal.epoch):delete:") ||
            $0.key.hasPrefix("restore:\(journal.epoch):remove:")) && $0.status == "verified" }.compactMap { $0.key.split(separator: ":").last.map(String.init) })
        for row in current {
            guard !removed.contains(row.id), (original[row.id] ?? owned[row.id]) == row.imageID else {
                throw DuoExecutionFailure.drift("Unowned or changed placement; no compensating write is permitted")
            }
        }
        for (id, _) in original.merging(owned, uniquingKeysWith: { first, _ in first }) {
            guard removed.contains(id) || current.contains(where: { $0.id == id }) else {
                throw DuoExecutionFailure.drift("A known placement vanished without this journal's verified deletion")
            }
        }
        try proveCompatibility(current)
    }

    private func rollback() throws {
        try reconcilePendingPlacementCreates()
        try guardOwnedGraph()
        guard let hash = journal.backupDigest, try digest(journal.backups) == hash else {
            throw DuoExecutionFailure.drift("Rollback backup is unsealed or changed")
        }
        for backup in journal.backups { _ = try validatedBytes(backup.file) }
        let orderKey = "restore:\(journal.epoch):order"
        if let previous = latest(orderKey), previous.status != "rejected" {
            let current = try group()
            let ids = try journal.activeBaseline.enumerated().map { index, old -> String in
                if current.contains(where: { $0.id == old.id && $0.imageID == old.imageID }) { return old.id }
                guard let id = latest("restore:\(journal.epoch):place:\(index + 1)")?.resourceID else {
                    throw DuoExecutionFailure.uncertain("Rollback order has incomplete restored placement identities")
                }
                return id
            }
            try order(ids, key: orderKey, baselineCount: journal.activeBaseline.count)
            try finishRollback(ids)
            return
        }
        let prefix = "switch:\(journal.epoch):place:"
        let created = Set(journal.entries.filter { $0.key.hasPrefix(prefix) }.compactMap { latest($0.key)?.resourceID })
        for id in created.sorted() { try remove(id, key: "restore:\(journal.epoch):remove:\(id)") }
        var restored: [String] = []
        for (index, old) in journal.activeBaseline.enumerated() {
            if (try group()).contains(where: { $0.id == old.id && $0.imageID == old.imageID }) { restored.append(old.id); continue }
            let backup = journal.backups[index].file
            let imageID = try stage(backup, key: "restore:\(journal.epoch):\(index + 1)")
            let request = try adapter.placeProcessedImage(processedImage(id: imageID, file: backup), expectedSpecID: backup.specID, localizationID: set.localizationID)
            restored.append(try createPlacement(key: "restore:\(journal.epoch):place:\(index + 1)", request: request, imageID: imageID))
        }
        if !restored.isEmpty { try order(restored, key: "restore:\(journal.epoch):order", baselineCount: journal.activeBaseline.count) }
        try finishRollback(restored)
    }

    private func finishRollback(_ restored: [String]) throws {
        let current = try group()
        guard current.map(\.id) == restored else { throw DuoExecutionFailure.uncertain("Original content order was not restored") }
        var identities: [String: JSONValue] = [:]
        for (index, row) in current.enumerated() {
            let old = journal.activeBaseline[index]
            if row.id == old.id {
                let raw = try service.image(id: row.imageID)
                guard row.imageID == old.imageID, raw["id"] == .string(row.imageID),
                      try imageIdentity(raw) == journal.activeImageIdentities[row.imageID] else {
                    throw DuoExecutionFailure.drift("Surviving original image identity changed during rollback")
                }
                identities[row.imageID] = try imageIdentity(raw)
            } else {
                guard latest("restore:\(journal.epoch):place:\(index + 1)")?.resourceID == row.id,
                      try reservedID("restore:\(journal.epoch):\(index + 1)") == row.imageID else {
                    throw DuoExecutionFailure.drift("Restored image/placement binding changed")
                }
                let raw = try processedImage(id: row.imageID, file: journal.backups[index].file)
                identities[row.imageID] = try imageIdentity(raw)
            }
        }
        try proveCompatibility(current)
        journal.activeBaseline = current; journal.activeImageIdentities = identities
        journal.activeCompatibility = journal.compatibilityCheckpoint
        journal.phase = "rolledBack"; try save()
    }

    var provenLegacyView: DuoLegacyView? { journal.compatibilityCheckpoint?.legacy }

    private func fileContent(_ image: DuoPublishImage, row: DuoRemotePlacement) throws -> DuoExpectedContent {
        let bytes = try validatedBytes(image)
        let pixelSHA: String
        if let existing = localPixelCache[image.sha256] { pixelSHA = existing }
        else {
            pixelSHA = try ImageValidation.pixelSHA256(bytes, context: "owned Duo upload content")
            localPixelCache[image.sha256] = pixelSHA
        }
        let previous = journal.compatibilityCheckpoint
        let index = previous?.placements.firstIndex { $0.id == row.id && $0.imageID == row.imageID }
        return DuoExpectedContent(fileName: image.fileName, byteCount: image.byteCount,
            width: image.pixelWidth, height: image.pixelHeight, pixels: pixelSHA, checksum: FileIO.md5(bytes),
            pinnedAsset: index.flatMap { previous?.content[$0].asset },
            pinnedLegacyID: index.flatMap { previous?.legacy.images[$0].id })
    }

    private func expectedContent(_ row: DuoRemotePlacement) throws -> DuoExpectedContent {
        if let active = journal.activeCompatibility,
           let index = active.placements.firstIndex(where: { $0.id == row.id && $0.imageID == row.imageID }) {
            let proof = active.content[index], legacy = active.legacy.images[index]
            return DuoExpectedContent(fileName: proof.fileName, byteCount: proof.byteCount,
                width: proof.asset.width, height: proof.asset.height, pixels: proof.pixelSHA256,
                checksum: legacy.checksum, pinnedAsset: proof.asset, pinnedLegacyID: legacy.id)
        }
        for image in set.images where latest("switch:\(journal.epoch):place:\(image.position)")?.resourceID == row.id {
            guard try reservedID("desired:\(image.position)") == row.imageID else {
                throw DuoExecutionFailure.drift("Duo desired placement points at a different image")
            }
            return try fileContent(image, row: row)
        }
        for backup in journal.backups where latest("restore:\(journal.epoch):place:\(backup.file.position)")?.resourceID == row.id {
            guard try reservedID("restore:\(journal.epoch):\(backup.file.position)") == row.imageID else {
                throw DuoExecutionFailure.drift("Duo restored placement points at a different image")
            }
            return try fileContent(backup.file, row: row)
        }
        throw DuoExecutionFailure.drift("Duo compatibility content has no reviewed or journal-owned origin")
    }

    private func proveCompatibility(_ graph: [DuoRemotePlacement]) throws {
        guard let compatibilityVerifier else { return }
        let expected = try graph.map(expectedContent)
        let checkpoint = try compatibilityVerifier.prove(graph: graph, expected: expected,
            previous: journal.compatibilityCheckpoint)
        if checkpoint != journal.compatibilityCheckpoint {
            journal.compatibilityCheckpoint = checkpoint
            try save()
        }
    }
}
