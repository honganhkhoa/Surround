import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ASCReleaseCore

final class NormalEfficiencyTests: XCTestCase {
    func testCompletedThirtySetResumeUsesTwoSnapshotsAndNoRepeatedSetReads() throws {
        try withFixture { fixture in
            try writeCompletedJournal(fixture)
            var snapshots = 0
            let transport = NormalEfficiencyTransport { request in
                XCTFail("Completed normal sets must reuse the freshly reconciled snapshot: \(request.url?.path ?? "")")
                throw ReleaseToolError.api("Unexpected transport request")
            }
            let publisher = try Publisher(client: client(transport), journalURL: fixture.journalURL,
                manifest: fixture.manifest, snapshotProvider: { _ in snapshots += 1; return fixture.final },
                sleeper: { _ in })
            try publisher.publish(manifest: fixture.manifest, confirmedVersion: "3.0")
            XCTAssertEqual(snapshots, 2, "One entry and one final global snapshot are sufficient")
            XCTAssertEqual(transport.requests.count, 0, "No extra GETs, transfers, polls or writes for thirty completed sets")
            let journal = try ManifestBuilder.decode(PublishJournal.self, at: fixture.journalURL)
            XCTAssertNotNil(journal.completedAt)
        }
    }

    func testCompletedResumeStillRejectsExternalScreenshotOrderDrift() throws {
        try withFixture { fixture in
            try writeCompletedJournal(fixture)
            let changed = try snapshot(localizations: fixture.final.targetVersion!.localizations.enumerated().map { index, locale in
                guard index == 0 else { return locale }
                let sets = locale.screenshotSets.enumerated().map { setIndex, set -> RemoteScreenshotSet in
                    guard setIndex == 0 else { return set }
                    return RemoteScreenshotSet(id: set.id, displayType: set.displayType,
                        screenshots: Array(set.screenshots.reversed()))
                }
                return RemoteLocalization(id: locale.id, locale: locale.locale,
                    attributes: locale.attributes, screenshotSets: sets)
            })
            try assertRejectedBeforeTransport(fixture, live: changed)
        }
    }

    func testCompletedResumeStillRejectsExternalSetIdentityDrift() throws {
        try withFixture { fixture in
            try writeCompletedJournal(fixture)
            let changed = try snapshot(localizations: fixture.final.targetVersion!.localizations.enumerated().map { index, locale in
                guard index == 0 else { return locale }
                let sets = locale.screenshotSets.enumerated().map { setIndex, set -> RemoteScreenshotSet in
                    RemoteScreenshotSet(id: setIndex == 0 ? "external-replacement" : set.id,
                        displayType: set.displayType, screenshots: set.screenshots)
                }
                return RemoteLocalization(id: locale.id, locale: locale.locale,
                    attributes: locale.attributes, screenshotSets: sets)
            })
            try assertRejectedBeforeTransport(fixture, live: changed)
        }
    }

    func testExistingTargetTextOnlyWorkUsesTwoSnapshotsAndFifteenPatches() throws {
        try withFixture(screenshots: false) { fixture in
            var snapshots = 0
            let transport = NormalEfficiencyTransport { request in
                XCTAssertEqual(request.httpMethod, "PATCH")
                XCTAssertTrue(request.url!.path.hasPrefix("/v1/appStoreVersionLocalizations/"))
                return TransportResponse(data: Data(), statusCode: 204)
            }
            let publisher = try Publisher(client: client(transport), journalURL: fixture.journalURL,
                manifest: fixture.manifest, snapshotProvider: { _ in
                    snapshots += 1
                    return snapshots == 1 ? fixture.baseline : fixture.final
                }, sleeper: { _ in })
            try publisher.publish(manifest: fixture.manifest, confirmedVersion: "3.0")
            XCTAssertEqual(snapshots, 2)
            XCTAssertEqual(transport.requests.count, 15)
        }
    }

    func testIncompleteSetStillReadsCurrentStateAndRejectsDriftBeforeDeletion() throws {
        try withFixture { fixture in
            let first = fixture.baseline.targetVersion!.localizations[0]
            let set = first.screenshotSets[0]
            let transport = NormalEfficiencyTransport { request in
                switch request.url?.path {
                case "/v1/appStoreVersionLocalizations/\(first.id)/appScreenshotSets":
                    return try self.json(.object(["data": .array([.object([
                        "id": .string(set.id), "attributes": .object([
                            "screenshotDisplayType": .string(set.displayType)
                        ])
                    ])])]))
                case "/v1/appScreenshotSets/\(set.id)/appScreenshots":
                    return try self.json(.object(["data": .array([.object([
                        "id": .string("external-image"), "attributes": .object([
                            "sourceFileChecksum": .string("unreviewed-checksum"),
                            "assetDeliveryState": .object(["state": .string("COMPLETE")])
                        ])
                    ])])]))
                default:
                    XCTFail("Fresh drift must stop before any backup or deletion: \(request.url?.path ?? "")")
                    throw ReleaseToolError.api("Unexpected request")
                }
            }
            let publisher = try Publisher(client: client(transport), journalURL: fixture.journalURL,
                manifest: fixture.manifest, snapshotProvider: { _ in fixture.baseline }, sleeper: { _ in })
            XCTAssertThrowsError(try publisher.publish(manifest: fixture.manifest, confirmedVersion: "3.0"))
            XCTAssertEqual(transport.requests.map(\.httpMethod), ["GET", "GET"])
        }
    }

    private func assertRejectedBeforeTransport(_ fixture: Fixture, live: RemoteSnapshot) throws {
        var snapshots = 0
        let transport = NormalEfficiencyTransport { _ in
            XCTFail("External drift must be rejected before another request")
            throw ReleaseToolError.api("Unexpected request")
        }
        let publisher = try Publisher(client: client(transport), journalURL: fixture.journalURL,
            manifest: fixture.manifest, snapshotProvider: { _ in snapshots += 1; return live }, sleeper: { _ in })
        XCTAssertThrowsError(try publisher.publish(manifest: fixture.manifest, confirmedVersion: "3.0"))
        XCTAssertEqual(snapshots, 1)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    private struct Fixture {
        let manifest: PublishManifest
        let baseline: RemoteSnapshot
        let final: RemoteSnapshot
        let journalURL: URL
    }

    private func withFixture(screenshots: Bool = true, _ body: (Fixture) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NormalEfficiency-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let locales = ["en-US", "fr-FR", "de-DE", "ja", "vi", "ko", "zh-Hans", "zh-Hant", "th", "es-ES", "es-MX", "pt-BR", "pt-PT", "ms", "id"]
        let images = try (1...10).map { index -> ManifestScreenshot in
            let data = try opaquePNG(byte: UInt8(index * 20))
            let url = directory.appendingPathComponent("\(index).png")
            try FileIO.write(data: data, to: url)
            return ManifestScreenshot(path: url.path, fileName: url.lastPathComponent,
                byteCount: data.count, sha256: FileIO.sha256(data), md5: FileIO.md5(data), order: index)
        }
        let sets: [ManifestScreenshotSet] = screenshots ? [
            ManifestScreenshotSet(family: "iphone", displayType: "APP_IPHONE_67", pixelWidth: 2, pixelHeight: 3, screenshots: images),
            ManifestScreenshotSet(family: "ipad", displayType: "APP_IPAD_PRO_3GEN_129", pixelWidth: 2, pixelHeight: 3, screenshots: images)
        ] : []
        let normalized = locales.map { locale in
            NormalizedLocaleRelease(appStoreLocale: locale, screenshotConfiguration: locale, whatsNew: "New notes",
                versionMetadata: ["whatsNew": .string("New notes")], appMetadata: [:], sourceFiles: [:])
        }
        let release = NormalizedRelease(version: "3.0", bundleId: "com.example.NormalEfficiency", platform: "IOS",
            sourceReleasePath: "/release.json", sourceDigest: "fixture", localizations: normalized, versionMetadata: [:])
        func remote(_ notes: String) -> [RemoteLocalization] {
            locales.map { locale in
                RemoteLocalization(id: "loc-\(locale)", locale: locale,
                    attributes: [
                        "locale": .string(locale), "whatsNew": .string(notes),
                        "description": .string("Play Go online"),
                        "keywords": .string("go,baduk,weiqi"),
                        "supportUrl": .string("https://example.com/support")
                    ],
                    screenshotSets: sets.map { set in
                        RemoteScreenshotSet(id: "set-\(locale)-\(set.family)", displayType: set.displayType,
                            screenshots: images.map { image in
                                RemoteScreenshot(id: "image-\(locale)-\(set.family)-\(image.order)", fileName: image.fileName,
                                    checksum: image.md5, attributes: [
                                        "sourceFileChecksum": .string(image.md5),
                                        "assetDeliveryState": .object(["state": .string("COMPLETE")])
                                    ])
                            })
                    })
            }
        }
        let baseline = try snapshot(localizations: remote("Old notes"))
        let final = try snapshot(localizations: remote("New notes"))
        let manifestLocales = locales.map { ManifestLocale(appStoreLocale: $0,
            versionMetadata: ["whatsNew": .string("New notes")], appMetadata: [:], screenshotSets: sets) }
        let capture: JSONValue = .object(["expectedScreenshotCount": .number(screenshots ? 300 : 0)])
        let draft = PublishManifest(schemaVersion: 1, generatedAt: "fixture", release: release,
            remoteSnapshot: baseline, remoteFingerprint: baseline.fingerprint, captureMetadata: capture,
            localizations: manifestLocales, manifestDigest: "")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifest = PublishManifest(schemaVersion: 1, generatedAt: draft.generatedAt, release: release,
            remoteSnapshot: baseline, remoteFingerprint: baseline.fingerprint, captureMetadata: capture,
            localizations: manifestLocales, manifestDigest: FileIO.sha256(try encoder.encode(draft)))
        try body(Fixture(manifest: manifest, baseline: baseline, final: final,
            journalURL: directory.appendingPathComponent("journal.json")))
    }

    private func snapshot(localizations: [RemoteLocalization]) throws -> RemoteSnapshot {
        let target = RemoteVersion(id: "version", versionString: "3.0", state: "PREPARE_FOR_SUBMISSION",
            attributes: ["versionString": .string("3.0"), "platform": .string("IOS")], localizations: localizations)
        let appInfo = RemoteAppInfo(id: "info", state: "PREPARE_FOR_SUBMISSION",
            localizations: localizations.map { RemoteAppInfoLocalization(id: "app-\($0.locale)", locale: $0.locale,
                attributes: [
                    "locale": .string($0.locale), "name": .string("Example"),
                    "subtitle": .string("Play Go online"),
                    "privacyPolicyUrl": .string("https://example.com/privacy")
                ]) })
        let draft = RemoteSnapshot(capturedAt: "fixture", fingerprint: "", appId: "app",
            bundleId: "com.example.NormalEfficiency", platform: "IOS", requestedVersion: "3.0",
            targetVersion: target, sourceVersion: nil, appInfo: appInfo)
        return RemoteSnapshot(capturedAt: draft.capturedAt, fingerprint: try SnapshotService.fingerprint(snapshot: draft),
            appId: draft.appId, bundleId: draft.bundleId, platform: draft.platform, requestedVersion: draft.requestedVersion,
            targetVersion: target, sourceVersion: nil, appInfo: appInfo)
    }

    private func writeCompletedJournal(_ fixture: Fixture) throws {
        var operations = [JournalOperation]()
        for locale in fixture.manifest.localizations {
            for set in locale.screenshotSets {
                for suffix in ["order", "complete"] {
                    operations.append(JournalOperation(key: "screenshots:\(locale.appStoreLocale):\(set.family):\(suffix)",
                        status: "complete", timestamp: "fixture", detail: "set-\(locale.appStoreLocale)-\(set.family)"))
                }
            }
            operations.append(JournalOperation(key: "version-locale:\(locale.appStoreLocale):metadata",
                status: "complete", timestamp: "fixture", detail: "loc-\(locale.appStoreLocale)"))
        }
        try FileIO.writeJSON(PublishJournal(version: "3.0", manifestDigest: fixture.manifest.manifestDigest,
            startedAt: "fixture", operations: operations), to: fixture.journalURL)
    }

    private func client(_ transport: HTTPTransport) -> ASCAPIClient {
        ASCAPIClient(credentials: ASCCredentials(keyId: "KEY", issuerId: "fixture",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation),
            baseURL: URL(string: "https://api.example")!, transport: transport, maxRetries: 0)
    }

    private func json(_ value: JSONValue) throws -> TransportResponse {
        TransportResponse(data: try JSONEncoder().encode(value), statusCode: 200)
    }

    private func opaquePNG(byte: UInt8) throws -> Data {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(repeating: byte, count: 24) as CFData))
        let image = try XCTUnwrap(CGImage(width: 2, height: 3, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 1] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}

private final class NormalEfficiencyTransport: HTTPTransport, @unchecked Sendable {
    private let handler: (URLRequest) throws -> TransportResponse
    private(set) var requests: [URLRequest] = []
    init(_ handler: @escaping (URLRequest) throws -> TransportResponse) { self.handler = handler }
    func send(_ request: URLRequest) throws -> TransportResponse {
        requests.append(request)
        return try handler(request)
    }
}
