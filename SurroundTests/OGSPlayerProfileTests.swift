//
//  OGSPlayerProfileTests.swift
//  SurroundTests
//

import Alamofire
import Combine
import XCTest

final class OGSPlayerProfileTests: XCTestCase {
    private final class ProfileURLProtocol: URLProtocol {
        private static let lock = NSLock()
        private static var handler: ((ProfileURLProtocol) -> Void)?
        private static var stopped: (() -> Void)?
        private static var requests: [URLRequest] = []

        static func configure(
            handler: ((ProfileURLProtocol) -> Void)?,
            stopped: (() -> Void)? = nil
        ) {
            lock.lock()
            defer { lock.unlock() }
            self.handler = handler
            self.stopped = stopped
            requests = []
        }

        static var recordedRequests: [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return requests
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

        override func stopLoading() {
            Self.lock.lock()
            let stopped = Self.stopped
            Self.lock.unlock()
            stopped?()
        }

        func respond(_ body: String, statusCode: Int = 200) {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private var preferenceSuites: [String] = []

    override func setUp() {
        super.setUp()
        ProfileURLProtocol.configure(handler: nil)
    }

    override func tearDown() {
        cancellables.removeAll()
        ProfileURLProtocol.configure(handler: nil)
        for suite in preferenceSuites {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        preferenceSuites.removeAll()
        super.tearDown()
    }

    func testSparseProfileDoesNotInventOptionalIdentityDetails() throws {
        for json in [
            #"{"user":{"id":42,"username":"player"}}"#,
            #"{"user":{"id":42,"username":"player","about":null,"country":null,"registration_date":null}}"#,
        ] {
            let profile = try decode(json)
            XCTAssertEqual(profile.id, 42)
            XCTAssertEqual(profile.user.username, "player")
            XCTAssertNil(profile.user.country)
            XCTAssertNil(profile.about)
            XCTAssertNil(profile.registrationDate)
        }
    }

    func testProfileDecodesNestedSnakeCaseFieldsAndBothTimestampPrecisions() throws {
        for dateString in ["2019-03-01T12:30:00Z", "2019-03-01T12:30:00.000Z"] {
            let profile = try decode("""
                {"user": {
                    "id": 42, "username": "player", "country": "tw",
                    "icon": "https://example.invalid/avatar.png",
                    "ui_class": "supporter", "supporter": true,
                    "about": "A **Go** player.\\nSecond paragraph.",
                    "registration_date": "\(dateString)"
                }, "active_games": [], "vs": {"wins": 4}}
                """)
            XCTAssertEqual(profile.user.country, "tw")
            XCTAssertEqual(profile.user.icon, "https://example.invalid/avatar.png")
            XCTAssertTrue(profile.user.isOGSSupporter)
            XCTAssertEqual(profile.about, "A **Go** player.\nSecond paragraph.")
            XCTAssertEqual(
                profile.registrationDate,
                ISO8601DateFormatter().date(from: "2019-03-01T12:30:00Z")
            )
        }
    }

    func testProfileRejectsMissingOrMalformedIdentity() {
        for json in [
            #"{}"#,
            #"{"user":null}"#,
            #"{"user":{"id":42}}"#,
            #"{"user":{"username":"player"}}"#,
            #"{"user":{"id":0,"username":"system"}}"#,
            #"{"user":{"id":42,"username":"  "}}"#,
            #"{"user":{"id":"42","username":"player"}}"#,
        ] {
            XCTAssertThrowsError(try decode(json), json)
        }
    }

    func testProfileIgnoresMalformedOptionalRegistrationDate() throws {
        for dateValue in [#""not-a-date""#, #""""#, "42", "true", "{}", "[]"] {
            let profile = try decode("""
                {"user":{"id":42,"username":"player","about":"A Go player.","registration_date":\(dateValue)}}
                """)
            XCTAssertEqual(profile.id, 42, dateValue)
            XCTAssertEqual(profile.user.username, "player", dateValue)
            XCTAssertEqual(profile.about, "A Go player.", dateValue)
            XCTAssertNil(profile.registrationDate, dateValue)
        }
    }

    func testFetchIsLazyAndUsesTheRequestedEnvironmentAndPlayer() throws {
        ProfileURLProtocol.configure(handler: { request in
            request.respond(#"{"user":{"id":42,"username":"player"}}"#)
        })
        let service = makeService()
        let publisher = service.fetchPlayerProfile(playerId: 42)
        XCTAssertTrue(ProfileURLProtocol.recordedRequests.isEmpty)

        let result = waitForResult(publisher)
        XCTAssertEqual(try result.get().id, 42)
        let request = try XCTUnwrap(ProfileURLProtocol.recordedRequests.first)
        XCTAssertEqual(ProfileURLProtocol.recordedRequests.count, 1)
        XCTAssertEqual(request.url?.absoluteString, "https://profile.ogs.test/api/v1/players/42/full")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(service.user)
        XCTAssertTrue(service.cachedUsersById.isEmpty)
    }

    func testFetchPreservesValidProfileWithMalformedOptionalDate() throws {
        ProfileURLProtocol.configure(handler: {
            $0.respond(#"{"user":{"id":42,"username":"player","registration_date":"not-a-date"}}"#)
        })
        let profile = try waitForResult(makeService().fetchPlayerProfile(playerId: 42)).get()
        XCTAssertEqual(profile.user.username, "player")
        XCTAssertNil(profile.registrationDate)
    }

    func testFetchRejectsAnotherPlayersResponseAndMalformedPayloads() {
        let service = makeService()
        for body in [
            #"{"user":{"id":99,"username":"other-player"}}"#,
            #"{"user":{"id":42}}"#,
            #"{"id":42,"username":"player"}"#,
            "not JSON",
        ] {
            ProfileURLProtocol.configure(handler: { $0.respond(body) })
            let result = waitForResult(service.fetchPlayerProfile(playerId: 42))
            guard case .failure(let error) = result,
                  case OGSServiceError.invalidJSON = error else {
                XCTFail("Expected an invalid profile response: \(body)")
                continue
            }
        }
    }

    func testFetchPreservesHTTPFailureInsteadOfReportingAnEmptyProfile() {
        ProfileURLProtocol.configure(handler: {
            $0.respond(#"{"user":{"id":42,"username":"player"}}"#, statusCode: 404)
        })
        let result = waitForResult(makeService().fetchPlayerProfile(playerId: 42))
        guard case .failure(let error) = result,
              let error = error as? AFError else {
            return XCTFail("Expected HTTP validation failure")
        }
        XCTAssertEqual(error.responseCode, 404)
    }

    func testFetchPreservesTransportFailure() {
        ProfileURLProtocol.configure(handler: {
            $0.client?.urlProtocol($0, didFailWithError: URLError(.notConnectedToInternet))
        })
        let result = waitForResult(makeService().fetchPlayerProfile(playerId: 42))
        guard case .failure(let error) = result,
              let error = error as? AFError,
              let underlying = error.underlyingError as? URLError else {
            return XCTFail("Expected the transport failure")
        }
        XCTAssertEqual(underlying.code, .notConnectedToInternet)
    }

    func testInvalidRequestedPlayerDoesNotStartHTTP() {
        for playerID in [0, -1] {
            let result = waitForResult(makeService().fetchPlayerProfile(playerId: playerID))
            guard case .failure(let error) = result,
                  case OGSServiceError.invalidJSON = error else {
                return XCTFail("Expected invalid player identity")
            }
        }
        XCTAssertTrue(ProfileURLProtocol.recordedRequests.isEmpty)
    }

    func testBootstrapProfilesResolveAndFailWithoutHTTPFallback() throws {
        let profile = OGSPlayerProfile(
            user: OGSUser(username: "fixture-player", id: 42),
            about: "Offline biography"
        )
        let service = makeService(initialState: .init(playerProfilesById: [42: profile]))
        XCTAssertEqual(try waitForResult(service.fetchPlayerProfile(playerId: 42)).get(), profile)

        let result = waitForResult(service.fetchPlayerProfile(playerId: 99))
        guard case .failure(let error) = result,
              case OGSServiceError.invalidJSON = error else {
            return XCTFail("A missing fixture must fail without requesting live data")
        }
        XCTAssertTrue(ProfileURLProtocol.recordedRequests.isEmpty)
    }

    func testCancellingProfileLoadCancelsItsHTTPRequest() {
        let started = expectation(description: "profile request started")
        let stopped = expectation(description: "profile request cancelled")
        ProfileURLProtocol.configure(
            handler: { _ in started.fulfill() },
            stopped: { stopped.fulfill() }
        )
        let service = makeService()
        let cancellable = service.fetchPlayerProfile(playerId: 42).sink(
            receiveCompletion: { _ in XCTFail("Cancelled request must not deliver completion") },
            receiveValue: { _ in XCTFail("Cancelled request must not deliver a profile") }
        )
        wait(for: [started], timeout: 5)
        cancellable.cancel()
        wait(for: [stopped], timeout: 5)
    }

    func testBootstrapPlayerSearchFiltersWithoutHTTP() {
        let service = makeService(initialState: .init(playerProfilesById: [
            42: OGSPlayerProfile(user: OGSUser(username: "Rin", id: 42)),
            43: OGSPlayerProfile(user: OGSUser(username: "RinGo", id: 43)),
            44: OGSPlayerProfile(user: OGSUser(username: "Other", id: 44)),
        ]))
        var users: [OGSUser] = []
        service.searchByUsername(keyword: "RIN").sink(
            receiveCompletion: {
                if case .failure = $0 { XCTFail("Fixture search must succeed") }
            },
            receiveValue: { users = $0 }
        ).store(in: &cancellables)
        XCTAssertEqual(users.map(\.id), [42, 43])
        XCTAssertTrue(ProfileURLProtocol.recordedRequests.isEmpty)
    }

    func testProfileFromPreviousAuthenticationContextIsDiscarded() throws {
        let started = expectation(description: "old-account profile request started")
        var heldRequest: ProfileURLProtocol?
        ProfileURLProtocol.configure(handler: {
            heldRequest = $0
            started.fulfill()
        })
        let service = makeService()
        let completed = expectation(description: "old-account profile discarded")
        var receivedError: Error?
        service.fetchPlayerProfile(playerId: 42).sink(
            receiveCompletion: {
                if case .failure(let error) = $0 { receivedError = error }
                completed.fulfill()
            },
            receiveValue: { _ in XCTFail("A response from the old account must not be delivered") }
        ).store(in: &cancellables)

        wait(for: [started], timeout: 5)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        service.ogsUIConfig = try decoder.decode(
            OGSUIConfig.self,
            from: Data(#"{"user":{"id":7,"username":"new-account","anonymous":false}}"#.utf8)
        )
        heldRequest?.respond(#"{"user":{"id":42,"username":"player"}}"#)
        wait(for: [completed], timeout: 5)
        guard let receivedError,
              case OGSServiceError.staleAuthenticationContext = receivedError else {
            return XCTFail("Expected the old authentication context to be rejected")
        }
    }

    private func decode(_ json: String) throws -> OGSPlayerProfile {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSPlayerProfile.self, from: Data(json.utf8))
    }

    private func waitForResult(
        _ publisher: AnyPublisher<OGSPlayerProfile, Error>
    ) -> Result<OGSPlayerProfile, Error> {
        let completed = expectation(description: "profile request completed")
        var result: Result<OGSPlayerProfile, Error>?
        publisher.sink(
            receiveCompletion: {
                if case .failure(let error) = $0 { result = .failure(error) }
                completed.fulfill()
            },
            receiveValue: { result = .success($0) }
        ).store(in: &cancellables)
        wait(for: [completed], timeout: 5)
        guard let result else {
            XCTFail("Profile request completed without a value or error")
            return .failure(OGSServiceError.invalidJSON)
        }
        return result
    }

    private func makeService(initialState: OGSService.BootstrapState? = nil) -> OGSService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileURLProtocol.self]
        configuration.httpCookieStorage = nil
        let suite = "com.honganhkhoa.Surround.ProfileTests.\(UUID().uuidString)"
        preferenceSuites.append(suite)
        return OGSService(
            environment: OGSEnvironment(rootURL: URL(string: "https://profile.ogs.test")!),
            httpClient: AlamofireOGSHTTPClient(
                session: Session(configuration: configuration),
                cookieStorage: nil
            ),
            preferences: UserDefaults(suiteName: suite)!,
            ogsWebsocket: OGSOfflineNoOpWebsocket(status: .disconnected),
            connectsAutomatically: false,
            usesSurroundOverviewService: false,
            enablesAppSideEffects: false,
            startsTimers: false,
            installsObservers: false,
            initialState: initialState
        )
    }
}
