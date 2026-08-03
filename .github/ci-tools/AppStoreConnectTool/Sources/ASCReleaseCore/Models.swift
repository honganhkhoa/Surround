import Foundation

public struct LocaleMapping: Codable, Equatable, Sendable {
    public let appStoreLocale: String
    public let screenshotConfiguration: String

    public init(appStoreLocale: String, screenshotConfiguration: String) {
        self.appStoreLocale = appStoreLocale
        self.screenshotConfiguration = screenshotConfiguration
    }
}

public struct ScreenshotPixelSize: Codable, Equatable, Hashable, Sendable {
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(pixelWidth: Int, pixelHeight: Int) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public struct ScreenshotFamily: Codable, Equatable, Sendable {
    public let name: String
    public let directory: String
    public let displayType: String
    public let expectedCount: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let additionalPixelSizes: [ScreenshotPixelSize]

    public var acceptedPixelSizes: [ScreenshotPixelSize] {
        [ScreenshotPixelSize(pixelWidth: pixelWidth, pixelHeight: pixelHeight)]
            + additionalPixelSizes
    }

    public init(
        name: String,
        directory: String,
        displayType: String,
        expectedCount: Int = 10,
        pixelWidth: Int,
        pixelHeight: Int,
        additionalPixelSizes: [ScreenshotPixelSize] = []
    ) {
        self.name = name
        self.directory = directory
        self.displayType = displayType
        self.expectedCount = expectedCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.additionalPixelSizes = additionalPixelSizes
    }
}

public struct LocaleConfiguration: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let bundleId: String
    public let platform: String
    public let localizations: [LocaleMapping]
    public let screenshotFamilies: [ScreenshotFamily]

    public init(
        schemaVersion: Int = 1,
        bundleId: String,
        platform: String = "IOS",
        localizations: [LocaleMapping],
        screenshotFamilies: [ScreenshotFamily] = LocaleConfiguration.defaultScreenshotFamilies
    ) {
        self.schemaVersion = schemaVersion
        self.bundleId = bundleId
        self.platform = platform
        self.localizations = localizations
        self.screenshotFamilies = screenshotFamilies
    }

    public static let defaultScreenshotFamilies = [
        ScreenshotFamily(
            name: "iphone-6.9",
            directory: "iphone-6.9",
            displayType: "APP_IPHONE_67",
            pixelWidth: 1_320,
            pixelHeight: 2_868,
            additionalPixelSizes: [
                ScreenshotPixelSize(pixelWidth: 1_260, pixelHeight: 2_736),
                ScreenshotPixelSize(pixelWidth: 1_290, pixelHeight: 2_796),
            ]
        ),
        ScreenshotFamily(
            name: "ipad-13",
            directory: "ipad-13",
            displayType: "APP_IPAD_PRO_3GEN_129",
            pixelWidth: 2_752,
            pixelHeight: 2_064,
            additionalPixelSizes: [
                ScreenshotPixelSize(pixelWidth: 2_732, pixelHeight: 2_048),
            ]
        ),
    ]

    public static func load(from url: URL) throws -> LocaleConfiguration {
        let root = try FileIO.readJSON(at: url)
        guard let object = root.objectValue else {
            throw ReleaseToolError.validation("Locale config must be a JSON object")
        }
        let schemaVersion = object["schemaVersion"]?.intValue ?? 1
        guard schemaVersion == 1 else {
            throw ReleaseToolError.validation("Unsupported locale config schemaVersion \(schemaVersion)")
        }
        guard let bundleId = (object["bundleId"] ?? object["bundleIdentifier"])?.stringValue,
              !bundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReleaseToolError.validation("Locale config requires bundleId")
        }
        let platform = object["platform"]?.stringValue ?? "IOS"
        guard platform == "IOS" else {
            throw ReleaseToolError.validation("Only platform IOS is currently supported")
        }

        let mappings = try parseMappings(object["localizations"] ?? object["locales"])
        guard !mappings.isEmpty else {
            throw ReleaseToolError.validation("Locale config requires at least one localization")
        }
        let duplicateLocales = Dictionary(grouping: mappings, by: \.appStoreLocale)
            .filter { $0.value.count > 1 }.keys.sorted()
        guard duplicateLocales.isEmpty else {
            throw ReleaseToolError.validation("Duplicate App Store locales: \(duplicateLocales.joined(separator: ", "))")
        }

        let families = try parseFamilies(object["screenshotFamilies"])
        return LocaleConfiguration(
            schemaVersion: schemaVersion,
            bundleId: bundleId,
            platform: platform,
            localizations: mappings,
            screenshotFamilies: families.isEmpty ? defaultScreenshotFamilies : families
        )
    }

    private static func parseMappings(_ value: JSONValue?) throws -> [LocaleMapping] {
        if let array = value?.arrayValue {
            return try array.map { item in
                guard let object = item.objectValue,
                      let locale = (object["appStoreLocale"] ?? object["locale"])?.stringValue else {
                    throw ReleaseToolError.validation("Each localization needs appStoreLocale")
                }
                let screenshot = (
                    object["screenshotConfiguration"]
                        ?? object["screenshotLocale"]
                        ?? object["screenshotLocaleIdentifier"]
                )?.stringValue ?? locale
                return LocaleMapping(appStoreLocale: locale, screenshotConfiguration: screenshot)
            }
        }
        if let object = value?.objectValue {
            return object.keys.sorted().map {
                LocaleMapping(appStoreLocale: $0, screenshotConfiguration: object[$0]?.stringValue ?? $0)
            }
        }
        return []
    }

    private static func parseFamilies(_ value: JSONValue?) throws -> [ScreenshotFamily] {
        guard let value else { return [] }
        if let array = value.arrayValue {
            return try array.map { item in
                guard let object = item.objectValue,
                      let name = (object["name"] ?? object["key"])?.stringValue,
                      let directory = object["directory"]?.stringValue,
                      let displayType = object["displayType"]?.stringValue else {
                    throw ReleaseToolError.validation(
                        "Each screenshot family needs name, directory, and displayType"
                    )
                }
                let count = object["expectedCount"]?.intValue ?? 10
                guard count > 0,
                      let pixelWidth = object["pixelWidth"]?.intValue, pixelWidth > 0,
                      let pixelHeight = object["pixelHeight"]?.intValue, pixelHeight > 0 else {
                    throw ReleaseToolError.validation(
                        "Screenshot family expectedCount, pixelWidth, and pixelHeight must be positive integers"
                    )
                }
                let additionalPixelSizes: [ScreenshotPixelSize]
                if let value = object["additionalPixelSizes"] {
                    guard let values = value.arrayValue else {
                        throw ReleaseToolError.validation(
                            "Screenshot family additionalPixelSizes must be an array"
                        )
                    }
                    additionalPixelSizes = try values.map { value in
                        guard let size = value.objectValue,
                              let width = size["pixelWidth"]?.intValue, width > 0,
                              let height = size["pixelHeight"]?.intValue, height > 0 else {
                            throw ReleaseToolError.validation(
                                "Each additional screenshot pixel size needs positive pixelWidth and pixelHeight integers"
                            )
                        }
                        return ScreenshotPixelSize(pixelWidth: width, pixelHeight: height)
                    }
                } else {
                    additionalPixelSizes = []
                }
                let acceptedPixelSizes = [
                    ScreenshotPixelSize(pixelWidth: pixelWidth, pixelHeight: pixelHeight),
                ] + additionalPixelSizes
                guard Set(acceptedPixelSizes).count == acceptedPixelSizes.count else {
                    throw ReleaseToolError.validation(
                        "Screenshot family pixel sizes must not contain duplicates"
                    )
                }
                return ScreenshotFamily(
                    name: name,
                    directory: directory,
                    displayType: displayType,
                    expectedCount: count,
                    pixelWidth: pixelWidth,
                    pixelHeight: pixelHeight,
                    additionalPixelSizes: additionalPixelSizes
                )
            }
        }
        throw ReleaseToolError.validation("screenshotFamilies must be an array")
    }
}

public struct NormalizedLocaleRelease: Codable, Equatable, Sendable {
    public let appStoreLocale: String
    public let screenshotConfiguration: String
    public let whatsNew: String
    public let versionMetadata: [String: JSONValue]
    public let appMetadata: [String: JSONValue]
    public let sourceFiles: [String: String]

    public init(
        appStoreLocale: String,
        screenshotConfiguration: String,
        whatsNew: String,
        versionMetadata: [String: JSONValue],
        appMetadata: [String: JSONValue],
        sourceFiles: [String: String]
    ) {
        self.appStoreLocale = appStoreLocale
        self.screenshotConfiguration = screenshotConfiguration
        self.whatsNew = whatsNew
        self.versionMetadata = versionMetadata
        self.appMetadata = appMetadata
        self.sourceFiles = sourceFiles
    }
}

public struct NormalizedRelease: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let version: String
    public let bundleId: String
    public let platform: String
    public let sourceReleasePath: String
    public let sourceDigest: String
    public let localizations: [NormalizedLocaleRelease]
    public let versionMetadata: [String: JSONValue]

    public init(
        schemaVersion: Int = 1,
        version: String,
        bundleId: String,
        platform: String,
        sourceReleasePath: String,
        sourceDigest: String,
        localizations: [NormalizedLocaleRelease],
        versionMetadata: [String: JSONValue]
    ) {
        self.schemaVersion = schemaVersion
        self.version = version
        self.bundleId = bundleId
        self.platform = platform
        self.sourceReleasePath = sourceReleasePath
        self.sourceDigest = sourceDigest
        self.localizations = localizations
        self.versionMetadata = versionMetadata
    }
}

public struct RemoteScreenshot: Codable, Equatable, Sendable {
    public let id: String
    public let fileName: String?
    public let checksum: String?
    public let attributes: [String: JSONValue]
}

public struct RemoteScreenshotSet: Codable, Equatable, Sendable {
    public let id: String
    public let displayType: String
    public let screenshots: [RemoteScreenshot]
}

public struct RemoteLocalization: Codable, Equatable, Sendable {
    public let id: String
    public let locale: String
    public let attributes: [String: JSONValue]
    public let screenshotSets: [RemoteScreenshotSet]
}

public struct RemoteVersion: Codable, Equatable, Sendable {
    public let id: String
    public let versionString: String
    public let state: String?
    public let attributes: [String: JSONValue]
    public let localizations: [RemoteLocalization]
}

public struct RemoteAppInfoLocalization: Codable, Equatable, Sendable {
    public let id: String
    public let locale: String
    public let attributes: [String: JSONValue]
}

public struct RemoteAppInfo: Codable, Equatable, Sendable {
    public let id: String
    public let state: String?
    public let localizations: [RemoteAppInfoLocalization]
}

public struct RemoteSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let capturedAt: String
    public let fingerprint: String
    public let appId: String
    public let bundleId: String
    public let platform: String
    public let requestedVersion: String
    public let targetVersion: RemoteVersion?
    public let sourceVersion: RemoteVersion?
    public let appInfo: RemoteAppInfo?

    public init(
        schemaVersion: Int = 1,
        capturedAt: String,
        fingerprint: String,
        appId: String,
        bundleId: String,
        platform: String,
        requestedVersion: String,
        targetVersion: RemoteVersion?,
        sourceVersion: RemoteVersion?,
        appInfo: RemoteAppInfo?
    ) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.fingerprint = fingerprint
        self.appId = appId
        self.bundleId = bundleId
        self.platform = platform
        self.requestedVersion = requestedVersion
        self.targetVersion = targetVersion
        self.sourceVersion = sourceVersion
        self.appInfo = appInfo
    }
}

public struct ManifestScreenshot: Codable, Equatable, Sendable {
    public let path: String
    public let fileName: String
    public let byteCount: Int
    public let sha256: String
    public let md5: String
    public let order: Int
}

public struct ManifestScreenshotSet: Codable, Equatable, Sendable {
    public let family: String
    public let displayType: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let screenshots: [ManifestScreenshot]
}

public struct ScreenshotBackupEntry: Codable, Equatable, Sendable {
    public let originalId: String
    public let originalSourceChecksum: String
    public let fileName: String
    public let order: Int
    public let path: String
    public let byteCount: Int
    public let sha256: String
    public let md5: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let hasAlpha: Bool
    public let orientation: Int
}

public struct ScreenshotBackupManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let createdAt: String
    public let locale: String
    public let family: String
    public let displayType: String
    public let screenshotSetId: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let screenshots: [ScreenshotBackupEntry]
}

public struct ScreenshotRollbackEntry: Codable, Equatable, Sendable {
    public let resourceId: String
    public let order: Int
    public let sourceChecksum: String
}

public struct ScreenshotRollbackCheckpoint: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let locale: String
    public let family: String
    public let displayType: String
    public let screenshotSetId: String
    public let backupDigest: String
    public let screenshots: [ScreenshotRollbackEntry]
}

public struct ManifestLocale: Codable, Equatable, Sendable {
    public let appStoreLocale: String
    public let versionMetadata: [String: JSONValue]
    public let appMetadata: [String: JSONValue]
    public let screenshotSets: [ManifestScreenshotSet]
}

public struct PublishManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: String
    public let release: NormalizedRelease
    public let remoteSnapshot: RemoteSnapshot
    public let remoteFingerprint: String
    public let captureMetadata: JSONValue
    public let localizations: [ManifestLocale]
    public let manifestDigest: String
}

public struct JournalOperation: Codable, Equatable, Sendable {
    public let key: String
    public let status: String
    public let timestamp: String
    public let detail: String?
}

public struct PublishJournal: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var version: String
    public var manifestDigest: String
    public var startedAt: String
    public var completedAt: String?
    public var operations: [JournalOperation]
}
