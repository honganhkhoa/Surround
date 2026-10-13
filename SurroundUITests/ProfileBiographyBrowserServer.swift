import Foundation
import Network
import XCTest

/// A test-owned HTTP endpoint that accepts only loopback connections.
/// Network callbacks and mutable state use one serial queue; public methods
/// take queue-synchronized snapshots. Active callbacks retain self, so teardown
/// cannot overlap deinitialization.
final class ProfileBiographyBrowserServer: @unchecked Sendable {
    static let pageMarker = "Surround biography browser fixture"
    static let requestTarget = "/biography/read?context=profile"

    private let queue = DispatchQueue(label: "SurroundUITests.biography-browser")
    private let listener: NWListener
    private let ready = XCTestExpectation(description: "Loopback biography server ready")
    private let requested = XCTestExpectation(description: "Safari requested the biography page")
    // Mutable state is confined to queue; async test methods take short snapshots.
    private var started = false
    private var readyReported = false
    private var readinessFailure: String?
    private var receivedTarget: String?
    private var connections: [NWConnection] = []

    // Temporary passive diagnostics; URL, response, and waiter bounds stay exact.
    private let telemetryInstance = UUID().uuidString
    private let telemetryLimit = 256
    private var telemetry = [[String: Any]]()
    private var discardedTelemetry = 0
    private var teardownJournalRegistered = false
    private var acceptedConnections = 0
    private var activeConnectionIDs = [ObjectIdentifier: Int]()
    private var listenerState = "not-started"

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionLimit = 8
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            listenerState = String(String(describing: state).prefix(512))
            record("listener-state", fields: ["state": listenerState])
            guard !readyReported else { return }
            switch state {
            case .ready:
                readyReported = true
                ready.fulfill()
            case .failed(let error), .waiting(let error):
                readinessFailure = error.localizedDescription
                readyReported = true
                ready.fulfill()
            case .cancelled:
                readinessFailure = "The loopback listener was cancelled before becoming ready."
                readyReported = true
                ready.fulfill()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            acceptedConnections += 1
            let connectionID = acceptedConnections
            activeConnectionIDs[ObjectIdentifier(connection)] = connectionID
            record("connection-accepted", connectionID: connectionID)
            connections.append(connection)
            connection.stateUpdateHandler = { [weak self] state in
                self?.record("connection-state", connectionID: connectionID,
                             fields: ["state": String(String(describing: state).prefix(512))])
            }
            connection.start(queue: queue)
            receiveHeaders(on: connection, connectionID: connectionID)
            queue.asyncAfter(deadline: .now() + 3) { [weak self, weak connection] in
                if let connection {
                    self?.finish(connection, connectionID: connectionID, reason: "existing-three-second-bound")
                }
            }
        }
    }

    func start(in test: XCTestCase, timeout: TimeInterval = 3) async throws -> URL {
        let registerJournal = queue.sync {
            guard !teardownJournalRegistered else { return false }
            teardownJournalRegistered = true
            return true
        }
        if registerJournal {
            // Original stop was registered before start. XCTest runs teardown
            // serially on main in LIFO order, so this journal precedes stop.
            test.addTeardownBlock { [self, weak test] in
                let journal = publishJournal(stage: "teardown", testAvailable: test != nil)
                let attachment = XCTAttachment(string: journal)
                attachment.name = "Biography browser passive telemetry – \(telemetryInstance)"
                attachment.lifetime = .keepAlways
                test?.add(attachment)
            }
        }
        queue.async { [self] in
            guard !started else { return }
            started = true
            record("listener-start")
            listener.start(queue: queue)
        }
        await test.fulfillment(of: [ready], timeout: timeout)
        return try queue.sync {
            guard readinessFailure == nil, readyReported, let port = listener.port,
                  let url = URL(string: "http://127.0.0.1:\(port.rawValue)\(Self.requestTarget)#local-proof") else {
                throw failure(readinessFailure ?? "The loopback server did not report an available port within the readiness timeout.")
            }
            record("server-url", fields: ["url": url.absoluteString])
            return url
        }
    }

    // Called explicitly by availability diagnostics while their body activity
    // is alive. Snapshot publication adds no request or new expectation.
    func attachSnapshot(in test: XCTestCase) {
        let journal = publishJournal(stage: "body", testAvailable: true)
        let attachment = XCTAttachment(string: journal)
        attachment.name = "Biography browser body journal – \(telemetryInstance)"
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }

    func waitForRequest(in test: XCTestCase, timeout: TimeInterval = 5) async throws -> String {
        queue.sync {
            record("request-wait-begin", fields: [
                "timeoutSeconds": timeout,
                "nominalDeadlineUptime": ProcessInfo.processInfo.systemUptime + timeout,
            ])
        }
        await test.fulfillment(of: [requested], timeout: timeout)
        return try queue.sync {
            record("request-wait-returned")
            guard let receivedTarget else {
                throw failure("Safari did not request the local biography page within the request timeout.")
            }
            return receivedTarget
        }
    }

    func stop() {
        queue.async { [self] in
            record("server-stop")
            listener.cancel()
            connections.forEach { connection in
                record("connection-close", connectionID: activeConnectionIDs[ObjectIdentifier(connection)],
                       fields: ["reason": "server-stop"])
                connection.cancel()
            }
            connections.removeAll()
            activeConnectionIDs.removeAll()
        }
    }

    deinit {
        listener.cancel()
        connections.forEach { $0.cancel() }
    }

    private func receiveHeaders(on connection: NWConnection, connectionID: Int, accumulated: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self, weak connection] data, _, complete, error in
            guard let self, let connection else { return }
            var headers = accumulated
            if let data { headers.append(data) }
            guard headers.count <= 16_384, error == nil else {
                record("headers-rejected", connectionID: connectionID, fields: [
                    "receivedBytes": headers.count,
                    "error": String(String(describing: error).prefix(512)),
                ])
                finish(connection, connectionID: connectionID, reason: "headers-limit-or-receive-error")
                return
            }
            let text = String(decoding: headers, as: UTF8.self)
            if text.contains("\r\n\r\n") {
                let fields = text.components(separatedBy: "\r\n").first?.split(separator: " ") ?? []
                let method = fields.first.map(String.init) ?? ""
                let authoredTarget = fields.count >= 2 ? String(fields[1]) : ""
                let target = fields.count >= 2 && fields[0] == "GET" ? String(fields[1]) : ""
                record("request-parsed", connectionID: connectionID, fields: [
                    "method": String(method.prefix(32)),
                    "target": String(authoredTarget.prefix(512)),
                    "targetTruncated": authoredTarget.count > 512,
                ])
                if target.hasPrefix("/biography/read"), receivedTarget == nil {
                    receivedTarget = target
                    record("request-fulfill-before", connectionID: connectionID)
                    requested.fulfill()
                    record("request-fulfill-after", connectionID: connectionID)
                }
                let matches = target == Self.requestTarget
                let body = matches
                    ? "<!doctype html><html><head><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>Local biography page</title></head><body><p id=\"local-proof\">\(Self.pageMarker)</p></body></html>"
                    : "Not found"
                let response = "HTTP/1.1 \(matches ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nContent-Security-Policy: default-src 'none'; base-uri 'none'; form-action 'none'\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n\(body)"
                record("response-send", connectionID: connectionID, fields: [
                    "exactTargetMatch": matches,
                    "responseBytes": response.utf8.count,
                ])
                connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self, weak connection] error in
                    guard let self, let connection else { return }
                    record("response-send-completed", connectionID: connectionID,
                           fields: ["error": String(String(describing: error).prefix(512))])
                    finish(connection, connectionID: connectionID,
                           reason: error == nil ? "response-sent" : "send-error")
                })
            } else if complete {
                record("headers-ended-incomplete", connectionID: connectionID,
                       fields: ["receivedBytes": headers.count])
                finish(connection, connectionID: connectionID, reason: "peer-ended-before-headers")
            } else {
                receiveHeaders(on: connection, connectionID: connectionID, accumulated: headers)
            }
        }
    }

    private func finish(_ connection: NWConnection, connectionID: Int, reason: String) {
        record("connection-close", connectionID: connectionID, fields: [
            "reason": reason,
            "wasActive": activeConnectionIDs[ObjectIdentifier(connection)] != nil,
        ])
        connection.cancel()
        connections.removeAll { $0 === connection }
        activeConnectionIDs.removeValue(forKey: ObjectIdentifier(connection))
    }

    // Called only on queue. Raw headers/bodies and credentials are not retained;
    // request method/target and state/error strings are bounded.
    private func record(_ event: String, connectionID: Int? = nil, fields: [String: Any] = [:]) {
        guard telemetry.count < telemetryLimit else {
            discardedTelemetry += 1
            return
        }
        var entry = fields
        entry["event"] = event
        entry["uptimeSeconds"] = ProcessInfo.processInfo.systemUptime
        entry["utcEpochSeconds"] = Date().timeIntervalSince1970
        if let connectionID { entry["connectionID"] = connectionID }
        telemetry.append(entry)
        // Emit each retained event immediately on queue, including callbacks
        // before teardown. Logging stays bounded by the same journal cap.
        emit(["instance": telemetryInstance, "recordedEvent": entry])
    }

    private func publishJournal(stage: String, testAvailable: Bool) -> String {
        queue.sync {
            record(stage == "teardown" ? "teardown-journal-before-stop" : "body-journal",
                   fields: ["testAvailable": testAvailable])
            var snapshot: [String: Any] = [
                "instance": telemetryInstance,
                "stage": stage,
                "testAvailable": testAvailable,
                "listenerState": listenerState,
                "readyReported": readyReported,
                "acceptedConnections": acceptedConnections,
                "activeConnectionIDs": activeConnectionIDs.values.sorted(),
                "eventLimit": telemetryLimit,
                "discardedEvents": discardedTelemetry,
                "events": telemetry,
            ]
            if let port = listener.port { snapshot["listenerPort"] = port.rawValue }
            if let receivedTarget { snapshot["receivedTarget"] = String(receivedTarget.prefix(512)) }
            if let readinessFailure { snapshot["readinessFailure"] = String(readinessFailure.prefix(512)) }
            let journal = encode(snapshot)
            emitEncoded(journal)
            return journal
        }
    }

    private func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"telemetryEncodingError\":true}"
        }
        return text
    }

    private func emit(_ object: [String: Any]) {
        emitEncoded(encode(object))
    }

    private func emitEncoded(_ text: String) {
        NSLog("[BiographyBrowserTelemetry] %@", text)
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "ProfileBiographyBrowserServer", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
