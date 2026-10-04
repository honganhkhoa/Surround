import Combine
import SwiftUI
import XCTest

final class PrivateMessageSendSessionTests: XCTestCase {
    private final class DeferredWebsocket: OGSWebsocketProtocol {
        var serverEventCallback: ((String, Any?) -> Void)?
        var onConnectTasks = [() -> Void]()
        var onStatusChanged: (() -> Void)?
        var authenticationConfigProvider: () -> OGSUIConfig? = { nil }
        let authenticated = true
        let opened = true
        let status = OGSWebsocketStatus.connected
        let callbackTimeout: TimeInterval
        var drift = 0.0
        var latency = 0.0
        private(set) var privateMessagePayloads = [[String: Any]]()
        private var callbackByAttempt = [Int: OGSWebsocketResultCallback]()

        init(callbackTimeout: TimeInterval = OGSWebsocket.defaultCallbackTimeout) {
            self.callbackTimeout = callbackTimeout
        }

        func connect() {}
        func close() {}
        func reconnectIfNeeded() {}
        func closeThenReconnect() {}

        func emit(command: String, data: Any?, resultCallback: OGSWebsocketResultCallback?) {
            guard command == "chat/pm", let payload = data as? [String: Any] else {
                resultCallback?(nil, nil)
                return
            }
            let attempt = privateMessagePayloads.count
            privateMessagePayloads.append(payload)
            callbackByAttempt[attempt] = resultCallback
        }

        func acknowledge(at attempt: Int, from accountID: Int = 101) {
            guard privateMessagePayloads.indices.contains(attempt) else {
                XCTFail("No private message was emitted for attempt \(attempt)")
                return
            }
            let payload = privateMessagePayloads[attempt]
            guard let uid = payload["uid"] as? String, let message = payload["message"] as? String else {
                XCTFail("The emitted private message is missing its ID or body")
                return
            }
            let messageData: [String: Any] = ["i": uid, "m": message, "t": Double(100 + attempt)]
            complete(at: attempt, data: [
                "from": ["id": accountID, "username": "Sender-\(accountID)"],
                "to": ["id": 202, "username": "Peer"],
                "message": messageData,
            ], error: nil)
        }

        func timeOut(at attempt: Int) {
            complete(at: attempt, data: nil, error: ["timeout": "No acknowledgement"])
        }

        func failPendingMessages() {
            for attempt in Array(callbackByAttempt.keys) {
                complete(at: attempt, data: nil, error: ["connection": "Test finished"])
            }
        }

        private func complete(at attempt: Int, data: Any?, error: [String: String]?) {
            // Match the socket's one-shot callback ownership, including expired IDs.
            callbackByAttempt.removeValue(forKey: attempt)?(data, error)
        }
    }

    private final class Draft {
        var message: String

        init(_ message: String) {
            self.message = message
        }

        var binding: Binding<String> {
            Binding(get: { self.message }, set: { self.message = $0 })
        }
    }

    private var acknowledgement: OGSPrivateMessage {
        OGSPrivateMessage(
            from: OGSUser(username: "Sender", id: 101),
            to: OGSUser(username: "Peer", id: 202),
            content: OGSPrivateMessageContent(id: "ack.1", message: "First message", timestamp: 100)
        )
    }

    func testAcknowledgementClearsSubmittedDraftAndBlocksDuplicateWhileSending() {
        let session = PrivateMessageSendSession()
        let draft = Draft("First message")
        let response = PassthroughSubject<OGSPrivateMessage, Error>()
        var submitted = [String]()
        let send: (String) -> AnyPublisher<OGSPrivateMessage, Error> = { message in
            submitted.append(message)
            return response.eraseToAnyPublisher()
        }

        session.send(draft: draft.binding, using: send)
        session.send(draft: draft.binding, using: send)
        XCTAssertEqual(submitted, ["First message"])
        XCTAssertEqual(draft.message, "First message")
        XCTAssertTrue(session.isSending)

        let finished = expectSendToFinish(session)
        response.send(acknowledgement)
        response.send(completion: .finished)
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(draft.message, "")
        XCTAssertFalse(session.isSending)
        XCTAssertNil(session.failure)
    }

    func testAcknowledgementDoesNotEraseNewerDraft() {
        let session = PrivateMessageSendSession()
        let draft = Draft("First message")
        let response = PassthroughSubject<OGSPrivateMessage, Error>()
        session.send(draft: draft.binding) { _ in response.eraseToAnyPublisher() }
        draft.message = "A newer thought"

        let finished = expectSendToFinish(session)
        response.send(acknowledgement)
        response.send(completion: .finished)
        wait(for: [finished], timeout: 1)

        XCTAssertEqual(draft.message, "A newer thought")
        XCTAssertFalse(session.isSending)
        XCTAssertNil(session.failure)
    }

    func testRejectedSendRetainsDraftAndAllowsRetry() {
        let session = PrivateMessageSendSession()
        let draft = Draft("First message")
        let rejected = expectSendToFinish(session)
        session.send(draft: draft.binding) { _ in
            Fail<OGSPrivateMessage, Error>(error: OGSPrivateMessageSendError.notSent)
                .eraseToAnyPublisher()
        }
        wait(for: [rejected], timeout: 1)

        XCTAssertEqual(draft.message, "First message")
        XCTAssertFalse(session.isSending)
        XCTAssertEqual(session.failure, .notSent)

        let retry = PassthroughSubject<OGSPrivateMessage, Error>()
        let retried = expectSendToFinish(session)
        session.send(draft: draft.binding) { _ in retry.eraseToAnyPublisher() }
        XCTAssertTrue(session.isSending)
        XCTAssertNil(session.failure)
        retry.send(acknowledgement)
        retry.send(completion: .finished)
        wait(for: [retried], timeout: 1)
        XCTAssertEqual(draft.message, "")
    }

    func testCompletionWithoutAcknowledgementRetainsDraftAsUnconfirmed() {
        let session = PrivateMessageSendSession()
        let draft = Draft("First message")
        let finished = expectSendToFinish(session)
        session.send(draft: draft.binding) { _ in
            Empty<OGSPrivateMessage, Error>().eraseToAnyPublisher()
        }
        wait(for: [finished], timeout: 1)

        XCTAssertEqual(draft.message, "First message")
        XCTAssertEqual(session.failure, .deliveryUnconfirmed)
        XCTAssertFalse(session.isSending)
    }

    func testTimeoutRetainsDraftAsUnconfirmed() {
        let session = PrivateMessageSendSession(acknowledgementTimeout: 0.01)
        let draft = Draft("First message")
        let finished = expectation(description: "Missing acknowledgement times out")
        session.onFinished = { finished.fulfill() }
        session.send(draft: draft.binding) { _ in
            Empty<OGSPrivateMessage, Error>(completeImmediately: false).eraseToAnyPublisher()
        }
        wait(for: [finished], timeout: 1)

        XCTAssertEqual(draft.message, "First message")
        XCTAssertEqual(session.failure, .deliveryUnconfirmed)
        XCTAssertFalse(session.isSending)
    }

    func testDefaultServiceSendAcceptsAcknowledgementBetweenTwentyAndThirtySeconds() throws {
        let socket = DeferredWebsocket()
        let service = try makeService(socket: socket)
        let peer = OGSUser(username: "Peer", id: 202)
        let session = PrivateMessageSendSessions.session(for: service, peerID: peer.id)
        let draft = Draft("First message")
        let finished = expectSendToFinish(session)
        let lateAcknowledgement = expectation(description: "Acknowledge inside the socket's default deadline")
        session.send(to: peer, draft: draft.binding, using: service)

        // Exercise the production defaults; a shortened override would miss the
        // original 20-second composer / 30-second socket mismatch.
        let delayedAck = DispatchWorkItem {
            XCTAssertTrue(session.isSending)
            XCTAssertNil(session.failure)
            XCTAssertEqual(draft.message, "First message")
            session.send(to: peer, draft: draft.binding, using: service)
            XCTAssertEqual(socket.privateMessagePayloads.count, 1)
            socket.acknowledge(at: 0)
            lateAcknowledgement.fulfill()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: delayedAck)
        defer { delayedAck.cancel() }
        wait(for: [lateAcknowledgement, finished], timeout: 30)

        XCTAssertEqual(draft.message, "")
        XCTAssertFalse(session.isSending)
        XCTAssertNil(session.failure)
        XCTAssertEqual(service.privateMessagesByPeerId[peer.id]?.map(\.content.message), ["First message"])
    }

    func testServiceDeadlineOverridesShorterConfiguredSessionFallback() throws {
        let socket = DeferredWebsocket(callbackTimeout: 0.2)
        let service = try makeService(socket: socket)
        let peer = OGSUser(username: "Peer", id: 202)
        let session = PrivateMessageSendSession(acknowledgementTimeout: 0.01)
        let draft = Draft("First message")
        let finished = expectSendToFinish(session)
        let lateAcknowledgement = expectation(description: "Acknowledge after the shorter session fallback")
        XCTAssertEqual(service.privateMessageAcknowledgementTimeout, 0.2)
        session.send(to: peer, draft: draft.binding, using: service)

        let delayedAck = DispatchWorkItem {
            XCTAssertTrue(session.isSending)
            XCTAssertNil(session.failure)
            socket.acknowledge(at: 0)
            lateAcknowledgement.fulfill()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: delayedAck)
        defer { delayedAck.cancel() }
        wait(for: [lateAcknowledgement, finished], timeout: 1)

        XCTAssertEqual(draft.message, "")
        XCTAssertNil(session.failure)
        XCTAssertEqual(service.privateMessagesByPeerId[peer.id]?.count, 1)
    }

    func testServiceAcknowledgementPreservesDraftEditedWhileSending() throws {
        let socket = DeferredWebsocket()
        let service = try makeService(socket: socket)
        let peer = OGSUser(username: "Peer", id: 202)
        let session = PrivateMessageSendSession()
        let draft = Draft("First message")
        let finished = expectSendToFinish(session)
        session.send(to: peer, draft: draft.binding, using: service)
        draft.message = "A newer thought"
        socket.acknowledge(at: 0)
        wait(for: [finished], timeout: 1)

        XCTAssertEqual(draft.message, "A newer thought")
        XCTAssertFalse(session.isSending)
        XCTAssertNil(session.failure)
        XCTAssertEqual(service.privateMessagesByPeerId[peer.id]?.map(\.content.message), ["First message"])
    }

    func testFallbackTimeoutAndRetryIgnoreEarlierAcknowledgement() throws {
        let socket = DeferredWebsocket()
        let service = try makeService(socket: socket)
        let peer = OGSUser(username: "Peer", id: 202)
        let session = PrivateMessageSendSession(acknowledgementTimeout: 0.01)
        let draft = Draft("First message")
        let timedOut = expectSendToFinish(session)
        // An injected publisher exercises the local fallback independently of
        // the service path's socket-deadline protection.
        session.send(draft: draft.binding) { service.sendPrivateMessage(to: peer, message: $0) }
        wait(for: [timedOut], timeout: 1)
        XCTAssertEqual(draft.message, "First message")
        XCTAssertEqual(session.failure, .deliveryUnconfirmed)

        let retried = expectSendToFinish(session)
        session.send(to: peer, draft: draft.binding, using: service)
        socket.acknowledge(at: 0)
        drainSendDelivery()
        XCTAssertTrue(session.isSending)
        XCTAssertNil(session.failure)
        XCTAssertEqual(draft.message, "First message")
        XCTAssertEqual(socket.privateMessagePayloads.count, 2)
        XCTAssertEqual(service.privateMessagesByPeerId[peer.id]?.count, 1)
        XCTAssertNotEqual(socket.privateMessagePayloads[0]["uid"] as? String, socket.privateMessagePayloads[1]["uid"] as? String)

        socket.acknowledge(at: 1)
        wait(for: [retried], timeout: 1)
        XCTAssertEqual(draft.message, "")
        XCTAssertFalse(session.isSending)
        XCTAssertNil(session.failure)
        XCTAssertEqual(service.privateMessagesByPeerId[peer.id]?.count, 2)
    }

    func testSocketTimeoutRetainsDraftAndRetryNeedsItsOwnAcknowledgement() throws {
        let socket = DeferredWebsocket()
        let service = try makeService(socket: socket)
        let peer = OGSUser(username: "Peer", id: 202)
        let session = PrivateMessageSendSession()
        let draft = Draft("First message")
        let timedOut = expectSendToFinish(session)
        session.send(to: peer, draft: draft.binding, using: service)
        socket.timeOut(at: 0)
        wait(for: [timedOut], timeout: 1)
        XCTAssertEqual(session.failure, .deliveryUnconfirmed)
        XCTAssertEqual(draft.message, "First message")
        XCTAssertFalse(session.isSending)

        let retried = expectSendToFinish(session)
        session.send(to: peer, draft: draft.binding, using: service)
        socket.acknowledge(at: 0)
        drainSendDelivery()
        XCTAssertTrue(session.isSending)
        XCTAssertEqual(draft.message, "First message")
        XCTAssertTrue(service.privateMessagesByPeerId.isEmpty)
        socket.acknowledge(at: 1)
        wait(for: [retried], timeout: 1)
        XCTAssertEqual(draft.message, "")
        XCTAssertNil(session.failure)
        XCTAssertEqual(service.privateMessagesByPeerId[peer.id]?.count, 1)
    }

    func testAccountSwitchRejectsOldAcknowledgementWithoutClearingEitherDraft() throws {
        let socket = DeferredWebsocket()
        let service = try makeService(socket: socket)
        let peer = OGSUser(username: "Peer", id: 202)
        let firstSession = PrivateMessageSendSessions.session(for: service, peerID: peer.id)
        let firstDraft = Draft("First account message")
        let firstFinished = expectSendToFinish(firstSession)
        firstSession.send(to: peer, draft: firstDraft.binding, using: service)

        try signIn(service, accountID: 404)
        let secondSession = PrivateMessageSendSessions.session(for: service, peerID: peer.id)
        let secondDraft = Draft("Second account message")
        let secondFinished = expectSendToFinish(secondSession)
        XCTAssertFalse(firstSession === secondSession)
        secondSession.send(to: peer, draft: secondDraft.binding, using: service)
        socket.acknowledge(at: 0)
        wait(for: [firstFinished], timeout: 1)
        XCTAssertEqual(firstDraft.message, "First account message")
        XCTAssertEqual(firstSession.failure, .deliveryUnconfirmed)
        XCTAssertTrue(secondSession.isSending)
        XCTAssertNil(secondSession.failure)
        XCTAssertEqual(secondDraft.message, "Second account message")
        XCTAssertTrue(service.privateMessagesByPeerId.isEmpty)

        socket.acknowledge(at: 1, from: 404)
        wait(for: [secondFinished], timeout: 1)
        XCTAssertEqual(secondDraft.message, "")
        XCTAssertNil(secondSession.failure)
        XCTAssertEqual(service.privateMessagesByPeerId[peer.id]?.map(\.from.id), [404])
    }

    func testRegistryRetainsPendingSendAcrossComposerReplacementAndPeerSelection() {
        let service = OGSService.previewInstance(user: OGSUser(username: "Sender", id: 101))
        let draft = Draft("First message")
        let response = PassthroughSubject<OGSPrivateMessage, Error>()
        weak var initialSession: PrivateMessageSendSession?
        do {
            let session = PrivateMessageSendSessions.session(for: service, peerID: 202)
            initialSession = session
            session.send(draft: draft.binding) { _ in response.eraseToAnyPublisher() }
        }
        // Idle conversations can be evicted, but the pending send stays owned.
        for peerID in 303..<343 {
            _ = PrivateMessageSendSessions.session(for: service, peerID: peerID)
        }
        let replacement = PrivateMessageSendSessions.session(for: service, peerID: 202)

        XCTAssertTrue(initialSession === replacement)
        XCTAssertTrue(replacement.isSending)
        let finished = expectSendToFinish(replacement)
        response.send(acknowledgement)
        response.send(completion: .finished)
        wait(for: [finished], timeout: 1)
        XCTAssertFalse(replacement.isSending)
        XCTAssertEqual(draft.message, "")
    }

    func testRegistrySeparatesAccountsPeersAndServiceInstances() {
        let service = OGSService.previewInstance(user: OGSUser(username: "Sender", id: 101))
        let first = PrivateMessageSendSessions.session(for: service, peerID: 202)
        let otherPeer = PrivateMessageSendSessions.session(for: service, peerID: 303)
        let otherService = OGSService.previewInstance(user: OGSUser(username: "Sender", id: 101))
        XCTAssertFalse(first === otherPeer)
        XCTAssertFalse(first === PrivateMessageSendSessions.session(for: otherService, peerID: 202))

        service.user = OGSUser(username: "Other account", id: 404)
        let otherAccount = PrivateMessageSendSessions.session(for: service, peerID: 202)
        XCTAssertFalse(first === otherAccount)
    }

    private func makeService(socket: DeferredWebsocket) throws -> OGSService {
        let suite = "com.honganhkhoa.Surround.SendSessionTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            socket.failPendingMessages()
            socket.serverEventCallback = nil
            socket.onStatusChanged = nil
            socket.authenticationConfigProvider = { nil }
            socket.onConnectTasks.removeAll()
            preferences.removePersistentDomain(forName: suite)
        }
        let service = OGSService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: OGSOfflineRejectingHTTPClient(),
            preferences: preferences,
            ogsWebsocket: socket,
            connectsAutomatically: false,
            usesSurroundOverviewService: false,
            enablesAppSideEffects: false,
            startsTimers: false,
            installsObservers: false
        )
        try signIn(service, accountID: 101)
        return service
    }

    private func signIn(_ service: OGSService, accountID: Int) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "csrf_token": "test-csrf",
            "user_jwt": "test-jwt-\(accountID)",
            "user": ["username": "Sender-\(accountID)", "id": accountID, "anonymous": false],
        ])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        service.preferences[.ogsSessionId] = "test-session-\(accountID)"
        service.ogsUIConfig = try decoder.decode(OGSUIConfig.self, from: data)
        XCTAssertEqual(service.user?.id, accountID)
    }

    private func drainSendDelivery() {
        let delivered = expectation(description: "Drain scheduled send delivery")
        DispatchQueue.main.async { delivered.fulfill() }
        wait(for: [delivered], timeout: 1)
    }

    private func expectSendToFinish(_ session: PrivateMessageSendSession) -> XCTestExpectation {
        let finished = expectation(description: "Complete send state after scheduled delivery")
        let previousCallback = session.onFinished
        session.onFinished = { [weak session] in
            session?.onFinished = previousCallback
            previousCallback?()
            finished.fulfill()
        }
        return finished
    }
}
