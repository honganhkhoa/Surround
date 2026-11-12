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

    /// What a socket reported about OGS's answer to `authenticate`: its
    /// `surround/socketAuthenticationAnswered` events and its log lines.
    private final class AnswerReports {
        var answers = [OGSWebsocketAuthenticationAnswer]()
        var logs = [String]()

        var answerLogs: [String] {
            logs.filter { $0.contains("Authentication answer") }
        }
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

    func testFrameCodecPreservesExactCommandArity() throws {
        XCTAssertEqual(
            try OGSWebsocketFrameCodec.encode(
                command: "automatch/available/subscribe"
            ),
            #"["automatch\/available\/subscribe"]"#
        )
        XCTAssertEqual(
            try OGSWebsocketFrameCodec.encode(
                command: "command/with-data",
                data: "payload"
            ),
            #"["command\/with-data","payload"]"#
        )
        XCTAssertEqual(
            try OGSWebsocketFrameCodec.encode(
                command: "command/with-empty-object",
                data: [String: String]()
            ),
            #"["command\/with-empty-object",{}]"#
        )
        XCTAssertEqual(
            try OGSWebsocketFrameCodec.encode(
                command: "command/with-callback",
                callbackID: 7
            ),
            #"["command\/with-callback",null,7]"#
        )
    }

    func testFrameCodecRedactsPushedJWTScalarAndUserJWTKeys() {
        let scalarSecret = "scalar-jwt-secret"
        let scalar = OGSWebsocketFrameCodec.redactedDescription(
            ofJSON: #"["user/jwt","scalar-jwt-secret"]"#
        )
        XCTAssertFalse(scalar.contains(scalarSecret))
        XCTAssertTrue(scalar.contains("<redacted>"))

        let keyedSecret = "keyed-jwt-secret"
        let keyed = OGSWebsocketFrameCodec.redactedDescription(
            ofJSON: #"["ui/config",{"user_jwt":"keyed-jwt-secret","safe":"visible"}]"#
        )
        XCTAssertFalse(keyed.contains(keyedSecret))
        XCTAssertTrue(keyed.contains("<redacted>"))
        XCTAssertTrue(keyed.contains("visible"))
    }

    func testConnectUsesInjectedOriginAuthenticatesWithoutListingAutomatchesAndNeverLogsJWT() throws {
        let scheduler = Scheduler()
        let factory = TransportFactory()
        let config = try makeConfig(jwt: "jwt-do-not-log", anonymous: false)
        var currentTime = 2_000_000_000.25
        var logs = [String]()
        var events = [String]()
        let socket = OGSWebsocket(
            rootURL: URL(string: "https://beta.online-go.com")!,
            authenticationConfigProvider: { config },
            transportFactory: factory.make,
            scheduler: scheduler,
            anonymousConfigLoader: { _, _ in XCTFail("A logged-in socket must not load anonymous config") },
            currentTime: { currentTime },
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
        XCTAssertEqual(transport.sentMessages.count, 2)
        let initialPing = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(transport.sentMessages[1].utf8)
            ) as? [Any]
        )
        XCTAssertEqual(initialPing[0] as? String, "net/ping")
        let initialPingTimestamp = try XCTUnwrap(
            ((initialPing[1] as? [String: Any])?["client"] as? NSNumber)?
                .doubleValue
        )
        XCTAssertEqual(
            initialPingTimestamp,
            2_000_000_000_250,
            accuracy: 0.001
        )

        currentTime = 2_000_000_010.75
        XCTAssertTrue(scheduler.runNext(after: 10))
        let repeatingPing = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(transport.sentMessages[2].utf8)
            ) as? [Any]
        )
        XCTAssertEqual(repeatingPing[0] as? String, "net/ping")
        let repeatingPingTimestamp = try XCTUnwrap(
            ((repeatingPing[1] as? [String: Any])?["client"] as? NSNumber)?
                .doubleValue
        )
        XCTAssertEqual(
            repeatingPingTimestamp,
            2_000_000_010_750,
            accuracy: 0.001
        )
        XCTAssertFalse(
            transport.sentMessages.contains(#"["automatch\/list",{}]"#)
        )
        XCTAssertFalse(logs.joined(separator: "\n").contains("jwt-do-not-log"))
    }

    func testTransportSendsExactCommandDataAndCallbackFrames() throws {
        let scheduler = Scheduler()
        let factory = TransportFactory()
        let socket = OGSWebsocket(
            rootURL: URL(string: "https://ogs.test")!,
            authenticationConfigProvider: {
                try? self.makeConfig(jwt: "anonymous-jwt", anonymous: true)
            },
            transportFactory: factory.make,
            scheduler: scheduler,
            logger: { _ in }
        )
        socket.connect()
        let transport = try XCTUnwrap(factory.transports.first)
        transport.open()

        socket.emit(command: "command-only")
        XCTAssertEqual(transport.sentMessages.last, #"["command-only"]"#)

        socket.emit(command: "command/with-data", data: "payload")
        XCTAssertEqual(
            transport.sentMessages.last,
            #"["command\/with-data","payload"]"#
        )

        socket.emit(
            command: "command/with-callback",
            data: nil
        ) { _, _ in }
        XCTAssertEqual(
            transport.sentMessages.last,
            #"["command\/with-callback",null,1]"#
        )
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

    func testPushedJWTIncludesTheTransportAuthenticationIdentity() throws {
        let scheduler = Scheduler()
        let factory = TransportFactory()
        let socket = OGSWebsocket(
            rootURL: URL(string: "https://ogs.test")!,
            authenticationConfigProvider: {
                try? self.makeConfig(jwt: "authenticated-jwt", anonymous: false)
            },
            transportFactory: factory.make,
            scheduler: scheduler,
            logger: { _ in }
        )
        var receivedUpdate: OGSWebsocketJWTUpdate?
        socket.serverEventCallback = { name, data in
            if name == "user/jwt" {
                receivedUpdate = data as? OGSWebsocketJWTUpdate
            }
        }

        socket.connect()
        let transport = try XCTUnwrap(factory.transports.first)
        transport.open()
        transport.receive(#"["user/jwt","pushed-jwt"]"#)

        XCTAssertEqual(receivedUpdate?.userJwt, "pushed-jwt")
        XCTAssertEqual(receivedUpdate?.authenticatedUserID, 1)
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
        XCTAssertNil(firstCallbackError?["not_sent"])
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
        XCTAssertNil(closeCallbackError?["not_sent"])
        XCTAssertEqual(scheduler.activeWorkCount, 0)
        XCTAssertGreaterThanOrEqual(secondTransport.disconnectCount, 1)

        socket.connect()
        socket.reconnectIfNeeded()
        socket.closeThenReconnect()
        XCTAssertEqual(factory.transports.count, 2)
        XCTAssertEqual(socket.status, .disconnected)
    }

    /// Retry and a network that came back use connect(): it restarts the
    /// backoff at 1 s, and the capped timer left from the old loop can no
    /// longer start a connection.
    func testConnectResetsTheReconnectBackoff() throws {
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
        var closedEvents = 0
        socket.serverEventCallback = { name, _ in
            if name == "surround/socketClosed" { closedEvents += 1 }
        }

        socket.connect()
        try XCTUnwrap(factory.transports.last).fail()
        for delay: TimeInterval in [1, 2, 4, 8, 16] {
            XCTAssertEqual(scheduler.scheduledDelays, [delay])
            XCTAssertTrue(scheduler.runNext(after: delay))
            try XCTUnwrap(factory.transports.last).fail()
        }
        XCTAssertEqual(scheduler.scheduledDelays, [30], "The backoff reached its cap.")
        XCTAssertEqual(factory.transports.count, 6)
        XCTAssertEqual(closedEvents, 1)

        socket.connect()
        XCTAssertEqual(socket.status, .connecting)
        XCTAssertEqual(factory.transports.count, 7, "A fresh attempt starts at once.")
        XCTAssertTrue(scheduler.runNext(after: 30))
        XCTAssertEqual(factory.transports.count, 7, "The old capped timer starts nothing.")

        try XCTUnwrap(factory.transports.last).fail()
        XCTAssertEqual(socket.status, .reconnecting)
        XCTAssertEqual(scheduler.scheduledDelays, [1], "connect() restarted the backoff.")
        XCTAssertEqual(closedEvents, 2, "A failed Retry reports the outage again.")
        socket.close()
    }

    func testEmitMarksOnlyPreSendFailuresAsDefinitelyNotSent() throws {
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

        var noTransportError: [String: String]?
        socket.emit(command: "chat/pm", data: [:]) { _, error in noTransportError = error }
        XCTAssertNotNil(noTransportError?["not_sent"])

        socket.connect()
        let transport = try XCTUnwrap(factory.transports.first)
        transport.open()
        transport.sendError = TestError.connectionLost
        var attemptedSendError: [String: String]?
        socket.emit(command: "chat/pm", data: [:]) { _, error in attemptedSendError = error }
        XCTAssertNotNil(attemptedSendError?["connection"])
        XCTAssertNil(attemptedSendError?["not_sent"])

        socket.close()
        var closedSocketError: [String: String]?
        socket.emit(command: "chat/pm", data: [:]) { _, error in closedSocketError = error }
        XCTAssertNotNil(closedSocketError?["not_sent"])
    }

    func testNaturalReconnectAuthenticatesWithFreshestProviderToken() throws {
        let scheduler = Scheduler()
        let factory = TransportFactory()
        var config = try makeConfig(jwt: "old-test-jwt", anonymous: false)
        let socket = OGSWebsocket(
            rootURL: URL(string: "https://ogs.test")!,
            authenticationConfigProvider: { config },
            transportFactory: factory.make,
            scheduler: scheduler,
            logger: { _ in }
        )

        socket.connect()
        let firstTransport = try XCTUnwrap(factory.transports.first)
        firstTransport.open()
        XCTAssertTrue(firstTransport.sentMessages.contains { $0.contains("old-test-jwt") })

        config = try makeConfig(jwt: "fresh-test-jwt", anonymous: false)
        firstTransport.fail()
        XCTAssertTrue(scheduler.runNext(after: 1))
        let secondTransport = try XCTUnwrap(factory.transports.last)
        secondTransport.open()

        let authentication = try XCTUnwrap(secondTransport.sentMessages.first)
        let frame = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(authentication.utf8)) as? [Any]
        )
        XCTAssertEqual(frame[0] as? String, "authenticate")
        XCTAssertEqual(
            (frame[1] as? [String: String])?["jwt"],
            "fresh-test-jwt"
        )
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
        XCTAssertFalse(
            transport.sentMessages.contains(#"["automatch\/list",{}]"#)
        )
    }

    // MARK: - OGS's answer to authenticate

    func testAnAnswerNamingTheAccountConfirmsIt() throws {
        // OGS sends the id as a JSON number; its digits in a string count too.
        for answer in [#"{"id":1,"username":"player"}"#, #"{"id":"1","username":"player"}"#] {
            let scheduler = Scheduler()
            let factory = TransportFactory()
            let reports = AnswerReports()
            let config = try makeConfig(jwt: "player-jwt", anonymous: false)
            let socket = makeSocket(scheduler: scheduler, factory: factory, reports: reports) { config }
            socket.connect()
            let transport = try XCTUnwrap(factory.transports.last)
            transport.open()

            let frame = try authenticateFrame(on: transport)
            XCTAssertEqual(frame.count, 3, "A signed-in connection asks for OGS's answer.")
            XCTAssertEqual((frame[1] as? [String: String])?["jwt"], "player-jwt")
            let authenticateID = try XCTUnwrap(frame[2] as? Int)
            XCTAssertEqual(reports.answers, [], "Nothing is reported before OGS answers.")

            transport.receive("[\(authenticateID),\(answer)]")
            XCTAssertEqual(
                reports.answers,
                [OGSWebsocketAuthenticationAnswer(userID: 1, outcome: .confirmed)],
                answer
            )
            XCTAssertEqual(reports.answerLogs, ["[websocket] Authentication answer: confirmed"], answer)
            XCTAssertEqual(scheduler.scheduledDelays, [10], "The answer cancelled its timeout; the ping remains.")
            socket.close()
        }
    }

    func testOtherAnswersReject() throws {
        let answers = [
            "null", // undefined: OGS names no account
            #"{"username":"player"}"#, // no id
            #"{"id":2,"username":"other"}"#, // another account
            #"{"id":true,"username":"player"}"#, // a Boolean is not an id
            #"{"id":1.5,"username":"player"}"#, // nor is a fraction
            #"null,{"code":"invalid_jwt","message":"Invalid JWT"}"#, // OGS's error answer
        ]
        for answer in answers {
            let scheduler = Scheduler()
            let factory = TransportFactory()
            let reports = AnswerReports()
            let config = try makeConfig(jwt: "player-jwt", anonymous: false)
            let socket = makeSocket(scheduler: scheduler, factory: factory, reports: reports) { config }
            socket.connect()
            let transport = try XCTUnwrap(factory.transports.last)
            transport.open()
            let authenticateID = try XCTUnwrap(authenticateFrame(on: transport).last as? Int)

            transport.receive("[\(authenticateID),\(answer)]")
            XCTAssertEqual(
                reports.answers,
                [OGSWebsocketAuthenticationAnswer(userID: 1, outcome: .rejected)],
                answer
            )
            XCTAssertEqual(reports.answerLogs, ["[websocket] Authentication answer: rejected"], answer)
            socket.close()
        }
    }

    func testNoAnswerWithinTheTimeoutIsUnanswered() throws {
        let config = try makeConfig(jwt: "player-jwt", anonymous: false)
        let scheduler = Scheduler()
        let factory = TransportFactory()
        let reports = AnswerReports()
        let socket = makeSocket(
            scheduler: scheduler, factory: factory, reports: reports, callbackTimeout: 5
        ) { config }
        socket.connect()
        let transport = try XCTUnwrap(factory.transports.last)
        transport.open()
        let authenticateID = try XCTUnwrap(authenticateFrame(on: transport).last as? Int)
        XCTAssertEqual(reports.answers, [])

        XCTAssertTrue(scheduler.runNext(after: 5))
        XCTAssertEqual(reports.answers, [OGSWebsocketAuthenticationAnswer(userID: 1, outcome: .unanswered)])
        XCTAssertEqual(reports.answerLogs, ["[websocket] Authentication answer: unanswered"])
        transport.receive("[\(authenticateID),{\"id\":1,\"username\":\"player\"}]")
        XCTAssertEqual(reports.answers.count, 1, "A late answer adds nothing.")
        socket.close()

        // A connection error reports nothing: the connection's socketClosed
        // ends its wait. Here the transport fails before OGS answers…
        let droppedScheduler = Scheduler()
        let droppedFactory = TransportFactory()
        let droppedReports = AnswerReports()
        let dropped = makeSocket(
            scheduler: droppedScheduler, factory: droppedFactory, reports: droppedReports, callbackTimeout: 5
        ) { config }
        dropped.connect()
        let droppedTransport = try XCTUnwrap(droppedFactory.transports.last)
        droppedTransport.open()
        droppedTransport.fail()
        XCTAssertFalse(droppedScheduler.runNext(after: 5), "The failure completed the callback.")

        // …and here the authenticate frame itself can't be sent, while the
        // identity is still the one sent.
        let unsentScheduler = Scheduler()
        let unsentFactory = TransportFactory()
        let unsentReports = AnswerReports()
        let unsent = makeSocket(
            scheduler: unsentScheduler, factory: unsentFactory, reports: unsentReports, callbackTimeout: 5
        ) { config }
        unsent.connect()
        let unsentTransport = try XCTUnwrap(unsentFactory.transports.last)
        unsentTransport.sendError = TestError.connectionLost
        unsentTransport.open()
        XCTAssertEqual(try authenticateFrame(on: unsentTransport).count, 3)
        XCTAssertFalse(unsentScheduler.runNext(after: 5), "The failed send completed the callback.")

        for (name, failed) in [("dropped", droppedReports), ("unsent", unsentReports)] {
            XCTAssertEqual(failed.answers, [], name)
            XCTAssertEqual(failed.answerLogs, [], name)
        }
        dropped.close()
        unsent.close()

        // A timeout that outlives its identity reports nothing either.
        // connect() on an open socket replaces the transport but leaves its
        // callbacks waiting, so account 1's authenticate times out after
        // account 2's is confirmed. Only the identity guard drops it.
        var switchedConfig = config
        let switchedScheduler = Scheduler()
        let switchedFactory = TransportFactory()
        let switchedReports = AnswerReports()
        let switched = makeSocket(
            scheduler: switchedScheduler, factory: switchedFactory, reports: switchedReports, callbackTimeout: 5
        ) { switchedConfig }
        switched.connect()
        try XCTUnwrap(switchedFactory.transports.last).open()
        switchedConfig = try makeConfig(jwt: "second-jwt", userID: 2, anonymous: false)
        switched.connect()
        let secondTransport = try XCTUnwrap(switchedFactory.transports.last)
        secondTransport.open()
        let secondID = try XCTUnwrap(authenticateFrame(on: secondTransport).last as? Int)
        secondTransport.receive("[\(secondID),{\"id\":2,\"username\":\"player\"}]")
        XCTAssertTrue(switchedScheduler.runNext(after: 5), "Account 1's authenticate times out.")
        XCTAssertEqual(switchedReports.answers, [OGSWebsocketAuthenticationAnswer(userID: 2, outcome: .confirmed)])
        XCTAssertEqual(switchedReports.answerLogs, ["[websocket] Authentication answer: confirmed"])
        switched.close()
    }

    func testAnAnswerAfterReconnectingConfirmsNothing() throws {
        let scheduler = Scheduler()
        let factory = TransportFactory()
        let reports = AnswerReports()
        let config = try makeConfig(jwt: "player-jwt", anonymous: false)
        let socket = makeSocket(scheduler: scheduler, factory: factory, reports: reports) { config }
        socket.connect()
        let first = try XCTUnwrap(factory.transports.last)
        first.open()
        let firstID = try XCTUnwrap(authenticateFrame(on: first).last as? Int)

        first.fail()
        XCTAssertTrue(scheduler.runNext(after: 1))
        let second = try XCTUnwrap(factory.transports.last)
        XCTAssertFalse(second === first)
        second.open()
        let secondID = try XCTUnwrap(authenticateFrame(on: second).last as? Int)
        XCTAssertNotEqual(secondID, firstID)

        // The first authenticate's answer, late on its own transport or on the new one.
        let identity = #"{"id":1,"username":"player"}"#
        first.receive("[\(firstID),\(identity)]")
        second.receive("[\(firstID),\(identity)]")
        XCTAssertEqual(reports.answers, [], "Only the open transport's own authenticate is answered.")
        XCTAssertEqual(reports.answerLogs, [])

        second.receive("[\(secondID),\(identity)]")
        XCTAssertEqual(reports.answers, [OGSWebsocketAuthenticationAnswer(userID: 1, outcome: .confirmed)])
        socket.close()
    }

    func testAnonymousSocketsAskForNoAnswer() throws {
        // A guest, a guest with an id, and an identity without one.
        let identities: [(userID: Int, anonymous: Bool)] = [(0, true), (7, true), (0, false)]
        for identity in identities {
            let scheduler = Scheduler()
            let factory = TransportFactory()
            let reports = AnswerReports()
            let config = try makeConfig(jwt: "guest-jwt", userID: identity.userID, anonymous: identity.anonymous)
            let socket = makeSocket(scheduler: scheduler, factory: factory, reports: reports) { config }
            socket.connect()
            let transport = try XCTUnwrap(factory.transports.last)
            transport.open()

            XCTAssertEqual(try authenticateFrame(on: transport).count, 2, "\(identity): today's frame")
            XCTAssertEqual(scheduler.scheduledDelays, [10], "\(identity): only the ping is scheduled")
            socket.emit(command: "command/with-callback", data: nil) { _, _ in }
            XCTAssertEqual(
                transport.sentMessages.last,
                #"["command\/with-callback",null,1]"#,
                "\(identity): the next callback gets id 1"
            )
            socket.close()
            XCTAssertEqual(reports.answers, [], "\(identity)")
            XCTAssertEqual(reports.answerLogs, [], "\(identity)")
        }
    }

    func testAuthenticatedUserIDFollowsTheTransport() throws {
        let scheduler = Scheduler()
        let factory = TransportFactory()
        let reports = AnswerReports()
        var config = try makeConfig(jwt: "first-jwt", userID: 1, anonymous: false)
        let socket: OGSWebsocketProtocol = makeSocket(
            scheduler: scheduler, factory: factory, reports: reports
        ) { config }
        XCTAssertNil(socket.authenticatedUserID)

        socket.connect()
        XCTAssertNil(socket.authenticatedUserID, "Nothing is sent before the transport opens.")
        let first = try XCTUnwrap(factory.transports.last)
        first.open()
        XCTAssertEqual(socket.authenticatedUserID, 1, "Set at the send, before OGS answers.")
        XCTAssertEqual(reports.answers, [])

        config = try makeConfig(jwt: "second-jwt", userID: 2, anonymous: false)
        first.fail()
        XCTAssertNil(socket.authenticatedUserID, "A reconnect clears it.")
        XCTAssertTrue(scheduler.runNext(after: 1))
        XCTAssertNil(socket.authenticatedUserID, "The new transport hasn't opened.")
        let second = try XCTUnwrap(factory.transports.last)
        second.open()
        XCTAssertEqual(socket.authenticatedUserID, 2, "The next connection's identity.")

        socket.close()
        XCTAssertNil(socket.authenticatedUserID, "A close clears it.")
        XCTAssertEqual(reports.answers, [])

        let offline: OGSWebsocketProtocol = OGSOfflineNoOpWebsocket()
        XCTAssertNil(offline.authenticatedUserID, "A fake that doesn't model identity has none.")
    }

    private func makeConfig(jwt: String, anonymous: Bool) throws -> OGSUIConfig {
        try makeConfig(jwt: jwt, userID: anonymous ? 0 : 1, anonymous: anonymous)
    }

    private func makeConfig(jwt: String, userID: Int, anonymous: Bool) throws -> OGSUIConfig {
        let object: [String: Any] = [
            "csrf_token": "csrf",
            "user_jwt": jwt,
            "user": ["username": anonymous ? "guest" : "player", "id": userID, "anonymous": anonymous]
        ]
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSUIConfig.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func callbackID(in message: String) throws -> Int {
        let frame = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(message.utf8)) as? [Any])
        return try XCTUnwrap(frame.last as? Int)
    }

    /// A socket on this file's fake transports and scheduler, recording its
    /// answer events and log lines in `reports`. It reads `config` at each
    /// authentication.
    private func makeSocket(
        scheduler: Scheduler,
        factory: TransportFactory,
        reports: AnswerReports,
        callbackTimeout: TimeInterval = OGSWebsocket.defaultCallbackTimeout,
        config: @escaping () -> OGSUIConfig?
    ) -> OGSWebsocket {
        let socket = OGSWebsocket(
            rootURL: URL(string: "https://ogs.test")!,
            authenticationConfigProvider: config,
            transportFactory: factory.make,
            scheduler: scheduler,
            anonymousConfigLoader: { _, _ in XCTFail("Every identity here comes from the provider.") },
            callbackTimeout: callbackTimeout,
            logger: { reports.logs.append($0) }
        )
        socket.serverEventCallback = { name, data in
            guard name == "surround/socketAuthenticationAnswered" else { return }
            if let answer = data as? OGSWebsocketAuthenticationAnswer {
                reports.answers.append(answer)
            } else {
                XCTFail("Unexpected answer payload: \(String(describing: data))")
            }
        }
        return socket
    }

    /// The first frame a transport sent: its connection's `authenticate`.
    private func authenticateFrame(on transport: Transport) throws -> [Any] {
        let message = try XCTUnwrap(transport.sentMessages.first)
        let frame = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(message.utf8)) as? [Any])
        XCTAssertEqual(frame.first as? String, "authenticate")
        return frame
    }
}
