//
//  SceneCoverPolicyTests.swift
//  SurroundTests
//
//  The scene cover's window choices: which windows stop editing when it
//  rises, which window takes key back when it lowers, and when a window that
//  opens covered raises while its anchor attaches.
//

import XCTest

final class SceneCoverPolicyTests: XCTestCase {
    private typealias PolicyWindow = SceneCoverPolicy.Window<Int>

    // MARK: - Window choices

    /// The app, a text effects window, a hidden window, the cover and the keyboard.
    private let scene = [
        PolicyWindow(id: 1, level: 0, isHidden: false),
        PolicyWindow(id: 2, level: 1, isHidden: false),
        PolicyWindow(id: 3, level: 0, isHidden: true),
        PolicyWindow(id: 9, level: 2_001, isHidden: false),
        PolicyWindow(id: 4, level: 10_000_000, isHidden: false),
    ]

    func testEditingEndsOnlyInVisibleWindowsBelowTheCover() {
        XCTAssertEqual(SceneCoverPolicy.windowsBelow(9, in: scene, coverLevel: 2_001), [1, 2])
    }

    func testKeyReturnsToTheWindowThatHadIt() {
        XCTAssertEqual(SceneCoverPolicy.keyWindowAfterLowering(
            scene, cover: 9, coverLevel: 2_001, previousKey: 2, content: 1), 2)
    }

    func testKeyFallsBackToTheContentWindow() {
        // The previous key window is hidden now, or sits above the cover.
        for previous in [3, 4] {
            XCTAssertEqual(SceneCoverPolicy.keyWindowAfterLowering(
                scene, cover: 9, coverLevel: 2_001, previousKey: previous, content: 1), 1)
        }
    }

    func testKeyFallsBackToTheLowestVisibleWindow() {
        XCTAssertEqual(SceneCoverPolicy.keyWindowAfterLowering(
            scene, cover: 9, coverLevel: 2_001, previousKey: nil, content: nil), 1)
        XCTAssertEqual(SceneCoverPolicy.keyWindowAfterLowering(
            scene, cover: 9, coverLevel: 2_001, previousKey: nil, content: 3), 1)
    }

    func testNoWindowTakesKeyWhenNoneQualifies() {
        let alone = [PolicyWindow(id: 9, level: 2_001, isHidden: false),
                     PolicyWindow(id: 4, level: 10_000_000, isHidden: false)]
        XCTAssertNil(SceneCoverPolicy.keyWindowAfterLowering(
            alone, cover: 9, coverLevel: 2_001, previousKey: 4, content: nil))
    }

    // MARK: - Raising while attaching

    func testOnlyAScenesFirstRequestRaisesWhileAttaching() {
        /// One delivery from an anchor to its scene's cover.
        struct Delivery: Equatable {
            var attaching, isFirstRequest, optionOn, wantsRaised, isRaised: Bool
        }
        // Every combination of the five inputs.
        let deliveries = (0..<32).map { bits in
            Delivery(attaching: bits & 1 != 0, isFirstRequest: bits & 2 != 0, optionOn: bits & 4 != 0,
                     wantsRaised: bits & 8 != 0, isRaised: bits & 16 != 0)
        }
        let raising = deliveries.filter { delivery in
            var options = SceneCoverOptions()
            options.raisesWhileAttaching = delivery.optionOn
            return SceneCoverPolicy.raisesWhileAttaching(
                attaching: delivery.attaching, isFirstRequest: delivery.isFirstRequest, options: options,
                wantsRaised: delivery.wantsRaised, isRaised: delivery.isRaised)
        }
        // Only a scene's first request, delivered as its anchor attaches, with
        // the option on, asking to raise a cover that is still lowered. An
        // update, a later re-attach or a cover already up waits a main turn.
        XCTAssertEqual(raising, [Delivery(attaching: true, isFirstRequest: true, optionOn: true,
                                          wantsRaised: true, isRaised: false)])
        // The shipped options raise a window that opens covered at attach.
        XCTAssertTrue(SceneCoverPolicy.raisesWhileAttaching(
            attaching: true, isFirstRequest: true, options: SceneCoverOptions(),
            wantsRaised: true, isRaised: false))
    }
}
