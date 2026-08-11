import Foundation

public enum ReleasePackageInitializer {
    public static func create(version: String, output: URL, configurationURL: URL) throws -> URL {
        try ReleaseValidator.validateVersion(version)
        let configuration = try LocaleConfiguration.load(from: configurationURL)
        let manager = FileManager.default
        if manager.fileExists(atPath: output.path) {
            let contents = try manager.contentsOfDirectory(atPath: output.path)
            guard contents.isEmpty else {
                throw ReleaseToolError.file("Refusing to overwrite nonempty directory \(output.path)")
            }
        }
        try manager.createDirectory(at: output, withIntermediateDirectories: true)

        var localizationObjects: [String: JSONValue] = [:]
        for mapping in configuration.localizations {
            let relativePath = "localizations/\(mapping.appStoreLocale)/whats-new.txt"
            let noteURL = output.appendingPathComponent(relativePath)
            try FileIO.write(data: Data(), to: noteURL)
            localizationObjects[mapping.appStoreLocale] = .object([
                "whatsNewFile": .string(relativePath),
            ])
        }

        let release: JSONValue = .object([
            "schemaVersion": .number(1),
            "version": .string(version),
            "localizations": .object(localizationObjects),
        ])
        let releaseURL = output.appendingPathComponent("release.json")
        try FileIO.writeJSONValue(release, to: releaseURL)
        return releaseURL
    }
}

public enum ReleaseValidator {
    private static let topLevelFields: Set<String> = [
        "schemaVersion", "version", "localizations", "versionMetadata", "copyright",
    ]
    private static let versionFields: Set<String> = [
        "description", "keywords", "promotionalText", "supportUrl", "marketingUrl",
    ]
    private static let appFields: Set<String> = ["name", "subtitle", "privacyPolicyUrl"]
    private static let nullableFields: Set<String> = [
        "keywords", "promotionalText", "marketingUrl", "subtitle",
    ]
    private static let fileBackedFields: Set<String> = ["description", "promotionalText"]
    private static let characterLimits: [String: Int] = [
        "whatsNew": 4_000,
        "description": 4_000,
        "keywords": 100,
        "promotionalText": 170,
        "subtitle": 30,
        "name": 30,
        "supportUrl": 255,
        "marketingUrl": 255,
        "privacyPolicyUrl": 255,
        "copyright": 100,
    ]
    private static let URLFields: Set<String> = [
        "supportUrl", "marketingUrl", "privacyPolicyUrl",
    ]

    public static func normalize(releaseURL: URL, configurationURL: URL) throws -> NormalizedRelease {
        let configuration = try LocaleConfiguration.load(from: configurationURL)
        let rootValue = try FileIO.readJSON(at: releaseURL)
        guard let root = rootValue.objectValue else {
            throw ReleaseToolError.validation("Release file must be a JSON object")
        }
        try rejectUnknownKeys(root, allowed: topLevelFields, context: "release")
        let schemaVersion = root["schemaVersion"]?.intValue ?? 1
        guard schemaVersion == 1 else {
            throw ReleaseToolError.validation("Unsupported release schemaVersion \(schemaVersion)")
        }
        guard let version = root["version"]?.stringValue else {
            throw ReleaseToolError.validation("Release file requires version")
        }
        try validateVersion(version)
        guard let localizations = root["localizations"]?.objectValue else {
            throw ReleaseToolError.validation("Release file requires a localizations object")
        }

        let expectedLocales = Set(configuration.localizations.map(\.appStoreLocale))
        let unexpected = Set(localizations.keys).subtracting(expectedLocales).sorted()
        guard unexpected.isEmpty else {
            throw ReleaseToolError.validation(
                "Release contains locales not present in locale config: \(unexpected.joined(separator: ", "))"
            )
        }

        let baseURL = releaseURL.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        var normalizedLocales: [NormalizedLocaleRelease] = []
        var digestParts = [try FileIO.canonicalData(rootValue)]

        for mapping in configuration.localizations {
            guard let entry = localizations[mapping.appStoreLocale]?.objectValue else {
                throw ReleaseToolError.validation(
                    "Release is missing localization \(mapping.appStoreLocale)"
                )
            }
            var sourceFiles: [String: String] = [:]
            let whatsNew = try requiredFileText(
                field: "whatsNew",
                entry: entry,
                baseURL: baseURL,
                sourceFiles: &sourceFiles,
                digestParts: &digestParts
            )
            try validateString(whatsNew, field: "whatsNew", locale: mapping.appStoreLocale)

            var versionMetadata: [String: JSONValue] = ["whatsNew": .string(whatsNew)]
            var appMetadata: [String: JSONValue] = [:]
            let nestedVersion = try metadataObject(entry["versionMetadata"], name: "versionMetadata")
            let nestedApp = try metadataObject(entry["appMetadata"], name: "appMetadata")
            try rejectUnknownKeys(
                nestedVersion,
                allowed: versionFields,
                context: "versionMetadata for \(mapping.appStoreLocale)"
            )
            try rejectUnknownKeys(
                nestedApp,
                allowed: appFields,
                context: "appMetadata for \(mapping.appStoreLocale)"
            )

            for field in versionFields.sorted() {
                if let value = try resolveOptionalField(
                    field: field,
                    direct: entry,
                    nested: nestedVersion,
                    baseURL: baseURL,
                    sourceFiles: &sourceFiles,
                    digestParts: &digestParts
                ) {
                    try validateMetadata(value, field: field, locale: mapping.appStoreLocale)
                    versionMetadata[field] = value
                }
            }
            for field in appFields.sorted() {
                if let value = try resolveOptionalField(
                    field: field,
                    direct: entry,
                    nested: nestedApp,
                    baseURL: baseURL,
                    sourceFiles: &sourceFiles,
                    digestParts: &digestParts
                ) {
                    try validateMetadata(value, field: field, locale: mapping.appStoreLocale)
                    appMetadata[field] = value
                }
            }

            try rejectUnknownFields(entry, locale: mapping.appStoreLocale)
            normalizedLocales.append(NormalizedLocaleRelease(
                appStoreLocale: mapping.appStoreLocale,
                screenshotConfiguration: mapping.screenshotConfiguration,
                whatsNew: whatsNew,
                versionMetadata: versionMetadata,
                appMetadata: appMetadata,
                sourceFiles: sourceFiles
            ))
        }

        var globalMetadata: [String: JSONValue] = [:]
        let nestedGlobal = try metadataObject(root["versionMetadata"], name: "versionMetadata")
        try rejectUnknownKeys(
            nestedGlobal,
            allowed: ["copyright"],
            context: "top-level versionMetadata"
        )
        guard root["copyright"] == nil || nestedGlobal["copyright"] == nil else {
            throw ReleaseToolError.validation("copyright is specified twice")
        }
        if let copyright = root["copyright"] ?? nestedGlobal["copyright"] {
            try validateMetadata(copyright, field: "copyright", locale: nil)
            globalMetadata["copyright"] = copyright
        }

        let sourceDigest = FileIO.sha256(digestParts.reduce(into: Data()) { result, data in
            result.append(data)
            result.append(0)
        })
        return NormalizedRelease(
            schemaVersion: 1,
            version: version,
            bundleId: configuration.bundleId,
            platform: configuration.platform,
            sourceReleasePath: releaseURL.standardizedFilePath,
            sourceDigest: sourceDigest,
            localizations: normalizedLocales,
            versionMetadata: globalMetadata
        )
    }

    public static func validateVersion(_ version: String) throws {
        let pattern = #"^[0-9]+(?:\.[0-9]+){1,2}$"#
        guard version.range(of: pattern, options: .regularExpression) != nil else {
            throw ReleaseToolError.validation(
                "Version must contain two or three numeric components, for example 2.1 or 2.1.0"
            )
        }
    }

    private static func metadataObject(
        _ value: JSONValue?,
        name: String
    ) throws -> [String: JSONValue] {
        guard let value else { return [:] }
        guard let object = value.objectValue else {
            throw ReleaseToolError.validation("\(name) must be an object")
        }
        return object
    }

    private static func requiredFileText(
        field: String,
        entry: [String: JSONValue],
        baseURL: URL,
        sourceFiles: inout [String: String],
        digestParts: inout [Data]
    ) throws -> String {
        let fileKey = "\(field)File"
        guard let path = entry[fileKey]?.stringValue, !path.isEmpty else {
            throw ReleaseToolError.validation("Each localization requires \(fileKey)")
        }
        return try readText(
            path: path,
            field: field,
            baseURL: baseURL,
            sourceFiles: &sourceFiles,
            digestParts: &digestParts
        )
    }

    private static func resolveOptionalField(
        field: String,
        direct: [String: JSONValue],
        nested: [String: JSONValue],
        baseURL: URL,
        sourceFiles: inout [String: String],
        digestParts: inout [Data]
    ) throws -> JSONValue? {
        let directValue = direct[field]
        let nestedValue = nested[field]
        guard directValue == nil || nestedValue == nil else {
            throw ReleaseToolError.validation("\(field) is specified twice")
        }
        let fileKey = "\(field)File"
        if let fileValue = direct[fileKey] {
            guard fileBackedFields.contains(field) else {
                throw ReleaseToolError.validation("\(fileKey) is not supported")
            }
            guard directValue == nil, nestedValue == nil else {
                throw ReleaseToolError.validation("\(field) and \(fileKey) cannot both be supplied")
            }
            guard let path = fileValue.stringValue else {
                throw ReleaseToolError.validation("\(fileKey) must be a string path")
            }
            return .string(try readText(
                path: path,
                field: field,
                baseURL: baseURL,
                sourceFiles: &sourceFiles,
                digestParts: &digestParts
            ))
        }
        return directValue ?? nestedValue
    }

    private static func readText(
        path: String,
        field: String,
        baseURL: URL,
        sourceFiles: inout [String: String],
        digestParts: inout [Data]
    ) throws -> String {
        guard !path.isEmpty, !NSString(string: path).isAbsolutePath else {
            throw ReleaseToolError.validation(
                "\(field)File must be a relative path inside the release package"
            )
        }
        let packageRoot = baseURL.resolvingSymlinksInPath().standardizedFileURL
        let url = packageRoot.appendingPathComponent(path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let rootPath = packageRoot.path.hasSuffix("/")
            ? packageRoot.path
            : packageRoot.path + "/"
        guard url.path.hasPrefix(rootPath) else {
            throw ReleaseToolError.validation(
                "\(field)File must resolve to a file inside the release package"
            )
        }
        let resourceValues: URLResourceValues
        do {
            resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
        } catch {
            throw ReleaseToolError.file(
                "Could not inspect \(field) file \(url.path): \(error.localizedDescription)"
            )
        }
        guard resourceValues.isRegularFile == true else {
            throw ReleaseToolError.validation(
                "\(field)File must resolve to a regular file inside the release package"
            )
        }
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch {
            throw ReleaseToolError.file("Could not read \(field) file \(url.path): \(error.localizedDescription)")
        }
        guard let raw = String(data: data, encoding: .utf8) else {
            throw ReleaseToolError.validation("\(field) file must be UTF-8: \(url.path)")
        }
        sourceFiles[field] = url.path
        digestParts.append(data)
        var value = raw.replacingOccurrences(of: "\r\n", with: "\n")
        while value.last == "\n" { value.removeLast() }
        return value
    }

    private static func validateMetadata(
        _ value: JSONValue,
        field: String,
        locale: String?
    ) throws {
        if case .null = value {
            guard nullableFields.contains(field) else {
                throw ReleaseToolError.validation("\(field) cannot be cleared with null")
            }
            return
        }
        guard let string = value.stringValue else {
            throw ReleaseToolError.validation("\(field) must be a string or an allowed null")
        }
        try validateString(string, field: field, locale: locale)
        if URLFields.contains(field) {
            guard let components = URLComponents(string: string),
                  ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
                  components.host != nil else {
                throw ReleaseToolError.validation("\(field) must be an absolute HTTP(S) URL")
            }
        }
    }

    private static func validateString(_ string: String, field: String, locale: String?) throws {
        let context = locale.map { " for \($0)" } ?? ""
        guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReleaseToolError.validation("\(field)\(context) cannot be empty")
        }
        if field == "name", string.count < 2 {
            throw ReleaseToolError.validation("name\(context) must contain at least 2 characters")
        }
        if field == "keywords", let limit = characterLimits[field], string.utf16.count > limit {
            throw ReleaseToolError.validation(
                "keywords\(context) is \(string.utf16.count) UTF-16 code units; maximum is \(limit)"
            )
        }
        if let limit = characterLimits[field], string.count > limit {
            throw ReleaseToolError.validation(
                "\(field)\(context) is \(string.count) characters; maximum is \(limit)"
            )
        }
    }

    private static func rejectUnknownFields(
        _ entry: [String: JSONValue],
        locale: String
    ) throws {
        var known = versionFields.union(appFields)
        known.formUnion(["whatsNewFile", "versionMetadata", "appMetadata"])
        known.formUnion(fileBackedFields.map { "\($0)File" })
        let unknown = Set(entry.keys).subtracting(known).sorted()
        guard unknown.isEmpty else {
            throw ReleaseToolError.validation(
                "Unknown fields for \(locale): \(unknown.joined(separator: ", "))"
            )
        }
    }

    private static func rejectUnknownKeys(
        _ object: [String: JSONValue],
        allowed: Set<String>,
        context: String
    ) throws {
        let unknown = Set(object.keys).subtracting(allowed).sorted()
        guard unknown.isEmpty else {
            throw ReleaseToolError.validation(
                "Unknown fields in \(context): \(unknown.joined(separator: ", "))"
            )
        }
    }
}
