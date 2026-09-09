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

        // Preserve the focus-on-appear assertion before dismissing it,
        // regardless of whether this simulator uses a hardware keyboard.
        XCTAssertTrue(
            pollUntil(timeout: timeout) {
                chatInputHasKeyboardFocus(in: app)
            },
            "Expected the compact chat composer to receive keyboard focus automatically.",
            file: file,
            line: line
        )

        guard tapChatLogBackground(
            chatLog, in: app, file: file, line: line
        ) else { return }

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
        guard tapChatLogBackground(
            chatLog, in: app, file: file, line: line
        ) else { return }
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
        assertNoSelectedChatItem(
            in: chatLog,
            timeout: 3,
            file: file,
            line: line
        )
        #endif
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
        guard viewport.width > 8,
              viewport.height > 8,
              viewport.minX == frame.minX,
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
                    dx: frame.minX + 4 - appFrame.minX,
                    dy: viewport.midY - appFrame.minY
                )
            )
            .tap()
        return true
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
            let gutterX = frame.minX + 4
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

    private func pollUntil(
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
