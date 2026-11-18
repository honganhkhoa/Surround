//
//  GameControlModel.swift
//  Surround
//
//  The in-game control's rules that need no view: the value Game Detail's
//  Active games slot shows, how a Game Detail switches to another game,
//  which challenge the game-over card shows, and where a game says that the
//  connection is down. Each reads only state Game Detail has before it
//  draws, so SurroundTests checks it without a socket or a view.
//

import Foundation

// MARK: - The slot's value

/// What Game Detail's Active games slot shows: the in-game control's state
/// (`ActivityModel.gameControl(_:context:)`) without a live game's ticking
/// fields, so the toolbar's inputs change only when the state does. The
/// control reads the other game's clock itself.
enum GameControlSlot: Equatable {
    /// Another live game on your move, which a tap switches to.
    case chip(gameID: Int, plusN: Int, hasDot: Bool)
    /// A live game that started elsewhere, which a tap opens.
    case gameStarted(gameID: Int, plusN: Int, hasDot: Bool)
    /// Your finished game, whose popover leads with the opponent's challenge.
    case gameOverCard(challengeID: Int, plusN: Int)
    /// The picker's grid icon, with +N above 0.
    case base(plusN: Int)
    /// While you play live, challenges and messages wait as a dot.
    case dot
    /// The inbox glyph and its count.
    case inbox(count: Int)

    init(_ control: ActivityModel.GameControl) {
        switch control {
        case let .chip(game, plusN, hasDot):
            self = .chip(gameID: game.id, plusN: plusN, hasDot: hasDot)
        case let .gameStarted(game, plusN, hasDot):
            self = .gameStarted(gameID: game.id, plusN: plusN, hasDot: hasDot)
        case let .gameOverCard(challengeID, plusN):
            self = .gameOverCard(challengeID: challengeID, plusN: plusN)
        case .base(let plusN):
            self = .base(plusN: plusN)
        case .dot:
            self = .dot
        case .inbox(let count):
            self = .inbox(count: count)
        }
    }

    /// The slot for the game `input.place` shows, or nil where the slot
    /// hides. One read of the window's state is all it needs, so the body
    /// pass that first draws the bar already has it, and the pass after an
    /// in-place switch has the new game's.
    init?(_ input: ActivityModel.Input, context: ActivityModel.GameControlContext) {
        guard let control = ActivityModel.gameControl(input, context: context) else { return nil }
        self.init(control)
    }

    /// Reads the window's state for a Game Detail showing `game`. The place
    /// comes from the game itself (`ActivityModel.Place(showing:)`), not from
    /// the window's registry, which settles a turn later and leaves out
    /// presented stacks. So the game's end counts at once, though the
    /// service's lists catch up later.
    /// - Parameters:
    ///   - startedGames: The window's live games that started elsewhere, by
    ///     start time, in seconds since 1970.
    ///   - now: Seconds since 1970.
    init?(ogs: OGSService, showing game: Game, context: ActivityModel.GameControlContext,
          startedGames: [Int: TimeInterval], now: TimeInterval) {
        let input = ActivityModel.Input(ogs: ogs, place: ActivityModel.Place(showing: game),
                                        startedGames: startedGames, now: now)
        self.init(input, context: context)
    }
}

// MARK: - Switching games

/// How a Game Detail switches to another game. The control's chip and its
/// started form, the Zen circle, the picker's entries, the popover's live
/// rows and Next (N) all follow it. Only Home's route with the picker
/// allowed switches in place; every other route opens the game on Home's.
enum GameControlSwitch: Equatable {
    /// Sets the route's own game, as the picker does.
    case inPlace
    /// Opens the game on Home's route through
    /// `NavigationService.goToActiveGame(game:)`.
    case throughHome

    /// - Parameters:
    ///   - route: The Game Detail's route in its stack, or nil at a stack's
    ///     root, which only compatibility scenes and previews use. With no
    ///     route to leave, a root follows its picker flag as Home's route
    ///     does.
    ///   - allowsActiveGamesCarousel: The route's picker flag. Public games
    ///     keep its default, true, so the flag alone can't say the route is
    ///     Home's.
    init(route: StackRoute?, allowsActiveGamesCarousel: Bool) {
        switch route {
        case nil, .homeGame?:
            self = allowsActiveGamesCarousel ? .inPlace : .throughHome
        default:
            self = .throughHome
        }
    }

    /// The popover lists the picker of same-speed games, and the user's own
    /// game shows the base form, only where a switch happens in place.
    var allowsPicker: Bool { self == .inPlace }

    /// Shows `game`. In place, the window's Activity request and any pending
    /// game open are cleared, so an older open can't replace this one, then
    /// `show` sets the route's game; no stack resets. Through Home,
    /// `goToActiveGame(game:)` closes tracked sheets and the account sheet,
    /// resets every stack and shows the game on Home's route with the
    /// picker allowed, once the window is no longer covered.
    func perform(_ game: Game, navigation: NavigationService, show: (Game) -> Void) {
        switch self {
        case .inPlace:
            navigation.clearPendingGameOpen()
            navigation.main.activity = nil
            show(game)
        case .throughHome:
            navigation.goToActiveGame(game: game)
        }
    }
}

// MARK: - The game-over card

/// Which challenge the game-over card shows in a finished game's popover.
/// The game is the user's own, over and not Rengo. The challenge comes from
/// its opponent and is newer than the game: its game id is higher, since OGS
/// creates a challenge's game when the challenge is made. Its board size,
/// rules, rankedness and clock, system and values, are the game's, as the
/// game's Rematch copies them (`OGSChallengeTemplate.rematch(for:)`). The
/// highest challenge id wins.
///
/// Nothing records yet when a game ended or when a challenge arrived, so the
/// card names a challenge, never a rematch. The rule decides what leads the
/// popover, never an action: an unusual challenge still offers View
/// (`ActivityRowActionState`).
enum GameOverCardRule {
    /// The card's challenge among those the user received, or nil.
    static func challengeID(for game: Game, among received: [OGSDirectChallenge]) -> Int? {
        guard ActivityModel.hasEnded(game), game.isUserPlaying, !game.rengo,
              let gameID = game.ogsID, let settings = game.gameData,
              let userColor = game.userStoneColor,
              let opponentID = game.currentPlayer(with: userColor.opponentColor())?.id else {
            return nil
        }
        return received
            .filter { matches($0, gameID: gameID, opponentID: opponentID, settings: settings) }
            .map(\.id)
            .max()
    }

    private static func matches(_ challenge: OGSDirectChallenge, gameID: Int, opponentID: Int,
                                settings: OGSGame) -> Bool {
        let offered = challenge.game
        guard challenge.challenger?.id == opponentID, offered.id > gameID else { return false }
        guard offered.width == settings.width, offered.height == settings.height else { return false }
        guard offered.rules == settings.rules, offered.ranked == settings.ranked else { return false }
        return offered.timeControl.system == settings.timeControl.system
    }
}

// MARK: - Connection status in a game

/// Where a game says that the window's connection is down, from state Game
/// Detail has before it draws: whether a clock is in play, the panel, the
/// bar's form, the platform and whether the user plays. It reads nothing a
/// layout reports, such as a rendered badge, the layout plan or a
/// preference, so a game opened or switched to during an outage shows its
/// status in its place from the first frame, and every later pass agrees.
///
/// - A clock in play: the to-move clock's mark, in every panel and form.
/// - No clock in play, with a title slot: in Play the capsule in the title
///   slot; in Chat or Analyze the mark on one clock, never the capsule.
/// - No clock in play and no title slot: the main action reads
///   "Reconnecting…".
/// - The Mac says it in the window subtitle in every state, and never shows
///   the capsule.
///
/// A clock in play takes its mark at once from the socket, as the actions
/// disable; the capsule, the one clock's mark, the relabel and the subtitle
/// follow the window's connection source.
struct GameConnectionPlacement: Equatable {
    /// What Game Detail knows before it draws.
    struct Input: Equatable {
        /// The game is in play and one side is to move, paused included
        /// (`GameDetailClockState.isToMove`). Not whether a clock runs,
        /// which turns false offline.
        var hasClockInPlay: Bool
        var panel: GameDetailPanel
        /// A remembered Chat panel reopens once Game Detail has measured its
        /// width. It counts as Chat from the first pass, so the capsule never
        /// shows for the pass before Chat opens.
        var restoresChatPanel = false
        /// Duo's vertical toolbars, which have no title slot.
        var isVerticalToolbar = false
        /// Zen, which has no title slot.
        var isZen = false
        var isCatalyst = false
        /// The user plays the game, so some of its actions need the
        /// connection.
        var userPlays: Bool
    }

    /// Where the clocks carry the mark.
    enum Clocks: Equatable {
        case unchanged
        /// The to-move clock's mark, on every variant that shows it.
        case toMoveClock
        /// No clock is in play: the mark on the one clock a single header
        /// chip shows, wherever the layout puts it.
        case oneClock
    }

    /// What the actions that need the connection show: Pass, Submit move,
    /// Accept removed stones and Rematch, which disable at once from the
    /// socket in every layout.
    enum Action: Equatable {
        /// The user doesn't play, so none of them shows.
        case none
        /// Disabled, with "Reconnecting…" as their VoiceOver value while the
        /// status shows.
        case disabled
        /// Disabled, and the main action reads "Reconnecting…" while the
        /// status shows, since nothing else in the game says it.
        case relabelled
    }

    var clocks: Clocks
    /// The capsule in the title slot, in place of the identity or the empty
    /// slot.
    var showsTitleCapsule: Bool
    /// The Mac's window subtitle.
    var showsWindowSubtitle: Bool
    var action: Action

    init(_ input: Input) {
        let hasTitleSlot = !input.isVerticalToolbar && !input.isZen
        let panel: GameDetailPanel = input.panel == .playerInfo && input.restoresChatPanel ? .chat : input.panel
        if input.hasClockInPlay {
            clocks = .toMoveClock
        } else if hasTitleSlot && panel != .playerInfo {
            clocks = .oneClock
        } else {
            clocks = .unchanged
        }
        showsTitleCapsule = !input.isCatalyst && !input.hasClockInPlay && hasTitleSlot && panel == .playerInfo
        showsWindowSubtitle = input.isCatalyst
        if !input.userPlays {
            action = .none
        } else if !input.hasClockInPlay && !hasTitleSlot {
            action = .relabelled
        } else {
            action = .disabled
        }
    }
}

extension GameConnectionPlacement.Input {
    /// Reads the clock and whether the user plays from `game`; the rest is
    /// Game Detail's own state.
    init(game: Game, panel: GameDetailPanel, restoresChatPanel: Bool, isVerticalToolbar: Bool,
         isZen: Bool, isCatalyst: Bool) {
        let hasClockInPlay = [StoneColor.black, .white].contains {
            GameDetailClockState(game: game, color: $0).isToMove
        }
        self.init(hasClockInPlay: hasClockInPlay, panel: panel, restoresChatPanel: restoresChatPanel,
                  isVerticalToolbar: isVerticalToolbar, isZen: isZen, isCatalyst: isCatalyst,
                  userPlays: game.isUserPlaying)
    }
}
