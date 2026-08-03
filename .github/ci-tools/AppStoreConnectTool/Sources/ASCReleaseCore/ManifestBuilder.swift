import Foundation

public enum ManifestBuilder {
    public static func build(
        releaseURL: URL,
        configurationURL: URL,
        screenshotsRoot: URL,
        captureMetadataURL: URL,
        remoteSnapshotURL: URL,
        outputURL: URL,
        reviewHTMLURL: URL
    ) throws -> PublishManifest {
        let release = try decode(NormalizedRelease.self, at: releaseURL)
        let configuration = try LocaleConfiguration.load(from: configurationURL)
        let snapshot = try decode(RemoteSnapshot.self, at: remoteSnapshotURL)
        let captureMetadata = try FileIO.readJSON(at: captureMetadataURL)
        try validateCaptureMetadata(captureMetadata, configuration: configuration)
        try SnapshotPreflight.validate(release: release, snapshot: snapshot)
        guard release.bundleId == configuration.bundleId,
              snapshot.bundleId == release.bundleId,
              snapshot.requestedVersion == release.version else {
            throw ReleaseToolError.validation("Release, locale config, and remote snapshot do not agree")
        }

        var locales: [ManifestLocale] = []
        for locale in release.localizations {
            guard let mapping = configuration.localizations.first(where: {
                $0.appStoreLocale == locale.appStoreLocale
            }) else {
                throw ReleaseToolError.validation("Locale \(locale.appStoreLocale) is absent from config")
            }
            var sets: [ManifestScreenshotSet] = []
            for family in configuration.screenshotFamilies {
                let directory = try locateScreenshotDirectory(
                    root: screenshotsRoot,
                    locale: mapping,
                    family: family
                )
                let files = try screenshotFiles(in: directory, expectedCount: family.expectedCount)
                guard let firstFile = files.first else {
                    throw ReleaseToolError.validation(
                        "Screenshot family \(family.name) must contain at least one image"
                    )
                }
                let firstImage = try ImageValidation.decodePNG(
                    Data(contentsOf: firstFile),
                    context: firstFile.path
                )
                let capturedPixelSize = ScreenshotPixelSize(
                    pixelWidth: firstImage.pixelWidth,
                    pixelHeight: firstImage.pixelHeight
                )
                guard family.acceptedPixelSizes.contains(capturedPixelSize) else {
                    let accepted = family.acceptedPixelSizes
                        .map { "\($0.pixelWidth)x\($0.pixelHeight)" }
                        .joined(separator: ", ")
                    throw ReleaseToolError.validation(
                        "Screenshot has \(firstImage.pixelWidth)x\(firstImage.pixelHeight) pixels; "
                            + "expected one of [\(accepted)]: \(firstFile.path)"
                    )
                }
                let screenshots = try files.enumerated().map { index, url in
                        let data = try Data(contentsOf: url)
                        try ImageValidation.validateScreenshot(
                            data,
                            pixelWidth: capturedPixelSize.pixelWidth,
                            pixelHeight: capturedPixelSize.pixelHeight,
                            context: url.path
                        )
                        return ManifestScreenshot(
                            path: url.standardizedFilePath,
                            fileName: url.lastPathComponent,
                            byteCount: data.count,
                            sha256: FileIO.sha256(data),
                            md5: FileIO.md5(data),
                            order: index + 1
                        )
                    }
                sets.append(ManifestScreenshotSet(
                    family: family.name,
                    displayType: family.displayType,
                    pixelWidth: capturedPixelSize.pixelWidth,
                    pixelHeight: capturedPixelSize.pixelHeight,
                    screenshots: screenshots
                ))
            }
            locales.append(ManifestLocale(
                appStoreLocale: locale.appStoreLocale,
                versionMetadata: locale.versionMetadata,
                appMetadata: locale.appMetadata,
                screenshotSets: sets
            ))
        }

        let generatedAt = ISO8601DateFormatter.releaseTool.string(from: Date())
        let draft = PublishManifest(
            schemaVersion: 1,
            generatedAt: generatedAt,
            release: release,
            remoteSnapshot: snapshot,
            remoteFingerprint: snapshot.fingerprint,
            captureMetadata: captureMetadata,
            localizations: locales,
            manifestDigest: ""
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let digest = FileIO.sha256(try encoder.encode(draft))
        let manifest = PublishManifest(
            schemaVersion: 1,
            generatedAt: generatedAt,
            release: release,
            remoteSnapshot: snapshot,
            remoteFingerprint: snapshot.fingerprint,
            captureMetadata: captureMetadata,
            localizations: locales,
            manifestDigest: digest
        )
        try FileIO.writeJSON(manifest, to: outputURL)
        try FileIO.write(data: Data(reviewHTML(manifest: manifest).utf8), to: reviewHTMLURL)
        return manifest
    }

    private static func validateCaptureMetadata(
        _ value: JSONValue,
        configuration: LocaleConfiguration
    ) throws {
        guard let object = value.objectValue else {
            throw ReleaseToolError.validation("Capture metadata must be a JSON object")
        }
        let expectedLocales = Set(configuration.localizations.map(\.screenshotConfiguration))
        guard let rawLocales = object["locales"]?.arrayValue else {
            throw ReleaseToolError.validation("Capture metadata requires locales")
        }
        let actualLocales = Set(rawLocales.compactMap(\.stringValue))
        guard actualLocales == expectedLocales, rawLocales.count == expectedLocales.count else {
            throw ReleaseToolError.validation(
                "Capture metadata locales do not match config; expected \(expectedLocales.sorted()), got \(actualLocales.sorted())"
            )
        }
        let expectedTotal = configuration.localizations.count
            * configuration.screenshotFamilies.reduce(0) { $0 + $1.expectedCount }
        guard object["expectedScreenshotCount"]?.intValue == expectedTotal else {
            throw ReleaseToolError.validation(
                "Capture metadata expectedScreenshotCount must be \(expectedTotal)"
            )
        }
        guard let devices = object["devices"]?.objectValue,
              let scenes = object["scenes"]?.objectValue else {
            throw ReleaseToolError.validation("Capture metadata requires devices and scenes objects")
        }
        for family in configuration.screenshotFamilies {
            guard devices[family.name] != nil || devices[family.directory] != nil else {
                throw ReleaseToolError.validation("Capture metadata is missing device \(family.name)")
            }
            let sceneCount = (scenes[family.name] ?? scenes[family.directory])?.arrayValue?.count
            guard sceneCount == family.expectedCount else {
                throw ReleaseToolError.validation(
                    "Capture metadata requires \(family.expectedCount) scenes for \(family.name)"
                )
            }
        }
    }

    public static func verify(_ manifest: PublishManifest) throws {
        guard manifest.schemaVersion == 1 else {
            throw ReleaseToolError.validation("Unsupported manifest schemaVersion")
        }
        guard manifest.remoteFingerprint == manifest.remoteSnapshot.fingerprint,
              try SnapshotService.fingerprint(snapshot: manifest.remoteSnapshot)
                == manifest.remoteFingerprint else {
            throw ReleaseToolError.validation(
                "Manifest remote snapshot fingerprint does not match its contents"
            )
        }
        try SnapshotPreflight.validate(
            release: manifest.release,
            snapshot: manifest.remoteSnapshot
        )
        let releaseLocales = Dictionary(
            uniqueKeysWithValues: manifest.release.localizations.map { ($0.appStoreLocale, $0) }
        )
        guard releaseLocales.count == manifest.release.localizations.count,
              Set(releaseLocales.keys) == Set(manifest.localizations.map(\.appStoreLocale)),
              Set(manifest.localizations.map(\.appStoreLocale)).count == manifest.localizations.count else {
            throw ReleaseToolError.validation("Manifest locale set does not match the normalized release")
        }
        var screenshotCount = 0
        for locale in manifest.localizations {
            guard let releaseLocale = releaseLocales[locale.appStoreLocale],
                  locale.versionMetadata == releaseLocale.versionMetadata,
                  locale.appMetadata == releaseLocale.appMetadata else {
                throw ReleaseToolError.validation(
                    "Manifest metadata differs from normalized release for \(locale.appStoreLocale)"
                )
            }
            guard Set(locale.screenshotSets.map(\.displayType)).count == locale.screenshotSets.count,
                  Set(locale.screenshotSets.map(\.family)).count == locale.screenshotSets.count else {
                throw ReleaseToolError.validation("Manifest contains duplicate screenshot sets")
            }
            for set in locale.screenshotSets {
                guard set.pixelWidth > 0, set.pixelHeight > 0,
                      set.screenshots.map(\.order) == set.screenshots.indices.map({ $0 + 1 }) else {
                    throw ReleaseToolError.validation("Manifest screenshot order or dimensions are invalid")
                }
                screenshotCount += set.screenshots.count
            }
        }
        guard manifest.captureMetadata["expectedScreenshotCount"]?.intValue == screenshotCount else {
            throw ReleaseToolError.validation(
                "Manifest screenshot count differs from reviewed capture metadata"
            )
        }
        let draft = PublishManifest(
            schemaVersion: manifest.schemaVersion,
            generatedAt: manifest.generatedAt,
            release: manifest.release,
            remoteSnapshot: manifest.remoteSnapshot,
            remoteFingerprint: manifest.remoteFingerprint,
            captureMetadata: manifest.captureMetadata,
            localizations: manifest.localizations,
            manifestDigest: ""
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard FileIO.sha256(try encoder.encode(draft)) == manifest.manifestDigest else {
            throw ReleaseToolError.validation("Manifest digest does not match its contents")
        }
        for locale in manifest.localizations {
            for set in locale.screenshotSets {
                for screenshot in set.screenshots {
                    let data: Data
                    do { data = try Data(contentsOf: URL(fileURLWithPath: screenshot.path)) }
                    catch { throw ReleaseToolError.file("Missing screenshot \(screenshot.path)") }
                    guard data.count == screenshot.byteCount,
                          FileIO.sha256(data) == screenshot.sha256,
                          FileIO.md5(data) == screenshot.md5 else {
                        throw ReleaseToolError.validation("Screenshot changed after review: \(screenshot.path)")
                    }
                    try ImageValidation.validateScreenshot(
                        data,
                        pixelWidth: set.pixelWidth,
                        pixelHeight: set.pixelHeight,
                        context: screenshot.path
                    )
                }
            }
        }
    }

    public static func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        do { return try JSONDecoder().decode(type, from: Data(contentsOf: url)) }
        catch {
            throw ReleaseToolError.file("Could not decode \(url.path): \(error.localizedDescription)")
        }
    }

    private static func locateScreenshotDirectory(
        root: URL,
        locale: LocaleMapping,
        family: ScreenshotFamily
    ) throws -> URL {
        let candidates = [
            root.appendingPathComponent(locale.screenshotConfiguration).appendingPathComponent(family.directory),
            root.appendingPathComponent("screenshots").appendingPathComponent(locale.screenshotConfiguration)
                .appendingPathComponent(family.directory),
            root.appendingPathComponent(locale.appStoreLocale).appendingPathComponent(family.directory),
            root.appendingPathComponent("screenshots").appendingPathComponent(locale.appStoreLocale)
                .appendingPathComponent(family.directory),
        ]
        if let match = candidates.first(where: {
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }) { return match }
        throw ReleaseToolError.file(
            "No screenshot directory for \(locale.screenshotConfiguration)/\(family.directory) under \(root.path)"
        )
    }

    private static func screenshotFiles(in directory: URL, expectedCount: Int) throws -> [URL] {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard files.count == expectedCount else {
            throw ReleaseToolError.validation(
                "Expected \(expectedCount) PNG files in \(directory.path); found \(files.count)"
            )
        }
        return files
    }

    private static func reviewHTML(manifest: PublishManifest) -> String {
        var body = """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>App Store release \(escape(manifest.release.version)) review</title>
        <style>
        body{font:15px -apple-system,BlinkMacSystemFont,sans-serif;margin:24px;color:#202124}
        h1,h2,h3{margin-top:1.4em}.locale{border-top:1px solid #ddd;margin-top:32px}
        .notes{white-space:pre-wrap;background:#f5f5f7;padding:16px;border-radius:8px}
        .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:14px}
        figure{margin:0}img{width:100%;height:260px;object-fit:contain;background:#eee}
        figcaption{font-size:12px;overflow-wrap:anywhere}.metadata{font-family:ui-monospace,monospace}
        </style></head><body>
        <h1>App Store release \(escape(manifest.release.version))</h1>
        <p>Bundle: <code>\(escape(manifest.release.bundleId))</code><br>
        Remote fingerprint: <code>\(escape(manifest.remoteFingerprint))</code><br>
        Manifest digest: <code>\(escape(manifest.manifestDigest))</code></p>
        """
        let baselineCopyright = manifest.remoteSnapshot.targetVersion?.attributes["copyright"]
            ?? manifest.remoteSnapshot.sourceVersion?.attributes["copyright"]
            ?? .null
        let effectiveCopyright = manifest.release.versionMetadata["copyright"]
            ?? baselineCopyright
        let copyrightMode = manifest.release.versionMetadata["copyright"] == nil ? "inherited" : "explicit"
        body += "<h2>Version-wide metadata</h2><div class=\"metadata\">"
        body += "copyright (\(copyrightMode)): \(escape(render(baselineCopyright))) → \(escape(render(effectiveCopyright)))"
        body += "</div>"
        for locale in manifest.localizations {
            body += "<section class=\"locale\"><h2>\(escape(locale.appStoreLocale))</h2>"
            if let notes = locale.versionMetadata["whatsNew"]?.stringValue {
                body += "<h3>What’s New</h3><div class=\"notes\">\(escape(notes))</div>"
            }
            let baselineVersion = manifest.remoteSnapshot.targetVersion?.localizations
                .first { $0.locale == locale.appStoreLocale }
                ?? manifest.remoteSnapshot.sourceVersion?.localizations
                    .first { $0.locale == locale.appStoreLocale }
            body += "<h3>Version-localized metadata changes</h3><div class=\"metadata\">"
            for (key, value) in locale.versionMetadata.sorted(by: { $0.key < $1.key }) {
                let before = baselineVersion?.attributes[key] ?? .null
                body += "\(escape(key)): \(escape(render(before))) → \(escape(render(value)))<br>"
            }
            body += "</div>"
            if !locale.appMetadata.isEmpty {
                let baselineApp = manifest.remoteSnapshot.appInfo?.localizations
                    .first { $0.locale == locale.appStoreLocale }
                body += "<h3>App-wide localized metadata changes</h3><div class=\"metadata\">"
                for (key, value) in locale.appMetadata.sorted(by: { $0.key < $1.key }) {
                    let before = baselineApp?.attributes[key] ?? .null
                    body += "\(escape(key)): \(escape(render(before))) → \(escape(render(value)))<br>"
                }
                body += "</div>"
            }
            for set in locale.screenshotSets {
                body += "<h3>\(escape(set.family)) — \(escape(set.displayType))</h3><div class=\"grid\">"
                for screenshot in set.screenshots {
                    let url = URL(fileURLWithPath: screenshot.path).absoluteString
                    body += "<figure><img src=\"\(escape(url))\"><figcaption>\(screenshot.order). \(escape(screenshot.fileName))</figcaption></figure>"
                }
                body += "</div>"
            }
            body += "</section>"
        }
        body += "</body></html>\n"
        return body
    }

    private static func render(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null (clear)"
        case let .string(string): return string
        default: return String(describing: value.any)
        }
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
