//
//  SurroundJourneyUITestCase.swift
//  SurroundUITests
//
//  Launch, element-resolution, and navigation helpers shared by the offline
//  journey suites. The screenshot suites keep their own private versions of
//  several of these names, so they live below `SurroundUITestCase`.
//

import XCTest
import UIKit

class SurroundJourneyUITestCase: SurroundUITestCase {
    enum ScrollRevealAxis {
        case horizontal
        case vertical
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    var animationDiagnosticsEnabled: Bool {
        ProcessInfo.processInfo.environment[
            "SURROUND_UI_ANIMATION_DIAGNOSTICS"
        ] == "1"
    }

    func traceAnimationTest(_ event: String) {
        guard animationDiagnosticsEnabled else { return }
        let message =
            "[SurroundAnimationTest] \(event) uptime=\(ProcessInfo.processInfo.systemUptime)\n"
        FileHandle.standardOutput.write(Data(message.utf8))
    }

    func launchApp(
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
    func element(
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

    // iPadOS 27 no longer forwards SwiftUI accessibility identifiers to the
    // buttons inside a presented Menu. They keep only their label, which can
    // append a subtitle ("Title, subtitle") or a count ("Title (2)"). Match
    // the identifier, or else an unidentified button or menu item with that
    // title, so identifiable controls outside the menu never match by label.
    func menuButton(
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
    func requiredMenuButton(
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

    func unresolvedAnalyzeMenuItem(
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
    func analyzeMenuItem(
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

    func tap(
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

    func tap(
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

    func activate(_ element: XCUIElement) {
        #if targetEnvironment(macCatalyst)
        element.click()
        #else
        element.tap()
        #endif
    }

    func waitUntilHittable(
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
    func revealChatItem(
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

    func tapChatItem(
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

    func hasTappableInteractionPoint(
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

    func validInteractionFrame(
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

    func dragScrollView(
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

    func activate(
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

    func keepInteractionHierarchy(
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

    // Deadlines, not sleeps: each wait returns as soon as its condition holds.
    // On hosted runners a single accessibility query can hang for about nine
    // seconds before XCTest retries it, which used up the old 5- and 10-second
    // windows while the app had already reached the expected state.
    let stateSettleTimeout: TimeInterval = 30

    func waitForValue(
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

    func assertSelected(
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

    func assertNotSelected(
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

    func scrollIntoTappableArea(
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
    func elementAfterScrolling(
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

    func keepScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(
            screenshot: XCUIScreen.main.screenshot(),
            quality: .original
        )
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func popoverDismissalPoint(
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

    func dismissPopover(
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

    func navigateBackFromPlayerProfile(
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
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: stateSettleTimeout), .completed,
                       "Back must pop the profile and reveal its originating page.",
                       file: file, line: line)
    }

    // Home pins its section headers over the grid, so a row that scrolling
    // left near the top can sit almost entirely under a header. A long press
    // then reaches the row's thin visible edge and opens the game instead of
    // the context menu. Center the row before pressing, and if the press
    // still opens its destination, return and press again, holding longer.
    @discardableResult
    func openProfileContextMenu(
        for row: XCUIElement,
        expecting accessibilityIdentifier: String,
        title: String = "View Profile",
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let menuItem = menuButton(accessibilityIdentifier, title: title, in: app)
        let pressDurations: [TimeInterval] = [1, 2.5, 2.5]
        for (attempt, pressDuration) in pressDurations.enumerated() {
            scrollIntoTappableArea(row, in: app)
            XCTAssertTrue(row.isHittable, "The row must be visible before opening its context menu.",
                          file: file, line: line)
            #if targetEnvironment(macCatalyst)
            row.rightClick()
            #else
            centerInScrollContainer(row, in: app)
            row.press(forDuration: pressDuration)
            #endif
            if attempt == pressDurations.count - 1 || menuItem.waitForExistence(timeout: 10) { break }
            guard !(row.exists && row.isHittable) else { continue }
            // A Back tap can be ignored while the pushed screen settles.
            for _ in 0..<2 {
                guard let back = backButtonOfPushedScreen(in: app) else { break }
                tap(back, description: "Return from the row's destination", in: app, file: file, line: line)
                if row.waitForExistence(timeout: 10) { break }
            }
            XCTAssertTrue(row.exists, "The row must reappear after leaving its destination.", file: file, line: line)
        }
        return requiredMenuButton(accessibilityIdentifier, title: title, in: app, file: file, line: line)
    }

    // Moves the row into the middle of the innermost scroll view, list, or
    // table that contains it, clear of pinned headers and bottom bars. Rows
    // at either end of their content stay where scrolling leaves them.
    private func centerInScrollContainer(_ row: XCUIElement, in app: XCUIApplication) {
        let containsRow = NSPredicate(format: "identifier == %@", row.identifier)
        let containers = [app.scrollViews, app.collectionViews, app.tables]
            .flatMap { $0.containing(containsRow).allElementsBoundByIndex }
            .filter { !$0.frame.isEmpty }
        guard let container = containers.min(by: {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }) else { return }
        let center = CGVector(dx: 0.5, dy: 0.5)
        for _ in 0..<4 {
            let viewport = container.frame.intersection(app.frame)
            let rowFrame = row.frame
            let middle = viewport.insetBy(dx: 0, dy: viewport.height * 0.3)
            if middle.contains(CGPoint(x: middle.midX, y: rowFrame.midY)) { return }
            guard dragScrollView(
                container,
                axis: .vertical,
                targetFrame: validInteractionFrame(rowFrame, interactionPoint: center),
                containerFrame: viewport,
                interactionPoint: center
            ), row.frame != rowFrame else { return }
        }
    }

    // UIKit identifies the back control on recent systems. Older releases
    // leave it as the unidentified first button of the titled bar.
    private func backButtonOfPushedScreen(in app: XCUIApplication) -> XCUIElement? {
        let identifiedBack = app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch
        if identifiedBack.exists {
            return identifiedBack
        }
        return app.navigationBars.allElementsBoundByIndex
            .last { !$0.identifier.isEmpty }?
            .buttons.firstMatch
    }

    func assertLoadedProfile(
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
}
