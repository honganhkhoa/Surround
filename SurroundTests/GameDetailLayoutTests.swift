import XCTest
import SwiftUI

final class GameDetailLayoutTests: XCTestCase {
    // The logic-test target has no localization catalog. Match the visible
    // English app labels, including the catalog's short scoring action.
    private let englishActionLabels = [
        "Pass", "Submit move", "Accept", "Clear estimates", "Rematch", "Next (999+)"
    ]

    private func plan(_ size: CGSize, compact: Bool = false, zen: Bool = false,
                      analyze: Bool = false, chat: Bool = false, keyboard: Bool = false,
                      hidesBoard: Bool = false,
                      composerHeight: CGFloat = 0, keyboardOverlap: CGFloat = 0,
                      division: CGRect? = nil, panelDivision: CGRect? = nil,
                      usesVerticalToolbar: Bool = false, preview: Bool = false,
                      zenBoardCenterY: CGFloat? = nil,
                      recoveryHeight: CGFloat = 0, fullClockFooterWidth: CGFloat = 0,
                      compactClockLineWidth: CGFloat = 0,
                      narrowChipWidth: CGFloat = 0,
                      identityTwoLineRowHeight: CGFloat? = nil,
                      chromeBandTop: CGFloat? = nil,
                      boardDepth: BoardDepthPlacement? = nil) -> GameDetailLayoutPlan {
        GameDetailLayoutPlan(size: size, compact: compact, zen: zen, analyze: analyze,
                             chat: chat, hidesBoard: hidesBoard, keyboard: keyboard,
                             accessibility: false, foldsClock: false,
                             composerHeight: composerHeight, keyboardOverlap: keyboardOverlap,
                             division: division, panelDivision: panelDivision,
                             usesVerticalToolbar: usesVerticalToolbar, preview: preview,
                             zenBoardCenterY: zenBoardCenterY,
                             identityTwoLineRowHeight: identityTwoLineRowHeight,
                             recoveryHeight: recoveryHeight,
                             fullClockFooterWidth: fullClockFooterWidth,
                             compactClockLineWidth: compactClockLineWidth,
                             narrowChipWidth: narrowChipWidth,
                             chromeBandTop: chromeBandTop,
                             boardDepth: boardDepth)
    }

    func testZenChipsGrowToTheirLongestCountdownWithinTheRow() {
        // iPhone 15 Pro portrait: a 30-day clock with komi needs 178 pt cards.
        let size = CGSize(width: 393, height: 700)
        let short = plan(size, compact: true, zen: true)
        XCTAssertEqual(short[.clocks].width, 282, accuracy: 0.5, "Short times keep the familiar pair.")
        let long = plan(size, compact: true, zen: true, narrowChipWidth: 178)
        XCTAssertEqual(long[.clocks].width, 178 * 2 + 8, accuracy: 0.5)
        XCTAssertEqual(long[.clocks].midX, size.width / 2, accuracy: 0.5)
        XCTAssertEqual(long[.board], short[.board], "Wider chips never move the board.")
        let tooLong = plan(size, compact: true, zen: true, narrowChipWidth: 260)
        XCTAssertLessThanOrEqual(tooLong[.clocks].width, size.width - 16 + 0.5)
    }

    func testShortColumnsReserveTwoNameLinesWithoutMovingTheBoard() {
        // iPhone SE and iPhone 15 Pro landscape.
        for size in [CGSize(width: 667, height: 375), CGSize(width: 734, height: 372)] {
            let oneLine = plan(size, compact: true)
            let twoLines = plan(size, compact: true, identityTwoLineRowHeight: 69)
            XCTAssertFalse(oneLine.wrapsColumnNames)
            XCTAssertTrue(twoLines.wrapsColumnNames, "\(size)")
            XCTAssertEqual(twoLines[.opponent].height, 69, accuracy: 0.5)
            XCTAssertEqual(twoLines[.board], oneLine[.board], "\(size): names never move the board")
            XCTAssertLessThanOrEqual(twoLines[.actions].maxY, size.height)
        }
        // Zen hides the chips; it reserves nothing for them.
        XCTAssertFalse(plan(CGSize(width: 667, height: 375), compact: true, zen: true,
                            identityTwoLineRowHeight: 69).wrapsColumnNames)
    }

    func testLandscapeZenClockColumnGrowsOnlyIntoFreeSpace() {
        // iPhone 15 Pro landscape inside its safe areas.
        let size = CGSize(width: 734, height: 372)
        let short = plan(size, compact: true, zen: true)
        let long = plan(size, compact: true, zen: true, narrowChipWidth: 178)
        XCTAssertEqual(long[.board], short[.board], "The board stays put.")
        XCTAssertEqual(long[.clocks].maxX, short[.clocks].maxX, accuracy: 0.5, "The column keeps its board edge.")
        XCTAssertGreaterThan(long[.clocks].width, short[.clocks].width)
        XCTAssertGreaterThanOrEqual(long[.clocks].minX, 8 - 0.5, "Never past the margin.")
        XCTAssertLessThanOrEqual(long[.clocks].width, 178 + 0.5)
    }

    func testBottomEdgeExtensionAllowsPhoneAndClosedDuoLandscape() {
        for size in [CGSize(width: 874, height: 402), CGSize(width: 678, height: 466)] {
            XCTAssertTrue(GameDetailBottomEdgePolicy.extendsContent(
                isPhone: true, compact: true, windowSize: size,
                hasDisplayDivision: false, keyboardVisible: false
            ))
        }
    }

    func testOrdinaryLayoutsLeaveTheRecoveryStatusSlotEmpty() {
        for (size, compact) in [(CGSize(width: 390, height: 740), true),
                                (CGSize(width: 742, height: 324), true),
                                (CGSize(width: 820, height: 1074), false),
                                (CGSize(width: 880, height: 714), false),
                                (CGSize(width: 1180, height: 714), false)] {
            for zen in [false, true] {
                let p = plan(size, compact: compact, zen: zen)
                XCTAssertTrue(p[.status].isEmpty)
            }
        }
    }

    func testNarrowCompactClocksReserveTheSameThirdLineForBothPlayers() {
        for (size, compact, vertical) in [(CGSize(width: 678, height: 466), true, false),
                                         (CGSize(width: 390, height: 740), true, false),
                                         (CGSize(width: 867, height: 611), false, true)] {
            let p = plan(size, compact: compact, zen: true, usesVerticalToolbar: vertical)
            XCTAssertTrue(p.narrowCompactClocks)
            let cardHeight: CGFloat = p.spaciousCompactClocks ? 76 : 68
            XCTAssertEqual(p[.clocks].height, p.stackedClocks ? cardHeight * 2 + 8 : cardHeight)
            XCTAssertFalse(p[.clocks].intersects(p[.board]))
            assertOccupiedSlotsFit(p, in: size)
        }
    }

    func testLargerTextCompactClocksReserveTheBadgeRowWithoutLosingAccessibilityHeight() {
        for accessibility in [false, true] {
            let p = GameDetailLayoutPlan(size: CGSize(width: 390, height: 740),
                compact: true, zen: false, analyze: false, chat: false,
                hidesBoard: false, keyboard: false, accessibility: accessibility,
                foldsClock: true, clockScale: 1.3)
            XCTAssertEqual(p.clockStyle, .compact)
            XCTAssertGreaterThan((p[.clocks].width - 8) / 2, 145)
            XCTAssertTrue(p.narrowCompactClocks)
            XCTAssertEqual(p[.clocks].height, (accessibility ? 76 : 68) * 1.3)
            XCTAssertFalse(p[.clocks].intersects(p[.board]))
            assertOccupiedSlotsFit(p, in: CGSize(width: 390, height: 740))
        }
    }

    func testCorrespondenceZenClocksReserveBadgeRowsWithoutShrinkingOrdinaryFoldedLayouts() {
        // Closed Duo Zen reclaims the toolbar's width but keeps its native
        // corner toolbar treatment. Its 156pt cards must fit 10h 47m and status.
        let duoSize = CGSize(width: 466, height: 678)
        let duo = plan(duoSize, compact: true, zen: true, usesVerticalToolbar: true)
        XCTAssertEqual((duo[.clocks].width - 8) / 2, 156)
        XCTAssertTrue(duo.narrowCompactClocks)
        XCTAssertEqual(duo[.clocks].height, 68)
        XCTAssertEqual(duo[.board].width, 466)
        XCTAssertFalse(duo[.clocks].intersects(duo[.board]))
        assertOccupiedSlotsFit(duo, in: duoSize)

        let foldedSize = CGSize(width: 390, height: 740)
        let folded = GameDetailLayoutPlan(size: foldedSize,
            compact: true, zen: false, analyze: false, chat: false,
            hidesBoard: false, keyboard: false, accessibility: false, foldsClock: true)
        XCTAssertEqual((folded[.clocks].width - 8) / 2, 183)
        XCTAssertFalse(folded.narrowCompactClocks)
        XCTAssertEqual(folded[.clocks].height, 50)
        XCTAssertEqual(folded[.board].width, foldedSize.width)
        assertOccupiedSlotsFit(folded, in: foldedSize)
    }

    func testCompactZenBadgeRowsScaleWithoutChangingOrdinaryFoldedClocks() {
        let size = CGSize(width: 440, height: 820)
        for scale: CGFloat in [1, 1.1] {
            let p = GameDetailLayoutPlan(size: size,
                compact: true, zen: false, analyze: false, chat: false,
                hidesBoard: false, keyboard: false, accessibility: false,
                foldsClock: true, clockScale: scale)
            XCTAssertEqual((p[.clocks].width - 8) / 2, 208)
            XCTAssertFalse(p.narrowCompactClocks)
            XCTAssertEqual(p[.clocks].height, 50 * scale)
            XCTAssertEqual(p[.board].width, size.width)
            assertOccupiedSlotsFit(p, in: size)

            let zen = GameDetailLayoutPlan(size: size,
                compact: true, zen: true, analyze: false, chat: false,
                hidesBoard: false, keyboard: false, accessibility: false,
                foldsClock: false, clockScale: scale, usesVerticalToolbar: true)
            XCTAssertTrue(zen.narrowCompactClocks)
            XCTAssertEqual(zen[.clocks].height, 68 * scale)
            XCTAssertEqual(zen[.board].width, size.width)
            assertOccupiedSlotsFit(zen, in: size)
        }
    }

    func testPortraitChatHistoryAndComposerShareEightPointSideInsets() {
        let size = CGSize(width: 390, height: 740)
        for hidden in [false, true] {
            let p = plan(size, compact: true, chat: true,
                hidesBoard: hidden, composerHeight: 52)
            for slot in [GameDetailLayoutPlan.Slot.chat, .composer] {
                XCTAssertEqual(p[slot].minX, 8)
                XCTAssertEqual(p[slot].width, 374)
            }
            XCTAssertEqual(p[.chat].maxY, p[.composer].minY)
            if hidden {
                XCTAssertTrue(p[.board].isEmpty)
            } else {
                XCTAssertGreaterThan(p[.board].width, 0)
                XCTAssertLessThan(p[.board].width, size.width)
                XCTAssertLessThanOrEqual(p[.board].maxX, p[.actions].minX)
                XCTAssertLessThanOrEqual(p[.composer].maxY, p[.board].minY)
            }
            assertOccupiedSlotsFit(p, in: size)
        }
    }

    func testRecoveryUsesVacantPortraitSpaceWithoutChangingGameGeometry() {
        let size = CGSize(width: 820, height: 1200)
        let normal = plan(size)
        let recovery = plan(size, recoveryHeight: 44)
        XCTAssertEqual(recovery[.board], normal[.board])
        XCTAssertEqual(recovery[.clocks], normal[.clocks])
        XCTAssertEqual(recovery[.actions], normal[.actions])
        XCTAssertEqual(recovery[.status].height, 44)
        XCTAssertLessThan(recovery[.status].maxY, recovery[.board].minY)
        for slot in [GameDetailLayoutPlan.Slot.clocks, .opponent, .board] {
            XCTAssertFalse(recovery[.status].intersects(recovery[slot]))
        }
        assertOccupiedSlotsFit(recovery, in: size)
    }

    func testRecoveryOverlaysHeightBoundBoardWithoutShrinkingIt() {
        let size = CGSize(width: 1180, height: 714)
        let normal = plan(size)
        let recovery = plan(size, recoveryHeight: 44)
        XCTAssertEqual(recovery[.board], normal[.board])
        XCTAssertEqual(recovery[.clocks], normal[.clocks])
        XCTAssertEqual(recovery[.actions], normal[.actions])
        XCTAssertEqual(recovery[.status].minY, recovery[.board].minY)
        XCTAssertEqual(recovery[.status].width, recovery[.board].width)
        XCTAssertTrue(recovery[.board].contains(recovery[.status]))
    }

    func testBottomEdgeExtensionPreservesPortraitIPadAndDuoPanelInsets() {
        let landscape = CGSize(width: 874, height: 402)
        let excluded: [(String, Bool, Bool, CGSize?, Bool)] = [
            ("portrait phone, including its keyboard-shortened viewport", true, true,
             CGSize(width: 402, height: 874), false),
            ("narrow iPad landscape", false, true, landscape, false),
            ("regular Duo Open", true, false, landscape, false),
            ("Duo Book or inactive Open division", true, true, landscape, true),
            ("window geometry not measured yet", true, true, nil, false),
            ("transient empty window", true, true, .zero, false)
        ]
        for (pose, isPhone, compact, windowSize, hasDivision) in excluded {
            XCTAssertFalse(GameDetailBottomEdgePolicy.extendsContent(
                isPhone: isPhone, compact: compact, windowSize: windowSize,
                hasDisplayDivision: hasDivision, keyboardVisible: false
            ), pose)
        }
    }

    func testLandscapeKeyboardRestoresBottomGestureAndContainerAvoidance() {
        for size in [CGSize(width: 874, height: 402), CGSize(width: 678, height: 466)] {
            XCTAssertFalse(GameDetailBottomEdgePolicy.extendsContent(
                isPhone: true, compact: true, windowSize: size,
                hasDisplayDivision: false, keyboardVisible: true
            ))
        }
    }

    func testReclaimedLandscapeHeightBenefitsOnlyHeightLimitedBoards() {
        let phoneBefore = plan(CGSize(width: 742, height: 304), compact: true)
        let phoneAfter = plan(CGSize(width: 742, height: 324), compact: true)
        XCTAssertEqual(phoneBefore[.board].width, 288)
        XCTAssertEqual(phoneAfter[.board].width, 308)

        let duoSize = CGSize(width: 594, height: 432)
        let duoExpanded = CGSize(width: 594, height: 466)
        let playBefore = plan(duoSize, compact: true, usesVerticalToolbar: true)
        let playAfter = plan(duoExpanded, compact: true, usesVerticalToolbar: true)
        // v146: Duo Closed landscape's single column leaves a height-bound
        // board, so the reclaimed home-indicator height goes to the board.
        XCTAssertEqual(playBefore[.board].width, 402)
        XCTAssertEqual(playAfter[.board].width, 436)
        let analyzeBefore = plan(duoSize, compact: true, analyze: true, usesVerticalToolbar: true)
        let analyzeAfter = plan(duoExpanded, compact: true, analyze: true, usesVerticalToolbar: true)
        // Once the 224pt tree column is reserved, this board is width-bound.
        // Reclaimed home-indicator space centers the same board/control group.
        XCTAssertEqual(analyzeBefore[.board].width, 346)
        XCTAssertEqual(analyzeAfter[.board].width, 346)
        XCTAssertLessThanOrEqual(analyzeAfter[.analysisControls].maxY, duoExpanded.height)
    }

    func testCompactPortraitBoardUsesAvailableWidthAndDiagonalRows() {
        let p = plan(CGSize(width: 390, height: 740), compact: true)
        XCTAssertEqual(p[.board].width, 390)
        XCTAssertEqual(p[.clocks].minY, 8)
        XCTAssertEqual(p[.board].width, p[.board].height)
        XCTAssertLessThanOrEqual(p[.opponent].maxY, p[.board].minY)
        XCTAssertGreaterThanOrEqual(p[.actions].minY, p[.board].maxY)
        XCTAssertTrue(p[.status].isEmpty)
        XCTAssertFalse(p.hidesOpponentIdentity)
    }

    func testTwoLineChipsPutTheBadgeOnItsOwnRowWhenTheLineDoesNotFit() {
        // Rule 12 (iPhone SE): the badge never truncates and both chips keep
        // one time size. When time, badge and komi need more than a chip's
        // width, both chips put the badge on its own row.
        let size = CGSize(width: 375, height: 540)
        let roomy = plan(size, compact: true)
        XCTAssertEqual(roomy.clockStyle, .compact)
        XCTAssertFalse(roomy.narrowCompactClocks)
        let measured = plan(size, compact: true, compactClockLineWidth: 234)
        XCTAssertEqual(measured.clockStyle, .compact)
        XCTAssertTrue(measured.narrowCompactClocks)
        XCTAssertGreaterThan(measured[.clocks].height, roomy[.clocks].height)
        assertOccupiedSlotsFit(measured, in: size)
    }

    func testShortPhoneFoldsBothClocksBeforeShrinkingBoard() {
        let p = plan(CGSize(width: 375, height: 540), compact: true)
        XCTAssertEqual(p.clockStyle, .compact)
        XCTAssertEqual(p[.board].width, p[.board].height)
        XCTAssertEqual(p[.board].width, 375)
        XCTAssertTrue(p.hidesOpponentIdentity)
        XCTAssertTrue(p[.opponent].isEmpty)
        XCTAssertFalse(p.hidesActionIdentity)
        XCTAssertLessThanOrEqual(p[.actions].maxY, 540)
    }

    func testLandscapeKeepsBothClocksInOneColumn() {
        let p = plan(CGSize(width: 780, height: 350), compact: true)
        XCTAssertTrue(p.stackedClocks)
        XCTAssertLessThan(p[.clocks].maxX, p[.board].minX)
        XCTAssertTrue(p[.status].isEmpty)
        XCTAssertGreaterThan(p[.actions].minX, p[.board].maxX)
        XCTAssertFalse(p.hidesOpponentIdentity)
    }

    func testPhoneLandscapeKeepsFullClocksAndMatchingHorizontalIdentities() {
        let size = CGSize(width: 742, height: 324)
        let p = plan(size, compact: true)
        XCTAssertEqual(p.clockStyle, .full)
        XCTAssertEqual(p[.clocks].height, 96 * 2 + 8)
        XCTAssertEqual(p[.clocks].width, 196)
        XCTAssertFalse(p.verticalOpponentIdentity)
        XCTAssertEqual(p[.opponent].height, 52)
        XCTAssertEqual(p[.board].width, 308)
        XCTAssertLessThanOrEqual(p[.actions].maxY, p[.board].maxY)
        assertOccupiedSlotsFit(p, in: size)
    }

    func testHeightLimitedPhoneLandscapeKeepsTwelvePointBoardGutters() {
        for size in [CGSize(width: 742, height: 324), CGSize(width: 780, height: 350)] {
            let p = plan(size, compact: true)
            XCTAssertEqual(p[.board].minX - p[.clocks].maxX, 12,
                           "Surplus width must not open a gap beside the clock column")
            XCTAssertEqual(p[.actions].minX - p[.board].maxX, 12)
            XCTAssertEqual(p[.board].width, size.height - 16)
            assertOccupiedSlotsFit(p, in: size)
        }
    }

    func testDuoClosedLandscapeFoldsIntoOneColumnBesideAFullHeightBoard() {
        // Canvas v146 DuoClosedLandscape: one 126 pt column at x 12 from y 15
        // to 451; the board is 436 at (150, 15), 12 pt from the column and
        // 8 pt from the toolbar. The opponent and the clocks at the top, the
        // action row and you at the bottom.
        let size = CGSize(width: 594, height: 466)
        let p = plan(size, compact: true, usesVerticalToolbar: true)
        XCTAssertEqual(p[.board], CGRect(x: 150, y: 15, width: 436, height: 436))
        XCTAssertEqual(p.clockStyle, .full)
        XCTAssertTrue(p.columnClockCards)
        XCTAssertTrue(p.columnActionRow)
        XCTAssertTrue(p.compactColumnIdentity)
        XCTAssertTrue(p.stackedClocks)
        for slot in [GameDetailLayoutPlan.Slot.opponent, .clocks, .actions] {
            XCTAssertEqual(p[slot].minX, 12, "\(slot)")
            XCTAssertEqual(p[slot].width, 126, "\(slot)")
        }
        XCTAssertEqual(p[.opponent].minY, 15)
        XCTAssertEqual(p[.clocks].minY, p[.opponent].maxY + 8)
        XCTAssertEqual(p[.clocks].height, 91 * 2 + 8)
        XCTAssertEqual(p[.actions].maxY, 451)
        XCTAssertLessThan(p[.clocks].maxY, p[.actions].minY)
        XCTAssertTrue(p[.status].isEmpty)
        assertOccupiedSlotsFit(p, in: size)

        // Chat and Analyze keep their short columns: the board steps down to
        // 356 pt beside the panel and returns to 436 pt when it closes.
        let chat = plan(size, compact: true, chat: true, composerHeight: 50, usesVerticalToolbar: true)
        XCTAssertEqual(chat[.board], CGRect(x: 230, y: 55, width: 356, height: 356))
        XCTAssertFalse(chat.columnClockCards)
    }

    /// v149, canvas "German · Duo Closed, landscape": when White's card line
    /// wraps, both cards grow by one line (91 → 105 pt) and both column chips
    /// drop their rank line, in the same pass; the board does not move. A
    /// wrap on Black's card alone fits its spare line and changes nothing.
    /// With ranks hidden the chips are always the short form.
    func testDuoClosedLandscapeColumnWrapGrowsCardsAndDropsTheChipsRankLine() {
        let size = CGSize(width: 594, height: 466)
        func columnPlan(_ detail: GameDetailColumnDetailLayouts, chip: CGFloat = 83,
                        shortChip: CGFloat = 66) -> GameDetailLayoutPlan {
            GameDetailLayoutPlan(size: size, compact: true, zen: false, analyze: false, chat: false,
                                 hidesBoard: false, keyboard: false, accessibility: false, foldsClock: false,
                                 usesVerticalToolbar: true, compactColumnIdentityHeight: chip,
                                 compactColumnIdentityShortHeight: shortChip, columnDetail: detail)
        }
        let english = columnPlan(.init())
        XCTAssertEqual(english[.board], CGRect(x: 150, y: 15, width: 436, height: 436))
        XCTAssertEqual(english[.opponent].height, 83)
        XCTAssertEqual(english[.clocks].height, 91 * 2 + 8)
        XCTAssertFalse(english.columnCardsGrow)
        XCTAssertFalse(english.compactColumnIdentityDropsSecondLine)

        var german = GameDetailColumnDetailLayouts()
        german.black = .splitAtSeparator
        german.white = .splitAtSeparator
        german.needsGrowth = true
        let wrapped = columnPlan(german)
        XCTAssertEqual(wrapped[.board], english[.board], "The board does not move")
        XCTAssertTrue(wrapped.columnClockCards)
        XCTAssertTrue(wrapped.columnCardsGrow)
        XCTAssertTrue(wrapped.compactColumnIdentityDropsSecondLine)
        XCTAssertEqual(wrapped.columnDetailLayouts, german)
        XCTAssertEqual(wrapped[.opponent], CGRect(x: 12, y: 15, width: 126, height: 66))
        XCTAssertEqual(wrapped[.clocks], CGRect(x: 12, y: 89, width: 126, height: 105 * 2 + 8))
        XCTAssertEqual(wrapped[.actions], CGRect(x: 12, y: 333, width: 126, height: 44 + 8 + 66))
        XCTAssertLessThanOrEqual(wrapped[.clocks].maxY + 8, wrapped[.actions].minY)
        assertOccupiedSlotsFit(wrapped, in: size)

        var blackOnly = GameDetailColumnDetailLayouts()
        blackOnly.black = .splitAtSeparator
        let spare = columnPlan(blackOnly)
        XCTAssertFalse(spare.columnCardsGrow)
        XCTAssertFalse(spare.compactColumnIdentityDropsSecondLine)
        XCTAssertEqual(spare.columnDetailLayouts.black, .splitAtSeparator)
        XCTAssertEqual(spare[.clocks], english[.clocks])

        // Hidden ranks: the chips are already the short form, so the cards
        // can grow with no further change.
        let hidden = columnPlan(.init(), chip: 66)
        XCTAssertEqual(hidden[.opponent].height, 66)
        XCTAssertEqual(hidden[.clocks].height, 91 * 2 + 8)
        let hiddenWrapped = columnPlan(german, chip: 66)
        XCTAssertTrue(hiddenWrapped.columnCardsGrow)
        XCTAssertFalse(hiddenWrapped.compactColumnIdentityDropsSecondLine)
        XCTAssertEqual(hiddenWrapped[.clocks], wrapped[.clocks])

        // Zen's two-line chips grow by one 11 pt line when one wraps.
        let zenPlan = GameDetailLayoutPlan(size: CGSize(width: 678, height: 466), compact: true, zen: true,
                                           analyze: false, chat: false, hidesBoard: false, keyboard: false,
                                           accessibility: false, foldsClock: false, usesVerticalToolbar: true,
                                           compactColumnDetail: german)
        XCTAssertEqual(zenPlan.clockStyle, .compact)
        XCTAssertTrue(zenPlan.columnCardsGrow)
        XCTAssertEqual(zenPlan[.clocks].height, (68 + 14) * 2 + 8)
        XCTAssertEqual(zenPlan[.board], CGRect(x: 150, y: 8, width: 450, height: 450))
    }

    func testDuoClosedLandscapeZenUsesTheSameColumnAndA450Board() {
        // Canvas v146 ZenDuoClosedLandscape (678 × 466, no toolbar inset):
        // board 450 at (150, 8); two-line chips at the top of the 126 pt
        // column, Pass and More at its bottom.
        let size = CGSize(width: 678, height: 466)
        let p = plan(size, compact: true, zen: true, usesVerticalToolbar: true)
        XCTAssertEqual(p[.board], CGRect(x: 150, y: 8, width: 450, height: 450))
        XCTAssertEqual(p.clockStyle, .compact)
        XCTAssertTrue(p.narrowCompactClocks)
        XCTAssertEqual(p[.clocks].minX, 12)
        XCTAssertEqual(p[.clocks].width, 126)
        XCTAssertEqual(p[.clocks].minY, 8)
        XCTAssertEqual(p[.actions].minX, 12)
        XCTAssertEqual(p[.actions].width, 126)
        XCTAssertEqual(p[.actions].maxY, 458)
        XCTAssertTrue(p[.opponent].isEmpty)
        assertOccupiedSlotsFit(p, in: size)
    }

    func testPortraitZenCentersBoardWithoutReducingItsSize() {
        for (size, compact, verticalToolbar) in [
            (CGSize(width: 390, height: 740), true, false),
            (CGSize(width: 382, height: 644), true, true),
            (CGSize(width: 820, height: 1080), false, false)
        ] {
            let p = plan(size, compact: compact, zen: true, usesVerticalToolbar: verticalToolbar)
            XCTAssertEqual(p[.board].width, size.width - (compact ? 0 : 48))
            XCTAssertEqual(p[.board].midY, size.height / 2)
            XCTAssertTrue(p[.status].isEmpty)
            XCTAssertLessThanOrEqual(p[.board].maxY, p[.actions].minY)
            assertOccupiedSlotsFit(p, in: size)
        }
    }

    func testPortraitZenUsesSceneCenterAndClampsControlsInsideContent() {
        let size = CGSize(width: 402, height: 740)
        let centered = plan(size, compact: true, zen: true, zenBoardCenterY: 390)
        XCTAssertEqual(centered[.board].midY, 390)
        XCTAssertEqual(centered[.board].width, 402)
        let upperBound = plan(size, compact: true, zen: true, zenBoardCenterY: 0)
        XCTAssertEqual(upperBound[.clocks].minY, 8)
        let lowerBound = plan(size, compact: true, zen: true, zenBoardCenterY: size.height)
        XCTAssertEqual(lowerBound[.actions].maxY, size.height)
        for p in [centered, upperBound, lowerBound] { assertOccupiedSlotsFit(p, in: size) }
    }

    func testShortLandscapeContentKeepsClocksInsideAvailableBody() {
        // A reduced content viewport must still fit its fixed controls.
        // Normal landscape no longer reserves a bottom mode toolbar.
        let size = CGSize(width: 780, height: 244)
        let p = plan(size, compact: true)
        XCTAssertTrue(p.stackedClocks)
        XCTAssertEqual(p.clockStyle, .compact)
        XCTAssertFalse(p.verticalOpponentIdentity)
        XCTAssertEqual(p[.opponent].height, 52)
        XCTAssertEqual(p[.board].width, size.height - 16)
        XCTAssertLessThanOrEqual(p[.opponent].maxY, p[.clocks].minY)
        XCTAssertTrue(p[.status].isEmpty)
        for slot in [GameDetailLayoutPlan.Slot.board, .opponent, .clocks, .actions] {
            XCTAssertTrue(CGRect(origin: .zero, size: size).contains(p[slot]), "\(slot): \(p[slot])")
        }
    }

    func testLargeTextMovesCompactOpponentToHeaderEvenWhenHeightIsAvailable() {
        let p = GameDetailLayoutPlan(
            size: CGSize(width: 390, height: 900), compact: true, zen: false,
            analyze: false, chat: false, hidesBoard: false, keyboard: false,
            accessibility: false, foldsClock: true, clockScale: 1.35
        )
        XCTAssertEqual(p.clockStyle, .compact)
        XCTAssertTrue(p.hidesOpponentIdentity)
        XCTAssertTrue(p[.opponent].isEmpty)
        XCTAssertEqual(p[.board].width, 390)
    }

    func testCompactPanelsAndZenDoNotRequestOpponentNavigationHeader() {
        let size = CGSize(width: 375, height: 560)
        for p in [plan(size, compact: true, analyze: true),
                  plan(size, compact: true, chat: true),
                  plan(size, compact: true, zen: true)] {
            XCTAssertFalse(p.hidesOpponentIdentity)
        }
    }

    func testCompactLandscapeZenCentersBoardWithoutReducingItsHeight() {
        for size in [CGSize(width: 742, height: 324), CGSize(width: 780, height: 350),
                     CGSize(width: 750, height: 402)] {
            let p = plan(size, compact: true, zen: true)
            XCTAssertEqual(p[.board].midX, size.width / 2)
            XCTAssertEqual(p[.board].width, size.height - 16)
            XCTAssertEqual(p[.clocks].width, 132)
            XCTAssertTrue(p[.status].isEmpty)
            XCTAssertEqual(p[.board].minX - p[.clocks].maxX, 8)
            XCTAssertEqual(p[.actions].minX - p[.board].maxX, 8)
            XCTAssertFalse(p[.board].intersects(p[.clocks]))
            XCTAssertFalse(p[.board].intersects(p[.actions]))
            assertOccupiedSlotsFit(p, in: size)
        }
    }

    func testCompactHorizontalZenUsesReclaimedDuoWidthForCenteredBoard() {
        let size = CGSize(width: 678, height: 466)
        let p = plan(size, compact: true, zen: true)
        XCTAssertEqual(p[.board].width, 382)
        XCTAssertEqual(p[.board].midX, size.width / 2)
        XCTAssertEqual(p[.clocks].width, 132)
        XCTAssertEqual(p[.board].minX - p[.clocks].maxX, 8)
        XCTAssertEqual(p[.actions].minX - p[.board].maxX, 8)
        XCTAssertEqual(p[.actions].width, 132)
        assertOccupiedSlotsFit(p, in: size)
    }

    func testCompactPortraitZenClockPairUsesPhoneWidthOnly() {
        let phone = plan(CGSize(width: 390, height: 740), compact: true, zen: true)
        XCTAssertEqual(phone[.clocks].width, 282)
        XCTAssertEqual(phone[.clocks].midX, 195)
        let ipad = plan(CGSize(width: 820, height: 1080), zen: true)
        XCTAssertEqual(ipad[.clocks].width, 360)
        let duo = plan(CGSize(width: 382, height: 644), compact: true, zen: true,
                       usesVerticalToolbar: true)
        XCTAssertEqual(duo[.clocks].width, 320)
    }

    func testCompactPortraitAnalysisInsetsTreeWithoutShrinkingBoardOrControls() {
        for (size, verticalToolbar) in [(CGSize(width: 390, height: 740), false),
                                        (CGSize(width: 382, height: 644), true)] {
            let p = plan(size, compact: true, analyze: true, usesVerticalToolbar: verticalToolbar)
            XCTAssertEqual(p[.analysis].minX, 8)
            XCTAssertEqual(p[.analysis].maxX, size.width - 8)
            XCTAssertEqual(p[.analysisControls].minX, 0)
            XCTAssertEqual(p[.analysisControls].width, size.width)
            XCTAssertEqual(p[.board].maxY, size.height)
            XCTAssertGreaterThanOrEqual(p[.analysis].height, 190)
            assertOccupiedSlotsFit(p, in: size)
        }
    }

    func testPhoneLandscapeUsesSurplusWidthForActionsAboveIdentity() {
        let size = CGSize(width: 750, height: 312)
        let p = plan(size, compact: true)
        XCTAssertTrue(p.verticalActions, "The identity stays below the controls")
        XCTAssertTrue(p.horizontalActionsInColumn)
        XCTAssertFalse(p.verticalOpponentIdentity)
        XCTAssertEqual(p[.board], CGRect(x: 216, y: 8, width: 296, height: 296))
        XCTAssertEqual(p[.actions].minX - p[.board].maxX, 12)
        XCTAssertEqual(p[.actions].maxX, size.width - 8)
        XCTAssertEqual(p[.actions].maxY, p[.board].maxY)
        XCTAssertEqual(p[.actions].height, 48 + 8 + 52)
        XCTAssertFalse(p.hidesActionIdentity)
        assertOccupiedSlotsFit(p, in: size)

        let narrow = plan(CGSize(width: 660, height: 312), compact: true)
        XCTAssertFalse(narrow.horizontalActionsInColumn)
        XCTAssertEqual(narrow[.board].width, p[.board].width)
        let accessibility = GameDetailLayoutPlan(size: size, compact: true, zen: false,
            analyze: false, chat: false, hidesBoard: false, keyboard: false,
            accessibility: true, foldsClock: true)
        XCTAssertFalse(accessibility.horizontalActionsInColumn)
        XCTAssertFalse(plan(size, compact: true, zen: true).horizontalActionsInColumn)
        XCTAssertFalse(plan(size, compact: true, usesVerticalToolbar: true).horizontalActionsInColumn)
    }

    func testBookBoardAvoidsVerticalAndHorizontalDivision() {
        for (size, division) in [
            (CGSize(width: 1100, height: 730), CGRect(x: 540, y: 0, width: 20, height: 730)),
            (CGSize(width: 730, height: 1100), CGRect(x: 0, y: 540, width: 730, height: 20))
        ] {
            for chat in [false, true] {
                let p = plan(size, chat: chat, division: division)
                XCTAssertFalse(p[.board].intersects(division))
                XCTAssertEqual(p[.board].width, p[.board].height)
                XCTAssertTrue(CGRect(origin: .zero, size: size).contains(p[.board]))
            }
        }
    }

    func testCompactPortraitAnalyzeDoesNotReserveAnEmptyActionFooter() {
        for size in [CGSize(width: 390, height: 740), CGSize(width: 320, height: 480)] {
            let p = plan(size, compact: true, analyze: true)
            XCTAssertTrue(p[.actions].isEmpty)
            XCTAssertEqual(p[.board].maxY, size.height)
            XCTAssertLessThanOrEqual(p[.clocks].maxY, p[.board].minY)
        }
    }

    func testBookTallAnchorsBoardAndVisibleActionsAtBottomMargin() {
        let size = CGSize(width: 730, height: 1400)
        let division = CGRect(x: 0, y: 440, width: 730, height: 20)
        for analyze in [false, true] {
            let p = plan(size, analyze: analyze, division: division)
            XCTAssertFalse(p[.board].intersects(division))
            XCTAssertGreaterThanOrEqual(p[.board].maxY, size.height - 16)
            XCTAssertLessThanOrEqual(p[.board].maxY, size.height)
            XCTAssertEqual(p[.actions].maxY, p[.board].maxY)
            XCTAssertFalse(p.hidesActionIdentity)
            XCTAssertTrue(p.verticalActions)
            XCTAssertLessThanOrEqual(p[.board].maxX, p[.actions].minX)
            XCTAssertLessThanOrEqual(p[.opponent].maxX, p[.board].minX)
            if analyze {
                XCTAssertEqual(p[.actions].height, 112)
                XCTAssertEqual(p[.opponent].height, 112)
                XCTAssertTrue(p.verticalOpponentIdentity)
                XCTAssertLessThanOrEqual(p[.board].maxX, p[.actions].minX)
                XCTAssertLessThanOrEqual(p[.opponent].maxX, p[.board].minX)
            }
        }
    }

    func testZenSuppressesPanelsWithoutChangingTheirIntentInput() {
        let p = plan(CGSize(width: 1024, height: 740), zen: true, analyze: true, chat: true)
        XCTAssertTrue(p[.chat].isEmpty)
        XCTAssertTrue(p[.analysis].isEmpty)
        XCTAssertTrue(p[.opponent].isEmpty)
        XCTAssertEqual(p.clockStyle, .compact)
    }

    func testCompactLandscapeTypingKeepsTheBoardAndEndsChatAboveTheKeyboard() {
        // v145: typing never hides the board. Board, clocks and actions stay;
        // the keyboard covers what it reaches, and the conversation ends 8 pt
        // above it (iPhone landscape: chat to y 173 with the keyboard at 181).
        for (size, verticalToolbar, overlap) in [
            (CGSize(width: 780, height: 350), false, CGFloat(140)),
            (CGSize(width: 594, height: 466), true, CGFloat(150))
        ] {
            for composerHeight in [CGFloat(50), CGFloat(188)] {
                let resting = plan(size, compact: true, chat: true,
                                   composerHeight: composerHeight,
                                   usesVerticalToolbar: verticalToolbar)
                let typing = plan(size, compact: true, chat: true, keyboard: true,
                                  composerHeight: composerHeight,
                                  keyboardOverlap: overlap, usesVerticalToolbar: verticalToolbar)
                XCTAssertFalse(resting[.board].isEmpty)
                XCTAssertEqual(typing[.board], resting[.board])
                XCTAssertEqual(typing[.actions], resting[.actions])
                assertClockPresentation(typing, equals: resting)
                XCTAssertEqual(typing[.composer].minX, resting[.composer].minX)
                XCTAssertEqual(typing[.composer].width, resting[.composer].width)
                XCTAssertEqual(typing[.composer].maxY,
                               min(resting[.composer].maxY, size.height - overlap - 8))
                if typing[.chat].isEmpty {
                    // A tall composer under a tall keyboard takes the whole
                    // panel; it never grows above the conversation's top.
                    XCTAssertEqual(typing[.composer].minY, resting[.chat].minY)
                } else {
                    XCTAssertEqual(typing[.chat].minX, resting[.chat].minX)
                    XCTAssertEqual(typing[.chat].width, resting[.chat].width)
                    XCTAssertEqual(typing[.chat].maxY, typing[.composer].minY)
                }
                assertOccupiedSlotsFit(typing, in: size)
            }
        }
    }

    func testCompactPortraitKeyboardPreservesPhoneAndClosedDuoScene() {
        for (size, verticalToolbar) in [(CGSize(width: 390, height: 740), false),
                                        (CGSize(width: 382, height: 644), true)] {
            for composerHeight in [CGFloat(50), CGFloat(188)] {
                let resting = plan(size, compact: true, chat: true,
                                   composerHeight: composerHeight,
                                   usesVerticalToolbar: verticalToolbar)
                let typing = plan(size, compact: true, chat: true, keyboard: true,
                                  composerHeight: composerHeight,
                                  keyboardOverlap: 300, usesVerticalToolbar: verticalToolbar)
                XCTAssertFalse(resting[.board].isEmpty)
                assertSceneOutsideChat(typing, equals: resting)
                XCTAssertEqual(typing[.composer].height, composerHeight)
                XCTAssertLessThanOrEqual(typing[.composer].maxY, size.height - 300)
                XCTAssertEqual(typing[.chat].maxY, typing[.composer].minY)
                assertOccupiedSlotsFit(typing, in: size)
            }
        }
    }

    func testNarrowPortraitKeyboardDoesNotHideOrResizeTheExistingBoard() {
        let size = CGSize(width: 300, height: 740)
        let resting = plan(size, compact: true, chat: true, composerHeight: 50)
        let typing = plan(size, compact: true, chat: true, keyboard: true,
                          composerHeight: 50, keyboardOverlap: 300)
        XCTAssertFalse(resting[.board].isEmpty)
        assertSceneOutsideChat(typing, equals: resting)
        XCTAssertEqual(typing[.composer].height, 50)
        XCTAssertLessThanOrEqual(typing[.composer].maxY, size.height - 300)
    }

    func testNearSquareCompactPortraitKeyboardKeepsBoardAndScene() {
        let size = CGSize(width: 590, height: 650)
        for composerHeight in [CGFloat(50), CGFloat(188)] {
            let resting = plan(size, compact: true, chat: true,
                               composerHeight: composerHeight)
            let typing = plan(size, compact: true, chat: true, keyboard: true,
                              composerHeight: composerHeight,
                              keyboardOverlap: 300)
            XCTAssertFalse(resting[.board].isEmpty)
            assertSceneOutsideChat(typing, equals: resting)
            XCTAssertGreaterThanOrEqual(typing[.composer].height, 50)
            XCTAssertLessThanOrEqual(typing[.composer].height, composerHeight)
            XCTAssertLessThanOrEqual(typing[.composer].maxY, size.height - 300)
            assertOccupiedSlotsFit(typing, in: size)
        }
    }

    func testHidingCompactLandscapeBoardExpandsChatBesideClocksAndActions() {
        let size = CGSize(width: 780, height: 350)
        let visible = plan(size, compact: true, chat: true)
        let hidden = plan(size, compact: true, chat: true, hidesBoard: true)
        XCTAssertTrue(hidden[.board].isEmpty)
        XCTAssertGreaterThan(hidden[.chat].width, visible[.chat].width)
        XCTAssertTrue(hidden.clocksInHeader)
        XCTAssertTrue(hidden[.clocks].isEmpty)
        XCTAssertTrue(hidden[.status].isEmpty)
        XCTAssertFalse(hidden[.actions].isEmpty)
        XCTAssertFalse(hidden[.chat].intersects(hidden[.clocks]))
        XCTAssertFalse(hidden[.chat].intersects(hidden[.actions]))
    }

    func testZeroKeyboardOverlapPreservesPortraitChatGeometry() {
        for (size, compact) in [(CGSize(width: 390, height: 740), true),
                                (CGSize(width: 820, height: 1080), false)] {
            let resting = plan(size, compact: compact, chat: true, composerHeight: 50)
            let typing = plan(size, compact: compact, chat: true, keyboard: true,
                              composerHeight: 50, keyboardOverlap: 0)
            assertSceneOutsideChat(typing, equals: resting)
            XCTAssertEqual(typing[.chat], resting[.chat])
            XCTAssertEqual(typing[.composer], resting[.composer])
        }
    }

    func testPortraitVariationComposerKeepsMeasuredHeightWithoutReflowingScene() {
        let size = CGSize(width: 430, height: 760)
        let resting = plan(size, compact: true, chat: true, hidesBoard: true,
                           composerHeight: 188)
        let typing = plan(size, compact: true, chat: true, keyboard: true,
                          hidesBoard: true,
                          composerHeight: 188, keyboardOverlap: 300)
        assertSceneOutsideChat(typing, equals: resting)
        XCTAssertTrue(typing[.board].isEmpty)
        XCTAssertEqual(typing[.composer].height, 188)
        XCTAssertLessThanOrEqual(typing[.composer].maxY, size.height - 300)
        XCTAssertEqual(typing[.chat].maxY, typing[.composer].minY)
        assertOccupiedSlotsFit(typing, in: size)
    }

    func testBoardRemainsWithinAvailableContentAcrossCommonSizes() {
        for size in [CGSize(width: 320, height: 480), CGSize(width: 430, height: 760),
                     CGSize(width: 860, height: 820), CGSize(width: 1194, height: 820),
                     CGSize(width: 1024, height: 600)] {
            for analyze in [false, true] {
                for chat in [false, true] {
                    let p = plan(size, compact: size.width < 600, analyze: analyze, chat: chat)
                    XCTAssertEqual(p[.board].width, p[.board].height)
                    XCTAssertTrue(CGRect(origin: .zero, size: size).contains(p[.board]), "\(size) analyze=\(analyze) chat=\(chat): \(p[.board])")
                }
            }
        }
    }

    func testAccessibilityActionWrapsAcrossFullRowAfterIdentityHides() {
        let metrics = GameControlRowMetrics(dynamicTypeSize: .accessibility5,
                                           localizedLabels: englishActionLabels)
        let p = GameDetailLayoutPlan(
            size: CGSize(width: 320, height: 740), compact: true, zen: false,
            analyze: false, chat: false, hidesBoard: false, keyboard: false,
            accessibility: true, foldsClock: true, clockScale: 1.65,
            actionSize: metrics.horizontalSize, actionMetrics: metrics
        )
        XCTAssertTrue(p.wrapsMainAction)
        XCTAssertTrue(p.hidesActionIdentity)
        XCTAssertGreaterThanOrEqual(p[.actions].height, metrics.rowHeight(at: p[.actions].width))
        XCTAssertLessThanOrEqual(p[.actions].maxY, 740)
        XCTAssertLessThanOrEqual(p[.board].maxY, p[.actions].minY)
    }

    func testAccessibility3PhoneUsesFullActionRowWithoutAvatarReservation() {
        let metrics = GameControlRowMetrics(dynamicTypeSize: .accessibility3,
                                           localizedLabels: englishActionLabels)
        let size = CGSize(width: 402, height: 682)
        let p = GameDetailLayoutPlan(
            size: size, compact: true, zen: false, analyze: false, chat: false,
            hidesBoard: false, keyboard: false, accessibility: true,
            foldsClock: true, clockScale: 1.65, actionSize: metrics.horizontalSize,
            actionMetrics: metrics
        )
        XCTAssertTrue(p.hidesActionIdentity)
        XCTAssertEqual(p.wrapsMainAction, metrics.horizontalSize.width > p[.actions].width)
        XCTAssertEqual(p[.actions].width, size.width - 16)
        XCTAssertGreaterThanOrEqual(p[.actions].height, metrics.rowHeight(at: p[.actions].width))
        XCTAssertGreaterThanOrEqual(p[.actions].height, 52)
        XCTAssertLessThanOrEqual(p[.board].maxY, p[.actions].minY)
        assertOccupiedSlotsFit(p, in: size)
    }

    func testBookKeepsClockAboveBoardWithOrWithoutPanels() {
        let size = CGSize(width: 1100, height: 730)
        let division = CGRect(x: 540, y: 0, width: 20, height: 730)
        for chat in [false, true] {
            let p = plan(size, chat: chat, division: division)
            XCTAssertGreaterThanOrEqual(p[.clocks].minX, division.maxX)
            XCTAssertTrue(p[.status].isEmpty)
            XCTAssertEqual(p[.board].minY - p[.opponent].maxY, 4)
            XCTAssertFalse(p[.opponent].isEmpty)
            XCTAssertTrue(p[.status].isEmpty)
        }
    }

    func testCompactConflictingPanelsDoNotDoubleAllocateHeight() {
        let size = CGSize(width: 430, height: 760)
        let both = plan(size, compact: true, analyze: true, chat: true)
        let analysis = plan(size, compact: true, analyze: true)
        XCTAssertEqual(both[.board], analysis[.board])
        XCTAssertTrue(both[.chat].isEmpty)
        XCTAssertTrue(CGRect(origin: .zero, size: size).contains(both[.board]))
    }

    func testPhoneLandscapeChatAndAnalyzeReserveSeparateFullHeightBoard() {
        // Artboards12/23: left history/horizontal tree, right square board.
        // Model the body after native landscape safe areas, not screen pixels.
        let size = CGSize(width: 756, height: 334)
        for analyze in [false, true] {
            let p = plan(size, compact: true, analyze: analyze, chat: !analyze,
                         composerHeight: analyze ? 0 : 50)
            XCTAssertGreaterThanOrEqual(p[.board].width, size.height - 24)
            XCTAssertTrue(p.clocksInHeader)
            XCTAssertTrue(p[.clocks].isEmpty)
            let panel = p[analyze ? .analysis : .chat]
            XCTAssertLessThanOrEqual(panel.maxX, p[.board].minX)
            XCTAssertFalse(panel.intersects(p[.board]))
            if analyze {
                XCTAssertGreaterThan(p[.analysis].width, p[.analysis].height)
                XCTAssertLessThanOrEqual(p[.analysisControls].maxX, p[.board].minX)
                XCTAssertLessThanOrEqual(p[.analysis].maxY, p[.analysisControls].minY)
            } else {
                XCTAssertEqual(p[.chat].maxY, p[.composer].minY)
                XCTAssertLessThanOrEqual(p[.composer].maxY, p[.actions].minY)
            }
            assertOccupiedSlotsFit(p, in: size)
        }
    }

    func testDuoClosedLandscapeAnalyzeUsesStackedClocksAndControlsUnderBoard() {
        // Artboard28 uses a vertical tree with snapshots, unlike phone23.
        let size = CGSize(width: 620, height: 418)
        let p = plan(size, compact: true, analyze: true, usesVerticalToolbar: true)
        XCTAssertGreaterThan(p[.analysis].height, p[.analysis].width)
        XCTAssertGreaterThanOrEqual(p[.board].width, 340)
        XCTAssertLessThanOrEqual(p[.analysis].maxX, p[.board].minX)
        XCTAssertGreaterThanOrEqual(p[.analysisControls].minY, p[.board].maxY)
        XCTAssertTrue(p.verticalAnalysisTree)
        XCTAssertTrue(p.stackedClocks)
        XCTAssertEqual(p.clockStyle, .inline)
        XCTAssertEqual(p[.analysisControls].minX, p[.board].minX)
        XCTAssertEqual(p[.analysisControls].width, p[.board].width)
        XCTAssertLessThanOrEqual(p[.clocks].maxY, p[.analysis].minY)
        XCTAssertFalse(p.clocksInHeader)
        assertOccupiedSlotsFit(p, in: size)

        let taller = plan(CGSize(width: 620, height: 470), compact: true,
                          analyze: true, usesVerticalToolbar: true)
        XCTAssertEqual(taller[.board].width, 620 - 224 - 8 - 16)
        XCTAssertEqual(taller[.analysis].width, 224)
        XCTAssertEqual(taller[.board].minY, 470 - taller[.analysisControls].maxY)
    }

    func testPortraitIPadZenAllowsTheWindowCenteredBoard() {
        let p = plan(CGSize(width: 820, height: 1074), zen: true, zenBoardCenterY: 504)
        XCTAssertEqual(p[.board], CGRect(x: 24, y: 118, width: 772, height: 772))
        XCTAssertTrue(p.spaciousCompactClocks)
        XCTAssertEqual(p[.clocks], CGRect(x: 230, y: 34, width: 360, height: 76))
        XCTAssertTrue(p.narrowCompactClocks,
                      "The larger iPad Zen type keeps its status on a dedicated row")
        XCTAssertTrue(p[.status].isEmpty)
        XCTAssertEqual(p[.board].minY - p[.clocks].maxY, 8)
        XCTAssertEqual(p[.actions].minX, p[.board].minX)
        XCTAssertEqual(p[.actions].maxX, p[.board].maxX)
        XCTAssertEqual(p[.actions].minY - p[.board].maxY, 12)
    }

    func testWideIPadZenUsesSymmetricSideRegionsAndHorizontalActions() {
        let size = CGSize(width: 1180, height: 800)
        let p = plan(size, zen: true)
        XCTAssertEqual(p[.board], CGRect(x: 206, y: 16, width: 768, height: 768))
        XCTAssertEqual(p[.clocks].minX, 24)
        XCTAssertEqual(p[.clocks].width, 174)
        XCTAssertEqual(p[.clocks].height, 160)
        XCTAssertTrue(p.narrowCompactClocks,
                      "Both 174 pt cards reserve the complete status, time and detail rows")
        XCTAssertEqual(p[.board].minX - p[.clocks].maxX, 8)
        XCTAssertEqual(p[.actions].minX - p[.board].maxX, 8)
        XCTAssertEqual(p[.actions].width, p[.clocks].width)
        XCTAssertEqual(p[.actions].maxX, size.width - 24)
        XCTAssertEqual(p[.actions].maxY, p[.board].maxY)
        XCTAssertFalse(p.verticalActions)
        assertOccupiedSlotsFit(p, in: size)
    }

    func testBookTallNativeBoardKeepsMatching116PointCornerColumns() {
        let size = CGSize(width: 669, height: 893)
        let division = CGRect(x: 0, y: 436, width: 669, height: 40)
        let p = plan(size, division: division)
        XCTAssertEqual(p[.board], CGRect(x: 136, y: 484, width: 397, height: 397))
        XCTAssertEqual(p[.opponent].width, 116)
        XCTAssertEqual(p[.opponent].minX, 12)
        XCTAssertEqual(p[.actions].width, 116)
        XCTAssertEqual(p[.actions].maxX, size.width - 12)
        XCTAssertEqual(p[.board].minX - p[.opponent].maxX, 8)
        XCTAssertEqual(p[.actions].minX - p[.board].maxX, 8)
        assertOccupiedSlotsFit(p, in: size)
    }

    func testClosedLandscapeOpponentAndClockColumnStartsAtBoardCornerWhenItFits() {
        let size = CGSize(width: 594, height: 466)
        let p = plan(size, compact: true, usesVerticalToolbar: true)
        XCTAssertTrue(p.verticalOpponentIdentity)
        XCTAssertEqual(p[.opponent].minY, p[.board].minY)
        XCTAssertEqual(p[.clocks].minY - p[.opponent].maxY, 8)
        XCTAssertTrue(p[.status].isEmpty)
        assertOccupiedSlotsFit(p, in: size)
    }

    func testFoldedCompactIPadKeepsOpponentRowInsteadOfRequestingOccupiedTitleSlot() {
        let size = CGSize(width: 375, height: 488)
        let p = GameDetailLayoutPlan(
            size: size, compact: true, zen: false, analyze: false, chat: false,
            hidesBoard: false, keyboard: false, accessibility: false, foldsClock: true,
            opponentSharesStatusWhenFolded: true
        )
        XCTAssertEqual(p[.board].minY - p[.opponent].maxY, 4)
        XCTAssertFalse(p.hidesOpponentIdentity)
        XCTAssertFalse(p[.opponent].isEmpty)
        XCTAssertTrue(p[.status].isEmpty)
        XCTAssertEqual(p[.board].midX, size.width / 2)
        assertOccupiedSlotsFit(p, in: size)
    }

    func testNarrowVerticalAnalyzeYieldsTreeBeforeBranchArrowBar() {
        let size = CGSize(width: 550, height: 466)
        let p = plan(size, compact: true, analyze: true, usesVerticalToolbar: true)
        XCTAssertEqual(p[.board].width, 346)
        XCTAssertEqual(p[.analysisControls].width, 346)
        XCTAssertEqual(p[.analysis].width, 180)
        XCTAssertEqual(p[.board].minX - p[.analysis].maxX, 8)
        assertOccupiedSlotsFit(p, in: size)
    }

    func testClosedLandscapeAnalysisPreservesTreeWidthAndCentersBoardGroup() {
        // The native84pt navigation rail leaves594pt from a678pt window.
        // Keep the reference tree width; the board absorbs that rail delta.
        let size = CGSize(width: 594, height: 466)
        let p = plan(size, compact: true, analyze: true, usesVerticalToolbar: true)
        XCTAssertEqual(p[.analysis].minX, 8)
        XCTAssertEqual(p[.analysis].width, 224)
        XCTAssertEqual(p[.clocks], CGRect(x: 52, y: 25, width: 180, height: 86))
        XCTAssertEqual(p[.clocks].maxX, p[.analysis].maxX)
        XCTAssertEqual(p[.analysis].minY, 114)
        XCTAssertEqual(p[.board], CGRect(x: 240, y: 30, width: 346, height: 346))
        XCTAssertEqual(p[.analysisControls], CGRect(x: 240, y: 384, width: 346, height: 52))
        XCTAssertEqual(p[.analysis].maxY, p[.analysisControls].maxY)
        XCTAssertEqual(p[.board].minY, size.height - p[.analysisControls].maxY)
        XCTAssertEqual(p[.board].minX - p[.analysis].maxX, 8)
        XCTAssertTrue(p.verticalAnalysisTree)
        assertOccupiedSlotsFit(p, in: size)
    }

    func testShortPortraitAnalyzeMovesClocksToNavigationWithoutBodyGap() {
        let size = CGSize(width: 375, height: 560)
        let p = plan(size, compact: true, analyze: true)
        XCTAssertTrue(p.clocksInHeader)
        XCTAssertTrue(p[.clocks].isEmpty)
        XCTAssertEqual(p[.board].width, 320)
        XCTAssertEqual(p[.board].maxY, size.height)
        XCTAssertLessThanOrEqual(p[.analysis].maxY, p[.analysisControls].minY)
        XCTAssertLessThanOrEqual(p[.analysisControls].maxY, p[.board].minY)
        XCTAssertLessThan(p[.analysis].height, 190)
        XCTAssertFalse(p[.analysis].intersects(p[.board]))
    }

    func testBookHiddenChatShowsInformationInOppositePanel() {
        for (size, division) in [
            (CGSize(width: 887, height: 621), CGRect(x: 445, y: 0, width: 12, height: 621)),
            (CGSize(width: 669, height: 870), CGRect(x: 0, y: 395, width: 669, height: 12))
        ] {
            let p = plan(size, division: division)
            XCTAssertFalse(p[.information].isEmpty)
            XCTAssertFalse(p[.information].intersects(division))
            XCTAssertFalse(p[.information].intersects(p[.clocks]))
            XCTAssertFalse(p[.information].intersects(p[.board]))
            XCTAssertTrue(p[.chat].isEmpty)
            if division.width > division.height {
                XCTAssertLessThanOrEqual(p[.information].maxY, p[.clocks].minY)
                XCTAssertTrue(p[.status].isEmpty)
            } else {
                XCTAssertLessThanOrEqual(p[.information].maxX, division.minX)
            }
            assertOccupiedSlotsFit(p, in: size)
        }
    }

    func testBookWideZenSeparatesCenteredClocksFromRightBoard() {
        let size = CGSize(width: 887, height: 621)
        let division = CGRect(x: 445, y: 0, width: 12, height: 621)
        let p = plan(size, zen: true, division: division)
        XCTAssertEqual(p.clockStyle, .compact)
        XCTAssertTrue(p.stackedClocks)
        XCTAssertEqual(p[.clocks].height, 68 * 2 + 8)
        XCTAssertEqual(p[.clocks].width, 160)
        XCTAssertLessThanOrEqual(p[.clocks].maxX, division.minX)
        XCTAssertTrue(p[.status].isEmpty)
        XCTAssertGreaterThanOrEqual(p[.board].minX, division.maxX)
        XCTAssertGreaterThanOrEqual(p[.board].width, 400)
        XCTAssertLessThanOrEqual(p[.clocks].minY, size.height / 2)
        XCTAssertTrue(p[.status].isEmpty)
        XCTAssertTrue(p[.information].isEmpty)
        assertOccupiedSlotsFit(p, in: size)
    }

    func testBookTallOnlyPlayAndZenKeepBodyClocksByFold() {
        let size = CGSize(width: 669, height: 870)
        let division = CGRect(x: 0, y: 395, width: 669, height: 12)
        for (analyze, zen) in [(false, false), (true, false), (false, true)] {
            let p = plan(size, zen: zen, analyze: analyze, division: division)
            if analyze {
                XCTAssertEqual(p.clockStyle, .inline)
                XCTAssertTrue(p.clocksInHeader)
                XCTAssertTrue(p[.clocks].isEmpty)
                XCTAssertTrue(p[.status].isEmpty)
                XCTAssertFalse(p.verticalAnalysisTree)
                XCTAssertEqual(p[.analysisControls].maxY, division.minY - 8)
            } else {
                XCTAssertEqual(p.clockStyle, zen ? .compact : .full)
                XCTAssertTrue(p[.status].isEmpty)
            }
            XCTAssertGreaterThanOrEqual(p[.board].minY, division.maxY)
            XCTAssertGreaterThanOrEqual(p[.board].width, 390)
            XCTAssertGreaterThanOrEqual(p[.board].maxY, size.height - 16)
            XCTAssertLessThanOrEqual(p[.board].maxX, p[.actions].minX)
            if !zen { XCTAssertLessThanOrEqual(p[.opponent].maxX, p[.board].minX) }
            assertOccupiedSlotsFit(p, in: size)
        }
    }

    func testLandscapeChatMeasuresWrappedActionsInTheLeftPanel() {
        // A measured label row fits the whole window but needs two lines in
        // the Chat pane. Do not let its wrapped controls cover the composer.
        let size = CGSize(width: 756, height: 334)
        func layout(hidesBoard: Bool) -> GameDetailLayoutPlan {
            GameDetailLayoutPlan(size: size, compact: true, zen: false,
                                 analyze: false, chat: true, hidesBoard: hidesBoard,
                                 keyboard: false, accessibility: false, foldsClock: false,
                                 actionSize: CGSize(width: 600, height: 48), composerHeight: 50)
        }
        let visible = layout(hidesBoard: false)
        XCTAssertTrue(visible.wrapsMainAction)
        XCTAssertGreaterThanOrEqual(visible[.actions].height, 96)
        XCTAssertLessThanOrEqual(visible[.composer].maxY, visible[.actions].minY)
        XCTAssertFalse(visible[.actions].intersects(visible[.board]))
        let hidden = layout(hidesBoard: true)
        XCTAssertFalse(hidden.wrapsMainAction)
        XCTAssertLessThan(hidden[.actions].height, visible[.actions].height)
        XCTAssertLessThanOrEqual(hidden[.composer].maxY, hidden[.actions].minY)
        assertOccupiedSlotsFit(visible, in: size)
        assertOccupiedSlotsFit(hidden, in: size)
    }

    func testShortCompactLandscapeFoldsLargeTextClocksBeforeTheyLeaveBody() {
        let size = CGSize(width: 780, height: 244)
        for accessibility in [false, true] {
            let p = GameDetailLayoutPlan(size: size, compact: true, zen: false,
                                        analyze: false, chat: false, hidesBoard: false,
                                        keyboard: false, accessibility: accessibility,
                                        foldsClock: true, clockScale: 1.65)
            XCTAssertEqual(p.clockStyle, .inline)
            XCTAssertTrue(p.stackedClocks)
            XCTAssertFalse(p[.clocks].isEmpty)
            XCTAssertTrue(p[.status].isEmpty)
            if !accessibility {
                XCTAssertTrue(p.hidesOpponentIdentity)
                XCTAssertTrue(p[.opponent].isEmpty)
            }
            assertOccupiedSlotsFit(p, in: size)
        }
    }

    func testPortraitAnalyzeUsesSpareHeightForTreeAfterBoardReachesMaximumWidth() {
        let short = plan(CGSize(width: 390, height: 740), compact: true, analyze: true)
        let tall = plan(CGSize(width: 390, height: 840), compact: true, analyze: true)
        XCTAssertEqual(short[.board].width, 390)
        XCTAssertEqual(tall[.board].width, 390)
        XCTAssertEqual(tall[.analysis].height - short[.analysis].height, 100)
        XCTAssertGreaterThanOrEqual(short[.analysis].height, 190)
        for p in [short, tall] {
            XCTAssertTrue(p.clocksInHeader)
            XCTAssertTrue(p[.status].isEmpty)
            XCTAssertTrue(p[.opponent].isEmpty)
            XCTAssertTrue(p[.actions].isEmpty)
            XCTAssertEqual(p[.analysisControls].height, 52)
            XCTAssertEqual(p[.analysis].maxY + 8, p[.analysisControls].minY)
            XCTAssertEqual(p[.analysisControls].maxY + 8, p[.board].minY)
        }
    }

    func testShortAndNarrowAnalyzeShrinksTreeBeforeBoardWithoutOverlay() {
        for size in [CGSize(width: 375, height: 560), CGSize(width: 320, height: 480),
                     CGSize(width: 280, height: 430)] {
            let p = plan(size, compact: true, analyze: true)
            XCTAssertEqual(p[.board].width, min(320, size.width))
            XCTAssertEqual(p[.board].maxY, size.height)
            XCTAssertGreaterThan(p[.analysis].height, 0)
            XCTAssertLessThan(p[.analysis].height, 190)
            XCTAssertFalse(p[.board].intersects(p[.analysis]))
            XCTAssertFalse(p[.board].intersects(p[.analysisControls]))
            assertOccupiedSlotsFit(p, in: size)
        }
    }

    func testDuoClosedPortraitAnalyzeKeepsItsOwnClockRowAboveTree() {
        let size = CGSize(width: 382, height: 620)
        let p = plan(size, compact: true, analyze: true, usesVerticalToolbar: true)
        XCTAssertFalse(p.clocksInHeader)
        XCTAssertFalse(p.stackedClocks)
        XCTAssertEqual(p.clockStyle, .inline)
        XCTAssertFalse(p[.clocks].isEmpty)
        XCTAssertLessThanOrEqual(p[.clocks].maxY, p[.analysis].minY)
        XCTAssertGreaterThanOrEqual(p[.board].width, 320)
        XCTAssertEqual(p[.board].maxY, size.height)
        assertOccupiedSlotsFit(p, in: size)
    }

    func testDuoClosedPortraitAnalysisRemovesOnlyRedundantStackGaps() {
        let size = CGSize(width: 382, height: 644)
        let p = plan(size, compact: true, analyze: true, usesVerticalToolbar: true)
        XCTAssertEqual(p[.clocks].maxY, 52)
        XCTAssertEqual(p[.analysis].minY, p[.clocks].maxY)
        XCTAssertEqual(p[.analysis].height, 190)
        XCTAssertEqual(p[.analysisControls].minY - p[.analysis].maxY, 8)
        XCTAssertEqual(p[.analysisControls].height, 52)
        XCTAssertEqual(p[.board].minY, p[.analysisControls].maxY)
        XCTAssertEqual(p[.board].minY, 302)
        XCTAssertEqual(p[.board].width, 342)
        XCTAssertEqual(p[.board].maxY, size.height)
        assertOccupiedSlotsFit(p, in: size)
    }

    func testCompactChatUsesSpaceBelowHeaderClocks() {
        for size in [CGSize(width: 390, height: 740), CGSize(width: 756, height: 334)] {
            let p = plan(size, compact: true, chat: true, composerHeight: 50)
            XCTAssertTrue(p.clocksInHeader)
            XCTAssertTrue(p[.clocks].isEmpty)
            XCTAssertTrue(p[.status].isEmpty)
            XCTAssertEqual(p[.chat].maxY, p[.composer].minY)
            assertOccupiedSlotsFit(p, in: size)
        }
    }

    func testExplicitlyHiddenPortraitBoardStaysHiddenAcrossKeyboardPresentation() {
        for (size, verticalToolbar) in [(CGSize(width: 402, height: 740), false),
                                        (CGSize(width: 382, height: 644), true)] {
            for composerHeight in [CGFloat(50), CGFloat(188)] {
                let resting = plan(size, compact: true, chat: true, hidesBoard: true,
                                   composerHeight: composerHeight,
                                   usesVerticalToolbar: verticalToolbar)
                let typing = plan(size, compact: true, chat: true, keyboard: true,
                                  hidesBoard: true,
                                  composerHeight: composerHeight, keyboardOverlap: 300,
                                  usesVerticalToolbar: verticalToolbar)
                XCTAssertTrue(resting[.board].isEmpty)
                XCTAssertTrue(typing[.board].isEmpty)
                assertSceneOutsideChat(typing, equals: resting)
                XCTAssertEqual(typing[.composer].height, composerHeight)
                XCTAssertEqual(typing[.chat].maxY, typing[.composer].minY)
                XCTAssertLessThanOrEqual(typing[.composer].maxY, size.height - 300)
                assertOccupiedSlotsFit(typing, in: size)
            }
        }
    }

    func testLandscapeVariationComposerUsesFullViewportAndExplicitKeyboardOverlap() {
        let size = CGSize(width: 750, height: 350)
        let resting = plan(size, compact: true, chat: true, hidesBoard: true,
                           composerHeight: 188)
        let typing = plan(size, compact: true, chat: true, keyboard: true,
                          hidesBoard: true,
                          composerHeight: 188, keyboardOverlap: 140)
        XCTAssertTrue(typing[.board].isEmpty, "Only the explicit Hide main board hides it")
        assertClockPresentation(typing, equals: resting)
        XCTAssertEqual(typing[.composer].height, 188)
        XCTAssertEqual(typing[.composer].maxY, size.height - 140 - 8)
        XCTAssertEqual(typing[.composer].width, size.width - 16)
        XCTAssertEqual(typing[.chat].maxY, typing[.composer].minY)
        assertOccupiedSlotsFit(typing, in: size)
    }

    func testRegularLandscapeUsesOneColumnAndPreservesTheBoardAcrossPanels() {
        for (size, verticalToolbar) in [(CGSize(width: 1180, height: 714), false),
                                        (CGSize(width: 867, height: 611), true),
                                        (CGSize(width: 880, height: 714), false)] {
            let play = plan(size, usesVerticalToolbar: verticalToolbar)
            for (analyze, chat) in [(true, false), (false, true)] {
                let panel = plan(size, analyze: analyze, chat: chat, composerHeight: 50,
                                 usesVerticalToolbar: verticalToolbar)
                for slot in [GameDetailLayoutPlan.Slot.board, .opponent, .actions] {
                    XCTAssertEqual(panel[slot], play[slot], "Panel changed \(slot) at \(size)")
                }
                XCTAssertFalse(panel.verticalActions)
                XCTAssertFalse(panel.verticalOpponentIdentity)
                XCTAssertFalse(panel.stackedClocks)
                XCTAssertEqual(panel.clockStyle, .full)
                XCTAssertEqual(panel[.clocks].minX, panel[analyze ? .analysis : .chat].minX)
                XCTAssertLessThanOrEqual(panel[.clocks].maxY, panel[analyze ? .analysis : .chat].minY)
                XCTAssertLessThanOrEqual(panel[.clocks].maxX, panel[.board].minX)
                XCTAssertTrue(panel[.information].isEmpty)
                assertOccupiedSlotsFit(panel, in: size)
            }
        }
    }

    func testIPadLandscapePanelHasFullClockPairAndFixedBoardRows() {
        let size = CGSize(width: 1180, height: 714)
        let chat = plan(size, chat: true, composerHeight: 50)
        XCTAssertEqual(chat[.board].size, CGSize(width: 570, height: 570))
        XCTAssertEqual(chat[.board].minY, 72)
        XCTAssertEqual(chat[.opponent].minY, 16)
        XCTAssertEqual(chat[.opponent].height, 52)
        XCTAssertEqual(chat[.opponent].minX, chat[.board].minX)
        XCTAssertEqual(chat[.opponent].width, chat[.board].width)
        XCTAssertEqual(chat[.actions].minY, 646)
        XCTAssertEqual(chat[.actions].maxY, 698)
        XCTAssertEqual(chat[.actions].minX, chat[.board].minX)
        XCTAssertEqual(chat[.clocks], CGRect(x: 24, y: 16, width: 400, height: 96))
        XCTAssertFalse(chat.narrowFullClocks)
        XCTAssertEqual(chat[.chat].minY, 120)
        XCTAssertEqual(chat[.chat].width, 400)
        XCTAssertEqual(chat[.composer], CGRect(x: 24, y: 648, width: 400, height: 50))
        XCTAssertEqual(chat[.chat].maxY, chat[.composer].minY)
        assertOccupiedSlotsFit(chat, in: size)
    }

    func testIPadClosedPanelCentersStackedClocksAgainstTheBoard() {
        let p = plan(CGSize(width: 1180, height: 714))
        XCTAssertEqual(p.clockStyle, .full)
        XCTAssertTrue(p.stackedClocks)
        XCTAssertEqual(p[.clocks].width, 300)
        XCTAssertEqual(p[.clocks].height, 200)
        XCTAssertEqual(p[.clocks].maxX, 424)
        XCTAssertEqual(p[.clocks].midY, p[.board].midY)
        XCTAssertTrue(p[.analysis].isEmpty)
        XCTAssertTrue(p[.chat].isEmpty)
        XCTAssertTrue(p[.information].isEmpty)
    }

    func testDuoOpenFullClockPairWrapsItsFooterOnlyWhenItDoesNotFit() {
        let size = CGSize(width: 867, height: 611)
        // "+ 1d · 2 captures" needs about 123 pt; the 164 pt cards fit it.
        for (footer, cardHeight) in [(CGFloat(123), CGFloat(96)), (CGFloat(200), CGFloat(110))] {
            let p = plan(size, chat: true, composerHeight: 50, usesVerticalToolbar: true,
                         fullClockFooterWidth: footer)
            XCTAssertEqual(p[.board], CGRect(x: 368, y: 64, width: 491, height: 491))
            XCTAssertEqual(p[.opponent], CGRect(x: 368, y: 8, width: 491, height: 52))
            XCTAssertEqual(p[.actions], CGRect(x: 368, y: 559, width: 491, height: 52))
            XCTAssertEqual(p[.clocks], CGRect(x: 16, y: 64, width: 336, height: cardHeight))
            XCTAssertEqual(p[.chat].minY, 64 + cardHeight + 8)
            XCTAssertEqual(p[.chat].width, 336)
            XCTAssertEqual(p[.composer].maxY, size.height)
            XCTAssertEqual(p.narrowFullClocks, cardHeight == 110)
            XCTAssertFalse(p.stackedClocks)
            assertOccupiedSlotsFit(p, in: size)
        }
    }

    func testDuoOpenWideGameUsesTheNavigationBandBesideTheSidebarButton() {
        // The content extends to the window top; the native bar starts at 24.
        let size = CGSize(width: 867, height: 635)
        for (analyze, chat) in [(false, false), (false, true), (true, false)] {
            let p = plan(size, analyze: analyze, chat: chat, composerHeight: chat ? 50 : 0,
                         usesVerticalToolbar: true, fullClockFooterWidth: 123, chromeBandTop: 24)
            XCTAssertEqual(p[.opponent], CGRect(x: 368, y: 32, width: 491, height: 52))
            XCTAssertEqual(p[.board], CGRect(x: 368, y: 88, width: 491, height: 491))
            XCTAssertEqual(p[.actions], CGRect(x: 368, y: 583, width: 491, height: 52))
            if chat || analyze {
                XCTAssertEqual(p[.clocks], CGRect(x: 16, y: 88, width: 336, height: 96))
            } else {
                XCTAssertEqual(p[.clocks].minX, 52)
                XCTAssertEqual(p[.clocks].width, 300)
                XCTAssertGreaterThanOrEqual(p[.clocks].minY, 88)
            }
            XCTAssertFalse(p.narrowFullClocks)
            assertOccupiedSlotsFit(p, in: size)
        }
    }

    func testDuoBookWideClockTableUsesTheBandOnTheRightScreen() {
        let size = CGSize(width: 867, height: 635)
        let fold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        for (analyze, chat) in [(false, false), (false, true), (true, false)] {
            let p = plan(size, analyze: analyze, chat: chat, composerHeight: chat ? 50 : 0,
                         division: fold, panelDivision: fold, usesVerticalToolbar: true,
                         fullClockFooterWidth: 123, chromeBandTop: 24)
            XCTAssertEqual(p[.clocks], CGRect(x: 503.5, y: 32, width: 355.5, height: 96))
            XCTAssertEqual(p[.opponent], CGRect(x: 503.5, y: 136, width: 355.5, height: 52))
            XCTAssertEqual(p[.board], CGRect(x: 503.5, y: 192, width: 355.5, height: 355.5))
            XCTAssertFalse(p.narrowFullClocks)
            let panel = [GameDetailLayoutPlan.Slot.analysis, .chat, .information]
                .map { p[$0] }.first { !$0.isEmpty }
            XCTAssertEqual(panel?.minX, 16)
            XCTAssertEqual(panel?.minY, 88, "The left panel starts below the sidebar button")
            assertOccupiedSlotsFit(p, in: size)
        }
    }

    func testDuoClosedLandscapeChatMatchesTheCanvas() {
        // v145 canvas: a 214 pt conversation column at x 8 and a 356 pt board
        // at (230, 55), centred vertically, with the clocks aligned to it.
        let size = CGSize(width: 594, height: 466)
        let p = plan(size, compact: true, chat: true, composerHeight: 50, usesVerticalToolbar: true)
        XCTAssertEqual(p[.chat].minX, 8)
        XCTAssertEqual(p[.chat].width, 214)
        XCTAssertEqual(p[.composer].width, 214)
        XCTAssertEqual(p[.board], CGRect(x: 230, y: 55, width: 356, height: 356))
        XCTAssertFalse(p[.chat].intersects(p[.board]))
        assertOccupiedSlotsFit(p, in: size)
    }

    func testDuoOpenWideZenCentresTheBoardOnTheHingeWithoutATray() {
        // v145: no tray in Open wide Zen. The content runs from the window's
        // top to the home indicator (951 × 635); the board is 611 at (170, 24).
        let size = CGSize(width: 951, height: 635)
        let hinge = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let p = plan(size, zen: true, panelDivision: hinge, chromeBandTop: 24)
        XCTAssertEqual(p[.board], CGRect(x: 170, y: 24, width: 611, height: 611))
        XCTAssertEqual(p[.board].midX, size.width / 2, "Centred on the hinge")
        XCTAssertEqual(p[.clocks].minX, 16)
        XCTAssertEqual(p[.clocks].width, 146)
        XCTAssertEqual(p[.clocks].midY, p[.board].midY, accuracy: 0.5)
        XCTAssertEqual(p[.actions].minX, 789)
        XCTAssertEqual(p[.actions].width, 146)
        XCTAssertEqual(p[.actions].maxY, p[.board].maxY)
        assertOccupiedSlotsFit(p, in: size)
    }

    func testDuoClosedPortraitChatClockPairSpansTheRowAndMoreTrails() {
        let size = CGSize(width: 382, height: 644)
        let p = plan(size, compact: true, chat: true, composerHeight: 50, usesVerticalToolbar: true)
        XCTAssertEqual(p[.clocks], CGRect(x: 8, y: 8, width: 366, height: 44))
        XCTAssertTrue(p.verticalActions)
        XCTAssertTrue(p.trailsMoreInColumn)
        assertOccupiedSlotsFit(p, in: size)
    }

    func testDuoOpenClosedPanelCentersItsClockStackInTheColumn() {
        let size = CGSize(width: 867, height: 611)
        let p = plan(size, usesVerticalToolbar: true)
        XCTAssertEqual(p[.board], CGRect(x: 368, y: 64, width: 491, height: 491))
        XCTAssertEqual(p[.clocks].minX, 52)
        XCTAssertEqual(p[.clocks].width, 300)
        XCTAssertEqual(p[.clocks].height, 200)
        XCTAssertEqual(p[.clocks].midY, (p[.board].minY + size.height) / 2)
        XCTAssertTrue(p.stackedClocks)
        XCTAssertFalse(p.narrowFullClocks)
        assertOccupiedSlotsFit(p, in: size)
    }

    func testInactiveDivisionDoesNotSplitAnOpenLandscapePanel() {
        let size = CGSize(width: 867, height: 611)
        let inactive = CGRect(x: 455.5, y: -24, width: 40, height: 669)
        for (analyze, chat) in [(false, false), (true, false), (false, true)] {
            let open = plan(size, analyze: analyze, chat: chat, composerHeight: 50,
                            usesVerticalToolbar: true)
            let marked = plan(size, analyze: analyze, chat: chat, composerHeight: 50,
                              panelDivision: inactive, usesVerticalToolbar: true)
            for slot in GameDetailLayoutPlan.Slot.allCases {
                XCTAssertEqual(marked[slot], open[slot], "Inactive division changed \(slot)")
            }
            assertClockPresentation(marked, equals: open)
        }
    }

    func testRegularPortraitPanelsKeepTheirDistinctBoardsBelowThePanel() {
        let size = CGSize(width: 820, height: 1074)
        let chat = plan(size, chat: true, composerHeight: 50)
        let analysis = plan(size, analyze: true)
        XCTAssertEqual(chat[.board], CGRect(x: 24, y: 406, width: 644, height: 644))
        XCTAssertEqual(analysis[.board], CGRect(x: 24, y: 278, width: 772, height: 772))
        XCTAssertEqual(chat[.chat], CGRect(x: 24, y: 16, width: 772, height: 332))
        XCTAssertEqual(chat[.composer], CGRect(x: 24, y: 348, width: 772, height: 50))
        XCTAssertEqual(chat[.actions].minX, 676)
        XCTAssertEqual(chat[.actions].width, 120)
        XCTAssertTrue(chat.hidesIdentity)
        XCTAssertTrue(chat[.opponent].isEmpty)
        XCTAssertTrue(chat.clocksInHeader)
        XCTAssertTrue(chat[.clocks].isEmpty)
        XCTAssertEqual(chat.clockStyle, .inline)
        XCTAssertFalse(analysis.verticalAnalysisTree)
        XCTAssertEqual(analysis[.analysis].minY, 16)
        XCTAssertEqual(analysis[.analysis].height, 194)
        XCTAssertEqual(analysis[.analysisControls].maxY, 270)
        XCTAssertEqual(analysis[.analysis].maxY + 8, analysis[.analysisControls].minY)
        for p in [chat, analysis] { assertOccupiedSlotsFit(p, in: size) }
    }

    func testConflictingPanelInputsSelectOnlyAnalyzeInEveryArrangement() {
        for (size, compact, vertical, division) in [
            (CGSize(width: 390, height: 740), true, false, Optional<CGRect>.none),
            (CGSize(width: 1180, height: 714), false, false, nil),
            (CGSize(width: 820, height: 1074), false, false, nil),
            (CGSize(width: 867, height: 611), false, true,
             CGRect(x: 455.5, y: -24, width: 40, height: 669)),
            (CGSize(width: 669, height: 870), false, true,
             CGRect(x: 0, y: 395, width: 669, height: 12))
        ] {
            let analysis = plan(size, compact: compact, analyze: true,
                                division: division, usesVerticalToolbar: vertical)
            let conflicting = plan(size, compact: compact, analyze: true, chat: true,
                                   composerHeight: 188, division: division,
                                   usesVerticalToolbar: vertical)
            for slot in GameDetailLayoutPlan.Slot.allCases {
                XCTAssertEqual(conflicting[slot], analysis[slot], "Conflicting panel changed \(slot)")
            }
            XCTAssertTrue(conflicting[.chat].isEmpty)
            XCTAssertTrue(conflicting[.composer].isEmpty)
        }
    }

    func testRegularLandscapeKeyboardChangesOnlyTheConversation() {
        for (size, vertical) in [(CGSize(width: 1180, height: 714), false),
                                 (CGSize(width: 867, height: 611), true)] {
            for composerHeight in [CGFloat(50), CGFloat(188)] {
                let resting = plan(size, chat: true, composerHeight: composerHeight,
                                   usesVerticalToolbar: vertical)
                let typing = plan(size, chat: true, keyboard: true,
                                  composerHeight: composerHeight, keyboardOverlap: 250,
                                  usesVerticalToolbar: vertical)
                assertSceneOutsideChat(typing, equals: resting)
                // The conversation ends 8 pt above the keyboard.
                let available = size.height - 250 - 8 - resting[.chat].minY
                XCTAssertEqual(typing[.composer].height, min(composerHeight, available))
                XCTAssertEqual(typing[.composer].maxY, size.height - 250 - 8)
                if typing[.chat].isEmpty {
                    XCTAssertEqual(typing[.composer].minY, resting[.chat].minY)
                } else {
                    XCTAssertEqual(typing[.chat].maxY, typing[.composer].minY)
                }
                XCTAssertFalse(typing[.composer].intersects(typing[.clocks]))
                assertOccupiedSlotsFit(typing, in: size)
            }
        }
    }

    func testPortraitKeyboardShortensPanelOnlyWhenItReachesTheComposer() {
        let size = CGSize(width: 820, height: 1074)
        let resting = plan(size, chat: true, composerHeight: 50)
        let belowPanel = plan(size, chat: true, keyboard: true,
                              composerHeight: 50, keyboardOverlap: 300)
        assertSceneOutsideChat(belowPanel, equals: resting)
        XCTAssertEqual(belowPanel[.composer], resting[.composer])
        let reachesPanel = plan(size, chat: true, keyboard: true,
                                composerHeight: 50, keyboardOverlap: 800)
        assertSceneOutsideChat(reachesPanel, equals: resting)
        XCTAssertEqual(reachesPanel[.composer].maxY, 1074 - 800 - 8, "8 pt above the keyboard")
        XCTAssertEqual(reachesPanel[.chat].maxY, reachesPanel[.composer].minY)
        XCTAssertFalse(reachesPanel[.chat].intersects(reachesPanel[.board]))
    }

    func testFullPairsReserveASecondFooterLineOnlyForTheMeasuredFooter() {
        // A 170 pt footer wraps in 164 pt cards and fits in 176 pt cards.
        for (width, expectedPairWidth, expectedHeight) in [
            (CGFloat(867), CGFloat(336), CGFloat(110)),
            (CGFloat(891), CGFloat(360), CGFloat(96))
        ] {
            let p = plan(CGSize(width: width, height: 611), chat: true,
                         composerHeight: 50, usesVerticalToolbar: true, fullClockFooterWidth: 170)
            XCTAssertEqual(p.clockStyle, .full)
            XCTAssertEqual(p[.clocks].width, expectedPairWidth)
            XCTAssertEqual(p[.clocks].height, expectedHeight)
            XCTAssertEqual(p.narrowFullClocks, expectedHeight == 110)
            XCTAssertEqual(p[.board].height, 491)
            XCTAssertEqual(p[.board].minY, 64)
        }
    }

    func testShortRegularLandscapeKeepsTheLargeTextComposerVisible() {
        let size = CGSize(width: 880, height: 450)
        for composerHeight in [CGFloat(50), CGFloat(188)] {
            let p = GameDetailLayoutPlan(size: size, compact: false, zen: false,
                analyze: false, chat: true, hidesBoard: false, keyboard: true,
                accessibility: true, foldsClock: true,
                clockScale: 1.65, composerHeight: composerHeight, keyboardOverlap: 280)
            XCTAssertEqual(p.clockStyle, .inline)
            XCTAssertTrue(p.clocksInHeader)
            XCTAssertTrue(p[.clocks].isEmpty)
            XCTAssertGreaterThan(p[.composer].height, 0)
            XCTAssertLessThanOrEqual(p[.composer].height, composerHeight)
            XCTAssertEqual(p[.composer].maxY, 450 - 280 - 8, "8 pt above the keyboard")
            // v145: typing never hides the board; the composer keeps the
            // conversation's column beside it.
            let resting = GameDetailLayoutPlan(size: size, compact: false, zen: false,
                analyze: false, chat: true, hidesBoard: false, keyboard: false,
                accessibility: true, foldsClock: true,
                clockScale: 1.65, composerHeight: composerHeight)
            XCTAssertEqual(p[.composer].width, resting[.composer].width)
            XCTAssertEqual(p[.board], resting[.board])
            XCTAssertFalse(p[.board].isEmpty)
            assertOccupiedSlotsFit(p, in: size)
        }
    }

    func testFullClockHeightScalesWithTheSharedNarrowFooterReservation() {
        for scale: CGFloat in [1, 1.3, 1.65] {
            for (size, vertical, chat) in [(CGSize(width: 1180, height: 714), false, false),
                                           (CGSize(width: 1180, height: 714), false, true),
                                           (CGSize(width: 867, height: 611), true, true)] {
                let p = GameDetailLayoutPlan(size: size, compact: false, zen: false,
                    analyze: false, chat: chat, hidesBoard: false, keyboard: false,
                    accessibility: scale > 1.3, foldsClock: scale > 1,
                    clockScale: scale, composerHeight: chat ? 50 : 0,
                    usesVerticalToolbar: vertical)
                XCTAssertEqual(p.clockStyle, .full)
                XCTAssertEqual(p.fullClockScale, scale > 1.3 ? 1.3 : scale,
                               "Regular accessibility sizes cap the full card")
                let cardHeight: CGFloat = (p.narrowFullClocks ? 110 : 96) * p.fullClockScale
                XCTAssertEqual(p[.clocks].height,
                               p.stackedClocks ? cardHeight * 2 + 8 : cardHeight)
                assertOccupiedSlotsFit(p, in: size)
            }
        }
    }

    func testRegularLandscapeActionRowsReserveMeasuredLabelsAndIdentityHeight() {
        let metrics = GameControlRowMetrics(dynamicTypeSize: .accessibility3,
            localizedLabels: ["Confirm all stones selected for removal", "Clear estimates"])
        let size = CGSize(width: 1180, height: 820)
        let p = GameDetailLayoutPlan(size: size, compact: false, zen: false,
            analyze: false, chat: true, hidesBoard: false, keyboard: false,
            accessibility: true, foldsClock: true, clockScale: 1.65,
            actionSize: metrics.horizontalSize, actionMetrics: metrics,
            composerHeight: 50, identityRowHeight: 108)
        XCTAssertFalse(p.verticalActions)
        XCTAssertGreaterThanOrEqual(p[.actions].height, 108)
        XCTAssertGreaterThanOrEqual(p[.actions].height, metrics.rowHeight(at: p[.actions].width))
        XCTAssertGreaterThanOrEqual(p[.opponent].height, 108)
        XCTAssertEqual(p[.opponent].maxY + 4, p[.board].minY)
        XCTAssertEqual(p[.board].maxY + 4, p[.actions].minY)
        XCTAssertFalse(p[.actions].intersects(p[.composer]))
        assertOccupiedSlotsFit(p, in: size)
    }

    func testPortraitAnalysisKeepsTheMeasuredPlayBoardSizeAtLargeText() {
        for (dynamicType, scale, identityHeight) in [
            (DynamicTypeSize.large, CGFloat(1), CGFloat(52)),
            (.accessibility3, CGFloat(1.65), CGFloat(108))
        ] {
            let metrics = GameControlRowMetrics(dynamicTypeSize: dynamicType,
                                                localizedLabels: englishActionLabels)
            for size in [CGSize(width: 820, height: 1074), CGSize(width: 820, height: 820)] {
                func layout(analyze: Bool) -> GameDetailLayoutPlan {
                    GameDetailLayoutPlan(size: size, compact: false, zen: false,
                        analyze: analyze, chat: false, hidesBoard: false, keyboard: false,
                        accessibility: scale > 1, foldsClock: scale > 1,
                        clockScale: scale, actionSize: metrics.horizontalSize,
                        actionMetrics: metrics, identityRowHeight: identityHeight)
                }
                let play = layout(analyze: false)
                let analysis = layout(analyze: true)
                XCTAssertEqual(analysis[.board].width, play[.board].width,
                               "Hiding the player rows must retain Play's measured board budget")
                XCTAssertEqual(analysis[.board].maxY, size.height - 24)
                XCTAssertFalse(analysis[.analysis].intersects(analysis[.board]))
                XCTAssertFalse(analysis[.analysisControls].intersects(analysis[.board]))
                assertOccupiedSlotsFit(analysis, in: size)
            }
        }
    }

    func testHeightLimitedPortraitFullClocksBudgetTheirFinalNarrowWidth() {
        // A 215 pt accessibility footer fits the wide pair, but not the cards
        // of a board narrowed by the 820 pt height.
        for (height, expectedClockHeight, expectedBoardWidth) in [
            (CGFloat(820), CGFloat(143), CGFloat(353)),
            (CGFloat(900), CGFloat(124.8), CGFloat(451.2))
        ] {
            let size = CGSize(width: 820, height: height)
            func layout(analyze: Bool) -> GameDetailLayoutPlan {
                GameDetailLayoutPlan(size: size, compact: false, zen: false,
                    analyze: analyze, chat: false, hidesBoard: false, keyboard: false,
                    accessibility: true, foldsClock: true, clockScale: 1.65,
                    identityRowHeight: 132, fullClockFooterWidth: 215)
            }
            let play = layout(analyze: false)
            let analysis = layout(analyze: true)
            XCTAssertEqual(play.clockStyle, .full)
            XCTAssertEqual(play[.clocks].width, play[.board].width)
            XCTAssertEqual(play[.clocks].height, expectedClockHeight, accuracy: 0.001)
            XCTAssertEqual(play[.board].width, expectedBoardWidth, accuracy: 0.001)
            XCTAssertEqual(play[.clocks].height, (play.narrowFullClocks ? 110 : 96) * 1.3,
                           accuracy: 0.001)
            XCTAssertLessThanOrEqual(play[.clocks].maxY + 8, play[.opponent].minY)
            XCTAssertEqual(analysis[.board].width, play[.board].width, accuracy: 0.001,
                           "Analyze must inherit the resolved Play clock budget")
            for p in [play, analysis] { assertOccupiedSlotsFit(p, in: size) }
        }
    }

    func testChatPreviewBarSharesTheOpponentRowInRegularLandscape() {
        for size in [CGSize(width: 1376, height: 958), CGSize(width: 1194, height: 790)] {
            let chat = plan(size, chat: true)
            let previewing = plan(size, chat: true, preview: true)
            XCTAssertTrue(previewing.previewInOpponentRow)
            XCTAssertTrue(previewing[.preview].isEmpty, "The opponent's row carries the bar.")
            XCTAssertEqual(previewing[.board], chat[.board], "Previewing never moves the board.")
            XCTAssertEqual(previewing[.opponent], chat[.opponent])
            XCTAssertLessThanOrEqual(previewing[.opponent].maxY, previewing[.board].minY)
        }
    }

    func testChatPreviewBarSitsAboveTheBoardInRegularPortrait() {
        for size in [CGSize(width: 1032, height: 1290), CGSize(width: 834, height: 1100)] {
            let chat = plan(size, chat: true, composerHeight: 50)
            let previewing = plan(size, chat: true, composerHeight: 50, preview: true)
            XCTAssertEqual(previewing[.board], chat[.board], "Previewing never moves the board.")
            XCTAssertFalse(previewing[.preview].isEmpty)
            XCTAssertLessThanOrEqual(previewing[.preview].maxY, previewing[.board].minY)
            XCTAssertLessThanOrEqual(previewing[.composer].maxY, previewing[.preview].minY)
            XCTAssertEqual(previewing[.preview].minX, previewing[.board].minX)
        }
    }

    func testRecoveryPreservesTheSimplifiedPanelAndBoardGeometry() {
        for (size, vertical) in [(CGSize(width: 1180, height: 714), false),
                                 (CGSize(width: 867, height: 611), true),
                                 (CGSize(width: 820, height: 1074), false)] {
            let normal = plan(size, chat: true, composerHeight: 50,
                              usesVerticalToolbar: vertical)
            let recovery = plan(size, chat: true, composerHeight: 50,
                                usesVerticalToolbar: vertical, recoveryHeight: 72)
            for slot in [GameDetailLayoutPlan.Slot.board, .clocks, .opponent, .actions,
                         .chat, .composer] {
                XCTAssertEqual(recovery[slot], normal[slot], "Recovery changed \(slot)")
            }
            XCTAssertFalse(recovery[.status].isEmpty)
            assertOccupiedSlotsFit(recovery, in: size)
        }
    }

    func testActiveBookDivisionsRetainSeparateBoardAndSinglePanelRegions() {
        for (size, division) in [
            (CGSize(width: 867, height: 611), CGRect(x: 455.5, y: -24, width: 40, height: 669)),
            (CGSize(width: 669, height: 870), CGRect(x: 0, y: 395, width: 669, height: 12))
        ] {
            for (analyze, chat) in [(true, false), (false, true)] {
                let p = plan(size, analyze: analyze, chat: chat, composerHeight: 50,
                             division: division, usesVerticalToolbar: true)
                XCTAssertFalse(p[.board].intersects(division))
                let panelSlots: [GameDetailLayoutPlan.Slot] = analyze
                    ? [.analysis, .analysisControls] : [.chat, .composer]
                for slot in panelSlots where !p[slot].isEmpty {
                    XCTAssertFalse(p[slot].intersects(division), "\(slot) crosses hinge")
                    XCTAssertFalse(p[slot].intersects(p[.board]), "\(slot) covers board")
                }
                XCTAssertEqual(p[.chat].isEmpty, analyze)
                XCTAssertEqual(p[.analysis].isEmpty, chat)
                if division.width > division.height {
                    XCTAssertTrue(p.clocksInHeader)
                    XCTAssertFalse(p.verticalAnalysisTree)
                } else {
                    XCTAssertFalse(p.clocksInHeader)
                    XCTAssertEqual(p.clockStyle, .full)
                }
                assertOccupiedSlotsFit(p, in: size)
            }
        }
    }

    func testActiveBookKeyboardKeepsSceneAndBoundsTheComposerToItsPane() {
        for (size, division) in [
            (CGSize(width: 1130, height: 610), CGRect(x: 445, y: 0, width: 12, height: 610)),
            (CGSize(width: 669, height: 870), CGRect(x: 0, y: 395, width: 669, height: 12))
        ] {
            for composerHeight in [CGFloat(50), CGFloat(188)] {
                let resting = plan(size, chat: true, composerHeight: composerHeight,
                                   division: division, usesVerticalToolbar: true)
                for overlap in [CGFloat(280), CGFloat(580)] {
                    let typing = plan(size, chat: true, keyboard: true,
                                      composerHeight: composerHeight, keyboardOverlap: overlap,
                                      division: division, usesVerticalToolbar: true)
                    assertSceneOutsideChat(typing, equals: resting)
                    let composer = typing[.composer]
                    let panelBottom = resting[.composer].maxY
                    let visibleBottom = min(panelBottom, size.height - overlap - 8)
                    XCTAssertEqual(composer.maxY, visibleBottom)
                    XCTAssertEqual(composer.height,
                                   min(composerHeight, visibleBottom - resting[.chat].minY))
                    XCTAssertFalse(composer.intersects(division))
                    XCTAssertFalse(composer.intersects(typing[.board]))
                    XCTAssertFalse(composer.intersects(typing[.clocks]))
                    assertOccupiedSlotsFit(typing, in: size)
                }
            }
        }
    }

    // MARK: Board depth

    /// Surround Studio's daytime board, which BoardView draws inset in its
    /// slot to fit its sidewall and shadow.
    private func studioDepth(lines: Int = 19) -> BoardDepthPlacement {
        BoardDepthPlacement(boardWidth: lines, boardHeight: lines, showsCoordinates: false, displayScale: 3,
                            depth: SurroundTheme.surroundStudio.board(for: .light).boardDepth)
    }

    private func assertRow(_ row: CGRect, along drawn: CGRect, _ message: String,
                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(row.minX, drawn.minX, accuracy: 0.01, message, file: file, line: line)
        XCTAssertEqual(row.maxX, drawn.maxX, accuracy: 0.01, message, file: file, line: line)
    }

    /// Flat themes keep the frames they had before boards had depth, also
    /// where a board falls just short of the pane its rows span.
    func testBoardsWithoutDepthKeepTheirFrames() {
        let flat = BoardDepthPlacement(boardWidth: 19, boardHeight: 19, showsCoordinates: true,
                                       displayScale: 2, depth: nil)
        let fold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let book = plan(CGSize(width: 867, height: 611), division: fold, panelDivision: fold,
                        usesVerticalToolbar: true, chromeBandTop: 24, boardDepth: flat)
        XCTAssertEqual(book[.board], CGRect(x: 503.75, y: 192, width: 355, height: 355))
        for slot in [GameDetailLayoutPlan.Slot.clocks, .opponent, .actions] {
            XCTAssertEqual(book[slot].minX, 503.5, "\(slot)")
            XCTAssertEqual(book[slot].width, 355.5, "\(slot)")
        }
        let layouts: [(String, (BoardDepthPlacement?) -> GameDetailLayoutPlan)] = [
            ("iPad portrait", { self.plan(CGSize(width: 820, height: 1074), recoveryHeight: 80, boardDepth: $0) }),
            ("iPad landscape", { self.plan(CGSize(width: 1180, height: 820), preview: true, boardDepth: $0) }),
            ("iPad portrait chat", { self.plan(CGSize(width: 820, height: 1074), chat: true, composerHeight: 50,
                                               preview: true, boardDepth: $0) }),
            ("phone landscape analyze", { self.plan(CGSize(width: 756, height: 334), compact: true, analyze: true,
                                                    boardDepth: $0) }),
            ("Duo Closed analyze", { self.plan(CGSize(width: 594, height: 466), compact: true, analyze: true,
                                               usesVerticalToolbar: true, boardDepth: $0) }),
        ]
        for (name, layout) in layouts {
            let without = layout(nil)
            let flatBoard = layout(flat)
            for slot in GameDetailLayoutPlan.Slot.allCases {
                XCTAssertEqual(flatBoard[slot], without[slot], "\(name): \(slot)")
            }
        }
        XCTAssertEqual(plan(CGSize(width: 594, height: 466), compact: true, analyze: true,
                            usesVerticalToolbar: true, boardDepth: flat)[.analysisControls].width, 346)
    }

    func testDepthRowsFollowTheDrawnBoardOnIPad() {
        let depth = studioDepth()
        let portrait = CGSize(width: 820, height: 1074)
        for (size, rows) in [(portrait, [GameDetailLayoutPlan.Slot.clocks, .opponent, .actions]),
                             (CGSize(width: 1180, height: 820), [.opponent, .actions])] {
            let flat = plan(size)
            let p = plan(size, boardDepth: depth)
            XCTAssertEqual(p[.board], flat[.board], "\(size): depth never moves the board")
            let drawn = depth.visibleBoard(in: p[.board])
            XCTAssertGreaterThan(drawn.minX - p[.board].minX, 10, "Studio insets an iPad board")
            for slot in rows {
                assertRow(p[slot], along: drawn, "\(size): \(slot)")
                XCTAssertEqual(p[slot].minY, flat[slot].minY, accuracy: 0.01,
                               "\(size): \(slot) keeps its gap from the board's slot")
            }
        }
        let zen = plan(portrait, zen: true, boardDepth: depth)
        assertRow(zen[.actions], along: depth.visibleBoard(in: zen[.board]), "Zen actions")
        let recovery = plan(portrait, recoveryHeight: 80, boardDepth: depth)
        assertRow(recovery[.status], along: depth.visibleBoard(in: recovery[.board]), "Recovery banner")
        let preview = plan(CGSize(width: 1180, height: 820), preview: true, boardDepth: depth)
        XCTAssertTrue(preview.previewInOpponentRow)
        assertRow(preview[.opponent], along: depth.visibleBoard(in: preview[.board]), "Preview row")
    }

    func testDepthPanelsFollowTheDrawnBoardInRegularPortrait() {
        let depth = studioDepth()
        let size = CGSize(width: 820, height: 1074)
        let chat = plan(size, chat: true, composerHeight: 50, preview: true, boardDepth: depth)
        XCTAssertEqual(chat[.board], plan(size, chat: true, composerHeight: 50, preview: true)[.board])
        let drawnChatBoard = depth.visibleBoard(in: chat[.board])
        assertRow(chat[.preview], along: drawnChatBoard, "Chat preview bar")
        XCTAssertEqual(chat[.chat].minX, drawnChatBoard.minX, accuracy: 0.01, "The conversation above it")
        XCTAssertEqual(chat[.composer].minX, drawnChatBoard.minX, accuracy: 0.01)
        XCTAssertEqual(chat[.chat].maxX, size.width - 24, "Its other side keeps the screen's margin")
        XCTAssertEqual(chat[.actions].minY, drawnChatBoard.minY, accuracy: 0.01)
        XCTAssertEqual(chat[.actions].maxY, drawnChatBoard.maxY, accuracy: 0.01,
                       "More rests level with the sidewall")
        let analysis = plan(size, analyze: true, boardDepth: depth)
        let drawn = depth.visibleBoard(in: analysis[.board])
        assertRow(analysis[.analysis], along: drawn, "Tree")
        assertRow(analysis[.analysisControls], along: drawn, "Controls")
        XCTAssertEqual(analysis[.analysisControls].maxY, plan(size, analyze: true)[.analysisControls].maxY,
                       "The controls keep their gap from the board's slot")
    }

    func testDepthColumnsSpanTheDrawnBoardBesideIt() {
        let depth = studioDepth()
        let closed = CGSize(width: 594, height: 466)
        for zen in [false, true] {
            let flat = plan(closed, compact: true, zen: zen, usesVerticalToolbar: true)
            let p = plan(closed, compact: true, zen: zen, usesVerticalToolbar: true, boardDepth: depth)
            XCTAssertEqual(p[.board], flat[.board])
            let drawn = depth.visibleBoard(in: p[.board])
            XCTAssertGreaterThan(drawn.minY - p[.board].minY, 3)
            XCTAssertEqual((zen ? p[.clocks] : p[.opponent]).minY, drawn.minY, accuracy: 0.01, "Zen \(zen)")
            XCTAssertEqual(p[.actions].maxY, drawn.maxY, accuracy: 0.01, "Zen \(zen)")
            for slot in [GameDetailLayoutPlan.Slot.clocks, .actions] {
                XCTAssertEqual(p[slot].minX, 12, "The column keeps its place")
                XCTAssertEqual(p[slot].width, 126)
            }
        }

        let tall = CGSize(width: 669, height: 893)
        let fold = CGRect(x: 0, y: 436, width: 669, height: 40)
        let book = plan(tall, division: fold, boardDepth: depth)
        XCTAssertEqual(book[.board], CGRect(x: 136, y: 484, width: 397, height: 397))
        let drawnBook = depth.visibleBoard(in: book[.board])
        XCTAssertEqual(book[.opponent].minY, drawnBook.minY, accuracy: 0.01)
        XCTAssertEqual(book[.actions].maxY, drawnBook.maxY, accuracy: 0.01)
        XCTAssertEqual(book[.board].minX - book[.opponent].maxX, 8, "Gutters stay measured from the slot")

        // A 9×9 board has full depth on a phone.
        let phoneDepth = studioDepth(lines: 9)
        let phone = CGSize(width: 750, height: 312)
        let landscape = plan(phone, compact: true, boardDepth: phoneDepth)
        XCTAssertEqual(landscape[.board], CGRect(x: 216, y: 8, width: 296, height: 296))
        let drawnPhone = phoneDepth.visibleBoard(in: landscape[.board])
        XCTAssertGreaterThan(drawnPhone.minY - landscape[.board].minY, 2)
        XCTAssertEqual(landscape[.opponent].minY, drawnPhone.minY, accuracy: 0.01)
        XCTAssertEqual(landscape[.clocks].minY - landscape[.opponent].maxY, 8, accuracy: 0.01)
        XCTAssertEqual(landscape[.actions].maxY, drawnPhone.maxY, accuracy: 0.01)
        XCTAssertEqual(landscape[.actions].minX - landscape[.board].maxX, 12)
    }

    func testDepthRowsInBookWideAndClosedAnalyzeFollowTheDrawnBoard() {
        let depth = studioDepth()
        let wide = CGSize(width: 867, height: 635)
        let fold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let book = plan(wide, division: fold, panelDivision: fold, usesVerticalToolbar: true,
                        fullClockFooterWidth: 123, chromeBandTop: 24, boardDepth: depth)
        XCTAssertEqual(book[.board], CGRect(x: 503.5, y: 192, width: 355.5, height: 355.5))
        let drawnBook = depth.visibleBoard(in: book[.board])
        for slot in [GameDetailLayoutPlan.Slot.clocks, .opponent, .actions] {
            assertRow(book[slot], along: drawnBook, "Book wide \(slot)")
        }
        XCTAssertFalse(book.narrowFullClocks)

        let closed = CGSize(width: 594, height: 466)
        XCTAssertEqual(plan(closed, compact: true, analyze: true, usesVerticalToolbar: true)[.analysisControls].width, 346)
        for coordinates in [false, true] {
            var placement = depth
            placement.showsCoordinates = coordinates
            let p = plan(closed, compact: true, analyze: true, usesVerticalToolbar: true, boardDepth: placement)
            let drawn = placement.visibleBoard(in: p[.board])
            assertRow(p[.analysisControls], along: drawn, "Controls under the board")
            // The branch arrows need the whole 346 pt; a hair less drops them.
            XCTAssertGreaterThanOrEqual(p[.analysisControls].width, 346, "coordinates \(coordinates)")
            XCTAssertLessThan(p[.analysisControls].width, 346.5, "coordinates \(coordinates)")
            XCTAssertGreaterThanOrEqual(p[.analysisControls].minY, p[.board].maxY)
            XCTAssertEqual(p[.clocks].minY, drawn.minY - 5, accuracy: 0.01, "The first clock face meets the face")
            XCTAssertLessThanOrEqual(p[.analysis].maxX, p[.board].minX)
        }
    }

    func testDepthReservesRowsAtTheDrawnWidth() {
        let depth = studioDepth()
        // Book wide: cards (343.6 - 8) / 2 wide need a second footer line.
        let wide = CGSize(width: 867, height: 635)
        let fold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let flatBook = plan(wide, division: fold, panelDivision: fold, usesVerticalToolbar: true,
                            fullClockFooterWidth: 170, chromeBandTop: 24)
        XCTAssertFalse(flatBook.narrowFullClocks)
        XCTAssertEqual(flatBook[.clocks].height, 96)
        let book = plan(wide, division: fold, panelDivision: fold, usesVerticalToolbar: true,
                        fullClockFooterWidth: 170, chromeBandTop: 24, boardDepth: depth)
        XCTAssertTrue(book.narrowFullClocks)
        XCTAssertEqual(book[.clocks].height, 110)
        XCTAssertEqual(book[.board], CGRect(x: 503.5, y: 206, width: 355.5, height: 355.5))

        // iPad portrait: cards (749.6 - 8) / 2 wide.
        let portrait = CGSize(width: 820, height: 1074)
        XCTAssertEqual(plan(portrait, fullClockFooterWidth: 375)[.clocks].height, 96)
        let clocks = plan(portrait, fullClockFooterWidth: 375, boardDepth: depth)
        XCTAssertTrue(clocks.narrowFullClocks)
        XCTAssertEqual(clocks[.clocks].height, 110)

        // A 752 pt action fits the 756 pt row but not the 749.6 pt drawn one.
        func actionPlan(_ size: CGSize, width: CGFloat, depth: BoardDepthPlacement?) -> GameDetailLayoutPlan {
            GameDetailLayoutPlan(size: size, compact: false, zen: false, analyze: false, chat: false,
                                 hidesBoard: false, keyboard: false, accessibility: false, foldsClock: false,
                                 actionSize: CGSize(width: width, height: 48), boardDepth: depth)
        }
        let flatRow = actionPlan(portrait, width: 752, depth: nil)
        XCTAssertFalse(flatRow.wrapsMainAction)
        XCTAssertEqual(flatRow[.actions].height, 52)
        let row = actionPlan(portrait, width: 752, depth: depth)
        XCTAssertTrue(row.wrapsMainAction)
        XCTAssertEqual(row[.actions].height, 96)
        // Regular landscape: a 665 pt action fits the 676 pt board but not its drawn row.
        let landscape = CGSize(width: 1180, height: 820)
        let flatFooter = actionPlan(landscape, width: 665, depth: nil)
        XCTAssertEqual(flatFooter[.board].width, 676)
        XCTAssertEqual(flatFooter[.actions].height, 52)
        let footer = actionPlan(landscape, width: 665, depth: depth)
        XCTAssertTrue(footer.wrapsMainAction)
        XCTAssertEqual(footer[.actions].height, 96)
        XCTAssertEqual(footer[.board].width, 632)
    }

    func testDepthRowsKeepTheirMarginToAHeightBoundBookBoard() {
        // The board is narrower than its pane; the rows overhang the drawn
        // board as much as a flat theme's rows overhang its board.
        let size = CGSize(width: 867, height: 600)
        let fold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let flat = plan(size, division: fold, panelDivision: fold, usesVerticalToolbar: true, chromeBandTop: 24)
        let depth = studioDepth()
        let p = plan(size, division: fold, panelDivision: fold, usesVerticalToolbar: true, chromeBandTop: 24,
                     boardDepth: depth)
        XCTAssertEqual(p[.board], flat[.board])
        XCTAssertLessThan(p[.board].width, flat[.clocks].width)
        let drawn = depth.visibleBoard(in: p[.board])
        let overhang = p[.board].minX - flat[.clocks].minX
        for slot in [GameDetailLayoutPlan.Slot.clocks, .opponent, .actions] {
            XCTAssertEqual(drawn.minX - p[slot].minX, overhang, accuracy: 0.01, "\(slot)")
            XCTAssertEqual(p[slot].maxX - drawn.maxX, overhang, accuracy: 0.01, "\(slot)")
        }
    }

    func testDepthPhoneLandscapePanelsSpanTheDrawnBoard() {
        let depth = studioDepth(lines: 9)
        let size = CGSize(width: 756, height: 334)
        let flatChat = plan(size, compact: true, chat: true, composerHeight: 50)
        let chat = plan(size, compact: true, chat: true, composerHeight: 50, boardDepth: depth)
        XCTAssertEqual(chat[.board], flatChat[.board])
        let drawn = depth.visibleBoard(in: chat[.board])
        XCTAssertGreaterThan(drawn.minY - chat[.board].minY, 2)
        XCTAssertEqual(chat[.chat].minY, drawn.minY, accuracy: 0.01)
        XCTAssertEqual(chat[.actions].maxY, drawn.maxY, accuracy: 0.01)
        XCTAssertEqual(chat[.board].minX - chat[.chat].maxX, 8, "The gutter stays measured from the slot")

        let analysis = plan(size, compact: true, analyze: true, boardDepth: depth)
        let drawnAnalysis = depth.visibleBoard(in: analysis[.board])
        XCTAssertEqual(analysis[.analysis].minY, drawnAnalysis.minY, accuracy: 0.01)
        XCTAssertEqual(analysis[.analysisControls].maxY, drawnAnalysis.maxY, accuracy: 0.01)
    }

    func testCompactPortraitChipsKeepTheScreenMargin() {
        let size = CGSize(width: 393, height: 760)
        let flat = plan(size, compact: true)
        let p = plan(size, compact: true, boardDepth: studioDepth())
        for slot in [GameDetailLayoutPlan.Slot.board, .clocks, .opponent, .actions] {
            XCTAssertEqual(p[slot], flat[slot], "\(slot)")
        }
    }

    private func assertClockPresentation(_ actual: GameDetailLayoutPlan,
                                         equals expected: GameDetailLayoutPlan,
                                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual[.clocks], expected[.clocks], file: file, line: line)
        XCTAssertEqual(actual.clockStyle, expected.clockStyle, file: file, line: line)
        XCTAssertEqual(actual.stackedClocks, expected.stackedClocks, file: file, line: line)
        XCTAssertEqual(actual.clocksInHeader, expected.clocksInHeader, file: file, line: line)
        XCTAssertEqual(actual.showsCurrentPlayerClockOnly, expected.showsCurrentPlayerClockOnly,
                       file: file, line: line)
        XCTAssertEqual(actual.narrowFullClocks, expected.narrowFullClocks, file: file, line: line)
        XCTAssertEqual(actual.narrowCompactClocks, expected.narrowCompactClocks, file: file, line: line)
        XCTAssertEqual(actual.spaciousCompactClocks, expected.spaciousCompactClocks,
                       file: file, line: line)
    }

    private func assertSceneOutsideChat(_ actual: GameDetailLayoutPlan,
                                        equals expected: GameDetailLayoutPlan,
                                        file: StaticString = #filePath, line: UInt = #line) {
        for slot in GameDetailLayoutPlan.Slot.allCases where slot != .chat && slot != .composer {
            XCTAssertEqual(actual[slot], expected[slot], "Keyboard changed \(slot)",
                           file: file, line: line)
        }
        assertClockPresentation(actual, equals: expected, file: file, line: line)
        XCTAssertEqual(actual.verticalOpponentIdentity, expected.verticalOpponentIdentity,
                       file: file, line: line)
        XCTAssertEqual(actual.verticalActions, expected.verticalActions, file: file, line: line)
        XCTAssertEqual(actual.verticalAnalysisTree, expected.verticalAnalysisTree, file: file, line: line)
    }

    private func assertOccupiedSlotsFit(_ p: GameDetailLayoutPlan, in size: CGSize,
                                        file: StaticString = #filePath, line: UInt = #line) {
        let bounds = CGRect(origin: .zero, size: size)
        for slot in GameDetailLayoutPlan.Slot.allCases where !p[slot].isEmpty {
            XCTAssertTrue(bounds.contains(p[slot]), "\(slot): \(p[slot]) outside \(bounds)", file: file, line: line)
        }
        XCTAssertEqual(p[.board].width, p[.board].height, file: file, line: line)
    }

}
