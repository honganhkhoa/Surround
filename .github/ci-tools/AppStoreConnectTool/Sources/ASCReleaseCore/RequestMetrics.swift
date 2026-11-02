import Foundation
import Darwin

/// Fixed labels prevent resource identifiers, signed URLs or credentials from
/// accidentally entering a metrics artifact through a caller-supplied phase.
public enum ASCRequestPhase: String, Codable, CaseIterable, Sendable {
    case unclassified, publication, singleImageRetry, initialVerification
    case snapshot, imageStaging, processingPoll, placementMutation
    case metadata, recovery, finalVerification
}

public enum ASCRequestCategory: String, Codable, CaseIterable, Sendable {
    case authenticatedRead, authenticatedWrite, binaryUpload, imageDownload
}

public enum ASCRequestMetricsOutcome: String, Codable, Sendable {
    case running, succeeded, failed
}

public struct ASCRequestMetricCounts: Codable, Equatable, Sendable {
    public var attempts = 0
    public var retries = 0
    public var inFlight = 0
    public var transportErrors = 0
    public var sentBytes = 0
    public var receivedBytes = 0
    public var transportSeconds: TimeInterval = 0
    public var scheduledPacingSeconds: TimeInterval = 0
    public var scheduledRetryWaitSeconds: TimeInterval = 0
    public var httpStatuses: [String: Int] = [:]
}

public struct ASCRequestMetricsSnapshot: Codable, Sendable {
    public let schemaVersion: Int
    public let invocationID: String
    public let startedAt: Date
    public let capturedAt: Date
    public let elapsedSeconds: TimeInterval
    public let outcome: ASCRequestMetricsOutcome
    public let total: ASCRequestMetricCounts
    public let categories: [String: ASCRequestMetricCounts]
    public let phases: [String: [String: ASCRequestMetricCounts]]
    public let recordsURLsHeadersBodiesOrResourceIDs: Bool
    public let counterCompleteness: String
    public let checkpointPolicy: String
    public let completedAttemptCheckpointThreshold: Int
    public let checkpointIntervalSeconds: TimeInterval
    public let inFlightAtCheckpoint: Int
    public let byteCountSemantics: String
}

struct ASCRequestMetricAttempt {
    let category: ASCRequestCategory
    let phase: ASCRequestPhase
    let startedAt: Date
}

/// Invocation-local counters for actual transport attempts, rather than
/// estimates based on logical API calls. Counter updates are thread-safe;
/// nested phase scopes are thread-local and do not relabel another worker.
public final class ASCRequestMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private let persistenceLock = NSLock()
    private let now: () -> Date
    private let startedAt: Date
    private let invocationID = UUID().uuidString
    private let phaseKey = "ASCRequestMetrics.phase." + UUID().uuidString
    private var total = ASCRequestMetricCounts()
    private var categories: [String: ASCRequestMetricCounts] = [:]
    private var phases: [String: [String: ASCRequestMetricCounts]] = [:]
    private var activeReportURL: URL?
    private var warnedAboutPersistence = false
    private var lastCheckpointAt: Date
    private var lastCheckpointCompletedAttempts = 0
    private var reportWrites = 0

    // Internal observability for regression tests; not a network request count.
    var successfulReportWrites: Int {
        lock.lock(); defer { lock.unlock() }
        return reportWrites
    }

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
        let start = now()
        self.startedAt = start
        self.lastCheckpointAt = start
    }

    public func withPhase<T>(_ phase: ASCRequestPhase, _ operation: () throws -> T) rethrows -> T {
        let dictionary = Thread.current.threadDictionary
        let previous = dictionary[phaseKey]
        dictionary[phaseKey] = phase.rawValue
        defer {
            if let previous { dictionary[phaseKey] = previous }
            else { dictionary.removeObject(forKey: phaseKey) }
        }
        return try operation()
    }

    private var currentPhase: ASCRequestPhase {
        (Thread.current.threadDictionary[phaseKey] as? String).flatMap(ASCRequestPhase.init(rawValue:)) ?? .unclassified
    }

    private func update(category: ASCRequestCategory, phase: ASCRequestPhase,
                        _ change: (inout ASCRequestMetricCounts) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        change(&total)
        var categoryCounts = categories[category.rawValue] ?? ASCRequestMetricCounts()
        change(&categoryCounts)
        categories[category.rawValue] = categoryCounts
        var phaseCounts = phases[phase.rawValue] ?? [:]
        var counts = phaseCounts[category.rawValue] ?? ASCRequestMetricCounts()
        change(&counts)
        phaseCounts[category.rawValue] = counts
        phases[phase.rawValue] = phaseCounts
    }

    func begin(category: ASCRequestCategory, retry: Bool, sentBytes: Int) -> ASCRequestMetricAttempt {
        let attempt = ASCRequestMetricAttempt(category: category, phase: currentPhase, startedAt: now())
        update(category: category, phase: attempt.phase) { counts in
            counts.attempts += 1
            counts.retries += retry ? 1 : 0
            counts.inFlight += 1
            counts.sentBytes += max(0, sentBytes)
        }
        return attempt
    }

    func finish(_ attempt: ASCRequestMetricAttempt, response: TransportResponse?) {
        let elapsed = max(0, now().timeIntervalSince(attempt.startedAt))
        update(category: attempt.category, phase: attempt.phase) { counts in
            counts.inFlight -= 1
            counts.transportSeconds += elapsed
            if let response {
                counts.receivedBytes += response.data.count
                counts.httpStatuses[String(response.statusCode), default: 0] += 1
            } else { counts.transportErrors += 1 }
        }
        checkpointIfRecording()
    }

    func recordWait(_ seconds: TimeInterval, category: ASCRequestCategory, pacing: Bool) {
        guard seconds > 0, seconds.isFinite else { return }
        update(category: category, phase: currentPhase) { counts in
            if pacing { counts.scheduledPacingSeconds += seconds }
            else { counts.scheduledRetryWaitSeconds += seconds }
        }
    }

    public func snapshot(outcome: ASCRequestMetricsOutcome = .running) -> ASCRequestMetricsSnapshot {
        let capturedAt = now()
        lock.lock()
        defer { lock.unlock() }
        return ASCRequestMetricsSnapshot(schemaVersion: 1, invocationID: invocationID,
            startedAt: startedAt, capturedAt: capturedAt,
            elapsedSeconds: max(0, capturedAt.timeIntervalSince(startedAt)), outcome: outcome,
            total: total, categories: categories, phases: phases,
            recordsURLsHeadersBodiesOrResourceIDs: false,
            counterCompleteness: outcome == .running ? "checkpoint-lower-bound" : "all-observed-transport-attempts",
            checkpointPolicy: "On completion after 25 additional completed attempts or 1 second, whichever occurs first; no background timer. With one writer and healthy persistence a hard stop may lose the current batch of up to 25 completions plus later in-flight attempts. Concurrent completions, checkpoint I/O or persistence failure can exceed that diagnostic bound. capturedAt/inFlight describe this checkpoint, not current activity. Recovery journal remains authoritative.",
            completedAttemptCheckpointThreshold: 25, checkpointIntervalSeconds: 1,
            inFlightAtCheckpoint: total.inFlight,
            byteCountSemantics: "sentBytes is attempted HTTP body length per HTTPTransport.send, not observed wire bytes; receivedBytes is returned response data. Redirects and transport-internal connection activity are not counted.")
    }

    /// Uses a unique file per command invocation so a resume never overwrites
    /// earlier counts. This is diagnostic evidence, never recovery authority.
    public func reportURL(beside journalURL: URL) -> URL {
        journalURL.deletingLastPathComponent()
            .appendingPathComponent("request-metrics-\(invocationID).json")
    }

    public func writeReport(to url: URL, outcome: ASCRequestMetricsOutcome) throws {
        try persistReport(snapshot(outcome: outcome), to: url)
    }

    private func persistReport(_ report: ASCRequestMetricsSnapshot, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try FileIO.write(data: encoder.encode(report) + Data([0x0A]), to: url)
        // FileIO's atomic replacement protects readers from partial JSON;
        // sync both file and directory before claiming the checkpoint durable.
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw ReleaseToolError.file("Could not sync request metrics") }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw ReleaseToolError.file("Could not sync request metrics") }
        let directory = Darwin.open(url.deletingLastPathComponent().path, O_RDONLY)
        guard directory >= 0 else { throw ReleaseToolError.file("Could not sync request metrics directory") }
        defer { Darwin.close(directory) }
        guard Darwin.fsync(directory) == 0 else { throw ReleaseToolError.file("Could not sync request metrics directory") }
        lock.lock(); reportWrites += 1; lock.unlock()
    }

    private func checkpointIfRecording() {
        persistenceLock.lock()
        defer { persistenceLock.unlock() }
        guard let url = activeReportURL else { return }
        let report = snapshot()
        let completed = report.total.attempts - report.total.inFlight
        guard completed - lastCheckpointCompletedAttempts >= report.completedAttemptCheckpointThreshold ||
                report.capturedAt.timeIntervalSince(lastCheckpointAt) >= report.checkpointIntervalSeconds else { return }
        do {
            try persistReport(report, to: url)
            lastCheckpointAt = report.capturedAt
            lastCheckpointCompletedAttempts = completed
        }
        catch { warnAboutPersistence() }
    }

    private func warnAboutPersistence() {
        guard !warnedAboutPersistence else { return }
        warnedAboutPersistence = true
        FileHandle.standardError.write(Data("warning: request metrics could not be saved; recovery journal remains authoritative\n".utf8))
    }

    private func writeFinalReport(to url: URL, outcome: ASCRequestMetricsOutcome) {
        persistenceLock.lock()
        defer { persistenceLock.unlock() }
        do { try writeReport(to: url, outcome: outcome) }
        catch { warnAboutPersistence() }
    }

    /// Saves counters for both known completion and thrown errors. No error
    /// description is retained because service errors can contain private data.
    public func recording<T>(to url: URL, operation: () throws -> T) throws -> T {
        persistenceLock.lock()
        guard activeReportURL == nil else {
            persistenceLock.unlock()
            throw ReleaseToolError.validation("Request metrics recording is already active")
        }
        activeReportURL = url
        persistenceLock.unlock()
        defer {
            persistenceLock.lock()
            activeReportURL = nil
            persistenceLock.unlock()
        }
        let initial = snapshot()
        try persistReport(initial, to: url)
        persistenceLock.lock()
        lastCheckpointAt = initial.capturedAt
        lastCheckpointCompletedAttempts = initial.total.attempts - initial.total.inFlight
        persistenceLock.unlock()
        let value: T
        do {
            value = try operation()
        } catch {
            writeFinalReport(to: url, outcome: .failed)
            throw error
        }
        // After a remote mutation, a diagnostic write failure must never turn
        // a known response into an apparent ambiguous request or invite replay.
        writeFinalReport(to: url, outcome: .succeeded)
        return value
    }
}
