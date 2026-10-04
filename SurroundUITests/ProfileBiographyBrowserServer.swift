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

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionLimit = 8
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, !readyReported else { return }
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
            connections.append(connection)
            connection.start(queue: queue)
            receiveHeaders(on: connection)
            queue.asyncAfter(deadline: .now() + 3) { [weak self, weak connection] in
                if let connection { self?.finish(connection) }
            }
        }
    }

    func start(in test: XCTestCase, timeout: TimeInterval = 3) async throws -> URL {
        queue.async { [self] in
            guard !started else { return }
            started = true
            listener.start(queue: queue)
        }
        await test.fulfillment(of: [ready], timeout: timeout)
        return try queue.sync {
            guard readinessFailure == nil, readyReported, let port = listener.port,
                  let url = URL(string: "http://127.0.0.1:\(port.rawValue)\(Self.requestTarget)#local-proof") else {
                throw failure(readinessFailure ?? "The loopback server did not report an available port within the readiness timeout.")
            }
            return url
        }
    }

    func waitForRequest(in test: XCTestCase, timeout: TimeInterval = 5) async throws -> String {
        await test.fulfillment(of: [requested], timeout: timeout)
        return try queue.sync {
            guard let receivedTarget else {
                throw failure("Safari did not request the local biography page within the request timeout.")
            }
            return receivedTarget
        }
    }

    func stop() {
        queue.async { [self] in
            listener.cancel()
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    deinit {
        listener.cancel()
        connections.forEach { $0.cancel() }
    }

    private func receiveHeaders(on connection: NWConnection, accumulated: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self, weak connection] data, _, complete, error in
            guard let self, let connection else { return }
            var headers = accumulated
            if let data { headers.append(data) }
            guard headers.count <= 16_384, error == nil else { finish(connection); return }
            let text = String(decoding: headers, as: UTF8.self)
            if text.contains("\r\n\r\n") {
                let fields = text.components(separatedBy: "\r\n").first?.split(separator: " ") ?? []
                let target = fields.count >= 2 && fields[0] == "GET" ? String(fields[1]) : ""
                if target.hasPrefix("/biography/read"), receivedTarget == nil {
                    receivedTarget = target
                    requested.fulfill()
                }
                let matches = target == Self.requestTarget
                let body = matches
                    ? "<!doctype html><html><head><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>Local biography page</title></head><body><p id=\"local-proof\">\(Self.pageMarker)</p></body></html>"
                    : "Not found"
                let response = "HTTP/1.1 \(matches ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nContent-Security-Policy: default-src 'none'; base-uri 'none'; form-action 'none'\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self, weak connection] _ in
                    if let connection { self?.finish(connection) }
                })
            } else if complete {
                finish(connection)
            } else {
                receiveHeaders(on: connection, accumulated: headers)
            }
        }
    }

    private func finish(_ connection: NWConnection) {
        connection.cancel()
        connections.removeAll { $0 === connection }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "ProfileBiographyBrowserServer", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
