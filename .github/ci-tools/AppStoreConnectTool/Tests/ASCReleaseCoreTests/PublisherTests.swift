import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ASCReleaseCore

final class PublisherTests: XCTestCase {
    func testPublisherUploadsCommitsOrdersAndPatchesMetadata() throws {
        try withTemporaryDirectory { directory in
            let desiredData = try opaquePNG(width: 2, height: 3, byte: 0x44)
            let oldBackupData = try opaquePNG(width: 2, height: 3, byte: 0x22)
            let fixture = try existingVersionFixture(
                directory: directory,
                desiredData: desiredData,
                oldBackupData: oldBackupData
            )
            var setReadCount = 0
            let transport = PublisherMockTransport { request in
                let method = request.httpMethod ?? ""
                let path = request.url?.path ?? ""
                switch (method, path) {
                case ("GET", "/v1/appStoreVersionLocalizations/loc/appScreenshotSets"):
                    return .json(.object(["data": .array([self.setResource(id: "set")])]))
                case ("GET", "/v1/appScreenshotSets/set/appScreenshots"):
                    setReadCount += 1
                    let resource = setReadCount <= 2
                        ? fixture.oldRawScreenshot
                        : fixture.newRawScreenshot
                    return .json(.object(["data": .array([resource])]))
                case ("GET", "/2x3.png"):
                    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                    return TransportResponse(data: oldBackupData, statusCode: 200)
                case ("DELETE", "/v1/appScreenshots/old"):
                    return TransportResponse(data: Data(), statusCode: 204)
                case ("POST", "/v1/appScreenshots"):
                    let body = try self.body(request)
                    XCTAssertEqual(
                        body["data"]?["relationships"]?["appScreenshotSet"]?["data"]?["id"]?.stringValue,
                        "set"
                    )
                    return .json(self.reservation(id: "new", byteCount: desiredData.count))
                case ("PUT", "/chunk"):
                    XCTAssertEqual(request.httpBody, desiredData)
                    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                    return TransportResponse(data: Data(), statusCode: 200)
                case ("PATCH", "/v1/appScreenshots/new"):
                    let body = try self.body(request)
                    XCTAssertEqual(
                        body["data"]?["attributes"]?["sourceFileChecksum"]?.stringValue,
                        FileIO.md5(desiredData)
                    )
                    return .json(.object(["data": fixture.newRawScreenshot]))
                case ("GET", "/v1/appScreenshots/new"):
                    return .json(.object(["data": fixture.newRawScreenshot]))
                case ("PATCH", "/v1/appScreenshotSets/set/relationships/appScreenshots"):
                    let body = try self.body(request)
                    XCTAssertEqual(body["data"]?.arrayValue?.first?["id"]?.stringValue, "new")
                    return TransportResponse(data: Data(), statusCode: 204)
                case ("PATCH", "/v1/appStoreVersionLocalizations/loc"):
                    return .json(.object(["data": .object(["type": .string("appStoreVersionLocalizations"), "id": .string("loc")])]))
                default:
                    XCTFail("Unexpected request \(method) \(request.url?.absoluteString ?? path)")
                    return TransportResponse(data: Data(), statusCode: 500)
                }
            }
            let provider = SnapshotSequence([fixture.baseline, fixture.baseline, fixture.final])
            let publisher = try Publisher(
                client: makeClient(transport),
                journalURL: directory.appendingPathComponent("journal.json"),
                manifest: fixture.manifest,
                snapshotProvider: provider.next,
                sleeper: { _ in }
            )
            try publisher.publish(manifest: fixture.manifest, confirmedVersion: "2.1")
            XCTAssertTrue(transport.requests.contains {
                $0.httpMethod == "DELETE" && $0.url?.path == "/v1/appScreenshots/old"
            })
            XCTAssertTrue(transport.requests.contains {
                $0.httpMethod == "PATCH" && $0.url?.path.contains("relationships/appScreenshots") == true
            })
            XCTAssertEqual(setReadCount, 3)
        }
    }

    func testPublisherDoesNotDeleteWhenAnyBackupCannotDecode() throws {
        try withTemporaryDirectory { directory in
            let desired = try opaquePNG(width: 2, height: 3, byte: 0x33)
            let fixture = try existingVersionFixture(
                directory: directory,
                desiredData: desired,
                oldBackupData: Data("not a png".utf8)
            )
            let transport = PublisherMockTransport { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET"?, "/v1/appStoreVersionLocalizations/loc/appScreenshotSets"?):
                    return .json(.object(["data": .array([self.setResource(id: "set")])]))
                case ("GET"?, "/v1/appScreenshotSets/set/appScreenshots"?):
                    return .json(.object(["data": .array([fixture.oldRawScreenshot])]))
                case ("GET"?, "/2x3.png"?):
                    return TransportResponse(data: Data("not a png".utf8), statusCode: 200)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "") \(request.url?.path ?? "")")
                    return TransportResponse(data: Data(), statusCode: 500)
                }
            }
            let provider = SnapshotSequence([fixture.baseline, fixture.baseline])
            let publisher = try Publisher(
                client: makeClient(transport),
                journalURL: directory.appendingPathComponent("journal.json"),
                manifest: fixture.manifest,
                snapshotProvider: provider.next,
                sleeper: { _ in }
            )
            XCTAssertThrowsError(try publisher.publish(
                manifest: fixture.manifest,
                confirmedVersion: "2.1"
            ))
            XCTAssertFalse(transport.requests.contains { $0.httpMethod == "DELETE" })
        }
    }

    func testReplacementFailureReuploadsAndReordersStructuredBackup() throws {
        try withTemporaryDirectory { directory in
            let desired = try opaquePNG(width: 2, height: 3, byte: 0x66)
            let backupData = try opaquePNG(width: 2, height: 3, byte: 0x11)
            let fixture = try existingVersionFixture(
                directory: directory, desiredData: desired, oldBackupData: backupData
            )
            let restoredRemote = remoteScreenshot(
                id: "restored", fileName: "old.png", checksum: FileIO.md5(backupData), imageAsset: false
            )
            var screenshotListCount = 0
            var reserveCount = 0
            var orderCount = 0
            let transport = PublisherMockTransport { request in
                let method = request.httpMethod ?? ""
                let path = request.url?.path ?? ""
                switch (method, path) {
                case ("GET", "/v1/appStoreVersionLocalizations/loc/appScreenshotSets"):
                    return .json(.object(["data": .array([self.setResource(id: "set")])]))
                case ("GET", "/v1/appScreenshotSets/set/appScreenshots"):
                    screenshotListCount += 1
                    let value: JSONValue
                    if screenshotListCount == 1 { value = fixture.oldRawScreenshot }
                    else if screenshotListCount == 2 { value = fixture.newRawScreenshot }
                    else { value = self.raw(restoredRemote) }
                    return .json(.object(["data": .array([value])]))
                case ("GET", "/2x3.png"):
                    return TransportResponse(data: backupData, statusCode: 200)
                case ("DELETE", "/v1/appScreenshots/old"),
                     ("DELETE", "/v1/appScreenshots/new"):
                    return TransportResponse(data: Data(), statusCode: 204)
                case ("POST", "/v1/appScreenshots"):
                    reserveCount += 1
                    let data = reserveCount == 1 ? desired : backupData
                    let id = reserveCount == 1 ? "new" : "restored"
                    return .json(self.reservation(id: id, byteCount: data.count))
                case ("PUT", "/chunk"):
                    return TransportResponse(data: Data(), statusCode: 200)
                case ("PATCH", "/v1/appScreenshots/new"):
                    return .json(.object(["data": fixture.newRawScreenshot]))
                case ("PATCH", "/v1/appScreenshots/restored"):
                    return .json(.object(["data": self.raw(restoredRemote)]))
                case ("GET", "/v1/appScreenshots/new"):
                    return .json(.object(["data": fixture.newRawScreenshot]))
                case ("GET", "/v1/appScreenshots/restored"):
                    return .json(.object(["data": self.raw(restoredRemote)]))
                case ("PATCH", "/v1/appScreenshotSets/set/relationships/appScreenshots"):
                    orderCount += 1
                    if orderCount == 1 {
                        return .json(.object(["errors": .array([.object([
                            "detail": .string("forced order failure"),
                        ])])]), status: 422)
                    }
                    let body = try self.body(request)
                    XCTAssertEqual(body["data"]?.arrayValue?.first?["id"]?.stringValue, "restored")
                    return TransportResponse(data: Data(), statusCode: 204)
                default:
                    XCTFail("Unexpected request \(method) \(path)")
                    return TransportResponse(data: Data(), statusCode: 500)
                }
            }
            let publisher = try Publisher(
                client: makeClient(transport),
                journalURL: directory.appendingPathComponent("journal.json"),
                manifest: fixture.manifest,
                snapshotProvider: SnapshotSequence([fixture.baseline, fixture.baseline]).next,
                sleeper: { _ in }
            )
            XCTAssertThrowsError(try publisher.publish(
                manifest: fixture.manifest, confirmedVersion: "2.1"
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("backup was restored"))
            }
            XCTAssertEqual(reserveCount, 2)
            XCTAssertEqual(orderCount, 2)
            XCTAssertTrue(transport.requests.contains {
                $0.httpMethod == "DELETE" && $0.url?.path == "/v1/appScreenshots/new"
            })
        }
    }

    func testSuccessfulRollbackEstablishesEpochAndSameManifestRetrySucceeds() throws {
        try withTemporaryDirectory { directory in
            let desired = try opaquePNG(width: 2, height: 3, byte: 0x77)
            let backupData = try opaquePNG(width: 2, height: 3, byte: 0x12)
            let fixture = try existingVersionFixture(
                directory: directory, desiredData: desired, oldBackupData: backupData
            )
            let restoredRemote = remoteScreenshot(
                id: "restored", fileName: "old.png", checksum: FileIO.md5(backupData),
                imageAsset: false
            )
            let retryRemote = remoteScreenshot(
                id: "retry", fileName: "desired.png", checksum: FileIO.md5(desired),
                imageAsset: false
            )
            let restoredLocale = RemoteLocalization(
                id: "loc", locale: "en-US",
                attributes: ["locale": .string("en-US"), "whatsNew": .string("Old notes")],
                screenshotSets: [RemoteScreenshotSet(
                    id: "set", displayType: "APP_IPHONE_67", screenshots: [restoredRemote]
                )]
            )
            let restoredVersion = version(locales: [restoredLocale])
            let restoredSnapshot = try snapshot(
                target: restoredVersion,
                source: restoredVersion,
                appInfo: appInfo(locales: ["en-US"])
            )
            let retryLocale = RemoteLocalization(
                id: "loc", locale: "en-US",
                attributes: ["locale": .string("en-US"), "whatsNew": .string("New notes")],
                screenshotSets: [RemoteScreenshotSet(
                    id: "set", displayType: "APP_IPHONE_67", screenshots: [retryRemote]
                )]
            )
            let retryVersion = version(locales: [retryLocale])
            let finalSnapshot = try snapshot(
                target: retryVersion,
                source: retryVersion,
                appInfo: appInfo(locales: ["en-US"])
            )

            var screenshotListCount = 0
            var reserveCount = 0
            var orderCount = 0
            let transport = PublisherMockTransport { request in
                let method = request.httpMethod ?? ""
                let path = request.url?.path ?? ""
                switch (method, path) {
                case ("GET", "/v1/appStoreVersionLocalizations/loc/appScreenshotSets"):
                    return .json(.object(["data": .array([self.setResource(id: "set")])]))
                case ("GET", "/v1/appScreenshotSets/set/appScreenshots"):
                    screenshotListCount += 1
                    let value: JSONValue
                    switch screenshotListCount {
                    case 1: value = fixture.oldRawScreenshot
                    case 2: value = fixture.newRawScreenshot
                    case 3, 4: value = self.raw(restoredRemote)
                    default: value = self.raw(retryRemote)
                    }
                    return .json(.object(["data": .array([value])]))
                case ("GET", "/2x3.png"):
                    return TransportResponse(data: backupData, statusCode: 200)
                case ("DELETE", "/v1/appScreenshots/old"),
                     ("DELETE", "/v1/appScreenshots/new"),
                     ("DELETE", "/v1/appScreenshots/restored"):
                    return TransportResponse(data: Data(), statusCode: 204)
                case ("POST", "/v1/appScreenshots"):
                    reserveCount += 1
                    let id: String
                    let byteCount: Int
                    switch reserveCount {
                    case 1: (id, byteCount) = ("new", desired.count)
                    case 2: (id, byteCount) = ("restored", backupData.count)
                    default: (id, byteCount) = ("retry", desired.count)
                    }
                    return .json(self.reservation(id: id, byteCount: byteCount))
                case ("PUT", "/chunk"):
                    return TransportResponse(data: Data(), statusCode: 200)
                case ("PATCH", "/v1/appScreenshots/new"):
                    return .json(.object(["data": fixture.newRawScreenshot]))
                case ("PATCH", "/v1/appScreenshots/restored"):
                    return .json(.object(["data": self.raw(restoredRemote)]))
                case ("PATCH", "/v1/appScreenshots/retry"):
                    return .json(.object(["data": self.raw(retryRemote)]))
                case ("GET", "/v1/appScreenshots/new"):
                    return .json(.object(["data": fixture.newRawScreenshot]))
                case ("GET", "/v1/appScreenshots/restored"):
                    return .json(.object(["data": self.raw(restoredRemote)]))
                case ("GET", "/v1/appScreenshots/retry"):
                    return .json(.object(["data": self.raw(retryRemote)]))
                case ("PATCH", "/v1/appScreenshotSets/set/relationships/appScreenshots"):
                    orderCount += 1
                    if orderCount == 1 {
                        return .json(.object(["errors": .array([.object([
                            "detail": .string("forced first-attempt order failure"),
                        ])])]), status: 422)
                    }
                    let expectedId = orderCount == 2 ? "restored" : "retry"
                    let body = try self.body(request)
                    XCTAssertEqual(body["data"]?.arrayValue?.first?["id"]?.stringValue, expectedId)
                    return TransportResponse(data: Data(), statusCode: 204)
                case ("PATCH", "/v1/appStoreVersionLocalizations/loc"):
                    return .json(.object(["data": .object([
                        "type": .string("appStoreVersionLocalizations"),
                        "id": .string("loc"),
                    ])]))
                default:
                    XCTFail("Unexpected request \(method) \(path)")
                    return TransportResponse(data: Data(), statusCode: 500)
                }
            }
            let journalURL = directory.appendingPathComponent("journal.json")
            let firstPublisher = try Publisher(
                client: makeClient(transport),
                journalURL: journalURL,
                manifest: fixture.manifest,
                snapshotProvider: SnapshotSequence([fixture.baseline, fixture.baseline]).next,
                sleeper: { _ in }
            )
            XCTAssertThrowsError(try firstPublisher.publish(
                manifest: fixture.manifest, confirmedVersion: "2.1"
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("backup was restored"))
            }

            let journalAfterRollback = try ManifestBuilder.decode(PublishJournal.self, at: journalURL)
            let rollback = try XCTUnwrap(journalAfterRollback.operations.last {
                $0.key == "screenshots:en-US:iphone-6.9:rollback"
            })
            let checkpointData = try XCTUnwrap(rollback.detail?.data(using: .utf8))
            let checkpoint = try JSONDecoder().decode(
                ScreenshotRollbackCheckpoint.self, from: checkpointData
            )
            XCTAssertEqual(checkpoint.screenshots.map(\.resourceId), ["restored"])

            let retryPublisher = try Publisher(
                client: makeClient(transport),
                journalURL: journalURL,
                manifest: fixture.manifest,
                snapshotProvider: SnapshotSequence([
                    restoredSnapshot, restoredSnapshot, finalSnapshot,
                ]).next,
                sleeper: { _ in }
            )
            try retryPublisher.publish(manifest: fixture.manifest, confirmedVersion: "2.1")

            XCTAssertEqual(reserveCount, 3)
            XCTAssertEqual(orderCount, 3)
            XCTAssertTrue(transport.requests.contains {
                $0.httpMethod == "DELETE" && $0.url?.path == "/v1/appScreenshots/restored"
            })
        }
    }

    func testLegacyUncheckpointedRollbackIsAdoptedAndRetrySucceeds() throws {
        try withTemporaryDirectory { directory in
            let desiredData = try opaquePNG(width: 2, height: 3, byte: 0x78)
            let backupData = try opaquePNG(width: 2, height: 3, byte: 0x13)
            let fixture = try existingVersionFixture(
                directory: directory, desiredData: desiredData, oldBackupData: backupData
            )
            let desired = try XCTUnwrap(
                fixture.manifest.localizations.first?.screenshotSets.first?.screenshots.first
            )
            let backupImageURL = directory.appendingPathComponent("old.png")
            try FileIO.write(data: backupData, to: backupImageURL)
            let decoded = try ImageValidation.decodePNG(backupData, context: backupImageURL.path)
            let backup = ScreenshotBackupManifest(
                schemaVersion: 1,
                createdAt: "now",
                locale: "en-US",
                family: "iphone-6.9",
                displayType: "APP_IPHONE_67",
                screenshotSetId: "set",
                pixelWidth: 2,
                pixelHeight: 3,
                screenshots: [ScreenshotBackupEntry(
                    originalId: "old",
                    originalSourceChecksum: "11111111111111111111111111111111",
                    fileName: "old.png",
                    order: 1,
                    path: backupImageURL.standardizedFilePath,
                    byteCount: backupData.count,
                    sha256: FileIO.sha256(backupData),
                    md5: FileIO.md5(backupData),
                    pixelWidth: decoded.pixelWidth,
                    pixelHeight: decoded.pixelHeight,
                    hasAlpha: decoded.hasAlpha,
                    orientation: decoded.orientation
                )]
            )
            let backupManifestURL = directory.appendingPathComponent("backup-manifest.json")
            try FileIO.writeJSON(backup, to: backupManifestURL)
            let journalURL = directory.appendingPathComponent("journal.json")
            try FileIO.writeJSON(PublishJournal(
                version: "2.1",
                manifestDigest: fixture.manifest.manifestDigest,
                startedAt: "now",
                operations: [
                    JournalOperation(
                        key: "screenshots:en-US:iphone-6.9:backup", status: "complete",
                        timestamp: "now", detail: backupManifestURL.standardizedFilePath
                    ),
                    JournalOperation(
                        key: "screenshot:en-US:iphone-6.9:delete:old", status: "complete",
                        timestamp: "now", detail: "old"
                    ),
                    JournalOperation(
                        key: "screenshot:en-US:iphone-6.9:upload:\(desired.sha256)",
                        status: "complete", timestamp: "now", detail: "new"
                    ),
                    JournalOperation(
                        key: "screenshots:en-US:iphone-6.9:order", status: "complete",
                        timestamp: "now", detail: "set"
                    ),
                ]
            ), to: journalURL)

            let restoredRemote = remoteScreenshot(
                id: "restored", fileName: "old.png", checksum: backup.screenshots[0].md5,
                imageAsset: false
            )
            let restoredLocale = RemoteLocalization(
                id: "loc", locale: "en-US",
                attributes: ["locale": .string("en-US"), "whatsNew": .string("Old notes")],
                screenshotSets: [RemoteScreenshotSet(
                    id: "set", displayType: "APP_IPHONE_67", screenshots: [restoredRemote]
                )]
            )
            let restoredVersion = version(locales: [restoredLocale])
            let restoredSnapshot = try snapshot(
                target: restoredVersion,
                source: restoredVersion,
                appInfo: appInfo(locales: ["en-US"])
            )
            let retryRemote = remoteScreenshot(
                id: "retry", fileName: desired.fileName, checksum: desired.md5, imageAsset: false
            )
            let finalLocale = RemoteLocalization(
                id: "loc", locale: "en-US",
                attributes: ["locale": .string("en-US"), "whatsNew": .string("New notes")],
                screenshotSets: [RemoteScreenshotSet(
                    id: "set", displayType: "APP_IPHONE_67", screenshots: [retryRemote]
                )]
            )
            let finalVersion = version(locales: [finalLocale])
            let finalSnapshot = try snapshot(
                target: finalVersion,
                source: finalVersion,
                appInfo: appInfo(locales: ["en-US"])
            )

            var relationshipWasPatched = false
            let transport = PublisherMockTransport { request in
                let method = request.httpMethod ?? ""
                let path = request.url?.path ?? ""
                switch (method, path) {
                case ("GET", "/v1/appStoreVersionLocalizations/loc/appScreenshotSets"):
                    return .json(.object(["data": .array([self.setResource(id: "set")])]))
                case ("GET", "/v1/appScreenshotSets/set/appScreenshots"):
                    let resource = relationshipWasPatched ? self.raw(retryRemote) : self.raw(restoredRemote)
                    return .json(.object(["data": .array([resource])]))
                case ("DELETE", "/v1/appScreenshots/restored"):
                    return TransportResponse(data: Data(), statusCode: 204)
                case ("POST", "/v1/appScreenshots"):
                    return .json(self.reservation(id: "retry", byteCount: desiredData.count))
                case ("PUT", "/chunk"):
                    return TransportResponse(data: Data(), statusCode: 200)
                case ("PATCH", "/v1/appScreenshots/retry"):
                    return .json(.object(["data": self.raw(retryRemote)]))
                case ("GET", "/v1/appScreenshots/retry"):
                    return .json(.object(["data": self.raw(retryRemote)]))
                case ("PATCH", "/v1/appScreenshotSets/set/relationships/appScreenshots"):
                    relationshipWasPatched = true
                    return TransportResponse(data: Data(), statusCode: 204)
                case ("PATCH", "/v1/appStoreVersionLocalizations/loc"):
                    return .json(.object(["data": .object([
                        "type": .string("appStoreVersionLocalizations"), "id": .string("loc"),
                    ])]))
                default:
                    XCTFail("Unexpected request \(method) \(path)")
                    return TransportResponse(data: Data(), statusCode: 500)
                }
            }
            let publisher = try Publisher(
                client: makeClient(transport),
                journalURL: journalURL,
                manifest: fixture.manifest,
                snapshotProvider: SnapshotSequence([
                    restoredSnapshot, restoredSnapshot, finalSnapshot,
                ]).next,
                sleeper: { _ in }
            )
            try publisher.publish(manifest: fixture.manifest, confirmedVersion: "2.1")

            let journal = try ManifestBuilder.decode(PublishJournal.self, at: journalURL)
            XCTAssertNotNil(journal.operations.first {
                $0.key == "screenshots:en-US:iphone-6.9:rollback"
            })
            XCTAssertNotNil(journal.operations.first {
                $0.key == "screenshots:en-US:iphone-6.9:complete"
            })
            XCTAssertNotNil(journal.completedAt)
        }
    }

    func testPublisherRejectsChangedStateBeforeMutation() throws {
        try withTemporaryDirectory { directory in
            let desired = try opaquePNG(width: 2, height: 3, byte: 0x44)
            let fixture = try existingVersionFixture(
                directory: directory,
                desiredData: desired,
                oldBackupData: desired
            )
            let changedTarget = RemoteVersion(
                id: "version", versionString: "2.1", state: "REJECTED",
                attributes: fixture.baseline.targetVersion!.attributes,
                localizations: fixture.baseline.targetVersion!.localizations
            )
            let changed = try snapshot(
                target: changedTarget,
                source: changedTarget,
                appInfo: fixture.baseline.appInfo!
            )
            let transport = PublisherMockTransport { _ in
                XCTFail("No API mutation/read should occur after snapshot drift")
                return TransportResponse(data: Data(), statusCode: 500)
            }
            let publisher = try Publisher(
                client: makeClient(transport),
                journalURL: directory.appendingPathComponent("journal.json"),
                manifest: fixture.manifest,
                snapshotProvider: SnapshotSequence([changed]).next,
                sleeper: { _ in }
            )
            XCTAssertThrowsError(try publisher.publish(
                manifest: fixture.manifest,
                confirmedVersion: "2.1"
            )) { XCTAssertTrue($0.localizedDescription.contains("changed")) }
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }

    func testFreshVersionUsesCorrectRelationshipsAndFiltersNullCreateAttributes() throws {
        try withTemporaryDirectory { directory in
            let fixture = try freshVersionFixture(directory: directory)
            let transport = PublisherMockTransport { request in
                let body = try request.httpBody.map { try JSONDecoder().decode(JSONValue.self, from: $0) }
                switch (request.httpMethod, request.url?.path) {
                case ("POST"?, "/v1/appStoreVersions"?):
                    XCTAssertEqual(body?["data"]?["relationships"]?["app"]?["data"]?["id"]?.stringValue, "app")
                    XCTAssertEqual(body?["data"]?["attributes"]?["versionString"]?.stringValue, "2.1")
                    XCTAssertEqual(body?["data"]?["attributes"]?["platform"]?.stringValue, "IOS")
                    XCTAssertNil(body?["data"]?["attributes"]?["releaseType"])
                    return .json(.object(["data": .object(["type": .string("appStoreVersions"), "id": .string("new-version")])]))
                case ("POST"?, "/v1/appInfoLocalizations"?):
                    XCTAssertEqual(body?["data"]?["relationships"]?["appInfo"]?["data"]?["id"]?.stringValue, "draft-info")
                    return .json(.object(["data": .object(["type": .string("appInfoLocalizations"), "id": .string("new-app-loc")])]))
                case ("POST"?, "/v1/appStoreVersionLocalizations"?):
                    XCTAssertEqual(body?["data"]?["relationships"]?["appStoreVersion"]?["data"]?["id"]?.stringValue, "new-version")
                    XCTAssertNil(body?["data"]?["attributes"]?["marketingUrl"])
                    return .json(.object(["data": .object(["type": .string("appStoreVersionLocalizations"), "id": .string("new-loc")])]))
                case ("PATCH"?, "/v1/appStoreVersions/new-version"?):
                    XCTAssertNil(body?["data"]?["attributes"]?["releaseType"])
                    return .json(.object(["data": .object(["type": .string("resource"), "id": .string("ok")])]))
                case ("PATCH"?, "/v1/appInfoLocalizations/new-app-loc"?),
                     ("PATCH"?, "/v1/appStoreVersionLocalizations/new-loc"?):
                    return .json(.object(["data": .object(["type": .string("resource"), "id": .string("ok")])]))
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "") \(request.url?.path ?? "")")
                    return TransportResponse(data: Data(), statusCode: 500)
                }
            }
            let provider = SnapshotSequence([
                fixture.baseline, fixture.createdEmpty, fixture.createdEmpty,
                fixture.createdAppInfoOnly, fixture.final,
            ])
            let publisher = try Publisher(
                client: makeClient(transport),
                journalURL: directory.appendingPathComponent("journal.json"),
                manifest: fixture.manifest,
                snapshotProvider: provider.next,
                sleeper: { _ in }
            )
            try publisher.publish(manifest: fixture.manifest, confirmedVersion: "2.1")
        }
    }

    func testFreshVersionAcceptsServerCreatedLocalizationDefaultsBeforeMetadataIsOwned() throws {
        try withTemporaryDirectory { directory in
            let fixture = try freshVersionFixture(
                directory: directory,
                serverCreatesVersionLocalization: true
            )
            let transport = PublisherMockTransport { request in
                switch (request.httpMethod, request.url?.path) {
                case ("POST"?, "/v1/appStoreVersions"?):
                    return .json(.object(["data": .object([
                        "type": .string("appStoreVersions"), "id": .string("new-version"),
                    ])]))
                case ("POST"?, "/v1/appInfoLocalizations"?):
                    return .json(.object(["data": .object([
                        "type": .string("appInfoLocalizations"), "id": .string("new-app-loc"),
                    ])]))
                case ("PATCH"?, "/v1/appStoreVersions/new-version"?),
                     ("PATCH"?, "/v1/appInfoLocalizations/new-app-loc"?),
                     ("PATCH"?, "/v1/appStoreVersionLocalizations/new-loc"?):
                    return .json(.object(["data": .object([
                        "type": .string("resource"), "id": .string("ok"),
                    ])]))
                case ("POST"?, "/v1/appStoreVersionLocalizations"?):
                    XCTFail("The server-created localization must be reused")
                    return TransportResponse(data: Data(), statusCode: 500)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "") \(request.url?.path ?? "")")
                    return TransportResponse(data: Data(), statusCode: 500)
                }
            }
            let provider = SnapshotSequence([
                fixture.baseline, fixture.createdEmpty, fixture.createdEmpty, fixture.final,
            ])
            let publisher = try Publisher(
                client: makeClient(transport),
                journalURL: directory.appendingPathComponent("journal.json"),
                manifest: fixture.manifest,
                snapshotProvider: provider.next,
                sleeper: { _ in }
            )

            try publisher.publish(manifest: fixture.manifest, confirmedVersion: "2.1")

            XCTAssertFalse(transport.requests.contains {
                $0.httpMethod == "POST" && $0.url?.path == "/v1/appStoreVersionLocalizations"
            })
        }
    }

    func testAppInfoCreatedVersionLocalizationIsAdoptedAndReused() throws {
        try withTemporaryDirectory { directory in
            let fixture = try freshVersionFixture(directory: directory)
            let emptyTarget = fixture.createdEmpty.targetVersion!
            let sideEffectLocale = RemoteLocalization(
                id: "new-loc", locale: "en-US",
                attributes: [
                    "locale": .string("en-US"),
                    "description": .null,
                    "keywords": .null,
                    "marketingUrl": .null,
                    "promotionalText": .null,
                    "supportUrl": .null,
                    "whatsNew": .null,
                ],
                screenshotSets: []
            )
            let sideEffectTarget = RemoteVersion(
                id: emptyTarget.id,
                versionString: emptyTarget.versionString,
                state: emptyTarget.state,
                attributes: emptyTarget.attributes,
                localizations: [sideEffectLocale]
            )
            let sideEffectSnapshot = try snapshot(
                target: sideEffectTarget,
                source: fixture.createdEmpty.sourceVersion,
                appInfo: fixture.createdAppInfoOnly.appInfo!
            )
            let transport = PublisherMockTransport { request in
                switch (request.httpMethod, request.url?.path) {
                case ("POST"?, "/v1/appStoreVersions"?):
                    return .json(.object(["data": .object([
                        "type": .string("appStoreVersions"), "id": .string("new-version"),
                    ])]))
                case ("POST"?, "/v1/appInfoLocalizations"?):
                    return .json(.object(["data": .object([
                        "type": .string("appInfoLocalizations"), "id": .string("new-app-loc"),
                    ])]))
                case ("PATCH"?, "/v1/appStoreVersions/new-version"?),
                     ("PATCH"?, "/v1/appInfoLocalizations/new-app-loc"?),
                     ("PATCH"?, "/v1/appStoreVersionLocalizations/new-loc"?):
                    return .json(.object(["data": .object([
                        "type": .string("resource"), "id": .string("ok"),
                    ])]))
                case ("POST"?, "/v1/appStoreVersionLocalizations"?):
                    XCTFail("The App Info-created version localization must be reused")
                    return TransportResponse(data: Data(), statusCode: 500)
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "") \(request.url?.path ?? "")")
                    return TransportResponse(data: Data(), statusCode: 500)
                }
            }
            let journalURL = directory.appendingPathComponent("journal.json")
            let provider = SnapshotSequence([
                fixture.baseline,
                fixture.createdEmpty,
                fixture.createdEmpty,
                sideEffectSnapshot,
                fixture.final,
            ])
            let publisher = try Publisher(
                client: makeClient(transport),
                journalURL: journalURL,
                manifest: fixture.manifest,
                snapshotProvider: provider.next,
                sleeper: { _ in }
            )

            try publisher.publish(manifest: fixture.manifest, confirmedVersion: "2.1")

            let journal = try ManifestBuilder.decode(PublishJournal.self, at: journalURL)
            XCTAssertEqual(
                journal.operations.first {
                    $0.key == "version-locale:en-US:app-info-side-effect"
                }?.detail,
                "new-loc"
            )
            XCTAssertFalse(transport.requests.contains {
                $0.httpMethod == "POST" && $0.url?.path == "/v1/appStoreVersionLocalizations"
            })
        }
    }

    func testJournaledVersionLocalizationMetadataRemainsStrict() throws {
        try withTemporaryDirectory { directory in
            let fixture = try freshVersionFixture(
                directory: directory,
                serverCreatesVersionLocalization: true
            )
            let journalURL = directory.appendingPathComponent("journal.json")
            try FileIO.writeJSON(PublishJournal(
                version: "2.1",
                manifestDigest: fixture.manifest.manifestDigest,
                startedAt: "now",
                operations: [
                    JournalOperation(
                        key: "version:2.1:create", status: "complete",
                        timestamp: "now", detail: "new-version"
                    ),
                    JournalOperation(
                        key: "version-locale:en-US:metadata", status: "complete",
                        timestamp: "now", detail: "new-loc"
                    ),
                ]
            ), to: journalURL)
            let transport = PublisherMockTransport { request in
                XCTFail("Drift must be rejected before API access: \(request.url?.path ?? "")")
                return TransportResponse(data: Data(), statusCode: 500)
            }
            let publisher = try Publisher(
                client: makeClient(transport), journalURL: journalURL,
                manifest: fixture.manifest,
                snapshotProvider: SnapshotSequence([fixture.createdEmpty]).next,
                sleeper: { _ in }
            )

            XCTAssertThrowsError(try publisher.publish(
                manifest: fixture.manifest, confirmedVersion: "2.1"
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("version locale en-US.whatsNew"))
            }
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }

    func testFreshServerCreatedLocalizationStillRejectsOtherInheritedMetadataDrift() throws {
        try withTemporaryDirectory { directory in
            let fixture = try freshVersionFixture(
                directory: directory,
                serverCreatesVersionLocalization: true
            )
            let created = fixture.createdEmpty
            var changedAttributes = created.targetVersion!.localizations[0].attributes
            changedAttributes["description"] = .string("Unexpected")
            let changedLocale = RemoteLocalization(
                id: "new-loc", locale: "en-US",
                attributes: changedAttributes, screenshotSets: []
            )
            let changedTarget = RemoteVersion(
                id: created.targetVersion!.id,
                versionString: created.targetVersion!.versionString,
                state: created.targetVersion!.state,
                attributes: created.targetVersion!.attributes,
                localizations: [changedLocale]
            )
            let changed = try snapshot(
                target: changedTarget,
                source: created.sourceVersion,
                appInfo: created.appInfo!
            )
            let journalURL = directory.appendingPathComponent("journal.json")
            try FileIO.writeJSON(PublishJournal(
                version: "2.1",
                manifestDigest: fixture.manifest.manifestDigest,
                startedAt: "now",
                operations: [JournalOperation(
                    key: "version:2.1:create", status: "complete",
                    timestamp: "now", detail: "new-version"
                )]
            ), to: journalURL)
            let transport = PublisherMockTransport { request in
                XCTFail("Drift must be rejected before API access: \(request.url?.path ?? "")")
                return TransportResponse(data: Data(), statusCode: 500)
            }
            let publisher = try Publisher(
                client: makeClient(transport), journalURL: journalURL,
                manifest: fixture.manifest,
                snapshotProvider: SnapshotSequence([changed]).next,
                sleeper: { _ in }
            )

            XCTAssertThrowsError(try publisher.publish(
                manifest: fixture.manifest, confirmedVersion: "2.1"
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("version locale en-US.description"))
            }
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }

    func testReviewedVersionLocalizationMetadataRemainsStrictAfterPublishingStarts() throws {
        try withTemporaryDirectory { directory in
            let desired = try opaquePNG(width: 2, height: 3, byte: 0x41)
            let fixture = try existingVersionFixture(
                directory: directory, desiredData: desired, oldBackupData: desired
            )
            let reviewed = fixture.manifest.remoteSnapshot
            let changedLocale = RemoteLocalization(
                id: "loc", locale: "en-US",
                attributes: ["locale": .string("en-US"), "whatsNew": .null],
                screenshotSets: reviewed.targetVersion!.localizations[0].screenshotSets
            )
            let changedTarget = RemoteVersion(
                id: reviewed.targetVersion!.id,
                versionString: reviewed.targetVersion!.versionString,
                state: reviewed.targetVersion!.state,
                attributes: reviewed.targetVersion!.attributes,
                localizations: [changedLocale]
            )
            let changed = try snapshot(
                target: changedTarget,
                source: reviewed.sourceVersion,
                appInfo: reviewed.appInfo!
            )
            let journalURL = directory.appendingPathComponent("journal.json")
            try FileIO.writeJSON(PublishJournal(
                version: "2.1",
                manifestDigest: fixture.manifest.manifestDigest,
                startedAt: "now",
                operations: [JournalOperation(
                    key: "screenshots:en-US:iphone-6.9:backup",
                    status: "complete", timestamp: "now", detail: "{}"
                )]
            ), to: journalURL)
            let transport = PublisherMockTransport { request in
                XCTFail("Drift must be rejected before API access: \(request.url?.path ?? "")")
                return TransportResponse(data: Data(), statusCode: 500)
            }
            let publisher = try Publisher(
                client: makeClient(transport), journalURL: journalURL,
                manifest: fixture.manifest,
                snapshotProvider: SnapshotSequence([changed]).next,
                sleeper: { _ in }
            )

            XCTAssertThrowsError(try publisher.publish(
                manifest: fixture.manifest, confirmedVersion: "2.1"
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("version locale en-US.whatsNew"))
            }
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }

    func testResumedMetadataIsReconciledInsteadOfBlindlyReplayed() throws {
        try withTemporaryDirectory { directory in
            let fixture = try resumeFixture(directory: directory)
            let journalURL = directory.appendingPathComponent("journal.json")
            try FileIO.writeJSON(PublishJournal(
                version: "2.1",
                manifestDigest: fixture.manifest.manifestDigest,
                startedAt: "now",
                operations: [JournalOperation(
                    key: "version-locale:en-US:metadata",
                    status: "complete",
                    timestamp: "now",
                    detail: "loc"
                )]
            ), to: journalURL)
            let transport = PublisherMockTransport { request in
                XCTFail("Reconciled completed metadata must not be replayed: \(request.url?.path ?? "")")
                return TransportResponse(data: Data(), statusCode: 500)
            }
            let provider = SnapshotSequence([fixture.live, fixture.live, fixture.live])
            let publisher = try Publisher(
                client: makeClient(transport), journalURL: journalURL,
                manifest: fixture.manifest, snapshotProvider: provider.next, sleeper: { _ in }
            )
            try publisher.publish(manifest: fixture.manifest, confirmedVersion: "2.1")
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }

    private struct ExistingFixture {
        let manifest: PublishManifest
        let baseline: RemoteSnapshot
        let final: RemoteSnapshot
        let oldRawScreenshot: JSONValue
        let newRawScreenshot: JSONValue
    }

    private func existingVersionFixture(
        directory: URL,
        desiredData: Data,
        oldBackupData: Data
    ) throws -> ExistingFixture {
        let desiredURL = directory.appendingPathComponent("desired.png")
        try FileIO.write(data: desiredData, to: desiredURL)
        let desired = ManifestScreenshot(
            path: desiredURL.path, fileName: "desired.png", byteCount: desiredData.count,
            sha256: FileIO.sha256(desiredData), md5: FileIO.md5(desiredData), order: 1
        )
        let oldRemote = remoteScreenshot(
            id: "old", fileName: "old.png", checksum: "11111111111111111111111111111111",
            imageAsset: true
        )
        let newRemote = remoteScreenshot(
            id: "new", fileName: "desired.png", checksum: desired.md5, imageAsset: false
        )
        let locale = RemoteLocalization(
            id: "loc", locale: "en-US",
            attributes: ["locale": .string("en-US"), "whatsNew": .string("Old notes")],
            screenshotSets: [RemoteScreenshotSet(
                id: "set", displayType: "APP_IPHONE_67", screenshots: [oldRemote]
            )]
        )
        let baselineVersion = version(locales: [locale])
        let baseline = try snapshot(
            target: baselineVersion, source: baselineVersion, appInfo: appInfo(locales: ["en-US"])
        )
        let finalLocale = RemoteLocalization(
            id: "loc", locale: "en-US",
            attributes: ["locale": .string("en-US"), "whatsNew": .string("New notes")],
            screenshotSets: [RemoteScreenshotSet(
                id: "set", displayType: "APP_IPHONE_67", screenshots: [newRemote]
            )]
        )
        let finalVersion = version(locales: [finalLocale])
        let final = try snapshot(
            target: finalVersion, source: finalVersion, appInfo: appInfo(locales: ["en-US"])
        )
        let releaseLocale = NormalizedLocaleRelease(
            appStoreLocale: "en-US", screenshotConfiguration: "en-US", whatsNew: "New notes",
            versionMetadata: ["whatsNew": .string("New notes")], appMetadata: [:], sourceFiles: [:]
        )
        let release = NormalizedRelease(
            version: "2.1", bundleId: "com.example.App", platform: "IOS",
            sourceReleasePath: "/release.json", sourceDigest: "source",
            localizations: [releaseLocale], versionMetadata: [:]
        )
        let manifest = try makeManifest(
            release: release,
            snapshot: baseline,
            locales: [ManifestLocale(
                appStoreLocale: "en-US",
                versionMetadata: releaseLocale.versionMetadata,
                appMetadata: [:],
                screenshotSets: [ManifestScreenshotSet(
                    family: "iphone-6.9", displayType: "APP_IPHONE_67",
                    pixelWidth: 2, pixelHeight: 3, screenshots: [desired]
                )]
            )],
            screenshotCount: 1
        )
        return ExistingFixture(
            manifest: manifest, baseline: baseline, final: final,
            oldRawScreenshot: raw(oldRemote), newRawScreenshot: raw(newRemote)
        )
    }

    private struct FreshFixture {
        let manifest: PublishManifest
        let baseline: RemoteSnapshot
        let createdEmpty: RemoteSnapshot
        let createdAppInfoOnly: RemoteSnapshot
        let final: RemoteSnapshot
    }

    private func freshVersionFixture(
        directory: URL,
        serverCreatesVersionLocalization: Bool = false
    ) throws -> FreshFixture {
        let metadata: [String: JSONValue] = [
            "whatsNew": .string("New"), "description": .string("Description"),
            "keywords": .string("go"), "supportUrl": .string("https://example.com/support"),
            "marketingUrl": .null,
        ]
        let appMetadata: [String: JSONValue] = [
            "name": .string("Example"),
            "subtitle": .string("Play Go Online"),
            "privacyPolicyUrl": .string("https://example.com/privacy"),
        ]
        let locale = NormalizedLocaleRelease(
            appStoreLocale: "en-US", screenshotConfiguration: "en-US", whatsNew: "New",
            versionMetadata: metadata, appMetadata: appMetadata, sourceFiles: [:]
        )
        let release = NormalizedRelease(
            version: "2.1", bundleId: "com.example.App", platform: "IOS",
            sourceReleasePath: "/release.json", sourceDigest: "source", localizations: [locale],
            versionMetadata: [:]
        )
        var sourceAttributes = createNonNull(metadata)
        sourceAttributes["locale"] = .string("en-US")
        sourceAttributes["whatsNew"] = .string("Old")
        let sourceLocalization = RemoteLocalization(
            id: "source-loc", locale: "en-US",
            attributes: sourceAttributes, screenshotSets: []
        )
        let source = RemoteVersion(
            id: "source", versionString: "2.0", state: "READY_FOR_DISTRIBUTION",
            attributes: [
                "versionString": .string("2.0"), "platform": .string("IOS"),
                "releaseType": .string("AFTER_APPROVAL"), "copyright": .string("2026 Example"),
            ], localizations: serverCreatesVersionLocalization ? [sourceLocalization] : []
        )
        let baseline = try snapshot(
            target: nil, source: source,
            appInfo: RemoteAppInfo(id: "live-info", state: "READY_FOR_DISTRIBUTION", localizations: [])
        )
        var serverDefaultAttributes = sourceAttributes
        serverDefaultAttributes["whatsNew"] = .null
        let serverCreatedLocalization = RemoteLocalization(
            id: "new-loc", locale: "en-US",
            attributes: serverDefaultAttributes, screenshotSets: []
        )
        let emptyTarget = RemoteVersion(
            id: "new-version", versionString: "2.1", state: "PREPARE_FOR_SUBMISSION",
            attributes: [
                "versionString": .string("2.1"), "platform": .string("IOS"),
                "releaseType": .string("MANUAL"),
            ], localizations: serverCreatesVersionLocalization ? [serverCreatedLocalization] : []
        )
        let createdEmpty = try snapshot(
            target: emptyTarget, source: source,
            appInfo: RemoteAppInfo(id: "draft-info", state: "PREPARE_FOR_SUBMISSION", localizations: [])
        )
        let createdAppInfoOnly = try snapshot(
            target: emptyTarget, source: source,
            appInfo: RemoteAppInfo(
                id: "draft-info", state: "PREPARE_FOR_SUBMISSION",
                localizations: [RemoteAppInfoLocalization(
                    id: "new-app-loc", locale: "en-US",
                    attributes: appMetadata.merging(["locale": .string("en-US")]) { _, value in value }
                )]
            )
        )
        let finalLocale = RemoteLocalization(
            id: "new-loc", locale: "en-US", attributes: createNonNull(metadata).merging([
                "locale": .string("en-US"),
            ]) { _, value in value }, screenshotSets: []
        )
        let finalTarget = RemoteVersion(
            id: "new-version", versionString: "2.1", state: "PREPARE_FOR_SUBMISSION",
            attributes: [
                "versionString": .string("2.1"), "platform": .string("IOS"),
                "releaseType": .string("MANUAL"), "copyright": .string("2026 Example"),
            ], localizations: [finalLocale]
        )
        let final = try snapshot(
            target: finalTarget, source: source,
            appInfo: RemoteAppInfo(
                id: "draft-info", state: "PREPARE_FOR_SUBMISSION",
                localizations: [RemoteAppInfoLocalization(
                    id: "new-app-loc", locale: "en-US",
                    attributes: appMetadata.merging(["locale": .string("en-US")]) { _, value in value }
                )]
            )
        )
        let manifest = try makeManifest(
            release: release, snapshot: baseline,
            locales: [ManifestLocale(
                appStoreLocale: "en-US", versionMetadata: metadata,
                appMetadata: appMetadata, screenshotSets: []
            )], screenshotCount: 0
        )
        return FreshFixture(
            manifest: manifest,
            baseline: baseline,
            createdEmpty: createdEmpty,
            createdAppInfoOnly: createdAppInfoOnly,
            final: final
        )
    }

    private struct ResumeFixture { let manifest: PublishManifest; let live: RemoteSnapshot }

    private func resumeFixture(directory: URL) throws -> ResumeFixture {
        let locale = NormalizedLocaleRelease(
            appStoreLocale: "en-US", screenshotConfiguration: "en-US", whatsNew: "New",
            versionMetadata: ["whatsNew": .string("New")], appMetadata: [:], sourceFiles: [:]
        )
        let release = NormalizedRelease(
            version: "2.1", bundleId: "com.example.App", platform: "IOS",
            sourceReleasePath: "/release", sourceDigest: "source", localizations: [locale],
            versionMetadata: [:]
        )
        let baselineLocale = RemoteLocalization(
            id: "loc", locale: "en-US",
            attributes: ["locale": .string("en-US"), "whatsNew": .string("Old")],
            screenshotSets: []
        )
        let baselineVersion = version(locales: [baselineLocale])
        let baseline = try snapshot(
            target: baselineVersion, source: baselineVersion, appInfo: appInfo(locales: ["en-US"])
        )
        let liveLocale = RemoteLocalization(
            id: "loc", locale: "en-US",
            attributes: ["locale": .string("en-US"), "whatsNew": .string("New")],
            screenshotSets: []
        )
        let liveVersion = version(locales: [liveLocale])
        let live = try snapshot(
            target: liveVersion, source: liveVersion, appInfo: appInfo(locales: ["en-US"])
        )
        let manifest = try makeManifest(
            release: release, snapshot: baseline,
            locales: [ManifestLocale(
                appStoreLocale: "en-US", versionMetadata: locale.versionMetadata,
                appMetadata: [:], screenshotSets: []
            )], screenshotCount: 0
        )
        return ResumeFixture(manifest: manifest, live: live)
    }

    private func makeManifest(
        release: NormalizedRelease,
        snapshot: RemoteSnapshot,
        locales: [ManifestLocale],
        screenshotCount: Int
    ) throws -> PublishManifest {
        let capture: JSONValue = .object(["expectedScreenshotCount": .number(Double(screenshotCount))])
        let draft = PublishManifest(
            schemaVersion: 1, generatedAt: "now", release: release,
            remoteSnapshot: snapshot, remoteFingerprint: snapshot.fingerprint,
            captureMetadata: capture, localizations: locales, manifestDigest: ""
        )
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let digest = FileIO.sha256(try encoder.encode(draft))
        return PublishManifest(
            schemaVersion: 1, generatedAt: "now", release: release,
            remoteSnapshot: snapshot, remoteFingerprint: snapshot.fingerprint,
            captureMetadata: capture, localizations: locales, manifestDigest: digest
        )
    }

    private func version(locales: [RemoteLocalization]) -> RemoteVersion {
        RemoteVersion(
            id: "version", versionString: "2.1", state: "PREPARE_FOR_SUBMISSION",
            attributes: [
                "versionString": .string("2.1"), "platform": .string("IOS"),
                "releaseType": .string("MANUAL"),
            ], localizations: locales
        )
    }

    private func appInfo(locales: [String]) -> RemoteAppInfo {
        RemoteAppInfo(
            id: "info", state: "PREPARE_FOR_SUBMISSION",
            localizations: locales.map {
                RemoteAppInfoLocalization(
                    id: "app-\($0)", locale: $0,
                    attributes: ["locale": .string($0), "name": .string("Example")]
                )
            }
        )
    }

    private func snapshot(
        target: RemoteVersion?, source: RemoteVersion?, appInfo: RemoteAppInfo
    ) throws -> RemoteSnapshot {
        let draft = RemoteSnapshot(
            capturedAt: "now", fingerprint: "", appId: "app", bundleId: "com.example.App",
            platform: "IOS", requestedVersion: "2.1", targetVersion: target,
            sourceVersion: source, appInfo: appInfo
        )
        return RemoteSnapshot(
            capturedAt: draft.capturedAt,
            fingerprint: try SnapshotService.fingerprint(snapshot: draft),
            appId: draft.appId, bundleId: draft.bundleId, platform: draft.platform,
            requestedVersion: draft.requestedVersion, targetVersion: target,
            sourceVersion: source, appInfo: appInfo
        )
    }

    private func remoteScreenshot(
        id: String, fileName: String, checksum: String, imageAsset: Bool
    ) -> RemoteScreenshot {
        var attributes: [String: JSONValue] = [
            "fileName": .string(fileName), "sourceFileChecksum": .string(checksum),
            "assetDeliveryState": .object(["state": .string("COMPLETE")]),
        ]
        if imageAsset {
            attributes["imageAsset"] = .object([
                "templateUrl": .string(#"https://cdn.example/{w}x{h}{c}.{f}"#),
                "width": .number(2), "height": .number(3),
            ])
        }
        return RemoteScreenshot(id: id, fileName: fileName, checksum: checksum, attributes: attributes)
    }

    private func raw(_ screenshot: RemoteScreenshot) -> JSONValue {
        .object([
            "type": .string("appScreenshots"), "id": .string(screenshot.id),
            "attributes": .object(screenshot.attributes),
        ])
    }

    private func setResource(id: String) -> JSONValue {
        .object([
            "type": .string("appScreenshotSets"), "id": .string(id),
            "attributes": .object(["screenshotDisplayType": .string("APP_IPHONE_67")]),
        ])
    }

    private func reservation(id: String, byteCount: Int) -> JSONValue {
        .object(["data": .object([
            "type": .string("appScreenshots"), "id": .string(id),
            "attributes": .object(["uploadOperations": .array([.object([
                "method": .string("PUT"), "url": .string("https://upload.example/chunk"),
                "offset": .number(0), "length": .number(Double(byteCount)),
                "requestHeaders": .array([]),
            ])])]),
        ])])
    }

    private func body(_ request: URLRequest) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(request.httpBody))
    }

    private func makeClient(_ transport: PublisherMockTransport) -> ASCAPIClient {
        ASCAPIClient(
            credentials: ASCCredentials(
                keyId: "KEY", issuerId: "00000000-0000-0000-0000-000000000000",
                privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation
            ),
            baseURL: URL(string: "https://api.example")!, transport: transport, maxRetries: 0
        )
    }

    private func opaquePNG(width: Int, height: Int, byte: UInt8) throws -> Data {
        let bytes = Data(repeating: byte, count: width * height * 4)
        let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 1] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func createNonNull(_ values: [String: JSONValue]) -> [String: JSONValue] {
        values.filter { $0.value != .null }
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PublisherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}

private final class SnapshotSequence {
    private let snapshots: [RemoteSnapshot]
    private var index = 0
    init(_ snapshots: [RemoteSnapshot]) { self.snapshots = snapshots }
    func next(_: NormalizedRelease) throws -> RemoteSnapshot {
        guard !snapshots.isEmpty else { throw ReleaseToolError.api("No mocked snapshot") }
        defer { index += 1 }
        return snapshots[min(index, snapshots.count - 1)]
    }
}

private final class PublisherMockTransport: HTTPTransport, @unchecked Sendable {
    private let handler: (URLRequest) throws -> TransportResponse
    private(set) var requests: [URLRequest] = []
    init(_ handler: @escaping (URLRequest) throws -> TransportResponse) { self.handler = handler }
    func send(_ request: URLRequest) throws -> TransportResponse {
        requests.append(request)
        return try handler(request)
    }
}

private extension TransportResponse {
    static func json(_ value: JSONValue, status: Int = 200) -> TransportResponse {
        let data = (try? JSONEncoder().encode(value)) ?? Data()
        return TransportResponse(data: data, statusCode: status, headers: ["content-type": "application/json"])
    }
}
