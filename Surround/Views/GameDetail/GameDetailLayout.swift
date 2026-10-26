import SwiftUI

/// Only the undivided compact phone landscape spends the home-indicator inset.
/// Its pose comes from the window so opening a keyboard in portrait cannot
/// accidentally enable landscape edge deferral.
enum GameDetailBottomEdgePolicy {
    static func extendsContent(
        isPhone: Bool, compact: Bool, windowSize: CGSize?,
        hasDisplayDivision: Bool, keyboardVisible: Bool
    ) -> Bool {
        guard isPhone, compact, !hasDisplayDivision, !keyboardVisible,
              let windowSize, windowSize.height > 0 else { return false }
        return windowSize.width > windowSize.height
    }
}

enum GameDetailClockStyle {
    case full, compact, inline

    /// At the default text size. The pair scales both cards together.
    var cardHeight: CGFloat {
        switch self {
        case .full: return 96
        case .compact: return 50
        case .inline: return 44
        }
    }
}

/// Geometry only: neither names nor the currently visible action can move the board.
/// All children keep the same structural slots while their frames rearrange.
struct GameDetailLayoutPlan {
    enum Slot: Int, CaseIterable { case board, clocks, status, opponent, actions, analysis, analysisControls, chat, composer, preview, information }
    var frames: [Slot: CGRect] = [:]
    var clockStyle = GameDetailClockStyle.full
    var stackedClocks = false
    var verticalActions = false
    var horizontalActionsInColumn = false
    /// Duo Closed landscape's single column: the pill (74 pt) and More share
    /// a line just above you, and the clock uses 126 pt column cards.
    var columnActionRow = false
    var columnClockCards = false
    var compactColumnIdentity = false
    /// v149: what the column's cards draw for their detail lines. A line
    /// that does not fit takes a second line; where its card has no spare
    /// line, both cards grow by one and both chips drop their second line
    /// (rank), in this same pass. The board never moves.
    var columnDetailLayouts = GameDetailColumnDetailLayouts()
    var columnCardsGrow = false
    var compactColumnIdentityDropsSecondLine = false
    private var enlargedCompactClockBadges = false
    private var compactClocksReserveStatusRow = false
    private var compactClockBadgeWidth: CGFloat = 145
    var verticalOpponentIdentity = false
    var verticalAnalysisTree = false
    var wrapsMainAction = false
    var hidesActionIdentity = false
    var hidesIdentity = false
    var hidesOpponentIdentity = false
    var clocksInHeader = false
    var showsCurrentPlayerClockOnly = false
    var spaciousCompactClocks = false
    /// Portrait chat columns put More under the action's trailing edge.
    var trailsMoreInColumn = false
    /// Short columns (iPhone landscape): both chips may show a name on two
    /// lines, and the layout reserves both lines.
    var wrapsColumnNames = false
    /// Regular landscape: the chat preview bar shares the opponent's row above
    /// the board, beside the chip, so previewing never moves the board.
    var previewInOpponentRow = false
    /// Regular layouts at accessibility sizes cap a full card's growth. Its
    /// metadata lines keep scaling; the countdown grows less.
    private(set) var fullClockScale: CGFloat = 1
    private var fullClockFooterWidth: CGFloat = 0

    /// A full card's footer wraps only when the game's real periods and
    /// captures do not fit on one line in that card.
    var narrowFullClocks: Bool {
        clockStyle == .full && !self[.clocks].isEmpty
            && (stackedClocks ? self[.clocks].width : (self[.clocks].width - 8) / 2) < fullClockFooterWidth
    }

    var narrowCompactClocks: Bool {
        clockStyle == .compact && !self[.clocks].isEmpty
            && (spaciousCompactClocks || enlargedCompactClockBadges || compactClocksReserveStatusRow
                || (stackedClocks ? self[.clocks].width : (self[.clocks].width - 8) / 2) < compactClockBadgeWidth)
    }

    subscript(_ slot: Slot) -> CGRect { frames[slot] ?? .zero }

    init(size: CGSize, compact: Bool, zen: Bool, analyze: Bool, chat: Bool,
         hidesBoard: Bool, keyboard: Bool, accessibility: Bool,
         foldsClock: Bool, clockScale: CGFloat = 1, actionSize: CGSize = CGSize(width: 180, height: 48),
         actionMetrics: GameControlRowMetrics? = nil,
         composerHeight: CGFloat = 0, keyboardOverlap: CGFloat = 0,
         division: CGRect? = nil, panelDivision: CGRect? = nil,
         usesVerticalToolbar: Bool = false, preview: Bool = false,
         zenBoardCenterY: CGFloat? = nil, identityRowHeight: CGFloat? = nil,
         identityTwoLineRowHeight: CGFloat? = nil,
         identityColumnHeight: CGFloat? = nil,
         opponentSharesStatusWhenFolded: Bool = false,
         recoveryHeight: CGFloat = 0, fullClockFooterWidth: CGFloat = 0,
         compactClockLineWidth: CGFloat = 0,
         narrowChipWidth: CGFloat = 0,
         spaciousNarrowChipWidth: CGFloat = 0,
         compactColumnIdentityHeight: CGFloat? = nil,
         compactColumnIdentityShortHeight: CGFloat? = nil,
         columnDetail: GameDetailColumnDetailLayouts = .init(),
         compactColumnDetail: GameDetailColumnDetailLayouts = .init(),
         chromeBandTop: CGFloat? = nil,
         boardDepth: BoardDepthPlacement? = nil) {
        // One panel on every arrangement, independent of the window size.
        let analyze = analyze && !zen
        let chat = chat && !zen && !analyze
        let composerHeight = chat ? max(0, composerHeight) : 0
        let width = max(0, size.width), height = max(0, size.height)
        guard width > 0, height > 0 else { return }
        // Short windows use the compact-height columns even when their
        // horizontal size class is regular (for example a wide iPad window).
        let compact = compact || (width > height && height < 500)
        let landscape = width > height * (compact ? 1.15 : 1)
        let footerWidth = max(0, fullClockFooterWidth)
        self.fullClockFooterWidth = footerWidth
        self.fullClockScale = accessibility && !compact ? min(clockScale, 1.3) : clockScale
        let fullClockScale = self.fullClockScale
        let hidesBoard = hidesBoard && compact
        enlargedCompactClockBadges = !analyze && clockScale > 1.2
        // Zen's narrower correspondence clocks need another row for a time
        // such as 10h 47m beside its badge. Ordinary folded clocks keep their
        // existing budget so short screens do not lose board space.
        // A measured line (time, badge and komi) raises the budget where
        // the game's values need more, so the badge moves to its own row
        // rather than truncating or shrinking the time (iPhone SE).
        compactClockBadgeWidth = max(zen ? 200 * clockScale : 145, compactClockLineWidth)
        let margin: CGFloat = compact ? 0 : 24
        let gap: CGFloat = 8
        let identityBoardGap: CGFloat = 4
        // A theme with depth draws the board smaller than its slot: the face,
        // with its sidewall below, leaves room for the shadow. The slot stays
        // as it is; what lines up with the board's sides, top or bottom lines
        // up with the board as drawn. Gaps are still measured from the slot,
        // whose margin holds the shadow.
        func visible(_ board: CGRect) -> CGRect { boardDepth?.visibleBoard(in: board) ?? board }
        func visibleWidth(ofBoard side: CGFloat) -> CGFloat {
            visible(CGRect(x: 0, y: 0, width: side, height: side)).width
        }
        /// The side of a board drawn at least `width` wide. Depth grows slowly
        /// with the side, so a few steps settle it; each steps a hair past, as
        /// the drawn width otherwise only approaches `width` from below.
        func boardSide(drawnWidth width: CGFloat) -> CGFloat {
            var side = width
            for _ in 0..<8 {
                let shortfall = width - visibleWidth(ofBoard: side)
                guard shortfall > 0 else { break }
                side += shortfall + 0.01
            }
            return side
        }
        spaciousCompactClocks = !compact && zen && division == nil && panelDivision == nil
        // Zen's two-line chips hug their content (canvas "Zen · iPhone"): the
        // familiar width at least, wider where the game's longest countdown,
        // badge and komi need it, never wider than the space they are offered.
        let zenChipWidth = spaciousCompactClocks ? spaciousNarrowChipWidth : narrowChipWidth
        func zenChipPairWidth(base: CGFloat, available: CGFloat) -> CGFloat {
            min(available, max(base * clockScale, zenChipWidth * 2 + gap))
        }
        let spaciousPortraitZen = spaciousCompactClocks && width <= height && !accessibility
        let fullClock = GameDetailClockStyle.full.cardHeight * fullClockScale
        let foldedClock = (accessibility || spaciousCompactClocks ? 76 : GameDetailClockStyle.compact.cardHeight) * clockScale
        func compactClockHeight(cardWidth: CGFloat) -> CGFloat {
            // Narrow folded clocks put their turn badge on a third line.
            // Reserve it for both players so a turn never moves the board.
            !accessibility && (cardWidth < compactClockBadgeWidth || enlargedCompactClockBadges)
                ? max(foldedClock, 68 * clockScale) : foldedClock
        }
        let inlineClock = max(GameDetailClockStyle.inline.cardHeight, GameDetailClockStyle.inline.cardHeight * clockScale)
        let analysisControlHeight: CGFloat = 52
        let preferredTreeHeight: CGFloat = 190
        let preferredAnalysisHeight = preferredTreeHeight + gap + analysisControlHeight
        let previewHeight: CGFloat = preview ? (accessibility ? 68 : 44) : 0
        hidesIdentity = zen || (division == nil && ((compact && accessibility)
            || ((chat || analyze) && (!landscape || compact))))
        let showsActions = !analyze && !preview
        let showsCornerIdentity = !hidesIdentity && !preview
        let showsCorner = showsActions || showsCornerIdentity
        let intrinsicIdentityHeight = max(52, identityRowHeight ?? ceil(52 * clockScale))
        let identityHeight: CGFloat = hidesIdentity ? 0 : intrinsicIdentityHeight
        let columnIdentityHeight: CGFloat = hidesIdentity ? 0
            : max(112, identityColumnHeight ?? ceil(112 * clockScale))
        let horizontalFold = division.map { $0.width > $0.height } ?? false
        let sideActionWidth: CGFloat = horizontalFold ? 116
            : (compact && usesVerticalToolbar ? 103 : (compact || !zen ? 104 : 116))
        let columnActionHeight = actionMetrics?.columnHeight(at: sideActionWidth)
            ?? actionSize.height + 52
        let columnCornerHeight = (showsActions ? columnActionHeight : 0)
            + (showsCornerIdentity ? (showsActions ? gap : 0) + columnIdentityHeight : 0)
        let columnFits = actionMetrics?.fitsColumn(at: sideActionWidth) ?? true

        func actionRowHeight(at availableWidth: CGFloat, includingActions: Bool? = nil,
                             includingIdentity: Bool? = nil) -> CGFloat {
            let includesIdentity = includingIdentity ?? showsCornerIdentity
            let identity = includesIdentity ? identityHeight : 0
            let controlsWidth = max(1, availableWidth)
            guard includingActions ?? showsActions else { return identity }
            guard actionSize.width > controlsWidth else { return max(max(52, actionSize.height), identity) }
            return max(max(52, identity), actionMetrics?.rowHeight(at: controlsWidth)
                ?? actionSize.height * ceil(actionSize.width / controlsWidth))
        }
        func fullClockHeight(at width: CGFloat, stacked: Bool = false) -> CGFloat {
            // A second footer line only when the measured footer needs it.
            let cardWidth = stacked ? width : (width - gap) / 2
            return (cardWidth < footerWidth ? 110 : GameDetailClockStyle.full.cardHeight) * fullClockScale
        }
        func portraitFullClockHeight(at availableWidth: CGFloat, reserving fixedHeight: CGFloat) -> CGFloat {
            let preferred = fullClockHeight(at: visibleWidth(ofBoard: availableWidth))
            let boardWidth = min(availableWidth, max(0, height - fixedHeight - preferred))
            // Portrait clocks follow the board's final edges. Crossing the
            // narrow threshold adds a footer line to both cards, which can
            // only reduce the board further, so this reservation stays stable.
            return max(preferred, fullClockHeight(at: visibleWidth(ofBoard: boardWidth)))
        }
        var rowWidth = max(0, width - margin * 2 - 16)
        if let division, division.height > division.width {
            rowWidth = max(0, width - division.maxX - gap)
        }
        let actionHeight = actionRowHeight(at: rowWidth)
        // Duo wide poses draw their own chrome in the top band (the sidebar
        // button, Exit Zen) instead of a navigation bar. The game uses the rest
        // of the band; content at the leading edge starts below the button.
        let bandContentTop = chromeBandTop.map { $0 + 8 }
        let bandLeadingTop = chromeBandTop.map { $0 + 64 }
        var spansInlineClocks = false

        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x, y: y, width: max(0, w), height: max(0, h))
        }
        func square(in area: CGRect, bottom: Bool = false) -> CGRect {
            let side = max(0, min(area.width, area.height))
            return rect(area.midX - side / 2, bottom ? area.maxY - side : area.midY - side / 2, side, side)
        }
        /// A row above or below the board: each side that meets one of the
        /// slot's sides moves in as far as the board is drawn inside it.
        func alongBoard(_ frame: CGRect, _ board: CGRect) -> CGRect {
            let drawn = visible(board)
            guard drawn != board else { return frame }
            let minX = frame.minX + (abs(frame.minX - board.minX) < 0.5 ? drawn.minX - board.minX : 0)
            let maxX = frame.maxX - (abs(frame.maxX - board.maxX) < 0.5 ? board.maxX - drawn.maxX : 0)
            return rect(minX, frame.minY, maxX - minX, frame.height)
        }

        // Only an active Book fold splits the scene. Open is one canvas.
        let split = division
        if let split, split.minX < width, split.minY < height,
           split.maxX >= 0, split.maxY >= 0 {
            let inset: CGFloat = 8
            let isVertical = split.height > split.width
            if isVertical {
                let leftWidth = max(0, split.minX - gap)
                let rightX = min(width, split.maxX + gap)
                let rightWidth = max(0, width - rightX - inset)
                // The rows span the pane. Where the board does too, they
                // share its drawn width; reserve their heights at that width.
                let rightRowWidth = visibleWidth(ofBoard: rightWidth)
                let rightActionHeight = actionRowHeight(at: rightRowWidth)
                if zen {
                    clockStyle = .compact
                    stackedClocks = true
                    let cw = min(leftWidth - inset * 2, 160 * clockScale)
                    let clockHeight = compactClockHeight(cardWidth: cw) * 2 + gap
                    let groupHeight = clockHeight
                    frames[.clocks] = rect((leftWidth - cw) / 2, (height - groupHeight) / 2, cw, clockHeight)
                    frames[.board] = square(in: rect(rightX, inset, rightWidth,
                                                    height - inset * 2 - rightActionHeight - gap))
                    let b = self[.board]
                    let drawn = visible(b)
                    frames[.actions] = rect(rightX + drawn.minX - b.minX, b.maxY + gap,
                                            rightWidth - (b.width - drawn.width), rightActionHeight)
                } else {
                    clockStyle = .full
                    let top = bandContentTop ?? inset
                    var clockHeight = fullClockHeight(at: rightRowWidth)
                    func availableBoardSide(with clockHeight: CGFloat) -> CGFloat {
                        height - top - inset - clockHeight - gap - identityHeight
                            - identityBoardGap * 2 - rightActionHeight
                    }
                    // Fold clocks before shrinking a pane-width board; stay
                    // in safe bounds.
                    if compact && availableBoardSide(with: clockHeight) < rightWidth {
                        clockStyle = .compact
                        let cardWidth = max(0, (rightRowWidth - gap) / 2)
                        compactClocksReserveStatusRow = !analyze && cardWidth < 200 * clockScale
                        clockHeight = max(compactClockHeight(cardWidth: cardWidth),
                                          compactClocksReserveStatusRow ? 68 * clockScale : 0)
                    }
                    // The identity keeps its row between clocks and board;
                    // game status is part of the clocks themselves.
                    let boardY = top + clockHeight + gap + identityHeight + identityBoardGap
                    let boardSide = min(rightWidth, max(0, availableBoardSide(with: clockHeight)))
                    frames[.board] = rect(rightX + (rightWidth - boardSide) / 2,
                                          boardY, boardSide, boardSide)
                    let b = self[.board]
                    // The board is centred in the pane, and so are its rows: they
                    // keep their margin to the board as drawn. Depth never thins
                    // as a board grows, so they are never narrower than rightRowWidth.
                    let drawn = visible(b)
                    let paneRowX = rightX + drawn.minX - b.minX
                    let paneRowWidth = rightWidth - (b.width - drawn.width)
                    frames[.clocks] = rect(paneRowX, top, paneRowWidth, clockHeight)
                    frames[.opponent] = rect(paneRowX, self[.clocks].maxY + gap, paneRowWidth, identityHeight)
                    frames[.actions] = rect(paneRowX, b.maxY + identityBoardGap, paneRowWidth, rightActionHeight)
                    let panelY = bandLeadingTop ?? inset
                    let panelHeight = max(0, height - panelY - (bandLeadingTop == nil ? inset : 0))
                    let panelLeading: CGFloat = 16
                    if analyze {
                        verticalAnalysisTree = true
                        frames[.analysis] = rect(panelLeading, panelY, leftWidth - panelLeading, panelHeight)
                    }
                    if chat {
                        frames[.chat] = rect(panelLeading, panelY, leftWidth - panelLeading, panelHeight)
                    } else if !analyze {
                        frames[.information] = rect(panelLeading, panelY, leftWidth - panelLeading, panelHeight)
                    }
                }
            } else {
                let inset: CGFloat = 12
                let topBottom = max(inset, split.minY - gap)
                let bottomY = min(height, split.maxY + gap)
                if analyze || chat {
                    // The horizontal fold leaves one short upper pane. Native
                    // navigation carries its clocks so panels use its height.
                    clockStyle = .inline
                    clocksInHeader = true
                    showsCurrentPlayerClockOnly = true
                    let panelWidth = width - inset * 2
                    if analyze {
                        verticalAnalysisTree = false
                        frames[.analysis] = rect(inset, inset, panelWidth, topBottom - inset)
                    } else {
                        frames[.chat] = rect(inset, inset, panelWidth, topBottom - inset)
                    }
                } else {
                    clockStyle = zen ? .compact : .full
                    let cw = min(width - inset * 2, (zen ? 320 : 420) * clockScale)
                    let ch = zen ? compactClockHeight(cardWidth: (cw - gap) / 2) : fullClock
                    frames[.clocks] = rect((width - cw) / 2, topBottom - ch, cw, ch)
                    if !zen {
                        frames[.information] = rect(inset, inset, width - inset * 2,
                                                    self[.clocks].minY - gap - inset)
                    }
                }
                verticalActions = true
                verticalOpponentIdentity = !zen
                let side: CGFloat = max(96, min(120, sideActionWidth))
                let boardX = inset + side + gap
                frames[.board] = square(in: rect(boardX, bottomY,
                                                 width - boardX * 2, height - bottomY - inset), bottom: true)
                let b = self[.board]
                let drawn = visible(b)
                frames[.opponent] = rect(b.minX - side - gap, drawn.minY, side, columnIdentityHeight)
                frames[.actions] = rect(b.maxX + gap, max(bottomY, drawn.maxY - columnCornerHeight),
                                        side, columnCornerHeight)
            }
        } else if landscape && compact && (analyze || chat) {
            // A compact landscape always has two independent content regions.
            // Preserve a usable tree/preview column before sizing its board.
            let outer: CGFloat = 8
            let separateControls = analyze && usesVerticalToolbar
            // Duo Closed landscape chat keeps Play's board, centred beside a
            // column that spans the board's height: clocks, chat, the action.
            let closedDuoChat = chat && !analyze && usesVerticalToolbar && !hidesBoard
            let alignsColumnToBoard = separateControls || closedDuoChat
            let controlsHeight = separateControls ? analysisControlHeight + gap : 0
            let minimumPanelWidth: CGFloat = separateControls ? 224 : (analyze ? 254 : (closedDuoChat ? 214 : 240))
            let availableWidth = max(0, width - gap - outer * 2)
            // Four branch columns receive 224pt when possible. Below that,
            // preserve the under-board bar's 346pt branch-arrow minimum first.
            // The bar is as wide as the board is drawn.
            let preferredBoardWidth = availableWidth - minimumPanelWidth
            let boardWidth = separateControls
                ? max(min(boardSide(drawnWidth: 346), availableWidth), preferredBoardWidth) : preferredBoardWidth
            let boardSide = min(height - outer * 2 - controlsHeight, boardWidth)
            let boardX = width - outer - boardSide
            let panelWidth = boardX - outer - gap
            clockStyle = .inline
            clocksInHeader = !usesVerticalToolbar
            stackedClocks = usesVerticalToolbar
            let clockHeight = clocksInHeader ? 0 : inlineClock * 2 + (alignsColumnToBoard ? -2 : gap)
            let cw = min(panelWidth, (separateControls ? 180 : 320) * clockScale)
            let clockX = separateControls ? outer + panelWidth - cw : outer
            let boardY = alignsColumnToBoard ? max(outer, (height - boardSide - controlsHeight) / 2) : outer
            let drawn = visible(rect(boardX, boardY, boardSide, boardSide))
            // Beside a board, the column starts level with its face and, where
            // the board reaches the bottom margin, ends on its sidewall.
            let besideBoard = analyze || !hidesBoard
            let columnTop = besideBoard ? outer + (drawn.minY - boardY) : outer
            let reachesBottom = besideBoard && abs(boardY + boardSide - (height - outer)) < 0.5
            let columnBottom = height - outer - (reachesBottom ? boardY + boardSide - drawn.maxY : 0)
            // Inline faces are34pt inside44pt hit slots. Align the first face
            // with the board and keep8pt between faces and the following panel.
            let clockY = alignsColumnToBoard ? max(0, drawn.minY - 5) : columnTop
            if clockHeight > 0 { frames[.clocks] = rect(clockX, clockY, cw, clockHeight) }
            let y = clockY + (clockHeight > 0 ? clockHeight + (alignsColumnToBoard ? 3 : gap) : 0)
            frames[.board] = rect(boardX, boardY, boardSide, boardSide)
            if analyze {
                verticalAnalysisTree = usesVerticalToolbar
                frames[.analysis] = rect(outer, y, panelWidth, columnBottom - y)
                if separateControls {
                    frames[.analysisControls] = alongBoard(rect(boardX, self[.board].maxY + gap,
                                                                boardSide, analysisControlHeight), self[.board])
                    frames[.analysis] = rect(outer, y, panelWidth, self[.analysisControls].maxY - y)
                }
            } else {
                let actionWidth = hidesBoard ? width - outer * 2 : panelWidth
                let chatActionHeight = actionRowHeight(at: actionWidth)
                let actionBottom = closedDuoChat ? drawn.maxY : columnBottom
                frames[.actions] = rect(outer, actionBottom - chatActionHeight, actionWidth, chatActionHeight)
                frames[.chat] = rect(outer, y, panelWidth, self[.actions].minY - y - gap)
                if hidesBoard {
                    frames[.board] = .zero
                    frames[.chat] = rect(outer, y, width - outer * 2,
                                         self[.actions].minY - y - gap)
                    frames[.actions] = rect(outer, height - outer - chatActionHeight, actionWidth, chatActionHeight)
                }
            }
        } else if chat && !landscape {
            // Portrait panels sit above the board. Chat gives the action a
            // column beside it; only the conversation avoids the keyboard.
            let outer: CGFloat = compact ? 8 : margin
            let top: CGFloat = compact ? 8 : 16
            let side: CGFloat = compact ? (usesVerticalToolbar ? 104 : 126) : 120
            clockStyle = .inline
            clocksInHeader = !usesVerticalToolbar
            showsCurrentPlayerClockOnly = compact && clocksInHeader
            hidesIdentity = true
            verticalActions = !hidesBoard
            let ch = clocksInHeader ? 0 : inlineClock
            if ch > 0 {
                // Without a title slot the pair spans the conversation's row.
                spansInlineClocks = true
                frames[.clocks] = rect(outer, outer, width - outer * 2, ch)
            }
            trailsMoreInColumn = verticalActions
            let panelY = top + (ch > 0 ? ch + gap : 0)
            let controlsHeight = actionMetrics?.columnHeight(at: side) ?? actionSize.height + 52
            let minimumPanel = max(120, composerHeight)
            let boardSide = hidesBoard ? 0 : min(max(0, width - outer * 2 - gap - side),
                max(0, height - outer - panelY - gap - minimumPanel))
            let boardY = height - outer - boardSide
            if boardSide > 0 {
                frames[.board] = rect(outer, boardY, boardSide, boardSide)
                let b = self[.board]
                let drawn = visible(b)
                frames[.actions] = compact
                    ? rect(outer + boardSide + gap,
                           max(panelY, height - outer - (b.maxY - drawn.maxY) - controlsHeight),
                           side, controlsHeight)
                    : rect(outer + boardSide + gap, drawn.minY, side, drawn.height)
                frames[.chat] = rect(outer, panelY, width - outer * 2, boardY - gap - panelY)
                if preview && !compact {
                    // The preview bar takes the conversation's last row,
                    // directly above the board, which never moves.
                    let barY = boardY - gap - previewHeight
                    frames[.preview] = alongBoard(rect(outer, barY, boardSide, previewHeight), b)
                    frames[.chat] = rect(outer, panelY, width - outer * 2, max(0, barY - gap - panelY))
                }
                if !compact {
                    // The conversation starts on the board's drawn side, as its
                    // preview row does. A compact one keeps the screen's edge.
                    frames[.chat] = alongBoard(self[.chat], b)
                }
            } else {
                let rowHeight = actionRowHeight(at: width - outer * 2)
                frames[.actions] = rect(outer, height - outer - rowHeight, width - outer * 2, rowHeight)
                frames[.chat] = rect(outer, panelY, width - outer * 2, self[.actions].minY - gap - panelY)
            }
        } else if analyze && !landscape {
            // Reserve a usable horizontal tree before maximizing the board.
            // Short phones reduce the tree first, never overlay it on the board.
            let top: CGFloat = compact ? 8 : 16
            let bottom = compact ? 0 : margin
            // Closed Duo's inline clocks already occupy a padded 44pt slot.
            // Its tree follows that slot directly and the controls meet the
            // board, retaining the tree's own 8pt control separation.
            let closedDuo = compact && usesVerticalToolbar
            let clockGap: CGFloat = closedDuo ? 0 : gap
            let boardGap: CGFloat = closedDuo ? 0 : gap
            let contentWidth = width - margin * 2
            hidesIdentity = true
            clockStyle = .inline
            clocksInHeader = !usesVerticalToolbar
            let ch = clocksInHeader ? 0 : inlineClock
            if ch > 0 {
                let cw = min(contentWidth - 16, 320 * clockScale)
                frames[.clocks] = rect((width - cw) / 2, top, cw, ch)
            }
            let panelY = top + (ch > 0 ? ch + clockGap : 0)
            let availableHeight = max(0, height - bottom - panelY)
            let boardFloor = min(contentWidth, 320, max(0, availableHeight - analysisControlHeight - boardGap))
            // Regular portrait keeps Play's board while the folded header
            // and hidden identities give their rows to the tree. Retain the
            // same footer budget as Play, even though Analyze paints its bar
            // above the board.
            let playActionHeight = max(intrinsicIdentityHeight,
                actionRowHeight(at: min(rowWidth, visibleWidth(ofBoard: contentWidth)),
                                includingActions: true, includingIdentity: true))
            let fixedPlayHeight = 16 + margin + intrinsicIdentityHeight
                + playActionHeight + gap * 2 + identityBoardGap
            let playClockHeight = portraitFullClockHeight(at: contentWidth, reserving: fixedPlayHeight)
            let playBoardLimit = height - fixedPlayHeight - playClockHeight
            let maximumBoard = compact ? contentWidth : min(contentWidth, max(0, playBoardLimit))
            let boardSize = compact
                ? min(maximumBoard, max(boardFloor, availableHeight - preferredAnalysisHeight - boardGap))
                : maximumBoard
            let boardY = height - bottom - boardSize
            let panelX = compact ? margin : (width - boardSize) / 2
            let panelWidth = compact ? contentWidth : boardSize
            frames[.analysis] = rect(panelX, panelY, panelWidth, max(0, boardY - boardGap - panelY))
            frames[.board] = rect((width - boardSize) / 2, boardY, boardSize, boardSize)
            if !compact {
                // The regular tree and its controls follow the board's edges;
                // compact ones keep the screen's.
                frames[.analysis] = alongBoard(self[.analysis], self[.board])
            }
        } else if landscape && compact && usesVerticalToolbar && !accessibility
                    && division == nil && panelDivision == nil {
            // Duo Closed landscape, Play and Zen (rule 2): one 126 pt column on
            // the left, 12 pt from the board, so the board takes the full
            // height (436 pt; 450 in Zen). The opponent and the clocks sit at
            // the top, the action and you at the bottom. Chat and Analyze keep
            // the short columns above, where the board steps down to 356 pt.
            let column: CGFloat = 126
            let columnX: CGFloat = 12
            let columnGap: CGFloat = 12
            let vertical: CGFloat = zen ? 8 : 15
            let trailing: CGFloat = 8
            let boardSide = max(0, min(height - vertical * 2 - previewHeight,
                                       width - columnX - column - columnGap - trailing))
            let boardY = previewHeight + max(vertical, (height - previewHeight - boardSide) / 2)
            frames[.board] = rect(columnX + column + columnGap, boardY, boardSide, boardSide)
            // The column spans the board as drawn, from its face to its sidewall.
            let b = visible(self[.board])
            stackedClocks = true
            columnActionRow = showsActions
            compactColumnIdentity = !hidesIdentity
            // The chip reserves its second line only when it has one: with
            // ranks hidden it is the avatar and name only (v149).
            let fullChip = hidesIdentity ? 0 : max(44, compactColumnIdentityHeight ?? ceil(88 * clockScale))
            let shortChip = hidesIdentity ? 0 : min(fullChip, max(44, compactColumnIdentityShortHeight ?? fullChip))
            let row = showsActions ? max(44, actionMetrics?.columnRowHeight(width: column) ?? 44) : 0
            func cornerHeight(_ chip: CGFloat) -> CGFloat { row + (row > 0 && chip > 0 ? gap : 0) + chip }
            let columnCard = ceil(GameDetailColumnDetailLayouts.fullCardHeight(grown: false) * clockScale)
            let grownColumnCard = ceil(GameDetailColumnDetailLayouts.fullCardHeight(grown: true) * clockScale)
            let foldedCard = compactClockHeight(cardWidth: column)
            let grownFoldedCard = foldedCard + GameDetailColumnDetailLayouts.compactLineGrowth * clockScale
            func fits(_ card: CGFloat, chip: CGFloat) -> Bool {
                chip + (chip > 0 ? gap : 0) + card * 2 + gap + gap + cornerHeight(chip) <= b.height
            }
            // At large text sizes the cards fold to two-line chips (rule 11)
            // before anything overlaps; Zen always uses two-line chips. A
            // detail line wraps only where the column has the room for it;
            // otherwise it keeps one line (and its ellipsis) as before.
            var chip = fullChip
            var card = foldedCard
            if !zen && !columnDetail.needsGrowth && fits(columnCard, chip: fullChip) {
                clockStyle = .full
                card = columnCard
                columnDetailLayouts = columnDetail
            } else if !zen && columnDetail.needsGrowth && fits(grownColumnCard, chip: shortChip) {
                clockStyle = .full
                card = grownColumnCard
                chip = shortChip
                columnCardsGrow = true
                compactColumnIdentityDropsSecondLine = shortChip < fullChip
                columnDetailLayouts = columnDetail
            } else if !zen && columnDetail.needsGrowth && fits(columnCard, chip: fullChip) {
                // No room to grow: the cards keep one line, as before v149.
                clockStyle = .full
                card = columnCard
            } else {
                clockStyle = .compact
                if compactColumnDetail.needsGrowth && fits(grownFoldedCard, chip: fullChip) {
                    card = grownFoldedCard
                    columnCardsGrow = true
                    columnDetailLayouts = compactColumnDetail
                } else if !compactColumnDetail.needsGrowth {
                    columnDetailLayouts = compactColumnDetail
                }
            }
            columnClockCards = clockStyle == .full
            let corner = cornerHeight(chip)
            verticalOpponentIdentity = chip > 0
            frames[.opponent] = rect(columnX, b.minY, column, chip)
            frames[.clocks] = rect(columnX, b.minY + chip + (chip > 0 ? gap : 0), column, card * 2 + gap)
            frames[.actions] = rect(columnX, b.maxY - corner, column, corner)
        } else if landscape && !compact && !zen {
            // Regular landscape always reserves the same board block and
            // side column. Opening a panel rearranges only the clock pair.
            let leading: CGFloat = usesVerticalToolbar ? 16 : 24
            let trailing: CGFloat = usesVerticalToolbar ? 8 : 24
            let top: CGFloat = bandContentTop ?? (usesVerticalToolbar ? 8 : 16)
            let bottom: CGFloat = usesVerticalToolbar ? 0 : 16
            let columnGap: CGFloat = 16
            let boardWidth = max(0, width - leading - trailing - 280 - columnGap)
            // The rows above and below the board are as wide as it is drawn.
            var footer = actionRowHeight(at: visibleWidth(ofBoard: boardWidth),
                                         includingActions: true, includingIdentity: true)
            var boardSide: CGFloat = 0
            for _ in 0..<4 {
                let boardHeight = max(0, height - top - bottom - identityHeight - footer - identityBoardGap * 2)
                boardSide = min(boardHeight, boardWidth)
                let requiredFooter = actionRowHeight(at: visibleWidth(ofBoard: boardSide),
                                                     includingActions: true, includingIdentity: true)
                guard requiredFooter > footer else { break }
                footer = requiredFooter
            }
            boardSide = min(boardWidth,
                max(0, height - top - bottom - identityHeight - footer - identityBoardGap * 2))
            let columnWidth = min(400, max(0, width - leading - trailing - boardSide - columnGap))
            let columnEnd = leading + columnWidth
            let boardX = usesVerticalToolbar ? width - trailing - boardSide
                : columnEnd + (width - columnEnd - boardSide) / 2
            let boardY = top + identityHeight + identityBoardGap
            frames[.board] = rect(boardX, boardY, boardSide, boardSide)
            let drawn = visible(self[.board])
            frames[.opponent] = rect(drawn.minX, top, drawn.width, identityHeight)
            // The row is at least 52 pt (64 at accessibility sizes): room for
            // the bar's single line beside the chip.
            previewInOpponentRow = preview && identityHeight > 0
            frames[.actions] = rect(drawn.minX, self[.board].maxY + identityBoardGap, drawn.width, footer)
            let panelTop = usesVerticalToolbar ? max(drawn.minY, bandLeadingTop ?? 0) : top
            let column = rect(leading, panelTop, columnWidth, height - bottom - panelTop)
            clockStyle = .full
            if chat || analyze {
                let clockHeight = fullClockHeight(at: columnWidth)
                frames[.clocks] = rect(leading, panelTop, columnWidth, clockHeight)
                let panel = rect(leading, self[.clocks].maxY + gap, columnWidth,
                                 column.maxY - self[.clocks].maxY - gap)
                if analyze {
                    verticalAnalysisTree = true
                    frames[.analysis] = panel
                } else {
                    frames[.chat] = panel
                }
            } else {
                stackedClocks = true
                let clockWidth = min(300, columnWidth)
                let clockHeight = fullClockHeight(at: clockWidth, stacked: true) * 2 + gap
                frames[.clocks] = rect(column.maxX - clockWidth,
                                      column.midY - clockHeight / 2, clockWidth, clockHeight)
            }
        } else if landscape {
            // Short columns, plus Zen's balanced reservations around the board.
            let outer: CGFloat = compact ? 8 : 16
            let boardGap: CGFloat = compact && !usesVerticalToolbar && !zen ? 12 : gap
            let compactHorizontalZen = compact && zen && !usesVerticalToolbar
            let unfoldedHorizontalZen = !compact && zen && !usesVerticalToolbar
                && division == nil && panelDivision != nil
            // Without its tray, Open wide Zen gives the board the height from
            // the band's top to the content's bottom, centred on the hinge.
            let trayFreeZenTop = unfoldedHorizontalZen ? chromeBandTop : nil
            let outerTop = trayFreeZenTop ?? outer
            let outerBottom = trayFreeZenTop == nil ? outer : 0
            let right: CGFloat = compact && !usesVerticalToolbar ? (compactHorizontalZen ? 132 : 136) : sideActionWidth
            let rowActions = accessibility || !columnFits || columnCornerHeight > height - outer * 2
            let spaciousWideZen = spaciousCompactClocks && width >= 1000 && !rowActions
            let sideRowActions = unfoldedHorizontalZen || spaciousWideZen
            var left: CGFloat = compact ? (usesVerticalToolbar ? sideActionWidth : (compactHorizontalZen ? 132 : 136)) : (accessibility ? 208 : 176)
            if !compact && usesVerticalToolbar && !accessibility && !rowActions {
                let boardHeight = max(0, height - outer * 2 - previewHeight)
                left = max(sideActionWidth, min(left, width - outer * 2 - right - gap * 2 - boardHeight))
            }
            if unfoldedHorizontalZen && !rowActions {
                let boardHeight = max(0, height - outerTop - outerBottom - previewHeight)
                left = max(104, min(left, (width - outer * 2 - gap * 2 - boardHeight) / 2))
            }
            if compact && !zen && !rowActions {
                let boardWidth = width - outer * 2 - left - right - boardGap * 2
                let boardHeight = height - outer * 2 - previewHeight
                left += min(max(0, 196 - left), max(0, boardWidth - boardHeight))
            }
            let landscapeFullClock = fullClockHeight(at: left, stacked: true)
            verticalActions = !rowActions && !sideRowActions
            stackedClocks = true
            clockStyle = zen ? .compact : .full
            // Narrow side columns allow a name two lines (canvas). Reserve
            // both on both chips, so a long name never moves anything.
            let shortColumnIdentityHeight = compact && !zen && !accessibility && identityHeight > 0
                ? max(identityHeight, identityTwoLineRowHeight ?? identityHeight) : identityHeight
            wrapsColumnNames = shortColumnIdentityHeight > identityHeight
            var landscapeIdentityHeight = shortColumnIdentityHeight
            if compact {
                func fitsClockCards(_ cardHeight: CGFloat) -> Bool {
                    landscapeIdentityHeight + cardHeight * 2 + gap * 2 + outer * 2 <= height
                }
                if clockStyle == .full && !fitsClockCards(landscapeFullClock) { clockStyle = .compact }
                if clockStyle == .compact && !fitsClockCards(compactClockHeight(cardWidth: left)) { clockStyle = .inline }
                if clockStyle == .inline && !fitsClockCards(inlineClock) {
                    landscapeIdentityHeight = 0
                    hidesOpponentIdentity = !hidesIdentity
                    wrapsColumnNames = false
                }
            }
            let ch = clockStyle == .full ? landscapeFullClock
                : (clockStyle == .compact ? compactClockHeight(cardWidth: left) : inlineClock)
            let clockHeight = ch * 2 + gap
            let boardX = outer + left + boardGap
            let reservedRight = zen && !usesVerticalToolbar ? left : right
            let boardWidth = max(0, width - boardX - outer - (rowActions ? 0 : reservedRight + boardGap))
            let boardAreaHeight = height - outerTop - outerBottom - previewHeight
            var landscapeActionHeight = actionRowHeight(at: visibleWidth(ofBoard: boardWidth))
            if rowActions {
                for _ in 0..<4 {
                    let squareWidth = min(boardWidth, max(0, boardAreaHeight - landscapeActionHeight - gap))
                    let requiredHeight = actionRowHeight(at: visibleWidth(ofBoard: squareWidth))
                    guard requiredHeight > landscapeActionHeight else { break }
                    landscapeActionHeight = requiredHeight
                }
            }
            let footer = rowActions ? landscapeActionHeight + gap : 0
            frames[.board] = square(in: rect(boardX, outerTop + previewHeight,
                                             boardWidth, boardAreaHeight - footer))
            if compact && !usesVerticalToolbar && !zen {
                frames[.board] = self[.board].offsetBy(dx: boardX - self[.board].minX, dy: 0)
            }
            let b = self[.board]
            let drawn = visible(b)
            // Phone Zen's stacked chips grow from the board toward the window
            // edge where the game's countdown needs it; the board stays put.
            let zenColumn = compactHorizontalZen
                ? min(max(left, zenChipWidth), max(left, b.minX - boardGap - outer)) : left
            let clockX = spaciousWideZen ? 24 : (compactHorizontalZen || unfoldedHorizontalZen ? b.minX - boardGap - zenColumn : outer)
            let clockWidth = spaciousWideZen ? max(0, b.minX - gap - clockX) : zenColumn
            // A column level with the board's top starts level with its face.
            let columnTop = outer + (abs(b.minY - outer) < 0.5 ? drawn.minY - b.minY : 0)
            frames[.opponent] = rect(outer, columnTop, left, landscapeIdentityHeight)
            let clockCenter = spaciousCompactClocks || trayFreeZenTop != nil ? b.midY : height / 2
            let clockY = zen ? max(outer, clockCenter - clockHeight / 2) : columnTop + landscapeIdentityHeight + gap
            frames[.clocks] = rect(clockX, clockY, clockWidth, clockHeight)
            let cornerIdentityHeight = wrapsColumnNames ? shortColumnIdentityHeight : identityHeight
            let cornerHeight = (showsActions ? columnActionHeight : 0)
                + (showsCornerIdentity ? gap + cornerIdentityHeight : 0)
            let surplusActionWidth = max(0, width - outer - b.maxX - boardGap)
            horizontalActionsInColumn = compact && !usesVerticalToolbar && !zen
                && !accessibility && !rowActions && showsActions && actionSize.width <= surplusActionWidth
            if horizontalActionsInColumn {
                let controlsHeight = max(44, actionSize.height)
                let corner = controlsHeight + (showsCornerIdentity ? gap + cornerIdentityHeight : 0)
                frames[.actions] = rect(b.maxX + boardGap, drawn.maxY - corner, surplusActionWidth, corner)
            } else if sideRowActions && !rowActions {
                let actionX = b.maxX + boardGap
                let actionWidth = width - (spaciousWideZen ? 24 : outer) - actionX
                let actionHeight = actionRowHeight(at: actionWidth, includingIdentity: false)
                frames[.actions] = rect(actionX, drawn.maxY - actionHeight, actionWidth, actionHeight)
            } else {
                frames[.actions] = rowActions
                    ? rect(drawn.minX, b.maxY + (showsCornerIdentity ? identityBoardGap : gap), drawn.width,
                           landscapeActionHeight)
                    : rect(b.maxX + boardGap, max(outer, drawn.maxY - cornerHeight), right, cornerHeight)
            }
        } else {
            // Width-bound Play and Zen: the clock and identity rows bound the board.
            let contentWidth = width - margin * 2
            let topInset: CGFloat = compact ? 8 : (spaciousPortraitZen ? 10 : (zen ? 12 : 16))
            // A regular row below the board spans it as drawn, never wider than
            // the content's own row. Reserve its height at that width.
            let rowActionHeight = !compact && (!zen || spaciousCompactClocks)
                ? actionRowHeight(at: min(rowWidth, visibleWidth(ofBoard: contentWidth))) : actionHeight
            clockStyle = zen ? .compact : .full
            if compact && (foldsClock || height - contentWidth < 250) && clockStyle == .full { clockStyle = .compact }
            var ch = clocksInHeader ? 0 : (clockStyle == .full
                ? fullClockHeight(at: contentWidth - (compact ? 16 : 0))
                : (clockStyle == .compact
                   ? compactClockHeight(cardWidth: ((zen
                        ? zenChipPairWidth(base: spaciousCompactClocks ? 360 : (compact && !usesVerticalToolbar ? 282 : 320),
                                           available: contentWidth - (compact ? 16 : 0))
                        : contentWidth - (compact ? 16 : 0)) - gap) / 2)
                   : inlineClock))
            let keepsFoldedOpponentRow = opponentSharesStatusWhenFolded && compact
                && clockStyle == .compact && !zen && !chat && !analyze && !hidesIdentity
            let rowGapCount: CGFloat = (ch > 0 ? 1 : 0) + (showsCorner ? 1 : 0)
            let fixedWithoutClockOrIdentity = rowActionHeight + previewHeight
                + gap * rowGapCount + topInset + margin
            var fixedWithoutIdentity = ch + fixedWithoutClockOrIdentity
            var rowIdentityHeight = identityHeight
            if compact && clockStyle == .compact && !zen && !chat && !analyze
                && !keepsFoldedOpponentRow
                && (foldsClock || height - fixedWithoutIdentity - identityHeight < contentWidth) {
                // A short phone or large text moves the opponent to the native
                // navigation header, giving this row's space back to the board.
                rowIdentityHeight = 0
                hidesOpponentIdentity = true
            }
            let opponentBoardGap = rowIdentityHeight > 0 ? identityBoardGap : 0
            if !compact && !zen {
                ch = portraitFullClockHeight(at: contentWidth,
                    reserving: fixedWithoutClockOrIdentity + rowIdentityHeight + opponentBoardGap)
                fixedWithoutIdentity = ch + fixedWithoutClockOrIdentity
            }
            let fixed = fixedWithoutIdentity + rowIdentityHeight + opponentBoardGap
            let boardSize = min(contentWidth, max(0, height - fixed))
            var y = topInset
            frames[.clocks] = rect(margin + (compact ? 8 : 0), y, contentWidth - (compact ? 16 : 0), ch)
            y += ch + (ch > 0 ? gap : 0)
            if !compact && !zen {
                y = max(y, height - margin - boardSize - rowActionHeight - rowIdentityHeight - opponentBoardGap - gap - previewHeight)
            }
            frames[.opponent] = rect(margin + 8, y, contentWidth - 16, rowIdentityHeight)
            y += rowIdentityHeight + opponentBoardGap
            if preview { frames[.preview] = rect(margin + 8, y, contentWidth - 16, previewHeight); y += previewHeight }
            frames[.board] = rect((width - boardSize) / 2, y, boardSize, boardSize)
            frames[.actions] = rect(margin + 8, y + boardSize
                                    + (showsCorner ? (showsCornerIdentity ? identityBoardGap : gap) : 0),
                                    contentWidth - 16, rowActionHeight)
            if !compact && !zen {
                // When height limits the portrait board, every adjacent row
                // follows the same edges instead of leaving three unrelated
                // margins for clocks, identities and the board.
                let board = visible(self[.board])
                for slot in [Slot.clocks, .opponent, .actions, .preview] {
                    let frame = self[slot]
                    if !frame.isEmpty {
                        frames[slot] = rect(board.minX, frame.minY, board.width, frame.height)
                    }
                }
                // The width-bound board stays bottom-anchored. Keep its
                // clocks and opponent together instead of leaving spare
                // vertical space between these related rows.
                let clocks = self[.clocks]
                let opponent = self[.opponent]
                if !clocks.isEmpty && !opponent.isEmpty {
                    frames[.clocks] = rect(clocks.minX,
                        max(clocks.minY, opponent.minY - gap - clocks.height),
                        clocks.width, clocks.height)
                }
            }
            if zen {
                if spaciousCompactClocks {
                    let board = self[.board]
                    let drawn = visible(board)
                    frames[.actions] = rect(drawn.minX, board.maxY + 12, drawn.width, rowActionHeight)
                }
                // Zen centers the board in its scene, with clocks above and
                // actions below. Clamp the whole group to the usable region so
                // native navigation and large text never cover those controls.
                let groupBottom = max(self[.board].maxY, self[.actions].maxY)
                let minimumShift = topInset - self[.clocks].minY
                let maximumShift = max(minimumShift, height - margin - groupBottom)
                let desiredShift = (zenBoardCenterY ?? height / 2) - self[.board].midY
                let shift = min(maximumShift, max(minimumShift, desiredShift))
                for slot in [Slot.clocks, .board, .actions] {
                    frames[slot] = self[slot].offsetBy(dx: 0, dy: shift)
                }
            }
        }
        if compact && chat && !landscape && split == nil,
           !self[.chat].isEmpty {
            // The rounded portrait conversation keeps the same side inset as
            // the move tree. Set it before splitting off the composer so both
            // surfaces share one continuous edge.
            let panel = self[.chat]
            let leading = max(8, panel.minX)
            frames[.chat] = rect(leading, panel.minY,
                min(width - 8, panel.maxX) - leading, panel.height)
        }
        if chat && composerHeight > 0 && self[.composer].isEmpty && self[.chat].width > 0 {
            // The full scene stays fixed behind the keyboard: board, clocks
            // and actions keep their places and the keyboard covers what it
            // reaches. Only the panel containing the field shortens, ending
            // 8 pt above the keyboard, with the fold remaining its limit.
            let panel = self[.chat]
            let overlap = keyboard ? max(0, keyboardOverlap) : 0
            let visibleBottom = min(panel.maxY, height - overlap - (overlap > 0 ? gap : 0))
            let composerHeight = min(composerHeight, max(0, visibleBottom - panel.minY))
            let composerY = visibleBottom - composerHeight
            frames[.composer] = rect(panel.minX, composerY, panel.width, composerHeight)
            frames[.chat] = rect(panel.minX, panel.minY, panel.width, max(0, composerY - panel.minY))
        }
        if !self[.analysis].isEmpty && self[.analysisControls].isEmpty {
            let panel = self[.analysis]
            let controlHeight = min(analysisControlHeight, panel.height)
            let controlGap = min(gap, max(0, panel.height - controlHeight))
            frames[.analysisControls] = rect(panel.minX, panel.maxY - controlHeight, panel.width, controlHeight)
            frames[.analysis] = rect(panel.minX, panel.minY, panel.width, panel.height - controlHeight - controlGap)
        }
        if compact && analyze && !landscape && split == nil && !self[.analysis].isEmpty {
            // The move-tree surface has the same side padding as the other
            // compact panels; its controls and the board still use full width.
            let tree = self[.analysis]
            frames[.analysis] = rect(tree.minX + 8, tree.minY, tree.width - 16, tree.height)
        }
        if !stackedClocks && !spansInlineClocks && (clockStyle == .inline || zen) && !self[.clocks].isEmpty {
            let f = self[.clocks]
            let preferredWidth: CGFloat = spaciousCompactClocks ? 360
                : (zen && compact && !usesVerticalToolbar ? 282 : 320)
            let cw = zen ? zenChipPairWidth(base: preferredWidth, available: f.width)
                : min(f.width, preferredWidth * clockScale)
            frames[.clocks] = rect(f.midX - cw / 2, f.minY, cw, f.height)
        }
        // These decisions depend on the layout's width and the complete label
        // set, never on which action the current game happens to expose.
        if !verticalActions, !columnActionRow, !self[.actions].isEmpty {
            wrapsMainAction = showsActions && actionSize.width > self[.actions].width
            hidesActionIdentity = !showsCornerIdentity
                || self[.actions].width < (showsActions ? actionSize.width + 10 : 0) + 64
        } else {
            hidesActionIdentity = !showsCornerIdentity
        }
        if hidesIdentity { hidesActionIdentity = true }
        if preview && !previewInOpponentRow && self[.preview].isEmpty {
            let b = visible(self[.board])
            frames[.preview] = rect(b.minX, b.minY, b.width, min(previewHeight, b.height))
        }
        if zen {
            frames[.opponent] = .zero
            frames[.analysis] = .zero
            frames[.chat] = .zero
        }
        if recoveryHeight > 0 {
            // Recovery is exceptional and never participates in the ordinary
            // board budget. Use empty space above a width-bound board first;
            // otherwise keep a bounded banner over its top edge.
            let board = self[.board]
            let drawn = visible(board)
            let bannerWidth = !board.isEmpty ? drawn.width : max(0, width - margin * 2 - 16)
            let bannerX = !board.isEmpty ? drawn.minX : (width - bannerWidth) / 2
            let bannerHeight = min(max(44, recoveryHeight), !board.isEmpty ? drawn.height : height)
            let occupiedAbove = [Slot.clocks, .opponent, .analysis, .analysisControls]
                .map { self[$0] }
                .filter { !$0.isEmpty && $0.maxY <= board.minY && $0.maxX > bannerX && $0.minX < bannerX + bannerWidth }
                .sorted { $0.minY > $1.minY }
            var freeBottom = board.minY
            var availableY: CGFloat?
            for occupied in occupiedAbove {
                if freeBottom - occupied.maxY >= bannerHeight + gap * 2 {
                    availableY = freeBottom - bannerHeight - gap
                    break
                }
                freeBottom = min(freeBottom, occupied.minY)
            }
            if availableY == nil && freeBottom >= bannerHeight + gap {
                availableY = freeBottom - bannerHeight - gap
            }
            let y = availableY ?? (!board.isEmpty ? drawn.minY : 0)
            frames[.status] = rect(bannerX, y, bannerWidth, bannerHeight)
        }
        // Hidden slots have no position as well as no size. CoreGraphics can
        // report a zero-height line inside another rectangle as intersecting;
        // do not expose those obsolete positions as occupied layout geometry.
        for slot in Slot.allCases where self[slot].isEmpty {
            frames[slot] = .zero
        }
    }
}

/// The content's final layout decides whether navigation must carry the player
/// identity. Reporting that decision avoids a second, drifting size heuristic.
struct GameDetailOpponentHeaderPreferenceKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct GameDetailSlotKey: LayoutValueKey {
    static let defaultValue = GameDetailLayoutPlan.Slot.board
}


struct GameDetailLayout: Layout {
    var plan: GameDetailLayoutPlan
    /// Places the chat and composer slots; see SingleGameView's chat transition.
    var chatPlan: GameDetailLayoutPlan? = nil
    /// The board's frame is the layout's animatable value: when a panel opens
    /// or closes, the board is placed at each in-between frame and redraws at
    /// that size, so one board moves (rule 19) instead of a drawing at its new
    /// size inside a frame that is still animating.
    var boardFrame: CGRect

    init(plan: GameDetailLayoutPlan, chatPlan: GameDetailLayoutPlan? = nil) {
        self.plan = plan
        self.chatPlan = chatPlan
        self.boardFrame = plan[.board]
    }

    var animatableData: CGRect.AnimatableData {
        get { boardFrame.animatableData }
        set { boardFrame.animatableData = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for view in subviews {
            let slot = view[GameDetailSlotKey.self]
            let frame = slot == .board ? boardFrame
                : (slot == .chat || slot == .composer ? chatPlan ?? plan : plan)[slot]
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}

extension View {
    func gameDetailSlot(_ slot: GameDetailLayoutPlan.Slot, plan: GameDetailLayoutPlan) -> some View {
        let frame = plan[slot]
        // The board takes the layout's (animated) proposal; see GameDetailLayout.
        let content = slot == .board
            ? AnyView(self.frame(maxWidth: .infinity, maxHeight: .infinity))
            : AnyView(self.frame(width: frame.width, height: frame.height))
        return Group {
            if slot == .board || slot == .analysis || slot == .analysisControls || slot == .information || slot == .chat || slot == .composer || slot == .preview {
                content.clipped()
            } else {
                content
            }
        }
            .opacity(frame.isEmpty ? 0 : 1)
            .allowsHitTesting(!frame.isEmpty)
            .accessibilityHidden(frame.isEmpty)
            // A hidden slot stays mounted; its content can tell it is not shown.
            .environment(\.gameDetailSlotVisible, !frame.isEmpty)
            .layoutValue(key: GameDetailSlotKey.self, value: slot)
    }
}

private struct GameDetailSlotVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False inside a Game Detail slot the layout plan leaves empty (for
    /// example the body clocks while they sit in the title slot).
    var gameDetailSlotVisible: Bool {
        get { self[GameDetailSlotVisibleKey.self] }
        set { self[GameDetailSlotVisibleKey.self] = newValue }
    }
}
