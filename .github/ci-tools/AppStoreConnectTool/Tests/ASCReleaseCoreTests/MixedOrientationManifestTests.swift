import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ASCReleaseCore

final class MixedOrientationManifestTests: XCTestCase {
    func testOptedInSetPreservesPortraitAndLandscapeDimensions() throws {
        try fixture(second: (20, 10), optIn: true) { manifest in
            let set = manifest.localizations[0].screenshotSets[0]
            XCTAssertEqual(set.allowsMixedOrientations, true)
            XCTAssertEqual(set.screenshots.map(\.pixelWidth), [10, 20])
            XCTAssertEqual(set.screenshots.map(\.pixelHeight), [20, 10])
            try ManifestBuilder.verify(manifest)
        }
    }

    func testTransposeRequiresOptInForPhoneAndPad() throws {
        for family in ["iphone-6.9", "ipad-13"] {
            XCTAssertThrowsError(try fixture(second: (20, 10), optIn: nil, family: family) { _ in })
        }
    }

    func testMixedHardwareResolutionIsRejectedEvenWhenAcceptedByFamily() throws {
        XCTAssertThrowsError(try fixture(second: (11, 21), optIn: true) { _ in })
    }

    func testMalformedDimensionsFailEvenWithRecomputedManifestDigest() throws {
        try fixture(second: (20, 10), optIn: true) { manifest in
            let original = manifest.localizations[0].screenshotSets[0].screenshots
            for size: (Int?, Int?) in [(nil, 10), (20, nil), (nil, nil), (0, 10), (-1, 10), (21, 10)] {
                let old = original[1]
                let replacement = ManifestScreenshot(
                    path: old.path, fileName: old.fileName, byteCount: old.byteCount,
                    sha256: old.sha256, md5: old.md5, order: old.order,
                    pixelWidth: size.0, pixelHeight: size.1
                )
                let altered = try resigned(manifest, images: [original[0], replacement])
                XCTAssertThrowsError(try ManifestBuilder.verify(altered), "dimensions \(size)")
            }
        }
    }

    func testLegacyEncodingAndDigestRetainOmittedOptionalFields() throws {
        try fixture(second: (10, 20), optIn: nil) { manifest in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(manifest)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let locale = (json["localizations"] as! [[String: Any]])[0]
            let set = (locale["screenshotSets"] as! [[String: Any]])[0]
            XCTAssertNil(set["allowsMixedOrientations"])
            for image in set["screenshots"] as! [[String: Any]] {
                XCTAssertNil(image["pixelWidth"])
                XCTAssertNil(image["pixelHeight"])
            }
            let decoded = try JSONDecoder().decode(PublishManifest.self, from: data)
            XCTAssertEqual(try encoder.encode(decoded), data)
            try ManifestBuilder.verify(decoded)
        }
    }

    func testMixedOptInMustBeBoolean() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        var config = configuration(optIn: true, family: "iphone-6.9")
        var families = config["screenshotFamilies"]!.arrayValue!
        var family = families[0].objectValue!
        family["allowsMixedOrientations"] = .string("true")
        families[0] = .object(family)
        config["screenshotFamilies"] = .array(families)
        try FileIO.writeJSONValue(.object(config), to: url)
        XCTAssertThrowsError(try LocaleConfiguration.load(from: url))
    }

    func testPublishDryRunNeedsNoCredentialsOrJournalAndRejectsWrongSuppliedDigest() throws {
        try fixture(second: (10, 20), optIn: nil) { manifest in
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.appendingPathComponent("manifest.json")
            let journal = directory.appendingPathComponent("never-created.json")
            try FileIO.writeJSON(manifest, to: path)
            let executable = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("app-store-connect-tool")
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))
            func command(_ digest: String) throws -> (Int32, String) {
                let process = Process(), pipe = Pipe()
                process.executableURL = executable
                process.arguments = ["publish", "--manifest", path.path, "--confirm-version", "3.0",
                    "--confirm-manifest-digest", digest, "--journal", journal.path, "--dry-run", "true"]
                var environment = ProcessInfo.processInfo.environment
                environment["ASC_KEY_ID"] = "test-unused"
                environment["ASC_ISSUER_ID"] = "test-unused"
                environment["ASC_PRIVATE_KEY_PATH"] = "/nonexistent-test-only-unused-key.p8"
                process.environment = environment; process.standardOutput = pipe; process.standardError = pipe
                try process.run(); process.waitUntilExit()
                return (process.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
            }
            let successful = try command(manifest.manifestDigest)
            XCTAssertEqual(successful.0, 0, successful.1)
            XCTAssertTrue(successful.1.contains("no credentials, journal, requests or mutations"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
            let refused = try command(String(repeating: "0", count: 64))
            XCTAssertNotEqual(refused.0, 0)
            XCTAssertTrue(refused.1.contains("digest confirmation differs"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        }
    }

    func testPublisherRejectsWrongOptionalLegacyDigestBeforeLiveSnapshot() throws {
        try fixture(second: (10, 20), optIn: nil) { manifest in
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let client = ASCAPIClient(credentials: ASCCredentials(keyId: "test", issuerId: "test",
                privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation))
            var snapshots = 0
            let publisher = try Publisher(client: client, journalURL: directory.appendingPathComponent("journal.json"),
                manifest: manifest, snapshotProvider: { _ in
                    snapshots += 1; throw ReleaseToolError.validation("Unexpected live snapshot")
                })
            XCTAssertThrowsError(try publisher.publish(manifest: manifest, confirmedVersion: "3.0",
                confirmedManifestDigest: String(repeating: "0", count: 64)))
            XCTAssertEqual(snapshots, 0)
        }
    }

    private func fixture(
        second: (Int, Int), optIn: Bool?, family: String = "iphone-6.9",
        body: (PublishManifest) throws -> Void
    ) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("config.json")
        try FileIO.writeJSONValue(.object(configuration(optIn: optIn, family: family)), to: config)
        let release = NormalizedRelease(
            version: "3.0", bundleId: "com.example.App", platform: "IOS",
            sourceReleasePath: "/release.json", sourceDigest: "source",
            localizations: [NormalizedLocaleRelease(
                appStoreLocale: "en-US", screenshotConfiguration: "en-US", whatsNew: "Notes",
                versionMetadata: ["whatsNew": .string("Notes")], appMetadata: [:], sourceFiles: [:]
            )], versionMetadata: [:]
        )
        let releaseURL = directory.appendingPathComponent("release.json")
        try FileIO.writeJSON(release, to: releaseURL)
        let version = RemoteVersion(
            id: "version", versionString: "3.0", state: "PREPARE_FOR_SUBMISSION",
            attributes: ["versionString": .string("3.0")],
            localizations: [RemoteLocalization(id: "loc", locale: "en-US", attributes: ["locale": .string("en-US")], screenshotSets: [])]
        )
        let info = RemoteAppInfo(id: "info", state: "PREPARE_FOR_SUBMISSION", localizations: [
            RemoteAppInfoLocalization(id: "info-loc", locale: "en-US", attributes: ["locale": .string("en-US")])
        ])
        let draft = RemoteSnapshot(
            capturedAt: "now", fingerprint: "", appId: "app", bundleId: "com.example.App",
            platform: "IOS", requestedVersion: "3.0", targetVersion: version, sourceVersion: version, appInfo: info
        )
        let snapshot = RemoteSnapshot(
            capturedAt: draft.capturedAt, fingerprint: try SnapshotService.fingerprint(snapshot: draft),
            appId: draft.appId, bundleId: draft.bundleId, platform: draft.platform,
            requestedVersion: draft.requestedVersion, targetVersion: version, sourceVersion: version, appInfo: info
        )
        let snapshotURL = directory.appendingPathComponent("snapshot.json")
        try FileIO.writeJSON(snapshot, to: snapshotURL)
        let metadata = directory.appendingPathComponent("capture.json")
        try FileIO.writeJSONValue(.object([
            "locales": .array([.string("en-US")]), "expectedScreenshotCount": .number(2),
            "devices": .object([family: .object([:])]),
            "scenes": .object([family: .array([.string("01"), .string("02")])])
        ]), to: metadata)
        let images = directory.appendingPathComponent("screenshots/en-US/\(family)")
        try FileIO.write(data: png(width: 10, height: 20), to: images.appendingPathComponent("01.png"))
        try FileIO.write(data: png(width: second.0, height: second.1), to: images.appendingPathComponent("02.png"))
        let manifest = try ManifestBuilder.build(
            releaseURL: releaseURL, configurationURL: config,
            screenshotsRoot: directory.appendingPathComponent("screenshots"), captureMetadataURL: metadata,
            remoteSnapshotURL: snapshotURL, outputURL: directory.appendingPathComponent("manifest.json"),
            reviewHTMLURL: directory.appendingPathComponent("review.html")
        )
        try body(manifest)
    }

    private func configuration(optIn: Bool?, family: String) -> [String: JSONValue] {
        var value: [String: JSONValue] = [
            "name": .string(family), "directory": .string(family), "displayType": .string("TEST_DISPLAY"),
            "expectedCount": .number(2), "pixelWidth": .number(10), "pixelHeight": .number(20),
            "additionalPixelSizes": .array([.object(["pixelWidth": .number(11), "pixelHeight": .number(21)])])
        ]
        if let optIn { value["allowsMixedOrientations"] = .bool(optIn) }
        return ["bundleId": .string("com.example.App"), "localizations": .array([.object([
            "appStoreLocale": .string("en-US"), "screenshotConfiguration": .string("en-US")
        ])]), "screenshotFamilies": .array([.object(value)])]
    }

    private func resigned(_ original: PublishManifest, images: [ManifestScreenshot]) throws -> PublishManifest {
        let old = original.localizations[0].screenshotSets[0]
        let set = ManifestScreenshotSet(
            family: old.family, displayType: old.displayType, pixelWidth: old.pixelWidth,
            pixelHeight: old.pixelHeight, screenshots: images, allowsMixedOrientations: old.allowsMixedOrientations
        )
        let locale = ManifestLocale(appStoreLocale: "en-US", versionMetadata: original.localizations[0].versionMetadata,
                                    appMetadata: [:], screenshotSets: [set])
        func manifest(_ digest: String) -> PublishManifest {
            PublishManifest(schemaVersion: original.schemaVersion, generatedAt: original.generatedAt,
                release: original.release, remoteSnapshot: original.remoteSnapshot,
                remoteFingerprint: original.remoteFingerprint, captureMetadata: original.captureMetadata,
                localizations: [locale], manifestDigest: digest)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return manifest(FileIO.sha256(try encoder.encode(manifest(""))))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func png(width: Int, height: Int) throws -> Data {
        let provider = CGDataProvider(data: Data(repeating: 96, count: width * height * 3) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
            bytesPerRow: width * 3, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
