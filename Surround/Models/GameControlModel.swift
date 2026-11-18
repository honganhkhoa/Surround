//
//  GameControlModel.swift
//  Surround
//
//  The in-game control's rules that need no view: the value Game Detail's
//  Active games slot shows, the window's width class and shape that the
//  control's frames follow, what each form draws and how its text fits a
//  fixed frame, what a tap or a hold does, what VoiceOver says, how a Game
//  Detail switches to another game, which challenge the game-over card
//  shows, and where a game says that the connection is down. Each reads
//  only state Game Detail has before it draws, so SurroundTests checks it
//  without a socket or a view.
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
}

// MARK: - The window

/// The window a Game Detail is in, as the window's root measures it: which
/// class its width falls in, and its shape. The control's frames are fixed
/// per class, so they change only when the window resizes or turns, which
/// nothing inside the window can cause. The root knows both long before a
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
        /// 390 pt and wider, where the full chip fits beside three modes.
        case standard

        /// The narrowest window in the class, in points.
        var minimumWidth: CGFloat {
            switch self {
            case .floor: 0
            case .narrow: 375
            case .standard: 390
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

    init(widthClass: WidthClass, shape: Shape) {
        self.widthClass = widthClass
        self.shape = shape
    }

    /// From the window's bounds.
    init(windowSize: CGSize) {
        self.init(widthClass: WidthClass(width: windowSize.width),
                  shape: windowSize.width > windowSize.height ? .landscape : .portrait)
    }
}

// MARK: - The control's forms

/// Where the control sits, which decides how it draws. The bars draw a
/// custom view. The Duo's rail and the Mac use the system's icon and badge:
/// a native item draws only an image, and the Mac's toolbar never draws a
/// custom view.
enum GameControlForm: Equatable {
    /// The iPhone's bottom bar, and a narrow iPad window's.
    case bottomBar
    /// A top bar on iOS, in compact landscape or in a wide window.
    case topBar
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

    /// The system's own item, which takes no hold and badges a count.
    var isNative: Bool { self == .rail || self == .mac }

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
/// fits: a frame fixed by the form, the state and the window's width class,
/// never by the clock, so the bar's layout never changes as the clock ticks;
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
    /// The bottom bar's chip, started game and card: from 390 pt, and from
    /// 375 pt beside fewer than three modes.
    static let chipWidth: CGFloat = 160
    /// The same, from 375 pt to 390 pt beside three modes.
    static let narrowChipWidth: CGFloat = 120
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
    ///   - allowsPicker: The route has the picker
    ///     (`GameControlSwitch.allowsPicker`).
    ///   - hasCountdown: The chip's game counts down. Without a countdown
    ///     the hourglass shows alone.
    ///   - isSuddenDeath: The chip's game is in its last byo-yomi period.
    init?(_ slot: GameControlSlot, form: GameControlForm, windowClass: GameControlWindowClass?,
          modeCount: Int, allowsPicker: Bool, hasCountdown: Bool = true, isSuddenDeath: Bool = false) {
        guard !form.isNative else { return nil }
        frame = Self.frame(slot, form: form, windowClass: windowClass, modeCount: modeCount)
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

    /// The fixed frame, from the form, the state and the window's class
    /// alone, so neither the clock nor sudden death moves the bar's layout.
    static func frame(_ slot: GameControlSlot, form: GameControlForm,
                      windowClass: GameControlWindowClass?, modeCount: Int) -> CGSize {
        let widthClass = windowClass?.widthClass ?? .standard
        let width: CGFloat
        if form.showsIconAlone(in: windowClass) {
            width = iconWidth
        } else {
            switch slot {
            case .chip, .gameStarted, .gameOverCard:
                if form != .bottomBar {
                    width = topBarChipWidth
                } else {
                    width = widthClass == .narrow && modeCount >= 3 ? narrowChipWidth : chipWidth
                }
            case .base, .dot, .inbox:
                width = slot.plusN > 0 ? iconWithCountWidth : iconWidth
            }
        }
        return CGSize(width: width, height: height)
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

/// The control on the Duo's rail and the Mac: the system's icon with its
/// red badge. A native item draws only its image and badge, so the chip's
/// game, a started game and the card show inside the popover instead.
struct GameControlNativeItem: Equatable {
    enum Badge: Equatable {
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
    ///   glyph, as the Duo's wide poses do so the pill beside it stays put.
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
/// - The native items on the rail and the Mac can't show the chip, so a tap
///   or a click opens the popover, which leads with the chip's game. They
///   take no hold: the system makes a long press's release a tap.
/// - The bottom bar's floor shows the icon alone, so a tap opens the
///   popover there too, as a hold does.
/// - Zen's circle and items: a tap switches; nothing else, since Zen has
///   no popover.
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

    /// A press in a custom form that ends `duration` after it began,
    /// whatever took the touch on the way. A release 0.5 s or more after the
    /// press began never switches: it opens the popover as a hold would,
    /// unless a hold already fired, and then it does nothing more. So when
    /// something else takes the hold, as the Large Content Viewer does at
    /// accessibility sizes, the worst case is the popover, not a switch.
    func release(after duration: TimeInterval, holdFired: Bool) -> GameControlAction {
        if holdFired { return .none }
        return duration >= Self.holdDuration ? hold : tap
    }
}

// MARK: - VoiceOver

/// What VoiceOver says for the control. The custom forms speak the other
/// game's time in the label, with what waits as the value. The native items
/// on the rail and the Mac, and the bottom bar's floor, show an icon alone:
/// their label carries no time, which would relabel a native item every
/// second, and carries the count, which a native item can drop as a value.
/// On the Mac that label is also the item's tooltip, so the pointer names
/// the game.
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
}

extension GameControlAccessibility {
    /// - Parameters:
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
            // As the chip, without a value: a tap switches.
            label = stateLabel
            value = nil
            hint = Words.switchesToThatGame
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
