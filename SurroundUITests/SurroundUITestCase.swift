//
//  SurroundUITestCase.swift
//  SurroundUITests
//
//  Shared interaction helpers for deterministic UI and screenshot tests.
//

import XCTest
import UIKit

class SurroundUITestCase: XCTestCase {
    func registerAppTermination(_ app: XCUIApplication) {
        addTeardownBlock {
            app.terminate()
        }
    }

    func selectSegment(
        at index: Int,
        in identifier: String,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Older capture journeys describe the three game tasks as segment
        // indices. Route those calls through the native toolbar controls while
        // keeping unrelated segmented controls (ratings, matchmaking) intact.
        if identifier == SurroundUITestContract.AccessibilityID.gameDisplayModePicker {
            switch index {
            case 0:
                setGameAnalyzing(true, in: app, file: file, line: line)
            case 1:
                setGameAnalyzing(false, in: app, file: file, line: line)
                setGameChatVisible(false, in: app, file: file, line: line)
            case 2:
                openGameChat(in: app, file: file, line: line)
            default:
                XCTFail("Unknown game display mode \(index)", file: file, line: line)
            }
            return
        }
        let controls = app
            .descendants(matching: .segmentedControl)
            .matching(identifier: identifier)
        XCTAssertTrue(
            controls.firstMatch.waitForExistence(timeout: 10),
            "Expected a segmented control named \(identifier)",
            file: file,
            line: line
        )

        var hittableSegment: XCUIElement?
        for controlIndex in 0..<controls.count {
            let candidate = controls
                .element(boundBy: controlIndex)
                .buttons
                .element(boundBy: index)
            if candidate.exists && candidate.isHittable {
                hittableSegment = candidate
                break
            }
        }

        guard let hittableSegment else {
            XCTFail(
                "Expected segment \(index) in \(identifier) to be hittable",
                file: file,
                line: line
            )
            return
        }
        hittableSegment.tap()
    }

    func gameAnalyzeControl(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ OR identifier == %@",
            SurroundUITestContract.AccessibilityID.gameAnalyzeToggle,
            SurroundUITestContract.AccessibilityID.gameDisplayModePicker + ".analyze"
        )).firstMatch
    }

    func gameChatControl(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.gameDisplayModePicker + ".chat"
        ).firstMatch
    }

    func gameToolbarToggleIsOn(_ control: XCUIElement) -> Bool {
        guard control.exists else { return false }
        return control.isSelected || (control.value as? String) == "1"
    }

    func setGameAnalyzing(
        _ analyzing: Bool,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        setGameToolbarToggle(
            gameAnalyzeControl(in: app), selected: analyzing,
            labels: ["Analyze mode", "Playback mode"],
            isPresented: {
                app.descendants(matching: .any).matching(identifier:
                    SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar).firstMatch.exists
            },
            in: app, file: file, line: line
        )
    }

    func openGameChat(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        setGameChatVisible(true, in: app, file: file, line: line)
    }

    func setGameChatVisible(
        _ visible: Bool,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        setGameToolbarToggle(
            gameChatControl(in: app), selected: visible,
            labels: ["Chat"],
            isPresented: {
                app.descendants(matching: .any).matching(identifier:
                    SurroundUITestContract.AccessibilityID.gameChatLog).firstMatch.exists
            },
            in: app, file: file, line: line
        )
    }

    private func setGameToolbarToggle(
        _ control: XCUIElement,
        selected: Bool,
        labels: [String],
        isPresented: () -> Bool,
        in app: XCUIApplication,
        file: StaticString,
        line: UInt
    ) {
        if isPresented() == selected { return }
        var target = control
        let overflows = app.buttons.matching(NSPredicate(
            format: "identifier IN %@ OR label == %@",
            ["OverflowBarButtonItem", "BottomOverflowBarButtonItem", "More"], "More"
        ))
        var overflow: XCUIElement?
        // The toggle can briefly read as not hittable while no overflow shows
        // either, although it is on screen a moment later (iPadOS 26.5,
        // October 2026). Wait for one of them; a collapsed toolbar shows its
        // overflow at once.
        let reachable = pollUntil(timeout: 5) {
            if target.exists && target.isHittable { return true }
            overflow = overflows.allElementsBoundByIndex.first { $0.isHittable }
            return overflow != nil
        }
        if let overflow {
            overflow.tap()
            if !target.exists || !target.isHittable {
                let menuActions = app.buttons.matching(NSPredicate(format: "label IN %@", labels))
                target = menuActions.allElementsBoundByIndex.first { $0.isHittable }
                    ?? menuActions.firstMatch
            }
        } else if !reachable {
            keepHierarchy(of: app, name: "missing game toolbar overflow")
            XCTFail("Expected the game mode or native toolbar overflow", file: file, line: line)
            return
        }
        XCTAssertTrue(pollUntil(timeout: 5) { target.exists && target.isHittable },
                      "Expected the native game mode action", file: file, line: line)
        #if targetEnvironment(macCatalyst)
        target.click()
        #else
        target.tap()
        #endif
        // Native overflow can remove or replace its toggle node after tapping.
        // The destination is the stable indication of the selected panel.
        let changed = pollUntil(timeout: 10) {
            isPresented() == selected
        }
        if !changed {
            print("[GameToolbarToggle] expected=\(selected) control=\(target.debugDescription)\n\(app.debugDescription)")
            keepHierarchy(of: app, name: "game toolbar toggle did not change")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Game toolbar toggle did not change"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertTrue(
            changed,
            "Expected the game toolbar toggle to become \(selected ? "on" : "off")",
            file: file, line: line
        )
    }

    /// Whether the main board is on screen. Game Detail keeps a hidden board
    /// mounted in a layout slot shrunk to nothing, so the board can remain in
    /// the accessibility tree with an empty frame.
    func gameBoardIsShown(in app: XCUIApplication) -> Bool {
        app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.gameBoard)
            .allElementsBoundByIndex.contains { board in
                let frame = board.frame
                return !frame.isEmpty && !frame.isInfinite && frame.intersects(app.frame)
            }
    }

    func dismissCompactChatInputAndWaitForLayout(
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let chatLog = requiredElement(
            SurroundUITestContract.AccessibilityID.gameChatLog,
            in: app,
            matching: .scrollView,
            timeout: timeout,
            file: file,
            line: line
        )
        let input = requiredElement(
            SurroundUITestContract.AccessibilityID.gameChatInput,
            in: app,
            matching: .textField,
            timeout: timeout,
            file: file,
            line: line
        )
        let chatIsReady = pollUntil(timeout: timeout) {
            input.isHittable
                && chatLog.isHittable
                && chatLog.frame.width > 8
                && chatLog.frame.height > 8
        }
        if !chatIsReady {
            keepHierarchy(
                of: app,
                name: "compact chat not ready"
            )
        }
        XCTAssertTrue(
            chatIsReady,
            "Expected the compact chat composer and log before dismissing focus.",
            file: file,
            line: line
        )

        // Opening chat never focuses the composer (v145); the keyboard
        // appears only when the field is tapped. A retained focus from earlier
        // typing is still dismissed through the log's background.
        if chatInputHasKeyboardFocus(in: app) {
            guard tapChatLogBackground(
                chatLog, in: app, file: file, line: line
            ) else { return }
        }

        XCTAssertTrue(
            pollUntil(timeout: timeout) {
                !chatInputHasKeyboardFocus(in: app)
                    && !softwareKeyboardIsVisible(app.keyboards.firstMatch, in: app)
            },
            "Expected the compact chat keyboard to disappear before capture.",
            file: file,
            line: line
        )

        let board = app.descendants(matching: .any)
            .matching(
                identifier: SurroundUITestContract.AccessibilityID.gameBoard
            )
            .firstMatch
        var previousFrame: CGRect?
        var stableFrameCount = 0
        XCTAssertTrue(
            pollUntil(timeout: timeout) {
                guard board.exists else {
                    previousFrame = nil
                    stableFrameCount = 0
                    return false
                }

                let currentFrame = board.frame
                guard currentFrame.width > 1,
                      currentFrame.height > 1,
                      currentFrame.intersects(app.frame) else {
                    previousFrame = currentFrame
                    stableFrameCount = 0
                    return false
                }

                if let previousFrame,
                   abs(previousFrame.minX - currentFrame.minX) <= 0.5,
                   abs(previousFrame.minY - currentFrame.minY) <= 0.5,
                   abs(previousFrame.width - currentFrame.width) <= 0.5,
                   abs(previousFrame.height - currentFrame.height) <= 0.5 {
                    stableFrameCount += 1
                } else {
                    stableFrameCount = 1
                }
                previousFrame = currentFrame
                return stableFrameCount >= 3
            },
            "Expected the compact game board layout to stabilize before capture.",
            file: file,
            line: line
        )
        assertNoSelectedChatItem(
            in: chatLog,
            timeout: min(timeout, 3),
            file: file,
            line: line
        )
    }

    func dismissSoftwareKeyboardIfNeeded(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #if !targetEnvironment(macCatalyst)
        let inputWasFocusedOrKeyboardVisible = pollUntil(timeout: 2) {
            chatInputHasKeyboardFocus(in: app)
                || softwareKeyboardIsVisible(
                    app.keyboards.firstMatch,
                    in: app
                )
        }
        guard inputWasFocusedOrKeyboardVisible else {
            return
        }

        let chatLog = requiredElement(
            SurroundUITestContract.AccessibilityID.gameChatLog,
            in: app,
            matching: .scrollView,
            timeout: 10,
            file: file,
            line: line
        )
        let viewport = visibleChatLogViewport(chatLog.frame, in: app)
        // The sharing composer and keyboard can leave a sliver of transcript
        // (11-inch landscape), where rows cover the background. Tap outside
        // chat instead; the first such tap only ends editing.
        let usedChatBackground = viewport.width > 8 && viewport.height >= 44
            && chatLog.isHittable
        if usedChatBackground {
            guard tapChatLogBackground(
                chatLog, in: app, file: file, line: line
            ) else { return }
        } else {
            let board = app.descendants(matching: .any).matching(
                identifier: SurroundUITestContract.AccessibilityID.gameBoard
            ).firstMatch
            let frame = board.exists ? board.frame : .null
            let point = CGPoint(x: frame.minX + frame.width * 0.1,
                                y: frame.minY + frame.height * 0.1)
            let keyboard = app.keyboards.firstMatch
            let hasUncoveredBoard = board.exists && board.isHittable
                && app.frame.contains(point)
                && (!keyboard.exists || !keyboard.frame.contains(point))
            // Compact layouts put the clocks in the header; regular layouts
            // keep them beside or above the board. A hidden layout slot can
            // leave a squeezed copy at the content's corner; take the largest.
            let clock = app.buttons.matching(identifier: "game.clock.black")
                .allElementsBoundByIndex.filter {
                    $0.isHittable && app.frame.contains($0.frame)
                        && (!keyboard.exists || !keyboard.frame.intersects($0.frame))
                }
                .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            if !hasUncoveredBoard, let clock, softwareKeyboardIsVisible(keyboard, in: app) {
                // Sharing can hide the main board and leave no history
                // gutter. A clock is the remaining intended first-tap
                // keyboard dismissal target.
                clock.tap()
                XCTAssertFalse(app.staticTexts["Time control"].exists,
                               "The first clock tap dismisses focus without opening details",
                               file: file, line: line)
            } else {
                // Preserve the board-tap/no-move acceptance in wide layouts.
                guard tapBoardToDismissChatKeyboard(
                    in: app, file: file, line: line
                ) else { return }
            }
        }
        let dismissed = pollUntil(timeout: 10) {
            !chatInputHasKeyboardFocus(in: app)
                && !softwareKeyboardIsVisible(app.keyboards.firstMatch, in: app)
        }
        if !dismissed {
            keepHierarchy(of: app, name: "chat composer focus not dismissed")
        }
        XCTAssertTrue(
            dismissed,
            "Expected the chat composer to lose focus and its keyboard to be dismissed",
            file: file,
            line: line
        )
        if usedChatBackground {
            assertNoSelectedChatItem(
                in: chatLog,
                timeout: 3,
                file: file,
                line: line
            )
        }
        #endif
    }

    private func tapBoardToDismissChatKeyboard(
        in app: XCUIApplication,
        file: StaticString,
        line: UInt
    ) -> Bool {
        let board = app.descendants(matching: .any).matching(
            identifier: SurroundUITestContract.AccessibilityID.gameBoard
        ).firstMatch
        guard board.exists, board.isHittable else {
            keepHierarchy(of: app, name: "no uncovered board for keyboard dismissal")
            XCTFail("Expected a chat gutter or uncovered board to dismiss the keyboard",
                    file: file, line: line)
            return false
        }
        let frame = board.frame
        let point = CGPoint(x: frame.minX + frame.width * 0.1,
                            y: frame.minY + frame.height * 0.1)
        let keyboard = app.keyboards.firstMatch
        guard app.frame.contains(point),
              !keyboard.exists || !keyboard.frame.contains(point) else {
            XCTFail("Expected the board dismissal tap to be above the keyboard",
                    file: file, line: line)
            return false
        }
        let boardValue = board.value as? String
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap()
        let dismissed = pollUntil(timeout: 10) { !self.chatInputHasKeyboardFocus(in: app) }
        XCTAssertTrue(dismissed, "The first board tap must dismiss chat focus",
                      file: file, line: line)
        XCTAssertEqual(board.value as? String, boardValue,
                       "The keyboard dismissal tap must not change the Go position or marks",
                       file: file, line: line)
        return dismissed
    }

    // The chat background clears FocusState and dismisses the keyboard in one
    // app gesture. Tapping the system Hide keyboard control first introduces
    // another transition that can leave XCTest waiting for keyboard animations.
    private func tapChatLogBackground(
        _ chatLog: XCUIElement,
        in app: XCUIApplication,
        file: StaticString,
        line: UInt
    ) -> Bool {
        let frame = chatLog.frame
        let viewport = visibleChatLogViewport(frame, in: app)
        let gutterX = chatLogGutterX(frame, in: app)
        guard viewport.width > 8,
              viewport.height > 8,
              viewport.minX <= gutterX, gutterX <= viewport.maxX,
              chatLog.isHittable else {
            keepHierarchy(of: app, name: "chat background has no usable viewport")
            XCTFail(
                "Expected a visible, hittable chat gutter before dismissing focus; "
                    + "frame: \(frame), visible viewport: \(viewport)",
                file: file,
                line: line
            )
            return false
        }

        // Use the validated rectangle, without resolving the log's origin again
        // after a keyboard or layout transition has changed its dimensions.
        let appFrame = app.frame
        app
            .coordinate(withNormalizedOffset: .zero)
            .withOffset(
                CGVector(
                    dx: gutterX - appFrame.minX,
                    dy: viewport.midY - appFrame.minY
                )
            )
            .tap()
        return true
    }

    // The log's 10-point horizontal padding leaves a background gutter on both
    // sides. iPadOS 27 ignores taps in a strip along the screen's leading edge
    // that is wider than that gutter, so a log that starts at the edge (the
    // compact layout) is tapped in its trailing gutter instead.
    private func chatLogGutterX(
        _ frame: CGRect,
        in app: XCUIApplication
    ) -> CGFloat {
        let leadingScreenEdgeInset: CGFloat = 24
        if frame.minX - app.frame.minX < leadingScreenEdgeInset {
            return frame.maxX - 4
        }
        return frame.minX + 4
    }

    func visibleChatLogViewport(
        _ frame: CGRect,
        in app: XCUIApplication
    ) -> CGRect {
        let viewport = frame.intersection(app.frame)
        guard !viewport.isNull, !viewport.isEmpty else { return .zero }

        var top = viewport.minY
        var bottom = viewport.maxY
        let navigationBar = app.navigationBars.firstMatch
        if navigationBar.exists {
            let navigationFrame = navigationBar.frame
            if navigationFrame.intersects(viewport) {
                top = max(top, navigationFrame.maxY)
            }
        }
        let preview = app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID
                .gameVariationSharePreview)
            .firstMatch
        let input = app.textFields
            .matching(identifier: SurroundUITestContract.AccessibilityID
                .gameChatInput)
            .firstMatch
        for composerElement in [preview, input] where composerElement.exists {
            bottom = min(bottom, composerElement.frame.minY)
        }
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            let keyboardFrame = keyboard.frame
            let gutterX = chatLogGutterX(frame, in: app)
            if !keyboardFrame.isEmpty,
               keyboardFrame.intersects(viewport),
               keyboardFrame.minX <= gutterX, gutterX <= keyboardFrame.maxX {
                bottom = min(bottom, keyboardFrame.minY)
            }
        }
        return CGRect(
            x: viewport.minX, y: top, width: viewport.width,
            height: max(0, bottom - top)
        )
    }

    func chatInputHasKeyboardFocus(in app: XCUIApplication) -> Bool {
        let input = app.textFields
            .matching(
                identifier:
                    SurroundUITestContract.AccessibilityID.gameChatInput
            )
            .firstMatch
        return input.exists
            && input.debugDescription.contains("Keyboard Focused")
    }

    func softwareKeyboardIsVisible(
        _ keyboard: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        guard keyboard.exists else {
            return false
        }
        let frame = keyboard.frame
        let visibleFrame = frame.intersection(app.frame)
        return !frame.isNull
            && visibleFrame.width > 1
            && visibleFrame.height > 1
    }

    private func assertNoSelectedChatItem(
        in chatLog: XCUIElement,
        timeout: TimeInterval,
        file: StaticString,
        line: UInt
    ) {
        let selectedItems = chatLog
            .descendants(matching: .any)
            .matching(NSPredicate(format: "selected == true"))
        // Settling is a duration, not a poll count. Each poll costs one
        // accessibility query plus a fixed run-loop spin, so requiring a fixed
        // number of consecutive clear polls inside a wall-clock deadline makes
        // the outcome depend on how fast the snapshot happens to be: when
        // queries slow down, the count cannot be reached before the deadline
        // and the assertion fails even though nothing is selected. Requiring
        // the selection to stay clear for `settleDuration` still rejects a
        // transient clear during the dismissal animation, but costs the same
        // wall-clock time whatever a query costs.
        let settleDuration: TimeInterval = 0.75
        var clearedAt: Date?
        XCTAssertTrue(
            pollUntil(timeout: timeout + settleDuration) {
                guard !selectedItems.firstMatch.exists else {
                    clearedAt = nil
                    return false
                }
                let firstClear = clearedAt ?? Date()
                clearedAt = firstClear
                return Date().timeIntervalSince(firstClear) >= settleDuration
            },
            "Expected no selected chat line or move after tapping the chat log background.",
            file: file,
            line: line
        )
    }

    private func requiredElement(
        _ identifier: String,
        in app: XCUIApplication,
        matching elementType: XCUIElement.ElementType,
        timeout: TimeInterval,
        file: StaticString,
        line: UInt
    ) -> XCUIElement {
        let element = app
            .descendants(matching: elementType)
            .matching(identifier: identifier)
            .firstMatch
        let appeared = element.waitForExistence(timeout: timeout)
        if !appeared {
            keepHierarchy(of: app, name: "missing \(identifier)")
        }
        XCTAssertTrue(
            appeared,
            "Expected element with identifier \(identifier)",
            file: file,
            line: line
        )
        return element
    }

    private func keepHierarchy(
        of app: XCUIApplication,
        name: String
    ) {
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Accessibility hierarchy – \(name)"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    /// `XCTWaiter.wait` plus one direct evaluation when it times out. A
    /// predicate expectation evaluates only while time remains, so on hosted
    /// runners a single accessibility query that stalled for 29 s used up a
    /// 30 s wait although the app had reached the expected state (October
    /// 2026). The final evaluation has no deadline of its own.
    func waitWithFinalCheck(
        for expectations: [XCTNSPredicateExpectation],
        timeout: TimeInterval
    ) -> XCTWaiter.Result {
        let result = XCTWaiter.wait(for: expectations, timeout: timeout)
        guard result == .timedOut,
              expectations.allSatisfy({ passesFinalCheck($0) })
        else { return result }
        XCTContext.runActivity(named: "A \(Int(timeout)) s wait timed out, but its condition held on a final check") { _ in }
        return .completed
    }

    /// Evaluates an expectation's predicate once, outside its waiter. The
    /// waiter reads an element's attributes in a safe mode where a missing
    /// element simply does not match; read directly, the same attributes
    /// record a test failure. Anything this check cannot read the waiter's
    /// way keeps the timeout.
    func passesFinalCheck(_ expectation: XCTNSPredicateExpectation) -> Bool {
        let predicate = expectation.predicate
        guard let element = expectation.object as? XCUIElement else {
            return predicate.evaluate(with: expectation.object)
        }
        // Here a block predicate reads its elements outside safe mode.
        if predicate.predicateFormat.hasPrefix("BLOCKPREDICATE") {
            return element.exists && predicate.evaluate(with: element)
        }
        let attributes = FinalCheckAttributes(element)
        return predicate.evaluate(with: attributes) && !attributes.isUnreadable
    }

    func pollUntil(
        timeout: TimeInterval,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        } while Date() < deadline
        return condition()
    }
}

/// An element's attributes for a final check, each read only when the
/// predicate asks for it. A missing element reads as absent, like the
/// waiter's safe mode. For an existing one, hittability comes from the
/// element as the waiter reads it, and everything else from a snapshot,
/// which throws rather than recording a failure; if that or a key fails,
/// the check is unreadable.
private final class FinalCheckAttributes: NSObject {
    private let element: XCUIElement
    @objc let exists: Bool
    private(set) var isUnreadable = false
    private lazy var snapshot: (any XCUIElementSnapshot)? = {
        guard exists else { return nil }
        do {
            return try element.snapshot()
        } catch {
            isUnreadable = true
            return nil
        }
    }()

    init(_ element: XCUIElement) {
        self.element = element
        exists = element.exists
        super.init()
    }

    @objc var isHittable: Bool { exists && element.isHittable }
    @objc var isSelected: Bool { snapshot?.isSelected ?? false }
    @objc var isEnabled: Bool { snapshot?.isEnabled ?? false }
    @objc var value: Any? { snapshot?.value }
    @objc var label: String? { snapshot?.label }
    @objc var identifier: String? { snapshot?.identifier }
    @objc var placeholderValue: String? { snapshot?.placeholderValue }

    override func value(forUndefinedKey key: String) -> Any? {
        isUnreadable = true
        return nil
    }
}
