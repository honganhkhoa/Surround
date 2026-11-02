import CryptoKit
import Foundation
import XCTest
@testable import ASCReleaseCore

final class RequestMetricsTests: XCTestCase {
    private func client(transport: HTTPTransport, retries: Int = 1,
                        now: @escaping () -> Date = Date.init,
                        sleeper: @escaping (TimeInterval) -> Void = { _ in }) -> ASCAPIClient {
        ASCAPIClient(credentials: ASCCredentials(keyId: "offline-test-key", issuerId: "offline-test-issuer",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation),
            baseURL: URL(string: "https://offline.example")!, transport: transport,
            maxRetries: retries, now: now, sleeper: sleeper)
    }

    func testActualAttemptsRetriesStatusesAndSeparateTransferCategories() throws {
        var reads = 0
        let transport = MetricsTransport { request in
            if request.url!.path == "/v1/read" {
                reads += 1
                return TransportResponse(data: Data("{}".utf8), statusCode: reads == 1 ? 503 : 200)
            }
            if request.url!.path == "/v1/network" {
                reads += 1
                if reads == 3 { throw URLError(.timedOut) }
                return TransportResponse(data: Data(), statusCode: 200)
            }
            if request.httpMethod == "POST" { return TransportResponse(data: Data(), statusCode: 500) }
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "Anonymous transfers must remain anonymous")
            return TransportResponse(data: Data([7, 8, 9]), statusCode: 200)
        }
        let client = client(transport: transport)
        try client.withPhase(.initialVerification) {
            _ = try client.request(method: "GET", path: "/v1/read")
            _ = try client.request(method: "GET", path: "/v1/network")
        }
        XCTAssertThrowsError(try client.withPhase(.placementMutation) {
            try client.request(method: "POST", path: "/v1/write", body: .object(["private": .string("not-recorded")]))
        })
        let operation = UploadOperation(method: "PUT", url: "https://offline.example/signed?private-token=hidden",
            offset: 1, length: 2, requestHeaders: [UploadHeader(name: "X-Upload-Secret", value: "not-recorded")])
        try client.withPhase(.imageStaging) { try client.upload(operation: operation, fileData: Data([1, 2, 3, 4])) }
        _ = try client.withPhase(.finalVerification) {
            try client.download(url: URL(string: "https://cdn.example/image?secret=not-recorded")!)
        }
        let report = client.metrics.snapshot()
        XCTAssertEqual(report.total.attempts, 7)
        XCTAssertEqual(report.total.retries, 2)
        XCTAssertEqual(report.total.inFlight, 0)
        XCTAssertEqual(report.total.transportErrors, 1)
        XCTAssertEqual(report.total.httpStatuses, ["200": 4, "503": 1, "500": 1])
        XCTAssertEqual(report.categories["authenticatedRead"]?.attempts, 4)
        XCTAssertEqual(report.categories["authenticatedWrite"]?.attempts, 1)
        XCTAssertEqual(report.categories["binaryUpload"]?.attempts, 1)
        XCTAssertEqual(report.categories["binaryUpload"]?.sentBytes, 2)
        XCTAssertEqual(report.categories["imageDownload"]?.attempts, 1)
        XCTAssertEqual(report.categories["imageDownload"]?.receivedBytes, 3)
        XCTAssertEqual(report.phases["initialVerification"]?["authenticatedRead"]?.attempts, 4)
        XCTAssertEqual(report.total.scheduledRetryWaitSeconds, 2)
        let serialized = String(data: try JSONEncoder().encode(report), encoding: .utf8)!
        for privateText in ["private-token", "not-recorded", "Authorization", "offline.example", "/v1/read", "offline-test-issuer"] {
            XCTAssertFalse(serialized.contains(privateText))
        }
        XCTAssertFalse(report.recordsURLsHeadersBodiesOrResourceIDs)
    }

    func testPacingAndTransportTimingAreCountedWithoutChangingRetryRules() throws {
        var now = Date(timeIntervalSince1970: 1000)
        let transport = MetricsTransport { _ in
            now.addTimeInterval(0.25)
            return TransportResponse(data: Data(), statusCode: 200,
                headers: ["X-Rate-Limit": "user-hour-lim:3600;user-hour-rem:3000;"])
        }
        let client = client(transport: transport, now: { now }, sleeper: { now.addTimeInterval($0) })
        _ = try client.request(method: "GET", path: "/v1/one")
        _ = try client.request(method: "GET", path: "/v1/two")
        let report = client.metrics.snapshot()
        XCTAssertEqual(report.total.attempts, 2)
        XCTAssertEqual(report.total.transportSeconds, 0.5, accuracy: 0.001)
        XCTAssertEqual(report.total.scheduledPacingSeconds, 1, accuracy: 0.001)
        XCTAssertEqual(report.elapsedSeconds, 1.5, accuracy: 0.001)
    }

    func testLongServerCooldownDoesNotCountAnUnsentRetryOrSleep() throws {
        let client = client(transport: MetricsTransport { _ in
            TransportResponse(data: Data(), statusCode: 429, headers: ["Retry-After": "54"])
        }, sleeper: { _ in XCTFail("Long cooldown must not sleep/retry") })
        XCTAssertThrowsError(try client.request(method: "GET", path: "/v1/read"))
        let report = client.metrics.snapshot()
        XCTAssertEqual(report.total.attempts, 1)
        XCTAssertEqual(report.total.retries, 0)
        XCTAssertEqual(report.total.httpStatuses, ["429": 1])
        XCTAssertEqual(report.total.scheduledRetryWaitSeconds, 0)
    }

    func testNestedPhaseRestoresAfterThrownOperation() throws {
        enum Expected: Error { case stop }
        let metrics = ASCRequestMetrics()
        try metrics.withPhase(.metadata) {
            XCTAssertThrowsError(try metrics.withPhase(.recovery) {
                let a = metrics.begin(category: .authenticatedWrite, retry: false, sentBytes: 0)
                metrics.finish(a, response: TransportResponse(data: Data(), statusCode: 200))
                throw Expected.stop
            })
            let b = metrics.begin(category: .authenticatedRead, retry: false, sentBytes: 0)
            metrics.finish(b, response: TransportResponse(data: Data(), statusCode: 200))
        }
        let c = metrics.begin(category: .imageDownload, retry: false, sentBytes: 0)
        metrics.finish(c, response: TransportResponse(data: Data(), statusCode: 200))
        let report = metrics.snapshot()
        XCTAssertEqual(report.phases["recovery"]?["authenticatedWrite"]?.attempts, 1)
        XCTAssertEqual(report.phases["metadata"]?["authenticatedRead"]?.attempts, 1)
        XCTAssertEqual(report.phases["unclassified"]?["imageDownload"]?.attempts, 1)
    }

    func testConcurrentWorkersKeepPhasesAndCountsSeparate() {
        let metrics = ASCRequestMetrics()
        DispatchQueue.concurrentPerform(iterations: 1000) { index in
            metrics.withPhase(index.isMultiple(of: 2) ? .processingPoll : .imageStaging) {
                let a = metrics.begin(category: .authenticatedRead, retry: false, sentBytes: 0)
                metrics.finish(a, response: TransportResponse(data: Data([1]), statusCode: 200))
            }
        }
        let report = metrics.snapshot()
        XCTAssertEqual(report.total.attempts, 1000)
        XCTAssertEqual(report.total.receivedBytes, 1000)
        XCTAssertEqual(report.total.inFlight, 0)
        XCTAssertEqual(report.phases["processingPoll"]?["authenticatedRead"]?.attempts, 500)
        XCTAssertEqual(report.phases["imageStaging"]?["authenticatedRead"]?.attempts, 500)
    }

    func testDurableRunningAndFailureReportsContainNoErrorOrRequestData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var output: URL!
        let client = client(transport: MetricsTransport { _ in
            let running = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: output))
            XCTAssertEqual(running["outcome"], .string("running"))
            XCTAssertEqual(running["counterCompleteness"], .string("checkpoint-lower-bound"))
            XCTAssertEqual(running["total"]?["attempts"]?.intValue, 0)
            XCTAssertEqual(running["total"]?["inFlight"]?.intValue, 0)
            throw NSError(domain: "secret-error-token", code: 7)
        }, retries: 0)
        output = client.metrics.reportURL(beside: directory.appendingPathComponent("journal.json"))
        XCTAssertThrowsError(try client.metrics.recording(to: output) {
            try client.request(method: "POST", path: "/v1/private-resource")
        })
        let data = try Data(contentsOf: output)
        let report = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(report["outcome"], .string("failed"))
        XCTAssertEqual(report["total"]?["attempts"]?.intValue, 1)
        XCTAssertEqual(report["total"]?["transportErrors"]?.intValue, 1)
        XCTAssertEqual(report["total"]?["inFlight"]?.intValue, 0)
        XCTAssertEqual(report["counterCompleteness"], .string("all-observed-transport-attempts"))
        let serialized = String(data: data, encoding: .utf8)!
        XCTAssertFalse(serialized.contains("secret-error-token"))
        XCTAssertFalse(serialized.contains("private-resource"))
        XCTAssertNotEqual(output, ASCRequestMetrics().reportURL(beside: directory.appendingPathComponent("journal.json")))
    }

    func testSuccessReportAndUnwritableInitialReportBeforeOperation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let metrics = ASCRequestMetrics(), output = metrics.reportURL(beside: directory.appendingPathComponent("journal.json"))
        XCTAssertEqual(try metrics.recording(to: output) { 42 }, 42)
        XCTAssertEqual(try FileIO.readJSON(at: output)["outcome"], .string("succeeded"))
        let notDirectory = directory.appendingPathComponent("file")
        try Data([1]).write(to: notDirectory)
        var ran = false
        XCTAssertThrowsError(try metrics.recording(to: notDirectory.appendingPathComponent("impossible.json")) { ran = true })
        XCTAssertFalse(ran, "Metrics admission must fail before starting the command")
    }

    func testLateTelemetryFailureNeverChangesKnownOperationOutcome() throws {
        enum Expected: Error { case originalFailure }
        for shouldThrow in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let metrics = ASCRequestMetrics()
            let output = metrics.reportURL(beside: directory.appendingPathComponent("journal.json"))
            func run() throws -> Int {
                try metrics.recording(to: output) {
                    // Only this test's disposable directory is replaced to
                    // force the final telemetry write to fail after the action.
                    try FileManager.default.removeItem(at: directory)
                    try Data([1]).write(to: directory)
                    if shouldThrow { throw Expected.originalFailure }
                    return 42
                }
            }
            if shouldThrow {
                XCTAssertThrowsError(try run()) { error in
                    guard case Expected.originalFailure = error else {
                        return XCTFail("Telemetry masked the operation's original error")
                    }
                }
            } else { XCTAssertEqual(try run(), 42) }
        }
    }

    func testRunningCheckpointsAreBatchedAndFinalCountersAreExact() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixedNow = Date(timeIntervalSince1970: 1000)
        let metrics = ASCRequestMetrics(now: { fixedNow })
        let output = metrics.reportURL(beside: directory.appendingPathComponent("journal.json"))
        try metrics.recording(to: output) {
            for count in 1...103 {
                let attempt = metrics.begin(category: .authenticatedRead, retry: false, sentBytes: 0)
                metrics.finish(attempt, response: TransportResponse(data: Data(), statusCode: 200))
                if [24, 25, 99, 103].contains(count) {
                    let checkpoint = try FileIO.readJSON(at: output)
                    XCTAssertEqual(checkpoint["total"]?["attempts"]?.intValue, (count / 25) * 25)
                    XCTAssertEqual(checkpoint["completedAttemptCheckpointThreshold"]?.intValue, 25)
                    XCTAssertEqual(checkpoint["counterCompleteness"], .string("checkpoint-lower-bound"))
                }
            }
            XCTAssertEqual(metrics.successfulReportWrites, 5, "Initial + four batches; never begin/finish per request")
        }
        XCTAssertEqual(metrics.successfulReportWrites, 6, "One exact durable final report")
        let final = try FileIO.readJSON(at: output)
        XCTAssertEqual(final["outcome"], .string("succeeded"))
        XCTAssertEqual(final["total"]?["attempts"]?.intValue, 103)
        XCTAssertEqual(final["counterCompleteness"], .string("all-observed-transport-attempts"))
    }

    func testRunningCheckpointTimeTriggerOccursOnCompletionOnly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = Date(timeIntervalSince1970: 1000)
        let metrics = ASCRequestMetrics(now: { now })
        let output = metrics.reportURL(beside: directory.appendingPathComponent("journal.json"))
        try metrics.recording(to: output) {
            let first = metrics.begin(category: .authenticatedRead, retry: false, sentBytes: 0)
            now.addTimeInterval(1.1)
            XCTAssertEqual(try FileIO.readJSON(at: output)["total"]?["attempts"]?.intValue, 0,
                           "No timer or begin-time disk write")
            metrics.finish(first, response: TransportResponse(data: Data(), statusCode: 200))
            XCTAssertEqual(try FileIO.readJSON(at: output)["total"]?["attempts"]?.intValue, 1)
            let second = metrics.begin(category: .imageDownload, retry: false, sentBytes: 0)
            now.addTimeInterval(0.1)
            metrics.finish(second, response: TransportResponse(data: Data(), statusCode: 200))
            XCTAssertEqual(metrics.successfulReportWrites, 2)
        }
        XCTAssertEqual(metrics.successfulReportWrites, 3)
        XCTAssertEqual(try FileIO.readJSON(at: output)["total"]?["attempts"]?.intValue, 2)
    }
}

private final class MetricsTransport: HTTPTransport, @unchecked Sendable {
    let handler: (URLRequest) throws -> TransportResponse
    init(_ handler: @escaping (URLRequest) throws -> TransportResponse) { self.handler = handler }
    func send(_ request: URLRequest) throws -> TransportResponse { try handler(request) }
}
