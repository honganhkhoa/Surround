//
//  HomeGameCard.swift
//  Surround
//
//  Home's game row (Compact) and tile (Large), drawn in the theme Home wears
//  (canvas "Home Redesign", Direction C: CRow and CLargeTile). Both fold the
//  clocks into chips in each side's stone colors, as Game Detail's cards do.
//

import SwiftUI

/// Under this much time on the user's own running clock, its chip turns red.
private let homeLowTimeThreshold: TimeInterval = 12 * 3600

/// What the line under the opponent's name says: the first that applies.
enum HomeGameNote: Equatable {
    case stoneRemoval
    case paused(String)
    case teammateMove
    case userNextOnTeam
    case conditionalMoves
    case settings(String)

    var text: String {
        switch self {
        case .stoneRemoval: String(localized: "Stone removal", comment: "pause reason")
        case .paused(let reason): reason
        case .teammateMove: String(localized: "Teammate’s move", comment: "Homeview - rengo game whose next move is the user's teammate's")
        case .userNextOnTeam: String(localized: "You are next on your team", comment: "Homeview - rengo game where the user plays their team's next move")
        case .conditionalMoves: String(localized: "Conditional moves set", comment: "Homeview - the user has saved conditional moves for this game")
        case .settings(let settings): settings
        }
    }
}

/// One game as Home lists it, from the signed-in player's side.
@MainActor
struct HomeGameFacts {
    let game: Game
    let user: OGSUser?

    /// The user's side; nil for a game the user only watches.
    var userColor: StoneColor? { game.userStoneColor }
    /// The upper chip is the opponent's; a watched game puts Black on top.
    var topColor: StoneColor { userColor?.opponentColor() ?? .black }
    var bottomColor: StoneColor { userColor ?? .white }
    var opponent: OGSUser? { game.currentPlayer(with: topColor) }

    var opponentTeamExtra: Int? {
        guard game.rengo, let team = game.orderedRengoTeam[topColor] ?? game.gameData?.rengoTeams?[topColor],
              team.count > 1 else { return nil }
        return team.count - 1
    }

    func clock(_ color: StoneColor) -> GameDetailClockState {
        GameDetailClockState(game: game, color: color)
    }

    var note: HomeGameNote? {
        if game.gamePhase == .stoneRemoval { return .stoneRemoval }
        if let pauseControl = game.pauseControl, pauseControl.isPaused() {
            let paused = String(localized: "Paused", comment: "pause reason")
            let reason = pauseControl.pauseReason(playerId: user?.id)
            // The user's own pause already says Paused, with the pauses left.
            if pauseControl.userPauseDetail != nil || reason.isEmpty || reason == paused {
                return .paused(reason.isEmpty ? paused : reason)
            }
            return .paused("\(paused) · \(reason)")
        }
        if game.rengo, let userColor, let user, game.gamePhase == .play,
           let toMove = game.clock?.currentPlayerColor {
            if toMove == userColor && !game.isUserTurn { return .teammateMove }
            if toMove != userColor, game.orderedRengoTeam[userColor]?.first?.id == user.id {
                return .userNextOnTeam
            }
        }
        if !game.isUserTurn, !game.conditionalMoveBranches.isEmpty { return .conditionalMoves }
        guard let gameData = game.gameData else { return nil }
        let ranked = gameData.ranked
            ? String(localized: "Ranked", comment: "ChallengeCell rank status")
            : String(localized: "Unranked", comment: "ChallengeCell rank status")
        guard let added = gameData.timeControl.system.homeAddedTime else { return .settings(ranked) }
        return .settings("\(ranked) · \(added)")
    }

    /// Time until the user's own clock runs out, counting byo-yomi periods
    /// and the current Canadian block.
    var userTimeUntilTimeout: TimeInterval? {
        guard let userColor, let clock = game.clock, clock.started,
              let system = game.gameData?.timeControl.system else { return nil }
        let time = userColor == .black ? clock.blackTime : clock.whiteTime
        let main = time.thinkingTimeLeft ?? 0
        switch system {
        case .ByoYomi:
            if main > 0 { return main + Double(time.periods ?? 0) * (time.periodTime ?? 0) }
            let periodsAfter = max(0, (time.periodsLeft ?? 1) - 1)
            return (time.periodTimeLeft ?? 0) + Double(periodsAfter) * (time.periodTime ?? 0)
        case .Canadian(_, let period, _):
            return main > 0 ? main + Double(period) : time.blockTimeLeft
        case .None, .Unknown:
            return nil
        default:
            return time.thinkingTimeLeft
        }
    }

    /// Low time is only ever the user's own running clock, and only where
    /// 12 hours means something: never in a live game.
    var userLowOnTime: Bool {
        guard let userColor, let gameData = game.gameData else { return false }
        let speed = gameData.timeControl.speed
            ?? gameData.timeControl.inferredSpeed(boardWidth: gameData.width, boardHeight: gameData.height)
        guard speed?.isRealtime != true, clock(userColor).running,
              let left = userTimeUntilTimeout else { return false }
        return left < homeLowTimeThreshold
    }

    func chipTime(_ color: StoneColor) -> String {
        let state = clock(color)
        if state.firstMoveDeadline {
            guard state.clock?.currentPlayerColor == color, let deadline = state.clock?.timeUntilExpiration else {
                return String(localized: "Waiting…")
            }
            return timeString(timeLeft: deadline)
        }
        guard state.canShowTimer, let clock = state.displayClock,
              let left = (color == .black ? clock.blackTime : clock.whiteTime).timeLeft else {
            return state.compactUnavailableTimeText
        }
        return timeString(timeLeft: left)
    }

    /// Overtime keeps its periods or stones beside the time; the main time
    /// needs no note, since the line under the name says what follows it.
    func chipDetail(_ color: StoneColor) -> String? {
        let state = clock(color)
        guard state.canShowTimer, !state.firstMoveDeadline, let time = state.thinkingTime,
              (time.thinkingTimeLeft ?? 0) <= 0 else { return nil }
        switch game.gameData?.timeControl.system {
        case .ByoYomi?, .Canadian?:
            let detail = state.inlineTimeDetail
            return detail.isEmpty ? nil : detail
        default:
            return nil
        }
    }

    /// Whether the game waits on the user, accepting stone removal included,
    /// as Home's sections decide it.
    var awaitsUser: Bool {
        guard let user else { return false }
        return game.requiresUserAction(forPlayerWithId: user.id)
    }

    var turnText: String {
        guard userColor != nil else { return "" }
        return awaitsUser
            ? String(localized: "Your move", comment: "Game\nHomeview")
            : String(localized: "Their move")
    }

    /// The whole row in one VoiceOver label, as the canvas's row button reads.
    var accessibilityLabel: String {
        var parts = [String]()
        if let opponent { parts.append([opponent.usernameAndRank, turnText].filter { !$0.isEmpty }.joined(separator: ", ")) }
        if let note { parts.append(note.text) }
        let topName = opponent?.username ?? (topColor == .black ? String(localized: "Black") : String(localized: "White"))
        parts.append("\(topName): \(chipTime(topColor))")
        if userColor != nil {
            parts.append("\(String(localized: "You")): \(chipTime(bottomColor))")
        } else if let player = game.currentPlayer(with: bottomColor) {
            parts.append("\(player.username): \(chipTime(bottomColor))")
        }
        if userLowOnTime { parts.append(String(localized: "Low on time", comment: "Homeview - VoiceOver: under 12 hours left on the user's running clock")) }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Clock chip

/// A clock folded into a chip in its side's stone colors. The running clock
/// wears the theme's turn ring; the user's own under 12 hours turns red.
struct HomeClockChip<Leading: View>: View {
    enum Size {
        case row, tile

        var minHeight: CGFloat { self == .row ? 28 : 34 }
        var radius: CGFloat { self == .row ? 8 : 9 }
        var padding: CGFloat { self == .row ? 9 : 10 }
    }

    @ObservedObject var game: Game
    let facts: HomeGameFacts
    let color: StoneColor
    var size: Size = .row
    @ViewBuilder var leading: () -> Leading

    @Environment(\.surroundTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var state: GameDetailClockState { facts.clock(color) }
    private var lowOnTime: Bool { color == facts.userColor && facts.userLowOnTime }
    private var warning: Bool { lowOnTime || (state.running && state.suddenDeath) }
    private var warningColor: Color { theme.clockSuddenDeathAccent(color, scheme: colorScheme) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size.radius, style: .continuous) }

    var body: some View {
        HStack(spacing: 4) {
            leading()
            Spacer(minLength: 4)
            statusIcon
            Text(verbatim: facts.chipTime(color))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(warning ? warningColor : theme.identityForeground(color))
                .lineLimit(1)
                .layoutPriority(1)
            if let detail = facts.chipDetail(color) {
                Text(verbatim: detail)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(warning ? warningColor : theme.identitySecondary(color))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(theme.identityForeground(color))
        .padding(.horizontal, size.padding)
        .frame(minHeight: size.minHeight)
        .background {
            if theme == .feltMeadow {
                FeltControlSurface(color: color, shape: shape)
            } else {
                shape.fill(LinearGradient(colors: theme.identityChipColors(color),
                                          startPoint: .top, endPoint: .bottom))
            }
        }
        .overlay { ring }
    }

    @ViewBuilder
    private var statusIcon: some View {
        let iconSize: CGFloat = size == .row ? 10 : 11
        if state.isScoring {
            if state.accepted {
                Image(systemName: "checkmark")
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(theme.identitySecondary(color))
            }
        } else if state.paused && state.isToMove {
            Image(systemName: "pause.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(theme.identitySecondary(color))
        } else if state.running {
            // The hourglass, like the ring, means the time is running.
            Image(systemName: "hourglass")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(warning ? warningColor : theme.homeChipAccent(color))
        }
    }

    /// Strokes, not blurred shadows: a list of rows must scroll smoothly.
    @ViewBuilder
    private var ring: some View {
        if state.running || lowOnTime {
            let ringColor = warning ? warningColor : theme.turnOutline(scheme: colorScheme)
            let glowColor = warning ? warningColor : theme.turnGlow
            shape.strokeBorder(ringColor, lineWidth: 1)
                .background {
                    shape.inset(by: -2.5).stroke(glowColor.opacity(colorScheme == .dark ? 0.5 : 0.4), lineWidth: 3)
                }
        } else {
            shape.strokeBorder(theme.identityChipBorder(color), lineWidth: 1)
        }
    }
}

// MARK: - Opponent name

private struct HomePlayerName: View {
    let player: OGSUser
    let surface: StoneColor?
    var extra: Int? = nil
    var nameFont: Font = .callout.weight(.semibold)
    var rankFont: Font = .subheadline
    var accessibilityIdentifier = ""
    @ObservedObject private var preferences = userDefaults
    @Environment(\.surroundTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    /// On a panel the surface follows the appearance; on a chip, the stone.
    private var roleSurface: StoneColor { surface ?? (colorScheme == .dark ? .black : .white) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            let name = Text(verbatim: player.username)
                .font(nameFont)
                .foregroundStyle(theme.roleColor(for: player, on: roleSurface))
                .lineLimit(1)
            if accessibilityIdentifier.isEmpty {
                name
            } else {
                name.accessibilityIdentifier(accessibilityIdentifier)
            }
            if !(preferences[.hidesRank] ?? false) {
                Text(verbatim: player.formattedRank)
                    .font(rankFont)
                    .modifier(HomeSecondaryText(surface: surface))
                    .lineLimit(1)
                    .fixedSize()
            }
            if let extra {
                Text(verbatim: "+\(extra)")
                    .font(rankFont.weight(.semibold))
                    .modifier(HomeSecondaryText(surface: surface))
                    .fixedSize()
                    .accessibilityLabel(Text("\(extra) teammates", comment: "Homeview - VoiceOver: more players on the opponent's rengo team"))
            }
        }
    }
}

/// Secondary text on a panel follows Game Detail's panels; on a chip it
/// uses the chip's own secondary pigment.
struct HomeSecondaryText: ViewModifier {
    var surface: StoneColor? = nil
    @Environment(\.surroundTheme) private var theme

    func body(content: Content) -> some View {
        if let surface {
            content.foregroundStyle(theme.identitySecondary(surface))
        } else {
            content.gameDetailSecondaryText()
        }
    }
}

// MARK: - Row (Compact)

/// The Compact row: a 120 pt board (never smaller: it is about the smallest
/// a board stays legible), the opponent, one line, and the two clocks.
struct HomeGameRow: View {
    @ObservedObject var game: Game
    var opensGame: () -> Void
    var navigationAccessibilityIdentifier = ""
    /// Rows after the first in a grouped panel draw a hairline above the text.
    var showsSeparator = false

    @EnvironmentObject private var ogs: OGSService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The board stays 120 pt; the text beside it grows with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = HomeGameRow.boardSize + 20

    static let boardSize: CGFloat = 120

    private var facts: HomeGameFacts { HomeGameFacts(game: game, user: ogs.user) }

    var body: some View {
        let facts = facts
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    board(facts)
                    details(facts)
                }
                .padding(12)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    board(facts)
                        .padding(.vertical, 10)
                    details(facts)
                        .padding(.top, 12)
                        .padding(.bottom, 10)
                        .padding(.trailing, 12)
                        .overlay(alignment: .top) {
                            if showsSeparator {
                                Rectangle()
                                    .fill(GameDetailSurfaceStyle(role: .panelBorder))
                                    .frame(height: 0.5)
                            }
                        }
                }
                .padding(.leading, 12)
                .frame(height: max(rowHeight, Self.boardSize + 20))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: opensGame)
        .modifier(GamePlayerProfileMenu(game: game))
    }

    private func board(_ facts: HomeGameFacts) -> some View {
        HomeBoardButton(game: game, opensGame: opensGame,
                        accessibilityIdentifier: navigationAccessibilityIdentifier,
                        accessibilityLabel: facts.accessibilityLabel)
            .frame(width: Self.boardSize, height: Self.boardSize)
    }

    private func details(_ facts: HomeGameFacts) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let opponent = facts.opponent {
                HomePlayerName(player: opponent, surface: nil, extra: facts.opponentTeamExtra,
                               accessibilityIdentifier: navigationAccessibilityIdentifier.isEmpty
                                ? "" : "\(navigationAccessibilityIdentifier).playerInfo")
            }
            if let note = facts.note {
                HomeGameNoteLine(game: game, note: note)
            }
            Spacer(minLength: 6)
            HomeClockChip(game: game, facts: facts, color: facts.topColor) { EmptyView() }
                .accessibilityElement(children: .combine)
            HomeClockChip(game: game, facts: facts, color: facts.bottomColor) {
                if facts.userColor != nil {
                    Text("You")
                        .font(.caption.weight(.medium))
                        .opacity(0.72)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// The line under the name. When it says conditional moves are set, it is
/// the button that shows them, as the old row's envelope button was.
private struct HomeGameNoteLine: View {
    @ObservedObject var game: Game
    let note: HomeGameNote
    @Environment(\.surroundTheme) private var theme

    var body: some View {
        if note == .conditionalMoves, let gameID = game.ogsID {
            ConditionalMovesButton(game: game, context: .home(gameID: gameID), usesHomeLineStyle: true)
        } else {
            HStack(spacing: 4) {
                switch note {
                case .paused:
                    Image(systemName: "pause.fill").font(.system(size: 10))
                case .teammateMove, .userNextOnTeam:
                    Image(systemName: "person.2").font(.system(size: 11))
                default:
                    EmptyView()
                }
                Text(verbatim: note.text)
                    .lineLimit(1)
            }
            .font(.footnote)
            .modifier(HomeSecondaryText())
        }
    }
}

// MARK: - Tile (Large)

/// The Large tile: the board edge to edge between the two chips. Boards are
/// never smaller than `HomeLayout.largeBoardSize`, where a 19×19 stone
/// reaches the 14 pt detail threshold, so a theme's textures and art show.
struct HomeGameTile: View {
    @ObservedObject var game: Game
    /// Nil shows a game without opening it, as Welcome's public games do.
    var opensGame: (() -> Void)?
    var navigationAccessibilityIdentifier = ""

    @EnvironmentObject private var ogs: OGSService

    static var minimumWidth: CGFloat { HomeLayout.largeTileWidth }

    var body: some View {
        let facts = HomeGameFacts(game: game, user: ogs.user)
        VStack(spacing: 8) {
            HomeClockChip(game: game, facts: facts, color: facts.topColor, size: .tile) {
                if let opponent = facts.opponent {
                    HomePlayerName(player: opponent, surface: facts.topColor, extra: facts.opponentTeamExtra,
                                   nameFont: .subheadline.weight(.semibold), rankFont: .footnote)
                }
            }
            // The combined chip carries the name's identifier, as the row's name does.
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(navigationAccessibilityIdentifier.isEmpty
                                     ? "" : "\(navigationAccessibilityIdentifier).playerInfo")
            Group {
                if let opensGame {
                    HomeBoardButton(game: game, opensGame: opensGame,
                                    accessibilityIdentifier: navigationAccessibilityIdentifier,
                                    accessibilityLabel: facts.accessibilityLabel)
                } else {
                    BoardView(boardPosition: game.currentPosition)
                        .accessibilityElement()
                        .accessibilityLabel(Text(verbatim: facts.accessibilityLabel))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            HomeClockChip(game: game, facts: facts, color: facts.bottomColor, size: .tile) {
                if facts.userColor != nil {
                    Text("You")
                        .font(.footnote.weight(.medium))
                        .opacity(0.72)
                    if !game.isUserTurn, !game.conditionalMoveBranches.isEmpty, let gameID = game.ogsID {
                        ConditionalMovesButton(game: game, context: .home(gameID: gameID), usesHomeLineStyle: true,
                                               showsHomeLineTitle: false)
                    }
                } else if let player = game.currentPlayer(with: facts.bottomColor) {
                    HomePlayerName(player: player, surface: facts.bottomColor,
                                   nameFont: .subheadline.weight(.semibold), rankFont: .footnote)
                }
            }
            .accessibilityElement(children: .contain)
        }
        .padding(HomeLayout.largeTilePadding)
        .contentShape(Rectangle())
        .onTapGesture { opensGame?() }
        .modifier(GamePlayerProfileMenu(game: game))
    }
}

// MARK: - Board

/// The board is the row's button; the rest of the row opens the game with
/// a tap, so the conditional-moves line keeps its own button.
private struct HomeBoardButton: View {
    @ObservedObject var game: Game
    var opensGame: () -> Void
    var accessibilityIdentifier: String
    var accessibilityLabel: String

    var body: some View {
        Button(action: opensGame) {
            ZStack {
                ZStack {
                    BoardView(boardPosition: game.currentPosition)
                    if game.gameData == nil {
                        Rectangle().fill(GameDetailSurfaceStyle(role: .panel).opacity(0.65))
                        ProgressView()
                            .accessibilityLabel(Text("Loading game…"))
                    }
                }
                .allowsHitTesting(false)
                Color.clear.contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
    }
}

// MARK: - Surfaces

/// A themed card: the theme's panel with its border, as in Game Detail.
struct HomeCard: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(GameDetailSurfaceStyle(role: .panel), in: shape)
            .clipShape(shape)
            .overlay { shape.strokeBorder(GameDetailSurfaceStyle(role: .panelBorder), lineWidth: 1) }
    }
}

/// Links and small actions in the theme's action color.
struct HomeActionText: ViewModifier {
    @Environment(\.surroundTheme) private var theme

    func body(content: Content) -> some View {
        content.foregroundStyle(theme.actionTint ?? .accentColor)
    }
}

/// The main action: white on the theme's action color, as New game is.
struct HomeActionSurface: ViewModifier {
    @Environment(\.surroundTheme) private var theme

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .background(theme.homeActionFill, in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1) }
    }
}

// MARK: - Placeholder

/// The first load's placeholder row: static shapes, no shimmer.
struct HomeSkeletonRow: View {
    var showsSeparator = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
                .frame(width: HomeGameRow.boardSize, height: HomeGameRow.boardSize)
                .padding(.vertical, 10)
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(.quaternary).frame(width: 120, height: 14)
                Capsule().fill(.quaternary).frame(width: 160, height: 10)
                Spacer(minLength: 6)
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary).frame(height: 28)
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary).frame(height: 28)
            }
            .padding(.vertical, 12)
            .padding(.trailing, 12)
            .overlay(alignment: .top) {
                if showsSeparator {
                    Rectangle().fill(GameDetailSurfaceStyle(role: .panelBorder)).frame(height: 0.5)
                }
            }
        }
        .padding(.leading, 12)
        .frame(height: HomeGameRow.boardSize + 20)
        .accessibilityHidden(true)
    }
}
