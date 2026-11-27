//
//  ActivityBarMetrics.swift
//  Surround
//
//  The Activity bar's fonts, and its parts' widths at a text size, measured
//  with UIKit as the in-game control's chip measures its own
//  (`GameControlChipMetrics`). The fonts are fixed at the size they scale to,
//  and the bar draws its text, symbols and fixed parts at these sizes, so
//  what fits here fits on screen. Text stops growing at XXL in every host.
//  The Now section's rows draw the same parts at the third row density.
//  The drawing and its drop order are the model's (`ActivityBarDrawing`);
//  SurroundTests' fit test proves that every kind's parts that never drop
//  fit each host's narrowest bar in every language, with the words that
//  must read whole kept whole. The bar's and the Now section's own colours
//  are here too, so the same test checks their contrast.
//

import UIKit

/// The text a bar's measured parts draw.
struct ActivityBarPartText {
    /// Line one at its narrowest: a letter and the ellipsis, or the ellipsis
    /// alone where line one may truncate to nothing, as "Can’t reach OGS"
    /// may where the title says it; or all of it, where it must read whole,
    /// as the status words do where nothing else on screen says them.
    var lineOneMinimum = ActivityBarPartText.letterAndEllipsis
    /// Beside the name in the two-line form and in compact height; it never
    /// truncates.
    var rank: String?
    /// Line two's grey status badge, where it shows on a lead in a host that
    /// says all status: it reads whole, so the lines' column is at least as
    /// wide as the badge.
    var statusBadge: String?
    var actionLabel: (ActivityBarAction) -> String = ActivityBarWords.action
    /// The clock's time; nil for a game without a countdown, whose chip
    /// shows its hourglass alone.
    var clock: GameControlClock?
    /// In sudden death, the mark the chip draws in the hourglass's place.
    var suddenDeathMark: GameControlSuddenDeathMark?
    var plusN = 0
    /// The language's direction. The parts mirror, and keep their widths.
    var direction = NSWritingDirection.leftToRight

    static let letterAndEllipsis = "W…"
    static let ellipsis = "…"
}

struct ActivityBarMetrics {
    /// The largest text size the bar draws, in every host.
    static let cap = UIContentSizeCategory.extraExtraLarge
    /// Every hit area is at least this big.
    static let targetSize: CGFloat = 44

    let form: ActivityBarForm
    /// The text size the bar draws at: the one asked for, up to the cap.
    let sizeCategory: UIContentSizeCategory
    /// Line one: 15 pt semibold, scaled as subheadline.
    let lineOneFont: UIFont
    /// The rank beside the name, and line two: 13 pt, scaled as footnote.
    let detailFont: UIFont
    /// The clock's digits and the sudden-death mark's text: 15 pt semibold
    /// with monospaced digits.
    let clockFont: UIFont
    /// View, Open game, Retry and Withdraw: 15 pt semibold.
    let actionFont: UIFont
    /// +N: 15 pt semibold with monospaced digits, 14 pt in one-line forms.
    let countFont: UIFont
    /// Line two's grey "Reconnecting…" badge: 12 pt semibold, scaled as
    /// caption.
    let badgeFont: UIFont

    var spacing: ActivityBarSpacing {
        form.isOneLine
            ? ActivityBarSpacing(leading: 8, trailing: 8, between: 6)
            : ActivityBarSpacing(leading: 8, trailing: 6, between: 8)
    }

    /// The opponent's, the challenger's, or a glyph's tile.
    var tileSize: CGFloat {
        switch form {
        case .expanded: 36
        case .compactHeight: 32
        case .inline, .closed: 30
        }
    }

    var clockHeight: CGFloat { form == .expanded ? 32 : 30 }
    /// The pills' and +N's drawn height, inside a 44 pt target.
    var capsuleHeight: CGFloat { form.isOneLine ? 30 : 36 }
    var clockPadding: CGFloat { form.isOneLine ? 8 : 9 }
    /// Between the hourglass or the mark and the digits, which read as one.
    var clockInnerGap: CGFloat { 4 }
    var pillPadding: CGFloat { form.isOneLine ? 10 : 12 }
    var withdrawPadding: CGFloat { 10 }
    var countPadding: CGFloat { form.isOneLine ? 8 : 10 }
    var countMinimumWidth: CGFloat { form.isOneLine ? 36 : 44 }
    var badgeHeight: CGFloat { ceil(badgeFont.lineHeight) + 4 }
    /// Between the name and its rank.
    static let rankGap: CGFloat = 4
    /// Between line one and line two.
    static let lineGap: CGFloat = 1

    init(form: ActivityBarForm, sizeCategory: UIContentSizeCategory) {
        self.form = form
        let requested = sizeCategory == .unspecified ? .large : sizeCategory
        let capped = min(requested, Self.cap)
        self.sizeCategory = capped
        let traits = UITraitCollection(preferredContentSizeCategory: capped)
        func scaled(_ size: CGFloat, as style: UIFont.TextStyle) -> CGFloat {
            UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size), compatibleWith: traits).pointSize
        }
        lineOneFont = .systemFont(ofSize: scaled(15, as: .subheadline), weight: .semibold)
        detailFont = .systemFont(ofSize: scaled(13, as: .footnote))
        clockFont = .monospacedDigitSystemFont(ofSize: scaled(15, as: .subheadline), weight: .semibold)
        actionFont = .systemFont(ofSize: scaled(15, as: .subheadline), weight: .semibold)
        countFont = .monospacedDigitSystemFont(ofSize: scaled(form.isOneLine ? 14 : 15, as: .subheadline),
                                               weight: .semibold)
        badgeFont = .systemFont(ofSize: scaled(12, as: .caption1), weight: .semibold)
    }

    /// The iPad's floating bar from iPadOS 26: its host fixes UIKit's
    /// accessory at 48 pt (`ActivityAccessoryHost.idealSize`).
    static let iPadAccessoryHeight: CGFloat = 48

    /// The bar's height in its host: the system's in a phone's accessory,
    /// about 44 pt, and the iPad host's 48 pt; the custom bar's 56 pt, and
    /// 48 pt in compact height.
    static func height(of bar: ActivityHostPolicy.Bar, form: ActivityBarForm,
                       container: ActivityHostPolicy.Container = .swiftUITabView) -> CGFloat {
        switch bar {
        case .customBar: form == .compactHeight ? 48 : 56
        case .uiKitAccessory where container == .iPadTabContainer: iPadAccessoryHeight
        case .swiftUIAccessory, .uiKitAccessory: 44
        }
    }

    /// Line one's height, and line two's or its status badge's, whichever
    /// is taller, with the gap between them: what two lines take.
    var twoLinesHeight: CGFloat {
        ceil(lineOneFont.lineHeight) + Self.lineGap + max(ceil(detailFont.lineHeight), badgeHeight)
    }

    /// The two-line form keeps line two where both lines fit the host's
    /// height at this text size: everywhere at the default size, but not in
    /// a phone's 44 pt accessories at the cap, where line two drops before
    /// any action does. Fonts decide it, never the bar's frame.
    func showsLineTwo(in bar: ActivityHostPolicy.Bar,
                      container: ActivityHostPolicy.Container = .swiftUITabView) -> Bool {
        form == .expanded && twoLinesHeight <= Self.height(of: bar, form: form, container: container)
    }

    // MARK: Widths

    /// A part's width in points, its padding included. The hourglass's
    /// width takes the clock's inner gap in place of the spacing before the
    /// clock, so the two read as one chip; line two shares line one's column,
    /// which is as wide as its status badge where one shows.
    /// - Parameter lineOneLines: The lines line one may take.
    func width(of part: ActivityBarPart, _ text: ActivityBarPartText, lineOneLines: Int = 1) -> CGFloat {
        switch part {
        case .tile: tileSize
        case .lineOne: max(lineOneWidth(text, lines: lineOneLines), badgeWidth(text))
        case .lineTwo: 0
        case .hourglass: symbolWidth("hourglass") + clockInnerGap - spacing.between
        case .clock: clockWidth(text)
        case .action(let action): actionWidth(action, label: text.actionLabel(action), direction: text.direction)
        case .plusN: max(Self.targetSize, countWidth(text.plusN, direction: text.direction))
        }
    }

    /// Line one at its narrowest, on `lines` lines, with the rank beside the
    /// name where the form draws it.
    func lineOneWidth(_ text: ActivityBarPartText, lines: Int = 1) -> CGFloat {
        var width = Self.columnWidth(text.lineOneMinimum, font: lineOneFont, lines: lines, direction: text.direction)
        if let rank = text.rank, !rank.isEmpty, !form.isOneLine {
            width += Self.rankGap + ceil(Self.textWidth(rank, font: detailFont, direction: text.direction))
        }
        return width
    }

    /// The status badge's capsule: its words and 8 pt on each side.
    func badgeWidth(_ text: ActivityBarPartText) -> CGFloat {
        text.statusBadge.map { ceil(Self.textWidth($0, font: badgeFont, direction: text.direction)) + 2 * 8 } ?? 0
    }

    /// The narrowest column that holds `text` on `lines` lines, broken
    /// between words as the bar's lines break it: its one-line width for a
    /// single line, and a point more than the measured column for more, which
    /// SwiftUI's lines then break within.
    static func columnWidth(_ text: String, font: UIFont, lines: Int,
                            direction: NSWritingDirection = .leftToRight) -> CGFloat {
        let oneLine = ceil(textWidth(text, font: font, direction: direction))
        guard lines > 1, !text.isEmpty else { return oneLine }
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = direction
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        let limit = lineHeight(text, font: font) * CGFloat(lines) + 0.5
        var narrow: CGFloat = 1
        var wide = oneLine
        while wide - narrow > 0.5 {
            let middle = (narrow + wide) / 2
            let height = (text as NSString).boundingRect(
                with: CGSize(width: middle, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height
            if ceil(height) <= limit { wide = middle } else { narrow = middle }
        }
        return min(oneLine, ceil(wide) + 1)
    }

    /// The clock's chip without a separate hourglass: its digits, or the
    /// hourglass alone without a countdown, with the sudden-death mark
    /// before the digits in sudden death.
    func clockWidth(_ text: ActivityBarPartText) -> CGFloat {
        guard let clock = text.clock else { return 2 * clockPadding + symbolWidth("hourglass") }
        var width = 2 * clockPadding + ceil(Self.textWidth(clock.widestSample, font: clockFont, direction: text.direction))
        if let mark = text.suddenDeathMark {
            width += markWidth(mark, direction: text.direction) + clockInnerGap
        }
        return width
    }

    func markWidth(_ mark: GameControlSuddenDeathMark, direction: NSWritingDirection = .leftToRight) -> CGFloat {
        switch mark {
        case .text(let text): ceil(Self.textWidth(text, font: clockFont, direction: direction))
        case .glyph: symbolWidth(GameControlSuddenDeathMark.glyphSystemName)
        }
    }

    /// View, Open game and Retry are pills; Withdraw is accent text. Each is
    /// at least 44 pt wide.
    func actionWidth(_ action: ActivityBarAction, label: String,
                     direction: NSWritingDirection = .leftToRight) -> CGFloat {
        let padding = action == .withdraw ? withdrawPadding : pillPadding
        return max(Self.targetSize, ceil(Self.textWidth(label, font: actionFont, direction: direction)) + 2 * padding)
    }

    /// +N's drawn capsule.
    func countWidth(_ plusN: Int, direction: NSWritingDirection = .leftToRight) -> CGFloat {
        max(countMinimumWidth,
            ceil(Self.textWidth(Self.countText(plusN), font: countFont, direction: direction)) + 2 * countPadding)
    }

    static func countText(_ plusN: Int) -> String { "+\(plusN)" }

    /// A symbol's width at the clock's text size, as the bar draws it.
    func symbolWidth(_ systemName: String) -> CGFloat {
        let configuration = UIImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
        let image = UIImage(systemName: systemName, withConfiguration: configuration)
        return ceil(image?.size.width ?? symbolPointSize)
    }

    /// The hourglass and the glyph beside the clock: three quarters of its
    /// text, as the design draws an 11 pt hourglass beside 15 pt digits.
    var symbolPointSize: CGFloat { (clockFont.pointSize * 0.75).rounded() }

    static func textWidth(_ text: String, font: UIFont,
                          direction: NSWritingDirection = .leftToRight) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = direction
        return (text as NSString).size(withAttributes: [.font: font, .paragraphStyle: paragraph]).width
    }

    /// One line's height as drawn, fallback fonts included.
    static func lineHeight(_ text: String, font: UIFont) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
        return ceil(max(bounds.height, font.lineHeight))
    }

    // MARK: Fitting

    /// The parts `drawing` keeps in `width`, after its drop order. Line two
    /// shares line one's column, and the chip draws its own mark in sudden
    /// death, or its hourglass alone without a countdown, which then never
    /// drops. Line one takes the lines the drawing gives it.
    func fit(_ drawing: ActivityBarDrawing, in width: CGFloat, text: ActivityBarPartText) -> ActivityBarFit {
        var horizontal = drawing
        let chipDrawsItsSymbol = text.clock == nil || text.suddenDeathMark != nil
        let left: (ActivityBarPart) -> Bool = { $0 == .lineTwo || ($0 == .hourglass && chipDrawsItsSymbol) }
        horizontal.parts.removeAll(where: left)
        horizontal.dropOrder.removeAll(where: left)
        return horizontal.fit(in: width, spacing: spacing) {
            self.width(of: $0, text, lineOneLines: drawing.lineOneLines)
        }
    }
}

// MARK: - The bar's own colours

/// The bar's and the Now section's own colours, apart from Messages'
/// indigo, which Activity's list shares. Their words read at 4.5:1 or
/// better on what draws under them in every host: the custom bar's material
/// and its tinted pills, the system's glass, and the sidebar.
enum ActivityBarColors {
    /// View, Open game, Retry and Withdraw, and All activity: the app's
    /// indigo, deeper in light and lighter in dark, where the custom bar's
    /// dark material and its pills would leave the system's indigo near
    /// 2:1.
    static let accent = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.69, green: 0.686, blue: 1, alpha: 1)
            : UIColor(red: 0.282, green: 0.275, blue: 0.784, alpha: 1)
    }

    /// The status badge behind its white words: a darker grey than the
    /// system's, which leaves white text near 3.3:1.
    static let statusBadge = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.388, green: 0.388, blue: 0.4, alpha: 1)
            : UIColor(red: 0.424, green: 0.424, blue: 0.439, alpha: 1)
    }
}

extension ActivityBarDrawing {
    /// Parts and a drop order of the caller's own, as the Now rows draw them.
    init(parts: [ActivityBarPart], dropOrder: [ActivityBarPart]) {
        self.parts = parts
        self.dropOrder = dropOrder
    }
}

// MARK: - The Now section's rows

/// A Now row at the third row density (`ActivityRowDensity.now`): a 32 pt
/// tile in a 60 pt row, the name in 15 pt semibold with the rank and line
/// two in 13 pt, then one trailing part: a live game's 28 pt clock, View,
/// Withdraw, Open game, or the status row's Retry. Its text stops growing
/// at XXL, as the bar's does, so the section keeps its height.
///
/// Line one keeps at least its first ten characters, or all of it
/// (`floor(of:)`). Where it wouldn't, the row's other parts give way in
/// this order: the hourglass, the tile, then the rank, which VoiceOver
/// still reads, and last the action's words, drawn as its symbol in their
/// pill (`actionDrawsSymbol`), beside which the hourglass, the tile and the
/// rank come back where they fit. The clock and the action never drop. The
/// clock chip keeps its width, and line two, which shares line one's
/// column, frees no room, so neither gives way.
///
/// The status row's words read whole, since nothing else on screen says
/// them: they take line two's place, the tile gives way, then Retry is
/// drawn as its symbol, and only then do they take a third line, which in
/// the Mac's rows at the larger sizes makes the row taller
/// (`statusLayout`). An iPad's row stays 60 pt.
struct ActivityNowRowMetrics {
    static let height: CGFloat = 60
    static let tileSize: CGFloat = 32
    static let clockHeight: CGFloat = 28
    static let pillHeight: CGFloat = 32
    /// Above and below the status row's words when they take three lines.
    static let statusPadding: CGFloat = 3

    /// The narrowest row the platform's section draws: 200 pt inside the
    /// Mac's sidebar, which is always 220 pt wide. On iPad, 232 pt, what
    /// iPadOS 26.5's rows leave for their content inside their own insets,
    /// taken as the whole row, so a choice made here keeps 18 pt in hand;
    /// 27.0's rows are 10 pt wider and 18.6's 50. A row decides its action's
    /// symbol and its status words' lines at this width.
    static var narrowestRowWidth: CGFloat {
        #if targetEnvironment(macCatalyst)
        200
        #else
        232
        #endif
    }

    /// The characters of line one a row keeps at least.
    static let keptCharacters = 10

    /// Line one at its narrowest: its first ten characters and an ellipsis,
    /// or all of it where it is no longer. A character is what a reader
    /// counts as one, a letter with its marks.
    static func floor(of lineOne: String) -> String {
        lineOne.count <= keptCharacters ? lineOne
            : String(lineOne.prefix(keptCharacters)) + ActivityBarPartText.ellipsis
    }

    let sizeCategory: UIContentSizeCategory
    let lineOneFont: UIFont
    let detailFont: UIFont
    /// The clock's digits: 14 pt semibold with monospaced digits.
    let clockFont: UIFont
    /// View, Open game, Retry and Withdraw: 14 pt semibold.
    let actionFont: UIFont

    let spacing = ActivityBarSpacing(leading: 10, trailing: 8, between: 10)
    let clockPadding: CGFloat = 8
    let clockInnerGap: CGFloat = 4
    let pillPadding: CGFloat = 12
    let withdrawPadding: CGFloat = 8

    init(sizeCategory: UIContentSizeCategory) {
        let requested = sizeCategory == .unspecified ? .large : sizeCategory
        let capped = min(requested, ActivityBarMetrics.cap)
        self.sizeCategory = capped
        let traits = UITraitCollection(preferredContentSizeCategory: capped)
        func scaled(_ size: CGFloat, as style: UIFont.TextStyle) -> CGFloat {
            UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size), compatibleWith: traits).pointSize
        }
        lineOneFont = .systemFont(ofSize: scaled(15, as: .subheadline), weight: .semibold)
        detailFont = .systemFont(ofSize: scaled(13, as: .footnote))
        clockFont = .monospacedDigitSystemFont(ofSize: scaled(14, as: .subheadline), weight: .semibold)
        actionFont = .systemFont(ofSize: scaled(14, as: .subheadline), weight: .semibold)
    }

    /// The row's parts: the bar's two-line drawing of its lead, or of the
    /// status row, without +N, which All activity carries.
    static func parts(_ lead: ActivityBarLead) -> [ActivityBarPart] {
        ActivityBarDrawing(.lead(lead, counted: [], status: nil), form: .expanded).parts
    }

    static func parts(_ status: NowStatusRow) -> [ActivityBarPart] {
        let content: ActivityBarContent = status.offersRetry ? .unreachable(counted: []) : .status(status.words)
        return ActivityBarDrawing(content, form: .expanded).parts
    }

    /// - Parameters:
    ///   - actionAsSymbol: The action is drawn as its symbol.
    ///   - lineOneLines: The lines line one may take.
    func width(of part: ActivityBarPart, _ text: ActivityBarPartText, actionAsSymbol: Bool = false,
               lineOneLines: Int = 1) -> CGFloat {
        switch part {
        case .tile: Self.tileSize
        case .lineOne:
            ActivityBarMetrics.columnWidth(text.lineOneMinimum, font: lineOneFont, lines: lineOneLines,
                                           direction: text.direction)
                + (text.rank.map { ActivityBarMetrics.rankGap + measured($0, detailFont, text) } ?? 0)
        case .lineTwo, .plusN: 0
        case .hourglass: symbolWidth("hourglass") + clockInnerGap - spacing.between
        case .clock:
            // In sudden death the chip draws its mark before the digits, in
            // the hourglass's place, as the bar's does.
            text.clock.map { clock in
                2 * clockPadding + measured(clock.widestSample, clockFont, text)
                    + (text.suddenDeathMark.map { markWidth($0, text) + clockInnerGap } ?? 0)
            } ?? 2 * clockPadding + symbolWidth("hourglass")
        case .action(let action) where actionAsSymbol:
            symbolActionWidth(action)
        case .action(let action):
            max(ActivityBarMetrics.targetSize,
                measured(text.actionLabel(action), actionFont, text) + 2 * (action == .withdraw ? withdrawPadding : pillPadding))
        }
    }

    private func measured(_ string: String, _ font: UIFont, _ text: ActivityBarPartText) -> CGFloat {
        ceil(ActivityBarMetrics.textWidth(string, font: font, direction: text.direction))
    }

    /// The sudden-death mark the chip draws before its digits.
    private func markWidth(_ mark: GameControlSuddenDeathMark, _ text: ActivityBarPartText) -> CGFloat {
        switch mark {
        case .text(let string): measured(string, clockFont, text)
        case .glyph: symbolWidth(GameControlSuddenDeathMark.glyphSystemName)
        }
    }

    func symbolWidth(_ systemName: String) -> CGFloat {
        let pointSize = (clockFont.pointSize * 0.75).rounded()
        let image = UIImage(systemName: systemName,
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold))
        return ceil(image?.size.width ?? pointSize)
    }

    /// The parts that drop where the rest doesn't fit, the first first.
    /// The rank goes after them.
    static let dropOrder: [ActivityBarPart] = [.hourglass, .tile]

    /// The row's parts in `width`, with line one at its narrowest, after
    /// the drop order; where they still don't fit, without the rank too.
    /// - Parameters:
    ///   - actionAsSymbol: The action is drawn as its symbol.
    ///   - lineOneLines: The lines line one may take.
    func fit(_ parts: [ActivityBarPart], in width: CGFloat, text: ActivityBarPartText,
             actionAsSymbol: Bool = false, lineOneLines: Int = 1) -> ActivityBarFit {
        // The chip draws its hourglass alone without a countdown, and its
        // mark in the hourglass's place in sudden death: neither drops.
        let chipDrawsItsSymbol = text.clock == nil || text.suddenDeathMark != nil
        let kept = parts.filter { $0 != .lineTwo && $0 != .plusN && !($0 == .hourglass && chipDrawsItsSymbol) }
        let drawing = ActivityBarDrawing(parts: kept, dropOrder: Self.dropOrder.filter(kept.contains))
        let fit = drawing.fit(in: width, spacing: spacing) {
            self.width(of: $0, text, actionAsSymbol: actionAsSymbol, lineOneLines: lineOneLines)
        }
        guard !fit.fits, let rank = text.rank, !rank.isEmpty else { return fit }
        var bare = text
        bare.rank = nil
        let rest = kept.filter { !Self.dropOrder.contains($0) }
        let total = spacing.width(of: rest) {
            self.width(of: $0, bare, actionAsSymbol: actionAsSymbol, lineOneLines: lineOneLines)
        }
        return ActivityBarFit(parts: rest, width: total, fits: total <= width, keepsRank: false)
    }

    // MARK: The action's symbol

    /// Whether the row's action is drawn as its symbol: where its words
    /// don't leave line one its floor in `width`, even with the hourglass,
    /// the tile and the rank dropped. Then the symbol sits in the words'
    /// pill, and the words are its tooltip on the Mac and its Large Content
    /// Viewer. It comes from the words' measurement at the row's text size,
    /// which stops growing at XXL, at the platform's narrowest row, never
    /// from the row's layout.
    func actionDrawsSymbol(_ parts: [ActivityBarPart], in width: CGFloat = Self.narrowestRowWidth,
                           text: ActivityBarPartText, lineOneLines: Int = 1) -> Bool {
        Self.hasAction(parts) && !fit(parts, in: width, text: text, lineOneLines: lineOneLines).fits
    }

    private static func hasAction(_ parts: [ActivityBarPart]) -> Bool {
        parts.contains { part in
            if case .action = part { return true }
            return false
        }
    }

    // MARK: The status row

    /// How the status row draws its words.
    struct StatusLayout: Equatable {
        /// The lines its words may take.
        var lines: Int
        /// Retry is drawn as its symbol.
        var actionAsSymbol: Bool
        /// The row's height: 60 pt, or more where three lines need it.
        var height: CGFloat
    }

    /// The status row's words whole in `width`, `text.lineOneMinimum` being
    /// all of them: on two lines, with Retry's words where they fit beside
    /// them once the tile has given way, else with Retry as its symbol; and
    /// only then on three lines, the row as tall as they need. From the
    /// words' measurement at the platform's narrowest row, never the row's
    /// layout.
    func statusLayout(_ parts: [ActivityBarPart], text: ActivityBarPartText,
                      in width: CGFloat = Self.narrowestRowWidth) -> StatusLayout {
        let symbols = Self.hasAction(parts) ? [false, true] : [false]
        for lines in [2, 3] {
            for symbol in symbols
            where fit(parts, in: width, text: text, actionAsSymbol: symbol, lineOneLines: lines).fits {
                return StatusLayout(lines: lines, actionAsSymbol: symbol,
                                    height: statusRowHeight(lines: lines, text: text))
            }
        }
        return StatusLayout(lines: 3, actionAsSymbol: symbols.count > 1, height: statusRowHeight(lines: 3, text: text))
    }

    /// The row's 60 pt, or the words' lines with a little room above and
    /// below them where that is taller.
    private func statusRowHeight(lines: Int, text: ActivityBarPartText) -> CGFloat {
        let words = ActivityBarMetrics.lineHeight(text.lineOneMinimum, font: lineOneFont) * CGFloat(lines)
        return max(Self.height, ceil(words) + 2 * Self.statusPadding)
    }

    /// Each action's symbol.
    static func symbolName(_ action: ActivityBarAction) -> String {
        switch action {
        case .openGame: "arrow.forward"
        case .view: "eye"
        case .withdraw: "xmark"
        case .retry: "arrow.clockwise"
        }
    }

    /// The symbol's pill: the symbol at the words' size, padded as their
    /// pill is, and at least 44 pt wide.
    func symbolActionWidth(_ action: ActivityBarAction) -> CGFloat {
        let configuration = UIImage.SymbolConfiguration(pointSize: actionFont.pointSize, weight: .semibold)
        let image = UIImage(systemName: Self.symbolName(action), withConfiguration: configuration)
        return max(ActivityBarMetrics.targetSize, ceil(image?.size.width ?? actionFont.pointSize) + 2 * pillPadding)
    }
}

/// How many Activity rows the iPad's Now section lists: two where they fit
/// below the sidebar's last tab row, one where only one does, and none where
/// even one would reach it, so the section shows nothing there: it has no
/// background, and the tab rows would show through it. It comes from the
/// window scene's height, the text size and the language the sidebar is
/// drawn in, which change only with the window and the person's settings,
/// never from the section's own geometry. The section's text stops growing
/// at XXL, but the sidebar's rows grow with the text, are taller in
/// languages whose lines iOS sets taller, and at accessibility sizes wrap
/// their titles, each language's in its own places. The heights are
/// measured: the last tab row ends at the same place in a window of any
/// height while the list fits, and the section sits at the window's bottom,
/// so each threshold is the window height at which the section's top would
/// meet the last tab row on iPadOS 26.5, where it sits highest (10 pt
/// higher in a resized window, or once its rows have changed, than at a
/// launch with two rows), plus 9 pt; 18.6 and 27.0 leave more room. Two
/// rows at XXL, and in Thai at the default size, start at 834 pt instead,
/// 1 pt above that height, so that a full-size landscape window keeps the
/// two rows every measurement found room for. The Mac's window is never
/// shorter than 600 pt, which leaves room for two rows, so the Mac doesn't
/// ask.
enum ActivityNowSectionRows {
    /// The language the sidebar is drawn in. Its titles are the app's own
    /// strings, and iOS sets their lines for the first of the person's
    /// preferred languages, which decides their height. The two differ only
    /// where that language is one the app doesn't ship: in Hindi, the
    /// English titles' lines are as tall as Thai's.
    struct Language: Equatable {
        /// The app's strings' language, such as "pt-BR".
        var strings: String
        /// The language iOS sets the lines in, such as "hi-IN".
        var lines: String

        init(strings: String, lines: String) {
            self.strings = strings
            self.lines = lines
        }

        /// One language for both, as where the app ships it.
        init(_ language: String) {
            self.init(strings: language, lines: language)
        }

        /// The app's own: its strings' language, and the first of the
        /// person's preferred languages.
        static var app: Language {
            Language(strings: Bundle.main.preferredLocalizations.first ?? "en",
                     lines: Locale.preferredLanguages.first ?? "en")
        }

        /// The lines' language without its script or region, such as "hi".
        var linesCode: String { lines.prefix { $0 != "-" && $0 != "_" }.lowercased() }
    }

    /// How tall iOS sets a line in a language, as the sidebar's rows show it
    /// at every text size, measured in 49 languages: most at the standard
    /// height, then, each taller, as Vietnamese, as Thai and as Khmer.
    /// Armenian and Sinhala, a little shorter than Thai, count as Thai.
    enum LineHeight: CaseIterable {
        case standard, likeVietnamese, likeThai, likeKhmer

        init(_ language: Language) {
            let code = language.linesCode
            self = Self.allCases.first { Self.codes[$0]?.contains(code) == true } ?? .standard
        }

        private static let codes: [LineHeight: Set<String>] = [
            .likeVietnamese: ["vi", "ar", "fa", "ml", "or", "ta"],
            .likeThai: ["th", "as", "bn", "gu", "hi", "hy", "lo", "mr", "ne", "pa", "si"],
            .likeKhmer: ["km", "bo", "kn", "my", "te", "ur"],
        ]
    }

    /// The shortest window that lists two rows, and the shortest that lists
    /// one; nil where none does.
    struct Heights: Equatable {
        var twoRows: CGFloat?
        var oneRow: CGFloat?

        init(twoRows: CGFloat?, oneRow: CGFloat?) {
            self.twoRows = twoRows
            self.oneRow = oneRow
        }

        static func onlyOneRow(from height: CGFloat) -> Heights { Heights(twoRows: nil, oneRow: height) }
        static let noRows = Heights(twoRows: nil, oneRow: nil)
    }

    /// The thresholds by text size, the default size and smaller taking
    /// Large's, for each line height. At accessibility sizes the titles
    /// wrap: one row at most, from the height the language that wraps most
    /// needs, never lower for taller lines, and from AX4 none, since even an
    /// 11-inch iPad's 1210 pt portrait window has no room left.
    private static let thresholds: [(upTo: UIContentSizeCategory, standard: Heights, likeVietnamese: Heights,
                                     likeThai: Heights, likeKhmer: Heights)] = [
        (.large, Heights(twoRows: 770, oneRow: 708), Heights(twoRows: 806, oneRow: 744),
         Heights(twoRows: 834, oneRow: 780), Heights(twoRows: 896, oneRow: 834)),
        (.extraLarge, Heights(twoRows: 806, oneRow: 744), Heights(twoRows: 847, oneRow: 785),
         Heights(twoRows: 883, oneRow: 821), Heights(twoRows: 946, oneRow: 884)),
        (.extraExtraLarge, Heights(twoRows: 834, oneRow: 780), Heights(twoRows: 883, oneRow: 821),
         Heights(twoRows: 928, oneRow: 866), Heights(twoRows: 991, oneRow: 929)),
        (.extraExtraExtraLarge, Heights(twoRows: 896, oneRow: 834), Heights(twoRows: 946, oneRow: 884),
         Heights(twoRows: 991, oneRow: 929), Heights(twoRows: 1063, oneRow: 1001)),
        (.accessibilityMedium, .onlyOneRow(from: 960), .onlyOneRow(from: 960), .onlyOneRow(from: 1004),
         .onlyOneRow(from: 1083)),
        (.accessibilityLarge, .onlyOneRow(from: 1106), .onlyOneRow(from: 1106), .onlyOneRow(from: 1157),
         .noRows),
        (.accessibilityExtraLarge, .onlyOneRow(from: 1182), .noRows, .noRows, .noRows),
        (.accessibilityExtraExtraExtraLarge, .noRows, .noRows, .noRows, .noRows),
    ]

    /// At AX1 the Chinese and Korean titles don't wrap, so one row clears
    /// them in a full-size landscape window.
    private static let unwrappedAtAX1: Set<String> = ["ko", "zh-Hans", "zh-Hant"]
    /// At AX3 the Spanish, French and European Portuguese titles wrap once
    /// more than the others', and leave no room even in a portrait window.
    private static let wrappedMoreAtAX3: Set<String> = ["es", "fr", "pt-PT"]

    static func heights(sizeCategory: UIContentSizeCategory, language: Language) -> Heights {
        let category = sizeCategory == .unspecified ? .large : sizeCategory
        let lines = LineHeight(language)
        guard let entry = thresholds.first(where: { category <= $0.upTo }) else { return .noRows }
        if category.isAccessibilityCategory {
            // Taller lines were measured around English titles and their own
            // language's only.
            if lines != .standard, language.strings != "en", language.strings != language.linesCode { return .noRows }
            if category == .accessibilityMedium, lines == .standard, unwrappedAtAX1.contains(language.strings) {
                return .onlyOneRow(from: 834)
            }
            if category == .accessibilityExtraLarge, wrappedMoreAtAX3.contains(language.strings) { return .noRows }
        }
        switch lines {
        case .standard: return entry.standard
        case .likeVietnamese: return entry.likeVietnamese
        case .likeThai: return entry.likeThai
        case .likeKhmer: return entry.likeKhmer
        }
    }

    static func count(windowHeight: CGFloat, sizeCategory: UIContentSizeCategory, language: Language) -> Int {
        let heights = heights(sizeCategory: sizeCategory, language: language)
        if let two = heights.twoRows, windowHeight >= two { return ActivityModel.nowSectionRows }
        if let one = heights.oneRow, windowHeight >= one { return 1 }
        return 0
    }
}
