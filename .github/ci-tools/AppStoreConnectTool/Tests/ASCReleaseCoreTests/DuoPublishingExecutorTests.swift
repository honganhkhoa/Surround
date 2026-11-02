import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ASCReleaseCore

final class DuoPublishingExecutorTests: XCTestCase {
    func testStagesAllImagesBeforeDeletionAndCompletedResumeOnlyReads() throws {
        let fixture = try DuoExecutorFixture()
        defer { fixture.clean() }
        fixture.service.beforeMutation = { _ in
            let journal = try ManifestBuilder.decode(DuoExecutionJournal.self, at: fixture.journal)
            XCTAssertEqual(journal.entries.last?.status, "intent")
        }
        try fixture.run()
        let events = fixture.service.events
        XCTAssertEqual(events.filter { $0.hasPrefix("reserve:") }.count, 10)
        XCTAssertLessThan(events.lastIndex(where: { $0.hasPrefix("commit:") })!, events.firstIndex(where: { $0.hasPrefix("delete:") })!)
        XCTAssertEqual(try fixture.state().phase, "complete")
        XCTAssertEqual(fixture.service.rows.count, 10)
        let count = events.count
        try fixture.run()
        XCTAssertEqual(fixture.service.events.count, count)
        XCTAssertTrue(fixture.originalImagesPreserved())
        XCTAssertFalse(try String(contentsOf: fixture.journal).contains("DO-NOT-PERSIST"))
    }

    func testIntentPersistenceFailureSendsNoMutation() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        let writer: (Data, URL) throws -> Void = { data, url in
            let journal = try JSONDecoder().decode(DuoExecutionJournal.self, from: data)
            if journal.entries.last?.status == "intent" { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        }
        XCTAssertThrowsError(try fixture.run(writer: writer)) { error in
            guard case DuoExecutionFailure.persistence = error else { return XCTFail("\(error)") }
        }
        XCTAssertTrue(fixture.service.events.isEmpty)
        XCTAssertEqual(fixture.service.rows, fixture.set.reviewedBaseline)
    }

    func testAmbiguousReservationNeverReplaysOrDeletesBaselineOnRestart() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        fixture.service.fault = { label, after in
            if label.hasPrefix("reserve:") && after {
                fixture.service.fault = nil
                throw DuoExecutionFailure.uncertain("lost reservation response")
            }
        }
        XCTAssertThrowsError(try fixture.run())
        XCTAssertThrowsError(try fixture.run())
        XCTAssertEqual(fixture.service.events.count, 1)
        XCTAssertEqual(fixture.service.rows, fixture.set.reviewedBaseline)
        XCTAssertEqual(try fixture.state().entries.last?.status, "uncertain")
    }

    func testLostPlacementResponseIsAdoptedOnlyByExactKnownImageID() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        fixture.service.fault = { label, after in
            if label == "place:1.png" && after {
                fixture.service.fault = nil
                throw DuoExecutionFailure.uncertain("lost placement response")
            }
        }
        XCTAssertThrowsError(try fixture.run())
        try fixture.run()
        XCTAssertEqual(fixture.service.events.filter { $0 == "place:1.png" }.count, 1)
        XCTAssertEqual(fixture.service.events.filter { $0.hasPrefix("reserve:") }.count, 10)
        XCTAssertEqual(try fixture.state().phase, "complete")
    }

    func testLostOrderResponseDoesNotRepeatOrderingPOST() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        fixture.service.fault = { label, after in
            if label == "order" && after { fixture.service.fault = nil; throw DuoExecutionFailure.uncertain("lost order response") }
        }
        XCTAssertThrowsError(try fixture.run())
        try fixture.run()
        XCTAssertEqual(fixture.service.events.filter { $0 == "order" }.count, 1)
        XCTAssertEqual(try fixture.state().phase, "complete")
    }

    func testKnownFailureRestoresPNGContentOrderAndResumesWithNewEpoch() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        fixture.service.fault = { label, after in
            if label == "place:3.png" && !after { fixture.service.fault = nil; throw DuoExecutionFailure.rejected("known validation failure") }
        }
        XCTAssertThrowsError(try fixture.run()) { error in
            guard case DuoExecutionFailure.restored = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try fixture.state().phase, "rolledBack")
        XCTAssertEqual(try fixture.currentPixels(), fixture.originalPixels)
        XCTAssertTrue(fixture.originalImagesPreserved())
        let reservations = fixture.service.events.filter { $0.hasPrefix("reserve:") }.count
        try fixture.run()
        XCTAssertEqual(try fixture.state().phase, "complete")
        XCTAssertEqual(try fixture.state().epoch, 1)
        XCTAssertEqual(fixture.service.events.filter { $0.hasPrefix("reserve:") }.count, reservations)
    }

    func testKnownDeleteFailureRestoresOnlyMissingOriginalPositions() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        fixture.service.fault = { label, after in
            if label == "delete:old-placement-3" && !after { fixture.service.fault = nil; throw DuoExecutionFailure.rejected("known delete failure") }
        }
        XCTAssertThrowsError(try fixture.run())
        XCTAssertEqual(try fixture.state().phase, "rolledBack")
        XCTAssertEqual(try fixture.currentPixels(), fixture.originalPixels)
        XCTAssertEqual(fixture.service.events.filter { $0.hasPrefix("reserve:backup-") }.count, 2)
        XCTAssertEqual(Array(fixture.service.rows.dropFirst(2)).map(\.id), Array(fixture.set.reviewedBaseline.dropFirst(2)).map(\.id))
    }

    func testProcessingFailureAndWrongSpecificationNeverDeletePlacements() throws {
        for wrongSpec in [false, true] {
            let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
            fixture.service.failProcessing = !wrongSpec; fixture.service.wrongSpecification = wrongSpec
            XCTAssertThrowsError(try fixture.run())
            XCTAssertFalse(fixture.service.events.contains { $0.hasPrefix("delete:") })
            XCTAssertEqual(fixture.service.rows, fixture.set.reviewedBaseline)
        }
    }

    func testForeignPlacementStopsCompensationWithoutClobberingIt() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        fixture.service.fault = { label, after in
            if label == "place:3.png" && !after {
                fixture.service.fault = nil
                fixture.service.rows.append(DuoRemotePlacement(id: "foreign", imageID: "old-image-1", group: "test-duo-group", state: "ACTIVE"))
                throw DuoExecutionFailure.rejected("known failure concurrent with foreign change")
            }
        }
        XCTAssertThrowsError(try fixture.run())
        XCTAssertEqual(try fixture.state().phase, "rollingBack")
        XCTAssertTrue(fixture.service.rows.contains { $0.id == "foreign" })
        XCTAssertFalse(fixture.service.events.contains { $0 == "delete:foreign" || $0 == "delete:placement-1" })
    }

    func testInterruptedRollbackAdoptsKnownImagePlacementWithoutReplay() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        var forwardFailed = false
        fixture.service.fault = { label, after in
            if label == "place:3.png" && !after && !forwardFailed {
                forwardFailed = true; throw DuoExecutionFailure.rejected("known forward failure")
            }
            if label == "place:backup-1.png" && after {
                fixture.service.fault = nil; throw DuoExecutionFailure.uncertain("lost rollback placement response")
            }
        }
        XCTAssertThrowsError(try fixture.run())
        XCTAssertEqual(try fixture.state().phase, "rollingBack")
        XCTAssertThrowsError(try fixture.run()) { error in
            guard case DuoExecutionFailure.restored = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try fixture.state().phase, "rolledBack")
        XCTAssertEqual(fixture.service.events.filter { $0 == "place:backup-1.png" }.count, 1)
        XCTAssertEqual(try fixture.currentPixels(), fixture.originalPixels)
    }

    func testEmptyAndSmallerBaselinesRestoreTheirWholeActualCount() throws {
        for count in [0, 3] {
            let fixture = try DuoExecutorFixture(baselineCount: count); defer { fixture.clean() }
            fixture.service.fault = { label, after in
                if label == "order" && !after { fixture.service.fault = nil; throw DuoExecutionFailure.rejected("known ordering failure") }
            }
            XCTAssertThrowsError(try fixture.run())
            XCTAssertEqual(try fixture.state().phase, "rolledBack")
            XCTAssertEqual(fixture.service.rows.count, count)
            XCTAssertEqual(try fixture.currentPixels(), fixture.originalPixels)
            XCTAssertEqual(fixture.service.events.filter { $0 == "order" }.count, count == 0 ? 1 : 2)
        }
    }

    func testTamperedSourceAndChangedJournalPlanAreRejected() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        try fixture.run()
        var changed = fixture.set.images
        let old = changed[0]
        changed[0] = DuoPublishImage(position: old.position, path: old.path, fileName: old.fileName, byteCount: old.byteCount,
            sha256: String(repeating: "0", count: 64), pixelWidth: old.pixelWidth, pixelHeight: old.pixelHeight, specID: old.specID, origin: old.origin)
        let other = DuoPublishSet(version: fixture.set.version, bundleID: fixture.set.bundleID, appID: fixture.set.appID,
            assetLibraryID: fixture.set.assetLibraryID, versionID: fixture.set.versionID, localizationID: fixture.set.localizationID,
            locale: fixture.set.locale, sourceManifestSHA256: fixture.set.sourceManifestSHA256, catalog: fixture.set.catalog,
            images: changed, reviewedBaseline: fixture.set.reviewedBaseline)
        XCTAssertThrowsError(try DuoPublishingExecutor(set: other, journalURL: fixture.journal, service: fixture.service))
        let events = fixture.service.events.count
        try Data("tampered PNG".utf8).write(to: URL(fileURLWithPath: old.path))
        XCTAssertThrowsError(try fixture.run())
        XCTAssertEqual(events, fixture.service.events.count)
    }

    func testCompletedLiveDriftIsNeverOverwritten() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        try fixture.run(); fixture.service.rows.reverse()
        let count = fixture.service.events.count
        XCTAssertThrowsError(try fixture.run())
        XCTAssertEqual(fixture.service.events.count, count)
    }

    func testExternalSurvivorReorderStopsFurtherMutationsAndRestart() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        fixture.service.fault = { label, after in
            if label == "delete:old-placement-1" && after {
                fixture.service.rows.reverse(); fixture.service.fault = nil
            }
        }
        XCTAssertThrowsError(try fixture.run())
        let count = fixture.service.events.count
        XCTAssertEqual(fixture.service.events.filter { $0.hasPrefix("delete:") }.count, 1)
        XCTAssertThrowsError(try fixture.run())
        XCTAssertEqual(fixture.service.events.count, count)
    }

    func testBackupPersistenceFailureAndWrongOriginalIDNeverMutate() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        XCTAssertThrowsError(try fixture.run(backupWriter: { _, _ in throw CocoaError(.fileWriteOutOfSpace) }))
        XCTAssertTrue(fixture.service.events.isEmpty)
        fixture.service.wrongOriginalResponseID = true
        XCTAssertThrowsError(try fixture.run())
        XCTAssertTrue(fixture.service.events.isEmpty)
        XCTAssertEqual(fixture.service.rows, fixture.set.reviewedBaseline)
    }

    func testLostDeleteResponseIsReadBackWithoutRepeatingDELETE() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        fixture.service.fault = { label, after in
            if label == "delete:old-placement-1" && after {
                fixture.service.fault = nil; throw DuoExecutionFailure.uncertain("lost delete response")
            }
        }
        XCTAssertThrowsError(try fixture.run())
        try fixture.run()
        XCTAssertEqual(fixture.service.events.filter { $0 == "delete:old-placement-1" }.count, 1)
    }

    func testLostRollbackOrderResponseReconcilesBeforeCleanupLoops() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        var forwardFailed = false
        fixture.service.fault = { label, after in
            if label == "place:3.png" && !after && !forwardFailed {
                forwardFailed = true; throw DuoExecutionFailure.rejected("known forward failure")
            }
            if label == "order" && after && forwardFailed {
                fixture.service.fault = nil; throw DuoExecutionFailure.uncertain("lost rollback order response")
            }
        }
        XCTAssertThrowsError(try fixture.run())
        XCTAssertEqual(try fixture.state().phase, "rollingBack")
        XCTAssertThrowsError(try fixture.run()) { error in
            guard case DuoExecutionFailure.restored = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try fixture.state().phase, "rolledBack")
        XCTAssertEqual(fixture.service.events.filter { $0 == "order" }.count, 1)
        XCTAssertEqual(try fixture.currentPixels(), fixture.originalPixels)
    }
}

extension DuoPublishingExecutorTests {
    private func printBudget(_ label: String, _ value: ASCRequestMetricsSnapshot) throws {
        let counts = value.categories.mapValues(\.attempts)
        print(label + " " + String(data: try JSONEncoder().encode(counts), encoding: .utf8)!)
    }
    private func coordinator(_ fixture: DuoExecutorFixture) -> DuoReleaseCoordinator {
        let binding = HandoffFileBinding(path: "/unused-test-binding", sha256: String(repeating: "a", count: 64))
        let handoff = SelectedReleaseHandoff(schemaVersion: 1, mode: "selected-release-handoff",
            selectedImport: binding, selectionSHA256: binding.sha256, evidenceAcceptance: binding,
            integrityVerification: binding, duoInspection: binding, duoCompatibility: binding, qualificationLimits: .object([:]), sets: [fixture.set])
        return DuoReleaseCoordinator(handoff: handoff, service: fixture.service, journalDirectory: fixture.directory)
    }

    func testAggregateCoordinatorPreflightsAndCompletedReadbackNeverMutates() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        let value = coordinator(fixture)
        try value.preflight()
        XCTAssertTrue(fixture.service.events.isEmpty)
        try value.publish()
        let count = fixture.service.events.count
        try value.verifyCompleted()
        try value.preflight()
        try value.publish()
        XCTAssertEqual(fixture.service.events.count, count)
    }

    func testAggregateCoordinatorCompletedDriftStopsBeforeFurtherWrites() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        let value = coordinator(fixture)
        try value.publish()
        fixture.service.rows.reverse()
        let count = fixture.service.events.count
        XCTAssertThrowsError(try value.preflight())
        XCTAssertEqual(fixture.service.events.count, count)
    }

    func testAggregateCoordinatorReadbackRejectsChangedStagedCloudImage() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        let value = coordinator(fixture)
        fixture.service.fault = { label, after in
            if label == "delete:old-placement-1" && !after {
                fixture.service.fault = nil
                throw DuoExecutionFailure.uncertain("interrupted before delete")
            }
        }
        XCTAssertThrowsError(try value.publish())
        var image = fixture.service.images["image-1"]!.objectValue!
        var attributes = image["attributes"]!.objectValue!
        attributes["state"] = .string("FAILED"); image["attributes"] = .object(attributes)
        fixture.service.images["image-1"] = .object(image)
        let count = fixture.service.events.count
        XCTAssertThrowsError(try value.preflight()) { XCTAssertTrue($0.localizedDescription.contains("processing failed")) }
        XCTAssertEqual(fixture.service.events.count, count)
    }

    func testAggregateCoordinatorReconcilesLostOrderWithoutAnotherOrderWrite() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        let value = coordinator(fixture)
        fixture.service.fault = { label, after in
            if label == "order" && after {
                fixture.service.fault = nil; throw DuoExecutionFailure.uncertain("lost order response")
            }
        }
        XCTAssertThrowsError(try value.publish())
        let count = fixture.service.events.count
        try value.preflight()
        XCTAssertEqual(fixture.service.events.count, count)
        try value.publish()
        XCTAssertEqual(fixture.service.events.count, count)
    }

    func testAggregateCoordinatorResumesRollbackBeforeAnyNewGroupWork() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        let value = coordinator(fixture)
        var rejected = false
        fixture.service.fault = { label, after in
            if label == "place:3.png" && !after && !rejected {
                rejected = true; throw DuoExecutionFailure.rejected("known placement failure")
            }
            if label == "order" && after && rejected {
                fixture.service.fault = nil; throw DuoExecutionFailure.uncertain("lost rollback order")
            }
        }
        XCTAssertThrowsError(try value.publish())
        let count = fixture.service.events.count
        XCTAssertThrowsError(try value.preflight())
        XCTAssertEqual(fixture.service.events.count, count)
        XCTAssertThrowsError(try value.recoverPendingRollback()) { error in
            guard case DuoExecutionFailure.restored = error else { return XCTFail("Unexpected \(error)") }
        }
        XCTAssertEqual(fixture.service.events.count, count)
    }

    func testAggregateCoordinatorRejectsForeignBaselineBeforeAnyMutation() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        fixture.service.rows.reverse()
        XCTAssertThrowsError(try coordinator(fixture).preflight())
        XCTAssertTrue(fixture.service.events.isEmpty)
        XCTAssertThrowsError(try coordinator(fixture).verifyCompleted())
        XCTAssertTrue(fixture.service.events.isEmpty)
    }
}

extension DuoPublishingExecutorTests {
    func testCompatibilityInspectorBracketsBothLiveViewsAndNeverMutates() throws {
        let fixture = try DuoExecutorFixture(compatibility: true); defer { fixture.clean() }
        let original = try XCTUnwrap(fixture.service.makeLegacy())
        let target = RemoteVersion(id: fixture.set.versionID, versionString: "3.0", state: "PREPARE_FOR_SUBMISSION", attributes: [:],
            localizations: [RemoteLocalization(id: fixture.set.localizationID, locale: "en-US", attributes: [:], screenshotSets: [original])])
        let snapshot = RemoteSnapshot(capturedAt: "fixture", fingerprint: "fixture", appId: "app", bundleId: "com.example.App", platform: "IOS",
            requestedVersion: "3.0", targetVersion: target, sourceVersion: nil, appInfo: nil)
        let placements = fixture.service.rows.map { row -> JSONValue in
            .object(["type": .string("appAssetLibraryPlacements"), "id": .string(row.id),
                "attributes": .object(["placementGroup": .string(row.group), "placementType": .string(row.placementType), "state": .string(row.state)]),
                "relationships": .object(["image": .object(["data": .object(["type": .string("appAssetLibraryImages"), "id": .string(row.imageID)])])])])
        }
        let inspection: JSONValue = .object(["remoteMutationsPerformed": .bool(false), "requestMethods": .array([.string("GET")]),
            "appId": .string("app"), "bundleId": .string("com.example.App"), "targetVersion": .object(["id": .string(fixture.set.versionID)]),
            "requestedVersion": .string("3.0"), "routing": .object(["placementGroup": .string("test-duo-group")]),
            "localizations": .array([.object(["locale": .string("en-US"), "localizationId": .string(fixture.set.localizationID),
                                             "orderedPlacements": .array(placements)])])])
        let good = try DuoCompatibilityInspector.capture(snapshot: snapshot, snapshotSHA256: String(repeating: "a", count: 64),
            inspection: inspection, inspectionSHA256: String(repeating: "b", count: 64), service: fixture.service)
        XCTAssertEqual(good["writePropagationProven"], .bool(false))
        XCTAssertEqual(good["locales"]?.arrayValue?.count, 1)
        var reads = 0
        fixture.service.legacyOverride = {
            reads += 1
            return reads == 1 ? original : RemoteScreenshotSet(id: original.id, displayType: original.displayType,
                screenshots: Array(original.screenshots.reversed()))
        }
        XCTAssertThrowsError(try DuoCompatibilityInspector.capture(snapshot: snapshot, snapshotSHA256: String(repeating: "a", count: 64),
            inspection: inspection, inspectionSHA256: String(repeating: "b", count: 64), service: fixture.service))
        XCTAssertTrue(fixture.service.events.isEmpty)
    }

    func testDualViewReplacementAndCompleteResumeReadBothViewsWithoutReplay() throws {
        let fixture = try DuoExecutorFixture(compatibility: true); defer { fixture.clean() }
        try fixture.run()
        let completed = try fixture.state()
        XCTAssertEqual(completed.phase, "complete")
        XCTAssertEqual(completed.compatibilityCheckpoint?.legacy.images.count, 10)
        XCTAssertNotEqual(completed.compatibilityCheckpoint?.legacy.images.map(\.id), fixture.service.rows.map(\.id))
        let writes = fixture.service.events.count, reads = fixture.service.downloads
        try fixture.run()
        XCTAssertEqual(fixture.service.events.count, writes)
        XCTAssertGreaterThan(fixture.service.downloads, reads)
    }

    func testDualViewKnownLagWaitsBeforeNextMutationAndTimeoutResumesWithoutReplay() throws {
        let fixture = try DuoExecutorFixture(compatibility: true); defer { fixture.clean() }
        var remaining = 100, frozen: RemoteScreenshotSet?
        fixture.service.beforeMutation = { label in
            if label == "delete:old-placement-1" && frozen == nil {
                frozen = try fixture.service.makeLegacy()
                fixture.service.legacyOverride = {
                    if remaining > 0 { remaining -= 1; return frozen }
                    return try fixture.service.makeLegacy()
                }
            }
        }
        XCTAssertThrowsError(try fixture.run()) { error in
            guard case DuoExecutionFailure.uncertain = error else { return XCTFail("Unexpected \(error)") }
        }
        XCTAssertEqual(fixture.service.events.filter { $0.hasPrefix("delete:") }.count, 1)
        let count = fixture.service.events.count
        XCTAssertThrowsError(try fixture.run())
        XCTAssertEqual(fixture.service.events.count, count)
        remaining = 0
        try fixture.run()
        XCTAssertEqual(fixture.service.events.filter { $0 == "delete:old-placement-1" }.count, 1)
        XCTAssertEqual(try fixture.state().phase, "complete")
    }

    func testCountMismatchRecordsSanitizedEvidenceWithoutAdoptingOlderRows() throws {
        let fixture = try DuoExecutorFixture(compatibility: true); defer { fixture.clean() }
        let original = try XCTUnwrap(fixture.set.compatibilityBaseline)
        let fullLegacy = try XCTUnwrap(fixture.service.makeLegacy())
        let previous = DuoCompatibilityBaseline(policy: original.policy,
            legacy: DuoLegacyView(setID: original.legacy.setID, images: Array(original.legacy.images.dropFirst(2))),
            placements: Array(original.placements.dropFirst(2)), content: Array(original.content.dropFirst(2)))
        let graph = Array(original.placements.dropFirst(3))
        fixture.service.rows = graph
        fixture.service.legacyOverride = { fullLegacy }
        let expected = zip(original.content.dropFirst(3), original.legacy.images.dropFirst(3)).map { proof, old in
            DuoExpectedContent(fileName: proof.fileName, byteCount: proof.byteCount, width: proof.asset.width,
                height: proof.asset.height, pixels: proof.pixelSHA256, checksum: old.checksum,
                pinnedAsset: proof.asset, pinnedLegacyID: old.id)
        }
        let verifier = DuoCompatibilityVerifier(service: fixture.service, localizationID: fixture.set.localizationID,
            group: "test-duo-group", attempts: 2, sleeper: { _ in })
        XCTAssertThrowsError(try verifier.prove(graph: graph, expected: expected, previous: previous)) { error in
            let message = error.localizedDescription
            let marker = "sanitized-readback="
            guard let start = message.range(of: marker) else { return XCTFail(message) }
            guard let evidence = try? JSONDecoder().decode(JSONValue.self, from: Data(message[start.upperBound...].utf8)) else {
                return XCTFail("Invalid sanitized readback JSON")
            }
            XCTAssertEqual(evidence["expectedModern"]?.arrayValue?.count, 7)
            XCTAssertEqual(evidence["observedLegacy"]?["rows"]?.arrayValue?.count, 10)
            XCTAssertEqual(evidence["previousLegacy"]?["rows"]?.arrayValue?.count, 8)
            XCTAssertEqual(evidence["previousCheckpointSHA256"]?.stringValue?.count, 64)
            XCTAssertNotNil(evidence["atUTC"]?.stringValue)
            XCTAssertFalse(message.contains("https://"))
            XCTAssertFalse(message.contains("old-1.png"))
            XCTAssertFalse(message.contains("DO-NOT-PERSIST"))
        }
        XCTAssertTrue(fixture.service.events.isEmpty)
        XCTAssertEqual(fixture.service.downloads, 0)
    }

    private func appendedDeletingRow(_ original: RemoteScreenshotSet, position: Int? = nil) throws -> RemoteScreenshotSet {
        let deleted = try XCTUnwrap(original.screenshots.first)
        var attributes = deleted.attributes
        var asset = try XCTUnwrap(attributes["imageAsset"]?.objectValue)
        asset["templateUrl"] = .string("https://pending.example/deleted-row.png")
        attributes["imageAsset"] = .object(asset)
        let pending = RemoteScreenshot(id: deleted.id, fileName: deleted.fileName,
            checksum: deleted.checksum, attributes: attributes)
        var rows = Array(original.screenshots.dropFirst())
        rows.insert(pending, at: position ?? rows.count)
        return RemoteScreenshotSet(id: original.id, displayType: original.displayType, screenshots: rows)
    }

    func testVerifiedDeletionAppendedLegacyRowWaitsForStrictCurrentPixelsIncludingEmptyGroup() throws {
        for count in [5, 1] {
          for position in Set([0, min(1, count - 1), count - 1]).sorted() {
            let fixture = try DuoExecutorFixture(baselineCount: count, compatibility: true); defer { fixture.clean() }
            let previous = try XCTUnwrap(fixture.set.compatibilityBaseline)
            let lagging = try appendedDeletingRow(XCTUnwrap(fixture.service.makeLegacy()), position: position)
            let graph = Array(previous.placements.dropFirst())
            fixture.service.rows = graph
            var reads = 0, waits = 0
            fixture.service.legacyOverride = {
                reads += 1
                return reads == 1 ? lagging : try fixture.service.makeLegacy()
            }
            let expected = zip(previous.content.dropFirst(), previous.legacy.images.dropFirst()).map { proof, old in
                DuoExpectedContent(fileName: proof.fileName, byteCount: proof.byteCount, width: proof.asset.width,
                    height: proof.asset.height, pixels: proof.pixelSHA256, checksum: old.checksum,
                    pinnedAsset: proof.asset, pinnedLegacyID: old.id)
            }
            let verifier = DuoCompatibilityVerifier(service: fixture.service, localizationID: fixture.set.localizationID,
                group: "test-duo-group", attempts: 2, sleeper: { _ in waits += 1 })
            let result = try verifier.prove(graph: graph, expected: expected, previous: previous,
                verifiedDeletionID: previous.placements[0].id)
            XCTAssertEqual(waits, 1)
            XCTAssertEqual(result.placements, graph)
            XCTAssertEqual(result.legacy.images, Array(previous.legacy.images.dropFirst()))
            XCTAssertEqual(result.content, Array(previous.content.dropFirst()))
            XCTAssertEqual(fixture.service.downloads, count - 1)
            XCTAssertTrue(fixture.service.events.isEmpty)
          }
        }
    }

    func testAppendedDeletingLegacyRowRejectsMissingContextAndUnownedOrChangedContent() throws {
        for fault in ["missing-context", "wrong-context", "foreign", "duplicate", "survivor-order", "survivor-template", "survivor-name", "deleted-checksum", "deleted-size", "deleted-dimensions"] {
            let fixture = try DuoExecutorFixture(baselineCount: 5, compatibility: true); defer { fixture.clean() }
            let previous = try XCTUnwrap(fixture.set.compatibilityBaseline)
            let original = try appendedDeletingRow(XCTUnwrap(fixture.service.makeLegacy()))
            var rows = original.screenshots
            if fault == "survivor-order" { rows.swapAt(0, 1) }
            else if fault == "duplicate" { rows[4] = rows[0] }
            else if !["missing-context", "wrong-context"].contains(fault) {
                let index = fault.hasPrefix("survivor") ? 0 : 4
                let old = rows[index]; var attributes = old.attributes
                var name = old.fileName, checksum = old.checksum, id = old.id
                if fault == "foreign" { id = "unknown-legacy-row" }
                if fault == "survivor-name" { name = "changed.png" }
                if fault == "deleted-checksum" { checksum = String(repeating: "0", count: 32) }
                if fault == "deleted-size" { attributes["fileSize"] = .number(1) }
                if ["survivor-template", "deleted-dimensions"].contains(fault) {
                    var asset = try XCTUnwrap(attributes["imageAsset"]?.objectValue)
                    asset[fault == "survivor-template" ? "templateUrl" : "width"] = fault == "survivor-template" ? .string("https://changed.example/survivor.png") : .number(1)
                    attributes["imageAsset"] = .object(asset)
                }
                rows[index] = RemoteScreenshot(id: id, fileName: name, checksum: checksum, attributes: attributes)
            }
            fixture.service.rows = Array(previous.placements.dropFirst())
            fixture.service.legacyOverride = { RemoteScreenshotSet(id: original.id, displayType: original.displayType, screenshots: rows) }
            let expected = zip(previous.content.dropFirst(), previous.legacy.images.dropFirst()).map { proof, old in
                DuoExpectedContent(fileName: proof.fileName, byteCount: proof.byteCount, width: proof.asset.width,
                    height: proof.asset.height, pixels: proof.pixelSHA256, checksum: old.checksum,
                    pinnedAsset: proof.asset, pinnedLegacyID: old.id)
            }
            var waits = 0
            let verifier = DuoCompatibilityVerifier(service: fixture.service, localizationID: fixture.set.localizationID,
                group: "test-duo-group", attempts: 2, sleeper: { _ in waits += 1 })
            let deletionID = fault == "missing-context" ? nil : (fault == "wrong-context" ? "wrong-placement" : previous.placements[0].id)
            XCTAssertThrowsError(try verifier.prove(graph: fixture.service.rows, expected: expected,
                previous: previous, verifiedDeletionID: deletionID), fault) { error in
                guard case DuoExecutionFailure.drift = error else { return XCTFail("\(fault): \(error)") }
            }
            XCTAssertEqual(waits, 0, fault)
            XCTAssertEqual(fixture.service.downloads, 0, fault)
            XCTAssertTrue(fixture.service.events.isEmpty, fault)
        }
    }

    func testAppendedDeletingRowTimeoutKeepsCheckpointAndResumesWithoutWriteReplay() throws {
        let fixture = try DuoExecutorFixture(compatibility: true); defer { fixture.clean() }
        var remaining = 100, lagging: RemoteScreenshotSet?
        fixture.service.beforeMutation = { label in
            if label == "delete:old-placement-1" && lagging == nil {
                lagging = try self.appendedDeletingRow(XCTUnwrap(fixture.service.makeLegacy()))
                fixture.service.legacyOverride = {
                    if remaining > 0 { remaining -= 1; return lagging }
                    return try fixture.service.makeLegacy()
                }
            }
            if label == "delete:old-placement-2" { XCTAssertEqual(remaining, 0) }
        }
        XCTAssertThrowsError(try fixture.run()) { error in
            guard case DuoExecutionFailure.uncertain = error else { return XCTFail("Unexpected \(error)") }
        }
        let paused = try fixture.state()
        XCTAssertEqual(paused.compatibilityCheckpoint?.placements.count, 10)
        XCTAssertEqual(paused.expectedGraph?.count, 9)
        XCTAssertEqual(fixture.service.events.filter { $0.hasPrefix("delete:") }.count, 1)
        let writes = fixture.service.events.count
        XCTAssertThrowsError(try fixture.run())
        XCTAssertEqual(fixture.service.events.count, writes)
        // A different epoch's verified DELETE cannot authorize waiting.
        let validJournal = try Data(contentsOf: fixture.journal)
        var object = try XCTUnwrap(FileIO.readJSON(at: fixture.journal).objectValue)
        object["entries"] = .array(try XCTUnwrap(object["entries"]?.arrayValue).map { value in
            guard value["key"] == .string("switch:0:delete:old-placement-1") else { return value }
            var entry = value.objectValue!
            entry["key"] = .string("switch:99:delete:old-placement-1")
            return .object(entry)
        })
        try FileIO.writeJSON(JSONValue.object(object), to: fixture.journal)
        XCTAssertThrowsError(try fixture.run()) { error in
            guard case DuoExecutionFailure.drift = error else { return XCTFail("Unexpected \(error)") }
        }
        XCTAssertEqual(fixture.service.events.count, writes)
        try validJournal.write(to: fixture.journal)
        remaining = 0
        try fixture.run()
        XCTAssertEqual(try fixture.state().phase, "complete")
        XCTAssertEqual(fixture.service.events.filter { $0 == "delete:old-placement-1" }.count, 1)
        XCTAssertEqual(fixture.service.events.filter { $0.hasPrefix("upload:") }.count, 10)
    }

    func testPendingDeletionStillRejectsChangedModernGraphAndConvergedWrongPixels() throws {
        for fault in ["modern-order", "served-pixels"] {
            let fixture = try DuoExecutorFixture(baselineCount: 5, compatibility: true); defer { fixture.clean() }
            let previous = try XCTUnwrap(fixture.set.compatibilityBaseline)
            let lagging = try appendedDeletingRow(XCTUnwrap(fixture.service.makeLegacy()))
            let graph = Array(previous.placements.dropFirst())
            fixture.service.rows = graph
            var reads = 0
            fixture.service.legacyOverride = {
                reads += 1
                return reads == 1 ? lagging : try fixture.service.makeLegacy()
            }
            let expected = zip(previous.content.dropFirst(), previous.legacy.images.dropFirst()).map { proof, old in
                DuoExpectedContent(fileName: proof.fileName, byteCount: proof.byteCount, width: proof.asset.width,
                    height: proof.asset.height, pixels: proof.pixelSHA256, checksum: old.checksum,
                    pinnedAsset: proof.asset, pinnedLegacyID: old.id)
            }
            let verifier = DuoCompatibilityVerifier(service: fixture.service, localizationID: fixture.set.localizationID,
                group: "test-duo-group", attempts: 2, sleeper: { _ in
                    if fault == "modern-order" { fixture.service.rows.reverse() }
                    else { fixture.service.data[graph[0].imageID] = try! Data(contentsOf: URL(fileURLWithPath: fixture.set.images[1].path)) }
                })
            XCTAssertThrowsError(try verifier.prove(graph: graph, expected: expected, previous: previous,
                verifiedDeletionID: previous.placements[0].id)) { error in
                guard case DuoExecutionFailure.drift = error else { return XCTFail("\(fault): \(error)") }
            }
            XCTAssertTrue(fixture.service.events.isEmpty)
        }
    }

    func testDualViewUnknownLegacyRowOrOrderStopsBeforeAnyCloudMutation() throws {
        for fault in ["identity", "order", "processing"] {
            let fixture = try DuoExecutorFixture(compatibility: true); defer { fixture.clean() }
            let original = try XCTUnwrap(fixture.service.makeLegacy())
            var rows = original.screenshots
            if fault == "order" { rows.reverse() }
            else {
                let old = rows[0]; var attributes = old.attributes
                if fault == "processing" { attributes["assetDeliveryState"] = .object(["state": .string("PROCESSING")]) }
                rows[0] = RemoteScreenshot(id: "unowned-identical-content", fileName: old.fileName,
                    checksum: old.checksum, attributes: attributes)
            }
            let foreign = RemoteScreenshotSet(id: original.id, displayType: original.displayType, screenshots: rows)
            fixture.service.legacyOverride = { foreign }
            XCTAssertThrowsError(try fixture.run())
            XCTAssertTrue(fixture.service.events.isEmpty)
        }
    }

    func testDualViewFreshPixelsDetectChangeUnderAnUnchangedTemplate() throws {
        let fixture = try DuoExecutorFixture(compatibility: true); defer { fixture.clean() }
        let executor = try DuoPublishingExecutor(set: fixture.set, journalURL: fixture.journal,
            service: fixture.service, compatibilityPollAttempts: 2, sleeper: { _ in })
        try executor.preflight()
        let old = try fixture.service.makeLegacy()
        fixture.service.legacyOverride = { old }
        fixture.service.data["old-image-1"] = try Data(contentsOf: URL(fileURLWithPath: fixture.set.images[0].path))
        XCTAssertThrowsError(try executor.preflight()) { XCTAssertTrue($0.localizedDescription.contains("pixels differ")) }
        XCTAssertTrue(fixture.service.events.isEmpty)
    }

    func testDualViewRollbackRecordsActualBackupContentAndNewCompatibilityIDs() throws {
        let fixture = try DuoExecutorFixture(compatibility: true); defer { fixture.clean() }
        fixture.service.fault = { label, after in
            if label == "place:3.png" && !after {
                fixture.service.fault = nil; throw DuoExecutionFailure.rejected("known placement failure")
            }
        }
        XCTAssertThrowsError(try fixture.run()) { error in
            guard case DuoExecutionFailure.restored = error else { return XCTFail("Unexpected \(error)") }
        }
        let state = try fixture.state()
        XCTAssertEqual(state.phase, "rolledBack")
        XCTAssertEqual(state.activeCompatibility?.legacy.images.map(\.fileName), (1...10).map { "backup-\($0).png" })
        XCTAssertEqual(state.activeCompatibility?.placements, state.activeBaseline)
        XCTAssertTrue(fixture.originalImagesPreserved())
    }

    func testDualViewPartialDeleteLostRollbackOrderReconcilesSurvivorsBeforeRecovery() throws {
        let fixture = try DuoExecutorFixture(compatibility: true); defer { fixture.clean() }
        var rejected = false
        fixture.service.fault = { label, after in
            if label == "delete:old-placement-2" && !after && !rejected {
                rejected = true; throw DuoExecutionFailure.rejected("known second deletion failure")
            }
            if label == "order" && after && rejected {
                fixture.service.fault = nil; throw DuoExecutionFailure.uncertain("lost restore ordering response")
            }
        }
        XCTAssertThrowsError(try fixture.run())
        XCTAssertEqual(try fixture.state().phase, "rollingBack")
        let count = fixture.service.events.count
        do {
            let reader = try DuoPublishingExecutor(set: fixture.set, journalURL: fixture.journal,
                service: fixture.service, compatibilityPollAttempts: 2, sleeper: { _ in })
            try reader.preflight(allowRollbackProof: true)
        }
        XCTAssertEqual(fixture.service.events.count, count)
        XCTAssertThrowsError(try fixture.run()) { error in
            guard case DuoExecutionFailure.restored = error else { return XCTFail("Unexpected \(error)") }
        }
        XCTAssertEqual(fixture.service.events.count, count)
        let proof = try XCTUnwrap(fixture.state().activeCompatibility)
        XCTAssertEqual(proof.legacy.images[0].fileName, "backup-1.png")
        XCTAssertEqual(proof.legacy.images[1].fileName, "old-2.png")
    }

    func testDualViewInitialSnapshotExceptionIsLimitedToProvenTargetProjection() throws {
        let fixture = try DuoExecutorFixture(compatibility: true); defer { fixture.clean() }
        let value = coordinator(fixture)
        func snapshot(_ legacy: RemoteScreenshotSet?, sourceCopyright: String = "Original", extra: Bool = false) throws -> RemoteSnapshot {
            var sets = legacy.map { [$0] } ?? []
            if extra { sets.append(RemoteScreenshotSet(id: "foreign", displayType: "UNMANAGED_DISPLAY", screenshots: [])) }
            let target = RemoteVersion(id: fixture.set.versionID, versionString: "3.0", state: "PREPARE_FOR_SUBMISSION",
                attributes: [:], localizations: [RemoteLocalization(id: fixture.set.localizationID, locale: "en-US", attributes: [:], screenshotSets: sets)])
            let source = RemoteVersion(id: "released", versionString: "2.4.1", state: "READY_FOR_DISTRIBUTION",
                attributes: ["copyright": .string(sourceCopyright)], localizations: [])
            let draft = RemoteSnapshot(capturedAt: "fixture", fingerprint: "", appId: "app", bundleId: "com.example.App", platform: "IOS",
                requestedVersion: "3.0", targetVersion: target, sourceVersion: source, appInfo: nil)
            return RemoteSnapshot(capturedAt: draft.capturedAt, fingerprint: try SnapshotService.fingerprint(snapshot: draft),
                appId: draft.appId, bundleId: draft.bundleId, platform: draft.platform, requestedVersion: draft.requestedVersion,
                targetVersion: target, sourceVersion: source, appInfo: nil)
        }
        let reviewed = try snapshot(fixture.service.makeLegacy())
        try value.publish()
        try value.prepareForReconciliation()
        let current = try fixture.service.makeLegacy()
        try value.requireInitialSnapshot(snapshot(current), reviewed: reviewed)
        XCTAssertThrowsError(try value.requireInitialSnapshot(snapshot(current, sourceCopyright: "Unreviewed"), reviewed: reviewed))
        XCTAssertThrowsError(try value.requireInitialSnapshot(snapshot(current, extra: true), reviewed: reviewed))
    }

    func testDualViewSecondLocaleFailureBlocksAllCloudMutations() throws {
        let first = try DuoExecutorFixture(compatibility: true), second = try DuoExecutorFixture(compatibility: true)
        defer { first.clean(); second.clean() }
        let old = second.set
        let fr = DuoPublishSet(version: old.version, bundleID: old.bundleID, appID: old.appID, assetLibraryID: old.assetLibraryID,
            versionID: old.versionID, localizationID: "target-fr", locale: "fr-FR", sourceManifestSHA256: old.sourceManifestSHA256,
            catalog: old.catalog, images: old.images, reviewedBaseline: old.reviewedBaseline, compatibilityBaseline: old.compatibilityBaseline)
        let original = try XCTUnwrap(second.service.makeLegacy())
        second.service.legacyOverride = { RemoteScreenshotSet(id: "unreviewed-legacy-container", displayType: original.displayType,
            screenshots: original.screenshots) }
        let binding = HandoffFileBinding(path: "/unused", sha256: String(repeating: "a", count: 64))
        let handoff = SelectedReleaseHandoff(schemaVersion: 1, mode: "selected-release-handoff", selectedImport: binding,
            selectionSHA256: binding.sha256, evidenceAcceptance: binding, integrityVerification: binding,
            duoInspection: binding, duoCompatibility: binding, qualificationLimits: .object([:]), sets: [first.set, fr])
        let service = TwoLocaleDuoService(first: first.service, second: second.service)
        let value = DuoReleaseCoordinator(handoff: handoff, service: service, journalDirectory: first.directory)
        XCTAssertThrowsError(try value.prepareForReconciliation())
        XCTAssertTrue(first.service.events.isEmpty)
        XCTAssertTrue(second.service.events.isEmpty)
        XCTAssertEqual(service.writes, 0)
    }

    func testDualViewCoordinatorAdmitsOwnedProgressButRejectsUnprovenSnapshot() throws {
        let fixture = try DuoExecutorFixture(compatibility: true); defer { fixture.clean() }
        let value = coordinator(fixture)
        try value.prepareForReconciliation()
        try value.requireSnapshotProjection(locale: "en-US", sets: [try XCTUnwrap(fixture.service.makeLegacy())])
        try value.publish()
        try value.prepareForReconciliation()
        try value.requireSnapshotProjection(locale: "en-US", sets: [try XCTUnwrap(fixture.service.makeLegacy())])
        XCTAssertThrowsError(try value.requireSnapshotProjection(locale: "another-locale", sets: []))
        var foreign = try XCTUnwrap(fixture.service.makeLegacy()).screenshots
        foreign.reverse()
        XCTAssertThrowsError(try value.requireSnapshotProjection(locale: "en-US", sets: [RemoteScreenshotSet(
            id: "legacy-view", displayType: "APP_IPHONE_DUO", screenshots: foreign)]))
    }
}

private final class DuoExecutorFixture {
    let directory: URL, journal: URL, set: DuoPublishSet
    let service: DuoMemoryService
    let originalPixels: [Data]

    init(baselineCount: Int = 10, compatibility: Bool = false, namespace: String = "", locale: String = "en-US") throws {
        directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("duo-executor-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        journal = directory.appendingPathComponent("journal.json")
        let sizes = [(1398, 2034), (2034, 1398), (2853, 2007), (2007, 2853)]
        let specs: [[String: Any]] = sizes.enumerated().map { index, size in [
            "specId": "spec-\(index)", "alphaAllowed": false, "compatiblePlacementTypes": ["APP_SCREENSHOT"],
            "fileExtensions": [".png"], "mimeTypes": ["image/png"], "maxFileSize": 524288000,
            "dimensions": ["minWidth": size.0, "maxWidth": size.0, "minHeight": size.1, "maxHeight": size.1]] }
        let catalog = [try JSONValue(any: ["id": "catalog", "attributes": [
            "placementProfileGroups": [["platform": "IPHONE_APP_STORE", "displayClassId": "IPHONE_DUO", "placementProfileGroupId": "test-duo-group"]],
            "placementTypes": [["placementTypeId": "APP_SCREENSHOT", "acceptsAssetCategories": ["APP_SCREENSHOTS_AND_PREVIEWS"],
                                "specMappings": [["placementGroupId": "test-duo-group", "specs": specs.map { $0["specId"]! }]]]],
            "features": [["featureId": "APP_STORE_VERSIONS", "placementPolicies": [["placementType": "APP_SCREENSHOT",
                "groupLimits": [["groupIds": ["test-duo-group"], "maxCount": 10]]]]]], "imageSpecs": specs]])]
        let oldOuter = try Self.png(1398, 2034, byte: 32), oldInner = try Self.png(2853, 2007, byte: 48)
        let newOuter = try Self.png(1398, 2034, byte: 96), newInner = try Self.png(2853, 2007, byte: 112)
        var desired: [DuoPublishImage] = [], baseline: [DuoRemotePlacement] = [], originals: [Data] = []
        service = DuoMemoryService(); service.namespace = namespace
        for position in 1...10 {
            let inner = (2...7).contains(position), size = inner ? sizes[2] : sizes[0]
            let data = inner ? newInner : newOuter, file = directory.appendingPathComponent("\(position).png")
            try data.write(to: file)
            desired.append(DuoPublishImage(position: position, path: file.path, fileName: file.lastPathComponent, byteCount: data.count,
                sha256: FileIO.sha256(data), pixelWidth: size.0, pixelHeight: size.1, specID: inner ? "spec-2" : "spec-0",
                origin: .object(["kind": .string("synthetic-unit-fixture")])) )
            if position <= baselineCount {
                let old = inner ? oldInner : oldOuter, id = namespace + "old-image-\(position)"
                service.data[id] = old; originals.append(old)
                service.images[id] = Self.resource(id: id, name: "old-\(position).png", data: old, size: size, spec: inner ? "spec-2" : "spec-0", state: "APPROVED")
                baseline.append(DuoRemotePlacement(id: namespace + "old-placement-\(position)", imageID: id, group: "test-duo-group", state: "ACTIVE"))
            }
        }
        service.rows = baseline; originalPixels = originals
        let paired: DuoCompatibilityBaseline?
        if compatibility {
            let legacy = try DuoLegacyView.read(service.makeLegacy())
            let linkedService = service
            let content = try baseline.map { row -> DuoContentProof in
                let cloud = linkedService.images[row.imageID]!["attributes"]!
                return DuoContentProof(imageID: row.imageID, fileName: cloud["fileName"]!.stringValue!,
                    byteCount: cloud["fileSize"]!.intValue!, asset: try DuoImageAsset.read(cloud["imageAsset"]!).0,
                    pixelSHA256: try ImageValidation.pixelSHA256(linkedService.data[row.imageID]!, context: "linked baseline fixture"))
            }
            paired = DuoCompatibilityBaseline(policy: DuoCompatibilityBaseline.policyName,
                legacy: legacy, placements: baseline, content: content)
        } else { paired = nil }
        set = DuoPublishSet(version: "3.0", bundleID: "com.example.App", appID: "app", assetLibraryID: namespace + "library", versionID: "target3",
            localizationID: namespace + "target3-locale", locale: locale, sourceManifestSHA256: String(repeating: "a", count: 64),
            catalog: catalog, images: desired, reviewedBaseline: baseline, compatibilityBaseline: paired)
    }
    func clean() { service.fault = nil; service.beforeMutation = nil; try? FileManager.default.removeItem(at: directory) }
    func run(writer: ((Data, URL) throws -> Void)? = nil, backupWriter: ((Data, URL) throws -> Void)? = nil) throws {
        let executor = try DuoPublishingExecutor(set: set, journalURL: journal, service: service, pollAttempts: 2, compatibilityPollAttempts: 3, sleeper: { _ in }, journalWriter: writer, backupWriter: backupWriter)
        try executor.publish(confirmedVersion: set.version, confirmedSetDigest: set.digest())
    }
    func state() throws -> DuoExecutionJournal { try ManifestBuilder.decode(DuoExecutionJournal.self, at: journal) }
    func currentPixels() throws -> [Data] { try service.rows.map { try XCTUnwrap(service.data[$0.imageID]) } }
    func originalImagesPreserved() -> Bool { set.reviewedBaseline.enumerated().allSatisfy { service.data[$0.element.imageID] == originalPixels[$0.offset] } }
    static func resource(id: String, name: String, data: Data, size: (Int, Int), spec: String, state: String) -> JSONValue {
        .object(["type": .string("appAssetLibraryImages"), "id": .string(id), "attributes": .object([
            "fileName": .string(name), "fileSize": .number(Double(data.count)), "category": .string("APP_SCREENSHOTS_AND_PREVIEWS"),
            "createdDate": .string("2026-01-01T00:00:00Z"), "lastModifiedDate": .string("2026-01-01T00:00:01Z"),
            "state": .string(state), "specId": .string(spec), "imageAsset": .object([
                "width": .number(Double(size.0)), "height": .number(Double(size.1)), "templateUrl": .string("https://backup.example/\(id).png")])])])
    }
    private static func png(_ width: Int, _ height: Int, byte: UInt8) throws -> Data {
        let provider = CGDataProvider(data: Data(repeating: byte, count: width * height * 3) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: width * 3,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let bytes = NSMutableData()
        let encoder = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(encoder, image, nil); XCTAssertTrue(CGImageDestinationFinalize(encoder)); return bytes as Data
    }
}

private final class DuoMemoryService: DuoPublishingService {
    var rows: [DuoRemotePlacement] = []
    var images: [String: JSONValue] = [:], data: [String: Data] = [:]
    var events: [String] = []
    var fault: ((String, Bool) throws -> Void)?
    var beforeMutation: ((String) throws -> Void)?
    var failProcessing = false, wrongSpecification = false, wrongOriginalResponseID = false
    var legacyOverride: (() throws -> RemoteScreenshotSet?)?
    var legacyReads = 0
    var downloads = 0
    var namespace = ""
    var holdProcessingNames: Set<String> = []
    var beforeImageRead: ((String) throws -> Void)?
    var beforePlacementRead: (() throws -> Void)?
    private var nextImage = 0, nextPlacement = 0
    func makeLegacy() throws -> RemoteScreenshotSet? {
        if rows.isEmpty { return nil }
        let screenshots = try rows.map { row -> RemoteScreenshot in
            let raw = try XCTUnwrap(images[row.imageID])["attributes"]!
            let bytes = try XCTUnwrap(data[row.imageID])
            let attributes: [String: JSONValue] = ["fileName": raw["fileName"]!, "fileSize": raw["fileSize"]!,
                "imageAsset": raw["imageAsset"]!, "sourceFileChecksum": .string(FileIO.md5(bytes)),
                "assetDeliveryState": .object(["state": .string("COMPLETE")])]
            return RemoteScreenshot(id: "legacy-" + row.id, fileName: raw["fileName"]!.stringValue,
                checksum: FileIO.md5(bytes), attributes: attributes)
        }
        return RemoteScreenshotSet(id: "legacy-view", displayType: "APP_IPHONE_DUO", screenshots: screenshots)
    }
    func legacyDuoSet(localizationID: String) throws -> RemoteScreenshotSet? {
        legacyReads += 1
        if let legacyOverride { return try legacyOverride() }
        return try makeLegacy()
    }
    func verifyEditableTarget(_ set: DuoPublishSet) throws {}
    func placements(localizationID: String, group: String) throws -> [DuoRemotePlacement] {
        try beforePlacementRead?(); return rows
    }
    func image(id: String) throws -> JSONValue {
        try beforeImageRead?(id)
        var row = try XCTUnwrap(images[id]).objectValue!
        if wrongOriginalResponseID && id.hasPrefix("old-image-") { row["id"] = .string("another-resource") }
        return .object(row)
    }
    func download(_ url: URL) throws -> Data { downloads += 1; return try XCTUnwrap(data[url.deletingPathExtension().lastPathComponent]) }
    func finishProcessing() throws {
        holdProcessingNames.removeAll()
        for (id, row) in images where row["attributes"]?["state"] == .string("UPLOAD_COMPLETE") {
            let bytes = try XCTUnwrap(data[id]), size = try ImageValidation.decodePNG(bytes, context: "queue fixture")
            images[id] = DuoExecutorFixture.resource(id: id, name: row["attributes"]!["fileName"]!.stringValue!, data: bytes,
                size: (size.pixelWidth, size.pixelHeight), spec: size.pixelWidth == 1398 ? "spec-0" : "spec-2", state: "PREPARE_FOR_SUBMISSION")
        }
    }
    private func begin(_ label: String) throws { try beforeMutation?(label); events.append(label); try fault?(label, false) }
    private func end(_ label: String) throws { try fault?(label, true) }
    func upload(_ operation: UploadOperation, bytes: Data) throws {
        let id = URL(string: operation.url)!.lastPathComponent, label = "upload:\(id)"
        try begin(label); XCTAssertEqual(operation.offset, 0); XCTAssertEqual(operation.length, bytes.count)
        data[id] = bytes; try end(label)
    }
    func send(_ request: DuoAssetLibraryRequest) throws -> JSONValue? {
        if request.path == "/v1/appAssetLibraryImages" {
            let attrs = request.body["data"]!["attributes"]!, name = attrs["fileName"]!.stringValue!, size = attrs["fileSize"]!.intValue!
            let label = "reserve:" + name; try begin(label); nextImage += 1; let id = namespace + "image-\(nextImage)"
            images[id] = .object(["type": .string("appAssetLibraryImages"), "id": .string(id), "attributes": .object([
                "fileName": .string(name), "fileSize": .number(Double(size)), "category": .string("APP_SCREENSHOTS_AND_PREVIEWS"),
                "state": .string("AWAITING_UPLOAD"), "uploadOperations": .array([.object([
                    "method": .string("PUT"), "url": .string("https://upload.example/\(id)?token=DO-NOT-PERSIST"),
                    "offset": .number(0), "length": .number(Double(size)), "requestHeaders": .array([])])])])])
            try end(label); return .object(["data": images[id]!])
        }
        if request.method == "PATCH" && request.path.hasPrefix("/v1/appAssetLibraryImages/") {
            let id = String(request.path.split(separator: "/").last!), label = "commit:" + id
            try begin(label); XCTAssertEqual(request.body["data"]?["attributes"], .object(["uploaded": .bool(true)]))
            let old = images[id]!, bytes = try XCTUnwrap(data[id]), decoded = try ImageValidation.decodePNG(bytes, context: "fixture")
            images[id] = DuoExecutorFixture.resource(id: id, name: old["attributes"]!["fileName"]!.stringValue!, data: bytes,
                size: (decoded.pixelWidth, decoded.pixelHeight), spec: wrongSpecification ? "wrong" : (decoded.pixelWidth == 1398 ? "spec-0" : "spec-2"),
                state: failProcessing ? "FAILED" : "PREPARE_FOR_SUBMISSION")
            if holdProcessingNames.contains(old["attributes"]!["fileName"]!.stringValue!) {
                var attrs = images[id]!["attributes"]!.objectValue!
                attrs["state"] = .string("UPLOAD_COMPLETE"); attrs["imageAsset"] = .null; attrs["specId"] = .null
                var row = images[id]!.objectValue!; row["attributes"] = .object(attrs); images[id] = .object(row)
            }
            try end(label); return .object(["data": images[id]!])
        }
        if request.method == "DELETE" {
            XCTAssertTrue(request.path.hasPrefix("/v1/appAssetLibraryPlacements/"))
            let id = String(request.path.split(separator: "/").last!), label = "delete:" + id
            try begin(label); rows.removeAll { $0.id == id }; try end(label); return nil
        }
        if request.path == "/v1/appAssetLibraryPlacements" {
            let imageID = request.body["data"]!["relationships"]!["image"]!["data"]!["id"]!.stringValue!
            let label = "place:" + images[imageID]!["attributes"]!["fileName"]!.stringValue!
            try begin(label); XCTAssertLessThan(rows.count, 10); nextPlacement += 1; let id = namespace + "placement-\(nextPlacement)"
            rows.insert(DuoRemotePlacement(id: id, imageID: imageID, group: "test-duo-group", state: "PARENT_PREPARE_FOR_SUBMISSION"), at: 0)
            try end(label); return .object(["data": .object(["type": .string("appAssetLibraryPlacements"), "id": .string(id)])])
        }
        if request.path == "/v1/appAssetLibraryPlacementOrderingRequests" {
            try begin("order")
            let ids = request.body["data"]!["relationships"]!["orderedPlacements"]!["data"]!.arrayValue!.map { $0["id"]!.stringValue! }
            XCTAssertEqual(Set(ids), Set(rows.map(\.id))); rows = ids.map { id in rows.first { $0.id == id }! }
            try end("order"); return nil
        }
        throw DuoExecutionFailure.rejected("Unexpected mock route")
    }
}

/// Exercises the real ASC adapter and request counters without any networking.
private final class DuoBudgetTransport: HTTPTransport, @unchecked Sendable {
    let fixture: DuoExecutorFixture
    var omitIncluded = false
    var editable = true
    var beforeRead: ((String) throws -> Void)?
    init(_ fixture: DuoExecutorFixture) { self.fixture = fixture }
    func send(_ request: URLRequest) throws -> TransportResponse {
        let url = request.url!, path = url.path, method = request.httpMethod ?? "GET"
        let set = fixture.set, memory = fixture.service
        func response(_ value: JSONValue?) throws -> TransportResponse {
            guard let value else { return TransportResponse(data: Data(), statusCode: 204) }
            return TransportResponse(data: try JSONEncoder().encode(value), statusCode: 200)
        }
        func list(_ rows: [JSONValue], included: [JSONValue] = []) throws -> TransportResponse {
            try response(.object(["data": .array(rows), "included": .array(included)]))
        }
        func target() -> JSONValue {
            .object(["type": .string("appStoreVersions"), "id": .string(set.versionID),
                "attributes": .object(["versionString": .string(set.version), "platform": .string("IOS"),
                    "appVersionState": .string(editable ? "PREPARE_FOR_SUBMISSION" : "WAITING_FOR_REVIEW")])])
        }
        if url.host == "backup.example" { return TransportResponse(data: try memory.download(url), statusCode: 200) }
        if url.host == "upload.example" {
            let bytes = request.httpBody ?? Data()
            try memory.upload(UploadOperation(method: "PUT", url: url.absoluteString, offset: 0,
                length: bytes.count, requestHeaders: []), bytes: bytes)
            return TransportResponse(data: Data(), statusCode: 200)
        }
        if method != "GET" {
            let body = try request.httpBody.map { try JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null
            return try response(memory.send(DuoAssetLibraryRequest(method: method, path: path, body: body)))
        }
        try beforeRead?(path)
        switch path {
        case "/v1/apps/\(set.appID)":
            return try response(.object(["data": .object(["type": .string("apps"), "id": .string(set.appID),
                "attributes": .object(["bundleId": .string(set.bundleID)])])]))
        case "/v1/apps/\(set.appID)/assetLibrary":
            return try response(.object(["data": .object(["type": .string("appAssetLibraries"), "id": .string(set.assetLibraryID)])]))
        case "/v1/apps/\(set.appID)/appStoreVersions": return try list([target()])
        case "/v1/appStoreVersions/\(set.versionID)": return try response(.object(["data": target()]))
        case "/v1/appStoreVersions/\(set.versionID)/appStoreVersionLocalizations":
            return try list([.object(["type": .string("appStoreVersionLocalizations"), "id": .string(set.localizationID),
                "attributes": .object(["locale": .string(set.locale)])])])
        case "/v1/appStoreVersionLocalizations/\(set.localizationID)/placements":
            let rows = memory.rows.map { row in JSONValue.object([
                "type": .string("appAssetLibraryPlacements"), "id": .string(row.id),
                "attributes": .object(["placementGroup": .string(row.group), "placementType": .string(row.placementType), "state": .string(row.state)]),
                "relationships": .object(["image": .object(["data": .object([
                    "type": .string("appAssetLibraryImages"), "id": .string(row.imageID)])])])]) }
            XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "include" })?.value, "image")
            return try list(rows, included: omitIncluded ? [] : memory.rows.compactMap { memory.images[$0.imageID] })
        case "/v1/appStoreVersionLocalizations/\(set.localizationID)/appScreenshotSets":
            let legacy = try memory.legacyDuoSet(localizationID: set.localizationID)
            return try list(legacy.map { [.object(["id": .string($0.id),
                "attributes": .object(["screenshotDisplayType": .string($0.displayType)])])] } ?? [])
        case "/v1/appScreenshotSets/legacy-view/appScreenshots":
            let legacy = try memory.legacyDuoSet(localizationID: set.localizationID)
            return try list(legacy?.screenshots.map { .object(["type": .string("appScreenshots"),
                "id": .string($0.id), "attributes": .object($0.attributes)]) } ?? [])
        default:
            if path.hasPrefix("/v1/appAssetLibraryImages/") {
                return try response(.object(["data": memory.image(id: String(path.split(separator: "/").last!))]))
            }
            throw ReleaseToolError.api("Unexpected offline budget route")
        }
    }
    func client() -> ASCAPIClient {
        let key = P256.Signing.PrivateKey()
        return ASCAPIClient(credentials: ASCCredentials(keyId: "test", issuerId: "test", privateKeyPEM: key.pemRepresentation),
            transport: self, maxRetries: 0, sleeper: { _ in })
    }
}

extension DuoPublishingExecutorTests {
    private func budgetCoordinator(_ f: DuoExecutorFixture, service: DuoPublishingService,
                                   queueSleep: @escaping (TimeInterval) -> Void = { _ in }) -> DuoReleaseCoordinator {
        let binding = HandoffFileBinding(path: "/unused-budget-binding", sha256: String(repeating: "a", count: 64))
        let handoff = SelectedReleaseHandoff(schemaVersion: 1, mode: "selected-release-handoff", selectedImport: binding,
            selectionSHA256: binding.sha256, evidenceAcceptance: binding, integrityVerification: binding,
            duoInspection: binding, duoCompatibility: binding, qualificationLimits: .object([:]), sets: [f.set])
        return DuoReleaseCoordinator(handoff: handoff, service: service, journalDirectory: f.directory, queueSleep: queueSleep)
    }

    func testEfficientCompoundWorkflowAndCompletedResumeHaveBoundedRequests() throws {
        let f = try DuoExecutorFixture(compatibility: true); defer { f.clean() }
        let transport = DuoBudgetTransport(f), client = transport.client()
        let service = ASCDuoPublishingService(client: client)
        do {
            let coordinator = budgetCoordinator(f, service: service)
            try coordinator.prepareForReconciliation()
            try coordinator.publish(continuingVerifiedEntry: true)
            try coordinator.prepareForReconciliation(requireComplete: true)
        }
        let clean = client.metrics.snapshot()
        XCTAssertEqual(clean.categories["authenticatedWrite"]?.attempts, 41)
        XCTAssertEqual(clean.categories["binaryUpload"]?.attempts, 10)
        XCTAssertLessThanOrEqual(clean.categories["authenticatedRead"]?.attempts ?? 0, 370)
        XCTAssertLessThanOrEqual(clean.categories["imageDownload"]?.attempts ?? 0, 60,
            "Unchanged survivors must not be redownloaded after each placement mutation")
        try printBudget("DUO_CLEAN_REQUEST_BUDGET", clean)
        let writes = f.service.events.count
        do {
            let coordinator = budgetCoordinator(f, service: service)
            try coordinator.prepareForReconciliation()
            try coordinator.publish(continuingVerifiedEntry: true)
            try coordinator.prepareForReconciliation(requireComplete: true)
        }
        let resumed = client.metrics.snapshot()
        XCTAssertEqual(f.service.events.count, writes)
        XCTAssertLessThanOrEqual(resumed.total.attempts - clean.total.attempts, 66)
        XCTAssertEqual((resumed.categories["imageDownload"]?.attempts ?? 0) - (clean.categories["imageDownload"]?.attempts ?? 0), 20)
        try printBudget("DUO_COMPLETE_RESUME_REQUEST_BUDGET", resumed)
    }

    func testCompoundFallbackAndSameInstanceCompletionStillRejectDrift() throws {
        for missing in [false, true] {
            let f = try DuoExecutorFixture(compatibility: true); defer { f.clean() }
            let transport = DuoBudgetTransport(f); transport.omitIncluded = missing
            let executor = try DuoPublishingExecutor(set: f.set, journalURL: f.journal,
                service: ASCDuoPublishingService(client: transport.client()), sleeper: { _ in })
            try executor.publish(confirmedVersion: "3.0", confirmedSetDigest: f.set.digest())
            f.service.rows.reverse()
            let writes = f.service.events.count
            XCTAssertThrowsError(try executor.publish(confirmedVersion: "3.0", confirmedSetDigest: f.set.digest()))
            XCTAssertEqual(f.service.events.count, writes)
        }
    }

    func testQueuedBackupTamperingStopsBeforeFirstDestructiveMutation() throws {
        let f = try DuoExecutorFixture(compatibility: true); defer { f.clean() }
        let executor = try DuoPublishingExecutor(set: f.set, journalURL: f.journal, service: f.service, sleeper: { _ in })
        try executor.preflight()
        let backup = try XCTUnwrap(f.state().backups.first)
        try Data("changed backup".utf8).write(to: URL(fileURLWithPath: backup.file.path))
        XCTAssertThrowsError(try executor.publish(confirmedVersion: "3.0", confirmedSetDigest: f.set.digest()))
        XCTAssertFalse(f.service.events.contains { $0.hasPrefix("delete:") || $0.hasPrefix("place:") })
    }

    func testReadyQueueRehashesSelectedFilesBeforeFirstDeletion() throws {
        let f = try DuoExecutorFixture(compatibility: true); defer { f.clean() }
        let executor = try DuoPublishingExecutor(set: f.set, journalURL: f.journal, service: f.service, sleeper: { _ in })
        try executor.preflight()
        for position in 1...10 { _ = try executor.submitDesired(position: position) }
        let writes = f.service.events.count
        try Data("tampered after upload".utf8).write(to: URL(fileURLWithPath: f.set.images[0].path))
        XCTAssertThrowsError(try executor.publish(confirmedVersion: "3.0", confirmedSetDigest: f.set.digest()))
        XCTAssertEqual(f.service.events.count, writes)
        XCTAssertEqual(f.service.rows, f.set.reviewedBaseline)
    }

    func testCompoundTargetStateChangeStopsBeforeNextPlacementMutation() throws {
        let f = try DuoExecutorFixture(compatibility: true); defer { f.clean() }
        let transport = DuoBudgetTransport(f)
        f.service.fault = { label, after in if label.hasPrefix("delete:") && after { transport.editable = false } }
        let executor = try DuoPublishingExecutor(set: f.set, journalURL: f.journal,
            service: ASCDuoPublishingService(client: transport.client()), sleeper: { _ in })
        XCTAssertThrowsError(try executor.publish(confirmedVersion: "3.0", confirmedSetDigest: f.set.digest()))
        XCTAssertEqual(f.service.events.filter { $0.hasPrefix("delete:") }.count, 1)
        XCTAssertFalse(f.service.events.contains { $0.hasPrefix("place:") })
    }

    func testFinalNativeProofRejectsSameMetadataChangedPixelsBeforeCompletion() throws {
        let f = try DuoExecutorFixture(compatibility: true); defer { f.clean() }
        let transport = DuoBudgetTransport(f)
        f.service.fault = { label, after in
            if label == "order" && after {
                let pinned = try f.service.makeLegacy()
                f.service.legacyOverride = { pinned }
                f.service.data["image-1"] = f.originalPixels[0]
            }
        }
        let executor = try DuoPublishingExecutor(set: f.set, journalURL: f.journal,
            service: ASCDuoPublishingService(client: transport.client()), sleeper: { _ in })
        XCTAssertThrowsError(try executor.publish(confirmedVersion: "3.0", confirmedSetDigest: f.set.digest()))
        XCTAssertNotEqual(try f.state().phase, "complete")
    }

    func testCoordinatorRetainsSingleWriterLockAndReleasesItOnDeinit() throws {
        let f = try DuoExecutorFixture(); defer { f.clean() }
        var coordinator: DuoReleaseCoordinator? = budgetCoordinator(f, service: f.service)
        try coordinator!.prepareForReconciliation()
        let path = f.directory.appendingPathComponent("duo-en-US-journal.json")
        XCTAssertThrowsError(try DuoPublishingExecutor(set: f.set, journalURL: path, service: f.service))
        coordinator = nil
        XCTAssertNoThrow(try DuoPublishingExecutor(set: f.set, journalURL: path, service: f.service))
    }

    func testScopedCacheHitStillFencesModernDriftDuringLegacyRead() throws {
        for missingAfter in [false, true] {
            let f = try DuoExecutorFixture(compatibility: true); defer { f.clean() }
            let transport = DuoBudgetTransport(f), service = ASCDuoPublishingService(client: transport.client())
            let baseline = try XCTUnwrap(f.set.compatibilityBaseline)
            let expected = baseline.content.enumerated().map { index, content in
                DuoExpectedContent(fileName: content.fileName, byteCount: content.byteCount,
                    width: content.asset.width, height: content.asset.height, pixels: content.pixelSHA256,
                    checksum: baseline.legacy.images[index].checksum, pinnedAsset: content.asset,
                    pinnedLegacyID: baseline.legacy.images[index].id)
            }
            let verifier = DuoCompatibilityVerifier(service: service, localizationID: f.set.localizationID,
                group: "test-duo-group", attempts: 1, sleeper: { _ in })
            let proof = try verifier.prove(graph: baseline.placements, expected: expected, previous: baseline)
            var changed = false
            transport.beforeRead = { path in
                guard !changed && path.hasSuffix("/appScreenshotSets") else { return }
                changed = true; transport.omitIncluded = missingAfter
                var raw = f.service.images["old-image-1"]!.objectValue!, attrs = raw["attributes"]!.objectValue!
                attrs["lastModifiedDate"] = .string("2026-01-02T00:00:00Z")
                raw["attributes"] = .object(attrs); f.service.images["old-image-1"] = .object(raw)
            }
            XCTAssertThrowsError(try verifier.prove(graph: baseline.placements, expected: expected,
                previous: proof, forceNative: false))
            XCTAssertTrue(f.service.events.isEmpty)
        }
    }

    func testNativeCacheRequiresRevisionAndForcedBoundariesAlwaysDownload() throws {
        for missing in ["none", "revision", "checksum"] {
            let f = try DuoExecutorFixture(compatibility: true); defer { f.clean() }
            if missing == "revision" {
                for (id, row) in f.service.images {
                    var value = row.objectValue!, attrs = value["attributes"]!.objectValue!
                    attrs.removeValue(forKey: "lastModifiedDate"); value["attributes"] = .object(attrs)
                    f.service.images[id] = .object(value)
                }
            }
            if missing == "checksum" {
                let original = try XCTUnwrap(f.service.makeLegacy())
                let screenshots = original.screenshots.map { row -> RemoteScreenshot in
                    var attrs = row.attributes; attrs.removeValue(forKey: "sourceFileChecksum")
                    return RemoteScreenshot(id: row.id, fileName: row.fileName, checksum: nil, attributes: attrs)
                }
                f.service.legacyOverride = { RemoteScreenshotSet(id: original.id, displayType: original.displayType, screenshots: screenshots) }
            }
            let baseline = try XCTUnwrap(f.set.compatibilityBaseline)
            let expected = baseline.content.enumerated().map { index, content in
                DuoExpectedContent(fileName: content.fileName, byteCount: content.byteCount,
                    width: content.asset.width, height: content.asset.height, pixels: content.pixelSHA256,
                    checksum: baseline.legacy.images[index].checksum, pinnedAsset: content.asset,
                    pinnedLegacyID: baseline.legacy.images[index].id)
            }
            let transport = DuoBudgetTransport(f)
            let verifier = DuoCompatibilityVerifier(service: ASCDuoPublishingService(client: transport.client()),
                localizationID: f.set.localizationID, group: "test-duo-group", attempts: 1, sleeper: { _ in })
            let initial = try verifier.prove(graph: baseline.placements, expected: expected, previous: missing == "checksum" ? nil : baseline)
            XCTAssertEqual(f.service.downloads, 10)
            _ = try verifier.prove(graph: baseline.placements, expected: expected, previous: initial, forceNative: false)
            XCTAssertEqual(f.service.downloads, missing == "none" ? 10 : 20)
            _ = try verifier.prove(graph: baseline.placements, expected: expected, previous: initial, forceNative: true)
            XCTAssertEqual(f.service.downloads, missing == "none" ? 20 : 30)
        }
    }

    func testCompoundInterruptedDeleteCreateAndOrderResumeWithoutReplay() throws {
        for label in ["delete:old-placement-1", "place:1.png", "order"] {
            let f = try DuoExecutorFixture(compatibility: true); defer { f.clean() }
            let transport = DuoBudgetTransport(f), client = transport.client()
            f.service.fault = { event, after in
                if event == label && after { f.service.fault = nil; throw DuoExecutionFailure.uncertain("lost response") }
            }
            func run() throws {
                let executor = try DuoPublishingExecutor(set: f.set, journalURL: f.journal,
                    service: ASCDuoPublishingService(client: client), sleeper: { _ in })
                try executor.publish(confirmedVersion: "3.0", confirmedSetDigest: f.set.digest())
            }
            XCTAssertThrowsError(try run())
            try run()
            XCTAssertEqual(try f.state().phase, "complete")
            XCTAssertEqual(f.service.events.filter { $0 == label }.count, 1, label)
            XCTAssertTrue(f.originalImagesPreserved())
        }
    }

    func testMissingIncludedImagesHasExplicitFallbackRequestBudget() throws {
        let f = try DuoExecutorFixture(compatibility: true); defer { f.clean() }
        let transport = DuoBudgetTransport(f); transport.omitIncluded = true
        let client = transport.client(), coordinator = budgetCoordinator(f, service: ASCDuoPublishingService(client: client))
        try coordinator.prepareForReconciliation()
        try coordinator.publish(continuingVerifiedEntry: true)
        try coordinator.prepareForReconciliation(requireComplete: true)
        let report = client.metrics.snapshot()
        XCTAssertEqual(report.categories["authenticatedWrite"]?.attempts, 41)
        XCTAssertEqual(report.categories["binaryUpload"]?.attempts, 10)
        XCTAssertLessThanOrEqual(report.categories["authenticatedRead"]?.attempts ?? 0, 820)
        XCTAssertLessThanOrEqual(report.categories["imageDownload"]?.attempts ?? 0, 60)
        try printBudget("DUO_FALLBACK_REQUEST_BUDGET", report)
    }

    func testSingleImageRetryOnlyUsesAffectedScopeAndHasBoundedRequests() throws {
        let f = try DuoExecutorFixture(compatibility: true); defer { f.clean() }
        let transport = DuoBudgetTransport(f)
        let path = f.directory.appendingPathComponent("duo-en-US-journal.json")
        f.service.holdProcessingNames = ["6.png"]
        do {
            let setup = try DuoPublishingExecutor(set: f.set, journalURL: path,
                service: ASCDuoPublishingService(client: transport.client()), sleeper: { _ in })
            _ = try setup.prepareQueuedStaging(confirmedVersion: "3.0", confirmedSetDigest: f.set.digest())
            for position in 1...10 { _ = try setup.submitDesired(position: position) }
        }
        f.service.holdProcessingNames = []
        let events = f.service.events.count, client = transport.client()
        let coordinator = budgetCoordinator(f, service: ASCDuoPublishingService(client: client))
        try coordinator.prepareForSingleImageRetry(locale: "en-US")
        let result = try coordinator.retryImage(locale: "en-US", position: 6,
            originalImageID: "image-6", sourceSHA256: f.set.images[5].sha256)
        XCTAssertEqual(result.state, "adopted")
        XCTAssertEqual(result.imageID, "image-11")
        XCTAssertEqual(f.service.rows, f.set.reviewedBaseline)
        XCTAssertEqual(f.service.images["image-6"]?["attributes"]?["state"], .string("UPLOAD_COMPLETE"))
        XCTAssertEqual(f.service.events.count - events, 3)
        let report = client.metrics.snapshot()
        XCTAssertEqual(report.categories["authenticatedWrite"]?.attempts, 2)
        XCTAssertEqual(report.categories["binaryUpload"]?.attempts, 1)
        XCTAssertLessThanOrEqual(report.categories["authenticatedRead"]?.attempts ?? 0, 130)
        XCTAssertLessThanOrEqual(report.categories["imageDownload"]?.attempts ?? 0, 25)
        try printBudget("DUO_ONE_IMAGE_RETRY_REQUEST_BUDGET", report)
    }

    func testNarrowRetryNeverReadsCompletedOtherLocaleAndRejectsItsInvalidJournal() throws {
        let first = try DuoExecutorFixture(compatibility: true, namespace: "a-"),
            second = try DuoExecutorFixture(compatibility: true, namespace: "b-", locale: "fr-FR")
        defer { first.clean(); second.clean() }
        first.service.holdProcessingNames = ["6.png"]
        do {
            let setup = try DuoPublishingExecutor(set: first.set, journalURL: first.journal, service: first.service, sleeper: { _ in })
            _ = try setup.prepareQueuedStaging(confirmedVersion: "3.0", confirmedSetDigest: first.set.digest())
            for position in 1...10 { _ = try setup.submitDesired(position: position) }
        }
        try second.run()
        let firstPath = first.directory.appendingPathComponent("duo-en-US-journal.json")
        let secondPath = first.directory.appendingPathComponent("duo-fr-FR-journal.json")
        try FileManager.default.copyItem(at: first.journal, to: firstPath)
        try FileManager.default.copyItem(at: second.journal, to: secondPath)
        first.service.holdProcessingNames = []
        let otherWrites = second.service.events, otherDownloads = second.service.downloads
        second.service.beforeImageRead = { _ in throw ReleaseToolError.api("Unaffected image must not be read by isolated retry") }
        second.service.beforePlacementRead = { throw ReleaseToolError.api("Unaffected placement must not be read by isolated retry") }
        second.service.legacyOverride = { throw ReleaseToolError.api("Unaffected legacy view must not be read by isolated retry") }
        do {
            let coordinator = queuedCoordinator([first, second])
            try coordinator.prepareForSingleImageRetry(locale: "en-US")
            let result = try coordinator.retryImage(locale: "en-US", position: 6,
                originalImageID: "a-image-6", sourceSHA256: first.set.images[5].sha256)
            XCTAssertEqual(result.state, "adopted")
            XCTAssertEqual(second.service.events, otherWrites)
            XCTAssertEqual(second.service.downloads, otherDownloads)
        }
        var changed = try ManifestBuilder.decode(DuoExecutionJournal.self, at: secondPath)
        changed.schemaVersion = 99; try FileIO.writeJSON(changed, to: secondPath)
        let coordinator = queuedCoordinator([first, second])
        XCTAssertThrowsError(try coordinator.prepareForSingleImageRetry(locale: "en-US"))
    }

    func testQueuedProcessingPollsStayWithinTheAffectedImageBudget() throws {
        let f = try DuoExecutorFixture(compatibility: true); defer { f.clean() }
        f.service.holdProcessingNames = ["6.png"]
        let transport = DuoBudgetTransport(f), client = transport.client()
        var sleeps = 0
        let coordinator = budgetCoordinator(f, service: ASCDuoPublishingService(client: client), queueSleep: { _ in
            sleeps += 1
            if sleeps == 2 { try! f.service.finishProcessing() }
            XCTAssertLessThan(sleeps, 4)
        })
        try coordinator.prepareForReconciliation()
        try coordinator.publish(continuingVerifiedEntry: true)
        try coordinator.prepareForReconciliation(requireComplete: true)
        let report = client.metrics.snapshot()
        XCTAssertEqual(report.categories["authenticatedWrite"]?.attempts, 41)
        XCTAssertEqual(report.categories["binaryUpload"]?.attempts, 10)
        XCTAssertLessThanOrEqual(report.categories["authenticatedRead"]?.attempts ?? 0, 380)
        XCTAssertEqual(report.categories["imageDownload"]?.attempts, 60)
        try printBudget("DUO_DELAYED_PROCESSING_REQUEST_BUDGET", report)
    }
}

private final class TwoLocaleDuoService: DuoPublishingService {
    let first: DuoMemoryService, second: DuoMemoryService
    var writes = 0
    init(first: DuoMemoryService, second: DuoMemoryService) { self.first = first; self.second = second }
    func verifyEditableTarget(_ set: DuoPublishSet) throws {}
    func placements(localizationID: String, group: String) throws -> [DuoRemotePlacement] {
        try (localizationID == "target-fr" ? second : first).placements(localizationID: localizationID, group: group)
    }
    func legacyDuoSet(localizationID: String) throws -> RemoteScreenshotSet? {
        try (localizationID == "target-fr" ? second : first).legacyDuoSet(localizationID: localizationID)
    }
    func image(id: String) throws -> JSONValue { try first.image(id: id) }
    func download(_ url: URL) throws -> Data { try first.download(url) }
    func send(_ request: DuoAssetLibraryRequest) throws -> JSONValue? { writes += 1; throw ReleaseToolError.validation("Unexpected multi-locale mutation") }
    func upload(_ operation: UploadOperation, bytes: Data) throws { writes += 1; throw ReleaseToolError.validation("Unexpected multi-locale upload") }
}

private final class QueueDuoService: DuoPublishingService {
    let fixtures: [DuoExecutorFixture]
    init(_ fixtures: [DuoExecutorFixture]) { self.fixtures = fixtures }
    private func forImage(_ id: String) throws -> DuoMemoryService {
        try XCTUnwrap(fixtures.first { $0.service.images[id] != nil }?.service)
    }
    private func forLocalization(_ id: String) throws -> DuoMemoryService {
        try XCTUnwrap(fixtures.first { $0.set.localizationID == id }?.service)
    }
    func verifyEditableTarget(_ set: DuoPublishSet) throws {}
    func image(id: String) throws -> JSONValue { try forImage(id).image(id: id) }
    func placements(localizationID: String, group: String) throws -> [DuoRemotePlacement] {
        try forLocalization(localizationID).placements(localizationID: localizationID, group: group)
    }
    func legacyDuoSet(localizationID: String) throws -> RemoteScreenshotSet? {
        try forLocalization(localizationID).legacyDuoSet(localizationID: localizationID)
    }
    func download(_ url: URL) throws -> Data { try forImage(url.deletingPathExtension().lastPathComponent).download(url) }
    func upload(_ operation: UploadOperation, bytes: Data) throws {
        try forImage(URL(string: operation.url)!.lastPathComponent).upload(operation, bytes: bytes)
    }
    func send(_ request: DuoAssetLibraryRequest) throws -> JSONValue? {
        let relations = request.body["data"]?["relationships"]
        let owner: DuoMemoryService
        if request.path == "/v1/appAssetLibraryImages" {
            let library = relations?["assetLibrary"]?["data"]?["id"]?.stringValue
            owner = try XCTUnwrap(fixtures.first { $0.set.assetLibraryID == library }?.service)
        } else if let locale = relations?["appStoreVersionLocalization"]?["data"]?["id"]?.stringValue {
            owner = try forLocalization(locale)
        } else if request.method == "DELETE" {
            let id = String(request.path.split(separator: "/").last!)
            owner = try XCTUnwrap(fixtures.first { $0.service.rows.contains { $0.id == id } }?.service)
        } else { owner = try forImage(String(request.path.split(separator: "/").last!)) }
        return try owner.send(request)
    }
}

extension DuoPublishingExecutorTests {
    private func queuedCoordinator(_ fixtures: [DuoExecutorFixture], window: Int = 3, idle: Int = 2,
                                   sleep: @escaping (TimeInterval) -> Void = { _ in }) -> DuoReleaseCoordinator {
        let binding = HandoffFileBinding(path: "/unused-test-binding", sha256: String(repeating: "a", count: 64))
        let handoff = SelectedReleaseHandoff(schemaVersion: 1, mode: "selected-release-handoff", selectedImport: binding,
            selectionSHA256: binding.sha256, evidenceAcceptance: binding, integrityVerification: binding,
            duoInspection: binding, duoCompatibility: binding, qualificationLimits: .object([:]), sets: fixtures.map(\.set))
        return DuoReleaseCoordinator(handoff: handoff, service: QueueDuoService(fixtures), journalDirectory: fixtures[0].directory,
            processingWindow: window, idlePollLimit: idle, queueSleep: sleep)
    }
    private func queuedState(_ fixture: DuoExecutorFixture, in root: DuoExecutorFixture) throws -> DuoExecutionJournal {
        try ManifestBuilder.decode(DuoExecutionJournal.self, at: root.directory.appendingPathComponent("duo-\(fixture.set.locale)-journal.json"))
    }
    func testQueuedSlowFirstLocaleDoesNotBlockReadyLocaleAndResumeReusesAllIDs() throws {
        let first = try DuoExecutorFixture(compatibility: true, namespace: "a-"), second = try DuoExecutorFixture(compatibility: true, namespace: "b-", locale: "fr-FR")
        defer { first.clean(); second.clean() }
        first.service.holdProcessingNames = ["1.png"]
        XCTAssertThrowsError(try queuedCoordinator([first, second]).publish())
        let before = try queuedState(first, in: first), secondState = try queuedState(second, in: first)
        XCTAssertEqual(before.phase, "preparing"); XCTAssertEqual(secondState.phase, "complete")
        XCTAssertEqual(first.service.rows, first.set.reviewedBaseline)
        XCTAssertEqual(first.service.events.filter { $0.hasPrefix("reserve:") }.count, 10)
        XCTAssertEqual(second.service.events.filter { $0.hasPrefix("reserve:") }.count, 10)
        XCTAssertEqual(before.entries.last { $0.key == "desired:1:commit" }?.status, "responseKnown")
        let pendingID = before.entries.last { $0.key == "desired:1:reserve" }?.resourceID
        let writes = first.service.events.count + second.service.events.count
        try queuedCoordinator([first, second]).preflight()
        XCTAssertEqual(first.service.events.count + second.service.events.count, writes)
        try first.service.finishProcessing()
        try queuedCoordinator([first, second]).publish()
        let after = try queuedState(first, in: first)
        XCTAssertEqual(after.phase, "complete")
        XCTAssertEqual(after.entries.last { $0.key == "desired:1:reserve" }?.resourceID, pendingID)
        XCTAssertEqual(first.service.events.filter { $0.hasPrefix("reserve:") }.count, 10)
        XCTAssertEqual(second.service.events.filter { $0.hasPrefix("reserve:") }.count, 10)
        XCTAssertTrue(first.originalImagesPreserved()); XCTAssertTrue(second.originalImagesPreserved())
    }
    func testQueuedWindowCountsExistingPendingAndRoundRobinIsFairOnRestart() throws {
        let first = try DuoExecutorFixture(namespace: "a-"), second = try DuoExecutorFixture(namespace: "b-", locale: "fr-FR")
        defer { first.clean(); second.clean() }
        first.service.holdProcessingNames = Set((1...10).map { "\($0).png" }); second.service.holdProcessingNames = first.service.holdProcessingNames
        var sleeps: [TimeInterval] = []
        XCTAssertThrowsError(try queuedCoordinator([first, second], sleep: { sleeps.append($0) }).publish())
        XCTAssertEqual(first.service.events.filter { $0.hasPrefix("reserve:") }.count, 2)
        XCTAssertEqual(second.service.events.filter { $0.hasPrefix("reserve:") }.count, 1)
        XCTAssertTrue(sleeps.allSatisfy { $0 == 15 }); XCTAssertEqual(sleeps.count, 2)
        let events = first.service.events + second.service.events
        XCTAssertFalse(events.contains { $0.hasPrefix("delete:") })
        XCTAssertThrowsError(try queuedCoordinator([first, second]).publish())
        XCTAssertEqual(first.service.events + second.service.events, events)
        try first.service.finishProcessing(); try second.service.finishProcessing()
        try queuedCoordinator([first, second]).publish()
        XCTAssertEqual(try queuedState(first, in: first).phase, "complete")
        XCTAssertEqual(try queuedState(second, in: first).phase, "complete")
    }
    func testQueuedUnknownReserveUploadOrCommitStopsAllOtherLocalesWithoutReplay() throws {
        for prefix in ["reserve:", "upload:", "commit:"] {
            let first = try DuoExecutorFixture(namespace: "a-"), second = try DuoExecutorFixture(namespace: "b-", locale: "fr-FR")
            defer { first.clean(); second.clean() }
            first.service.holdProcessingNames = ["1.png"]
            first.service.fault = { label, after in
                if label.hasPrefix(prefix) && after { first.service.fault = nil; throw DuoExecutionFailure.uncertain("lost response") }
            }
            XCTAssertThrowsError(try queuedCoordinator([first, second]).publish())
            XCTAssertTrue(second.service.events.isEmpty)
            let events = first.service.events
            XCTAssertThrowsError(try queuedCoordinator([first, second]).preflight())
            XCTAssertThrowsError(try queuedCoordinator([first, second]).publish())
            XCTAssertEqual(first.service.events, events); XCTAssertTrue(second.service.events.isEmpty)
            XCTAssertEqual(first.service.rows, first.set.reviewedBaseline)
        }
    }
    func testQueuedRateLimitedReadStopsWithoutRepeatingOrExpandingWrites() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        fixture.service.holdProcessingNames = ["1.png"]
        var pendingReads = 0
        fixture.service.beforeImageRead = { id in
            if id == "image-1", fixture.service.images[id]?["attributes"]?["state"] == .string("UPLOAD_COMPLETE") {
                pendingReads += 1
                if pendingReads == 2 { throw DuoExecutionFailure.uncertain("HTTP 429 read quota exhausted") }
            }
        }
        XCTAssertThrowsError(try queuedCoordinator([fixture], window: 1).publish())
        XCTAssertEqual(fixture.service.events.filter { $0.hasPrefix("reserve:") }.count, 1)
        XCTAssertFalse(fixture.service.events.contains { $0.hasPrefix("delete:") })
        let events = fixture.service.events
        fixture.service.beforeImageRead = { _ in throw DuoExecutionFailure.uncertain("HTTP 429") }
        XCTAssertThrowsError(try queuedCoordinator([fixture]).preflight())
        XCTAssertEqual(fixture.service.events, events)
    }
    func testQueuedUnexpectedCommittedStateDoesNotEnterPerImageWait() throws {
        for state in ["AWAITING_UPLOAD", "UNKNOWN", "FAILED"] {
            let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
            fixture.service.holdProcessingNames = ["1.png"]
            do {
                let executor = try DuoPublishingExecutor(set: fixture.set, journalURL: fixture.journal, service: fixture.service,
                    sleeper: { _ in XCTFail("Queue inspection must not enter a per-image wait") })
                try executor.prepareQueuedStaging(confirmedVersion: fixture.set.version, confirmedSetDigest: fixture.set.digest())
                _ = try executor.submitDesired(position: 1)
                var row = fixture.service.images["image-1"]!.objectValue!, attrs = row["attributes"]!.objectValue!
                attrs["state"] = .string(state); row["attributes"] = .object(attrs); fixture.service.images["image-1"] = .object(row)
                XCTAssertThrowsError(try executor.pollDesiredReadiness())
            }
            XCTAssertFalse(fixture.service.events.contains { $0.hasPrefix("delete:") })
        }
    }
    func testQueuedReadyCacheCannotAuthorizeChangedSpecificationOrForeignGraph() throws {
        for defect in ["spec", "graph", "state"] {
            let fixture = try DuoExecutorFixture(compatibility: true); defer { fixture.clean() }
            fixture.service.holdProcessingNames = ["10.png"]
            var changed = false
            let queue = queuedCoordinator([fixture], sleep: { _ in
                guard !changed else { return }; changed = true
                try! fixture.service.finishProcessing()
                if defect != "graph" {
                    var row = fixture.service.images["image-1"]!.objectValue!, attrs = row["attributes"]!.objectValue!
                    if defect == "spec" { attrs["specId"] = .string("foreign-spec") }
                    else { attrs["state"] = .string("UPLOAD_COMPLETE") }
                    row["attributes"] = .object(attrs); fixture.service.images["image-1"] = .object(row)
                } else { fixture.service.rows.reverse() }
            })
            XCTAssertThrowsError(try queue.publish())
            XCTAssertFalse(fixture.service.events.contains { $0.hasPrefix("delete:") })
        }
    }
}

extension DuoPublishingExecutorTests {
    func testQueuedProcessedImageCannotAdmitMissingUploadDependency() throws {
        let fixture = try DuoExecutorFixture(); defer { fixture.clean() }
        fixture.service.holdProcessingNames = ["1.png"]
        do {
            let executor = try DuoPublishingExecutor(set: fixture.set, journalURL: fixture.journal, service: fixture.service)
            try executor.prepareQueuedStaging(confirmedVersion: fixture.set.version, confirmedSetDigest: fixture.set.digest())
            _ = try executor.submitDesired(position: 1)
        }
        try fixture.service.finishProcessing()
        var state = try fixture.state()
        state.entries.removeAll { $0.key == "desired:1:upload" }
        try JSONEncoder().encode(state).write(to: fixture.journal)
        let writes = fixture.service.events.count
        let executor = try DuoPublishingExecutor(set: fixture.set, journalURL: fixture.journal, service: fixture.service)
        XCTAssertThrowsError(try executor.preflight(allowKnownProcessing: true))
        XCTAssertEqual(fixture.service.events.count, writes)
    }
}

extension DuoPublishingExecutorTests {
    func testRateCooldownMidPlacementPreservesCheckpointAndResumesWithoutReplay() throws {
        let fixture = try DuoExecutorFixture(compatibility: true); defer { fixture.clean() }
        var stopped = false
        fixture.service.beforeImageRead = { id in
            if fixture.service.rows.count < 10 && id == "old-image-2" && !stopped {
                stopped = true
                throw ASCRateLimitCooldown(method: "GET", path: "/v1/appAssetLibraryImages/old-image-2", notBefore: Date().addingTimeInterval(120), serverSpecified: true)
            }
        }
        XCTAssertThrowsError(try fixture.run()) { XCTAssertTrue($0 is ASCRateLimitCooldown) }
        let checkpoint = try fixture.state()
        XCTAssertEqual(checkpoint.phase, "switching")
        XCTAssertEqual(fixture.service.rows.count, 9)
        XCTAssertEqual(checkpoint.entries.last?.status, "verified")
        XCTAssertFalse(checkpoint.entries.contains { $0.status == "uncertain" })
        try fixture.run()
        XCTAssertEqual(try fixture.state().phase, "complete")
        XCTAssertEqual(fixture.service.events.filter { $0 == "delete:old-placement-1" }.count, 1)
        XCTAssertEqual(fixture.service.events.filter { $0.hasPrefix("reserve:") }.count, 10)
        XCTAssertTrue(fixture.originalImagesPreserved())
    }
}

extension DuoPublishingExecutorTests {
    private func singleRetryFixture() throws -> DuoExecutorFixture {
        let f = try DuoExecutorFixture(compatibility: true)
        f.service.holdProcessingNames = ["6.png"]
        do {
            let e = try DuoPublishingExecutor(set: f.set, journalURL: f.journal, service: f.service, sleeper: { _ in })
            try e.prepareQueuedStaging(confirmedVersion: f.set.version, confirmedSetDigest: f.set.digest())
            for p in 1...10 { _ = try e.submitDesired(position: p) }
        }
        f.service.holdProcessingNames.removeAll()
        return f
    }
    private func retry(_ f: DuoExecutorFixture, writer: ((Data, URL) throws -> Void)? = nil) throws -> DuoSingleImageRetryResult {
        let e = try DuoPublishingExecutor(set: f.set, journalURL: f.journal, service: f.service,
            pollAttempts: 2, sleeper: { _ in }, journalWriter: writer)
        return try e.retrySingleImage(position: 6, originalImageID: "image-6", confirmedSourceSHA256: f.set.images[5].sha256)
    }
    func testSingleRetryAdoptsExactCandidateAndReusesItThroughCompletedResume() throws {
        let f = try singleRetryFixture(); defer { f.clean() }
        let old = f.service.images["image-6"], originalEntries = try f.state().entries
        let result = try retry(f)
        XCTAssertEqual(result.state, "adopted"); XCTAssertEqual(result.imageID, "image-11")
        XCTAssertEqual(try f.state().schemaVersion, 2)
        XCTAssertEqual(try f.state().entries, originalEntries)
        let sidecar = DuoExecutionJournal.retryURL(f.journal, position: 6)
        let sealed = try Data(contentsOf: sidecar)
        XCTAssertEqual(try retry(f).imageID, "image-11")
        try f.run(); try f.run()
        XCTAssertEqual(try Data(contentsOf: sidecar), sealed)
        XCTAssertEqual(f.service.events.filter { $0.hasPrefix("reserve:") }.count, 11)
        XCTAssertTrue(f.service.rows.contains { $0.imageID == "image-11" })
        XCTAssertFalse(f.service.rows.contains { $0.imageID == "image-6" })
        XCTAssertEqual(f.service.images["image-6"], old)
        XCTAssertTrue(f.originalImagesPreserved())
        XCTAssertEqual(try DuoJournalEvidence.desiredImageID(set: f.set, journalURL: f.journal, position: 6), "image-11")
    }
    func testSingleRetryPrefersOriginalBeforeReservationAndBeforeUpload() throws {
        for late in [false, true] {
            let f = try singleRetryFixture(); defer { f.clean() }
            let uploads = f.service.events.filter { $0.hasPrefix("upload:") }.count
            if late {
                f.service.fault = { label, after in
                    if label == "reserve:6.png" && after { f.service.fault = nil; try f.service.finishProcessing() }
                }
            } else { try f.service.finishProcessing() }
            XCTAssertEqual(try retry(f).state, "original")
            XCTAssertEqual(f.service.events.filter { $0.hasPrefix("upload:") }.count, uploads)
            try f.run()
            XCTAssertTrue(f.service.rows.contains { $0.imageID == "image-6" })
        }
    }
    func testSingleRetryUnknownReserveAndUploadNeverReplayOrPublish() throws {
        for prefix in ["reserve:", "upload:"] {
            let f = try singleRetryFixture(); defer { f.clean() }
            f.service.fault = { label, after in
                if label.hasPrefix(prefix) && after { f.service.fault = nil; throw DuoExecutionFailure.uncertain("lost retry response") }
            }
            XCTAssertThrowsError(try retry(f))
            let events = f.service.events
            XCTAssertThrowsError(try retry(f)); XCTAssertThrowsError(try f.run())
            XCTAssertEqual(f.service.events, events)
            XCTAssertEqual(f.service.rows, f.set.reviewedBaseline)
        }
    }
    func testSingleRetryLostCommitResponseUsesExactReadbackWithoutPATCHReplay() throws {
        let f = try singleRetryFixture(); defer { f.clean() }
        f.service.fault = { label, after in
            if label == "commit:image-11" && after { f.service.fault = nil; throw DuoExecutionFailure.uncertain("lost retry commit") }
        }
        XCTAssertThrowsError(try retry(f))
        XCTAssertEqual(try retry(f).state, "adopted")
        XCTAssertEqual(f.service.events.filter { $0 == "commit:image-11" }.count, 1)
        XCTAssertEqual(f.service.events.filter { $0.hasPrefix("reserve:") }.count, 11)
    }
    func testSingleRetryPendingCandidateDoesNotCreateSecondAttemptAndAllowsLateOriginal() throws {
        let f = try singleRetryFixture(); defer { f.clean() }
        f.service.holdProcessingNames = ["6.png"]
        XCTAssertEqual(try retry(f).state, "processing")
        let events = f.service.events
        XCTAssertEqual(try retry(f).state, "processing"); XCTAssertEqual(f.service.events, events)
        XCTAssertThrowsError(try f.run())
        try f.service.finishProcessing()
        XCTAssertEqual(try retry(f).state, "adopted")
        XCTAssertEqual(f.service.events, events)
    }
    func testSingleRetryWrongPixelsSpecificationAndFailureNeverAdoptOrDelete() throws {
        for defect in ["pixels", "spec", "failed"] {
            let f = try singleRetryFixture(); defer { f.clean() }
            f.service.wrongSpecification = defect == "spec"; f.service.failProcessing = defect == "failed"
            if defect == "pixels" {
                f.service.fault = { label, after in
                    if label == "commit:image-11" && after { f.service.data["image-11"] = f.service.data["old-image-6"] }
                }
            }
            XCTAssertThrowsError(try retry(f))
            XCTAssertEqual(try f.state().singleImageRetry?.state, "pending")
            XCTAssertEqual(f.service.rows, f.set.reviewedBaseline)
            XCTAssertFalse(f.service.events.contains { $0.hasPrefix("delete:") })
        }
    }
    func testSingleRetryAdoptionPersistenceFailureResumesWithoutNewUpload() throws {
        let f = try singleRetryFixture(); defer { f.clean() }
        let writer: (Data, URL) throws -> Void = { data, url in
            let value = try JSONDecoder().decode(DuoExecutionJournal.self, from: data)
            if value.singleImageRetry?.state == "adopted" { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        }
        XCTAssertThrowsError(try retry(f, writer: writer))
        XCTAssertEqual(try f.state().singleImageRetry?.state, "pending")
        let events = f.service.events
        XCTAssertEqual(try retry(f).state, "adopted"); XCTAssertEqual(f.service.events, events)
    }
    func testSingleRetryFenceAndSealedSidecarRejectInvalidStateBeforeHTTP() throws {
        let f = try singleRetryFixture(); defer { f.clean() }
        _ = try retry(f)
        let events = f.service.events
        let sidecar = DuoExecutionJournal.retryURL(f.journal, position: 6)
        var bytes = try Data(contentsOf: sidecar); bytes.append(32); try bytes.write(to: sidecar)
        XCTAssertThrowsError(try f.run()); XCTAssertEqual(f.service.events, events)
        var journal = try f.state(); journal.singleImageRetry = nil
        try FileIO.writeJSON(journal, to: f.journal)
        XCTAssertThrowsError(try f.run()); XCTAssertEqual(f.service.events, events)
    }
    func testSingleRetryExactScopeAndFencePersistencePrecedeAnyNewMutation() throws {
        let f = try singleRetryFixture(); defer { f.clean() }
        let events = f.service.events
        do {
            let e = try DuoPublishingExecutor(set: f.set, journalURL: f.journal, service: f.service)
            XCTAssertThrowsError(try e.retrySingleImage(position: 5, originalImageID: "image-6", confirmedSourceSHA256: f.set.images[5].sha256))
            XCTAssertThrowsError(try e.retrySingleImage(position: 6, originalImageID: "foreign", confirmedSourceSHA256: f.set.images[5].sha256))
            XCTAssertThrowsError(try e.retrySingleImage(position: 6, originalImageID: "image-6", confirmedSourceSHA256: String(repeating: "0", count: 64)))
        }
        let writer: (Data, URL) throws -> Void = { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        XCTAssertThrowsError(try retry(f, writer: writer))
        XCTAssertEqual(f.service.events, events)
    }
}

extension DuoPublishingExecutorTests {
    func testSingleRetryKnownRejectionDoesNotReplayReservationOrCommit() throws {
        for prefix in ["reserve:", "commit:"] {
            let f = try singleRetryFixture(); defer { f.clean() }
            f.service.fault = { label, after in
                if label.hasPrefix(prefix) && !after { f.service.fault = nil; throw DuoExecutionFailure.rejected("known retry rejection") }
            }
            XCTAssertThrowsError(try retry(f)); let events = f.service.events
            XCTAssertThrowsError(try retry(f)); XCTAssertEqual(f.service.events, events)
            XCTAssertEqual(f.service.rows, f.set.reviewedBaseline)
        }
    }
    func testSingleRetryMissingOrLostStartedAttemptNeverCreatesAnotherReservation() throws {
        for missing in [false, true] {
            let f = try singleRetryFixture(); defer { f.clean() }
            f.service.holdProcessingNames = ["6.png"]
            _ = try retry(f); let events = f.service.events
            let sidecar = DuoExecutionJournal.retryURL(f.journal, position: 6)
            if missing { try FileManager.default.removeItem(at: sidecar) }
            else {
                var state = try ManifestBuilder.decode(DuoExecutionJournal.self, at: sidecar)
                state.entries = []; try FileIO.writeJSON(state, to: sidecar)
            }
            XCTAssertThrowsError(try retry(f)); XCTAssertEqual(f.service.events, events)
        }
    }
    func testSingleRetryAdoptedBindingSurvivesRollbackAndReusesItsCandidate() throws {
        let f = try singleRetryFixture(); defer { f.clean() }; _ = try retry(f)
        f.service.fault = { label, after in
            if label == "place:3.png" && !after { f.service.fault = nil; throw DuoExecutionFailure.rejected("placement rejected") }
        }
        XCTAssertThrowsError(try f.run()); XCTAssertEqual(try f.state().phase, "rolledBack")
        let candidates = f.service.events.filter { $0 == "reserve:6.png" }.count
        try f.run(); XCTAssertEqual(try f.state().phase, "complete")
        XCTAssertEqual(f.service.events.filter { $0 == "reserve:6.png" }.count, candidates)
        XCTAssertTrue(f.service.rows.contains { $0.imageID == "image-11" })
    }
    func testSingleRetryOtherLocaleRollbackBlocksBeforeAnyHTTPOrMutation() throws {
        let first = try DuoExecutorFixture(namespace: "a-"), second = try DuoExecutorFixture(namespace: "b-", locale: "fr-FR")
        defer { first.clean(); second.clean() }
        let value = queuedCoordinator([first, second]); try value.preflight()
        let path = first.directory.appendingPathComponent("duo-fr-FR-journal.json")
        var state = try ManifestBuilder.decode(DuoExecutionJournal.self, at: path)
        state.phase = "rollingBack"; try FileIO.writeJSON(state, to: path)
        XCTAssertThrowsError(try value.requireSingleRetryCheckpoint(locale: "en-US"))
        XCTAssertTrue(first.service.events.isEmpty && second.service.events.isEmpty)
    }
}
