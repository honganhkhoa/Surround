import XCTest
import UIKit

/// Read-only visual inventory for the October Game Detail artboard audit.
/// Every scene uses the design-specific offline fixture; no game command is sent.
final class ArtboardPhoneAuditTests: SurroundJourneyUITestCase {
    private typealias ID = SurroundUITestContract.AccessibilityID
    private typealias Scene = SurroundUITestContract.CompatibilityScene
    private var routeNote = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SURROUND_ARTBOARD_AUDIT"] == "1",
                          "Manual artboard audit is opt-in and does not run in CI.")
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Phone artboard inventory uses iOS simulators.")
        #endif
    }

    private func launch(
        _ scene: Scene = .activeGameBoard,
        artboard: Int? = 1,
        clock: String? = nil,
        players: String? = nil,
        textSize: UIContentSizeCategory? = nil,
        orientation: UIDeviceOrientation = .portrait,
        fromMainNavigation: Bool = true,
        dark: Bool = false,
        socketDown: Bool = false,
        hidesRank: Bool = false,
        theme: String? = nil,
        appearance: SurroundUITestContract.Appearance? = nil
    ) -> XCUIApplication {
        let usesHome = fromMainNavigation
        var arguments = [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.emptyMessagesLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            usesHome ? Scene.home.rawValue : scene.rawValue,
        ]
        if let artboard {
            arguments += [SurroundUITestContract.gameDetailDesignArtboardLaunchArgument, String(artboard)]
        }
        if let clock {
            arguments += [SurroundUITestContract.gameDetailClockStateLaunchArgument, clock]
        }
        if let players {
            arguments += [SurroundUITestContract.gameDetailPlayersLaunchArgument, players]
        }
        if let textSize {
            arguments += ["-UIPreferredContentSizeCategoryName", textSize.rawValue]
        }
        if let theme {
            arguments += [SurroundUITestContract.themeLaunchArgument, theme]
        }
        if let appearance {
            arguments += [SurroundUITestContract.appearanceLaunchArgument, appearance.rawValue]
        } else if theme == nil && dark {
            arguments += [SurroundUITestContract.appearanceLaunchArgument, "dark"]
        }
        if socketDown {
            arguments.append(SurroundUITestContract.gameDetailSocketDownLaunchArgument)
        }
        if hidesRank {
            // Only the isolated UI-test preferences suite (v149).
            arguments.append(SurroundUITestContract.hidesRankLaunchArgument)
        }
        let app = launchApp(additionalLaunchArguments: arguments, orientation: orientation)
        if usesHome {
            let game = element(ID.homeGame(SurroundUITestContract.screenshotPrimaryGameID),
                               in: app, matching: .button)
            let home = app.scrollViews[ID.screenHome].firstMatch
            // Closed landscape has less vertical room than portrait. Reveal
            // the real Home card before taking the same navigation route.
            for _ in 0..<4 where !game.isHittable {
                let upper = home.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35))
                let lower = home.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.70))
                let moveDown = game.frame.minY < app.windows.firstMatch.frame.minY + 82
                (moveDown ? upper : lower).press(forDuration: 0.05,
                    thenDragTo: moveDown ? lower : upper, withVelocity: .slow, thenHoldForDuration: 0.3)
            }
            tap(game, description: "Open the design fixture from Home", in: app)
            if scene == .zenMode { tap(ID.gameZenEnter, in: app, matching: .button) }
            routeNote = "MainView Home → design fixture game; native navigation chrome."
        } else {
            routeNote = "Standalone clock-reference scene \(scene.rawValue)."
        }
        if let theme { routeNote += " Theme: \(theme)." }
        if let appearance { routeNote += " Appearance: \(appearance.rawValue)." }
        element(ID.gameBoard, in: app)
        return app
    }

    private func rotate(_ orientation: UIDeviceOrientation, app: XCUIApplication) {
        XCUIDevice.shared.orientation = orientation
        XCTAssertTrue(pollUntil(timeout: 10) {
            orientation.isLandscape ? app.frame.width > app.frame.height
                : app.frame.height > app.frame.width
        })
    }

    private func assertSelectedBranchVisible(_ path: [String], in app: XCUIApplication,
                                             file: StaticString = #filePath, line: UInt = #line) {
        let node = element(ID.gameAnalysisPosition(baseMoveNumber: 38, movePath: path),
                           in: app, file: file, line: line)
        let tree = app.scrollViews[ID.gameAnalyzeTreeScroll].firstMatch
        XCTAssertTrue(pollUntil(timeout: 10) {
            guard node.exists, node.isSelected, tree.exists else { return false }
            let ancestors = app.scrollViews.containing(.scrollView, identifier: ID.gameAnalyzeTreeScroll)
                .allElementsBoundByIndex
            let viewport = ([app.frame, tree.frame] + ancestors.map { $0.frame })
                .reduce(CGRect.infinite) { $0.intersection($1) }
            // The inner scroll view's AX frame includes clipped content. Use
            // every clipping ancestor and include the selected stone's ring.
            return !viewport.isEmpty && viewport.insetBy(dx: -1, dy: -1)
                .contains(node.frame.insetBy(dx: -3, dy: -3))
        }, "The selected branch and its ring must be fully visible in the tree viewport",
                      file: file, line: line)
    }

    private func capture(_ number: Int, app: XCUIApplication, note: String = "", suffix: String = "") {
        let name = String(format: "native-%03d", number) + suffix
        // Keep rendered state and geometry alongside the visual evidence.
        let board = app.descendants(matching: .any).matching(identifier: ID.gameBoard).firstMatch
        if board.exists {
            XCTAssertTrue(pollUntil(timeout: 5) {
                abs(board.frame.width - board.frame.height) < 1
            }, "Wait for the board layout to settle before recording geometry")
        }
        let input = app.textFields[ID.gameChatInput].firstMatch
        let chat = app.scrollViews[ID.gameChatLog].firstMatch
        let tree = app.scrollViews[ID.gameAnalyzeTreeScroll].firstMatch
        let latest = app.buttons[ID.gameChatLine("app-store-chat-variation")].firstMatch
        let blackClock = app.buttons["game.clock.black"].firstMatch
        let whiteClock = app.buttons["game.clock.white"].firstMatch
        let more = app.buttons[ID.gameActionsMenu].firstMatch
        let text = """
        Artboard: \(number)\(suffix)
        Window: \(app.frame)
        Board frame: \(board.exists ? String(describing: board.frame) : "absent")
        Board value: \(board.exists ? String(describing: board.value) : "absent")
        Chat frame: \(chat.exists ? String(describing: chat.frame) : "absent")
        Analysis tree frame: \(tree.exists ? String(describing: tree.frame) : "absent")
        Black clock frame: \(blackClock.exists ? String(describing: blackClock.frame) : "absent")
        White clock frame: \(whiteClock.exists ? String(describing: whiteClock.frame) : "absent")
        More actions frame: \(more.exists ? String(describing: more.frame) : "absent")
        Black clock state: \(blackClock.exists ? String(describing: blackClock.value) : "absent")
        White clock state: \(whiteClock.exists ? String(describing: whiteClock.value) : "absent")
        Latest chat bubble: \(latest.exists ? String(describing: latest.frame) : "absent")
        Global message overlay: \(app.buttons["global.privateMessages"].exists)
        Keyboard visible: \(app.keyboards.firstMatch.exists)
        Keyboard frame: \(app.keyboards.firstMatch.exists ? String(describing: app.keyboards.firstMatch.frame) : "absent")
        Software keyboard onscreen: \(keyboardIsOnscreen(in: app))
        Input: \(input.exists ? String(describing: input.value) : "absent")
        Fixture note: \(note)
        Navigation route: \(routeNote)
        """
        let attachment = XCTAttachment(string: text)
        attachment.name = name + "-state"
        attachment.lifetime = .keepAlways
        add(attachment)
        recordArtboardCapture(number, screenshotName: name, in: app,
                              note: [routeNote, note].joined(separator: " "))
        if number == 68 && suffix.isEmpty {
            XCTAssertTrue(keyboardIsOnscreen(in: app),
                          "The landscape typing capture must still contain the software keyboard")
        }
        keepScreenshot(name, in: app)
        let previousContinueAfterFailure = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = previousContinueAfterFailure }
        if [11, 16, 67, 72].contains(number) {
            XCTAssertTrue(blackClock.exists, "The compact portrait title keeps the current player's clock")
            XCTAssertFalse(whiteClock.exists, "The other clock gives the compact title its required clearance")
        }
        if [12, 68].contains(number) {
            XCTAssertTrue(blackClock.exists && whiteClock.exists,
                          "The wider landscape title retains both clocks")
        }
        if [11, 12, 67, 68].contains(number) {
            let latest = app.buttons[ID.gameChatLine("app-store-chat-variation")].firstMatch
            XCTAssertTrue(pollUntil(timeout: 5) {
                latest.exists && chat.exists
                    && latest.frame.maxY <= chat.frame.maxY + 4
                    && latest.frame.maxY > chat.frame.minY
            }, "Latest chat message stays immediately above the composer through viewport changes")
        }
        if [22, 23, 82].contains(number) {
            let viewport = assertAuditAnalysisTreeAxis(vertical: false, in: app)
            if number == 22 {
                XCTAssertGreaterThanOrEqual(viewport.height, 186,
                                            "Analyze reserves four branch lines on a full-size phone")
            }
        }
        if [2, 12, 23].contains(number) {
            // These formerly shrank to 226pt (Play/Chat) or 54pt (Analyze).
            // Assert usable native geometry, independent of fixture stones.
            XCTAssertTrue(board.exists)
            XCTAssertGreaterThanOrEqual(board.frame.width, 280,
                                        "Landscape must retain a usable main board")
            if number == 12, chat.exists {
                XCTAssertTrue(board.frame.intersection(chat.frame).isNull
                              || board.frame.intersection(chat.frame).width < 1,
                              "Landscape Chat must sit beside the main board")
            }
            if number == 23, tree.exists {
                XCTAssertTrue(board.frame.intersection(tree.frame).isNull
                              || board.frame.intersection(tree.frame).width < 1,
                              "Landscape Analyze tree must sit beside the main board")
            }
        }
    }

    private func keyboardIsOnscreen(in app: XCUIApplication) -> Bool {
        let keyboard = app.keyboards.firstMatch
        return keyboard.exists && keyboard.frame.intersection(app.frame).height > 100
    }

    private func openDuoChat(in app: XCUIApplication) {
        if app.textFields[ID.gameChatInput].firstMatch.exists { return }
        var chat = gameChatControl(in: app)
        if !chat.exists || !chat.isHittable {
            // The short native vertical toolbar moves Chat into More.
            tap("BottomOverflowBarButtonItem", in: app, matching: .button)
            if !chat.waitForExistence(timeout: 2) {
                chat = app.buttons["Chat"].firstMatch
            }
        }
        // Opening chat never focuses its composer; observe the field rather
        // than the toggle state.
        tap(chat, description: "Open Duo chat", in: app)
        _ = element(ID.gameChatInput, in: app, matching: .textField)
        XCTAssertFalse(pollUntil(timeout: 2) { self.chatInputHasKeyboardFocus(in: app) },
                       "Opening chat must not focus the composer")
        XCTAssertFalse(keyboardIsOnscreen(in: app), "Opening chat must not raise the keyboard")
    }

    /// With the keyboard up, the Chat toggle closes chat: directly when the
    /// toggle is visible, otherwise from the vertical toolbar's "…" overflow.
    /// The conversation and the keyboard go and stay gone (the field regaining
    /// focus must not present chat again); the draft is kept for next time.
    @discardableResult
    private func closeChatWhileTyping(_ draft: String, in app: XCUIApplication,
                                      file: StaticString = #filePath, line: UInt = #line) -> Bool {
        XCTAssertTrue(keyboardIsOnscreen(in: app), "The keyboard is up before closing", file: file, line: line)
        let chat = gameChatControl(in: app)
        let usedOverflow: Bool
        if chat.exists && chat.isHittable {
            tap(chat, description: "Close chat with its toggle while typing", in: app, file: file, line: line)
            usedOverflow = false
        } else {
            tap("BottomOverflowBarButtonItem", in: app, matching: .button, file: file, line: line)
            // iOS 27 menus drop identifiers; take the hittable Chat item.
            let candidates = app.descendants(matching: .any).matching(NSPredicate(
                format: "(elementType == %lu OR elementType == %lu OR elementType == %lu) AND (identifier == %@ OR label == 'Chat' OR label BEGINSWITH 'Chat,')",
                XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.menuItem.rawValue,
                XCUIElement.ElementType.switch.rawValue, ID.gameDisplayModePicker + ".chat"))
            var item: XCUIElement?
            _ = pollUntil(timeout: 5) {
                item = (0..<candidates.count).lazy.map { candidates.element(boundBy: $0) }
                    .first { $0.isHittable }
                return item != nil
            }
            guard let item else {
                XCTFail("The overflow offers Chat", file: file, line: line)
                return true
            }
            tap(item, description: "Close chat from the toolbar overflow", in: app, file: file, line: line)
            usedOverflow = true
        }
        let log = app.descendants(matching: .any).matching(identifier: ID.gameChatLog).firstMatch
        XCTAssertTrue(pollUntil(timeout: 5) { !log.exists }, "Chat closes", file: file, line: line)
        XCTAssertTrue(pollUntil(timeout: 5) { !self.keyboardIsOnscreen(in: app) },
                      "Closing chat dismisses the keyboard", file: file, line: line)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(log.exists, "Chat stays closed; focus restoration must not re-present it",
                       file: file, line: line)
        keepScreenshot("chat-closed-while-typing" + (usedOverflow ? "-overflow" : "-toggle"), in: app)
        if app.textFields[ID.gameChatInput].firstMatch.exists == false {
            if chat.exists && chat.isHittable {
                openGameChat(in: app, file: file, line: line)
            } else {
                openDuoChat(in: app)
            }
        }
        XCTAssertEqual(element(ID.gameChatInput, in: app, matching: .textField).value as? String, draft,
                       "Closing chat keeps the draft", file: file, line: line)
        return usedOverflow
    }

    func testSelectedChatMatchesSelectedAnalyze() {
        // v145: selected Chat uses the native selected-toggle look (solid
        // accent, white glyph). Keep crops of each selected control for a
        // side-by-side comparison in light and dark.
        for dark in [false, true] {
            let app = launch(artboard: 11, dark: dark)
            let appearance = dark ? "dark" : "light"
            openGameChat(in: app)
            dismissSoftwareKeyboardIfNeeded(in: app)
            let chat = gameChatControl(in: app)
            XCTAssertTrue(gameToolbarToggleIsOn(chat), "Chat reports its selected state")
            keepElementCrop(chat, named: "selected-chat-\(appearance)")
            setGameChatVisible(false, in: app)
            setGameAnalyzing(true, in: app)
            let analyze = gameAnalyzeControl(in: app)
            keepElementCrop(analyze, named: "selected-analyze-\(appearance)")
            keepElementCrop(chat, named: "unselected-chat-\(appearance)")
            app.terminate()
        }
    }

    private func keepElementCrop(_ element: XCUIElement, named name: String) {
        XCTAssertTrue(element.exists, "\(name) exists")
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("[SelectedToggle] \(name) \(element.frame)")
    }

    func testOpeningChatNeverRaisesTheKeyboard() {
        // v145: opening chat never focuses the field, in either orientation;
        // the keyboard appears only when the field is tapped.
        let app = launch(artboard: 11)
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            if orientation != .portrait {
                rotate(orientation, app: app)
                // The window reports landscape before the bar settles.
                XCTAssertTrue(waitUntilHittable(gameChatControl(in: app), timeout: 10))
            }
            openGameChat(in: app)
            _ = element(ID.gameChatInput, in: app, matching: .textField)
            XCTAssertFalse(pollUntil(timeout: 2) { self.chatInputHasKeyboardFocus(in: app) },
                           "Opening chat must not focus the composer (\(orientation.rawValue))")
            XCTAssertFalse(keyboardIsOnscreen(in: app),
                           "Opening chat must not raise the keyboard (\(orientation.rawValue))")
            setGameChatVisible(false, in: app)
        }
    }

    func testLandscapeTypingKeepsTheBoardAndTheToggleClosesChat() {
        // v145: typing never hides the board; the keyboard covers its lower
        // part. With the keyboard up the Chat toggle closes chat directly.
        let app = launch(artboard: 12, orientation: .landscapeLeft)
        openGameChat(in: app)
        let board = element(ID.gameBoard, in: app)
        let resting = board.frame
        let boardValue = board.value as? String
        let geometry = app.descendants(matching: .any).matching(identifier: "game.layout.geometry").firstMatch
        print("[LandscapeTypingGeometry] resting \(geometry.value as? String ?? "absent")")
        let input = element(ID.gameChatInput, in: app, matching: .textField)
        tap(input, description: "Focus the landscape chat composer", in: app)
        input.typeText(SurroundUITestContract.gameDetailDesignChatDraft)
        XCTAssertTrue(pollUntil(timeout: 10) { self.keyboardIsOnscreen(in: app) })
        Thread.sleep(forTimeInterval: 1)
        print("[LandscapeTypingGeometry] typing \(geometry.value as? String ?? "absent") keyboard \(app.keyboards.firstMatch.frame)")
        XCTAssertTrue(pollUntil(timeout: 5) {
            abs(board.frame.minX - resting.minX) < 1 && abs(board.frame.minY - resting.minY) < 1
                && abs(board.frame.width - resting.width) < 1
        }, "Typing keeps the landscape board's frame; got \(board.frame), resting \(resting)")
        XCTAssertLessThanOrEqual(input.frame.maxY, app.keyboards.firstMatch.frame.minY - 6,
                                 "The conversation ends above the keyboard")
        keepScreenshot("landscape-typing-keeps-board", in: app)
        closeChatWhileTyping(SurroundUITestContract.gameDetailDesignChatDraft, in: app)
        XCTAssertEqual(board.value as? String, boardValue)
    }

    func testKeyboardDismissalNeverPlacesAStone() {
        // Your turn (fixture 15). Swiping the conversation down, then a first
        // tap outside chat, each dismiss the keyboard without playing. In
        // landscape the board's upper part stays visible above the keyboard;
        // in portrait the keyboard covers it.
        let app = launch(artboard: 15, orientation: .landscapeLeft)
        openGameChat(in: app)
        let board = element(ID.gameBoard, in: app)
        let position = board.value as? String
        let input = element(ID.gameChatInput, in: app, matching: .textField)
        tap(input, description: "Focus the chat composer", in: app)
        input.typeText("Thinking")
        XCTAssertTrue(pollUntil(timeout: 10) { self.keyboardIsOnscreen(in: app) })
        // The log dismisses interactively: the drag starts in the
        // conversation and follows the keyboard down, crossing the board.
        let log = element(ID.gameChatLog, in: app)
        let keyboard = app.keyboards.firstMatch.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        log.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(
            forDuration: 0.05,
            thenDragTo: origin.withOffset(CGVector(dx: log.frame.midX, dy: keyboard.maxY - 24)),
            withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(pollUntil(timeout: 5) { !self.keyboardIsOnscreen(in: app) },
                      "Swiping the conversation down dismisses the keyboard")
        XCTAssertEqual(board.value as? String, position)
        tap(input, description: "Focus the chat composer again", in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { self.keyboardIsOnscreen(in: app) })
        let keyboardTop = app.keyboards.firstMatch.frame.minY
        XCTAssertLessThan(board.frame.minY + 20, keyboardTop, "Part of the board stays above the keyboard")
        let boardTarget = CGPoint(x: board.frame.midX, y: (board.frame.minY + min(board.frame.maxY, keyboardTop)) / 2)
        origin.withOffset(CGVector(dx: boardTarget.x, dy: boardTarget.y)).tap()
        XCTAssertTrue(pollUntil(timeout: 5) { !self.keyboardIsOnscreen(in: app) },
                      "The first tap outside chat dismisses the keyboard")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(board.value as? String, position, "That tap places no stone")
        XCTAssertFalse(app.buttons["Submit move"].exists, "No pending move")
        XCTAssertEqual(input.value as? String, "Thinking", "The draft is kept")
    }

    private func startChat(in app: XCUIApplication, typing: Bool) {
        openGameChat(in: app)
        let input = element(ID.gameChatInput, in: app, matching: .textField)
        if typing {
            tap(input, description: "Focus the chat composer", in: app)
            input.typeText(SurroundUITestContract.gameDetailDesignChatDraft)
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        } else {
            dismissSoftwareKeyboardIfNeeded(in: app)
        }
    }

    func testChatOpensAndClosesAtItsFinalSize() {
        // v145: chat above the portrait board arrives at its final size and
        // fades/slides in and out, never focusing the field; the host records
        // the screen meanwhile.
        let app = launch(artboard: 11)
        recordChatToggle("chat-toggle-phone-portrait", in: app,
                         open: { openGameChat(in: app) },
                         close: { setGameChatVisible(false, in: app) })
        XCTAssertFalse(keyboardIsOnscreen(in: app), "Opening chat never raises the keyboard")
    }

    func testPillKeepsItsSlotWhenPassBecomesSubmitMove() {
        // Rule 19: the pill reserves its phase's labels, so staging a move
        // (Pass becomes Submit move) never grows it leftwards.
        let app = launch(artboard: 15)
        let pass = app.buttons["Pass"].firstMatch
        XCTAssertTrue(pass.waitForExistence(timeout: 10))
        let passFrame = pass.frame
        keepScreenshot("pill-pass", in: app)
        let board = element(ID.gameBoard, in: app)
        // The 1-1 point is empty in the design fixture.
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5 / 19, dy: 0.5 / 19)).tap()
        let submit = app.buttons["Submit move"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 5), "A board tap stages a move")
        print("[PillSlot] pass=\(passFrame) submit=\(submit.frame)")
        XCTAssertEqual(submit.frame.minX, passFrame.minX, accuracy: 1, "The pill does not grow leftwards")
        XCTAssertEqual(submit.frame.width, passFrame.width, accuracy: 1)
        keepScreenshot("pill-submit-move", in: app)
    }

    func testPhonePlay() {
        let app = launch()
        capture(1, app: app, note: "Design-matched players, board, clock values and waiting turn.")
        rotate(.landscapeLeft, app: app)
        capture(2, app: app, note: "Design-matched waiting state in native landscape.")
    }

    /// Scene art and stone rendering must fit the same compact layouts as the
    /// standard board. The existing captures also check panel separation and
    /// the usable landscape board size.
    func testRakedGardenThemeStates() throws {
        try auditThemeStates(theme: "rakedGarden", title: "Raked Garden", suffix: "-raked-garden",
                             appearance: .light)
    }

    func testRakedGardenNightThemeStates() throws {
        try auditThemeStates(theme: "rakedGarden", title: "Raked Garden at night",
                             suffix: "-raked-garden-night", appearance: .dark)
    }

    func testSurroundStudioThemeControlStates() throws {
        auditThemeControlStates(theme: "surroundStudio", title: "Surround Studio",
                                appearance: .light, suffix: "-surround-studio")
    }

    func testSurroundStudioNightThemeControlStates() throws {
        auditThemeControlStates(theme: "surroundStudio", title: "Surround Studio",
                                appearance: .dark, suffix: "-surround-studio-night")
    }

    func testSurroundStudioNightBoardMarkerGallery() throws {
        try auditThemeBoardMarkerGallery(theme: "surroundStudio", appearance: .dark,
                                         suffix: "surround-studio-night", pageBrightnessBand: 0...0.25,
                                         boardBrightnessBand: 0.30...0.60)
    }

    func testChristmasKeepsakesBoardMarkerGallery() throws {
        try auditThemeBoardMarkerGallery(theme: "christmasKeepsakes", appearance: .light,
                                         suffix: "christmas-keepsakes", pageBrightnessBand: 0.70...1,
                                         boardBrightnessBand: 0.12...0.40)
    }

    func testChristmasKeepsakesNightBoardMarkerGallery() throws {
        try auditThemeBoardMarkerGallery(theme: "christmasKeepsakes", appearance: .dark,
                                         suffix: "christmas-keepsakes-night", pageBrightnessBand: 0...0.25,
                                         boardBrightnessBand: 0.08...0.32)
    }

    func testNightGardenBoardMarkerGallery() throws {
        try auditThemeBoardMarkerGallery(theme: "nightGarden", appearance: .light,
                                         suffix: "night-garden", pageBrightnessBand: 0.70...1,
                                         boardBrightnessBand: 0.45...0.75)
    }

    func testNightGardenNightBoardMarkerGallery() throws {
        try auditThemeBoardMarkerGallery(theme: "nightGarden", appearance: .dark,
                                         suffix: "night-garden-night", pageBrightnessBand: 0...0.25,
                                         boardBrightnessBand: 0.35...0.65)
    }

    func testFeltMeadowBoardMarkerGallery() throws {
        try auditThemeBoardMarkerGallery(theme: "feltMeadow", appearance: .light,
                                         suffix: "felt-meadow", pageBrightnessBand: 0.60...1,
                                         boardBrightnessBand: 0.40...0.70)
    }

    func testFeltMeadowNightBoardMarkerGallery() throws {
        try auditThemeBoardMarkerGallery(theme: "feltMeadow", appearance: .dark,
                                         suffix: "felt-meadow-night", pageBrightnessBand: 0...0.25,
                                         boardBrightnessBand: 0.25...0.55)
    }

    private func auditThemeBoardMarkerGallery(theme: String, appearance: SurroundUITestContract.Appearance,
                                             suffix: String, pageBrightnessBand: ClosedRange<Double>,
                                             boardBrightnessBand: ClosedRange<Double>) throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "The marker gallery audit requires a full-size phone in portrait.")
        // Explicit native panels keep each sample visible as the complete
        // fixture catalog grows; the unfiltered gallery is a long scroll view.
        let panels: [(id: String, samples: [(id: String, title: String, coordinates: Bool)])] = [
            ("core-1", [("last-black", "Last move · black", false),
                        ("last-white", "Last move · white", false),
                        ("pending-black", "Pending · black", false),
                        ("pending-white", "Pending · white", false)]),
            ("core-2", [("markup", "Markup · empty / black / white", false),
                        ("variation", "Variation · 1–6", false),
                        ("score", "Score · dame · dead", false),
                        ("chat-undo", "Chat highlight · undo", true)]),
            ("interaction-1", [("legal-empty", "Legal crosshair · empty", false),
                               ("illegal-empty", "Illegal crosshair · empty", false),
                               ("illegal-black", "Illegal crosshair · black", false),
                               ("illegal-white", "Illegal crosshair · white", false)]),
            ("interaction-2", [("remove", "Remove × · black / white / empty", false),
                               ("restore", "Restore + · black / white / empty", false),
                               ("removal-crosshair", "Removal crosshair · both colors", false)]),
        ]
        for cellSize in [20, 13, 7] {
            for panel in panels {
                let app = launchApp(additionalLaunchArguments: [
                    "--surround-board-marker-audit", String(cellSize),
                    "--surround-board-marker-panel", panel.id,
                    SurroundUITestContract.themeLaunchArgument, theme,
                    SurroundUITestContract.appearanceLaunchArgument, appearance.rawValue,
                ], orientation: .portrait)
                defer { app.terminate() }
                // SwiftUI coalesces the panel and its enclosing gallery into
                // one accessibility container; the outer identifier wins.
                let gallery = element("uitest.boardMarkerAudit", in: app)
                XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
                XCTAssertTrue(gallery.isHittable, "The selected native marker panel is visible")
                XCTAssertTrue(app.staticTexts[panel.id].waitForExistence(timeout: 5))
                let window = app.windows.firstMatch.frame
                let cell = CGFloat(cellSize)
                for sample in panel.samples {
                    let label = app.staticTexts[sample.title].firstMatch
                    let identifier = app.staticTexts[sample.id].firstMatch
                    XCTAssertTrue(label.waitForExistence(timeout: 5), "\(panel.id) includes \(sample.title)")
                    XCTAssertTrue(identifier.waitForExistence(timeout: 5), "\(panel.id) includes sample \(sample.id)")
                    XCTAssertTrue(window.contains(label.frame), "The sample title fits its native capture")
                    // Panel samples show an identifier below the title; the
                    // board starts four points after that final text line.
                    let side = cell * CGFloat(sample.coordinates ? 8 : 7)
                    let boardFrame = CGRect(x: identifier.frame.minX, y: identifier.frame.maxY + 4,
                                            width: side, height: side)
                    XCTAssertTrue(window.contains(boardFrame), "The complete \(sample.id) board fits its native capture")
                }
                let firstIdentifier = app.staticTexts[panel.samples[0].id].firstMatch.frame
                // The trailing 16pt panel padding is outside every sample.
                let pagePatch = CGRect(x: window.maxX - 14, y: window.maxY - 50, width: 8, height: 8)
                // Every panel's first sample has a 7×7 board. Sample its inner
                // six cells to exclude the bevel and cast shadow.
                let boardPatch = CGRect(x: firstIdentifier.minX + cell / 2,
                                        y: firstIdentifier.maxY + 4 + cell / 2,
                                        width: cell * 6, height: cell * 6)
                var pageBrightness: Double?
                var boardBrightness: Double?
                XCTAssertTrue(pollUntil(timeout: 10) {
                    guard let image = app.screenshot().image.cgImage else { return false }
                    pageBrightness = self.markerGalleryBrightness(in: pagePatch, image: image, frame: app.frame)
                    boardBrightness = self.markerGalleryBrightness(in: boardPatch, image: image, frame: app.frame)
                    guard let pageBrightness, let boardBrightness else { return false }
                    return pageBrightnessBand.contains(pageBrightness) && boardBrightnessBand.contains(boardBrightness)
                }, "The rendered panel must show \(theme)'s \(appearance.rawValue) palette, not only accept an appearance flag")
                print("[ThemeMarkerGallery] theme=\(theme) appearance=\(appearance.rawValue) panel=\(panel.id) cell=\(cellSize) pageBrightness=\(String(describing: pageBrightness)) boardBrightness=\(String(describing: boardBrightness))")
                keepScreenshot("\(suffix)-markers-\(cellSize)pt-\(panel.id)", in: app)
            }
        }
    }

    private func markerGalleryBrightness(in region: CGRect, image: CGImage, frame: CGRect) -> Double? {
        guard frame.width > 0, frame.height > 0, frame.contains(region),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let scaleX = CGFloat(image.width) / frame.width
        let scaleY = CGFloat(image.height) / frame.height
        let pixelsRect = CGRect(x: (region.minX - frame.minX) * scaleX,
                                y: (region.minY - frame.minY) * scaleY,
                                width: region.width * scaleX, height: region.height * scaleY)
        guard let sample = image.cropping(to: pixelsRect) else { return nil }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                            | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(sample, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        // A loop, not a single-expression reduce: Xcode 26 cannot type-check
        // the reduce closure in reasonable time.
        var sum = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            sum += (0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1])
                    + 0.0722 * Double(pixels[index + 2])) / 255
        }
        return sum / Double(side * side)
    }

    private func auditThemeControlStates(theme: String, title: String,
                                        appearance: SurroundUITestContract.Appearance, suffix: String) {
        for number in [78, 79] {
            let urgent = launch(artboard: number, clock: "sudden-death",
                                fromMainNavigation: false, theme: theme, appearance: appearance)
            let clock = element(number == 78 ? "game.clock.black" : "game.clock.white", in: urgent)
            XCTAssertTrue((clock.value as? String)?.contains("Sudden death") == true,
                          "The clock reference must exercise the final period warning")
            capture(number, app: urgent, note: "\(title) urgent clock text over tinted glass.",
                    suffix: "\(suffix)-urgent")
            urgent.terminate()
        }
        let disconnected = launch(artboard: 64, socketDown: true, theme: theme, appearance: appearance)
        defer { disconnected.terminate() }
        let accept = disconnected.buttons["Accept"].firstMatch
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        XCTAssertFalse(accept.isEnabled, "Disconnected scoring keeps Accept disabled")
        capture(64, app: disconnected, note: "\(title) disconnected scoring; disabled Accept remains distinct.",
                suffix: "\(suffix)-disabled")
    }

    func testFrostPineBoardMarkerGallery() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "The marker gallery audit requires a full-size phone.")
        for appearance in ["light", "dark"] {
            for cellSize in [20, 13, 7] {
                for (panel, titles) in [
                    ("core-1", ["Last move · black", "Last move · white", "Pending · black", "Pending · white"]),
                    ("core-2", ["Markup · empty / black / white", "Variation · 1–6", "Score · dame · dead", "Chat highlight · undo"]),
                ] {
                    let app = launchApp(additionalLaunchArguments: [
                        "--surround-board-marker-audit", String(cellSize),
                        "--surround-board-marker-panel", panel,
                        SurroundUITestContract.themeLaunchArgument, "frostPine",
                        SurroundUITestContract.appearanceLaunchArgument, appearance,
                    ], orientation: .portrait)
                    XCTAssertTrue(element("uitest.boardMarkerAudit", in: app).isHittable)
                    for title in titles {
                        let label = app.staticTexts[title].firstMatch
                        XCTAssertTrue(label.waitForExistence(timeout: 5))
                        XCTAssertTrue(app.windows.firstMatch.frame.contains(label.frame))
                    }
                    keepScreenshot("frost-pine-\(appearance)-markers-\(cellSize)pt-\(panel)", in: app)
                    app.terminate()
                }
            }
        }
    }

    func testFrostPineThemeStates() throws {
        try auditThemeStates(theme: "frostPine", title: "Frost & Pine",
                             suffix: "-frost-pine", appearance: .light)
    }

    func testFrostPineNightThemeStates() throws {
        try auditThemeStates(theme: "frostPine", title: "Frost & Pine at night",
                             suffix: "-frost-pine-night", appearance: .dark)
    }

    func testFrostPineThemeScoring() throws {
        try auditThemeScoring(theme: "frostPine", title: "Frost & Pine",
                             suffix: "-frost-pine", appearance: .light)
    }

    func testFrostPineNightThemeScoring() throws {
        try auditThemeScoring(theme: "frostPine", title: "Frost & Pine at night",
                             suffix: "-frost-pine-night", appearance: .dark)
    }

    func testFrostPineThemeSmallPhone() throws {
        try auditThemeSmallPhone(theme: "frostPine", title: "Frost & Pine",
                             suffix: "-frost-pine", appearance: .light)
    }

    func testFrostPineNightThemeSmallPhone() throws {
        try auditThemeSmallPhone(theme: "frostPine", title: "Frost & Pine at night",
                             suffix: "-frost-pine-night", appearance: .dark)
    }

    func testSurroundStudioThemeStates() throws {
        try auditThemeStates(theme: "surroundStudio", title: "Surround Studio", suffix: "-surround-studio",
                             appearance: .light)
    }

    func testSurroundStudioNightThemeStates() throws {
        try auditThemeStates(theme: "surroundStudio", title: "Surround Studio at night",
                             suffix: "-surround-studio-night", appearance: .dark)
    }

    func testChristmasKeepsakesThemePanelTransitions() throws {
        try auditThemePanelTransitions(theme: "christmasKeepsakes", title: "Christmas Keepsakes",
                                       suffix: "-christmas-keepsakes", appearance: nil, deviceAppearance: .light)
    }

    func testChristmasKeepsakesNightThemePanelTransitions() throws {
        try auditThemePanelTransitions(theme: "christmasKeepsakes", title: "Christmas Keepsakes in Dark Mode",
                                       suffix: "-christmas-keepsakes-night", appearance: nil, deviceAppearance: .dark)
    }

    func testChristmasKeepsakesThemeStates() throws {
        try auditThemeStates(theme: "christmasKeepsakes", title: "Christmas Keepsakes",
                             suffix: "-christmas-keepsakes", appearance: .light)
    }

    func testChristmasKeepsakesNightThemeStates() throws {
        try auditThemeStates(theme: "christmasKeepsakes", title: "Christmas Keepsakes in Dark Mode",
                             suffix: "-christmas-keepsakes-night", appearance: .dark)
    }

    func testChristmasKeepsakesThemeScoring() throws {
        try auditThemeScoring(theme: "christmasKeepsakes", title: "Christmas Keepsakes",
                              suffix: "-christmas-keepsakes", appearance: .light)
    }

    func testChristmasKeepsakesNightThemeScoring() throws {
        try auditThemeScoring(theme: "christmasKeepsakes", title: "Christmas Keepsakes in Dark Mode",
                              suffix: "-christmas-keepsakes-night", appearance: .dark)
    }

    func testChristmasKeepsakesThemeSmallPhone() throws {
        try auditThemeSmallPhone(theme: "christmasKeepsakes", title: "Christmas Keepsakes",
                                 suffix: "-christmas-keepsakes", appearance: .light)
    }

    func testChristmasKeepsakesThemeControlStates() {
        auditThemeControlStates(theme: "christmasKeepsakes", title: "Christmas Keepsakes",
                                appearance: .light, suffix: "-christmas-keepsakes")
    }

    func testChristmasKeepsakesNightThemeControlStates() {
        auditThemeControlStates(theme: "christmasKeepsakes", title: "Christmas Keepsakes in Dark Mode",
                                appearance: .dark, suffix: "-christmas-keepsakes-night")
    }

    func testNightGardenThemeStates() throws {
        try auditThemeStates(theme: "nightGarden", title: "Night Garden", suffix: "-night-garden",
                             appearance: .light)
    }

    func testNightGardenThemeScoring() throws {
        try auditThemeScoring(theme: "nightGarden", title: "Night Garden", suffix: "-night-garden",
                              appearance: .light)
    }

    func testNightGardenNightThemeScoring() throws {
        try auditThemeScoring(theme: "nightGarden", title: "Night Garden in Dark Mode", suffix: "-night-garden-night",
                              appearance: .dark)
    }

    func testNightGardenThemeSmallPhone() throws {
        try auditThemeSmallPhone(theme: "nightGarden", title: "Night Garden", suffix: "-night-garden",
                                 appearance: .light)
    }

    func testNightGardenThemeControlStates() {
        auditThemeControlStates(theme: "nightGarden", title: "Night Garden", appearance: .light,
                                suffix: "-night-garden")
    }

    func testNightGardenThemePanelTransitions() throws {
        try auditThemePanelTransitions(theme: "nightGarden", title: "Night Garden", suffix: "-night-garden",
                                       appearance: nil, deviceAppearance: .light)
    }

    func testNightGardenNightThemePanelTransitions() throws {
        try auditThemePanelTransitions(theme: "nightGarden", title: "Night Garden in Dark Mode", suffix: "-night-garden-night",
                                       appearance: nil, deviceAppearance: .dark)
    }

    func testFeltMeadowThemeStates() throws {
        try auditThemeStates(theme: "feltMeadow", title: "Felt Meadow", suffix: "-felt-meadow", appearance: .light)
    }

    func testFeltMeadowNightThemeStates() throws {
        try auditThemeStates(theme: "feltMeadow", title: "Felt Meadow at night", suffix: "-felt-meadow-night",
                             appearance: .dark)
    }

    func testFeltMeadowThemeControlStates() {
        auditThemeControlStates(theme: "feltMeadow", title: "Felt Meadow", appearance: .light, suffix: "-felt-meadow")
    }

    func testFeltMeadowNightThemeControlStates() {
        auditThemeControlStates(theme: "feltMeadow", title: "Felt Meadow", appearance: .dark,
                                suffix: "-felt-meadow-night")
    }

    func testFeltMeadowHomeCompact() {
        auditFeltMeadowHome(appearance: .light, large: false)
    }

    func testFeltMeadowNightHomeCompact() {
        auditFeltMeadowHome(appearance: .dark, large: false)
    }

    func testFeltMeadowHomeLarge() {
        auditFeltMeadowHome(appearance: .light, large: true)
    }

    func testFeltMeadowNightHomeLarge() {
        auditFeltMeadowHome(appearance: .dark, large: true)
    }

    private func auditFeltMeadowHome(appearance: SurroundUITestContract.Appearance, large: Bool) {
        // Plain offline Home retains the state fixtures and the ordinary
        // Appearance popover; compatibility scenes have a different game list.
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.homeStatesLaunchArgument,
            SurroundUITestContract.themeLaunchArgument, "feltMeadow",
            SurroundUITestContract.appearanceLaunchArgument, appearance.rawValue,
        ], orientation: .portrait)
        defer { app.terminate() }
        let home = element(ID.screenHome, in: app, matching: .scrollView)
        let mode = large ? "Large" : "Compact"
        let picker = element(ID.homeAppearance, in: app, matching: .button)
        // Toolbar buttons do not consistently expose SwiftUI accessibilityValue
        // through XCTest. Select explicitly and verify the resulting board size.
        tap(picker, description: "Open Home's Appearance popover", in: app)
        let modes = element(ID.homeDisplayMode, in: app, matching: .segmentedControl)
        tap(modes.buttons[mode], description: "Show \(mode) Home games", in: app)
        dismissPopover(in: app)

        let states: [(Int, String, [String])] = [
            (SurroundUITestContract.homeStatesLowTimeGameID, "low-time", ["Your move", "Low on time"]),
            (SurroundUITestContract.homeStatesPausedGameID, "paused", ["Your move", "Paused"]),
            (SurroundUITestContract.homeStatesStoneRemovalGameID, "scoring", ["Stone removal"]),
            (SurroundUITestContract.homeStatesUnknownClockGameID, "unknown-clock", ["Your move", "—"]),
        ]
        for (gameID, state, labels) in states {
            let board = elementAfterScrolling(ID.homeGame(gameID), in: app, within: home, matching: .button)
            XCTAssertTrue(pollUntil(timeout: 5) {
                large ? board.frame.width >= 266 : abs(board.frame.width - 120) <= 1
            }, "Home applies \(mode) display mode to the rendered board")
            revealHomeAuditCard(board, large: large, in: home, app: app)
            XCTAssertEqual(board.frame.width, board.frame.height, accuracy: 1)
            if large {
                XCTAssertGreaterThanOrEqual(board.frame.width, 266,
                                            "Large Home tiles retain detailed board rendering")
            } else {
                XCTAssertEqual(board.frame.width, 120, accuracy: 1,
                               "Compact Home rows retain their solid 120 pt boards")
            }
            for label in labels {
                XCTAssertTrue(board.label.contains(label), "The \(state) fixture exposes \(label)")
            }
            let name = "felt-meadow-home-\(appearance.rawValue)-\(mode.lowercased())-\(state)"
            let evidence = XCTAttachment(string: """
            Appearance: \(appearance.rawValue)
            Display mode: \(mode), verified by board geometry
            Appearance button accessibility value: \(picker.value ?? "absent")
            Fixture: \(gameID) (\(state))
            Board: \(board.frame)
            Accessible state: \(board.label)
            """)
            evidence.name = name + "-state"
            evidence.lifetime = .keepAlways
            add(evidence)
            keepScreenshot(name, in: app)
        }
    }

    private func revealHomeAuditCard(_ board: XCUIElement, large: Bool,
                                     in home: XCUIElement, app: XCUIApplication) {
        func viewport() -> CGRect {
            var frame = home.frame.intersection(app.frame)
            let navigation = app.navigationBars.firstMatch
            let tabs = app.tabBars.firstMatch
            let top = navigation.exists ? max(frame.minY, navigation.frame.maxY) : frame.minY
            let bottom = tabs.exists ? min(frame.maxY, tabs.frame.minY) : frame.maxY - 34
            frame.origin.y = top + 8
            frame.size.height = max(0, bottom - top - 16)
            return frame
        }
        func cardFrame() -> CGRect {
            // Large chips sit above and below the board; Compact chips share
            // its row. Capture the complete surfaces, not just a tappable stone.
            board.frame.insetBy(dx: 0, dy: large ? -46 : -10)
        }
        for _ in 0..<12 {
            let visible = viewport()
            if board.isHittable && visible.contains(cardFrame()) { return }
            guard dragScrollView(home, axis: .vertical, targetFrame: cardFrame(),
                                 containerFrame: visible, interactionPoint: CGVector(dx: 0.5, dy: 0.5),
                                 dragStartPoint: CGPoint(x: visible.midX, y: visible.midY),
                                 dragVelocity: .slow, dragHoldDuration: 0.2) else { break }
        }
        XCTAssertTrue(board.isHittable && viewport().contains(cardFrame()),
                      "The Home board and both clock chips must be fully visible for the material audit")
    }

    func testSurroundStudioThemePanelTransitions() throws {
        try auditThemePanelTransitions(theme: "surroundStudio", title: "Surround Studio", suffix: "-surround-studio")
    }

    func testFeltMeadowThemePanelTransitions() throws {
        try auditThemePanelTransitions(theme: "feltMeadow", title: "Felt Meadow", suffix: "-felt-meadow")
    }

    private func auditThemePanelTransitions(theme: String, title: String, suffix: String,
                                           appearance: SurroundUITestContract.Appearance? = .light,
                                           deviceAppearance: XCUIDevice.Appearance? = nil) throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "The compact theme transition audit requires an iPhone.")
        if let deviceAppearance {
            let device = XCUIDevice.shared
            let originalAppearance = device.appearance
            addTeardownBlock { device.appearance = originalAppearance }
            device.appearance = deviceAppearance
            XCTAssertTrue(pollUntil(timeout: 10) { device.appearance == deviceAppearance },
                          "Native toolbar evidence uses the requested device appearance")
            XCTAssertNil(appearance, "A fixture override must not mask the device's native toolbar appearance")
        }
        let app = launch(artboard: 1, theme: theme, appearance: appearance)
        if let deviceAppearance {
            XCTAssertFalse(app.launchArguments.contains(SurroundUITestContract.appearanceLaunchArgument))
            XCTAssertEqual(XCUIDevice.shared.appearance, deviceAppearance)
        }
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
        let board = element(ID.gameBoard, in: app)
        let value = board.value as? String
        for portrait in [true, false] {
            rotate(portrait ? .portrait : .landscapeLeft, app: app)
            XCTAssertEqual(board.value as? String, value, "Rotation retains the same game position")
            let orientation = portrait ? "portrait" : "landscape"
            auditStudioPanelTransitions(in: app) { step in
                if portrait, let deviceAppearance, step == "02-chat" {
                    // Check rendered pigment as well as the device getter in
                    // portrait, before rotating the same session. Landscape
                    // screenshot pixels carry orientation metadata; its full
                    // interactions, geometry and native captures remain audited.
                    // The trailing chat gutter avoids text and board artwork.
                    let chat = app.scrollViews[ID.gameChatLog].firstMatch.frame
                    let patch = CGRect(x: chat.maxX - 12, y: chat.midY, width: 6, height: 6)
                    let band: ClosedRange<Double> = deviceAppearance == .light ? 0.70...1 : 0...0.35
                    var observedBrightness: Double?
                    XCTAssertTrue(self.pollUntil(timeout: 10) {
                        guard let image = app.screenshot().image.cgImage else { return false }
                        observedBrightness = self.markerGalleryBrightness(in: patch, image: image, frame: app.frame)
                        guard let brightness = observedBrightness else { return false }
                        return band.contains(brightness)
                    }, "Chat must render the requested system palette while native toolbar controls remain usable; brightness=\(String(describing: observedBrightness)), expected=\(band), patch=\(patch), app=\(app.frame)")
                }
                self.capture(portrait ? 1 : 2, app: app,
                             note: "\(title) \(orientation), \(step). Same session; compare fixed decoration across panel transitions.",
                             suffix: "\(suffix)-transition-\(orientation)-\(step)")
            }
        }
    }

    private func auditThemeStates(theme: String, title: String, suffix: String,
                                  appearance: SurroundUITestContract.Appearance? = nil) throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "The compact theme audit requires an iPhone.")
        defer { XCUIDevice.shared.orientation = .portrait }
        let scenes: [(Scene, Int, Int, String)] = [
            (.activeGameBoard, 1, 2, "play"),
            (.activeGameBoard, 11, 12, "chat"),
            (.gameAnalysis, 22, 23, "analyze"),
            (.zenMode, 36, 37, "zen"),
        ]
        for (scene, portrait, landscape, state) in scenes {
            let app = launch(scene, artboard: portrait, theme: theme, appearance: appearance)
            if state == "chat" { startChat(in: app, typing: false) }
            if state == "analyze" {
                XCTAssertFalse(app.scrollViews[ID.gameChatLog].exists,
                               "The themed Analyze view remains the only open panel")
                assertSelectedBranchVisible(["lj", "lk", "mk"], in: app)
            }
            let board = element(ID.gameBoard, in: app)
            let value = board.value as? String
            XCTAssertNotNil(value, "The audit records an identifiable board position")
            capture(portrait, app: app, note: "\(title) \(state), portrait.",
                    suffix: suffix)
            rotate(.landscapeLeft, app: app)
            XCTAssertEqual(board.value as? String, value, "Rotation retains the displayed position")
            if state == "analyze" { assertSelectedBranchVisible(["lj", "lk", "mk"], in: app) }
            if state == "zen" { element(ID.gameZenExit, in: app, matching: .button) }
            capture(landscape, app: app, note: "\(title) \(state), native landscape.",
                    suffix: suffix)
            app.terminate()
        }
    }

    func testRakedGardenThemeScoring() throws {
        try auditThemeScoring(theme: "rakedGarden", title: "Raked Garden", suffix: "-raked-garden",
                              appearance: .light)
    }

    func testRakedGardenNightThemeScoring() throws {
        try auditThemeScoring(theme: "rakedGarden", title: "Raked Garden at night",
                              suffix: "-raked-garden-night", appearance: .dark)
    }

    func testSurroundStudioThemeScoring() throws {
        try auditThemeScoring(theme: "surroundStudio", title: "Surround Studio", suffix: "-surround-studio",
                              appearance: .light)
    }

    func testSurroundStudioNightThemeScoring() throws {
        try auditThemeScoring(theme: "surroundStudio", title: "Surround Studio at night",
                              suffix: "-surround-studio-night", appearance: .dark)
    }

    func testFeltMeadowThemeScoring() throws {
        try auditThemeScoring(theme: "feltMeadow", title: "Felt Meadow", suffix: "-felt-meadow", appearance: .light)
    }

    func testFeltMeadowNightThemeScoring() throws {
        try auditThemeScoring(theme: "feltMeadow", title: "Felt Meadow at night", suffix: "-felt-meadow-night",
                              appearance: .dark)
    }

    private func auditThemeScoring(theme: String, title: String, suffix: String,
                                   appearance: SurroundUITestContract.Appearance? = nil) throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "The compact scoring audit requires an iPhone.")
        let app = launch(artboard: 64, theme: theme, appearance: appearance)
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Accept"].firstMatch.waitForExistence(timeout: 5),
                      "The theme retains the stone-removal action")
        XCTAssertTrue(app.buttons["Accept"].firstMatch.isEnabled,
                      "The connected scoring fixture keeps Accept usable")
        capture(64, app: app, note: "\(title) removed-stone marks and scoring overlays.",
                suffix: suffix)
        tap("game.clock.black", in: app)
        capture(65, app: app, note: "\(title) score details.",
                suffix: suffix)
    }

    /// Use the small-phone fixtures on an SE-size simulator; unlike the
    /// full-size portrait analysis artboard, these do not require four rows.
    func testRakedGardenThemeSmallPhone() throws {
        try auditThemeSmallPhone(theme: "rakedGarden", title: "Raked Garden", suffix: "-raked-garden",
                                 appearance: .light)
    }

    func testRakedGardenNightThemeSmallPhone() throws {
        try auditThemeSmallPhone(theme: "rakedGarden", title: "Raked Garden at night",
                                 suffix: "-raked-garden-night", appearance: .dark)
    }

    func testSurroundStudioThemeSmallPhone() throws {
        try auditThemeSmallPhone(theme: "surroundStudio", title: "Surround Studio", suffix: "-surround-studio",
                                 appearance: .light)
    }

    func testSurroundStudioNightThemeSmallPhone() throws {
        try auditThemeSmallPhone(theme: "surroundStudio", title: "Surround Studio at night",
                                 suffix: "-surround-studio-night", appearance: .dark)
    }

    func testFeltMeadowThemeSmallPhone() throws {
        try auditThemeSmallPhone(theme: "feltMeadow", title: "Felt Meadow", suffix: "-felt-meadow", appearance: .light)
    }

    func testFeltMeadowNightThemeSmallPhone() throws {
        try auditThemeSmallPhone(theme: "feltMeadow", title: "Felt Meadow at night", suffix: "-felt-meadow-night",
                                 appearance: .dark)
    }

    private func auditThemeSmallPhone(theme: String, title: String, suffix: String,
                                      appearance: SurroundUITestContract.Appearance? = nil) throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "The small-phone theme audit requires an iPhone.")
        for (scene, number, state) in [
            (Scene.activeGameBoard, 81, "play"),
            (.gameAnalysis, 82, "analyze"),
            (.activeGameBoard, 83, "scoring"),
        ] {
            let app = launch(scene, artboard: number, theme: theme, appearance: appearance)
            if scene == .gameAnalysis { assertSelectedBranchVisible(["lj", "lk", "mk"], in: app) }
            if state == "scoring" {
                let accept = app.buttons["Accept"].firstMatch
                XCTAssertTrue(accept.waitForExistence(timeout: 5))
                XCTAssertTrue(accept.isEnabled, "The smaller scoring fixture keeps Accept usable")
            }
            capture(number, app: app, note: "\(title) small-phone \(state).",
                    suffix: suffix)
            if theme == "feltMeadow", state == "play" {
                tap(app.navigationBars.buttons.element(boundBy: 0), description: "Return to Home", in: app)
                element(ID.screenHome, in: app)
                keepScreenshot("\(suffix.dropFirst())-small-phone-home-after-back", in: app)
            }
            app.terminate()
        }
    }

    func testPhoneChat() {
        let app = launch(artboard: 11)
        startChat(in: app, typing: false)
        capture(11, app: app, note: "Design-matched chat history; keyboard dismissed.")
        rotate(.landscapeLeft, app: app)
        capture(12, app: app, note: "Design-matched chat history; keyboard dismissed.")
        rotate(.portrait, app: app)
        tap(ID.gameChatBoardHide, in: app, matching: .button)
        capture(16, app: app, note: "Chat with Hide main board selected.")
    }

    func testPhoneAnalyze() {
        let app = launch(.gameAnalysis, artboard: 22)
        capture(22, app: app, note: "Design audit analysis position; accepted native tree styling.")
        rotate(.landscapeLeft, app: app)
        capture(23, app: app, note: "Design audit analysis position in native landscape.")
    }

    func testCompactChatExitRestoresZenAccess() {
        let app = launch()
        setGameAnalyzing(true, in: app)
        openGameChat(in: app)
        dismissSoftwareKeyboardIfNeeded(in: app)
        setGameChatVisible(false, in: app)
        XCTAssertFalse(gameToolbarToggleIsOn(gameAnalyzeControl(in: app)))
        XCTAssertFalse(gameToolbarToggleIsOn(gameChatControl(in: app)))
        tap(ID.gameZenEnter, in: app, matching: .button)
        element(ID.gameZenExit, in: app, matching: .button)
        keepScreenshot("compact-chat-exit-restores-zen", in: app)
    }

    func testLiveGameBannerOpensOutsideZenFromCorrespondence() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.liveGameBannerNavigationLaunchArgument,
        ], orientation: .portrait)
        let correspondenceID = SurroundUITestContract.liveBannerCorrespondenceGameIDs[0]
        let correspondence = elementAfterScrolling(ID.homeGame(correspondenceID), in: app)
        scrollIntoTappableArea(correspondence, in: app)
        tap(correspondence, description: "Open correspondence game", in: app)
        element(ID.gameDetail(correspondenceID), in: app)

        tap(ID.gameZenEnter, in: app, matching: .button)
        element(ID.gameZenExit, in: app, matching: .button)
        let banner = element(ID.liveGameBanner, in: app, matching: .button)
        keepScreenshot("live-banner-visible-in-correspondence-zen", in: app)
        tap(banner, description: "Open active live game from Zen", in: app)

        element(ID.gameDetail(SurroundUITestContract.fixtureGameID), in: app)
        XCTAssertFalse(banner.exists, "The live-game banner must disappear on the live board.")
        XCTAssertFalse(app.buttons[ID.gameZenExit].exists,
                       "Switching from correspondence to live must leave Zen mode.")
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: ID.gameActiveGamesCarousel).firstMatch.exists,
                       "The correspondence carousel must not remain on the live game.")
        XCTAssertFalse(app.navigationBars.buttons["Close"].exists,
                       "The live game must use the existing navigation stack.")
        keepScreenshot("live-banner-opens-live-game-outside-zen", in: app)
    }

    func testPhoneZen() {
        let app = launch(.zenMode, artboard: 36)
        capture(36, app: app, note: "Design-matched fixture in Zen mode.")
        rotate(.landscapeLeft, app: app)
        // Rotation temporarily reveals the system gesture affordance. Capture
        // the settled edge-deferral state, as in the Duo landscape audit.
        Thread.sleep(forTimeInterval: 10)
        capture(37, app: app, note: "Design-matched fixture in Zen mode, native landscape.")
    }

    func testPhoneSpectating() {
        let app = launch(.publicGameSpectator, artboard: 46)
        capture(46, app: app, note: "Design-matched spectator players, clock and board.")
    }

    /// Rule 19: your name comes first. A row chip never truncates its name
    /// while its row has unused width (live Beta: "hakho…" beside free space).
    private func assertTeamChipNamesFit(_ context: String, in app: XCUIApplication,
                                        file: StaticString = #filePath, line: UInt = #line) {
        for side in ["black", "white"] {
            let probe = app.descendants(matching: .any).matching(identifier: "game.identity.nameFit.\(side)").firstMatch
            guard probe.waitForExistence(timeout: 5) else { continue }
            let value = probe.value as? String ?? ""
            print("[RengoNameFit] \(context) \(side) \(value)")
            let chips = app.buttons.matching(NSPredicate(format: "label CONTAINS 'hakhoa' OR label CONTAINS 'bob_k' OR label CONTAINS 'tenuki'"))
                .allElementsBoundByIndex.map { "\($0.label)@\($0.frame)" }
            let more = app.descendants(matching: .any).matching(identifier: "game.actions").firstMatch
            print("[RengoNameFit] \(context) chips=\(chips) more=\(more.exists ? "\(more.frame)" : "-")")
            XCTAssertTrue(value.hasPrefix("full"), "\(context): the \(side) team chip shows its full name (\(value))",
                          file: file, line: line)
        }
    }

    func testPhoneRengo() {
        let app = launch(artboard: 49)
        capture(49, app: app, note: "Design-matched Rengo team names and order; two visible avatars.")
        assertTeamChipNamesFit("artboard 49 portrait", in: app)
        // Game details (the clock's popover) list both whole teams in turn
        // order, not only the pair at the board.
        tap("game.clock.white", in: app, matching: .button)
        let teams = element("game.details.rengoTeams", in: app)
        for name in ["tenuki_tom", "dave", "emma", "bob_k", "carol", "kosumi"] {
            XCTAssertTrue(teams.descendants(matching: .any)
                            .matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch.exists,
                          "Game details list \(name)")
        }
        keepScreenshot("rengo-game-details-both-teams", in: app)
        dismissPopover(in: app)
        let team = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "kosumi"
        )).firstMatch
        tap(team, description: "Open own team turn order", in: app)
        element("game.team.details", in: app)
        XCTAssertTrue(app.popovers.firstMatch.exists, "The team list is a popover anchored to the team chip")
        capture(52, app: app, note: "Own-team details from the design-matched White team, as an opaque popover.")
        app.terminate()
        // The live game's shape: your team's next player beside Pass and More.
        let live = launch(artboard: 1, players: "rengo-live")
        assertTeamChipNamesFit("rengo-live portrait", in: live)
        keepScreenshot("rengo-own-chip-portrait", in: live)
        // You are your team's next player: one "You · next" pill, not two.
        let ownTeam = live.buttons.matching(NSPredicate(format: "label BEGINSWITH 'hakhoa3'")).firstMatch
        tap(ownTeam, description: "Open own team turn order", in: live)
        element("game.team.details", in: live)
        let popover = live.descendants(matching: .any).matching(identifier: "game.team.details").firstMatch
        // Row buttons merge their texts into one label.
        XCTAssertTrue(popover.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'You · next'"))
                        .firstMatch.waitForExistence(timeout: 5), "One combined pill when you are next")
        keepScreenshot("rengo-team-popover-you-next", in: live)
        dismissPopover(in: live)
        rotate(.landscapeLeft, app: live)
        Thread.sleep(forTimeInterval: 1)
        assertTeamChipNamesFit("rengo-live landscape", in: live)
        keepScreenshot("rengo-own-chip-landscape", in: live)
        rotate(.portrait, app: live)
    }

    func testPhoneLongNames() {
        let app = launch(artboard: 53)
        capture(53, app: app, note: "Design-matched long player names.")
    }

    func testPhoneLargeText() {
        for (number, size) in [(56, UIContentSizeCategory.extraExtraExtraLarge),
                               (57, UIContentSizeCategory.accessibilityExtraLarge)] {
            let app = launch(artboard: number, textSize: size)
            capture(number, app: app, note: "Dynamic Type \(size.rawValue); design-matched players and board.")
            app.terminate()
        }
    }

    func testEstimateScoreKeepsBoardStableWithNarrowAndLargeText() {
        for (suffix, size) in [("-estimate-narrow", UIContentSizeCategory.large),
                               ("-estimate-ax3", UIContentSizeCategory.accessibilityExtraLarge)] {
            let app = launch(artboard: 53, textSize: size)
            let board = element(ID.gameBoard, in: app)
            let originalFrame = board.frame
            tap(ID.gameActionsMenu, in: app, matching: .button)
            tap(app.buttons["Estimate score"].firstMatch,
                description: "Estimate the current playing position", in: app)

            let clear = app.buttons["Clear estimates"].firstMatch
            XCTAssertTrue(clear.waitForExistence(timeout: 30))
            let more = element(ID.gameActionsMenu, in: app, matching: .button)
            capture(77, app: app,
                    note: "Playing phase after Estimate score, long names, \(size.rawValue). The visible Clear estimates label is outside the playing-phase reservation by design.",
                    suffix: suffix)
            XCTAssertEqual(board.frame.minX, originalFrame.minX, accuracy: 1)
            XCTAssertEqual(board.frame.minY, originalFrame.minY, accuracy: 1)
            XCTAssertEqual(board.frame.width, originalFrame.width, accuracy: 1)
            XCTAssertEqual(board.frame.height, originalFrame.height, accuracy: 1)
            XCTAssertGreaterThanOrEqual(clear.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(clear.frame.maxX, app.frame.maxX + 1)
            XCTAssertLessThanOrEqual(clear.frame.maxY, app.frame.maxY + 1)
            XCTAssertTrue(clear.isHittable && more.isHittable)
            let frameEvidence = XCTAttachment(string: """
                Clear estimates: \(clear.frame)
                More: \(more.frame)
                Board: \(board.frame)
                Accessibility hierarchy:
                \(app.debugDescription)
                """)
            frameEvidence.name = "action-frames" + suffix
            frameEvidence.lifetime = .keepAlways
            add(frameEvidence)
            let navigationFrame = app.navigationBars.firstMatch.frame
            let dismissMenu = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: navigationFrame.midX - app.frame.minX,
                dy: navigationFrame.midY - app.frame.minY
            ))
            tap(more, description: "Open More beside Clear estimates", in: app)
            XCTAssertTrue(app.buttons["Estimate score"].firstMatch.waitForExistence(timeout: 5),
                          "Activating More must open its menu without clearing the estimate")
            keepScreenshot("more-open" + suffix, in: app)
            dismissMenu.tap()
            XCTAssertTrue(clear.waitForExistence(timeout: 5),
                          "Dismissing More must preserve the score estimate")
            XCTAssertEqual(more.frame.width, more.frame.height, accuracy: 1, "More stays a circle")
            if size == .large {
                XCTAssertEqual(more.frame.width, 44, accuracy: 1)
            } else {
                XCTAssertGreaterThanOrEqual(more.frame.height, 54,
                                            "At accessibility sizes More grows with the large main action")
            }
            XCTAssertLessThanOrEqual(clear.frame.maxX, more.frame.minX + 1,
                                     "The current action keeps its width without covering More")

            tap(clear, description: "Clear the local score estimate", in: app)
            XCTAssertTrue(pollUntil(timeout: 5) { !clear.exists })
            XCTAssertEqual(board.frame, originalFrame,
                           "Clearing an estimate must retain the playing-phase board frame")
            app.terminate()
        }
    }

    func testPhoneClockDetails() {
        let app = launch(artboard: 60)
        tap("game.clock.black", in: app)
        element("game.details", in: app)
        XCTAssertTrue(app.popovers.firstMatch.exists, "Game details are a popover anchored to the clock")
        capture(60, app: app, note: "Opaque clock details popover from the design-matched fixture.")
    }

    func testFrostPineControlInteractions() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "This smoke test covers the phone's full and inline Frost controls.")
        let app = launch(artboard: 1, theme: "frostPine", appearance: .light)
        defer { app.terminate() }
        let position = element(ID.gameBoard, in: app).value as? String
        XCTAssertNotNil(position, "The smoke test retains an identifiable game position")

        tap("game.clock.black", in: app, matching: .button)
        element("game.details", in: app)
        XCTAssertTrue(app.popovers.firstMatch.exists, "The full Frost clock opens its details")
        keepScreenshot("frost-pine-interaction-full-clock-details", in: app)
        dismissPopover(in: app)

        for (entry, name) in [(ID.profileBannerAvatarEntry(915_100), "avatar"),
                              (ID.profileBannerNameEntry(915_100), "name")] {
            tap(entry, in: app, matching: .button)
            element(ID.screenPlayerProfile, in: app)
            keepScreenshot("frost-pine-interaction-profile-\(name)", in: app)
            navigateBackFromPlayerProfile(in: app)
            XCTAssertEqual(element(ID.gameBoard, in: app).value as? String, position,
                           "Returning from the \(name) keeps the game position")
        }

        startChat(in: app, typing: false)
        let inlineClock = app.navigationBars.buttons.matching(identifier: "game.clock.black").firstMatch
        tap(inlineClock, description: "Open the inline Frost clock", in: app)
        XCTAssertTrue(app.staticTexts["Time control"].waitForExistence(timeout: 5))
        for color in ["black", "white"] {
            element("game.details.clock.\(color)", in: app)
        }
        keepScreenshot("frost-pine-interaction-inline-clock-details", in: app)
    }

    func testSingleClockDetailsRetainsBothTimes() {
        let app = launch(artboard: 11)
        startChat(in: app, typing: false)
        XCTAssertTrue(app.buttons["game.clock.black"].exists)
        XCTAssertFalse(app.buttons["game.clock.white"].exists)
        tap("game.clock.black", in: app)
        XCTAssertTrue(app.staticTexts["Time control"].waitForExistence(timeout: 5))
        capture(60, app: app, note: "The single-clock Chat title opens details with both players' time remaining.",
                suffix: "-single-clock")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "single-clock-details-accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let black = app.descendants(matching: .any).matching(identifier: "game.details.clock.black").firstMatch
        let white = app.descendants(matching: .any).matching(identifier: "game.details.clock.white").firstMatch
        XCTAssertTrue(black.exists, "Details retain the current black clock")
        XCTAssertTrue(white.exists, "The hidden white clock remains available in details")
        XCTAssertTrue((black.value as? String)?.contains("4:32") == true)
        XCTAssertTrue((white.value as? String)?.contains("6:15") == true)
    }

    func testPhoneScoring() {
        let app = launch(artboard: 64)
        capture(64, app: app, note: "Design-matched stone-removal position and score record.")
        tap("game.clock.black", in: app)
        capture(65, app: app, note: "Score details from the design-matched stone-removal fixture.")
        app.terminate()
        let zen = launch(.zenMode, artboard: 66)
        capture(66, app: zen, note: "Design-matched stone-removal position in Zen.")
    }

    func testPhoneKeyboard() {
        let app = launch(artboard: 67)
        openGameChat(in: app)
        let input = element(ID.gameChatInput, in: app, matching: .textField)
        XCTAssertFalse(pollUntil(timeout: 2) { self.chatInputHasKeyboardFocus(in: app) },
                       "Opening chat must not focus the composer or raise the keyboard")
        XCTAssertFalse(keyboardIsOnscreen(in: app))
        let portraitBoard = element(ID.gameBoard, in: app).frame
        let portraitClock = element("game.clock.black", in: app, matching: .button).frame
        tap(input, description: "Focus the chat composer", in: app)
        input.typeText(SurroundUITestContract.gameDetailDesignChatDraft)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(pollUntil(timeout: 10) { self.keyboardIsOnscreen(in: app) },
                      "The overlay check requires a visible software keyboard")
        XCTAssertTrue(pollUntil(timeout: 5) {
            let board = app.descendants(matching: .any).matching(identifier: ID.gameBoard).firstMatch
            let clock = app.buttons["game.clock.black"].firstMatch
            return board.exists && clock.exists
                && abs(board.frame.minX - portraitBoard.minX) < 1
                && abs(board.frame.minY - portraitBoard.minY) < 1
                && abs(board.frame.width - portraitBoard.width) < 1
                && abs(clock.frame.width - portraitClock.width) < 1
                && abs(clock.frame.height - portraitClock.height) < 1
        }, "Portrait typing covers the same board and keeps its clock size")
        capture(67, app: app, note: "Actual software keyboard and typed chat draft.")
        rotate(.landscapeLeft, app: app)
        // Rotation can briefly retain the old keyboard accessibility element.
        // Require the landscape keyboard to remain visible after that handoff;
        // refocusing here would conceal a lost first responder during rotation.
        var keyboardVisibleSince: Date?
        let retainedLandscapeKeyboard = pollUntil(timeout: 10) {
            let keyboard = app.keyboards.firstMatch
            guard self.keyboardIsOnscreen(in: app),
                  keyboard.frame.width > app.frame.height else {
                keyboardVisibleSince = nil
                return false
            }
            if keyboardVisibleSince == nil { keyboardVisibleSince = Date() }
            return Date().timeIntervalSince(keyboardVisibleSince!) >= 1
        }
        if !retainedLandscapeKeyboard {
            // Keep the failed state before continueAfterFailure ends the test.
            // Reading evidence must not tap, refocus or alter this assertion.
            let input = app.textFields[ID.gameChatInput].firstMatch
            let keyboard = app.keyboards.firstMatch
            let board = app.descendants(matching: .any).matching(identifier: ID.gameBoard).firstMatch
            let layout = app.descendants(matching: .any).matching(identifier: "game.layout.geometry").firstMatch
            let evidence = XCTAttachment(string: """
            Window: \(app.frame)
            Input focus: \(chatInputHasKeyboardFocus(in: app))
            Input frame: \(input.exists ? String(describing: input.frame) : "absent")
            Input value: \(input.exists ? String(describing: input.value) : "absent")
            Keyboard frame: \(keyboard.exists ? String(describing: keyboard.frame) : "absent")
            Board frame: \(board.exists ? String(describing: board.frame) : "absent")
            Layout: \(layout.exists ? String(describing: layout.value) : "absent")

            \(app.debugDescription)
            """)
            evidence.name = "keyboard-rotation-failure-state"
            evidence.lifetime = .keepAlways
            add(evidence)
            keepScreenshot("keyboard-rotation-failure", in: app)
        }
        XCTAssertTrue(retainedLandscapeKeyboard,
                      "The rotated composer retains a settled landscape software keyboard")
        // v145: typing never hides the board. It stays beside chat; the
        // keyboard covers its lower part, and the conversation ends above it.
        let typingBoard = app.descendants(matching: .any).matching(identifier: ID.gameBoard).firstMatch
        XCTAssertTrue(pollUntil(timeout: 5) {
            typingBoard.exists && typingBoard.frame.width > 200 && typingBoard.frame.height > 200
        }, "Landscape typing keeps the board")
        let landscapeTypingBoard = typingBoard.frame
        XCTAssertLessThanOrEqual(input.frame.maxY, app.keyboards.firstMatch.frame.minY - 6,
                                 "The conversation ends above the keyboard")
        capture(68, app: app, note: "Same draft with actual landscape software keyboard; the board stays.")
        tap("game.clock.black", in: app)
        XCTAssertTrue(pollUntil(timeout: 5) { !app.keyboards.firstMatch.exists },
                      "First header clock tap dismisses the keyboard")
        XCTAssertFalse(app.staticTexts["Time control"].exists,
                       "First header clock tap must not open clock details")
        let board = app.descendants(matching: .any).matching(identifier: ID.gameBoard).firstMatch
        XCTAssertTrue(pollUntil(timeout: 5) {
            board.exists && abs(board.frame.minX - landscapeTypingBoard.minX) < 1
                && abs(board.frame.minY - landscapeTypingBoard.minY) < 1
                && abs(board.frame.width - landscapeTypingBoard.width) < 1
        }, "Dismissing the keyboard leaves the landscape board where it was")
        XCTAssertEqual(element(ID.gameChatInput, in: app, matching: .textField).value as? String,
                       SurroundUITestContract.gameDetailDesignChatDraft,
                       "Header dismissal retains the unsent chat draft")
        capture(68, app: app, note: "Header clock dismissed the keyboard without opening details; the unsent draft remains.",
                suffix: "-keyboard-dismissed")
        tap("game.clock.black", in: app)
        XCTAssertTrue(app.staticTexts["Time control"].waitForExistence(timeout: 5),
                      "Second clock tap opens clock details")
    }

    func testDuoClosedKeyboardKeepsBoardAndMatchedClocks() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SURROUND_EXPECT_CLOSED_DUO"] == "1",
                          "Run on a Duo in the verified Closed portrait pose.")
        let app = launch(artboard: 15)
        openDuoChat(in: app)
        dismissSoftwareKeyboardIfNeeded(in: app)
        let board = element(ID.gameBoard, in: app)
        let black = element("game.clock.black", in: app, matching: .button)
        let white = element("game.clock.white", in: app, matching: .button)
        let boardFrame = board.frame, blackFrame = black.frame, whiteFrame = white.frame
        XCTAssertEqual(blackFrame.width, whiteFrame.width, accuracy: 1)
        XCTAssertEqual(blackFrame.height, whiteFrame.height, accuracy: 1)
        let input = element(ID.gameChatInput, in: app, matching: .textField)
        tap(input, description: "Focus Duo chat", in: app)
        input.typeText("Overlay keyboard draft")
        XCTAssertTrue(pollUntil(timeout: 10) { self.keyboardIsOnscreen(in: app) })
        XCTAssertTrue(pollUntil(timeout: 5) {
            abs(board.frame.minX - boardFrame.minX) < 1
                && abs(board.frame.minY - boardFrame.minY) < 1
                && abs(board.frame.width - boardFrame.width) < 1
                && abs(black.frame.width - blackFrame.width) < 1
                && abs(white.frame.width - whiteFrame.width) < 1
                && abs(black.frame.height - blackFrame.height) < 1
                && abs(white.frame.height - whiteFrame.height) < 1
        }, "Closed portrait keeps the board and both matched clocks fixed behind its keyboard")
        XCTAssertLessThanOrEqual(input.frame.maxY, app.keyboards.firstMatch.frame.minY + 2)
        keepScreenshot("duo-closed-keyboard-overlays-fixed-board", in: app)
        dismissSoftwareKeyboardIfNeeded(in: app)
        XCTAssertEqual(input.value as? String, "Overlay keyboard draft")
        XCTAssertEqual(board.frame.width, boardFrame.width, accuracy: 1)
        keepScreenshot("duo-closed-keyboard-dismissed-fixed-board", in: app)
        // With the keyboard up again, the Chat toggle closes chat.
        tap(input, description: "Focus Duo chat again", in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { self.keyboardIsOnscreen(in: app) })
        let overflow = closeChatWhileTyping("Overlay keyboard draft", in: app)
        print("[DuoChatToggleWhileTyping] closed-portrait overflow=\(overflow)")
    }

    func testDuoClosedLandscapeKeyboardKeepsMatchedClocks() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SURROUND_EXPECT_CLOSED_DUO_LANDSCAPE"] == "1",
                          "Run on a Duo in the verified Closed landscape pose.")
        // Device Hub owns Duo's physical pose; XCTest rotation alone cannot
        // change it. Verify the host-provided pose before measuring the scene.
        let app = launch(artboard: 15, orientation: .landscapeLeft)
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        openDuoChat(in: app)
        let input = element(ID.gameChatInput, in: app, matching: .textField)
        dismissSoftwareKeyboardIfNeeded(in: app)
        let board = app.descendants(matching: .any).matching(identifier: ID.gameBoard).firstMatch
        let black = element("game.clock.black", in: app, matching: .button)
        let white = element("game.clock.white", in: app, matching: .button)
        let landscapeBlack = element("game.clock.black", in: app, matching: .button).frame
        let landscapeWhite = element("game.clock.white", in: app, matching: .button).frame
        XCTAssertEqual(landscapeBlack.width, landscapeWhite.width, accuracy: 1)
        XCTAssertEqual(landscapeBlack.height, landscapeWhite.height, accuracy: 1)
        let restingBoard = board.frame
        tap(input, description: "Focus landscape Duo chat", in: app)
        input.typeText("Landscape draft")
        XCTAssertTrue(pollUntil(timeout: 10) { self.keyboardIsOnscreen(in: app) })
        XCTAssertTrue(pollUntil(timeout: 5) {
            board.exists && abs(board.frame.minX - restingBoard.minX) < 1
                && abs(board.frame.minY - restingBoard.minY) < 1
                && abs(board.frame.width - restingBoard.width) < 1
                && abs(black.frame.minX - landscapeBlack.minX) < 1
                && abs(black.frame.minY - landscapeBlack.minY) < 1
                && abs(black.frame.width - landscapeBlack.width) < 1
                && abs(white.frame.width - landscapeWhite.width) < 1
        }, "Landscape typing keeps the board and the stacked clock pair in place")
        XCTAssertLessThanOrEqual(input.frame.maxY, app.keyboards.firstMatch.frame.minY - 6,
                                 "The conversation ends above the keyboard")
        keepScreenshot("duo-closed-landscape-keyboard-fixed-clocks", in: app)
        // The keyboard pushes Chat into the vertical toolbar's overflow;
        // choosing it there closes chat and keeps the draft.
        let overflow = closeChatWhileTyping("Landscape draft", in: app)
        print("[DuoChatToggleWhileTyping] closed-landscape overflow=\(overflow)")
    }

    func testPhoneSharingKeyboard() {
        let app = launch(.gameAnalysis, artboard: 72)
        tap(ID.gameAnalyzeActionsMenu, in: app)
        tap(analyzeMenuItem(ID.gameAnalyzeShare, catalystTitle: "Share variation in chat", in: app),
            description: "Prepare a variation draft", in: app)
        let input = element(ID.gameChatInput, in: app, matching: .textField)
        // Sharing already requests focus. Tapping an already-focused empty
        // field can open Paste/AutoFill rather than show the software keyboard.
        let automaticallyFocused = pollUntil(timeout: 10) {
            self.chatInputHasKeyboardFocus(in: app)
                && self.keyboardIsOnscreen(in: app)
        }
        if !automaticallyFocused {
            capture(72, app: app, note: "Variation sharing did not automatically focus its name field with an onscreen keyboard.",
                    suffix: "-focus-failure")
        }
        XCTAssertTrue(automaticallyFocused,
                      "Sharing a variation automatically focuses its name field and presents the software keyboard")
        guard automaticallyFocused else { return }
        capture(72, app: app, note: "Design-matched three-move variation with an empty focused name field and visible software keyboard.")
        input.typeText("Atari")
        XCTAssertEqual(input.value as? String, "Atari",
                       "The focused field accepts and retains the variation name")
        let keyboardShown = pollUntil(timeout: 10) { self.keyboardIsOnscreen(in: app) }
        capture(72, app: app, note: "The variation draft accepts and retains its typed name. Onscreen software keyboard: \(keyboardShown).",
                suffix: "-typed-draft")
        XCTAssertTrue(keyboardShown, "Capture requires a visible software keyboard, not an offscreen accessory")
    }

    func testSEScenes() {
        let play = launch(artboard: 81)
        XCTAssertEqual(play.frame.width, 375, accuracy: 1, "SE artboards require the native 375-point viewport")
        XCTAssertEqual(play.frame.height, 667, accuracy: 1, "SE artboards require the native 667-point viewport")
        capture(81, app: play, note: "Native iPhone SE viewport; design-matched fixture.")
        play.terminate()
        let analyze = launch(.gameAnalysis, artboard: 82)
        assertSelectedBranchVisible(["lj", "lk", "mk"], in: analyze)
        // Both branches end at move 41. Changing only branch level must reveal
        // the new selection just as entering Analyze does.
        tap(ID.gameAnalyzeNextBranch, in: analyze, matching: .button)
        assertSelectedBranchVisible(["lj", "mj", "nj"], in: analyze)
        tap(ID.gameAnalyzePreviousBranch, in: analyze, matching: .button)
        assertSelectedBranchVisible(["lj", "lk", "mk"], in: analyze)
        capture(82, app: analyze, note: "Native iPhone SE viewport; design audit analysis position.")
        analyze.terminate()
        let scoring = launch(artboard: 83)
        capture(83, app: scoring, note: "Native iPhone SE viewport; design-matched stone-removal fixture.")
    }

    func testChatUnreadBadgeClearsAfterReading() {
        let app = launch(artboard: 81)
        let number = app.frame.width < 380 ? 81 : 1
        let chat = app.buttons[ID.gameDisplayModePicker + ".chat"]
        XCTAssertTrue(chat.waitForExistence(timeout: 5))
        XCTAssertEqual(chat.value as? String, "3")
        capture(number, app: app, note: "The bottom toolbar displays the three unread fixture messages.", suffix: "-unread-badge")
        startChat(in: app, typing: false)
        XCTAssertNotEqual(chat.value as? String, "3")
        setGameChatVisible(false, in: app)
        XCTAssertNotEqual(chat.value as? String, "3", "Reading the conversation clears its unread badge after closing Chat.")
        capture(number, app: app, note: "Reading Chat clears the unread badge without changing the toolbar target.", suffix: "-chat-read")
    }

    func testPhoneNotificationAccess() {
        let app = launch()
        // Messages use the app's notice row, which shows only for unread
        // messages (SurroundUITests covers it over Game Detail); this fixture
        // has none, so the toolbar is drawn without it.
        XCTAssertFalse(app.buttons["global.privateMessages"].exists,
                       "The design review fixture starts without private messages")
        keepScreenshot("game-settings-toolbar-without-message-badge", in: app)
        tap(ID.gameOptions, in: app, matching: .button)
        element(ID.screenGameOptions, in: app)
        XCTAssertTrue(app.switches["Board coordinates"].exists)
        capture(1, app: app, note: "Settings contains gameplay preferences only, with no message route or added message toolbar control.",
                suffix: "-notification-access")
    }

    func testPausedClockKeepsTheTurnBadge() {
        // Canvas Clock table states 5 and 10, rule 18: while paused the side
        // to move keeps its badge (no hourglass, no glow); the pause reason
        // stays on the sub-line.
        let app = launch(artboard: 79, clock: "paused", fromMainNavigation: false)
        let turnLabels = ["Your move", "Their move", "To move", "Teammate"]
        let values = ["game.clock.black", "game.clock.white"].map {
            element($0, in: app, matching: .button).value as? String ?? ""
        }
        print("[PausedBadge] cards \(values)")
        let badged = values.filter { value in turnLabels.contains { value.hasPrefix($0) } }
        XCTAssertEqual(badged.count, 1, "Exactly the side to move keeps its turn badge while paused: \(values)")
        XCTAssertFalse(values.contains { $0.contains("running") }, "A paused clock never runs")
        XCTAssertTrue(values.contains { $0.contains("Weekend") }, "The pause reason stays")
        capture(79, app: app, note: "Paused (weekend): the side to move keeps its badge, without hourglass or glow.",
                suffix: "-paused-turn-badge")
        // Chat folds the clock into the title slot's single chip, which keeps
        // its turn label while paused.
        openGameChat(in: app)
        dismissSoftwareKeyboardIfNeeded(in: app)
        let chips = app.navigationBars.buttons.matching(NSPredicate(
            format: "identifier == 'game.clock.black' OR identifier == 'game.clock.white'")).allElementsBoundByIndex
        let chipValues = chips.map { $0.value as? String ?? "" }
        print("[PausedBadge] title chips \(chipValues)")
        XCTAssertTrue(chipValues.contains { value in turnLabels.contains { value.hasPrefix($0) } },
                      "The title chip keeps Your move / Their move while paused: \(chipValues)")
        keepScreenshot("paused-chat-title-chip", in: app)
    }

    func testPhoneClockReferences() {
        let allStates = ["byoyomi-main", "byoyomi-overtime", "sudden-death", "fischer",
                      "canadian-main", "canadian-overtime", "simple", "absolute", "untimed",
                      "not-started", "first-move", "paused", "disconnected", "stone-removal",
                      "finished-points", "finished-resignation", "finished-timeout", "draw", "annulled", "canceled"]
        let requested = ProcessInfo.processInfo.environment["SURROUND_CLOCK_AUDIT_STATES"]?
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let states = requested.map { requested in allStates.filter { requested.contains($0) } } ?? allStates
        XCTAssertFalse(states.isEmpty, "The clock-state filter must select at least one supported state.")
        for state in states {
            let number = ["not-started", "paused", "disconnected", "stone-removal",
                          "finished-points", "finished-resignation", "finished-timeout", "draw", "annulled", "canceled"].contains(state) ? 79 : 78
            let app = launch(artboard: number, clock: state, fromMainNavigation: false)
            capture(number, app: app, note: "Design audit clock fixture: \(state).", suffix: "-" + state)
            app.terminate()
        }
    }

    // MARK: v148 connection feedback

    private func connectionBanner(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: ID.connectionBanner).firstMatch
    }

    private func shownClocks(in app: XCUIApplication) -> [XCUIElement] {
        ["game.clock.black", "game.clock.white"].flatMap {
            app.buttons.matching(identifier: $0).allElementsBoundByIndex
        }.filter { $0.exists && $0.frame.width > 1 }
    }

    private func clockValues(in app: XCUIApplication) -> [String] {
        shownClocks(in: app).map { $0.value as? String ?? "" }
    }

    /// The countdown each shown clock reads out ("4:32"), by side.
    private func displayedTimes(in app: XCUIApplication) -> [String] {
        shownClocks(in: app).map { clock in
            let side = clock.identifier.replacingOccurrences(of: "game.clock.", with: "")
            let parts = (clock.value as? String ?? "").components(separatedBy: ", ")
            let time = parts.first { $0.range(of: #"^\d+(:\d{2}){1,2}$"#, options: .regularExpression) != nil }
            return "\(side)=\(time ?? "?")"
        }.sorted()
    }

    /// Stone removal with the socket down: the banner explains why marking
    /// stones and Accept are disabled; on iPhone it takes the title slot and
    /// the title gives way (canvas "Reconnecting in stone removal · iPhone").
    func testConnectionBannerInStoneRemoval() {
        let app = launch(artboard: 64, socketDown: true)
        let banner = connectionBanner(in: app)
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "Stone removal shows the app's connection banner")
        XCTAssertTrue(banner.label.contains("Reconnecting"), "The banner reads \(banner.label)")
        XCTAssertFalse(clockValues(in: app).contains { $0.hasPrefix("Reconnecting…") },
                       "Scoring clocks carry no Reconnecting… badge: \(clockValues(in: app))")
        XCTAssertTrue(pollUntil(timeout: 5) { !app.navigationBars.staticTexts["Stone removal"].exists },
                      "The title gives way to the banner")
        let accept = app.buttons["Accept"].firstMatch
        XCTAssertTrue(accept.waitForExistence(timeout: 5), "Accept stays in place")
        XCTAssertFalse(accept.isEnabled, "Accept is disabled while disconnected")
        recordConnectionBannerPlacement("phone-portrait-stone-removal", in: app)
        rotate(.landscapeLeft, app: app)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(banner.exists, "Landscape keeps the banner")
        XCTAssertFalse(app.navigationBars.staticTexts["Stone removal"].exists, "Landscape's title gives way too")
        recordConnectionBannerPlacement("phone-landscape-stone-removal", in: app)
        rotate(.portrait, app: app)
    }

    /// After the game: no clock runs, so no badge can stand in for the banner.
    func testConnectionBannerAfterTheGame() {
        let app = launch(artboard: 79, clock: "finished-points", socketDown: true)
        let banner = connectionBanner(in: app)
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "A finished game shows the app's connection banner")
        XCTAssertTrue(pollUntil(timeout: 5) { !app.navigationBars.staticTexts["Game over"].exists },
                      "The title gives way to the banner")
        recordConnectionBannerPlacement("phone-portrait-game-over", in: app)
    }

    /// Play: the running clock's Reconnecting… badge stands in for the banner.
    /// A title chip stands in only when it renders the label: Chat's single
    /// chip drops it when "Reconnecting…" does not fit beside the countdown,
    /// and Analyze's glow-only chips have none, so the banner shows there.
    func testReconnectingBadgeStandsInForTheBanner() {
        let app = launch(artboard: 1, socketDown: true)
        let banner = connectionBanner(in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { self.clockValues(in: app).contains { $0.hasPrefix("Reconnecting…") } },
                      "The running clock shows Reconnecting…: \(clockValues(in: app))")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(banner.exists, "Only the badge shows; the app's banner gives way")
        recordConnectionBannerPlacement("phone-portrait-play-badge", in: app)

        openGameChat(in: app)
        dismissSoftwareKeyboardIfNeeded(in: app)
        Thread.sleep(forTimeInterval: 1)
        let chips = app.navigationBars.buttons.matching(NSPredicate(
            format: "identifier == 'game.clock.black' OR identifier == 'game.clock.white'")).allElementsBoundByIndex
        print("[ConnectionBanner] phone chat chips \(chips.map { "\($0.identifier) \($0.frame) texts=\($0.staticTexts.allElementsBoundByIndex.map(\.label))" })")
        let labelled = chips.contains { $0.staticTexts["Reconnecting…"].exists }
        XCTAssertEqual(banner.waitForExistence(timeout: 3), !labelled,
                       "The banner shows unless the title chip renders the Reconnecting… label")
        recordConnectionBannerPlacement("phone-portrait-chat-chip", in: app)
        setGameChatVisible(false, in: app)

        setGameAnalyzing(true, in: app)
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "Analyze's glow-only title chips show the banner")
        recordConnectionBannerPlacement("phone-portrait-analyze-chips", in: app)
        setGameAnalyzing(false, in: app)
        XCTAssertTrue(pollUntil(timeout: 5) { !banner.exists },
                      "Back in Play the badge returns and the banner gives way")
    }

    /// One disconnect snapshot per game: mounting the title chips (Chat,
    /// Analyze) or the body pair again never shows a later local tick, while
    /// the shared model clock keeps ticking (the fixture's 1 s timer).
    func testFrozenClockHoldsAcrossChatAndAnalyze() {
        let app = launch(artboard: 1, socketDown: true)
        let model = element("game.clock.model", in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { self.displayedTimes(in: app).count == 2 })
        let initial = displayedTimes(in: app)
        let modelAtStart = model.value as? String ?? ""
        print("[FrozenClock] start displayed=\(initial) model=\(modelAtStart)")
        XCTAssertTrue((model.value as? String ?? "").contains("frozen=true"), "The game holds a disconnect snapshot")
        func assertUnchanged(_ step: String, file: StaticString = #filePath, line: UInt = #line) {
            Thread.sleep(forTimeInterval: 2.2)
            let shown = displayedTimes(in: app)
            print("[FrozenClock] \(step) displayed=\(shown) model=\(model.value as? String ?? "")")
            XCTAssertFalse(shown.isEmpty, "\(step): a clock is shown", file: file, line: line)
            for value in shown {
                XCTAssertTrue(initial.contains(value), "\(step): \(value) differs from \(initial)", file: file, line: line)
            }
        }
        assertUnchanged("play")
        openGameChat(in: app)
        dismissSoftwareKeyboardIfNeeded(in: app)
        assertUnchanged("chat-1")
        setGameChatVisible(false, in: app)
        assertUnchanged("chat-1-closed")
        openGameChat(in: app)
        dismissSoftwareKeyboardIfNeeded(in: app)
        assertUnchanged("chat-2")
        setGameChatVisible(false, in: app)
        assertUnchanged("chat-2-closed")
        setGameAnalyzing(true, in: app)
        assertUnchanged("analyze")
        setGameAnalyzing(false, in: app)
        assertUnchanged("analyze-off")
        let modelAtEnd = model.value as? String ?? ""
        print("[FrozenClock] end model=\(modelAtEnd)")
        XCTAssertNotEqual(modelAtEnd, modelAtStart, "The shared model kept ticking underneath")
        keepScreenshot("frozen-clock-after-chat-and-analyze", in: app)
    }

    /// v147 translation fit: run in one long-text language (de) and one CJK
    /// language (ja) by setting TEST_RUNNER_SURROUND_UI_LANGUAGE. On iPhone
    /// it uses portrait; with TEST_RUNNER_SURROUND_EXPECT_CLOSED_DUO_LANDSCAPE=1
    /// the Duo's Closed landscape column. Rule 12: a badge never truncates.
    /// A clock's badge is the first part of its accessibility value; its text
    /// frame must hold the label at the badge's 70% minimum scale. Every
    /// clock line is logged for the captures' review.
    func testLocalizedClockFit() {
        let environment = ProcessInfo.processInfo.environment
        let language = environment["SURROUND_UI_LANGUAGE"] ?? "en"
        let duoLandscape = environment["SURROUND_EXPECT_CLOSED_DUO_LANDSCAPE"] == "1"
        // v149: SURROUND_HIDES_RANK=1 runs with "Hide ranks and ratings" on;
        // SURROUND_FIT_ZEN=1 enters Zen (the column's two-line chips).
        let hidesRank = environment["SURROUND_HIDES_RANK"] == "1"
        let zen = environment["SURROUND_FIT_ZEN"] == "1"
        continueAfterFailure = true
        var scenes: [(name: String, scene: Scene, artboard: Int, clock: String?, home: Bool)] = [
            ("their-move", .activeGameBoard, 1, nil, true),
            ("your-move", .activeGameBoard, 7, nil, true),
            ("spectating", .publicGameSpectator, 46, nil, true),
            ("rengo", .activeGameBoard, 49, nil, true),
        ]
        let detailStates = ["not-started", "byoyomi-overtime", "undo-offered", "sudden-death", "fischer", "paused", "disconnected",
                            "stone-removal", "finished-points", "finished-resignation", "finished-timeout",
                            "canceled", "annulled", "draw"]
        for state in detailStates + ["first-move", "canadian-overtime", "simple", "absolute", "untimed"] {
            scenes.append((state, .activeGameBoard, detailStates.contains(state) ? 79 : 78, state, false))
        }
        if let requested = environment["SURROUND_FIT_SCENES"]?.split(separator: ",").map(String.init) {
            scenes = scenes.filter { requested.contains($0.name) }
        }
        let badgeFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
        for scene in scenes {
            let app = launch(scene.scene, artboard: scene.artboard, clock: scene.clock,
                             orientation: duoLandscape ? .landscapeLeft : .portrait,
                             fromMainNavigation: scene.home, hidesRank: hidesRank)
            if zen {
                let enter = app.buttons[ID.gameZenEnter].firstMatch
                if enter.waitForExistence(timeout: 5) && enter.isHittable {
                    enter.tap()
                } else {
                    XCTFail("\(language) \(scene.name): Zen could not be entered")
                }
            }
            if duoLandscape { Thread.sleep(forTimeInterval: 3) }
            // A standalone scene can still be in its launch zoom (frames at a
            // third of their size): settle, then wait until the clock holds still.
            Thread.sleep(forTimeInterval: 2)
            var lastFrame = CGRect.zero
            _ = pollUntil(timeout: 8) {
                let frame = app.buttons["game.clock.black"].firstMatch.frame
                defer { lastFrame = frame }
                return frame == lastFrame && frame.width > 40
            }
            let tag = "[ClockFit] \(language) \(scene.name)"
            for side in ["black", "white"] {
                let clock = app.buttons["game.clock.\(side)"].firstMatch
                guard clock.exists else { continue }
                let value = clock.value as? String ?? ""
                let texts = clock.staticTexts.allElementsBoundByIndex
                for text in texts {
                    print("\(tag) \(side) line '\(text.label)' frame=\(text.frame)")
                }
                print("\(tag) \(side) card=\(clock.frame) value='\(value)'")
                let parts = value.components(separatedBy: ", ")
                // v148: the stone-removal header ("Accepted") and the result
                // lines must not truncate either. Only rendered lines are found.
                func checkLine(_ text: String, _ what: String, font: UIFont, scale: CGFloat, extra: CGFloat = 0) {
                    guard !text.isEmpty, let line = texts.first(where: { $0.label == text }) else { return }
                    let ideal = (text as NSString).size(withAttributes: [.font: font]).width
                    let required = ideal * scale + extra
                    print("\(tag) \(side) \(what) '\(text)' width=\(line.frame.width) ideal=\(ideal) required=\(required)")
                    XCTAssertGreaterThanOrEqual(line.frame.width, required,
                                                "\(language) \(scene.name): the \(side) \(what) '\(text)' truncates (width \(line.frame.width), needs \(required))")
                }
                let detailSize: CGFloat = duoLandscape ? 12 : 13
                if scene.name == "stone-removal", parts.count > 2 {
                    // A Label: its frame also holds the checkmark and its gap
                    // (22.4-22.6 pt at 13 pt in de, es, fr, th). The header has
                    // no minimum scale, so the text needs all of its width.
                    checkLine(parts[2], "header", font: .systemFont(ofSize: detailSize, weight: .medium),
                              scale: 0.98, extra: 18 * detailSize / 13)
                }
                if ["finished-points", "finished-resignation", "finished-timeout", "canceled", "annulled", "draw"]
                    .contains(scene.name), parts.count > 1 {
                    let titleSize: CGFloat = duoLandscape ? 18 : (clock.frame.width < 145 ? 21 : 30)
                    checkLine(parts[0], "result", font: .systemFont(ofSize: titleSize, weight: .semibold), scale: 0.74)
                    checkLine(parts[1], "result detail", font: .systemFont(ofSize: detailSize), scale: 0.74)
                }
                let first = parts.first ?? ""
                guard let badge = texts.first(where: { $0.label == first && $0.frame.height < 18 }) else { continue }
                let ideal = (first as NSString).size(withAttributes: [.font: badgeFont]).width
                let scale = badge.frame.width / max(1, ideal)
                print("\(tag) \(side) badge '\(first)' width=\(badge.frame.width) ideal=\(ideal) scale=\(String(format: "%.2f", min(1, scale)))")
                // 0.74, not the 0.7 minimum scale: at 0.70 "Repris…" already
                // showed an ellipsis on the 17e (the measured ideal is ±3%).
                XCTAssertGreaterThanOrEqual(badge.frame.width, ideal * 0.74,
                                            "\(language) \(scene.name): the \(side) badge '\(first)' truncates (width \(badge.frame.width), needs \(ideal * 0.74))")
            }
            if duoLandscape {
                assertColumnFit("\(language) \(scene.name)", scoring: scene.name == "stone-removal",
                                zen: zen, hidesRank: hidesRank, in: app)
            }
            let name = "fit-\(language)\(zen ? "-zen" : "")\(hidesRank ? "-hidden-ranks" : "")-\(scene.name)"
            capture(scene.artboard, app: app, note: "Translation fit (\(language)): \(scene.name).",
                    suffix: "-" + name)
            FileHandle.standardOutput.write(Data("[ArtboardCaptureReady] native-\(name) window=\(app.windows.firstMatch.frame)\n".utf8))
            Thread.sleep(forTimeInterval: 2)
            app.terminate()
        }
    }
    // MARK: v149 column wrap, hidden ranks, disabled main action

    /// The 12 pt (11 pt in Zen's two-line chips) disconnect note is semibold.
    private static let disconnectedNotes = ["Disconnected", "Verbindung getrennt", "接続切れ"]

    private struct ColumnChip {
        let height: CGFloat
        let secondLine: Bool
    }

    /// The column chip's painted height and whether it shows a second line,
    /// from the app's DEBUG identity probe.
    private func columnChip(_ side: String, in app: XCUIApplication) -> ColumnChip? {
        let probe = app.descendants(matching: .any).matching(identifier: "game.identity.nameFit.\(side)").firstMatch
        guard probe.waitForExistence(timeout: 3) else { return nil }
        let value = probe.value as? String ?? ""
        guard let range = value.range(of: #"height=([0-9.]+)"#, options: .regularExpression) else { return nil }
        let height = CGFloat(Double(value[range].dropFirst("height=".count)) ?? 0)
        return ColumnChip(height: height, secondLine: value.contains("secondLine=yes"))
    }

    /// The column chip at the default text size: a 32 pt avatar, 6 pt gap,
    /// the name and (optionally) the rank line, 5 pt padding.
    private func expectedColumnChipHeight(secondLine: Bool) -> CGFloat {
        let name = UIFont.preferredFont(forTextStyle: .subheadline).lineHeight
        let rank = UIFont.preferredFont(forTextStyle: .footnote).lineHeight
        return ceil(5 + 32 + 6 + name + (secondLine ? 1 + rank : 0) + 5)
    }

    /// v149, Duo Closed landscape's column (canvas "German · Duo Closed,
    /// landscape"): no card line ends in "…" (each line the app drew, split
    /// where it broke it, fits at the 75% minimum scale), and the chips drop
    /// their rank line exactly when the cards grow for a wrapped line, which
    /// happens exactly when White's card (komi on its own line) wraps. With
    /// ranks hidden the chips are always the short form.
    private func assertColumnFit(_ tag: String, scoring: Bool, zen: Bool, hidesRank: Bool,
                                 in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let black = app.buttons["game.clock.black"].firstMatch
        let white = app.buttons["game.clock.white"].firstMatch
        guard black.exists, white.exists, abs(black.frame.width - 126) < 1 else {
            print("[ColumnFit] \(tag) not a column card: black=\(black.frame)")
            XCTFail("\(tag): expected the 126 pt column cards; black=\(black.frame)", file: file, line: line)
            return
        }
        let size: CGFloat = zen ? 11 : 12
        var wrapped = ["black": false, "white": false]
        var komiLine = false
        for (side, clock) in [("black", black), ("white", white)] {
            for text in clock.staticTexts.allElementsBoundByIndex where text.frame.width > 1 {
                let label = text.label
                if side == "white", label.range(of: #"^(\d+([.,]\d)? [Kk]omi|コミ\d+([.,]\d)?)$"#,
                                                options: .regularExpression) != nil {
                    komiLine = true
                }
                // Detail lines join their parts with " · ". The scoring
                // breakdown wraps by itself (no line limit).
                guard label.contains("·"), !scoring else { continue }
                let semibold = Self.disconnectedNotes.contains { label.hasPrefix($0) }
                // At the 75% minimum size itself: its tracking is wider than
                // 75% of the full-size width, and SwiftUI draws it at that size.
                let font = UIFont.systemFont(ofSize: size * 0.75, weight: semibold ? .semibold : .regular)
                let pieces = label.components(separatedBy: "\n")
                // A single-line text at the minimum scale is about 11 pt tall;
                // two lines are at least 22 pt.
                let drawnLines = text.frame.height > 20 ? 2 : 1
                if pieces.count > 1 || drawnLines > 1 { wrapped[side] = true }
                for piece in pieces {
                    let ideal = (piece as NSString).size(withAttributes: [.font: font]).width
                    // A line broken by the text system (no "\n") shares the
                    // frame's two lines; one split by the app has one each.
                    let capacity = text.frame.width * CGFloat(drawnLines > pieces.count ? drawnLines : 1)
                    print("[ColumnFit] \(tag) \(side) line '\(piece)' atMinimum=\(String(format: "%.1f", ideal)) frame=\(text.frame) lines=\(drawnLines)")
                    XCTAssertGreaterThanOrEqual(capacity + 0.5, ideal,
                                                "\(tag): the \(side) card's line '\(piece)' truncates (width \(text.frame.width), needs \(ideal) at the minimum size)",
                                                file: file, line: line)
                }
            }
        }
        XCTAssertEqual(black.frame.height, white.frame.height, accuracy: 0.5,
                       "\(tag): the two cards stay matched", file: file, line: line)
        let grown = black.frame.height > (zen ? 75 : 98)
        let chips = ["black", "white"].compactMap { columnChip($0, in: app) }
        let fullChip = expectedColumnChipHeight(secondLine: true)
        let shortChip = expectedColumnChipHeight(secondLine: false)
        print("[ColumnFit] \(tag) cards=\(black.frame.height) grown=\(grown) wraps=black:\(wrapped["black"]!),white:\(wrapped["white"]!) whiteKomiLine=\(komiLine) chips=\(chips.map { "\($0.height)/\($0.secondLine ? "rank" : "short")" }) expected full=\(fullChip) short=\(shortChip) blackCard=\(black.frame) whiteCard=\(white.frame)")
        if zen {
            XCTAssertEqual(grown, wrapped.values.contains(true),
                           "\(tag): Zen's two-line chips grow exactly when one wraps", file: file, line: line)
            return
        }
        XCTAssertEqual(grown, wrapped["white"]! && komiLine,
                       "\(tag): the cards grow exactly when White's card, with its komi line, wraps",
                       file: file, line: line)
        XCTAssertEqual(chips.count, 2, "\(tag): both column chips report", file: file, line: line)
        for chip in chips {
            let short = abs(chip.height - shortChip) < 1 && !chip.secondLine
            if hidesRank && chip.secondLine {
                // A Rengo chip keeps its Next line (no rank) until the cards
                // grow; then it is the short form too.
                XCTAssertFalse(grown, "\(tag): the cards grew, so the chips drop their second line", file: file, line: line)
                XCTAssertEqual(chip.height, fullChip, accuracy: 1, "\(tag): a Rengo chip with its Next line", file: file, line: line)
            } else if hidesRank {
                XCTAssertTrue(short, "\(tag): with ranks hidden the chip is avatar and name only (\(chip.height), expected \(shortChip))",
                              file: file, line: line)
            } else {
                XCTAssertEqual(short, grown,
                               "\(tag): the chip drops its rank line only, and always, when the cards grow for a wrap (\(chip.height); full \(fullChip), short \(shortChip))",
                               file: file, line: line)
                if !short {
                    XCTAssertEqual(chip.height, fullChip, accuracy: 1, "\(tag): the full chip", file: file, line: line)
                }
            }
        }
    }

    /// Ranks as Game Detail would print them: "name [2d]" (title, chat,
    /// details, VoiceOver values) or a chip's rank line ("2d", "13k", "?").
    private func rankTexts(in app: XCUIApplication) -> [String] {
        let tree = app.debugDescription
        var found = [String]()
        // A whole label or value that is a rank; "2d 4h" (a time) is not.
        for pattern in [#"\[(\d{1,2}[kdp]|\?)\]"#, #"(label|value): '?(\d{1,2}[kdp]|\?)'?(?=,|\n|$)"#] {
            let regex = try! NSRegularExpression(pattern: pattern)
            for match in regex.matches(in: tree, range: NSRange(tree.startIndex..., in: tree)) {
                let range = Range(match.range, in: tree)!
                let lineStart = tree[..<range.lowerBound].lastIndex(of: "\n").map { tree.index(after: $0) } ?? tree.startIndex
                let lineEnd = tree[range.upperBound...].firstIndex(of: "\n") ?? tree.endIndex
                found.append(String(tree[lineStart..<lineEnd]).trimmingCharacters(in: .whitespaces))
            }
        }
        return found
    }

    private func assertNoRanks(_ context: String, in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) {
        Thread.sleep(forTimeInterval: 1)
        let ranks = rankTexts(in: app)
        print("[HiddenRanks] \(context) rank texts: \(ranks.count)\(ranks.isEmpty ? "" : " \(ranks.prefix(5))")")
        XCTAssertTrue(ranks.isEmpty, "\(context): no rank with Hide ranks and ratings on: \(ranks.prefix(5))",
                      file: file, line: line)
    }

    /// iPhone row chips: with ranks hidden the chip lays out no second line
    /// at all (the app's DEBUG identity probe), so no empty line sits under
    /// the name. The chip's name is merged into its profile button, so its
    /// own text frame is not exposed; the probe reports the layout instead.
    private func assertRowChipsHaveNoSecondLine(_ context: String, in app: XCUIApplication,
                                                file: StaticString = #filePath, line: UInt = #line) {
        for side in ["black", "white"] {
            let probe = app.descendants(matching: .any).matching(identifier: "game.identity.nameFit.\(side)").firstMatch
            guard probe.waitForExistence(timeout: 3) else {
                print("[HiddenRanks] \(context) \(side): no chip probe")
                continue
            }
            let value = probe.value as? String ?? ""
            print("[HiddenRanks] \(context) \(side) chip \(value)")
            XCTAssertTrue(value.contains("secondLine=no"),
                          "\(context): the \(side) chip lays out no rank line (\(value))", file: file, line: line)
        }
    }

    /// v149, Settings › Hide ranks and ratings (set by launch argument in the
    /// isolated UI-test preferences only). iPhone: Play, the clock details,
    /// Chat and the Rengo team popover. Duo Closed landscape
    /// (SURROUND_EXPECT_CLOSED_DUO_LANDSCAPE=1, en and de): the column chips
    /// are the short form whether or not the cards wrap.
    func testHiddenRanksAndRatings() {
        continueAfterFailure = true
        let environment = ProcessInfo.processInfo.environment
        let language = environment["SURROUND_UI_LANGUAGE"] ?? "en"
        if environment["SURROUND_EXPECT_CLOSED_DUO_LANDSCAPE"] == "1" {
            // Your move (correspondence; no wrap), Their move (byo-yomi;
            // wraps in German) and Rengo (its chips keep their Next line
            // while the cards do not wrap).
            for artboard in [7, 1, 49] {
                let app = launch(artboard: artboard, orientation: .landscapeLeft, hidesRank: true)
                Thread.sleep(forTimeInterval: 5)
                XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height,
                                     "Closed landscape")
                assertNoRanks("duo-\(language)-\(artboard)", in: app)
                assertColumnFit("hidden-ranks \(language) \(artboard)", scoring: false, zen: false,
                                hidesRank: true, in: app)
                let name = "native-hidden-ranks-duo-closed-landscape-\(language)-\(artboard)"
                keepScreenshot(name, in: app)
                FileHandle.standardOutput.write(Data("[ArtboardCaptureReady] \(name) window=\(app.windows.firstMatch.frame)\n".utf8))
                Thread.sleep(forTimeInterval: 3)
                tap("game.clock.white", in: app, matching: .button)
                _ = element("game.details", in: app)
                assertNoRanks("duo-\(language)-\(artboard)-details", in: app)
                dismissPopover(in: app)
                app.terminate()
            }
            return
        }
        // The check itself: with the setting off, ranks are found.
        let control = launch(artboard: 1)
        let shown = rankTexts(in: control)
        print("[HiddenRanks] control (setting off) rank texts: \(shown.count) \(shown.prefix(3))")
        XCTAssertFalse(shown.isEmpty, "With the setting off the probe finds the ranks")
        control.terminate()

        let app = launch(artboard: 1, hidesRank: true)
        assertNoRanks("play", in: app)
        assertRowChipsHaveNoSecondLine("play", in: app)
        capture(1, app: app, note: "Hide ranks and ratings: Play.", suffix: "-hidden-ranks")
        tap("game.clock.black", in: app)
        _ = element("game.details", in: app)
        assertNoRanks("clock details", in: app)
        capture(60, app: app, note: "Hide ranks and ratings: clock details.", suffix: "-hidden-ranks")
        dismissPopover(in: app)
        openGameChat(in: app)
        dismissSoftwareKeyboardIfNeeded(in: app)
        assertNoRanks("chat", in: app)
        capture(1, app: app, note: "Hide ranks and ratings: Chat.", suffix: "-hidden-ranks-chat")
        app.terminate()

        let rengo = launch(artboard: 49, hidesRank: true)
        assertNoRanks("rengo", in: rengo)
        let team = rengo.buttons.matching(NSPredicate(format: "label CONTAINS %@", "kosumi")).firstMatch
        tap(team, description: "Open own team turn order", in: rengo)
        _ = element("game.team.details", in: rengo)
        assertNoRanks("rengo team popover", in: rengo)
        capture(52, app: rengo, note: "Hide ranks and ratings: Rengo team popover.", suffix: "-hidden-ranks")
    }

    /// Mean colour of the pill's surface, left of its label, and the
    /// brightest label pixels, from the on-screen pixels.
    private func pillColours(of element: XCUIElement) -> (fill: (Double, Double, Double), label: Double, crop: UIImage) {
        let image = element.screenshot().image
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let upright = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(at: .zero) }
        guard let cgImage = upright.cgImage else { return ((0, 0, 0), 0, upright) }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        func pixel(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            let index = (y * width + x) * 4
            return (Double(pixels[index]), Double(pixels[index + 1]), Double(pixels[index + 2]))
        }
        var sum = (0.0, 0.0, 0.0), count = 0.0
        for y in Int(Double(height) * 0.35)..<Int(Double(height) * 0.65) {
            for x in Int(Double(width) * 0.10)..<Int(Double(width) * 0.20) {
                let p = pixel(x, y)
                sum = (sum.0 + p.0, sum.1 + p.1, sum.2 + p.2); count += 1
            }
        }
        var brightness = [Double]()
        for y in Int(Double(height) * 0.3)..<Int(Double(height) * 0.7) {
            for x in Int(Double(width) * 0.3)..<Int(Double(width) * 0.7) {
                let p = pixel(x, y)
                brightness.append(min(p.0, p.1, p.2))
            }
        }
        brightness.sort()
        let label = brightness.isEmpty ? 0 : brightness[Int(Double(brightness.count - 1) * 0.99)]
        return ((sum.0 / max(1, count), sum.1 / max(1, count), sum.2 / max(1, count)), label, upright)
    }

    /// v149: a disabled main action is a grey pill with a white label and no
    /// accent, on every iOS version (Accept offline in stone removal); the
    /// enabled pill keeps the accent.
    func testDisabledMainActionIsGrey() {
        continueAfterFailure = true
        for socketDown in [true, false] {
            let app = launch(artboard: 64, socketDown: socketDown)
            let accept = app.buttons["Accept"].firstMatch
            XCTAssertTrue(accept.waitForExistence(timeout: 10), "Accept is shown")
            XCTAssertEqual(accept.isEnabled, !socketDown, "Accept is enabled only while connected")
            Thread.sleep(forTimeInterval: 2)
            let state = socketDown ? "disabled" : "enabled"
            let (fill, label, crop) = pillColours(of: accept)
            let spread = max(fill.0, fill.1, fill.2) - min(fill.0, fill.1, fill.2)
            print("[MainActionFill] \(UIDevice.current.systemVersion) \(state) frame=\(accept.frame) fill=\(String(format: "%.0f %.0f %.0f", fill.0, fill.1, fill.2)) spread=\(String(format: "%.0f", spread)) label=\(String(format: "%.0f", label))")
            let attachment = XCTAttachment(image: crop)
            attachment.name = "main-action-\(state)"
            attachment.lifetime = .keepAlways
            add(attachment)
            if socketDown {
                XCTAssertLessThan(spread, 24, "The disabled pill is grey, with no accent (fill \(fill))")
                XCTAssertTrue((90...200).contains(fill.0), "The disabled pill is a mid grey (fill \(fill))")
            } else {
                XCTAssertGreaterThan(fill.2 - fill.0, 60, "The enabled pill keeps the accent (fill \(fill))")
            }
            XCTAssertGreaterThan(label, 225, "The label stays white (\(label))")
            capture(64, app: app, note: "Accept \(state).", suffix: "-main-action-\(state)")
            FileHandle.standardOutput.write(Data("[ArtboardCaptureReady] native-main-action-\(state) window=\(app.windows.firstMatch.frame)\n".utf8))
            Thread.sleep(forTimeInterval: 3)
            app.terminate()
        }
    }
}

extension XCTestCase {
    /// v148: where the app's connection banner lands in a Game Detail layout,
    /// and whether it covers a clock (card or title chip) or the board. Logs
    /// the frames, keeps a screenshot and asks the host for a display capture.
    func recordConnectionBannerPlacement(_ layout: String, in app: XCUIApplication) {
        typealias ID = SurroundUITestContract.AccessibilityID
        Thread.sleep(forTimeInterval: 1)
        let window = app.windows.firstMatch.frame
        let banner = app.descendants(matching: .any).matching(identifier: ID.connectionBanner).firstMatch
        let board = app.descendants(matching: .any).matching(identifier: ID.gameBoard).firstMatch
        let clocks = ["game.clock.black", "game.clock.white"].flatMap {
            app.buttons.matching(identifier: $0).allElementsBoundByIndex
        }.filter { $0.exists && $0.frame.width > 1 && $0.frame.intersects(window) }
        let bars = app.navigationBars.allElementsBoundByIndex.filter { $0.exists && $0.frame.height > 0 }
        func covers(_ a: CGRect, _ b: CGRect) -> CGRect? {
            let overlap = a.intersection(b)
            return overlap.isNull || overlap.width <= 1 || overlap.height <= 1 ? nil : overlap
        }
        let bannerFrame = banner.exists ? banner.frame : .null
        let clockLines = clocks.map { clock -> String in
            let overlap = covers(bannerFrame, clock.frame)
            return "\(clock.identifier) frame=\(clock.frame) inTitle=\(bars.contains { $0.frame.contains(CGPoint(x: clock.frame.midX, y: clock.frame.midY)) }) covered=\(overlap.map { "\($0)" } ?? "no")"
        }
        let boardOverlap = board.exists ? covers(bannerFrame, board.frame) : nil
        let text = """
        Layout: \(layout)
        Window: \(window)
        Banner: \(banner.exists ? "\(bannerFrame) label='\(banner.label)'" : "absent")
        Navigation bars: \(bars.map { "\($0.frame)" })
        Board: \(board.exists ? "\(board.frame)" : "absent") covered=\(boardOverlap.map { "\($0)" } ?? "no")
        Clocks:
        \(clockLines.joined(separator: "\n"))
        """
        print("[ConnectionBanner] " + text.replacingOccurrences(of: "\n", with: " | "))
        let attachment = XCTAttachment(string: text)
        attachment.name = "connection-banner-\(layout)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "connection-banner-\(layout)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        FileHandle.standardOutput.write(Data("[ArtboardCaptureReady] native-connection-banner-\(layout) window=\(window)\n".utf8))
        Thread.sleep(forTimeInterval: 3)
    }
}
