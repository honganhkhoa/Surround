//
//  GameConnectionPlacementTests.swift
//  SurroundTests
//
//  Where a game says that the window's connection is down, from whether a
//  clock is in play, the panel, the bar's form, the platform, whether the
//  user plays and the action row's main action; never from what a layout
//  drew.
//

import XCTest

final class GameConnectionPlacementTests: XCTestCase {
    private typealias Placement = GameConnectionPlacement
    private typealias Input = GameConnectionPlacement.Input

    private var preferenceSuites = [String]()
    /// A game holds its service weakly; these keep each test's alive.
    private var services = [OGSService]()

    override func tearDown() {
        services.removeAll()
        preferenceSuites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        preferenceSuites.removeAll()
        super.tearDown()
    }

    /// Every panel, form, platform and player, with or without a clock in
    /// play, a main action that needs the connection and a chat preview, and
    /// no Chat panel waiting to reopen.
    private func inputs(clockInPlay: Bool) -> [Input] {
        [GameDetailPanel.playerInfo, .chat, .analyze].flatMap { panel in
            (0..<64).map { bits in
                Input(hasClockInPlay: clockInPlay, panel: panel, isVerticalToolbar: bits & 1 != 0,
                      isZen: bits & 2 != 0, isCatalyst: bits & 4 != 0, userPlays: bits & 8 != 0,
                      mainActionNeedsConnection: bits & 16 != 0, showsChatPreview: bits & 32 != 0)
            }
        }
    }

    private func hasTitleSlot(_ input: Input) -> Bool { !input.isVerticalToolbar && !input.isZen }

    /// The main action reads Reconnecting… and the row draws it: the action
    /// needs the connection, and Zen, or neither Analyze nor a chat preview,
    /// leaves the row in place.
    private func relabelShows(_ input: Input, _ placement: Placement) -> Bool {
        placement.action == .relabelled && input.mainActionNeedsConnection
            && (input.isZen || (input.panel != .analyze && !input.showsChatPreview))
    }

    // MARK: The table

    func testAClockInPlayCarriesTheMarkInEveryPanelAndForm() {
        for input in inputs(clockInPlay: true) {
            let placement = Placement(input)
            XCTAssertEqual(placement.clocks, .toMoveClock, "\(input)")
            XCTAssertFalse(placement.showsTitleCapsule, "The title slot keeps its clocks or identity: \(input)")
            XCTAssertEqual(placement.action, input.userPlays ? .disabled : .none, "\(input)")
        }
    }

    func testWithNoClockInPlayPlayShowsTheCapsuleInTheTitleSlot() {
        for input in inputs(clockInPlay: false) where hasTitleSlot(input) && input.panel == .playerInfo
            && !input.isCatalyst {
            let placement = Placement(input)
            XCTAssertTrue(placement.showsTitleCapsule, "\(input)")
            XCTAssertEqual(placement.clocks, .unchanged, "\(input)")
            XCTAssertEqual(placement.action, input.userPlays ? .disabled : .none, "\(input)")
        }
    }

    func testChatOrAnalyzeMarksOneClockAndNeverShowsTheCapsule() {
        for input in inputs(clockInPlay: false) where hasTitleSlot(input) && input.panel != .playerInfo {
            let placement = Placement(input)
            XCTAssertEqual(placement.clocks, .oneClock, "\(input)")
            XCTAssertFalse(placement.showsTitleCapsule, "\(input)")
            XCTAssertEqual(placement.action, input.userPlays ? .disabled : .none, "\(input)")
        }
    }

    /// Without a title slot the main action of a game the user plays reads
    /// Reconnecting…. Where the row draws it on an action that needs the
    /// connection, the clocks stay as they are; elsewhere, as in a game the
    /// user watches, one clock says it.
    func testWithoutATitleSlotTheActionSaysItElseOneClockDoes() {
        for input in inputs(clockInPlay: false) where !hasTitleSlot(input) {
            let placement = Placement(input)
            XCTAssertFalse(placement.showsTitleCapsule, "\(input)")
            XCTAssertEqual(placement.action, input.userPlays ? .relabelled : .none, "\(input)")
            XCTAssertEqual(placement.clocks, relabelShows(input, placement) ? .unchanged : .oneClock, "\(input)")
        }
    }

    /// The Mac's game toolbar draws no title, so neither a capsule nor a
    /// window subtitle would show: where iOS shows the capsule, the Mac's
    /// main action reads Reconnecting…, and where that doesn't show, one
    /// clock says it. Everywhere else, as on iOS.
    func testTheMacRelabelsTheActionWhereIOSShowsTheCapsule() {
        for input in inputs(clockInPlay: true) + inputs(clockInPlay: false) where input.isCatalyst {
            let placement = Placement(input)
            XCTAssertFalse(placement.showsTitleCapsule, "\(input)")
            var iOS = input
            iOS.isCatalyst = false
            let onIOS = Placement(iOS)
            if onIOS.showsTitleCapsule {
                XCTAssertEqual(placement.action, input.userPlays ? .relabelled : .none, "\(input)")
                XCTAssertEqual(placement.clocks, relabelShows(input, placement) ? .unchanged : .oneClock,
                               "\(input)")
            } else {
                XCTAssertEqual(placement.action, onIOS.action, "The action as on iOS: \(input)")
                XCTAssertEqual(placement.clocks, onIOS.clocks, "The clocks as on iOS: \(input)")
            }
        }
    }

    /// With no clock in play, one clock carries the mark wherever neither the
    /// capsule nor a relabelled action shows: Analyze or a chat preview in
    /// the action row's place, a main action that needs no connection, a
    /// game the user watches. Everywhere else the status stays where it was.
    func testOneClockSaysItWhereNeitherTheCapsuleNorARelabelShows() {
        struct Row {
            let name: String
            let input: Input
            let clocks: Placement.Clocks
            let showsCapsule: Bool
            let action: Placement.Action
        }
        func input(_ panel: GameDetailPanel = .playerInfo, vertical: Bool = false, zen: Bool = false,
                   mac: Bool = false, plays: Bool = true, needsConnection: Bool = true,
                   preview: Bool = false, clockInPlay: Bool = false) -> Input {
            Input(hasClockInPlay: clockInPlay, panel: panel, isVerticalToolbar: vertical, isZen: zen,
                  isCatalyst: mac, userPlays: plays, mainActionNeedsConnection: needsConnection,
                  showsChatPreview: preview)
        }
        let rows: [Row] = [
            // Where the action row isn't drawn.
            Row(name: "Duo's vertical toolbar with Analyze open, Accept due",
                input: input(.analyze, vertical: true), clocks: .oneClock, showsCapsule: false, action: .relabelled),
            Row(name: "Duo's vertical toolbar with a chat preview on the board, Rematch",
                input: input(.chat, vertical: true, preview: true), clocks: .oneClock, showsCapsule: false,
                action: .relabelled),
            // Where no action that needs the connection is there to relabel:
            // stone removal once the user has accepted, a finished Rengo game.
            Row(name: "The Mac in Play, stone removal after accepting",
                input: input(mac: true, needsConnection: false), clocks: .oneClock, showsCapsule: false,
                action: .relabelled),
            Row(name: "Duo's vertical toolbar in Play, a finished Rengo game",
                input: input(vertical: true, needsConnection: false), clocks: .oneClock, showsCapsule: false,
                action: .relabelled),
            Row(name: "Duo's vertical toolbar with Chat open, stone removal after accepting",
                input: input(.chat, vertical: true, needsConnection: false), clocks: .oneClock, showsCapsule: false,
                action: .relabelled),
            Row(name: "Zen, stone removal after accepting",
                input: input(zen: true, needsConnection: false), clocks: .oneClock, showsCapsule: false,
                action: .relabelled),
            // A game the user watches, where nothing is relabelled.
            Row(name: "Zen, a game you watch", input: input(zen: true, plays: false, needsConnection: false),
                clocks: .oneClock, showsCapsule: false, action: .none),
            Row(name: "Duo's vertical toolbar, a game you watch",
                input: input(vertical: true, plays: false, needsConnection: false), clocks: .oneClock,
                showsCapsule: false, action: .none),
            Row(name: "The Mac in Play, a game you watch",
                input: input(mac: true, plays: false, needsConnection: false), clocks: .oneClock,
                showsCapsule: false, action: .none),
            // As they were.
            Row(name: "A title slot in Play", input: input(needsConnection: false), clocks: .unchanged,
                showsCapsule: true, action: .disabled),
            Row(name: "A title slot in Play, a game you watch", input: input(plays: false, needsConnection: false),
                clocks: .unchanged, showsCapsule: true, action: .none),
            Row(name: "A title slot with Chat open", input: input(.chat), clocks: .oneClock, showsCapsule: false,
                action: .disabled),
            Row(name: "A title slot with Analyze open", input: input(.analyze), clocks: .oneClock,
                showsCapsule: false, action: .disabled),
            Row(name: "The Mac with Analyze open", input: input(.analyze, mac: true), clocks: .oneClock,
                showsCapsule: false, action: .disabled),
            Row(name: "Duo's vertical toolbar in Play, Accept due", input: input(vertical: true), clocks: .unchanged,
                showsCapsule: false, action: .relabelled),
            Row(name: "Duo's vertical toolbar with Chat open, Rematch", input: input(.chat, vertical: true),
                clocks: .unchanged, showsCapsule: false, action: .relabelled),
            Row(name: "Zen, Accept due", input: input(zen: true), clocks: .unchanged, showsCapsule: false,
                action: .relabelled),
            Row(name: "Zen entered from Analyze, Rematch", input: input(.analyze, zen: true), clocks: .unchanged,
                showsCapsule: false, action: .relabelled),
            Row(name: "The Mac in Play, Accept due", input: input(mac: true), clocks: .unchanged,
                showsCapsule: false, action: .relabelled),
            Row(name: "A clock in play, Duo's vertical toolbar with Analyze open",
                input: input(.analyze, vertical: true, needsConnection: false, clockInPlay: true),
                clocks: .toMoveClock, showsCapsule: false, action: .disabled),
        ]
        for row in rows {
            let placement = Placement(row.input)
            XCTAssertEqual(placement.clocks, row.clocks, row.name)
            XCTAssertEqual(placement.showsTitleCapsule, row.showsCapsule, row.name)
            XCTAssertEqual(placement.action, row.action, row.name)
        }
    }

    // MARK: The first frame

    func testAFirstDrawAndALaterOneGiveTheSameAnswer() {
        for input in inputs(clockInPlay: true) + inputs(clockInPlay: false) where input.panel != .chat {
            // The first pass, before Game Detail has measured and reopened a
            // remembered Chat panel, and a later one, once it has.
            var first = input
            first.restoresChatPanel = true
            var later = input
            if input.panel == .playerInfo {
                later.panel = .chat
            }
            XCTAssertEqual(Placement(first), Placement(later), "\(input)")
        }
    }

    /// Game Detail reopens a remembered Chat panel once it has measured its
    /// width: only once per route, only at regular width, and only from
    /// Play. Until then the panel is Play but the restore is pending.
    func testAChatRestoreIsPendingUntilGameDetailHasMeasuredARegularWidth() {
        typealias Restore = GameDetailChatRestore
        let pending = Restore(hasRestored: false, remembersChat: true, isCompact: false)
        XCTAssertTrue(pending.opensChat(from: .playerInfo))
        XCTAssertFalse(pending.opensChat(from: .analyze), "A route that opened in Analyze keeps it")
        XCTAssertFalse(pending.opensChat(from: .chat), "Chat is already open")
        XCTAssertFalse(Restore(hasRestored: true, remembersChat: true, isCompact: false).opensChat(from: .playerInfo),
                       "Once per route")
        XCTAssertFalse(Restore(hasRestored: false, remembersChat: false, isCompact: false).opensChat(from: .playerInfo),
                       "Chat wasn't open when the user last left a game")
        XCTAssertFalse(Restore(hasRestored: false, remembersChat: true, isCompact: true).opensChat(from: .playerInfo),
                       "A compact layout has no side Chat to restore")
    }

    /// A game opened during an outage at regular width, with Chat
    /// remembered: its first pass, before Chat opens, already places the
    /// status as Chat does, on one clock and never in the title slot, and so
    /// does every pass after it. At compact width nothing waits, and the
    /// capsule shows from the first pass.
    func testAPendingChatRestoreCountsAsChatFromTheFirstPass() throws {
        let scoring = try game(.stoneRemoval)
        func placement(panel: GameDetailPanel, restore: GameDetailChatRestore) -> Placement {
            Placement(Input(game: scoring, blocksActions: false, panel: panel,
                            restoresChatPanel: restore.opensChat(from: panel),
                            isVerticalToolbar: false, isZen: false, isCatalyst: false))
        }
        let firstPass = placement(panel: .playerInfo,
                                  restore: GameDetailChatRestore(hasRestored: false, remembersChat: true, isCompact: false))
        let afterRestore = placement(panel: .chat,
                                     restore: GameDetailChatRestore(hasRestored: true, remembersChat: true, isCompact: false))
        XCTAssertEqual(firstPass, afterRestore)
        XCTAssertFalse(firstPass.showsTitleCapsule)
        XCTAssertEqual(firstPass.clocks, .oneClock)

        let compact = placement(panel: .playerInfo,
                                restore: GameDetailChatRestore(hasRestored: false, remembersChat: true, isCompact: true))
        XCTAssertTrue(compact.showsTitleCapsule)
        XCTAssertEqual(compact.clocks, .unchanged)
        let forgotten = placement(panel: .playerInfo,
                                  restore: GameDetailChatRestore(hasRestored: false, remembersChat: false, isCompact: false))
        XCTAssertTrue(forgotten.showsTitleCapsule, "Nothing to restore: Play keeps the capsule")
    }

    /// A game says an outage while it shows, as Reconnecting… or Can’t reach
    /// OGS, never during a short drop, and never "Connected".
    func testGamesSayOnlyAnOutageThatShows() {
        XCTAssertFalse(ConnectionStatusModel.Status.hidden.showsInGame)
        XCTAssertTrue(ConnectionStatusModel.Status.reconnecting.showsInGame)
        XCTAssertTrue(ConnectionStatusModel.Status.unreachable(.timedOut).showsInGame)
        XCTAssertTrue(ConnectionStatusModel.Status.unreachable(.noNetwork).showsInGame)
        XCTAssertFalse(ConnectionStatusModel.Status.connected.showsInGame, "No Connected in games")
    }

    // MARK: Reading a game

    private func makeService(user: OGSUser?) -> OGSService {
        let suite = "com.honganhkhoa.Surround.GameConnectionPlacementTests.\(UUID().uuidString)"
        preferenceSuites.append(suite)
        let service = OGSService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: OGSOfflineRejectingHTTPClient(),
            preferences: UserDefaults(suiteName: suite)!,
            ogsWebsocket: OGSOfflineNoOpWebsocket(),
            connectsAutomatically: false,
            usesSurroundOverviewService: false,
            enablesAppSideEffects: false,
            startsTimers: false,
            installsObservers: false
        )
        service.user = user
        services.append(service)
        return service
    }

    /// Game 26268404, White to move; with `rengo`, a Rengo game of one player
    /// a side. With no account a game in stone removal doesn't start scoring
    /// it, nor once an account is given afterwards.
    private func game(_ phase: OGSGamePhase, outcome: String? = nil, rengo: Bool = false) throws -> Game {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "game-26268404", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var data = try decoder.decode(OGSGame.self, from: Data(contentsOf: url))
        data.phase = phase
        data.outcome = outcome
        if rengo {
            data.rengo = true
            data.rengoTeams = OGSGame.RengoTeams(black: [data.players.black], white: [data.players.white])
        }
        return Game(ogsGame: data)
    }

    private func input(_ game: Game) -> Input {
        Input(game: game, blocksActions: false, panel: .playerInfo, restoresChatPanel: false,
              isVerticalToolbar: false, isZen: false, isCatalyst: false)
    }

    /// With no clock in play the main action needs the connection only as
    /// Rematch after a game the user played, or as Accept removed stones
    /// while the user's acceptance is due; never while an action is sending
    /// or a scoring change waits for its refresh.
    func testWithNoClockInPlayOnlyRematchAndADueAcceptanceNeedTheConnection() throws {
        func needsConnection(_ game: Game, blocksActions: Bool = false) -> Bool {
            Input.mainActionNeedsConnection(game: game, blocksActions: blocksActions)
        }
        let scoring = try game(.stoneRemoval)
        let white = try XCTUnwrap(scoring.whitePlayer)
        scoring.ogs = makeService(user: white)
        scoring.currentPosition.removedStones = []
        XCTAssertFalse(input(scoring).hasClockInPlay)
        XCTAssertTrue(needsConnection(scoring), "Accept removed stones, before the user accepts")
        scoring.removedStonesAccepted[.white] = []
        XCTAssertFalse(needsConnection(scoring), "Once the user has accepted: Next, or nothing")
        XCTAssertFalse(input(scoring).mainActionNeedsConnection)

        let finished = try game(.finished, outcome: "Resignation")
        finished.ogs = makeService(user: white)
        XCTAssertTrue(needsConnection(finished), "Rematch")
        XCTAssertTrue(input(finished).mainActionNeedsConnection)
        XCTAssertFalse(needsConnection(finished, blocksActions: true), "Sending, or a refresh pending")

        let rengo = try game(.finished, outcome: "Resignation", rengo: true)
        rengo.ogs = makeService(user: white)
        XCTAssertEqual(rengo.userStoneColor, .white)
        XCTAssertFalse(needsConnection(rengo), "No rematch after a Rengo game")

        let watched = try game(.finished, outcome: "Resignation")
        watched.ogs = makeService(user: OGSUser(username: "Watcher", id: 999_999_001, rank: 25))
        XCTAssertFalse(needsConnection(watched), "A game the user watches")
    }

    func testAClockIsInPlayWhileTheGameIsPlayedPausedIncluded() throws {
        let played = try game(.play)
        played.ogs = makeService(user: try XCTUnwrap(played.whitePlayer))
        XCTAssertTrue(input(played).hasClockInPlay)
        XCTAssertTrue(input(played).userPlays)

        played.pauseControl = try JSONDecoder().decode(OGSPauseControl.self, from: Data(#"{"weekend": true}"#.utf8))
        XCTAssertTrue(input(played).hasClockInPlay, "A paused clock is still in play.")

        played.ogs = makeService(user: OGSUser(username: "Watcher", id: 999_999_001, rank: 25))
        XCTAssertTrue(input(played).hasClockInPlay)
        XCTAssertFalse(input(played).userPlays)

        XCTAssertFalse(input(try game(.stoneRemoval)).hasClockInPlay, "Stone removal")
        XCTAssertFalse(input(try game(.finished, outcome: "Resignation")).hasClockInPlay, "After the game")
        XCTAssertFalse(input(try game(.play, outcome: "Timeout")).hasClockInPlay,
                       "An outcome can arrive before the phase does.")
    }
}
