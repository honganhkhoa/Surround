//
//  OGSServiceIsolationTests.swift
//  SurroundTests
//

import Alamofire
import Combine
import XCTest

final class OGSServiceIsolationTests: XCTestCase {
    private final class StubWebsocket: OGSWebsocketProtocol {
        var serverEventCallback: ((String, Any?) -> Void)?
        var onConnectTasks = [() -> Void]()
        var onStatusChanged: (() -> Void)?
        var authenticationConfigProvider: () -> OGSUIConfig? = { nil }
        var authenticated = false
        var opened = false
        var status = OGSWebsocketStatus.disconnected
        var drift = 0.0
        var latency = 0.0
        private(set) var reconnectCount = 0

        func connect() {}
        func close() {}
        func reconnectIfNeeded() {}
        func closeThenReconnect() { reconnectCount += 1 }

        func emit(command: String, data: Any, resultCallback: OGSWebsocketResultCallback?) {
            resultCallback?(nil, nil)
        }
    }

    private final class StubURLProtocol: URLProtocol {
        static let lock = NSLock()
        static var requests = [URLRequest]()
        static var cookieStorageByUsername = [String: HTTPCookieStorage]()
        static var rejectedUsernames = Set<String>()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lock.lock()
            Self.requests.append(request)
            Self.lock.unlock()

            let path = request.url?.path ?? ""
            let body: Data
            var headers = [String: String]()
            var statusCode = 200

            switch path {
            case "/api/v0/login":
                let username = request.value(forHTTPHeaderField: "X-Surround-Test-Username") ?? "unknown"
                Self.lock.lock()
                let cookieStorage = Self.cookieStorageByUsername[username]
                let isRejected = Self.rejectedUsernames.contains(username)
                Self.lock.unlock()
                if isRejected {
                    statusCode = 401
                    body = Data(#"{"error":"invalid credentials"}"#.utf8)
                } else {
                    let userID = username == "player-one" ? 101 : 202
                    body = Data(#"{"csrf_token":"csrf-\#(username)","user_jwt":"jwt-\#(username)","user":{"username":"\#(username)","id":\#(userID),"anonymous":false}}"#.utf8)
                    headers["Set-Cookie"] = "sessionid=session-\(username); Path=/; Secure"
                    if let cookie = HTTPCookie(properties: [
                        .name: "sessionid",
                        .value: "session-\(username)",
                        .domain: request.url?.host ?? "ogs.test",
                        .path: "/",
                        .secure: "TRUE"
                    ]) {
                        // Custom URL protocols bypass URLSession's normal cookie
                        // persistence, so reproduce that platform behavior here.
                        cookieStorage?.setCookie(cookie)
                    }
                }
            case "/api/v1/ui/friends":
                body = Data(#"{"friends":[]}"#.utf8)
            case "/api/v1/ui/overview":
                body = Data("{}".utf8)
            default:
                body = Data("{}".utf8)
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private var cancellables = Set<AnyCancellable>()
    private var preferenceSuites = [String]()

    override func setUp() {
        super.setUp()
        StubURLProtocol.lock.lock()
        StubURLProtocol.requests = []
        StubURLProtocol.cookieStorageByUsername = [:]
        StubURLProtocol.rejectedUsernames = []
        StubURLProtocol.lock.unlock()
    }
    override func tearDown() {
        cancellables.removeAll()
        for suite in preferenceSuites {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        preferenceSuites.removeAll()
        super.tearDown()
    }

    func testEnvironmentDerivesMatchingWebSocketOrigins() {
        XCTAssertEqual(OGSEnvironment.production.rootURL.absoluteString, "https://online-go.com")
        XCTAssertEqual(OGSEnvironment.production.websocketURL.absoluteString, "wss://online-go.com")
        XCTAssertEqual(OGSEnvironment.beta.rootURL.absoluteString, "https://beta.online-go.com")
        XCTAssertEqual(OGSEnvironment.beta.websocketURL.absoluteString, "wss://beta.online-go.com")

        let local = OGSEnvironment(rootURL: URL(string: "http://127.0.0.1:8080")!)
        XCTAssertEqual(local.websocketURL.absoluteString, "ws://127.0.0.1:8080")
    }

    func testTwoLoginsKeepCookiesPreferencesAndUsersIsolated() throws {
        let environment = OGSEnvironment(rootURL: URL(string: "https://ogs.test")!)
        let firstHTTP = makeHTTPClient(responseUsername: "player-one")
        let secondHTTP = makeHTTPClient(responseUsername: "player-two")
        let firstSocket = StubWebsocket()
        let secondSocket = StubWebsocket()
        let first = makeService(environment: environment, httpClient: firstHTTP, socket: firstSocket, label: "one")
        let second = makeService(environment: environment, httpClient: secondHTTP, socket: secondSocket, label: "two")

        let firstLogin = expectation(description: "first login")
        let secondLogin = expectation(description: "second login")
        var loginErrors = [Error]()

        first.login(username: "player-one", password: "not-logged")
            .sink(
                receiveCompletion: {
                    if case .failure(let error) = $0 { loginErrors.append(error) }
                    firstLogin.fulfill()
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        second.login(username: "player-two", password: "not-logged")
            .sink(
                receiveCompletion: {
                    if case .failure(let error) = $0 { loginErrors.append(error) }
                    secondLogin.fulfill()
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        wait(for: [firstLogin, secondLogin], timeout: 5)
        XCTAssertTrue(loginErrors.isEmpty)
        XCTAssertEqual(first.user?.id, 101)
        XCTAssertEqual(second.user?.id, 202)
        XCTAssertTrue(first.isLoggedIn)
        XCTAssertTrue(second.isLoggedIn)

        XCTAssertEqual(cookie(named: "sessionid", in: firstHTTP.cookieStorage), "session-player-one")
        XCTAssertEqual(cookie(named: "sessionid", in: secondHTTP.cookieStorage), "session-player-two")
        XCTAssertEqual(cookie(named: "csrftoken", in: firstHTTP.cookieStorage), "csrf-player-one")
        XCTAssertEqual(cookie(named: "csrftoken", in: secondHTTP.cookieStorage), "csrf-player-two")
        XCTAssertNotEqual(first.ogsUIConfig?.userJwt, second.ogsUIConfig?.userJwt)
        XCTAssertEqual(firstSocket.reconnectCount, 1)
        XCTAssertEqual(secondSocket.reconnectCount, 1)
        XCTAssertEqual(firstSocket.authenticationConfigProvider()?.userJwt, "jwt-player-one")
        XCTAssertEqual(secondSocket.authenticationConfigProvider()?.userJwt, "jwt-player-two")

        let remoteSettingsKey = OGSRemoteSettingKey<[OGSChallengeTemplate]>.preferredGameSettings
        let storedSettings = OGSRemoteSettingValue<[OGSChallengeTemplate]>(
            value: [],
            replication: .RemoteOnly,
            modified: Date()
        )
        first.preferences.set(try JSONEncoder().encode(storedSettings), forKey: remoteSettingsKey.name)
        XCTAssertNotNil(first.remoteSettings[remoteSettingsKey])
        XCTAssertNil(second.remoteSettings[remoteSettingsKey])

        let firstGame = Game(width: 5, height: 5, blackName: "black", whiteName: "white", gameId: .OGS(1))
        let secondGame = Game(width: 5, height: 5, blackName: "black", whiteName: "white", gameId: .OGS(2))
        firstGame.ogs = first
        secondGame.ogs = second
        XCTAssertTrue(firstGame.preferences === first.preferences)
        XCTAssertTrue(secondGame.preferences === second.preferences)

        StubURLProtocol.lock.lock()
        let loginRequests = StubURLProtocol.requests.filter { $0.url?.path == "/api/v0/login" }
        StubURLProtocol.lock.unlock()
        XCTAssertEqual(loginRequests.count, 2)
    }

    func testSubmitMoveWithoutGameDataFailsInsteadOfHanging() {
        let environment = OGSEnvironment(rootURL: URL(string: "https://ogs.test")!)
        let service = makeService(
            environment: environment,
            httpClient: makeHTTPClient(responseUsername: "unused"),
            label: "move"
        )
        let game = Game(width: 5, height: 5, blackName: "black", whiteName: "white", gameId: .OGS(42))
        let completed = expectation(description: "publisher completed")
        var receivedError: Error?

        service.submitMove(move: .pass, forGame: game)
            .sink(
                receiveCompletion: {
                    if case .failure(let error) = $0 { receivedError = error }
                    completed.fulfill()
                },
                receiveValue: { XCTFail("A move without game data must not succeed") }
            )
            .store(in: &cancellables)

        wait(for: [completed], timeout: 1)
        XCTAssertNotNil(receivedError)
    }

    func testToggleRemovedStonesWithoutGameDataFailsInsteadOfHanging() {
        let environment = OGSEnvironment(rootURL: URL(string: "https://ogs.test")!)
        let service = makeService(
            environment: environment,
            httpClient: makeHTTPClient(responseUsername: "unused"),
            label: "stones"
        )
        let game = Game(width: 5, height: 5, blackName: "black", whiteName: "white", gameId: .OGS(43))
        let completed = expectation(description: "publisher completed")
        var receivedError: Error?

        service.toggleRemovedStones(stones: [[0, 0]], forGame: game)
            .sink(
                receiveCompletion: {
                    if case .failure(let error) = $0 { receivedError = error }
                    completed.fulfill()
                },
                receiveValue: { XCTFail("Stone removal without game data must not succeed") }
            )
            .store(in: &cancellables)

        wait(for: [completed], timeout: 1)
        XCTAssertNotNil(receivedError)
    }

    func testFailedAccountSwitchClearsThePreviousIdentity() {
        let environment = OGSEnvironment(rootURL: URL(string: "https://ogs.test")!)
        let httpClient = makeHTTPClient(responseUsername: "player-one")
        let socket = StubWebsocket()
        let service = makeService(
            environment: environment,
            httpClient: httpClient,
            socket: socket,
            label: "failed-switch"
        )
        let firstLogin = expectation(description: "initial login")
        service.login(username: "player-one", password: "not-logged")
            .sink(
                receiveCompletion: { _ in firstLogin.fulfill() },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
        wait(for: [firstLogin], timeout: 5)
        XCTAssertTrue(service.isLoggedIn)

        StubURLProtocol.lock.lock()
        StubURLProtocol.rejectedUsernames.insert("player-one")
        StubURLProtocol.lock.unlock()

        let rejectedLogin = expectation(description: "rejected login")
        var receivedError: Error?
        service.login(username: "another-player", password: "not-logged")
            .sink(
                receiveCompletion: {
                    if case .failure(let error) = $0 { receivedError = error }
                    rejectedLogin.fulfill()
                },
                receiveValue: { _ in XCTFail("Rejected credentials must not produce a config") }
            )
            .store(in: &cancellables)
        wait(for: [rejectedLogin], timeout: 5)

        XCTAssertNotNil(receivedError)
        XCTAssertFalse(service.isLoggedIn)
        XCTAssertNil(service.user)
        XCTAssertNil(service.ogsUIConfig)
        XCTAssertNil(cookie(named: "sessionid", in: httpClient.cookieStorage))
        XCTAssertNil(socket.authenticationConfigProvider())
        XCTAssertEqual(socket.reconnectCount, 2)
    }

    private func makeHTTPClient(responseUsername: String) -> AlamofireOGSHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        let storage = configuration.httpCookieStorage!
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpShouldSetCookies = true
        configuration.httpAdditionalHeaders = ["X-Surround-Test-Username": responseUsername]
        StubURLProtocol.lock.lock()
        StubURLProtocol.cookieStorageByUsername[responseUsername] = storage
        StubURLProtocol.lock.unlock()
        return AlamofireOGSHTTPClient(
            session: Session(configuration: configuration),
            cookieStorage: storage
        )
    }

    private func makeService(
        environment: OGSEnvironment,
        httpClient: AlamofireOGSHTTPClient,
        socket: OGSWebsocketProtocol = StubWebsocket(),
        label: String
    ) -> OGSService {
        let suite = "com.honganhkhoa.Surround.IsolationTests.\(label).\(UUID().uuidString)"
        preferenceSuites.append(suite)
        return OGSService(
            environment: environment,
            httpClient: httpClient,
            preferences: UserDefaults(suiteName: suite)!,
            ogsWebsocket: socket,
            connectsAutomatically: false,
            usesSurroundOverviewService: false,
            enablesAppSideEffects: false,
            startsTimers: false
        )
    }

    private func cookie(named name: String, in storage: HTTPCookieStorage?) -> String? {
        storage?.cookies?.first { $0.name == name }?.value
    }
}
