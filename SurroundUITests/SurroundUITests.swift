//
//  SurroundUITests.swift
//  SurroundUITests
//
//  Created by Anh Khoa Hong on 6/30/20.
//

import XCTest
import UIKit

final class SurroundUITests: SurroundUITestCase {
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

    @discardableResult
    private func analyzeMenuItem(
        _ accessibilityIdentifier: String,
        catalystTitle: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        #if targetEnvironment(macCatalyst)
        let menuItems = app.descendants(matching: .menuItem)
        let exactTitleItem = menuItems
            .matching(identifier: catalystTitle)
            .firstMatch
        if exactTitleItem.exists {
            return exactTitleItem
        }

        let compatibleItem = menuItems.matching(
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
        let appeared = compatibleItem.waitForExistence(timeout: 10)
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
        return compatibleItem
        #else
        return element(
            accessibilityIdentifier,
            in: app,
            matching: .button,
            file: file,
            line: line
        )
        #endif
    }

    private func tapAnalyzeMenuItem(
        _ accessibilityIdentifier: String,
        catalystTitle: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
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
        #if targetEnvironment(macCatalyst)
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
        #else
        tap(
            accessibilityIdentifier,
            in: app,
            matching: .button,
            file: file,
            line: line
        )
        #endif
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
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: element
        )
        let result = XCTWaiter.wait(for: [hittable], timeout: 10)
        if result != .completed {
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
            result,
            .completed,
            "Expected \(description) to be hittable",
            file: file,
            line: line
        )
        #if targetEnvironment(macCatalyst)
        element.click()
        #else
        element.tap()
        #endif
    }

    private func enterText(
        _ text: String,
        into textField: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        tap(
            textField,
            description: SurroundUITestContract.AccessibilityID.gameChatInput,
            in: app,
            file: file,
            line: line
        )

        #if !targetEnvironment(macCatalyst)
        let focused = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasFocus == true"),
            object: textField
        )
        let focusResult = XCTWaiter.wait(for: [focused], timeout: 10)
        if focusResult != .completed {
            keepTextInputHierarchy(
                textField,
                in: app,
                reason: "chat composer not focused"
            )
        }
        XCTAssertEqual(
            focusResult,
            .completed,
            "Expected the chat composer to accept keyboard input",
            file: file,
            line: line
        )
        #endif

        textField.typeText(text)

        let completeValue = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", text),
            object: textField
        )
        let result = XCTWaiter.wait(for: [completeValue], timeout: 5)
        if result != .completed {
            keepTextInputHierarchy(
                textField,
                in: app,
                reason: "incomplete chat composer input"
            )
        }
        XCTAssertEqual(
            result,
            .completed,
            "Expected the chat composer value to become \(text.debugDescription); actual value: \(String(describing: textField.value))",
            file: file,
            line: line
        )
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
            app.swipeUp()
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

    private func dismissPopover(in app: XCUIApplication) {
        #if targetEnvironment(macCatalyst)
        let outside = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.02, dy: 0.98)
        )
        outside.click()
        #else
        let outside = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.02, dy: 0.12)
        )
        outside.tap()
        #endif
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
        element(SurroundUITestContract.AccessibilityID.screenAbout, in: app)

        tap(SurroundUITestContract.AccessibilityID.navigationBrowser, in: app)
        element(SurroundUITestContract.AccessibilityID.screenBrowser, in: app)

        tap(SurroundUITestContract.AccessibilityID.navigationHome, in: app)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
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
        element(
            SurroundUITestContract.AccessibilityID.gameResign,
            in: app
        )
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
        input.typeText("Compact focus")
        XCTAssertEqual(input.value as? String, "Compact focus")
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
        let selectedPosition = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND selected == true",
                "game.analysis.position."
            )
        ).firstMatch
        XCTAssertTrue(
            selectedPosition.waitForExistence(timeout: 10),
            "Expected branch navigation to select a shareable variation."
        )
        let selectedIdentifier = selectedPosition.identifier
        XCTAssertFalse(selectedIdentifier.isEmpty)
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

        tap(firstLineID, in: app, matching: .button)
        assertSelected(firstLineID, in: app)
        tap(firstLineID, in: app, matching: .button)
        assertNotSelected(firstLineID, in: app)

        tap(firstLineID, in: app, matching: .button)
        tap(secondLineID, in: app, matching: .button)
        assertNotSelected(firstLineID, in: app)
        assertSelected(secondLineID, in: app)

        let chatLog = element(
            SurroundUITestContract.AccessibilityID.gameChatLog,
            in: app,
            matching: .scrollView
        )
        let secondLine = element(
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

        let moveID = SurroundUITestContract.AccessibilityID.gameChatMove(42)
        tap(moveID, in: app, matching: .button)
        assertSelected(moveID, in: app)
        tap(firstLineID, in: app, matching: .button)
        assertNotSelected(moveID, in: app)
        assertSelected(firstLineID, in: app)

        #if targetEnvironment(macCatalyst)
        let usesRegularGameLayout = true
        #else
        let usesRegularGameLayout = UIDevice.current.userInterfaceIdiom == .pad
        #endif
        if usesRegularGameLayout {
            tap(moveID, in: app, matching: .button)
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

            tap(moveID, in: app, matching: .button)
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

    func testVariationSharingDraftSurvivesNavigationAndCanBeReplaced() {
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

        tap(selectedIdentifier, in: app)
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu,
            in: app
        )
        tapAnalyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeShare,
            catalystTitle: "Share variation in chat",
            in: app
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
        let frozenPreviewValue = sharingPreview.value as? String
        XCTAssertNotNil(frozenPreviewValue)
        let variationName = "Persistent variation"
        let variationNameInput = element(
            SurroundUITestContract.AccessibilityID.gameChatInput,
            in: app,
            matching: .textField
        )
        enterText(variationName, into: variationNameInput, in: app)
        dismissSoftwareKeyboardIfNeeded(in: app)
        let mainBoard = element(
            SurroundUITestContract.AccessibilityID.gameBoard,
            in: app
        )
        let sharedSourceBoardValue = mainBoard.value as? String
        XCTAssertNotNil(sharedSourceBoardValue)

        func assertSharingDraftIsIntact(
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertTrue(
                sharingTitle.exists,
                "Expected Variation sharing to remain active.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                sharingPreview.value as? String,
                frozenPreviewValue,
                "Expected the composer preview to remain frozen.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                element(
                    SurroundUITestContract.AccessibilityID.gameChatInput,
                    in: app,
                    matching: .textField,
                    file: file,
                    line: line
                ).value as? String,
                variationName,
                "Expected the draft variation name to be preserved.",
                file: file,
                line: line
            )
        }

        let lineID = SurroundUITestContract.AccessibilityID.gameChatLine(
            "app-store-chat-1"
        )
        tap(lineID, in: app, matching: .button)
        assertSelected(lineID, in: app)
        let plainChatLineBoardValue = mainBoard.value as? String
        XCTAssertNotNil(plainChatLineBoardValue)
        XCTAssertEqual(
            plainChatLineBoardValue,
            "position:48:fk",
            "Expected a plain chat line to render the current-game fallback board."
        )
        assertSharingDraftIsIntact()

        tap(lineID, in: app, matching: .button)
        assertNotSelected(lineID, in: app)
        XCTAssertEqual(
            mainBoard.value as? String,
            plainChatLineBoardValue,
            "Expected plain-line deselection to preserve the fallback board."
        )
        assertSharingDraftIsIntact()

        let moveID = SurroundUITestContract.AccessibilityID.gameChatMove(42)
        tap(moveID, in: app, matching: .button)
        assertSelected(moveID, in: app)
        XCTAssertNotEqual(
            mainBoard.value as? String,
            sharedSourceBoardValue,
            "Expected a chat move selection to control the main board independently of the frozen composer preview."
        )
        assertSharingDraftIsIntact()

        tap(moveID, in: app, matching: .button)
        assertNotSelected(moveID, in: app)
        assertSharingDraftIsIntact()

        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeToggle,
            in: app
        )
        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar,
            in: app
        )
        tap(selectedIdentifier, in: app)
        assertSelected(selectedIdentifier, in: app)
        let selectedAnalyzeBoardValue = mainBoard.value as? String
        XCTAssertNotNil(selectedAnalyzeBoardValue)
        assertSharingDraftIsIntact()
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzePrevious,
            in: app,
            matching: .button
        )
        assertSelected(parentIdentifier, in: app)
        XCTAssertNotEqual(
            mainBoard.value as? String,
            selectedAnalyzeBoardValue,
            "Expected Analyze navigation to update the main board independently of the frozen composer preview."
        )
        assertSharingDraftIsIntact()

        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeToggle,
            in: app
        )
        assertSharingDraftIsIntact()
        activateZenControl(
            SurroundUITestContract.AccessibilityID.gameZenEnter,
            in: app
        )
        element(SurroundUITestContract.AccessibilityID.gameZenExit, in: app)
        activateZenControl(
            SurroundUITestContract.AccessibilityID.gameZenExit,
            in: app
        )
        element(
            SurroundUITestContract.AccessibilityID.gameVariationSharePreview,
            in: app
        )
        dismissSoftwareKeyboardIfNeeded(in: app)
        element(
            SurroundUITestContract.AccessibilityID.gameZenEnter,
            in: app,
            matching: .button
        )
        assertSharingDraftIsIntact()
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeToggle,
            in: app
        )
        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar,
            in: app
        )
        tap(parentIdentifier, in: app)
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu,
            in: app
        )
        tapAnalyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeShare,
            catalystTitle: "Share variation in chat",
            in: app
        )

        let replacementPreview = element(
            SurroundUITestContract.AccessibilityID.gameVariationSharePreview,
            in: app
        )
        XCTAssertNotEqual(
            replacementPreview.value as? String,
            frozenPreviewValue,
            "Sharing another branch should replace the frozen composer preview."
        )
        let replacementName = "Replacement variation"
        let replacementNameInput = element(
            SurroundUITestContract.AccessibilityID.gameChatInput,
            in: app,
            matching: .textField
        )
        enterText(replacementName, into: replacementNameInput, in: app)
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
        let firstLine = element(
            firstLineID,
            in: app,
            matching: .button
        )

        firstLine
            .coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)
            )
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
        XCTAssertEqual(topBoardFrame.minY, noPlanBoardFrame.minY, accuracy: 1)
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

        dismissPopover(in: app)
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: homePopover
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [dismissed], timeout: 10),
            .completed,
            "Expected the Home conditional popover to dismiss."
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
        tap(conflictingNodeIdentifier, in: app)
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
        dismissPopover(in: app)
        tap(selectedNodeIdentifier, in: app)
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
        dismissPopover(in: app)
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

        tap(conflictingNodeIdentifier, in: app)
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
        tap(selectedNodeIdentifier, in: app)
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

    func testAnalyzeControlBarNavigatesSharesAndDeletesBranch() {
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

        tap(selectedIdentifier, in: app)
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
        tap(selectedIdentifier, in: app)
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
        let frozenPreviewValue = sharingPreview.value as? String
        XCTAssertNotNil(frozenPreviewValue)
        let variationNameInput = element(
            SurroundUITestContract.AccessibilityID.gameChatInput,
            in: app,
            matching: .textField
        )
        XCTAssertEqual(variationNameInput.label, "Variation name...")
        enterText(
            "Focused variation",
            into: variationNameInput,
            in: app
        )
        dismissSoftwareKeyboardIfNeeded(in: app)
        element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar,
            in: app
        )
        assertSelected(selectedIdentifier, in: app)

        func assertSharingDraftIsIntact(
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertTrue(
                sharingTitle.exists,
                "Expected Variation sharing to remain active.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                sharingPreview.value as? String,
                frozenPreviewValue,
                "Expected Analyze navigation to preserve the shared variation preview.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                element(
                    SurroundUITestContract.AccessibilityID.gameChatInput,
                    in: app,
                    matching: .textField,
                    file: file,
                    line: line
                ).value as? String,
                "Focused variation",
                "Expected Analyze navigation to preserve the draft name.",
                file: file,
                line: line
            )
        }

        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzePrevious,
            in: app,
            matching: .button
        )
        assertSelected(parentIdentifier, in: app)
        assertSharingDraftIsIntact()

        tap(selectedIdentifier, in: app)
        assertSelected(selectedIdentifier, in: app)
        assertSharingDraftIsIntact()
        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzePrevious,
            in: app,
            matching: .button
        )
        assertSelected(parentIdentifier, in: app)
        assertSharingDraftIsIntact()

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
            object: sharingPreview
        )
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [sharingTitleGone, sharingPreviewGone],
                timeout: 10
            ),
            .completed,
            "Expected Cancel to dismiss the Variation sharing composer."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)[
                SurroundUITestContract.AccessibilityID
                    .gameVariationShareCancel
            ].exists
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
        assertSelected(parentIdentifier, in: app)

        tap(selectedIdentifier, in: app)
        assertSelected(selectedIdentifier, in: app)

        tap(
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu,
            in: app
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

        tap(selectedIdentifier, in: app)
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
        let preview = element(
            SurroundUITestContract.AccessibilityID.gameVariationSharePreview,
            in: app
        )
        XCTAssertTrue(
            (preview.value as? String)?.contains(":|marks:A=") == true,
            "Expected a zero-move variation preview containing the marker."
        )
        tap(
            SurroundUITestContract.AccessibilityID.gameVariationShareCancel,
            in: app,
            matching: .button
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
        element(
            SurroundUITestContract.AccessibilityID.gameNext,
            in: app
        )
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(
                    identifier: SurroundUITestContract.AccessibilityID.gameResign
                )
                .firstMatch
                .exists,
            "Finished game actions should not offer Resign."
        )
        tap(
            SurroundUITestContract.AccessibilityID.gameNext,
            in: app
        )
        element(
            SurroundUITestContract.AccessibilityID.gameDetail(
                SurroundUITestContract.screenshotPrimaryGameID
            ),
            in: app
        )
    }
}
