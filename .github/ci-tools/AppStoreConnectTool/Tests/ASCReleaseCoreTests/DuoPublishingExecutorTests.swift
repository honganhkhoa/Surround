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

    init(baselineCount: Int = 10, compatibility: Bool = false) throws {
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
        service = DuoMemoryService()
        for position in 1...10 {
            let inner = (2...7).contains(position), size = inner ? sizes[2] : sizes[0]
            let data = inner ? newInner : newOuter, file = directory.appendingPathComponent("\(position).png")
            try data.write(to: file)
            desired.append(DuoPublishImage(position: position, path: file.path, fileName: file.lastPathComponent, byteCount: data.count,
                sha256: FileIO.sha256(data), pixelWidth: size.0, pixelHeight: size.1, specID: inner ? "spec-2" : "spec-0",
                origin: .object(["kind": .string("synthetic-unit-fixture")])) )
            if position <= baselineCount {
                let old = inner ? oldInner : oldOuter, id = "old-image-\(position)"
                service.data[id] = old; originals.append(old)
                service.images[id] = Self.resource(id: id, name: "old-\(position).png", data: old, size: size, spec: inner ? "spec-2" : "spec-0", state: "APPROVED")
                baseline.append(DuoRemotePlacement(id: "old-placement-\(position)", imageID: id, group: "test-duo-group", state: "ACTIVE"))
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
        set = DuoPublishSet(version: "3.0", bundleID: "com.example.App", appID: "app", assetLibraryID: "library", versionID: "target3",
            localizationID: "target3-locale", locale: "en-US", sourceManifestSHA256: String(repeating: "a", count: 64),
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
    func placements(localizationID: String, group: String) throws -> [DuoRemotePlacement] { rows }
    func image(id: String) throws -> JSONValue {
        var row = try XCTUnwrap(images[id]).objectValue!
        if wrongOriginalResponseID && id.hasPrefix("old-image-") { row["id"] = .string("another-resource") }
        return .object(row)
    }
    func download(_ url: URL) throws -> Data { downloads += 1; return try XCTUnwrap(data[url.deletingPathExtension().lastPathComponent]) }
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
            let label = "reserve:" + name; try begin(label); nextImage += 1; let id = "image-\(nextImage)"
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
            try begin(label); XCTAssertLessThan(rows.count, 10); nextPlacement += 1; let id = "placement-\(nextPlacement)"
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
