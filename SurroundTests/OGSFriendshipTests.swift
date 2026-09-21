//
//  OGSFriendshipTests.swift
//  SurroundTests
//

import Alamofire
import Combine
import CoreFoundation
import XCTest

final class OGSFriendshipTests: XCTestCase {
    private final class FriendshipWebsocket: OGSWebsocketProtocol {
        var serverEventCallback: ((String, Any?) -> Void)?
        var onConnectTasks: [() -> Void] = []
        var onStatusChanged: (() -> Void)?
        var authenticationConfigProvider: () -> OGSUIConfig? = { nil }
        var authenticated = false
        var opened = false
        var status = OGSWebsocketStatus.disconnected
        var drift = 0.0
        var latency = 0.0

        func connect() {}
        func close() {}
        func reconnectIfNeeded() {}
        func closeThenReconnect() {}
        func emit(command: String, data: Any?, resultCallback: OGSWebsocketResultCallback?) {
            resultCallback?(nil, nil)
        }
    }

    /// Responses may be retained and delivered later without blocking URLSession's
    /// protocol queue, so concurrent requests and cancellation remain testable.
    private final class FriendshipURLProtocol: URLProtocol {
        private static let lock = NSLock()
        private static var handler: ((FriendshipURLProtocol) -> Void)?
        private static var requests: [URLRequest] = []

        static func configure(_ handler: ((FriendshipURLProtocol) -> Void)?) {
            lock.lock()
            defer { lock.unlock() }
            self.handler = handler
            requests = []
        }

        static var recordedRequests: [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return requests
        }

        static func path(for request: URLRequest) -> String? {
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.path }
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lock.lock()
            Self.requests.append(request)
            let handler = Self.handler
            Self.lock.unlock()
            if let handler {
                handler(self)
            } else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            }
        }

        override func stopLoading() {}

        func respond(_ body: String = "", statusCode: Int = 200) {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !body.isEmpty {
                client?.urlProtocol(self, didLoad: Data(body.utf8))
            }
            client?.urlProtocolDidFinishLoading(self)
        }

        func respondToListRequest(friends: Bool = false) {
            switch Self.path(for: request) {
            case "/api/v1/ui/friends":
                respond(friends ? #"{"friends":[{"id":42,"username":"opponent"}]}"# : #"{"friends":[]}"#)
            case "/api/v1/me/friends/invitations/":
                respond("[]")
            default:
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            }
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private var preferenceSuites: [String] = []

    override func setUp() {
        super.setUp()
        FriendshipURLProtocol.configure(nil)
    }

    override func tearDown() {
        cancellables.removeAll()
        FriendshipURLProtocol.configure(nil)
        for suite in preferenceSuites {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        preferenceSuites.removeAll()
        super.tearDown()
    }

    func testAutomaticFriendshipRefreshUsesRecentFullProfileUntilExpiry() throws {
        FriendshipURLProtocol.configure { request in
            request.respond(Self.profileJSON(flags: #""is_friend":true"#))
        }
        let service = try makeService(friendship: .none)
        var now: TimeInterval = 100
        service.friendshipRefreshTime = { now }

        _ = try waitForResult(service.fetchPlayerProfile(playerId: 42)).get()
        XCTAssertEqual(try waitForResult(service.refreshFriendship(playerID: 42, force: false)).get(), .friends)
        now += 4.9
        _ = try waitForResult(service.refreshFriendship(playerID: 42, force: false)).get()
        XCTAssertEqual(FriendshipURLProtocol.recordedRequests.count, 1)

        now = 105
        _ = try waitForResult(service.refreshFriendship(playerID: 42, force: false)).get()
        XCTAssertEqual(FriendshipURLProtocol.recordedRequests.count, 2)
        _ = try waitForResult(service.refreshFriendship(playerID: 42, force: true)).get()
        XCTAssertEqual(FriendshipURLProtocol.recordedRequests.count, 3)
        // A new visible profile still loads its biography, ratings and games.
        _ = try waitForResult(service.fetchPlayerProfile(playerId: 42)).get()
        XCTAssertEqual(FriendshipURLProtocol.recordedRequests.count, 4)
    }

    func testFailedOrMalformedFriendshipRefreshDoesNotBecomeFresh() throws {
        var attempt = 0
        FriendshipURLProtocol.configure { request in
            attempt += 1
            switch attempt {
            case 2: request.respond(statusCode: 503)
            case 3: request.respond(Self.profileJSON(flags: #""is_friend":false"#))
            default: request.respond(Self.profileJSON(flags: #""is_friend":true"#))
            }
        }
        let service = try makeService(friendship: .none)
        service.friendshipRefreshTime = { 100 }
        _ = try waitForResult(service.fetchPlayerProfile(playerId: 42)).get()
        guard case .failure = waitForResult(service.refreshFriendship(playerID: 42, force: true)) else {
            return XCTFail("The explicit refresh should surface the HTTP failure")
        }
        guard case .failure = waitForResult(service.refreshFriendship(playerID: 42, force: false)) else {
            return XCTFail("An incomplete response cannot count as a fresh relationship")
        }
        XCTAssertEqual(try waitForResult(service.refreshFriendship(playerID: 42, force: false)).get(), .friends)
        XCTAssertEqual(FriendshipURLProtocol.recordedRequests.count, 4)
    }

    func testOverlappingFriendshipRefreshesShareRequestAndSurviveOneCancellation() throws {
        let started = expectation(description: "shared profile request started")
        var pending: FriendshipURLProtocol?
        FriendshipURLProtocol.configure { request in
            pending = request
            started.fulfill()
        }
        let service = try makeService(friendship: .none)
        let cancelled = service.refreshFriendship(playerID: 42, force: false)
            .sink(receiveCompletion: { _ in XCTFail("Cancelled subscriber completed") },
                  receiveValue: { _ in XCTFail("Cancelled subscriber received a value") })
        wait(for: [started], timeout: 5)
        let completed = expectation(description: "remaining subscriber completed")
        service.refreshFriendship(playerID: 42, force: true)
            .sink(receiveCompletion: {
                if case .failure(let error) = $0 { XCTFail("Unexpected failure: \(error)") }
                completed.fulfill()
            }, receiveValue: { XCTAssertEqual($0, .requestSent) })
            .store(in: &cancellables)
        cancelled.cancel()
        try XCTUnwrap(pending).respond(Self.profileJSON(flags: #""friend_request_sent":13017"#))
        wait(for: [completed], timeout: 5)
        XCTAssertEqual(FriendshipURLProtocol.recordedRequests.count, 1)
    }

    func testCancellingAllFriendshipRefreshSubscribersAllowsNewRequest() throws {
        let started = expectation(description: "cancelled profile request started")
        FriendshipURLProtocol.configure { _ in started.fulfill() }
        let service = try makeService(friendship: .none)
        let cancelled = service.refreshFriendship(playerID: 42, force: false)
            .sink(receiveCompletion: { _ in XCTFail("Cancelled subscriber completed") }, receiveValue: { _ in })
        wait(for: [started], timeout: 5)
        cancelled.cancel()
        FriendshipURLProtocol.configure { request in
            request.respond(Self.profileJSON(flags: #""is_friend":true"#))
        }
        XCTAssertEqual(try waitForResult(service.refreshFriendship(playerID: 42, force: false)).get(), .friends)
        XCTAssertEqual(FriendshipURLProtocol.recordedRequests.count, 1)
    }

    func testFriendshipMutationInvalidatesRecentProfileFlags() throws {
        var profileRequests = 0
        FriendshipURLProtocol.configure { request in
            if FriendshipURLProtocol.path(for: request.request) == "/api/v1/players/42/full" {
                profileRequests += 1
                request.respond(Self.profileJSON(flags: profileRequests == 1
                    ? #""is_friend":false,"friend_request_sent":false,"friend_request_received":false"#
                    : #""friend_request_sent":13017"#))
            } else if request.request.httpMethod == "POST" {
                request.respond(statusCode: 204)
            } else {
                request.respondToListRequest()
            }
        }
        let service = try makeService(friendship: .none)
        service.friendshipRefreshTime = { 100 }
        _ = try waitForResult(service.fetchPlayerProfile(playerId: 42)).get()
        try waitForResult(service.performFriendshipAction(.send, user: makeUser(id: 42))).get()
        XCTAssertEqual(try waitForResult(service.refreshFriendship(playerID: 42, force: false)).get(), .requestSent)
        XCTAssertEqual(profileRequests, 2)
    }

    func testAccountChangeDiscardsSharedRefreshAndFreshness() throws {
        let started = expectation(description: "old account profile started")
        var pending: FriendshipURLProtocol?
        FriendshipURLProtocol.configure { request in
            pending = request
            started.fulfill()
        }
        let service = try makeService(friendship: .none)
        service.friendshipRefreshTime = { 100 }
        let staleCompleted = expectation(description: "old account rejected")
        service.refreshFriendship(playerID: 42, force: false)
            .sink(receiveCompletion: {
                guard case .failure(let error) = $0,
                      case OGSServiceError.staleAuthenticationContext = error else {
                    return XCTFail("The old account's profile must be rejected")
                }
                staleCompleted.fulfill()
            }, receiveValue: { _ in XCTFail("Old account response delivered") })
            .store(in: &cancellables)
        wait(for: [started], timeout: 5)
        service.ogsUIConfig = try makeUIConfig(userID: 8)
        FriendshipURLProtocol.configure { request in
            request.respond(Self.profileJSON(flags: #""friend_request_sent":13017"#))
        }
        XCTAssertEqual(try waitForResult(service.refreshFriendship(playerID: 42, force: false)).get(), .requestSent)
        try XCTUnwrap(pending).respond(Self.profileJSON(flags: #""is_friend":true"#))
        wait(for: [staleCompleted], timeout: 5)
        XCTAssertEqual(service.friendship(for: 42), .requestSent)

        service.ogsUIConfig = try makeUIConfig(userID: 9)
        _ = try waitForResult(service.refreshFriendship(playerID: 42, force: false)).get()
        XCTAssertEqual(FriendshipURLProtocol.recordedRequests.count, 2)
    }

    func testSocketInvalidationBypassesRecentProfileFlags() throws {
        var profileRequests = 0
        FriendshipURLProtocol.configure { request in
            if FriendshipURLProtocol.path(for: request.request) == "/api/v1/players/42/full" {
                profileRequests += 1
                request.respond(Self.profileJSON(flags: #""friend_request_sent":13017"#))
            } else {
                request.respondToListRequest()
            }
        }
        let socket = FriendshipWebsocket()
        let service = try makeService(friendship: .none, socket: socket)
        service.friendshipRefreshTime = { 100 }
        _ = try waitForResult(service.fetchPlayerProfile(playerId: 42)).get()
        let refreshed = expectation(description: "socket refresh completed")
        service.$friendsLoading.combineLatest(service.$friendInvitationsLoading)
            .dropFirst().filter { !$0.0 && !$0.1 }.prefix(1)
            .sink { _ in DispatchQueue.main.async { refreshed.fulfill() } }
            .store(in: &cancellables)
        socket.serverEventCallback?("ui-push", ["event": "update-friend-list"])
        wait(for: [refreshed], timeout: 5)
        _ = try waitForResult(service.refreshFriendship(playerID: 42, force: false)).get()
        XCTAssertEqual(profileRequests, 2)
    }

    func testProfileDecodesFriendshipFlagsAndPrecedence() throws {
        let cases: [(String, OGSProfileFriendship)] = [
            (#""is_friend":false,"friend_request_sent":false,"friend_request_received":false"#, .none),
            (#""is_friend":false,"friend_request_sent":true,"friend_request_received":false"#, .requestSent),
            (#""is_friend":false,"friend_request_sent":false,"friend_request_received":true"#, .requestReceived),
            (#""is_friend":false,"friend_request_sent":13017,"friend_request_received":false"#, .requestSent),
            (#""is_friend":false,"friend_request_sent":false,"friend_request_received":13017"#, .requestReceived),
            (#""is_friend":true,"friend_request_sent":false,"friend_request_received":false"#, .friends),
            (#""is_friend":true,"friend_request_sent":true,"friend_request_received":true"#, .friends),
            (#""is_friend":false,"friend_request_sent":true,"friend_request_received":true"#, .requestReceived),
        ]
        for (flags, expected) in cases {
            let profile = try decodeProfile(flags: flags)
            XCTAssertEqual(profile.friendship, expected, flags)
        }
    }

    func testMissingOrMalformedFriendshipFlagsDoNotInventAnUnrelatedState() throws {
        for flags in [
            "", #""is_friend":null"#, #""is_friend":"false""#,
            #""is_friend":1,"friend_request_sent":false,"friend_request_received":false"#,
            #""is_friend":false"#,
            #""is_friend":false,"friend_request_sent":false,"friend_request_received":{}"#,
        ] {
            let profile = try decodeProfile(flags: flags)
            XCTAssertEqual(profile.user.username, "opponent")
            XCTAssertNil(profile.friendship, flags)
        }
        XCTAssertEqual(try decodeProfile(flags: #""is_friend":true"#).friendship, .friends)
        XCTAssertEqual(try decodeProfile(flags: #""friend_request_received":true"#).friendship, .requestReceived)
        XCTAssertEqual(try decodeProfile(flags: #""friend_request_sent":true"#).friendship, .requestSent)
    }

    func testMalformedRequestIDsRemainUnknown() throws {
        for key in ["friend_request_sent", "friend_request_received"] {
            let otherKey = key == "friend_request_sent" ? "friend_request_received" : "friend_request_sent"
            for value in ["0", "-1", "1.25", "1e100", #""13017""#, "null", "{}", "[]"] {
                let flags = #""is_friend":false,"\#(key)":\#(value),"\#(otherKey)":false"#
                let profile = try decodeProfile(flags: flags)
                XCTAssertEqual(profile.user.id, 42)
                XCTAssertNil(profile.friendship, flags)
            }
        }
    }

    func testFreshServiceLoadsAndReopensRequestSentFromAnotherClient() throws {
        FriendshipURLProtocol.configure { request in
            if FriendshipURLProtocol.path(for: request.request) == "/api/v1/players/42/full" {
                request.respond(Self.profileJSON(flags:
                    #""is_friend":false,"friend_request_sent":13017,"friend_request_received":false"#
                ))
            } else {
                request.respondToListRequest()
            }
        }
        let service = try makeService(friendship: .none, hasKnownFriendship: false)
        XCTAssertNil(service.friendship(for: 42))

        let profile = try waitForResult(service.fetchPlayerProfile(playerId: 42)).get()
        XCTAssertEqual(profile.friendship, .requestSent)
        XCTAssertEqual(service.friendship(for: 42), .requestSent)

        try waitForResult(service.refreshFriendships()).get()
        XCTAssertEqual(try waitForResult(service.refreshFriendship(playerID: 42)).get(), .requestSent)
        XCTAssertEqual(service.friendship(for: 42), .requestSent)
        XCTAssertTrue(service.friends.isEmpty)
        XCTAssertTrue(service.friendInvitations.isEmpty)
        XCTAssertTrue(FriendshipURLProtocol.recordedRequests.allSatisfy { $0.httpMethod == "GET" })
    }

    func testEachActionUsesOGSContractAndAcceptsEmptySuccessResponse() throws {
        struct Scenario {
            let action: OGSFriendshipAction
            let initial: OGSProfileFriendship
            let resulting: OGSProfileFriendship
            let path: String
            let expectedBody: [String: String]
        }
        let scenarios = [
            Scenario(action: .send, initial: .none, resulting: .requestSent,
                     path: "/api/v1/me/friends", expectedBody: ["player_id": "42"]),
            Scenario(action: .accept, initial: .requestReceived, resulting: .friends,
                     path: "/api/v1/me/friends/invitations/", expectedBody: ["from_user": "42"]),
            Scenario(action: .reject(notifyRequestor: false), initial: .requestReceived, resulting: .none,
                     path: "/api/v1/me/friends/invitations/",
                     expectedBody: ["from_user": "42", "delete": "true", "notify_requestor": "false"]),
            Scenario(action: .reject(notifyRequestor: true), initial: .requestReceived, resulting: .none,
                     path: "/api/v1/me/friends/invitations/",
                     expectedBody: ["from_user": "42", "delete": "true", "notify_requestor": "true"]),
            Scenario(action: .remove, initial: .friends, resulting: .none,
                     path: "/api/v1/me/friends", expectedBody: ["player_id": "42", "delete": "true"]),
        ]

        for scenario in scenarios {
            FriendshipURLProtocol.configure { request in
                if request.request.httpMethod == "POST" {
                    request.respond(statusCode: 204)
                } else {
                    request.respondToListRequest(friends: scenario.resulting == .friends)
                }
            }
            let service = try makeService(friendship: scenario.initial)
            try waitForResult(service.performFriendshipAction(scenario.action, user: makeUser(id: 42))).get()
            // The lists do not contain outgoing requests. A successful send
            // must remain pending when those lists are subsequently refreshed.
            try waitForResult(service.refreshFriendships()).get()
            XCTAssertEqual(service.friendship(for: 42), scenario.resulting)
            XCTAssertFalse(service.friendshipActionPlayerIDs.contains(42))
            let mutations = FriendshipURLProtocol.recordedRequests.filter { $0.httpMethod == "POST" }
            let request = try XCTUnwrap(mutations.first)
            XCTAssertEqual(mutations.count, 1)
            XCTAssertEqual(request.url?.host, "friendship.ogs.test")
            XCTAssertEqual(FriendshipURLProtocol.path(for: request), scenario.path)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-CSRFToken"), "test-csrf")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://friendship.ogs.test/player/42")
            XCTAssertEqual(try parameters(in: request), scenario.expectedBody)
        }
    }

    func testMutationDoesNotChangeStateBeforeServerAcknowledgesIt() throws {
        let started = expectation(description: "friend request started")
        var pending: FriendshipURLProtocol?
        FriendshipURLProtocol.configure { request in
            if request.request.httpMethod == "POST" {
                pending = request
                started.fulfill()
            } else {
                request.respondToListRequest()
            }
        }
        let service = try makeService(friendship: .none)
        let completed = expectation(description: "friend request completed")
        service.performFriendshipAction(.send, user: try makeUser(id: 42))
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion { XCTFail("\(error)") }
                completed.fulfill()
            }, receiveValue: {})
            .store(in: &cancellables)
        wait(for: [started], timeout: 5)
        XCTAssertEqual(service.friendship(for: 42), OGSProfileFriendship.none)
        XCTAssertTrue(service.friendshipActionPlayerIDs.contains(42))
        try XCTUnwrap(pending).respond(statusCode: 204)
        wait(for: [completed], timeout: 5)
        XCTAssertEqual(service.friendship(for: 42), .requestSent)
        XCTAssertFalse(service.friendshipActionPlayerIDs.contains(42))
    }

    func testServerFailurePreservesRelationshipAndAllowsRetry() throws {
        let service = try makeService(friendship: .requestReceived)
        let responseLock = NSLock()
        var attempts = 0
        FriendshipURLProtocol.configure { request in
            responseLock.lock()
            if request.request.httpMethod == "POST" { attempts += 1 }
            let accepted = attempts > 1
            responseLock.unlock()
            if request.request.httpMethod == "POST" {
                if accepted {
                    request.respond(statusCode: 204)
                } else {
                    request.respond(#"{"error":"The invitation has expired."}"#, statusCode: 400)
                }
            } else if FriendshipURLProtocol.path(for: request.request) == "/api/v1/me/friends/invitations/", !accepted {
                request.respond(#"[{"from_user":{"id":42,"username":"opponent"},"accepted":false}]"#)
            } else {
                request.respondToListRequest(friends: accepted)
            }
        }
        let result = waitForResult(service.performFriendshipAction(.accept, user: try makeUser(id: 42)))
        guard case .failure(let error) = result else { return XCTFail("Expected the server failure") }
        XCTAssertTrue(error.localizedDescription.contains("The invitation has expired."))
        XCTAssertEqual(service.friendship(for: 42), .requestReceived)
        XCTAssertEqual(service.friendInvitations.map(\.fromUser.id), [42])
        XCTAssertFalse(service.friendshipActionPlayerIDs.contains(42))

        try waitForResult(service.performFriendshipAction(.accept, user: makeUser(id: 42))).get()
        XCTAssertEqual(service.friendship(for: 42), .friends)
        XCTAssertTrue(service.friends.contains { $0.id == 42 })
        XCTAssertTrue(service.friendInvitations.isEmpty)
    }

    func testDuplicateMutationIsRejectedWhileFirstRequestIsInFlight() throws {
        let started = expectation(description: "first request started")
        var pending: FriendshipURLProtocol?
        FriendshipURLProtocol.configure { request in
            if request.request.httpMethod == "POST" {
                pending = request
                started.fulfill()
            } else {
                request.respondToListRequest()
            }
        }
        let service = try makeService(friendship: .none)
        let opponent = try makeUser(id: 42)
        let completed = expectation(description: "first request completed")
        service.performFriendshipAction(.send, user: opponent)
            .sink(receiveCompletion: { _ in completed.fulfill() }, receiveValue: {})
            .store(in: &cancellables)
        wait(for: [started], timeout: 5)
        guard case .failure = waitForResult(service.performFriendshipAction(.send, user: opponent)) else {
            return XCTFail("A duplicate mutation must fail instead of submitting twice")
        }
        XCTAssertEqual(FriendshipURLProtocol.recordedRequests.filter { $0.httpMethod == "POST" }.count, 1)
        XCTAssertTrue(service.friendshipActionPlayerIDs.contains(42))
        try XCTUnwrap(pending).respond(statusCode: 204)
        wait(for: [completed], timeout: 5)
        XCTAssertEqual(service.friendship(for: 42), .requestSent)
    }

    func testSelfAndAnonymousActionsCannotReachTheNetwork() throws {
        let signedIn = try makeService(friendship: .none)
        let signedOut = try makeService(friendship: .none, loggedIn: false)
        let anonymous = try makeService(friendship: .none, anonymous: true)
        for (service, targetID) in [(signedIn, 7), (signedOut, 42), (anonymous, 42)] {
            let result = waitForResult(service.performFriendshipAction(.send, user: try makeUser(id: targetID)))
            guard case .failure = result else { return XCTFail("Unavailable action unexpectedly succeeded") }
            XCTAssertTrue(service.friendshipActionPlayerIDs.isEmpty)
        }
        XCTAssertTrue(FriendshipURLProtocol.recordedRequests.isEmpty)
    }

    func testMutationFinishesAfterItsViewSubscriptionIsCancelled() throws {
        let started = expectation(description: "request started")
        var pending: FriendshipURLProtocol?
        FriendshipURLProtocol.configure { request in
            if request.request.httpMethod == "POST" {
                pending = request
                started.fulfill()
            } else {
                request.respondToListRequest()
            }
        }
        let service = try makeService(friendship: .none)
        let updated = expectation(description: "shared relationship updated")
        service.$friendshipByPlayerID
            .filter { $0[42] == .requestSent }
            .prefix(1)
            .sink { _ in updated.fulfill() }
            .store(in: &cancellables)
        let viewSubscription = service.performFriendshipAction(.send, user: try makeUser(id: 42))
            .sink(receiveCompletion: { _ in }, receiveValue: {})
        wait(for: [started], timeout: 5)
        viewSubscription.cancel()
        try XCTUnwrap(pending).respond(statusCode: 204)
        wait(for: [updated], timeout: 5)
        XCTAssertEqual(service.friendship(for: 42), .requestSent)
        XCTAssertFalse(service.friendshipActionPlayerIDs.contains(42))
    }

    func testOldAccountMutationCannotChangeNewAccountsRelationshipState() throws {
        let started = expectation(description: "old account request started")
        var pending: FriendshipURLProtocol?
        FriendshipURLProtocol.configure { request in
            pending = request
            started.fulfill()
        }
        let service = try makeService(friendship: .requestReceived)
        let completed = expectation(description: "old account request rejected")
        var receivedError: Error?
        service.performFriendshipAction(.accept, user: try makeUser(id: 42))
            .sink(receiveCompletion: {
                if case .failure(let error) = $0 { receivedError = error }
                completed.fulfill()
            }, receiveValue: {})
            .store(in: &cancellables)
        wait(for: [started], timeout: 5)
        service.ogsUIConfig = try makeUIConfig(userID: 8)
        try XCTUnwrap(pending).respond(statusCode: 204)
        wait(for: [completed], timeout: 5)
        guard let receivedError,
              case OGSServiceError.staleAuthenticationContext = receivedError else {
            return XCTFail("The old account's response must be rejected")
        }
        XCTAssertTrue(service.friendshipByPlayerID.isEmpty)
        XCTAssertTrue(service.friendInvitations.isEmpty)
        XCTAssertTrue(service.friends.isEmpty)
        XCTAssertTrue(service.friendshipActionPlayerIDs.isEmpty)
    }

    func testOlderProfileRefreshCannotUndoAcknowledgedFriendRequest() throws {
        let refreshStarted = expectation(description: "profile refresh started")
        var pendingRefresh: FriendshipURLProtocol?
        FriendshipURLProtocol.configure { request in
            if FriendshipURLProtocol.path(for: request.request) == "/api/v1/players/42/full" {
                pendingRefresh = request
                refreshStarted.fulfill()
            } else if request.request.httpMethod == "POST" {
                request.respond(statusCode: 204)
            } else {
                request.respondToListRequest()
            }
        }
        let service = try makeService(friendship: .none)
        let refreshed = expectation(description: "older profile refresh completed")
        service.refreshFriendship(playerID: 42)
            .sink(receiveCompletion: { _ in refreshed.fulfill() }, receiveValue: { _ in })
            .store(in: &cancellables)
        wait(for: [refreshStarted], timeout: 5)
        try waitForResult(service.performFriendshipAction(.send, user: makeUser(id: 42))).get()
        try XCTUnwrap(pendingRefresh).respond(Self.profileJSON(flags:
            #""is_friend":false,"friend_request_sent":false,"friend_request_received":false"#
        ))
        wait(for: [refreshed], timeout: 5)
        XCTAssertEqual(service.friendship(for: 42), .requestSent)
    }

    func testRefreshRejectsMalformedOptionalFlagsWithoutErasingKnownRelationship() throws {
        let service = try makeService(friendship: .requestSent)
        FriendshipURLProtocol.configure { request in
            request.respond(Self.profileJSON(flags: #""is_friend":false"#))
        }
        guard case .failure = waitForResult(service.refreshFriendship(playerID: 42)) else {
            return XCTFail("Incomplete friendship flags must not be treated as authoritative")
        }
        XCTAssertEqual(service.friendship(for: 42), .requestSent)
    }

    func testFriendListRefreshLoadsIncomingRequestsAndOmitsAcceptedInvitations() throws {
        FriendshipURLProtocol.configure { request in
            switch FriendshipURLProtocol.path(for: request.request) {
            case "/api/v1/ui/friends":
                request.respond(#"{"friends":[{"id":42,"username":"opponent"}]}"#)
            case "/api/v1/me/friends/invitations/":
                request.respond("""
                    [{"from_user":{"id":51,"username":"requestor"},"accepted":false},
                     {"from_user":{"id":52,"username":"already-accepted"},"accepted":true}]
                    """)
            default:
                request.respond(statusCode: 404)
            }
        }
        let service = try makeService(friendship: .none)
        try waitForResult(service.refreshFriendships()).get()
        XCTAssertEqual(service.friends.map(\.id), [42])
        XCTAssertEqual(service.friendInvitations.map(\.fromUser.id), [51])
        XCTAssertEqual(service.friendship(for: 42), .friends)
        XCTAssertEqual(service.friendship(for: 51), .requestReceived)
        XCTAssertNotEqual(service.friendship(for: 52), .requestReceived)
        XCTAssertEqual(Set(FriendshipURLProtocol.recordedRequests.compactMap { FriendshipURLProtocol.path(for: $0) }), [
            "/api/v1/ui/friends", "/api/v1/me/friends/invitations/",
        ])
        XCTAssertTrue(FriendshipURLProtocol.recordedRequests.allSatisfy { $0.httpMethod == "GET" })
    }

    func testOlderFriendListCannotRestoreFriendRemovedAfterRefreshStarted() throws {
        let listStarted = expectation(description: "old friend list request started")
        var pendingList: FriendshipURLProtocol?
        FriendshipURLProtocol.configure { request in
            if FriendshipURLProtocol.path(for: request.request) == "/api/v1/ui/friends", pendingList == nil {
                pendingList = request
                listStarted.fulfill()
            } else if request.request.httpMethod == "POST" {
                request.respond(statusCode: 204)
            } else {
                request.respondToListRequest()
            }
        }
        let service = try makeService(friendship: .friends)
        let refreshed = expectation(description: "old friend list request completed")
        service.refreshFriendships()
            .sink(receiveCompletion: { _ in refreshed.fulfill() }, receiveValue: {})
            .store(in: &cancellables)
        wait(for: [listStarted], timeout: 5)
        try waitForResult(service.performFriendshipAction(.remove, user: makeUser(id: 42))).get()
        try XCTUnwrap(pendingList).respond(#"{"friends":[{"id":42,"username":"opponent"}]}"#)
        wait(for: [refreshed], timeout: 5)
        XCTAssertEqual(service.friendship(for: 42), OGSProfileFriendship.none)
        XCTAssertFalse(service.friends.contains { $0.id == 42 })
    }

    func testOlderProfileCannotEraseFriendOrInvitationLearnedFromNewerLists() throws {
        for expected in [OGSProfileFriendship.friends, .requestReceived] {
            let started = expectation(description: "old profile request started")
            var pendingProfile: FriendshipURLProtocol?
            FriendshipURLProtocol.configure { request in
                switch FriendshipURLProtocol.path(for: request.request) {
                case "/api/v1/players/42/full":
                    pendingProfile = request
                    started.fulfill()
                case "/api/v1/ui/friends":
                    request.respondToListRequest(friends: expected == .friends)
                case "/api/v1/me/friends/invitations/":
                    request.respond(expected == .requestReceived
                        ? #"[{"from_user":{"id":42,"username":"opponent"},"accepted":false}]"# : "[]")
                default:
                    request.respond(statusCode: 404)
                }
            }
            let service = try makeService(friendship: .none)
            let refreshed = expectation(description: "old profile request completed")
            service.refreshFriendship(playerID: 42)
                .sink(receiveCompletion: { _ in refreshed.fulfill() }, receiveValue: { _ in })
                .store(in: &cancellables)
            wait(for: [started], timeout: 5)
            try waitForResult(service.refreshFriendships()).get()
            XCTAssertEqual(service.friendship(for: 42), expected)
            try XCTUnwrap(pendingProfile).respond(Self.profileJSON(flags:
                #""is_friend":false,"friend_request_sent":false,"friend_request_received":false"#
            ))
            wait(for: [refreshed], timeout: 5)
            XCTAssertEqual(service.friendship(for: 42), expected)
        }
    }

    func testOlderConcurrentProfileResponseCannotReplaceNewerResponse() throws {
        let firstStarted = expectation(description: "first profile request started")
        let secondStarted = expectation(description: "second profile request started")
        var pending: [FriendshipURLProtocol] = []
        FriendshipURLProtocol.configure { request in
            pending.append(request)
            (pending.count == 1 ? firstStarted : secondStarted).fulfill()
        }
        let service = try makeService(friendship: .none)
        let firstCompleted = expectation(description: "first profile request completed")
        let secondCompleted = expectation(description: "second profile request completed")
        service.fetchPlayerProfile(playerId: 42)
            .sink(receiveCompletion: { _ in firstCompleted.fulfill() }, receiveValue: { _ in })
            .store(in: &cancellables)
        wait(for: [firstStarted], timeout: 5)
        service.fetchPlayerProfile(playerId: 42)
            .sink(receiveCompletion: { _ in secondCompleted.fulfill() }, receiveValue: { _ in })
            .store(in: &cancellables)
        wait(for: [secondStarted], timeout: 5)
        pending[1].respond(Self.profileJSON(flags: #""is_friend":true"#))
        wait(for: [secondCompleted], timeout: 5)
        pending[0].respond(Self.profileJSON(flags:
            #""is_friend":false,"friend_request_sent":false,"friend_request_received":false"#
        ))
        wait(for: [firstCompleted], timeout: 5)
        XCTAssertEqual(service.friendship(for: 42), .friends)
        XCTAssertEqual(service.friends.map(\.id), [42])
    }

    func testFriendshipSocketEventsReloadAuthoritativeLists() throws {
        let events: [(String, [String: Any])] = [
            ("ui-push", ["event": "update-friend-list"]),
            ("notification", ["type": "friendRequest", "id": "incoming-42"]),
            ("notification", ["type": "friendAccepted", "id": "accepted-42"]),
            ("notification", ["type": "friendDeclined", "id": "declined-42"]),
        ]
        for (name, payload) in events {
            FriendshipURLProtocol.configure { request in request.respondToListRequest(friends: true) }
            let socket = FriendshipWebsocket()
            let service = try makeService(friendship: .none, socket: socket)
            let revision = service.friendshipRefreshRevision
            let refreshed = expectation(description: "authoritative lists refreshed for \(payload)")
            service.$friendsLoading.combineLatest(service.$friendInvitationsLoading)
                .dropFirst().filter { !$0.0 && !$0.1 }.prefix(1)
                .sink { _ in DispatchQueue.main.async { refreshed.fulfill() } }
                .store(in: &cancellables)
            socket.serverEventCallback?(name, payload)
            wait(for: [refreshed], timeout: 5)
            XCTAssertEqual(service.friendship(for: 42), .friends)
            XCTAssertGreaterThan(service.friendshipRefreshRevision, revision)
            XCTAssertEqual(FriendshipURLProtocol.recordedRequests.count, 2)
            XCTAssertEqual(Set(FriendshipURLProtocol.recordedRequests.compactMap {
                FriendshipURLProtocol.path(for: $0)
            }), ["/api/v1/ui/friends", "/api/v1/me/friends/invitations/"])
        }
    }

    func testRepeatedFriendNotificationDoesNotReplayRefreshOrStateTransition() throws {
        FriendshipURLProtocol.configure { request in
            if FriendshipURLProtocol.path(for: request.request) == "/api/v1/me/friends/invitations/" {
                request.respond(#"[{"from_user":{"id":42,"username":"opponent"},"accepted":false}]"#)
            } else {
                request.respondToListRequest()
            }
        }
        let socket = FriendshipWebsocket()
        let service = try makeService(friendship: .none, socket: socket)
        let refreshed = expectation(description: "incoming request loaded")
        service.$friendsLoading.combineLatest(service.$friendInvitationsLoading)
            .dropFirst().filter { !$0.0 && !$0.1 }.prefix(1)
            .sink { _ in DispatchQueue.main.async { refreshed.fulfill() } }
            .store(in: &cancellables)
        let notification: [String: Any] = ["type": "friendRequest", "id": 123]
        socket.serverEventCallback?("notification", notification)
        wait(for: [refreshed], timeout: 5)
        let revision = service.friendshipRefreshRevision
        XCTAssertEqual(service.friendship(for: 42), .requestReceived)

        let replayed = expectation(description: "duplicate must not reload")
        replayed.isInverted = true
        FriendshipURLProtocol.configure { request in
            replayed.fulfill()
            request.respondToListRequest()
        }
        socket.serverEventCallback?("notification", notification)
        wait(for: [replayed], timeout: 0.3)
        XCTAssertEqual(service.friendshipRefreshRevision, revision)
        XCTAssertEqual(service.friendship(for: 42), .requestReceived)
        XCTAssertEqual(service.friendInvitations.map(\.id), [42])
    }

    func testLateListResponseCannotRepopulateSnapshotsAfterAccountChange() throws {
        let started = expectation(description: "both list requests started")
        started.expectedFulfillmentCount = 2
        let pendingLock = NSLock()
        var pending: [FriendshipURLProtocol] = []
        FriendshipURLProtocol.configure { request in
            pendingLock.lock()
            pending.append(request)
            pendingLock.unlock()
            started.fulfill()
        }
        let service = try makeService(friendship: .requestReceived)
        let completed = expectation(description: "old account list response rejected")
        var receivedError: Error?
        service.refreshFriendships().sink(receiveCompletion: {
            if case .failure(let error) = $0 { receivedError = error }
            completed.fulfill()
        }, receiveValue: {}).store(in: &cancellables)
        wait(for: [started], timeout: 5)
        service.ogsUIConfig = try makeUIConfig(userID: 8)
        pendingLock.lock()
        let responses = pending
        pendingLock.unlock()
        responses.forEach { $0.respondToListRequest(friends: true) }
        wait(for: [completed], timeout: 5)
        guard let receivedError,
              case OGSServiceError.staleAuthenticationContext = receivedError else {
            return XCTFail("The former account's list response must be rejected")
        }
        XCTAssertTrue(service.friends.isEmpty)
        XCTAssertTrue(service.friendInvitations.isEmpty)
        XCTAssertTrue(service.friendshipByPlayerID.isEmpty)
        XCTAssertFalse(service.friendInvitationsLoading)
        XCTAssertNil(service.friendInvitationsError)
    }

    func testMissingOrMalformedInvitationDatePreservesValidRequest() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        for dateField in ["", #", "created":null"#, #", "created":"not-a-date""#, #", "created":42"#] {
            let invitation = try decoder.decode(OGSFriendInvitation.self, from: Data(
                #"{"from_user":{"id":42,"username":"opponent"},"accepted":false\#(dateField)}"#.utf8
            ))
            XCTAssertEqual(invitation.id, 42)
            XCTAssertFalse(invitation.accepted)
            XCTAssertNil(invitation.created)
        }
    }

    func testNewerProfileWinsOverOlderFriendListInEitherCompletionOrder() throws {
        for profileFinishesFirst in [false, true] {
            let listStarted = expectation(description: "older list started")
            let profileStarted = expectation(description: "newer profile started")
            var pendingList: FriendshipURLProtocol?
            var pendingProfile: FriendshipURLProtocol?
            FriendshipURLProtocol.configure { request in
                switch FriendshipURLProtocol.path(for: request.request) {
                case "/api/v1/ui/friends":
                    pendingList = request
                    listStarted.fulfill()
                case "/api/v1/players/42/full":
                    pendingProfile = request
                    profileStarted.fulfill()
                default:
                    request.respondToListRequest()
                }
            }
            let service = try makeService(friendship: .friends)
            let listCompleted = expectation(description: "older list completed")
            let profileCompleted = expectation(description: "newer profile completed")
            service.refreshFriendships()
                .sink(receiveCompletion: { _ in listCompleted.fulfill() }, receiveValue: {})
                .store(in: &cancellables)
            wait(for: [listStarted], timeout: 5)
            service.refreshFriendship(playerID: 42)
                .sink(receiveCompletion: { _ in profileCompleted.fulfill() }, receiveValue: { _ in })
                .store(in: &cancellables)
            wait(for: [profileStarted], timeout: 5)
            if profileFinishesFirst {
                try XCTUnwrap(pendingProfile).respond(Self.profileJSON(flags: #""is_friend":true"#))
                wait(for: [profileCompleted], timeout: 5)
                try XCTUnwrap(pendingList).respond(#"{"friends":[]}"#)
                wait(for: [listCompleted], timeout: 5)
            } else {
                try XCTUnwrap(pendingList).respond(#"{"friends":[]}"#)
                wait(for: [listCompleted], timeout: 5)
                try XCTUnwrap(pendingProfile).respond(Self.profileJSON(flags: #""is_friend":true"#))
                wait(for: [profileCompleted], timeout: 5)
            }
            XCTAssertEqual(service.friendship(for: 42), .friends)
            XCTAssertEqual(service.friends.map(\.id), [42])
        }
    }

    func testNewerEmptyListsPreventOlderProfileFromRestoringFriendshipForKnownPlayers() throws {
        for initial in [OGSProfileFriendship.none, .requestSent] {
            let started = expectation(description: "older profile request started")
            var pendingProfile: FriendshipURLProtocol?
            FriendshipURLProtocol.configure { request in
                if FriendshipURLProtocol.path(for: request.request) == "/api/v1/players/42/full" {
                    pendingProfile = request
                    started.fulfill()
                } else {
                    request.respondToListRequest()
                }
            }
            let service = try makeService(friendship: initial)
            let completed = expectation(description: "older profile request completed")
            service.refreshFriendship(playerID: 42)
                .sink(receiveCompletion: { _ in completed.fulfill() }, receiveValue: { _ in })
                .store(in: &cancellables)
            wait(for: [started], timeout: 5)
            try waitForResult(service.refreshFriendships()).get()
            XCTAssertEqual(service.friendship(for: 42), initial)
            try XCTUnwrap(pendingProfile).respond(Self.profileJSON(flags: #""is_friend":true"#))
            wait(for: [completed], timeout: 5)
            XCTAssertEqual(service.friendship(for: 42), initial)
            XCTAssertTrue(service.friends.isEmpty)
            XCTAssertTrue(service.friendInvitations.isEmpty)
        }
    }

    func testFriendListsDoNotOverrideOutgoingFlagsTheyCannotDescribe() throws {
        struct Scenario {
            let initial: OGSProfileFriendship
            let profile: OGSProfileFriendship
            let lists: OGSProfileFriendship
            let expected: OGSProfileFriendship
        }
        let scenarios = [
            Scenario(initial: .none, profile: .requestSent, lists: .none, expected: .requestSent),
            Scenario(initial: .requestSent, profile: .none, lists: .none, expected: .none),
            Scenario(initial: .none, profile: .none, lists: .friends, expected: .friends),
            Scenario(initial: .none, profile: .requestSent, lists: .friends, expected: .friends),
            Scenario(initial: .none, profile: .none, lists: .requestReceived, expected: .requestReceived),
            Scenario(initial: .none, profile: .requestSent, lists: .requestReceived, expected: .requestReceived),
        ]
        for scenario in scenarios {
            let started = expectation(description: "older profile request started")
            var pendingProfile: FriendshipURLProtocol?
            FriendshipURLProtocol.configure { request in
                switch FriendshipURLProtocol.path(for: request.request) {
                case "/api/v1/players/42/full":
                    pendingProfile = request
                    started.fulfill()
                case "/api/v1/me/friends/invitations/" where scenario.lists == .requestReceived:
                    request.respond(#"[{"from_user":{"id":42,"username":"opponent"},"accepted":false}]"#)
                default:
                    request.respondToListRequest(friends: scenario.lists == .friends)
                }
            }
            let service = try makeService(friendship: scenario.initial)
            let completed = expectation(description: "older profile request completed")
            service.refreshFriendship(playerID: 42)
                .sink(receiveCompletion: { _ in completed.fulfill() }, receiveValue: { _ in })
                .store(in: &cancellables)
            wait(for: [started], timeout: 5)
            try waitForResult(service.refreshFriendships()).get()
            let requestSent = scenario.profile == .requestSent
            try XCTUnwrap(pendingProfile).respond(Self.profileJSON(flags:
                #""is_friend":false,"friend_request_sent":\#(requestSent),"friend_request_received":false"#
            ))
            wait(for: [completed], timeout: 5)
            XCTAssertEqual(service.friendship(for: 42), scenario.expected)
            XCTAssertEqual(service.friends.contains { $0.id == 42 }, scenario.expected == .friends)
            XCTAssertEqual(service.friendInvitations.contains { $0.id == 42 }, scenario.expected == .requestReceived)
        }
    }

    func testFailureSurvivesSubscriberCancellationAndRetryClearsOnlyItsOwnFailure() throws {
        let firstStarted = expectation(description: "first send started")
        let retryStarted = expectation(description: "retry send started")
        var pending: [FriendshipURLProtocol] = []
        FriendshipURLProtocol.configure { request in
            if request.request.httpMethod == "POST" {
                pending.append(request)
                (pending.count == 1 ? firstStarted : retryStarted).fulfill()
            } else {
                request.respondToListRequest()
            }
        }
        let service = try makeService(friendship: .none)
        let failureRecorded = expectation(description: "failure retained after view left")
        service.$friendshipFailuresByPlayerID.filter { $0[42] != nil }.prefix(1)
            .sink { _ in DispatchQueue.main.async { failureRecorded.fulfill() } }
            .store(in: &cancellables)
        let viewSubscription = service.performFriendshipAction(.send, user: try makeUser(id: 42))
            .sink(receiveCompletion: { _ in }, receiveValue: {})
        wait(for: [firstStarted], timeout: 5)
        viewSubscription.cancel()
        pending[0].respond(#"{"error":"Unable to send the request."}"#, statusCode: 400)
        wait(for: [failureRecorded], timeout: 5)
        let firstFailure = try XCTUnwrap(service.friendshipFailuresByPlayerID[42])
        XCTAssertEqual(firstFailure.user.id, 42)
        XCTAssertEqual(firstFailure.action, .send)
        XCTAssertEqual(firstFailure.message, "Unable to send the request.")
        XCTAssertEqual(service.friendship(for: 42), OGSProfileFriendship.none)
        XCTAssertFalse(service.friendshipActionPlayerIDs.contains(42))

        let retryCompleted = expectation(description: "retry failed")
        service.performFriendshipAction(.send, user: try makeUser(id: 42))
            .sink(receiveCompletion: { _ in retryCompleted.fulfill() }, receiveValue: {})
            .store(in: &cancellables)
        wait(for: [retryStarted], timeout: 5)
        XCTAssertNil(service.friendshipFailuresByPlayerID[42])
        pending[1].respond(#"{"error":"Still unable to send the request."}"#, statusCode: 400)
        wait(for: [retryCompleted], timeout: 5)
        let latestFailure = try XCTUnwrap(service.friendshipFailuresByPlayerID[42])
        XCTAssertNotEqual(latestFailure.id, firstFailure.id)
        XCTAssertEqual(latestFailure.message, "Still unable to send the request.")
        service.dismissFriendshipFailure(playerID: 42, failureID: firstFailure.id)
        XCTAssertEqual(service.friendshipFailuresByPlayerID[42]?.id, latestFailure.id)
        service.dismissFriendshipFailure(playerID: 42, failureID: latestFailure.id)
        XCTAssertNil(service.friendshipFailuresByPlayerID[42])
    }

    func testListFailuresAreIsolatedAndKeepCachedMembers() throws {
        for friendsFail in [true, false] {
            for hasCache in [true, false] {
                for malformedEnvelope in [true, false] {
                    FriendshipURLProtocol.configure { request in
                        let isFriends = FriendshipURLProtocol.path(for: request.request) == "/api/v1/ui/friends"
                        if isFriends == friendsFail {
                            request.respond(malformedEnvelope ? #"{"unexpected":true}"# : "", statusCode: malformedEnvelope ? 200 : 503)
                        } else if isFriends {
                            request.respond(#"{"friends":[{"id":51,"username":"new-friend"}]}"#)
                        } else {
                            request.respond(#"[{"from_user":{"id":51,"username":"new-request"},"accepted":false}]"#)
                        }
                    }
                    let initial: OGSProfileFriendship = friendsFail ? .friends : .requestReceived
                    let service = try makeService(friendship: initial, hasKnownFriendship: hasCache)
                    guard case .failure = waitForResult(service.refreshFriendships()) else {
                        return XCTFail("The failed list must report failure without discarding the successful list")
                    }
                    XCTAssertEqual(service.friendship(for: 42), hasCache ? initial : nil)
                    XCTAssertEqual(service.friendship(for: 51), friendsFail ? .requestReceived : .friends)
                    XCTAssertEqual(service.friends.map(\.id).sorted(), friendsFail ? (hasCache ? [42] : []) : [51])
                    XCTAssertEqual(service.friendInvitations.map(\.id).sorted(), friendsFail ? [51] : (hasCache ? [42] : []))
                    XCTAssertEqual(service.friendsError != nil, friendsFail)
                    XCTAssertEqual(service.friendInvitationsError != nil, !friendsFail)
                    XCTAssertFalse(service.friendsLoading)
                    XCTAssertFalse(service.friendInvitationsLoading)
                }
            }
        }
    }

    func testEachListAppearsBeforeTheOtherRequestCompletes() throws {
        for friendsFinishFirst in [true, false] {
            let started = expectation(description: "both requests started")
            started.expectedFulfillmentCount = 2
            var pendingFriends: FriendshipURLProtocol?
            var pendingInvitations: FriendshipURLProtocol?
            FriendshipURLProtocol.configure { request in
                if FriendshipURLProtocol.path(for: request.request) == "/api/v1/ui/friends" {
                    pendingFriends = request
                } else {
                    pendingInvitations = request
                }
                started.fulfill()
            }
            let service = try makeService(friendship: .none, hasKnownFriendship: false)
            let completed = expectation(description: "both requests completed")
            service.refreshFriendships().sink(receiveCompletion: { _ in completed.fulfill() }, receiveValue: {})
                .store(in: &cancellables)
            wait(for: [started], timeout: 5)
            let firstLoaded = expectation(description: "first list becomes available")
            if friendsFinishFirst {
                service.$friendsLoading.filter { !$0 }.prefix(1).sink { _ in firstLoaded.fulfill() }
                    .store(in: &cancellables)
                try XCTUnwrap(pendingFriends).respond(#"{"friends":[{"id":42,"username":"opponent"}]}"#)
            } else {
                service.$friendInvitationsLoading.filter { !$0 }.prefix(1).sink { _ in firstLoaded.fulfill() }
                    .store(in: &cancellables)
                try XCTUnwrap(pendingInvitations).respond(#"[{"from_user":{"id":42,"username":"opponent"},"accepted":false}]"#)
            }
            wait(for: [firstLoaded], timeout: 5)
            XCTAssertEqual(service.friendship(for: 42), friendsFinishFirst ? .friends : .requestReceived)
            XCTAssertEqual(service.friendsLoading, !friendsFinishFirst)
            XCTAssertEqual(service.friendInvitationsLoading, friendsFinishFirst)
            try XCTUnwrap(friendsFinishFirst ? pendingInvitations : pendingFriends).respond(statusCode: 503)
            wait(for: [completed], timeout: 5)
        }
    }

    func testMalformedListEntriesKeepGoodRowsAndDoNotImplyRemoval() throws {
        for malformedFriends in [true, false] {
            FriendshipURLProtocol.configure { request in
                if FriendshipURLProtocol.path(for: request.request) == "/api/v1/ui/friends" {
                    request.respond(malformedFriends
                        ? #"{"friends":[null,{},"bad",{"id":42},{"id":0,"username":"invalid"},{"id":51,"username":"valid"}]}"#
                        : #"{"friends":[]}"#)
                } else {
                    request.respond(malformedFriends ? "[]"
                        : #"[null,{},"bad",{"from_user":{"id":42}},{"from_user":{"id":0,"username":"invalid"},"accepted":false},{"from_user":{"id":51,"username":"valid"},"accepted":false}]"#)
                }
            }
            let relationship: OGSProfileFriendship = malformedFriends ? .friends : .requestReceived
            let service = try makeService(friendship: relationship)
            guard case .failure = waitForResult(service.refreshFriendships()) else {
                return XCTFail("An incomplete list must retain an error while showing usable rows")
            }
            XCTAssertEqual(service.friendship(for: 42), relationship)
            XCTAssertEqual(service.friendship(for: 51), relationship)
            XCTAssertEqual(service.friends.map(\.id).sorted(), malformedFriends ? [42, 51] : [])
            XCTAssertEqual(service.friendInvitations.map(\.id).sorted(), malformedFriends ? [] : [42, 51])
            XCTAssertEqual(service.friendsError != nil, malformedFriends)
            XCTAssertEqual(service.friendInvitationsError != nil, !malformedFriends)

            // A complete retry can confirm removal and clears only real errors.
            FriendshipURLProtocol.configure { request in request.respondToListRequest() }
            try waitForResult(service.refreshFriendships()).get()
            XCTAssertTrue(service.friends.isEmpty)
            XCTAssertTrue(service.friendInvitations.isEmpty)
            XCTAssertEqual(service.friendship(for: 42), OGSProfileFriendship.none)
            XCTAssertEqual(service.friendship(for: 51), OGSProfileFriendship.none)
            XCTAssertNil(service.friendsError)
            XCTAssertNil(service.friendInvitationsError)
        }
    }

    func testPartialListAbsenceOnlySupersedesItsOwnOlderProfileMembership() throws {
        for friendsSucceed in [true, false] {
            for profileIsFriend in [true, false] {
                let profileStarted = expectation(description: "older profile request started")
                var pendingProfile: FriendshipURLProtocol?
                FriendshipURLProtocol.configure { request in
                    let path = FriendshipURLProtocol.path(for: request.request)
                    if path == "/api/v1/players/42/full" {
                        pendingProfile = request
                        profileStarted.fulfill()
                    } else if (path == "/api/v1/ui/friends") == friendsSucceed {
                        request.respondToListRequest()
                    } else {
                        request.respond(statusCode: 503)
                    }
                }
                let service = try makeService(friendship: .none, hasKnownFriendship: false)
                let profileCompleted = expectation(description: "older profile completed")
                service.fetchPlayerProfile(playerId: 42)
                    .sink(receiveCompletion: { _ in profileCompleted.fulfill() }, receiveValue: { _ in })
                    .store(in: &cancellables)
                wait(for: [profileStarted], timeout: 5)
                guard case .failure = waitForResult(service.refreshFriendships()) else {
                    return XCTFail("One list failed")
                }
                try XCTUnwrap(pendingProfile).respond(Self.profileJSON(flags: profileIsFriend
                    ? #""is_friend":true"# : #""is_friend":false,"friend_request_received":true"#))
                wait(for: [profileCompleted], timeout: 5)
                if friendsSucceed == profileIsFriend {
                    XCTAssertNil(service.friendship(for: 42), "The completed empty list disproves this old membership")
                } else {
                    XCTAssertEqual(service.friendship(for: 42), profileIsFriend ? .friends : .requestReceived,
                                   "A failed list cannot disprove its membership")
                }
            }
        }
    }

    private static func profileJSON(flags: String) -> String {
        let suffix = flags.isEmpty ? "" : ",\(flags)"
        return #"{"user":{"id":42,"username":"opponent"}\#(suffix)}"#
    }

    private func decodeProfile(flags: String) throws -> OGSPlayerProfile {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSPlayerProfile.self, from: Data(Self.profileJSON(flags: flags).utf8))
    }

    private func makeUser(id: Int, anonymous: Bool = false) throws -> OGSUser {
        try JSONDecoder().decode(OGSUser.self, from: Data(
            #"{"id":\#(id),"username":"\#(id == 42 ? "opponent" : "viewer")","anonymous":\#(anonymous)}"#.utf8
        ))
    }

    private func makeUIConfig(userID: Int = 7, anonymous: Bool = false) throws -> OGSUIConfig {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSUIConfig.self, from: Data(
            #"{"csrf_token":"test-csrf","user":{"id":\#(userID),"username":"viewer","anonymous":\#(anonymous)}}"#.utf8
        ))
    }

    private func makeService(
        friendship: OGSProfileFriendship,
        hasKnownFriendship: Bool = true,
        loggedIn: Bool = true,
        anonymous: Bool = false,
        socket: OGSWebsocketProtocol = OGSOfflineNoOpWebsocket(status: .disconnected)
    ) throws -> OGSService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FriendshipURLProtocol.self]
        let suite = "com.honganhkhoa.Surround.FriendshipTests.\(UUID().uuidString)"
        preferenceSuites.append(suite)
        let preferences = UserDefaults(suiteName: suite)!
        if loggedIn {
            preferences[.ogsUIConfig] = try makeUIConfig(anonymous: anonymous)
            preferences[.ogsSessionId] = "test-session"
        }
        var state = OGSService.BootstrapState()
        state.isLoggedIn = loggedIn
        state.user = loggedIn ? try makeUser(id: 7, anonymous: anonymous) : nil
        if hasKnownFriendship {
            state.friendshipByPlayerID = [42: friendship]
            if friendship == .friends {
                state.friends = [try makeUser(id: 42)]
            } else if friendship == .requestReceived {
                state.friendInvitations = [OGSFriendInvitation(fromUser: try makeUser(id: 42))]
            }
        }
        return OGSService(
            environment: OGSEnvironment(rootURL: URL(string: "https://friendship.ogs.test")!),
            httpClient: AlamofireOGSHTTPClient(
                session: Session(configuration: configuration),
                cookieStorage: configuration.httpCookieStorage
            ),
            preferences: preferences,
            ogsWebsocket: socket,
            connectsAutomatically: false,
            usesSurroundOverviewService: false,
            enablesAppSideEffects: false,
            startsTimers: false,
            installsObservers: false,
            initialState: state
        )
    }

    private func waitForResult<Value>(_ publisher: AnyPublisher<Value, Error>) -> Result<Value, Error> {
        let completed = expectation(description: "friendship operation completed")
        var result: Result<Value, Error>?
        publisher.sink(receiveCompletion: {
            if case .failure(let error) = $0 { result = .failure(error) }
            completed.fulfill()
        }, receiveValue: { result = .success($0) }).store(in: &cancellables)
        wait(for: [completed], timeout: 5)
        guard let result else {
            XCTFail("Operation completed without a value or an error")
            return .failure(OGSServiceError.invalidJSON)
        }
        return result
    }

    private func parameters(in request: URLRequest) throws -> [String: String] {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            data = body
        } else {
            return [:]
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object.mapValues { value in
                if let number = value as? NSNumber,
                   CFGetTypeID(number) == CFBooleanGetTypeID() {
                    return number.boolValue ? "true" : "false"
                }
                return String(describing: value)
            }
        }
        var components = URLComponents()
        components.percentEncodedQuery = String(decoding: data, as: UTF8.self)
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
            let value = $0.value ?? ""
            return ($0.name, ($0.name == "delete" || $0.name == "notify_requestor")
                ? (value == "1" ? "true" : value == "0" ? "false" : value) : value)
        })
    }
}
