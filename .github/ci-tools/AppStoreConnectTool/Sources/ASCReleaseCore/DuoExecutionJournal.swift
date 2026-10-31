import Darwin
import Foundation

struct DuoBackupImage: Codable, Equatable {
    let originalPlacement: DuoRemotePlacement
    let originalImageIdentity: JSONValue
    let file: DuoPublishImage
}

struct DuoExecutionEntry: Codable {
    let key: String
    let status: String
    let requestDigest: String
    let resourceID: String?
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
