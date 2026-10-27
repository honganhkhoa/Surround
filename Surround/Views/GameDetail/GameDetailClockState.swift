import Foundation
import UIKit

/// A projection of authoritative game data; it never advances or mutates clocks.
struct GameDetailClockState {
    let game: Game
    let color: StoneColor
    var clockOverride: OGSClock? = nil
    var isConnected = true
    /// The socket is recovering a connection it had. Before the first one
    /// (launch, sign-in) the badge reads Connecting…, as the app's banner does.
    var recoversConnection = true

    var clock: OGSClock? { clockOverride ?? game.clock }
    var isFinished: Bool {
        game.gamePhase == .finished || !(game.gameData?.outcome?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
    var isScoring: Bool { !isFinished && game.gamePhase == .stoneRemoval }
    var paused: Bool { game.pauseControl?.isPaused() ?? false }
    var notStarted: Bool { clock?.started == false }
    var firstMoveDeadline: Bool { notStarted && clock?.timeUntilExpiration != nil }
    var thinkingTime: ThinkingTime? { color == .black ? clock?.blackTime : clock?.whiteTime }
    var autoResign: TimeInterval? {
        color == .black ? clock?.blackTimeUntilAutoResign : clock?.whiteTimeUntilAutoResign
    }
    var isToMove: Bool {
        !isFinished && !isScoring && game.gamePhase == .play
            && (clock?.currentPlayerColor ?? game.currentPosition.nextToMove) == color
    }
    var reconnecting: Bool { !isConnected && isToMove }
    var passed: Bool {
        guard !isFinished, !isScoring, case .pass = game.currentPosition.lastMove else { return false }
        return game.currentPosition.nextToMove.opponentColor() == color
    }
    /// Legacy undo events omit the requester; they were only sent for the
    /// previous player's turn. Explicit requester IDs always take precedence.
    var ownsUndoRequest: Bool {
        guard !game.rengo, !isFinished, !isScoring, game.hasCurrentUndoRequest,
              let request = game.undoRequest else { return false }
        if let requester = request.requestedBy {
            return (color == .black ? game.blackPlayer?.id : game.whitePlayer?.id) == requester
        }
        return color == clock?.currentPlayerColor.opponentColor()
    }
    var canAnswerUndo: Bool { ownsUndoRequest && game.canAcceptUndo }
    var canWithdrawUndo: Bool { ownsUndoRequest && game.canCancelUndo }

    func badgeTitle(narrow: Bool = false) -> String {
        guard !isFinished, !isScoring else { return "" }
        if reconnecting {
            return recoversConnection ? String(localized: "Reconnecting…")
                : String(localized: "Connecting…", comment: "Clock badge while the app first connects to OGS")
        }
        if ownsUndoRequest {
            return canAnswerUndo ? String(localized: "Undo?") : String(localized: "Undo asked")
        }
        if passed { return String(localized: "Passed") }
        // A paused clock keeps the badge on the side to move, so the turn
        // stays clear; the card drops its hourglass and glow instead.
        guard isToMove else { return "" }
        if notStarted && !firstMoveDeadline { return String(localized: "Not started") }
        guard let userColor = game.userStoneColor else { return String(localized: "To move") }
        if game.rengo && userColor == color && !game.isUserTurn { return String(localized: "Teammate") }
        if narrow { return String(localized: "To move") }
        return userColor == color ? String(localized: "Your move", comment: "Game") : String(localized: "Their move")
    }
    var running: Bool {
        isConnected && canShowTimer && !isFinished && !isScoring && !paused && autoResign == nil
            && clock?.currentPlayerColor == color
            && (clock?.started == true || firstMoveDeadline)
            && game.gameData?.timeControl.system.supportsClock == true
            && game.gameData?.timeControl.system != .None
    }
    var suddenDeath: Bool {
        guard !notStarted, !isFinished, !isScoring,
              case .ByoYomi = game.gameData?.timeControl.system else { return false }
        return (thinkingTime?.thinkingTimeLeft ?? 1) <= 0 && thinkingTime?.periodsLeft == 1
    }
    var captures: Int { game.currentPosition.captures[color] ?? 0 }
    var accepted: Bool {
        guard let accepted = game.removedStonesAccepted[color] else { return false }
        return accepted == game.currentPosition.removedStones
    }
    var scores: GameScores? {
        isFinished ? game.gameData?.score : game.currentPosition.gameScores
    }
    var score: PlayerScore? { color == .black ? scores?.black : scores?.white }
    var scoreValue: String { score.map { gameDetailPoints($0.total) } ?? "—" }
    var scoreText: String {
        score.map { String(localized: "\(gameDetailPoints($0.total)) pts") } ?? "—"
    }
    var scoreBreakdown: String {
        guard let score, let data = game.gameData else { return String(localized: "Calculating score…") }
        var parts = [String]()
        if data.scoreStones { parts.append(String(localized: "\(score.stones) stones")) }
        if data.scoreTerritory { parts.append(String(localized: "\(score.territory) territory")) }
        if data.scorePrisoners { parts.append(String(localized: "\(score.prisoners) captures")) }
        return parts.joined(separator: " · ")
    }
    var pauseReason: String {
        game.pauseControl?.pauseReason(playerId: clock?.nextPlayerId(with: color)) ?? ""
    }

    // TimerView hides a pre-start clock without a deadline. Present its existing
    // starting values with an inert copy; the model and running indicator stay unchanged.
    var displayClock: OGSClock? {
        guard var clock = clock else { return nil }
        if !clock.started && clock.timeUntilExpiration == nil {
            clock.started = true
            // InlineTimerView also owns the hourglass. A pre-start card must
            // show neither an hourglass nor a running glow.
            clock.currentPlayerColor = color.opponentColor()
            if let system = game.gameData?.timeControl.system {
                clock.blackTime = startingTime(clock.blackTime, system: system)
                clock.whiteTime = startingTime(clock.whiteTime, system: system)
            }
        }
        return clock
    }
    // Give the established timer formatter the already-derived timeLeft value.
    // This separates the large value from metadata without recalculating time.
    var valueTimeControl: TimeControl { TimeControlSystem.Absolute(totalTime: 0).timeControlObject }
    var valueClock: OGSClock? {
        guard var clock = displayClock else { return nil }
        if clock.started {
            clock.blackTime.thinkingTimeLeft = clock.blackTime.timeLeft
            clock.whiteTime.thinkingTimeLeft = clock.whiteTime.timeLeft
        }
        return clock
    }
    private var displayThinkingTime: ThinkingTime? {
        color == .black ? displayClock?.blackTime : displayClock?.whiteTime
    }
    var timeDetail: String {
        if firstMoveDeadline {
            return clock?.currentPlayerColor == color ? String(localized: "first move") : ""
        }
        guard let system = game.gameData?.timeControl.system, let time = displayThinkingTime else { return "" }
        switch system {
        case .ByoYomi:
            if (time.thinkingTimeLeft ?? 0) > 0 {
                return "+ \(time.periods ?? 0)× \(timeString(timeLeft: time.periodTime ?? 0))"
            }
            if (time.periodsLeft ?? 0) <= 1 { return String(localized: "SD") }
            return "+ \((time.periodsLeft ?? 1) - 1)× \(timeString(timeLeft: time.periodTime ?? 0))"
        case .Fischer(_, let increment, _):
            // An increment is a duration, so a day-sized correspondence
            // allowance should read 1d rather than the countdown's 24h.
            let duration = increment >= 86_400
                ? durationString(seconds: increment) : timeString(timeLeft: increment)
            return "+ \(duration)"
        case .Canadian(_, let period, let moves):
            if (time.thinkingTimeLeft ?? 0) > 0 { return "+ \(timeString(timeLeft: period))/\(moves)" }
            return String(localized: "\(time.movesLeft ?? 0) of \(moves) stones left")
        case .Simple: return String(localized: "per move")
        case .Absolute: return String(localized: "total")
        default: return ""
        }
    }
    /// Full cards have room to explain the shorthand used by folded clocks.
    var fullTimeDetail: String {
        if firstMoveDeadline {
            return clock?.currentPlayerColor == color ? String(localized: "to make first move") : ""
        }
        guard let system = game.gameData?.timeControl.system, let time = displayThinkingTime else { return "" }
        switch system {
        case .Fischer(_, let increment, _) where increment >= 86_400:
            // The compact day allowance fits narrow correspondence cards;
            // the full per-move explanation remains in game details.
            return timeDetail
        case .Fischer(_, let increment, _):
            return String(localized: "+ \(timeString(timeLeft: increment)) per move")
        case .Canadian(_, let period, let moves) where (time.thinkingTimeLeft ?? 0) > 0:
            return String(localized: "+ \(timeString(timeLeft: period)) for \(moves) stones")
        default: return timeDetail
        }
    }

    var inlineTimeDetail: String {
        if firstMoveDeadline { return timeDetail }
        guard let system = game.gameData?.timeControl.system, let time = displayThinkingTime else { return "" }
        if case .ByoYomi = system {
            if (time.thinkingTimeLeft ?? 0) > 0 { return "+\(time.periods ?? 0)×" }
            return (time.periodsLeft ?? 0) <= 1 ? String(localized: "SD") : "+\((time.periodsLeft ?? 1) - 1)×"
        }
        if case .Canadian = system, (time.thinkingTimeLeft ?? 0) <= 0 {
            return String(localized: "\(time.movesLeft ?? 0) stones")
        }
        if case .Absolute = system { return "" }
        // Inline cards reserve their scarce width for the countdown. Simple
        // has no period/increment to preserve; the per-move rule remains in
        // full/compact cards, accessibility output and the details popover.
        if case .Simple = system { return "" }
        return timeDetail
    }
    private func startingTime(_ time: ThinkingTime, system: TimeControlSystem) -> ThinkingTime {
        guard time.thinkingTimeLeft == nil else { return time }
        switch system {
        case .ByoYomi(let main, let periods, let period):
            return ThinkingTime(thinkingTimeLeft: Double(main), periods: periods,
                                periodsLeft: periods, periodTime: Double(period), periodTimeLeft: Double(period))
        case .Canadian(let main, let period, let moves):
            return ThinkingTime(thinkingTimeLeft: Double(main), movesLeft: moves, blockTimeLeft: Double(period))
        case .Fischer(let initial, _, _): return ThinkingTime(thinkingTimeLeft: Double(initial))
        case .Simple(let perMove): return ThinkingTime(thinkingTimeLeft: Double(perMove))
        case .Absolute(let total): return ThinkingTime(thinkingTimeLeft: Double(total))
        default: return time
        }
    }
    var canShowTimer: Bool {
        guard let system = game.gameData?.timeControl.system, system.supportsClock,
              system != .None, let clock = displayClock else { return false }
        if !clock.started { return clock.timeUntilExpiration != nil }
        let time = color == .black ? clock.blackTime : clock.whiteTime
        guard let main = time.thinkingTimeLeft else { return false }
        switch system {
        case .ByoYomi:
            return main > 0 ? time.periods != nil && time.periodTime != nil
                : time.periodTimeLeft != nil && time.periodsLeft != nil && time.periodTime != nil
        case .Canadian:
            return main > 0 || (time.blockTimeLeft != nil && time.movesLeft != nil)
        default: return true
        }
    }
    var unavailableTimeText: String {
        game.gameData?.timeControl.system == .None ? String(localized: "No time limit") : "—"
    }
    var compactUnavailableTimeText: String {
        game.gameData?.timeControl.system == .None ? String(localized: "No limit") : "—"
    }
    var roleName: String {
        guard let userColor = game.userStoneColor else {
            return color == .black ? String(localized: "Black") : String(localized: "White")
        }
        return userColor == color ? String(localized: "You") : String(localized: "Opponent")
    }
    private var outcome: String {
        (game.gameData?.outcome ?? game.historySummary?.outcome ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private var annulled: Bool {
        game.historySummary?.annulled ?? game.historyAnnulled
            ?? (game.ogsRawData?["annulled"] as? Bool) ?? false
    }
    var winner: StoneColor? {
        if let id = game.gameData?.winner, let player = game.playerByOGSId[id] {
            return game.stoneColor(of: player)
        }
        return game.historySummary?.winnerColor
    }

    /// The one clock a title slot shows when it cannot hold both (rule 14):
    /// the player to move; when no one is (stone removal, game over), the
    /// viewer's own; spectators see the winner's, or Black's without one.
    static func singleChipColor(game: Game, clock: OGSClock?) -> StoneColor {
        let state = GameDetailClockState(game: game, color: .black, clockOverride: clock)
        guard state.isFinished || state.isScoring else {
            return (clock ?? game.clock)?.currentPlayerColor ?? game.currentPosition.nextToMove
        }
        return game.userStoneColor ?? state.winner ?? .black
    }
    var resultTitle: String {
        if annulled { return String(localized: "Annulled") }
        if outcome == "cancellation" { return String(localized: "Canceled") }
        if game.gameData?.winner == 0 || game.historySummary?.isDraw == true { return String(localized: "Draw") }
        guard let winner else { return String(localized: "Game over") }
        if winner == color { return String(localized: "Won") }
        if outcome == "resignation" { return String(localized: "Resigned") }
        if outcome == "timeout" { return String(localized: "Out of time") }
        return String(localized: "Lost")
    }
    var resultDetail: String {
        if annulled { return String(localized: "no winner") }
        if outcome == "cancellation" {
            return String(localized: "before move \(game.currentPosition.lastMoveNumber + 1)")
        }
        if let score, game.gameData?.winner == 0 || game.historySummary?.isDraw == true
            || Double(outcome.split(separator: " ").first ?? "") != nil {
            return String(localized: "\(gameDetailPoints(score.total)) points")
        }
        if winner != color { return String(localized: "move \(game.currentPosition.lastMoveNumber)") }
        switch outcome {
        case "resignation": return String(localized: "by resignation")
        case "timeout": return String(localized: "on time")
        case "disconnection": return String(localized: "by disconnection")
        case "stone removal timeout": return String(localized: "scoring timeout")
        case "disqualification": return String(localized: "by disqualification")
        case "moderator decision": return String(localized: "moderator decision")
        case "abandonment": return String(localized: "by abandonment")
        default: return game.gameData?.outcome ?? ""
        }
    }
    var accessibilityLabel: String {
        let side = color == .black ? String(localized: "Black") : String(localized: "White")
        guard let userColor = game.userStoneColor else { return side }
        return (userColor == color ? String(localized: "You") : String(localized: "Opponent")) + ", " + side
    }
    var accessibilityValue: String {
        var values = [String]()
        let badge = badgeTitle()
        if !badge.isEmpty { values.append(badge) }
        if isFinished {
            values += [resultTitle, resultDetail]
        } else if isScoring {
            values += [scoreText, scoreBreakdown, accepted ? String(localized: "Accepted") : String(localized: "Not accepted")]
            if !accepted, let time = clock?.timeUntilExpiration { values.append(timeString(timeLeft: time)) }
        } else if let autoResign {
            values += [String(localized: "Disconnected"), timeString(timeLeft: autoResign)]
        } else if firstMoveDeadline {
            if clock?.currentPlayerColor == color, let time = clock?.timeUntilExpiration {
                values += [timeString(timeLeft: time), String(localized: "first move")]
            } else { values.append(String(localized: "Waiting…")) }
        } else if canShowTimer, let clock = displayClock,
                  let time = (color == .black ? clock.blackTime : clock.whiteTime).timeLeft {
            values.append(timeString(timeLeft: time))
            if suddenDeath { values.append(String(localized: "Sudden death")) }
            else if !paused, !timeDetail.isEmpty { values.append(timeDetail) }
        } else { values.append(unavailableTimeText) }
        values.append(String(localized: "\(captures) captures"))
        if color == .white, let komi = game.gameData?.komi { values.append(String(localized: "\(gameDetailPoints(komi)) komi")) }
        if notStarted && !firstMoveDeadline && !isScoring && !isFinished { values.append(String(localized: "Clock not started")) }
        if paused && !isScoring && !isFinished { values.append(pauseReason) }
        if running { values.append(String(localized: "running")) }
        return values.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

func gameDetailPoints(_ points: Double) -> String {
    points.formatted(.number.precision(.fractionLength(0...1)))
}

/// v149: how a card in Duo Closed landscape's 126 pt column lays out its
/// detail line (periods, pause or disconnect note, result · captures).
enum GameDetailColumnDetailLayout: Equatable {
    /// One line, scaled down to at most 75% when it needs to (as before).
    case oneLine
    /// Two lines broken at " · ", so the periods and the captures stay whole.
    case splitAtSeparator
    /// Two lines wherever the text breaks: one part is longer than a line.
    case wrapped

    var wraps: Bool { self != .oneLine }
}

/// Both column cards' detail lines for the game's current values. The layout
/// plan decides from these whether the column has the room (cards and chips
/// switch in the same pass); the cards draw what it allowed.
struct GameDetailColumnDetailLayouts: Equatable {
    var black = GameDetailColumnDetailLayout.oneLine
    var white = GameDetailColumnDetailLayout.oneLine
    /// A wrapping card has no spare line, so both cards grow by one (they
    /// stay matched): White's full card, whose komi has its own line, or
    /// either two-line chip.
    var needsGrowth = false

    subscript(_ color: StoneColor) -> GameDetailColumnDetailLayout { color == .black ? black : white }
    var anyWraps: Bool { black.wraps || white.wraps }

    /// Full column cards at the default text size: 91 pt, 105 pt grown (one
    /// 12 pt line). Two-line chips grow by one 11 pt line.
    static func fullCardHeight(grown: Bool) -> CGFloat { grown ? 105 : 91 }
    static let compactLineGrowth: CGFloat = 14

    init() {}

    /// `fullCards`: the column cards (12 pt detail, 10 pt padding); otherwise
    /// the column's two-line chips (Zen, larger text; 11 pt, 8 pt).
    init(game: Game, fullCards: Bool, cardWidth: CGFloat, scale: CGFloat,
         clockOverride: OGSClock? = nil, isConnected: Bool = true) {
        guard cardWidth > 0 else { return }
        func layout(_ color: StoneColor) -> GameDetailColumnDetailLayout {
            let state = GameDetailClockState(game: game, color: color, clockOverride: clockOverride,
                                             isConnected: isConnected)
            return Self.layout(of: state, fullCards: fullCards, cardWidth: cardWidth, scale: scale)
        }
        black = layout(.black)
        white = layout(.white)
        if fullCards {
            let whiteState = GameDetailClockState(game: game, color: .white, clockOverride: clockOverride,
                                                  isConnected: isConnected)
            needsGrowth = white.wraps && whiteState.showsColumnKomiLine
        } else {
            needsGrowth = anyWraps
        }
    }

    /// One line while it fits at the 75% minimum scale. Measured at that
    /// size: SwiftUI draws the scaled text at 9 pt, whose tracking is wider
    /// than 75% of the 12 pt width ("vor Zug 3 · 2 Gefangene": 102.8 pt
    /// scaled, 106.6 pt at 9 pt in a 106 pt line, drawn with an ellipsis).
    static func layout(of state: GameDetailClockState, fullCards: Bool,
                       cardWidth: CGFloat, scale: CGFloat) -> GameDetailColumnDetailLayout {
        guard let line = state.cardDetail(full: fullCards), !line.text.isEmpty else { return .oneLine }
        let size = (fullCards ? 12 : 11) * scale
        let minimumFont = UIFont.systemFont(ofSize: size * 0.75, weight: line.emphasized ? .semibold : .regular)
        let padding: CGFloat = fullCards ? 10 : 8
        let available = cardWidth - padding * 2 - (line.symbol == nil ? 0 : ceil(size) + 3)
        func fits(_ text: String) -> Bool {
            (text as NSString).size(withAttributes: [.font: minimumFont]).width <= available - 0.5
        }
        let captures = String(localized: "\(state.captures) captures")
        if fits(line.text + " · " + captures) { return .oneLine }
        return fits(line.text + " ·") && fits(captures) ? .splitAtSeparator : .wrapped
    }
}

extension GameDetailClockState {
    /// The line a full or two-line card draws under its time, before " ·
    /// captures": the result, the disconnect note, or the periods (the pause
    /// reason while paused, with its symbol). Nil while scoring: the score
    /// breakdown takes its own lines.
    func cardDetail(full: Bool) -> (text: String, symbol: String?, emphasized: Bool)? {
        if isScoring { return nil }
        if isFinished { return (resultDetail, nil, false) }
        if autoResign != nil { return (String(localized: "Disconnected"), nil, true) }
        if canShowTimer {
            return (paused ? pauseReason : (full ? fullTimeDetail : timeDetail),
                    paused ? "pause.fill" : nil, false)
        }
        return ("", nil, false)
    }

    /// A column card's own komi line under the time: White's, while its
    /// clock shows. Black's card keeps that line spare.
    var showsColumnKomiLine: Bool {
        color == .white && game.gameData?.komi != nil
            && !isScoring && !isFinished && autoResign == nil && canShowTimer
    }
}

extension GameDetailClockState {
    /// Countdowns whose text is the widest of each format a clock with this
    /// maximum can show. The widest day form ("29 days 23h") is one second
    /// under a whole-day maximum, which itself shows only "30 days".
    static func widestCountdownSamples(maximumTime: Int) -> [Int] {
        [0, 59, 3_599, min(maximumTime, 86_399), min(maximumTime, 172_799),
         max(0, maximumTime - 1), maximumTime]
    }
}
