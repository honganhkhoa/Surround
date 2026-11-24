//
//  GameControlModel.swift
//  Surround
//
//  The in-game control's rules that need no view: the value Game Detail's
//  Active games slot shows, the window's width class, shape and top-bar
//  room that the control's frames and forms follow, what each form draws
//  and how its text fits a fixed frame, what a tap or a hold does, what
//  VoiceOver says, how a Game Detail switches to another game, when the
//  control's popover is open, which challenge the game-over card shows,
//  where a game says that the connection is down, and where a
//  conversation shows the live game that needs you. Each reads only state
//  its screen has before it draws, so SurroundTests checks it without a
//  socket or a view.
//

import Foundation
import UIKit

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

    /// The control in a conversation's top bar, from the window's input for
    /// the conversation (`ActivityModel.conversationControl(_:)`): another
    /// live game on your move, or one that started elsewhere, with no +N and
    /// no dot. Nil while no live game needs you.
    init?(conversation input: ActivityModel.Input) {
        guard let control = ActivityModel.conversationControl(input) else { return nil }
        self.init(control)
    }
}

/// Which control a custom item draws, and the identifier XCTest finds it by.
enum GameControlItemRole: Equatable, CaseIterable {
    /// Game Detail's Active games slot: a tap shows the chip's game, and a
    /// touch and hold opens the popover.
    case activeGames
    /// Zen's control beside Exit: a tap shows the game; Zen has no popover.
    case zen
    /// A conversation's top bar while a live game needs you: a tap shows the
    /// game through Home, with no hold and no popover.
    case conversation

    var accessibilityIdentifier: String {
        switch self {
        case .activeGames: SurroundUITestContract.AccessibilityID.gameActiveGamesButton
        case .zen: SurroundUITestContract.AccessibilityID.gameZenControl
        case .conversation: SurroundUITestContract.AccessibilityID.messagesConversationGameControl
        }
    }

    /// A tap shows the game and nothing else, with no hold and no popover:
    /// Zen's control and a conversation's, which VoiceOver says as Zen's.
    var isTapOnly: Bool { self != .activeGames }
}

// MARK: - The window

/// The window a Game Detail is in, as the window's root measures it: which
/// class its width falls in, its shape, and whether a full-size top bar has
/// room for the chip. The control's frames and forms are fixed per class,
/// so they change only when the window resizes or turns, which nothing
/// inside the window can cause. The root knows all three long before a
/// game opens, while Game Detail's own geometry arrives a main-queue turn
/// after its first layout.
struct GameControlWindowClass: Equatable {
    /// The window widths at which the control's frames change, narrowest
    /// first. Another boundary is one more case with its minimum width.
    enum WidthClass: Comparable, CaseIterable {
        /// Narrower than 375 pt, which no device measured: the bottom bar
        /// shows the base icon alone, and the popover carries the rest.
        case floor
        /// From 375 pt to 390 pt. At 375 pt the full chip beside three
        /// modes pushes Analyze and Chat into More on iOS 26 and 27, so
        /// there the chip narrows.
        case narrow
        /// From 390 pt to 402 pt, where the full chip fits beside three
        /// modes at the default text size. From one size larger, iOS 27's
        /// bar keeps wider side insets at 390 pt and takes Analyze and Chat
        /// out of it, so there the chip narrows too
        /// (`GameControlDrawing.narrowsFromTextSize`).
        case standard
        /// 402 pt and wider, where the full chip fits beside three modes at
        /// every text size.
        case wide

        /// The narrowest window in the class, in points.
        var minimumWidth: CGFloat {
            switch self {
            case .floor: 0
            case .narrow: 375
            case .standard: 390
            case .wide: 402
            }
        }

        /// The widest class whose minimum `width` reaches.
        init(width: CGFloat) {
            self = Self.allCases.last { width >= $0.minimumWidth } ?? .floor
        }
    }

    enum Shape: Equatable {
        case portrait
        /// Wider than tall, as Game Detail reads its window for its
        /// landscape layouts.
        case landscape
    }

    var widthClass: WidthClass
    var shape: Shape
    /// A full-size top bar, the wide windows' one row of Back, the modes,
    /// the control and the utilities, has room for the 96 pt chip beside
    /// three modes, Zen and Options. Where it hasn't, the control there is
    /// the system's icon with its badge (`GameControlForm.narrowTopBar`).
    var topBarFitsChip: Bool

    init(widthClass: WidthClass, shape: Shape, topBarFitsChip: Bool = true) {
        self.widthClass = widthClass
        self.shape = shape
        self.topBarFitsChip = topBarFitsChip
    }

    /// From the window's bounds and horizontal size class, and the device.
    init(windowSize: CGSize, isRegularWidth: Bool = false, isPhone: Bool = false) {
        self.init(widthClass: WidthClass(width: windowSize.width),
                  shape: windowSize.width > windowSize.height ? .landscape : .portrait,
                  topBarFitsChip: Self.topBarFitsChip(windowSize: windowSize, isRegularWidth: isRegularWidth,
                                                      isPhone: isPhone))
    }

    /// The row a full-size top bar needs for the chip: Back and the sidebar
    /// toggle, which end 128 pt from the window's leading edge; the 393 pt
    /// platter of three modes, the chip, Zen and Options; at least 16 pt
    /// between the two groups; and the window's 16 pt trailing corner.
    static let topBarRowForChip: CGFloat = 553

    /// What the status bar takes from the end of a top bar's row where it
    /// shares the row: 144 pt on the Duo in its tall poses, 128 pt more than
    /// the corner every window keeps.
    static let statusBarShareOfTopBarRow: CGFloat = 128

    /// Whether a full-size top bar has room for the chip, from the window's
    /// width, less what the status bar takes where it shares the row. On a
    /// phone at regular width in a window taller than wide, as the Duo's
    /// tall poses are, the status bar sits at the end of the top bar's row
    /// rather than above it, and the chip would push Zen and Options into
    /// More. No inset the window reports gives that share steadily: the
    /// bar's layout region drops it while Zen hides the status bar, which
    /// would change the form when Zen ends. Window controls never decide
    /// it: the narrowest regular iPad window still has room with them. Only
    /// a regular-width window shows a full-size top bar, so a compact one
    /// counts as having room and keeps its value while it resizes.
    static func topBarFitsChip(windowSize: CGSize, isRegularWidth: Bool, isPhone: Bool) -> Bool {
        guard isRegularWidth else { return true }
        let sharesRowWithStatusBar = isPhone && windowSize.height > windowSize.width
        let row = windowSize.width - (sharesRowWithStatusBar ? statusBarShareOfTopBarRow : 0)
        return row >= topBarRowForChip
    }
}

// MARK: - The control's forms

/// Where the control sits, which decides how it draws. The bars draw a
/// custom view. The Duo's rail and the Mac use the system's icon and badge:
/// a native item draws only an image, and the Mac's toolbar never draws a
/// custom view. So does a full-size top bar too narrow for the chip.
enum GameControlForm: Equatable {
    /// The iPhone's bottom bar, and a narrow iPad window's.
    case bottomBar
    /// A top bar on iOS, in compact landscape or in a wide window.
    case topBar
    /// A wide window's top bar without room for the chip, as the Duo's in
    /// its tall poses, whose status bar shares the bar's row: the system's
    /// icon and badge, as on the rail.
    case narrowTopBar
    /// The Duo's vertical rail.
    case rail
    /// The Mac's toolbar.
    case mac

    init(_ form: GameActiveGamesPlacement.Form, isCatalyst: Bool) {
        if isCatalyst {
            self = .mac
            return
        }
        switch form {
        case .bottomBar: self = .bottomBar
        case .topBar: self = .topBar
        case .rail: self = .rail
        }
    }

    /// The form at `placement` in a window: a wide window's top bar shows
    /// the system's icon where the window leaves it no room for the chip.
    /// Compact landscape's bar always has room. A window the root hasn't
    /// measured gets the chip, as it gets the full frames.
    init(_ placement: GameActiveGamesPlacement, isCatalyst: Bool, windowClass: GameControlWindowClass?) {
        self.init(placement.form, isCatalyst: isCatalyst)
        if self == .topBar, placement == .topBarAfterModes, windowClass?.topBarFitsChip == false {
            self = .narrowTopBar
        }
    }

    /// The system's own item, which takes no hold and badges a count.
    var isNative: Bool { self == .rail || self == .mac || self == .narrowTopBar }

    /// The native items, and the bottom bar below 375 pt, show an icon and
    /// nothing of the state's content.
    func showsIconAlone(in windowClass: GameControlWindowClass?) -> Bool {
        isNative || (self == .bottomBar && windowClass?.widthClass == .floor)
    }
}

/// The icon the control shows alone, or before its count.
enum GameControlIcon: Equatable {
    /// The picker's grid: Active games.
    case grid
    /// The inbox glyph: Activity, where there is no picker.
    case inbox

    var systemName: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .inbox: "tray"
        }
    }

    /// A state's icon where the control shows an icon alone: the native
    /// items, and the bottom bar's floor. The dot keeps the inbox glyph
    /// where there is no picker, as its drawn form does.
    init(_ slot: GameControlSlot, allowsPicker: Bool) {
        switch slot {
        case .inbox: self = .inbox
        case .dot: self = allowsPicker ? .grid : .inbox
        case .chip, .gameStarted, .gameOverCard, .base: self = .grid
        }
    }
}

extension GameControlSlot {
    /// What waits beyond what the control shows: +N, or the inbox's count.
    var plusN: Int {
        switch self {
        case let .chip(_, plusN, _), let .gameStarted(_, plusN, _),
             let .gameOverCard(_, plusN), let .base(plusN):
            plusN
        case .inbox(let count): count
        case .dot: 0
        }
    }

    /// A challenge or a message waits while the user plays live.
    var hasDot: Bool {
        switch self {
        case let .chip(_, _, hasDot), let .gameStarted(_, _, hasDot): hasDot
        case .dot: true
        case .gameOverCard, .base, .inbox: false
        }
    }

    /// The game the state shows: the chip's, or the one that started.
    var gameID: Int? {
        switch self {
        case let .chip(gameID, _, _), let .gameStarted(gameID, _, _): gameID
        case .gameOverCard, .base, .dot, .inbox: nil
        }
    }

    /// The challenge the game-over card shows.
    var cardChallengeID: Int? {
        if case let .gameOverCard(challengeID, _) = self { return challengeID }
        return nil
    }
}

// MARK: - The chip's clock

/// The other game's clock as the chip draws it: digits only, the same in
/// every language. `MM:SS` under an hour, `H:MM:SS` from an hour and
/// `HH:MM:SS` from ten. The digits are monospaced, so every time of one
/// length is as wide as `widestSample`, and the chip's fit changes only
/// when the clock crosses an hour boundary.
struct GameControlClock: Equatable {
    /// Whole seconds left, truncated as Home's chip reads them.
    let seconds: Int

    init(timeLeft: TimeInterval) {
        // A clock never reads below 0, and no game's clock is near the
        // bound, which keeps the conversion from overflowing.
        seconds = timeLeft.isFinite ? Int(min(max(timeLeft, 0), 1e9)) : 0
    }

    var text: String {
        let minutesAndSeconds = Self.twoDigits(seconds / 60 % 60) + ":" + Self.twoDigits(seconds % 60)
        let hours = seconds / 3600
        return hours > 0 ? "\(hours):" + minutesAndSeconds : minutesAndSeconds
    }

    /// The text with every digit 0, as wide as any time of its length.
    var widestSample: String {
        String(text.map { $0 == ":" ? ":" : "0" })
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

/// The mark the chip draws in the hourglass's place in sudden death, the
/// other game's last byo-yomi period, beside a red outline and red digits,
/// so the state never rests on color alone.
enum GameControlSuddenDeathMark: Equatable {
    /// The language's "SD".
    case text(String)
    /// A red exclamation mark in a circle.
    case glyph

    static let glyphSystemName = "exclamationmark.circle.fill"
    /// The widest the text may draw at the bottom bar's cap, in points.
    static let textSlotWidth: CGFloat = 26

    /// The bottom bar's mark for a language's "SD": the text where it fits
    /// the slot at the bottom bar's cap, otherwise the glyph. No text size
    /// draws it wider than the cap does, so a language keeps one form at
    /// every size, and a new translation moves its language between the
    /// forms without a code change.
    init(bottomBar localizedSD: String) {
        let atCap = GameControlChipMetrics(form: .bottomBar, sizeCategory: GameControlChipMetrics.cap(for: .bottomBar))
        let fits = GameControlChipMetrics.textWidth(localizedSD, font: atCap.textFont) <= Self.textSlotWidth
        self = !localizedSD.isEmpty && fits ? .text(localizedSD) : .glyph
    }

    /// The mark `form` draws, in the app's language. Top bars always draw
    /// the glyph.
    static func drawn(in form: GameControlForm) -> Self {
        guard form == .bottomBar else { return .glyph }
        return Self(bottomBar: String(localized: "SD", comment: "Final byo-yomi period (Sudden Death)"))
    }
}

// MARK: - What the custom forms draw

/// A part of the control's custom view, from leading to trailing.
enum GameControlPart: Equatable {
    /// The other game's flat mini board, or a started game's.
    case board
    /// The challenger's tile, at game over.
    case tile
    case icon(GameControlIcon)
    /// Before the clock as it counts down; alone where the game has no
    /// countdown.
    case hourglass
    /// In the hourglass's place in sudden death.
    case suddenDeathMark
    case clock
    /// What waits beyond what the control shows, in a neutral capsule.
    case plusN
}

/// What the control's custom view draws in a bar for a slot, before it
/// fits: a frame fixed by the form, the state, the window's width class
/// and, beside three modes in the bottom bar, the text size, never by the
/// clock, so the bar's layout never changes as the clock ticks;
/// the parts; and those that drop when the rest doesn't fit, the first to
/// drop first. Text never truncates.
///
/// - Bottom bar: the chip's board, hourglass, clock and +N, with a dot at
///   the top trailing corner while a challenge or a message waits as you
///   play live. In sudden death the mark takes the hourglass's place and +N
///   always drops. The hourglass drops first, then +N, whose count stays in
///   VoiceOver and the popover. A started game's mini board, or the
///   challenger's tile at game over, with +N.
/// - Top bars: the chip's board, hourglass and clock, with the glyph as the
///   mark. The hourglass drops first, then the board. A started game's mini
///   board, or the tile, alone.
/// - Both: the base's grid icon, and the inbox glyph, with +N; the dot's
///   icon with the dot.
/// - The floor, below 375 pt in the bottom bar: the base icon alone, with
///   the dot where one applies. The popover carries the rest.
/// - The name never shows in a bar: VoiceOver and the popover say who.
///
/// The clock and the mark never drop. Nor does the bottom bar's board, in
/// any language up to the cap, for a clock under a hundred hours, or under
/// an hour in sudden death, as a live game's last period always is but for
/// the first second of an hour-long one. The board drops last only so that
/// a clock wider than those still can't overflow.
struct GameControlDrawing: Equatable {
    /// The bottom bar's chip, started game and card: from 402 pt; from
    /// 390 pt below `narrowsFromTextSize`; and from 375 pt beside fewer
    /// than three modes.
    static let chipWidth: CGFloat = 160
    /// The same beside three modes, from 375 pt to 390 pt, and from 390 pt
    /// to 402 pt at `narrowsFromTextSize` and larger.
    static let narrowChipWidth: CGFloat = 120
    /// The text size from which the bottom bar's own items have grown so
    /// that the full chip beside three modes no longer fits a window from
    /// 390 pt to 402 pt: one size above the default.
    static let narrowsFromTextSize = UIContentSizeCategory.extraLarge
    /// A top bar's chip, started game and card.
    static let topBarChipWidth: CGFloat = 96
    /// An icon alone.
    static let iconWidth: CGFloat = 44
    /// An icon and its count.
    static let iconWithCountWidth: CGFloat = 84
    static let height: CGFloat = 44

    var frame: CGSize
    var parts: [GameControlPart]
    /// The parts that may drop, the first to drop first.
    var dropOrder: [GameControlPart]
    /// The count `.plusN` draws; 0 where no part draws it.
    var plusN: Int
    /// The 10 pt dot at the top trailing corner.
    var hasDot: Bool
    /// The red outline and digits, with the mark in the hourglass's place.
    var isSuddenDeath: Bool

    /// Nil in the native forms, which draw the system's item.
    /// - Parameters:
    ///   - windowClass: The window's, from its root; nil until the root has
    ///     measured it, which gives the full frames.
    ///   - modeCount: The mode buttons beside the control: Analyze and
    ///     Chat, and Conditional moves while it shows.
    ///   - sizeCategory: The text size of the screen that owns the bar.
    ///   - allowsPicker: The route has the picker
    ///     (`GameControlSwitch.allowsPicker`).
    ///   - hasCountdown: The chip's game counts down. Without a countdown
    ///     the hourglass shows alone.
    ///   - isSuddenDeath: The chip's game is in its last byo-yomi period.
    init?(_ slot: GameControlSlot, form: GameControlForm, windowClass: GameControlWindowClass?,
          modeCount: Int, sizeCategory: UIContentSizeCategory, allowsPicker: Bool, hasCountdown: Bool = true,
          isSuddenDeath: Bool = false) {
        guard !form.isNative else { return nil }
        frame = Self.frame(slot, form: form, windowClass: windowClass, modeCount: modeCount,
                           sizeCategory: sizeCategory)
        hasDot = form == .bottomBar ? slot.hasDot : slot == .dot
        self.isSuddenDeath = false
        let inBottomBar = form == .bottomBar
        let count: [GameControlPart] = slot.plusN > 0 ? [.plusN] : []
        if form.showsIconAlone(in: windowClass) {
            parts = [.icon(GameControlIcon(slot, allowsPicker: allowsPicker))]
            dropOrder = []
        } else {
            switch slot {
            case .chip where !hasCountdown:
                // The hourglass stands in for the clock, so it stays.
                parts = [.board, .hourglass] + (inBottomBar ? count : [])
                dropOrder = inBottomBar ? count : []
            case .chip where isSuddenDeath:
                // +N always drops; in a top bar the glyph may push the
                // board out.
                self.isSuddenDeath = true
                parts = [.board, .suddenDeathMark, .clock]
                dropOrder = [.board]
            case .chip:
                parts = [.board, .hourglass, .clock] + (inBottomBar ? count : [])
                dropOrder = [.hourglass] + (inBottomBar ? count : []) + [.board]
            case .gameStarted:
                parts = [.board] + (inBottomBar ? count : [])
                dropOrder = inBottomBar ? count : []
            case .gameOverCard:
                parts = [.tile] + (inBottomBar ? count : [])
                dropOrder = inBottomBar ? count : []
            case .base:
                parts = [.icon(.grid)] + count
                dropOrder = count
            case .dot:
                parts = [.icon(GameControlIcon(slot, allowsPicker: allowsPicker))]
                dropOrder = []
            case .inbox:
                parts = [.icon(.inbox)] + count
                dropOrder = count
            }
        }
        plusN = parts.contains(.plusN) ? slot.plusN : 0
    }

    /// The fixed frame, from the form, the state, the window's class, the
    /// mode count and the text size alone, so neither the clock nor sudden
    /// death moves the bar's layout.
    static func frame(_ slot: GameControlSlot, form: GameControlForm, windowClass: GameControlWindowClass?,
                      modeCount: Int, sizeCategory: UIContentSizeCategory) -> CGSize {
        let widthClass = windowClass?.widthClass ?? .wide
        let width: CGFloat
        if form.showsIconAlone(in: windowClass) {
            width = iconWidth
        } else {
            switch slot {
            case .chip, .gameStarted, .gameOverCard:
                if form != .bottomBar {
                    width = topBarChipWidth
                } else {
                    width = narrowsBesideModes(widthClass, modeCount: modeCount, sizeCategory: sizeCategory)
                        ? narrowChipWidth : chipWidth
                }
            case .base, .dot, .inbox:
                width = slot.plusN > 0 ? iconWithCountWidth : iconWidth
            }
        }
        return CGSize(width: width, height: height)
    }

    /// The bottom bar's chip narrows beside three modes: from 375 pt to
    /// 390 pt at every text size, and from 390 pt to 402 pt from
    /// `narrowsFromTextSize`, where the bar's own items have grown. Nothing
    /// else narrows it, so the bar's layout follows the window and the
    /// text size alone.
    static func narrowsBesideModes(_ widthClass: GameControlWindowClass.WidthClass, modeCount: Int,
                                   sizeCategory: UIContentSizeCategory) -> Bool {
        guard modeCount >= 3 else { return false }
        switch widthClass {
        case .narrow: return true
        case .standard: return sizeCategory != .unspecified && sizeCategory >= narrowsFromTextSize
        case .floor, .wide: return false
        }
    }
}

/// The parts a drawing keeps at a text size, after its drop order.
struct GameControlFit: Equatable {
    var parts: [GameControlPart]
    /// The parts with their padding and the spacing between them, in points.
    var width: CGFloat
    /// The parts that never drop fit the frame.
    var fits: Bool
}

extension GameControlDrawing {
    /// Drops parts in `dropOrder` until the rest fit the frame, measured
    /// with `metrics` for the current clock's length and +N.
    func fit(_ metrics: GameControlChipMetrics, clock: GameControlClock?,
             mark: GameControlSuddenDeathMark) -> GameControlFit {
        fit(spacing: metrics.spacing) { metrics.width(of: $0, clock: clock, plusN: plusN, mark: mark) }
    }

    /// The drop rule alone, from each part's width.
    func fit(spacing: GameControlChipSpacing, width: (GameControlPart) -> CGFloat) -> GameControlFit {
        var kept = parts
        var drops = dropOrder[...]
        var total = spacing.width(of: kept, width)
        while total > frame.width, let next = drops.popFirst() {
            kept.removeAll { $0 == next }
            total = spacing.width(of: kept, width)
        }
        return GameControlFit(parts: kept, width: total, fits: total <= frame.width)
    }
}

/// The padding and spacing of a custom form's parts, in points.
struct GameControlChipSpacing: Equatable {
    var leading: CGFloat
    var trailing: CGFloat
    /// Between two parts.
    var between: CGFloat
    /// Between the hourglass or the mark and the clock, which read as one.
    var beforeClock: CGFloat

    /// The narrow frame holds the board, the widest mark the text form
    /// allows, and the clock at the cap, with 1 pt to spare.
    static let bottomBar = Self(leading: 5, trailing: 5, between: 4, beforeClock: 2)
    static let topBar = Self(leading: 2, trailing: 2, between: 4, beforeClock: 2)

    func width(of parts: [GameControlPart], _ width: (GameControlPart) -> CGFloat) -> CGFloat {
        guard !parts.isEmpty else { return 0 }
        var total = leading + trailing
        for (index, part) in parts.enumerated() {
            total += width(part)
            guard index > 0 else { continue }
            let joinsClock = part == .clock && [.hourglass, .suddenDeathMark].contains(parts[index - 1])
            total += joinsClock ? beforeClock : between
        }
        return total
    }
}

/// The custom forms' fonts, and their parts' widths at a text size,
/// measured with UIKit as Game Detail's action row measures its labels
/// (`GameControlRowMetrics`). The fonts are fixed at the size they scale to,
/// and the view draws its text and symbols at those sizes, so what fits
/// here fits on screen. Text stops growing at each form's cap: extra large
/// in the bottom bar, large in top bars, which draw within 36 pt of height.
/// At accessibility sizes a bar caps a custom item's text at XXL, above
/// both, so these caps decide.
struct GameControlChipMetrics {
    /// The mini board, and the challenger's tile.
    static let boardWidth: CGFloat = 28
    /// The base, dot and inbox icons, which don't grow with the text.
    static let iconWidth: CGFloat = 24
    /// The padding on each side of +N's text in its capsule.
    static let countPadding: CGFloat = 6
    /// The narrowest +N's capsule draws.
    static let countMinimumWidth: CGFloat = 26

    /// The largest text size `form` draws.
    static func cap(for form: GameControlForm) -> UIContentSizeCategory {
        form == .bottomBar ? .extraLarge : .large
    }

    let form: GameControlForm
    /// The text size the form draws at: the one asked for, up to its cap.
    let sizeCategory: UIContentSizeCategory
    /// The clock and the mark's text: 15 pt semibold with monospaced
    /// digits, scaled as subheadline.
    let textFont: UIFont
    /// +N: 13 pt semibold with monospaced digits, scaled as footnote.
    let countFont: UIFont

    var spacing: GameControlChipSpacing { form == .bottomBar ? .bottomBar : .topBar }

    init(form: GameControlForm, sizeCategory: UIContentSizeCategory) {
        self.form = form
        let requested = sizeCategory == .unspecified ? .large : sizeCategory
        let capped = min(requested, Self.cap(for: form))
        self.sizeCategory = capped
        let traits = UITraitCollection(preferredContentSizeCategory: capped)
        func scaled(_ size: CGFloat, as style: UIFont.TextStyle) -> CGFloat {
            UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size), compatibleWith: traits).pointSize
        }
        textFont = .monospacedDigitSystemFont(ofSize: scaled(15, as: .subheadline), weight: .semibold)
        countFont = .monospacedDigitSystemFont(ofSize: scaled(13, as: .footnote), weight: .semibold)
    }

    /// A part's width in points. The clock measures its widest sample, so
    /// its width changes only with its length.
    func width(of part: GameControlPart, clock: GameControlClock?, plusN: Int,
               mark: GameControlSuddenDeathMark) -> CGFloat {
        switch part {
        case .board, .tile: Self.boardWidth
        case .icon: Self.iconWidth
        case .hourglass: symbolWidth("hourglass")
        case .suddenDeathMark:
            switch mark {
            case .text(let text): ceil(Self.textWidth(text, font: textFont))
            case .glyph: symbolWidth(GameControlSuddenDeathMark.glyphSystemName)
            }
        case .clock: ceil(Self.textWidth(clock?.widestSample ?? "", font: textFont))
        case .plusN:
            max(Self.countMinimumWidth,
                ceil(Self.textWidth(Self.countText(plusN), font: countFont)) + 2 * Self.countPadding)
        }
    }

    /// +N as its capsule draws it.
    static func countText(_ plusN: Int) -> String { "+\(plusN)" }

    static func textWidth(_ text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// A symbol's width at the text's size and weight, as the view draws it
    /// beside the clock.
    func symbolWidth(_ systemName: String) -> CGFloat {
        let configuration = UIImage.SymbolConfiguration(pointSize: textFont.pointSize, weight: .semibold)
        let image = UIImage(systemName: systemName, withConfiguration: configuration)
        return ceil(image?.size.width ?? textFont.pointSize)
    }
}

// MARK: - The native forms

/// The control on the Duo's rail, on the Mac and in a top bar too narrow
/// for the chip: the system's icon with its red badge. A native item draws
/// only its image and badge, so the chip's game, a started game and the
/// card show inside the popover instead.
struct GameControlNativeItem: Equatable {
    enum Badge: Hashable {
        case none
        case count(Int)
        /// An empty-text badge, which the system draws as a red dot.
        case dot
    }

    var icon: GameControlIcon
    var badge: Badge

    init(icon: GameControlIcon, badge: Badge) {
        self.icon = icon
        self.badge = badge
    }

    /// - The chip, a started game and the card: the grid icon, its count the
    ///   game it stands for and +N. In Zen, where +N is 0, a badge of 1.
    /// - Base: the grid icon and +N. Inbox: the inbox glyph and its count.
    /// - Dot: the dot's icon with the red dot.
    /// - No slot: hidden, except where `keepsPlace` keeps the unbadged inbox
    ///   glyph (`keepsPlace(at:isSignedIn:)`).
    init?(_ slot: GameControlSlot?, allowsPicker: Bool, keepsPlace: Bool = false) {
        guard let slot else {
            guard keepsPlace else { return nil }
            self.init(icon: .inbox, badge: .none)
            return
        }
        let icon = GameControlIcon(slot, allowsPicker: allowsPicker)
        switch slot {
        case .chip, .gameStarted, .gameOverCard:
            self.init(icon: icon, badge: .count(slot.plusN + 1))
        case .base, .inbox:
            self.init(icon: icon, badge: slot.plusN > 0 ? .count(slot.plusN) : .none)
        case .dot:
            self.init(icon: icon, badge: .dot)
        }
    }

    /// Whether the item keeps its place, as the unbadged inbox glyph, while
    /// no slot shows: in the Duo's wide poses, so the pill beside it stays
    /// put, while the user is signed in. Signed out nothing can wait, so the
    /// item hides there too, rather than open a popover with nothing in it.
    static func keepsPlace(at placement: GameActiveGamesPlacement, isSignedIn: Bool) -> Bool {
        placement == .railSeparated && isSignedIn
    }
}

/// When the control's native item is made again. iOS 27 can keep a native
/// bar item's stale badge, so the item takes a new identity when its badge
/// changes. Never while the popover it presented is open or still on
/// screen: the item that presented a popover has to stay until the popover
/// has gone, or UIKit can no longer dismiss it and it stays on screen. A
/// live Accept or a switch closes the popover in code in the same pass that
/// changes the badge, so the item keeps the badge it was made with until
/// the popover's content has disappeared, then takes the one it shows.
struct GameControlNativeIdentity: Equatable {
    /// The badge the item was made with; nil for no item.
    private(set) var badge: GameControlNativeItem.Badge?
    /// The popover's content is on screen: from its appearance until its
    /// disappearance, which comes once the popover has gone.
    private(set) var isPopoverOnScreen = false

    /// The popover is open or still on screen, so the item stays as it is.
    func holds(isPopoverOpen: Bool) -> Bool {
        isPopoverOpen || isPopoverOnScreen
    }

    /// The item's identity in a pass that shows `badge`.
    func id(showing badge: GameControlNativeItem.Badge?, isPopoverOpen: Bool) -> GameControlNativeItem.Badge? {
        holds(isPopoverOpen: isPopoverOpen) ? self.badge : badge
    }

    /// The item shows `badge`. Unless the identity holds, that is now the
    /// badge it was made with.
    mutating func follow(_ badge: GameControlNativeItem.Badge?, isPopoverOpen: Bool) {
        guard !holds(isPopoverOpen: isPopoverOpen) else { return }
        self.badge = badge
    }

    mutating func popoverAppeared() {
        isPopoverOnScreen = true
    }

    mutating func popoverDisappeared() {
        isPopoverOnScreen = false
    }
}

// MARK: - A conversation's control

/// Where a conversation shows the live game that needs you
/// (`GameControlSlot(conversation:)`). The window's size classes, the Duo's
/// vertical toolbar and the platform choose, never a bar's measured width:
/// a pushed conversation's toolbar is built in the pass that hides the tab
/// bar, so the place it has there is the place every later pass gives it.
///
/// - Pushed, with a horizontal bar, in compact width and regular height (a
///   phone in portrait, a compact iPad window): the system's small icon
///   with a badge of 1, since the chip would cost the heading its room.
/// - Pushed, with a horizontal bar elsewhere (an iPhone in landscape, an
///   iPad in regular width): the chip, an item of its own.
/// - With the Duo's vertical toolbar, pushed or in Messages' pane: the
///   rail's icon with a badge of 1, as Game Detail's rail; none on the
///   closed Duo turned sideways (compact both ways), where a third item
///   would push Challenge and Profile into More.
/// - Messages' pane with a horizontal bar, the Mac's two columns included:
///   the chip in the pane's heading.
/// - The Mac, pushed: the toolbar's icon with a badge of 1.
/// - Inside Activity's own stack: none, since Back already shows its live
///   row.
///
/// Each goes before Challenge and Profile.
enum ConversationGameControlPlacement: Equatable {
    case none
    /// The system's icon with a badge of 1, among the top bar's trailing
    /// items.
    case barIcon
    /// The chip, among the top bar's trailing items.
    case barChip
    /// The vertical toolbar's icon with a badge of 1, in a group of its own.
    case railIcon
    /// The chip in the pane's heading, which is no bar item.
    case headingChip
    /// The Mac's toolbar icon with a badge of 1.
    case macToolbarIcon

    /// What the window knows before the conversation draws.
    struct Input: Equatable {
        /// Messages' side pane, rather than a pushed screen.
        var isPane: Bool
        /// Activity's own stack, where `\.activityConnection` is set.
        var isInActivityStack = false
        /// The Duo's vertical toolbar (`\.isVerticalToolbar`).
        var isVerticalToolbar = false
        var isCompactWidth: Bool
        var isCompactHeight: Bool
        var isCatalyst = false
    }

    init(_ input: Input) {
        if input.isInActivityStack {
            self = .none
        } else if input.isCatalyst {
            self = input.isPane ? .headingChip : .macToolbarIcon
        } else if input.isVerticalToolbar {
            self = input.isCompactWidth && input.isCompactHeight ? .none : .railIcon
        } else if input.isPane {
            self = .headingChip
        } else {
            self = input.isCompactWidth && !input.isCompactHeight ? .barIcon : .barChip
        }
    }

    /// The form the control draws and speaks in: the top bar's chip, or a
    /// native item, whose label carries no time. Nil where none shows.
    var form: GameControlForm? {
        switch self {
        case .none: nil
        case .barChip, .headingChip: .topBar
        case .barIcon: .narrowTopBar
        case .railIcon: .rail
        case .macToolbarIcon: .mac
        }
    }
}

// MARK: - Tap, touch and hold

/// What a tap, a click or a touch and hold on the control does.
enum GameControlAction: Equatable {
    case none
    /// Shows the game, as `GameControlSwitch` says: the chip's switch, a
    /// started game's open, and Zen's switch.
    case show(gameID: Int)
    /// Opens the control's popover: the picker, then Activity's sections.
    case openPopover
}

/// What the control does for a tap and for a touch and hold.
///
/// - The chip and a started game: a tap shows that game; a touch and hold,
///   or VoiceOver's Open Activity, opens the popover, never a sheet over a
///   running clock.
/// - Game over, base, dot and inbox: both open the popover.
/// - The native items, on the rail, on the Mac and in a top bar too narrow
///   for the chip, can't show the chip, so a tap or a click opens the
///   popover, which leads with the chip's game. They take no hold: the
///   system makes a long press's release a tap.
/// - The bottom bar's floor shows the icon alone, so a tap opens the
///   popover there too, as a hold does.
/// - Zen's circle and items, and a conversation's control: a tap shows the
///   game; nothing else, since neither has a popover.
struct GameControlInteraction: Equatable {
    /// How long a press lasts before it is a hold.
    static let holdDuration: TimeInterval = 0.5

    var tap: GameControlAction
    var hold: GameControlAction
    /// VoiceOver offers Open Activity, which does what a hold does, where
    /// a tap shows a game.
    var offersOpenActivity: Bool

    init(_ slot: GameControlSlot, form: GameControlForm, windowClass: GameControlWindowClass? = nil,
         isZen: Bool = false) {
        if isZen {
            tap = slot.gameID.map { .show(gameID: $0) } ?? .none
            hold = .none
        } else if form.isNative {
            tap = .openPopover
            hold = .none
        } else if form.showsIconAlone(in: windowClass) {
            tap = .openPopover
            hold = .openPopover
        } else {
            tap = slot.gameID.map { .show(gameID: $0) } ?? .openPopover
            hold = .openPopover
        }
        offersOpenActivity = hold == .openPopover && tap != .openPopover
    }

    /// A press in a custom form that ends `duration` after it began. A
    /// release 0.5 s or more after the press began never switches: it opens
    /// the popover as a hold would, unless a hold already fired, and then it
    /// does nothing more. So a press whose hold didn't fire still never
    /// switches games, as long as the button saw it begin.
    func release(after duration: TimeInterval, holdFired: Bool) -> GameControlAction {
        if holdFired { return .none }
        return duration >= Self.holdDuration ? hold : tap
    }
}

/// When the current press on a custom item began, and whether its hold
/// fired: what `GameControlInteraction.release(after:holdFired:)` needs. A
/// reference, so a press redraws nothing. Some presses end without the
/// release: a hold that opened the popover can end off the item, and so can
/// a short press dragged off it. Neither may reach a later release whose
/// press the button style never saw, as when a press begins and ends within
/// one update. So a hold's press is cleared when its popover closes, and a
/// press shorter than a hold is cleared a main-queue turn after it stops
/// showing as pressed, unless a release ended it first, as a tap's does. A
/// longer press stays until its release, so that release never switches
/// games.
final class GameControlPress {
    /// A press older than this was never released on the item, as one
    /// dragged away from it; it can't be the one a tap ends.
    private static let longestPress: TimeInterval = 60
    private var began: TimeInterval?
    private var holdFired = false
    /// Goes up whenever a press is cleared, so a clear meant for one press
    /// never reaches the next.
    private var generation = 0
    private let now: () -> TimeInterval
    private let nextTurn: (@escaping () -> Void) -> Void

    /// - Parameters:
    ///   - now: Monotonic seconds, replaceable for tests.
    ///   - nextTurn: Runs its work a main-queue turn later, replaceable for
    ///     tests.
    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         nextTurn: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) {
        self.now = now
        self.nextTurn = nextTurn
    }

    /// The button style shows the item pressed.
    func begin() {
        clear()
        began = now()
    }

    /// The hold fired; the release that ends it then does nothing more.
    func hold() {
        if began == nil { began = now() - GameControlInteraction.holdDuration }
        holdFired = true
    }

    /// The button style no longer shows the item pressed. A press shorter
    /// than a hold that no release ends within this main-queue turn was
    /// dragged off the item, so it is cleared then.
    func end() {
        guard let began, !holdFired, now() - began < GameControlInteraction.holdDuration else { return }
        let press = generation
        nextTurn { [weak self] in
            guard let self, self.generation == press, !self.holdFired else { return }
            self.clear()
        }
    }

    /// The item's popover closed. A hold that opened it has ended by now,
    /// whether or not its release reached the item.
    func popoverClosed() {
        if holdFired { clear() }
    }

    /// The press that a release ends: how long it lasted and whether its
    /// hold fired. A release whose press was never seen counts as a tap.
    func release() -> (duration: TimeInterval, holdFired: Bool) {
        defer { clear() }
        let time = now()
        guard let began, time - began < Self.longestPress else { return (0, false) }
        return (time - began, holdFired)
    }

    private func clear() {
        began = nil
        holdFired = false
        generation += 1
    }
}

// MARK: - VoiceOver

/// What VoiceOver says for the control. The custom forms speak the other
/// game's time in the label, with what waits as the value. The native items
/// (`GameControlForm.isNative`) and the bottom bar's floor show an icon alone:
/// their label carries no time, which would relabel a native item every
/// second, and carries the count, which a native item can drop as a value.
/// On the Mac that label is also the item's tooltip, so the pointer names
/// the game. Zen's control and a conversation's, which a tap only shows,
/// say the chip's label with no value, and what that tap does.
struct GameControlAccessibility: Equatable {
    var label: String
    var value: String?
    var hint: String?
    /// The label speaks a running clock.
    var updatesFrequently: Bool
    /// The custom action Open Activity, which stands for a touch and hold.
    var offersOpenActivity: Bool

    /// The custom action's name.
    static var openActivity: String {
        String(localized: "Open Activity",
               comment: "In-game control, VoiceOver: an action that opens the popover of the user's other games and Activity, as a touch and hold does")
    }

    /// What Game Detail says once when the control first shows a live game
    /// that started elsewhere: the started state's label.
    static func gameStarted(with name: String) -> String {
        Words.gameStarted(with: name)
    }

    /// What a root screen says once as a live challenge from `name` first
    /// leads its bar or its Now section: the game-over card's label.
    static func challenge(from name: String) -> String {
        Words.challenge(from: name)
    }
}

extension GameControlAccessibility {
    /// - Parameters:
    ///   - isZen: A control a tap only shows (`GameControlItemRole.isTapOnly`):
    ///     Zen's, or a conversation's.
    ///   - name: Who the state names: the chip's or a started game's
    ///     opponent, or the card's challenger.
    ///   - timeLeft: The chip's game's time on the user's clock; nil
    ///     without a countdown.
    ///   - isSuddenDeath: That clock is in its last byo-yomi period.
    ///   - locale: The spoken time's language.
    init(_ slot: GameControlSlot, form: GameControlForm, windowClass: GameControlWindowClass? = nil,
         isZen: Bool = false, allowsPicker: Bool = true, name: String = "",
         timeLeft: TimeInterval? = nil, isSuddenDeath: Bool = false, locale: Locale = Self.appLocale) {
        let iconAlone = form.showsIconAlone(in: windowClass)
        offersOpenActivity = GameControlInteraction(slot, form: form, windowClass: windowClass,
                                                    isZen: isZen).offersOpenActivity
        // The chip's label speaks its game's time, but only in a custom form.
        var speaksTime = false
        let stateLabel: String
        let waiting: String?
        let tapHint: String?
        switch slot {
        case let .chip(_, plusN, hasDot):
            if let timeLeft, !iconAlone {
                let time = Self.spokenDuration(timeLeft, locale: locale)
                stateLabel = isSuddenDeath ? Words.yourMoveInSuddenDeath(name, left: time) : Words.yourMove(name, left: time)
                speaksTime = true
            } else {
                stateLabel = Words.yourMove(name)
            }
            waiting = Words.beyondTheGame(plusN: plusN, hasDot: hasDot)
            tapHint = Words.switchesToThatGame
        case let .gameStarted(_, plusN, hasDot):
            stateLabel = Words.gameStarted(with: name)
            waiting = Words.beyondTheGame(plusN: plusN, hasDot: hasDot)
            tapHint = Words.opensThatGame
        case .gameOverCard(_, let plusN):
            stateLabel = Words.challenge(from: name)
            waiting = plusN > 0 ? Words.moreWaiting(plusN) : nil
            tapHint = Words.opensActivity
        case .base(let plusN):
            stateLabel = Words.activeGames
            waiting = plusN > 0 ? Words.waiting(plusN) : nil
            tapHint = nil
        case .dot:
            stateLabel = allowsPicker ? Words.activeGames : Words.activity
            waiting = Words.newActivityWaiting
            tapHint = nil
        case .inbox(let count):
            stateLabel = Words.activity
            waiting = count > 0 ? Words.waiting(count) : nil
            tapHint = nil
        }
        if isZen {
            // As the chip, without a value: a tap switches to the game, or
            // opens one that started, as a conversation's control can show.
            label = stateLabel
            value = nil
            hint = slot.gameID == nil ? nil : tapHint
        } else if iconAlone {
            label = waiting.map { Words.joined(stateLabel, $0) } ?? stateLabel
            value = nil
            hint = Words.opensActivity
        } else {
            label = stateLabel
            value = waiting
            hint = tapHint
        }
        updatesFrequently = speaksTime
    }

    /// A clock's time as VoiceOver says it, in full units without the zero
    /// ones, such as "42 seconds" or "1 hour, 30 minutes". It truncates as
    /// the chip's digits do, so both say one time.
    static func spokenDuration(_ timeLeft: TimeInterval, locale: Locale = Self.appLocale) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(GameControlClock(timeLeft: timeLeft).seconds)) ?? ""
    }

    /// The language the app's strings show in, so the spoken time matches
    /// the words around it.
    static var appLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }

    private enum Words {
        static func yourMove(_ name: String, left time: String) -> String {
            String(localized: "\(name), your move in your live game, \(time) left",
                   comment: "In-game control, VoiceOver: another of the user's live games is on their move. The first value is the opponent's name, the second the time left on the user's clock there, such as 42 seconds")
        }

        static func yourMoveInSuddenDeath(_ name: String, left time: String) -> String {
            String(localized: "\(name), your move in your live game, sudden death, \(time) left",
                   comment: "In-game control, VoiceOver: another of the user's live games is on their move, in its last byo-yomi period. The first value is the opponent's name, the second the time left, such as 8 seconds")
        }

        static func yourMove(_ name: String) -> String {
            String(localized: "\(name), your move in your live game",
                   comment: "In-game control, VoiceOver: another of the user's live games is on their move, said without its time. The value is the opponent's name")
        }

        static func gameStarted(with name: String) -> String {
            String(localized: "Game started with \(name)",
                   comment: "In-game control, VoiceOver: a live game with this opponent started elsewhere. The value is the opponent's name")
        }

        static func challenge(from name: String) -> String {
            String(localized: "Challenge from \(name)",
                   comment: "In-game control, VoiceOver, after a game ends: the opponent sent the user a challenge. The value is the opponent's name")
        }

        static var activeGames: String { String(localized: "Active games") }

        static var activity: String {
            String(localized: "Activity", comment: "Title of the list of the user's games, challenges, searches and messages")
        }

        /// What waits beyond the chip's or a started game's game.
        static func beyondTheGame(plusN: Int, hasDot: Bool) -> String? {
            switch (plusN > 0, hasDot) {
            case (true, true): joined(moreInActivity(plusN), newActivityWaiting)
            case (true, false): moreInActivity(plusN)
            case (false, true): newActivityWaiting
            case (false, false): nil
            }
        }

        static func moreInActivity(_ count: Int) -> String {
            String(localized: "\(count) more in Activity",
                   comment: "In-game control, VoiceOver: how many other games, challenges and messages wait in Activity besides the game the control shows")
        }

        static func moreWaiting(_ count: Int) -> String {
            String(localized: "\(count) more waiting",
                   comment: "In-game control, VoiceOver, after a game ends: how many other games, challenges and messages wait besides the opponent's challenge")
        }

        static func waiting(_ count: Int) -> String {
            String(localized: "\(count) waiting",
                   comment: "In-game control, VoiceOver: how many games, challenges and messages wait in Activity")
        }

        static var newActivityWaiting: String {
            String(localized: "New activity waiting",
                   comment: "In-game control, VoiceOver: while the user plays a live game, a challenge or a message waits, shown as a dot without a count")
        }

        static var switchesToThatGame: String {
            String(localized: "Switches to that game.",
                   comment: "In-game control, VoiceOver hint: a tap shows the other game the control names")
        }

        static var opensThatGame: String {
            String(localized: "Opens that game.",
                   comment: "In-game control, VoiceOver hint: a tap opens the live game that just started")
        }

        static var opensActivity: String {
            String(localized: "Opens Activity.",
                   comment: "In-game control, VoiceOver hint: a tap opens the popover of the user's other games and Activity")
        }

        static func joined(_ first: String, _ second: String) -> String {
            String(localized: "\(first), \(second)",
                   comment: "Two parts of an accessibility description separated by a comma, such as a speaker and message or a game speed and search status.")
        }
    }
}

// MARK: - Zen by Exit

/// Where Zen shows another live game on your move, by Exit. In compact
/// landscape Exit is a bar item and the board reaches the window's top, so
/// the top-bar chip and Exit share one platter above the board's trailing
/// column. Where that column is too narrow for the platter, the platter
/// would lie over the board's corner, and the control is the drawn circle
/// in the column under Exit instead, the board keeping its size. It follows
/// the column the Zen layout leaves beside the board, never the bar, so the
/// bar's first Zen pass has it and it keeps for the pose: one control at a
/// time. Where Exit is drawn in the game's content (an iPad, a regular-width
/// phone, Duo Open), the circle beside Exit moves to the same column where it
/// would reach over the clocks or the board, as in an iPad's compact window
/// or a narrow one at regular width, or stays beside Exit without its
/// countdown.
enum GameControlZenCorner: Equatable {
    /// The top-bar chip before Exit, where their platter clears the board.
    case barChip
    /// The circle in the board's trailing column under Exit, its countdown
    /// hanging below where the column holds the 76 pt button, alone where
    /// it holds only the 44 pt circle.
    case circle(showsCountdown: Bool)
    /// Where Exit is drawn in the game's content: the 44 pt circle alone
    /// beside Exit, where it sits when its countdown shows, 18 pt before
    /// Exit at Exit's top.
    case besideExitAlone
    /// A column narrower than the circle, or none that clears the layout:
    /// no control in Zen.
    case noRoom

    /// The room the platter needs beside the board, from the window's
    /// trailing edge: the chip and Exit with their spacing reach about
    /// 180 pt in on the iPhone SE and the Duo, and 199 pt beside a Dynamic
    /// Island, whose bar keeps a wider margin; 8 pt more keep them off the
    /// board.
    static let barChipRoom: CGFloat = 208
    /// The circle's button with its countdown below.
    static let circleWithCountdownWidth: CGFloat = 76
    /// The circle alone.
    static let circleAloneWidth: CGFloat = 44

    /// - Parameters:
    ///   - column: From the board's trailing edge to the content's.
    ///   - trailingInset: The window beyond the content's trailing edge,
    ///     where the bar still puts its items, as beside a Dynamic Island.
    init(column: CGFloat, trailingInset: CGFloat) {
        if column + trailingInset >= Self.barChipRoom {
            self = .barChip
        } else if column >= Self.circleWithCountdownWidth {
            self = .circle(showsCountdown: true)
        } else if column >= Self.circleAloneWidth {
            self = .circle(showsCountdown: false)
        } else {
            self = .noRoom
        }
    }

    /// The width the circle takes in the column.
    static func width(showsCountdown: Bool) -> CGFloat {
        showsCountdown ? circleWithCountdownWidth : circleAloneWidth
    }

    /// Where Exit is drawn in the game's content: nil where the circle beside
    /// Exit, with its countdown, clears the Zen layout's clocks, board and
    /// actions, so it stays there. Elsewhere, as where the clocks reach into
    /// Exit's band, the first of: the circle with its countdown under Exit in
    /// the board's trailing column, where that clears them too; the circle
    /// alone beside Exit, where it keeps 8 pt clear of them; the circle alone
    /// in the column; no control.
    /// - Parameters:
    ///   - exit: Exit's frame, in the layout's coordinates.
    ///   - countdownBelow: Whether the countdown hangs below the circle
    ///     beside Exit, rather than on its leading side.
    ///   - width: The layout's width.
    ///   - column: From the board's trailing edge to the layout's.
    ///   - occupied: The layout's clocks, board and actions.
    init?(contentExit exit: CGRect, countdownBelow: Bool, width: CGFloat, column: CGFloat, occupied: [CGRect]) {
        let occupied = occupied.filter { !$0.isEmpty }
        func clears(_ frame: CGRect) -> Bool { !occupied.contains { $0.intersects(frame) } }
        if clears(Self.besideExitFrame(exit, countdownBelow: countdownBelow)) { return nil }
        func columnClears(showsCountdown: Bool) -> Bool {
            column >= Self.width(showsCountdown: showsCountdown)
                && clears(Self.columnFrame(showsCountdown: showsCountdown, width: width, column: column,
                                           top: exit.maxY + Self.gapUnderExit))
        }
        let clearance = -Self.besideExitAloneClearance
        if columnClears(showsCountdown: true) {
            self = .circle(showsCountdown: true)
        } else if clears(Self.besideExitAloneFrame(exit).insetBy(dx: clearance, dy: clearance)) {
            self = .besideExitAlone
        } else if columnClears(showsCountdown: false) {
            self = .circle(showsCountdown: false)
        } else {
            self = .noRoom
        }
    }

    /// The circle's button with its countdown below: the 44 pt circle, 4 pt,
    /// and the 22 pt capsule.
    static let circleWithCountdownHeight: CGFloat = 70
    /// From Exit, or the bar under it, to the circle in the column.
    static let gapUnderExit: CGFloat = 8
    /// What the circle alone beside Exit keeps clear of the clocks, the
    /// board and the actions, all round.
    static let besideExitAloneClearance: CGFloat = 8

    /// Where the circle's button sits beside an Exit drawn at `exit`: with
    /// its countdown below, 2 pt before Exit; with the countdown on its
    /// leading side, the circle 18 pt before Exit and a capsule of up to
    /// 76 pt 4 pt before that.
    static func besideExitFrame(_ exit: CGRect, countdownBelow: Bool) -> CGRect {
        countdownBelow
            ? CGRect(x: exit.minX - 2 - circleWithCountdownWidth, y: exit.minY,
                     width: circleWithCountdownWidth, height: circleWithCountdownHeight)
            : CGRect(x: exit.minX - 18 - circleAloneWidth - 4 - circleWithCountdownWidth, y: exit.minY,
                     width: circleWithCountdownWidth + 4 + circleAloneWidth, height: circleAloneWidth)
    }

    /// Where the circle alone sits beside an Exit drawn at `exit`: where it
    /// sits with its countdown, 18 pt before Exit, at Exit's top.
    static func besideExitAloneFrame(_ exit: CGRect) -> CGRect {
        CGRect(x: exit.minX - 18 - circleAloneWidth, y: exit.minY, width: circleAloneWidth, height: circleAloneWidth)
    }

    /// The circle `top` down the board's trailing column, centred in it.
    static func columnFrame(showsCountdown: Bool, width: CGFloat, column: CGFloat, top: CGFloat) -> CGRect {
        let side = Self.width(showsCountdown: showsCountdown)
        return CGRect(x: width - (column + side) / 2, y: top, width: side,
                      height: showsCountdown ? circleWithCountdownHeight : circleAloneWidth)
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

// MARK: - The popover

/// The control's popover in one Game Detail: the placement its item had
/// when it opened, and the window's Activity request it made, which App
/// Review, the window's resets and the list's own actions follow. Each item
/// presents only at its own placement, so the item a rotation, a pose
/// change or a resize leaves can't keep the popover open, and the item that
/// takes its place starts closed and opens again on the next hold, tap or
/// VoiceOver action.
struct GameControlPopover: Equatable {
    private(set) var placement: GameActiveGamesPlacement?
    /// The window's request this popover made.
    private(set) var sessionID: UUID?
    /// The list's session: the request's, kept after it closes, so the list
    /// keeps its own while the popover goes.
    private(set) var listSessionID = UUID()

    var isOpen: Bool { placement != nil }

    func isPresented(at placement: GameActiveGamesPlacement) -> Bool {
        self.placement == placement
    }

    /// Opens the popover from the item at `placement`, with a new request
    /// in the window. The window has one list, so this request replaces any
    /// other, and another Game Detail's popover closes.
    mutating func open(at placement: GameActiveGamesPlacement, place: ActivityModel.Place,
                       navigation: NavigationService) {
        let request = ActivityRequest(source: .gameControl, style: .popover, place: place)
        navigation.main.activity = request
        self.placement = placement
        sessionID = request.sessionID
        listSessionID = request.sessionID
    }

    /// Closes the popover, and clears the window's request while it is
    /// still this popover's. Game Detail calls it when the slot moves to
    /// another bar, as SwiftUI may never report the old item's popover
    /// closed, on a switch, on entering Zen and when it disappears.
    mutating func close(navigation: NavigationService) {
        if let sessionID, navigation.main.activity?.sessionID == sessionID {
            navigation.main.activity = nil
        }
        placement = nil
        sessionID = nil
    }

    /// The item at `placement` reports its popover closed, after a tap
    /// outside it or Escape. A late report from an item the control has
    /// already left closes nothing.
    mutating func itemClosed(at placement: GameActiveGamesPlacement, navigation: NavigationService) {
        guard self.placement == placement else { return }
        close(navigation: navigation)
    }

    /// The window's request is now `sessionID`: something cleared this
    /// popover's, such as a reset of the window's navigation, an account
    /// change or one of the list's own actions, or another surface replaced
    /// it. The popover closes and leaves the window's request alone.
    mutating func windowRequestChanged(to sessionID: UUID?) {
        guard let current = self.sessionID, sessionID != current else { return }
        placement = nil
        self.sessionID = nil
    }
}

// MARK: - On screen

/// What the control does only while its Game Detail is on screen, as the
/// Game Detail's visible registration says. A stack can keep a Game Detail
/// under another screen, and each tab keeps its own: their controls
/// announce nothing, and keep no timer (`GameControlDeadlines`). The Game
/// Detail the user sees is the one that announces a game that started, and
/// one that comes back on screen announces a start the window has not
/// announced yet.
enum GameControlOnScreen {
    /// The game whose start to announce, as "Game started with CedarWave":
    /// the started game the control shows, while on screen. The window
    /// announces each game once (`StartedGamesRecorder`).
    static func startedGameToAnnounce(_ value: GameControlSlot?, isOnScreen: Bool) -> Int? {
        guard isOnScreen, case let .gameStarted(gameID, _, _)? = value else { return nil }
        return gameID
    }
}

#if DEBUG
extension GameControlSlot {
    /// The state as UI tests read it: "chip game-N +K", "started game-N +K"
    /// (each with " dot" while a dot shows), "card challenge-N +K",
    /// "base +K", "dot", "inbox K", and "none" without a slot.
    static func testDescription(_ slot: GameControlSlot?) -> String {
        switch slot {
        case .none: "none"
        case let .chip(gameID, plusN, hasDot)?: "chip game-\(gameID) +\(plusN)" + (hasDot ? " dot" : "")
        case let .gameStarted(gameID, plusN, hasDot)?: "started game-\(gameID) +\(plusN)" + (hasDot ? " dot" : "")
        case let .gameOverCard(challengeID, plusN)?: "card challenge-\(challengeID) +\(plusN)"
        case .base(let plusN)?: "base +\(plusN)"
        case .dot?: "dot"
        case .inbox(let count)?: "inbox \(count)"
        }
    }
}
#endif

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
/// bar's form, the platform, whether the user plays and the action row's
/// main action. It reads nothing a layout reports, such as a rendered badge,
/// the layout plan or a preference, so a game opened or switched to during
/// an outage shows its status in its place from the first frame, and every
/// later pass agrees.
///
/// - A clock in play: the to-move clock's mark, in every panel and form.
/// - No clock in play, with a title slot: in Play the capsule in the title
///   slot; in Chat or Analyze the mark on one clock, never the capsule.
/// - No clock in play and no title slot: the main action reads
///   "Reconnecting…".
/// - The Mac never shows the capsule. Its game toolbar draws no title, so
///   a window subtitle would not show either: where iOS shows the capsule,
///   the Mac's main action reads "Reconnecting…" instead.
/// - No clock in play, and neither the capsule nor a relabelled action
///   shows: the mark on one clock. That is where Analyze or a chat preview
///   takes the action row's place, and where its main action needs no
///   connection: in stone removal once the user has accepted, after a Rengo
///   game, in a game the user watches.
///
/// A clock in play takes its mark at once from the socket, as the actions
/// disable; the capsule, the one clock's mark and the relabel follow the
/// window's connection source.
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
        /// The action row's main action is one that needs the connection
        /// (`mainActionNeedsConnection(game:blocksActions:)`), so a relabel
        /// on it can say the outage.
        var mainActionNeedsConnection: Bool
        /// A chat message's position is on the board, which takes the action
        /// row's place, as Analyze does.
        var showsChatPreview = false
    }

    /// Where the clocks carry the mark.
    enum Clocks: Equatable {
        case unchanged
        /// The to-move clock's mark, on every variant that shows it.
        case toMoveClock
        /// No clock is in play, and neither the capsule nor a relabelled
        /// action says so: the mark on one clock, wherever the layout puts
        /// it. It is the clock a single header chip shows: the user's own,
        /// else the winner's, else Black's
        /// (`GameDetailClockState.singleChipColor`).
        case oneClock
    }

    /// What the actions that need the connection show: Pass, Submit move,
    /// Accept removed stones and Rematch, which disable at once from the
    /// socket in every layout. While the status shows they say
    /// "Reconnecting…", or "Connecting…" before the window's first
    /// connection (`ConnectionStatusModel.Status.gameActionWords`).
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
    var action: Action

    init(_ input: Input) {
        let hasTitleSlot = !input.isVerticalToolbar && !input.isZen
        let panel: GameDetailPanel = input.panel == .playerInfo && input.restoresChatPanel ? .chat : input.panel
        let capsuleState = !input.hasClockInPlay && hasTitleSlot && panel == .playerInfo
        showsTitleCapsule = !input.isCatalyst && capsuleState
        if !input.userPlays {
            action = .none
        } else if (!input.hasClockInPlay && !hasTitleSlot) || (input.isCatalyst && capsuleState) {
            action = .relabelled
        } else {
            action = .disabled
        }
        // Zen draws its action row whatever the panel; elsewhere Analyze and
        // a chat preview take its place.
        let drawsActionRow = input.isZen || (panel != .analyze && !input.showsChatPreview)
        let relabelShows = action == .relabelled && input.mainActionNeedsConnection && drawsActionRow
        if input.hasClockInPlay {
            clocks = .toMoveClock
        } else if showsTitleCapsule || relabelShows {
            clocks = .unchanged
        } else {
            clocks = .oneClock
        }
    }
}

extension ConnectionStatusModel.Status {
    /// A game says an outage while it shows, as Reconnecting… or Can’t
    /// reach OGS, and never "Connected": once the outage ends, its title
    /// slot, clocks, action and window subtitle are as they were.
    var showsInGame: Bool {
        switch self {
        case .reconnecting, .unreachable: true
        case .hidden, .connected: false
        }
    }

    /// What a game's title-slot capsule says while the outage shows, in the
    /// words every carrier of the window's status says
    /// (`RootConnectionLine.words(status:hasConnected:socket:)`): "Can’t
    /// reach OGS" once the window gives up waiting, else "Reconnecting…", or
    /// "Connecting…" before the window's first connection, while its socket
    /// is on its first attempt. Never "Connected"; nil while nothing shows.
    func gameCapsuleWords(hasConnected: Bool, socket: OGSWebsocketStatus) -> RootConnectionLine.Words? {
        guard showsInGame else { return nil }
        return RootConnectionLine.words(status: self, hasConnected: hasConnected, socket: socket)
    }

    /// What a game's actions that need the connection say while the outage
    /// shows (`GameConnectionPlacement.Action`), as the clocks and the
    /// capsule say it: "Connecting…" while the window has never connected
    /// and its socket is on its first attempt, else "Reconnecting…". Never
    /// "Can’t reach OGS": a relabelled action keeps one word. Nil while
    /// nothing shows.
    func gameActionWords(hasConnected: Bool, socket: OGSWebsocketStatus) -> RootConnectionLine.Words? {
        guard showsInGame else { return nil }
        return GameDetailClockState.recoversConnection(hasConnected: hasConnected, socket: socket)
            ? .reconnecting : .connecting
    }
}

extension GameConnectionPlacement.Action {
    /// The VoiceOver value of each action that needs the connection while
    /// `words` show: nil where the user doesn't play, so none shows.
    func value(_ words: RootConnectionLine.Words?) -> RootConnectionLine.Words? {
        self == .none ? nil : words
    }

    /// What the main action reads in place of its name while `words` show:
    /// only where the game relabels it.
    func relabel(_ words: RootConnectionLine.Words?) -> RootConnectionLine.Words? {
        self == .relabelled ? words : nil
    }
}

extension GameConnectionPlacement.Input {
    /// Reads the clock, whether the user plays and the main action from
    /// `game`; the rest is Game Detail's own state.
    /// - Parameter blocksActions: An action is sending, or a scoring change
    ///   waits for its refresh (`GameControlState.blocksGameActions`).
    init(game: Game, blocksActions: Bool, panel: GameDetailPanel, restoresChatPanel: Bool,
         showsChatPreview: Bool = false, isVerticalToolbar: Bool, isZen: Bool, isCatalyst: Bool) {
        let hasClockInPlay = [StoneColor.black, .white].contains {
            GameDetailClockState(game: game, color: $0).isToMove
        }
        self.init(hasClockInPlay: hasClockInPlay, panel: panel, restoresChatPanel: restoresChatPanel,
                  isVerticalToolbar: isVerticalToolbar, isZen: isZen, isCatalyst: isCatalyst,
                  userPlays: game.isUserPlaying,
                  mainActionNeedsConnection: Self.mainActionNeedsConnection(game: game, blocksActions: blocksActions),
                  showsChatPreview: showsChatPreview)
    }

    /// Whether the action row's main action needs the connection where no
    /// clock is in play: Rematch after a game the user played, or Accept
    /// removed stones while the user's acceptance is due, as the row shows
    /// them (`GameControlRow.mainActionButton`). The row shows neither while
    /// an action is sending or a scoring change waits for its refresh
    /// (`blocksActions`), nor over an estimate.
    static func mainActionNeedsConnection(game: Game, blocksActions: Bool) -> Bool {
        guard !blocksActions, game.currentPosition.estimatedScores == nil,
              let userColor = game.userStoneColor else { return false }
        if OGSChallengeTemplate.rematch(for: game) != nil { return true }
        return game.isUserPlaying && game.gamePhase == .stoneRemoval
            && game.removedStonesAccepted[userColor] != game.currentPosition.removedStones
    }
}
