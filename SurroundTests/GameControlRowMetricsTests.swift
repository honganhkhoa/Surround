import SwiftUI
import XCTest

final class GameControlRowMetricsTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    func testPlayingAndFinishedReserveOnlyPlayingLabels() {
        let expected = GameControlRowMetrics(
            dynamicTypeSize: .large, locale: locale,
            localizedLabels: ["Pass", "Submit move", "Rematch", "Next (999+)"]
        )
        for phase: OGSGamePhase? in [.play, .finished, nil] {
            let metrics = GameControlRowMetrics(dynamicTypeSize: .large,
                                                locale: locale, phase: phase)
            XCTAssertEqual(metrics.horizontalSize, expected.horizontalSize)
            XCTAssertEqual(metrics.columnHeight(at: 104), expected.columnHeight(at: 104))
            XCTAssertEqual(metrics.rowHeight(at: 210), expected.rowHeight(at: 210))
        }
    }

    func testScoringDoesNotReservePlayOrRematchLabels() {
        // The logic-test target has no app localization catalog, so Accept uses
        // its source key here rather than the catalog's short English translation.
        let expected = GameControlRowMetrics(
            dynamicTypeSize: .accessibility3, locale: locale,
            localizedLabels: ["Accept removed stones", "Clear estimates"]
        )
        let scoring = GameControlRowMetrics(dynamicTypeSize: .accessibility3,
                                            locale: locale, phase: .stoneRemoval)
        XCTAssertEqual(scoring.horizontalSize, expected.horizontalSize)
        XCTAssertEqual(scoring.columnHeight(at: 104), expected.columnHeight(at: 104))
        XCTAssertEqual(scoring.fitsColumn(at: 104), expected.fitsColumn(at: 104))
    }

    func testNameBorrowsOnlyUnusedReservationBeforeActionShrinks() {
        let metrics = GameControlRowMetrics(dynamicTypeSize: .large, locale: locale)
        let actionWidth: CGFloat = 64
        let minimum = actionWidth + GameControlRowMetrics.spacing + GameControlRowMetrics.moreDiameter
        let reservation = metrics.horizontalSize.width
        XCTAssertGreaterThan(reservation, minimum + 12)

        XCTAssertEqual(metrics.rowSize(proposedWidth: nil, mainActionWidth: actionWidth,
                                       wrapsMainAction: false).width, reservation)
        XCTAssertEqual(metrics.rowSize(proposedWidth: reservation - 12, mainActionWidth: actionWidth,
                                       wrapsMainAction: false).width, reservation - 12)
        XCTAssertEqual(metrics.rowSize(proposedWidth: 0, mainActionWidth: actionWidth,
                                       wrapsMainAction: false).width, minimum)
        XCTAssertEqual(metrics.rowSize(proposedWidth: reservation + 100, mainActionWidth: actionWidth,
                                       wrapsMainAction: false).width, reservation)
    }

    func testOnlyMoreCanYieldTheEntireUnusedMainActionSlot() {
        let metrics = GameControlRowMetrics(dynamicTypeSize: .large, locale: locale)
        XCTAssertEqual(metrics.rowSize(proposedWidth: 0, mainActionWidth: 0,
                                       wrapsMainAction: false).width,
                       GameControlRowMetrics.moreDiameter)
        XCTAssertEqual(metrics.rowSize(proposedWidth: nil, mainActionWidth: 0,
                                       wrapsMainAction: false), metrics.horizontalSize)
    }

    func testCurrentActionNeverChangesReservedRowHeight() {
        let metrics = GameControlRowMetrics(dynamicTypeSize: .accessibility3,
                                            locale: locale, phase: .play)
        let reserved = metrics.horizontalSize
        // Includes no action, Pass, Next, and a long translated Clear estimates
        // still reachable from Estimate score during the playing server phase.
        for currentWidth: CGFloat in [0, 64, 120, reserved.width + 60] {
            let row = metrics.rowSize(proposedWidth: 300, mainActionWidth: currentWidth,
                                      wrapsMainAction: false)
            XCTAssertEqual(row.height, reserved.height)
            if currentWidth > 0 {
                XCTAssertGreaterThanOrEqual(row.width,
                    currentWidth + GameControlRowMetrics.spacing + GameControlRowMetrics.moreDiameter)
            }
            XCTAssertEqual(metrics.horizontalSize, reserved,
                           "The current action must not change the board's phase budget")
        }
    }

    func testLastResortWrappingKeepsPhaseHeightAcrossActionChanges() {
        let metrics = GameControlRowMetrics(dynamicTypeSize: .accessibility5,
                                            locale: locale, phase: .stoneRemoval)
        let width: CGFloat = 359
        for currentWidth: CGFloat in [0, 64, 200, 500] {
            let row = metrics.rowSize(proposedWidth: width, mainActionWidth: currentWidth,
                                      wrapsMainAction: true)
            XCTAssertEqual(row.width, width)
            XCTAssertEqual(row.height, metrics.rowHeight(at: width))
        }
    }

    func testUnboundedLayoutProposalStillReturnsFiniteSize() {
        let metrics = GameControlRowMetrics(dynamicTypeSize: .accessibility5,
                                            locale: locale)
        for wraps in [false, true] {
            for currentWidth: CGFloat in [64, .infinity, .nan] {
                let size = metrics.rowSize(proposedWidth: .infinity, mainActionWidth: currentWidth,
                                           wrapsMainAction: wraps)
                XCTAssertTrue(size.width.isFinite)
                XCTAssertTrue(size.height.isFinite)
            }
        }
    }

    func testTwoLineStatusBudgetScalesWithoutDependingOnPhaseOrActionLabels() {
        let regular = GameControlRowMetrics(dynamicTypeSize: .large, locale: locale)
        let large = GameControlRowMetrics(dynamicTypeSize: .accessibility3, locale: locale)
        let scoring = GameControlRowMetrics(dynamicTypeSize: .accessibility3, locale: locale,
                                             phase: .stoneRemoval)
        let longLabels = GameControlRowMetrics(dynamicTypeSize: .accessibility3, locale: locale,
                                               localizedLabels: [String(repeating: "Long action ", count: 12)])
        XCTAssertGreaterThan(large.twoLineStatusHeight, regular.twoLineStatusHeight)
        XCTAssertEqual(large.twoLineStatusHeight, scoring.twoLineStatusHeight)
        XCTAssertEqual(large.twoLineStatusHeight, longLabels.twoLineStatusHeight)
    }
}
