//
//  SurroundUITests.swift
//  SurroundUITests
//
//  Created by Anh Khoa Hong on 6/30/20.
//

import XCTest
import UIKit

final class SurroundUITests: XCTestCase {
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

    private func scrollIntoTappableArea(
        _ element: XCUIElement,
        in app: XCUIApplication
    ) {
        for _ in 0..<4 {
            #if targetEnvironment(macCatalyst)
            let overlapsTabBar = false
            #else
            let overlapsTabBar = element.frame.maxY > app.frame.maxY - 100
            #endif
            guard !element.isHittable || overlapsTabBar else {
                return
            }
            app.swipeUp()
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
        XCTAssertFalse(
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
