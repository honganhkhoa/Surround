//
//  SurroundUITests.swift
//  SurroundUITests
//
//  Created by Anh Khoa Hong on 6/30/20.
//

import XCTest
import UIKit

final class SurroundUITests: SurroundJourneyUITestCase {
    private struct VariationSharingDraft {
        let app: XCUIApplication
        let selectedAnalysisPosition: String
        let parentAnalysisPosition: String
        let sharingTitle: XCUIElement
        let sharingPreview: XCUIElement
        let frozenPreviewValue: String?
        let variationName: String
        let mainBoard: XCUIElement
        let sharedSourceBoardValue: String?
    }

    private enum TextInputFocusMode {
        case acquireWithRetry
        case requireExistingFocus
    }

    private func openGameFailureAlert(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let alert = app.alerts["Unable to open game"].firstMatch
        let retry = alert.buttons["Retry"].firstMatch
        let appeared = retry.waitForExistence(timeout: 10)
        if !appeared {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name =
                "Accessibility hierarchy – missing open-game failure alert"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(
            appeared,
            "Expected the open-game failure alert with a Retry action",
            file: file,
            line: line
        )
        return alert
    }

    private func tapAnalyzeMenuItem(
        _ accessibilityIdentifier: String,
        catalystTitle: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var menuItem = analyzeMenuItem(
            accessibilityIdentifier,
            catalystTitle: catalystTitle,
            in: app,
            file: file,
            line: line
        )
        if !waitUntilHittable(menuItem, timeout: 3) {
            let actionsMenu = app.descendants(matching: .any)
                .matching(
                    identifier:
                        SurroundUITestContract.AccessibilityID
                            .gameAnalyzeActionsMenu
                )
                .firstMatch
            #if targetEnvironment(macCatalyst)
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            if waitUntilHittable(actionsMenu, timeout: 2) {
                activate(actionsMenu)
            }
            #else
            if waitUntilHittable(actionsMenu, timeout: 2) {
                activate(actionsMenu)
                let refreshedItem = unresolvedAnalyzeMenuItem(
                    accessibilityIdentifier,
                    catalystTitle: catalystTitle,
                    in: app
                )
                if !waitUntilHittable(refreshedItem, timeout: 2),
                   waitUntilHittable(actionsMenu, timeout: 2) {
                    activate(actionsMenu)
                }
            }
            #endif
            menuItem = unresolvedAnalyzeMenuItem(
                accessibilityIdentifier,
                catalystTitle: catalystTitle,
                in: app
            )
        }
        if accessibilityIdentifier ==
            SurroundUITestContract.AccessibilityID.gameAnalyzeShare {
            traceAnimationTest("ARM share")
        }
        tap(
            menuItem,
            description: catalystTitle,
            in: app,
            file: file,
            line: line
        )
    }

    private func dismissAnalyzeActionsMenu(
        containing menuItem: XCUIElement,
        in app: XCUIApplication,
        restoring identifiers: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(menuItem.exists, file: file, line: line)
        #if targetEnvironment(macCatalyst)
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        #else
        let dismissButton = app.buttons["Dismiss context menu"].firstMatch
        if dismissButton.exists && dismissButton.isHittable {
            tap(dismissButton, description: "Dismiss Analyze menu", in: app,
                file: file, line: line)
        } else {
            // This runtime exposes the native menu as a collection view, with
            // no dismissal button. Derive an uncovered backdrop point from its
            // observed frame: a fixed point on the board can hit Share instead.
            let menu = app.collectionViews.containing(.button, identifier: menuItem.identifier).firstMatch
            guard menu.waitForExistence(timeout: 3) else {
                keepTextInputHierarchy(menuItem, in: app, reason: "missing Analyze menu surface")
                XCTFail("Expected the native collection containing the Analyze menu item", file: file, line: line)
                return
            }
            let window = app.frame
            let covered = menu.frame.intersection(window)
                .insetBy(dx: -8, dy: -8).intersection(window)
            let clearRegions = [
                CGRect(x: window.minX, y: window.minY, width: window.width,
                       height: max(0, covered.minY - window.minY)),
                CGRect(x: covered.maxX, y: window.minY,
                       width: max(0, window.maxX - covered.maxX), height: window.height),
                CGRect(x: window.minX, y: covered.maxY, width: window.width,
                       height: max(0, window.maxY - covered.maxY)),
                CGRect(x: window.minX, y: window.minY,
                       width: max(0, covered.minX - window.minX), height: window.height),
            ]
            guard !covered.isNull, !covered.isEmpty,
                  let region = clearRegions.filter({ $0.width >= 20 && $0.height >= 20 })
                    .max(by: { $0.width * $0.height < $1.width * $1.height }) else {
                keepTextInputHierarchy(menuItem, in: app, reason: "no Analyze menu dismissal region")
                XCTFail("Expected visible backdrop outside the native Analyze menu", file: file, line: line)
                return
            }
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: region.midX - window.minX,
                                     dy: region.midY - window.minY)).tap()
        }
        #endif
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: menuItem
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [dismissed], timeout: stateSettleTimeout),
            .completed,
            "Expected the Analyze menu to dismiss without selecting an action.",
            file: file,
            line: line
        )
        for identifier in identifiers {
            element(identifier, in: app, file: file, line: line)
        }
    }

    private func assertAnalyzeMenuSubtitle(
        _ subtitle: String,
        for menuItem: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let combinedMenuItemText = [
            menuItem.identifier,
            menuItem.label,
            String(describing: menuItem.value),
        ].joined(separator: " ")
        if combinedMenuItemText.contains(subtitle) {
            return
        }

        let subtitlePredicate = NSPredicate(
            format: "label CONTAINS %@ OR title CONTAINS %@ OR identifier CONTAINS %@ OR value CONTAINS %@",
            subtitle,
            subtitle,
            subtitle,
            subtitle
        )
        let subtitleElement = menuItem.descendants(matching: .any)
            .matching(subtitlePredicate)
            .firstMatch
        let appeared = subtitleElement.waitForExistence(timeout: 10)
        if !appeared {
            let hierarchy = XCTAttachment(
                string: """
                Menu item:
                \(menuItem.debugDescription)

                Application hierarchy:
                \(app.debugDescription)
                """
            )
            hierarchy.name =
                "Accessibility hierarchy – missing menu subtitle \(subtitle)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(
            appeared,
            "Expected menu subtitle \(subtitle)",
            file: file,
            line: line
        )
    }

    private func tapAnalyzeDeleteConfirmation(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #if targetEnvironment(macCatalyst)
        let confirmationButton = app.sheets
            .buttons
            .matching(identifier: "Delete branch")
            .firstMatch
        let appeared = confirmationButton.waitForExistence(timeout: 10)
        if !appeared {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name =
                "Accessibility hierarchy – missing Delete branch confirmation"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(
            appeared,
            "Expected the Delete branch confirmation button",
            file: file,
            line: line
        )
        tap(
            confirmationButton,
            description: "Delete branch confirmation",
            in: app,
            file: file,
            line: line
        )
        #else
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeConfirmDelete,
            in: app,
            matching: .button,
            file: file,
            line: line
        )
        #endif
    }

    private func tapChatChannel(
        _ accessibilityIdentifier: String,
        catalystTitle: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        openGameChat(in: app, file: file, line: line)
        tap(
            SurroundUITestContract.AccessibilityID.gameChatChannelPicker,
            in: app,
            matching: .button,
            file: file,
            line: line
        )
        tap(
            analyzeMenuItem(
                accessibilityIdentifier,
                catalystTitle: catalystTitle,
                in: app,
                file: file,
                line: line
            ),
            description: catalystTitle,
            in: app,
            file: file,
            line: line
        )
    }

    private func analysisViewportFrame(
        _ analysisTree: XCUIElement,
        in app: XCUIApplication
    ) -> CGRect? {
        let interactionPoint = CGVector(dx: 0.5, dy: 0.5)
        let ancestorScrollViews = app.scrollViews.containing(
            .scrollView,
            identifier: SurroundUITestContract.AccessibilityID.gameAnalyzeTreeScroll
        ).allElementsBoundByIndex
        let frames = [app.frame, analysisTree.frame]
            + ancestorScrollViews.map { $0.frame }
        var viewport = CGRect.infinite
        for frame in frames {
            guard let frame = validInteractionFrame(
                frame,
                interactionPoint: interactionPoint
            ) else { return nil }
            viewport = viewport.intersection(frame)
        }
        return validInteractionFrame(viewport, interactionPoint: interactionPoint)
    }

    private func analysisPositionIsFullyVisible(
        _ frame: CGRect,
        in viewport: CGRect?
    ) -> Bool {
        guard let frame = validInteractionFrame(
            frame,
            interactionPoint: CGVector(dx: 0.5, dy: 0.5)
        ), let viewport else { return false }
        return viewport.insetBy(dx: 4, dy: 4).contains(frame)
    }

    private func revealAnalysisPosition(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement? {
        let target = app.buttons
            .matching(identifier: identifier)
            .firstMatch
        let analysisTree = element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeTreeScroll,
            in: app,
            matching: .scrollView,
            file: file,
            line: line
        )

        for attempt in 0...10 {
            var targetExists = target.exists
            var targetFrame = targetExists ? target.frame : .null
            var viewport = analysisViewportFrame(analysisTree, in: app)
            if analysisPositionIsFullyVisible(targetFrame, in: viewport) {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                targetExists = target.exists
                targetFrame = targetExists ? target.frame : .null
                viewport = analysisViewportFrame(analysisTree, in: app)
                if analysisPositionIsFullyVisible(targetFrame, in: viewport) {
                    return target
                }
            }

            guard attempt < 10, let viewport else { break }

            let interactionPoint = CGVector(dx: 0.5, dy: 0.5)
            // A tree scrolls along moves and across branches. Choose the
            // clipped dimension of this node, not just the tree's main axis.
            let scrollAxis: ScrollRevealAxis
            if targetExists {
                scrollAxis = targetFrame.minY < viewport.minY + 4
                    || targetFrame.maxY > viewport.maxY - 4 ? .vertical : .horizontal
            } else {
                scrollAxis = viewport.height > viewport.width ? .vertical : .horizontal
            }
            guard dragScrollView(
                analysisTree,
                axis: scrollAxis,
                targetFrame: targetExists
                    ? validInteractionFrame(
                        targetFrame,
                        interactionPoint: interactionPoint
                    ) : nil,
                containerFrame: viewport,
                interactionPoint: interactionPoint,
                dragStartPoint: CGPoint(x: viewport.midX, y: viewport.midY)
            ) else { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        keepInteractionHierarchy(
            target,
            container: analysisTree,
            in: app,
            reason: "unable to reveal analysis position \(identifier)"
        )
        keepScreenshot("Unable to fully reveal analysis position \(identifier)", in: app)
        XCTFail(
            "Expected analysis position \(identifier) to become fully visible",
            file: file,
            line: line
        )
        return nil
    }

    private func tapAnalysisPosition(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var lastTarget: XCUIElement?
        for attempt in 0..<2 {
            // XCTest can throw while computing a hit point for a node at the
            // clipped tree edge. Reveal its complete frame and activate its
            // center, then require the same real, stable selection as before.
            guard let target = revealAnalysisPosition(
                identifier,
                in: app,
                file: file,
                line: line
            ) else { return }
            lastTarget = target
            XCTContext.runActivity(
                named: "Select fully visible analysis position \(identifier), attempt \(attempt + 1)"
            ) { _ in
                activate(target, at: CGVector(dx: 0.5, dy: 0.5))
            }
            if waitForStableSelection(of: target, timeout: 5) {
                return
            }
        }

        let target = lastTarget ?? app.buttons
            .matching(identifier: identifier)
            .firstMatch
        let analysisTree = app.scrollViews
            .matching(
                identifier:
                    SurroundUITestContract.AccessibilityID.gameAnalyzeTreeScroll
            )
            .firstMatch
        keepInteractionHierarchy(
            target,
            container: analysisTree,
            in: app,
            reason: "analysis selection did not settle for \(identifier)"
        )
        keepScreenshot("Analysis selection did not settle for \(identifier)", in: app)
        XCTFail(
            "Expected analysis position \(identifier) to remain selected",
            file: file,
            line: line
        )
    }

    private func waitForStableSelection(
        of element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"),
            object: element
        )
        guard XCTWaiter.wait(for: [selected], timeout: timeout) == .completed else {
            return false
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        return element.exists && element.isSelected
    }

    private func enterText(
        _ text: String,
        into textField: XCUIElement,
        in app: XCUIApplication,
        focusMode: TextInputFocusMode = .acquireWithRetry,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var currentTextField = focusChatInput(
            textField,
            in: app,
            mode: focusMode,
            file: file,
            line: line
        )
        currentTextField.typeText(text)

        var observedValue: String?
        var observedDescription = "not read"
        var observationDuration: TimeInterval = 0
        func observeCurrentValue() -> Bool {
            let started = ProcessInfo.processInfo.systemUptime
            let rawValue = currentTextField.value
            observationDuration = ProcessInfo.processInfo.systemUptime - started
            observedValue = rawValue as? String
            observedDescription = observedValue?.debugDescription
                ?? "nil or non-string: \(String(describing: rawValue))"
            return observedValue == text
        }

        var completed = waitForValue(text, in: currentTextField, timeout: 2)
        if !completed {
            // A slow accessibility lookup can outlast the predicate deadline
            // even when it returns the exact value. A stale empty or partial
            // value can also precede delivery of the original typing request.
            // Observe that request without submitting duplicate input.
            currentTextField = resolvedChatInput(in: app)
            completed = observeCurrentValue()
            if !completed {
                completed = waitForValue(text, in: currentTextField, timeout: 5)
                if !completed {
                    currentTextField = resolvedChatInput(in: app)
                    completed = observeCurrentValue()
                }
            }
        }
        if !completed {
            keepTextInputHierarchy(
                currentTextField,
                in: app,
                reason: "incomplete chat composer input"
            )
        }
        XCTAssertTrue(
            completed,
            "Expected the chat composer value to become \(text.debugDescription); observed value: \(observedDescription), read duration: \(observationDuration)s",
            file: file,
            line: line
        )
    }

    private func focusChatInput(
        _ textField: XCUIElement,
        in app: XCUIApplication,
        mode: TextInputFocusMode,
        file: StaticString,
        line: UInt
    ) -> XCUIElement {
        #if targetEnvironment(macCatalyst)
        if mode == .acquireWithRetry {
            tap(
                textField,
                description:
                    SurroundUITestContract.AccessibilityID.gameChatInput,
                in: app,
                file: file,
                line: line
            )
        }
        return textField
        #else
        switch mode {
        case .requireExistingFocus:
            if waitForChatInputFocus(in: app, timeout: 10) {
                return resolvedChatInput(in: app)
            }
        case .acquireWithRetry:
            if chatInputHasKeyboardFocus(in: app) {
                return resolvedChatInput(in: app)
            }
            for _ in 0..<2 {
                let currentTextField = resolvedChatInput(in: app)
                focusChatInputAtTrailingEdgeIfNeeded(
                    currentTextField,
                    in: app,
                    file: file,
                    line: line
                )
                if waitForChatInputFocus(in: app, timeout: 3) {
                    return resolvedChatInput(in: app)
                }
            }
        }

        keepTextInputHierarchy(
            textField,
            in: app,
            reason: "chat composer not focused"
        )
        XCTFail(
            "Expected the chat composer to accept keyboard input",
            file: file,
            line: line
        )
        return textField
        #endif
    }

    private func focusChatInputAtTrailingEdgeIfNeeded(
        _ textField: XCUIElement,
        in app: XCUIApplication,
        file: StaticString,
        line: UInt
    ) {
        let existingValue = textField.value as? String ?? ""
        guard !existingValue.isEmpty else {
            tap(
                textField,
                description:
                    SurroundUITestContract.AccessibilityID.gameChatInput,
                in: app,
                file: file,
                line: line
            )
            return
        }

        let isHittable = waitUntilHittable(textField, timeout: 10)
        if !isHittable {
            keepTextInputHierarchy(
                textField,
                in: app,
                reason: "nonempty chat composer not hittable for refocus"
            )
        }
        XCTAssertTrue(
            isHittable,
            "Expected the chat composer to be hittable for refocus",
            file: file,
            line: line
        )
        guard isHittable else {
            return
        }

        // Refocus at the trailing edge to keep the insertion point after any
        // existing text.
        activate(textField, at: CGVector(dx: 0.98, dy: 0.5))
    }

    private func resolvedChatInput(in app: XCUIApplication) -> XCUIElement {
        app.textFields
            .matching(
                identifier:
                    SurroundUITestContract.AccessibilityID.gameChatInput
            )
            .firstMatch
    }

    private func waitForChatInputFocus(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            if chatInputHasKeyboardFocus(in: app) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline

        return false
    }

    private func focusSharedVariationInput(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let textField = element(
            SurroundUITestContract.AccessibilityID.gameChatInput,
            in: app,
            matching: .textField,
            file: file,
            line: line
        )
        return focusChatInput(
            textField,
            in: app,
            mode: .requireExistingFocus,
            file: file,
            line: line
        )
    }

    private func beginVariationSharingDraft(
        named variationName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> VariationSharingDraft {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameAnalysis.rawValue,
        ])
        let selectedAnalysisPosition =
            SurroundUITestContract.AccessibilityID.gameAnalysisPosition(
                baseMoveNumber:
                    SurroundUITestContract.screenshotAnalysisBaseMoveNumber,
                movePath:
                    SurroundUITestContract.screenshotAnalysisSelectedMovePath
            )
        let parentAnalysisPosition =
            SurroundUITestContract.AccessibilityID.gameAnalysisPosition(
                baseMoveNumber:
                    SurroundUITestContract.screenshotAnalysisBaseMoveNumber,
                movePath: Array(
                    SurroundUITestContract.screenshotAnalysisSelectedMovePath
                        .dropLast()
                )
            )

        tapAnalysisPosition(
            selectedAnalysisPosition,
            in: app,
            file: file,
            line: line
        )
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu,
            in: app,
            file: file,
            line: line
        )
        tapAnalyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeShare,
            catalystTitle: "Share variation in chat",
            in: app,
            file: file,
            line: line
        )
        let variationNameInput = focusSharedVariationInput(
            in: app,
            file: file,
            line: line
        )
        let sharingTitle = element(
            SurroundUITestContract.AccessibilityID.gameVariationShareStatus,
            in: app,
            file: file,
            line: line
        )
        XCTAssertEqual(
            sharingTitle.label,
            "Sharing variation",
            file: file,
            line: line
        )
        let sharingPreview = element(
            SurroundUITestContract.AccessibilityID.gameVariationSharePreview,
            in: app,
            file: file,
            line: line
        )
        XCTAssertEqual(
            sharingPreview.frame.width,
            120,
            accuracy: 4,
            file: file,
            line: line
        )
        XCTAssertEqual(
            sharingPreview.frame.height,
            120,
            accuracy: 4,
            file: file,
            line: line
        )
        let frozenPreviewValue = sharingPreview.value as? String
        XCTAssertNotNil(frozenPreviewValue, file: file, line: line)
        enterText(
            variationName,
            into: variationNameInput,
            in: app,
            focusMode: .requireExistingFocus,
            file: file,
            line: line
        )
        dismissSoftwareKeyboardIfNeeded(in: app)
        let mainBoard = element(
            SurroundUITestContract.AccessibilityID.gameBoard,
            in: app,
            file: file,
            line: line
        )
        let sharedSourceBoardValue = mainBoard.value as? String
        XCTAssertNotNil(sharedSourceBoardValue, file: file, line: line)

        return VariationSharingDraft(
            app: app,
            selectedAnalysisPosition: selectedAnalysisPosition,
            parentAnalysisPosition: parentAnalysisPosition,
            sharingTitle: sharingTitle,
            sharingPreview: sharingPreview,
            frozenPreviewValue: frozenPreviewValue,
            variationName: variationName,
            mainBoard: mainBoard,
            sharedSourceBoardValue: sharedSourceBoardValue
        )
    }

    private func assertVariationSharingDraftIsIntact(
        _ draft: VariationSharingDraft,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            draft.sharingTitle.exists,
            "Expected Variation sharing to remain active.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            draft.sharingPreview.value as? String,
            draft.frozenPreviewValue,
            "Expected the composer preview to remain frozen.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            element(
                SurroundUITestContract.AccessibilityID.gameChatInput,
                in: draft.app,
                matching: .textField,
                file: file,
                line: line
            ).value as? String,
            draft.variationName,
            "Expected the draft variation name to be preserved.",
            file: file,
            line: line
        )
    }

    private func assertQuickMatchToggle(
        _ identifier: String,
        isOn: Bool,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let toggle: XCUIElement
        #if targetEnvironment(macCatalyst)
        toggle = element(identifier, in: app, file: file, line: line)
        #else
        if identifier == SurroundUITestContract.AccessibilityID
            .quickMatchStrictHandicap {
            guard let revealedSwitch = revealQuickMatchSwitch(
                identifier,
                in: app,
                file: file,
                line: line
            ) else { return }
            toggle = revealedSwitch
        } else {
            toggle = element(identifier, in: app, file: file, line: line)
        }
        #endif
        XCTAssertTrue(
            waitForValue(isOn ? "1" : "0", in: toggle, timeout: stateSettleTimeout),
            "Expected \(identifier) to be \(isOn ? "on" : "off")",
            file: file,
            line: line
        )
    }

    private func revealQuickMatchSwitch(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString,
        line: UInt
    ) -> XCUIElement? {
        let target = element(identifier, in: app, file: file, line: line)
        let scroll = element(
            SurroundUITestContract.AccessibilityID.quickMatchScroll,
            in: app,
            matching: .scrollView,
            file: file,
            line: line
        )
        let center = CGVector(dx: 0.5, dy: 0.5)
        for attempt in 0...10 {
            guard let scrollFrame = validInteractionFrame(
                scroll.frame,
                interactionPoint: center
            ), let appFrame = validInteractionFrame(
                app.frame,
                interactionPoint: center
            ) else { break }
            guard let viewport = validInteractionFrame(
                scrollFrame.intersection(appFrame),
                interactionPoint: center
            ), viewport.width > 8, viewport.height > 16,
               target.exists,
               let targetFrame = validInteractionFrame(
                target.frame,
                interactionPoint: center
               ) else { break }
            if viewport.insetBy(dx: 0, dy: 8).contains(targetFrame) {
                // Inspect the native value without requiring a disabled switch
                // to accept interaction or changing the restored criteria.
                return element(
                    identifier,
                    in: app,
                    matching: .switch,
                    file: file,
                    line: line
                )
            }
            guard attempt < 10 else { break }
            guard dragScrollView(
                scroll,
                axis: .vertical,
                targetFrame: targetFrame,
                containerFrame: viewport,
                interactionPoint: center,
                dragStartPoint: CGPoint(x: viewport.midX, y: viewport.midY)
            ) else { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        keepInteractionHierarchy(
            target,
            container: scroll,
            in: app,
            reason: "unable to reveal Quick Match switch \(identifier)"
        )
        XCTFail(
            "Expected Quick Match switch \(identifier) inside its visible viewport",
            file: file,
            line: line
        )
        return nil
    }

    private func openQuickMatchAdvanced(in app: XCUIApplication) {
        let advanced = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID.quickMatchAdvanced,
            in: app,
            matching: .button
        )
        scrollIntoTappableArea(advanced, in: app)
        let clockSystem = app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.quickMatchClockSystem)
            .firstMatch
        // A quick tab round-trip can preserve the disclosure state. Only tap
        // when its content is absent, so this helper never closes Advanced.
        if !clockSystem.exists {
            tap(advanced, description: "Quick Match advanced settings", in: app)
        }
        XCTAssertTrue(
            clockSystem.waitForExistence(timeout: 10),
            "Expected Quick Match advanced settings to be expanded."
        )
    }

    private func selectQuickMatchCorrespondence(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement? {
        let correspondence = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID.quickMatchSpeedTab("correspondence"),
            in: app,
            matching: .button,
            file: file,
            line: line
        )
        scrollIntoTappableArea(correspondence, in: app)
        let realtime = app.buttons.matching(identifier:
            SurroundUITestContract.AccessibilityID.quickMatchSpeedTab("live")
        ).firstMatch
        let gameCount = app.steppers.matching(identifier:
            SurroundUITestContract.AccessibilityID.quickMatchGameCount
        ).firstMatch

        func observeSelection() -> (
            correspondenceSelected: Bool, realtimeSelected: Bool,
            gameCountExists: Bool, enabled: Bool, hittable: Bool, frame: CGRect
        ) {
            let exists = correspondence.exists
            return (
                exists && correspondence.isSelected,
                realtime.exists && realtime.isSelected,
                gameCount.exists,
                exists && correspondence.isEnabled,
                exists && correspondence.isHittable,
                exists ? correspondence.frame : .zero
            )
        }

        // This is setup for the pending-submission journey. Keep the separate
        // correspondence journey's single-tap selection assertions unchanged.
        for attempt in 1...2 {
            // Re-observe after any diagnostic capture, which can itself take
            // time. Never retry based only on the earlier failed wait.
            let before = observeSelection()
            if before.correspondenceSelected && before.gameCountExists {
                return gameCount
            }
            guard !before.correspondenceSelected && before.realtimeSelected
                    && before.enabled && before.hittable else {
                let hierarchy = XCTAttachment(string: """
                    Captured selection before attempt \(attempt): \(before)
                    Application hierarchy:
                    \(app.debugDescription)
                    """)
                hierarchy.name = "Quick Match – correspondence selection unavailable"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
                keepScreenshot("Quick Match – correspondence selection unavailable", in: app)
                XCTFail("Cannot select Correspondence from observed state: \(before)", file: file, line: line)
                return nil
            }

            activate(correspondence)
            let ready = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    correspondence.isSelected && gameCount.exists
                },
                object: nil
            )
            _ = XCTWaiter.wait(for: [ready], timeout: 10)
            // An accessibility query can outlast the waiter's deadline even
            // when the transition succeeded. Accept the fresh exact state.
            let after = observeSelection()
            if after.correspondenceSelected && after.gameCountExists {
                return gameCount
            }

            let hierarchy = XCTAttachment(string: """
                Captured selection after attempt \(attempt): \(after)
                Application hierarchy:
                \(app.debugDescription)
                """)
            hierarchy.name = "Quick Match – correspondence selection attempt \(attempt)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            keepScreenshot("Quick Match – correspondence selection attempt \(attempt)", in: app)

            // Selecting a segment is idempotent. Retry only a confirmed missed
            // selection; a selected tab without its Stepper must still fail.
            guard attempt == 1, !after.correspondenceSelected,
                  after.realtimeSelected, after.enabled, after.hittable else {
                XCTFail("Expected selected Correspondence and its game-count Stepper; observed: \(after)", file: file, line: line)
                return nil
            }
        }
        return nil
    }

    private func keepTextInputHierarchy(
        _ textField: XCUIElement,
        in app: XCUIApplication,
        reason: String
    ) {
        let hierarchy = XCTAttachment(
            string: """
            Element:
            \(textField.debugDescription)

            Application hierarchy:
            \(app.debugDescription)
            """
        )
        hierarchy.name = "Accessibility hierarchy – \(reason)"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    func testPrivateMessageProfileEntriesPreserveConversationDraft() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.messagesInbox.rawValue,
        ])
        let peerID = 765_826
        let rowID = SurroundUITestContract.AccessibilityID.privateMessageRow(peerID)
        let toolbarID = SurroundUITestContract.AccessibilityID.profileMessageToolbarEntry(peerID)
        let row = element(rowID, in: app)
        tap(openProfileContextMenu(
            for: row,
            expecting: SurroundUITestContract.AccessibilityID.profileMessageMenuEntry(peerID),
            in: app
        ), description: "View the message-list peer's profile", in: app)
        assertLoadedProfile(named: "hakhoa", in: app)

        tap(SurroundUITestContract.AccessibilityID.profileMessage, in: app)
        element(SurroundUITestContract.AccessibilityID.profileConversation, in: app)
        tap(toolbarID, in: app, matching: .button)
        assertLoadedProfile(named: "hakhoa", in: app)
        // The toolbar must return to the existing profile, whose Back still
        // reaches the inbox, rather than growing profile/conversation loops.
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenMessages, in: app)

        tap(rowID, in: app)
        let composer = element(SurroundUITestContract.AccessibilityID.privateMessageComposer, in: app, matching: .textField)
        let draft = "Keep this private message draft"
        tap(composer, description: "Private-message composer", in: app)
        composer.typeText(draft)
        XCTAssertTrue(waitForValue(draft, in: composer, timeout: 10))
        keepScreenshot("Private message – unsent draft and profile toolbar", in: app)
        tap(toolbarID, in: app, matching: .button)
        assertLoadedProfile(named: "hakhoa", in: app)
        navigateBackFromPlayerProfile(in: app)
        XCTAssertTrue(waitForValue(draft, in: composer, timeout: 10),
                      "Back from the toolbar profile must retain the unsent draft.")

        tap(toolbarID, in: app, matching: .button)
        assertLoadedProfile(named: "hakhoa", in: app)
        tap(SurroundUITestContract.AccessibilityID.profileMessage, in: app)
        XCTAssertTrue(waitForValue(draft, in: composer, timeout: 10),
                      "Message must reuse the existing conversation and its unsent draft.")
        let navigationBar = app.navigationBars["hakhoa"].firstMatch
        let identifiedBack = navigationBar.buttons.matching(identifier: "BackButton").firstMatch
        let back = identifiedBack.exists ? identifiedBack : navigationBar.buttons.firstMatch
        tap(back, description: "Return from Profile's conversation to the peer Profile", in: app)
        assertLoadedProfile(named: "hakhoa", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        element(rowID, in: app)
        let retainedComposer = element(SurroundUITestContract.AccessibilityID.privateMessageComposer,
                                       in: app, matching: .textField)
        XCTAssertTrue(waitUntilHittable(retainedComposer, timeout: 10),
                      "Profile Back must restore the retained Messages conversation.")
        XCTAssertTrue(waitForValue(draft, in: retainedComposer, timeout: 10),
                      "Both Back actions must preserve the exact original unsent draft.")
        XCTAssertTrue(element(toolbarID, in: app, matching: .button).label.contains("hakhoa"),
                      "The restored Messages conversation must still belong to the original peer.")
        keepScreenshot("Private message – Profile Back restores peer and exact draft", in: app)
    }

    func testMessagesNavigationIsHiddenWhenSignedOut() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.welcome.rawValue,
        ], orientation: UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .landscapeLeft)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        let signIn = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Sign in to your OGS account")).firstMatch
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))

        // Exercise the main navigation so a collapsed sidebar cannot hide an
        // incorrectly exposed account destination from this assertion.
        selectMainNavigation(SurroundUITestContract.AccessibilityID.navigationPublicGames, in: app)
        element(SurroundUITestContract.AccessibilityID.screenPublicGames, in: app)
        let sidebar = app.buttons["Toggle sidebar"].firstMatch
        let home = app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.navigationHome).firstMatch
        if !home.isHittable && sidebar.exists && sidebar.isHittable {
            tap(sidebar, description: "Show signed-out navigation", in: app)
        }
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.navigationMessages).firstMatch.exists)
        XCTAssertFalse(app.tabBars.buttons["Messages"].exists)
        selectMainNavigation(SurroundUITestContract.AccessibilityID.navigationHome, in: app)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
    }

    func testPreferredSettingEditorRetainsRulesAcrossNavigation() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.preferredSettings.rawValue,
        ], orientation: .portrait)
        element(SurroundUITestContract.AccessibilityID.screenPreferredSettings, in: app)
        let edit = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label == %@",
            SurroundUITestContract.AccessibilityID.preferredSetting(0), "Edit"
        )).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        scrollIntoTappableArea(edit, in: app)
        tap(edit, description: "Edit the first preferred setting", in: app)
        XCTAssertTrue(app.navigationBars["Edit preferred setting"].waitForExistence(timeout: 10))
        let editor = element(SurroundUITestContract.AccessibilityID.screenCustomGame, in: app, matching: .scrollView)

        let advancedRules = app.buttons["Advanced rules settings"].firstMatch
        XCTAssertTrue(advancedRules.waitForExistence(timeout: 10))
        scrollIntoTappableArea(advancedRules, in: app)
        tap(advancedRules, description: "Open advanced rules from the setting editor", in: app)
        XCTAssertTrue(app.navigationBars["Advanced rules settings"].waitForExistence(timeout: 10))
        // The preferred-setting fixture starts with Japanese rules. AGA also
        // changes the editor from its two-option picker to the rule-name link.
        tap(app.buttons["AGA"].firstMatch, description: "Choose AGA rules", in: app)

        func navigateBack(from title: String) {
            let bar = app.navigationBars[title].firstMatch
            XCTAssertTrue(bar.waitForExistence(timeout: 10))
            let identifiedBack = bar.buttons.matching(identifier: "BackButton").firstMatch
            tap(identifiedBack.exists ? identifiedBack : bar.buttons.firstMatch,
                description: "Back from \(title)", in: app)
        }

        navigateBack(from: "Advanced rules settings")
        XCTAssertTrue(app.navigationBars["Edit preferred setting"].waitForExistence(timeout: 10))
        let retainedRule = editor.buttons.matching(NSPredicate(
            format: "label == %@ OR label BEGINSWITH %@", "AGA", "AGA "
        )).firstMatch
        XCTAssertTrue(retainedRule.waitForExistence(timeout: 10),
                      "Returning from Advanced rules must preserve the existing editor draft's rule.")
        keepScreenshot("Preferred setting – edited rule retained after Back", in: app)

        navigateBack(from: "Edit preferred setting")
        element(SurroundUITestContract.AccessibilityID.screenPreferredSettings, in: app)
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        let add = app.navigationBars.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@ OR identifier == %@", "Add", "plus", "plus"
        )).firstMatch
        tap(add, description: "Add a new preferred setting", in: app)
        XCTAssertTrue(app.navigationBars["New preferred setting"].waitForExistence(timeout: 10))
        element(SurroundUITestContract.AccessibilityID.screenCustomGame, in: app)
        navigateBack(from: "New preferred setting")
        element(SurroundUITestContract.AccessibilityID.screenPreferredSettings, in: app)
        XCTAssertTrue(edit.waitForExistence(timeout: 10),
                      "Cancelling creation must return to the original preferred-settings list.")
    }

    func testMessagesNavigationRemainsAvailableWithoutThreads() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.home.rawValue,
            SurroundUITestContract.emptyMessagesLaunchArgument,
        ], orientation: UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .landscapeLeft)
        selectMainNavigation(SurroundUITestContract.AccessibilityID.navigationMessages, in: app)
        element(SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "messages.row."
        )).firstMatch.exists, "This regression must exercise an inbox with no message threads.")
        selectMainNavigation(SurroundUITestContract.AccessibilityID.navigationHome, in: app)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        selectMainNavigation(SurroundUITestContract.AccessibilityID.navigationMessages, in: app)
        element(SurroundUITestContract.AccessibilityID.screenMessages, in: app)
    }

    func testTopLevelNavigation() throws {
        try XCTSkipIf(
            UIDevice.current.userInterfaceIdiom == .phone,
            "Top-level navigation requires the regular-width iPad or Mac layout."
        )

        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.home.rawValue,
        ])

        #if !targetEnvironment(macCatalyst)
        let usesIPadAccountSheets = UIDevice.current.userInterfaceIdiom == .pad
        #else
        let usesIPadAccountSheets = false
        #endif
        func dismissAccountSheetReturningToMessages() {
            let done = element("account.sheet.done", in: app, matching: .button)
            tap(done, description: "Dismiss the account sheet to return to Messages", in: app)
            let dismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: done
            )
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: stateSettleTimeout), .completed)
            let messages = element(SurroundUITestContract.AccessibilityID.screenMessages, in: app)
            XCTAssertTrue(waitUntilHittable(messages, timeout: 10),
                          "Dismissing the account sheet must retain the selected Messages destination.")
        }

        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)

        tap(SurroundUITestContract.AccessibilityID.navigationPublicGames, in: app)
        element(SurroundUITestContract.AccessibilityID.screenPublicGames, in: app)

        tap(SurroundUITestContract.AccessibilityID.navigationMessages, in: app)
        element(SurroundUITestContract.AccessibilityID.screenMessages, in: app)

        selectMainNavigation(SurroundUITestContract.AccessibilityID.navigationProfile, in: app)
        assertLoadedProfile(named: "JuniperStone", isOwnProfile: true, in: app)
        if usesIPadAccountSheets { dismissAccountSheetReturningToMessages() }

        selectMainNavigation(SurroundUITestContract.AccessibilityID.navigationSettings, in: app)
        element(SurroundUITestContract.AccessibilityID.screenSettings, in: app)
        if usesIPadAccountSheets { dismissAccountSheetReturningToMessages() }

        selectMainNavigation(SurroundUITestContract.AccessibilityID.navigationAbout, in: app)
        let about = element(SurroundUITestContract.AccessibilityID.screenAbout, in: app)
        let reviewLink = element(
            SurroundUITestContract.AccessibilityID.aboutWriteReview,
            in: app
        )
        for _ in 0..<4 where !reviewLink.isHittable {
            about.swipeUp()
        }
        XCTAssertEqual(reviewLink.label, "Write a Review")
        tap(reviewLink, description: "Write a Review", in: app)
        // The offline root discards URL actions; this must remain in the app.
        XCTAssertTrue(about.exists)

        selectMainNavigation(SurroundUITestContract.AccessibilityID.navigationBrowser, in: app)
        element(SurroundUITestContract.AccessibilityID.screenBrowser, in: app)

        tap(SurroundUITestContract.AccessibilityID.navigationHome, in: app)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
    }

    func testQuickMatchLiveSearchLocksTheFormAndCanBeCancelled() {
        let app = launchApp()

        tap(
            SurroundUITestContract.AccessibilityID.homeNewGame,
            in: app,
            matching: .button
        )
        element(
            SurroundUITestContract.AccessibilityID.quickMatchRecap,
            in: app
        )
        let boardSize = element(
            SurroundUITestContract.AccessibilityID.quickMatchBoardSize(9),
            in: app
        )
        let rapid = element(
            SurroundUITestContract.AccessibilityID.quickMatchSpeed("rapid"),
            in: app
        )
        keepScreenshot("Quick Match – default selections", in: app)

        tap(
            SurroundUITestContract.AccessibilityID.quickMatchFind,
            in: app,
            matching: .button
        )
        let searchingStatus = element(
            SurroundUITestContract.AccessibilityID.quickMatchSearching,
            in: app
        )
        XCTAssertEqual(
            searchingStatus.label,
            "Searching for a game…",
            "The search identifier must use the visible localized status text."
        )
        XCTAssertFalse(
            boardSize.isEnabled,
            "A live search must lock the editable match criteria."
        )
        XCTAssertFalse(rapid.isEnabled)
        XCTAssertFalse(element(
            SurroundUITestContract.AccessibilityID.quickMatchSpeedTabs,
            in: app,
            matching: .segmentedControl
        ).isEnabled)

        tap(
            SurroundUITestContract.AccessibilityID.quickMatchCancel,
            in: app,
            matching: .button
        )
        let findAgain = element(
            SurroundUITestContract.AccessibilityID.quickMatchFind,
            in: app,
            matching: .button
        )
        XCTAssertTrue(waitUntilHittable(findAgain, timeout: 5))
        XCTAssertTrue(boardSize.isEnabled)
        XCTAssertTrue(rapid.isEnabled)
    }

    func testQuickMatchMultiselectionAndAdvancedPreferences() {
        let app = launchApp()
        tap(
            SurroundUITestContract.AccessibilityID.homeNewGame,
            in: app,
            matching: .button
        )

        let board9 = SurroundUITestContract.AccessibilityID
            .quickMatchBoardSize(9)
        let board13 = SurroundUITestContract.AccessibilityID
            .quickMatchBoardSize(13)
        assertSelected(board9, in: app)
        tap(board13, in: app)
        assertSelected(board9, in: app)
        assertSelected(board13, in: app)
        let recap = element(
            SurroundUITestContract.AccessibilityID.quickMatchRecap,
            in: app
        )
        XCTAssertTrue(recap.label.contains("9 by 9"))
        XCTAssertTrue(recap.label.contains("13 by 13"))

        let waitingLegend = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Players waiting")).firstMatch
        let popularLegend = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Popular lately")).firstMatch
        XCTAssertFalse(waitingLegend.exists)
        XCTAssertFalse(popularLegend.exists)

        let rapid = SurroundUITestContract.AccessibilityID
            .quickMatchSpeed("rapid")
        let live = SurroundUITestContract.AccessibilityID
            .quickMatchSpeed("live")
        assertQuickMatchToggle(rapid, isOn: true, in: app)
        let liveToggle = element(live, in: app)
        scrollIntoTappableArea(liveToggle, in: app)
        // The switch accessibility frame includes its wide label. Target the
        // trailing switch itself, since the center can be empty label space.
        activate(liveToggle, at: CGVector(dx: 0.95, dy: 0.5))
        assertQuickMatchToggle(rapid, isOn: true, in: app)
        assertQuickMatchToggle(live, isOn: true, in: app)
        let rapidToggle = element(rapid, in: app)
        scrollIntoTappableArea(rapidToggle, in: app)
        activate(rapidToggle, at: CGVector(dx: 0.95, dy: 0.5))
        assertQuickMatchToggle(rapid, isOn: false, in: app)
        assertQuickMatchToggle(live, isOn: true, in: app)

        openQuickMatchAdvanced(in: app)
        let eitherClock = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID.quickMatchClockPreference("flexible"),
            in: app,
            matching: .button
        )
        XCTAssertEqual(eitherClock.label, "Either clock")
        let byoYomi = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID
                .quickMatchClockPreference("byoyomi"),
            in: app,
            matching: .button
        )
        scrollIntoTappableArea(byoYomi, in: app)
        activate(byoYomi)
        XCTAssertTrue(byoYomi.isSelected)
        XCTAssertTrue(recap.label.contains("Byo-Yomi"))
        XCTAssertFalse(recap.label.contains("Fischer"))
        let rapidClocks = element(
            SurroundUITestContract.AccessibilityID.quickMatchClockValues("rapid"),
            in: app
        )
        XCTAssertTrue(rapidClocks.label.contains("9×9"))
        XCTAssertTrue(rapidClocks.label.contains("13×13"))
        XCTAssertTrue(rapidClocks.label.contains("Byo-Yomi"))
        XCTAssertFalse(rapidClocks.label.contains("Fischer"))

        let correspondenceTab = element(
            SurroundUITestContract.AccessibilityID.quickMatchSpeedTab("correspondence"),
            in: app,
            matching: .button
        )
        scrollIntoTappableArea(correspondenceTab, in: app)
        activate(correspondenceTab)
        XCTAssertTrue(correspondenceTab.isSelected)
        XCTAssertFalse(app.switches.matching(identifier: live).firstMatch.exists)
        XCTAssertTrue(recap.label.contains("Correspondence"))
        XCTAssertTrue(recap.label.contains("Fischer"))
        XCTAssertTrue(popularLegend.waitForExistence(timeout: 5))
        XCTAssertFalse(waitingLegend.exists)

        let options = app.segmentedControls[
            SurroundUITestContract.AccessibilityID.newGameOptionPicker
        ]
        let custom = options.buttons["Custom"]
        let quickMatch = options.buttons["Quick match"]
        let quickMatchScroll = app.scrollViews[SurroundUITestContract.AccessibilityID.quickMatchScroll]
        activate(custom)
        let customSelected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"),
            object: custom
        )
        XCTAssertEqual(XCTWaiter.wait(for: [customSelected], timeout: 10), .completed)
        element(SurroundUITestContract.AccessibilityID.screenCustomGame, in: app)
        let quickMatchHidden = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: quickMatchScroll
        )
        XCTAssertEqual(XCTWaiter.wait(for: [quickMatchHidden], timeout: 10), .completed)
        activate(quickMatch)
        let quickMatchSelected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"),
            object: quickMatch
        )
        XCTAssertEqual(XCTWaiter.wait(for: [quickMatchSelected], timeout: 10), .completed)
        XCTAssertTrue(quickMatchScroll.waitForExistence(timeout: 10))

        let liveTab = element(
            SurroundUITestContract.AccessibilityID.quickMatchSpeedTab("live"),
            in: app,
            matching: .button
        )
        scrollIntoTappableArea(liveTab, in: app)
        activate(liveTab)
        XCTAssertTrue(liveTab.isSelected)
        XCTAssertFalse(waitingLegend.exists)
        XCTAssertFalse(popularLegend.exists)
        assertQuickMatchToggle(rapid, isOn: false, in: app)
        assertQuickMatchToggle(live, isOn: true, in: app)
        XCTAssertTrue(recap.label.contains("9 by 9"))
        XCTAssertTrue(recap.label.contains("13 by 13"))
        XCTAssertTrue(recap.label.contains("Byo-Yomi"))
        XCTAssertFalse(recap.label.contains("Fischer"))

        // Calling twice must leave Advanced open, including after a tab round-trip.
        openQuickMatchAdvanced(in: app)
        openQuickMatchAdvanced(in: app)

        let allowHandicap = SurroundUITestContract.AccessibilityID
            .quickMatchAllowHandicap
        let strictHandicap = SurroundUITestContract.AccessibilityID
            .quickMatchStrictHandicap
        assertQuickMatchToggle(allowHandicap, isOn: true, in: app)
        let strict = elementAfterScrolling(strictHandicap, in: app)
        XCTAssertEqual(strict.label, "Require handicap")
        scrollIntoTappableArea(strict, in: app)
        activate(strict)
        assertQuickMatchToggle(strictHandicap, isOn: true, in: app)
        XCTAssertTrue(recap.label.contains("Handicap required"))

        let allow = element(allowHandicap, in: app)
        scrollIntoTappableArea(allow, in: app)
        activate(allow)
        assertQuickMatchToggle(allowHandicap, isOn: false, in: app)
        XCTAssertTrue(recap.label.contains("No handicap"))
        XCTAssertFalse(strict.isEnabled)
        keepScreenshot("Quick Match – multiselection and Advanced", in: app)
    }

    func testRestoredLiveAutomatchLocksQuickMatchForm() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.home.rawValue,
        ])

        let homeSearchingBanner = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Searching for")
        ).firstMatch
        XCTAssertTrue(homeSearchingBanner.waitForExistence(timeout: 10))
        XCTAssertTrue(homeSearchingBanner.isHittable)
        keepScreenshot("Home – restored search progress", in: app)

        tap(
            SurroundUITestContract.AccessibilityID.homeNewGame,
            in: app,
            matching: .button
        )
        element(
            SurroundUITestContract.AccessibilityID.quickMatchSearching,
            in: app
        )
        let recap = element(
            SurroundUITestContract.AccessibilityID.quickMatchRecap,
            in: app
        )
        XCTAssertTrue(
            recap.label.contains("13 by 13"),
            "A restored search must describe its server-owned board size."
        )
        XCTAssertFalse(
            recap.label.contains("9 by 9"),
            "A restored search must not describe the saved editor draft."
        )
        XCTAssertTrue(recap.label.contains("Fischer"))
        XCTAssertTrue(recap.label.contains("Handicap required"))
        let cancel = element(
            SurroundUITestContract.AccessibilityID.quickMatchCancel,
            in: app,
            matching: .button
        )
        XCTAssertTrue(waitUntilHittable(cancel, timeout: 5))

        let boardSize = element(
            SurroundUITestContract.AccessibilityID.quickMatchBoardSize(9),
            in: app
        )
        let activeBoardSize = element(
            SurroundUITestContract.AccessibilityID.quickMatchBoardSize(13),
            in: app
        )
        XCTAssertFalse(
            boardSize.isEnabled,
            "A restored live search must lock the editable match criteria."
        )
        XCTAssertFalse(boardSize.isSelected)
        XCTAssertTrue(
            activeBoardSize.isSelected,
            "The disabled form must select the board size from the active entry."
        )

        let rapid = SurroundUITestContract.AccessibilityID
            .quickMatchSpeed("rapid")
        assertQuickMatchToggle(rapid, isOn: true, in: app)
        XCTAssertFalse(element(rapid, in: app).isEnabled)
        XCTAssertFalse(element(
            SurroundUITestContract.AccessibilityID.quickMatchSpeedTabs,
            in: app,
            matching: .segmentedControl
        ).isEnabled)
        assertQuickMatchToggle(
            SurroundUITestContract.AccessibilityID.quickMatchSpeed("live"),
            isOn: false,
            in: app
        )

        openQuickMatchAdvanced(in: app)
        let clock = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID
                .quickMatchClockPreference("fischer"),
            in: app,
            matching: .button
        )
        XCTAssertTrue(clock.isSelected)
        XCTAssertFalse(element(
            SurroundUITestContract.AccessibilityID.quickMatchClockSystem,
            in: app,
            matching: .segmentedControl
        ).isEnabled)
        assertQuickMatchToggle(
            SurroundUITestContract.AccessibilityID.quickMatchAllowHandicap,
            isOn: true,
            in: app
        )
        assertQuickMatchToggle(
            SurroundUITestContract.AccessibilityID.quickMatchStrictHandicap,
            isOn: true,
            in: app
        )
        XCTAssertFalse(
            element(
                SurroundUITestContract.AccessibilityID.quickMatchStrictHandicap,
                in: app
            ).isEnabled
        )

        let find = app.buttons.matching(
            identifier: SurroundUITestContract.AccessibilityID.quickMatchFind
        ).firstMatch
        XCTAssertFalse(
            find.exists,
            "A restored live search must replace Find with its searching state."
        )
        keepScreenshot("Quick Match – restored live search", in: app)
    }

    func testQuickMatchCorrespondenceAllowsAnotherSearch() {
        let app = launchApp()

        tap(
            SurroundUITestContract.AccessibilityID.homeNewGame,
            in: app,
            matching: .button
        )
        element(
            SurroundUITestContract.AccessibilityID.quickMatchRecap,
            in: app
        )

        tap(
            SurroundUITestContract.AccessibilityID.quickMatchBoardSize(13),
            in: app
        )
        let correspondenceID = SurroundUITestContract.AccessibilityID
            .quickMatchSpeedTab("correspondence")
        let correspondence = elementAfterScrolling(correspondenceID, in: app)
        scrollIntoTappableArea(correspondence, in: app)
        tap(
            correspondence,
            description: "Correspondence speed",
            in: app
        )
        XCTAssertTrue(correspondence.isSelected)
        XCTAssertFalse(
            app.switches.matching(identifier:
                SurroundUITestContract.AccessibilityID.quickMatchSpeed("rapid")
            ).firstMatch.exists
        )
        assertSelected(
            SurroundUITestContract.AccessibilityID.quickMatchBoardSize(9),
            in: app
        )
        assertSelected(
            SurroundUITestContract.AccessibilityID.quickMatchBoardSize(13),
            in: app
        )

        let gameCount = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID.quickMatchGameCount,
            in: app,
            matching: .stepper
        )
        scrollIntoTappableArea(gameCount, in: app)
        XCTAssertTrue(waitForValue("1", in: gameCount, timeout: 5))
        let increment = gameCount.buttons[
            SurroundUITestContract.AccessibilityID.quickMatchGameCount + "-Increment"
        ]
        tap(increment, description: "Increase correspondence game count", in: app)
        XCTAssertTrue(waitForValue("2", in: gameCount, timeout: 5))

        let find = element(
            SurroundUITestContract.AccessibilityID.quickMatchFind,
            in: app,
            matching: .button
        )
        XCTAssertEqual(find.label, "Find 2 games")

        tap(find, description: "Find two correspondence games", in: app)
        let banner = element(
            SurroundUITestContract.AccessibilityID.quickMatchWaitingBanner,
            in: app
        )
        let firstBatch = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label CONTAINS %@",
                "Searching for 2 games"
            ),
            object: banner
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [firstBatch], timeout: 5),
            .completed,
            "Each requested correspondence game must create a separate search."
        )
        let findAnother = element(
            SurroundUITestContract.AccessibilityID.quickMatchFind,
            in: app,
            matching: .button
        )
        XCTAssertTrue(
            waitUntilHittable(findAnother, timeout: 5),
            "Correspondence must leave another batch available."
        )
        XCTAssertEqual(findAnother.label, "Find 2 more games")
        keepScreenshot("Quick Match – correspondence tab", in: app)

        openQuickMatchAdvanced(in: app)
        let clock = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID.quickMatchClockSystem,
            in: app
        )
        XCTAssertTrue(
            [clock.label, clock.value as? String ?? ""]
                .joined(separator: " ").contains("Fischer")
        )
        XCTAssertFalse(
            app.segmentedControls.matching(
                identifier: SurroundUITestContract.AccessibilityID
                    .quickMatchClockSystem
            ).firstMatch.exists,
            "Correspondence must describe its fixed Fischer clock without an editable clock picker."
        )
        XCTAssertTrue(gameCount.isEnabled)
        XCTAssertTrue(correspondence.isEnabled)
        activate(findAnother)

        let bothBatches = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Searching for 4 games"),
            object: banner
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [bothBatches], timeout: 5),
            .completed,
            "Repeating a batch must add searches without replacing the first batch."
        )
        XCTAssertEqual(findAnother.label, "Find 2 more games")
        // The offline runtime keeps these searches optimistic rather than
        // inserting server entries, so the destination has no stored requests.
        tap(banner, description: "Show empty active-search list", in: app)
        XCTAssertTrue(app.staticTexts["No active searches"].waitForExistence(timeout: 5))
        keepScreenshot("Waiting games – no active searches", in: app)
    }

    func testQuickMatchShowsPendingCorrespondenceSubmission() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.holdQuickMatchAcknowledgementsLaunchArgument,
        ])
        tap(SurroundUITestContract.AccessibilityID.homeNewGame, in: app, matching: .button)
        guard let gameCount = selectQuickMatchCorrespondence(in: app) else { return }
        scrollIntoTappableArea(gameCount, in: app)
        tap(
            gameCount.buttons[SurroundUITestContract.AccessibilityID.quickMatchGameCount + "-Increment"],
            description: "Request two correspondence games",
            in: app
        )
        let find = element(SurroundUITestContract.AccessibilityID.quickMatchFind, in: app, matching: .button)
        tap(find, description: "Start correspondence searches", in: app)
        let starting = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Starting searches…"),
            object: find
        )
        XCTAssertEqual(XCTWaiter.wait(for: [starting], timeout: 5), .completed)
        XCTAssertFalse(find.isEnabled, "Awaiting acknowledgement must prevent duplicate submissions.")
        XCTAssertFalse(gameCount.isEnabled)
        XCTAssertTrue(element(SurroundUITestContract.AccessibilityID.quickMatchWaitingBanner, in: app)
            .label.contains("Searching for 2 games"))
        keepScreenshot("Quick Match – starting correspondence searches", in: app)
    }

    func testQuickMatchShowsMatchingOpenCustomGamesInline() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.quickMatch.rawValue,
        ])

        XCTAssertTrue(app.segmentedControls[SurroundUITestContract.AccessibilityID.newGameOptionPicker]
            .buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open (")).firstMatch.exists)

        element(
            SurroundUITestContract.AccessibilityID.quickMatchRecap,
            in: app
        )

        let boardSize = element(
            SurroundUITestContract.AccessibilityID.quickMatchBoardSize(19),
            in: app
        )
        scrollIntoTappableArea(boardSize, in: app)
        activate(boardSize)
        tap(
            SurroundUITestContract.AccessibilityID.quickMatchBoardSize(9),
            in: app
        )

        let correspondence = element(
            SurroundUITestContract.AccessibilityID.quickMatchSpeedTab("correspondence"),
            in: app
        )
        scrollIntoTappableArea(correspondence, in: app)
        activate(correspondence)

        let summary = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID
                .quickMatchMatchingChallenges,
            in: app,
            matching: .button
        )
        XCTAssertTrue(
            summary.label.contains("10 open custom games"),
            "Only non-rengo custom games matching the selected size and speed should be suggested."
        )
        elementAfterScrolling(
            SurroundUITestContract.AccessibilityID
                .quickMatchOpenChallenge(91_001),
            in: app
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(
                    identifier: SurroundUITestContract.AccessibilityID
                        .quickMatchRecap
                )
                .firstMatch
                .exists,
            "Matching custom games should appear inline without leaving Quick Match."
        )
    }

    func testWaitingQuickMatchRequestsShowNeutralClockSummaries() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.waitingGames.rawValue,
        ])

        let exact = element(
            SurroundUITestContract.AccessibilityID.waitingGamesAutomatchEntry(
                "f0050bcf-f5fc-46c8-9ed6-01dfd898e0d0"
            ),
            in: app
        )
        XCTAssertTrue(exact.staticTexts["Fischer"].exists)
        XCTAssertFalse(exact.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "+")
        ).firstMatch.exists, "Clock values belong in the speed picker, not request cards.")

        let flexible = element(
            SurroundUITestContract.AccessibilityID.waitingGamesAutomatchEntry(
                "f0050bcf-f5fc-46c8-9ed6-01dfd898e0d1"
            ),
            in: app
        )
        XCTAssertTrue(flexible.staticTexts["Fischer or Byo-Yomi"].exists)
        XCTAssertFalse(flexible.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "+", "preferred")
        ).firstMatch.exists)

        let mixed = element(
            SurroundUITestContract.AccessibilityID.waitingGamesAutomatchEntry(
                "f0050bcf-f5fc-46c8-9ed6-01dfd898e0d2"
            ),
            in: app
        )
        XCTAssertTrue(mixed.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Blitz", "Fischer")
        ).firstMatch.exists)
        XCTAssertTrue(mixed.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Rapid", "Byo-Yomi")
        ).firstMatch.exists)
        XCTAssertTrue(mixed.staticTexts["No handicap"].exists)
        keepScreenshot("Waiting games – neutral clock summaries", in: app)
    }

    func testQuickMatchActivityIsExposedWithoutRelyingOnColor() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.quickMatch.rawValue,
        ])

        let waitingBoard = element(
            SurroundUITestContract.AccessibilityID.quickMatchBoardSize(9),
            in: app
        )
        XCTAssertTrue(
            waitingBoard.label.contains("Players waiting")
        )
        XCTAssertFalse((waitingBoard.value as? String ?? "").contains("Players waiting"))

        let popularBoard = element(
            SurroundUITestContract.AccessibilityID.quickMatchBoardSize(13),
            in: app
        )
        XCTAssertTrue(
            popularBoard.label.contains("Popular lately")
        )
        XCTAssertFalse((popularBoard.value as? String ?? "").contains("Popular lately"))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Players waiting")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Popular lately")).firstMatch.exists)

        let waitingSpeed = element(
            SurroundUITestContract.AccessibilityID.quickMatchSpeed("rapid"),
            in: app
        )
        XCTAssertTrue(waitingSpeed.label.contains("Players waiting"))
        assertQuickMatchToggle(
            SurroundUITestContract.AccessibilityID.quickMatchSpeed("rapid"),
            isOn: true,
            in: app
        )

        let popularSpeed = element(
            SurroundUITestContract.AccessibilityID.quickMatchSpeed("live"),
            in: app
        )
        XCTAssertTrue(popularSpeed.label.contains("Popular lately"))
        assertQuickMatchToggle(
            SurroundUITestContract.AccessibilityID.quickMatchSpeed("live"),
            isOn: false,
            in: app
        )

        for speed in ["blitz", "rapid", "live"] {
            let clocks = element(
                SurroundUITestContract.AccessibilityID.quickMatchClockValues(speed),
                in: app
            )
            XCTAssertTrue(clocks.label.contains("Fischer"))
            XCTAssertTrue(clocks.label.contains("Byo-Yomi"))
            XCTAssertTrue(clocks.label.contains("+"), "Every speed must expose actual clock values, even when off.")
        }
        keepScreenshot("Quick Match – clock values under all speeds", in: app)
    }

    func testFixtureGameOpens() {
        let app = launchApp()
        let gameID = SurroundUITestContract.fixtureGameID

        element(
            SurroundUITestContract.AccessibilityID.homeGame(gameID),
            in: app,
            matching: .button
        )
        tap(
            SurroundUITestContract.AccessibilityID.homeGamePlayerInfo(gameID),
            in: app
        )
        element(SurroundUITestContract.AccessibilityID.gameDetail(gameID), in: app)
        element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        element(SurroundUITestContract.AccessibilityID.gameOptions, in: app)
        tap(
            SurroundUITestContract.AccessibilityID.gameActionsMenu,
            in: app
        )
        requiredMenuButton(
            SurroundUITestContract.AccessibilityID.gameResign,
            title: "Resign",
            in: app
        )
    }

    func testRegularIPadToolbarPlacesActiveGamesBetweenAnalyzeAndZen() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("This toolbar order applies to native iPad.")
        #else
        try XCTSkipIf(
            UIDevice.current.userInterfaceIdiom != .pad,
            "This toolbar order applies to native iPad."
        )
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.liveGameBannerNavigationLaunchArgument,
        ], orientation: .landscapeLeft)
        let gameID = SurroundUITestContract.liveBannerCorrespondenceGameIDs[0]
        let firstGame = elementAfterScrolling(SurroundUITestContract.AccessibilityID.homeGame(gameID), in: app)
        scrollIntoTappableArea(firstGame, in: app)
        tap(firstGame, description: "Open the first correspondence game", in: app)
        element(SurroundUITestContract.AccessibilityID.gameDetail(gameID), in: app)

        XCTAssertGreaterThan(
            app.frame.width, app.frame.height,
            "This test requires a wide native iPad window."
        )
        XCTAssertFalse(
            app.toolbars.buttons
                .matching(identifier: SurroundUITestContract.AccessibilityID.gameActiveGamesButton)
                .firstMatch.exists,
            "iPad must not retain the bottom Active Games item."
        )
        let analyzeButton = app.navigationBars.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.gameAnalyzeToggle)
            .firstMatch
        let activeGamesButton = app.navigationBars.buttons
            .matching(identifier: SurroundUITestContract.AccessibilityID.gameActiveGamesButton)
            .firstMatch
        let zenButton = app.navigationBars.buttons
            .matching(identifier: SurroundUITestContract.AccessibilityID.gameZenEnter)
            .firstMatch
        for button in [analyzeButton, activeGamesButton, zenButton] {
            XCTAssertTrue(button.waitForExistence(timeout: 10), "Expected a direct toolbar control: \(button)")
            XCTAssertTrue(waitUntilHittable(button, timeout: 10), "Expected a hittable toolbar control: \(button)")
        }
        let order = XCTAttachment(string: """
            Analyze: \(analyzeButton.frame)
            Active Games: \(activeGamesButton.frame)
            Zen: \(zenButton.frame)
            """)
        order.name = "Required regular iPad toolbar order"
        order.lifetime = .keepAlways
        add(order)
        keepScreenshot("Wide iPad toolbar order", in: app)
        XCTAssertLessThan(
            analyzeButton.frame.midX, activeGamesButton.frame.midX,
            "Active Games must follow Analyze in the regular iPad toolbar."
        )
        XCTAssertLessThan(
            activeGamesButton.frame.midX, zenButton.frame.midX,
            "Active Games must precede Zen in the regular iPad toolbar."
        )
        #endif
    }

    func testActiveGamesPopoverSwitchesGameAndDismisses() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.liveGameBannerNavigationLaunchArgument,
        ], orientation: .portrait)
        let gameIDs = SurroundUITestContract.liveBannerCorrespondenceGameIDs
        let firstGame = elementAfterScrolling(SurroundUITestContract.AccessibilityID.homeGame(gameIDs[0]), in: app)
        scrollIntoTappableArea(firstGame, in: app)
        tap(firstGame, description: "Open the first correspondence game", in: app)
        element(SurroundUITestContract.AccessibilityID.gameDetail(gameIDs[0]), in: app)
        let carousel = app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.gameActiveGamesCarousel).firstMatch
        XCTAssertFalse(carousel.exists, "Game thumbnails must not occupy the game screen by default.")

        func openActiveGames() {
            let identifier = SurroundUITestContract.AccessibilityID
                .gameActiveGamesButton
            #if !targetEnvironment(macCatalyst)
            if UIDevice.current.userInterfaceIdiom == .pad {
                XCTAssertFalse(
                    app.toolbars.buttons.matching(identifier: identifier)
                        .firstMatch.exists,
                    "iPad must not retain the bottom Active Games item."
                )
                let topButton = app.navigationBars.buttons
                    .matching(identifier: identifier).firstMatch
                if topButton.exists {
                    let analyzeButton = app.navigationBars.descendants(matching: .any)
                        .matching(identifier: SurroundUITestContract.AccessibilityID.gameAnalyzeToggle)
                        .firstMatch
                    let zenButton = app.navigationBars.buttons
                        .matching(identifier: SurroundUITestContract.AccessibilityID.gameZenEnter)
                        .firstMatch
                    if analyzeButton.isHittable && topButton.isHittable && zenButton.isHittable {
                        let order = XCTAttachment(string: """
                            Analyze: \(analyzeButton.frame)
                            Active Games: \(topButton.frame)
                            Zen: \(zenButton.frame)
                            """)
                        order.name = "Regular iPad toolbar order checked"
                        order.lifetime = .keepAlways
                        add(order)
                        XCTAssertLessThan(
                            analyzeButton.frame.midX, topButton.frame.midX,
                            "Active Games must follow Analyze in the regular iPad toolbar."
                        )
                        XCTAssertLessThan(
                            topButton.frame.midX, zenButton.frame.midX,
                            "Active Games must precede Zen in the regular iPad toolbar."
                        )
                    }
                    tap(topButton, description: "Top Active Games action", in: app)
                } else {
                    tap(
                        app.navigationBars.buttons["More"].firstMatch,
                        description: "Game toolbar overflow",
                        in: app
                    )
                    tap(
                        requiredMenuButton(identifier, title: "Active games", in: app),
                        description: "Overflowed Active Games action",
                        in: app
                    )
                }
                return
            }
            #endif
            let activeGamesButton = element(identifier, in: app, matching: .button)
            // iOS 27 reports this visible bottom-bar item as not hittable while
            // the hidden tab bar retains an accessibility frame over it.
            activeGamesButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        openActiveGames()
        let popover = element(SurroundUITestContract.AccessibilityID.gameActiveGamesPopover, in: app)
        element(SurroundUITestContract.AccessibilityID.gameActiveGamesCarousel, in: app)
        for gameID in gameIDs {
            let entries = popover.descendants(matching: .button)
                .matching(identifier: SurroundUITestContract.AccessibilityID.gameActiveGamesEntry(gameID))
            XCTAssertTrue(entries.firstMatch.waitForExistence(timeout: 10))
            XCTAssertEqual(entries.count, 1, "Each popover game must have a unique entry identifier.")
            XCTAssertTrue(entries.firstMatch.label.contains("Friendly Match"))
            XCTAssertTrue(
                entries.firstMatch.label.contains("OrbitFox"),
                "The opponent must be announced even when the games share the same name."
            )
            XCTAssertTrue(
                entries.firstMatch.label.contains("Your move"),
                "Turn status must be announced without relying on the thumbnail color."
            )
            XCTAssertEqual(entries.firstMatch.isSelected, gameID == gameIDs[0])
            XCTAssertFalse(popover.descendants(matching: .any)
                .matching(identifier: SurroundUITestContract.AccessibilityID.homeGame(gameID)).firstMatch.exists,
                "Popover entries must not reuse Home's game identifiers.")
        }
        let nextGame = popover.descendants(matching: .button)
            .matching(identifier: SurroundUITestContract.AccessibilityID.gameActiveGamesEntry(gameIDs[1])).firstMatch
        XCTAssertTrue(nextGame.waitForExistence(timeout: 10))
        tap(nextGame, description: "Switch to the second correspondence game", in: app)
        element(SurroundUITestContract.AccessibilityID.gameDetail(gameIDs[1]), in: app)
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: popover)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
        XCTAssertFalse(carousel.exists, "Selecting a game must return to its unobstructed board.")
        openActiveGames()
        let reopened = element(SurroundUITestContract.AccessibilityID.gameActiveGamesPopover, in: app)
        let selectedGame = reopened.descendants(matching: .button)
            .matching(identifier: SurroundUITestContract.AccessibilityID.gameActiveGamesEntry(gameIDs[1]))
            .firstMatch
        XCTAssertTrue(selectedGame.waitForExistence(timeout: 10))
        XCTAssertTrue(selectedGame.isSelected, "Reopening must retain the selected game.")
        tap(selectedGame, description: "Return to the selected game", in: app)
        let reopenedDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: reopened
        )
        XCTAssertEqual(XCTWaiter.wait(for: [reopenedDismissed], timeout: 10), .completed)
    }

    func testGameMessageNotificationUsesToolbarWithoutCoveringClocks() {
        // The basic game fixture has no private messages. Explicitly seed
        // incoming messages so this journey exercises the unread notice.
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.messagesContentLaunchArgument,
        ], orientation: .portrait)
        let id = SurroundUITestContract.AccessibilityID.self
        let messageIdentifier = "global.privateMessages"
        let messageButton = element(messageIdentifier, in: app, matching: .button)
        let unreadCount = Int(messageButton.value as? String ?? "") ?? 0
        XCTAssertGreaterThan(unreadCount, 0,
                             "The notification fixture must contain unread private messages.")
        tap(id.homeGame(SurroundUITestContract.fixtureGameID), in: app)
        setGameAnalyzing(true, in: app)

        XCTAssertTrue(messageButton.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: messageIdentifier).count, 1,
                       "Game Detail replaces the overlay icon with one native toolbar action.")
        XCTAssertTrue(messageButton.isHittable,
                      "Private messages must remain reachable in Game Detail.")
        XCTAssertEqual(Int(messageButton.value as? String ?? ""), unreadCount,
                       "Native toolbar extraction must preserve the unread-message count.")
        XCTAssertGreaterThanOrEqual(messageButton.frame.width, 44)
        XCTAssertGreaterThanOrEqual(messageButton.frame.height, 44)
        XCTAssertTrue(pollUntil(timeout: 5) {
            app.buttons.matching(identifier: "game.clock.white").allElementsBoundByIndex
                .contains { $0.isHittable }
        }, "The current clock must remain reachable.")
        let clockCandidates = ["game.clock.black", "game.clock.white"].flatMap { identifier in
            app.buttons.matching(identifier: identifier).allElementsBoundByIndex
        }
        // Retained hidden content can remain in the XCTest tree.
        // Count the reachable controls, including any duplicate targets.
        let visibleClocks = clockCandidates.filter { $0.isHittable }
        let currentClockIsInHorizontalNavigationBar = app.navigationBars.allElementsBoundByIndex.contains { bar in
            bar.frame.width > bar.frame.height
                && bar.buttons.matching(identifier: "game.clock.white").allElementsBoundByIndex
                    .contains { $0.isHittable }
        }
        let clockEvidence = XCTAttachment(string: clockCandidates.map {
            "\($0.identifier): hittable=\($0.isHittable), frame=\($0.frame)"
        }.joined(separator: "\n") + "\n\n" + app.debugDescription)
        clockEvidence.name = "Notification toolbar clock candidates"
        clockEvidence.lifetime = .keepAlways
        add(clockEvidence)
        keepScreenshot("Private-message toolbar leaves game clocks visible", in: app)
        if app.frame.width < 500 && currentClockIsInHorizontalNavigationBar {
            XCTAssertEqual(visibleClocks.count, 1,
                           "The crowded phone header must show the complete current clock instead of compressing two Fischer clocks.")
        }
        XCTAssertEqual(visibleClocks.filter { $0.identifier == "game.clock.white" }.count, 1,
                       "The selected layout must expose exactly one reachable current clock.")
        for clock in visibleClocks {
            XCTAssertTrue(clock.isHittable, "Each displayed clock must remain reachable.")
            let overlap = messageButton.frame.intersection(clock.frame)
            XCTAssertTrue(overlap.isNull || overlap.isEmpty,
                          "The message action must not cover \(clock.identifier): \(overlap)")
            XCTAssertGreaterThanOrEqual(clock.frame.height, 44)
        }
        tap(messageButton, description: "Open private messages from Game Detail", in: app)
        element("global.privateMessagesPanel", in: app)
    }

    func testLiveGameBannerUsesHomeNavigationStack() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.liveGameBannerNavigationLaunchArgument,
        ], orientation: .portrait)
        let correspondenceID = SurroundUITestContract.liveBannerCorrespondenceGameIDs[0]
        let correspondence = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID.homeGame(correspondenceID),
            in: app
        )
        scrollIntoTappableArea(correspondence, in: app)
        tap(correspondence, description: "Open correspondence game", in: app)
        element(SurroundUITestContract.AccessibilityID.gameDetail(correspondenceID), in: app)
        let carousel = app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.gameActiveGamesCarousel).firstMatch
        XCTAssertFalse(carousel.exists, "Active games must stay hidden until requested.")
        let banner = element(SurroundUITestContract.AccessibilityID.liveGameBanner, in: app, matching: .button)

        func openLiveGameFromBanner() {
            tap(banner, description: "Open active live game", in: app)
            element(
                SurroundUITestContract.AccessibilityID.gameDetail(SurroundUITestContract.fixtureGameID),
                in: app
            )
            XCTAssertFalse(banner.exists, "The live-game banner must disappear on the live board.")
            XCTAssertFalse(carousel.exists, "The correspondence carousel must not remain on the only live game.")
            XCTAssertFalse(app.navigationBars.buttons["Close"].exists, "Active games must open in the navigation stack.")
            XCTAssertFalse(
                app.buttons[SurroundUITestContract.AccessibilityID.gameZenExit].exists,
                "The live game must open outside Zen mode."
            )
        }

        func backToHome() {
            // iOS 18 exposes the destination title; newer UIKit uses BackButton.
            // Trailing toolbar controls can overflow, so match Back directly.
            let back = app.navigationBars.buttons.matching(NSPredicate(
                format: "identifier == %@ OR label == %@", "BackButton", "Active games"
            )).firstMatch
            tap(back, description: "Back to active games", in: app)
            // Identify Home by its navigation bar and screen, even when its
            // New game button is scrolled offscreen after returning from history.
            XCTAssertTrue(app.navigationBars["Active games"].waitForExistence(timeout: 10))
            element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
            XCTAssertFalse(app.descendants(matching: .any)
                .matching(identifier: SurroundUITestContract.AccessibilityID.screenGameHistory)
                .firstMatch.exists)
        }

        activateZenControl(SurroundUITestContract.AccessibilityID.gameZenEnter, in: app)
        element(SurroundUITestContract.AccessibilityID.gameZenExit, in: app)
        openLiveGameFromBanner()
        keepScreenshot("Live banner – replaces correspondence detail", in: app)
        backToHome()

        let publicGamesTabs = app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.navigationPublicGames)
        // The live banner can cover iPad's top tab bar. Use the sidebar when
        // needed, and account for duplicate accessibility nodes in adaptive tabs.
        let openedSidebar = !publicGamesTabs.allElementsBoundByIndex.contains { $0.isHittable }
        if openedSidebar {
            keepScreenshot("Live banner – overlaps iPad tabs", in: app)
            if let sidebar = nativeSidebarToggle(in: app) {
                tap(sidebar, description: "Show navigation sidebar", in: app)
            }
        }
        var publicGamesTab: XCUIElement?
        let publicGamesReady = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                publicGamesTab = publicGamesTabs.allElementsBoundByIndex.first(where: { $0.isHittable })
                return publicGamesTab != nil
            },
            object: nil
        )
        guard XCTWaiter.wait(for: [publicGamesReady], timeout: 10) == .completed,
              let publicGamesTab else {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Accessibility hierarchy – Public games navigation unavailable"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            keepScreenshot("Live banner – Public games navigation unavailable", in: app)
            XCTFail("Expected a hittable Public games tab or sidebar item.")
            return
        }
        tap(publicGamesTab, description: "Open Public games", in: app)
        element(SurroundUITestContract.AccessibilityID.screenPublicGames, in: app)
        if openedSidebar && app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.navigationSettings)
            .allElementsBoundByIndex.contains(where: { $0.isHittable }) {
            // Restore the initial sidebar state so it cannot affect later tests.
            if let sidebar = nativeSidebarToggle(in: app) {
                tap(sidebar, description: "Hide navigation sidebar", in: app)
            }
        }
        openLiveGameFromBanner()
        backToHome()

        func openGameHistory() {
            let history = elementAfterScrolling(
                SurroundUITestContract.AccessibilityID.homeHistoryViewAll,
                in: app,
                matching: .button
            )
            scrollIntoTappableArea(history, in: app)
            tap(history, description: "Open game history", in: app)
            element(SurroundUITestContract.AccessibilityID.screenGameHistory, in: app)
        }

        openGameHistory()
        openLiveGameFromBanner()
        backToHome()

        // Two levels deep. The banner has to pop Game history *and* its detail
        // while pushing Home's own destination in the same update.
        openGameHistory()
        let historyGameID = SurroundUITestContract.liveBannerHistoryGameID
        // Home keeps its own copy of the same row behind the pushed screen, so
        // scope the query to Game history rather than taking a first match.
        let historyGame = app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.screenGameHistory)
            .firstMatch
            .descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.homeHistoryGame(historyGameID))
            .firstMatch
        XCTAssertTrue(historyGame.waitForExistence(timeout: 10))
        scrollIntoTappableArea(historyGame, in: app)
        tap(historyGame, description: "Open your finished realtime game from history", in: app)
        element(SurroundUITestContract.AccessibilityID.gameDetail(historyGameID), in: app)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.gameActiveGamesButton].exists,
                       "A history game does not own an active-games picker.")
        XCTAssertTrue(banner.waitForExistence(timeout: 5),
                      "Your finished realtime game must preserve the banner for the separate active live game.")
        openLiveGameFromBanner()
        keepScreenshot("Live banner – replaces a history detail", in: app)
        backToHome()
    }

    func testLiveGameBannerRestoresCompactChatBoard() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("The compact Chat layout requires an iOS device.")
        #else
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.liveGameBannerNavigationLaunchArgument,
            SurroundUITestContract.compactGameLayoutLaunchArgument,
        ], orientation: .portrait)
        let correspondence = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID.homeGame(
                SurroundUITestContract.liveBannerCorrespondenceGameIDs[0]
            ),
            in: app
        )
        scrollIntoTappableArea(correspondence, in: app)
        tap(correspondence, description: "Open correspondence game", in: app)

        selectSegment(at: 2, in: SurroundUITestContract.AccessibilityID.gameDisplayModePicker, app: app)
        dismissCompactChatInputAndWaitForLayout(in: app)
        tap(SurroundUITestContract.AccessibilityID.gameChatBoardHide, in: app, matching: .button)
        element(SurroundUITestContract.AccessibilityID.gameChatBoardShow, in: app, matching: .button)
        XCTAssertTrue(pollUntil(timeout: 10) { !gameBoardIsShown(in: app) })

        selectSegment(at: 1, in: SurroundUITestContract.AccessibilityID.gameDisplayModePicker, app: app)
        activateZenControl(SurroundUITestContract.AccessibilityID.gameZenEnter, in: app)
        element(SurroundUITestContract.AccessibilityID.gameZenExit, in: app)
        tap(SurroundUITestContract.AccessibilityID.liveGameBanner, in: app, matching: .button)
        element(
            SurroundUITestContract.AccessibilityID.gameDetail(SurroundUITestContract.fixtureGameID),
            in: app
        )
        element(SurroundUITestContract.AccessibilityID.gameZenEnter, in: app)

        // Player info always shows the board, so reopen Chat to verify that
        // the previous game's hidden-board choice was also cleared.
        selectSegment(at: 2, in: SurroundUITestContract.AccessibilityID.gameDisplayModePicker, app: app)
        dismissCompactChatInputAndWaitForLayout(in: app)
        element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        element(SurroundUITestContract.AccessibilityID.gameChatBoardHide, in: app, matching: .button)
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.gameChatBoardShow).firstMatch.exists)
        keepScreenshot("Live banner – restores the compact Chat board", in: app)
        #endif
    }

    func testQuickMatchRestorationKeepsSettingsEditable() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.quickMatch.rawValue,
            SurroundUITestContract.automatchRestorationLaunchArgument,
        ])

        let speedTabs = element(
            SurroundUITestContract.AccessibilityID.quickMatchSpeedTabs,
            in: app
        )
        XCTAssertTrue(
            speedTabs.isEnabled,
            "Restoration must not lock the match criteria."
        )
        let liveTab = element(
            SurroundUITestContract.AccessibilityID.quickMatchSpeedTab("live"),
            in: app,
            matching: .button
        )
        scrollIntoTappableArea(liveTab, in: app)
        activate(liveTab)
        XCTAssertTrue(liveTab.isSelected)

        // A live request could replace a search the restore has not reported
        // yet, so Find waits — and says why.
        let find = element(
            SurroundUITestContract.AccessibilityID.quickMatchFind,
            in: app,
            matching: .button
        )
        XCTAssertFalse(find.isEnabled)
        let reason = element(
            SurroundUITestContract.AccessibilityID.quickMatchConnectionReason,
            in: app
        )
        XCTAssertEqual(reason.label, "Restoring active searches from OGS…")

        // The editor itself stays live: toggling a board size must take effect.
        let thirteen = element(
            SurroundUITestContract.AccessibilityID.quickMatchBoardSize(13),
            in: app
        )
        scrollIntoTappableArea(thirteen, in: app)
        XCTAssertTrue(thirteen.isEnabled)
        let wasSelected = thirteen.isSelected
        activate(thirteen)
        let flipped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == %@", NSNumber(value: !wasSelected)),
            object: thirteen
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [flipped], timeout: 5),
            .completed,
            "A board size must respond while searches are being restored."
        )

        // Accepting someone else's live game is a submission too, so the
        // matching custom games stay blocked.
        let liveChallenge = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID.quickMatchOpenChallenge(
                SurroundUITestContract.restorationLiveChallengeID
            ),
            in: app
        )
        XCTAssertFalse(
            liveChallenge.isEnabled,
            "A live restore must not allow accepting a matching live game."
        )
        keepScreenshot("Quick Match – editable while restoring", in: app)

        // Correspondence is unaffected by a live restore.
        let correspondenceTab = element(
            SurroundUITestContract.AccessibilityID.quickMatchSpeedTab("correspondence"),
            in: app,
            matching: .button
        )
        scrollIntoTappableArea(correspondenceTab, in: app)
        activate(correspondenceTab)
        XCTAssertTrue(waitUntilHittable(find, timeout: 5))
        XCTAssertTrue(find.isEnabled)
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(identifier: SurroundUITestContract.AccessibilityID.quickMatchConnectionReason)
                .firstMatch.exists,
            "A correspondence request has nothing to wait for."
        )
        // The fixture's custom games are 19×19, which the saved draft leaves
        // unselected, so select it to bring the suggestions into view.
        let nineteen = element(
            SurroundUITestContract.AccessibilityID.quickMatchBoardSize(19),
            in: app
        )
        scrollIntoTappableArea(nineteen, in: app)
        XCTAssertFalse(nineteen.isSelected)
        activate(nineteen)
        let correspondenceChallenge = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID.quickMatchOpenChallenge(91_001),
            in: app
        )
        XCTAssertTrue(
            correspondenceChallenge.isEnabled,
            "A live restore must not block accepting a correspondence game."
        )
    }

    func testWidgetDeepLinkRouting() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(
            "Widget URL interaction is exercised on iPad; Catalyst scene reuse remains a manual multi-window check."
        )
        #else
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.widgetDeepLinkRoutingLaunchArgument,
        ])
        let firstGameID = SurroundUITestContract.fixtureGameID
        let secondGameID =
            SurroundUITestContract.widgetRoutingSecondGameID
        let missingGameID =
            SurroundUITestContract.widgetRoutingMissingGameID

        // Terminate the priming launch so the first URL exercises cold launch.
        app.terminate()
        app.open(URL(string: "surround://home/\(firstGameID)")!)
        element(
            SurroundUITestContract.AccessibilityID.gameDetail(firstGameID),
            in: app
        )

        // A newer tap atomically replaces an already open game.
        app.open(URL(string: "surround://home/\(secondGameID)")!)
        element(
            SurroundUITestContract.AccessibilityID.gameDetail(secondGameID),
            in: app
        )

        let playerProfileEntry = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", SurroundUITestContract.AccessibilityID.profileBannerAvatarPrefix
        )).firstMatch
        tap(playerProfileEntry, description: "Open player profile above the active game", in: app)
        let profile = element(SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)

        // Repeating the same game route must also remove its profile descendants
        // even though the active-game presentation flag is already true.
        app.open(URL(string: "surround://home/\(secondGameID)")!)
        element(
            SurroundUITestContract.AccessibilityID.gameDetail(secondGameID),
            in: app
        )
        let profileWasPopped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: profile
        )
        XCTAssertEqual(XCTWaiter.wait(for: [profileWasPopped], timeout: 10), .completed)

        // A REST-only route fails deterministically, then returns to the
        // existing Home context. Do not assert the transient loading overlay:
        // app.open may reconnect after the route has already reached its alert.
        app.open(URL(string: "surround://home")!)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        app.open(URL(string: "surround://home/\(missingGameID)")!)
        let failureAlert = openGameFailureAlert(in: app)
        let cancel = failureAlert.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)

        // Tracked sheets must not block a subsequent game route.
        tap(
            SurroundUITestContract.AccessibilityID.homeNewGame,
            in: app,
            matching: .button
        )
        let newGame = element(
            SurroundUITestContract.AccessibilityID.screenNewGame,
            in: app
        )
        app.open(URL(string: "surround://home/\(firstGameID)")!)
        element(
            SurroundUITestContract.AccessibilityID.gameDetail(firstGameID),
            in: app
        )
        XCTAssertFalse(
            newGame.exists,
            "Opening a routed game must dismiss the tracked New Game sheet."
        )
        #endif
    }

    func testHomeHistoryRetryRecoversAndKeepsNavigationAvailable() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.homeHistoryFailsOnceLaunchArgument,
        ])

        let error = element(
            SurroundUITestContract.AccessibilityID.homeHistoryError,
            in: app
        )
        let retry = element(
            SurroundUITestContract.AccessibilityID.homeHistoryRetry,
            in: app,
            matching: .button
        )
        // XCTest can call an element hittable while its frame still overlaps
        // the tab bar. Move Retry only when it is obscured or in that zone.
        scrollIntoTappableArea(retry, in: app)
        tap(
            SurroundUITestContract.AccessibilityID.homeHistoryRetry,
            in: app,
            matching: .button
        )
        element(
            SurroundUITestContract.AccessibilityID.homeHistoryGame(
                SurroundUITestContract.homeHistoryRetryFixtureGameID
            ),
            in: app
        )
        let errorDisappeared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: error
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [errorDisappeared], timeout: 10),
            .completed,
            "Expected the history error to disappear after Retry succeeds."
        )

        let viewAll = element(
            SurroundUITestContract.AccessibilityID.homeHistoryViewAll,
            in: app,
            matching: .button
        )
        scrollIntoTappableArea(viewAll, in: app)
        tap(
            SurroundUITestContract.AccessibilityID.homeHistoryViewAll,
            in: app,
            matching: .button
        )
        element(SurroundUITestContract.AccessibilityID.screenGameHistory, in: app)
        element(
            SurroundUITestContract.AccessibilityID.gameHistoryEmpty,
            in: app
        )
    }

    func testZenModeRoundTrip() {
        let app = launchApp()

        tap(
            SurroundUITestContract.AccessibilityID.homeGame(SurroundUITestContract.fixtureGameID),
            in: app
        )
        let board = element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        let livePosition = board.value as? String
        setGameAnalyzing(true, in: app)
        tap(SurroundUITestContract.AccessibilityID.gameAnalyzePrevious,
            in: app, matching: .button)
        let analysisPosition = board.value as? String
        XCTAssertNotEqual(analysisPosition, livePosition)
        activateZenControl(
            SurroundUITestContract.AccessibilityID.gameZenEnter,
            in: app
        )
        element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        XCTAssertEqual(board.value as? String, livePosition,
                       "Zen should show the live game while retaining analysis work.")
        activateZenControl(
            SurroundUITestContract.AccessibilityID.gameZenExit,
            in: app
        )
        element(SurroundUITestContract.AccessibilityID.gameZenEnter, in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar).firstMatch.exists)
        XCTAssertEqual(board.value as? String, analysisPosition,
                       "Leaving Zen should restore the selected analysis position.")
    }

    func testPendingMoveAndPassConfirmationSurviveRotation() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("This journey verifies native iPhone and iPad rotation.")
        #else
        let app = launchApp(orientation: .portrait)
        let id = SurroundUITestContract.AccessibilityID.self
        tap(id.homeGame(SurroundUITestContract.fixtureGameID), in: app)
        let board = element(id.gameBoard, in: app)
        let livePosition = try XCTUnwrap(board.value as? String)
        let pass = app.buttons["Pass"].firstMatch
        XCTAssertTrue(pass.waitForExistence(timeout: 10))
        tap(pass, description: "Open the pass confirmation", in: app)
        let confirmation = app.alerts["Are you sure you want to pass?"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        XCTAssertTrue(confirmation.buttons["Pass"].isEnabled)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(pollUntil(timeout: 10) { app.frame.width > app.frame.height },
                      "The app must actually adopt landscape before validating retention.")
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10),
                      "Rotation must preserve the pending confirmation.")
        tap(confirmation.buttons["Dismiss"], description: "Keep playing without passing", in: app)
        XCTAssertEqual(board.value as? String, livePosition)
        XCTAssertTrue(pass.isEnabled)

        // A19 is empty in the bundled ongoing fixture. The board exposes its
        // full bounds, including half-cell margins around the 19 intersections.
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.025)).tap()
        let submit = app.buttons["Submit move"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 10),
                      "A legal tentative move must reveal the Submit move action.")
        XCTAssertTrue(submit.isEnabled)
        XCTAssertEqual(board.value as? String, livePosition,
                       "The authoritative position must not change before submission.")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(pollUntil(timeout: 10) {
            app.frame.height > app.frame.width && submit.isHittable
        })
        XCTAssertTrue(submit.isEnabled,
                      "The tentative move must survive rotation without being sent.")
        XCTAssertEqual(board.value as? String, livePosition)
        keepScreenshot("Tentative move retained after rotation", in: app)
        #endif
    }

    func testKeyboardPreflightSupportsComposerInput() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(
            "The composer-input preflight requires an iOS device."
        )
        #else
        let app = launchApp(
            additionalLaunchArguments: [
                SurroundUITestContract.compatibilityScreenshotLaunchArgument,
                SurroundUITestContract.compatibilitySceneLaunchArgument,
                SurroundUITestContract.CompatibilityScene.activeGameBoard
                    .rawValue,
                SurroundUITestContract.compactGameLayoutLaunchArgument,
            ],
            orientation: .portrait
        )

        selectSegment(
            at: 2,
            in: SurroundUITestContract.AccessibilityID.gameDisplayModePicker,
            app: app
        )
        let input = element(
            SurroundUITestContract.AccessibilityID.gameChatInput,
            in: app,
            matching: .textField
        )
        // Opening chat never focuses the composer; the preflight focuses it
        // the way a person does, by tapping the field.
        XCTAssertFalse(
            waitForChatInputFocus(in: app, timeout: 2),
            "Opening chat must not focus the composer."
        )

        enterText(
            "Keyboard preflight",
            into: input,
            in: app,
            focusMode: .acquireWithRetry
        )

        dismissSoftwareKeyboardIfNeeded(in: app)
        #endif
    }

    func testCompactChatCanHideAndShowMainBoard() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(
            "The compact Chat layout requires an iOS device."
        )
        #else
        let app = launchApp(
            additionalLaunchArguments: [
                SurroundUITestContract.compatibilityScreenshotLaunchArgument,
                SurroundUITestContract.compatibilitySceneLaunchArgument,
                SurroundUITestContract.CompatibilityScene.activeGameBoard
                    .rawValue,
                SurroundUITestContract.compactGameLayoutLaunchArgument,
                SurroundUITestContract
                    .attachedSoftwareKeyboardVisibleLaunchArgument,
            ],
            orientation: .portrait
        )

        element(SurroundUITestContract.AccessibilityID.gameZenEnter, in: app)
        selectSegment(
            at: 2,
            in: SurroundUITestContract.AccessibilityID.gameDisplayModePicker,
            app: app
        )
        dismissCompactChatInputAndWaitForLayout(in: app)
        element(
            SurroundUITestContract.AccessibilityID.gameBoard,
            in: app
        )
        let hideBoard = element(
            SurroundUITestContract.AccessibilityID.gameChatBoardHide,
            in: app,
            matching: .button
        )
        XCTAssertEqual(hideBoard.label, "Hide main board")
        XCTAssertFalse(
            app.descendants(matching: .any)[
                SurroundUITestContract.AccessibilityID.gameZenEnter
            ].exists
        )

        hideBoard.tap()
        XCTAssertTrue(
            pollUntil(timeout: 10) { !gameBoardIsShown(in: app) },
            "Expected Hide main board to remove the compact Chat board."
        )
        element(
            SurroundUITestContract.AccessibilityID.gameActionsMenu,
            in: app,
            matching: .button
        )
        let showBoard = element(
            SurroundUITestContract.AccessibilityID.gameChatBoardShow,
            in: app,
            matching: .button
        )
        XCTAssertEqual(showBoard.label, "Show main board")

        showBoard.tap()
        XCTAssertTrue(pollUntil(timeout: 10) { gameBoardIsShown(in: app) },
                      "Expected Show main board to restore the board.")
        XCTAssertEqual(
            element(
                SurroundUITestContract.AccessibilityID.gameChatBoardHide,
                in: app,
                matching: .button
            ).label,
            "Hide main board"
        )

        selectSegment(
            at: 1,
            in: SurroundUITestContract.AccessibilityID.gameDisplayModePicker,
            app: app
        )
        element(SurroundUITestContract.AccessibilityID.gameZenEnter, in: app)
        XCTAssertFalse(
            app.descendants(matching: .any)[
                SurroundUITestContract.AccessibilityID.gameChatBoardHide
            ].exists
        )
        XCTAssertFalse(
            app.descendants(matching: .any)[
                SurroundUITestContract.AccessibilityID.gameChatBoardShow
            ].exists
        )
        #endif
    }

    func testCompactVariationSharingHidesMainBoardAndShowsComposerPreview()
        throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(
            "The compact Variation sharing layout requires an iOS device."
        )
        #else
        let app = launchApp(
            additionalLaunchArguments: [
                SurroundUITestContract.compatibilityScreenshotLaunchArgument,
                SurroundUITestContract.compatibilitySceneLaunchArgument,
                SurroundUITestContract.CompatibilityScene.gameAnalysis
                    .rawValue,
                SurroundUITestContract.compactGameLayoutLaunchArgument,
            ],
            orientation: .portrait
        )
        element(
            SurroundUITestContract.AccessibilityID.gameBoard,
            in: app
        )

        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar,
            in: app
        )
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeNextBranch,
            in: app,
            matching: .button
        )
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu,
            in: app
        )
        let shareVariation = analyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeShare,
            catalystTitle: "Share variation in chat",
            in: app
        )
        let shareableVariationSelected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: shareVariation
        )
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [shareableVariationSelected],
                timeout: 10
            ),
            .completed,
            "Expected branch navigation to select a shareable variation."
        )
        tapAnalyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeShare,
            catalystTitle: "Share variation in chat",
            in: app
        )

        let sharingTitle = element(
            SurroundUITestContract.AccessibilityID.gameVariationShareStatus,
            in: app
        )
        XCTAssertEqual(sharingTitle.label, "Sharing variation")
        let preview = element(
            SurroundUITestContract.AccessibilityID.gameVariationSharePreview,
            in: app
        )
        XCTAssertEqual(preview.frame.width, 120, accuracy: 4)
        XCTAssertEqual(preview.frame.height, 120, accuracy: 4)
        XCTAssertEqual(
            element(
                SurroundUITestContract.AccessibilityID.gameChatInput,
                in: app,
                matching: .textField
            ).label,
            "Variation name..."
        )
        let cancel = element(
            SurroundUITestContract.AccessibilityID.gameVariationShareCancel,
            in: app,
            matching: .button
        )
        XCTAssertEqual(cancel.label, "Cancel")
        XCTAssertLessThanOrEqual(
            sharingTitle.frame.maxY,
            cancel.frame.minY,
            "Expected the sharing title to appear above Cancel."
        )
        XCTAssertEqual(
            app.buttons.matching(
                identifier: SurroundUITestContract.AccessibilityID
                    .gameVariationShareCancel
            ).count,
            1,
            "Variation sharing should expose only the composer Cancel button."
        )
        dismissSoftwareKeyboardIfNeeded(in: app)

        XCTAssertTrue(
            pollUntil(timeout: 10) { !gameBoardIsShown(in: app) },
            "Expected compact Variation sharing to hide the main board."
        )
        let showBoard = element(
            SurroundUITestContract.AccessibilityID.gameChatBoardShow,
            in: app,
            matching: .button
        )
        XCTAssertEqual(showBoard.label, "Show main board")

        showBoard.tap()
        XCTAssertTrue(pollUntil(timeout: 10) { gameBoardIsShown(in: app) },
                      "Expected Show main board to restore the board.")
        XCTAssertEqual(
            element(
                SurroundUITestContract.AccessibilityID
                    .gameVariationSharePreview,
                in: app
            ).frame.width,
            120,
            accuracy: 4
        )
        let hideBoard = element(
            SurroundUITestContract.AccessibilityID.gameChatBoardHide,
            in: app,
            matching: .button
        )
        XCTAssertEqual(hideBoard.label, "Hide main board")

        hideBoard.tap()
        XCTAssertTrue(
            pollUntil(timeout: 10) { !gameBoardIsShown(in: app) },
            "Expected the toolbar to hide the main board again."
        )
        element(
            SurroundUITestContract.AccessibilityID.gameChatBoardShow,
            in: app,
            matching: .button
        ).tap()
        element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        cancel.tap()

        element(
            SurroundUITestContract.AccessibilityID.gameChatLog,
            in: app
        )
        XCTAssertEqual(
            element(
                SurroundUITestContract.AccessibilityID.gameChatInput,
                in: app
            ).label,
            "Say hi!"
        )
        element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        element(
            SurroundUITestContract.AccessibilityID.gameChatBoardHide,
            in: app,
            matching: .button
        )
        XCTAssertFalse(
            app.descendants(matching: .any)[
                SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar
            ].exists,
            "Expected Cancel to keep the compact detail in Chat."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)[
                SurroundUITestContract.AccessibilityID
                    .gameVariationSharePreview
            ].exists
        )
        XCTAssertFalse(
            app.descendants(matching: .any)[
                SurroundUITestContract.AccessibilityID
                    .gameVariationShareStatus
            ].exists
        )
        XCTAssertFalse(
            app.buttons[
                SurroundUITestContract.AccessibilityID
                    .gameVariationShareCancel
            ].exists
        )

        dismissSoftwareKeyboardIfNeeded(in: app)
        element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        element(
            SurroundUITestContract.AccessibilityID.gameChatBoardHide,
            in: app,
            matching: .button
        )

        selectSegment(
            at: 0,
            in: SurroundUITestContract.AccessibilityID.gameDisplayModePicker,
            app: app
        )
        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar,
            in: app
        )
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeBackToFork,
            in: app,
            matching: .button
        )
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeNext,
            in: app,
            matching: .button
        )
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeNextBranch,
            in: app,
            matching: .button
        )
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu,
            in: app
        )
        XCTAssertTrue(
            analyzeMenuItem(
                SurroundUITestContract.AccessibilityID.gameAnalyzeShare,
                catalystTitle: "Share variation in chat",
                in: app
            ).isEnabled,
            "Expected branch navigation to select a shareable variation."
        )
        tapAnalyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeShare,
            catalystTitle: "Share variation in chat",
            in: app
        )
        let secondPreview = element(
            SurroundUITestContract.AccessibilityID.gameVariationSharePreview,
            in: app
        )
        element(
            SurroundUITestContract.AccessibilityID.gameChatSend,
            in: app,
            matching: .button
        ).tap()
        let secondPreviewGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: secondPreview
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [secondPreviewGone], timeout: 10),
            .completed,
            "Expected Send to dismiss the compact sharing preview."
        )
        XCTAssertTrue(
            pollUntil(timeout: 10) { !gameBoardIsShown(in: app) },
            "Expected Send to preserve the hidden main-board state."
        )
        element(
            SurroundUITestContract.AccessibilityID.gameChatBoardShow,
            in: app,
            matching: .button
        )
        #endif
    }

    func testChatLineSelectionTogglesAndBackgroundDeselects() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameChat.rawValue,
        ])
        let firstLineID = SurroundUITestContract.AccessibilityID.gameChatLine(
            "app-store-chat-1"
        )
        let secondLineID = SurroundUITestContract.AccessibilityID.gameChatLine(
            "app-store-chat-2"
        )

        tapChatItem(firstLineID, in: app, matching: .button)
        assertSelected(firstLineID, in: app)
        tapChatItem(firstLineID, in: app, matching: .button)
        assertNotSelected(firstLineID, in: app)

        tapChatItem(firstLineID, in: app, matching: .button)
        tapChatItem(secondLineID, in: app, matching: .button)
        assertNotSelected(firstLineID, in: app)
        assertSelected(secondLineID, in: app)

        let chatLog = element(
            SurroundUITestContract.AccessibilityID.gameChatLog,
            in: app,
            matching: .scrollView
        )
        let secondLine = revealChatItem(
            secondLineID,
            in: app,
            matching: .button
        )
        let background = chatLog
            .coordinate(withNormalizedOffset: .zero)
            .withOffset(
                CGVector(
                    dx: 4,
                    dy: secondLine.frame.midY - chatLog.frame.minY
                )
            )
        #if targetEnvironment(macCatalyst)
        background.click()
        #else
        background.tap()
        #endif
        assertNotSelected(secondLineID, in: app)

        let moveID = SurroundUITestContract.AccessibilityID.gameChatMove(0)
        tapChatItem(moveID, in: app, matching: .button)
        assertSelected(moveID, in: app)
        tapChatItem(firstLineID, in: app, matching: .button)
        assertNotSelected(moveID, in: app)
        assertSelected(firstLineID, in: app)

        #if targetEnvironment(macCatalyst)
        let usesRegularGameLayout = true
        #else
        let usesRegularGameLayout = UIDevice.current.userInterfaceIdiom == .pad
        #endif
        if usesRegularGameLayout {
            tapChatItem(moveID, in: app, matching: .button)
            assertSelected(moveID, in: app)
            setGameAnalyzing(true, in: app)
            let analyzeControlBar = element(
                SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar,
                in: app
            )
            XCTAssertFalse(app.scrollViews[SurroundUITestContract.AccessibilityID.gameChatLog].exists,
                           "Analyze replaces the selected Chat preview")

            tapChatItem(moveID, in: app, matching: .button)
            assertSelected(moveID, in: app)
            let exitedAnalyze = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: analyzeControlBar
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [exitedAnalyze], timeout: 10),
                .completed,
                "Selecting a chat preview should exit Analyze mode"
            )
        }
    }

    func testStructuredChatFormatsRenderAcrossMoveLessLines() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameChat.rawValue,
            SurroundUITestContract.structuredChatFormatsLaunchArgument,
        ])
        dismissSoftwareKeyboardIfNeeded(in: app)
        #if !targetEnvironment(macCatalyst)
        if UIDevice.current.userInterfaceIdiom == .phone {
            // Give older lazy rows room to appear while inspecting message
            // formats; keyboard and compact-board behavior have separate tests.
            tap(SurroundUITestContract.AccessibilityID.gameChatBoardHide, in: app)
        }
        #endif

        @discardableResult
        func assertChatLine(
            _ fixtureID: String,
            contains expectedText: String? = nil,
            file: StaticString = #filePath,
            line: UInt = #line
        ) -> XCUIElement {
            let accessibilityID = SurroundUITestContract.AccessibilityID
                .gameChatLine(fixtureID)
            let chatLine = revealChatItem(
                accessibilityID,
                in: app,
                file: file,
                line: line
            )
            if let expectedText {
                XCTAssertTrue(
                    chatLine.label.contains(expectedText),
                    "Expected \(accessibilityID) to render "
                        + "\(expectedText), got \(chatLine.label)",
                    file: file,
                    line: line
                )
            }
            return chatLine
        }

        // The fixture opens at the bottom. Walk upward so lazy chat rows are
        // materialized deterministically on both iOS and Mac Catalyst.
        let analysisLine = assertChatLine(
            SurroundUITestContract.structuredChatAnalysisLineID,
            contains: "Variation: "
                + SurroundUITestContract.structuredChatAnalysisText
        )
        XCTAssertTrue(analysisLine.label.contains("CopperKoi"))
        XCTAssertEqual(analysisLine.elementType, .button,
                       "A variation must remain selectable independently of its sender's profile.")
        assertChatLine(
            SurroundUITestContract.structuredChatThirdPersonLineID,
            contains: SurroundUITestContract.structuredChatThirdPersonText
        )
        let hiddenLine = assertChatLine(
            SurroundUITestContract.structuredChatHiddenLineID,
            contains: SurroundUITestContract.structuredChatHiddenText
        )
        XCTAssertTrue(hiddenLine.label.contains("JuniperStone"))
        XCTAssertTrue(hiddenLine.label.contains("Moderator-only"))
        XCTAssertEqual(hiddenLine.elementType, .button)
        XCTAssertTrue(
            String(describing: hiddenLine.value)
                .contains("Visible only to moderators"),
            "Expected the hidden chat row to describe its moderator-only visibility; got \(String(describing: hiddenLine.value))."
        )
        let reviewRowID = SurroundUITestContract.AccessibilityID.gameChatLine(
            SurroundUITestContract.structuredChatReviewLineID
        )
        assertChatLine(SurroundUITestContract.structuredChatReviewLineID)
        let reviewLabel =
            "Review: #\(SurroundUITestContract.structuredChatReviewID)"
        let reviewLink = app.links[reviewRowID].firstMatch
        XCTAssertTrue(
            reviewLink.waitForExistence(timeout: 10),
            "Expected the structured review row to expose its review link."
        )
        XCTAssertTrue(
            reviewLink.label.contains(reviewLabel),
            "Expected the structured review link to render \(reviewLabel), "
                + "got \(reviewLink.label)."
        )
        XCTAssertTrue(reviewLink.label.contains("JuniperStone"),
                      "The review link must announce who shared it as well as the review ID.")
        assertChatLine(
            SurroundUITestContract.structuredChatTranslatedLineID,
            contains: SurroundUITestContract.structuredChatTranslatedText
        )

        let repeatedMoveID = SurroundUITestContract.AccessibilityID
            .gameChatMove(91)
        revealChatItem(
            repeatedMoveID,
            in: app,
            matching: .button
        )
        XCTAssertEqual(
            app.buttons.matching(identifier: repeatedMoveID).count,
            1,
            "Move-less chat lines must not create a duplicate move-91 divider."
        )
    }

    func testVariationSharingDraftSurvivesChatSelection() {
        let draft = beginVariationSharingDraft(named: "Persistent variation")
        let app = draft.app
        let lineID = SurroundUITestContract.AccessibilityID.gameChatLine(
            "app-store-chat-1"
        )
        tapChatItem(lineID, in: app, matching: .button)
        assertSelected(lineID, in: app)
        let plainChatLineBoardValue = draft.mainBoard.value as? String
        XCTAssertNotNil(plainChatLineBoardValue)
        XCTAssertEqual(
            plainChatLineBoardValue,
            "position:101:cq",
            "Expected a plain chat line to render the current-game fallback board."
        )
        assertVariationSharingDraftIsIntact(draft)

        tapChatItem(lineID, in: app, matching: .button)
        assertNotSelected(lineID, in: app)
        XCTAssertEqual(
            draft.mainBoard.value as? String,
            plainChatLineBoardValue,
            "Expected plain-line deselection to preserve the fallback board."
        )
        assertVariationSharingDraftIsIntact(draft)

        let moveID = SurroundUITestContract.AccessibilityID.gameChatMove(0)
        tapChatItem(moveID, in: app, matching: .button)
        assertSelected(moveID, in: app)
        XCTAssertNotEqual(
            draft.mainBoard.value as? String,
            draft.sharedSourceBoardValue,
            "Expected a chat move selection to control the main board independently of the frozen composer preview."
        )
        assertVariationSharingDraftIsIntact(draft)

        tapChatItem(moveID, in: app, matching: .button)
        assertNotSelected(moveID, in: app)
        assertVariationSharingDraftIsIntact(draft)
    }

    func testVariationSharingDraftSurvivesAnalyzeNavigation() {
        let draft = beginVariationSharingDraft(named: "Persistent variation")
        let app = draft.app

        // Sharing opens Chat in place of Analyze. Returning to Analyze hides
        // the composer; the draft must survive navigating there and back.
        setGameAnalyzing(true, in: app)
        XCTAssertFalse(
            app.textFields[SurroundUITestContract.AccessibilityID.gameChatInput].exists,
            "Expected Analyze to replace the sharing composer."
        )
        // tapAnalysisPosition verifies the exact Button's stable selection.
        tapAnalysisPosition(draft.selectedAnalysisPosition, in: app)
        let selectedAnalyzeBoardValue = draft.mainBoard.value as? String
        XCTAssertNotNil(selectedAnalyzeBoardValue)
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzePrevious,
            in: app,
            matching: .button
        )
        assertSelected(draft.parentAnalysisPosition, in: app)
        XCTAssertNotEqual(
            draft.mainBoard.value as? String,
            selectedAnalyzeBoardValue,
            "Expected Analyze navigation to update the main board independently of the frozen composer preview."
        )

        // tapAnalysisPosition verifies the exact Button's stable selection.
        tapAnalysisPosition(draft.selectedAnalysisPosition, in: app)
        openGameChat(in: app)
        assertVariationSharingDraftIsIntact(draft)
    }

    func testVariationSharingDraftSurvivesZenModeRoundTrip() {
        let draft = beginVariationSharingDraft(named: "Persistent variation")
        let app = draft.app

        assertVariationSharingDraftIsIntact(draft)
        activateZenControl(
            SurroundUITestContract.AccessibilityID.gameZenEnter,
            in: app
        )
        element(SurroundUITestContract.AccessibilityID.gameZenExit, in: app)
        activateZenControl(
            SurroundUITestContract.AccessibilityID.gameZenExit,
            in: app
        )
        #if !targetEnvironment(macCatalyst)
        _ = focusSharedVariationInput(in: app)
        let restoredPreview = draft.sharingPreview.frame
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Post-Zen focused variation composer layout"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let screenshot = XCTAttachment(
            screenshot: XCUIScreen.main.screenshot(), quality: .original
        )
        screenshot.name = "Post-Zen focused variation composer layout"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertFalse(
            app.buttons.matching(
                identifier: SurroundUITestContract.AccessibilityID.gameZenExit
            ).firstMatch.exists,
            "Expected the normal composer layout to replace Zen mode."
        )
        XCTAssertEqual(draft.sharingTitle.label, "Sharing variation")
        XCTAssertEqual(restoredPreview.width, 120, accuracy: 4)
        XCTAssertEqual(restoredPreview.height, 120, accuracy: 4)
        #else
        element(
            SurroundUITestContract.AccessibilityID.gameZenEnter,
            in: app,
            matching: .button
        )
        #endif
        element(
            SurroundUITestContract.AccessibilityID.gameVariationSharePreview,
            in: app
        )
        assertVariationSharingDraftIsIntact(draft)
    }

    func testSharingAnotherVariationReplacesDraft() {
        let draft = beginVariationSharingDraft(named: "Persistent variation")
        let app = draft.app

        // Sharing opened Chat in place of Analyze; return to pick another branch.
        setGameAnalyzing(true, in: app)
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzePrevious,
            in: app,
            matching: .button
        )
        assertSelected(draft.parentAnalysisPosition, in: app)
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu,
            in: app
        )
        tapAnalyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeShare,
            catalystTitle: "Share variation in chat",
            in: app
        )
        let replacementNameInput = focusSharedVariationInput(in: app)

        let replacementPreview = element(
            SurroundUITestContract.AccessibilityID.gameVariationSharePreview,
            in: app
        )
        XCTAssertNotEqual(
            replacementPreview.value as? String,
            draft.frozenPreviewValue,
            "Sharing another branch should replace the frozen composer preview."
        )
        enterText(
            "Replacement variation",
            into: replacementNameInput,
            in: app,
            focusMode: .requireExistingFocus
        )
    }

    func testChatTextUsesSystemSelectionMenu() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(
            "Touch-and-hold text selection requires an iOS device."
        )
        #else
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameChat.rawValue,
        ])
        let firstLineID = SurroundUITestContract.AccessibilityID.gameChatLine(
            "app-store-chat-1"
        )
        let selectionPoint = CGVector(dx: 0.5, dy: 0.75)
        let firstLine = revealChatItem(
            firstLineID,
            in: app,
            matching: .button,
            interactionPoint: selectionPoint
        )

        firstLine
            .coordinate(withNormalizedOffset: selectionPoint)
            .press(forDuration: 1)

        let copyCommand = app
            .descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier == %@ OR label == %@",
                    "Copy",
                    "Copy"
                )
            )
            .firstMatch
        XCTAssertTrue(
            copyCommand.waitForExistence(timeout: 10),
            "Expected the system text-selection menu to include Copy"
        )
        assertNotSelected(firstLineID, in: app)
        #endif
    }

    func testHomeBoardsStayAlignedWithConditionalMoveButtons() throws {
        try XCTSkipIf(
            UIDevice.current.userInterfaceIdiom == .phone,
            "Full Home game cards require the regular-width iPad or Mac layout."
        )

        var launchArguments = [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.home.rawValue,
            SurroundUITestContract.homeBoardAlignmentLaunchArgument,
        ]
        #if targetEnvironment(macCatalyst)
        launchArguments += [
            SurroundUITestContract.catalystWindowSizeLaunchArgument,
            "1440x760",
        ]
        let idiom = "catalyst"
        #else
        let idiom = "ipad"
        #endif
        let app = launchApp(
            additionalLaunchArguments: launchArguments,
            orientation: .landscapeRight
        )

        let topPlanGameID = SurroundUITestContract.screenshotPrimaryGameID
        let bottomPlanGameID =
            SurroundUITestContract.homeHistoryRetryFixtureGameID
        let noPlanGameID =
            SurroundUITestContract.conditionalMovesFixtureGameID
        let topBoard = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID.homeGame(topPlanGameID),
            in: app,
            matching: .button
        )
        scrollIntoTappableArea(topBoard, in: app)
        let bottomBoard = element(
            SurroundUITestContract.AccessibilityID.homeGame(bottomPlanGameID),
            in: app,
            matching: .button
        )
        let noPlanBoard = element(
            SurroundUITestContract.AccessibilityID.homeGame(noPlanGameID),
            in: app,
            matching: .button
        )
        let topPlanButton = element(
            SurroundUITestContract.AccessibilityID
                .homeConditionalButton(topPlanGameID),
            in: app,
            matching: .button
        )
        let bottomPlanButton = element(
            SurroundUITestContract.AccessibilityID
                .homeConditionalButton(bottomPlanGameID),
            in: app,
            matching: .button
        )

        let topBoardFrame = topBoard.frame
        let bottomBoardFrame = bottomBoard.frame
        let noPlanBoardFrame = noPlanBoard.frame
        XCTAssertLessThan(
            topBoardFrame.maxX,
            bottomBoardFrame.minX,
            "The two planned games must occupy neighboring grid columns."
        )
        XCTAssertGreaterThan(
            topBoardFrame.width,
            250,
            "The alignment regression must exercise full-size game cards."
        )
        XCTAssertEqual(topBoardFrame.minY, bottomBoardFrame.minY, accuracy: 1)
        XCTAssertEqual(topBoardFrame.maxY, bottomBoardFrame.maxY, accuracy: 1)
        XCTAssertEqual(
            topBoardFrame.width,
            bottomBoardFrame.width,
            accuracy: 1
        )
        XCTAssertEqual(
            topBoardFrame.height,
            bottomBoardFrame.height,
            accuracy: 1
        )
        XCTAssertEqual(
            topBoardFrame.width,
            noPlanBoardFrame.width,
            accuracy: 1
        )
        XCTAssertEqual(
            topBoardFrame.height,
            noPlanBoardFrame.height,
            accuracy: 1
        )
        // Wide layouts have a third column; narrower iPads wrap the third game.
        if noPlanBoardFrame.minX > bottomBoardFrame.maxX {
            XCTAssertEqual(
                topBoardFrame.minY,
                noPlanBoardFrame.minY,
                accuracy: 1
            )
            XCTAssertEqual(
                topBoardFrame.maxY,
                noPlanBoardFrame.maxY,
                accuracy: 1
            )
        } else {
            XCTAssertEqual(
                topBoardFrame.minX,
                noPlanBoardFrame.minX,
                accuracy: 1,
                "The no-plan game must wrap to the first grid column."
            )
            XCTAssertGreaterThan(
                noPlanBoardFrame.minY,
                topBoardFrame.maxY,
                "The no-plan game must wrap below the planned games."
            )
        }
        XCTAssertLessThan(
            topPlanButton.frame.midY,
            topBoardFrame.minY,
            "The Black user's conditional-plan button must be above its board."
        )
        XCTAssertGreaterThan(
            bottomPlanButton.frame.midY,
            bottomBoardFrame.maxY,
            "The White user's conditional-plan button must be below its board."
        )
        keepScreenshot("home-board-alignment-\(idiom)", in: app)

        XCTAssertFalse(
            app.descendants(matching: .button)
                .matching(
                    identifier: SurroundUITestContract.AccessibilityID
                        .homeConditionalButton(noPlanGameID)
                )
                .firstMatch.exists,
            "The third fixture must exercise a game without a saved plan."
        )
    }

    func testConditionalVariationsOpenAndJumpToAnalyze() {
        #if targetEnvironment(macCatalyst)
        let orientation = UIDeviceOrientation.landscapeRight
        let idiom = "catalyst"
        let expectedVariationBoardSize: CGFloat = 200
        #else
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        let orientation: UIDeviceOrientation = isPhone
            ? .portrait : .landscapeRight
        let idiom = isPhone ? "iphone" : "ipad"
        let expectedVariationBoardSize: CGFloat = isPhone ? 160 : 200
        #endif
        let gameID = SurroundUITestContract.conditionalMovesFixtureGameID
        let app = launchApp(
            additionalLaunchArguments: [
                SurroundUITestContract.compatibilityScreenshotLaunchArgument,
                SurroundUITestContract.compatibilitySceneLaunchArgument,
                SurroundUITestContract.CompatibilityScene.home.rawValue,
            ],
            orientation: orientation
        )

        let homeButton = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID
                .homeConditionalButton(gameID),
            in: app,
            matching: .button
        )
        XCTAssertEqual(homeButton.label, "Conditional moves")
        scrollIntoTappableArea(homeButton, in: app)
        let homeDismissalPoint = popoverDismissalPoint(in: app, navigationTitle: "Active games")
        tap(homeButton, description: "Home Conditional button", in: app)
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(
                    identifier: SurroundUITestContract.AccessibilityID
                        .gameDetail(gameID)
                )
                .firstMatch.exists,
            "Opening conditional variations must not open Game Detail."
        )
        let homePopover = element(
            SurroundUITestContract.AccessibilityID
                .homeConditionalPopover(gameID),
            in: app
        )
        let homePopoverTitle = element(
            SurroundUITestContract.AccessibilityID
                .homeConditionalPopoverTitle(gameID),
            in: app
        )
        XCTAssertEqual(homePopoverTitle.label, "Conditional moves plan")
        for branchID in SurroundUITestContract
            .conditionalMovesFixtureBranchIDs {
            let variation = element(
                SurroundUITestContract.AccessibilityID
                    .homeConditionalVariation(
                        gameID,
                        branchID: branchID
                    ),
                in: app
            )
            XCTAssertEqual(
                variation.frame.width,
                expectedVariationBoardSize,
                accuracy: 4
            )
            XCTAssertEqual(
                variation.frame.height,
                expectedVariationBoardSize,
                accuracy: 4
            )
        }
        keepScreenshot("conditional-popover-home-\(idiom)", in: app)

        dismissPopover(
            in: app,
            at: homeDismissalPoint,
            containing: homePopover,
            restoring: [SurroundUITestContract.AccessibilityID.screenHome]
        )

        let gameButton = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID.homeGame(gameID),
            in: app,
            matching: .button
        )
        scrollIntoTappableArea(gameButton, in: app)
        tap(gameButton, description: "conditional fixture board", in: app)
        element(
            SurroundUITestContract.AccessibilityID.gameDetail(gameID),
            in: app
        )

        let detailButton = element(
            SurroundUITestContract.AccessibilityID.gameConditionalButton,
            in: app,
            matching: .button
        )
        XCTAssertEqual(detailButton.label, "Conditional moves")
        tap(
            detailButton,
            description: "Game Detail Conditional moves button",
            in: app
        )
        element(
            SurroundUITestContract.AccessibilityID.gameConditionalPopover,
            in: app
        )
        let detailPopoverTitle = element(
            SurroundUITestContract.AccessibilityID
                .gameConditionalPopoverTitle,
            in: app
        )
        XCTAssertEqual(detailPopoverTitle.label, "Conditional moves plan")
        let selectedPath = SurroundUITestContract
            .conditionalMovesFixturePaths[1]
        tap(
            SurroundUITestContract.AccessibilityID.gameConditionalVariation(
                SurroundUITestContract.conditionalMovesFixtureBranchIDs[1]
            ),
            in: app,
            matching: .button
        )

        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar,
            in: app
        )
        let quickAddConditional = app.descendants(matching: .button)
            .matching(
                identifier: SurroundUITestContract.AccessibilityID
                    .gameAnalyzeQuickAddConditional
            )
            .firstMatch
        let quickRemoveConditional = app.descendants(matching: .button)
            .matching(
                identifier: SurroundUITestContract.AccessibilityID
                    .gameAnalyzeQuickRemoveConditional
            )
            .firstMatch
        XCTAssertFalse(
            quickAddConditional.exists,
            "The quick Add action should stay hidden until Add has been used."
        )
        XCTAssertFalse(
            quickRemoveConditional.exists,
            "The quick Remove action should stay hidden until Add has been used."
        )
        let selectedNodeIdentifier = SurroundUITestContract.AccessibilityID
            .gameAnalysisPosition(
                baseMoveNumber: SurroundUITestContract
                    .conditionalMovesFixtureRootMoveNumber,
                movePath: selectedPath
            )
        assertSelected(selectedNodeIdentifier, in: app)
        let selectedNode = element(selectedNodeIdentifier, in: app)
        XCTAssertTrue(
            String(describing: selectedNode.value).contains("Conditional"),
            "Expected the selected Analyze node to expose its conditional state."
        )
        let sharedPrefixNodeIdentifier = SurroundUITestContract.AccessibilityID
            .gameAnalysisPosition(
                baseMoveNumber: SurroundUITestContract
                    .conditionalMovesFixtureRootMoveNumber,
                movePath: Array(selectedPath.prefix(2))
            )
        let sharedPrefixNode = element(sharedPrefixNodeIdentifier, in: app)
        XCTAssertFalse(
            String(describing: sharedPrefixNode.value).contains("Conditional"),
            "Expected an intermediate path node not to be marked as a conditional variation."
        )

        let conflictingNodeIdentifier = SurroundUITestContract.AccessibilityID
            .gameAnalysisPosition(
                baseMoveNumber: SurroundUITestContract
                    .conditionalMovesFixtureRootMoveNumber,
                movePath: SurroundUITestContract
                    .conditionalMovesFixtureConflictingPath
            )
        tapAnalysisPosition(conflictingNodeIdentifier, in: app)
        assertSelected(conflictingNodeIdentifier, in: app)
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu,
            in: app
        )
        let replacingAddItem = analyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeAddConditional,
            catalystTitle: "Add to conditional moves",
            in: app
        )
        XCTAssertTrue(
            replacingAddItem.isEnabled,
            "Expected the conflicting analysis path to be addable."
        )
        assertAnalyzeMenuSubtitle(
            "Replaces conflicting variations",
            for: replacingAddItem,
            in: app
        )
        dismissAnalyzeActionsMenu(
            containing: replacingAddItem,
            in: app,
            restoring: [
                SurroundUITestContract.AccessibilityID.gameDetail(gameID),
                SurroundUITestContract.AccessibilityID.gameAnalyzeTreeScroll,
            ]
        )
        tapAnalysisPosition(selectedNodeIdentifier, in: app)
        assertSelected(selectedNodeIdentifier, in: app)

        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu,
            in: app
        )
        XCTAssertFalse(
            analyzeMenuItem(
                SurroundUITestContract.AccessibilityID.gameAnalyzeAddConditional,
                catalystTitle: "Add to conditional moves",
                in: app
            ).isEnabled
        )
        XCTAssertTrue(
            analyzeMenuItem(
                SurroundUITestContract.AccessibilityID.gameAnalyzeRemoveConditional,
                catalystTitle: "Remove from conditional moves",
                in: app
            ).isEnabled
        )
        tapAnalyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeRemoveConditional,
            catalystTitle: "Remove from conditional moves",
            in: app
        )
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu,
            in: app
        )
        let addAfterRemoval = analyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeAddConditional,
            catalystTitle: "Add to conditional moves",
            in: app
        )
        let removedConditionalState = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: addAfterRemoval
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [removedConditionalState], timeout: 10),
            .completed,
            "Expected the server echo to remove the selected conditional variation."
        )
        XCTAssertFalse(
            analyzeMenuItem(
                SurroundUITestContract.AccessibilityID.gameAnalyzeRemoveConditional,
                catalystTitle: "Remove from conditional moves",
                in: app
            ).isEnabled
        )
        dismissAnalyzeActionsMenu(
            containing: addAfterRemoval,
            in: app,
            restoring: [
                SurroundUITestContract.AccessibilityID.gameDetail(gameID),
                SurroundUITestContract.AccessibilityID.gameAnalyzeTreeScroll,
            ]
        )
        XCTAssertFalse(
            quickAddConditional.exists,
            "Using Remove must not unlock conditional-move quick actions."
        )
        XCTAssertFalse(
            quickRemoveConditional.exists,
            "Using Remove must not unlock conditional-move quick actions."
        )
        XCTAssertFalse(
            String(describing: element(selectedNodeIdentifier, in: app).value)
                .contains("Conditional"),
            "Expected the removed variation endpoint to lose its conditional accessibility value."
        )
        assertSelected(selectedNodeIdentifier, in: app)
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu,
            in: app
        )
        tapAnalyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeAddConditional,
            catalystTitle: "Add to conditional moves",
            in: app
        )
        let restoredConditionalState = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                String(describing: selectedNode.value).contains("Conditional")
            },
            object: selectedNode
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [restoredConditionalState], timeout: stateSettleTimeout),
            .completed,
            "Expected the server echo to restore the selected conditional variation."
        )

        let quickRemoveAfterAdd = element(
            SurroundUITestContract.AccessibilityID
                .gameAnalyzeQuickRemoveConditional,
            in: app,
            matching: .button
        )
        XCTAssertEqual(
            quickRemoveAfterAdd.label,
            "Remove from conditional moves"
        )
        // The regular side column is 400pt wide; the bar shortens the
        // shortcut to its icon there so every branch arrow stays visible.
        XCTAssertGreaterThanOrEqual(quickRemoveAfterAdd.frame.width, 44)
        XCTAssertTrue(quickRemoveAfterAdd.isHittable)
        XCTAssertEqual(quickRemoveAfterAdd.frame.height, 44, accuracy: 4)
        XCTAssertFalse(
            quickAddConditional.exists,
            "Only the available conditional-move quick action should be shown."
        )
        let markerTool = element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeMarkerMenu,
            in: app
        )
        XCTAssertGreaterThan(
            quickRemoveAfterAdd.frame.midX,
            markerTool.frame.midX,
            "The conditional-move quick action should follow the marker tool."
        )

        tapAnalysisPosition(conflictingNodeIdentifier, in: app)
        assertSelected(conflictingNodeIdentifier, in: app)
        let replacingQuickAdd = element(
            SurroundUITestContract.AccessibilityID
                .gameAnalyzeQuickAddConditional,
            in: app,
            matching: .button
        )
        XCTAssertEqual(
            replacingQuickAdd.label,
            "Add to conditional moves, Replaces conflicting variations"
        )
        XCTAssertFalse(
            quickRemoveConditional.exists,
            "Quick Add should replace Quick Remove for a conflicting branch."
        )
        tapAnalysisPosition(selectedNodeIdentifier, in: app)
        assertSelected(selectedNodeIdentifier, in: app)

        tap(
            quickRemoveAfterAdd,
            description: "Quick Remove from conditional moves",
            in: app
        )
        let quickAddAfterRemoval = element(
            SurroundUITestContract.AccessibilityID
                .gameAnalyzeQuickAddConditional,
            in: app,
            matching: .button
        )
        XCTAssertEqual(quickAddAfterRemoval.label, "Add to conditional moves")
        // The regular side column is 400pt wide; the bar shortens the
        // shortcut to its icon there so every branch arrow stays visible.
        XCTAssertGreaterThanOrEqual(quickAddAfterRemoval.frame.width, 44)
        XCTAssertTrue(quickAddAfterRemoval.isHittable)
        XCTAssertEqual(quickAddAfterRemoval.frame.height, 44, accuracy: 4)
        XCTAssertFalse(
            quickRemoveConditional.exists,
            "Quick Remove should be replaced when only Add is available."
        )

        tap(
            quickAddAfterRemoval,
            description: "Quick Add to conditional moves",
            in: app
        )
        element(
            SurroundUITestContract.AccessibilityID
                .gameAnalyzeQuickRemoveConditional,
            in: app,
            matching: .button
        )
        keepScreenshot("conditional-analyze-detail-\(idiom)", in: app)

        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu,
            in: app
        )
        tapAnalyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeDeleteBranch,
            catalystTitle: "Delete branch",
            in: app
        )
        let conditionalDeleteWarning =
            "This removes the selected move and every move after it in this branch. "
            + "Conditional-move variations in this branch will also be removed."
        let conditionalDeleteWarningText = app.staticTexts
            .matching(
                NSPredicate(
                    format: "label == %@",
                    conditionalDeleteWarning
                )
            )
            .firstMatch
        XCTAssertTrue(
            conditionalDeleteWarningText.waitForExistence(
                timeout: 10
            ),
            "Expected Delete branch to warn about registered conditional variations."
        )
        tapAnalyzeDeleteConfirmation(in: app)
        let deleted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: selectedNode
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [deleted], timeout: 10),
            .completed,
            "Expected coordinated deletion to remove the selected branch after the server echo."
        )
        assertSelected(
            SurroundUITestContract.AccessibilityID.gameAnalysisPosition(
                baseMoveNumber: SurroundUITestContract
                    .conditionalMovesFixtureRootMoveNumber,
                movePath: Array(selectedPath.dropLast())
            ),
            in: app
        )
    }

    func testAnalyzeControlBarNavigatesAndDeletesBranch() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameAnalysis.rawValue,
        ])

        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar,
            in: app
        )
        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzePreviousBranch,
            in: app,
            matching: .button
        )
        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeNextBranch,
            in: app,
            matching: .button
        )
        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeBackToFork,
            in: app,
            matching: .button
        )

        let selectedIdentifier =
            SurroundUITestContract.AccessibilityID.gameAnalysisPosition(
                baseMoveNumber:
                    SurroundUITestContract.screenshotAnalysisBaseMoveNumber,
                movePath:
                    SurroundUITestContract.screenshotAnalysisSelectedMovePath
            )
        let parentIdentifier =
            SurroundUITestContract.AccessibilityID.gameAnalysisPosition(
                baseMoveNumber:
                    SurroundUITestContract.screenshotAnalysisBaseMoveNumber,
                movePath: Array(
                    SurroundUITestContract.screenshotAnalysisSelectedMovePath
                        .dropLast()
                )
            )
        let nestedForkIdentifier =
            SurroundUITestContract.AccessibilityID.gameAnalysisPosition(
                baseMoveNumber:
                    SurroundUITestContract.screenshotAnalysisBaseMoveNumber,
                movePath: Array(
                    SurroundUITestContract.screenshotAnalysisSelectedMovePath
                        .dropLast(2)
                )
            )

        tapAnalysisPosition(selectedIdentifier, in: app)
        assertSelected(selectedIdentifier, in: app)

        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzePreviousBranch,
            in: app,
            matching: .button
        )
        XCTAssertFalse(
            element(
                SurroundUITestContract.AccessibilityID.gameAnalyzePreviousBranch,
                in: app,
                matching: .button
            ).isEnabled
        )
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeNextBranch,
            in: app,
            matching: .button
        )
        assertSelected(selectedIdentifier, in: app)

        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeBackToFork,
            in: app,
            matching: .button
        )
        assertSelected(nestedForkIdentifier, in: app)
        XCTAssertTrue(
            element(
                SurroundUITestContract.AccessibilityID.gameAnalyzeBackToFork,
                in: app,
                matching: .button
            ).isEnabled
        )
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeBackToFork,
            in: app,
            matching: .button
        )
        XCTAssertFalse(
            element(
                SurroundUITestContract.AccessibilityID.gameAnalyzeBackToFork,
                in: app,
                matching: .button
            ).isEnabled
        )
        tapAnalysisPosition(selectedIdentifier, in: app)
        assertSelected(selectedIdentifier, in: app)

        XCTAssertFalse(
            element(
                SurroundUITestContract.AccessibilityID.gameAnalyzeNext,
                in: app,
                matching: .button
            ).isEnabled
        )

        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzePrevious,
            in: app,
            matching: .button
        )
        assertSelected(parentIdentifier, in: app)
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeNext,
            in: app,
            matching: .button
        )
        assertSelected(selectedIdentifier, in: app)

        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu,
            in: app
        )
        XCTAssertTrue(
            analyzeMenuItem(
                SurroundUITestContract.AccessibilityID.gameAnalyzeShare,
                catalystTitle: "Share variation in chat",
                in: app,
            ).isEnabled
        )
        XCTAssertFalse(
            analyzeMenuItem(
                SurroundUITestContract.AccessibilityID.gameAnalyzeAddConditional,
                catalystTitle: "Add to conditional moves",
                in: app,
            ).isEnabled
        )
        XCTAssertFalse(
            analyzeMenuItem(
                SurroundUITestContract.AccessibilityID.gameAnalyzeRemoveConditional,
                catalystTitle: "Remove from conditional moves",
                in: app,
            ).isEnabled
        )
        tapAnalyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeDeleteBranch,
            catalystTitle: "Delete branch",
            in: app,
        )
        tapAnalyzeDeleteConfirmation(in: app)

        let deletedPosition = app.descendants(matching: .any)[selectedIdentifier]
        let deleted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: deletedPosition
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [deleted], timeout: 10),
            .completed,
            "Expected the deleted analysis position to disappear"
        )
        assertSelected(parentIdentifier, in: app)
    }

    func testAnalyzeShareComposerAutomaticallyFocusesAndAcceptsName() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameAnalysis.rawValue,
        ])
        let selectedIdentifier =
            SurroundUITestContract.AccessibilityID.gameAnalysisPosition(
                baseMoveNumber:
                    SurroundUITestContract.screenshotAnalysisBaseMoveNumber,
                movePath:
                    SurroundUITestContract.screenshotAnalysisSelectedMovePath
            )

        tapAnalysisPosition(selectedIdentifier, in: app)
        assertSelected(selectedIdentifier, in: app)
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu,
            in: app
        )
        tapAnalyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeShare,
            catalystTitle: "Share variation in chat",
            in: app
        )

        let sharingTitle = element(
            SurroundUITestContract.AccessibilityID.gameVariationShareStatus,
            in: app
        )
        XCTAssertEqual(sharingTitle.label, "Sharing variation")
        let sharingPreview = element(
            SurroundUITestContract.AccessibilityID.gameVariationSharePreview,
            in: app
        )
        XCTAssertEqual(sharingPreview.frame.width, 120, accuracy: 4)
        XCTAssertEqual(sharingPreview.frame.height, 120, accuracy: 4)
        XCTAssertNotNil(sharingPreview.value as? String)
        let variationNameInput = focusSharedVariationInput(in: app)
        XCTAssertEqual(variationNameInput.label, "Variation name...")
        enterText(
            "Focused variation",
            into: variationNameInput,
            in: app,
            focusMode: .requireExistingFocus
        )

        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar).firstMatch.exists,
            "Sharing opens Chat as the only panel")
        dismissSoftwareKeyboardIfNeeded(in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar).firstMatch.exists,
            "Dismissing the keyboard keeps Chat selected")
        XCTAssertEqual(variationNameInput.value as? String, "Focused variation")
        setGameAnalyzing(true, in: app)
        assertSelected(selectedIdentifier, in: app)
    }

    func testShareVariationUsesSelectedChannelAndStaysInChatAfterSending() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameAnalysis.rawValue,
        ])
        let selectedIdentifier =
            SurroundUITestContract.AccessibilityID.gameAnalysisPosition(
                baseMoveNumber:
                    SurroundUITestContract.screenshotAnalysisBaseMoveNumber,
                movePath:
                    SurroundUITestContract.screenshotAnalysisSelectedMovePath
            )

        tapAnalysisPosition(selectedIdentifier, in: app)
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu,
            in: app
        )
        tapAnalyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeShare,
            catalystTitle: "Share variation in chat",
            in: app
        )

        let sharingTitle = element(
            SurroundUITestContract.AccessibilityID.gameVariationShareStatus,
            in: app
        )
        XCTAssertEqual(sharingTitle.label, "Sharing variation")
        let sharingPreview = element(
            SurroundUITestContract.AccessibilityID.gameVariationSharePreview,
            in: app
        )
        XCTAssertEqual(sharingPreview.frame.width, 120, accuracy: 4)
        XCTAssertEqual(sharingPreview.frame.height, 120, accuracy: 4)
        let sharingCancel = element(
            SurroundUITestContract.AccessibilityID.gameVariationShareCancel,
            in: app,
            matching: .button
        )
        _ = focusSharedVariationInput(in: app)
        dismissSoftwareKeyboardIfNeeded(in: app)
        tapChatChannel(
            SurroundUITestContract.AccessibilityID.gameChatChannelMalkovich,
            catalystTitle: "Malkovich",
            in: app
        )
        XCTAssertEqual(sharingTitle.label, "Recording variation")
        tapChatChannel(
            SurroundUITestContract.AccessibilityID.gameChatChannelPersonal,
            catalystTitle: "Personal",
            in: app
        )
        XCTAssertEqual(sharingTitle.label, "Recording variation")
        tapChatChannel(
            SurroundUITestContract.AccessibilityID.gameChatChannelMalkovich,
            catalystTitle: "Malkovich",
            in: app
        )
        XCTAssertEqual(sharingTitle.label, "Recording variation")

        let send = element(
            SurroundUITestContract.AccessibilityID.gameChatSend,
            in: app,
            matching: .button
        )
        XCTAssertTrue(send.isEnabled, "Blank variation names should auto-number.")
        send.tap()

        let sharingTitleGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: sharingTitle
        )
        let sharingPreviewGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: sharingPreview
        )
        let sharingCancelGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: sharingCancel
        )
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [
                    sharingTitleGone,
                    sharingPreviewGone,
                    sharingCancelGone,
                ],
                timeout: 10
            ),
            .completed,
            "Expected local dispatch to dismiss the Variation sharing composer."
        )
        XCTAssertEqual(
            element(
                SurroundUITestContract.AccessibilityID.gameChatInput,
                in: app
            ).label,
            "Hidden from opponent during the game"
        )
        XCTAssertTrue(app.scrollViews[SurroundUITestContract.AccessibilityID.gameChatLog].exists,
                      "Sending the variation must keep Chat open.")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar).firstMatch.exists)
        dismissSoftwareKeyboardIfNeeded(in: app)
        // Every device shows one requested panel. Returning to Analyze
        // must reveal the same branch that was just shared.
        setGameAnalyzing(true, in: app)
        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar,
            in: app
        )
        assertSelected(selectedIdentifier, in: app)
    }

    func testPlaybackControlBarShowsNavigationAndBackToLiveWithoutEditing() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameAnalysis.rawValue,
            SurroundUITestContract.analysisDisabledLaunchArgument,
        ])

        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar,
            in: app
        )
        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzePrevious,
            in: app,
            matching: .button
        )
        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeNext,
            in: app,
            matching: .button
        )

        for hiddenIdentifier in [
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu,
            SurroundUITestContract.AccessibilityID.gameAnalyzeMarkerMenu,
            SurroundUITestContract.AccessibilityID.gameAnalyzePreviousBranch,
            SurroundUITestContract.AccessibilityID.gameAnalyzeNextBranch,
            SurroundUITestContract.AccessibilityID.gameAnalyzeBackToFork,
        ] {
            XCTAssertFalse(
                app.descendants(matching: .any)[hiddenIdentifier].exists,
                "Expected Playback mode to hide \(hiddenIdentifier)."
            )
        }
        let board = element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        let selected = board.value as? String
        let live = element("game.analyze.live", in: app, matching: .button)
        XCTAssertTrue(live.isEnabled)
        tap(live, description: "Return playback to the live position", in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { !live.isEnabled })
        XCTAssertNotEqual(board.value as? String, selected)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar).firstMatch.exists,
            "Back to live must retain the playback session.")
    }

    func testFinishedAnalysisDisabledGameShowsFullAnalyzeControlBar() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.finishedGamePlayback.rawValue,
            SurroundUITestContract.analysisDisabledLaunchArgument,
        ])

        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar,
            in: app
        )
        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu,
            in: app
        )
        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeMarkerMenu,
            in: app
        )
        for visibleIdentifier in [
            SurroundUITestContract.AccessibilityID.gameAnalyzePreviousBranch,
            SurroundUITestContract.AccessibilityID.gameAnalyzeNextBranch,
            SurroundUITestContract.AccessibilityID.gameAnalyzeBackToFork,
            SurroundUITestContract.AccessibilityID.gameAnalyzePrevious,
            SurroundUITestContract.AccessibilityID.gameAnalyzeNext,
        ] {
            element(
                visibleIdentifier,
                in: app,
                matching: .button
            )
        }
    }

    func testAnalyzeBoardQuickTaps() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameAnalysis.rawValue,
        ])
        let board = element(
            SurroundUITestContract.AccessibilityID.gameBoard,
            in: app
        )
        let baseline = "position:46:fl"
        let placed = "variation:46:jj"
        XCTAssertTrue(waitForValue(baseline, in: board, timeout: 10))

        // The accessibility text is centered on the empty K10 intersection;
        // its intrinsic frame does not describe the board's outer bounds.
        let center = board.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        center.tap()
        XCTAssertTrue(
            waitForValue(placed, in: board, timeout: 5),
            "A quick tap must place a stone without requiring a hold."
        )

        center.tap()
        XCTAssertEqual(
            board.value as? String,
            placed,
            "Tapping the occupied intersection must not create another move."
        )

        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzePrevious,
            in: app,
            matching: .button
        )
        XCTAssertTrue(waitForValue(baseline, in: board, timeout: 5))
        board.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).press(forDuration: 0.01)
        XCTAssertTrue(
            waitForValue(placed, in: board, timeout: 5),
            "A brief press must select the same point again after Previous."
        )
    }

    func testAnalyzeBoardDragOutsideCancels() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameAnalysis.rawValue,
        ])
        let board = element(
            SurroundUITestContract.AccessibilityID.gameBoard,
            in: app
        )
        let controlBar = element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar,
            in: app
        )
        let baseline = "position:46:fl"
        XCTAssertTrue(waitForValue(baseline, in: board, timeout: 10))

        let center = board.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        let appFrame = app.frame
        let controlBarFrame = controlBar.frame
        let outsidePoint = CGPoint(
            x: controlBarFrame.midX,
            y: controlBarFrame.midY
        )
        XCTAssertTrue(controlBarFrame.width > 0 && controlBarFrame.height > 0)
        XCTAssertTrue(appFrame.contains(outsidePoint))
        // The Analyze toolbar is outside the board in either layout. Use its
        // center through app coordinates rather than the board text's width.
        let outside = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(
                dx: outsidePoint.x - appFrame.minX,
                dy: outsidePoint.y - appFrame.minY
            )
        )
        center.press(forDuration: 0.1, thenDragTo: outside)
        XCTAssertEqual(
            board.value as? String,
            baseline,
            "Releasing outside the board must cancel the hovered move."
        )

        board.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()
        XCTAssertTrue(
            waitForValue("variation:46:jj", in: board, timeout: 5),
            "A cancelled drag must leave the board ready for a quick tap."
        )
    }

    func testThemedBoardDepthKeepsMovesAligned() {
        let appearances = [
            (theme: "nebulaPearl", appearance: "dark"),
            (theme: "surroundStudio", appearance: "light"),
            (theme: "surroundStudio", appearance: "dark"),
        ]
        #if targetEnvironment(macCatalyst)
        let orientations: [(name: String, value: UIDeviceOrientation)] = [("window", .unknown)]
        #else
        let orientations: [(name: String, value: UIDeviceOrientation)] = [
            ("portrait", .portrait), ("landscape", .landscapeLeft),
        ]
        defer { XCUIDevice.shared.orientation = .landscapeLeft }
        #endif

        for appearance in appearances {
            let app = launchApp(additionalLaunchArguments: [
                SurroundUITestContract.compatibilityScreenshotLaunchArgument,
                SurroundUITestContract.compatibilitySceneLaunchArgument,
                SurroundUITestContract.CompatibilityScene.gameAnalysis.rawValue,
                SurroundUITestContract.themeLaunchArgument, appearance.theme,
                SurroundUITestContract.appearanceLaunchArgument, appearance.appearance,
            ], orientation: orientations[0].value)
            let board = element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
            let baseline = "position:46:fl"

            for orientation in orientations {
                let name = "\(appearance.theme)-\(appearance.appearance)-\(orientation.name)"
                XCTContext.runActivity(named: name) { _ in
                    #if !targetEnvironment(macCatalyst)
                    XCUIDevice.shared.orientation = orientation.value
                    XCTAssertTrue(pollUntil(timeout: 10) {
                        orientation.value == .portrait
                            ? app.frame.height > app.frame.width
                            : app.frame.width > app.frame.height
                    }, "The window must adopt \(orientation.name) before checking board taps.")
                    #endif
                    XCTAssertTrue(waitForValue(baseline, in: board, timeout: 10))
                    var previousFrame: CGRect?
                    var stableFrames = 0
                    XCTAssertTrue(pollUntil(timeout: 10) {
                        let frame = board.frame
                        guard frame.width > 1 && frame.height > 1 else { return false }
                        stableFrames = frame == previousFrame ? stableFrames + 1 : 1
                        previousFrame = frame
                        return stableFrames >= 3
                    }, "The board must settle before checking its inset playing face.")

                    // A19, K10 and T1 are empty at move 46 in copperKoiOpening.
                    // Probe inside the first/last cells of the inset face.
                    // The outer slot also contains the noninteractive slab
                    // and shadow, so its extreme corners are not grid points.
                    for point in [
                        (name: "A19", offset: CGFloat(0.05), move: "aa"),
                        (name: "K10", offset: CGFloat(0.5), move: "jj"),
                        (name: "T1", offset: CGFloat(0.95), move: "ss"),
                    ] {
                        board.coordinate(withNormalizedOffset: CGVector(dx: point.offset, dy: point.offset)).tap()
                        XCTAssertTrue(waitForValue("variation:46:\(point.move)", in: board, timeout: 5),
                                      "\(name): tapping \(point.name) must select that intersection.")
                        tap(SurroundUITestContract.AccessibilityID.gameAnalyzePrevious, in: app, matching: .button)
                        XCTAssertTrue(waitForValue(baseline, in: board, timeout: 5))
                    }

                    let controlBar = element(SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar, in: app)
                    let appFrame = app.frame
                    let controlBarFrame = controlBar.frame
                    let outsidePoint = CGPoint(x: controlBarFrame.midX, y: controlBarFrame.midY)
                    XCTAssertTrue(controlBarFrame.width > 0 && controlBarFrame.height > 0)
                    XCTAssertTrue(appFrame.contains(outsidePoint))
                    XCTAssertFalse(board.frame.contains(outsidePoint))
                    let outside = app.coordinate(withNormalizedOffset: .zero).withOffset(
                        CGVector(dx: outsidePoint.x - appFrame.minX, dy: outsidePoint.y - appFrame.minY))
                    let center = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    center.press(forDuration: 0.1, thenDragTo: outside)
                    XCTAssertEqual(board.value as? String, baseline,
                                   "\(name): releasing outside the inset board must cancel the move.")
                    center.tap()
                    XCTAssertTrue(waitForValue("variation:46:jj", in: board, timeout: 5),
                                  "Cancelling a drag must leave the themed board ready for a quick tap.")
                    keepScreenshot("Board depth aligned — \(name)", in: app)
                    tap(SurroundUITestContract.AccessibilityID.gameAnalyzePrevious, in: app, matching: .button)
                    XCTAssertTrue(waitForValue(baseline, in: board, timeout: 5))
                }
            }
            app.terminate()
        }
    }

    func testAnalyzeBoardMarkerMenuPlacesAndTogglesSequentialLetters() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameAnalysis.rawValue,
        ])
        let markerMenu = element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeMarkerMenu,
            in: app
        )
        markerMenu.tap()
        analyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeMarkerTool(
                "letters"
            ),
            catalystTitle: "Letters",
            in: app
        ).tap()
        XCTAssertEqual(
            markerMenu.value as? String,
            "Letters, Next label: A"
        )

        let board = element(
            SurroundUITestContract.AccessibilityID.gameBoard,
            in: app
        )
        board.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()
        XCTAssertTrue(
            (board.value as? String)?.contains("|marks:A=") == true
        )
        XCTAssertEqual(
            markerMenu.value as? String,
            "Letters, Next label: B"
        )

        board.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()
        XCTAssertFalse(
            (board.value as? String)?.contains("|marks:") == true
        )
    }

    func testAnalyzeTrunkMarkersShareWithoutLeakingToLiveBoard() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.activeGameBoard.rawValue,
        ])
        let board = element(
            SurroundUITestContract.AccessibilityID.gameBoard,
            in: app
        )
        let liveBoardValue = board.value as? String
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeToggle,
            in: app
        )
        let markerMenu = element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeMarkerMenu,
            in: app
        )
        markerMenu.tap()
        analyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeMarkerTool(
                "letters"
            ),
            catalystTitle: "Letters",
            in: app
        ).tap()
        board.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()
        XCTAssertTrue(
            (board.value as? String)?.contains("|marks:A=") == true
        )

        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeToggle,
            in: app
        )
        XCTAssertEqual(board.value as? String, liveBoardValue)
        XCTAssertFalse(
            (board.value as? String)?.contains("|marks:") == true,
            "Expected Analyze markers to stay off the live game board."
        )
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeToggle,
            in: app
        )
        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar,
            in: app
        )
        XCTAssertTrue(
            (board.value as? String)?.contains("|marks:A=") == true,
            "Expected the Analyze session to retain markers for sharing."
        )

        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu,
            in: app
        )
        let share = analyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeShare,
            catalystTitle: "Share variation in chat",
            in: app
        )
        XCTAssertTrue(
            share.isEnabled,
            "Expected marks on a main-branch position to be shareable."
        )
        share.tap()
        let sharingTitle = element(
            SurroundUITestContract.AccessibilityID.gameVariationShareStatus,
            in: app
        )
        _ = focusSharedVariationInput(in: app)
        let preview = element(
            SurroundUITestContract.AccessibilityID.gameVariationSharePreview,
            in: app
        )
        let sharingCancel = element(
            SurroundUITestContract.AccessibilityID.gameVariationShareCancel,
            in: app,
            matching: .button
        )
        XCTAssertTrue(
            (preview.value as? String)?.contains(":|marks:A=") == true,
            "Expected a zero-move variation preview containing the marker."
        )
        dismissSoftwareKeyboardIfNeeded(in: app)
        tap(
            SurroundUITestContract.AccessibilityID.gameVariationShareCancel,
            in: app,
            matching: .button
        )

        let sharingTitleGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: sharingTitle
        )
        let sharingPreviewGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: preview
        )
        let sharingCancelGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: sharingCancel
        )
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [
                    sharingTitleGone,
                    sharingPreviewGone,
                    sharingCancelGone,
                ],
                timeout: stateSettleTimeout
            ),
            .completed,
            "Expected Cancel to dismiss the variation-sharing composer."
        )
        XCTAssertEqual(
            element(
                SurroundUITestContract.AccessibilityID.gameChatInput,
                in: app
            ).label,
            "Say hi!"
        )
        // Cancel leaves Chat open; Analyze retains its marked position.
        setGameAnalyzing(true, in: app)
        XCTAssertTrue(
            (board.value as? String)?.contains("|marks:A=") == true,
            "Expected Cancel to preserve the active Analyze position."
        )
    }

    func testFinishedGameOffersRematchEditor() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameHistory.rawValue,
        ])

        tap(
            SurroundUITestContract.AccessibilityID.homeHistoryGame(
                SurroundUITestContract.screenshotHistoryGameIDs[0]
            ),
            in: app
        )
        tap(
            SurroundUITestContract.AccessibilityID.gameRematch,
            in: app,
            matching: .button
        )
        element(
            SurroundUITestContract.AccessibilityID.screenCustomGame,
            in: app
        )
        element(
            SurroundUITestContract.AccessibilityID.gameRematchOpponent,
            in: app
        )
    }

    func testFinishedGameKeepsNextInActionsMenu() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameHistory.rawValue,
        ])

        tap(
            SurroundUITestContract.AccessibilityID.homeHistoryGame(
                SurroundUITestContract.screenshotHistoryGameIDs[0]
            ),
            in: app
        )
        element(
            SurroundUITestContract.AccessibilityID.gameRematch,
            in: app,
            matching: .button
        )
        tap(
            SurroundUITestContract.AccessibilityID.gameActionsMenu,
            in: app
        )
        let next = requiredMenuButton(
            SurroundUITestContract.AccessibilityID.gameNext,
            title: "Next",
            in: app
        )
        XCTAssertFalse(
            menuButton(
                SurroundUITestContract.AccessibilityID.gameResign,
                title: "Resign",
                in: app
            ).exists,
            "Finished game actions should not offer Resign."
        )
        tap(next, description: "Next", in: app)
        element(
            SurroundUITestContract.AccessibilityID.gameDetail(
                SurroundUITestContract.screenshotNextGameID
            ),
            in: app
        )
    }
}
