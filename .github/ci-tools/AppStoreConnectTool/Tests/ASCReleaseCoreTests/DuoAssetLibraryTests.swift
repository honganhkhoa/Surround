import CryptoKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ASCReleaseCore

final class DuoAssetLibraryTests: XCTestCase {
    func testRuntimeOrdinaryGroupUsesOneSharedLimitAcrossDisplays() throws {
        let route = try DuoAssetLibraryRouting.resolve(catalog: catalog())
        XCTAssertEqual(route["placementGroup"], .string("runtime-duo-group"))
        XCTAssertEqual(route["maxCountPerGroupAndLocalization"], .number(10))
        XCTAssertEqual(route["imageSpecs"]?.arrayValue?.count, 4)
        XCTAssertEqual(route["legacyScreenshotDisplayType"], .null)
        XCTAssertEqual(route["uploadAcceptanceVerified"], .bool(false))
        XCTAssertEqual(route["publisherMutationAdapterAvailable"], .bool(false))
    }

    func testMissingAmbiguousOrIMessageOnlyGroupFailsClosed() throws {
        for groups: [[String: Any]] in [[], [group(), group()], [group(platform: "IMESSAGE_APP_STORE")]] {
            XCTAssertThrowsError(try DuoAssetLibraryRouting.resolve(catalog: catalog(groups: groups)))
        }
    }

    func testMissingSpecOrAlphaAllowanceFailsClosed() throws {
        XCTAssertThrowsError(try DuoAssetLibraryRouting.resolve(catalog: catalog(alpha: true)))
        XCTAssertThrowsError(try DuoAssetLibraryRouting.resolve(catalog: catalog(includeInner: false)))
    }

    func testMalformedMappedSpecCannotBeSilentlyDiscarded() throws {
        XCTAssertThrowsError(try DuoAssetLibraryRouting.resolve(catalog: catalog(malformedSpec: true)))
    }

    func testReturnedResourceIDsCannotBeDotPathSegments() throws {
        for appID in [".", ".."] {
            let transport = ReadOnlyDuoTransport(catalog: try catalog(), appID: appID)
            let credentials = ASCCredentials(keyId: "test", issuerId: "test",
                                             privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation)
            let client = ASCAPIClient(credentials: credentials, transport: transport, maxRetries: 0)
            XCTAssertThrowsError(try DuoAssetLibraryInspector(client: client).capture(bundleId: "com.example.App", version: "3.0"))
            XCTAssertEqual(transport.methods, ["GET", "GET"])
        }
    }

    func testInspectorUsesOnlyGETAndReturnedPerAppPlacementIDs() throws {
        let transport = ReadOnlyDuoTransport(catalog: try catalog())
        let credentials = ASCCredentials(keyId: "test", issuerId: "test",
                                         privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation)
        let client = ASCAPIClient(credentials: credentials, transport: transport, maxRetries: 0)
        let result = try DuoAssetLibraryInspector(client: client).capture(bundleId: "com.example.App", version: "3.0")
        XCTAssertEqual(result["assetLibraryId"], .string("library"))
        XCTAssertEqual(result["perAppAssetLibraryReadable"], .bool(true))
        XCTAssertEqual(result["uploadAcceptanceVerified"], .bool(false))
        XCTAssertEqual(result["localizations"]?.arrayValue?.first?["orderedPlacements"]?.arrayValue?.first?["id"], .string("placement"))
        XCTAssertEqual(transport.methods, Array(repeating: "GET", count: 6))
        XCTAssertEqual(transport.lastQuery?.first { $0.name == "filter[placementGroup]" }?.value, "runtime-duo-group")
        XCTAssertEqual(transport.lastQuery?.first { $0.name == "sort" }?.value, "placementGroupPosition")
    }

    func testOfflineAdapterUsesAssetLibraryBodiesWithoutLegacyFields() throws {
        let adapter = try DuoAssetLibraryAdapter(catalog: catalog(), assetLibraryID: "library")
        let reserve = try adapter.reserveImage(fileName: "05-quick.png", fileSize: 123)
        XCTAssertEqual(reserve.method, "POST")
        XCTAssertEqual(reserve.path, "/v1/appAssetLibraryImages")
        XCTAssertEqual(reserve.body["data"]?["attributes"]?.objectValue?.keys.sorted(), ["category", "fileName", "fileSize"])
        XCTAssertEqual(reserve.body["data"]?["relationships"]?["assetLibrary"]?["data"]?["id"], .string("library"))
        let commit = try adapter.commitImage(imageID: "returned-image")
        XCTAssertEqual(commit.method, "PATCH")
        XCTAssertEqual(commit.body["data"]?["attributes"], .object(["uploaded": .bool(true)]))
        let placement = try adapter.placeProcessedImage(processedImage(), expectedSpecID: "spec-0", localizationID: "target-locale")
        XCTAssertEqual(placement.path, "/v1/appAssetLibraryPlacements")
        XCTAssertEqual(placement.body["data"]?["attributes"], .object([
            "placementType": .string("APP_SCREENSHOT"), "placementGroup": .string("runtime-duo-group")]))
        XCTAssertEqual(placement.body["data"]?["relationships"]?.objectValue?.keys.sorted(), ["appStoreVersionLocalization", "image"])
    }

    func testPlacementRequiresProcessedImageAndMatchedSpecification() throws {
        let adapter = try DuoAssetLibraryAdapter(catalog: catalog(), assetLibraryID: "library")
        for state in ["AWAITING_UPLOAD", "UPLOAD_COMPLETE", "FAILED", "COMPLETE", "ACTIVE"] {
            XCTAssertThrowsError(try adapter.placeProcessedImage(processedImage(state: state), expectedSpecID: "spec-0", localizationID: "loc"))
        }
        XCTAssertThrowsError(try adapter.placeProcessedImage(processedImage(), expectedSpecID: "spec-1", localizationID: "loc"))
        XCTAssertThrowsError(try adapter.placeProcessedImage(processedImage(), expectedSpecID: "unknown", localizationID: "loc"))
    }

    func testOrderingHasTenUniqueIDsInArrayOrderAndNoPositionAttribute() throws {
        let adapter = try DuoAssetLibraryAdapter(catalog: catalog(), assetLibraryID: "library")
        let ids = (1...10).map { "placement-\($0)" }.reversed().map { $0 }
        let request = try adapter.orderPlacements(ids, localizationID: "target-locale")
        XCTAssertEqual(request.path, "/v1/appAssetLibraryPlacementOrderingRequests")
        XCTAssertEqual(request.body["data"]?["attributes"], .object(["placementGroup": .string("runtime-duo-group")]))
        XCTAssertEqual(request.body["data"]?["relationships"]?["orderedPlacements"]?["data"]?.arrayValue?.compactMap { $0["id"]?.stringValue }, ids)
        for invalid in [Array(ids.prefix(9)), ids + ["extra"], Array(repeating: "same", count: 10)] {
            XCTAssertThrowsError(try adapter.orderPlacements(invalid, localizationID: "loc"))
        }
    }

    func testOfflineAdapterRejectsUnsafeIDsAndReservationInputs() throws {
        let adapter = try DuoAssetLibraryAdapter(catalog: catalog(), assetLibraryID: "library")
        for id in ["", ".", "..", "a/b", "a?query"] {
            XCTAssertThrowsError(try adapter.commitImage(imageID: id))
        }
        for name in ["../x.png", "x.jpg", "/x.png", "x.png?secret"] {
            XCTAssertThrowsError(try adapter.reserveImage(fileName: name, fileSize: 1))
        }
        XCTAssertThrowsError(try adapter.reserveImage(fileName: "x.png", fileSize: 0))
    }

    func testOfflinePlanPreservesReviewedOriginsAndUnresolvedTargetIDs() throws {
        let fixture = try planFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let plan = try fixture.build()
        XCTAssertEqual(plan["publishable"], .bool(false))
        XCTAssertEqual(plan["networkExecutorIncluded"], .bool(false))
        XCTAssertEqual(plan["targetVersion"], .null)
        let locale = try XCTUnwrap(plan["localizations"]?.arrayValue?.first)
        XCTAssertEqual(locale["appStoreVersionLocalizationId"], .null)
        let images = try XCTUnwrap(locale["images"]?.arrayValue)
        XCTAssertEqual(images.count, 10)
        XCTAssertEqual(images.map { $0["position"]?.intValue }, Array(1...10).map(Optional.some))
        XCTAssertEqual(images[0]["origin"], .object(["kind": .string("fixture-original-origin"), "launch": .null]))
        XCTAssertEqual(images[0]["imageId"], .null)
        XCTAssertEqual(images[0]["placementId"], .null)
        XCTAssertEqual(Set(images.compactMap { $0["reservationDependencyKey"]?.stringValue }).count, 10)
        XCTAssertEqual(plan["qualificationLimits"], .object(["widgetUnresolved": .array([.string("AX_READY_NOT_OBSERVED")])]))
    }

    func testOfflinePlanRejectsChangedInputsWrongAppAndCatalogFileConstraints() throws {
        let fixture = try planFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        XCTAssertThrowsError(try DuoAssetLibraryPlanBuilder.build(inspectionURL: fixture.inspection, expectedInspectionSHA256: fixture.inspectionSHA, importURL: fixture.importURL,
            expectedImportSHA256: String(repeating: "0", count: 64), expectedSelectionSHA256: fixture.selectionSHA))
        var inspection = try FileIO.readJSON(at: fixture.inspection).objectValue!
        let original = inspection
        inspection["bundleId"] = .string("another.app")
        try FileIO.writeJSONValue(.object(inspection), to: fixture.inspection)
        XCTAssertThrowsError(try fixture.build(revisedInspectionSHA256: FileIO.sha256(try Data(contentsOf: fixture.inspection))))
        inspection = original
        var catalog = inspection["catalogResources"]!.arrayValue!
        var row = catalog[0].objectValue!, attrs = row["attributes"]!.objectValue!
        var specs = attrs["imageSpecs"]!.arrayValue!
        for index in specs.indices {
            var spec = specs[index].objectValue!
            spec["maxFileSize"] = .number(1)
            specs[index] = .object(spec)
        }
        attrs["imageSpecs"] = .array(specs); row["attributes"] = .object(attrs); catalog[0] = .object(row)
        inspection["catalogResources"] = .array(catalog)
        try FileIO.writeJSONValue(.object(inspection), to: fixture.inspection)
        XCTAssertThrowsError(try fixture.build(revisedInspectionSHA256: FileIO.sha256(try Data(contentsOf: fixture.inspection))))
        try FileIO.writeJSONValue(.object(original), to: fixture.inspection)
        try Data("tampered retained evidence".utf8).write(to: fixture.directory.appendingPathComponent("import/config.json"))
        XCTAssertThrowsError(try fixture.build())
    }

    func testOfflinePlanPinsInspectionAndRejectsStaleTargetIDs() throws {
        let fixture = try planFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var inspection = try FileIO.readJSON(at: fixture.inspection).objectValue!
        inspection["localizations"] = .array([.object(["locale": .string("en-US"), "localizationId": .string("old-2.4-locale")])])
        try FileIO.writeJSONValue(.object(inspection), to: fixture.inspection)
        XCTAssertThrowsError(try fixture.build()) { error in
            XCTAssertTrue(error.localizedDescription.contains("Inspection hash differs"))
        }
        XCTAssertThrowsError(try fixture.build(revisedInspectionSHA256: FileIO.sha256(try Data(contentsOf: fixture.inspection)))) { error in
            XCTAssertTrue(error.localizedDescription.contains("Absent target"))
        }
        inspection["localizations"] = .array([])
        for (version, platform) in [("2.4", "IOS"), ("3.0", "MAC_OS")] {
            inspection["targetVersion"] = .object(["id": .string("target"), "attributes": .object([
                "appVersionState": .string("PREPARE_FOR_SUBMISSION"), "versionString": .string(version), "platform": .string(platform)])])
            try FileIO.writeJSONValue(.object(inspection), to: fixture.inspection)
            XCTAssertThrowsError(try fixture.build(revisedInspectionSHA256: FileIO.sha256(try Data(contentsOf: fixture.inspection))))
        }
    }

    func testSelectedAdmissionPinsOwnerLimitsAndActualTargetBeforeBuildingExecutableHandoff() throws {
        let fixture = try planFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let root = fixture.importURL.deletingLastPathComponent()
        var envelope = try FileIO.readJSON(at: fixture.importURL).objectValue!
        let limits: JSONValue = .object(["selectedXCTestDuoQualificationClaimed": .bool(false),
            "widgetUnresolved": .array([.string("SAME_RENDER_DISPLAY_BINDING_UNRESOLVED")])])
        var selected = try FileIO.readJSON(at: root.appendingPathComponent("selection.json")).objectValue!
        selected["qualificationLimits"] = limits
        var completeCards = envelope["cards"]!.arrayValue!
        var selectedCards = selected["images"]!.arrayValue!
        let originalRoot = URL(fileURLWithPath: envelope["selectionOriginalPath"]!.stringValue!).deletingLastPathComponent().deletingLastPathComponent()
        for i in completeCards.indices {
            var card = completeCards[i].objectValue!, source = selectedCards[i].objectValue!
            let template = card["assets"]!["screenshots"]!.objectValue!
            var assets: [String: JSONValue] = [:], originals: [String: JSONValue] = [:]
            for role in ["raw", "source-screenshots", "screenshots"] {
                let relative = role + "/en-US/" + card["family"]!.stringValue! + "/" + String(card["position"]!.intValue!) + ".png"
                let original = "artifacts/fixture/" + relative
                var asset = template
                asset["importedPath"] = .string(relative)
                asset["originalPath"] = .string(originalRoot.appendingPathComponent(original).path)
                assets[role] = .object(asset)
                asset["path"] = .string(original)
                originals[role] = .object(asset)
            }
            card["assets"] = .object(assets); source["assets"] = .object(originals)
            completeCards[i] = .object(card); selectedCards[i] = .object(source)
        }
        envelope["cards"] = .array(completeCards); selected["images"] = .array(selectedCards)
        try FileIO.writeJSONValue(.object(selected), to: root.appendingPathComponent("selection.json"))
        let selectionBytes = try Data(contentsOf: root.appendingPathComponent("selection.json"))
        let selectionSHA = FileIO.sha256(selectionBytes)
        var bindings = envelope["sourceBindings"]!.arrayValue!
        var binding = bindings[0].objectValue!
        binding["sha256"] = .string(selectionSHA); binding["bytes"] = .number(Double(selectionBytes.count))
        bindings[0] = .object(binding); envelope["sourceBindings"] = .array(bindings)
        envelope["qualificationLimits"] = limits; envelope["selectionSHA256"] = .string(selectionSHA)
        let cards = envelope["cards"]!.arrayValue!
        let png = try Data(contentsOf: root.appendingPathComponent("screenshots/en-US/iphone-duo-profile/1.png"))
        for card in cards {
            for asset in card["assets"]!.objectValue!.values {
                try FileIO.write(data: png, to: root.appendingPathComponent(asset["importedPath"]!.stringValue!))
            }
        }
        try FileIO.writeJSONValue(.object(envelope), to: fixture.importURL)
        let verifierURL = fixture.directory.appendingPathComponent("synthetic-verifier.py")
        try Data("Synthetic successful semantic verifier fixture".utf8).write(to: verifierURL)
        let integrityURL = fixture.directory.appendingPathComponent("integrity.json")
        try FileIO.writeJSONValue(.object(["mode": .string("selected-import-integrity-verification"),
            "selectedImport": .object(["path": .string(fixture.importURL.path),
                "sha256": .string(FileIO.sha256(try Data(contentsOf: fixture.importURL)))]),
            "selectionSHA256": .string(selectionSHA),
            "verifier": .object(["path": .string(verifierURL.path), "sha256": .string(FileIO.sha256(try Data(contentsOf: verifierURL)))]),
            "result": .object(["integrity": .string("passed"), "images": .number(30), "sourceBindings": .number(2), "publishable": .bool(false)])]), to: integrityURL)
        let widgets = cards.filter { $0["position"] == .number($0["family"] == .string("iphone-duo-profile") ? 10 : 6) }.map {
            JSONValue.object(["screenshotConfiguration": $0["screenshotConfiguration"]!, "family": $0["family"]!,
                "position": $0["position"]!, "sha256": $0["assets"]!["screenshots"]!["sha256"]!])
        }
        var receipt: [String: JSONValue] = ["status": .string("owner-accepted-historical-widget-evidence-limits"),
            "selectionSHA256": .string(selectionSHA), "qualificationLimits": limits,
            "historicalTechnicalProofEstablished": .bool(false), "publishingAuthorization": .bool(false),
            "remoteMutationAuthorization": .bool(false), "approvesUnrelatedVisualDifferences": .bool(false),
            "question": .object(["text": .string("Accept these historical evidence limits without recapture?")]),
            "response": .object(["text": .string("Yes")]), "selectedWidgetEntries": .array(widgets)]
        let acceptanceURL = fixture.directory.appendingPathComponent("acceptance.json")
        func acceptance() throws -> HandoffFileBinding {
            try FileIO.writeJSONValue(.object(receipt), to: acceptanceURL)
            return HandoffFileBinding(path: acceptanceURL.path, sha256: FileIO.sha256(try Data(contentsOf: acceptanceURL)))
        }
        let accepted = try acceptance()
        try SelectedReleaseHandoff.verifyEvidence(.object(envelope), root: root, selectionSHA256: selectionSHA, acceptance: accepted)
        receipt["historicalTechnicalProofEstablished"] = .bool(true)
        XCTAssertThrowsError(try SelectedReleaseHandoff.verifyEvidence(.object(envelope), root: root,
            selectionSHA256: selectionSHA, acceptance: acceptance()))
        receipt["historicalTechnicalProofEstablished"] = .bool(false)
        receipt["status"] = .string("visual-approved-by-user")
        XCTAssertThrowsError(try SelectedReleaseHandoff.verifyEvidence(.object(envelope), root: root,
            selectionSHA256: selectionSHA, acceptance: acceptance()))
        receipt["status"] = .string("owner-accepted-historical-widget-evidence-limits")
        let finalAcceptance = try acceptance()
        let release = NormalizedRelease(version: "3.0", bundleId: "com.example.App", platform: "IOS",
            sourceReleasePath: "/release.json", sourceDigest: "source", localizations: [NormalizedLocaleRelease(
                appStoreLocale: "en-US", screenshotConfiguration: "en-US", whatsNew: "Notes",
                versionMetadata: ["whatsNew": .string("Notes")], appMetadata: [:], sourceFiles: [:])], versionMetadata: [:])
        let remoteLocale = RemoteLocalization(id: "target-en-US", locale: "en-US", attributes: [:], screenshotSets: [])
        let target = RemoteVersion(id: "target", versionString: "3.0", state: "PREPARE_FOR_SUBMISSION", attributes: [:], localizations: [remoteLocale])
        func snapshot(_ version: RemoteVersion?, source: RemoteVersion? = nil) -> RemoteSnapshot {
            RemoteSnapshot(capturedAt: "fixture", fingerprint: "fixture", appId: "app", bundleId: release.bundleId,
                platform: "IOS", requestedVersion: "3.0", targetVersion: version, sourceVersion: source, appInfo: nil)
        }
        let compatibilityURL = fixture.directory.appendingPathComponent("compatibility.json")
        func build(_ snap: RemoteSnapshot, proofVersion: String = "3.0") throws -> SelectedReleaseHandoff {
            let legacy = try DuoLegacyView.read(snap.targetVersion?.localizations.first?.screenshotSets.first { $0.displayType == "APP_IPHONE_DUO" })
            let baseline = DuoCompatibilityBaseline(policy: DuoCompatibilityBaseline.policyName, legacy: legacy, placements: [], content: [])
            let baselineJSON = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(baseline))
            try FileIO.writeJSONValue(.object(["schemaVersion": .number(1), "mode": .string("duo-cross-view-readonly-proof"),
                "snapshotFingerprint": .string(snap.fingerprint),
                "inspectionSHA256": .string(FileIO.sha256(try Data(contentsOf: fixture.inspection))),
                "appID": .string("app"), "bundleID": .string("com.example.App"), "version": .string(proofVersion),
                "versionID": .string("target"), "policy": .string(DuoCompatibilityBaseline.policyName),
                "requestMethods": .array([.string("GET")]), "remoteMutationsPerformed": .bool(false), "writePropagationProven": .bool(false),
                "locales": .array([.object(["locale": .string("en-US"), "localizationID": .string("target-en-US"), "baseline": baselineJSON])])]), to: compatibilityURL)
            return try SelectedReleaseHandoff.build(importFile: HandoffFileBinding(path: fixture.importURL.path,
                sha256: FileIO.sha256(try Data(contentsOf: fixture.importURL))), selectionSHA256: selectionSHA,
                acceptance: finalAcceptance, integrityVerification: HandoffFileBinding(path: integrityURL.path,
                sha256: FileIO.sha256(try Data(contentsOf: integrityURL))), inspection: HandoffFileBinding(path: fixture.inspection.path,
                sha256: FileIO.sha256(try Data(contentsOf: fixture.inspection))),
                compatibility: HandoffFileBinding(path: compatibilityURL.path, sha256: FileIO.sha256(try Data(contentsOf: compatibilityURL))),
                release: release, snapshot: snap)
        }
        XCTAssertThrowsError(try build(snapshot(nil))) { XCTAssertTrue($0.localizedDescription.contains("existing editable target")) }
        var inspection = try FileIO.readJSON(at: fixture.inspection).objectValue!
        inspection["appId"] = .string("app")
        inspection["targetVersion"] = .object(["id": .string("target"), "attributes": .object([
            "versionString": .string("3.0"), "platform": .string("IOS"), "appVersionState": .string("PREPARE_FOR_SUBMISSION")])])
        inspection["localizations"] = .array([.object(["locale": .string("en-US"),
            "localizationId": .string("target-en-US"), "orderedPlacements": .array([])])])
        try FileIO.writeJSONValue(.object(inspection), to: fixture.inspection)
        let result = try build(snapshot(target))
        XCTAssertEqual(result.qualificationLimits, limits)
        XCTAssertEqual(result.sets.count, 1)
        XCTAssertEqual(result.sets[0].localizationID, "target-en-US")
        XCTAssertEqual(result.sets[0].images.map(\.position), Array(1...10))
        XCTAssertTrue(result.sets[0].reviewedBaseline.isEmpty)
        // Exercise the actual selected Publisher entry point with read-only Duo
        // proof first, while released-source and unrelated-set drift stay strict.
        let wireInfo = RemoteAppInfo(id: "info", state: "PREPARE_FOR_SUBMISSION", localizations: [
            RemoteAppInfoLocalization(id: "info-en", locale: "en-US", attributes: ["locale": .string("en-US"),
                "name": .string("Example"), "subtitle": .string("Test"), "privacyPolicyUrl": .string("https://example.com/privacy")])])
        let externalImage = RemoteScreenshot(id: "external-image", fileName: "external.png", checksum: String(repeating: "a", count: 32),
            attributes: ["assetDeliveryState": .object(["state": .string("COMPLETE")])])
        let externalSet = RemoteScreenshotSet(id: "external-set", displayType: "UNMANAGED_DISPLAY", screenshots: [externalImage])
        let wireLocale = RemoteLocalization(id: "target-en-US", locale: "en-US",
            attributes: ["locale": .string("en-US"), "whatsNew": .string("Notes"), "description": .string("Description"),
                "keywords": .string("game"), "supportUrl": .string("https://example.com/support")], screenshotSets: [externalSet])
        let wireTarget = RemoteVersion(id: "target", versionString: "3.0", state: "PREPARE_FOR_SUBMISSION",
            attributes: ["versionString": .string("3.0")], localizations: [wireLocale])
        let wireSource = RemoteVersion(id: "released", versionString: "2.4.1", state: "READY_FOR_DISTRIBUTION",
            attributes: ["copyright": .string("Original")], localizations: [RemoteLocalization(id: "released-en", locale: "en-US",
                attributes: wireLocale.attributes, screenshotSets: [])])
        func wireSnapshot(target: RemoteVersion, source: RemoteVersion) throws -> RemoteSnapshot {
            let draft = RemoteSnapshot(capturedAt: "fixture", fingerprint: "", appId: "app", bundleId: release.bundleId,
                platform: "IOS", requestedVersion: "3.0", targetVersion: target, sourceVersion: source, appInfo: wireInfo)
            return RemoteSnapshot(capturedAt: draft.capturedAt, fingerprint: try SnapshotService.fingerprint(snapshot: draft),
                appId: draft.appId, bundleId: draft.bundleId, platform: draft.platform, requestedVersion: draft.requestedVersion,
                targetVersion: target, sourceVersion: source, appInfo: wireInfo)
        }
        let wireReviewed = try wireSnapshot(target: wireTarget, source: wireSource)
        let wireHandoff = try build(wireReviewed)
        let wireHandoffURL = fixture.directory.appendingPathComponent("wire-handoff.json")
        try FileIO.writeJSON(wireHandoff, to: wireHandoffURL)
        let sets = try ["iphone-6.9", "ipad-13"].map { family -> ManifestScreenshotSet in
            let images = try cards.filter { $0["family"] == .string(family) }.map { card -> ManifestScreenshot in
                let url = root.appendingPathComponent(card["assets"]!["screenshots"]!["importedPath"]!.stringValue!)
                let data = try Data(contentsOf: url)
                return ManifestScreenshot(path: url.path, fileName: url.lastPathComponent, byteCount: data.count,
                    sha256: FileIO.sha256(data), md5: FileIO.md5(data), order: card["position"]!.intValue!)
            }
            return ManifestScreenshotSet(family: family, displayType: family == "iphone-6.9" ? "APP_IPHONE_67" : "APP_IPAD_PRO_3GEN_129",
                pixelWidth: 1398, pixelHeight: 2034, screenshots: images)
        }
        let wireHandoffSHA = FileIO.sha256(try Data(contentsOf: wireHandoffURL))
        func wireManifest(_ digest: String) -> PublishManifest {
            PublishManifest(schemaVersion: 1, generatedAt: "fixture", release: release, remoteSnapshot: wireReviewed,
                remoteFingerprint: wireReviewed.fingerprint, captureMetadata: .object(["mode": .string("selected-lineup"),
                    "expectedScreenshotCount": .number(20), "selectedHandoff": .object(["path": .string(wireHandoffURL.path),
                    "sha256": .string(wireHandoffSHA)])]),
                localizations: [ManifestLocale(appStoreLocale: "en-US", versionMetadata: ["whatsNew": .string("Notes")],
                    appMetadata: [:], screenshotSets: sets)], manifestDigest: digest)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifest = wireManifest(FileIO.sha256(try encoder.encode(wireManifest(""))))
        try ManifestBuilder.verify(manifest)
        for fault in ["source", "unmanaged-content", "unmanaged-set-id"] {
            var source = wireSource, target = wireTarget
            if fault == "source" {
                source = RemoteVersion(id: wireSource.id, versionString: wireSource.versionString, state: wireSource.state,
                    attributes: ["copyright": .string("Unreviewed")], localizations: wireSource.localizations)
            } else {
                let image = RemoteScreenshot(id: externalImage.id, fileName: externalImage.fileName,
                    checksum: fault == "unmanaged-content" ? String(repeating: "b", count: 32) : externalImage.checksum,
                    attributes: externalImage.attributes)
                let other = RemoteScreenshotSet(id: fault == "unmanaged-set-id" ? "unowned-replacement-set" : externalSet.id,
                    displayType: externalSet.displayType, screenshots: [image])
                target = RemoteVersion(id: wireTarget.id, versionString: wireTarget.versionString, state: wireTarget.state,
                    attributes: wireTarget.attributes, localizations: [RemoteLocalization(id: wireLocale.id, locale: wireLocale.locale,
                        attributes: wireLocale.attributes, screenshotSets: [other])])
            }
            let live = try wireSnapshot(target: target, source: source)
            let directory = fixture.directory.appendingPathComponent("wire-" + fault)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let journalURL = directory.appendingPathComponent("journal.json")
            let journal = PublishJournal(version: "3.0", manifestDigest: manifest.manifestDigest, startedAt: "fixture",
                operations: [JournalOperation(key: "version-locale:en-US:metadata", status: "complete", timestamp: "fixture", detail: "target-en-US")])
            try FileIO.writeJSON(journal, to: journalURL)
            let before = try Data(contentsOf: journalURL)
            var trace: [String] = []
            let service = WireReadOnlyDuoService { trace.append($0) }
            let transport = WireNoHTTPTransport()
            let client = ASCAPIClient(credentials: ASCCredentials(keyId: "test", issuerId: "test",
                privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation), transport: transport)
            let publisher = try Publisher(client: client, journalURL: journalURL, manifest: manifest,
                snapshotProvider: { _ in trace.append("snapshot"); return live }, duoService: service)
            XCTAssertThrowsError(try publisher.publish(manifest: manifest, confirmedVersion: "3.0",
                confirmedManifestDigest: manifest.manifestDigest)) { error in
                XCTAssertTrue(error.localizedDescription.contains(fault == "source" ? "Live source version" : "Unmanaged screenshot set changed"), error.localizedDescription)
            }
            XCTAssertLessThan(try XCTUnwrap(trace.firstIndex(of: "duo-legacy")), try XCTUnwrap(trace.firstIndex(of: "snapshot")))
            XCTAssertEqual(transport.count, 0)
            XCTAssertEqual(service.writes, 0)
            XCTAssertEqual(try Data(contentsOf: journalURL), before)
        }
        let dualLocale = RemoteLocalization(id: "target-en-US", locale: "en-US", attributes: [:],
            screenshotSets: [RemoteScreenshotSet(id: "legacy-duo", displayType: "APP_IPHONE_DUO", screenshots: [])])
        let dualTarget = RemoteVersion(id: "target", versionString: "3.0", state: "PREPARE_FOR_SUBMISSION",
            attributes: [:], localizations: [dualLocale])
        let dualSource = RemoteVersion(id: "released-source", versionString: "2.4.1", state: "READY_FOR_DISTRIBUTION",
            attributes: [:], localizations: [dualLocale])
        for value in [snapshot(dualTarget), snapshot(target, source: dualSource)] {
            let qualified = try build(value)
            XCTAssertEqual(qualified.sets[0].compatibilityBaseline?.policy, DuoCompatibilityBaseline.policyName)
        }
        XCTAssertThrowsError(try build(snapshot(target), proofVersion: "2.4.1")) {
            XCTAssertTrue($0.localizedDescription.contains("different target/snapshot"))
        }
        var changedCards = cards
        var changed = changedCards[0].objectValue!
        changed["origin"] = .object(["kind": .string("rewritten-origin")]); changedCards[0] = .object(changed)
        envelope["cards"] = .array(changedCards)
        try FileIO.writeJSONValue(.object(envelope), to: fixture.importURL)
        XCTAssertThrowsError(try build(snapshot(target))) { XCTAssertTrue($0.localizedDescription.contains("missing or stale")) }
        envelope["cards"] = .array(cards)
        try FileIO.writeJSONValue(.object(envelope), to: fixture.importURL)
        inspection["localizations"] = .array([.object(["locale": .string("en-US"),
            "localizationId": .string("old-source-2.4-ID"), "orderedPlacements": .array([])])])
        try FileIO.writeJSONValue(.object(inspection), to: fixture.inspection)
        XCTAssertThrowsError(try build(snapshot(target)))
    }

    private func processedImage(state: String = "PREPARE_FOR_SUBMISSION") -> JSONValue {
        .object(["type": .string("appAssetLibraryImages"), "id": .string("returned-image"),
                 "attributes": .object(["state": .string(state), "category": .string("APP_SCREENSHOTS_AND_PREVIEWS"), "specId": .string("spec-0")])])
    }

    func testOfflinePlanRequiresCompleteConfiguredLocaleBijection() throws {
        let fixture = try planFixture(extraConfiguredLocale: true)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        XCTAssertThrowsError(try fixture.build()) { error in
            XCTAssertTrue(error.localizedDescription.contains("configured locale bijection"))
        }
    }

    private struct PlanFixture {
        let directory: URL, importURL: URL, inspection: URL
        let importSHA: String, selectionSHA: String, inspectionSHA: String
        func build(revisedInspectionSHA256: String? = nil) throws -> JSONValue {
            try DuoAssetLibraryPlanBuilder.build(inspectionURL: inspection, expectedInspectionSHA256: revisedInspectionSHA256 ?? inspectionSHA, importURL: importURL,
                expectedImportSHA256: importSHA, expectedSelectionSHA256: selectionSHA)
        }
    }

    private func planFixture(extraConfiguredLocale: Bool = false) throws -> PlanFixture {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let root = directory.appendingPathComponent("import")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let originalSelection = directory.appendingPathComponent("AppStoreReleases/3.0/screenshots/selected-lineup.json").path
        let configURL = root.appendingPathComponent("config.json")
        var configuredLocales: [JSONValue] = [.object([
            "appStoreLocale": .string("en-US"), "screenshotConfiguration": .string("en-US")])]
        if extraConfiguredLocale {
            configuredLocales.append(.object(["appStoreLocale": .string("es-MX"), "screenshotConfiguration": .string("es-MX")]))
        }
        try FileIO.writeJSONValue(.object(["bundleId": .string("com.example.App"), "localizations": .array(configuredLocales)]), to: configURL)
        let provider = CGDataProvider(data: Data(repeating: 96, count: 1398 * 2034 * 3) as CFData)!
        let image = CGImage(width: 1398, height: 2034, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: 1398 * 3,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let png = NSMutableData(); let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        let bytes = png as Data, imageSHA = FileIO.sha256(bytes)
        var cards: [JSONValue] = [], selected: [JSONValue] = []
        for family in ["iphone-6.9", "ipad-13", "iphone-duo-profile"] {
            for position in 1...10 {
                let file = "\(position).png", relative = "screenshots/en-US/\(family)/\(file)"
                let asset: JSONValue = .object(["sha256": .string(imageSHA), "dimensions": .array([.number(1398), .number(2034)]),
                                               "importedPath": .string(relative)])
                if family == "iphone-duo-profile" { try FileIO.write(data: bytes, to: root.appendingPathComponent(relative)) }
                var card: [String: JSONValue] = ["appStoreLocale": .string("en-US"), "screenshotConfiguration": .string("en-US"),
                    "family": .string(family), "position": .number(Double(position)), "assets": .object(["screenshots": asset])]
                card["origin"] = .object(["kind": .string("fixture-original-origin"), "launch": .null]); cards.append(.object(card))
                card["outputFile"] = .string(file); selected.append(.object(card))
            }
        }
        let limits: JSONValue = .object(["widgetUnresolved": .array([.string("AX_READY_NOT_OBSERVED")])])
        let selectionURL = root.appendingPathComponent("selection.json")
        try FileIO.writeJSONValue(.object(["releaseVersion": .string("3.0"), "screenshotConfigurationOrder": .array([.string("en-US")]),
            "selectedFramedImageCount": .number(30), "images": .array(selected), "qualificationLimits": limits,
            "localeMappingSource": .object(["path": .string("../../Surround/config.json"), "sha256": .string(FileIO.sha256(try Data(contentsOf: configURL)))]),
            "locales": .array([.object(["appStoreLocale": .string("en-US"), "screenshotConfiguration": .string("en-US")])])]), to: selectionURL)
        let selectionSHA = FileIO.sha256(try Data(contentsOf: selectionURL))
        func binding(_ url: URL, original: String) throws -> JSONValue {
            let data = try Data(contentsOf: url)
            return .object(["originalPath": .string(original), "retainedPath": .string(url.lastPathComponent),
                            "sha256": .string(FileIO.sha256(data)), "bytes": .number(Double(data.count))])
        }
        let importURL = root.appendingPathComponent("selected-import.json")
        try FileIO.writeJSONValue(.object(["schemaVersion": .number(1), "mode": .string("selected-import"), "publishable": .bool(false),
            "selectionSHA256": .string(selectionSHA), "selectionOriginalPath": .string(originalSelection),
            "qualificationLimits": limits, "cards": .array(cards), "sourceBindings": .array([
                try binding(selectionURL, original: originalSelection),
                try binding(configURL, original: directory.appendingPathComponent("Surround/config.json").path)])]), to: importURL)
        let inspectionURL = directory.appendingPathComponent("inspection.json")
        let reference = try catalog()
        try FileIO.writeJSONValue(.object(["purpose": .string("duo-asset-library-readonly-inspection"),
            "perAppAssetLibraryReadable": .bool(true), "remoteMutationsPerformed": .bool(false),
            "bundleId": .string("com.example.App"), "requestedVersion": .string("3.0"),
            "catalogResources": .array(reference), "routing": try DuoAssetLibraryRouting.resolve(catalog: reference),
            "assetLibraryId": .string("library"), "targetVersion": .null, "localizations": .array([])]), to: inspectionURL)
        return PlanFixture(directory: directory, importURL: importURL, inspection: inspectionURL,
                           importSHA: FileIO.sha256(try Data(contentsOf: importURL)), selectionSHA: selectionSHA,
                           inspectionSHA: FileIO.sha256(try Data(contentsOf: inspectionURL)))
    }

    private func group(platform: String = "IPHONE_APP_STORE") -> [String: Any] {
        ["platform": platform, "displayClassId": "IPHONE_DUO", "placementProfileGroupId": "runtime-duo-group"]
    }

    private func catalog(groups: [[String: Any]]? = nil, alpha: Bool = false, includeInner: Bool = true, malformedSpec: Bool = false) throws -> [JSONValue] {
        let sizes = [(1398, 2034), (2034, 1398)] + (includeInner ? [(2853, 2007), (2007, 2853)] : [])
        let specs: [[String: Any]] = sizes.enumerated().map { index, size in
            ["specId": "spec-\(index)", "alphaAllowed": alpha, "compatiblePlacementTypes": ["APP_SCREENSHOT"],
             "mimeTypes": ["image/png"], "maxFileSize": 524288000,
             "fileExtensions": [".png"], "dimensions": ["minWidth": size.0, "maxWidth": size.0,
                                                          "minHeight": size.1, "maxHeight": size.1]]
        }
        return [try JSONValue(any: ["id": "catalog", "attributes": [
            "placementProfileGroups": groups ?? [group(), group(platform: "IMESSAGE_APP_STORE")],
            "placementTypes": [["placementTypeId": "APP_SCREENSHOT", "acceptsAssetCategories": ["APP_SCREENSHOTS_AND_PREVIEWS"],
                                "specMappings": [["placementGroupId": "runtime-duo-group", "specs": specs.map { $0["specId"]! } + (malformedSpec ? [42] : [])]]]],
            "features": [["featureId": "APP_STORE_VERSIONS", "placementPolicies": [["placementType": "APP_SCREENSHOT",
                           "groupLimits": [["groupIds": ["runtime-duo-group", "other-phone"], "maxCount": 10]]]]]],
            "imageSpecs": specs,
        ]])]
    }
}

private final class ReadOnlyDuoTransport: HTTPTransport, @unchecked Sendable {
    let catalog: [JSONValue]
    var methods: [String] = []
    var lastQuery: [URLQueryItem]?
    let appID: String
    init(catalog: [JSONValue], appID: String = "app") { self.catalog = catalog; self.appID = appID }
    func send(_ request: URLRequest) throws -> TransportResponse {
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        methods.append(request.httpMethod!)
        let value: JSONValue
        switch request.url!.path {
        case "/v1/appAssetLibraryRefData": value = .object(["data": .array(catalog)])
        case "/v1/apps": value = .object(["data": .array([.object(["id": .string(appID)])])])
        case "/v1/apps/app/assetLibrary": value = .object(["data": .object(["id": .string("library")])])
        case "/v1/apps/app/appStoreVersions": value = .object(["data": .array([.object([
            "id": .string("version"), "attributes": .object(["versionString": .string("3.0")])
        ])])])
        case "/v1/appStoreVersions/version/appStoreVersionLocalizations": value = .object(["data": .array([.object([
            "id": .string("locale"), "attributes": .object(["locale": .string("en-US")])
        ])])])
        case "/v1/appStoreVersionLocalizations/locale/placements":
            lastQuery = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            value = .object(["data": .array([.object(["id": .string("placement")])])])
        default: throw ReleaseToolError.api("Unexpected mocked GET")
        }
        return TransportResponse(data: try JSONEncoder().encode(value), statusCode: 200)
    }
}

private final class WireReadOnlyDuoService: DuoPublishingService {
    let read: (String) -> Void
    var writes = 0
    init(_ read: @escaping (String) -> Void) { self.read = read }
    func verifyEditableTarget(_ set: DuoPublishSet) throws { read("duo-context") }
    func placements(localizationID: String, group: String) throws -> [DuoRemotePlacement] { read("duo-placements"); return [] }
    func legacyDuoSet(localizationID: String) throws -> RemoteScreenshotSet? { read("duo-legacy"); return nil }
    func image(id: String) throws -> JSONValue { throw ReleaseToolError.validation("Unexpected fixture image read") }
    func download(_ url: URL) throws -> Data { throw ReleaseToolError.validation("Unexpected fixture download") }
    func send(_ request: DuoAssetLibraryRequest) throws -> JSONValue? { writes += 1; throw ReleaseToolError.validation("Unexpected fixture mutation") }
    func upload(_ operation: UploadOperation, bytes: Data) throws { writes += 1; throw ReleaseToolError.validation("Unexpected fixture upload") }
}

private final class WireNoHTTPTransport: HTTPTransport, @unchecked Sendable {
    var count = 0
    func send(_ request: URLRequest) throws -> TransportResponse {
        count += 1
        throw ReleaseToolError.validation("No HTTP is authorized in this fixture")
    }
}
