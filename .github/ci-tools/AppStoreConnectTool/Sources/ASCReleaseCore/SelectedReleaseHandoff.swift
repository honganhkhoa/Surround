import Foundation

public struct HandoffFileBinding: Codable, Equatable, Sendable {
    public let path: String
    public let sha256: String

    public init(path: String, sha256: String) { self.path = path; self.sha256 = sha256 }

    func bytes() throws -> Data {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard path == url.path, url.resolvingSymlinksInPath() == url,
              sha256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
            throw ReleaseToolError.validation("Unsafe handoff binding")
        }
        let data = try Data(contentsOf: url)
        guard FileIO.sha256(data) == sha256 else {
            throw ReleaseToolError.validation("Handoff input changed: \(path)")
        }
        return data
    }
}

/// A separate admission record; immutable capture qualification is never promoted.
/// An executable handoff requires actual editable target IDs and reviewed baselines.
public struct SelectedReleaseHandoff: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let mode: String
    public let selectedImport: HandoffFileBinding
    public let selectionSHA256: String
    public let evidenceAcceptance: HandoffFileBinding
    public let integrityVerification: HandoffFileBinding
    public let duoInspection: HandoffFileBinding
    public let qualificationLimits: JSONValue
    public let sets: [DuoPublishSet]

    public static let mode = "selected-lineup"

    public static func build(importFile: HandoffFileBinding, selectionSHA256: String,
                             acceptance: HandoffFileBinding, integrityVerification: HandoffFileBinding,
                             inspection: HandoffFileBinding,
                             release: NormalizedRelease, snapshot: RemoteSnapshot) throws -> Self {
        let envelope = try JSONDecoder().decode(JSONValue.self, from: importFile.bytes())
        let report = try JSONDecoder().decode(JSONValue.self, from: integrityVerification.bytes())
        let pinnedImport = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(importFile))
        guard report["mode"] == .string("selected-import-integrity-verification"),
              report["selectedImport"] == pinnedImport, report["selectionSHA256"] == .string(selectionSHA256),
              report["result"]?["integrity"] == .string("passed"),
              report["result"]?["images"]?.intValue == envelope["cards"]?.arrayValue?.count,
              report["result"]?["sourceBindings"]?.intValue == envelope["sourceBindings"]?.arrayValue?.count,
              report["result"]?["publishable"] == .bool(false), let verifier = report["verifier"] else {
            throw ReleaseToolError.validation("Full semantic selected-import verification receipt is missing or stale")
        }
        let verifierBinding = try JSONDecoder().decode(HandoffFileBinding.self, from: JSONEncoder().encode(verifier))
        _ = try verifierBinding.bytes()
        try verifyEvidence(envelope, root: URL(fileURLWithPath: importFile.path).deletingLastPathComponent(),
                           selectionSHA256: selectionSHA256, acceptance: acceptance)
        let observedVersions = [snapshot.sourceVersion, snapshot.targetVersion].compactMap { $0 }
        guard !observedVersions.contains(where: { version in
            version.localizations.contains { $0.screenshotSets.contains { $0.displayType == "APP_IPHONE_DUO" } }
        }) else {
            throw ReleaseToolError.validation("Selected mixed-transport publishing has an unqualified legacy Duo view (APP_IPHONE_DUO); keep both views in preflight and resolve their compatibility policy before execution")
        }
        let inspected = try JSONDecoder().decode(JSONValue.self, from: inspection.bytes())
        guard let target = snapshot.targetVersion,
              target.state == "PREPARE_FOR_SUBMISSION",
              inspected["targetVersion"]?["id"] == .string(target.id),
              inspected["requestedVersion"] == .string(release.version),
              inspected["appId"] == .string(snapshot.appId),
              inspected["bundleId"] == .string(release.bundleId),
              let library = inspected["assetLibraryId"]?.stringValue,
              let catalog = inspected["catalogResources"]?.arrayValue else {
            throw ReleaseToolError.validation("Duo handoff requires an existing editable target and its actual localization/baseline IDs; no version was created")
        }
        let plan = try DuoAssetLibraryPlanBuilder.build(inspectionURL: URL(fileURLWithPath: inspection.path),
            expectedInspectionSHA256: inspection.sha256, importURL: URL(fileURLWithPath: importFile.path),
            expectedImportSHA256: importFile.sha256, expectedSelectionSHA256: selectionSHA256)
        let root = URL(fileURLWithPath: importFile.path).deletingLastPathComponent()
        let planned = plan["localizations"]?.arrayValue ?? []
        guard planned.count == release.localizations.count,
              Set(planned.compactMap { $0["appStoreLocale"]?.stringValue }) == Set(release.localizations.map(\.appStoreLocale)) else {
            throw ReleaseToolError.validation("Duo handoff locale set differs from release")
        }
        let sets = try planned.map { row -> DuoPublishSet in
            guard let locale = row["appStoreLocale"]?.stringValue,
                  let localizationID = row["appStoreVersionLocalizationId"]?.stringValue,
                  target.localizations.contains(where: { $0.locale == locale && $0.id == localizationID }),
                  let remote = inspected["localizations"]?.arrayValue?.first(where: { $0["locale"] == .string(locale) }),
                  let placements = remote["orderedPlacements"]?.arrayValue else {
                throw ReleaseToolError.validation("Duo target localization has no exact reviewed baseline")
            }
            let images = try (row["images"]?.arrayValue ?? []).map { card -> DuoPublishImage in
                guard let position = card["position"]?.intValue,
                      let path = card["asset"]?["importedPath"]?.stringValue,
                      let sha = card["asset"]?["sha256"]?.stringValue,
                      let size = card["asset"]?["dimensions"]?.arrayValue,
                      let width = size.first?.intValue, let height = size.last?.intValue,
                      let spec = card["catalogImageSpecification"]?["specId"]?.stringValue,
                      let origin = card["origin"] else { throw ReleaseToolError.validation("Incomplete Duo handoff image") }
                let url = root.appendingPathComponent(path).standardizedFileURL
                return DuoPublishImage(position: position, path: url.path, fileName: url.lastPathComponent,
                    byteCount: try Data(contentsOf: url).count, sha256: sha, pixelWidth: width,
                    pixelHeight: height, specID: spec, origin: origin)
            }
            return DuoPublishSet(version: release.version, bundleID: release.bundleId, appID: snapshot.appId,
                assetLibraryID: library, versionID: target.id, localizationID: localizationID, locale: locale,
                sourceManifestSHA256: importFile.sha256, catalog: catalog, images: images,
                reviewedBaseline: try placements.map(DuoRemotePlacement.parse))
        }
        return Self(schemaVersion: 1, mode: "selected-release-handoff", selectedImport: importFile,
            selectionSHA256: selectionSHA256, evidenceAcceptance: acceptance,
            integrityVerification: integrityVerification, duoInspection: inspection,
            qualificationLimits: envelope["qualificationLimits"]!, sets: sets)
    }

    public static func load(manifest: PublishManifest) throws -> Self? {
        let mode = manifest.captureMetadata["mode"]?.stringValue
        guard mode == Self.mode else {
            guard mode != "selected-lineup-draft", manifest.captureMetadata["selectedHandoff"] == nil else {
                throw ReleaseToolError.validation("Review-only selected lineup cannot be published")
            }
            return nil
        }
        guard let binding = manifest.captureMetadata["selectedHandoff"] else {
            throw ReleaseToolError.validation("Selected lineup requires an admitted Duo handoff")
        }
        let descriptor = try JSONDecoder().decode(HandoffFileBinding.self, from: JSONEncoder().encode(binding))
        let handoff = try JSONDecoder().decode(Self.self, from: descriptor.bytes())
        guard handoff.schemaVersion == 1, handoff.mode == "selected-release-handoff" else {
            throw ReleaseToolError.validation("Unsupported selected handoff")
        }
        let rebuilt = try build(importFile: handoff.selectedImport, selectionSHA256: handoff.selectionSHA256,
            acceptance: handoff.evidenceAcceptance, integrityVerification: handoff.integrityVerification,
            inspection: handoff.duoInspection,
            release: manifest.release, snapshot: manifest.remoteSnapshot)
        guard rebuilt == handoff else { throw ReleaseToolError.validation("Selected handoff differs from its pinned inputs") }
        let envelope = try JSONDecoder().decode(JSONValue.self, from: handoff.selectedImport.bytes())
        let cards = envelope["cards"]?.arrayValue ?? []
        let root = URL(fileURLWithPath: handoff.selectedImport.path).deletingLastPathComponent()
        var count = 0
        for locale in manifest.localizations {
            let families = ["iphone-6.9": "APP_IPHONE_67", "ipad-13": "APP_IPAD_PRO_3GEN_129"]
            guard locale.screenshotSets.count == families.count,
                  Set(locale.screenshotSets.map(\.family)) == Set(families.keys) else {
                throw ReleaseToolError.validation("Selected locale requires its two exact legacy families")
            }
            for set in locale.screenshotSets {
                guard families[set.family] == set.displayType,
                      set.screenshots.map(\.order) == Array(1...10) else {
                    throw ReleaseToolError.validation("Selected family requires its exact display type and ten ordered slots")
                }
                for image in set.screenshots {
                    let matches = cards.filter { $0["appStoreLocale"] == .string(locale.appStoreLocale) &&
                        $0["family"] == .string(set.family) && $0["position"] == .number(Double(image.order)) }
                    guard matches.count == 1, let asset = matches[0]["assets"]?["screenshots"],
                          let path = asset["importedPath"]?.stringValue,
                          root.appendingPathComponent(path).standardizedFileURL.path == image.path,
                          asset["sha256"] == .string(image.sha256),
                          asset["dimensions"] == .array([.number(Double(image.pixelWidth ?? set.pixelWidth)),
                                                         .number(Double(image.pixelHeight ?? set.pixelHeight))]) else {
                        throw ReleaseToolError.validation("Legacy screenshot differs from selected component origin")
                    }
                    count += 1
                }
            }
        }
        guard count + handoff.sets.reduce(0, { $0 + $1.images.count }) == cards.count,
              count == manifest.release.localizations.count * 20 else {
            throw ReleaseToolError.validation("Selected handoff must account for all 30 slots per locale")
        }
        return handoff
    }

    public static func verifyEvidence(_ envelope: JSONValue, root: URL, selectionSHA256: String,
                               acceptance: HandoffFileBinding) throws {
        guard envelope["mode"] == .string("selected-import"), envelope["publishable"] == .bool(false),
              envelope["selectionSHA256"] == .string(selectionSHA256),
              let limits = envelope["qualificationLimits"],
              limits["selectedXCTestDuoQualificationClaimed"] == .bool(false),
              let cards = envelope["cards"]?.arrayValue, !cards.isEmpty else {
            throw ReleaseToolError.validation("Selected admission must retain historical qualification limits")
        }
        let receipt = try JSONDecoder().decode(JSONValue.self, from: acceptance.bytes())
        guard receipt["status"] == .string("owner-accepted-historical-widget-evidence-limits"),
              receipt["selectionSHA256"] == .string(selectionSHA256), receipt["qualificationLimits"] == limits,
              receipt["historicalTechnicalProofEstablished"] == .bool(false),
              receipt["publishingAuthorization"] == .bool(false), receipt["remoteMutationAuthorization"] == .bool(false),
              receipt["approvesUnrelatedVisualDifferences"] == .bool(false),
              !(receipt["question"]?["text"]?.stringValue ?? "").isEmpty,
              !(receipt["response"]?["text"]?.stringValue ?? "").isEmpty,
              let widgets = receipt["selectedWidgetEntries"]?.arrayValue else {
            throw ReleaseToolError.validation("Exact owner acceptance of the selected historical widget limits is missing")
        }
        let selectedWidgets = cards.filter { $0["position"] == .number($0["family"] == .string("iphone-duo-profile") ? 10 : 6) }
        guard widgets.count == selectedWidgets.count else { throw ReleaseToolError.validation("Widget acceptance scope is incomplete") }
        for card in selectedWidgets {
            guard widgets.filter({ $0["screenshotConfiguration"] == card["screenshotConfiguration"] &&
                $0["family"] == card["family"] && $0["position"] == card["position"] &&
                $0["sha256"] == card["assets"]?["screenshots"]?["sha256"] }).count == 1 else {
                throw ReleaseToolError.validation("Widget acceptance does not match the selected bytes")
            }
        }
        guard let originalSelection = envelope["selectionOriginalPath"]?.stringValue,
              let rows = envelope["sourceBindings"]?.arrayValue else {
            throw ReleaseToolError.validation("Selected import has no retained canonical selection")
        }
        let selectionBindings = rows.filter { $0["originalPath"] == .string(originalSelection) &&
            $0["sha256"] == .string(selectionSHA256) }
        guard selectionBindings.count == 1, let retained = selectionBindings[0]["retainedPath"]?.stringValue else {
            throw ReleaseToolError.validation("Canonical selection binding is missing or ambiguous")
        }
        let selectionURL = root.appendingPathComponent(retained).standardizedFileURL
        guard !retained.hasPrefix("/"), selectionURL.path.hasPrefix(root.path + "/") else {
            throw ReleaseToolError.validation("Retained selection escapes the import")
        }
        let selected = try JSONDecoder().decode(JSONValue.self,
            from: HandoffFileBinding(path: selectionURL.path, sha256: selectionSHA256).bytes())
        guard let selectedCards = selected["images"]?.arrayValue, selectedCards.count == cards.count else {
            throw ReleaseToolError.validation("Selected card matrix differs from canonical selection")
        }
        let releaseRoot = URL(fileURLWithPath: originalSelection).deletingLastPathComponent().deletingLastPathComponent()
        for card in cards {
            let matches = selectedCards.filter { $0["appStoreLocale"] == card["appStoreLocale"] &&
                $0["screenshotConfiguration"] == card["screenshotConfiguration"] &&
                $0["family"] == card["family"] && $0["position"] == card["position"] }
            guard matches.count == 1 else { throw ReleaseToolError.validation("Selected card is missing, duplicated or relabeled") }
            guard let assets = card["assets"]?.objectValue else { throw ReleaseToolError.validation("Missing selected assets") }
            guard Set(assets.keys) == Set(["raw", "source-screenshots", "screenshots"]) else {
                throw ReleaseToolError.validation("Selected card must preserve raw, source and framed assets")
            }
            for (role, asset) in assets {
                let canonicalAsset = matches[0]["assets"]?[role]
                guard let relative = asset["importedPath"]?.stringValue,
                      let sha = asset["sha256"]?.stringValue,
                      let originalPath = canonicalAsset?["path"]?.stringValue,
                      canonicalAsset?["sha256"] == asset["sha256"],
                      canonicalAsset?["dimensions"] == asset["dimensions"],
                      asset["originalPath"] == .string(releaseRoot.appendingPathComponent(originalPath).standardizedFileURL.path),
                      matches[0]["outputFile"] == .string(URL(fileURLWithPath: relative).lastPathComponent) else {
                    throw ReleaseToolError.validation("Selected asset differs from its canonical slot, bytes, dimensions or origin path")
                }
                let url = root.appendingPathComponent(relative).standardizedFileURL
                guard !relative.hasPrefix("/"), url.path.hasPrefix(root.path + "/") else {
                    throw ReleaseToolError.validation("Selected asset escapes its import")
                }
                _ = try HandoffFileBinding(path: url.path, sha256: sha).bytes()
            }
        }
    }
}

final class DuoReleaseCoordinator {
    let handoff: SelectedReleaseHandoff
    let service: DuoPublishingService
    let journalDirectory: URL

    init(handoff: SelectedReleaseHandoff, service: DuoPublishingService, journalDirectory: URL) {
        self.handoff = handoff; self.service = service; self.journalDirectory = journalDirectory
    }

    private func journal(_ set: DuoPublishSet) -> URL {
        journalDirectory.appendingPathComponent("duo-\(set.locale)-journal.json")
    }

    func preflight() throws {
        for set in handoff.sets {
            _ = try duoIdentifier(set.locale)
            try service.verifyEditableTarget(set)
            if FileManager.default.fileExists(atPath: journal(set).path) {
                let executor = try DuoPublishingExecutor(set: set, journalURL: journal(set), service: service)
                try executor.preflight()
            } else {
                let adapter = try DuoAssetLibraryAdapter(catalog: set.catalog, assetLibraryID: set.assetLibraryID)
                guard try service.placements(localizationID: set.localizationID,
                    group: adapter.routing["placementGroup"]!.stringValue!) == set.reviewedBaseline else {
                    throw ReleaseToolError.remoteDrift("Duo placements changed since review for \(set.locale)")
                }
            }
        }
    }

    func publish() throws {
        for set in handoff.sets {
            let executor = try DuoPublishingExecutor(set: set, journalURL: journal(set), service: service)
            try executor.publish(confirmedVersion: set.version, confirmedSetDigest: set.digest())
        }
    }

    /// Resume only an existing rollback, then stop at its verified checkpoint.
    /// The caller invokes this before touching any legacy screenshot or metadata.
    func recoverPendingRollback() throws {
        for set in handoff.sets where FileManager.default.fileExists(atPath: journal(set).path) {
            let state = try ManifestBuilder.decode(DuoExecutionJournal.self, at: journal(set))
            guard state.phase == "rollingBack" else { continue }
            let executor = try DuoPublishingExecutor(set: set, journalURL: journal(set), service: service)
            try executor.publish(confirmedVersion: set.version, confirmedSetDigest: set.digest())
        }
    }

    func verifyCompleted() throws {
        for set in handoff.sets {
            let completed = try ManifestBuilder.decode(DuoExecutionJournal.self, at: journal(set))
            guard completed.phase == "complete" else {
                throw ReleaseToolError.validation("Duo execution has no completed checkpoint")
            }
            // The executor's completed path performs readback only, including image processing/specification.
            let executor = try DuoPublishingExecutor(set: set, journalURL: journal(set), service: service)
            try executor.publish(confirmedVersion: set.version, confirmedSetDigest: set.digest())
        }
    }
}
