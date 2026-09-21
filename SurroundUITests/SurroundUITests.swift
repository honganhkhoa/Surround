//
//  SurroundUITests.swift
//  SurroundUITests
//
//  Created by Anh Khoa Hong on 6/30/20.
//

import XCTest
import UIKit

final class SurroundUITests: SurroundUITestCase {
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

    private enum ScrollRevealAxis {
        case horizontal
        case vertical
    }

    private func activateZenControl(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #if targetEnvironment(macCatalyst)
        element(
            identifier,
            in: app,
            matching: .button,
            file: file,
            line: line
        )
        app.typeKey("z", modifierFlags: [.control, .option])
        #else
        tap(
            identifier,
            in: app,
            matching: .button,
            file: file,
            line: line
        )
        #endif
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var animationDiagnosticsEnabled: Bool {
        ProcessInfo.processInfo.environment[
            "SURROUND_UI_ANIMATION_DIAGNOSTICS"
        ] == "1"
    }

    private func traceAnimationTest(_ event: String) {
        guard animationDiagnosticsEnabled else { return }
        let message =
            "[SurroundAnimationTest] \(event) uptime=\(ProcessInfo.processInfo.systemUptime)\n"
        FileHandle.standardOutput.write(Data(message.utf8))
    }

    private func launchApp(
        additionalLaunchArguments: [String] = [],
        orientation: UIDeviceOrientation = .landscapeLeft
    ) -> XCUIApplication {
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.orientation = orientation
        #endif

        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            SurroundUITestContract.launchArgument,
        ] + additionalLaunchArguments
        if animationDiagnosticsEnabled {
            app.launchArguments.append(
                SurroundUITestContract.animationDiagnosticsLaunchArgument
            )
            traceAnimationTest("launch tracing=enabled")
        }
        registerAppTermination(app)
        app.launch()
        #if targetEnvironment(macCatalyst)
        app.activate()
        #endif
        return app
    }

    @discardableResult
    private func element(
        _ identifier: String,
        in app: XCUIApplication,
        matching elementType: XCUIElement.ElementType = .any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let element = app
            .descendants(matching: elementType)
            .matching(identifier: identifier)
            .firstMatch
        let appeared = element.waitForExistence(timeout: 10)
        if !appeared {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Accessibility hierarchy – missing \(identifier)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(
            appeared,
            "Expected element with identifier \(identifier)",
            file: file,
            line: line
        )
        return element
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

    // iPadOS 27 no longer forwards SwiftUI accessibility identifiers to the
    // buttons inside a presented Menu. They keep only their label, which can
    // append a subtitle ("Title, subtitle") or a count ("Title (2)"). Match
    // the identifier, or else an unidentified button or menu item with that
    // title, so identifiable controls outside the menu never match by label.
    private func menuButton(
        _ accessibilityIdentifier: String,
        title: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(
                format: "(elementType == %lu OR elementType == %lu) AND (identifier == %@ OR (identifier == '' AND (label == %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@)))",
                XCUIElement.ElementType.button.rawValue,
                XCUIElement.ElementType.menuItem.rawValue,
                accessibilityIdentifier,
                title,
                title + ", ",
                title + " ("
            )
        ).firstMatch
    }

    @discardableResult
    private func requiredMenuButton(
        _ accessibilityIdentifier: String,
        title: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let menuItem = menuButton(accessibilityIdentifier, title: title, in: app)
        let appeared = menuItem.waitForExistence(timeout: 10)
        if !appeared {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name =
                "Accessibility hierarchy – missing menu item \(accessibilityIdentifier)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(
            appeared,
            "Expected menu item \(accessibilityIdentifier) titled \(title)",
            file: file,
            line: line
        )
        return menuItem
    }

    private func unresolvedAnalyzeMenuItem(
        _ accessibilityIdentifier: String,
        catalystTitle: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        #if targetEnvironment(macCatalyst)
        let menuItems = app.descendants(matching: .menuItem)
        let exactTitleItem = menuItems
            .matching(identifier: catalystTitle)
            .firstMatch
        if exactTitleItem.exists {
            return exactTitleItem
        }

        return menuItems.matching(
            NSPredicate(
                format: "identifier == %@ OR label == %@ OR title == %@ OR value == %@ OR identifier BEGINSWITH %@ OR label BEGINSWITH %@ OR title BEGINSWITH %@ OR value BEGINSWITH %@",
                catalystTitle,
                catalystTitle,
                catalystTitle,
                catalystTitle,
                catalystTitle,
                catalystTitle,
                catalystTitle,
                catalystTitle
            )
        ).firstMatch
        #else
        return menuButton(accessibilityIdentifier, title: catalystTitle, in: app)
        #endif
    }

    @discardableResult
    private func analyzeMenuItem(
        _ accessibilityIdentifier: String,
        catalystTitle: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let menuItem = unresolvedAnalyzeMenuItem(
            accessibilityIdentifier,
            catalystTitle: catalystTitle,
            in: app
        )
        let appeared = menuItem.waitForExistence(timeout: 10)
        if !appeared {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name =
                "Accessibility hierarchy – missing menu item \(catalystTitle)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(
            appeared,
            "Expected menu item titled \(catalystTitle)",
            file: file,
            line: line
        )
        return menuItem
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

    private func tap(
        _ identifier: String,
        in app: XCUIApplication,
        matching elementType: XCUIElement.ElementType = .any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let element = element(
            identifier,
            in: app,
            matching: elementType,
            file: file,
            line: line
        )
        tap(
            element,
            description: identifier,
            in: app,
            file: file,
            line: line
        )
    }

    private func tap(
        _ element: XCUIElement,
        description: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let isHittable = waitUntilHittable(element, timeout: 10)
        if !isHittable {
            let hierarchy = XCTAttachment(
                string: """
                Element:
                \(element.debugDescription)

                Application hierarchy:
                \(app.debugDescription)
                """
            )
            hierarchy.name =
                "Accessibility hierarchy – not hittable \(description)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(
            isHittable,
            true,
            "Expected \(description) to be hittable",
            file: file,
            line: line
        )
        activate(element)
    }

    private func activate(_ element: XCUIElement) {
        #if targetEnvironment(macCatalyst)
        element.click()
        #else
        element.tap()
        #endif
    }

    private func waitUntilHittable(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: element
        )
        return XCTWaiter.wait(for: [hittable], timeout: timeout) == .completed
    }

    @discardableResult
    private func revealChatItem(
        _ identifier: String,
        in app: XCUIApplication,
        matching elementType: XCUIElement.ElementType = .any,
        interactionPoint: CGVector = CGVector(dx: 0.5, dy: 0.5),
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let chatLog = element(
            SurroundUITestContract.AccessibilityID.gameChatLog,
            in: app,
            matching: .scrollView,
            file: file,
            line: line
        )
        let target = app.descendants(matching: elementType)
            .matching(identifier: identifier)
            .firstMatch

        for attempt in 0...8 {
            var targetExists = target.exists
            var targetFrame = targetExists ? target.frame : .null
            var chatLogFrame = chatLog.frame
            if hasTappableInteractionPoint(
                interactionPoint,
                targetFrame,
                in: chatLogFrame
            ) {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                targetExists = target.exists
                targetFrame = targetExists ? target.frame : .null
                chatLogFrame = chatLog.frame
                if hasTappableInteractionPoint(
                    interactionPoint,
                    targetFrame,
                    in: chatLogFrame
                ) {
                    if targetFrame.height > chatLogFrame.height
                        || target.isHittable {
                        return target
                    }
                }
            }

            guard attempt < 8 else { break }

            guard dragScrollView(
                chatLog,
                axis: .vertical,
                targetFrame: targetExists
                    ? validInteractionFrame(
                        targetFrame,
                        interactionPoint: interactionPoint
                    ) : nil,
                containerFrame: chatLogFrame,
                interactionPoint: interactionPoint
            ) else { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        keepInteractionHierarchy(
            target,
            container: chatLog,
            in: app,
            reason: "unable to reveal chat item \(identifier)"
        )
        XCTFail(
            "Expected chat item \(identifier) to become visible and hittable",
            file: file,
            line: line
        )
        return target
    }

    private func tapChatItem(
        _ identifier: String,
        in app: XCUIApplication,
        matching elementType: XCUIElement.ElementType = .any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let interactionPoint = CGVector(dx: 0.5, dy: 0.5)
        let target = revealChatItem(
            identifier,
            in: app,
            matching: elementType,
            interactionPoint: interactionPoint,
            file: file,
            line: line
        )
        activate(target, at: interactionPoint)
    }

    @discardableResult
    private func revealAnalysisPosition(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
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
            var analysisTreeFrame = analysisTree.frame
            if hasTappableInteractionPoint(
                CGVector(dx: 0.5, dy: 0.5),
                targetFrame,
                in: analysisTreeFrame
            ) {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                targetExists = target.exists
                targetFrame = targetExists ? target.frame : .null
                analysisTreeFrame = analysisTree.frame
                if hasTappableInteractionPoint(
                    CGVector(dx: 0.5, dy: 0.5),
                    targetFrame,
                    in: analysisTreeFrame
                ), target.isHittable {
                    return target
                }
            }

            guard attempt < 10 else { break }

            let interactionPoint = CGVector(dx: 0.5, dy: 0.5)
            guard dragScrollView(
                analysisTree,
                axis: .horizontal,
                targetFrame: targetExists
                    ? validInteractionFrame(
                        targetFrame,
                        interactionPoint: interactionPoint
                    ) : nil,
                containerFrame: analysisTreeFrame,
                interactionPoint: interactionPoint
            ) else { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        keepInteractionHierarchy(
            target,
            container: analysisTree,
            in: app,
            reason: "unable to reveal analysis position \(identifier)"
        )
        XCTFail(
            "Expected analysis position \(identifier) to become visible and hittable",
            file: file,
            line: line
        )
        return target
    }

    private func tapAnalysisPosition(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var lastTarget: XCUIElement?
        for attempt in 0..<2 {
            // AnalyzeTreeView normally centers the selected position. Use
            // XCTest's valid hit point in that common case so long journeys do
            // not repeatedly traverse the complete accessibility hierarchy.
            // If that interaction does not select the node, the next attempt
            // falls back to the frame-aware reveal and centered interaction.
            let visibleTarget = app.buttons
                .matching(identifier: identifier)
                .firstMatch
            let analysisTree = app.scrollViews
                .matching(
                    identifier:
                        SurroundUITestContract.AccessibilityID
                            .gameAnalyzeTreeScroll
                )
                .firstMatch
            let interactionPoint = CGVector(dx: 0.5, dy: 0.5)
            if attempt == 0,
               visibleTarget.exists,
               hasTappableInteractionPoint(
                   interactionPoint,
                   visibleTarget.frame,
                   in: analysisTree.frame
               ) {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                if visibleTarget.exists,
                   hasTappableInteractionPoint(
                       interactionPoint,
                       visibleTarget.frame,
                       in: analysisTree.frame
                   ), visibleTarget.isHittable {
                    lastTarget = visibleTarget
                    activate(visibleTarget)
                    if waitForStableSelection(of: visibleTarget, timeout: 5) {
                        return
                    }
                    continue
                }
            }

            let target = revealAnalysisPosition(
                identifier,
                in: app,
                file: file,
                line: line
            )
            lastTarget = target
            activate(target, at: CGVector(dx: 0.5, dy: 0.5))
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
        XCTFail(
            "Expected analysis position \(identifier) to remain selected",
            file: file,
            line: line
        )
    }

    private func hasTappableInteractionPoint(
        _ interactionPoint: CGVector,
        _ elementFrame: CGRect,
        in containerFrame: CGRect
    ) -> Bool {
        guard let elementFrame = validInteractionFrame(
            elementFrame,
            interactionPoint: interactionPoint
        ), !containerFrame.isEmpty else {
            return false
        }

        let screenPoint = CGPoint(
            x: elementFrame.minX + elementFrame.width * interactionPoint.dx,
            y: elementFrame.minY + elementFrame.height * interactionPoint.dy
        )
        return containerFrame.insetBy(dx: 4, dy: 4).contains(screenPoint)
    }

    private func validInteractionFrame(
        _ frame: CGRect,
        interactionPoint: CGVector
    ) -> CGRect? {
        guard !frame.isEmpty,
              !frame.isNull,
              frame.minX.isFinite,
              frame.minY.isFinite,
              frame.width.isFinite,
              frame.height.isFinite else {
            return nil
        }

        let x = frame.minX + frame.width * interactionPoint.dx
        let y = frame.minY + frame.height * interactionPoint.dy
        return x.isFinite && y.isFinite ? frame : nil
    }

    private func dragScrollView(
        _ scrollView: XCUIElement,
        axis: ScrollRevealAxis,
        targetFrame: CGRect?,
        containerFrame: CGRect,
        interactionPoint: CGVector
    ) -> Bool {
        guard !containerFrame.isEmpty else { return false }

        let viewportLength: CGFloat
        let targetCoordinate: CGFloat?
        let viewportCenter: CGFloat
        switch axis {
        case .horizontal:
            viewportLength = containerFrame.width
            targetCoordinate = targetFrame.map {
                $0.minX + $0.width * interactionPoint.dx
            }
            viewportCenter = containerFrame.midX
        case .vertical:
            viewportLength = containerFrame.height
            targetCoordinate = targetFrame.map {
                $0.minY + $0.height * interactionPoint.dy
            }
            viewportCenter = containerFrame.midY
        }

        guard viewportLength.isFinite, viewportLength > 0 else {
            return false
        }

        let maximumDelta = viewportLength * 0.3
        let requestedDelta = targetCoordinate.map { viewportCenter - $0 }
            ?? maximumDelta
        guard requestedDelta.isFinite else { return false }
        let clampedDelta = min(
            maximumDelta,
            max(-maximumDelta, requestedDelta)
        )
        let minimumEffectiveDelta = min(CGFloat(12), maximumDelta)
        guard abs(clampedDelta) >= minimumEffectiveDelta else {
            return false
        }
        let dragDelta = clampedDelta

        #if targetEnvironment(macCatalyst)
        switch (axis, dragDelta.sign) {
        case (.horizontal, .plus):
            scrollView.swipeRight(velocity: .slow)
        case (.horizontal, .minus):
            scrollView.swipeLeft(velocity: .slow)
        case (.vertical, .plus):
            scrollView.swipeDown(velocity: .slow)
        case (.vertical, .minus):
            scrollView.swipeUp(velocity: .slow)
        }
        #else
        let start = scrollView.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        let offset: CGVector
        switch axis {
        case .horizontal:
            offset = CGVector(dx: dragDelta, dy: 0)
        case .vertical:
            offset = CGVector(dx: 0, dy: dragDelta)
        }
        start.press(
            forDuration: 0.05,
            thenDragTo: start.withOffset(offset)
        )
        #endif
        return true
    }

    private func activate(
        _ element: XCUIElement,
        at interactionPoint: CGVector
    ) {
        let coordinate = element.coordinate(
            withNormalizedOffset: interactionPoint
        )
        #if targetEnvironment(macCatalyst)
        coordinate.click()
        #else
        coordinate.tap()
        #endif
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

    private func keepInteractionHierarchy(
        _ element: XCUIElement,
        container: XCUIElement,
        in app: XCUIApplication,
        reason: String
    ) {
        let hierarchy = XCTAttachment(
            string: """
            Element:
            \(element.debugDescription)

            Container:
            \(container.debugDescription)

            Application hierarchy:
            \(app.debugDescription)
            """
        )
        hierarchy.name = "Accessibility hierarchy – \(reason)"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
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

    // Deadlines, not sleeps: each wait returns as soon as its condition holds.
    // On hosted runners a single accessibility query can hang for about nine
    // seconds before XCTest retries it, which used up the old 5- and 10-second
    // windows while the app had already reached the expected state.
    private let stateSettleTimeout: TimeInterval = 30

    private func waitForValue(
        _ value: String,
        in textField: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let completeValue = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: textField
        )
        return XCTWaiter.wait(for: [completeValue], timeout: timeout) == .completed
    }

    private func assertQuickMatchToggle(
        _ identifier: String,
        isOn: Bool,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let toggle = element(identifier, in: app, file: file, line: line)
        XCTAssertTrue(
            waitForValue(isOn ? "1" : "0", in: toggle, timeout: stateSettleTimeout),
            "Expected \(identifier) to be \(isOn ? "on" : "off")",
            file: file,
            line: line
        )
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

    private func assertSelected(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let selectedElement = element(
            identifier,
            in: app,
            file: file,
            line: line
        )
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"),
            object: selectedElement
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [selected], timeout: 10),
            .completed,
            "Expected element with identifier \(identifier) to be selected",
            file: file,
            line: line
        )
    }

    private func assertNotSelected(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let selectedElement = element(
            identifier,
            in: app,
            file: file,
            line: line
        )
        let notSelected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == false"),
            object: selectedElement
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [notSelected], timeout: 10),
            .completed,
            "Expected element with identifier \(identifier) not to be selected",
            file: file,
            line: line
        )
    }

    private func scrollIntoTappableArea(
        _ element: XCUIElement,
        in app: XCUIApplication
    ) {
        if element.identifier.hasPrefix("quickMatch.") {
            let scroll = app.scrollViews[SurroundUITestContract.AccessibilityID.quickMatchScroll]
            if scroll.exists {
                for _ in 0..<10 {
                    let safeFrame = scroll.frame.insetBy(dx: 0, dy: 8)
                    if element.isHittable && safeFrame.contains(element.frame) { return }
                    if element.frame.minY < safeFrame.minY {
                        scroll.swipeDown()
                    } else {
                        scroll.swipeUp()
                    }
                }
                return
            }
        }
        for _ in 0..<4 {
            #if targetEnvironment(macCatalyst)
            guard !element.isHittable else {
                return
            }
            app.swipeUp()
            #else
            let safeTop = app.frame.minY
            let safeBottom = app.frame.maxY - 100
            let overlapsTopEdge = element.frame.minY < safeTop
            let overlapsTabBar = element.frame.maxY > safeBottom

            guard !element.isHittable
                    || overlapsTopEdge
                    || overlapsTabBar else {
                return
            }

            if overlapsTopEdge {
                // XCTest can report a partially clipped LazyVGrid button as
                // hittable, then dispatch its coordinate tap through another
                // row. Move the entire target back inside the viewport.
                let dragStartsAt = app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.75, dy: 0.35)
                )
                let dragEndsAt = app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.75, dy: 0.50)
                )
                dragStartsAt.press(forDuration: 0.05, thenDragTo: dragEndsAt)
            } else {
                app.swipeUp()
            }
            #endif
        }
    }

    @discardableResult
    private func elementAfterScrolling(
        _ identifier: String,
        in app: XCUIApplication,
        matching elementType: XCUIElement.ElementType = .any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let candidate = app.descendants(matching: elementType)
            .matching(identifier: identifier)
            .firstMatch
        for _ in 0..<8 where !candidate.exists {
            let quickMatchScroll = app.scrollViews[
                SurroundUITestContract.AccessibilityID.quickMatchScroll
            ]
            if identifier.hasPrefix("quickMatch.") && quickMatchScroll.exists {
                quickMatchScroll.swipeUp()
            } else {
                app.swipeUp()
            }
        }
        return element(
            identifier,
            in: app,
            matching: elementType,
            file: file,
            line: line
        )
    }

    private func keepScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(
            screenshot: XCUIScreen.main.screenshot(),
            quality: .original
        )
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func popoverDismissalPoint(
        in app: XCUIApplication,
        navigationTitle: String
    ) -> XCUICoordinate {
        #if targetEnvironment(macCatalyst)
        return app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.98))
        #else
        let title = app.navigationBars.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", navigationTitle))
            .firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(title.isHittable, "Expected the owning page's navigation title.")
        let frame = title.frame
        XCTAssertTrue(app.frame.contains(frame))
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        // Capture coordinates while the title is exposed. Resolving its query
        // after the menu opens can fail because the menu obscures accessibility.
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: frame.midX - app.frame.minX,
            dy: frame.midY - app.frame.minY
        ))
        #endif
    }

    private func dismissPopover(
        in app: XCUIApplication,
        at point: XCUICoordinate,
        containing presentedElement: XCUIElement,
        restoring identifiers: [String]
    ) {
        XCTAssertTrue(presentedElement.exists, "Expected the popover or menu before dismissal.")
        #if targetEnvironment(macCatalyst)
        point.click()
        #else
        point.tap()
        #endif
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: presentedElement
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [dismissed], timeout: stateSettleTimeout), .completed,
            "Expected the popover or menu to dismiss."
        )
        // Menu disappearance alone would also pass after an accidental tap on
        // Home in the sidebar. Verify that the owning page remains displayed.
        for identifier in identifiers {
            element(identifier, in: app)
        }
    }

    private func navigateBackFromPlayerProfile(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let profileScreen = element(SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app,
                                    file: file, line: line)
        let loadedHeader = app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.profileLoaded).firstMatch
        let header = loadedHeader.exists ? loadedHeader
            : element(SurroundUITestContract.AccessibilityID.profileIdentity, in: app, file: file, line: line)
        let navigationBar: XCUIElement
        if header.staticTexts["You"].exists {
            navigationBar = app.navigationBars["Profile"].firstMatch
        } else {
            // Match the title to the identity already rendered by this
            // profile. Its rank can be appended to the identity label.
            let identity = header.staticTexts.firstMatch.label
            let matchingBar = app.navigationBars.allElementsBoundByIndex.first { bar in
                [bar.identifier, bar.label].contains { title in
                    !title.isEmpty && (identity == title || identity.hasPrefix(title + " ["))
                }
            }
            XCTAssertNotNil(matchingBar, "The other player's username must title its navigation bar.", file: file, line: line)
            guard let matchingBar else { return }
            navigationBar = matchingBar
        }
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertFalse(app.navigationBars.buttons["Close"].exists,
                       "Profiles must use stack navigation, without a modal Close action.",
                       file: file, line: line)
        XCTAssertFalse(navigationBar.buttons["Close"].exists, file: file, line: line)

        // UIKit exposes BackButton on recent systems; older releases use
        // the preceding page's title for the first navigation-bar button.
        let identifiedBack = navigationBar.buttons.matching(identifier: "BackButton").firstMatch
        let back = identifiedBack.exists ? identifiedBack : navigationBar.buttons.firstMatch
        tap(back, description: "Back from profile", in: app, file: file, line: line)
        let returned = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            // A conversation can have the same username title. The profile
            // content, rather than the title, must leave the visible stack.
            object: profileScreen
        )
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed,
                       "Back must pop the profile and reveal its originating page.",
                       file: file, line: line)
    }

    private func revealCustomGameControl(
        _ identifier: String,
        in app: XCUIApplication,
        matching type: XCUIElement.ElementType = .any
    ) -> XCUIElement {
        let control = element(identifier, in: app, matching: type)
        let scroll = app.scrollViews.containing(.textField, identifier: SurroundUITestContract.AccessibilityID.customGameName).firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        for _ in 0..<12 {
            let safeFrame = scroll.frame.intersection(app.frame).insetBy(dx: 0, dy: 12)
            if control.isHittable && safeFrame.contains(control.frame) { return control }
            if control.frame.minY < safeFrame.minY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(control.isHittable, "Expected form control \(identifier) to be visible.")
        return control
    }

    private func openProfileContextMenu(
        for row: XCUIElement,
        in app: XCUIApplication
    ) {
        scrollIntoTappableArea(row, in: app)
        XCTAssertTrue(row.isHittable, "The row must be visible before opening its context menu.")
        #if targetEnvironment(macCatalyst)
        row.rightClick()
        #else
        row.press(forDuration: 1)
        #endif
    }

    private func assertLoadedProfile(
        named username: String,
        isOwnProfile: Bool = false,
        in app: XCUIApplication
    ) {
        let header = element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        let identity = header.descendants(matching: .staticText).matching(
            NSPredicate(format: "label == %@ OR label BEGINSWITH %@", username, username + " [")
        ).firstMatch
        XCTAssertTrue(identity.waitForExistence(timeout: 10),
                      "The selected player's identity must appear in the loaded profile.")
        XCTAssertTrue(app.navigationBars[isOwnProfile ? "Profile" : username].waitForExistence(timeout: 10),
                      "Own profiles use Profile; other profiles use the player's username as their title.")
    }

    private func launchProfileContent(
        scene: SurroundUITestContract.CompatibilityScene = .home,
        additionalLaunchArguments: [String] = []
    ) -> XCUIApplication {
        launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            scene.rawValue,
            SurroundUITestContract.profileContentLaunchArgument,
        ] + additionalLaunchArguments, orientation: UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .landscapeLeft)
    }

    private func openProfileContentFromHome(in app: XCUIApplication) {
        let gameID = SurroundUITestContract.screenshotPrimaryGameID
        let row = elementAfterScrolling(SurroundUITestContract.AccessibilityID.homeGame(gameID), in: app)
        openProfileContextMenu(for: row, in: app)
        tap(requiredMenuButton(
            SurroundUITestContract.AccessibilityID.profileGameMenuEntry(gameID, SurroundUITestContract.profileFixtureOpponentID),
            title: "View Profile", in: app
        ), description: "Open CopperKoi's profile", in: app)
        assertLoadedProfile(named: "CopperKoi", in: app)
    }

    @discardableResult
    private func revealProfileControl(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let control = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let scroll = app.scrollViews[SurroundUITestContract.AccessibilityID.screenPlayerProfile].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        let interactionPoint = CGVector(dx: 0.5, dy: 0.5)
        for _ in 0..<14 {
            let safeFrame = scroll.frame.intersection(app.frame).insetBy(dx: 0, dy: 12)
            guard control.exists else {
                // A lazy grid does not expose the target's position until
                // its row approaches the viewport.
                scroll.swipeUp()
                continue
            }
            let targetFrame = control.frame
            let center = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
            let visibleEnough = safeFrame.contains(targetFrame)
                || (targetFrame.height > safeFrame.height && safeFrame.contains(center))
            if visibleEnough && control.isHittable { return control }
            // Full swipes can repeatedly overshoot a large Dynamic Type
            // headline. Move toward its measured center in bounded steps.
            guard dragScrollView(
                scroll,
                axis: .vertical,
                targetFrame: validInteractionFrame(targetFrame, interactionPoint: interactionPoint),
                containerFrame: safeFrame,
                interactionPoint: interactionPoint
            ) else { break }
        }
        keepInteractionHierarchy(control, container: scroll, in: app,
                                 reason: "unable to reveal profile control \(identifier)")
        XCTFail("Expected visible profile control \(identifier).")
        return control
    }

    private func backToProfile(from navigationTitle: String, destinationID: String, in app: XCUIApplication) {
        // Regular-width layouts also expose the sidebar's navigation bar.
        // Scope Back to the destination we actually opened.
        let destination = element(destinationID, in: app)
        let navigationBar = app.navigationBars[navigationTitle].firstMatch
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10))
        let identifiedBack = navigationBar.buttons.matching(identifier: "BackButton").firstMatch
        let back = identifiedBack.exists ? identifiedBack : navigationBar.buttons.firstMatch
        tap(back, description: "Return to profile", in: app)
        element(SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
        element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        XCTAssertFalse(destination.exists, "Back must leave the \(navigationTitle) destination, even when the profile shares its title.")
    }

    func testProfileActiveGamesPreviewAndNavigationReuse() {
        let app = launchProfileContent()
        openProfileContentFromHome(in: app)
        keepScreenshot("Profile – identity and ratings", in: app)
        let activeIDs = SurroundUITestContract.profileFixtureActiveGameIDs
        for gameID in activeIDs.prefix(3) {
            revealProfileControl(SurroundUITestContract.AccessibilityID.profileActiveGame(gameID), in: app)
        }
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.profileActiveGame(activeIDs[3])).firstMatch.exists,
            "The profile preview must stop after three active games.")
        keepScreenshot("Profile – active games preview", in: app)
        let seeAll = revealProfileControl(SurroundUITestContract.AccessibilityID.profileAllActiveGames, in: app)
        tap(seeAll, description: "See all profile active games", in: app)
        element(SurroundUITestContract.AccessibilityID.screenProfileActiveGames, in: app)
        elementAfterScrolling(SurroundUITestContract.AccessibilityID.profileActiveGame(activeIDs[3]), in: app)
        let firstGame = element(SurroundUITestContract.AccessibilityID.profileActiveGame(activeIDs[0]), in: app)
        scrollIntoTappableArea(firstGame, in: app)
        tap(firstGame, description: "Open a profile's active game", in: app)
        element(SurroundUITestContract.AccessibilityID.gameDetail(activeIDs[0]), in: app)
        tap(SurroundUITestContract.AccessibilityID.profileBannerAvatarEntry(
            SurroundUITestContract.profileFixtureOpponentID), in: app, matching: .button)
        assertLoadedProfile(named: "CopperKoi", in: app)
        // Reuse the earlier profile. Its Back must reach Home directly,
        // rather than stacking a second profile over the game and list.
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
    }

    private func launchFriendship(
        scene: SurroundUITestContract.CompatibilityScene = .home,
        failsOnce: Bool = false,
        additionalLaunchArguments: [String] = []
    ) -> XCUIApplication {
        var arguments = [SurroundUITestContract.friendshipLaunchArgument]
        if failsOnce {
            arguments.append(SurroundUITestContract.friendshipFailsOnceLaunchArgument)
        }
        return launchProfileContent(scene: scene, additionalLaunchArguments: arguments + additionalLaunchArguments)
    }

    @discardableResult
    private func assertFriendshipState(_ state: String, in app: XCUIApplication) -> XCUIElement {
        let action = revealProfileControl(SurroundUITestContract.AccessibilityID.profileFriendshipAction, in: app)
        let labels = ["none": "Add friend", "requestSent": "Request sent", "friends": "Friends"]
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", labels[state] ?? state), object: action
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed,
                      "Expected the profile's friendship state to become \(state).")
        return action
    }

    private func tapFriendshipDialogAction(_ identifier: String, title: String, in app: XCUIApplication) {
        let action = requiredMenuButton(identifier, title: title, in: app)
        if !action.isHittable {
            // At accessibility text sizes UIKit gives a confirmation sheet's
            // actions their own scroll view, separate from the title/message.
            // Reveal the action inside that native sheet, never in the profile
            // scroll view underneath its popover.
            let actionsScroll = app.sheets.scrollViews.containing(NSPredicate(
                format: "elementType == %lu AND (identifier == %@ OR label == %@)",
                XCUIElement.ElementType.button.rawValue, identifier, title
            )).firstMatch
            for _ in 0..<4 where !action.isHittable {
                guard actionsScroll.exists else { break }
                actionsScroll.swipeUp()
            }
            if action.isHittable {
                keepScreenshot("Friendship confirmation – revealed \(title)", in: app)
            }
        }
        tap(action, description: title, in: app)
    }

    private func openRemoveFriendConfirmation(in app: XCUIApplication) {
        tap(assertFriendshipState("friends", in: app), description: "Open friendship actions", in: app)
        tapFriendshipDialogAction(SurroundUITestContract.AccessibilityID.profileRemoveFriend,
                                  title: "Remove friend", in: app)
        requiredMenuButton(SurroundUITestContract.AccessibilityID.friendshipRemoveConfirm,
                           title: "Remove friend", in: app)
    }

    private func cancelFriendshipConfirmation(
        in app: XCUIApplication,
        at dismissalPoint: XCUICoordinate,
        containing confirmation: XCUIElement,
        restoring identifier: String
    ) {
        let popover = app.popovers.firstMatch
        if popover.exists {
            // iOS 27 can use a popover on iPhone as well as iPad. Its frame
            // may cover the previously visible navigation title, so choose
            // an observed point outside the actual presented popover.
            let bounds = app.frame.insetBy(dx: 20, dy: 20)
            let presentedFrame = popover.frame
            let candidates = [
                CGPoint(x: bounds.midX, y: presentedFrame.maxY + 20),
                CGPoint(x: presentedFrame.maxX + 20, y: bounds.midY),
                CGPoint(x: presentedFrame.minX - 20, y: bounds.midY),
                CGPoint(x: bounds.midX, y: presentedFrame.minY - 20),
            ]
            guard let outside = candidates.first(where: { bounds.contains($0) && !presentedFrame.contains($0) }) else {
                XCTFail("Expected space outside the confirmation popover to cancel it.")
                return
            }
            let point = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: outside.x - app.frame.minX, dy: outside.y - app.frame.minY
            ))
            dismissPopover(in: app, at: point, containing: confirmation, restoring: [identifier])
            return
        }
        #if !targetEnvironment(macCatalyst)
        if UIDevice.current.userInterfaceIdiom == .phone {
            let cancel = app.buttons.matching(NSPredicate(format: "label == %@", "Cancel"))
                .allElementsBoundByIndex.first(where: \.isHittable)
            XCTAssertNotNil(cancel, "The phone confirmation sheet must offer Cancel.")
            guard let cancel else { return }
            tap(cancel, description: "Cancel the friendship confirmation", in: app)
            let dismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: confirmation
            )
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
            element(identifier, in: app)
            return
        }
        #endif
        // Regular-width confirmation dialogs omit Cancel. Dismiss their
        // popover outside its bounds, without activating a control beneath it.
        dismissPopover(in: app, at: dismissalPoint, containing: confirmation, restoring: [identifier])
    }

    private func assertFriendRequestRemoved(_ playerID: Int, in app: XCUIApplication, timeout: TimeInterval = 10) {
        let request = app.buttons[SurroundUITestContract.AccessibilityID.friendRequestProfile(playerID)].firstMatch
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: request)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: timeout), .completed,
                       "A completed request must leave the Home request list.")
    }

    private func retryFriendshipError(in app: XCUIApplication) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "A failed friendship action must explain the error.")
        tap(alert.buttons["Retry"].firstMatch, description: "Retry the failed friendship action", in: app)
    }

    private func revealHomeFriendRequest(_ playerID: Int, in app: XCUIApplication) -> XCUIElement {
        let control = elementAfterScrolling(SurroundUITestContract.AccessibilityID.friendRequestProfile(playerID),
                                            in: app, matching: .button)
        let scroll = element(SurroundUITestContract.AccessibilityID.screenHome, in: app, matching: .scrollView)
        let header = app.staticTexts[SurroundUITestContract.AccessibilityID.homeFriendRequests].firstMatch
        let navigationBar = app.navigationBars["Active games"].firstMatch
        let tabBar = app.tabBars.firstMatch
        for _ in 0..<10 {
            let viewport = scroll.frame.intersection(app.frame)
            var top = navigationBar.exists ? max(viewport.minY, navigationBar.frame.maxY) : viewport.minY
            if header.exists, header.frame.intersects(viewport) { top = max(top, header.frame.maxY) }
            let bottom = tabBar.exists ? min(viewport.maxY, tabBar.frame.minY) : viewport.maxY
            let safeFrame = CGRect(x: viewport.minX, y: top + 8, width: viewport.width,
                                   height: max(0, bottom - top - 16))
            if control.isHittable, safeFrame.contains(control.frame) { return control }
            if safeFrame.isEmpty {
                scroll.swipeUp()
            } else if !dragScrollView(scroll, axis: .vertical, targetFrame: control.frame,
                                      containerFrame: safeFrame, interactionPoint: CGVector(dx: 0.5, dy: 0.5)) {
                break
            }
        }
        keepInteractionHierarchy(control, container: scroll, in: app,
                                 reason: "unable to reveal friendship identity below pinned Home header")
        XCTFail("The friendship identity must fit below Home's pinned section header before tapping.")
        return control
    }

    func testFriendRequestAcceptSynchronizesProfileHomeAndOpponentPicker() {
        let app = launchFriendship()
        let playerID = SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]
        let username = SurroundUITestContract.friendshipFixtureRequestUsernames[0]
        let profileEntry = elementAfterScrolling(SurroundUITestContract.AccessibilityID.friendRequestProfile(playerID),
                                                in: app, matching: .button)
        scrollIntoTappableArea(profileEntry, in: app)
        keepScreenshot("Friendship – incoming requests on Home", in: app)
        tap(profileEntry, description: "View the incoming friend's profile", in: app)
        assertLoadedProfile(named: username, in: app)
        element(SurroundUITestContract.AccessibilityID.profileFriendRequest, in: app)
        tap(SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID), in: app, matching: .button)
        assertFriendshipState("friends", in: app)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID)].exists)
        keepScreenshot("Friendship – accepted from profile", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        assertFriendRequestRemoved(playerID, in: app)
        elementAfterScrolling(SurroundUITestContract.AccessibilityID.friendRequestProfile(
            SurroundUITestContract.friendshipFixtureRequestPlayerIDs[1]), in: app, matching: .button)

        // The picker consumes the shared friends list. Enter from a different
        // profile so the new friend cannot appear just as a selected opponent.
        openProfileContentFromHome(in: app)
        tap(SurroundUITestContract.AccessibilityID.profileChallenge, in: app, matching: .button)
        let opponent = revealCustomGameControl(SurroundUITestContract.AccessibilityID.customGameOpponent,
                                              in: app, matching: .button)
        tap(opponent, description: "Choose a challenge opponent", in: app)
        element(SurroundUITestContract.AccessibilityID.screenOpponentPicker, in: app)
        let newFriend = elementAfterScrolling(SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID),
                                             in: app, matching: .button)
        scrollIntoTappableArea(newFriend, in: app)
        tap(newFriend, description: "Open the accepted friend from the picker", in: app)
        assertLoadedProfile(named: username, in: app)
        assertFriendshipState("friends", in: app)
    }

    func testFriendRequestRejectionCanCancelNotifyOrStayQuiet() {
        let app = launchFriendship()
        let playerIDs = SurroundUITestContract.friendshipFixtureRequestPlayerIDs
        for (index, playerID) in playerIDs.prefix(2).enumerated() {
            let reject = elementAfterScrolling(SurroundUITestContract.AccessibilityID.friendRequestReject(playerID),
                                               in: app, matching: .button)
            scrollIntoTappableArea(reject, in: app)
            let dismissalPoint = popoverDismissalPoint(in: app, navigationTitle: "Active games")
            tap(reject, description: "Review rejection choices", in: app)
            let confirmation = requiredMenuButton(SurroundUITestContract.AccessibilityID.friendshipRejectNotify,
                                                  title: "Reject and Let Them Know", in: app)
            requiredMenuButton(SurroundUITestContract.AccessibilityID.friendshipRejectQuietly,
                               title: "Reject Quietly", in: app)
            if index == 0 {
                cancelFriendshipConfirmation(in: app, at: dismissalPoint, containing: confirmation,
                                             restoring: SurroundUITestContract.AccessibilityID.screenHome)
                XCTAssertTrue(reject.exists, "Cancelling must leave the request available.")
                tap(reject, description: "Reopen rejection choices", in: app)
            }
            tapFriendshipDialogAction(index == 0
                ? SurroundUITestContract.AccessibilityID.friendshipRejectQuietly
                : SurroundUITestContract.AccessibilityID.friendshipRejectNotify,
                title: index == 0 ? "Reject Quietly" : "Reject and Let Them Know", in: app)
            assertFriendRequestRemoved(playerID, in: app)
        }
        elementAfterScrolling(SurroundUITestContract.AccessibilityID.friendRequestProfile(playerIDs[2]),
                              in: app, matching: .button)
        keepScreenshot("Friendship – only the unanswered request remains", in: app)
    }

    func testRemovingFriendUpdatesPickerAndSendingRequestPersistsAcrossNavigation() {
        let app = launchFriendship(scene: .opponentPicker)
        let playerID = SurroundUITestContract.profileFixturePickerFriendID
        tap(SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID), in: app, matching: .button)
        assertLoadedProfile(named: "BambooPath", in: app)
        let dismissalPoint = popoverDismissalPoint(in: app, navigationTitle: "BambooPath")
        openRemoveFriendConfirmation(in: app)
        let confirmation = requiredMenuButton(SurroundUITestContract.AccessibilityID.friendshipRemoveConfirm,
                                              title: "Remove friend", in: app)
        cancelFriendshipConfirmation(in: app, at: dismissalPoint, containing: confirmation,
                                     restoring: SurroundUITestContract.AccessibilityID.screenPlayerProfile)
        assertFriendshipState("friends", in: app)
        openRemoveFriendConfirmation(in: app)
        tapFriendshipDialogAction(SurroundUITestContract.AccessibilityID.friendshipRemoveConfirm,
                                  title: "Remove friend", in: app)
        assertFriendshipState("none", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenOpponentPicker, in: app)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID)].exists,
                       "The removed friend must disappear from the picker's friends list.")

        let search = element(SurroundUITestContract.AccessibilityID.opponentSearch, in: app)
        tap(search, description: "Find the former friend", in: app)
        search.typeText("Bamboo\n")
        XCTAssertTrue(waitForValue("Bamboo", in: search, timeout: 10))
        tap(SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID), in: app, matching: .button)
        assertLoadedProfile(named: "BambooPath", in: app)
        tap(assertFriendshipState("none", in: app), description: "Send a friend request", in: app)
        XCTAssertFalse(assertFriendshipState("requestSent", in: app).isEnabled,
                       "A sent request must not allow duplicate submissions.")
        navigateBackFromPlayerProfile(in: app)
        tap(SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID), in: app, matching: .button)
        XCTAssertFalse(assertFriendshipState("requestSent", in: app).isEnabled,
                       "Returning to the profile must retain the pending request.")
        keepScreenshot("Friendship – request sent", in: app)
    }

    func testFriendshipAcceptAndSendFailuresCanRetryWithoutLosingState() {
        let app = launchFriendship(failsOnce: true)
        let playerID = SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]
        let accept = elementAfterScrolling(SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID),
                                           in: app, matching: .button)
        scrollIntoTappableArea(accept, in: app)
        tap(accept, description: "Accept with a simulated connection failure", in: app)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        tap(alert.buttons["Cancel"].firstMatch, description: "Dismiss the failed acceptance", in: app)
        XCTAssertTrue(accept.exists, "A failed acceptance must preserve its request.")
        XCTAssertTrue(accept.isEnabled, "A failed action must unlock its controls.")
        tap(accept, description: "Accept the retained request", in: app)
        assertFriendRequestRemoved(playerID, in: app)

        openProfileContentFromHome(in: app)
        tap(assertFriendshipState("none", in: app), description: "Send with a simulated connection failure", in: app)
        retryFriendshipError(in: app)
        XCTAssertFalse(assertFriendshipState("requestSent", in: app).isEnabled)
    }

    func testRemovingFriendFailureCanRetry() {
        let app = launchFriendship(scene: .opponentPicker, failsOnce: true)
        let playerID = SurroundUITestContract.profileFixturePickerFriendID
        tap(SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID), in: app, matching: .button)
        openRemoveFriendConfirmation(in: app)
        tapFriendshipDialogAction(SurroundUITestContract.AccessibilityID.friendshipRemoveConfirm,
                                  title: "Remove friend", in: app)
        retryFriendshipError(in: app)
        assertFriendshipState("none", in: app)
        navigateBackFromPlayerProfile(in: app)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID)].exists)
    }

    func testFriendshipFailureArrivingAfterOpeningProfileCanRetryWithoutReentry() {
        let app = launchFriendship(failsOnce: true, additionalLaunchArguments: [
            SurroundUITestContract.friendshipSlowResponseLaunchArgument,
        ])
        let playerID = SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]
        let username = SurroundUITestContract.friendshipFixtureRequestUsernames[0]
        let entry = revealHomeFriendRequest(playerID, in: app)
        let accept = elementAfterScrolling(SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID),
                                           in: app, matching: .button)
        scrollIntoTappableArea(accept, in: app)
        tap(accept, description: "Start accepting the request on Home", in: app)
        tap(entry, description: "Open the sender's profile while acceptance is pending", in: app)
        assertLoadedProfile(named: username, in: app)
        element(SurroundUITestContract.AccessibilityID.friendRequestBusy(playerID), in: app)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID)].exists,
                       "The profile must share Home's pending action and prevent another submission.")

        let failure = app.alerts.firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 20),
                      "The failure must appear on the already-open profile without leaving and reentering it.")
        tap(failure.buttons["Retry"].firstMatch, description: "Retry Home's failed acceptance from the profile", in: app)
        let friendship = app.buttons[SurroundUITestContract.AccessibilityID.profileFriendshipAction].firstMatch
        XCTAssertTrue(friendship.waitForExistence(timeout: 20))
        assertLoadedProfile(named: username, in: app)
        assertFriendshipState("friends", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        assertFriendRequestRemoved(playerID, in: app)
    }

    func testFriendshipFailureArrivingAfterReturningHomeCanRetryWithoutReentry() {
        let app = launchFriendship(failsOnce: true, additionalLaunchArguments: [
            SurroundUITestContract.friendshipSlowResponseLaunchArgument,
        ])
        let playerID = SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]
        let entry = revealHomeFriendRequest(playerID, in: app)
        tap(entry, description: "Open the incoming friend's profile", in: app)
        assertLoadedProfile(named: SurroundUITestContract.friendshipFixtureRequestUsernames[0], in: app)
        tap(SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID), in: app, matching: .button)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        element(SurroundUITestContract.AccessibilityID.friendRequestBusy(playerID), in: app)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID)].exists,
                       "Home must share the profile's pending acceptance.")

        let failure = app.alerts.firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 20),
                      "A failure after leaving the profile must appear on Home without reopening the profile.")
        tap(failure.buttons["Retry"].firstMatch, description: "Retry the profile's failed acceptance from Home", in: app)
        assertFriendRequestRemoved(playerID, in: app, timeout: 20)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
    }

    func testFriendRequestRemainsUsableInDarkModeAtLargestDynamicType() {
        let app = launchFriendship(additionalLaunchArguments: [
            SurroundUITestContract.appearanceLaunchArgument, "dark",
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ])
        let playerID = SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]
        let entry = revealHomeFriendRequest(playerID, in: app)
        tap(entry, description: "Open an incoming request at the largest text size", in: app)
        assertLoadedProfile(named: SurroundUITestContract.friendshipFixtureRequestUsernames[0], in: app)
        let identity = element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        XCTAssertTrue(waitForValue("dark", in: identity, timeout: 10))
        for identifier in [
            SurroundUITestContract.AccessibilityID.friendRequestReject(playerID),
            SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID),
            SurroundUITestContract.AccessibilityID.profileChallenge,
            SurroundUITestContract.AccessibilityID.profileMessage,
        ] {
            XCTAssertTrue(revealProfileControl(identifier, in: app).isHittable,
                          "Each incoming-request and profile action must remain reachable at the largest text size.")
        }
        keepScreenshot("Friendship – incoming request in dark and largest Dynamic Type", in: app)
        let reject = revealProfileControl(SurroundUITestContract.AccessibilityID.friendRequestReject(playerID), in: app)
        tap(reject, description: "Reject an incoming request at the largest text size", in: app)
        tapFriendshipDialogAction(SurroundUITestContract.AccessibilityID.friendshipRejectQuietly,
                                  title: "Reject Quietly", in: app)
        XCTAssertTrue(assertFriendshipState("none", in: app).isHittable)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID)].exists)
        keepScreenshot("Friendship – Add friend after rejection at the largest text size", in: app)
    }

    func testProfileHistoryAndHeadToHeadUseCorrectPerspective() {
        let app = launchProfileContent()
        openProfileContentFromHome(in: app)
        let summary = revealProfileControl(SurroundUITestContract.AccessibilityID.profileHeadToHeadSummary, in: app)
        let summaryText = summary.label + " " + (summary.value as? String ?? "")
        for total in ["14", "9", "1"] {
            XCTAssertTrue(summaryText.contains(total), "Head-to-head must display server totals, independently of its five recent results.")
        }
        let historyIDs = SurroundUITestContract.profileFixtureHistoryGameIDs
        for (gameID, result) in zip(historyIDs, ["Win", "Loss", "Draw", "Win", "Loss"]) {
            let recent = element(SurroundUITestContract.AccessibilityID.profileHeadToHeadRecent(gameID), in: app)
            XCTAssertTrue((recent.label + " " + (recent.value as? String ?? "")).contains(result),
                          "Recent results must use the signed-in viewer's perspective.")
        }
        keepScreenshot("Profile – viewer-relative head-to-head", in: app)
        let previewCount = UIDevice.current.userInterfaceIdiom == .phone ? 2 : 4
        _ = revealProfileControl(SurroundUITestContract.AccessibilityID.profileHistoryGame(historyIDs[0]), in: app)
        for gameID in historyIDs.prefix(previewCount) {
            element(SurroundUITestContract.AccessibilityID.profileHistoryGame(gameID), in: app)
        }
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.profileHistoryGame(historyIDs[previewCount])).firstMatch.exists,
            "The profile history preview must show two games on phone and four at regular width.")
        let history = revealProfileControl(SurroundUITestContract.AccessibilityID.profileAllHistory, in: app)
        tap(history, description: "See the player's complete game history", in: app)
        element(SurroundUITestContract.AccessibilityID.screenProfileGameHistory, in: app)
        let generalFirst = element(SurroundUITestContract.AccessibilityID.profileHistoryGame(historyIDs[0]), in: app)
        XCTAssertTrue(generalFirst.label.contains("Loss"), "General history must use CopperKoi's result, not the viewer's win.")
        XCTAssertTrue(generalFirst.label.contains("You"), "The signed-in player must use the You identity in another player's history.")
        XCTAssertFalse(generalFirst.label.contains("JuniperStone"), "The self-opponent row should not replace You with the signed-in username.")
        elementAfterScrolling(SurroundUITestContract.AccessibilityID.profileHistoryGame(historyIDs.last!), in: app)
        backToProfile(from: "Game history", destinationID: SurroundUITestContract.AccessibilityID.screenProfileGameHistory, in: app)
        let headToHeadHistory = revealProfileControl(SurroundUITestContract.AccessibilityID.profileHeadToHeadHistory, in: app)
        XCTAssertTrue(headToHeadHistory.label.contains("See all games"))
        XCTAssertFalse(headToHeadHistory.label.contains("24"),
                       "The filtered history link must not imply its feed has the server record's total number of games.")
        tap(headToHeadHistory, description: "Open history against this player", in: app)
        element(SurroundUITestContract.AccessibilityID.screenProfileGameHistory, in: app)
        let filteredFirst = element(SurroundUITestContract.AccessibilityID.profileHistoryGame(historyIDs[0]), in: app)
        XCTAssertTrue(filteredFirst.label.contains("Win"), "Head-to-head history must agree with the viewer's record.")
        XCTAssertTrue(filteredFirst.label.contains("CopperKoi"))
        elementAfterScrolling(SurroundUITestContract.AccessibilityID.profileHistoryGame(historyIDs.last!), in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.profileHistoryGame(historyIDs[5])).firstMatch.exists,
            "The filtered history must exclude CopperKoi's game against a different player.")
    }

    func testShortProfileHistoryDoesNotOfferRedundantSeeAll() {
        let app = launchProfileContent(additionalLaunchArguments: [
            SurroundUITestContract.profileShortHistoryLaunchArgument,
        ])
        openProfileContentFromHome(in: app)
        let historyIDs = SurroundUITestContract.profileFixtureHistoryGameIDs
        for gameID in historyIDs.prefix(2) {
            _ = revealProfileControl(SurroundUITestContract.AccessibilityID.profileHistoryGame(gameID), in: app)
        }
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.profileHistoryGame(historyIDs[2])).firstMatch.exists)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profileAllHistory].exists,
                       "When every finished game is already in the preview, neither phone nor wide layouts should offer See all games.")
        keepScreenshot("Profile history – complete two-game preview", in: app)
    }

    func testProfileRatingsCategoriesAndPreferencePersistence() {
        let app = launchProfileContent()
        openProfileContentFromHome(in: app)
        for category in ["overall", "19x19", "13x13", "9x9", "blitz", "live", "correspondence"] {
            element(SurroundUITestContract.AccessibilityID.profileRatingCategory(category), in: app)
        }
        let nine = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("9x9"), in: app)
        XCTAssertTrue((nine.value as? String ?? "").contains("Provisional"), "A category at deviation 160 is provisional even with a stable overall rating.")
        let overall = element(SurroundUITestContract.AccessibilityID.profileRatingCategory("overall"), in: app)
        XCTAssertFalse((overall.value as? String ?? "").contains("Provisional"))
        tap(nine, description: "Select provisional 9×9 rating", in: app)
        let headline = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingHeadline, in: app)
        XCTAssertTrue(headline.label.contains("Provisional"))
        XCTAssertFalse(headline.label.contains("±"), "A provisional Rank headline uses its likely range instead of a deviation subtitle.")
        keepScreenshot("Profile ratings – category-specific provisional rank", in: app)
        _ = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingMode, in: app)
        selectSegment(at: 1, in: SurroundUITestContract.AccessibilityID.profileRatingMode, app: app)
        XCTAssertTrue(headline.label.contains("1650") || headline.label.contains("1,650"))
        XCTAssertTrue(headline.label.contains("±"), "Numeric Rating mode keeps the category's deviation, including provisional categories.")
        navigateBackFromPlayerProfile(in: app)
        openProfileContentFromHome(in: app)
        let mode = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingMode, in: app)
        XCTAssertTrue(mode.buttons.element(boundBy: 1).isSelected, "The Rank/Rating preference must survive reopening a profile.")
        let reloadedHeadline = element(SurroundUITestContract.AccessibilityID.profileRatingHeadline, in: app)
        XCTAssertTrue(reloadedHeadline.label.contains("1875") || reloadedHeadline.label.contains("1,875"))
        let thirteen = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("13x13"), in: app)
        XCTAssertEqual(thirteen.value as? String, "No rated games")
        tap(thirteen, description: "Select the unrated 13×13 category", in: app)
        let missingHeadline = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingHeadline, in: app)
        XCTAssertEqual(missingHeadline.label, "No rated games", "A missing category needs only its explanation, without a placeholder or subtitle.")
        keepScreenshot("Profile ratings – missing 13×13 data", in: app)
    }

    func testOwnProfileOmitsOpponentSectionsAndHonorsHiddenRatings() {
        let app = launchProfileContent(scene: .settings)
        tap(SurroundUITestContract.AccessibilityID.profileSettingsEntry, in: app)
        assertLoadedProfile(named: "JuniperStone", isOwnProfile: true, in: app)
        element(SurroundUITestContract.AccessibilityID.profileRatings, in: app)
        keepScreenshot("Own profile – supporter identity and section margins", in: app)
        for identifier in [SurroundUITestContract.AccessibilityID.profileActiveGames,
                           SurroundUITestContract.AccessibilityID.profileHeadToHead] {
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists)
        }
        _ = revealProfileControl(SurroundUITestContract.AccessibilityID.profileAllHistory, in: app)
        keepScreenshot("Own profile – ratings and game history", in: app)
        navigateBackFromPlayerProfile(in: app)
        let hideRatings = app.switches["Hide ranks and ratings"].firstMatch
        XCTAssertTrue(hideRatings.waitForExistence(timeout: 10))
        scrollIntoTappableArea(hideRatings, in: app)
        // SwiftUI includes the wide label in a switch's accessibility frame.
        // Activate the trailing switch rather than empty label space.
        activate(hideRatings, at: CGVector(dx: 0.95, dy: 0.5))
        XCTAssertTrue(waitForValue("1", in: hideRatings, timeout: 10))
        let profileEntry = element(SurroundUITestContract.AccessibilityID.profileSettingsEntry, in: app)
        scrollIntoTappableArea(profileEntry, in: app)
        tap(profileEntry, description: "Reopen own profile with ratings hidden", in: app)
        assertLoadedProfile(named: "JuniperStone", isOwnProfile: true, in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.profileRatings).firstMatch.exists,
            "Hide ranks and ratings must remove the entire rating section.")
        element(SurroundUITestContract.AccessibilityID.profileEdit, in: app)
        element(SurroundUITestContract.AccessibilityID.profileGameHistory, in: app)
    }

    func testProfileRatingsRemainUsableInDarkModeAtLargestDynamicType() {
        let app = launchProfileContent(scene: .settings, additionalLaunchArguments: [
            SurroundUITestContract.appearanceLaunchArgument, "dark",
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ])
        tap(SurroundUITestContract.AccessibilityID.profileSettingsEntry, in: app)
        let identity = element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 10), "The own-profile title remains Profile.")
        XCTAssertTrue(waitForValue("dark", in: identity, timeout: 10))
        keepScreenshot("Own profile – supporter identity in dark and largest Dynamic Type", in: app)
        let provisional = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("9x9"), in: app)
        XCTAssertTrue((provisional.value as? String ?? "").contains("Provisional"))
        tap(provisional, description: "Choose provisional category at the largest text size", in: app)
        let headline = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingHeadline, in: app)
        XCTAssertTrue(headline.label.contains("Provisional"))
        XCTAssertFalse(headline.label.contains("±"))
        keepScreenshot("Profile ratings – dark and largest Dynamic Type headline", in: app)

        _ = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingMode, in: app)
        selectSegment(at: 1, in: SurroundUITestContract.AccessibilityID.profileRatingMode, app: app)
        XCTAssertTrue(headline.label.contains("1650") || headline.label.contains("1,650"))
        let missing = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("13x13"), in: app)
        XCTAssertEqual(missing.value as? String, "No rated games")
        tap(missing, description: "Choose missing category at the largest text size", in: app)
        XCTAssertEqual(element(SurroundUITestContract.AccessibilityID.profileRatingHeadline, in: app).label, "No rated games")
        let correspondence = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("correspondence"), in: app)
        XCTAssertTrue((correspondence.value as? String ?? "").contains("1950")
            || (correspondence.value as? String ?? "").contains("1,950"))
        keepScreenshot("Profile ratings – dark and largest Dynamic Type rows", in: app)
        tap(correspondence, description: "Choose the longest category label at the largest text size", in: app)
        let finalHeadline = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingHeadline, in: app)
        XCTAssertTrue(finalHeadline.label.contains("1950") || finalHeadline.label.contains("1,950"))
        _ = revealProfileControl(SurroundUITestContract.AccessibilityID.profileHistoryGame(
            SurroundUITestContract.screenshotHistoryGameIDs[0]), in: app)
        keepScreenshot("Profile history – dark and largest Dynamic Type", in: app)
    }

    func testEmptyProfileSectionsAndIndependentCategoryRating() {
        let app = launchProfileContent(scene: .opponentPicker)
        tap(SurroundUITestContract.AccessibilityID.profilePickerEntry(
            SurroundUITestContract.profileFixturePickerFriendID), in: app, matching: .button)
        assertLoadedProfile(named: "BambooPath", in: app)
        for message in ["No active games", "No games together yet", "No finished games yet"] {
            XCTAssertTrue(app.staticTexts[message].firstMatch.waitForExistence(timeout: 10),
                          "An empty section must have a clear explanation: \(message).")
        }
        let overall = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("overall"), in: app)
        XCTAssertTrue((overall.value as? String ?? "").contains("Provisional"))
        let live = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("live"), in: app)
        XCTAssertFalse((live.value as? String ?? "").contains("Provisional"),
                       "A stable category must remain stable when the overall rating is provisional.")
        tap(live, description: "Select the independently stable live rating", in: app)
        let headline = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingHeadline, in: app)
        XCTAssertFalse(headline.label.contains("Provisional"))
        keepScreenshot("Profile – stable category despite provisional overall", in: app)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profileAllHistory].exists,
                       "An empty preview should not offer a redundant See all games action.")
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenOpponentPicker, in: app)
        assertNotSelected(SurroundUITestContract.AccessibilityID.opponentSelection(
            SurroundUITestContract.profileFixturePickerFriendID), in: app)
    }

    func testProfileSectionFailuresPreserveIdentityRatingsAndActions() {
        let app = launchProfileContent(scene: .activeGameBoard, additionalLaunchArguments: [
            SurroundUITestContract.profileSectionsUnavailableLaunchArgument,
        ])
        tap(SurroundUITestContract.AccessibilityID.profileBannerAvatarEntry(
            SurroundUITestContract.profileFixtureOpponentID), in: app, matching: .button)
        assertLoadedProfile(named: "CopperKoi", in: app)
        element(SurroundUITestContract.AccessibilityID.profileChallenge, in: app)
        element(SurroundUITestContract.AccessibilityID.profileMessage, in: app)
        element(SurroundUITestContract.AccessibilityID.profileRatings, in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.profileError).firstMatch.exists,
            "An unavailable section must not replace the loaded profile with a whole-page error.")
        for message in ["Couldn’t load active games", "Couldn’t load head-to-head record", "Couldn’t load game history"] {
            XCTAssertTrue(app.staticTexts[message].firstMatch.waitForExistence(timeout: 10),
                          "Missing section data must report its own error: \(message).")
        }
        let nine = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("9x9"), in: app)
        tap(nine, description: "Select 9×9 before retrying independent profile sections", in: app)
        let headline = element(SurroundUITestContract.AccessibilityID.profileRatingHeadline, in: app)
        let selectedHeadline = headline.label
        XCTAssertTrue(selectedHeadline.contains("Provisional"))
        for retryID in [SurroundUITestContract.AccessibilityID.profileHeadToHeadRetry,
                        SurroundUITestContract.AccessibilityID.profileActiveGamesRetry,
                        SurroundUITestContract.AccessibilityID.gameHistoryRetry] {
            let retry = revealProfileControl(retryID, in: app)
            tap(retry, description: "Retry the failed profile section", in: app)
            element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
                SurroundUITestContract.AccessibilityID.profileLoading).firstMatch.exists,
                "A section retry must retain the loaded profile instead of restarting its page load.")
            XCTAssertEqual(headline.label, selectedHeadline,
                           "A section retry must preserve the independently selected 9×9 rating category.")
            element(SurroundUITestContract.AccessibilityID.profileChallenge, in: app)
            element(SurroundUITestContract.AccessibilityID.profileMessage, in: app)
        }
        element(SurroundUITestContract.AccessibilityID.gameHistoryError, in: app)
        keepScreenshot("Profile – independent section errors retain useful content", in: app)
        _ = revealProfileControl(SurroundUITestContract.AccessibilityID.profileMessage, in: app)
        tap(SurroundUITestContract.AccessibilityID.profileMessage, in: app)
        element(SurroundUITestContract.AccessibilityID.profileConversation, in: app)
        backToProfile(from: "CopperKoi", destinationID: SurroundUITestContract.AccessibilityID.profileConversation, in: app)
        assertLoadedProfile(named: "CopperKoi", in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.profileConversation).firstMatch.exists,
            "Returning from Message must reveal the retained profile, not an unrelated history screen.")
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.gameDetail(
            SurroundUITestContract.screenshotPrimaryGameID), in: app)
    }

    func testHomeGameMenusOpenOpponentProfilesWithoutOpeningGames() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.home.rawValue,
        ])
        let games = [
            (SurroundUITestContract.screenshotPrimaryGameID,
             SurroundUITestContract.AccessibilityID.homeGame(SurroundUITestContract.screenshotPrimaryGameID),
             SurroundUITestContract.profileFixtureOpponentID, "CopperKoi"),
            (SurroundUITestContract.screenshotHistoryGameIDs[0],
             SurroundUITestContract.AccessibilityID.homeHistoryGame(SurroundUITestContract.screenshotHistoryGameIDs[0]),
             851_001, "CedarWave"),
        ]
        for (gameID, rowID, playerID, username) in games {
            let row = elementAfterScrolling(rowID, in: app)
            openProfileContextMenu(for: row, in: app)
            let profileAction = requiredMenuButton(
                SurroundUITestContract.AccessibilityID.profileGameMenuEntry(gameID, playerID),
                title: "View Profile", in: app
            )
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
                SurroundUITestContract.AccessibilityID.profileGameMenuEntry(
                    gameID, SurroundUITestContract.profileFixtureOwnerID
                )
            ).firstMatch.exists, "Game menus should offer the opponent, excluding the viewer.")
            tap(profileAction, description: "View \(username)'s profile", in: app)
            assertLoadedProfile(named: username, in: app)
            navigateBackFromPlayerProfile(in: app)
            element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
            XCTAssertTrue(row.exists)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
                SurroundUITestContract.AccessibilityID.gameDetail(gameID)
            ).firstMatch.exists, "Opening the context-menu profile must not also open the game.")
        }
    }

    func testGameHistoryMenuOpensOpponentProfile() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameHistory.rawValue,
        ])
        let gameID = SurroundUITestContract.screenshotHistoryGameIDs[0]
        let row = element(SurroundUITestContract.AccessibilityID.homeHistoryGame(gameID), in: app)
        openProfileContextMenu(for: row, in: app)
        tap(requiredMenuButton(
            SurroundUITestContract.AccessibilityID.profileGameMenuEntry(gameID, 851_001),
            title: "View Profile", in: app
        ), description: "View the historical opponent's profile", in: app)
        assertLoadedProfile(named: "CedarWave", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenGameHistory, in: app)
        XCTAssertTrue(row.exists)
        // A normal row tap must keep its existing game-navigation behavior.
        tap(row, description: "Open the historical game", in: app)
        element(SurroundUITestContract.AccessibilityID.gameDetail(gameID), in: app)
    }

    func testPublicGameMenuOffersBothPlayers() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.publicGames.rawValue,
        ])
        let gameID = SurroundUITestContract.screenshotPublicGameID
        let row = element(SurroundUITestContract.AccessibilityID.publicGame(gameID), in: app)
        for (playerID, username) in [(901_001, "MapleLeaf"), (901_002, "SilverPine")] {
            openProfileContextMenu(for: row, in: app)
            // The shared title is intentionally identical. Resolve by player
            // ID so this proves that each item selects its own participant.
            let black = element(SurroundUITestContract.AccessibilityID.profileGameMenuEntry(gameID, 901_001), in: app)
            let white = element(SurroundUITestContract.AccessibilityID.profileGameMenuEntry(gameID, 901_002), in: app)
            XCTAssertTrue(black.exists && white.exists)
            if playerID == 901_001 {
                keepScreenshot("Public game – profile actions for both players", in: app)
            }
            tap(element(
                SurroundUITestContract.AccessibilityID.profileGameMenuEntry(gameID, playerID), in: app
            ), description: "View \(username)'s profile", in: app)
            assertLoadedProfile(named: username, in: app)
            navigateBackFromPlayerProfile(in: app)
            element(SurroundUITestContract.AccessibilityID.screenPublicGames, in: app)
            XCTAssertTrue(row.exists)
        }
        tap(row, description: "Open the public game normally", in: app)
        element(SurroundUITestContract.AccessibilityID.gameDetail(gameID), in: app)
    }

    func testChallengeIdentityOpensProfileWithoutAccepting() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.openChallenges.rawValue,
        ])
        let entryID = SurroundUITestContract.AccessibilityID.profileChallengeEntry(91_001, 801_001)
        let entry = elementAfterScrolling(entryID, in: app, matching: .button)
        scrollIntoTappableArea(entry, in: app)
        keepScreenshot("Challenge card – compact profile target", in: app)
        tap(entry, description: "View the challenger", in: app)
        assertLoadedProfile(named: "BambooPath", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenOpenChallenges, in: app)
        element(entryID, in: app, matching: .button)
        XCTAssertTrue(app.buttons["Accept"].firstMatch.exists,
                      "Viewing a challenger must leave their challenge available.")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testRengoPlayerMenuOpensProfileForNonOrganizer() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.rengoOpenChallenges.rawValue,
        ])
        let prefix = SurroundUITestContract.AccessibilityID.profileRengoMenuPrefix
        let avatars = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        XCTAssertTrue(avatars.firstMatch.waitForExistence(timeout: 10))
        // The fixture's twenty challenges are grouped and sorted by clock.
        // Exercise the first visible participant, without hunting a specific
        // card across the entire challenge list.
        let avatar = avatars.allElementsBoundByIndex.first(where: { $0.isHittable })
            ?? avatars.firstMatch
        scrollIntoTappableArea(avatar, in: app)
        let menuID = avatar.identifier
        let identifiers = menuID.dropFirst(prefix.count).split(separator: ".")
        guard identifiers.count == 2,
              let challengeID = Int(identifiers[0]),
              let playerID = Int(identifiers[1]) else {
            XCTFail("Expected a Rengo menu identifying its challenge and player: \(menuID)")
            return
        }
        let playerLabel = avatar.label
        let username = playerLabel.range(of: " [", options: .backwards)
            .map { String(playerLabel[..<$0.lowerBound]) } ?? playerLabel
        tap(avatar, description: "Open the Rengo player's menu", in: app)
        let profileAction = requiredMenuButton(
            SurroundUITestContract.AccessibilityID.profileRengoEntry(challengeID, playerID),
            title: "View Profile", in: app
        )
        XCTAssertFalse(app.buttons["Move to White team"].exists)
        XCTAssertFalse(app.menuItems["Move to White team"].exists,
                       "A nonorganizer must not gain team-management actions.")
        tap(profileAction, description: "View the Rengo player's profile", in: app)
        assertLoadedProfile(named: username, in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenOpenChallenges, in: app)
        element(menuID, in: app)
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
        openProfileContextMenu(for: row, in: app)
        tap(requiredMenuButton(
            SurroundUITestContract.AccessibilityID.profileMessageMenuEntry(peerID),
            title: "View Profile", in: app
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
        tap(back, description: "Return from the conversation to the inbox", in: app)
        element(SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        element(rowID, in: app)
    }

    func testOwnProfileFromSettingsOffersAccountActions() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.settings.rawValue,
        ])
        tap(SurroundUITestContract.AccessibilityID.profileSettingsEntry, in: app)
        assertLoadedProfile(named: "JuniperStone", isOwnProfile: true, in: app)
        element(SurroundUITestContract.AccessibilityID.profileEdit, in: app)
        element(SurroundUITestContract.AccessibilityID.profileShare, in: app)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profileChallenge].exists)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profileMessage].exists)

        keepScreenshot("Own profile – loaded from Settings", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenSettings, in: app)
    }

    func testOwnProfileFromMainNavigationUsesLightAppearance() {
        assertOwnProfileAppearance(.light)
    }

    func testOwnProfileFromMainNavigationUsesDarkAppearance() {
        assertOwnProfileAppearance(.dark)
    }

    private func assertOwnProfileAppearance(_ appearance: SurroundUITestContract.Appearance) {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.appearanceLaunchArgument,
            appearance.rawValue,
        ])
        let homeSettings = app.navigationBars.buttons["Settings"].firstMatch
        if homeSettings.waitForExistence(timeout: 2) {
            tap(homeSettings, description: "Home Settings", in: app)
        } else {
            // An expanded navigation sidebar replaces the Home toolbar button.
            tap(SurroundUITestContract.AccessibilityID.navigationSettings, in: app)
        }
        element(SurroundUITestContract.AccessibilityID.screenSettings, in: app)
        tap(SurroundUITestContract.AccessibilityID.profileSettingsEntry, in: app)
        let header = element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        XCTAssertTrue(waitForValue(appearance.rawValue, in: header, timeout: 10),
                      "The profile must resolve the requested appearance, independent of the test host.")
        keepScreenshot("Own profile – \(appearance.rawValue) appearance", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenSettings, in: app)
    }

    func testGameAnalysisSurvivesTabSwitchesWithAndWithoutProfile() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .phone,
                      "This journey exercises the regular-width analysis controls and tabs.")
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.home.rawValue,
        ])
        let game = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID.homeGame(
                SurroundUITestContract.screenshotPrimaryGameID), in: app)
        scrollIntoTappableArea(game, in: app)
        tap(game, description: "Open game for analysis", in: app)
        tap(SurroundUITestContract.AccessibilityID.gameAnalyzeToggle, in: app)
        tap(SurroundUITestContract.AccessibilityID.gameAnalyzePrevious, in: app)
        let board = element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        let markerMenu = element(SurroundUITestContract.AccessibilityID.gameAnalyzeMarkerMenu, in: app)
        tap(markerMenu, description: "Choose analysis tool", in: app)
        tap(analyzeMenuItem(SurroundUITestContract.AccessibilityID.gameAnalyzeMarkerTool("letters"),
                            catalystTitle: "Letters", in: app), description: "Letters", in: app)
        let markerPoint = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        #if targetEnvironment(macCatalyst)
        markerPoint.click()
        #else
        markerPoint.tap()
        #endif
        let markedBoard = board.value as? String
        XCTAssertTrue(markedBoard?.contains("|marks:A=") == true)

        func selectTab(_ identifier: String) {
            let tabs = app.descendants(matching: .any).matching(identifier: identifier)
            if !tabs.allElementsBoundByIndex.contains(where: { $0.isHittable }) {
                tap(app.buttons["Toggle sidebar"], description: "Show navigation sidebar", in: app)
            }
            var visibleTab: XCUIElement?
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                visibleTab = tabs.allElementsBoundByIndex.first(where: { $0.isHittable })
                return visibleTab != nil
            }, object: nil)
            guard XCTWaiter.wait(for: [ready], timeout: 10) == .completed,
                  let tab = visibleTab else {
                return XCTFail("Expected a visible tab: \(identifier)")
            }
            tap(tab, description: identifier, in: app)
        }

        for profileIsOpen in [false, true] {
            if profileIsOpen {
                tap(SurroundUITestContract.AccessibilityID.profileBannerAvatarEntry(
                    SurroundUITestContract.profileFixtureOpponentID), in: app, matching: .button)
                element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
            }
            selectTab(SurroundUITestContract.AccessibilityID.navigationPublicGames)
            element(SurroundUITestContract.AccessibilityID.screenPublicGames, in: app)
            selectTab(SurroundUITestContract.AccessibilityID.navigationHome)
            if profileIsOpen {
                element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
                navigateBackFromPlayerProfile(in: app)
            }
            element(SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar, in: app)
            XCTAssertEqual(board.value as? String, markedBoard,
                           "Switching tabs must preserve the retained game's position and markers.")
            XCTAssertEqual(markerMenu.value as? String, "Letters, Next label: B")
        }
    }

    func testProfileActionsPreserveGameAnalysisAndMarkers() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameAnalysis.rawValue,
        ])
        let board = element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        let initialBoardValue = board.value as? String
        tap(SurroundUITestContract.AccessibilityID.gameAnalyzeNext, in: app)
        XCTAssertNotEqual(board.value as? String, initialBoardValue,
                          "Use a different position so a fixture reset cannot mimic preservation.")
        let markerMenu = element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeMarkerMenu,
            in: app
        )
        tap(markerMenu, description: "Analysis marker menu", in: app)
        let letters = analyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeMarkerTool("letters"),
            catalystTitle: "Letters",
            in: app
        )
        tap(letters, description: "Letters marker tool", in: app)
        let markerPoint = board.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        #if targetEnvironment(macCatalyst)
        markerPoint.click()
        #else
        markerPoint.tap()
        #endif
        let markedBoardValue = board.value as? String
        XCTAssertTrue(markedBoardValue?.contains("|marks:A=") == true)

        let opponentID = SurroundUITestContract.profileFixtureOpponentID
        #if targetEnvironment(macCatalyst)
        let profileEntryID = SurroundUITestContract.AccessibilityID
            .profileBannerAvatarEntry(opponentID)
        #else
        // Compact analysis replaces the banner with the move tree; its
        // opponent title opens the same profile without leaving analysis.
        let profileEntryID = UIDevice.current.userInterfaceIdiom == .phone
            ? SurroundUITestContract.AccessibilityID.profileGameTitleEntry(opponentID)
            : SurroundUITestContract.AccessibilityID.profileBannerAvatarEntry(opponentID)
        #endif
        tap(
            profileEntryID,
            in: app,
            matching: .button
        )
        element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        keepScreenshot("Other profile – opened from analysis", in: app)

        tap(SurroundUITestContract.AccessibilityID.profileChallenge, in: app)
        element(SurroundUITestContract.AccessibilityID.screenCustomGame, in: app)
        XCTAssertTrue(app.staticTexts["CopperKoi"].exists,
                      "Challenge should preselect the profile's player.")
        backToProfile(from: "Challenge", destinationID: SurroundUITestContract.AccessibilityID.screenCustomGame, in: app)

        tap(SurroundUITestContract.AccessibilityID.profileMessage, in: app)
        element(SurroundUITestContract.AccessibilityID.profileConversation, in: app)
        XCTAssertTrue(app.navigationBars["CopperKoi"].exists,
                      "Message should open the profile's conversation.")
        backToProfile(from: "CopperKoi", destinationID: SurroundUITestContract.AccessibilityID.profileConversation, in: app)
        navigateBackFromPlayerProfile(in: app)

        element(SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar, in: app)
        XCTAssertEqual(board.value as? String, markedBoardValue,
                       "Profile navigation must preserve the analysis position and markups.")
        XCTAssertEqual(markerMenu.value as? String, "Letters, Next label: B",
                       "The selected analysis tool must survive the profile round trip.")
    }

    func testChatSenderProfilePreservesSelectedChatPreview() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameChat.rawValue,
        ])
        dismissSoftwareKeyboardIfNeeded(in: app)
        let selectedLine = SurroundUITestContract.AccessibilityID.gameChatLine(
            "app-store-chat-1"
        )
        let otherLine = SurroundUITestContract.AccessibilityID.gameChatLine(
            "app-store-chat-2"
        )
        #if !targetEnvironment(macCatalyst)
        if UIDevice.current.userInterfaceIdiom == .phone {
            // After dismissing the keyboard, the short compact chat viewport
            // can retain an unmaterialized first lazy row even at scroll 0%.
            // Expand chat with its normal control before selecting that row.
            tap(SurroundUITestContract.AccessibilityID.gameChatBoardHide, in: app)
        }
        #endif
        tapChatItem(selectedLine, in: app, matching: .button)
        assertSelected(selectedLine, in: app)
        let selectedBubble = element(selectedLine, in: app, matching: .button)
        XCTAssertTrue(selectedBubble.label.contains("JuniperStone"),
                      "A message must announce its sender independently of the profile button.")
        XCTAssertTrue(selectedBubble.label.contains("Good luck — have a great game!"))
        #if !targetEnvironment(macCatalyst)
        if UIDevice.current.userInterfaceIdiom == .phone {
            tap(SurroundUITestContract.AccessibilityID.gameChatBoardShow, in: app)
        }
        #endif
        let board = element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        let previewValue = board.value as? String
        XCTAssertNotNil(previewValue)

        tapChatItem(
            SurroundUITestContract.AccessibilityID.profileChatEntry("app-store-chat-2"),
            in: app,
            matching: .button
        )
        element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        navigateBackFromPlayerProfile(in: app)

        assertSelected(selectedLine, in: app)
        assertNotSelected(otherLine, in: app)
        XCTAssertEqual(board.value as? String, previewValue,
                       "Opening a sender profile must keep the selected chat preview.")
    }

    func testPickerProfilePreservesSearchWithoutSelectingOpponent() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.opponentPicker.rawValue,
        ])
        let search = element(SurroundUITestContract.AccessibilityID.opponentSearch, in: app)
        tap(search, description: "Search opponents", in: app)
        search.typeText("Bamboo\n")
        XCTAssertTrue(waitForValue("Bamboo", in: search, timeout: 10))
        let playerID = SurroundUITestContract.profileFixturePickerFriendID
        let selectionID = SurroundUITestContract.AccessibilityID.opponentSelection(playerID)
        assertNotSelected(selectionID, in: app)
        tap(
            SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID),
            in: app,
            matching: .button
        )
        element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        element(SurroundUITestContract.AccessibilityID.profileSelectOpponent, in: app, matching: .button)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profileChallenge].exists)
        navigateBackFromPlayerProfile(in: app)

        element(SurroundUITestContract.AccessibilityID.screenOpponentPicker, in: app)
        XCTAssertEqual(search.value as? String, "Bamboo")
        assertNotSelected(selectionID, in: app)
        tap(selectionID, in: app, matching: .button)
        assertSelected(selectionID, in: app)
    }

    func testPickerProfilesSelectDifferentOpponentsWithoutReplacingEditedChallenge() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.customGame.rawValue,
        ])
        let draftName = "Profile draft retained"
        let name = revealCustomGameControl(SurroundUITestContract.AccessibilityID.customGameName, in: app, matching: .textField)
        tap(name, description: "Challenge game name", in: app)
        let oldName = name.value as? String ?? ""
        let trailingEdge = name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        #if targetEnvironment(macCatalyst)
        trailingEdge.click()
        #else
        trailingEdge.tap()
        #endif
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldName.count) + draftName + "\n")
        XCTAssertTrue(waitForValue(draftName, in: name, timeout: 10))

        _ = revealCustomGameControl(SurroundUITestContract.AccessibilityID.customGameSpeed, in: app, matching: .segmentedControl)
        selectSegment(at: 1, in: SurroundUITestContract.AccessibilityID.customGameSpeed, app: app)
        _ = revealCustomGameControl(SurroundUITestContract.AccessibilityID.customGameOpponentMode, in: app, matching: .segmentedControl)
        selectSegment(at: 1, in: SurroundUITestContract.AccessibilityID.customGameOpponentMode, app: app)

        for (query, playerID, username) in [
            ("Bamboo", 801_001, "BambooPath"),
            ("Misty", 801_002, "MistyMountain"),
        ] {
            let opponent = revealCustomGameControl(SurroundUITestContract.AccessibilityID.customGameOpponent, in: app, matching: .button)
            tap(opponent, description: "Choose draft opponent", in: app)
            let search = element(SurroundUITestContract.AccessibilityID.opponentSearch, in: app)
            tap(search, description: "Search draft opponents", in: app)
            search.typeText(query + "\n")
            XCTAssertTrue(waitForValue(query, in: search, timeout: 10))
            tap(SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID), in: app, matching: .button)
            element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
            XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profileChallenge].exists)
            tap(SurroundUITestContract.AccessibilityID.profileSelectOpponent, in: app, matching: .button)

            element(SurroundUITestContract.AccessibilityID.screenCustomGame, in: app)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
                SurroundUITestContract.AccessibilityID.screenPlayerProfile).firstMatch.exists)
            XCTAssertFalse(app.descendants(matching: .any)
                .matching(identifier: SurroundUITestContract.AccessibilityID.screenOpponentPicker).firstMatch.exists)
            let selectedOpponent = revealCustomGameControl(SurroundUITestContract.AccessibilityID.customGameOpponent, in: app, matching: .button)
            XCTAssertTrue(selectedOpponent.label.contains(username), "The existing draft should use the newly selected opponent.")
            let preservedName = revealCustomGameControl(SurroundUITestContract.AccessibilityID.customGameName, in: app, matching: .textField)
            XCTAssertEqual(preservedName.value as? String, draftName)
            let speed = revealCustomGameControl(SurroundUITestContract.AccessibilityID.customGameSpeed, in: app, matching: .segmentedControl)
            XCTAssertTrue(speed.buttons.element(boundBy: 1).isSelected,
                          "Profile selection must retain the draft's correspondence setting.")
        }
    }

    func testSavedSettingsProfileBackPreservesPickerWithoutSubmittingChallenge() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.preferredSettings.rawValue,
        ])
        // SwiftUI applies the card's identifier to its child buttons.
        let chooseOpponent = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label == %@",
            SurroundUITestContract.AccessibilityID.preferredSetting(0), "Select your opponent "
        )).firstMatch
        tap(chooseOpponent, description: "Choose saved-setting opponent", in: app)
        let search = element(SurroundUITestContract.AccessibilityID.opponentSearch, in: app)
        tap(search, description: "Search saved-setting opponents", in: app)
        search.typeText("Bamboo\n")
        XCTAssertTrue(waitForValue("Bamboo", in: search, timeout: 10))
        tap(SurroundUITestContract.AccessibilityID.profilePickerEntry(801_001), in: app, matching: .button)
        element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        element(SurroundUITestContract.AccessibilityID.profileChallengeWithSettings, in: app, matching: .button)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profileSelectOpponent].exists)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profileChallenge].exists)
        navigateBackFromPlayerProfile(in: app)

        element(SurroundUITestContract.AccessibilityID.screenOpponentPicker, in: app)
        XCTAssertEqual(search.value as? String, "Bamboo")
        assertNotSelected(SurroundUITestContract.AccessibilityID.opponentSelection(801001), in: app)
        let back = app.navigationBars.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "BackButton", "Preferred Settings"
        )).firstMatch
        tap(back, description: "Cancel saved-setting opponent selection", in: app)
        element(SurroundUITestContract.AccessibilityID.screenPreferredSettings, in: app)
        XCTAssertTrue(chooseOpponent.isEnabled)
    }

    func testUnavailableProfileCanRetryAndNavigateBack() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.settings.rawValue,
            SurroundUITestContract.unavailableProfileLaunchArgument,
        ])
        tap(SurroundUITestContract.AccessibilityID.profileSettingsEntry, in: app)
        element(SurroundUITestContract.AccessibilityID.profileError, in: app)
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.profileLoaded)
            .firstMatch.exists)
        tap(SurroundUITestContract.AccessibilityID.profileRetry, in: app)
        element(SurroundUITestContract.AccessibilityID.profileError, in: app)
        keepScreenshot("Profile – unavailable with retry", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenSettings, in: app)
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

        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)

        tap(SurroundUITestContract.AccessibilityID.navigationPublicGames, in: app)
        element(SurroundUITestContract.AccessibilityID.screenPublicGames, in: app)

        tap(SurroundUITestContract.AccessibilityID.navigationMessages, in: app)
        element(SurroundUITestContract.AccessibilityID.screenMessages, in: app)

        tap(SurroundUITestContract.AccessibilityID.navigationSettings, in: app)
        element(SurroundUITestContract.AccessibilityID.screenSettings, in: app)

        tap(SurroundUITestContract.AccessibilityID.navigationAbout, in: app)
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

        tap(SurroundUITestContract.AccessibilityID.navigationBrowser, in: app)
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
        let carousel = element(SurroundUITestContract.AccessibilityID.gameActiveGamesCarousel, in: app)
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
            tap(app.buttons["Toggle sidebar"], description: "Show navigation sidebar", in: app)
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
            tap(app.buttons["Toggle sidebar"], description: "Hide navigation sidebar", in: app)
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
        tap(historyGame, description: "Open a finished game from history", in: app)
        element(SurroundUITestContract.AccessibilityID.gameDetail(historyGameID), in: app)
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
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.gameBoard).firstMatch.exists)

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
        activateZenControl(
            SurroundUITestContract.AccessibilityID.gameZenEnter,
            in: app
        )
        element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        activateZenControl(
            SurroundUITestContract.AccessibilityID.gameZenExit,
            in: app
        )
        element(SurroundUITestContract.AccessibilityID.gameZenEnter, in: app)
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
        let focusAcquired = waitForChatInputFocus(in: app, timeout: 10)
        if !focusAcquired {
            keepTextInputHierarchy(
                input,
                in: app,
                reason: "keyboard preflight did not focus composer"
            )
        }
        XCTAssertTrue(
            focusAcquired,
            "Expected the compact composer to receive focus during the keyboard preflight."
        )

        enterText(
            "Keyboard preflight",
            into: resolvedChatInput(in: app),
            in: app,
            focusMode: .requireExistingFocus
        )

        dismissSoftwareKeyboardIfNeeded(in: app)
        #endif
    }

    func testCompactChatAutomaticallyFocusesComposer() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(
            "The compact composer keyboard path requires an iOS device."
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
        enterText(
            "Compact focus",
            into: input,
            in: app,
            focusMode: .requireExistingFocus
        )
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
        let board = element(
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
        let boardHidden = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: board
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [boardHidden], timeout: 10),
            .completed,
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
        element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
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
        let board = element(
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

        let boardHidden = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: board
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [boardHidden], timeout: 10),
            .completed,
            "Expected compact Variation sharing to hide the main board."
        )
        let showBoard = element(
            SurroundUITestContract.AccessibilityID.gameChatBoardShow,
            in: app,
            matching: .button
        )
        XCTAssertEqual(showBoard.label, "Show main board")

        showBoard.tap()
        element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
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
        let boardHiddenAgain = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: board
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [boardHiddenAgain], timeout: 10),
            .completed,
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
        let boardStillHidden = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: board
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [boardStillHidden], timeout: 10),
            .completed,
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
            tap(
                SurroundUITestContract.AccessibilityID.gameAnalyzeToggle,
                in: app
            )
            let analyzeControlBar = element(
                SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar,
                in: app
            )
            assertNotSelected(moveID, in: app)

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

        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeToggle,
            in: app
        )
        dismissSoftwareKeyboardIfNeeded(in: app)
        XCTAssertFalse(
            app.descendants(matching: .any)[
                SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar
            ].exists,
            "Expected the first toggle to leave Analyze mode."
        )
        assertVariationSharingDraftIsIntact(draft)
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeToggle,
            in: app
        )
        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar,
            in: app
        )
        // tapAnalysisPosition verifies the exact Button's stable selection.
        tapAnalysisPosition(draft.selectedAnalysisPosition, in: app)
        assertVariationSharingDraftIsIntact(draft)
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
        assertVariationSharingDraftIsIntact(draft)

        // tapAnalysisPosition verifies the exact Button's stable selection.
        tapAnalysisPosition(draft.selectedAnalysisPosition, in: app)
        assertVariationSharingDraftIsIntact(draft)
    }

    func testVariationSharingDraftSurvivesZenModeRoundTrip() {
        let draft = beginVariationSharingDraft(named: "Persistent variation")
        let app = draft.app

        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeToggle,
            in: app
        )
        dismissSoftwareKeyboardIfNeeded(in: app)
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
        let detailDismissalPoint = popoverDismissalPoint(in: app, navigationTitle: "vs ")
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
        dismissPopover(
            in: app,
            at: detailDismissalPoint,
            containing: replacingAddItem,
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
        dismissPopover(
            in: app,
            at: detailDismissalPoint,
            containing: addAfterRemoval,
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
            XCTWaiter.wait(for: [restoredConditionalState], timeout: 10),
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
        XCTAssertGreaterThan(
            quickRemoveAfterAdd.frame.width,
            44,
            "The shortcut should visibly include its short Remove label."
        )
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
        XCTAssertGreaterThan(
            quickAddAfterRemoval.frame.width,
            44,
            "The shortcut should visibly include its short Add label."
        )
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

        #if !targetEnvironment(macCatalyst)
        let keyboard = app.keyboards.firstMatch
        let keyboardFrame = keyboard.exists ? keyboard.frame : .zero
        let appFrame = app.frame
        // Floating keyboards and hardware-keyboard strips leave the regular
        // Analyze toolbar visible. XCTest's docked keyboard bounds can stop
        // a few points above the screen edge.
        if keyboardFrame.height > 100,
           abs(keyboardFrame.minX - appFrame.minX) <= 1,
           abs(keyboardFrame.width - appFrame.width) <= 1,
           abs(keyboardFrame.maxY - appFrame.maxY) <= 10 {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Retained Analyze toolbar with keyboard"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            XCTAssertFalse(
                app.buttons[
                    SurroundUITestContract.AccessibilityID.gameAnalyzePrevious
                ].isHittable,
                "Hidden Analyze actions must not accept interaction while the keyboard is visible."
            )
            dismissSoftwareKeyboardIfNeeded(in: app)
            XCTAssertTrue(
                element(
                    SurroundUITestContract.AccessibilityID.gameAnalyzePrevious,
                    in: app,
                    matching: .button
                ).isHittable,
                "The Analyze toolbar must become usable again after keyboard dismissal."
            )
            assertSelected(selectedIdentifier, in: app)
        }
        #endif
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
        dismissSoftwareKeyboardIfNeeded(in: app)
        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar,
            in: app
        )
        assertSelected(selectedIdentifier, in: app)
    }

    func testPlaybackControlBarOnlyShowsPreviousAndNext() {
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
        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar,
            in: app
        )
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
