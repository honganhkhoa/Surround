//
//  GameConnectionPlacementTests.swift
//  SurroundTests
//
//  Where a game says that the window's connection is down, from whether a
//  clock is in play, the panel, the bar's form, the platform and whether the
//  user plays; never from what a layout drew.
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
    /// play, and no Chat panel waiting to reopen.
    private func inputs(clockInPlay: Bool) -> [Input] {
        [GameDetailPanel.playerInfo, .chat, .analyze].flatMap { panel in
            (0..<16).map { bits in
                Input(hasClockInPlay: clockInPlay, panel: panel, isVerticalToolbar: bits & 1 != 0,
                      isZen: bits & 2 != 0, isCatalyst: bits & 4 != 0, userPlays: bits & 8 != 0)
            }
        }
    }

    private func hasTitleSlot(_ input: Input) -> Bool { !input.isVerticalToolbar && !input.isZen }

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

    func testWithoutATitleSlotTheActionSaysIt() {
        for input in inputs(clockInPlay: false) where !hasTitleSlot(input) {
            let placement = Placement(input)
            XCTAssertEqual(placement.clocks, .unchanged, "\(input)")
            XCTAssertFalse(placement.showsTitleCapsule, "\(input)")
            XCTAssertEqual(placement.action, input.userPlays ? .relabelled : .none,
                           "A game you watch shows nothing here: \(input)")
        }
    }

    /// The Mac's game toolbar draws no title, so neither a capsule nor a
    /// window subtitle would show: where iOS shows the capsule, the Mac's
    /// main action reads Reconnecting…. Everywhere else, as on iOS.
    func testTheMacRelabelsTheActionWhereIOSShowsTheCapsule() {
        for input in inputs(clockInPlay: true) + inputs(clockInPlay: false) where input.isCatalyst {
            let placement = Placement(input)
            XCTAssertFalse(placement.showsTitleCapsule, "\(input)")
            var iOS = input
            iOS.isCatalyst = false
            let onIOS = Placement(iOS)
            XCTAssertEqual(placement.clocks, onIOS.clocks, "The clocks as on iOS: \(input)")
            if onIOS.showsTitleCapsule {
                XCTAssertEqual(placement.action, input.userPlays ? .relabelled : .none, "\(input)")
            } else {
                XCTAssertEqual(placement.action, onIOS.action, "The action as on iOS: \(input)")
            }
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
            Placement(Input(game: scoring, panel: panel, restoresChatPanel: restore.opensChat(from: panel),
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

    /// Game 26268404, White to move. With no account a game in stone
    /// removal doesn't start scoring it.
    private func game(_ phase: OGSGamePhase, outcome: String? = nil) throws -> Game {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "game-26268404", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var data = try decoder.decode(OGSGame.self, from: Data(contentsOf: url))
        data.phase = phase
        data.outcome = outcome
        return Game(ogsGame: data)
    }

    private func input(_ game: Game) -> Input {
        Input(game: game, panel: .playerInfo, restoresChatPanel: false, isVerticalToolbar: false, isZen: false,
              isCatalyst: false)
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
