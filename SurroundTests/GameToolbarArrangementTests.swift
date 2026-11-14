import XCTest

/// The toolbar split (notices build item 4) matches the inline branches it
/// replaced: GameDetailView.swift:453-459, 1152 and 1503-1588 at de44c66.
final class GameToolbarArrangementTests: XCTestCase {
    private struct Inputs {
        var isVerticalToolbar, compact, landscape, isCatalyst, navigationBarHidden: Bool
        var compactLandscape: Bool { compact && landscape }   // as GameDetailView derives it
    }

    private let allInputs: [Inputs] = (0..<32).map { b in
        Inputs(isVerticalToolbar: b & 1 != 0, compact: b & 2 != 0, landscape: b & 4 != 0,
               isCatalyst: b & 8 != 0, navigationBarHidden: b & 16 != 0)
    }

    private func arrangement(_ i: Inputs) -> GameToolbarArrangement {
        GameToolbarArrangement(isVerticalToolbar: i.isVerticalToolbar, compact: i.compact,
                               compactLandscape: i.compactLandscape, isCatalyst: i.isCatalyst)
    }

    private func originalPlacesTop(_ i: Inputs) -> Bool {          // 453-459
        i.isCatalyst ? true : !i.isVerticalToolbar && (!i.compact || i.compactLandscape)
    }

    private func originalArrangement(_ i: Inputs) -> GameToolbarArrangement {   // 1507, 1552, 1569
        if i.isVerticalToolbar { return .vertical }
        if i.compact && !i.compactLandscape && !originalPlacesTop(i) { return .bottomBar }
        if i.compactLandscape { return .compactLandscape }
        return .wide
    }

    func testArrangementFollowsTheBranchesItReplaced() {
        for i in allInputs {
            XCTAssertEqual(arrangement(i), originalArrangement(i), "\(i)")
            XCTAssertEqual(GameToolbarArrangement.placesActiveGamesAtTop(
                isVerticalToolbar: i.isVerticalToolbar, compact: i.compact,
                compactLandscape: i.compactLandscape, isCatalyst: i.isCatalyst), originalPlacesTop(i), "\(i)")
            // usesBottomChatToolbar, 1152
            XCTAssertEqual(arrangement(i) == .bottomBar, i.compact && !i.compactLandscape
                           && !originalPlacesTop(i) && !i.isVerticalToolbar, "\(i)")
            // The wide branch's repeated placesActiveGamesAtTop (1580) always held.
            if originalArrangement(i) == .wide { XCTAssertTrue(originalPlacesTop(i), "\(i)") }
        }
    }

    func testEachArrangementPlacesTheSlotWhereItsBranchDid() {
        for i in allInputs {
            let expected: GameActiveGamesPlacement
            switch originalArrangement(i) {
            case .vertical:   // 1508 (Closed) precedes 1523 (navigationBarHidden)
                expected = !i.compact && i.navigationBarHidden ? .railSeparated : .rail
            case .bottomBar: expected = .bottomBar
            case .compactLandscape: expected = .topBarBeforeModes
            case .wide: expected = .topBarAfterModes
            }
            XCTAssertEqual(arrangement(i).activeGamesPlacement(
                compact: i.compact, navigationBarHidden: i.navigationBarHidden), expected, "\(i)")
        }
    }

    func testPlacementsMapToTheDrawnForms() {
        XCTAssertEqual([GameActiveGamesPlacement.rail, .railSeparated, .bottomBar, .topBarBeforeModes,
                        .topBarAfterModes].map(\.form), [.rail, .rail, .bottomBar, .topBar, .topBar])
    }
}
