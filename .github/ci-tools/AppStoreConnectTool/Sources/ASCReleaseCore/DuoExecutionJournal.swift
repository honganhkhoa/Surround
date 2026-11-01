import Darwin
import Foundation

struct DuoBackupImage: Codable, Equatable {
    let originalPlacement: DuoRemotePlacement
    let originalImageIdentity: JSONValue
    let file: DuoPublishImage
}

struct DuoExecutionEntry: Codable, Equatable {
    let key: String
    let status: String
    let requestDigest: String
    let resourceID: String?
}

struct DuoSingleImageRetry: Codable {
    let position: Int
    let originalImageID: String
    let sourceSHA256: String
    let originalEntries: [DuoExecutionEntry]
    var state: String = "pending"
    var attemptStarted = false
    var adoptedEntries: [DuoExecutionEntry]?
    var attemptJournalSHA256: String?
}

struct DuoExecutionJournal: Codable {
    var schemaVersion = 1
    let setDigest: String
    let version: String
    let rollbackStrategy: String
    var phase: String = "preparing"
    var epoch = 0
    var backups: [DuoBackupImage] = []
    var backupDigest: String?
    var activeBaseline: [DuoRemotePlacement]
    var activeImageIdentities: [String: JSONValue] = [:]
    var expectedGraph: [DuoRemotePlacement]?
    var completedPlacements: [DuoRemotePlacement] = []
    var entries: [DuoExecutionEntry] = []
    var activeCompatibility: DuoCompatibilityBaseline?
    var compatibilityCheckpoint: DuoCompatibilityBaseline?
    var singleImageRetry: DuoSingleImageRetry?

    func latest(_ key: String) -> DuoExecutionEntry? {
        if let retry = singleImageRetry, retry.state == "adopted",
           key.hasPrefix("desired:\(retry.position):") {
            return retry.adoptedEntries?.last { $0.key == key }
        }
        return entries.last { $0.key == key }
    }

    static func retryURL(_ url: URL, position: Int) -> URL {
        url.appendingPathExtension("single-image-retry-\(position).json")
    }

    func validateRetry(set: DuoPublishSet, url: URL) throws {
        guard (schemaVersion == 1 && singleImageRetry == nil) || (schemaVersion == 2 && singleImageRetry != nil) else {
            throw ReleaseToolError.validation("Unknown Duo journal schema or missing retry fence")
        }
        guard let retry = singleImageRetry else { return }
        guard let image = set.images.first(where: { $0.position == retry.position }),
              retry.sourceSHA256 == image.sha256,
              entries.last(where: { $0.key == "desired:\(retry.position):reserve" })?.resourceID == retry.originalImageID,
              ["pending", "original", "adopted"].contains(retry.state),
              retry.state != "pending" || (phase == "preparing" && epoch == 0) else {
            throw ReleaseToolError.validation("Retry scope, original identity or phase changed")
        }
        let prefix = "desired:\(retry.position):"
        let original = entries.filter { $0.key.hasPrefix(prefix) }
        guard !retry.originalEntries.isEmpty,
              Array(original.prefix(retry.originalEntries.count)) == retry.originalEntries,
              retry.originalEntries.last(where: { $0.key == prefix + "reserve" })?.status == "verified",
              retry.originalEntries.last(where: { $0.key == prefix + "upload" })?.status == "verified",
              retry.originalEntries.last(where: { $0.key == prefix + "commit" })?.status == "responseKnown",
              retry.state == "original" || original == retry.originalEntries else {
            throw ReleaseToolError.validation("Original known retry history changed")
        }
        if retry.state == "adopted" {
            let bytes = try Data(contentsOf: Self.retryURL(url, position: retry.position))
            let attempt = try JSONDecoder().decode(DuoExecutionJournal.self, from: bytes)
            guard retry.attemptJournalSHA256 == FileIO.sha256(bytes),
                  attempt.schemaVersion == 1, attempt.singleImageRetry == nil,
                  attempt.setDigest == setDigest, attempt.version == version,
                  attempt.rollbackStrategy == rollbackStrategy,
                  attempt.phase == "preparing", attempt.epoch == 0,
                  attempt.entries == retry.adoptedEntries,
                  Set(attempt.entries.map(\.key)) == Set([prefix + "reserve", prefix + "upload", prefix + "commit"]),
                  ["reserve", "upload", "commit"].allSatisfy({ attempt.latest(prefix + $0)?.status == "verified" }),
                  let id = attempt.latest(prefix + "reserve")?.resourceID, id != retry.originalImageID else {
                throw ReleaseToolError.validation("Adopted retry is not bound to its sealed one-attempt journal")
            }
        } else {
            guard retry.adoptedEntries == nil,
                  FileManager.default.fileExists(atPath: Self.retryURL(url, position: retry.position).path) else {
                throw ReleaseToolError.validation("Unadopted retry contains an active replacement binding")
            }
            if retry.state == "pending" {
                guard retry.attemptJournalSHA256 == nil else { throw ReleaseToolError.validation("Pending attempt is prematurely sealed") }
            } else {
                let bytes = try Data(contentsOf: Self.retryURL(url, position: retry.position))
                let attempt = try JSONDecoder().decode(DuoExecutionJournal.self, from: bytes)
                guard retry.attemptJournalSHA256 == FileIO.sha256(bytes), attempt.setDigest == setDigest,
                      attempt.schemaVersion == 1, attempt.singleImageRetry == nil,
                      attempt.version == version, attempt.phase == "preparing", attempt.epoch == 0,
                      Set(attempt.entries.map(\.key)).isSubset(of: [prefix + "reserve"]),
                      attempt.entries.isEmpty || (attempt.latest(prefix + "reserve")?.status == "verified" &&
                          attempt.latest(prefix + "reserve")?.resourceID != nil) else {
                    throw ReleaseToolError.validation("Unused retry reservation is not sealed at original preference")
                }
            }
        }
    }
}

/// Offline readers use the same desired-ID resolution as live execution.
public enum DuoJournalEvidence {
    public static func resolvedEntries(set: DuoPublishSet, journalURL: URL) throws -> [JSONValue] {
        let journal = try ManifestBuilder.decode(DuoExecutionJournal.self, at: journalURL)
        guard journal.setDigest == (try set.digest()) else { throw ReleaseToolError.validation("Duo evidence set changed") }
        try journal.validateRetry(set: set, url: journalURL)
        let entries = Set(journal.entries.map(\.key)).sorted().compactMap { journal.latest($0) }
        return try JSONDecoder().decode([JSONValue].self, from: JSONEncoder().encode(entries))
    }
    public static func desiredImageID(set: DuoPublishSet, journalURL: URL, position: Int) throws -> String {
        let journal = try ManifestBuilder.decode(DuoExecutionJournal.self, at: journalURL)
        guard journal.setDigest == (try set.digest()) else { throw ReleaseToolError.validation("Duo evidence set changed") }
        try journal.validateRetry(set: set, url: journalURL)
        guard let id = journal.latest("desired:\(position):reserve")?.resourceID else {
            throw ReleaseToolError.validation("Duo evidence has no owned desired image")
        }
        return id
    }
}

/// Exclusive ownership plus fsync-before-rename journal writes. Temporary files
/// contain no credentials or upload URLs and are retained if persistence fails.
final class DuoJournalFile {
    let url: URL
    private var lockFD: Int32 = -1
    private let writer: ((Data, URL) throws -> Void)?

    init(url: URL, writer: ((Data, URL) throws -> Void)?) throws {
        self.url = url; self.writer = writer
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &directory), directory.boolValue else {
            throw DuoExecutionFailure.persistence("Provide an existing handoff directory; journal creation never creates an unsynced parent chain")
        }
        guard url.resolvingSymlinksInPath() == url.standardizedFileURL else {
            throw ReleaseToolError.validation("Journal path must not use symlinks")
        }
        lockFD = Darwin.open(url.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lockFD >= 0 else { throw DuoExecutionFailure.persistence("Cannot open journal ownership lock") }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(lockFD)
            lockFD = -1
            throw DuoExecutionFailure.persistence("Another executor owns this journal")
        }
        try Self.syncDirectory(url.deletingLastPathComponent())
        try Self.syncDirectory(url.deletingLastPathComponent().deletingLastPathComponent())
    }

    deinit { if lockFD >= 0 { flock(lockFD, LOCK_UN); Darwin.close(lockFD) } }

    static func syncDirectory(_ url: URL) throws {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw DuoExecutionFailure.persistence("Cannot open the handoff directory for sync") }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw DuoExecutionFailure.persistence("Cannot sync the handoff directory") }
    }

    static func writeNewDataDurably(_ data: Data, to url: URL) throws {
        let fd = Darwin.open(url.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw DuoExecutionFailure.persistence("Cannot exclusively create the backup file") }
        defer { Darwin.close(fd) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                guard count > 0 else { throw DuoExecutionFailure.persistence("Backup file write failed") }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw DuoExecutionFailure.persistence("Backup file sync failed") }
        try syncDirectory(url.deletingLastPathComponent())
    }

    func save(_ journal: DuoExecutionJournal) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(journal)
        do {
            if let writer { try writer(data, url); return }
            let temporary = url.appendingPathExtension("pending-" + UUID().uuidString)
            let fd = Darwin.open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw POSIXError(.EIO) }
            defer { Darwin.close(fd) }
            try data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                    guard count > 0 else { throw POSIXError(.EIO) }
                    offset += count
                }
            }
            guard fsync(fd) == 0, Darwin.rename(temporary.path, url.path) == 0 else { throw POSIXError(.EIO) }
            let directory = Darwin.open(url.deletingLastPathComponent().path, O_RDONLY)
            guard directory >= 0 else { throw POSIXError(.EIO) }
            defer { Darwin.close(directory) }
            guard fsync(directory) == 0 else { throw POSIXError(.EIO) }
        } catch { throw DuoExecutionFailure.persistence("No further mutation is permitted until journal storage is healthy") }
    }
}
