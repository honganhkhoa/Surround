import SwiftUI
import XCTest

final class MessagesLayoutTests: XCTestCase {
    func testWidthBelowMessagesBreakpointUsesOnePane() {
        let layout = MessagesColumnLayout(size: CGSize(width: 659, height: 900))

        XCTAssertFalse(layout.usesColumns)
        XCTAssertEqual(layout.inboxWidth, 659)
        XCTAssertEqual(layout.gap, 0)
    }

    func testBreakpointAndDuoPortraitUse360PointInbox() {
        let widths: [CGFloat] = [660, 669]
        for width in widths {
            let layout = MessagesColumnLayout(size: CGSize(width: width, height: 900))

            XCTAssertTrue(layout.usesColumns, "Width \(width) must retain portrait columns")
            XCTAssertEqual(layout.inboxWidth, 360)
            XCTAssertEqual(layout.gap, 1)
        }
    }

    func testAuthoritativeCompactModeOverridesStaleExpandedWidth() {
        // A covered destination can retain its expanded bounds during closing.
        let layout = MessagesColumnLayout(size: CGSize(width: 669, height: 900), usesColumns: false)

        XCTAssertFalse(layout.usesColumns)
        XCTAssertEqual(layout.inboxWidth, 669)
        XCTAssertEqual(layout.gap, 0)
    }

    func testAuthoritativeColumnModeSurvivesToolbarReducedWidth() {
        // Native toolbar space can reduce the content width below the breakpoint.
        let layout = MessagesColumnLayout(size: CGSize(width: 585, height: 900), usesColumns: true)

        XCTAssertTrue(layout.usesColumns)
        XCTAssertEqual(layout.inboxWidth, 360)
        XCTAssertEqual(layout.gap, 1)
    }

    func testWideTabletKeepsInboxWidthWhileDetailUsesRemainingSpace() {
        let widths: [CGFloat] = [834, 1024, 1366]
        for width in widths {
            let layout = MessagesColumnLayout(size: CGSize(width: width, height: 1024))

            XCTAssertTrue(layout.usesColumns)
            XCTAssertEqual(layout.inboxWidth, 360)
            XCTAssertEqual(layout.gap, 1)
        }
    }

    func testBookUsesEqualPanesAtTheSystemVerticalDivision() {
        let size = CGSize(width: 1104, height: 720)
        let division = CGRect(x: 540, y: 0, width: 24, height: 720)
        let layout = MessagesColumnLayout(size: size, divisions: [division])

        XCTAssertTrue(layout.usesColumns)
        XCTAssertEqual(layout.inboxWidth, 540)
        XCTAssertEqual(layout.gap, 24)
        XCTAssertEqual(layout.inboxWidth, size.width - layout.inboxWidth - layout.gap)
        XCTAssertEqual(layout.inboxWidth, division.minX)
    }

    func testHorizontalPortraitDivisionKeepsColumnsWithoutAddingFoldGap() {
        let size = CGSize(width: 669, height: 1000)
        let division = CGRect(x: 0, y: 488, width: 669, height: 24)
        let flat = MessagesColumnLayout(size: size)
        let folded = MessagesColumnLayout(size: size, divisions: [division])

        XCTAssertEqual(folded, flat)
        XCTAssertTrue(folded.usesColumns)
        XCTAssertEqual(folded.inboxWidth, 360)
        XCTAssertEqual(folded.gap, 1, "The horizontal fold adds no center clearance to the columns")
    }

    func testNativeBookDivisionStaysAlignedWhenTrailingToolbarConsumesSpace() {
        // The observed 951-point native host reserves 84 points for its
        // trailing toolbar. The fold remains centered in the physical host.
        let size = CGSize(width: 867, height: 635)
        let division = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let layout = MessagesColumnLayout(size: size, divisions: [division])

        XCTAssertTrue(layout.usesColumns)
        XCTAssertEqual(layout.inboxWidth, 455.5)
        XCTAssertEqual(layout.gap, 40)
        XCTAssertEqual(size.width - layout.inboxWidth - layout.gap, 371.5)
    }

    func testHorizontalDivisionBelowBreakpointKeepsCompactLayout() {
        let size = CGSize(width: 600, height: 1000)
        let division = CGRect(x: 0, y: 488, width: 600, height: 24)
        let layout = MessagesColumnLayout(size: size, divisions: [division])

        XCTAssertFalse(layout.usesColumns)
        XCTAssertEqual(layout.inboxWidth, 600)
        XCTAssertEqual(layout.gap, 0)
    }

    func testKeyboardReducedPortraitViewportKeepsColumnsAndInboxWidth() {
        // Native keyboard avoidance can leave only the upper display visible.
        // The shorter viewport must not be interpreted as a landscape pose or
        // rearranged into top/bottom panes; the system owns composer avoidance.
        let size = CGSize(width: 669, height: 470)
        let divisionBelowViewport = CGRect(x: 0, y: 488, width: 669, height: 24)
        let layout = MessagesColumnLayout(size: size, divisions: [divisionBelowViewport])

        XCTAssertTrue(layout.usesColumns)
        XCTAssertEqual(layout.inboxWidth, 360)
        XCTAssertEqual(layout.gap, 1)
    }

}
