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

    func require(_ names: String...) throws -> [String] {
        let expected = Set(names)
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
      validate-snapshot --release NORMALIZED_JSON --snapshot REMOTE_SNAPSHOT_JSON
      build-manifest --release NORMALIZED_JSON --locales-config FILE \\
        --screenshots-root DIR --capture-metadata FILE --remote-snapshot FILE \\
        --output FILE --review-html FILE
      publish --manifest FILE --confirm-version V --journal FILE

    snapshot and publish require ASC_KEY_ID, ASC_ISSUER_ID, and ASC_PRIVATE_KEY_PATH.
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

    case "validate-snapshot":
        let values = try arguments.require("--release", "--snapshot")
        let release = try ManifestBuilder.decode(NormalizedRelease.self, at: fileURL(values[0]))
        let snapshot = try ManifestBuilder.decode(RemoteSnapshot.self, at: fileURL(values[1]))
        try SnapshotPreflight.validate(release: release, snapshot: snapshot)
        print("Validated App Store Connect metadata preflight for \(release.version)")

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

    case "publish":
        let values = try arguments.require("--manifest", "--confirm-version", "--journal")
        let manifest = try ManifestBuilder.decode(PublishManifest.self, at: fileURL(values[0]))
        let credentials = try ASCCredentials.fromEnvironment()
        let publisher = try Publisher(
            client: ASCAPIClient(credentials: credentials),
            journalURL: fileURL(values[2]),
            manifest: manifest
        )
        try publisher.publish(manifest: manifest, confirmedVersion: values[1])
        print("Published and verified App Store metadata for version \(manifest.release.version)")

    default:
        throw ReleaseToolError.usage("Unknown command \(arguments.command)\n\n\(Arguments.help)")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
