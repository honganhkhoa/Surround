import SwiftUI
import AVFoundation

private func gameDetailProfileColor(_ player: OGSUser?, dark: Bool) -> Color {
    guard let player else { return .secondary }
    if !dark, !player.isOGSModerator, !player.isOGSAdmin {
        if player.isOGSProfessional { return Color(red: 15 / 255, green: 107 / 255, blue: 51 / 255) }
        if player.isOGSSupporter { return Color(red: 153 / 255, green: 71 / 255, blue: 8 / 255) }
    }
    let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
    return Color(uiColor: UIColor(player.uiColor).resolvedColor(with: traits))
}

/// The neutral Game Detail surfaces follow the theme, and in the standard
/// theme the system's light/dark appearance.
enum GameDetailAppearance {
    static let background = GameDetailSurfaceStyle(role: .page)
    static let panel = GameDetailSurfaceStyle(role: .panel)
    static let panelBorder = GameDetailSurfaceStyle(role: .panelBorder)
}

/// The order follows the players' corners, independently of their stone colors.
struct GameDetailClockPair: View {
    @ObservedObject var game: Game
    var topLeftPlayerColor: StoneColor
    var stacked = false
    var style: GameDetailClockStyle = .full
    var narrowFullCards = false
    var narrowCompactCards = false
    var spaciousCompact = false
    /// Duo Closed landscape's 126 pt column: badge row, time, komi on its
    /// own line (White) and periods · captures on one line.
    var columnCards = false
    /// v149, the same column: each card's detail line where it needs a
    /// second line (the layout plan allows it only when the column has the
    /// room), and whether both cards grow by that line.
    var columnDetailLayouts = GameDetailColumnDetailLayouts()
    var columnCardsGrow = false
    var isInToolbar = false
    var showsCurrentPlayerOnly = false
    /// The layout's full-card scale, which regular accessibility sizes cap.
    var fullCardScale: CGFloat? = nil
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var showsRoleNames = false
    /// A header can consume the first tap to dismiss an attached keyboard.
    var onTapBeforeDetails: (() -> Bool)? = nil
    var blocksGameActions = false
    var showsStatus = true
    @EnvironmentObject private var ogs: OGSService

    /// The game's one disconnect snapshot (OGSService), shared by the body
    /// and header pairs, so remounting a pair never shows a later local tick.
    private var disconnectedClock: OGSClock? {
        ogs.socketStatus == .connected ? nil : game.disconnectedClock
    }

    private var layout: AnyLayout {
        // Inline faces are 10pt shorter than their touch targets. The two
        // expanded targets share 2pt; both open the same game information.
        stacked ? AnyLayout(VStackLayout(alignment: style == .inline ? .trailing : .center,
                                         spacing: style == .inline ? -2 : 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    @ViewBuilder private var cards: some View {
        if isInToolbar && style == .inline && !stacked {
            // A title slot gets what Back and the bar items leave, which can be
            // less than the layout plan expects. Fit the chips before painting:
            // a pair shows the glow alone; a single chip drops its turn label,
            // then its periods.
            ViewThatFits(in: .horizontal) {
                if !showsCurrentPlayerOnly {
                    clockCards(currentOnly: false, detail: .withoutStatusLabel)
                        .fixedSize(horizontal: true, vertical: false)
                }
                clockCards(currentOnly: true, detail: .full)
                    .fixedSize(horizontal: true, vertical: false)
                clockCards(currentOnly: true, detail: .withoutStatusLabel)
                    .fixedSize(horizontal: true, vertical: false)
                clockCards(currentOnly: true, detail: .countdownOnly)
            }
        } else {
            clockCards(currentOnly: showsCurrentPlayerOnly, detail: .full)
        }
    }

    private func clockCards(currentOnly: Bool, detail: GameDetailInlineChipDetail) -> some View {
        layout {
            if currentOnly {
                card(GameDetailClockState.singleChipColor(game: game, clock: disconnectedClock),
                     currentOnly: true, detail: detail)
            } else {
                card(topLeftPlayerColor, currentOnly: false, detail: detail)
                card(topLeftPlayerColor.opponentColor(), currentOnly: false, detail: detail)
            }
        }
        .frame(maxWidth: stacked && style == .inline ? .infinity : nil, alignment: .trailing)
    }

    private var scale: CGFloat { min(textScale, 1.65) }

    private var cardHeight: CGFloat {
        if style == .full && columnCards {
            return ceil(GameDetailColumnDetailLayouts.fullCardHeight(grown: columnCardsGrow) * scale)
        }
        let baseHeight: CGFloat = style == .full && narrowFullCards ? 110
            : (style == .compact && dynamicTypeSize.isAccessibilitySize ? 76
               : (style == .compact && compactStatusOnOwnRow ? (spaciousCompact ? 76 : 68)
                  : (style == .compact && spaciousCompact ? 60 : style.cardHeight)))
        let cardScale = style == .full ? min(scale, fullCardScale ?? scale) : scale
        // The column's two-line chips grow by one detail line together.
        let grownLine: CGFloat = style == .compact && columnCardsGrow
            ? GameDetailColumnDetailLayouts.compactLineGrowth : 0
        return max(44, (baseHeight + grownLine) * cardScale)
    }

    private var compactStatusOnOwnRow: Bool {
        narrowCompactCards || (showsStatus && (spaciousCompact || textScale > 1.2))
    }

    @ViewBuilder private func card(_ color: StoneColor, currentOnly: Bool,
                                   detail: GameDetailInlineChipDetail) -> some View {
        if style != .inline || !isInToolbar {
            // Scene clocks use the proposal, independently of the current
            // countdown, turn badge or phase. GeometryReader gives both sides
            // equal flexible slots in a row and the full width when stacked.
            // Only native title-bar chips are allowed to hug their content.
            GeometryReader { geometry in
                clockCard(color, cardWidth: geometry.size.width, currentOnly: currentOnly, detail: detail)
            }.frame(height: cardHeight)
        } else {
            clockCard(color, currentOnly: currentOnly, detail: detail)
        }
    }

    private func clockCard(_ color: StoneColor, cardWidth: CGFloat = .infinity,
                           currentOnly: Bool, detail: GameDetailInlineChipDetail) -> some View {
        GameDetailClockCard(game: game, color: color, style: style,
                            height: cardHeight,
                            narrowFullCard: narrowFullCards,
                            narrowCompactCard: compactStatusOnOwnRow,
                            spaciousCompact: spaciousCompact,
                            columnCard: columnCards && style == .full,
                            columnDetailLayout: style == .inline ? .oneLine : columnDetailLayouts[color],
                            capsFullCountdown: style == .full && (fullCardScale ?? scale) < scale,
                            cardWidth: cardWidth,
                            clockOverride: disconnectedClock,
                            isConnected: ogs.socketStatus == .connected,
                            mirrored: !currentOnly && !stacked && color != topLeftPlayerColor,
                            showsRoleName: showsRoleNames,
                            revealsBothClocks: currentOnly,
                            onTapBeforeDetails: onTapBeforeDetails,
                            blocksGameActions: blocksGameActions,
                            showsStatus: showsStatus,
                            inlineDetail: detail)
        .frame(maxWidth: style == .inline && isInToolbar ? nil : .infinity)
    }

    /// The width a full card needs to keep its periods and captures on one
    /// line, card padding included, for the game's current values. Both cards
    /// share the widest so the pair keeps one height.
    static func fullFooterWidth(game: Game, scale: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 13 * scale)
        let emphasizedFont = UIFont.systemFont(ofSize: 13 * scale, weight: .semibold)
        func width(_ text: String, _ font: UIFont) -> CGFloat {
            text.isEmpty ? 0 : ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        return [StoneColor.black, .white].map { color -> CGFloat in
            let state = GameDetailClockState(game: game, color: color)
            // Scoring cards show their breakdown in place of this footer.
            guard !state.isScoring else { return 0 }
            var detail = width(state.isFinished ? state.resultDetail : "", font)
            if state.autoResign != nil {
                detail = width(String(localized: "Disconnected"), emphasizedFont)
            } else if !state.isFinished && state.canShowTimer {
                detail = width(state.paused ? state.pauseReason : state.fullTimeDetail, font)
                    + (state.paused ? ceil(13 * scale) + 3 : 0)
            }
            let captures = width(String(localized: "\(state.captures) captures"), font)
            // Two 4 pt gaps around the spacer, and 12 pt card padding per side.
            return detail + captures + 8 + 24
        }.max() ?? 0
    }

    /// The width a two-line chip needs to keep its time, turn badge and komi
    /// on one line, for the game's time system at this text size (rule 12:
    /// the badge never truncates and both chips keep the same time size).
    /// Chips narrower than this put the badge on its own row, both of them.
    static func compactLineWidth(game: Game, scale: CGFloat) -> CGFloat {
        func width(_ text: String, _ font: UIFont) -> CGFloat {
            text.isEmpty ? 0 : ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        let maximumTime: Int
        switch game.gameData?.timeControl.system {
        case .ByoYomi(let main, _, let period): maximumTime = max(main, period)
        case .Fischer(let initial, let increment, let maximum): maximumTime = max(initial, increment, maximum)
        case .Canadian(let main, let period, _): maximumTime = max(main, period)
        case .Simple(let perMove): maximumTime = perMove
        case .Absolute(let total): maximumTime = total
        default: maximumTime = 0
        }
        let timeFont = UIFont.monospacedDigitSystemFont(ofSize: 20 * scale, weight: .semibold)
        let countdown = [0, 59, 3_599, min(maximumTime, 86_399), min(maximumTime, 172_799), maximumTime]
            .map { width(timeString(timeLeft: TimeInterval($0)), timeFont) }.max() ?? 0
        let badgeFont = UIFont.systemFont(ofSize: 12 * scale, weight: .semibold)
        let titles = [String(localized: "Your move", comment: "Game"), String(localized: "Their move"),
                      String(localized: "To move"), String(localized: "Teammate"), String(localized: "Passed")]
        // Title, hourglass and its 3 pt gap, 6 pt capsule padding per side.
        // Typed in parts: Xcode 26.2's type checker times out on one expression.
        let widestTitle: CGFloat = titles.map { width($0, badgeFont) }.max() ?? 0
        let hourglass: CGFloat = ceil(10 * scale)
        let badge: CGFloat = widestTitle + hourglass + 3 + 12
        let komi = game.gameData.map {
            width(String(localized: "\(gameDetailPoints($0.komi)) komi"), UIFont.systemFont(ofSize: 11 * scale))
        } ?? 0
        // 8 pt card padding per side and 4 pt between the parts.
        return 16 + countdown + 4 + badge + (komi > 0 ? 4 + komi : 0)
    }

    var body: some View {
        Group {
            if #available(iOS 26, *), !isInToolbar {
                GlassEffectContainer(spacing: 4) { cards }
            } else {
                // The native toolbar already hosts glass. Nesting a separate
                // container here can create a zero-sized interaction host.
                cards
            }
        }
        .opacity(ogs.socketStatus == .connected ? 1 : 0.65)
        .onChange(of: game.ID, initial: true) { _, _ in
            // A game the service did not freeze (shown before its connection
            // was requested) takes its snapshot here, once for every pair.
            ogs.freezeClockIfDisconnected(game)
        }
        .onReceive(game.$clock.dropFirst()) { _ in
            // If the screen opened before its first clock arrived, keep that
            // first value while disconnected. Never stop the shared model.
            DispatchQueue.main.async { ogs.freezeClockIfDisconnected(game) }
        }
    }
}

/// What a title-slot chip keeps when the native bar leaves it less room.
enum GameDetailInlineChipDetail {
    case full, withoutStatusLabel, countdownOnly
}

private struct GameDetailNotificationContextKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    /// The visible Game Detail's notification context (NavigationService),
    /// shared by its content and its native toolbar items.
    var gameDetailNotificationContextID: UUID? {
        get { self[GameDetailNotificationContextKey.self] }
        set { self[GameDetailNotificationContextKey.self] = newValue }
    }
}

/// Registers a Reconnecting… badge while it is actually on screen: mounted,
/// in a slot the layout shows, and in the chip variant the title slot chose.
/// The banner reads these only for a Game Detail context that is visible.
private struct GameDetailReconnectingBadgeReport: ViewModifier {
    let isShown: Bool
    @Environment(\.gameDetailNotificationContextID) private var contextID
    @Environment(\.gameDetailSlotVisible) private var slotVisible
    @EnvironmentObject private var nav: NavigationService
    @State private var badgeID = UUID()
    @State private var context: UUID?

    private var reports: Bool { isShown && slotVisible }

    private func report(_ shown: Bool) {
        if let context, context != contextID {
            nav.setGameDetailReconnectingBadge(badgeID, context: context, shown: false)
        }
        context = contextID
        guard let contextID else { return }
        nav.setGameDetailReconnectingBadge(badgeID, context: contextID, shown: shown)
    }

    func body(content: Content) -> some View {
        content
            .onAppear { report(reports) }
            .onDisappear { report(false) }
            .onChange(of: reports) { _, shown in report(shown) }
            .onChange(of: contextID) { _, _ in report(reports) }
    }
}

private struct GameDetailClockUndoAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct GameDetailClockCard: View {
    @ObservedObject var game: Game
    let color: StoneColor
    let style: GameDetailClockStyle
    let height: CGFloat
    var narrowFullCard = false
    var narrowCompactCard = false
    var spaciousCompact = false
    var columnCard = false
    /// v149: in Duo Closed landscape's column, the detail line can take a
    /// second line (decided by the layout plan for both cards).
    var columnDetailLayout = GameDetailColumnDetailLayout.oneLine
    var capsFullCountdown = false
    var cardWidth: CGFloat = .infinity
    var clockOverride: OGSClock?
    var isConnected: Bool
    var mirrored: Bool
    var showsRoleName: Bool
    var revealsBothClocks = false
    var onTapBeforeDetails: (() -> Bool)? = nil
    var blocksGameActions = false
    var showsStatus = true
    var inlineDetail = GameDetailInlineChipDetail.full
    @EnvironmentObject private var ogs: OGSService
    @Environment(\.gameDetailSlotVisible) private var slotVisible
    @State private var showsDetails = false
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.surroundTheme) private var theme

    private var state: GameDetailClockState {
        .init(game: game, color: color, clockOverride: clockOverride, isConnected: isConnected)
    }
    private var foreground: Color {
        theme.clockForeground(color, scheme: colorScheme)
    }
    private var accent: Color {
        if state.suddenDeath {
            return theme.clockSuddenDeathAccent(color, scheme: colorScheme)
        }
        return theme.clockAccent(color)
    }
    private var turnOutline: Color {
        if state.suddenDeath { return Color(uiColor: .systemRed) }
        return theme.turnOutline(scheme: colorScheme)
    }
    private var turnGlow: Color {
        state.suddenDeath ? Color(uiColor: .systemRed) : theme.turnGlow
    }
    // Match the scale used by the layout plan. Letting semantic fonts grow
    // beyond that cap makes their ideal height escape the fixed clock surface.
    private var scale: CGFloat { min(textScale, 1.65) }
    private var detailFont: Font {
        .system(size: (columnCard ? 12 : (style == .full || spaciousCompact ? 13 : 11)) * scale)
    }
    private var smallFont: Font { .system(size: 12 * scale) }
    private var mainFont: Font {
        let size: CGFloat = columnCard ? 18 : style == .full ? (cardWidth < 145 ? 21 : 30)
            : (style == .compact ? (spaciousCompact ? 24 : (cardWidth < 145 ? 18 : 20)) : 15)
        // A capped accessibility card keeps the countdown near 36 pt so the
        // larger metadata lines fit the same card.
        let countdownScale = capsFullCountdown ? min(scale, 1.2) : scale
        return .system(size: size * countdownScale, weight: .semibold).monospacedDigit()
    }
    /// A narrow title chip can drop its turn label; the glow still shows the turn.
    private var displaysStatus: Bool {
        showsStatus && (style != .inline || inlineDetail == .full)
    }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: spaciousCompact ? 14 : 12)
    }

    private var alignment: HorizontalAlignment { mirrored ? .trailing : .leading }
    private var frameAlignment: Alignment { mirrored ? .trailing : .leading }
    private var badgeTitle: String {
        displaysStatus ? state.badgeTitle(narrow: style != .inline && cardWidth < 125) : ""
    }
    private var hasUndoMenu: Bool {
        displaysStatus && isConnected && (state.canAnswerUndo || state.canWithdrawUndo)
    }
    private var badgeBackground: Color {
        if state.reconnecting { return theme.statusBadge }
        if state.ownsUndoRequest { return Color(red: 196 / 255, green: 106 / 255, blue: 0) }
        if state.passed || (state.notStarted && !state.firstMoveDeadline) {
            return Color(uiColor: .systemGray)
        }
        return state.suddenDeath ? Color.red : theme.statusBadge
    }
    private var agreementColor: Color {
        color == .black ? Color(red: 125 / 255, green: 210 / 255, blue: 141 / 255)
            : Color(red: 30 / 255, green: 122 / 255, blue: 52 / 255)
    }
    private var disconnectedColor: Color {
        color == .black ? Color(red: 1, green: 159 / 255, blue: 10 / 255)
            : Color(red: 160 / 255, green: 72 / 255, blue: 0)
    }

    var body: some View {
        Button {
            guard onTapBeforeDetails?() != true else { return }
            showsDetails = true
        } label: {
            content
                // Column cards keep their rows aligned across the pair: the
                // white card's komi line leaves the black card space below.
                .padding(.top, columnCard ? 4 * scale : 0)
                .frame(maxHeight: columnCard ? .infinity : nil, alignment: .top)
                .foregroundStyle(foreground)
                .padding(.horizontal, spaciousCompact ? 14 : (style == .full ? (columnCard ? 10 : 12) : 8))
                .frame(minWidth: 44, maxWidth: style == .inline && !cardWidth.isFinite ? nil : .infinity)
                .frame(height: style == .inline ? max(34, height - 10) : height)
                .background { surface }
                .overlay { clockOutline }
                .modifier(GameDetailClearGlass(shape: shape,
                                               enabled: !reduceTransparency && (theme != .rakedGarden || contrast != .increased),
                                               tint: showsThemeGlass ? theme.clockGlassTint(color) : nil))
                .frame(height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: state.accessibilityLabel))
        .accessibilityValue(Text(verbatim: state.accessibilityValue))
        .accessibilityHint("Shows game details")
        // VoiceOver skips a clock kept mounted in an empty slot, but XCTest
        // still lists it; only the clock on screen carries the clock's name.
        .accessibilityIdentifier((color == .black ? "game.clock.black" : "game.clock.white")
            + (slotVisible ? "" : ".hidden"))
        .overlayPreferenceValue(GameDetailClockUndoAnchor.self) { anchor in
            if hasUndoMenu, let anchor {
                GeometryReader { geometry in
                    let frame = geometry[anchor]
                    undoMenu
                        .frame(width: max(44, frame.width), height: max(44, frame.height))
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .popover(isPresented: $showsDetails) {
            GameDetailClockDetails(game: game, showsClocks: revealsBothClocks || style == .inline,
                                   clockOverride: clockOverride, isConnected: isConnected)
        }
    }

    private var undoMenu: some View {
        Group {
            if let onTapBeforeDetails {
                Button { _ = onTapBeforeDetails() } label: { undoMenuLabel }
            } else {
                Menu {
                    if state.canAnswerUndo {
                        Button {
                            guard !blocksGameActions, ogs.socketStatus == .connected,
                                  state.canAnswerUndo else { return }
                            ogs.acceptUndo(game: game)
                        } label: { Label("Accept undo", systemImage: "arrow.uturn.left") }
                        Button {
                            guard !blocksGameActions, ogs.socketStatus == .connected,
                                  state.canAnswerUndo else { return }
                            ogs.cancelUndo(game: game)
                        } label: { Label("Reject undo", systemImage: "xmark") }
                    } else if state.canWithdrawUndo {
                        Button {
                            guard !blocksGameActions, ogs.socketStatus == .connected,
                                  state.canWithdrawUndo else { return }
                            ogs.cancelUndo(game: game)
                        } label: { Label("Cancel undo", systemImage: "xmark") }
                    }
                } label: { undoMenuLabel }
            }
        }
        .buttonStyle(.plain)
        .disabled(blocksGameActions || !isConnected)
        .accessibilityLabel(Text(verbatim: badgeTitle))
        .accessibilityIdentifier("game.clock.undo")
    }

    private var undoMenuLabel: some View {
        statusBadge.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }

    private var statusBadgeSlot: some View {
        statusBadge.opacity(hasUndoMenu ? 0 : 1)
            .anchorPreference(key: GameDetailClockUndoAnchor.self, value: .bounds) { $0 }
            // The app's connection banner gives way only to a rendered badge.
            .modifier(GameDetailReconnectingBadgeReport(
                isShown: state.reconnecting && !badgeTitle.isEmpty))
    }

    @ViewBuilder private var statusBadge: some View {
        if !badgeTitle.isEmpty {
            if style == .inline {
                HStack(spacing: 4) {
                    Rectangle().fill(foreground.opacity(0.3)).frame(width: 1, height: 12 * scale)
                    if state.reconnecting {
                        ProgressView().controlSize(.mini)
                    } else if state.ownsUndoRequest {
                        Image(systemName: "arrow.uturn.left")
                    }
                    Text(verbatim: badgeTitle)
                    if hasUndoMenu { Image(systemName: "chevron.down").font(.system(size: 8 * scale)) }
                }
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(state.ownsUndoRequest ? badgeBackground : foreground)
                .lineLimit(1).minimumScaleFactor(0.7)
            } else {
            HStack(spacing: 3) {
                if state.reconnecting {
                    ProgressView().controlSize(.mini).tint(.white)
                } else if state.ownsUndoRequest {
                    Image(systemName: "arrow.uturn.left").font(.system(size: 10 * scale))
                } else if state.running && !state.ownsUndoRequest && !state.notStarted {
                    // The hourglass, like the glow, means the time is running.
                    Image(systemName: "hourglass").font(.system(size: 10 * scale))
                }
                Text(verbatim: badgeTitle)
                if hasUndoMenu { Image(systemName: "chevron.down").font(.system(size: 8 * scale, weight: .semibold)) }
            }
            .font(.system(size: 12 * scale, weight: .semibold))
            .lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(badgeBackground, in: Capsule())
            }
        }
    }

    /// Scene clocks in a glass theme; header chips already sit on the bar's
    /// glass, and accessibility settings keep the solid surfaces.
    private var showsThemeGlass: Bool {
        guard theme.usesGlassControls, style != .inline, !reduceTransparency, contrast != .increased else {
            return false
        }
        if #available(iOS 26, *) { return true }
        return false
    }

    @ViewBuilder private var surface: some View {
        if showsThemeGlass {
            Color.clear
        } else if reduceTransparency || contrast == .increased {
            shape.fill(theme.clockSolidSurface(color))
        } else {
            shape.fill(LinearGradient(stops: theme.clockSurfaceStops(color, scheme: colorScheme),
                                      startPoint: .top, endPoint: .bottom))
                .opacity(theme == .rakedGarden && style != .inline ? (color == .black ? 0.94 : 0.90) : 1)
                .background {
                    if theme == .rakedGarden && style != .inline {
                        shape.fill(.regularMaterial)
                    }
                }
        }
    }

    // The halo and outline belong to the glass's foreground content. Applying
    // a shadow after glassEffect lets the native compositor cover it. A blurred
    // ring keeps the center clear while leaving the active edge visible.
    private var clockOutline: some View {
        ZStack {
            if state.running && contrast != .increased {
                shape.strokeBorder(turnGlow.opacity(colorScheme == .dark ? 0.6 : 0.55), lineWidth: 6)
                    .blur(radius: style == .inline ? 6 : (colorScheme == .dark ? 9 : 8))
            }
            shape.strokeBorder(
                state.running
                    ? turnOutline.opacity(contrast == .increased ? 1 : (colorScheme == .dark ? 0.85 : 0.7))
                    : (contrast == .increased ? foreground.opacity(0.5) : theme.panelBorder),
                lineWidth: contrast == .increased ? 2 : 1
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        if style == .inline {
            inlineContent(showsTimeDetail: inlineDetail != .countdownOnly && inlineTimeDetailFits)
            .font(detailFont)
            .opacity(state.paused || (state.notStarted && !state.firstMoveDeadline) ? 0.6 : 1)
            .lineLimit(1)
            // Toolbar space also depends on Back and notification controls.
            // Accept its proposal so the complete time/detail row scales
            // inside the card instead of painting across neighboring buttons.
            .minimumScaleFactor(0.5)
        } else {
            VStack(alignment: alignment, spacing: columnCard ? 1 : 3) {
                if showsRoleName && style != .compact {
                    Text(verbatim: state.roleName).font(smallFont.weight(.semibold))
                }
                if style == .full { header.frame(height: columnCard ? 18 * scale : nil) }
                primaryContent.frame(maxWidth: .infinity, alignment: frameAlignment)
            }
            // A full card can contain a header and two metadata lines. Eight
            // points per edge made SwiftUI shrink the 30pt countdown to fit its
            // 96pt surface; four preserves the type size and centered content.
            .padding(.vertical, 4)
        }
    }

    private func inlineContent(showsTimeDetail: Bool) -> some View {
        HStack(spacing: 4) {
            if state.isScoring {
                Image(systemName: state.accepted ? "checkmark.circle.fill" : "hourglass")
                    .foregroundStyle(state.accepted ? agreementColor : accent)
                scoreValue
                if !state.accepted, let expiration = state.clock?.timeUntilExpiration {
                    Text(timeString(timeLeft: expiration)).font(detailFont.monospacedDigit())
                }
            } else if state.isFinished {
                Text(state.resultTitle).font(mainFont)
            } else if let deadline = state.autoResign {
                Image(systemName: "bolt.slash")
                    .foregroundStyle(disconnectedColor)
                Text(timeString(timeLeft: deadline)).font(mainFont)
                    .foregroundStyle(disconnectedColor)
                if displaysStatus {
                    if state.reconnecting {
                        statusBadgeSlot
                    } else {
                        Text("Disconnected").font(detailFont)
                            .foregroundStyle(disconnectedColor)
                    }
                }
            } else if state.canShowTimer {
                TimerView(timeControl: state.valueTimeControl,
                          clock: state.valueClock, player: color,
                          mainFont: mainFont, subFont: smallFont.monospacedDigit())
                    .foregroundStyle(state.suddenDeath ? accent : foreground)
                if showsTimeDetail || !hasOptionalInlineTimeDetail {
                    Text(state.paused ? state.pauseReason : state.inlineTimeDetail).font(detailFont)
                }
                inlineTurnIndicator
            } else {
                Text(state.compactUnavailableTimeText).font(mainFont)
                inlineTurnIndicator
            }
        }
    }

    /// Increments and overtime details remain in accessibility and game details
    /// when a one-line chip needs its width for the countdown and current status.
    /// Pause reasons and first-move deadlines are always retained.
    private var hasOptionalInlineTimeDetail: Bool {
        guard !state.paused, !state.firstMoveDeadline else { return false }
        switch game.gameData?.timeControl.system {
        case .ByoYomi, .Fischer, .Canadian: return true
        default: return false
        }
    }

    private var inlineTimeDetailReservation: (maximumTime: Int, labels: [String])? {
        switch game.gameData?.timeControl.system {
        case .ByoYomi(let main, let periods, let period):
            return (max(0, main, period), ["+\(max(1, periods))×", String(localized: "SD")])
        case .Fischer(let initial, let increment, let maximum):
            let duration = increment >= 86_400
                ? durationString(seconds: increment) : timeString(timeLeft: increment)
            return (max(0, initial, increment, maximum), ["+ \(duration)"])
        case .Canadian(let main, let period, let moves):
            return (max(0, main, period), ["+ \(timeString(timeLeft: period))/\(moves)",
                                            String(localized: "\(moves) stones")])
        default: return nil
        }
    }

    /// Decide from the slot and the game's rules, never the current countdown
    /// or badge. A turn, undo request or reconnect must not add/remove metadata
    /// while the same matched pair remains in place.
    private var inlineTimeDetailFits: Bool {
        guard cardWidth.isFinite, let reservation = inlineTimeDetailReservation else {
            return true
        }
        let mainFont = UIFont.monospacedDigitSystemFont(ofSize: 15 * scale, weight: .semibold)
        let detailFont = UIFont.systemFont(ofSize: 11 * scale)
        let badgeFont = UIFont.systemFont(ofSize: 12 * scale, weight: .semibold)
        let maximumTime = reservation.maximumTime
        let timeSamples = [0, 59, 3_599, min(maximumTime, 86_399),
                           min(maximumTime, 172_799), maximumTime]
        let countdownWidth = timeSamples.map {
            (timeString(timeLeft: TimeInterval($0)) as NSString).size(withAttributes: [.font: mainFont]).width
        }.max() ?? 0
        let detailWidth = reservation.labels.map {
            ($0 as NSString).size(withAttributes: [.font: detailFont]).width
        }.max() ?? 0
        let statusWidth: CGFloat
        if showsStatus {
            let titles = [String(localized: "Reconnecting…"), String(localized: "Undo?"),
                          String(localized: "Undo asked"), String(localized: "Passed"),
                          String(localized: "Not started"), String(localized: "To move"),
                          String(localized: "Teammate"), String(localized: "Your move", comment: "Game"),
                          String(localized: "Their move")]
            let titleWidth = titles.map {
                ($0 as NSString).size(withAttributes: [.font: badgeFont]).width
            }.max() ?? 0
            // The badge already permits 70% text scaling. Reserve every title,
            // spinner/undo icon and disclosure at that supported minimum before
            // removing useful time metadata from a wider one-line clock.
            statusWidth = (titleWidth + 24 * scale) * 0.7 + 12
        } else {
            statusWidth = 12 * scale
        }
        return cardWidth >= ceil(16 + countdownWidth + detailWidth + statusWidth + 8)
    }

    @ViewBuilder private var inlineTurnIndicator: some View {
        if displaysStatus && !badgeTitle.isEmpty {
            // A status label replaces the running hourglass. Showing both
            // needlessly shrinks the countdown inside a narrow matched chip.
            statusBadgeSlot
        } else if state.paused || inlineDetail == .full {
            // A chip fitted to its slot reserves no hidden hourglass. While
            // paused, only the side to move shows the pause glyph.
            Image(systemName: state.paused ? "pause.fill" : "hourglass")
                .font(smallFont)
                .opacity(state.paused ? (state.isToMove ? 1 : 0) : (displaysStatus && state.running ? 1 : 0))
                .accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            if columnCard {
                // Only the badge: komi has its own line under the time.
                clockIndicator
                Spacer(minLength: 0)
            } else {
                if mirrored { clockIndicator }
                if !mirrored { komiHeader }
                Spacer(minLength: 0)
                if mirrored { komiHeader }
                if !mirrored { clockIndicator }
            }
        }
        .font(detailFont.weight(.medium)).lineLimit(1)
        .frame(minHeight: 14)
    }

    @ViewBuilder private var komiHeader: some View {
        if color == .white, let komi = game.gameData?.komi {
            Text("\(gameDetailPoints(komi)) komi")
        }
    }

    @ViewBuilder private var clockIndicator: some View {
        if state.isScoring {
            if state.accepted {
                Label("Accepted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(agreementColor)
            } else if let expiration = state.clock?.timeUntilExpiration {
                Label(timeString(timeLeft: expiration), systemImage: "hourglass")
            } else {
                Image(systemName: "hourglass")
            }
        } else if showsStatus {
            statusBadgeSlot
        } else if state.running {
            Image(systemName: "hourglass").foregroundStyle(accent)
        }
    }

    @ViewBuilder private var primaryContent: some View {
        if state.isScoring {
            VStack(alignment: alignment, spacing: 2) {
                if style == .compact && narrowCompactCard {
                    HStack(spacing: 4) {
                        compactScoringIndicator
                        Spacer(minLength: 0)
                        compactKomi
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if style == .compact && !narrowCompactCard && mirrored {
                        compactScoringIndicator
                        Spacer(minLength: 0)
                    }
                    scoreValue
                    if style == .compact && !narrowCompactCard {
                        compactKomi
                    }
                    if style == .compact && !narrowCompactCard && !mirrored {
                        Spacer(minLength: 0)
                        compactScoringIndicator
                    }
                }
                Text(state.scoreBreakdown)
                    .font(detailFont)
                    .lineLimit(style == .compact ? 1 : nil)
                    .fixedSize(horizontal: false, vertical: true)
            }.lineLimit(1).minimumScaleFactor(0.7)
        } else if state.isFinished {
            VStack(alignment: alignment, spacing: 2) {
                Text(state.resultTitle).font(mainFont)
                detailRow(state.resultDetail)
            }.lineLimit(1).minimumScaleFactor(0.7)
        } else if let deadline = state.autoResign {
            VStack(alignment: alignment, spacing: 2) {
                if style == .compact && narrowCompactCard {
                    statusBadgeSlot.frame(height: 18 * scale, alignment: frameAlignment)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "bolt.slash")
                        .font(.system(size: (style == .full ? 18 : 12) * scale, weight: .semibold))
                        .foregroundStyle(disconnectedColor)
                    Text(timeString(timeLeft: deadline)).font(mainFont)
                        .foregroundStyle(disconnectedColor)
                    if style == .compact && !narrowCompactCard { statusBadgeSlot }
                }
                detailRow(String(localized: "Disconnected"), emphasized: true, detailColor: disconnectedColor)
            }.lineLimit(1).minimumScaleFactor(0.7)
        } else if state.canShowTimer {
            VStack(alignment: alignment, spacing: 2) {
                if style == .compact && narrowCompactCard {
                    // Reserve this row on both clocks, even when this side has
                    // no news, so a turn or undo request never shifts the time.
                    statusBadgeSlot.frame(height: 18 * scale, alignment: frameAlignment)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if style == .compact && mirrored { compactKomi }
                    if style == .compact && !showsStatus && state.running {
                        Image(systemName: "hourglass")
                            .font(smallFont).foregroundStyle(accent)
                    }
                    TimerView(timeControl: state.valueTimeControl,
                              clock: state.valueClock, player: color,
                              mainFont: mainFont, subFont: detailFont)
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: frameAlignment)
                    if style == .compact && !narrowCompactCard {
                        statusBadgeSlot
                    }
                    if style == .compact && !mirrored { compactKomi }
                }
                if columnCard { komiHeader.font(detailFont).lineLimit(1) }
                detailRow(state.paused ? state.pauseReason : (style == .full ? state.fullTimeDetail : state.timeDetail),
                          symbol: state.paused ? "pause.fill" : nil)
            }
            .foregroundStyle(state.suddenDeath ? accent : foreground)
            .opacity(state.paused || (state.notStarted && !state.firstMoveDeadline) ? 0.6 : 1)
            .lineLimit(1)
        } else {
            VStack(alignment: alignment, spacing: 2) {
                if style == .compact && narrowCompactCard {
                    statusBadgeSlot.frame(height: 18 * scale, alignment: frameAlignment)
                }
                Text(style == .full ? state.unavailableTimeText : state.compactUnavailableTimeText).font(.system(size: (style == .full ? 20 : 15) * scale))
                if style == .compact && !narrowCompactCard { statusBadgeSlot }
                detailRow("")
            }.lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private var scoreValue: Text {
        if state.score == nil { return Text(verbatim: state.scoreValue).font(mainFont) }
        return Text(verbatim: state.scoreValue).font(mainFont)
            + Text(" pts").font(detailFont).foregroundColor(foreground.opacity(0.75))
    }

    private var compactScoringIndicator: some View {
        HStack(spacing: 3) {
            Image(systemName: state.accepted ? "checkmark.circle.fill" : "hourglass")
                .foregroundStyle(state.accepted ? agreementColor : accent)
            if !state.accepted, let expiration = state.clock?.timeUntilExpiration {
                Text(timeString(timeLeft: expiration)).monospacedDigit()
            }
        }.font(detailFont).fixedSize()
    }

    @ViewBuilder private var compactKomi: some View {
        if !dynamicTypeSize.isAccessibilitySize {
            komiHeader.font(detailFont).fixedSize()
        }
    }

    @ViewBuilder private func detailRow(_ detail: String, symbol: String? = nil, emphasized: Bool = false,
                                       detailColor: Color? = nil) -> some View {
        if columnCard {
            Group {
                if let detailColor {
                    tintedCompactDetail(detail, tint: detailColor)
                } else {
                    metadataLine(compactDetail(detail), symbol: symbol)
                }
            }
            .font(detailFont.weight(emphasized ? .semibold : .regular))
            // The card's own foreground: a nil colour would reset the line to
            // the system primary (black on the black card, white on white in
            // dark mode). A tinted detail keeps its tint on its own segment.
            .foregroundColor(state.suddenDeath ? accent : foreground)
            // v149: a second line rather than an ellipsis (German), still
            // with the 75% minimum scale.
            .lineLimit(columnDetailLayout.wraps ? 2 : 1).minimumScaleFactor(0.75)
        } else if style == .compact {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: alignment, spacing: 0) {
                    metadataLine(detail, symbol: symbol).foregroundColor(detailColor ?? (state.suddenDeath ? accent : foreground))
                    captures
                }
                .font(.system(size: 13 * scale))
            } else {
                Group {
                    if let detailColor {
                        tintedCompactDetail(detail, tint: detailColor)
                    } else {
                        metadataLine(compactDetail(detail), symbol: symbol)
                    }
                }
                    .lineLimit(columnDetailLayout.wraps ? 2 : 1).minimumScaleFactor(0.75)
                    .font(detailFont.weight(emphasized ? .semibold : .regular))
            }
        } else if narrowFullCard {
            VStack(alignment: alignment, spacing: 0) {
                metadataLine(detail, symbol: symbol).fontWeight(emphasized ? .semibold : .regular)
                    .foregroundColor(detailColor ?? (state.suddenDeath ? accent : foreground))
                captures
            }.font(detailFont)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    if mirrored { captures.fixedSize() }
                    if mirrored { Spacer(minLength: 0) }
                    metadataLine(detail, symbol: symbol).fontWeight(emphasized ? .semibold : .regular).fixedSize()
                        .foregroundColor(detailColor ?? (state.suddenDeath ? accent : foreground))
                    if !mirrored { Spacer(minLength: 0) }
                    if !mirrored { captures.fixedSize() }
                }
                VStack(alignment: alignment, spacing: 0) {
                    metadataLine(detail, symbol: symbol).fontWeight(emphasized ? .semibold : .regular)
                        .foregroundColor(detailColor ?? (state.suddenDeath ? accent : foreground))
                    captures
                }
            }
            .font(detailFont)
        }
    }

    private func metadataLine(_ detail: String, symbol: String?) -> some View {
        // A two-line detail keeps its pause symbol on the first line.
        HStack(alignment: columnDetailLayout.wraps ? .firstTextBaseline : .center, spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            Text(verbatim: detail)
        }
        .multilineTextAlignment(mirrored ? .trailing : .leading)
    }

    /// " · " between the parts; a column line split at it breaks after the
    /// dot, so the periods (or note) and the captures each stay whole.
    private var compactDetailSeparator: String {
        columnDetailLayout == .splitAtSeparator ? " ·\n" : " · "
    }

    private func compactDetail(_ detail: String) -> String {
        let captures = String(localized: "\(state.captures) captures")
        let parts = mirrored ? [captures, detail] : [detail, captures]
        return parts.filter { !$0.isEmpty }.joined(separator: compactDetailSeparator)
    }

    private func tintedCompactDetail(_ detail: String, tint: Color) -> Text {
        let captures = String(localized: "\(state.captures) captures")
        let detailText = Text(verbatim: detail).foregroundColor(tint)
        return mirrored ? Text(verbatim: captures + compactDetailSeparator) + detailText
            : detailText + Text(verbatim: compactDetailSeparator + captures)
    }

    @ViewBuilder private var captures: some View {
        if style == .compact && dynamicTypeSize.isAccessibilitySize
            && showsRoleName && game.userStoneColor == color {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(state.roleName).font(.system(size: 11 * scale, weight: .medium))
                Spacer(minLength: 2)
                Text("\(state.captures) captures")
            }
        } else {
            Text("\(state.captures) captures")
        }
    }
}

private struct GameDetailClearGlass: ViewModifier {
    let shape: RoundedRectangle
    let enabled: Bool
    /// Regular glass in this tint; nil keeps clear glass over a solid fill.
    var tint: Color? = nil
    var interactive = true
    func body(content: Content) -> some View {
        if #available(iOS 26, *), enabled {
            if let tint {
                content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
            } else {
                content.glassEffect(.clear.interactive(interactive), in: shape)
            }
        } else {
            content
        }
    }
}

struct GameDetailPlayerIdentity: View {
    /// Match the uncapped semantic name/rank fonts when reserving a footer.
    /// Accessibility sizes use a fixed 64 pt row with capped text.
    static func rowHeight(dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return accessibilityRowHeight }
        let traits = identityTraits(dynamicTypeSize)
        let name = UIFont.preferredFont(forTextStyle: .callout, compatibleWith: traits)
        let rank = UIFont.preferredFont(forTextStyle: .footnote, compatibleWith: traits)
        return ceil(max(44, name.lineHeight + rank.lineHeight + 1) + 8)
    }

    /// Reserve both permitted name lines, so long names cannot move the board.
    static func columnHeight(dynamicTypeSize: DynamicTypeSize,
                             avatarSize: CGFloat = 52, padding: CGFloat = 8) -> CGFloat {
        let traits = identityTraits(dynamicTypeSize)
        let name = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits)
        let rank = UIFont.preferredFont(forTextStyle: .footnote, compatibleWith: traits)
        return ceil(max(44, avatarSize) + 8
                    + max(44, name.lineHeight * 2 + rank.lineHeight + 1) + padding * 2)
    }

    /// Duo Closed landscape's 126 pt column chip: a 32 pt avatar over the
    /// name and rank on one line each, 5 pt padding, 6 pt between. Without
    /// its second line (v149: ranks hidden, or the column's cards wrap) the
    /// chip is the avatar and the name only.
    static func compactColumnHeight(dynamicTypeSize: DynamicTypeSize, secondLine: Bool = true) -> CGFloat {
        let traits = identityTraits(dynamicTypeSize)
        let name = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits)
        let rank = UIFont.preferredFont(forTextStyle: .footnote, compatibleWith: traits)
        return ceil(5 + 32 + 6 + name.lineHeight + (secondLine ? 1 + rank.lineHeight : 0) + 5)
    }

    /// Whether a chip has a second line to show: the rank, unless ranks are
    /// hidden, or a Rengo team's Next and team size.
    static func hasSecondLine(game: Game, color: StoneColor, hidesRank: Bool) -> Bool {
        if !hidesRank && game.currentPlayer(with: color) != nil { return true }
        guard game.rengo else { return false }
        let teamSize = (game.orderedRengoTeam[color] ?? game.gameData?.rengoTeams?[color] ?? []).count
        return !GameDetailClockState(game: game, color: color).isFinished || teamSize > 1
    }

    /// The column's two chips share one height: either has a second line.
    static func columnChipsHaveSecondLine(game: Game, hidesRank: Bool) -> Bool {
        hasSecondLine(game: game, color: .black, hidesRank: hidesRank)
            || hasSecondLine(game: game, color: .white, hidesRank: hidesRank)
    }

    private static let accessibilityRowHeight: CGFloat = 64

    private static func identityTraits(_ dynamicTypeSize: DynamicTypeSize) -> UITraitCollection {
        let category: UIContentSizeCategory
        switch dynamicTypeSize {
        case .xSmall: category = .extraSmall
        case .small: category = .small
        case .medium: category = .medium
        case .large: category = .large
        case .xLarge: category = .extraLarge
        case .xxLarge: category = .extraExtraLarge
        case .xxxLarge: category = .extraExtraExtraLarge
        case .accessibility1: category = .accessibilityMedium
        case .accessibility2: category = .accessibilityLarge
        case .accessibility3: category = .accessibilityExtraLarge
        case .accessibility4: category = .accessibilityExtraExtraLarge
        case .accessibility5: category = .accessibilityExtraExtraExtraLarge
        @unknown default: category = .large
        }
        return UITraitCollection(preferredContentSizeCategory: category)
    }

    @ObservedObject var game: Game
    var color: StoneColor
    var vertical = false
    var facesBoard = false
    var navigationHeader = false
    var compactHeader = false
    var avatarOnly = false
    var columnAvatarSize: CGFloat = 52
    var columnPadding: CGFloat = 8
    /// Duo Closed landscape's column: one compact chip that opens the
    /// profile, on the board side (right) whichever corner it is.
    var compactColumn = false
    /// v149: the column chip's second line (rank, Rengo's Next). The layout
    /// drops it on both chips when the cards wrap, or when it has nothing.
    var columnSecondLine = true
    @Environment(\.openPlayerProfile) private var openPlayerProfile
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.surroundTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Setting(.hidesRank) private var hidesRank: Bool
    @State private var showsTeam = false
    #if DEBUG && MAIN_APP
    @State private var nameWidths = (shown: CGFloat(0), ideal: CGFloat(0))
    @State private var columnWidths = (column: CGFloat(0), secondLine: CGFloat(0), chip: CGFloat(0), chipHeight: CGFloat(0))
    #endif

    private var player: OGSUser? { game.currentPlayer(with: color) }
    private var team: [OGSUser] { game.orderedRengoTeam[color] ?? game.gameData?.rengoTeams?[color] ?? [] }
    private var secondaryColor: Color {
        theme.identitySecondary(color)
    }
    private var nameColor: Color { roleColor(player) }
    /// A row chip at accessibility sizes: 44 pt avatar, 22/20 pt text, 64 pt row.
    private var accessibleRow: Bool {
        !vertical && !navigationHeader && !compactHeader && dynamicTypeSize.isAccessibilitySize
    }

    private func roleColor(_ player: OGSUser?) -> Color {
        guard let player else { return secondaryColor }
        if let roleColor = theme.identityRoleColor(for: player, on: color) {
            return roleColor
        }
        if color == .white, !player.isOGSModerator, !player.isOGSAdmin {
            if player.isOGSProfessional { return Color(red: 15 / 255, green: 107 / 255, blue: 51 / 255) }
            if player.isOGSSupporter { return Color(red: 153 / 255, green: 71 / 255, blue: 8 / 255) }
        }
        // The side's surface decides the role variant even in the opposite
        // system appearance, just as a white stone remains white in Dark Mode.
        let traits = UITraitCollection(userInterfaceStyle: color == .black ? .dark : .light)
        return Color(uiColor: UIColor(player.uiColor).resolvedColor(with: traits))
    }

    var body: some View {
        Group {
            if game.rengo {
                Button { showsTeam = true } label: { identityContent.frame(minHeight: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: team.map(\.usernameAndRank).joined(separator: ", ")))
                    .accessibilityValue(Text("Next: \(player?.username ?? "—")"))
                    .accessibilityHint("Shows team turn order")
            } else {
                identityContent
            }
        }
        .padding(vertical ? (compactColumn ? 5 : columnPadding) : (compactHeader ? 0 : (accessibleRow ? 6 : 4)))
        .frame(minHeight: 44)
        // Paint the whole two-line reservation, keeping unused name space
        // inside the identity instead of enlarging its gap to the clock.
        .frame(height: vertical ? (compactColumn ? Self.compactColumnHeight(dynamicTypeSize: dynamicTypeSize,
                                                                            secondLine: columnSecondLine)
                                   : Self.columnHeight(dynamicTypeSize: dynamicTypeSize,
                                                       avatarSize: columnAvatarSize,
                                                       padding: columnPadding)) : nil,
               alignment: isBottomRightPlayer ? .bottom : .top)
        .background {
            if !showsThemeGlass {
                let translucentGarden = theme == .rakedGarden && !navigationHeader
                    && !reduceTransparency && contrast != .increased
                RoundedRectangle(cornerRadius: chipCornerRadius)
                    .fill(LinearGradient(colors: theme.identityChipColors(color), startPoint: .top, endPoint: .bottom))
                    .opacity(translucentGarden ? (color == .black ? 0.94 : 0.90) : 1)
                    .background {
                        if translucentGarden {
                            RoundedRectangle(cornerRadius: chipCornerRadius).fill(.regularMaterial)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: chipCornerRadius)
                            .strokeBorder(theme.identityChipBorder(color), lineWidth: 1)
                    }
            }
        }
        // The avatar and name are the chip's buttons; the glass itself
        // stays still.
        .modifier(GameDetailClearGlass(shape: RoundedRectangle(cornerRadius: chipCornerRadius),
                                       enabled: showsThemeGlass,
                                       tint: theme.identityGlassTint(color), interactive: false))
        .foregroundStyle(theme.identityForeground(color))
        #if DEBUG && MAIN_APP
        .onGeometryChange(for: CGSize.self) { $0.size } action: {
            columnWidths.chip = $0.width
            columnWidths.chipHeight = $0.height
        }
        #endif
        .popover(isPresented: $showsTeam) {
            GameDetailTeamDetails(game: game, color: color)
        }
        #if DEBUG && MAIN_APP
        .overlay(alignment: .topLeading) {
            if SurroundUITestContract.isEnabled && !navigationHeader && !avatarOnly {
                // Text truncation has no accessibility signal; compare the
                // name's laid-out width with its single-line ideal.
                Color.clear.frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "Identity name fit"))
                    .accessibilityIdentifier("game.identity.nameFit.\(color == .black ? "black" : "white")")
                    .accessibilityValue(Text(verbatim: String(format: "%@ shown=%.1f ideal=%.1f column=%.1f line2=%.1f chip=%.1f height=%.1f secondLine=%@",
                        nameWidths.shown + 0.5 >= nameWidths.ideal ? "full" : "truncated",
                        nameWidths.shown, nameWidths.ideal,
                        columnWidths.column, columnWidths.secondLine, columnWidths.chip, columnWidths.chipHeight,
                        Self.hasSecondLine(game: game, color: color, hidesRank: hidesRank)
                            && (!compactColumn || columnSecondLine) ? "yes" : "no")))
            }
        }
        #endif
    }

    private var chipCornerRadius: CGFloat { compactColumn ? 9 : (vertical ? 12 : 10) }

    /// Scene chips in a glass theme; the navigation header sits on the bar's
    /// glass, and accessibility settings keep the solid chip.
    private var showsThemeGlass: Bool {
        guard theme.usesGlassControls, !navigationHeader, !reduceTransparency, contrast != .increased else {
            return false
        }
        if #available(iOS 26, *) { return true }
        return false
    }

    private var nameFont: Font {
        accessibleRow ? .system(size: 22, weight: .semibold)
            : (vertical ? Font.subheadline : .callout).weight(.semibold)
    }

    @ViewBuilder private var identityContent: some View {
        if navigationHeader {
            HStack(spacing: 4) {
                profilePart(isAvatar: true) { avatar }
                profilePart(isAvatar: false) { identityText }
            }
        } else {
            chip
        }
    }

    @ViewBuilder private var chip: some View {
        if vertical && compactColumn {
            wholeChipProfile {
                VStack(alignment: .trailing, spacing: 6) {
                    if !isBottomRightPlayer { avatar }
                    stackedIdentityText
                    if isBottomRightPlayer { avatar }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else if vertical {
            VStack(alignment: identityAlignment, spacing: 8) {
                if !isBottomRightPlayer {
                    profilePart(isAvatar: true) { avatar }
                }
                profilePart(isAvatar: false) { identityText }
                if isBottomRightPlayer {
                    profilePart(isAvatar: true) { avatar }
                }
            }
            .frame(maxWidth: .infinity, alignment: identityFrameAlignment)
        } else {
            HStack(spacing: 4) {
                if avatarLeads { profilePart(isAvatar: true) { avatar } }
                // The name is laid out first, whichever side the avatar is
                // on. A Rengo chip's second line cannot shrink, so HStack
                // otherwise split the width evenly with a trailing avatar and
                // truncated your name beside free space (live Beta "hakho…").
                if !avatarOnly { profilePart(isAvatar: false) { identityText }.layoutPriority(1) }
                if !avatarLeads { profilePart(isAvatar: true) { avatar } }
            }
        }
    }

    /// The compact column chip is small enough to be one target.
    @ViewBuilder private func wholeChipProfile<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if !game.rengo, let player, player.id > 0, let openPlayerProfile {
            Button { openPlayerProfile(player) } label: { content().contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("View \(player.username)’s profile"))
                .accessibilityValue(Text(verbatim: player.usernameAndRank))
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileBannerAvatarEntry(player.id))
        } else {
            content()
        }
    }

    private var isBottomRightPlayer: Bool { color == (game.userStoneColor ?? .white) }
    private var avatarLeads: Bool { facesBoard ? isBottomRightPlayer : !isBottomRightPlayer }
    private var identityAlignment: HorizontalAlignment {
        if compactColumn { return .trailing }
        if vertical || facesBoard { return isBottomRightPlayer ? .leading : .trailing }
        return isBottomRightPlayer ? .trailing : .leading
    }
    private var identityFrameAlignment: Alignment { identityAlignment == .trailing ? .trailing : .leading }

    @ViewBuilder private var identityText: some View {
        if compactHeader {
            HStack(spacing: 4) {
                Text(verbatim: player?.username ?? "—")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(nameColor)
                    .lineLimit(1).truncationMode(.tail)
                if !hidesRank, let player {
                    Text(verbatim: player.formattedRank)
                        .font(.footnote).foregroundStyle(secondaryColor).fixedSize()
                }
                if game.rengo, team.count > 1 {
                    Text(verbatim: "+\(team.count - 1)")
                        .font(.footnote).foregroundStyle(secondaryColor).fixedSize()
                }
            }
            .padding(.trailing, 6)
        } else {
            stackedIdentityText
        }
    }

    private var stackedIdentityText: some View {
        VStack(alignment: identityAlignment, spacing: 1) {
            Text(verbatim: player?.username ?? "—")
                .font(nameFont)
                .foregroundStyle(nameColor)
                .lineLimit(vertical && !compactColumn ? 2 : 1)
                .truncationMode(.tail)
                .multilineTextAlignment(identityAlignment == .trailing ? .trailing : .leading)
                #if DEBUG && MAIN_APP
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { nameWidths.shown = $0 }
                .background(alignment: .leading) {
                    if SurroundUITestContract.isEnabled {
                        Text(verbatim: player?.username ?? "—").font(nameFont)
                            .fixedSize().hidden()
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { nameWidths.ideal = $0 }
                    }
                }
                #endif
            // With ranks hidden (and no Rengo line) there is no second line
            // at all, so the name is not followed by an empty gap.
            if Self.hasSecondLine(game: game, color: color, hidesRank: hidesRank)
                && (!compactColumn || columnSecondLine) {
                HStack(spacing: 4) {
                    if !hidesRank, let player {
                        Text(verbatim: player.formattedRank).fixedSize()
                    }
                    if game.rengo {
                        // "Next" names the team's coming player; a finished game has none.
                        if !GameDetailClockState(game: game, color: color).isFinished {
                            Text("Next").fixedSize()
                        }
                        if team.count > 1 {
                            Label("+\(team.count - 1)", systemImage: "person.fill")
                                .font(.caption2.weight(.semibold)).fixedSize()
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }.font(accessibleRow ? .system(size: 20) : .footnote).foregroundStyle(secondaryColor)
                #if DEBUG && MAIN_APP
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columnWidths.secondLine = $0 }
                #endif
            }
        }
        #if DEBUG && MAIN_APP
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columnWidths.column = $0 }
        #endif
        .padding(.horizontal, vertical ? 0 : 4)
    }

    private var avatar: some View {
        let size: CGFloat = vertical ? columnAvatarSize : (compactHeader ? 32 : (accessibleRow ? 44 : 40))
        return ZStack {
            if game.rengo, team.count > 1 {
                GameDetailAvatar(player: team[1], size: size)
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(roleColor(team[1]), lineWidth: 2) }
                    .offset(x: -6, y: -4)
            }
            GameDetailAvatar(player: player, size: size)
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(nameColor, lineWidth: 2) }
        }.frame(width: game.rengo ? size + 6 : size, height: size)
    }

    @ViewBuilder private func profilePart<Content: View>(isAvatar: Bool, @ViewBuilder content: () -> Content) -> some View {
        if !game.rengo, let player, player.id > 0, let openPlayerProfile {
            Button { openPlayerProfile(player) } label: { content().contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .frame(minWidth: isAvatar ? 44 : 0, minHeight: 44)
                .accessibilityLabel(Text("View \(player.username)’s profile"))
                .accessibilityValue(Text(verbatim: player.usernameAndRank))
                .accessibilityIdentifier(isAvatar
                    ? SurroundUITestContract.AccessibilityID.profileBannerAvatarEntry(player.id)
                    : SurroundUITestContract.AccessibilityID.profileBannerNameEntry(player.id))
        } else {
            content()
        }
    }
}

private struct GameDetailAvatar: View {
    let player: OGSUser?
    let size: CGFloat
    var body: some View {
        Group {
            #if DEBUG && MAIN_APP
            if SurroundUITestContract.gameDetailDesignArtboard != nil, let player {
                GameDetailDesignAvatar(player: player, size: size)
            } else if SurroundUITestContract.isCapturingAppStoreScreenshots, let player {
                AppStoreScreenshotAvatar(player: player, size: size)
            } else {
                remoteAvatar
            }
            #else
            remoteAvatar
            #endif
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }
    private var remoteAvatar: some View {
        AsyncImage(url: player?.iconURL(ofSize: Int(size * 2))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                (player?.uiColor ?? .gray).opacity(0.22)
                Text(verbatim: String(player?.username.prefix(1) ?? "?"))
                    .font(.system(size: size * 0.44, weight: .semibold))
            }
        }
    }
}

#if DEBUG && MAIN_APP
/// Bundled avatar data for the opt-in design fixture, with no remote image load.
private struct GameDetailDesignAvatar: View {
    let player: OGSUser
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var fill: Color {
        let rgb: (Double, Double, Double)
        switch player.username {
        case "tenuki_tom", "the_extremely_patient_kibitzer": rgb = (63, 95, 143)
        case "kosumi", "sabaki_and_shinogi_forever": rgb = (154, 75, 44)
        case "shusaku_fan": rgb = (47, 107, 79)
        case "honinbo_jr": rgb = (122, 78, 154)
        case "bob_k": rgb = (47, 127, 127)
        case "carol": rgb = (181, 101, 29)
        case "dave": rgb = (94, 127, 58)
        case "emma": rgb = (138, 79, 140)
        default: rgb = (128, 128, 128)
        }
        return Color(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(fill)
            .overlay {
                Text(verbatim: player.username.prefix(1).uppercased())
                    .font(.system(size: (size * 0.42).rounded(), weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(colorScheme == .dark
                        ? Color(red: 72 / 255, green: 72 / 255, blue: 74 / 255)
                        : Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255), lineWidth: 1)
            }
            .frame(width: size, height: size)
    }
}
#endif

/// Popovers anchored to the tapped clock or team, on every device. An opaque
/// surface keeps text readable above the board's high-contrast grid and
/// stones; glass let both show through. Content scrolls only when the window
/// cannot fit it. A tap outside, or the escape gesture, closes it.
private struct GameDetailOpaquePopover: ViewModifier {
    let identifier: String

    func body(content: Content) -> some View {
        ViewThatFits(in: .vertical) {
            content.fixedSize(horizontal: false, vertical: true)
            ScrollView { content }
        }
        .frame(width: 340)
        .background(GameDetailAppearance.panel)
        .presentationBackground(GameDetailAppearance.panel)
        .presentationCompactAdaptation(.popover)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

private struct GameDetailTeamDetails: View {
    @ObservedObject var game: Game
    let color: StoneColor
    @Environment(\.openPlayerProfile) private var openPlayerProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Setting(.hidesRank) private var hidesRank: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: GameDetailTeamRows.title(game: game, color: color)).font(.headline)
                Spacer(minLength: 0)
                Text("Turn order").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
            Divider()
            GameDetailTeamRows(game: game, color: color, onSelect: openPlayerProfile.map { open in
                { player in
                    dismiss()
                    open(player)
                }
            })
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .modifier(GameDetailOpaquePopover(identifier: "game.team.details"))
    }
}

/// A Rengo team in turn order: the team's next player first, marked Next,
/// and you marked You (one "You · next" pill when you are next). A finished
/// game has no next player. Shared by the team popover and game details.
private struct GameDetailTeamRows: View {
    @ObservedObject var game: Game
    let color: StoneColor
    var onSelect: ((OGSUser) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @Setting(.hidesRank) private var hidesRank: Bool
    private var team: [OGSUser] { game.orderedRengoTeam[color] ?? game.gameData?.rengoTeams?[color] ?? [] }

    static func title(game: Game, color: StoneColor) -> String {
        let side = color == .black ? String(localized: "Black") : String(localized: "White")
        return color == game.userStoneColor
            ? String(localized: "Your team · \(side)") : String(localized: "\(side) team")
    }

    var body: some View {
        let finished = GameDetailClockState(game: game, color: color).isFinished
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(team.enumerated()), id: \.element.id) { index, player in
                Button {
                    onSelect?(player)
                } label: {
                    HStack(spacing: 10) {
                        Text(verbatim: String(index + 1))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(minWidth: 18)
                        ZStack(alignment: .bottomTrailing) {
                            GameDetailAvatar(player: player, size: 32)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(gameDetailProfileColor(player, dark: colorScheme == .dark), lineWidth: 2)
                                }
                            Stone(color: color, shadowRadius: 0)
                                .frame(width: 11, height: 11).offset(x: 3, y: 2)
                        }
                        (Text(verbatim: player.username).fontWeight(.semibold)
                            .foregroundColor(gameDetailProfileColor(player, dark: colorScheme == .dark))
                            + Text(verbatim: hidesRank ? "" : " [\(player.formattedRank)]").foregroundColor(.secondary))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        let isNext = index == 0 && !finished
                        let isYou = player.id == game.ogs?.user?.id
                        if isNext && isYou {
                            teamBadge("You · next", prominent: true)
                        } else if isNext {
                            teamBadge("Next", prominent: true)
                        } else if isYou {
                            teamBadge("You", prominent: false)
                        }
                    }.frame(minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(onSelect == nil || player.id <= 0)
                if index < team.count - 1 { Divider() }
            }
        }
    }

    private func teamBadge(_ title: LocalizedStringKey, prominent: Bool) -> some View {
        Text(title).font(.caption2.bold())
            .foregroundStyle(prominent ? Color.accentColor : .secondary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(prominent ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.1), in: Capsule())
    }
}

private struct GameDetailClockDetails: View {
    @ObservedObject var game: Game
    var showsClocks = false
    var clockOverride: OGSClock?
    var isConnected = true
    @Environment(\.openPlayerProfile) private var openPlayerProfile
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        GameDetailInformationContent(game: game, showsClocks: showsClocks,
                                     clockOverride: clockOverride, isConnected: isConnected)
            .padding(18)
            .modifier(GameDetailOpaquePopover(identifier: "game.details"))
            .environment(\.openPlayerProfile, openPlayerProfile.map { action in
                { player in dismiss(); action(player) }
            })
    }
}

/// The same complete game details as the clock sheet, available in Book's
/// otherwise empty information pane. Long titles and accessibility text scroll.
struct GameDetailInformationCard: View {
    @ObservedObject var game: Game
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                GameDetailInformationContent(game: game,
                    columns: geometry.size.width >= 560 && !dynamicTypeSize.isAccessibilitySize)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GameDetailAppearance.panel, in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(GameDetailAppearance.panelBorder) }
            }
        }
        .accessibilityIdentifier("game.information")
    }
}

private struct GameDetailInformationContent: View {
    @ObservedObject var game: Game
    var columns = false
    var showsClocks = false
    var clockOverride: OGSClock?
    var isConnected = true
    @Environment(\.openPlayerProfile) private var openPlayerProfile
    @Environment(\.colorScheme) private var colorScheme
    @Setting(.hidesRank) private var hidesRank: Bool
    @State private var selectedTeam: StoneColor?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            title
            if game.gamePhase == .stoneRemoval || game.gamePhase == .finished {
                scoreDetails
            }
            Divider()
            if columns {
                HStack(alignment: .top, spacing: 24) {
                    players.frame(maxWidth: .infinity, alignment: .leading)
                    metadata.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                players
                Divider()
                metadata
            }
        }
        .font(.subheadline)
    }

    @ViewBuilder private var players: some View {
        let firstColor: StoneColor = game.isUserPlaying ? (game.userStoneColor?.opponentColor() ?? .black) : .black
        if game.rengo {
            // Rengo lists both whole teams in turn order, as the team popover
            // does, rather than only the pair at the board.
            VStack(alignment: .leading, spacing: 6) {
                ForEach([firstColor, firstColor.opponentColor()], id: \.self) { color in
                    if color != firstColor { Divider() }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: GameDetailTeamRows.title(game: game, color: color))
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if showsClocks { clockReadout(color) }
                    }
                    GameDetailTeamRows(game: game, color: color,
                                       onSelect: openPlayerProfile.map { open in { open($0) } })
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("game.details.rengoTeams")
        } else {
            VStack(spacing: 0) {
                playerRow(firstColor)
                Divider()
                playerRow(firstColor.opponentColor())
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let data = game.gameData {
                VStack(spacing: 7) {
                    if let tournament = data.tournamentId {
                        metadataRow("Tournament", value: "#\(tournament)")
                        Divider()
                    }
                    metadataRow("Rules", value: data.rules.fullName)
                    Divider()
                    metadataRow("Komi", value: gameDetailPoints(data.komi))
                    if data.handicap > 0 {
                        Divider()
                        metadataRow("Handicap", value: String(data.handicap))
                    }
                    Divider()
                    metadataRow("Time control", value: data.timeControl.system.name)
                }
                .font(.subheadline)
                data.timeControl.system.descriptionText
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: game.gameName.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Game details"))
                .font(.headline).fixedSize(horizontal: false, vertical: true)
            if let data = game.gameData {
                let classification = data.ranked ? String(localized: "Ranked") : String(localized: "Unranked")
                let speed = data.timeControl.speed?.localizedString().localizedCapitalized
                Text(verbatim: [classification, "\(data.width)×\(data.height)", speed].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func playerRow(_ color: StoneColor) -> some View {
        let player = game.currentPlayer(with: color)
        return Button {
            if game.rengo { selectedTeam = color }
            else if let player { openPlayerProfile?(player) }
        } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    GameDetailAvatar(player: player, size: 28)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(gameDetailProfileColor(player, dark: colorScheme == .dark), lineWidth: 2)
                        }
                    Stone(color: color, shadowRadius: 0).frame(width: 10, height: 10).offset(x: 3, y: 2)
                }
                VStack(alignment: .leading, spacing: 4) {
                    (Text(verbatim: player?.username ?? "—")
                        .foregroundColor(gameDetailProfileColor(player, dark: colorScheme == .dark))
                        + Text(verbatim: !hidesRank ? " [\(player?.formattedRank ?? "—")]" : "").foregroundColor(.secondary))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if showsClocks { clockReadout(color) }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!game.rengo && (openPlayerProfile == nil || (player?.id ?? 0) <= 0))
        .popover(isPresented: Binding(get: { selectedTeam == color }, set: { if !$0 { selectedTeam = nil } })) {
            GameDetailTeamDetails(game: game, color: color)
        }
    }

    @ViewBuilder private func clockReadout(_ color: StoneColor) -> some View {
        let state = GameDetailClockState(game: game, color: color,
                                         clockOverride: clockOverride, isConnected: isConnected)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if state.isFinished {
                Text(verbatim: state.resultTitle).font(.subheadline)
                Text(verbatim: state.resultDetail).font(.caption).foregroundStyle(.secondary)
            } else if state.isScoring {
                Text(verbatim: state.scoreText).font(.subheadline)
                Text(state.accepted ? "Accepted" : "Not accepted")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let deadline = state.autoResign {
                Text(verbatim: timeString(timeLeft: deadline)).font(.subheadline.monospacedDigit())
                Text("Disconnected").font(.caption).foregroundStyle(.secondary)
            } else if state.canShowTimer {
                TimerView(timeControl: state.valueTimeControl, clock: state.valueClock,
                          player: color, mainFont: .subheadline.monospacedDigit(), subFont: .caption)
                Text(verbatim: state.paused ? state.pauseReason : state.timeDetail)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(verbatim: state.unavailableTimeText).font(.subheadline)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: state.accessibilityLabel))
        .accessibilityValue(Text(verbatim: state.accessibilityValue))
        .accessibilityIdentifier(color == .black ? "game.details.clock.black" : "game.details.clock.white")
    }

    private func metadataRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(verbatim: value).multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scoreDetails: some View {
        let black = GameDetailClockState(game: game, color: .black).score
        let white = GameDetailClockState(game: game, color: .white).score
        return VStack(alignment: .leading, spacing: 8) {
            Text(game.gamePhase == .finished ? "Final score" : "Provisional score")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if game.gamePhase == .finished { Text(verbatim: game.status).font(.subheadline) }
            // A resignation or timeout has no score; show no table of dashes.
            if black != nil || white != nil {
            Grid(alignment: .trailing, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Text("Black")
                    Text("White")
                }.font(.caption).foregroundStyle(.secondary)
                if let data = game.gameData {
                    if data.scoreTerritory { scoreRow("Territory", black: black.map { String($0.territory) }, white: white.map { String($0.territory) }) }
                    if data.scoreStones { scoreRow("Stones", black: black.map { String($0.stones) }, white: white.map { String($0.stones) }) }
                    if data.scorePrisoners { scoreRow("Captures", black: black.map { String($0.prisoners) }, white: white.map { String($0.prisoners) }) }
                    scoreRow("Komi", black: black.map { gameDetailPoints($0.komi) }, white: white.map { gameDetailPoints($0.komi) })
                    if data.scoreHandicap { scoreRow("Handicap", black: black.map { String($0.handicap) }, white: white.map { String($0.handicap) }) }
                }
                Divider()
                scoreRow("Total", black: black.map { gameDetailPoints($0.total) }, white: white.map { gameDetailPoints($0.total) }).bold()
            }
            .monospacedDigit()
            }
        }
    }

    private func scoreRow(_ title: LocalizedStringKey, black: String?, white: String?) -> some View {
        GridRow {
            Text(title).frame(maxWidth: .infinity, alignment: .leading).gridColumnAlignment(.leading)
            Text(verbatim: black ?? "—")
            Text(verbatim: white ?? "—")
        }
    }
}

/// Apply once to the persistent game screen, not to each responsive clock card.
struct GameDetailVoiceCountdown: ViewModifier {
    @ObservedObject var game: Game
    @EnvironmentObject private var ogs: OGSService
    @Setting(.voiceCountdown) private var voiceCountdown: Bool
    @State private var synthesizer: AVSpeechSynthesizer?
    @State private var lastValue: Int?
    @State private var lastSpokenAt = Date.distantPast

    func body(content: Content) -> some View {
        content
            .onAppear { updateSynthesizer() }
            .onChange(of: voiceCountdown) { _, _ in updateSynthesizer() }
            .onChange(of: game.ID) { _, _ in stop(); updateSynthesizer() }
            .onChange(of: game.isUserPlaying) { _, _ in updateSynthesizer() }
            .onChange(of: ogs.socketStatus) { _, status in
                if status != .connected { stop() }
            }
            .onDisappear { stop() }
            .onReceive(game.$clock) { clock in
                guard voiceCountdown, ogs.socketStatus == .connected, game.isUserTurn,
                      game.pauseControl?.isPaused() != true, let clock else { return }
                let time = game.userStoneColor == .black ? clock.blackTime : clock.whiteTime
                guard let remaining = time.timeLeft, remaining.isFinite,
                      remaining >= 0, remaining <= 10 else { return }
                let value = Int(remaining)
                guard value != lastValue || Date().timeIntervalSince(lastSpokenAt) >= 3 else { return }
                updateSynthesizer()
                lastValue = value
                lastSpokenAt = Date()
                synthesizer?.speak(AVSpeechUtterance(string: String(value)))
            }
    }
    private func updateSynthesizer() {
        if voiceCountdown && game.isUserPlaying {
            if synthesizer == nil { synthesizer = AVSpeechSynthesizer() }
        } else { stop() }
    }
    private func stop() {
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
        lastValue = nil
    }
}
