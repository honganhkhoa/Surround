//
//  GameContinuityUITests.swift
//  SurroundUITests
//
//  Keep game state alive while the same route adapts between compact/regular layouts.
//  These tests run in the composer phase because some transitions own focus.
//

import XCTest
import UIKit

final class GameContinuityUITests: SurroundJourneyUITestCase {
    private typealias ID = SurroundUITestContract.AccessibilityID

    override func setUpWithError() throws {
        try super.setUpWithError()
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("These layout transitions exercise the iOS game layouts.")
        #endif
    }

    private func launchContinuityScene(
        _ scene: SurroundUITestContract.CompatibilityScene,
        additionalLaunchArguments: [String] = []
    ) -> XCUIApplication {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            scene.rawValue,
            GameLayoutUITestContract.launchArgument,
        ] + additionalLaunchArguments)
        element(GameLayoutUITestContract.current, in: app)
        XCTAssertEqual(
            element(GameLayoutUITestContract.current, in: app).label,
            "regular"
        )
        element(ID.gameBoard, in: app)
        return app
    }

    private func launchNativeGame(additionalLaunchArguments: [String] = []) -> XCUIApplication {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.activeGameBoard.rawValue,
        ] + additionalLaunchArguments)
        element(ID.gameBoard, in: app)
        return app
    }

    private func changeLayout(
        toCompact compact: Bool,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        tap(
            compact ? GameLayoutUITestContract.compact
                : GameLayoutUITestContract.regular,
            in: app,
            matching: .button,
            file: file,
            line: line
        )
        assertProperty(
            "label", equals: compact ? "compact" : "regular",
            of: element(GameLayoutUITestContract.current, in: app),
            file: file, line: line
        )
        if app.buttons[ID.gameZenExit].exists {
            XCTAssertFalse(gameAnalyzeControl(in: app).exists,
                           "Zen keeps the native mode controls hidden while adapting.")
            return
        }
        // Native overflow can remove the toolbar toggle from accessibility.
        // The game content remains the stable owner through the size change.
        XCTAssertTrue(
            pollUntil(timeout: 10) {
                app.descendants(matching: .any).matching(identifier: ID.gameBoard).firstMatch.exists
                    || app.scrollViews[ID.gameChatLog].exists
            },
            "Expected the retained game content after the requested layout change.",
            file: file, line: line
        )
    }

    private func assertProperty(
        _ property: String,
        equals value: String,
        of element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let matches = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "%K == %@", property, value),
            object: element
        )
        XCTAssertEqual(
            waitWithFinalCheck(for: [matches], timeout: 10), .completed,
            "Expected \(property) to remain \(value.debugDescription).",
            file: file, line: line
        )
    }

    private func boardValue(in app: XCUIApplication) throws -> String {
        try XCTUnwrap(element(ID.gameBoard, in: app).value as? String)
    }

    private func typeDraft(_ text: String, in app: XCUIApplication) {
        openGameChat(in: app)
        let input = element(ID.gameChatInput, in: app, matching: .textField)
        if !chatInputHasKeyboardFocus(in: app) {
            tap(input, description: "chat composer", in: app)
        }
        input.typeText(text)
        assertProperty("value", equals: text, of: input)
    }

    private func selectPersonalChannel(in app: XCUIApplication) {
        openGameChat(in: app)
        tap(ID.gameChatChannelPicker, in: app)
        tap(
            requiredMenuButton(
                ID.gameChatChannelPersonal, title: "Personal", in: app
            ),
            description: "Personal chat channel", in: app
        )
    }

    func testChatVariationPreviewKeepsAnExitAcrossLayouts() throws {
        let app = launchContinuityScene(.activeGameBoard)
        let liveBoard = try boardValue(in: app)
        tapChatItem(
            ID.gameChatLine("app-store-chat-variation"),
            in: app, matching: .button
        )
        let previewBoard = try boardValue(in: app)
        XCTAssertEqual(previewBoard, "variation:91:ii-hh-hi-cq")
        element("game.chat.preview.return", in: app, matching: .button)

        changeLayout(toCompact: true, in: app)
        assertProperty(
            "value", equals: previewBoard, of: element(ID.gameBoard, in: app)
        )
        tap("game.chat.preview.return", in: app, matching: .button)
        assertProperty(
            "value", equals: liveBoard, of: element(ID.gameBoard, in: app)
        )
        XCTAssertFalse(app.buttons["game.chat.preview.return"].exists)

        changeLayout(toCompact: false, in: app)
        assertProperty(
            "value", equals: liveBoard, of: element(ID.gameBoard, in: app)
        )
    }

    func testCompactChatChangesPreserveTheRegularChatPreference() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad,
                      "This journey needs room for the regular game layout.")
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.home.rawValue,
            GameLayoutUITestContract.launchArgument,
        ])
        let gameID = SurroundUITestContract.screenshotPrimaryGameID

        func openGame() {
            let entry = element(ID.homeGamePlayerInfo(gameID), in: app)
            scrollIntoTappableArea(entry, in: app)
            tap(entry, description: "Open the fixture game", in: app)
            element(ID.gameDetail(gameID), in: app)
            element(ID.gameBoard, in: app)
        }

        func reopenInRegularLayout() {
            // Compact Chat can focus the composer. End input before leaving
            // so the navigation control remains accessible on a small layout.
            if chatInputHasKeyboardFocus(in: app) {
                dismissSoftwareKeyboardIfNeeded(in: app)
            }
            let backs = app.buttons.matching(NSPredicate(
                format: "identifier == %@ OR label == %@ OR label == %@",
                "BackButton", "Active games", "Back"
            ))
            var back: XCUIElement?
            let visibleBack = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                back = backs.allElementsBoundByIndex.first(where: { $0.isHittable })
                return back != nil
            }, object: nil)
            XCTAssertEqual(waitWithFinalCheck(for: [visibleBack], timeout: 10), .completed,
                           "Expected the game's visible Back control.")
            guard let back else { return }
            tap(back, description: "Return to Home", in: app)
            element(ID.screenHome, in: app)
            tap(GameLayoutUITestContract.regular, in: app, matching: .button)
            assertProperty("label", equals: "regular",
                           of: element(GameLayoutUITestContract.current, in: app))
            openGame()
        }

        openGame()
        openGameChat(in: app)
        changeLayout(toCompact: true, in: app)
        setGameChatVisible(false, in: app)
        reopenInRegularLayout()
        element(ID.gameChatLog, in: app)
        XCTAssertTrue(gameToolbarToggleIsOn(gameChatControl(in: app)),
                      "Closing Chat in compact layout must preserve the saved regular open state.")

        setGameChatVisible(false, in: app)
        changeLayout(toCompact: true, in: app)
        openGameChat(in: app)
        reopenInRegularLayout()
        XCTAssertFalse(app.scrollViews[ID.gameChatLog].exists,
                       "Opening Chat in compact layout must preserve the saved regular closed state.")
        XCTAssertFalse(gameToolbarToggleIsOn(gameChatControl(in: app)))
    }

    func testMovePreviewKeepsAnExitAcrossLayouts() throws {
        let app = launchContinuityScene(.activeGameBoard)
        let liveBoard = try boardValue(in: app)
        tapChatItem(ID.gameChatMove(91), in: app, matching: .button)
        let previewBoard = try boardValue(in: app)
        XCTAssertNotEqual(previewBoard, liveBoard)

        changeLayout(toCompact: true, in: app)
        assertProperty(
            "value", equals: previewBoard, of: element(ID.gameBoard, in: app)
        )
        changeLayout(toCompact: false, in: app)
        tap("game.chat.preview.return", in: app, matching: .button)
        assertProperty(
            "value", equals: liveBoard, of: element(ID.gameBoard, in: app)
        )
    }

    func testInitialAnalyzeStateStartsAtCurrentPositionWithoutFixtureReseeding() throws {
        let liveApp = launchNativeGame()
        let currentBoard = try boardValue(in: liveApp)
        liveApp.terminate()

        // The scene initializes GameDetailInteraction(panel: .analyze), but
        // never assigns SingleGameView's selected position or toggles its mode.
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.initialGameAnalysis.rawValue,
        ])
        element(ID.gameAnalyzeControlBar, in: app)
        assertProperty("value", equals: currentBoard, of: element(ID.gameBoard, in: app))
        let previous = element(ID.gameAnalyzePrevious, in: app, matching: .button)
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: previous
        )
        XCTAssertEqual(
            waitWithFinalCheck(for: [enabled], timeout: 10), .completed,
            "Initial Analyze must select the current position before any user interaction."
        )

        tap(previous, description: "Explore the previous move", in: app)
        XCTAssertNotEqual(try boardValue(in: app), currentBoard)
        tap(ID.gameAnalyzeNext, in: app, matching: .button)
        assertProperty("value", equals: currentBoard, of: element(ID.gameBoard, in: app))
    }

    func testAnalyzeOffAndOnPreservesPositionAndToolInBothLayouts() throws {
        for compact in [false, true] {
            let app = compact ? launchContinuityScene(.activeGameBoard) : launchNativeGame()
            let liveBoard = try boardValue(in: app)
            if compact { changeLayout(toCompact: true, in: app) }
            func setAnalyzing(_ analyzing: Bool) {
                setGameAnalyzing(analyzing, in: app)
            }
            setAnalyzing(true)
            tap(ID.gameAnalyzePrevious, in: app, matching: .button)
            let exploredBoard = try boardValue(in: app)
            XCTAssertNotEqual(exploredBoard, liveBoard)
            tap(ID.gameAnalyzeMarkerMenu, in: app)
            tap(analyzeMenuItem(ID.gameAnalyzeMarkerTool("letters"), catalystTitle: "Letters", in: app),
                description: "Letters marker tool", in: app)

            let selectedTool = try XCTUnwrap(element(ID.gameAnalyzeMarkerMenu, in: app).value as? String)
            setAnalyzing(false)
            assertProperty("value", equals: liveBoard, of: element(ID.gameBoard, in: app))
            setAnalyzing(true)
            assertProperty("value", equals: exploredBoard, of: element(ID.gameBoard, in: app))
            assertProperty("value", equals: selectedTool, of: element(ID.gameAnalyzeMarkerMenu, in: app))
            setAnalyzing(false)
            app.terminate()
        }
    }

    func testFocusedChatProfileRoundTripKeepsDraftWithoutRestoringKeyboard() {
        let app = launchNativeGame()
        let draft = "Keep this draft while viewing the player"
        typeDraft(draft, in: app)
        let avatar = element(ID.profileBannerAvatarEntry(SurroundUITestContract.profileFixtureOpponentID),
                             in: app, matching: .button)
        let profile = app.descendants(matching: .any).matching(identifier: ID.profileLoaded).firstMatch
        tap(avatar, description: "Opponent avatar", in: app)
        if !profile.waitForExistence(timeout: 5) {
            // With the on-screen keyboard up, a first tap outside chat only
            // ends editing; it must not also act on what it lands on.
            XCTAssertFalse(chatInputHasKeyboardFocus(in: app))
            tap(avatar, description: "Opponent avatar", in: app)
        }
        element(ID.profileLoaded, in: app)
        navigateBackFromPlayerProfile(in: app)

        let input = element(ID.gameChatInput, in: app, matching: .textField)
        assertProperty("value", equals: draft, of: input)
        XCTAssertFalse(chatInputHasKeyboardFocus(in: app))
        tap(input, description: "Resume the retained draft", in: app)
        input.typeText(".")
        // A deliberate tap places the caret at the tapped point, which need
        // not be the end of the retained text. Verify editing preserves it.
        let edited = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = input.value as? String else { return false }
            return value.count == draft.count + 1
                && value.replacingOccurrences(of: ".", with: "") == draft
        }, object: nil)
        XCTAssertEqual(waitWithFinalCheck(for: [edited], timeout: 10), .completed)
    }

    func testFocusedChatTabRoundTripKeepsDraftWithoutRestoringKeyboard() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.home.rawValue,
        ])
        let gameEntry = element(ID.homeGamePlayerInfo(SurroundUITestContract.screenshotPrimaryGameID), in: app)
        for _ in 0..<6 where !gameEntry.isHittable { app.swipeUp() }
        tap(gameEntry, description: "Open the fixture game", in: app)
        element(ID.gameBoard, in: app)
        let draft = "Keep this draft while checking Settings"
        typeDraft(draft, in: app)
        #if !targetEnvironment(macCatalyst)
        let usesIPadAccountSheets = UIDevice.current.userInterfaceIdiom == .pad
        #else
        let usesIPadAccountSheets = false
        #endif
        if usesIPadAccountSheets {
            selectMainNavigation(ID.navigationPublicGames, in: app)
            element(ID.screenPublicGames, in: app)
            selectMainNavigation(ID.navigationHome, in: app)
        } else {
            tap(ID.navigationSettings, in: app)
            element(ID.screenSettings, in: app)
            tap(ID.navigationHome, in: app)
        }
        assertProperty("value", equals: draft,
                       of: element(ID.gameChatInput, in: app, matching: .textField))
        XCTAssertFalse(chatInputHasKeyboardFocus(in: app))
    }

    func testOrdinaryChatZenRoundTripKeepsDraftWithoutRestoringKeyboard() {
        let app = launchNativeGame()
        let draft = "Keep this draft while concentrating on the board"
        typeDraft(draft, in: app)
        // Dismissing the keyboard is deliberate; entering and leaving Zen
        // must preserve the draft without restoring keyboard focus.
        dismissSoftwareKeyboardIfNeeded(in: app)
        activateZenControl(ID.gameZenEnter, in: app)
        element(ID.gameZenExit, in: app)
        tap(ID.gameZenExit, in: app, matching: .button)
        assertProperty("value", equals: draft,
                       of: element(ID.gameChatInput, in: app, matching: .textField))
        XCTAssertFalse(chatInputHasKeyboardFocus(in: app))
    }

    func testChatPreviewFitsLargestDynamicTypeInBothRegularLayouts() throws {
        let app = launchNativeGame(additionalLaunchArguments: [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ])
        let liveBoard = try boardValue(in: app)
        tapChatItem(ID.gameChatLine("app-store-chat-variation"), in: app, matching: .button)
        assertProperty("value", equals: "variation:91:ii-hh-hi-cq", of: element(ID.gameBoard, in: app))
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            let board = element(ID.gameBoard, in: app)
            let returnButton = element("game.chat.preview.return", in: app, matching: .button)
            let fits = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let window = app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1)
                return board.frame.width > 100 && board.frame.height > 100
                    && abs(board.frame.width - board.frame.height) <= 1
                    && window.contains(board.frame) && window.contains(returnButton.frame)
                    && returnButton.frame.maxY <= board.frame.minY + 1
            }, object: nil)
            let result = waitWithFinalCheck(for: [fits], timeout: 10)
            keepScreenshot("Chat preview – largest Dynamic Type – \(orientation.rawValue)", in: app)
            XCTAssertEqual(result, .completed,
                           "The full board and preview action must fit without overlapping at the largest text size. Window: \(app.windows.firstMatch.frame); board: \(board.frame); return: \(returnButton.frame).")
            XCTAssertTrue(returnButton.isHittable)
        }
        tap("game.chat.preview.return", in: app, matching: .button)
        assertProperty("value", equals: liveBoard, of: element(ID.gameBoard, in: app))
    }

    func testOrdinaryChatDraftAndChannelSurviveLayouts() {
        let app = launchContinuityScene(.gameChat)
        selectPersonalChannel(in: app)
        let channel = element(ID.gameChatChannelPicker, in: app)
        let channelValue = channel.value as? String
        XCTAssertNotNil(channelValue)
        let draft = "A thought to finish after folding"
        typeDraft(draft, in: app)

        // First transition happens while the composer owns keyboard focus.
        changeLayout(toCompact: true, in: app)
        assertProperty(
            "value", equals: draft,
            of: element(ID.gameChatInput, in: app, matching: .textField)
        )
        XCTAssertEqual(channel.value as? String, channelValue)
        dismissSoftwareKeyboardIfNeeded(in: app)

        // A deliberately dismissed keyboard should stay dismissed when the
        // replacement composer appears; its draft remains independently alive.
        changeLayout(toCompact: false, in: app)
        assertProperty(
            "value", equals: draft,
            of: element(ID.gameChatInput, in: app, matching: .textField)
        )
        XCTAssertFalse(chatInputHasKeyboardFocus(in: app))
        changeLayout(toCompact: true, in: app)
        assertProperty(
            "value", equals: draft,
            of: element(ID.gameChatInput, in: app, matching: .textField)
        )
        XCTAssertFalse(chatInputHasKeyboardFocus(in: app))
        XCTAssertEqual(channel.value as? String, channelValue)
    }

    func testPanelSwitchesRetainWorkWithoutRestoringHiddenPanelsAcrossLayouts() throws {
        let app = launchContinuityScene(.gameAnalysis)
        let initialBoard = try boardValue(in: app)
        let draft = "Keep this thought while exploring the next move"
        typeDraft(draft, in: app)
        dismissSoftwareKeyboardIfNeeded(in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: ID.gameAnalyzeControlBar).firstMatch.exists)
        setGameAnalyzing(true, in: app)
        XCTAssertFalse(app.textFields[ID.gameChatInput].exists)
        tap(ID.gameAnalyzeNext, in: app, matching: .button)
        let exploredBoard = try boardValue(in: app)
        XCTAssertNotEqual(exploredBoard, initialBoard)
        for compact in [true, false] {
            changeLayout(toCompact: compact, in: app)
            assertProperty("value", equals: exploredBoard, of: element(ID.gameBoard, in: app))
            XCTAssertFalse(app.textFields[ID.gameChatInput].exists,
                           "Resizing preserves Analyze as the only open panel")
        }
        openGameChat(in: app)
        assertProperty("value", equals: draft, of: element(ID.gameChatInput, in: app, matching: .textField))
        setGameChatVisible(false, in: app)
        let liveBoard = try boardValue(in: app)
        changeLayout(toCompact: true, in: app)
        activateZenControl(ID.gameZenEnter, in: app)
        element(ID.gameZenExit, in: app)
        changeLayout(toCompact: false, in: app)
        assertProperty("value", equals: liveBoard, of: element(ID.gameBoard, in: app))
        tap(ID.gameZenExit, in: app, matching: .button)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: ID.gameAnalyzeControlBar).firstMatch.exists,
                       "Exiting Zen preserves Play rather than restoring a hidden panel")
        XCTAssertFalse(app.textFields[ID.gameChatInput].exists)
        setGameAnalyzing(true, in: app)
        assertProperty("value", equals: exploredBoard, of: element(ID.gameBoard, in: app))
        openGameChat(in: app)
        assertProperty("value", equals: draft, of: element(ID.gameChatInput, in: app, matching: .textField))
    }

    func testAnalysisAndExplicitChatRetainWorkAcrossNativeRotation() throws {
        try XCTSkipIf(
            UIDevice.current.userInterfaceIdiom != .pad,
            "This journey exercises the two regular iPad arrangements."
        )
        let app = launchNativeGame()
        XCTAssertFalse(gameToolbarToggleIsOn(gameAnalyzeControl(in: app)))
        XCTAssertFalse(gameToolbarToggleIsOn(gameChatControl(in: app)))
        XCTAssertFalse(app.textFields[ID.gameChatInput].exists,
                       "Chat starts closed until the user requests it.")
        setGameAnalyzing(true, in: app)
        tap(ID.gameAnalyzePrevious, in: app, matching: .button)
        tap(ID.gameAnalyzeMarkerMenu, in: app)
        tap(analyzeMenuItem(ID.gameAnalyzeMarkerTool("letters"), catalystTitle: "Letters", in: app),
            description: "Letters marker tool", in: app)
        element(ID.gameBoard, in: app)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let markedBoard = try boardValue(in: app)
        XCTAssertTrue(markedBoard.contains("|marks:A="))
        let markerTool = try XCTUnwrap(element(ID.gameAnalyzeMarkerMenu, in: app).value as? String)

        XCUIDevice.shared.orientation = .portrait
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.height > app.frame.width
        }, object: nil)
        XCTAssertEqual(waitWithFinalCheck(for: [portrait], timeout: 10), .completed)
        assertProperty("value", equals: markedBoard, of: element(ID.gameBoard, in: app))
        assertProperty("value", equals: markerTool, of: element(ID.gameAnalyzeMarkerMenu, in: app))
        XCTAssertFalse(app.textFields[ID.gameChatInput].exists)

        let draft = "Keep this marked position while rotating"
        typeDraft(draft, in: app)
        dismissSoftwareKeyboardIfNeeded(in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: ID.gameAnalyzeControlBar).firstMatch.exists,
                       "Chat replaces Analyze while preserving its work")
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(waitWithFinalCheck(for: [landscape], timeout: 10), .completed)
        assertProperty("value", equals: draft, of: element(ID.gameChatInput, in: app, matching: .textField))
        XCTAssertFalse(chatInputHasKeyboardFocus(in: app))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: ID.gameAnalyzeControlBar).firstMatch.exists)
        setGameAnalyzing(true, in: app)
        assertProperty("value", equals: markedBoard, of: element(ID.gameBoard, in: app))
        assertProperty("value", equals: markerTool, of: element(ID.gameAnalyzeMarkerMenu, in: app))
        XCTAssertFalse(app.textFields[ID.gameChatInput].exists)
        openGameChat(in: app)
        assertProperty("value", equals: draft, of: element(ID.gameChatInput, in: app, matching: .textField))
    }

    func testPhoneAnalysisAndChatRetainWorkAcrossNativeRotation() throws {
        try XCTSkipIf(
            UIDevice.current.userInterfaceIdiom != .phone,
            "This journey exercises the phone's compact portrait arrangement."
        )
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameAnalysis.rawValue,
        ], orientation: .portrait)
        tap(ID.gameAnalyzeMarkerMenu, in: app)
        tap(analyzeMenuItem(ID.gameAnalyzeMarkerTool("letters"), catalystTitle: "Letters", in: app),
            description: "Letters marker tool", in: app)
        element(ID.gameBoard, in: app)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let markedBoard = try boardValue(in: app)
        XCTAssertTrue(markedBoard.contains("|marks:A="))
        let markerTool = try XCTUnwrap(element(ID.gameAnalyzeMarkerMenu, in: app).value as? String)

        let draft = "Keep this phone draft while rotating"
        typeDraft(draft, in: app)
        dismissSoftwareKeyboardIfNeeded(in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(pollUntil(timeout: 10) { app.frame.width > app.frame.height })
        assertProperty("value", equals: draft,
                       of: element(ID.gameChatInput, in: app, matching: .textField))
        XCTAssertFalse(chatInputHasKeyboardFocus(in: app))
        setGameChatVisible(false, in: app)
        setGameAnalyzing(true, in: app)
        assertProperty("value", equals: markedBoard, of: element(ID.gameBoard, in: app))
        assertProperty("value", equals: markerTool, of: element(ID.gameAnalyzeMarkerMenu, in: app))

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(pollUntil(timeout: 10) { app.frame.height > app.frame.width })
        assertProperty("value", equals: markedBoard, of: element(ID.gameBoard, in: app))
        openGameChat(in: app)
        assertProperty("value", equals: draft,
                       of: element(ID.gameChatInput, in: app, matching: .textField))
        keepScreenshot("Phone analysis and chat retained through rotation", in: app)
    }

    func testSharingKeepsDraftAndAnalysisSessionAcrossLayouts() throws {
        let app = launchContinuityScene(.gameAnalysis)
        // The narrow analysis pane intentionally drops adjacent-branch buttons.
        // Either destination gives this journey a non-live position to mark.
        let nextBranch = app.buttons[ID.gameAnalyzeNextBranch]
        tap(nextBranch.exists ? ID.gameAnalyzeNextBranch : ID.gameAnalyzePrevious,
            in: app, matching: .button)
        tap(ID.gameAnalyzeMarkerMenu, in: app)
        tap(
            analyzeMenuItem(
                ID.gameAnalyzeMarkerTool("letters"),
                catalystTitle: "Letters", in: app
            ),
            description: "Letters marker tool", in: app
        )
        element(ID.gameBoard, in: app)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .tap()
        let sourceBoard = try boardValue(in: app)
        XCTAssertTrue(sourceBoard.contains("|marks:A="))
        let sourceTool = try XCTUnwrap(
            element(ID.gameAnalyzeMarkerMenu, in: app).value as? String
        )
        tap(ID.gameAnalyzeActionsMenu, in: app)
        tap(
            analyzeMenuItem(
                ID.gameAnalyzeShare,
                catalystTitle: "Share variation in chat", in: app
            ),
            description: "Share variation in chat", in: app
        )
        selectPersonalChannel(in: app)
        let draftName = "Marked branch after folding"
        typeDraft(draftName, in: app)
        let frozenPreview = try XCTUnwrap(
            element(ID.gameVariationSharePreview, in: app).value as? String
        )
        let channelValue = try XCTUnwrap(
            element(ID.gameChatChannelPicker, in: app).value as? String
        )
        dismissSoftwareKeyboardIfNeeded(in: app)

        for compact in [true, false, true] {
            changeLayout(toCompact: compact, in: app)
            assertProperty(
                "value", equals: frozenPreview,
                of: element(ID.gameVariationSharePreview, in: app)
            )
            assertProperty(
                "value", equals: draftName,
                of: element(ID.gameChatInput, in: app, matching: .textField)
            )
            assertProperty(
                "value", equals: channelValue,
                of: element(ID.gameChatChannelPicker, in: app)
            )
            XCTAssertTrue(element(ID.gameVariationShareCancel, in: app).isHittable)
            XCTAssertTrue(element(ID.gameChatSend, in: app).isHittable)
        }

        tap(ID.gameVariationShareCancel, in: app, matching: .button)
        setGameAnalyzing(true, in: app)
        assertProperty(
            "value", equals: sourceBoard, of: element(ID.gameBoard, in: app)
        )
        assertProperty(
            "value", equals: sourceTool,
            of: element(ID.gameAnalyzeMarkerMenu, in: app)
        )
        changeLayout(toCompact: false, in: app)
        assertProperty(
            "value", equals: sourceBoard, of: element(ID.gameBoard, in: app)
        )
    }

    func testForwardRemembersSelectedBranchAcrossLayouts() throws {
        let app = launchContinuityScene(.gameAnalysis)
        tap(ID.gameAnalyzeNextBranch, in: app, matching: .button)
        tap(ID.gameAnalyzePrevious, in: app, matching: .button)
        let preferredChild = try boardValue(in: app)
        XCTAssertTrue(preferredChild.contains("bn-bm-bo-cf"))
        tap(ID.gameAnalyzePrevious, in: app, matching: .button)
        let fork = try boardValue(in: app)
        XCTAssertNotEqual(fork, preferredChild)

        changeLayout(toCompact: true, in: app)
        assertProperty("value", equals: fork, of: element(ID.gameBoard, in: app))
        tap(ID.gameAnalyzeNext, in: app, matching: .button)
        assertProperty(
            "value", equals: preferredChild, of: element(ID.gameBoard, in: app)
        )

        tap(ID.gameAnalyzePrevious, in: app, matching: .button)
        changeLayout(toCompact: false, in: app)
        tap(ID.gameAnalyzeNext, in: app, matching: .button)
        assertProperty(
            "value", equals: preferredChild, of: element(ID.gameBoard, in: app)
        )
    }
}
