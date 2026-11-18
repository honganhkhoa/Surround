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
            XCTAssertEqual(placement.action, input.userPlays ? .relabelled : .none, "\(input)")
            if !input.userPlays && !input.isCatalyst {
                XCTAssertFalse(placement.showsWindowSubtitle, "A game you watch shows nothing here: \(input)")
            }
        }
    }

    func testTheMacUsesTheWindowSubtitleInsteadOfTheCapsule() {
        for input in inputs(clockInPlay: true) + inputs(clockInPlay: false) {
            let placement = Placement(input)
            XCTAssertEqual(placement.showsWindowSubtitle, input.isCatalyst, "Every state on the Mac: \(input)")
            guard input.isCatalyst else { continue }
            XCTAssertFalse(placement.showsTitleCapsule, "\(input)")
            var iOS = input
            iOS.isCatalyst = false
            let onIOS = Placement(iOS)
            XCTAssertEqual(placement.clocks, onIOS.clocks, "The clocks as on iOS: \(input)")
            XCTAssertEqual(placement.action, onIOS.action, "The action as on iOS: \(input)")
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
