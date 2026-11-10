//
//  ActivityFixtures.swift
//  Surround
//
//  Opt-in offline states for Activity, the moderator cover and rematches:
//  `--surround-ui-testing --surround-activity-state <state>` (TESTING.md).
//  Every time is an offset from one reference second shared by all windows,
//  so a state reads the same in every run.
//

import Foundation

#if DEBUG
enum ActivityFixtures {
    typealias State = SurroundUITestContract.ActivityFixtureState
    private typealias Contract = SurroundUITestContract
    private typealias ID = SurroundUITestContract.ActivityFixtureID

    // MARK: Time

    struct Clock: Equatable {
        var reference: TimeInterval   // a whole second; every fixture time is an offset from it
        var isFrozen = true           // frozen: `now` stays at `reference`; running: the wall clock
        var now: TimeInterval { isFrozen ? reference : Date().timeIntervalSince1970 }
        func ago(_ seconds: TimeInterval) -> TimeInterval { reference - seconds }
    }

    /// What Activity's caller adds to OGSService state, and data the rematch
    /// label needs that Surround doesn't decode or record yet.
    struct Seed: Equatable {
        var startedGames: [Int: TimeInterval] = [:]
        var firstSeen: [String: TimeInterval] = [:]   // keyed by ActivityModel.Waiting.id
        var sessionStart: TimeInterval = 0
        var challengeNotificationTimes: [Int: TimeInterval] = [:]
        var gameEndTimes: [Int: TimeInterval] = [:]
        var rematchSourceGameIDs: [Int: Int] = [:]    // sent challenge → the game whose Rematch made it
    }

    static func input(_ ogs: OGSService, place: ActivityModel.Place, seed: Seed,
                      clock: Clock) -> ActivityModel.Input {
        ActivityModel.Input(ogs: ogs, place: place, startedGames: seed.startedGames,
                            firstSeen: seed.firstSeen, sessionStart: seed.sessionStart, now: clock.now)
    }

    // MARK: Launch arguments

    struct Launch: Equatable { var state: State; var clock: Clock }

    enum LaunchError: Error, Equatable, CustomStringConvertible {
        case missingValue(String), unknownState(String), unknownClock(String), cannotCombine(String)

        var description: String {
            switch self {
            case .missingValue(let flag): "\(flag) needs a value."
            case .unknownState(let raw):
                "Unknown Activity state '\(raw)'. Use one of: " + State.allCases.map(\.rawValue).joined(separator: ", ")
            case .unknownClock(let raw): "Unknown Activity clock '\(raw)'. Use frozen or running."
            case .cannotCombine(let flag): "\(Contract.activityStateLaunchArgument) can't be combined with \(flag)."
            }
        }
    }

    /// Captures, other roots, and flags that rewrite the data a state owns.
    static let conflictingArguments: [String] = [
        Contract.screenshotLaunchArgument, Contract.compatibilityScreenshotLaunchArgument,
        Contract.appReviewPresentationLaunchArgument,
        Contract.homeStatesLaunchArgument, Contract.homeFinishedOnlyLaunchArgument,
        Contract.liveGameBannerNavigationLaunchArgument, Contract.widgetDeepLinkRoutingLaunchArgument,
        Contract.emptyMessagesLaunchArgument, Contract.messagesContentLaunchArgument,
        Contract.messagesMarketingLaunchArgument, Contract.messagesOverflowLaunchArgument,
        Contract.messagesShortHistoryLaunchArgument, Contract.messagesDelayedHistoryLaunchArgument,
        Contract.messagesIncomingLaunchArgument, Contract.messagesLoadingLaunchArgument,
    ]

    /// Nil without `--surround-activity-state`. The reference is floored to a second.
    static func parse(_ arguments: [String], reference: TimeInterval) throws -> Launch? {
        func value(after flag: String) throws -> String? {
            guard let index = arguments.firstIndex(of: flag) else { return nil }
            guard arguments.indices.contains(index + 1) else { throw LaunchError.missingValue(flag) }
            return arguments[index + 1]
        }
        guard let raw = try value(after: Contract.activityStateLaunchArgument) else { return nil }
        guard let state = State(rawValue: raw) else { throw LaunchError.unknownState(raw) }
        var isFrozen = true
        if let rawClock = try value(after: Contract.activityClockLaunchArgument) {
            guard let mode = Contract.ActivityFixtureClock(rawValue: rawClock) else {
                throw LaunchError.unknownClock(rawClock)
            }
            isFrozen = mode == .frozen
        }
        if let flag = conflictingArguments.first(where: { arguments.contains($0) }) {
            throw LaunchError.cannotCombine(flag)
        }
        if isFrozen, arguments.contains(Contract.fixtureClockTicksLaunchArgument) {
            throw LaunchError.cannotCombine(Contract.fixtureClockTicksLaunchArgument)
        }
        return Launch(state: state, clock: Clock(reference: reference.rounded(.down), isFrozen: isFrozen))
    }

    // MARK: Building

    /// Applies `selected` to the plain offline journey's bootstrap state
    /// (`OGSService.offlineUITestInstance()`: game 26268404, the user as White).
    @discardableResult
    static func apply(_ selected: State, to state: inout OGSService.BootstrapState,
                      clock: Clock) -> Seed {
        var build = Builder(state: state, clock: clock)
        switch selected {
        case .nothingWaiting: build.baseGame(.correspondenceTheirMove)
        case .liveYourMove: build.baseGame(.liveTheirMove); build.harborMist(.yourMove)
        case .liveTheirMove: build.baseGame(.correspondenceTheirMove); build.harborMist(.theirMove)
        case .lowTime: build.baseGame(.liveTheirMove); build.harborMist(.lastPeriod)
        case .stoneRemoval: build.baseGame(.liveTheirMove); build.stoneRemoval()
        case .gameStarted: build.baseGame(.liveTheirMove); build.startedGame()
        case .challengeReceived: build.baseGame(.liveTheirMove); build.receive(.usual)
        case .unusualChallenge: build.baseGame(.liveTheirMove); build.receive(.unusual)
        case .searching: build.baseGame(.correspondenceTheirMove); build.quickMatch(.live)
        case .waiting:
            build.baseGame(.correspondenceTheirMove)
            build.quickMatch(.live); build.quickMatch(.correspondence)
            build.openChallenge(); build.send(.quietPine); build.joinRengo()
        case .correspondenceYourMove: build.baseGame(.correspondenceTheirMove); build.correspondenceGames()
        case .nothingLeads:
            build.baseGame(.correspondenceTheirMove); build.receive(.correspondence); build.conversations()
        case .several:
            build.baseGame(.liveTheirMove); build.harborMist(.yourMove); build.receive(.usual)
            build.quickMatch(.live); build.quickMatch(.correspondence); build.openChallenge()
            build.correspondenceGames(); build.conversations()
        case .superchat: build.baseGame(.liveTheirMove); build.harborMist(.yourMove); build.moderatorMessage()
        case .rematchOffered: build.baseGame(.finished); build.receive(.rematch)
        case .rematchBothAsked: build.baseGame(.finished); build.receive(.rematch); build.send(.rematch)
        }
        state = build.state
        return build.seed
    }

    /// After the service exists: read markers, then the moderator's superchat.
    static func finish(_ selected: State, service: OGSService) {
        // No-ops where the state has no such conversation.
        service.markPrivateMessageThreadAsRead(peerId: Cast.mossLantern.id)
        service.markPrivateMessageThreadAsRead(peerId: Cast.cedarWave.id)
        if selected == .superchat, let user = service.user {
            service.handleSuperchat(config: superchatPayload(for: user, enable: true))
        }
    }

    /// OGS's `private-superchat` event, as Goban's ServerToClient protocol declares it.
    static func superchatPayload(for user: OGSUser, enable: Bool) -> [String: Any] {
        ["moderator_id": Cast.moderator.id, "moderator_username": Cast.moderator.username,
         "player_id": user.id, "player_username": user.username, "enable": enable]
    }

    /// Names, ids and ranks as AppStoreScreenshotProfileData's in
    /// OGSService+Fixtures.swift, plus the design fixture's tenuki_tom.
    enum Cast {
        static let cedarWave = OGSUser(username: "CedarWave", id: 851_001, ranking: 25.629_229_229_465_31)
        static let jadeLantern = OGSUser(username: "JadeLantern", id: 851_002, ranking: 30.959_438_736_382_154)
        static let harborMist = OGSUser(username: "HarborMist", id: 851_003, ranking: 30.953_150_119_443_812)
        static let quietPine = OGSUser(username: "QuietPine", id: 851_006, ranking: 25.887_438_469_018_903)
        static let amberKite = OGSUser(username: "AmberKite", id: 851_009, ranking: 30.809_786_803_592_292)
        static let indigoCrane = OGSUser(username: "IndigoCrane", id: 851_011, ranking: 28.105_412_404_704_705)
        static let mapleRidge = OGSUser(username: "MapleRidge", id: 851_012, ranking: 27.088_590_439_774_116)
        static let tenukiTom = OGSUser(username: "tenuki_tom", id: 915_100, ranking: 32)
        static let mossLantern = OGSUser(username: "MossLantern", id: 916_001, ranking: 27)
        static let moderator = OGSUser(username: "WardenKestrel", id: SurroundUITestContract.ActivityFixtureID.moderatorID,
                                       ranking: 29, uiClass: "moderator", isModerator: true)
        static let all = [cedarWave, jadeLantern, harborMist, quietPine, amberKite, indigoCrane,
                          mapleRidge, tenukiTom, mossLantern, moderator]
    }

    private struct Builder {
        var state: OGSService.BootstrapState
        var seed: Seed
        let clock: Clock
        let user: OGSUser
        /// Game 26268404 as the journey built it.
        let template: OGSGame

        static let liveFischer = TimeControlSystem.Fischer(initialTime: 1_800, timeIncrement: 30, maxTime: 1_800)
        static let liveByoyomi = TimeControlSystem.ByoYomi(mainTime: 600, periods: 5, periodTime: 30)
        static let correspondence = TimeControlSystem.Fischer(initialTime: 259_200, timeIncrement: 86_400,
                                                              maxTime: 604_800)

        enum BaseRole { case liveTheirMove, correspondenceTheirMove, finished }
        enum Turn { case yourMove, theirMove, lastPeriod }
        enum Received { case usual, unusual, correspondence, rematch }
        enum Sent { case quietPine, rematch }
        enum Search { case live, correspondence }

        init(state: OGSService.BootstrapState, clock: Clock) {
            guard let user = state.user,
                  let template = state.activeGames[SurroundUITestContract.fixtureGameID]?.gameData,
                  template.players.white.id == user.id else {
                preconditionFailure("Activity states build on the offline journey: game 26268404, the user as White.")
            }
            self.state = state
            self.clock = clock
            self.user = user
            self.template = template
            seed = Seed(sessionStart: clock.ago(3_600))
            for player in Cast.all { self.state.cachedUsersById[player.id] = player }
        }

        /// 26268404 against OrbitFox, on its own 30 min Fischer clock or on a
        /// correspondence one.
        mutating func baseGame(_ role: BaseRole) {
            let id = Contract.fixtureGameID
            switch role {
            case .liveTheirMove:      // OrbitFox 4:05, you 12:34
                addGame(id, vs: nil, Self.liveFischer, toMove: .black,
                        black: fischer(251), white: fischer(754), thinking: 6)
            case .finished:           // you won by resignation 90 s ago
                addGame(id, vs: nil, Self.liveFischer, toMove: .black,
                        black: fischer(251), white: fischer(754), thinking: 6, phase: .finished)
                seed.gameEndTimes[id] = clock.ago(90)
            case .correspondenceTheirMove:   // OrbitFox 2d 3h, you 4d 1h
                addGame(id, vs: nil, Self.correspondence, toMove: .black,
                        black: fischer(201_600), white: fischer(349_200), thinking: 18_000)
            }
        }

        mutating func harborMist(_ turn: Turn) {
            let id = ID.harborMistGameID
            switch turn {
            case .yourMove:      // 0:42 of main time, then 5×30 s
                addGame(id, vs: Cast.harborMist, Self.liveByoyomi, toMove: .white,
                        black: byoyomi(238, periods: 5), white: byoyomi(60, periods: 5), thinking: 18)
            case .theirMove:     // HarborMist has 3:10 of main time
                addGame(id, vs: Cast.harborMist, Self.liveByoyomi, toMove: .black,
                        black: byoyomi(197, periods: 5), white: byoyomi(495, periods: 5), thinking: 7)
            case .lastPeriod:    // 22 s into the last 30 s period: 0:08 left
                addGame(id, vs: Cast.harborMist, Self.liveByoyomi, toMove: .white,
                        black: byoyomi(0, periods: 3), white: byoyomi(0, periods: 1), thinking: 22)
            }
        }

        /// CedarWave to play on an empty board, 5 s after the game started.
        mutating func startedGame() {
            let id = ID.startedGameID
            addGame(id, vs: Cast.cedarWave, Self.liveByoyomi, toMove: .black,
                    black: byoyomi(600, periods: 5), white: byoyomi(600, periods: 5), thinking: 5,
                    emptyBoard: true)
            seed.startedGames[id] = clock.ago(5)
        }

        /// A stone removal the user hasn't accepted.
        mutating func stoneRemoval() {
            addGame(ID.stoneRemovalGameID, vs: Cast.mapleRidge, Self.liveByoyomi, toMove: .white,
                    black: byoyomi(130, periods: 5), white: byoyomi(210, periods: 5), thinking: 0,
                    phase: .stoneRemoval)
        }

        /// Your move in three: 22h 19m, 2d 3h, and 1d 2h paused for the weekend.
        mutating func correspondenceGames() {
            let ids = ID.correspondenceGameIDs
            addGame(ids[0], vs: Cast.indigoCrane, Self.correspondence, toMove: .white,
                    black: fischer(205_200), white: fischer(91_140), thinking: 10_800)
            addGame(ids[1], vs: Cast.quietPine, Self.correspondence, toMove: .white,
                    black: fischer(259_200), white: fischer(190_800), thinking: 7_200)
            addGame(ids[2], vs: Cast.jadeLantern, Self.correspondence, toMove: .white,
                    black: fischer(172_800), white: fischer(93_600), thinking: 0, paused: true)
        }

        mutating func receive(_ kind: Received) {
            let challenge: OGSDirectChallenge
            switch kind {
            case .usual:
                challenge = direct(ID.usualChallengeID, from: Cast.cedarWave, to: user, Self.liveByoyomi, ranked: true)
            case .unusual:   // 0.5 komi under Japanese rules is custom komi (OGSChallenge.useCustomKomi)
                challenge = direct(ID.unusualChallengeID, from: Cast.jadeLantern, to: user,
                                   .ByoYomi(mainTime: 300, periods: 3, periodTime: 20), ranked: false, komi: 0.5)
            case .correspondence:
                challenge = direct(ID.correspondenceChallengeID, from: Cast.cedarWave, to: user,
                                   Self.correspondence, ranked: true)
            case .rematch:
                challenge = direct(ID.rematchChallengeID, from: template.players.black, to: user, Self.liveFischer,
                                   ranked: template.ranked, rules: template.rules, komi: nil)
                seed.challengeNotificationTimes[challenge.id] = clock.ago(20)
            }
            state.challengesReceived.append(challenge)
        }

        mutating func send(_ kind: Sent) {
            let challenge: OGSDirectChallenge
            switch kind {
            case .quietPine:     // sent 45 s ago
                challenge = direct(ID.sentChallengeID, from: user, to: Cast.quietPine, Self.liveByoyomi, ranked: true)
                seed.firstSeen["sent-\(challenge.id)"] = clock.ago(45)
            case .rematch:       // sent from 26268404's Rematch button 30 s ago
                challenge = direct(ID.rematchSentChallengeID, from: user, to: template.players.black,
                                   Self.liveFischer, ranked: template.ranked, rules: template.rules, komi: nil)
                seed.firstSeen["sent-\(challenge.id)"] = clock.ago(30)
                seed.rematchSourceGameIDs[challenge.id] = Contract.fixtureGameID
            }
            state.challengesSent.append(challenge)
        }

        mutating func quickMatch(_ search: Search) {
            let entry: OGSAutomatchEntry
            switch search {
            case .live:              // searching for 1:12
                entry = OGSAutomatchEntry(
                    sizeSpeedOptions: [OGSAutomatchSizeSpeedOption(size: 19, speed: .live, system: .byoyomi)],
                    uuid: ID.liveQuickMatchUUID, creationTimestamp: clock.ago(72))
            case .correspondence:    // searching for 1 h
                entry = OGSAutomatchEntry(
                    sizeSpeedOptions: [OGSAutomatchSizeSpeedOption(size: 19, speed: .correspondence, system: .fischer),
                                       OGSAutomatchSizeSpeedOption(size: 13, speed: .correspondence, system: .fischer)],
                    uuid: ID.correspondenceQuickMatchUUID, creationTimestamp: clock.ago(3_600))
            }
            state.autoMatchEntryById[entry.uuid] = entry
        }

        /// The user's live 9×9 open challenge, open for 3:40.
        mutating func openChallenge() {
            var challenge = OGSChallengeSampleData.sampleOpenChallenge   // byo-yomi, tagged live
            challenge.id = ID.openChallengeID
            challenge.challenger = user
            challenge.game.id = ID.openChallengeID + 10_000
            challenge.game.width = 9
            challenge.game.height = 9
            state.openChallengeSentById[challenge.id] = challenge
            seed.firstSeen["open-\(challenge.id)"] = clock.ago(220)
        }

        /// AmberKite's casual correspondence Rengo, which the user joined 10 min ago.
        mutating func joinRengo() {
            var challenge = OGSChallengeSampleData.sampleRengoChallenge
            challenge.id = ID.rengoChallengeID
            challenge.challenger = Cast.amberKite
            challenge.game.id = ID.rengoChallengeID + 10_000
            challenge.game.rengoNominees = [user.id]
            challenge.game.rengoWhiteTeam = [Cast.amberKite.id]
            challenge.game.rengoParticipants = [Cast.amberKite.id, user.id]
            state.participatingRengoChallengeById[challenge.id] = challenge
            seed.firstSeen["rengo-\(challenge.id)"] = clock.ago(600)
        }

        /// Two unread, then two read: MossLantern in this session and
        /// CedarWave 25 h ago, before it (`ActivityFixtures.finish` reads them).
        mutating func conversations() {
            message(from: Cast.tenukiTom, "gg! Rematch tomorrow?", ago: 120)
            message(from: Cast.quietPine, "Thanks for the review of our last game", ago: 1_500)
            message(from: Cast.mossLantern, "See you at the club on Sunday", ago: 2_400)
            message(from: Cast.cedarWave, "Good game yesterday!", ago: 90_000)
        }

        mutating func moderatorMessage() {
            message(from: Cast.moderator, "Hello, I'm a moderator. Please reply here before you play on.", ago: 60)
        }

        private mutating func message(from peer: OGSUser, _ text: String, ago seconds: TimeInterval) {
            state.privateMessages.append(OGSPrivateMessage(from: peer, to: user, content: OGSPrivateMessageContent(
                id: "activity-fixture-\(peer.id)", message: text, timestamp: clock.ago(seconds))))
        }

        /// A direct challenge built on the sample one.
        private func direct(_ id: Int, from challenger: OGSUser, to challenged: OGSUser, _ system: TimeControlSystem,
                            ranked: Bool, rules: OGSRule = .japanese, komi: Double? = 6.5) -> OGSDirectChallenge {
            var challenge = OGSChallengeSampleData.sampleChallenge
            challenge.id = id
            challenge.challenger = challenger
            challenge.challenged = challenged
            challenge.game.id = id + 10_000
            challenge.game.name = "Friendly Match"
            challenge.game.width = 19
            challenge.game.height = 19
            challenge.game.ranked = ranked
            challenge.game.isPrivate = false
            challenge.game.handicap = 0
            challenge.game.komi = komi
            challenge.game.rules = rules
            challenge.game.disableAnalysis = false
            challenge.game.timeControl = system.timeControlObject
            return challenge
        }

        private func fischer(_ seconds: TimeInterval) -> ThinkingTime {
            ThinkingTime(thinkingTime: seconds, thinkingTimeLeft: seconds)
        }

        private func byoyomi(_ main: TimeInterval, periods: Int) -> ThinkingTime {
            ThinkingTime(thinkingTime: main, thinkingTimeLeft: main, periods: periods, periodsLeft: periods,
                         periodTime: 30, periodTimeLeft: 30)
        }

        /// A started clock as OGS sends it: `toMove` has thought `thinking` seconds
        /// since the last move; `black` and `white` are the times at that move.
        private mutating func addGame(
            _ id: Int, vs opponent: OGSUser?, _ system: TimeControlSystem, toMove: StoneColor,
            black: ThinkingTime, white: ThinkingTime, thinking: TimeInterval,
            phase: OGSGamePhase = .play, paused: Bool = false, emptyBoard: Bool = false
        ) {
            var data = template
            data.gameId = id
            if let opponent {
                data.players.black = opponent
                data.blackPlayerId = opponent.id
            }
            data.timeControl = system.timeControlObject
            data.phase = phase
            data.outcome = phase == .finished ? "Resignation" : nil
            data.winner = phase == .finished ? user.id : nil
            if emptyBoard {
                data.moves = []
                data.handicap = 0
                data.freeHandicapPlacement = false
                data.komi = 6.5
                data.rules = .japanese
            } else if phase == .play && toMove == .black {
                data.moves = Array(template.moves.dropLast())   // 185 moves leave White to play
            }
            var gameClock = data.clock
            gameClock.blackPlayerId = data.players.black.id
            gameClock.whitePlayerId = data.players.white.id
            gameClock.currentPlayerColor = toMove
            gameClock.currentPlayerId = toMove == .black ? data.players.black.id : data.players.white.id
            gameClock.blackTime = black
            gameClock.whiteTime = white
            gameClock.started = true
            gameClock.lastMoveTime = clock.ago(thinking) * 1_000
            gameClock.timeUntilExpiration = nil
            if case .ByoYomi = system {
                gameClock.expiration = nil
            } else {
                let moving = toMove == .black ? black : white
                gameClock.expiration = gameClock.lastMoveTime + (moving.thinkingTime ?? 0) * 1_000
            }
            data.pauseControl = paused
                ? try! JSONDecoder().decode(OGSPauseControl.self, from: Data(#"{"weekend": true}"#.utf8))
                : nil
            gameClock.pauseControl = data.pauseControl
            gameClock.pausedTime = paused ? gameClock.lastMoveTime : nil
            data.clock = gameClock
            let game = Game(ogsGame: data)
            game.ogsRawData = [:]
            // Game(ogsGame:) measured from the wall clock, and calculateTimeLeft leaves a
            // clock alone until a whole second has passed (stone removal's thinking 0),
            // so start again from the clock at the last move.
            game.clock = gameClock
            game.clock?.calculateTimeLeft(with: system, pauseControl: game.pauseControl,
                                          now: clock.reference * 1_000)
            state.activeGames[id] = game
        }
    }
}

#if MAIN_APP
extension ActivityFixtures {
    /// The launch's state and reference second, read once so every window shares them.
    static let selected: Launch? = {
        guard SurroundUITestContract.isEnabled else { return nil }
        do {
            return try ActivityFixtures.parse(ProcessInfo.processInfo.arguments,
                                              reference: Date().timeIntervalSince1970)
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    /// The selected state's seed, once a window has built it.
    private(set) static var selectedSeed: Seed?

    /// The plain offline journey's service in the selected state; nil without one.
    static func selectedService(from state: OGSService.BootstrapState,
                                make: (OGSService.BootstrapState) -> OGSService) -> OGSService? {
        guard let selected = Self.selected else { return nil }
        var state = state
        selectedSeed = apply(selected.state, to: &state, clock: selected.clock)
        let service = make(state)
        finish(selected.state, service: service)
        return service
    }

    /// Activity's input in the selected state, for Debug probes that draw real rows.
    static func selectedInput(_ ogs: OGSService, place: ActivityModel.Place) -> ActivityModel.Input? {
        guard let selected = Self.selected, let seed = selectedSeed else { return nil }
        return input(ogs, place: place, seed: seed, clock: selected.clock)
    }
}
#endif
#endif
