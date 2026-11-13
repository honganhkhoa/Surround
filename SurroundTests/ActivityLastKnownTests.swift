//
//  ActivityLastKnownTests.swift
//  SurroundTests
//
//  Activity's copy of the user's own open challenges and Rengo challenges,
//  through a real OGSService and a fake socket: the copy outlives
//  `surround/socketClosed`, which clears the service's own rows, and the
//  next seek graph update replaces it.
//

import Alamofire
import Combine
import XCTest

final class ActivityLastKnownTests: XCTestCase {
    /// The socket as OGSService sees it: the test opens, authenticates and
    /// drops it, and delivers server events.
    private final class FakeWebsocket: OGSWebsocketProtocol {
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

        /// The transport opens, then authentication is sent.
        func open() {
            opened = true
            status = .connected
            onStatusChanged?()
            deliver(name: "surround/socketOpened")
            authenticated = true
            deliver(name: "surround/socketAuthenticated")
        }

        /// As OGSWebsocket drops a connection: the flags go first, then the
        /// status, then `surround/socketClosed`.
        func drop() {
            opened = false
            authenticated = false
            status = .reconnecting
            onStatusChanged?()
            deliver(name: "surround/socketClosed")
        }

        func deliver(name: String, data: Any? = nil) {
            serverEventCallback?(name, data)
        }
    }

    /// Holds the copy's reconnect grace until the test fires it.
    private final class GraceScheduler: OGSWebsocketScheduling {
        private(set) var delays = [TimeInterval]()
        private var blocks = [() -> Void]()
        func async(_ block: @escaping () -> Void) { block() }
        func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
            delays.append(delay)
            blocks.append(block)
            let index = blocks.count - 1
            return AnyCancellable { [weak self] in self?.blocks[index] = {} }
        }
        func scheduleRepeating(every interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
            AnyCancellable {}
        }
        func fire() {
            let pending = blocks
            blocks = blocks.map { _ in {} }
            pending.forEach { $0() }
        }
    }

    /// Never runs the open live challenge keepalive.
    private final class IdleScheduler: OGSWebsocketScheduling {
        func async(_ block: @escaping () -> Void) { block() }
        func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable { AnyCancellable {} }
        func scheduleRepeating(every interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
            AnyCancellable {}
        }
    }

    private let user = OGSUser(username: "current", id: 1, rank: 25)
    private var preferenceSuites = [String]()

    override func tearDown() {
        preferenceSuites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        preferenceSuites.removeAll()
        super.tearDown()
    }

    // MARK: Builders

    private func makeService(
        socket: OGSWebsocketProtocol,
        initialState: OGSService.BootstrapState? = nil
    ) -> OGSService {
        let suite = "com.honganhkhoa.Surround.ActivityLastKnownTests.\(UUID().uuidString)"
        preferenceSuites.append(suite)
        return OGSService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: OGSOfflineRejectingHTTPClient(),
            preferences: UserDefaults(suiteName: suite)!,
            ogsWebsocket: socket,
            connectsAutomatically: false,
            usesSurroundOverviewService: false,
            enablesAppSideEffects: false,
            startsTimers: false,
            installsObservers: false,
            keepAliveScheduler: IdleScheduler(),
            initialState: initialState
        )
    }

    /// A signed-in service on an open, authenticated socket, subscribed to
    /// the seek graph.
    private func connectedService() -> (OGSService, FakeWebsocket) {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        service.user = user
        socket.open()
        drainMainQueue()
        XCTAssertEqual(service.socketStatus, .connected)
        service.subscribeToSeekGraph()
        return (service, socket)
    }

    /// The service hears of a status change one main-queue turn later.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
    }

    private func seekGraphChallenge(
        _ id: Int, challengerID: Int, rengoParticipants: [Int]? = nil
    ) -> [String: Any] {
        [
            "challenge_id": id,
            "user_id": challengerID,
            "username": "player-\(challengerID)",
            "rank": 25.0,
            "min_rank": 5,
            "max_rank": 38,
            "game_id": id + 1_000,
            "name": "Last known",
            "ranked": false,
            "handicap": 0,
            "komi": NSNull(),
            "rules": "japanese",
            "width": 9,
            "height": 9,
            "challenger_color": "black",
            "disable_analysis": false,
            "time_control_parameters": [
                "per_move": 20,
                "pause_on_weekends": false,
                "speed": "live",
                "system": "simple",
                "time_control": "simple",
            ],
            "rengo": rengoParticipants != nil,
            "rengo_nominees": [],
            "rengo_black_team": [],
            "rengo_white_team": [],
            "rengo_participants": rengoParticipants ?? [],
            "rengo_casual_mode": false,
            "rengo_auto_start": 0,
        ]
    }

    private func keys(_ dictionary: [Int: OGSSeekgraphChallenge]) -> Set<Int> {
        Set(dictionary.keys)
    }

    // MARK: Tests

    func testTheCopyOutlivesAClosedSocketAndTheNextSeekGraphReplacesIt() {
        let (service, socket) = connectedService()
        let lastKnown = ActivityLastKnown()
        lastKnown.attach(ogs: service)
        socket.deliver(name: "seekgraph/global", data: [
            seekGraphChallenge(51, challengerID: 1),
            seekGraphChallenge(61, challengerID: 2, rengoParticipants: [1, 2]),
            seekGraphChallenge(62, challengerID: 1, rengoParticipants: [1, 3]),
        ])
        let listed = lastKnown.copy
        XCTAssertEqual(keys(listed.openChallengeSentById), [51])
        XCTAssertEqual(keys(listed.participatingRengoChallengeById), [61, 62])
        XCTAssertEqual(keys(listed.hostingRengoChallengeById), [62])
        XCTAssertEqual(lastKnown.openChallenges(live: service), listed)

        socket.drop()
        XCTAssertTrue(service.openChallengeSentById.isEmpty, "Closing the socket clears the service's own rows.")
        XCTAssertTrue(service.participatingRengoChallengeById.isEmpty)
        XCTAssertEqual(service.socketStatus, .connected, "The service hears of the close a turn later.")
        XCTAssertEqual(lastKnown.copy, listed, "The rows went while the status still said connected.")
        XCTAssertEqual(lastKnown.openChallenges(live: service), listed)
        drainMainQueue()
        XCTAssertEqual(service.socketStatus, .reconnecting)
        XCTAssertEqual(lastKnown.copy, listed)
        XCTAssertEqual(lastKnown.openChallenges(live: service), listed, "Offline, Activity lists the copy.")

        socket.open()
        drainMainQueue()
        XCTAssertEqual(service.socketStatus, .connected)
        socket.deliver(name: "seekgraph/global", data: [seekGraphChallenge(52, challengerID: 1)])
        XCTAssertEqual(keys(lastKnown.copy.openChallengeSentById), [52],
                       "The first seek graph update after reconnecting replaces the copy.")
        XCTAssertTrue(lastKnown.copy.participatingRengoChallengeById.isEmpty)
        XCTAssertTrue(lastKnown.copy.hostingRengoChallengeById.isEmpty)
        XCTAssertEqual(lastKnown.openChallenges(live: service), lastKnown.copy)
    }

    func testAfterReconnectingTheCopyStandsInUntilTheSeekGraphListsAgain() {
        let (service, socket) = connectedService()
        let scheduler = GraceScheduler()
        let lastKnown = ActivityLastKnown(scheduler: scheduler)
        lastKnown.attach(ogs: service)
        socket.deliver(name: "seekgraph/global", data: [seekGraphChallenge(71, challengerID: 1)])
        let listed = lastKnown.copy
        XCTAssertEqual(keys(listed.openChallengeSentById), [71])

        socket.drop()
        drainMainQueue()
        XCTAssertTrue(lastKnown.awaitsUpdate)
        socket.open()
        drainMainQueue()
        XCTAssertEqual(service.socketStatus, .connected)
        XCTAssertTrue(service.openChallengeSentById.isEmpty, "The service lists nothing before the seek graph's update.")
        XCTAssertEqual(lastKnown.openChallenges(live: service), listed, "The copy stands in until then.")
        XCTAssertEqual(scheduler.delays, [ActivityLastKnown.reconnectGrace])

        scheduler.fire()
        XCTAssertFalse(lastKnown.awaitsUpdate)
        XCTAssertEqual(lastKnown.openChallenges(live: service), ActivityLastKnown.OpenChallenges(),
                       "With no update in time, Activity lists what the service lists.")
    }

    func testTheSeekGraphsFirstUpdateAfterReconnectingEndsTheGrace() {
        let (service, socket) = connectedService()
        let scheduler = GraceScheduler()
        let lastKnown = ActivityLastKnown(scheduler: scheduler)
        lastKnown.attach(ogs: service)
        socket.deliver(name: "seekgraph/global", data: [seekGraphChallenge(72, challengerID: 1)])
        socket.drop()
        drainMainQueue()
        socket.open()
        drainMainQueue()
        socket.deliver(name: "seekgraph/global", data: [seekGraphChallenge(73, challengerID: 1)])
        XCTAssertFalse(lastKnown.awaitsUpdate)
        XCTAssertEqual(keys(lastKnown.openChallenges(live: service).openChallengeSentById), [73])
        scheduler.fire()
        XCTAssertEqual(keys(lastKnown.openChallenges(live: service).openChallengeSentById), [73],
                       "A grace that already ended changes nothing.")
    }

    func testWhileConnectedEachChangeReplacesTheCopy() {
        let (service, socket) = connectedService()
        let lastKnown = ActivityLastKnown()
        lastKnown.attach(ogs: service)
        socket.deliver(name: "seekgraph/global", data: [
            seekGraphChallenge(53, challengerID: 1),
            seekGraphChallenge(54, challengerID: 1),
            seekGraphChallenge(55, challengerID: 2),
        ])
        XCTAssertEqual(keys(lastKnown.copy.openChallengeSentById), [53, 54], "Only the user's own challenges.")
        socket.deliver(name: "seekgraph/global", data: [["challenge_id": 53, "delete": 1]])
        XCTAssertEqual(keys(lastKnown.copy.openChallengeSentById), [54])
    }

    func testAttachingWhileOfflineKeepsWhatTheServiceLists() {
        var state = OGSService.BootstrapState()
        state.user = user
        state.isLoggedIn = true
        state.socketStatus = .reconnecting
        var challenge = OGSChallengeSampleData.sampleOpenChallenge
        challenge.id = 56
        state.openChallengeSentById[challenge.id] = challenge
        let service = makeService(socket: OGSOfflineNoOpWebsocket(status: .reconnecting), initialState: state)

        let lastKnown = ActivityLastKnown()
        lastKnown.attach(ogs: service)
        XCTAssertEqual(keys(lastKnown.copy.openChallengeSentById), [56], "What the service has is the best known.")
        XCTAssertEqual(lastKnown.openChallenges(live: service), lastKnown.copy)
    }

    func testResetForgetsTheCopy() {
        let (service, socket) = connectedService()
        let lastKnown = ActivityLastKnown()
        lastKnown.attach(ogs: service)
        socket.deliver(name: "seekgraph/global", data: [seekGraphChallenge(57, challengerID: 1)])
        socket.drop()
        drainMainQueue()
        XCTAssertEqual(keys(lastKnown.openChallenges(live: service).openChallengeSentById), [57])

        lastKnown.reset()
        XCTAssertEqual(lastKnown.copy, ActivityLastKnown.OpenChallenges())
        XCTAssertEqual(lastKnown.openChallenges(live: service), ActivityLastKnown.OpenChallenges(),
                       "A new account starts with nothing known.")
    }
}
