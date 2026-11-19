//
//  GameControlView.swift
//  Surround
//
//  The in-game control in Game Detail's bars. The bottom bar and top bars
//  draw a custom view: another live game's mini board and clock, a game
//  that started elsewhere, at game over the challenger's tile, or an icon
//  with what waits. The Duo's rail and the Mac show the system's icon with
//  its red badge. A tap on the chip shows its game; a touch and hold, or
//  VoiceOver's Open Activity, opens the control's popover, which Game
//  Detail fills. Each item keeps one identity across states, so an open
//  popover keeps its anchor, and a frame fixed by its form, its state and
//  the window's width class, so the bar's layout never follows the clock.
//  The other game's clock ticks inside the item, which observes that game.
//  In Zen only another live game on your move shows, beside Exit: a circle
//  where Exit is drawn in the game's content, the top-bar chip before a
//  native Exit, and the system's icon on the Mac and the Duo's rail. A tap
//  shows that game; Zen has no popover.
//  GameControlModel.swift holds the rules each form follows.
//

import os
import SwiftUI
import UIKit

// MARK: - The custom items

/// What Game Detail gives one of the control's custom items.
struct GameControlItemModel {
    var slot: GameControlSlot
    /// The window's, from its root; nil gives the full frames.
    var windowClass: GameControlWindowClass?
    /// The mode buttons beside the control: Analyze and Chat, and
    /// Conditional moves while it shows.
    var modeCount: Int
    /// Game Detail's text size, read in the pass that draws the bar. The
    /// bar caps its items' own text size, so the frame takes the screen's.
    var sizeCategory: UIContentSizeCategory
    /// The route has the picker (`GameControlSwitch.allowsPicker`).
    var allowsPicker: Bool
    /// The chip's game, or the one that started. The item observes it, so
    /// its clock ticks there and nowhere else in the bar.
    var game: Game?
    /// The game-over card's challenger, whose tile the item draws.
    var challenger: OGSUser?
    /// Shows a game by its id, as Game Detail switches games.
    var show: (Int) -> Void
    /// Opens the control's popover.
    var openPopover: () -> Void
    /// Zen's control, whose tap shows the chip's game and nothing else.
    var isZen = false
}

/// The control in the bottom bar: a custom view, 160 pt wide at most.
struct GameControlBottomBarItem: View {
    let model: GameControlItemModel
    @Binding var isPresented: Bool
    let popover: AnyView

    var body: some View {
        GameControlCustomItem(form: .bottomBar, model: model)
            .popover(isPresented: $isPresented) {
                popover.presentationCompactAdaptation(.popover)
            }
    }
}

/// The control in a top bar: a custom view 96 pt wide at most, drawn within
/// 36 pt of its 44 pt height. It takes only the slot's value and what to
/// do, so any top bar can show it.
struct GameControlTopBarItem: View {
    let model: GameControlItemModel
    @Binding var isPresented: Bool
    let popover: AnyView

    var body: some View {
        GameControlCustomItem(form: .topBar, model: model)
            .popover(isPresented: $isPresented) {
                popover.presentationCompactAdaptation(.popover)
            }
    }
}

/// Zen's control in a top bar, before a native Exit: the top-bar chip for
/// another live game on your move, in the chip's fixed 96 pt frame, which a
/// tap shows. Zen has no popover.
struct GameControlZenTopBarItem: View {
    let model: GameControlItemModel

    var body: some View {
        GameControlCustomItem(form: .topBar, model: model)
    }
}

private struct GameControlCustomItem: View {
    let form: GameControlForm
    let model: GameControlItemModel

    private var frame: CGSize {
        GameControlDrawing.frame(model.slot, form: form, windowClass: model.windowClass, modeCount: model.modeCount,
                                 sizeCategory: model.sizeCategory)
    }

    var body: some View {
        // The container keeps the toolbar from synthesizing a native item
        // out of the label, as GameToolbarChatButton's does, and anchors the
        // popover whatever the state.
        ZStack {
            if let game = model.game, model.slot.gameID != nil {
                GameControlGameButton(form: form, model: model, game: game)
            } else {
                GameControlIconButton(form: form, model: model)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .background {
            GameControlLargeContentViewerGuard()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }
}

/// The chip and a started game, which show another game: observing it
/// redraws the clock each second, here alone.
private struct GameControlGameButton: View {
    let form: GameControlForm
    let model: GameControlItemModel
    @ObservedObject var game: Game
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let face = GameControlFace(form: form, model: model, game: game, dynamicTypeSize: dynamicTypeSize) {
            GameControlButton(face: face, model: model)
        }
    }
}

/// The states that show no other game: base, the dot, the inbox and the
/// game-over card.
private struct GameControlIconButton: View {
    let form: GameControlForm
    let model: GameControlItemModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let face = GameControlFace(form: form, model: model, game: nil, dynamicTypeSize: dynamicTypeSize) {
            GameControlButton(face: face, model: model)
        }
    }
}

/// A custom item's button, and the Zen circle's: a tap does the state's tap
/// and a touch and hold opens the popover, or in Zen does nothing. Its press
/// timing keeps a release 0.5 s or more after the press began from ever
/// switching games, whatever took the touch on the way, as the Large Content
/// Viewer does at accessibility sizes.
private struct GameControlButton<Label: View>: View {
    let face: GameControlFace
    let model: GameControlItemModel
    @ViewBuilder let label: () -> Label
    @State private var press = GameControlPress()

    var body: some View {
        let accessibility = face.accessibility
        Button {
            let release = press.release()
            perform(face.interaction.release(after: release.duration, holdFired: release.holdFired))
        } label: {
            label()
        }
        .buttonStyle(GameControlPressStyle(onPress: press.begin))
        .simultaneousGesture(LongPressGesture(minimumDuration: GameControlInteraction.holdDuration).onEnded { _ in
            press.hold()
            perform(face.interaction.hold)
        })
        .accessibilityLabel(Text(verbatim: accessibility.label))
        .accessibilityValue(Text(verbatim: accessibility.value ?? ""))
        .accessibilityHint(Text(verbatim: accessibility.hint ?? ""))
        .accessibilityAddTraits(accessibility.updatesFrequently ? .updatesFrequently : [])
        // VoiceOver's activation is the tap, whatever an earlier press left.
        .accessibilityAction { perform(face.interaction.tap) }
        .accessibilityActions {
            if accessibility.offersOpenActivity {
                Button(GameControlAccessibility.openActivity) { perform(.openPopover) }
            }
        }
        .accessibilityIdentifier(model.isZen
            ? SurroundUITestContract.AccessibilityID.gameZenControl
            : SurroundUITestContract.AccessibilityID.gameActiveGamesButton)
    }

    private func perform(_ action: GameControlAction) {
        switch action {
        case .none: break
        case .show(let gameID): model.show(gameID)
        case .openPopover: model.openPopover()
        }
    }
}

extension GameControlButton where Label == GameControlFaceView {
    /// A bar item's button, which draws the item's face.
    init(face: GameControlFace, model: GameControlItemModel) {
        self.init(face: face, model: model) { GameControlFaceView(face: face) }
    }
}

/// When the current press on a custom item began, and whether its hold
/// fired. A reference, so a press redraws nothing.
private final class GameControlPress {
    /// A press older than this was never released on the item, as one
    /// dragged away from it; it can't be the one a tap ends.
    private static let longestPress: TimeInterval = 60
    private var began: TimeInterval?
    private var holdFired = false

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func begin() {
        began = now
        holdFired = false
    }

    /// The hold fired; the release that ends it then does nothing more.
    func hold() {
        if began == nil { began = now - GameControlInteraction.holdDuration }
        holdFired = true
    }

    /// The press that a release ends: how long it lasted and whether its
    /// hold fired. A release whose press was never seen counts as a tap.
    func release() -> (duration: TimeInterval, holdFired: Bool) {
        defer {
            began = nil
            holdFired = false
        }
        guard let began, now - began < Self.longestPress else { return (0, false) }
        return (now - began, holdFired)
    }
}

/// Reports each press as it begins, and dims the item while it is pressed.
private struct GameControlPressStyle: ButtonStyle {
    let onPress: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .onChange(of: configuration.isPressed) { wasPressed, isPressed in
                if isPressed && !wasPressed { onPress() }
            }
    }
}

// MARK: - What a custom item draws

/// What one custom item draws and says now: its fixed frame, the parts that
/// fit it at the text size, the other game's clock, and what a tap, a hold
/// and VoiceOver do.
private struct GameControlFace {
    let form: GameControlForm
    let drawing: GameControlDrawing
    let metrics: GameControlChipMetrics
    let parts: [GameControlPart]
    let clock: GameControlClock?
    let mark: GameControlSuddenDeathMark
    /// The other game is low on time: a red outline and red digits.
    let warns: Bool
    let board: BoardPosition?
    /// The game-over card's challenger, drawn as the tile.
    let challenger: OGSUser?
    let interaction: GameControlInteraction
    let accessibility: GameControlAccessibility

    /// Top bars draw within 36 pt, which iPadOS 26's top bar doesn't clip.
    var drawingHeight: CGFloat { form == .topBar ? 36 : GameControlDrawing.height }

    var textFont: Font { Font(metrics.textFont as CTFont) }
    var countFont: Font { Font(metrics.countFont as CTFont) }
    /// Symbols at the text's size and weight, as the metrics measure them.
    var symbolFont: Font { .system(size: metrics.textFont.pointSize, weight: .semibold) }

    func width(of part: GameControlPart) -> CGFloat {
        metrics.width(of: part, clock: clock, plusN: drawing.plusN, mark: mark)
    }

    /// The space before the part at `index`, as the fit counts it.
    func gap(before index: Int) -> CGFloat {
        let joinsClock = parts[index] == .clock
            && [GameControlPart.hourglass, .suddenDeathMark].contains(parts[index - 1])
        return joinsClock ? metrics.spacing.beforeClock : metrics.spacing.between
    }
}

extension GameControlFace {
    /// Nil only for the native forms, which draw the system's item.
    @MainActor
    init?(form: GameControlForm, model: GameControlItemModel, game: Game?, dynamicTypeSize: DynamicTypeSize) {
        var timeLeft: TimeInterval?
        var isSuddenDeath = false
        var lowTime = false
        // The chip's or a started game's opponent, or the card's challenger.
        var name = model.challenger?.username ?? ""
        if let game, let color = game.userStoneColor {
            // The user's time on that game's clock, as Home's chip reads it.
            timeLeft = HomeGameFacts(game: game, user: game.ogs?.user).chipTimeLeft(color)
            isSuddenDeath = GameDetailClockState(game: game, color: color).suddenDeath
            name = game.currentPlayer(with: color.opponentColor())?.username ?? ""
            if let userID = game.ogs?.user?.id, let live = ActivityModel.LiveGame(game: game, userID: userID) {
                lowTime = ActivityModel.isLowOnTime(live)
            }
        }
        guard let drawing = GameControlDrawing(
            model.slot, form: form, windowClass: model.windowClass, modeCount: model.modeCount,
            sizeCategory: model.sizeCategory, allowsPicker: model.allowsPicker, hasCountdown: timeLeft != nil,
            isSuddenDeath: isSuddenDeath
        ) else { return nil }
        let metrics = GameControlChipMetrics(form: form, sizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let clock = timeLeft.map(GameControlClock.init(timeLeft:))
        let mark = form == .bottomBar ? GameControlMarks.bottomBar : .glyph
        self.form = form
        self.drawing = drawing
        self.metrics = metrics
        parts = drawing.fit(metrics, clock: clock, mark: mark).parts
        self.clock = clock
        self.mark = mark
        warns = lowTime || drawing.isSuddenDeath
        board = game?.currentPosition
        challenger = model.challenger
        interaction = GameControlInteraction(model.slot, form: form, windowClass: model.windowClass,
                                             isZen: model.isZen)
        accessibility = GameControlAccessibility(
            model.slot, form: form, windowClass: model.windowClass, isZen: model.isZen,
            allowsPicker: model.allowsPicker, name: name, timeLeft: timeLeft, isSuddenDeath: isSuddenDeath
        )
    }
}

/// The bottom bar's sudden-death mark in the app's language, measured once:
/// the app's language can't change while it runs.
private enum GameControlMarks {
    static let bottomBar = GameControlSuddenDeathMark.drawn(in: .bottomBar)
}

/// A custom item's drawing: its parts in a row, each at the width the fit
/// measured, centred in the item's fixed frame. From iOS 26 the bar draws
/// its own glass platter around the item; before, the item draws a light
/// capsule of its own.
private struct GameControlFaceView: View {
    let face: GameControlFace

    var body: some View {
        let spacing = face.metrics.spacing
        HStack(spacing: 0) {
            ForEach(Array(face.parts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Color.clear.frame(width: face.gap(before: index), height: 1)
                }
                partView(part)
                    .frame(width: face.width(of: part))
            }
        }
        .padding(.leading, spacing.leading)
        .padding(.trailing, spacing.trailing)
        .frame(width: face.drawing.frame.width, height: face.drawingHeight)
        .background { surface }
        .overlay {
            if face.warns {
                Capsule().strokeBorder(Color.gameControlWarning, lineWidth: 1.5)
            }
        }
        .overlay(alignment: .topTrailing) {
            if face.drawing.hasDot { dot }
        }
        .frame(width: face.drawing.frame.width, height: face.drawing.frame.height)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func partView(_ part: GameControlPart) -> some View {
        switch part {
        case .board:
            board
        case .tile:
            tile
        case .icon(let icon):
            Image(systemName: icon.systemName)
                .font(.system(size: 20))
                .imageScale(.medium)
                .foregroundStyle(.primary)
        case .hourglass:
            Image(systemName: "hourglass")
                .font(face.symbolFont)
                .foregroundStyle(.secondary)
        case .suddenDeathMark:
            switch face.mark {
            case .text(let text):
                Text(verbatim: text)
                    .font(face.textFont)
                    .foregroundStyle(Color.gameControlWarning)
                    .fixedSize()
            case .glyph:
                Image(systemName: GameControlSuddenDeathMark.glyphSystemName)
                    .font(face.symbolFont)
                    .foregroundStyle(Color.gameControlWarning)
            }
        case .clock:
            Text(verbatim: face.clock?.text ?? "")
                .font(face.textFont)
                .foregroundStyle(face.warns ? Color.gameControlWarning : Color.primary)
                .fixedSize()
        case .plusN:
            Text(verbatim: GameControlChipMetrics.countText(face.drawing.plusN))
                .font(face.countFont)
                .foregroundStyle(.primary)
                .fixedSize()
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
        }
    }

    /// The other game's flat mini board, at a size where every board is
    /// drawn in solid colors.
    @ViewBuilder private var board: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Group {
            if let position = face.board {
                PositionBoardView(boardPosition: position).equatable()
            } else {
                shape.fill(Color(uiColor: .secondarySystemFill))
            }
        }
        .frame(width: GameControlChipMetrics.boardWidth, height: GameControlChipMetrics.boardWidth)
        .clipShape(shape)
    }

    /// The challenger's avatar, as Activity's rows draw it, at the board's
    /// size. A neutral tile stands in for a challenger the control no
    /// longer knows.
    @ViewBuilder private var tile: some View {
        if let challenger = face.challenger {
            MessageAvatar(user: challenger, size: GameControlChipMetrics.boardWidth)
        } else {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(uiColor: .secondarySystemFill))
                .overlay { Image(systemName: "person.fill").font(.system(size: 14)).foregroundStyle(.secondary) }
                .frame(width: GameControlChipMetrics.boardWidth, height: GameControlChipMetrics.boardWidth)
        }
    }

    @ViewBuilder private var surface: some View {
        if #available(iOS 26.0, *) {
            EmptyView()
        } else {
            Capsule()
                .fill(.regularMaterial)
                .overlay { Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1) }
        }
    }

    /// The 10 pt dot with its 2 pt ring, as a challenge or a message waits
    /// while you play live: no count, no sound.
    private var dot: some View {
        Circle()
            .fill(Color(uiColor: .systemIndigo))
            .frame(width: 10, height: 10)
            .padding(2)
            .background(Circle().fill(Color(uiColor: .systemBackground)))
            .padding(1)
            .accessibilityHidden(true)
    }
}

private extension Color {
    /// The other game's low time: deeper than the system red in light mode,
    /// so the digits keep their contrast on the bar.
    static let gameControlWarning = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.42, blue: 0.40, alpha: 1)
            : UIColor(red: 0.69, green: 0.0, blue: 0.10, alpha: 1)
    })
}

// MARK: - The native item

/// The control on the Duo's rail, on the Mac and in a top bar too narrow
/// for the chip: the system's icon with its red count, or an empty badge as
/// the dot. A native item takes no hold, so a tap or a click opens the
/// popover, which leads with what the chip would show. Its label carries
/// the count but no time, so a tick never relabels it, and on the Mac it is
/// also the tooltip. Game Detail keeps its identity while the popover's
/// content is on screen (`GameControlNativeIdentity`).
struct GameControlNativeButton: View {
    let item: GameControlNativeItem
    let label: String
    @Binding var isPresented: Bool
    let popover: AnyView
    let openPopover: () -> Void
    let popoverAppeared: () -> Void
    let popoverDisappeared: () -> Void

    var body: some View {
        Button(action: openPopover) {
            Label {
                Text(verbatim: label)
            } icon: {
                Image(systemName: item.icon.systemName)
            }
            #if os(iOS) && !targetEnvironment(macCatalyst)
            .frame(minWidth: 44, minHeight: 44)
            #endif
        }
        .badge(item.badgeText)
        #if targetEnvironment(macCatalyst)
        .help(Text(verbatim: label))
        #endif
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameActiveGamesButton)
        .popover(isPresented: $isPresented) {
            popover
                .onAppear(perform: popoverAppeared)
                .onDisappear(perform: popoverDisappeared)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// Zen's control on the Mac and on the Duo's rail in Closed portrait,
/// before Exit: the system's grid icon with a badge of 1 for another live
/// game on your move. A tap or a click shows that game. Its label names the
/// game without its time, and on the Mac it is also the tooltip.
struct GameControlZenNativeButton: View {
    let item: GameControlNativeItem
    let label: String
    let hint: String?
    let show: () -> Void

    var body: some View {
        Button(action: show) {
            Label {
                Text(verbatim: label)
            } icon: {
                Image(systemName: item.icon.systemName)
            }
            #if os(iOS) && !targetEnvironment(macCatalyst)
            .frame(minWidth: 44, minHeight: 44)
            #endif
        }
        .badge(item.badgeText)
        #if targetEnvironment(macCatalyst)
        .help(Text(verbatim: label))
        #endif
        .accessibilityHint(Text(verbatim: hint ?? ""))
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameZenControl)
    }
}

private extension GameControlNativeItem {
    /// One badge modifier for every state, so a change of state keeps the
    /// item: an empty text draws the system's dot.
    var badgeText: Text? {
        switch badge {
        case .none: nil
        case .count(let count): Text(count, format: .number)
        case .dot: Text(verbatim: "")
        }
    }
}

// MARK: - The Zen circle

/// Where the Zen circle's countdown sits, from the window's shape, or that
/// the circle shows alone.
enum GameControlZenCountdownPlacement: Equatable {
    /// 4 pt below the circle, as drawn, where the window is wider than tall
    /// and the board's column leaves its corners clear.
    case below
    /// On the circle's leading side, inside Exit's 44 pt band, where the
    /// layout is portrait-shaped, so it reaches no lower than Exit.
    case leading
    /// No countdown: the 44 pt circle alone, in the board's column where it
    /// has room for no more, or beside Exit where the countdown would reach
    /// the clocks.
    case omitted
}

private struct GameControlZenKey: EnvironmentKey {
    static let defaultValue: GameControlItemModel? = nil
}

extension EnvironmentValues {
    /// Zen's control for the game on screen, which the toolbar reads in the
    /// pass that draws the bar, for the game's content to draw beside Exit
    /// or in the board's column under it. Nil outside Zen, without another
    /// live game on your move, and where the control is a bar item before
    /// Exit or has no room.
    var gameControlZen: GameControlItemModel? {
        get { self[GameControlZenKey.self] }
        set { self[GameControlZenKey.self] = newValue }
    }
}

/// Zen's control where Exit is drawn in the game's content: another live
/// game on your move, as a 44 pt glass circle with its mini board and a 22 pt
/// countdown capsule, in a 76 pt button beside Exit and on Exit's surface, or
/// the circle alone where the capsule would reach the clocks. A tap shows
/// that game; a touch and hold does nothing. Draws nothing without the
/// toolbar's `gameControlZen`.
struct GameControlZenCircle: View {
    let placement: GameControlZenCountdownPlacement
    @Environment(\.gameControlZen) private var zen

    var body: some View {
        if let zen, let game = zen.game {
            GameControlZenCircleButton(model: zen, game: game, placement: placement)
                // The circle keeps the place the 76 pt button gives it in
                // every placement: 18 pt from Exit's circle.
                .padding(.trailing, placement == .below
                         ? GameControlZenMetrics.gapBeforeExit
                         : GameControlZenMetrics.buttonInset + GameControlZenMetrics.gapBeforeExit)
        }
    }
}

/// Zen's control in the board's trailing column under Exit
/// (`GameControlZenCorner.circle`): in compact landscape where the top-bar
/// chip and Exit would reach over the board, and in an iPad's compact window
/// where the circle beside Exit would reach over the clocks or the board. Its
/// countdown hangs below where the column holds the 76 pt button. As beside
/// Exit, a tap shows that game and a touch and hold does nothing. Draws
/// nothing without the toolbar's `gameControlZen`.
struct GameControlZenColumnCircle: View {
    let showsCountdown: Bool
    @Environment(\.gameControlZen) private var zen

    var body: some View {
        if let zen, let game = zen.game {
            GameControlZenCircleButton(model: zen, game: game, placement: showsCountdown ? .below : .omitted)
        }
    }
}

private enum GameControlZenMetrics {
    static let circle: CGFloat = 44
    static let buttonWidth: CGFloat = 76
    /// The space on each side of the circle in its 76 pt button.
    static let buttonInset = (buttonWidth - circle) / 2
    static let gapBeforeExit: CGFloat = 2
    static let countdownGap: CGFloat = 4
    static let countdownHeight: CGFloat = 22
    static let countdownPadding: CGFloat = 7
    static let countdownSpacing: CGFloat = 3
    static let symbolSize: CGFloat = 11
}

/// The circle's button, which observes the other game so its countdown
/// ticks here alone. It speaks as the bar chip does in Zen: the game and its
/// time, with no value.
private struct GameControlZenCircleButton: View {
    let model: GameControlItemModel
    @ObservedObject var game: Game
    let placement: GameControlZenCountdownPlacement
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // The top bar's chip in Zen: its clock, its sudden-death glyph and its
        // text capped at the large size, which the 22 pt capsule fits.
        if let face = GameControlFace(form: .topBar, model: model, game: game, dynamicTypeSize: dynamicTypeSize) {
            GameControlButton(face: face, model: model) {
                GameControlZenCircleLabel(face: face, countdown: GameControlZenCountdown(face: face),
                                          placement: placement)
            }
        }
    }
}

/// The capsule's parts: the clock after its hourglass, or after the
/// sudden-death mark, no wider than the circle's 76 pt button. The hourglass
/// drops first, as a clock of an hour or more needs its room; the clock and
/// the mark never drop. A game with no countdown shows the hourglass alone.
private struct GameControlZenCountdown {
    var symbol: String?
    var symbolIsWarning: Bool
    var showsClock: Bool

    init(face: GameControlFace) {
        let isSuddenDeath = face.drawing.isSuddenDeath
        let name = isSuddenDeath ? GameControlSuddenDeathMark.glyphSystemName : "hourglass"
        symbolIsWarning = isSuddenDeath
        guard let clock = face.clock else {
            symbol = name
            showsClock = false
            return
        }
        showsClock = true
        let configuration = UIImage.SymbolConfiguration(pointSize: GameControlZenMetrics.symbolSize, weight: .semibold)
        let symbolWidth = ceil(UIImage(systemName: name, withConfiguration: configuration)?.size.width
                               ?? GameControlZenMetrics.symbolSize)
        let clockWidth = ceil(GameControlChipMetrics.textWidth(clock.widestSample, font: face.metrics.textFont))
        let width = GameControlZenMetrics.countdownPadding * 2 + symbolWidth
            + GameControlZenMetrics.countdownSpacing + clockWidth
        symbol = isSuddenDeath || width <= GameControlZenMetrics.buttonWidth ? name : nil
    }
}

/// The circle and its countdown, each on Exit's glass, the countdown below
/// the circle or on its leading side.
private struct GameControlZenCircleLabel: View {
    let face: GameControlFace
    let countdown: GameControlZenCountdown
    let placement: GameControlZenCountdownPlacement

    var body: some View {
        Group {
            switch placement {
            case .below:
                VStack(spacing: GameControlZenMetrics.countdownGap) {
                    circle
                    capsule
                }
                .frame(minWidth: GameControlZenMetrics.buttonWidth)
            case .leading:
                HStack(spacing: GameControlZenMetrics.countdownGap) {
                    capsule
                    circle
                }
                .frame(height: GameControlZenMetrics.circle)
            case .omitted:
                circle
            }
        }
        .contentShape(Rectangle())
    }

    /// The other game's flat mini board in a 44 pt glass circle.
    private var circle: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return Group {
            if let position = face.board {
                PositionBoardView(boardPosition: position).equatable()
            } else {
                shape.fill(Color(uiColor: .secondarySystemFill))
            }
        }
        .frame(width: GameControlChipMetrics.boardWidth, height: GameControlChipMetrics.boardWidth)
        .clipShape(shape)
        .frame(width: GameControlZenMetrics.circle, height: GameControlZenMetrics.circle)
        .modifier(GameChromeButtonSurface())
    }

    /// The countdown in a 22 pt glass capsule, with a red outline and red
    /// digits when the other game is low on time.
    private var capsule: some View {
        HStack(spacing: GameControlZenMetrics.countdownSpacing) {
            if let symbol = countdown.symbol {
                Image(systemName: symbol)
                    .font(.system(size: GameControlZenMetrics.symbolSize, weight: .semibold))
                    .foregroundStyle(countdown.symbolIsWarning ? Color.gameControlWarning : Color.secondary)
            }
            if countdown.showsClock {
                Text(verbatim: face.clock?.text ?? "")
                    .font(face.textFont)
                    .foregroundStyle(face.warns ? Color.gameControlWarning : Color.primary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, GameControlZenMetrics.countdownPadding)
        .frame(height: GameControlZenMetrics.countdownHeight)
        .modifier(GameChromeButtonSurface(shape: Capsule()))
        .overlay {
            if face.warns {
                Capsule().strokeBorder(Color.gameControlWarning, lineWidth: 1.5)
            }
        }
    }
}

// MARK: - Deadlines

/// Redraws the control where time alone changes its state: when a started
/// game's lead ends, and each second while two or more of the user's other
/// live games are on their move, whose order can change, or while a started
/// game leads. It only redraws; Game Detail computes the state again in its
/// body.
final class GameControlDeadlines: ObservableObject {
    struct Plan: Equatable {
        /// When the latest started game's lead ends, in seconds since 1970.
        var leadEnds: TimeInterval?
        var ticksEachSecond = false
    }

    private var plan = Plan()
    private var timer: Timer?

    /// Follows `plan` from `now`, in seconds since 1970.
    func follow(_ plan: Plan, now: TimeInterval) {
        guard plan != self.plan else { return }
        self.plan = plan
        timer?.invalidate()
        timer = nil
        let interval: TimeInterval
        if plan.ticksEachSecond {
            interval = 1
        } else if let leadEnds = plan.leadEnds, leadEnds > now {
            interval = leadEnds - now
        } else {
            return
        }
        let timer = Timer(timeInterval: interval, repeats: plan.ticksEachSecond) { [weak self] _ in
            self?.objectWillChange.send()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }
}

// MARK: - The Large Content Viewer

/// Takes the Large Content Viewer off the bar's host of a custom item while
/// the item is in a window. At accessibility text sizes the bar gives that
/// host a viewer interaction, which takes a touch and hold for its own
/// enlarged copy of the item and turns the release into a tap, which on the
/// chip is a switch. The control's popover is its large view instead. When
/// it enters a window, and whenever the text size changes, the guard looks
/// from its own view up to the enclosing bar and removes every viewer
/// interaction on the way. It stops before the bar's own views, which serve
/// the bar's other items, also after Back. When it leaves the window it
/// adds each back, so a host the bar reuses for another item keeps its
/// viewer, unless another custom item's guard is inside that host by then,
/// which gives it back in turn. If the bar ever gives one back first, a
/// hold switches games again: the viewer takes the touch before the button
/// sees a press, and its release reaches the chip as a tap.
private struct GameControlLargeContentViewerGuard: UIViewRepresentable {
    func makeUIView(context: Context) -> GuardView { GuardView() }

    func updateUIView(_ view: GuardView, context: Context) {}

    final class GuardView: UIView {
        /// A viewer interaction the guard removed, and the view it was on.
        private struct Removed {
            weak var view: UIView?
            let interaction: UILargeContentViewerInteraction
        }

        /// What it removed and gives back when it leaves the window.
        private var removed = [Removed]()

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            accessibilityElementsHidden = true
            registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: GuardView, _: UITraitCollection) in
                view.removeViewers()
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // What it took in the window it left goes back first.
            restoreViewers()
            removeViewers()
        }

        /// Now, and again a main-queue turn later, once the bar has finished
        /// setting up the item.
        private func removeViewers() {
            removeViewersNow()
            DispatchQueue.main.async { [weak self] in
                self?.removeViewersNow()
            }
        }

        private func removeViewersNow() {
            guard window != nil else { return }
            var ancestor = superview
            while let view = ancestor, !(view is UIWindow) {
                let name = String(describing: type(of: view))
                if name.contains("Toolbar") || name.contains("NavigationBar") { return }
                for case let interaction as UILargeContentViewerInteraction in view.interactions {
                    view.removeInteraction(interaction)
                    removed.append(Removed(view: view, interaction: interaction))
                    #if DEBUG && MAIN_APP
                    GameControlLog.record("removed the Large Content Viewer from \(type(of: view))")
                    #endif
                }
                ancestor = view.superview
            }
        }

        private func restoreViewers() {
            let records = removed
            removed = []
            for record in records {
                guard let view = record.view else { continue }
                if let heir = Self.guardView(in: view, otherThan: self) {
                    heir.removed.append(record)
                    #if DEBUG && MAIN_APP
                    GameControlLog.record("left the Large Content Viewer off \(type(of: view)) for the item in it")
                    #endif
                } else if !view.interactions.contains(where: { $0 is UILargeContentViewerInteraction }) {
                    view.addInteraction(record.interaction)
                    #if DEBUG && MAIN_APP
                    GameControlLog.record("restored the Large Content Viewer to \(type(of: view))")
                    #endif
                }
            }
        }

        /// Another guard in a window inside `view`.
        private static func guardView(in view: UIView, otherThan excluded: GuardView) -> GuardView? {
            for subview in view.subviews {
                if let found = subview as? GuardView, found !== excluded, found.window != nil { return found }
                if let found = guardView(in: subview, otherThan: excluded) { return found }
            }
            return nil
        }
    }
}

#if DEBUG && MAIN_APP
/// Lines under subsystem com.honganhkhoa.Surround, category GameControl.
enum GameControlLog {
    private static let log = Logger(subsystem: "com.honganhkhoa.Surround", category: "GameControl")

    static func record(_ message: String) {
        log.notice("\(message, privacy: .public)")
    }
}
#endif
