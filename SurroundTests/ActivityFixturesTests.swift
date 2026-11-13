//
//  ActivityFixturesTests.swift
//  SurroundTests
//
//  What each `--surround-activity-state` shows, read through the Activity
//  model, and how the states keep their times, data and launch arguments.
//

#if DEBUG
import Combine
import XCTest

final class ActivityFixturesTests: XCTestCase {
    private typealias Fixtures = ActivityFixtures
    private typealias Contract = SurroundUITestContract
    private typealias State = SurroundUITestContract.ActivityFixtureState
    private typealias ID = SurroundUITestContract.ActivityFixtureID
    private let baseID = SurroundUITestContract.fixtureGameID
    private let publicGameID = 25_291_907   // the plain journey's public game
    private let clock = ActivityFixtures.Clock(reference: 1_794_220_920)   // 9 Nov 2026, 10:42 UTC
    private var suites = [String]()

    override func tearDown() {
        suites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        suites.removeAll()
        super.tearDown()
    }

    // MARK: Builders

    private func decodedGame(_ resource: String) throws -> OGSGame {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: resource, withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSGame.self, from: Data(contentsOf: url))
    }

    /// The plain offline journey's start, as `OGSService.offlineUITestInstance()` builds it.
    private func journeyState() throws -> OGSService.BootstrapState {
        var data = try decodedGame("game-26268404")
        data.players.black.username = "OrbitFox"
        data.players.white.username = "PuzzleHeron"
        let game = Game(ogsGame: data)
        game.ogsRawData = [:]
        var state = OGSService.BootstrapState()
        state.user = try XCTUnwrap(game.whitePlayer)
        state.isLoggedIn = true
        state.socketStatus = .connected
        state.isLoadingOverview = false
        state.activeGames[baseID] = game
        state.finishedGamesSnapshot = []
        return state
    }

    private func newSuite() -> String {
        let suite = "com.honganhkhoa.Surround.ActivityFixturesTests.\(UUID().uuidString)"
        suites.append(suite)
        return suite
    }

    /// One window's service in `selected`. Windows of one app share `suite`
    /// and `store`, the app's superchat store; without one, nothing is covered.
    private func service(_ selected: State, clock: Fixtures.Clock? = nil, suite: String? = nil,
                         store: SuperchatStore? = nil, startsSuperchat: Bool = true,
                         actions: Fixtures.Actions? = nil) throws -> (OGSService, Fixtures.Seed) {
        var state = try journeyState()
        let seed = Fixtures.apply(selected, to: &state, clock: clock ?? self.clock)
        state.activityActions = actions
        let service = OGSService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: OGSOfflineRejectingHTTPClient(), preferences: UserDefaults(suiteName: suite ?? newSuite())!,
            ogsWebsocket: OGSOfflineNoOpWebsocket(), connectsAutomatically: false,
            usesSurroundOverviewService: false, enablesAppSideEffects: false, startsTimers: false,
            installsObservers: false, initialState: state)
        service.superchatStore = store
        Fixtures.finish(selected, service: service, startsSuperchat: startsSuperchat)
        return (service, seed)
    }

    private func input(_ ogs: OGSService, _ place: ActivityModel.Place, _ seed: Fixtures.Seed) -> ActivityModel.Input {
        Fixtures.input(ogs, place: place, seed: seed, clock: clock)
    }

    /// A request's one answer, once it comes.
    @discardableResult
    private func answer<Value>(_ reply: AnyPublisher<Value, Error>,
                               file: StaticString = #filePath, line: UInt = #line) throws -> Value {
        let done = expectation(description: "The request answers")
        var result: Result<Value, Error>?
        let subscription = reply.sink(receiveCompletion: { end in
            if case .failure(let error) = end { result = .failure(error) }
            done.fulfill()
        }, receiveValue: { result = .success($0) })
        wait(for: [done], timeout: 5)
        subscription.cancel()
        return try XCTUnwrap(result, "The request answered", file: file, line: line).get()
    }

    /// "no bar", "started game-N", the item's id, or "N waiting".
    private func describe(_ lead: ActivityModel.Lead?) -> String {
        switch lead {
        case .none: return "no bar"
        case .gameStarted(let game): return "started game-\(game.id)"
        case .item(let item): return item.id
        case .waiting(let count): return "\(count) waiting"
        }
    }

    /// "none", "started game-N +K[ dot]", "chip game-N +K[ dot]", "base +K", "dot" or "inbox K".
    private func describe(_ control: ActivityModel.GameControl?) -> String {
        switch control {
        case .none: return "none"
        case let .gameStarted(game, plusN, hasDot): return "started game-\(game.id) +\(plusN)" + (hasDot ? " dot" : "")
        case let .chip(game, plusN, hasDot): return "chip game-\(game.id) +\(plusN)" + (hasDot ? " dot" : "")
        case .base(let plusN): return "base +\(plusN)"
        case .dot: return "dot"
        case .inbox(let count): return "inbox \(count)"
        }
    }

    // MARK: The states

    private struct Expectation {
        var lead: String
        var plusN = 0
        var list: [String]
        var lowTime: Set<Int> = []
        var baseIsLive: Bool
        var baseIsOver = false
        var inGame: String
    }

    /// The designed table. Exhaustive, so a new state can't go unchecked.
    private func expected(_ state: State) -> Expectation {
        let base = "game-26268404", harbor = "game-91004001", chip = "chip game-91004001 +0"
        let started = "game-91004002", removal = "game-91004003"
        let q1 = "waiting-quick-match-\(ID.liveQuickMatchUUID)"
        let q2 = "waiting-quick-match-\(ID.correspondenceQuickMatchUUID)"
        let talks = ["conversation-915100", "conversation-851006", "conversation-916001"]
        switch state {
        case .nothingWaiting:
            return Expectation(lead: "no bar", list: [], baseIsLive: false, inGame: "base +0")
        case .liveYourMove:
            return Expectation(lead: harbor, list: [harbor, base], baseIsLive: true, inGame: chip)
        case .liveTheirMove:
            return Expectation(lead: harbor, list: [harbor], baseIsLive: false, inGame: "base +0")
        case .lowTime:
            return Expectation(lead: harbor, list: [harbor, base], lowTime: [ID.harborMistGameID],
                               baseIsLive: true, inGame: chip)
        case .stoneRemoval:
            return Expectation(lead: removal, list: [removal, base], baseIsLive: true,
                               inGame: "chip game-91004003 +0")
        case .gameStarted:
            return Expectation(lead: "started \(started)", list: [base, started], baseIsLive: true,
                               inGame: "started \(started) +0")
        case .challengeReceived:
            return Expectation(lead: "challenge-95001", list: [base, "challenge-95001"], baseIsLive: true,
                               inGame: "dot")
        case .unusualChallenge:
            return Expectation(lead: "challenge-95002", list: [base, "challenge-95002"], baseIsLive: true,
                               inGame: "dot")
        case .searching:
            return Expectation(lead: q1, list: [q1], baseIsLive: false, inGame: "base +0")
        case .waiting:
            return Expectation(lead: "waiting-open-95101",
                               list: [q2, "waiting-rengo-95301", "waiting-open-95101", q1, "waiting-sent-95201"],
                               baseIsLive: false, inGame: "base +0")
        case .correspondenceYourMove:
            return Expectation(lead: "no bar", list: ["correspondence-games"], baseIsLive: false, inGame: "base +0")
        case .nothingLeads:
            return Expectation(lead: "3 waiting", list: ["challenge-95003"] + talks, baseIsLive: false,
                               inGame: "base +3")
        case .several:
            let list = [harbor, base, "challenge-95001", q2, "waiting-open-95101", q1, "correspondence-games"]
            return Expectation(lead: harbor, plusN: 3, list: list + talks, baseIsLive: true, inGame: chip + " dot")
        case .superchat:
            return Expectation(lead: harbor, plusN: 1, list: [harbor, base, "conversation-916002"],
                               baseIsLive: true, inGame: chip + " dot")
        case .rematchOffered:
            return Expectation(lead: "challenge-95004", list: ["challenge-95004"], baseIsLive: true,
                               baseIsOver: true, inGame: "base +1")
        case .rematchBothAsked:
            return Expectation(lead: "challenge-95004", list: ["challenge-95004", "waiting-sent-95202"],
                               baseIsLive: true, baseIsOver: true, inGame: "base +1")
        }
    }

    private func basePlace(_ state: State) -> ActivityModel.Place {
        let want = expected(state)
        return .game(id: baseID, isOwnGame: true, isLive: want.baseIsLive, isOver: want.baseIsOver)
    }

    func testEveryStateReadsAsDesigned() throws {
        for state in State.allCases {
            let (ogs, seed) = try service(state)
            let want = expected(state)
            let root = ActivityModel.snapshot(input(ogs, .root(isMessagesTab: false), seed))
            XCTAssertEqual(describe(root.lead), want.lead, "\(state)")
            XCTAssertEqual(root.plusN, want.plusN, "\(state)")
            XCTAssertEqual(root.list.map(\.id), want.list, "\(state)")
            XCTAssertEqual(root.lowTimeGameIDs, want.lowTime, "\(state)")
            let base = try XCTUnwrap(ogs.activeGames[baseID], "\(state)")
            XCTAssertEqual(ActivityModel.Place(showing: base), basePlace(state), "\(state)")
            let control = ActivityModel.gameControl(input(ogs, basePlace(state), seed))
            XCTAssertEqual(describe(control), want.inGame, "\(state)")
        }
    }

    // MARK: Times

    func testTimesAreOffsetsFromTheReferenceSecond() throws {
        var lists = [[String]]()
        for reference in [clock.reference, clock.reference + 86_400] {
            let at = Fixtures.Clock(reference: reference)
            let (ogs, seed) = try service(.several, clock: at)
            XCTAssertEqual(ogs.activeGames[ID.harborMistGameID]?.clock?.whiteTime.thinkingTimeLeft, 42)
            XCTAssertEqual(ogs.activeGames[ID.correspondenceGameIDs[0]]?.clock?.whiteTime.thinkingTimeLeft, 80_340)
            XCTAssertEqual(ogs.autoMatchEntryById[ID.liveQuickMatchUUID]?.creationTimestamp, reference - 72)
            XCTAssertEqual(seed.firstSeen["open-\(ID.openChallengeID)"], reference - 220)
            let root = ActivityModel.snapshot(Fixtures.input(ogs, place: .root(isMessagesTab: false), seed: seed,
                                                             clock: at))
            lists.append(root.list.map(\.id))
        }
        XCTAssertEqual(lists[0], lists[1])

        // Stone removal's White has thought 0 s, so its times at the last move stand
        // whatever the wall clock reads, as in a window opened after launch.
        for reference in [clock.reference, Date().timeIntervalSince1970.rounded(.down) - 3_600] {
            let (ogs, _) = try service(.stoneRemoval, clock: Fixtures.Clock(reference: reference))
            let white = try XCTUnwrap(ogs.activeGames[ID.stoneRemovalGameID]?.clock?.whiteTime)
            XCTAssertEqual(white.thinkingTimeLeft, 210)
            XCTAssertEqual(white.periodsLeft, 5)
            XCTAssertEqual(white.periodTimeLeft, 30)
        }
    }

    func testLowTimeIsTheLastByoyomiPeriod() throws {
        let (ogs, _) = try service(.lowTime)
        let game = try XCTUnwrap(ogs.activeGames[ID.harborMistGameID])
        XCTAssertEqual(game.clock?.whiteTime.periodsLeft, 1)
        XCTAssertEqual(game.clock?.whiteTime.periodTimeLeft, 8)
        XCTAssertTrue(GameDetailClockState(game: game, color: .white).suddenDeath)
        XCTAssertEqual(game.timeUntilTimeout(for: .white), 8)
    }

    func testTheStartedLeadEndsAfterThirtySeconds() throws {
        let (ogs, seed) = try service(.gameStarted)
        XCTAssertEqual(clock.now, clock.reference, "A frozen clock stays at the reference.")
        var root = input(ogs, .root(isMessagesTab: false), seed)
        XCTAssertEqual(describe(ActivityModel.snapshot(root).lead), "started game-91004002")
        root.now = clock.reference + 30
        XCTAssertEqual(describe(ActivityModel.snapshot(root).lead), "game-26268404")
    }

    // MARK: Counts and rows

    func testTheCorrespondenceRowOpensTheMostUrgentRunningGame() throws {
        let (ogs, seed) = try service(.correspondenceYourMove)
        let ids = ID.correspondenceGameIDs
        let root = ActivityModel.snapshot(input(ogs, .root(isMessagesTab: false), seed))
        XCTAssertEqual(root.list, [.correspondenceGames(count: 3, mostUrgentID: ids[0])])
        let inG4 = ActivityModel.Place.game(id: ids[0], isOwnGame: true, isLive: false, isOver: false)
        XCTAssertEqual(ActivityModel.snapshot(input(ogs, inG4, seed)).list,
                       [.correspondenceGames(count: 2, mostUrgentID: ids[1])],
                       "The paused game never opens first.")
    }

    func testCountsOnMessagesAndSpectatedGames() throws {
        let (quiet, quietSeed) = try service(.nothingLeads)
        let messages = ActivityModel.snapshot(input(quiet, .root(isMessagesTab: true), quietSeed))
        XCTAssertEqual(describe(messages.lead), "1 waiting")

        let spectated = Game(ogsGame: try decodedGame("game-25291907"))
        spectated.ogs = quiet
        let place = ActivityModel.Place(showing: spectated)
        XCTAssertEqual(place.gameID, publicGameID)
        XCTAssertEqual(describe(ActivityModel.gameControl(input(quiet, place, quietSeed))), "inbox 3")

        let (busy, busySeed) = try service(.several)
        let inG4 = ActivityModel.Place.game(id: ID.correspondenceGameIDs[0], isOwnGame: true, isLive: false,
                                            isOver: false)
        XCTAssertEqual(describe(ActivityModel.gameControl(input(busy, inG4, busySeed))), "chip game-91004001 +3")
    }

    func testTheModeratorChatIsActiveWithAnUnreadConversation() throws {
        let store = SuperchatStore(preferences: nil)
        let (ogs, _) = try service(.superchat, store: store)
        let user = try XCTUnwrap(ogs.user)
        let cover = try XCTUnwrap(store.covers[user.id], "The state covers its user.")
        XCTAssertEqual(cover.moderators.map(\.id), [ID.moderatorID])
        XCTAssertEqual(cover.moderators.first?.username, Fixtures.Cast.moderator.username)
        XCTAssertTrue(cover.isOn)
        XCTAssertEqual(ogs.superchatCover, cover, "The window shows the store's cover.")
        XCTAssertEqual(ogs.privateMessagesUnreadPeerIds, [ID.moderatorID])
        let payload = Fixtures.superchatPayload(for: user, enable: false)
        XCTAssertEqual(payload["player_id"] as? Int, user.id)
        XCTAssertEqual(payload["moderator_id"] as? Int, ID.moderatorID)
        ogs.handleSuperchat(config: payload)
        XCTAssertEqual(store.covers[user.id]?.awaitsDone, true, "The end waits for Done.")
        store.done(accountID: user.id)
        XCTAssertNil(store.covers[user.id])
        XCTAssertNil(ogs.superchatCover)

        // The Debug commands' payloads: the moderator's own echo never covers, and
        // the second moderator, who has no profile, is named from the event.
        let echo = Fixtures.superchatEchoPayload(for: user, enable: true)
        // Well formed for this account, so only the echo rule can turn it away.
        XCTAssertEqual(echo["moderator_id"] as? Int, user.id)
        XCTAssertEqual(echo["player_id"] as? Int, user.id)
        XCTAssertEqual(echo["enable"] as? Bool, true)
        ogs.handleSuperchat(config: echo)
        XCTAssertNil(store.covers[user.id])
        let second = Fixtures.Cast.secondModerator
        XCTAssertFalse(Fixtures.Cast.all.contains(second))
        ogs.handleSuperchat(config: Fixtures.superchatPayload(for: user, enable: true, moderator: second))
        XCTAssertEqual(store.covers[user.id]?.moderators.map(\.id), [ID.secondModeratorID])
        XCTAssertEqual(store.covers[user.id]?.moderators.first?.username, "SentinelHeron")
    }

    /// The app starts the state's superchat in its first window only: later
    /// services join the store as it is.
    func testFinishCanLeaveTheSuperchatAlone() throws {
        let store = SuperchatStore(preferences: nil)
        let (ogs, _) = try service(.superchat, store: store, startsSuperchat: false)
        XCTAssertTrue(store.covers.isEmpty)
        XCTAssertNil(ogs.superchatCover)
        XCTAssertEqual(ogs.privateMessagesUnreadPeerIds, [ID.moderatorID], "The moderator's message is still there.")
    }

    func testRematchDataWaitsForTheLabel() throws {
        let (ogs, seed) = try service(.rematchBothAsked)
        XCTAssertEqual(seed.gameEndTimes[baseID], clock.reference - 90)
        XCTAssertEqual(seed.challengeNotificationTimes[ID.rematchChallengeID], clock.reference - 20)
        XCTAssertEqual(seed.rematchSourceGameIDs[ID.rematchSentChallengeID], baseID)

        let template = try decodedGame("game-26268404")
        let rematch = try XCTUnwrap(ogs.challengesReceived.first { $0.id == ID.rematchChallengeID })
        XCTAssertEqual(rematch.challenger?.username, "OrbitFox")
        XCTAssertEqual(rematch.challenger?.id, template.players.black.id)
        XCTAssertEqual(rematch.game.width, template.width)
        XCTAssertEqual(rematch.game.height, template.height)
        XCTAssertEqual(rematch.game.rules, template.rules)
        XCTAssertEqual(rematch.game.ranked, template.ranked)
        XCTAssertEqual(rematch.game.timeControl.system, template.timeControl.system)
        XCTAssertEqual(rematch.game.handicap, 0)
        XCTAssertFalse(rematch.isUnusual)
        XCTAssertEqual(ogs.challengesSent.map(\.id), [ID.rematchSentChallengeID])
        XCTAssertEqual(ogs.challengesSent.first?.challenged?.id, template.players.black.id)
    }

    // MARK: Windows and the journey

    func testTwoWindowsBuildTheSameState() throws {
        for state in State.allCases {
            // Two windows of one app share its preferences suite and its superchat store.
            let suite = newSuite()
            let store = SuperchatStore(preferences: nil)
            let (first, firstSeed) = try service(state, suite: suite, store: store)
            let (second, secondSeed) = try service(state, suite: suite, store: store)
            XCTAssertEqual(firstSeed, secondSeed, "\(state)")
            // In the superchat state both windows start it; the store holds one moderator.
            let user = try XCTUnwrap(first.user, "\(state)")
            XCTAssertEqual(store.covers[user.id]?.moderators.map(\.id) ?? [],
                           state == .superchat ? [ID.moderatorID] : [], "\(state)")
            XCTAssertEqual(first.superchatCover, store.covers[user.id], "\(state)")
            XCTAssertEqual(second.superchatCover, store.covers[user.id], "\(state)")
            // Inputs list waiting items in dictionary order; snapshots sort them.
            for place in [ActivityModel.Place.root(isMessagesTab: false), basePlace(state)] {
                XCTAssertEqual(ActivityModel.snapshot(input(first, place, firstSeed)),
                               ActivityModel.snapshot(input(second, place, secondSeed)), "\(state) \(place)")
                XCTAssertEqual(ActivityModel.gameControl(input(first, place, firstSeed)),
                               ActivityModel.gameControl(input(second, place, secondSeed)), "\(state) \(place)")
            }
        }
    }

    func testTheJourneysOtherDataStays() throws {
        var state = try journeyState()
        let publicGame = Game(ogsGame: try decodedGame("game-25291907"))
        state.publicGames[publicGameID] = publicGame
        state.sortedPublicGames = [publicGame]
        let friend = OGSUser(username: "RiverWillow", id: 912_001, ranking: 24)
        state.friends = [friend]
        let history = Game(ogsGame: try decodedGame("game-18759438"))   // a finished game
        state.finishedGamesSnapshot = [history]

        for selected in State.allCases {
            var applied = state
            Fixtures.apply(selected, to: &applied, clock: clock)
            XCTAssertEqual(applied.publicGames.count, 1, "\(selected)")
            XCTAssertTrue(applied.publicGames[publicGameID] === publicGame, "\(selected)")
            XCTAssertEqual(applied.sortedPublicGames.map(\.ogsID), [publicGameID], "\(selected)")
            XCTAssertEqual(applied.friends, [friend], "\(selected)")
            XCTAssertEqual(applied.finishedGamesSnapshot?.count, 1, "\(selected)")
            XCTAssertTrue(applied.finishedGamesSnapshot?.first === history, "\(selected)")
            XCTAssertEqual(applied.user, state.user, "\(selected)")
            XCTAssertEqual(applied.socketStatus, .connected, "\(selected)")
            XCTAssertTrue(applied.friendInvitations.isEmpty, "\(selected)")
            for player in Fixtures.Cast.all {
                XCTAssertEqual(applied.cachedUsersById[player.id], player, "\(selected)")
            }
        }
    }

    func testTheBootstrapCarriesSentChallengesAndRengo() {
        let sent = OGSChallengeSampleData.sampleChallenge
        let joined = OGSChallengeSampleData.sampleRengoChallenge
        var hosted = OGSChallengeSampleData.sampleRengoChallenge
        hosted.id += 1
        var state = OGSService.BootstrapState()
        state.challengesSent = [sent]
        state.participatingRengoChallengeById = [joined.id: joined]
        state.hostingRengoChallengeById = [hosted.id: hosted]

        let service = OGSService(previewState: state)
        XCTAssertEqual(service.challengesSent, [sent])
        XCTAssertEqual(service.participatingRengoChallengeById, [joined.id: joined])
        XCTAssertEqual(service.hostingRengoChallengeById, [hosted.id: hosted])
    }

    // MARK: Launch arguments

    func testLaunchArguments() throws {
        let state = SurroundUITestContract.activityStateLaunchArgument
        let clockFlag = SurroundUITestContract.activityClockLaunchArgument
        let connectionFlag = SurroundUITestContract.activityConnectionLaunchArgument
        let ticks = SurroundUITestContract.fixtureClockTicksLaunchArgument
        let reference = clock.reference + 0.75
        func parse(_ arguments: [String]) throws -> Fixtures.Launch? {
            try Fixtures.parse([SurroundUITestContract.launchArgument] + arguments, reference: reference)
        }
        func failure(_ arguments: [String]) -> Fixtures.LaunchError? {
            do {
                _ = try parse(arguments)
                return nil
            } catch {
                return error as? Fixtures.LaunchError
            }
        }

        XCTAssertNil(try parse([]))
        XCTAssertNil(try parse([clockFlag, "running"]), "The clock alone selects nothing.")
        XCTAssertNil(try parse([connectionFlag, "offline"]), "The connection alone selects nothing.")
        XCTAssertEqual(try parse([state, "several"]), Fixtures.Launch(state: .several, clock: clock),
                       "Frozen by default, at the floored reference.")
        XCTAssertEqual(try parse([state, "several"])?.connection, .online, "Online by default.")
        XCTAssertEqual(try parse([state, "superchat", connectionFlag, "offline"]),
                       Fixtures.Launch(state: .superchat, clock: clock, connection: .offline))
        XCTAssertEqual(try parse([state, "superchat", connectionFlag, "online"])?.connection, .online)
        // The Debug script rewrites no data a state owns, so it combines with every state.
        XCTAssertEqual(try parse([state, "superchat", SurroundUITestContract.superchatDebugScriptLaunchArgument,
                                  "end@2,start@4"])?.state, .superchat)
        XCTAssertEqual(try parse([state, "several", clockFlag, "frozen"]), Fixtures.Launch(state: .several, clock: clock))
        for selected in State.allCases {
            XCTAssertEqual(try parse([state, selected.rawValue])?.state, selected)
        }

        XCTAssertEqual(failure([state, "x"]), .unknownState("x"))
        XCTAssertTrue(Fixtures.LaunchError.unknownState("x").description.contains("several"))
        XCTAssertEqual(failure([state]), .missingValue(state))
        XCTAssertEqual(failure([state, "several", clockFlag]), .missingValue(clockFlag))
        XCTAssertEqual(failure([state, "several", clockFlag, "slow"]), .unknownClock("slow"))
        XCTAssertEqual(failure([state, "several", connectionFlag]), .missingValue(connectionFlag))
        XCTAssertEqual(failure([state, "several", connectionFlag, "x"]), .unknownConnection("x"))
        XCTAssertTrue(Fixtures.LaunchError.unknownConnection("x").description.contains("offline"))
        for flag in [SurroundUITestContract.screenshotLaunchArgument,
                     SurroundUITestContract.compatibilityScreenshotLaunchArgument,
                     SurroundUITestContract.homeStatesLaunchArgument] {
            XCTAssertEqual(failure([state, "several", flag]), .cannotCombine(flag))
        }
        XCTAssertEqual(failure([state, "several", ticks]), .cannotCombine(ticks))

        let running = Fixtures.Clock(reference: clock.reference, isFrozen: false)
        XCTAssertEqual(try parse([state, "several", clockFlag, "running", ticks]),
                       Fixtures.Launch(state: .several, clock: running))
    }

    func testTheActivityOpenerNeedsAStateAndAKnownStyle() throws {
        let open = Contract.activityOpenLaunchArgument
        let state = Contract.activityStateLaunchArgument
        func parse(_ arguments: [String]) throws -> Contract.ActivityOpen? {
            try Contract.parseActivityOpen(arguments)
        }
        func failure(_ arguments: [String]) -> Contract.ActivityOpenError? {
            do {
                _ = try parse(arguments)
                return nil
            } catch {
                return error as? Contract.ActivityOpenError
            }
        }

        XCTAssertNil(try parse([]))
        XCTAssertNil(try parse([state, "several"]), "A state alone opens nothing.")
        XCTAssertEqual(try parse([state, "several", open, "sheet"]), .sheet)
        XCTAssertEqual(try parse([open, "sheet", state, "waiting"]), .sheet)
        XCTAssertEqual(try parse([state, "waiting", open, "game-popover"]), .gamePopover)

        XCTAssertEqual(failure([state, "several", open]), .missingValue)
        XCTAssertEqual(failure([state, "several", open, "popover"]), .unknownValue("popover"))
        XCTAssertEqual(failure([open, "sheet"]), .needsActivityState)
        XCTAssertEqual(failure([open, "game-popover"]), .needsActivityState)
        let unknown = Contract.ActivityOpenError.unknownValue("x").description
        XCTAssertTrue(unknown.contains("sheet") && unknown.contains("game-popover"))
    }

    func testTheActionFlagNeedsAStateAndAKnownMode() throws {
        let actions = Contract.activityActionsLaunchArgument
        let state = Contract.activityStateLaunchArgument
        func parse(_ arguments: [String]) throws -> Contract.ActivityActions? {
            try Contract.parseActivityActions(arguments)
        }
        func failure(_ arguments: [String]) -> Contract.ActivityActionsError? {
            do {
                _ = try parse(arguments)
                return nil
            } catch {
                return error as? Contract.ActivityActionsError
            }
        }

        XCTAssertNil(try parse([]))
        XCTAssertNil(try parse([state, "waiting"]), "A state alone leaves its actions to OGS.")
        XCTAssertEqual(try parse([state, "waiting", actions, "succeed"]), .succeed)
        XCTAssertEqual(try parse([actions, "fail-once", state, "challenge-received"]), .failOnce)

        XCTAssertEqual(failure([state, "waiting", actions]), .missingValue)
        XCTAssertEqual(failure([state, "waiting", actions, "fail"]), .unknownValue("fail"))
        XCTAssertEqual(failure([actions, "succeed"]), .needsActivityState)
        let unknown = Contract.ActivityActionsError.unknownValue("x").description
        XCTAssertTrue(unknown.contains("succeed") && unknown.contains("fail-once"))
    }

    func testTheActionFixtureAnswersAsOGSWould() throws {
        let actions = Fixtures.Actions(mode: .succeed, clock: clock, delay: 0)

        // An accepted challenge starts a game, live or correspondence as it is.
        let (received, receivedSeed) = try service(.challengeReceived, actions: actions)
        let usual = try XCTUnwrap(received.challengesReceived.first { $0.id == ID.usualChallengeID })
        let liveID = ID.acceptedGameID(ID.usualChallengeID)
        XCTAssertEqual(liveID, 995_001)
        XCTAssertEqual(try answer(received.acceptChallenge(challenge: usual)), liveID)
        let live = try XCTUnwrap(received.activeGames[liveID])
        XCTAssertTrue(live.ogs === received)
        XCTAssertEqual(live.blackPlayer?.id, Fixtures.Cast.cedarWave.id, "The challenger plays Black.")
        XCTAssertEqual(live.whitePlayer?.id, received.user?.id)
        XCTAssertEqual(live.gameData?.moves.count, 0, "The game has just started.")
        XCTAssertEqual(live.gameData?.timeControl.system, usual.game.timeControl.system)
        XCTAssertTrue(received.liveGames.contains { $0.ogsID == liveID })
        XCTAssertTrue(received.challengesReceived.isEmpty, "The accepted challenge leaves its list.")
        // Both on their move, so by id.
        let list = ActivityModel.snapshot(input(received, .root(isMessagesTab: false), receivedSeed)).list.map(\.id)
        XCTAssertEqual(list, ["game-\(liveID)", "game-\(baseID)"])

        let (leads, _) = try service(.nothingLeads, actions: actions)
        let correspondence = try XCTUnwrap(leads.challengesReceived.first)
        let correspondenceID = ID.acceptedGameID(ID.correspondenceChallengeID)
        XCTAssertEqual(try answer(leads.acceptChallenge(challenge: correspondence)), correspondenceID)
        XCTAssertTrue(leads.sortedActiveCorrespondenceGamesNotOnUserTurn.contains { $0.ogsID == correspondenceID },
                      "The challenger moves first.")
        XCTAssertFalse(leads.liveGames.contains { $0.ogsID == correspondenceID })

        // Withdrawn and rejected challenges leave their lists; the pill counts what's left.
        let (waiting, _) = try service(.waiting, actions: actions)
        XCTAssertEqual(waiting.waitingLiveGames, 3)
        let open = try XCTUnwrap(waiting.openChallengeSentById[ID.openChallengeID])
        try answer(waiting.withdrawOrDeclineChallenge(challenge: open))
        let sent = try XCTUnwrap(waiting.challengesSent.first)
        try answer(waiting.withdrawOrDeclineChallenge(challenge: sent))
        XCTAssertNil(waiting.openChallengeSentById[ID.openChallengeID])
        XCTAssertTrue(waiting.challengesSent.isEmpty)
        XCTAssertEqual(waiting.waitingLiveGames, 1, "Only the live search is left.")
        XCTAssertEqual(waiting.autoMatchEntryById.count, 2, "Searches are withdrawn over the socket.")

        let (rejecting, _) = try service(.unusualChallenge, actions: actions)
        try answer(rejecting.withdrawOrDeclineChallenge(challenge: try XCTUnwrap(rejecting.challengesReceived.first)))
        XCTAssertTrue(rejecting.challengesReceived.isEmpty)
    }

    func testFailOnceFailsEachChallengesFirstAction() throws {
        let (waiting, _) = try service(.waiting, actions: Fixtures.Actions(mode: .failOnce, clock: clock, delay: 0))
        let open = try XCTUnwrap(waiting.openChallengeSentById[ID.openChallengeID])
        XCTAssertThrowsError(try answer(waiting.withdrawOrDeclineChallenge(challenge: open)))
        XCTAssertNotNil(waiting.openChallengeSentById[ID.openChallengeID], "A failure changes nothing.")
        try answer(waiting.withdrawOrDeclineChallenge(challenge: open))
        XCTAssertNil(waiting.openChallengeSentById[ID.openChallengeID], "The next try goes through.")
        let sent = try XCTUnwrap(waiting.challengesSent.first)
        XCTAssertThrowsError(try answer(waiting.withdrawOrDeclineChallenge(challenge: sent)), "Each challenge fails once.")

        let (received, _) = try service(.challengeReceived, actions: Fixtures.Actions(mode: .failOnce, clock: clock, delay: 0))
        let usual = try XCTUnwrap(received.challengesReceived.first)
        XCTAssertThrowsError(try answer(received.acceptChallenge(challenge: usual)))
        XCTAssertNil(received.activeGames[ID.acceptedGameID(usual.id)])
        XCTAssertEqual(try answer(received.acceptChallenge(challenge: usual)), ID.acceptedGameID(usual.id))

        // Without the flag, the offline service fails at once, as before.
        let (plain, _) = try service(.challengeReceived)
        XCTAssertThrowsError(try answer(plain.acceptChallenge(challenge: try XCTUnwrap(plain.challengesReceived.first))))
        XCTAssertEqual(plain.challengesReceived.count, 1)
    }

    func testTheWaitingPillCountsEachStatesLiveSearchesAndChallenges() throws {
        // As the observer counts them: sent and open challenges and Quick
        // Match searches that aren't correspondence. Rengo doesn't count.
        let expected: [State: Int] = [.searching: 1, .waiting: 3, .several: 2, .rematchBothAsked: 1]
        for state in State.allCases {
            let (service, _) = try service(state)
            XCTAssertEqual(service.waitingLiveGames, expected[state] ?? 0, state.rawValue)
        }
    }

    func testActivityIdentifiersTakeTheItemsID() {
        typealias ID = SurroundUITestContract.AccessibilityID
        XCTAssertEqual(ID.activityRow("challenge-95001"), "activity.row.challenge-95001")
        XCTAssertEqual(ID.activityRow("waiting-open-95101", .withdraw), "activity.row.waiting-open-95101.withdraw")
        XCTAssertEqual(ID.activityRow("challenge-95003", .openGame), "activity.row.challenge-95003.openGame")
        XCTAssertEqual(ID.activityRowResult("challenge-95003"), "activity.row.challenge-95003.result")
        XCTAssertEqual(ID.activitySection("waiting"), "activity.section.waiting")
        XCTAssertEqual([ID.activityList, ID.activityEmpty, ID.activityAllMessages, ID.activityDone],
                       ["activity.list", "activity.empty", "activity.allMessages", "activity.done"])
    }
}
#endif
