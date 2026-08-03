import Foundation

public final class Publisher {
    private let client: ASCAPIClient
    private let journalURL: URL
    private let snapshotProvider: (NormalizedRelease) throws -> RemoteSnapshot
    private let sleeper: (TimeInterval) -> Void
    private var journal: PublishJournal

    public init(
        client: ASCAPIClient,
        journalURL: URL,
        manifest: PublishManifest,
        snapshotProvider: ((NormalizedRelease) throws -> RemoteSnapshot)? = nil,
        sleeper: @escaping (TimeInterval) -> Void = Thread.sleep
    ) throws {
        self.client = client
        self.journalURL = journalURL
        self.snapshotProvider = snapshotProvider ?? { release in
            try SnapshotService(client: client).capture(release: release)
        }
        self.sleeper = sleeper
        if FileManager.default.fileExists(atPath: journalURL.path) {
            journal = try ManifestBuilder.decode(PublishJournal.self, at: journalURL)
            guard journal.version == manifest.release.version,
                  journal.manifestDigest == manifest.manifestDigest else {
                throw ReleaseToolError.validation("Journal belongs to a different release manifest")
            }
        } else {
            journal = PublishJournal(
                version: manifest.release.version,
                manifestDigest: manifest.manifestDigest,
                startedAt: ISO8601DateFormatter.releaseTool.string(from: Date()),
                operations: []
            )
            try persistJournal()
        }
    }

    public func publish(manifest: PublishManifest, confirmedVersion: String) throws {
        guard confirmedVersion == manifest.release.version else {
            throw ReleaseToolError.validation(
                "--confirm-version must exactly match \(manifest.release.version)"
            )
        }
        try ManifestBuilder.verify(manifest)

        var snapshot = try snapshotProvider(manifest.release)
        guard snapshot.appId == manifest.remoteSnapshot.appId else {
            throw ReleaseToolError.remoteDrift("Live app resource does not match the reviewed manifest")
        }
        try reconcileLiveState(manifest: manifest, live: snapshot)

        let versionId: String
        if let target = snapshot.targetVersion {
            guard target.state == "PREPARE_FOR_SUBMISSION" else {
                throw ReleaseToolError.validation("Target version is no longer PREPARE_FOR_SUBMISSION")
            }
            versionId = target.id
        } else {
            versionId = try createVersion(manifest: manifest)
            snapshot = try waitForVersion(manifest.release, id: versionId)
        }

        // Creating a version can create a draft AppInfo. Always re-read and only mutate that draft.
        snapshot = try snapshotProvider(manifest.release)
        guard snapshot.appId == manifest.remoteSnapshot.appId else {
            throw ReleaseToolError.remoteDrift("App resource changed after version creation")
        }
        try reconcileLiveState(manifest: manifest, live: snapshot)
        guard let appInfo = snapshot.appInfo, appInfo.state == "PREPARE_FOR_SUBMISSION" else {
            throw ReleaseToolError.validation(
                "App Store Connect did not expose a PREPARE_FOR_SUBMISSION App Info after version creation"
            )
        }
        var appInfoLocalizationIds = Dictionary(
            uniqueKeysWithValues: appInfo.localizations.map { ($0.locale, $0.id) }
        )
        let versionLocalesBeforeAppInfoCreation = Set(
            (snapshot.targetVersion?.localizations ?? []).map(\.locale)
        )
        var needsVersionLocalizationRefresh = false
        for locale in manifest.localizations {
            guard appInfoLocalizationIds[locale.appStoreLocale] == nil else { continue }
            guard case .string? = locale.appMetadata["name"] else {
                throw ReleaseToolError.validation(
                    "Creating App Info locale \(locale.appStoreLocale) requires appMetadata.name"
                )
            }
            let key = "app-info:\(locale.appStoreLocale):create"
            let id: String
            if let recordedId = try operationDetail(key: key) {
                id = recordedId
            } else {
                id = try perform(key: key) {
                    var attributes = createAttributes(locale.appMetadata)
                    attributes["locale"] = .string(locale.appStoreLocale)
                    let response = try client.request(
                        method: "POST",
                        path: "/v1/appInfoLocalizations",
                        body: resourceBody(
                            type: "appInfoLocalizations",
                            attributes: attributes,
                            relationship: ("appInfo", "appInfos", appInfo.id)
                        )
                    )
                    return try resourceId(response, context: "create app info localization")
                }
                if versionLocalesBeforeAppInfoCreation.contains(locale.appStoreLocale) == false {
                    needsVersionLocalizationRefresh = true
                }
            }
            appInfoLocalizationIds[locale.appStoreLocale] = id
        }

        // Creating an App Info localization can also materialize the matching
        // version localization. Refresh before deciding which version locales
        // still need an explicit POST, otherwise the stale snapshot can cause
        // a duplicate-locale conflict.
        if needsVersionLocalizationRefresh {
            snapshot = try snapshotProvider(manifest.release)
            guard snapshot.appId == manifest.remoteSnapshot.appId,
                  snapshot.targetVersion?.id == versionId else {
                throw ReleaseToolError.remoteDrift(
                    "App or target version changed after creating App Info localizations"
                )
            }
            try reconcileLiveState(manifest: manifest, live: snapshot)
        }

        guard let liveTarget = snapshot.targetVersion, liveTarget.id == versionId else {
            throw ReleaseToolError.api("Target version disappeared before localization publishing")
        }
        let reviewedOrInheritedLocales = Set(
            (
                manifest.remoteSnapshot.targetVersion?.localizations
                    ?? manifest.remoteSnapshot.sourceVersion?.localizations
                    ?? []
            ).map(\.locale)
        )
        for locale in manifest.localizations {
            let localeName = locale.appStoreLocale
            let directCreateKey = "version-locale:\(localeName):create"
            let appInfoCreateKey = "app-info:\(localeName):create"
            let sideEffectKey = "version-locale:\(localeName):app-info-side-effect"
            guard reviewedOrInheritedLocales.contains(localeName) == false,
                  isDone(appInfoCreateKey),
                  isDone(directCreateKey) == false,
                  let actual = liveTarget.localizations.first(where: { $0.locale == localeName }) else {
                continue
            }
            if let adoptedId = operationDetailValue(key: sideEffectKey) {
                guard adoptedId == actual.id else {
                    throw ReleaseToolError.remoteDrift(
                        "App Info-created version locale \(localeName) was replaced"
                    )
                }
            } else {
                _ = try perform(key: sideEffectKey) { actual.id }
            }
        }

        var versionLocalizationIds = Dictionary(
            uniqueKeysWithValues: liveTarget.localizations.map { ($0.locale, $0.id) }
        )
        for locale in manifest.localizations {
            guard versionLocalizationIds[locale.appStoreLocale] == nil else { continue }
            let key = "version-locale:\(locale.appStoreLocale):create"
            let id = try operationDetail(key: key) ?? perform(key: key) {
                var attributes = inheritedVersionAttributes(
                    locale: locale.appStoreLocale,
                    snapshot: manifest.remoteSnapshot
                )
                attributes.merge(locale.versionMetadata) { _, proposed in proposed }
                attributes["locale"] = .string(locale.appStoreLocale)
                attributes = createAttributes(attributes)
                let response = try client.request(
                    method: "POST",
                    path: "/v1/appStoreVersionLocalizations",
                    body: resourceBody(
                        type: "appStoreVersionLocalizations",
                        attributes: attributes,
                        relationship: ("appStoreVersion", "appStoreVersions", versionId)
                    )
                )
                return try resourceId(response, context: "create version localization")
            }
            versionLocalizationIds[locale.appStoreLocale] = id
        }

        for locale in manifest.localizations {
            guard let localizationId = versionLocalizationIds[locale.appStoreLocale] else {
                throw ReleaseToolError.api("Missing version localization ID for \(locale.appStoreLocale)")
            }
            for set in locale.screenshotSets {
                try publishScreenshotSet(
                    locale: locale.appStoreLocale,
                    localizationId: localizationId,
                    set: set,
                    manifest: manifest
                )
            }
        }

        // Apply reviewed textual metadata only after every screenshot has processed and been ordered.
        let effectiveVersionMetadata = effectiveVersionMetadata(manifest)
        if !effectiveVersionMetadata.isEmpty {
            try perform(key: "version:\(versionId):metadata") {
                _ = try client.request(
                    method: "PATCH",
                    path: "/v1/appStoreVersions/\(versionId)",
                    body: resourceBody(
                        type: "appStoreVersions",
                        id: versionId,
                        attributes: effectiveVersionMetadata
                    )
                )
                return nil
            }
        }
        for locale in manifest.localizations {
            if !locale.appMetadata.isEmpty,
               let id = appInfoLocalizationIds[locale.appStoreLocale] {
                try perform(key: "app-info:\(locale.appStoreLocale):metadata") {
                    _ = try client.request(
                        method: "PATCH",
                        path: "/v1/appInfoLocalizations/\(id)",
                        body: resourceBody(
                            type: "appInfoLocalizations",
                            id: id,
                            attributes: locale.appMetadata
                        )
                    )
                    return id
                }
            }
            if let id = versionLocalizationIds[locale.appStoreLocale] {
                try perform(key: "version-locale:\(locale.appStoreLocale):metadata") {
                    _ = try client.request(
                        method: "PATCH",
                        path: "/v1/appStoreVersionLocalizations/\(id)",
                        body: resourceBody(
                            type: "appStoreVersionLocalizations",
                            id: id,
                            attributes: locale.versionMetadata
                        )
                    )
                    return id
                }
            }
        }

        let finalSnapshot = try snapshotProvider(manifest.release)
        guard finalSnapshot.appId == manifest.remoteSnapshot.appId else {
            throw ReleaseToolError.remoteDrift("App resource changed before final verification")
        }
        try verifyReadBack(manifest: manifest, snapshot: finalSnapshot)
        journal.completedAt = ISO8601DateFormatter.releaseTool.string(from: Date())
        try persistJournal()
    }

    private func createVersion(manifest: PublishManifest) throws -> String {
        let key = "version:\(manifest.release.version):create"
        if let id = try operationDetail(key: key) { return id }
        return try perform(key: key) {
            let response = try client.request(
                method: "POST",
                path: "/v1/appStoreVersions",
                body: resourceBody(
                    type: "appStoreVersions",
                    attributes: [
                        "versionString": .string(manifest.release.version),
                        "platform": .string(manifest.release.platform),
                    ],
                    relationship: ("app", "apps", manifest.remoteSnapshot.appId)
                )
            )
            return try resourceId(response, context: "create version")
        }
    }

    private func waitForVersion(_ release: NormalizedRelease, id: String) throws -> RemoteSnapshot {
        for _ in 0..<12 {
            let snapshot = try snapshotProvider(release)
            if snapshot.targetVersion?.id == id { return snapshot }
            sleeper(2)
        }
        throw ReleaseToolError.api("Created version \(id) was not visible after 24 seconds")
    }

    private func publishScreenshotSet(
        locale: String,
        localizationId: String,
        set desired: ManifestScreenshotSet,
        manifest: PublishManifest
    ) throws {
        let completionKey = "screenshots:\(locale):\(desired.family):complete"
        let rawSets = try client.list(
            path: "/v1/appStoreVersionLocalizations/\(localizationId)/appScreenshotSets",
            query: [URLQueryItem(name: "limit", value: "200")]
        )
        let matchingSets = rawSets.filter {
            $0["attributes"]?["screenshotDisplayType"]?.stringValue == desired.displayType
        }
        guard matchingSets.count <= 1 else {
            throw ReleaseToolError.remoteDrift(
                "Multiple screenshot sets have display type \(desired.displayType) for \(locale)"
            )
        }
        let matchingSet = matchingSets.first
        let setId: String
        if let id = matchingSet?["id"]?.stringValue { setId = id }
        else {
            let key = "screenshot-set:\(locale):\(desired.displayType):create"
            if isDone(key) {
                throw ReleaseToolError.remoteDrift(
                    "Journal records screenshot set creation, but the live natural key is absent for \(locale) \(desired.displayType)"
                )
            }
            setId = try perform(key: key) {
                let response = try client.request(
                    method: "POST",
                    path: "/v1/appScreenshotSets",
                    body: resourceBody(
                        type: "appScreenshotSets",
                        attributes: ["screenshotDisplayType": .string(desired.displayType)],
                        relationship: (
                            "appStoreVersionLocalization", "appStoreVersionLocalizations", localizationId
                        )
                    )
                )
                return try resourceId(response, context: "create screenshot set")
            }
        }

        let current = try client.list(
            path: "/v1/appScreenshotSets/\(setId)/appScreenshots",
            query: [URLQueryItem(name: "limit", value: "200")]
        )
        let baselineVersion = manifest.remoteSnapshot.targetVersion
            ?? manifest.remoteSnapshot.sourceVersion
        let baselineSet = baselineVersion?.localizations.first(where: { $0.locale == locale })?
            .screenshotSets.first(where: { $0.displayType == desired.displayType })
        let currentRemote = try current.map(remoteScreenshot(from:))
        if !isDone(completionKey) {
            try reconcilePartialScreenshots(
                locale: locale,
                desired: desired,
                liveSet: RemoteScreenshotSet(
                    id: setId,
                    displayType: desired.displayType,
                    screenshots: currentRemote
                ),
                baselineSet: baselineSet,
                allowsInheritedIds: manifest.remoteSnapshot.targetVersion == nil
            )
        }
        if screenshotsMatch(current, desired.screenshots) {
            if operationDetailValue(key: completionKey) != setId {
                try record(key: completionKey, detail: setId)
            }
            return
        }
        if isDone(completionKey) {
            throw ReleaseToolError.remoteDrift(
                "Completed screenshot set \(locale)/\(desired.family) no longer matches the reviewed manifest"
            )
        }

        let backup = try verifiedBackup(
            screenshots: current,
            locale: locale,
            set: desired,
            setId: setId
        )
        do {
            var retainedByDigest: [String: String] = [:]
            for resource in current {
                guard let id = resource["id"]?.stringValue else {
                    throw ReleaseToolError.remoteDrift("Live screenshot has no resource ID")
                }
                if let desiredScreenshot = desired.screenshots.first(where: {
                    resourceChecksum(resource) == $0.md5.lowercased()
                        && resourceIsComplete(resource)
                }), operationDetailValue(
                    key: "screenshot:\(locale):\(desired.family):upload:\(desiredScreenshot.sha256)"
                ) == id {
                    retainedByDigest[desiredScreenshot.sha256] = id
                    continue
                }
                let deleteKey = "screenshot:\(locale):\(desired.family):delete:\(id)"
                if isDone(deleteKey) {
                    throw ReleaseToolError.remoteDrift(
                        "Journal says screenshot \(id) was deleted, but it is live again"
                    )
                }
                try deleteScreenshotIfPresent(id)
                try record(key: deleteKey, detail: id)
            }

            var newIds: [String] = []
            for screenshot in desired.screenshots.sorted(by: { $0.order < $1.order }) {
                let key = "screenshot:\(locale):\(desired.family):upload:\(screenshot.sha256)"
                if let id = retainedByDigest[screenshot.sha256] {
                    newIds.append(id)
                    continue
                }
                if isDone(key) {
                    throw ReleaseToolError.remoteDrift(
                        "Journal upload resource for \(locale)/\(screenshot.fileName) is missing or changed"
                    )
                }
                let id = try uploadScreenshot(screenshot, setId: setId)
                try record(key: key, detail: id)
                newIds.append(id)
            }

            let relationships = newIds.map { id in
                JSONValue.object(["type": .string("appScreenshots"), "id": .string(id)])
            }
            _ = try client.request(
                method: "PATCH",
                path: "/v1/appScreenshotSets/\(setId)/relationships/appScreenshots",
                body: .object(["data": .array(relationships)])
            )
            _ = try waitForScreenshotSet(
                setId: setId,
                screenshots: desired.screenshots,
                expectedIds: newIds,
                context: "Screenshot replacement read-back mismatch for \(locale)/\(desired.family)"
            )
            try record(key: "screenshots:\(locale):\(desired.family):order", detail: setId)
            try record(key: completionKey, detail: setId)
        } catch {
            let originalError = error
            do {
                let restored = try restoreBackup(backup, setId: setId)
                let checkpoint = ScreenshotRollbackCheckpoint(
                    schemaVersion: 1,
                    locale: locale,
                    family: desired.family,
                    displayType: desired.displayType,
                    screenshotSetId: setId,
                    backupDigest: try backupDigest(backup),
                    screenshots: restored
                )
                try record(
                    key: "screenshots:\(locale):\(desired.family):rollback",
                    detail: try checkpointDetail(checkpoint)
                )
            } catch {
                let rollbackError = error
                throw ReleaseToolError.api(
                    "Replacement failed for \(locale)/\(desired.family): \(originalError.localizedDescription). Rollback also failed: \(rollbackError.localizedDescription)"
                )
            }
            throw ReleaseToolError.api(
                "Replacement failed for \(locale)/\(desired.family): \(originalError.localizedDescription). Original screenshot backup was restored."
            )
        }
    }

    private func uploadScreenshot(_ screenshot: ManifestScreenshot, setId: String) throws -> String {
        let fileData = try Data(contentsOf: URL(fileURLWithPath: screenshot.path))
        func reserve() throws -> (id: String, attributes: [String: JSONValue]) {
            let response = try client.request(
                method: "POST",
                path: "/v1/appScreenshots",
                body: resourceBody(
                    type: "appScreenshots",
                    attributes: [
                        "fileName": .string(screenshot.fileName),
                        "fileSize": .number(Double(screenshot.byteCount)),
                    ],
                    relationship: ("appScreenshotSet", "appScreenshotSets", setId)
                )
            )
            guard let data = response?["data"], let id = data["id"]?.stringValue,
                  let attributes = data["attributes"]?.objectValue else {
                throw ReleaseToolError.api("Screenshot reservation response is malformed")
            }
            return (id, attributes)
        }

        var reservation = try reserve()
        do {
            try sendUploadOperations(reservation.attributes, data: fileData)
        } catch let error as ReleaseToolError where error.description.contains("HTTP 403") {
            // Upload URLs are time-limited. Delete the stale reservation and reserve once more.
            _ = try? client.request(method: "DELETE", path: "/v1/appScreenshots/\(reservation.id)")
            reservation = try reserve()
            try sendUploadOperations(reservation.attributes, data: fileData)
        }
        _ = try client.request(
            method: "PATCH",
            path: "/v1/appScreenshots/\(reservation.id)",
            body: resourceBody(
                type: "appScreenshots",
                id: reservation.id,
                attributes: [
                    "uploaded": .bool(true),
                    "sourceFileChecksum": .string(screenshot.md5.lowercased()),
                ]
            )
        )
        try waitForScreenshot(id: reservation.id)
        return reservation.id
    }

    private func sendUploadOperations(_ attributes: [String: JSONValue], data: Data) throws {
        guard let rawOperations = attributes["uploadOperations"]?.arrayValue,
              !rawOperations.isEmpty else {
            throw ReleaseToolError.api("Screenshot reservation contains no upload operations")
        }
        for raw in rawOperations {
            try client.upload(operation: UploadOperation.parse(raw), fileData: data)
        }
    }

    private func waitForScreenshot(id: String) throws {
        for _ in 0..<120 {
            let response = try client.request(method: "GET", path: "/v1/appScreenshots/\(id)")
            let delivery = response?["data"]?["attributes"]?["assetDeliveryState"]
            let state = delivery?["state"]?.stringValue
            if state == "COMPLETE" { return }
            if state == "FAILED" {
                throw ReleaseToolError.api("Screenshot \(id) processing failed: \(String(describing: delivery?.any))")
            }
            sleeper(5)
        }
        throw ReleaseToolError.api("Screenshot \(id) processing timed out after 10 minutes")
    }

    private func verifiedBackup(
        screenshots: [JSONValue],
        locale: String,
        set: ManifestScreenshotSet,
        setId: String
    ) throws -> ScreenshotBackupManifest {
        let key = "screenshots:\(locale):\(set.family):backup"
        if let manifestPath = operationDetailValue(key: key) {
            let backup = try ManifestBuilder.decode(
                ScreenshotBackupManifest.self,
                at: URL(fileURLWithPath: manifestPath)
            )
            try verifyBackup(backup, locale: locale, set: set, setId: setId)
            return backup
        }

        let directory = journalURL.deletingLastPathComponent()
            .appendingPathComponent("remote-screenshot-backup")
            .appendingPathComponent(locale)
            .appendingPathComponent("\(set.family)-\(UUID().uuidString)")
        do {
            var entries: [ScreenshotBackupEntry] = []
            for (index, resource) in screenshots.enumerated() {
                guard let id = resource["id"]?.stringValue,
                      let attributes = resource["attributes"]?.objectValue,
                      let sourceChecksum = attributes["sourceFileChecksum"]?.stringValue,
                      let asset = attributes["imageAsset"]?.objectValue,
                      let template = (asset["templateUrl"] ?? asset["template"])?.stringValue,
                      let width = asset["width"]?.intValue,
                      let height = asset["height"]?.intValue else {
                    throw ReleaseToolError.api(
                        "Cannot back up screenshot \(index + 1): complete imageAsset metadata is unavailable"
                    )
                }
                guard resourceIsComplete(resource), !sourceChecksum.isEmpty else {
                    throw ReleaseToolError.api(
                        "Cannot back up screenshot \(id): source checksum or COMPLETE delivery state is unavailable"
                    )
                }
                let urlString = template
                    .replacingOccurrences(of: "{w}", with: String(width))
                    .replacingOccurrences(of: "{h}", with: String(height))
                    .replacingOccurrences(of: "{c}", with: "")
                    .replacingOccurrences(of: "{f}", with: "png")
                guard let url = URL(string: urlString) else {
                    throw ReleaseToolError.api("Cannot back up screenshot \(id): invalid imageAsset URL")
                }
                let downloadedData = try client.download(url: url)
                let data: Data
                do {
                    data = try ImageValidation.removingOpaqueAlphaChannel(
                        from: downloadedData,
                        context: "remote backup \(id)"
                    )
                } catch {
                    throw ReleaseToolError.api(
                        "Cannot back up screenshot \(id): \(error.localizedDescription)"
                    )
                }
                let decoded = try ImageValidation.decodePNG(data, context: "remote backup \(id)")
                let reportedName = attributes["fileName"]?.stringValue ?? "screenshot.png"
                let baseName = URL(fileURLWithPath: reportedName).deletingPathExtension().lastPathComponent
                let originalName = (baseName.isEmpty ? "screenshot" : baseName) + ".png"
                let safeName = originalName.replacingOccurrences(
                    of: #"[^A-Za-z0-9._-]"#,
                    with: "_",
                    options: .regularExpression
                )
                let fileName = String(format: "%02d", index + 1) + "-" + safeName
                let fileURL = directory.appendingPathComponent(fileName)
                try FileIO.write(data: data, to: fileURL)
                entries.append(ScreenshotBackupEntry(
                    originalId: id,
                    originalSourceChecksum: sourceChecksum.lowercased(),
                    fileName: originalName,
                    order: index + 1,
                    path: fileURL.standardizedFilePath,
                    byteCount: data.count,
                    sha256: FileIO.sha256(data),
                    md5: FileIO.md5(data),
                    pixelWidth: decoded.pixelWidth,
                    pixelHeight: decoded.pixelHeight,
                    hasAlpha: decoded.hasAlpha,
                    orientation: decoded.orientation
                ))
            }
            let backup = ScreenshotBackupManifest(
                schemaVersion: 1,
                createdAt: ISO8601DateFormatter.releaseTool.string(from: Date()),
                locale: locale,
                family: set.family,
                displayType: set.displayType,
                screenshotSetId: setId,
                pixelWidth: set.pixelWidth,
                pixelHeight: set.pixelHeight,
                screenshots: entries
            )
            let manifestURL = directory.appendingPathComponent("backup-manifest.json")
            try FileIO.writeJSON(backup, to: manifestURL)
            try verifyBackup(backup, locale: locale, set: set, setId: setId)
            try record(key: key, detail: manifestURL.standardizedFilePath)
            return backup
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private func verifyBackup(
        _ backup: ScreenshotBackupManifest,
        locale: String,
        set: ManifestScreenshotSet,
        setId: String
    ) throws {
        guard backup.schemaVersion == 1,
              backup.locale == locale,
              backup.family == set.family,
              backup.displayType == set.displayType,
              backup.screenshotSetId == setId,
              backup.pixelWidth == set.pixelWidth,
              backup.pixelHeight == set.pixelHeight,
              backup.screenshots.map(\.order) == backup.screenshots.indices.map({ $0 + 1 }),
              Set(backup.screenshots.map(\.originalId)).count == backup.screenshots.count,
              backup.screenshots.allSatisfy({ !$0.originalSourceChecksum.isEmpty }) else {
            throw ReleaseToolError.validation("Screenshot backup manifest does not match the live set")
        }
        for entry in backup.screenshots {
            let data = try Data(contentsOf: URL(fileURLWithPath: entry.path))
            guard data.count == entry.byteCount,
                  FileIO.sha256(data) == entry.sha256,
                  FileIO.md5(data) == entry.md5 else {
                throw ReleaseToolError.validation("Screenshot backup file changed: \(entry.path)")
            }
            let decoded = try ImageValidation.decodePNG(data, context: entry.path)
            guard decoded.pixelWidth == entry.pixelWidth,
                  decoded.pixelHeight == entry.pixelHeight,
                  decoded.hasAlpha == entry.hasAlpha,
                  decoded.orientation == entry.orientation else {
                throw ReleaseToolError.validation("Screenshot backup metadata changed: \(entry.path)")
            }
        }
    }

    private func restoreBackup(
        _ backup: ScreenshotBackupManifest,
        setId: String
    ) throws -> [ScreenshotRollbackEntry] {
        try verifyBackup(
            backup,
            locale: backup.locale,
            set: ManifestScreenshotSet(
                family: backup.family,
                displayType: backup.displayType,
                pixelWidth: backup.pixelWidth,
                pixelHeight: backup.pixelHeight,
                screenshots: []
            ),
            setId: setId
        )
        let live = try client.list(
            path: "/v1/appScreenshotSets/\(setId)/appScreenshots",
            query: [URLQueryItem(name: "limit", value: "200")]
        )
        for resource in live {
            guard let id = resource["id"]?.stringValue else {
                throw ReleaseToolError.api("Rollback found a screenshot without an ID")
            }
            try deleteScreenshotIfPresent(id)
        }
        var restoredIds: [String] = []
        var restoredScreenshots: [ManifestScreenshot] = []
        for entry in backup.screenshots.sorted(by: { $0.order < $1.order }) {
            let screenshot = ManifestScreenshot(
                path: entry.path,
                fileName: entry.fileName,
                byteCount: entry.byteCount,
                sha256: entry.sha256,
                md5: entry.md5,
                order: entry.order
            )
            restoredIds.append(try uploadScreenshot(screenshot, setId: setId))
            restoredScreenshots.append(screenshot)
        }
        _ = try client.request(
            method: "PATCH",
            path: "/v1/appScreenshotSets/\(setId)/relationships/appScreenshots",
            body: .object([
                "data": .array(restoredIds.map {
                    .object(["type": .string("appScreenshots"), "id": .string($0)])
                }),
            ])
        )
        let readBack = try waitForScreenshotSet(
            setId: setId,
            screenshots: restoredScreenshots,
            expectedIds: restoredIds,
            context: "Rollback read-back did not match the structured backup"
        )
        return try zip(
            readBack,
            backup.screenshots.sorted(by: { $0.order < $1.order })
        ).map { resource, entry in
            guard let resourceId = resource["id"]?.stringValue,
                  let checksum = resourceChecksum(resource),
                  checksum == entry.md5.lowercased(),
                  resourceIsComplete(resource) else {
                throw ReleaseToolError.api(
                    "Rollback checkpoint could not identify a restored COMPLETE screenshot"
                )
            }
            return ScreenshotRollbackEntry(
                resourceId: resourceId,
                order: entry.order,
                sourceChecksum: checksum
            )
        }
    }

    private func screenshotsMatch(_ remote: [JSONValue], _ local: [ManifestScreenshot]) -> Bool {
        guard remote.count == local.count else { return false }
        for (resource, expected) in zip(remote, local.sorted(by: { $0.order < $1.order })) {
            guard resourceChecksum(resource) == expected.md5.lowercased(),
                  resourceIsComplete(resource) else { return false }
        }
        return true
    }

    private func waitForScreenshotSet(
        setId: String,
        screenshots: [ManifestScreenshot],
        expectedIds: [String],
        context: String
    ) throws -> [JSONValue] {
        let attempts = 60
        for attempt in 0..<attempts {
            let readBack = try client.list(
                path: "/v1/appScreenshotSets/\(setId)/appScreenshots",
                query: [URLQueryItem(name: "limit", value: "200")]
            )
            let ids = readBack.compactMap { $0["id"]?.stringValue }
            if ids == expectedIds, screenshotsMatch(readBack, screenshots) {
                return readBack
            }
            if attempt + 1 < attempts { sleeper(2) }
        }
        throw ReleaseToolError.api("\(context) after 120 seconds")
    }

    private func deleteScreenshotIfPresent(_ id: String) throws {
        do {
            _ = try client.request(method: "DELETE", path: "/v1/appScreenshots/\(id)")
        } catch let error as ReleaseToolError where error.description.contains("HTTP 404") {
            return
        }
    }

    private func resourceChecksum(_ resource: JSONValue) -> String? {
        resource["attributes"]?["sourceFileChecksum"]?.stringValue?.lowercased()
    }

    private func resourceIsComplete(_ resource: JSONValue) -> Bool {
        resource["attributes"]?["assetDeliveryState"]?["state"]?.stringValue == "COMPLETE"
    }

    private func reconcileLiveState(manifest: PublishManifest, live: RemoteSnapshot) throws {
        guard live.appId == manifest.remoteSnapshot.appId,
              live.bundleId == manifest.release.bundleId,
              live.requestedVersion == manifest.release.version else {
            throw ReleaseToolError.remoteDrift("Live app identity differs from the reviewed snapshot")
        }
        if journal.operations.isEmpty {
            guard live.fingerprint == manifest.remoteFingerprint else {
                throw ReleaseToolError.remoteDrift(
                    "Run prepare again; the live snapshot changed before publishing"
                )
            }
            return
        }

        try reconcileSourceVersion(manifest: manifest, live: live)
        let baselineTarget = manifest.remoteSnapshot.targetVersion
        let createVersionKey = "version:\(manifest.release.version):create"
        let createdVersionId = operationDetailValue(key: createVersionKey)
        let liveTarget: RemoteVersion
        if let baselineTarget {
            guard let target = live.targetVersion, target.id == baselineTarget.id else {
                throw ReleaseToolError.remoteDrift("Reviewed target version was removed or replaced")
            }
            liveTarget = target
        } else if let createdVersionId {
            guard let target = live.targetVersion, target.id == createdVersionId else {
                throw ReleaseToolError.remoteDrift(
                    "Journal-created version is absent or has a different resource ID"
                )
            }
            liveTarget = target
        } else {
            guard live.targetVersion == nil else {
                throw ReleaseToolError.remoteDrift(
                    "Target version appeared without a journaled create operation"
                )
            }
            guard live.fingerprint == manifest.remoteFingerprint else {
                throw ReleaseToolError.remoteDrift("Unknown remote change before version creation")
            }
            return
        }
        guard liveTarget.versionString == manifest.release.version,
              liveTarget.state == "PREPARE_FOR_SUBMISSION" else {
            throw ReleaseToolError.remoteDrift("Live target version is no longer safely editable")
        }

        var expectedVersionAttributes: [String: JSONValue]
        if let baselineTarget {
            expectedVersionAttributes = filtered(
                baselineTarget.attributes,
                keys: ["versionString", "platform", "releaseType", "copyright"]
            )
        } else {
            expectedVersionAttributes = [
                "versionString": .string(manifest.release.version),
                "platform": .string(manifest.release.platform),
            ]
        }
        if isDone("version:\(liveTarget.id):metadata") {
            expectedVersionAttributes.merge(effectiveVersionMetadata(manifest)) { _, proposed in proposed }
        }
        try requireAttributes(
            filtered(liveTarget.attributes, keys: Set(expectedVersionAttributes.keys)),
            equal: expectedVersionAttributes,
            context: "target version metadata"
        )

        guard let liveAppInfo = live.appInfo, liveAppInfo.state == "PREPARE_FOR_SUBMISSION" else {
            throw ReleaseToolError.remoteDrift("Draft App Info is absent during resumed publishing")
        }
        if baselineTarget != nil, liveAppInfo.id != manifest.remoteSnapshot.appInfo?.id {
            throw ReleaseToolError.remoteDrift("Draft App Info resource was replaced")
        }
        try reconcileAppInfo(
            manifest: manifest,
            live: liveAppInfo,
            allowsInheritedIds: baselineTarget == nil
        )
        try reconcileVersionLocalizations(
            manifest: manifest,
            live: liveTarget,
            baseline: baselineTarget ?? manifest.remoteSnapshot.sourceVersion,
            allowsInheritedIds: baselineTarget == nil
        )
    }

    private func reconcileSourceVersion(manifest: PublishManifest, live: RemoteSnapshot) throws {
        guard let reviewed = manifest.remoteSnapshot.sourceVersion else {
            guard live.sourceVersion == nil else {
                throw ReleaseToolError.remoteDrift("An unreviewed source version appeared")
            }
            return
        }
        if reviewed.id == manifest.remoteSnapshot.targetVersion?.id { return }
        guard let current = live.sourceVersion,
              stableVersionProjection(current) == stableVersionProjection(reviewed) else {
            throw ReleaseToolError.remoteDrift("Live source version metadata or assets changed")
        }
    }

    private func reconcileAppInfo(
        manifest: PublishManifest,
        live: RemoteAppInfo,
        allowsInheritedIds: Bool
    ) throws {
        let baselineLocales = Dictionary(
            uniqueKeysWithValues: (manifest.remoteSnapshot.appInfo?.localizations ?? []).map { ($0.locale, $0) }
        )
        var expectedLocales = Set(baselineLocales.keys)
        var createdLocales: Set<String> = []
        for locale in manifest.localizations where isDone("app-info:\(locale.appStoreLocale):create") {
            expectedLocales.insert(locale.appStoreLocale)
            createdLocales.insert(locale.appStoreLocale)
        }
        let actualLocales = Set(live.localizations.map(\.locale))
        let localeSetIsValid = allowsInheritedIds
            ? actualLocales.isSubset(of: expectedLocales) && createdLocales.isSubset(of: actualLocales)
            : actualLocales == expectedLocales
        guard localeSetIsValid else {
            throw ReleaseToolError.remoteDrift(
                "App Info locale set changed unexpectedly; expected \(expectedLocales.sorted()), got \(actualLocales.sorted())"
            )
        }
        for actual in live.localizations {
            guard let desired = manifest.localizations.first(where: {
                $0.appStoreLocale == actual.locale
            }) else {
                throw ReleaseToolError.remoteDrift("Unmanaged App Info locale \(actual.locale)")
            }
            let createKey = "app-info:\(actual.locale):create"
            let metadataKey = "app-info:\(actual.locale):metadata"
            var expected = filtered(
                baselineLocales[actual.locale]?.attributes ?? [:],
                keys: ["locale", "name", "subtitle", "privacyPolicyUrl"]
            )
            if isDone(createKey) || isDone(metadataKey) {
                expected.merge(desired.appMetadata) { _, proposed in proposed }
            }
            expected["locale"] = .string(actual.locale)
            try requireAttributes(
                filtered(actual.attributes, keys: ["locale", "name", "subtitle", "privacyPolicyUrl"]),
                equal: createAttributes(expected),
                context: "App Info \(actual.locale)"
            )
            if let createdId = operationDetailValue(key: createKey) {
                guard actual.id == createdId else {
                    throw ReleaseToolError.remoteDrift("Created App Info locale \(actual.locale) was replaced")
                }
            } else if !allowsInheritedIds, let baseline = baselineLocales[actual.locale], actual.id != baseline.id {
                throw ReleaseToolError.remoteDrift("App Info locale \(actual.locale) resource was replaced")
            }
            if let patchedId = operationDetailValue(key: metadataKey), patchedId != actual.id {
                throw ReleaseToolError.remoteDrift("App Info metadata journal contains a stale resource ID")
            }
        }
    }

    private func reconcileVersionLocalizations(
        manifest: PublishManifest,
        live: RemoteVersion,
        baseline: RemoteVersion?,
        allowsInheritedIds: Bool
    ) throws {
        let baselineLocales = Dictionary(
            uniqueKeysWithValues: (baseline?.localizations ?? []).map { ($0.locale, $0) }
        )
        var allowedLocales = Set(baselineLocales.keys)
        var requiredLocales = allowsInheritedIds ? Set<String>() : allowedLocales
        for locale in manifest.localizations {
            let localeName = locale.appStoreLocale
            let directCreateKey = "version-locale:\(localeName):create"
            let appInfoCreateKey = "app-info:\(localeName):create"
            let sideEffectKey = "version-locale:\(localeName):app-info-side-effect"
            if isDone(directCreateKey) || isDone(sideEffectKey) {
                allowedLocales.insert(localeName)
                requiredLocales.insert(localeName)
            } else if baselineLocales[localeName] == nil, isDone(appInfoCreateKey) {
                // App Store Connect may create this locale as a side effect of
                // the journaled App Info localization. Allow it during the
                // crash-safe window before its resource ID is adopted.
                allowedLocales.insert(localeName)
            }
        }
        let actualLocales = Set(live.localizations.map(\.locale))
        let localeSetIsValid = actualLocales.isSubset(of: allowedLocales)
            && requiredLocales.isSubset(of: actualLocales)
        guard localeSetIsValid else {
            throw ReleaseToolError.remoteDrift(
                "Version locale set changed unexpectedly; allowed \(allowedLocales.sorted()), "
                    + "required \(requiredLocales.sorted()), got \(actualLocales.sorted())"
            )
        }
        for actual in live.localizations {
            guard let desired = manifest.localizations.first(where: {
                $0.appStoreLocale == actual.locale
            }) else {
                throw ReleaseToolError.remoteDrift("Unmanaged version locale \(actual.locale)")
            }
            let createKey = "version-locale:\(actual.locale):create"
            let appInfoCreateKey = "app-info:\(actual.locale):create"
            let sideEffectKey = "version-locale:\(actual.locale):app-info-side-effect"
            let metadataKey = "version-locale:\(actual.locale):metadata"
            let baselineLocale = baselineLocales[actual.locale]
            let directCreateIsDone = isDone(createKey)
            let metadataIsDone = isDone(metadataKey)
            let isUnownedAppInfoSideEffect = baselineLocale == nil
                && isDone(appInfoCreateKey)
                && directCreateIsDone == false
                && metadataIsDone == false
            var expected = filtered(
                baselineLocale?.attributes ?? [:],
                keys: [
                    "locale", "description", "keywords", "marketingUrl", "promotionalText",
                    "supportUrl", "whatsNew",
                ]
            )
            if isUnownedAppInfoSideEffect {
                for key in [
                    "description", "keywords", "marketingUrl", "promotionalText", "supportUrl",
                    "whatsNew",
                ] {
                    expected[key] = .null
                }
            } else if allowsInheritedIds && directCreateIsDone == false && metadataIsDone == false {
                // App Store Connect creates a localization for a fresh version by inheriting
                // the source metadata while deliberately clearing the previous release notes.
                expected["whatsNew"] = .null
            }
            if directCreateIsDone || metadataIsDone {
                expected.merge(desired.versionMetadata) { _, proposed in proposed }
            }
            expected["locale"] = .string(actual.locale)
            try requireAttributes(
                filtered(actual.attributes, keys: Set(expected.keys)),
                equal: createAttributes(expected),
                context: "version locale \(actual.locale)"
            )
            if let createdId = operationDetailValue(key: createKey) {
                guard actual.id == createdId else {
                    throw ReleaseToolError.remoteDrift("Created version locale \(actual.locale) was replaced")
                }
            } else if let adoptedId = operationDetailValue(key: sideEffectKey) {
                guard actual.id == adoptedId else {
                    throw ReleaseToolError.remoteDrift(
                        "App Info-created version locale \(actual.locale) was replaced"
                    )
                }
            } else if !allowsInheritedIds, let baselineLocale,
                      actual.id != baselineLocale.id {
                throw ReleaseToolError.remoteDrift("Version locale \(actual.locale) resource was replaced")
            }
            if let patchedId = operationDetailValue(key: metadataKey), patchedId != actual.id {
                throw ReleaseToolError.remoteDrift("Version metadata journal contains a stale resource ID")
            }
            try reconcileScreenshotSets(
                manifestLocale: desired,
                live: actual,
                baseline: baselineLocales[actual.locale],
                allowsInheritedIds: allowsInheritedIds
            )
        }
    }

    private func reconcileScreenshotSets(
        manifestLocale: ManifestLocale,
        live: RemoteLocalization,
        baseline: RemoteLocalization?,
        allowsInheritedIds: Bool
    ) throws {
        let baselineSets = Dictionary(
            uniqueKeysWithValues: (baseline?.screenshotSets ?? []).map { ($0.displayType, $0) }
        )
        var expectedTypes = Set(baselineSets.keys)
        var createdTypes: Set<String> = []
        for desired in manifestLocale.screenshotSets where isDone(
            "screenshot-set:\(manifestLocale.appStoreLocale):\(desired.displayType):create"
        ) {
            expectedTypes.insert(desired.displayType)
            createdTypes.insert(desired.displayType)
        }
        let actualTypes = Set(live.screenshotSets.map(\.displayType))
        let typeSetIsValid = allowsInheritedIds
            ? actualTypes.isSubset(of: expectedTypes) && createdTypes.isSubset(of: actualTypes)
            : actualTypes == expectedTypes
        guard typeSetIsValid else {
            throw ReleaseToolError.remoteDrift(
                "Screenshot set types changed for \(manifestLocale.appStoreLocale)"
            )
        }
        for actual in live.screenshotSets {
            let baselineSet = baselineSets[actual.displayType]
            guard let desired = manifestLocale.screenshotSets.first(where: {
                $0.displayType == actual.displayType
            }) else {
                guard let baselineSet,
                      stableScreenshotProjection(actual.screenshots)
                        == stableScreenshotProjection(baselineSet.screenshots) else {
                    throw ReleaseToolError.remoteDrift("Unmanaged screenshot set changed")
                }
                continue
            }
            let createKey = "screenshot-set:\(manifestLocale.appStoreLocale):\(actual.displayType):create"
            if let createdId = operationDetailValue(key: createKey) {
                guard actual.id == createdId else {
                    throw ReleaseToolError.remoteDrift("Created screenshot set was replaced")
                }
            } else if !allowsInheritedIds, let baselineSet, actual.id != baselineSet.id {
                throw ReleaseToolError.remoteDrift("Existing screenshot set was replaced")
            }
            let completionKey = "screenshots:\(manifestLocale.appStoreLocale):\(desired.family):complete"
            let orderKey = "screenshots:\(manifestLocale.appStoreLocale):\(desired.family):order"
            if isDone(completionKey) {
                guard remoteScreenshotsMatch(actual.screenshots, desired.screenshots) else {
                    throw ReleaseToolError.remoteDrift(
                        "Journal-completed screenshot set no longer matches \(manifestLocale.appStoreLocale)/\(desired.family)"
                    )
                }
                if let setId = operationDetailValue(key: completionKey), setId != actual.id {
                    throw ReleaseToolError.remoteDrift("Completed screenshot set journal has a stale ID")
                }
                if let setId = operationDetailValue(key: orderKey), setId != actual.id {
                    throw ReleaseToolError.remoteDrift("Screenshot order journal has a stale set ID")
                }
                continue
            }
            try reconcilePartialScreenshots(
                locale: manifestLocale.appStoreLocale,
                desired: desired,
                liveSet: actual,
                baselineSet: baselineSet,
                allowsInheritedIds: allowsInheritedIds
            )
        }
    }

    private func reconcilePartialScreenshots(
        locale: String,
        desired: ManifestScreenshotSet,
        liveSet: RemoteScreenshotSet,
        baselineSet: RemoteScreenshotSet?,
        allowsInheritedIds: Bool
    ) throws {
        let backupKey = "screenshots:\(locale):\(desired.family):backup"
        let backup = try operationDetailValue(key: backupKey).map { path -> ScreenshotBackupManifest in
            let value = try ManifestBuilder.decode(
                ScreenshotBackupManifest.self,
                at: URL(fileURLWithPath: path)
            )
            try verifyBackup(value, locale: locale, set: desired, setId: liveSet.id)
            return value
        }
        if screenshotRollbackOperation(locale: locale, family: desired.family) != nil,
           backup == nil {
            throw ReleaseToolError.remoteDrift(
                "Screenshot rollback checkpoint has no verified backup manifest"
            )
        }
        let epochStart = screenshotEpochStartIndex(locale: locale, family: desired.family)
        let hasReplacementMutation = journal.operations.enumerated().contains { index, operation in
            guard index >= epochStart, operation.status == "complete" else { return false }
            let itemPrefix = "screenshot:\(locale):\(desired.family):"
            let orderKey = "screenshots:\(locale):\(desired.family):order"
            return operation.key.hasPrefix(itemPrefix) || operation.key == orderKey
        }
        if let backup,
           hasReplacementMutation,
           liveScreenshotsMatchBackup(liveSet.screenshots, backup: backup) {
            let orderedBackup = backup.screenshots.sorted(by: { $0.order < $1.order })
            let checkpoint = ScreenshotRollbackCheckpoint(
                schemaVersion: 1,
                locale: locale,
                family: desired.family,
                displayType: desired.displayType,
                screenshotSetId: liveSet.id,
                backupDigest: try backupDigest(backup),
                screenshots: zip(liveSet.screenshots, orderedBackup).map { screenshot, entry in
                    ScreenshotRollbackEntry(
                        resourceId: screenshot.id,
                        order: entry.order,
                        sourceChecksum: entry.md5.lowercased()
                    )
                }
            )
            try record(
                key: "screenshots:\(locale):\(desired.family):rollback",
                detail: try checkpointDetail(checkpoint)
            )
            return
        }
        let checkpoint = try backup.flatMap {
            try latestRollbackCheckpoint(
                locale: locale,
                family: desired.family,
                setId: liveSet.id,
                backup: $0
            )
        }
        let hasScreenshotJournal = journal.operations.enumerated().contains { index, operation in
            index >= epochStart && operation.status == "complete" && (
                operation.key.hasPrefix("screenshot:\(locale):\(desired.family):")
                    || operation.key.hasPrefix("screenshots:\(locale):\(desired.family):")
            )
        }
        if allowsInheritedIds,
           liveSet.screenshots.isEmpty,
           backup == nil,
           checkpoint == nil,
           !hasScreenshotJournal {
            return
        }
        let originals: [(id: String?, checksum: String?)]
        if let checkpoint {
            originals = checkpoint.screenshots.map {
                ($0.resourceId as String?, $0.sourceChecksum as String?)
            }
        } else if let backup {
            originals = backup.screenshots.map {
                ($0.originalId as String?, $0.originalSourceChecksum as String?)
            }
        } else {
            originals = (baselineSet?.screenshots ?? []).map {
                (allowsInheritedIds ? nil : $0.id, $0.checksum?.lowercased())
            }
        }
        let actualIds = Set(liveSet.screenshots.map(\.id))
        var allowedActualIds: Set<String> = []

        for original in originals {
            let matching: RemoteScreenshot?
            if let id = original.id {
                matching = liveSet.screenshots.first { $0.id == id }
                let deleteKey = "screenshot:\(locale):\(desired.family):delete:\(id)"
                if isDone(deleteKey) {
                    guard matching == nil else {
                        throw ReleaseToolError.remoteDrift("Deleted screenshot \(id) reappeared")
                    }
                } else {
                    guard let matching else {
                        throw ReleaseToolError.remoteDrift("Screenshot \(id) disappeared without a journaled delete")
                    }
                    guard let checksum = original.checksum,
                          matching.checksum?.lowercased() == checksum.lowercased(),
                          screenshotIsComplete(matching) else {
                        throw ReleaseToolError.remoteDrift(
                            "Screenshot \(id) checksum or delivery state changed"
                        )
                    }
                    allowedActualIds.insert(matching.id)
                }
            } else {
                guard let checksum = original.checksum else {
                    throw ReleaseToolError.remoteDrift(
                        "Inherited screenshot has no checksum and cannot be safely reconciled"
                    )
                }
                matching = liveSet.screenshots.first {
                    $0.checksum?.lowercased() == checksum && screenshotIsComplete($0)
                }
                guard let matching else {
                    throw ReleaseToolError.remoteDrift("Inherited screenshot changed without a journaled operation")
                }
                allowedActualIds.insert(matching.id)
            }
        }
        for screenshot in desired.screenshots {
            let key = "screenshot:\(locale):\(desired.family):upload:\(screenshot.sha256)"
            guard let id = operationDetailValue(key: key) else { continue }
            guard let actual = liveSet.screenshots.first(where: { $0.id == id }),
                  actual.checksum?.lowercased() == screenshot.md5.lowercased(),
                  screenshotIsComplete(actual) else {
                throw ReleaseToolError.remoteDrift("Journaled screenshot upload is missing or changed")
            }
            allowedActualIds.insert(id)
        }
        guard actualIds == allowedActualIds else {
            throw ReleaseToolError.remoteDrift("Screenshot set contains an unknown asset")
        }
    }

    private func liveScreenshotsMatchBackup(
        _ live: [RemoteScreenshot],
        backup: ScreenshotBackupManifest
    ) -> Bool {
        let expected = backup.screenshots.sorted(by: { $0.order < $1.order })
        guard live.count == expected.count,
              Set(live.map(\.id)).count == live.count else { return false }
        return zip(live, expected).allSatisfy { screenshot, entry in
            screenshot.checksum?.lowercased() == entry.md5.lowercased()
                && screenshotIsComplete(screenshot)
        }
    }

    private func latestRollbackCheckpoint(
        locale: String,
        family: String,
        setId: String,
        backup: ScreenshotBackupManifest
    ) throws -> ScreenshotRollbackCheckpoint? {
        guard let (_, operation) = screenshotRollbackOperation(locale: locale, family: family) else {
            return nil
        }
        guard let detail = operation.detail,
              let data = detail.data(using: .utf8) else {
            throw ReleaseToolError.remoteDrift("Screenshot rollback checkpoint is malformed")
        }
        let checkpoint: ScreenshotRollbackCheckpoint
        do {
            checkpoint = try JSONDecoder().decode(ScreenshotRollbackCheckpoint.self, from: data)
        } catch {
            throw ReleaseToolError.remoteDrift(
                "Screenshot rollback checkpoint could not be decoded: \(error.localizedDescription)"
            )
        }
        let expectedScreenshots = backup.screenshots.sorted(by: { $0.order < $1.order })
        guard checkpoint.schemaVersion == 1,
              checkpoint.locale == locale,
              checkpoint.family == family,
              checkpoint.displayType == backup.displayType,
              checkpoint.screenshotSetId == setId,
              checkpoint.backupDigest == (try backupDigest(backup)),
              checkpoint.screenshots.map(\.order) == expectedScreenshots.map(\.order),
              checkpoint.screenshots.map({ $0.sourceChecksum.lowercased() })
                == expectedScreenshots.map({ $0.md5.lowercased() }),
              Set(checkpoint.screenshots.map(\.resourceId)).count == checkpoint.screenshots.count else {
            throw ReleaseToolError.remoteDrift(
                "Screenshot rollback checkpoint does not match the verified backup"
            )
        }
        return checkpoint
    }

    private func checkpointDetail(_ checkpoint: ScreenshotRollbackCheckpoint) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(checkpoint)
        guard let detail = String(data: data, encoding: .utf8) else {
            throw ReleaseToolError.file("Could not encode screenshot rollback checkpoint")
        }
        return detail
    }

    private func backupDigest(_ backup: ScreenshotBackupManifest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return FileIO.sha256(try encoder.encode(backup))
    }

    private func screenshotRollbackOperation(
        locale: String,
        family: String
    ) -> (index: Int, operation: JournalOperation)? {
        let key = "screenshots:\(locale):\(family):rollback"
        for index in journal.operations.indices.reversed() {
            let operation = journal.operations[index]
            if operation.key == key, operation.status == "complete" {
                return (index, operation)
            }
        }
        return nil
    }

    private func screenshotEpochStartIndex(locale: String, family: String) -> Int {
        screenshotRollbackOperation(locale: locale, family: family).map { $0.index + 1 } ?? 0
    }

    private func screenshotEpochScope(for key: String) -> (locale: String, family: String)? {
        let components = key.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 4,
              components[0] == "screenshot" || components[0] == "screenshots" else {
            return nil
        }
        if components[0] == "screenshots",
           components[3] == "backup" || components[3] == "rollback" {
            return nil
        }
        return (components[1], components[2])
    }

    private func completedOperation(key: String) -> JournalOperation? {
        let startIndex: Int
        if let scope = screenshotEpochScope(for: key) {
            startIndex = screenshotEpochStartIndex(locale: scope.locale, family: scope.family)
        } else {
            startIndex = 0
        }
        guard startIndex < journal.operations.count else { return nil }
        return journal.operations[startIndex...].last {
            $0.key == key && $0.status == "complete"
        }
    }

    private func stableVersionProjection(_ version: RemoteVersion) -> JSONValue {
        .object([
            "id": .string(version.id),
            "version": .string(version.versionString),
            "state": version.state.map(JSONValue.string) ?? .null,
            "attributes": .object(filtered(
                version.attributes,
                keys: ["versionString", "platform", "releaseType", "copyright"]
            )),
            "localizations": .array(version.localizations.sorted { $0.locale < $1.locale }.map {
                .object([
                    "id": .string($0.id),
                    "locale": .string($0.locale),
                    "attributes": .object(filtered($0.attributes, keys: [
                        "locale", "description", "keywords", "marketingUrl", "promotionalText",
                        "supportUrl", "whatsNew",
                    ])),
                    "sets": .array($0.screenshotSets.sorted { $0.displayType < $1.displayType }.map {
                        .object([
                            "id": .string($0.id),
                            "type": .string($0.displayType),
                            "screenshots": .array(stableScreenshotProjection($0.screenshots)),
                        ])
                    }),
                ])
            }),
        ])
    }

    private func stableScreenshotProjection(_ screenshots: [RemoteScreenshot]) -> [JSONValue] {
        screenshots.map {
            .object([
                "id": .string($0.id),
                "checksum": $0.checksum.map { .string($0.lowercased()) } ?? .null,
                "complete": .bool(screenshotIsComplete($0)),
            ])
        }
    }

    private func remoteScreenshot(from value: JSONValue) throws -> RemoteScreenshot {
        guard let id = value["id"]?.stringValue,
              let attributes = value["attributes"]?.objectValue else {
            throw ReleaseToolError.remoteDrift("Malformed live screenshot resource")
        }
        return RemoteScreenshot(
            id: id,
            fileName: attributes["fileName"]?.stringValue,
            checksum: attributes["sourceFileChecksum"]?.stringValue,
            attributes: attributes
        )
    }

    private func remoteScreenshotsMatch(
        _ remote: [RemoteScreenshot],
        _ desired: [ManifestScreenshot]
    ) -> Bool {
        guard remote.count == desired.count else { return false }
        return zip(remote, desired.sorted(by: { $0.order < $1.order })).allSatisfy {
            $0.0.checksum?.lowercased() == $0.1.md5.lowercased() && screenshotIsComplete($0.0)
        }
    }

    private func screenshotIsComplete(_ screenshot: RemoteScreenshot) -> Bool {
        screenshot.attributes["assetDeliveryState"]?["state"]?.stringValue == "COMPLETE"
    }

    private func filtered(
        _ attributes: [String: JSONValue],
        keys: Set<String>
    ) -> [String: JSONValue] {
        attributes.filter { keys.contains($0.key) }
    }

    private func requireAttributes(
        _ actual: [String: JSONValue],
        equal expected: [String: JSONValue],
        context: String
    ) throws {
        let keys = Set(actual.keys).union(expected.keys)
        for key in keys {
            let lhs = actual[key] ?? .null
            let rhs = expected[key] ?? .null
            guard lhs == rhs else {
                throw ReleaseToolError.remoteDrift(
                    "Unknown change in \(context).\(key): expected \(rhs.any), got \(lhs.any)"
                )
            }
        }
    }

    private func verifyReadBack(manifest: PublishManifest, snapshot: RemoteSnapshot) throws {
        guard let target = snapshot.targetVersion,
              target.versionString == manifest.release.version,
              target.state == "PREPARE_FOR_SUBMISSION" else {
            throw ReleaseToolError.api("Published version could not be read back in an editable state")
        }
        let expectedLocales = Set(manifest.localizations.map(\.appStoreLocale))
        let actualVersionLocales = Set(target.localizations.map(\.locale))
        guard actualVersionLocales == expectedLocales else {
            throw ReleaseToolError.api(
                "Version localization set mismatch; expected \(expectedLocales.sorted()), got \(actualVersionLocales.sorted())"
            )
        }
        guard let appInfo = snapshot.appInfo, appInfo.state == "PREPARE_FOR_SUBMISSION" else {
            throw ReleaseToolError.api("Draft App Info is missing during final verification")
        }
        let actualAppLocales = Set(appInfo.localizations.map(\.locale))
        guard actualAppLocales == expectedLocales else {
            throw ReleaseToolError.api(
                "App Info localization set mismatch; expected \(expectedLocales.sorted()), got \(actualAppLocales.sorted())"
            )
        }
        try compare(
            effectiveVersionMetadata(manifest),
            with: target.attributes,
            context: "version \(manifest.release.version)"
        )
        for locale in manifest.localizations {
            guard let remote = target.localizations.first(where: { $0.locale == locale.appStoreLocale }) else {
                throw ReleaseToolError.api("Missing read-back locale \(locale.appStoreLocale)")
            }
            try compare(locale.versionMetadata, with: remote.attributes, context: locale.appStoreLocale)
            if !locale.appMetadata.isEmpty {
                guard let remoteApp = snapshot.appInfo?.localizations.first(where: {
                    $0.locale == locale.appStoreLocale
                }) else { throw ReleaseToolError.api("Missing App Info locale \(locale.appStoreLocale)") }
                try compare(locale.appMetadata, with: remoteApp.attributes, context: "App Info \(locale.appStoreLocale)")
            }
            for desiredSet in locale.screenshotSets {
                guard let remoteSet = remote.screenshotSets.first(where: {
                    $0.displayType == desiredSet.displayType
                }), remoteSet.screenshots.count == desiredSet.screenshots.count else {
                    throw ReleaseToolError.api("Screenshot count mismatch for \(locale.appStoreLocale) \(desiredSet.family)")
                }
                for (actual, desired) in zip(remoteSet.screenshots, desiredSet.screenshots.sorted(by: { $0.order < $1.order })) {
                    guard actual.checksum?.lowercased() == desired.md5.lowercased(),
                          actual.attributes["assetDeliveryState"]?["state"]?.stringValue == "COMPLETE" else {
                        throw ReleaseToolError.api("Screenshot checksum/order mismatch for \(locale.appStoreLocale)")
                    }
                }
            }
        }
    }

    private func compare(
        _ expected: [String: JSONValue],
        with actual: [String: JSONValue],
        context: String
    ) throws {
        for (key, value) in expected {
            if value == .null {
                guard actual[key] == nil || actual[key] == .null else {
                    throw ReleaseToolError.api("Read-back mismatch for \(context).\(key)")
                }
            } else if actual[key] != value {
                throw ReleaseToolError.api("Read-back mismatch for \(context).\(key)")
            }
        }
    }

    private func inheritedVersionAttributes(
        locale: String,
        snapshot: RemoteSnapshot
    ) -> [String: JSONValue] {
        let source = snapshot.targetVersion?.localizations.first { $0.locale == locale }
            ?? snapshot.sourceVersion?.localizations.first { $0.locale == locale }
        let allowed = Set([
            "description", "keywords", "marketingUrl", "promotionalText", "supportUrl", "whatsNew",
        ])
        return source?.attributes.filter { allowed.contains($0.key) } ?? [:]
    }

    private func effectiveVersionMetadata(_ manifest: PublishManifest) -> [String: JSONValue] {
        var metadata = manifest.release.versionMetadata
        if manifest.remoteSnapshot.targetVersion == nil,
           metadata["copyright"] == nil,
           let inherited = manifest.remoteSnapshot.sourceVersion?.attributes["copyright"] {
            metadata["copyright"] = inherited
        }
        return metadata
    }

    private func createAttributes(_ attributes: [String: JSONValue]) -> [String: JSONValue] {
        attributes.filter { $0.value != .null }
    }

    private func resourceBody(
        type: String,
        id: String? = nil,
        attributes: [String: JSONValue],
        relationship: (name: String, type: String, id: String)? = nil
    ) -> JSONValue {
        var data: [String: JSONValue] = [
            "type": .string(type),
            "attributes": .object(attributes),
        ]
        if let id { data["id"] = .string(id) }
        if let relationship {
            data["relationships"] = .object([
                relationship.name: .object([
                    "data": .object([
                        "type": .string(relationship.type),
                        "id": .string(relationship.id),
                    ]),
                ]),
            ])
        }
        return .object(["data": .object(data)])
    }

    private func resourceId(_ response: JSONValue?, context: String) throws -> String {
        guard let id = response?["data"]?["id"]?.stringValue else {
            throw ReleaseToolError.api("Malformed response for \(context)")
        }
        return id
    }

    @discardableResult
    private func perform(key: String, action: () throws -> String?) throws -> String {
        if let operation = completedOperation(key: key) {
            return operation.detail ?? ""
        }
        let detail = try action()
        try record(key: key, detail: detail)
        return detail ?? ""
    }

    private func isDone(_ key: String) -> Bool {
        completedOperation(key: key) != nil
    }

    private func operationDetail(key: String) throws -> String? {
        completedOperation(key: key)?.detail
    }

    private func operationDetailValue(key: String) -> String? {
        completedOperation(key: key)?.detail
    }

    private func record(key: String, detail: String?) throws {
        journal.operations.append(JournalOperation(
            key: key,
            status: "complete",
            timestamp: ISO8601DateFormatter.releaseTool.string(from: Date()),
            detail: detail
        ))
        try persistJournal()
    }

    private func persistJournal() throws { try FileIO.writeJSON(journal, to: journalURL) }
}
