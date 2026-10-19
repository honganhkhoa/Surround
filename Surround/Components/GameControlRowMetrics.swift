import SwiftUI

/// Reserve the current phase's labels independently of the visible action.
/// Identity can borrow unused horizontal space without changing the board budget.
struct GameControlRowMetrics {
    static let moreDiameter: CGFloat = 44
    static let spacing: CGFloat = 8
    private static let horizontalPadding: CGFloat = 28
    private static let columnPadding: CGFloat = 24
    private static let verticalPadding: CGFloat = 12

    let font: UIFont
    let columnFont: UIFont
    private let labels: [String]
    let horizontalSize: CGSize
    let twoLineStatusHeight: CGFloat
    /// More matches the main action's height, so large text never leaves a
    /// small circle beside a large pill.
    let moreButtonDiameter: CGFloat

    init(dynamicTypeSize: DynamicTypeSize, locale: Locale = .current,
         phase: OGSGamePhase? = .play,
         localizedLabels: [String]? = nil) {
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
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 17, weight: .semibold),
            compatibleWith: UITraitCollection(preferredContentSizeCategory: category)
        )
        // Unit geometry tests run without the app's localization bundle, so
        // they can supply the same visible labels directly.
        let labels: [String]
        if let localizedLabels {
            labels = localizedLabels
        } else if phase == .stoneRemoval {
            labels = [
                String(localized: "Accept removed stones", locale: locale,
                       comment: "Displayed next to Stone Removal Phase - keep short. eg: 'Accept'"),
                String(localized: "Clear estimates", locale: locale)
            ]
        } else {
            labels = [
                String(localized: "Pass", locale: locale),
                String(localized: "Submit move", locale: locale),
                String(localized: "Rematch", locale: locale),
                // Reserve a count independently of the currently waiting games.
                String(localized: "Next", locale: locale) + " (999+)"
            ]
        }
        self.font = font
        let statusFont = UIFont.preferredFont(
            forTextStyle: .subheadline,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: category)
        )
        self.twoLineStatusHeight = ceil(statusFont.lineHeight * 2 + 8)
        self.columnFont = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 15, weight: .semibold),
            compatibleWith: UITraitCollection(preferredContentSizeCategory: category)
        )
        self.labels = labels
        let labelWidth = labels.map {
            ($0 as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        let moreButtonDiameter = max(Self.moreDiameter, ceil(font.lineHeight) + Self.verticalPadding)
        self.moreButtonDiameter = moreButtonDiameter
        horizontalSize = CGSize(
            width: ceil(labelWidth) + Self.horizontalPadding
                + Self.spacing + moreButtonDiameter,
            height: moreButtonDiameter
        )
    }

    /// A row prefers the phase reservation, but may give unused width to its
    /// neighboring identity. The current action is a minimum, never a board input.
    /// An unspecified proposal reports the stable ideal; a zero proposal reports
    /// the real minimum so HStack can prioritize the name without shrinking a label.
    func rowSize(proposedWidth: CGFloat?, mainActionWidth: CGFloat,
                 wrapsMainAction: Bool) -> CGSize {
        // Flexible SwiftUI frames normally return their intrinsic ideal for an
        // unspecified proposal. Keep the phase reservation if a child ever
        // reports an unbounded size instead of propagating infinity to HStack.
        let measuredActionWidth = mainActionWidth.isFinite ? max(0, mainActionWidth)
            : horizontalSize.width - Self.spacing - moreButtonDiameter
        let minimumWidth = measuredActionWidth > 0
            ? max(moreButtonDiameter, measuredActionWidth) + Self.spacing + moreButtonDiameter
            : moreButtonDiameter
        let idealWidth = max(horizontalSize.width, minimumWidth)
        guard wrapsMainAction else {
            let width = proposedWidth.map { max(minimumWidth, min(idealWidth, $0)) } ?? idealWidth
            return CGSize(width: width, height: horizontalSize.height)
        }

        // Wrapping is the layout's explicit last resort. Its height still comes
        // from all phase labels, not whichever action happens to be visible.
        let availableWidth = proposedWidth.flatMap { $0.isFinite ? $0 : nil }
        let width = max(96, availableWidth ?? idealWidth)
        return CGSize(width: width, height: rowHeight(at: width))
    }

    func columnHeight(at width: CGFloat) -> CGFloat {
        let labelHeight = min(
            maximumLabelHeight(at: width, font: columnFont, padding: Self.columnPadding), ceil(columnFont.lineHeight * 2)
        )
        return max(Self.moreDiameter, labelHeight + Self.verticalPadding)
            + Self.spacing + moreButtonDiameter
    }

    /// Duo Closed landscape's column row: a pill beside More within `width`,
    /// its label at the column font on at most two lines (it scales down to
    /// 70% before a third), reserved for every label of the phase.
    func columnRowHeight(width: CGFloat) -> CGFloat {
        let pillWidth = max(1, width - Self.spacing - moreButtonDiameter)
        let labelHeight = min(maximumLabelHeight(at: pillWidth, font: columnFont, padding: 12),
                              ceil(columnFont.lineHeight * 2))
        return max(moreButtonDiameter, labelHeight + 8)
    }

    /// A caller can switch to identity/action rows when a side column cannot
    /// fit every label within two lines, even at the allowed 70% text scale.
    func fitsColumn(at width: CGFloat) -> Bool {
        let minimumFont = columnFont.withSize(columnFont.pointSize * 0.7)
        return width >= Self.moreDiameter
            && maximumLabelHeight(at: width, font: minimumFont, padding: Self.columnPadding)
                <= ceil(minimumFont.lineHeight * 2) + 1
    }

    /// Height for the last-resort, full-width action row at large text sizes.
    func rowHeight(at width: CGFloat) -> CGFloat {
        let pillWidth = width - Self.spacing - moreButtonDiameter
        return max(
            moreButtonDiameter,
            maximumLabelHeight(at: pillWidth, font: font) + Self.verticalPadding
        )
    }

    private func maximumLabelHeight(at width: CGFloat, font: UIFont, padding: CGFloat = Self.horizontalPadding) -> CGFloat {
        labels.map {
            ceil(($0 as NSString).boundingRect(
                with: CGSize(width: max(1, width - padding),
                             height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font], context: nil
            ).height)
        }.max() ?? ceil(font.lineHeight)
    }
}

