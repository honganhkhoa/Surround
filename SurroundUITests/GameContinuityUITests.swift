//
//  GameContinuityUITests.swift
//  SurroundUITests
//
//  Keep the game route alive while replacing its compact/regular descendants.
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
        let picker = app.segmentedControls[ID.gameDisplayModePicker]
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == %@", NSNumber(value: compact)),
            object: picker
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [changed], timeout: 10), .completed,
            "Expected the actual game subtree to adopt the requested layout.",
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
            XCTWaiter.wait(for: [matches], timeout: 10), .completed,
            "Expected \(property) to remain \(value.debugDescription).",
            file: file, line: line
        )
    }

    private func boardValue(in app: XCUIApplication) throws -> String {
        try XCTUnwrap(element(ID.gameBoard, in: app).value as? String)
    }

    private func typeDraft(_ text: String, in app: XCUIApplication) {
        let input = element(ID.gameChatInput, in: app, matching: .textField)
        if !chatInputHasKeyboardFocus(in: app) {
            tap(input, description: "chat composer", in: app)
        }
        input.typeText(text)
        assertProperty("value", equals: text, of: input)
    }

    private func selectPersonalChannel(in app: XCUIApplication) {
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
            XCTWaiter.wait(for: [enabled], timeout: 10), .completed,
            "Initial Analyze must select the current position before any user interaction."
        )

        tap(previous, description: "Explore the previous move", in: app)
        XCTAssertNotEqual(try boardValue(in: app), currentBoard)
        tap(ID.gameAnalyzeNext, in: app, matching: .button)
        assertProperty("value", equals: currentBoard, of: element(ID.gameBoard, in: app))
    }

    func testExplicitAnalyzeExitResetsPositionAndToolInBothLayouts() throws {
        for compact in [false, true] {
            let app = compact ? launchContinuityScene(.activeGameBoard) : launchNativeGame()
            let liveBoard = try boardValue(in: app)
            if compact { changeLayout(toCompact: true, in: app) }
            func setAnalyzing(_ analyzing: Bool) {
                if compact {
                    selectSegment(at: analyzing ? 0 : 1, in: ID.gameDisplayModePicker, app: app)
                } else {
                    tap(ID.gameAnalyzeToggle, in: app)
                }
            }
            setAnalyzing(true)
            let defaultTool = try XCTUnwrap(element(ID.gameAnalyzeMarkerMenu, in: app).value as? String)
            tap(ID.gameAnalyzePrevious, in: app, matching: .button)
            XCTAssertNotEqual(try boardValue(in: app), liveBoard)
            tap(ID.gameAnalyzeMarkerMenu, in: app)
            tap(analyzeMenuItem(ID.gameAnalyzeMarkerTool("letters"), catalystTitle: "Letters", in: app),
                description: "Letters marker tool", in: app)

            setAnalyzing(false)
            setAnalyzing(true)
            assertProperty("value", equals: liveBoard, of: element(ID.gameBoard, in: app))
            assertProperty("value", equals: defaultTool, of: element(ID.gameAnalyzeMarkerMenu, in: app))
            setAnalyzing(false)
            app.terminate()
        }
    }

    func testFocusedChatProfileRoundTripKeepsDraftWithoutRestoringKeyboard() {
        let app = launchNativeGame()
        let draft = "Keep this draft while viewing the player"
        typeDraft(draft, in: app)
        tap(ID.profileBannerAvatarEntry(SurroundUITestContract.profileFixtureOpponentID), in: app, matching: .button)
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
        XCTAssertEqual(XCTWaiter.wait(for: [edited], timeout: 10), .completed)
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
        // The regular layout hides its navigation bar while typing. Follow
        // the real entry path, then verify Zen does not undo that dismissal.
        dismissSoftwareKeyboardIfNeeded(in: app)
        tap(ID.gameZenEnter, in: app, matching: .button)
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
            let result = XCTWaiter.wait(for: [fits], timeout: 10)
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

    func testAnalysisNavigationBecomesActiveAfterTypingInWideChat() throws {
        let app = launchContinuityScene(.gameAnalysis)
        let initialBoard = try boardValue(in: app)
        let draft = "Keep this thought while exploring the next move"
        typeDraft(draft, in: app)
        dismissSoftwareKeyboardIfNeeded(in: app)

        // Wide layout supports both tasks. Returning to analysis controls is
        // the latest explicit intent, even though a chat draft remains alive.
        tap(ID.gameAnalyzeNext, in: app, matching: .button)
        let exploredBoard = try boardValue(in: app)
        XCTAssertNotEqual(exploredBoard, initialBoard)
        changeLayout(toCompact: true, in: app)
        let analyzeSegment = element(
            ID.gameDisplayModePicker, in: app, matching: .segmentedControl
        ).buttons.element(boundBy: 0)
        XCTAssertTrue(
            analyzeSegment.isSelected,
            "Folding should reveal the analysis task most recently used."
        )
        element(ID.gameAnalyzeControlBar, in: app)
        assertProperty(
            "value", equals: exploredBoard, of: element(ID.gameBoard, in: app)
        )

        changeLayout(toCompact: false, in: app)
        assertProperty(
            "value", equals: draft,
            of: element(ID.gameChatInput, in: app, matching: .textField)
        )
        assertProperty(
            "value", equals: exploredBoard, of: element(ID.gameBoard, in: app)
        )
    }

    func testSharingKeepsDraftAndAnalysisSessionAcrossLayouts() throws {
        let app = launchContinuityScene(.gameAnalysis)
        tap(ID.gameAnalyzeNextBranch, in: app, matching: .button)
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
        selectSegment(at: 0, in: ID.gameDisplayModePicker, app: app)
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
