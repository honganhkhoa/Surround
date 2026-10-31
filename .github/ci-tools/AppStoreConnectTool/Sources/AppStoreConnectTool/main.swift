import ASCReleaseCore
import Foundation

private struct Arguments {
    let command: String
    let options: [String: String]

    init(_ raw: [String]) throws {
        guard let command = raw.first, !command.hasPrefix("-") else {
            throw ReleaseToolError.usage(Self.help)
        }
        self.command = command
        var options: [String: String] = [:]
        var index = 1
        while index < raw.count {
            let flag = raw[index]
            guard flag.hasPrefix("--"), index + 1 < raw.count else {
                throw ReleaseToolError.usage("Expected --name value, got \(flag)\n\n\(Self.help)")
            }
            guard options[flag] == nil else {
                throw ReleaseToolError.usage("Duplicate option \(flag)")
            }
            options[flag] = raw[index + 1]
            index += 2
        }
        self.options = options
    }

    func require(_ names: String..., optional: Set<String> = []) throws -> [String] {
        let expected = Set(names).union(optional)
        let unknown = Set(options.keys).subtracting(expected)
        guard unknown.isEmpty else {
            throw ReleaseToolError.usage("Unknown options: \(unknown.sorted().joined(separator: ", "))")
        }
        return try names.map { name in
            guard let value = options[name], !value.isEmpty else {
                throw ReleaseToolError.usage("Missing required option \(name)")
            }
            return value
        }
    }

    static let help = """
    app-store-connect-tool commands:

      init --version V --output DIR --locales-config FILE
      validate-release --release FILE --locales-config FILE --output FILE
      snapshot --release NORMALIZED_JSON --output FILE
      inspect-duo-placement --bundle-id ID --version V --output FILE
      build-duo-placement-plan --inspection FILE --selected-import FILE \\
        --expected-inspection-sha256 SHA256 --expected-import-sha256 SHA256 \\
        --expected-selection-sha256 SHA256 --output FILE
      build-selected-handoff --release NORMALIZED_JSON --snapshot FILE \\
        --selected-import FILE --expected-import-sha256 SHA256 --expected-selection-sha256 SHA256 \\
        --evidence-acceptance FILE --expected-acceptance-sha256 SHA256 \\
        --integrity-report FILE --expected-integrity-sha256 SHA256 \\
        --inspection FILE --expected-inspection-sha256 SHA256 --output FILE
      verify-manifest --manifest FILE
      validate-snapshot --release NORMALIZED_JSON --snapshot REMOTE_SNAPSHOT_JSON
      build-manifest --release NORMALIZED_JSON --locales-config FILE \\
        --screenshots-root DIR --capture-metadata FILE --remote-snapshot FILE \\
        --output FILE --review-html FILE
      build-metadata-only-manifest --release NORMALIZED_JSON --locales-config FILE \\
        --remote-snapshot FILE --expected-source-version V \\
        --output FILE --review-html FILE
      verify-metadata-only-manifest --manifest FILE --locales-config FILE \\
        --expected-source-version V
      publish --manifest FILE --confirm-version V --journal FILE \\
        [--confirm-manifest-digest SHA256] [--dry-run true]
      publish-metadata-only --manifest FILE --locales-config FILE \\
        --expected-source-version V --confirm-version V \\
        --confirm-manifest-digest SHA256 --journal FILE

    snapshot, inspect-duo-placement and both publish commands require ASC_KEY_ID,
    ASC_ISSUER_ID, and ASC_PRIVATE_KEY_PATH. build-duo-placement-plan is offline.
    """
}

private func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        .standardizedFileURL
}

do {
    let raw = Array(CommandLine.arguments.dropFirst())
    if raw.isEmpty || raw == ["--help"] || raw == ["help"] {
        print(Arguments.help)
        exit(EXIT_SUCCESS)
    }
    let arguments = try Arguments(raw)
    switch arguments.command {
    case "init":
        let values = try arguments.require("--version", "--output", "--locales-config")
        let releaseURL = try ReleasePackageInitializer.create(
            version: values[0],
            output: fileURL(values[1]),
            configurationURL: fileURL(values[2])
        )
        print("Created release package: \(releaseURL.path)")

    case "validate-release":
        let values = try arguments.require("--release", "--locales-config", "--output")
        let release = try ReleaseValidator.normalize(
            releaseURL: fileURL(values[0]),
            configurationURL: fileURL(values[1])
        )
        try FileIO.writeJSON(release, to: fileURL(values[2]))
        print("Validated release \(release.version) for \(release.localizations.count) locales")

    case "snapshot":
        let values = try arguments.require("--release", "--output")
        let release = try ManifestBuilder.decode(NormalizedRelease.self, at: fileURL(values[0]))
        let credentials = try ASCCredentials.fromEnvironment()
        let snapshot = try SnapshotService(client: ASCAPIClient(credentials: credentials)).capture(release: release)
        try FileIO.writeJSON(snapshot, to: fileURL(values[1]))
        let target = snapshot.targetVersion == nil ? "missing (will be created on publish)" : "existing"
        print("Captured App Store Connect snapshot for \(release.version): \(target)")

    case "inspect-duo-placement":
        let values = try arguments.require("--bundle-id", "--version", "--output")
        let output = fileURL(values[2])
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw ReleaseToolError.validation("Inspection output already exists")
        }
        let credentials: ASCCredentials
        do { credentials = try ASCCredentials.fromEnvironment() }
        catch { throw ReleaseToolError.validation("Configured ASC credentials are unavailable; no request was made") }
        let client = ASCAPIClient(credentials: credentials, maxRetries: 0)
        let result = try DuoAssetLibraryInspector(client: client).capture(bundleId: values[0], version: values[1])
        try FileIO.writeJSONValue(result, to: output)
        print("Saved GET-only Duo placement discovery; upload acceptance and publication are not claimed")

    case "validate-snapshot":
        let values = try arguments.require("--release", "--snapshot")
        let release = try ManifestBuilder.decode(NormalizedRelease.self, at: fileURL(values[0]))
        let snapshot = try ManifestBuilder.decode(RemoteSnapshot.self, at: fileURL(values[1]))
        try SnapshotPreflight.validate(release: release, snapshot: snapshot)
        print("Validated App Store Connect metadata preflight for \(release.version)")

    case "build-duo-placement-plan":
        let values = try arguments.require("--inspection", "--selected-import", "--expected-inspection-sha256", "--expected-import-sha256", "--expected-selection-sha256", "--output")
        let output = fileURL(values[5])
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw ReleaseToolError.validation("Offline plan output already exists")
        }
        let plan = try DuoAssetLibraryPlanBuilder.build(inspectionURL: fileURL(values[0]), expectedInspectionSHA256: values[2], importURL: fileURL(values[1]),
            expectedImportSHA256: values[3], expectedSelectionSHA256: values[4])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(plan).write(to: output, options: .withoutOverwriting)
        print("Saved offline Duo request plan; no requests, uploads or qualification changes were performed")

    case "build-selected-handoff":
        let v = try arguments.require("--release", "--snapshot", "--selected-import", "--expected-import-sha256",
            "--expected-selection-sha256", "--evidence-acceptance", "--expected-acceptance-sha256",
            "--inspection", "--expected-inspection-sha256", "--integrity-report", "--expected-integrity-sha256", "--output")
        let output = fileURL(v[11])
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw ReleaseToolError.validation("Selected handoff output already exists")
        }
        let release = try ManifestBuilder.decode(NormalizedRelease.self, at: fileURL(v[0]))
        let snapshot = try ManifestBuilder.decode(RemoteSnapshot.self, at: fileURL(v[1]))
        try SnapshotPreflight.validate(release: release, snapshot: snapshot)
        let handoff = try SelectedReleaseHandoff.build(
            importFile: HandoffFileBinding(path: fileURL(v[2]).path, sha256: v[3]), selectionSHA256: v[4],
            acceptance: HandoffFileBinding(path: fileURL(v[5]).path, sha256: v[6]),
            integrityVerification: HandoffFileBinding(path: fileURL(v[9]).path, sha256: v[10]),
            inspection: HandoffFileBinding(path: fileURL(v[7]).path, sha256: v[8]), release: release, snapshot: snapshot)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(handoff).write(to: output, options: .withoutOverwriting)
        print("Saved admitted selected handoff with actual target IDs; publishing remains separately authorized")

    case "verify-manifest":
        let v = try arguments.require("--manifest")
        let manifest = try ManifestBuilder.decode(PublishManifest.self, at: fileURL(v[0]))
        try ManifestBuilder.verify(manifest)
        print("Verified handoff \(manifest.manifestDigest) offline; no credentials, journal or network used")

    case "build-manifest":
        let values = try arguments.require(
            "--release", "--locales-config", "--screenshots-root", "--capture-metadata",
            "--remote-snapshot", "--output", "--review-html"
        )
        let manifest = try ManifestBuilder.build(
            releaseURL: fileURL(values[0]),
            configurationURL: fileURL(values[1]),
            screenshotsRoot: fileURL(values[2]),
            captureMetadataURL: fileURL(values[3]),
            remoteSnapshotURL: fileURL(values[4]),
            outputURL: fileURL(values[5]),
            reviewHTMLURL: fileURL(values[6])
        )
        let count = manifest.localizations.flatMap(\.screenshotSets).flatMap(\.screenshots).count
        print("Built reviewed manifest \(manifest.manifestDigest) with \(count) screenshots")

    case "build-metadata-only-manifest":
        let values = try arguments.require(
            "--release", "--locales-config", "--remote-snapshot",
            "--expected-source-version", "--output", "--review-html"
        )
        let manifest = try MetadataOnlyManifestBuilder.build(
            releaseURL: fileURL(values[0]),
            configurationURL: fileURL(values[1]),
            remoteSnapshotURL: fileURL(values[2]),
            expectedSourceVersion: values[3],
            outputURL: fileURL(values[4]),
            reviewHTMLURL: fileURL(values[5])
        )
        print(
            "Built reviewed metadata-only manifest \(manifest.manifestDigest) "
                + "for \(manifest.localizations.count) locales and zero screenshots"
        )

    case "verify-metadata-only-manifest":
        let values = try arguments.require(
            "--manifest", "--locales-config", "--expected-source-version"
        )
        let manifest = try ManifestBuilder.decode(PublishManifest.self, at: fileURL(values[0]))
        let configuration = try LocaleConfiguration.load(from: fileURL(values[1]))
        try MetadataOnlyManifestBuilder.verify(
            manifest,
            configuration: configuration,
            expectedSourceVersion: values[2]
        )
        print("Verified metadata-only manifest \(manifest.manifestDigest)")

    case "publish":
        let values = try arguments.require("--manifest", "--confirm-version", "--journal",
            optional: ["--confirm-manifest-digest", "--dry-run"])
        let manifest = try ManifestBuilder.decode(PublishManifest.self, at: fileURL(values[0]))
        try ManifestBuilder.verify(manifest)
        guard values[1] == manifest.release.version else { throw ReleaseToolError.validation("Version confirmation differs from manifest") }
        if let digest = arguments.options["--confirm-manifest-digest"], digest != manifest.manifestDigest {
            throw ReleaseToolError.validation("Manifest digest confirmation differs from reviewed contents")
        }
        if manifest.captureMetadata["mode"] == .string(SelectedReleaseHandoff.mode) {
            guard arguments.options["--confirm-manifest-digest"] == manifest.manifestDigest else {
                throw ReleaseToolError.validation("Selected release requires its reviewed aggregate manifest digest")
            }
        }
        if let dryRun = arguments.options["--dry-run"] {
            guard dryRun == "true" else { throw ReleaseToolError.usage("--dry-run accepts only true") }
            print("Dry run verified \(manifest.manifestDigest); no credentials, journal, requests or mutations")
            exit(EXIT_SUCCESS)
        }
        let credentials = try ASCCredentials.fromEnvironment()
        let publisher = try Publisher(
            client: ASCAPIClient(credentials: credentials),
            journalURL: fileURL(values[2]),
            manifest: manifest
        )
        try publisher.publish(manifest: manifest, confirmedVersion: values[1],
                              confirmedManifestDigest: arguments.options["--confirm-manifest-digest"])
        print("Published and verified App Store metadata for version \(manifest.release.version)")

    case "publish-metadata-only":
        let values = try arguments.require(
            "--manifest", "--locales-config", "--expected-source-version",
            "--confirm-version", "--confirm-manifest-digest", "--journal"
        )
        let manifest = try ManifestBuilder.decode(PublishManifest.self, at: fileURL(values[0]))
        let configuration = try LocaleConfiguration.load(from: fileURL(values[1]))
        try MetadataOnlyManifestBuilder.verify(
            manifest,
            configuration: configuration,
            expectedSourceVersion: values[2]
        )
        let credentials = try ASCCredentials.fromEnvironment()
        let publisher = MetadataOnlyPublisher(
            client: ASCAPIClient(credentials: credentials),
            journalURL: fileURL(values[5]),
            configuration: configuration,
            expectedSourceVersion: values[2]
        )
        try publisher.publish(
            manifest: manifest,
            confirmedVersion: values[3],
            confirmedManifestDigest: values[4]
        )
        print(
            "Published and verified exactly \(manifest.localizations.count) What's New fields "
                + "for \(manifest.release.version); screenshots and App Info were unchanged"
        )

    default:
        throw ReleaseToolError.usage("Unknown command \(arguments.command)\n\n\(Arguments.help)")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
