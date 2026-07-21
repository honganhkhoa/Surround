//
//  OGSWebsocketTests.swift
//  SurroundTests
//

import Combine
import XCTest

final class OGSWebsocketTests: XCTestCase {
    private final class Cancellation: Cancellable {
        private var handler: (() -> Void)?

        init(_ handler: @escaping () -> Void) {
            self.handler = handler
        }

        func cancel() {
            handler?()
            handler = nil
        }
    }

    private final class Scheduler: OGSWebsocketScheduling {
        private struct Work {
            let delay: TimeInterval
            let repeats: Bool
            let block: () -> Void
        }

        private var nextID = 0
        private var workByID = [Int: Work]()

        var activeWorkCount: Int { workByID.count }
        var scheduledDelays: [TimeInterval] { workByID.values.map(\.delay) }

        func async(_ block: @escaping () -> Void) {
            block()
        }

        func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
            register(delay: delay, repeats: false, block: block)
        }

        func scheduleRepeating(every interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
            register(delay: interval, repeats: true, block: block)
        }

        @discardableResult
        func runNext(after delay: TimeInterval) -> Bool {
            guard let entry = workByID.first(where: { $0.value.delay == delay }) else { return false }
            if !entry.value.repeats {
                workByID.removeValue(forKey: entry.key)
            }
            entry.value.block()
            return true
        }

        private func register(delay: TimeInterval, repeats: Bool, block: @escaping () -> Void) -> Cancellable {
            nextID += 1
            let id = nextID
            workByID[id] = Work(delay: delay, repeats: repeats, block: block)
            return Cancellation { [weak self] in
                self?.workByID.removeValue(forKey: id)
            }
        }
    }

    private final class Transport: OGSWebsocketTransport {
        weak var delegate: OGSWebsocketTransportDelegate?
        private(set) var connectedURL: URL?
        private(set) var sentMessages = [String]()
        private(set) var disconnectCount = 0
        var sendError: Error?

        func connect(to url: URL) {
            connectedURL = url
        }

        func send(_ message: String, completion: @escaping (Error?) -> Void) {
            sentMessages.append(message)
            completion(sendError)
        }

        func disconnect() {
            disconnectCount += 1
        }

        func open() {
            delegate?.websocketTransportDidOpen(self)
        }

        func receive(_ message: String) {
            delegate?.websocketTransport(self, didReceive: message)
        }

        func fail(_ error: Error = TestError.connectionLost) {
            delegate?.websocketTransport(self, didFailWith: error)
        }
    }

    private final class TransportFactory {
        private(set) var transports = [Transport]()

        func make() -> OGSWebsocketTransport {
            let transport = Transport()
            transports.append(transport)
            return transport
        }
    }

    private enum TestError: LocalizedError {
        case connectionLost

        var errorDescription: String? { "Connection lost" }
    }

    func testFrameCodecRoundTripsCallbacksAndRedactsCredentials() throws {
        let encoded = try OGSWebsocketFrameCodec.encode(
            command: "authenticate",
            data: [
                "jwt": "jwt-secret",
                "nested": ["csrf_token": "csrf-secret", "safe": "visible"]
            ],
            callbackID: 7
        )
        let components = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [Any])
        XCTAssertEqual(components[0] as? String, "authenticate")
        XCTAssertEqual(components[2] as? Int, 7)

        let redacted = OGSWebsocketFrameCodec.redactedDescription(ofJSON: encoded)
        XCTAssertFalse(redacted.contains("jwt-secret"))
        XCTAssertFalse(redacted.contains("csrf-secret"))
        XCTAssertTrue(redacted.contains("<redacted>"))
        XCTAssertTrue(redacted.contains("visible"))

        switch try OGSWebsocketFrameCodec.decode(#"[7,{"accepted":true},{"code":"warning"}]"#) {
        case .callback(let id, let data, let error):
            XCTAssertEqual(id, 7)
            XCTAssertEqual((data as? [String: Bool])?["accepted"], true)
            XCTAssertEqual(error?["code"], "warning")
        default:
            XCTFail("Expected a callback frame")
        }

        switch try OGSWebsocketFrameCodec.decode(#"["game/42/phase","stone removal"]"#) {
        case .event(let name, let data):
            XCTAssertEqual(name, "game/42/phase")
            XCTAssertEqual(data as? String, "stone removal")
        default:
            XCTFail("Expected an event frame")
        }

        XCTAssertThrowsError(try OGSWebsocketFrameCodec.decode("not-json"))
        XCTAssertThrowsError(try OGSWebsocketFrameCodec.decode("[]"))
    }

    func testConnectUsesInjectedOriginAuthenticatesAndNeverLogsJWT() throws {
        let scheduler = Scheduler()
        let factory = TransportFactory()
        let config = try makeConfig(jwt: "jwt-do-not-log", anonymous: false)
        var logs = [String]()
        var events = [String]()
        let socket = OGSWebsocket(
            rootURL: URL(string: "https://beta.online-go.com")!,
            authenticationConfigProvider: { config },
            transportFactory: factory.make,
            scheduler: scheduler,
            anonymousConfigLoader: { _, _ in XCTFail("A logged-in socket must not load anonymous config") },
            logger: { logs.append($0) }
        )
        socket.serverEventCallback = { name, _ in events.append(name) }

        socket.connect()
        let transport = try XCTUnwrap(factory.transports.first)
        XCTAssertEqual(transport.connectedURL?.absoluteString, "wss://beta.online-go.com")

        transport.open()

        XCTAssertEqual(socket.status, .connected)
        XCTAssertTrue(socket.opened)
        XCTAssertTrue(socket.authenticated)
        XCTAssertTrue(events.contains("surround/socketAuthenticated"))
        XCTAssertTrue(events.contains("surround/socketOpened"))

        let authentication = try XCTUnwrap(transport.sentMessages.first)
        let frame = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(authentication.utf8)) as? [Any])
        XCTAssertEqual(frame[0] as? String, "authenticate")
        XCTAssertEqual((frame[1] as? [String: String])?["jwt"], "jwt-do-not-log")
        XCTAssertTrue(transport.sentMessages.contains { message in
            let frame = try? JSONSerialization.jsonObject(with: Data(message.utf8)) as? [Any]
            return frame?.first as? String == "automatch/list"
        })
        XCTAssertFalse(logs.joined(separator: "\n").contains("jwt-do-not-log"))
    }

    func testCallbacksEventsAndTimeoutsAreDispatchedExactlyOnce() throws {
        let scheduler = Scheduler()
        let factory = TransportFactory()
        let socket = OGSWebsocket(
            rootURL: URL(string: "https://ogs.test")!,
            authenticationConfigProvider: { try? self.makeConfig(jwt: "jwt", anonymous: true) },
            transportFactory: factory.make,
            scheduler: scheduler,
            callbackTimeout: 5,
            logger: { _ in }
        )
        socket.connect()
        let transport = try XCTUnwrap(factory.transports.first)
        transport.open()

        var callbackCount = 0
        var callbackValue: String?
        socket.emit(command: "game/move", data: ["game_id": 42, "move": "aa"]) { data, error in
            callbackCount += 1
            callbackValue = (data as? [String: String])?["result"]
            XCTAssertNil(error)
        }
        let completedCallbackID = try callbackID(in: XCTUnwrap(transport.sentMessages.last))
        transport.receive("[\(completedCallbackID),{\"result\":\"ok\"},null]")
        transport.receive("[\(completedCallbackID),{\"result\":\"late\"},null]")
        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(callbackValue, "ok")

        var receivedEvent: (String, Int)?
        socket.serverEventCallback = { name, data in
            if name == "active_game" {
                receivedEvent = (name, (data as? [String: Int])?["id"] ?? -1)
            }
        }
        transport.receive(#"["active_game",{"id":99}]"#)
        XCTAssertEqual(receivedEvent?.0, "active_game")
        XCTAssertEqual(receivedEvent?.1, 99)

        var timeoutCount = 0
        var timeoutError: [String: String]?
        socket.emit(command: "slow/request", data: [:]) { _, error in
            timeoutCount += 1
            timeoutError = error
        }
        let timeoutID = try callbackID(in: XCTUnwrap(transport.sentMessages.last))
        XCTAssertTrue(scheduler.runNext(after: 5))
        XCTAssertEqual(timeoutCount, 1)
        XCTAssertNotNil(timeoutError?["timeout"])
        transport.receive("[\(timeoutID),{\"too\":\"late\"},null]")
        XCTAssertEqual(timeoutCount, 1)
    }

    func testFailureReconnectsAndCloseCancelsAllWorkWithoutRestarting() throws {
        let scheduler = Scheduler()
        let factory = TransportFactory()
        let socket = OGSWebsocket(
            rootURL: URL(string: "https://ogs.test")!,
            authenticationConfigProvider: { try? self.makeConfig(jwt: "jwt", anonymous: true) },
            transportFactory: factory.make,
            scheduler: scheduler,
            connectTimeout: 15,
            maxReconnectDelay: 30,
            callbackTimeout: 5,
            logger: { _ in }
        )
        socket.connect()
        let firstTransport = try XCTUnwrap(factory.transports.first)
        firstTransport.open()

        var firstCallbackError: [String: String]?
        socket.emit(command: "pending", data: [:]) { _, error in firstCallbackError = error }
        firstTransport.fail()

        XCTAssertEqual(socket.status, .reconnecting)
        XCTAssertFalse(socket.opened)
        XCTAssertNotNil(firstCallbackError?["connection"])
        XCTAssertTrue(scheduler.scheduledDelays.contains(1))
        XCTAssertTrue(scheduler.runNext(after: 1))
        XCTAssertEqual(factory.transports.count, 2)

        let secondTransport = factory.transports[1]
        secondTransport.open()
        XCTAssertEqual(socket.status, .connected)

        var closeCallbackError: [String: String]?
        socket.emit(command: "pending-at-close", data: [:]) { _, error in closeCallbackError = error }
        socket.close()

        XCTAssertEqual(socket.status, .disconnected)
        XCTAssertFalse(socket.opened)
        XCTAssertFalse(socket.authenticated)
        XCTAssertNotNil(closeCallbackError?["connection"])
        XCTAssertEqual(scheduler.activeWorkCount, 0)
        XCTAssertGreaterThanOrEqual(secondTransport.disconnectCount, 1)

        socket.connect()
        socket.reconnectIfNeeded()
        socket.closeThenReconnect()
        XCTAssertEqual(factory.transports.count, 2)
        XCTAssertEqual(socket.status, .disconnected)
    }

    func testAnonymousConfigLoaderReceivesTheInjectedRoot() throws {
        let scheduler = Scheduler()
        let factory = TransportFactory()
        let anonymousConfig = try makeConfig(jwt: "anonymous-jwt", anonymous: true)
        var requestedRoot: URL?
        let socket = OGSWebsocket(
            rootURL: URL(string: "https://beta.online-go.com")!,
            authenticationConfigProvider: { nil },
            transportFactory: factory.make,
            scheduler: scheduler,
            anonymousConfigLoader: { root, completion in
                requestedRoot = root
                completion(.success(anonymousConfig))
            },
            logger: { _ in }
        )

        socket.connect()
        let transport = try XCTUnwrap(factory.transports.first)
        transport.open()

        XCTAssertEqual(requestedRoot?.absoluteString, "https://beta.online-go.com")
        XCTAssertTrue(socket.authenticated)
        XCTAssertTrue(transport.sentMessages.contains { $0.contains("anonymous-jwt") })
    }

    private func makeConfig(jwt: String, anonymous: Bool) throws -> OGSUIConfig {
        let object: [String: Any] = [
            "csrf_token": "csrf",
            "user_jwt": jwt,
            "user": ["username": anonymous ? "guest" : "player", "id": anonymous ? 0 : 1, "anonymous": anonymous]
        ]
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSUIConfig.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func callbackID(in message: String) throws -> Int {
        let frame = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(message.utf8)) as? [Any])
        return try XCTUnwrap(frame.last as? Int)
    }
}
