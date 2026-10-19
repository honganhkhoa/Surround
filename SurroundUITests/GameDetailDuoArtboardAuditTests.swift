import XCTest
import UIKit

/// Opt-in screenshot evidence. The operator sets the physical Duo pose before
/// each run; the harness applies the matching screen orientation and sends no game commands.
final class GameDetailDuoArtboardAuditTests: SurroundJourneyUITestCase {
    private typealias ID = SurroundUITestContract.AccessibilityID
    private typealias Scene = SurroundUITestContract.CompatibilityScene

    private enum Pose: String {
        case closedPortrait = "closed-portrait"
        case closedLandscape = "closed-landscape"
        case bookWide = "book-wide"
        case openWide = "open-wide"
        case bookTall = "book-tall"

        var playArtboard: Int {
            switch self {
            case .closedPortrait: return 6
            case .closedLandscape: return 7
            case .bookWide: return 18
            case .openWide: return 19
            case .bookTall: return 20
            }
        }

        var playChatArtboard: Int? {
            switch self {
            case .closedPortrait: return 15
            case .closedLandscape: return nil
            case .bookWide: return 8
            case .openWide: return 9
            case .bookTall: return 10
            }
        }

        var analyzeArtboard: Int {
            switch self {
            case .closedPortrait: return 27
            case .closedLandscape: return 28
            case .bookWide: return 29
            case .openWide: return 30
            case .bookTall: return 31
            }
        }

        var zenArtboard: Int {
            switch self {
            case .closedPortrait: return 41
            case .closedLandscape: return 42
            case .bookWide: return 43
            case .openWide: return 44
            case .bookTall: return 45
            }
        }
    }

    private var pose: Pose!
    private var launchedArtboard: Int!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SURROUND_ARTBOARD_AUDIT"] == "1",
                          "Manual artboard audit is opt-in and does not run in CI.")
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Duo artboard inventory requires an iOS simulator.")
        #endif
        guard let requested = ProcessInfo.processInfo.environment["SURROUND_DUO_POSE"],
              let pose = Pose(rawValue: requested) else {
            throw XCTSkip("Set SURROUND_DUO_POSE to the physical pose configured by the operator.")
        }
        self.pose = pose
    }

    private func launchScene(_ scene: Scene, artboard: Int, appearance: String? = nil,
                             clock: String? = nil, socketDown: Bool = false,
                             rightToLeft: Bool = false) -> XCUIApplication {
        // Keep the operator-selected fold pose, then apply its artboard orientation.
        // XCTest can restore portrait when its runner launches.
        XCUIDevice.shared.orientation = [.closedLandscape, .bookWide, .openWide].contains(pose) ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        launchedArtboard = artboard
        app.launchArguments = languageLaunchArguments + [
            SurroundUITestContract.launchArgument,
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.emptyMessagesLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument, Scene.home.rawValue,
            SurroundUITestContract.gameDetailDesignArtboardLaunchArgument, String(artboard),
        ]
        if let appearance {
            app.launchArguments += [SurroundUITestContract.appearanceLaunchArgument, appearance]
        }
        if let clock {
            app.launchArguments += [SurroundUITestContract.gameDetailClockStateLaunchArgument, clock]
        }
        if socketDown {
            app.launchArguments.append(SurroundUITestContract.gameDetailSocketDownLaunchArgument)
        }
        if rightToLeft {
            // Xcode's "Right-to-Left Pseudolanguage" scheme option.
            app.launchArguments += ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"]
        }
        registerAppTermination(app)
        app.launch()
        let game = element(ID.homeGame(SurroundUITestContract.screenshotPrimaryGameID),
                           in: app, matching: .button)
        let home = app.scrollViews[ID.screenHome].firstMatch
        // The two genuinely ready games needed for Next (2) can put this
        // correspondence game below the short Closed landscape viewport.
        for _ in 0..<4 {
            let window = app.windows.firstMatch.frame
            let top = max(window.minY + 8, app.navigationBars.firstMatch.frame.maxY + 8)
            let bottom = window.maxY - 42
            let target = game.frame
            if game.isHittable && target.minY >= top && target.maxY <= bottom { break }
            let upper = home.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35))
            let lower = home.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.70))
            let moveDown = target.minY < top
            print("[DuoHomeTarget] frame=\(target), viewport=\(window), dragDown=\(moveDown)")
            (moveDown ? upper : lower).press(
                forDuration: 0.05,
                thenDragTo: moveDown ? lower : upper,
                withVelocity: .slow,
                thenHoldForDuration: 0.3
            )
        }
        tap(game, description: "Open the design fixture from Home", in: app)
        if scene == .zenMode {
            tap(ID.gameZenEnter, in: app, matching: .button)
        }
        element(ID.gameBoard, in: app)
        attachState("duo-\(pose.rawValue)-\(scene.rawValue)-initial", in: app)
        return app
    }

    private func attachState(_ name: String, in app: XCUIApplication) {
        let board = app.descendants(matching: .any).matching(identifier: ID.gameBoard).firstMatch
        let windows = app.windows.allElementsBoundByIndex.enumerated().map { index, window in
            "Window \(index) id=\(window.identifier) frame=\(window.frame)"
        }.joined(separator: "\n")
        let geometry = app.descendants(matching: .any).matching(identifier: "game.layout.geometry").firstMatch
        let clocks = ["game.clock.black", "game.clock.white"].map { identifier in
            let clock = app.buttons.matching(identifier: identifier).firstMatch
            return "\(identifier): \(clock.exists ? "frame=\(clock.frame), label=\(clock.label), value=\(String(describing: clock.value))" : "absent")"
        }.joined(separator: "\n")
        let metadata = """
        Requested physical pose: \(pose.rawValue)
        Layout geometry: \(geometry.exists ? String(describing: geometry.value) : "absent")
        App frame: \(app.frame)
        \(windows)
        Board frame: \(board.exists ? String(describing: board.frame) : "absent")
        Board value: \(board.exists ? String(describing: board.value) : "absent")
        Keyboard visible: \(app.keyboards.firstMatch.exists)
        \(clocks)
        Fixture: exact design artboard \(launchedArtboard!), with its player roles, clocks, board, and chat.
        Route: MainView Home → design fixture game; native navigation chrome.

        \(app.debugDescription)
        """
        let attachment = XCTAttachment(string: metadata)
        attachment.name = name + "-hierarchy"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func capture(_ number: Int, in app: XCUIApplication) {
        // The system may briefly show the home indicator after launch or an
        // interaction even when this landscape view requests automatic hiding.
        Thread.sleep(forTimeInterval: pose == .closedLandscape ? 10 : 0.7)
        let expectsLandscape = [Pose.closedLandscape, .bookWide, .openWide].contains(pose)
        // On Duo the application-level frame can retain the cover display's
        // orientation. The app window reports the active display geometry.
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(window.width > window.height, expectsLandscape,
                       "Capture orientation must match the operator-selected physical pose")
        let name = String(format: "native-%03d-duo-", number) + pose.rawValue
        attachState(name, in: app)
        recordArtboardCapture(number, screenshotName: name, in: app,
                              note: "Host must capture and verify the active Duo display.",
                              physicalPose: pose.rawValue)
        // The full screen capture preserves physical Duo orientation. The app
        // screenshot API can rotate/crop landscape captures on this runtime.
        keepScreenshot(name, in: app)
        let marker = "[ArtboardCaptureReady] \(name) window=\(window)\n"
        FileHandle.standardOutput.write(Data(marker.utf8))
        // The host captures the active Duo display with simctl. XCUIScreen
        // captures the inactive cover display as black in Book/Open poses.
        Thread.sleep(forTimeInterval: 3)
        if (27...31).contains(number) {
            let viewport = assertAuditAnalysisTreeAxis(vertical: [28, 29, 30].contains(number), in: app)
            let controls = element(ID.gameAnalyzeControlBar, in: app)
            let board = element(ID.gameBoard, in: app)
            if number == 28 {
                XCTAssertLessThanOrEqual(viewport.maxX, board.frame.minX + 1)
                XCTAssertGreaterThanOrEqual(controls.frame.minY, board.frame.maxY - 1,
                                            "Duo Closed landscape controls sit below the board")
            }
            if number == 31 {
                XCTAssertFalse(app.scrollViews[ID.gameChatLog].exists,
                               "Book tall Analyze is the only open panel")
                XCTAssertLessThanOrEqual(controls.frame.maxY, board.frame.minY + 1,
                                         "Book tall keeps panels off the lower board pane")
            }
        }
        if pose == .bookTall && [10, 31].contains(number) {
            let clockIDs = ["game.clock.black", "game.clock.white"]
            let clocks = clockIDs.flatMap {
                app.buttons.matching(identifier: $0).allElementsBoundByIndex
            }.filter { $0.isHittable }
            XCTAssertEqual(clocks.count, 1,
                           "Book tall's constrained title slot shows only the clock of the player to move")
            for clock in clocks {
                let frame = clock.frame
                XCTAssertGreaterThanOrEqual(frame.width, 44)
                XCTAssertGreaterThanOrEqual(frame.height, 44)
                XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(frame),
                              "The complete clock touch target stays in the active window")
                guard let bar = app.navigationBars.allElementsBoundByIndex.first(where: {
                    $0.frame.intersects(frame)
                }) else {
                    XCTFail("The Book tall inline clock must belong to a native navigation bar")
                    continue
                }
                XCTAssertTrue(bar.frame.insetBy(dx: -1, dy: -1).contains(frame),
                              "The clock must fit within its native toolbar")
                for control in bar.buttons.allElementsBoundByIndex
                    where control.isHittable && !clockIDs.contains(control.identifier) {
                    let overlap = frame.intersection(control.frame)
                    XCTAssertTrue(overlap.isNull || overlap.width <= 1 || overlap.height <= 1,
                                  "Clock overlaps native control \(control.identifier): clock=\(frame), control=\(control.frame)")
                }
                for text in clock.staticTexts.allElementsBoundByIndex {
                    XCTAssertTrue(frame.insetBy(dx: -1, dy: -1).contains(text.frame),
                                  "Clock text paints outside its target: \(text.label), \(text.frame)")
                }
            }
        }
        if [8, 9, 18, 19, 29, 30].contains(number) {
            assertWideGameDrawsItsOwnChrome(number, window: window, in: app)
        }
        if number == 44 {
            assertTrayFreeOpenWideZen(window: window, in: app)
        }
        if number == 43 && pose == .bookWide {
            assertBookWideZenKeepsItsTray(in: app)
        }
        if pose == .closedLandscape && [7, 42].contains(number) {
            assertClosedLandscapeColumn(zen: number == 42, in: app)
        }
    }

    /// v146 (canvas DuoClosedLandscape and ZenDuoClosedLandscape): one 126 pt
    /// column at x 12; the board takes the height beside it, 436 at (150, 15)
    /// in Play and 450 at (150, 8) in Zen.
    private func assertClosedLandscapeColumn(zen: Bool, in app: XCUIApplication) {
        let board = element(ID.gameBoard, in: app).frame
        let black = element("game.clock.black", in: app, matching: .button).frame
        let white = element("game.clock.white", in: app, matching: .button).frame
        let more = app.descendants(matching: .any).matching(identifier: "game.actions").firstMatch
        print("[DuoClosedLandscapeColumn] zen=\(zen) board=\(board) white=\(white) black=\(black) more=\(more.exists ? "\(more.frame)" : "-")")
        XCTAssertEqual(board.width, zen ? 450 : 436, accuracy: 1, "Board side; got \(board)")
        XCTAssertEqual(board.minX, 150, accuracy: 1, "Board x; got \(board)")
        XCTAssertEqual(board.minY, zen ? 8 : 15, accuracy: 1, "Board y; got \(board)")
        for clock in [white, black] {
            XCTAssertEqual(clock.minX, 12, accuracy: 1, "Clock column x; got \(clock)")
            XCTAssertEqual(clock.width, 126, accuracy: 1, "Clock column width; got \(clock)")
            XCTAssertLessThanOrEqual(clock.maxX + 12, board.minX + 1, "12 pt from the board")
        }
        XCTAssertLessThan(white.minY, black.minY, "The opponent's clock on top")
        XCTAssertEqual(white.height, black.height, accuracy: 1, "Matched clocks")
        if more.exists {
            XCTAssertGreaterThanOrEqual(more.frame.minX, 12 + 74 + 8 - 1, "More shares the line with the 74 pt pill")
            XCTAssertLessThanOrEqual(more.frame.maxX, 12 + 126 + 1)
            XCTAssertGreaterThan(more.frame.minY, black.maxY, "The action row is at the column's bottom")
        }
        if !zen {
            let opponent = app.descendants(matching: .any).matching(identifier: ID.profileBannerAvatarEntry(915_100)).firstMatch
            if opponent.exists {
                XCTAssertGreaterThanOrEqual(opponent.frame.minX, 12 - 1)
                XCTAssertLessThan(opponent.frame.maxY, white.minY + 1, "The opponent's chip above the clocks")
            }
        }
    }

    /// v145: in the wide poses the game hides the navigation bar, which held
    /// only the system sidebar toggle, and draws its own 44 pt sidebar button
    /// at (16, 32). Back and the game controls stay in the vertical toolbar.
    /// The game uses the rest of the top band: Open wide's opponent row,
    /// Book wide's clock table; leading content starts below the button.
    private func assertWideGameDrawsItsOwnChrome(_ number: Int, window: CGRect, in app: XCUIApplication) {
        let shownBars = app.navigationBars.allElementsBoundByIndex.filter {
            $0.exists && $0.frame.height > 0 && $0.frame.maxY > window.minY && $0.frame.intersects(window)
        }
        XCTAssertTrue(shownBars.isEmpty, "Wide poses hide the navigation bar; found \(shownBars.map(\.frame))")
        let toggle = element(ID.gameSidebarToggle, in: app, matching: .button)
        XCTAssertEqual(toggle.label, "Toggle sidebar")
        XCTAssertEqual(toggle.frame.minX, 16, accuracy: 2, "Sidebar button x; got \(toggle.frame)")
        XCTAssertEqual(toggle.frame.minY, 32, accuracy: 2, "Sidebar button y; got \(toggle.frame)")
        XCTAssertEqual(toggle.frame.width, 44, accuracy: 1)
        // The hidden bar's system Back is replaced by the game's own Back at
        // the top of the vertical bar (system Back: centre (903, 144)); the
        // game controls stay in the bar's lower group.
        let back = element(ID.gameBack, in: app, matching: .button)
        XCTAssertTrue(back.isHittable, "Back stays at the top of the vertical bar")
        XCTAssertEqual(back.frame.midX, window.maxX - 48, accuracy: 2, "Back on the bar's centre line; got \(back.frame)")
        XCTAssertEqual(back.frame.midY, 144, accuracy: 2, "Back where the system put it; got \(back.frame)")
        XCTAssertEqual(back.frame.width, 44, accuracy: 1)
        let modes = gameChatControl(in: app)
        XCTAssertTrue(modes.exists || app.buttons["BottomOverflowBarButtonItem"].exists,
                      "The game controls stay in the vertical toolbar")
        if modes.exists {
            XCTAssertEqual(modes.frame.midX, back.frame.midX, accuracy: 2, "Back shares the bar's centre line")
            XCTAssertLessThan(back.frame.maxY, modes.frame.minY, "Back sits above the controls")
        }
        let board = element(ID.gameBoard, in: app).frame
        print("[DuoWideBoard] artboard=\(number) pose=\(pose.rawValue) board=\(board) sidebarButton=\(toggle.frame) back=\(back.frame)")
        if pose == .openWide {
            XCTAssertEqual(board.width, 491, accuracy: 2, "Open wide board (design 491 at (368, 88)); got \(board)")
            XCTAssertEqual(board.minX, 368, accuracy: 2, "Open wide board x; got \(board)")
            XCTAssertEqual(board.minY, 88, accuracy: 2, "Open wide board top; got \(board)")
            let opponent = element(ID.profileBannerAvatarEntry(915_100), in: app, matching: .button).frame
            XCTAssertEqual(opponent.minY, 36, accuracy: 6,
                           "The opponent's row sits at y 32 beside the sidebar button; got \(opponent)")
        } else {
            XCTAssertEqual(board.width, 355, accuracy: 2, "Book wide board (design 355 at (504, 196)); got \(board)")
            XCTAssertLessThanOrEqual(board.minY, 197, "Book wide board top; got \(board)")
        }
        for identifier in ["game.clock.black", "game.clock.white"] {
            let clock = element(identifier, in: app).frame
            XCTAssertGreaterThanOrEqual(clock.height, 80, "Wide Duo keeps full clock cards")
            XCTAssertLessThanOrEqual(clock.height, 100,
                                     "\"+ 1d · 1 capture\" fits on one footer line in the wide cards; got \(clock)")
            if pose == .bookWide {
                XCTAssertEqual(clock.minY, 32, accuracy: 2, "Book wide's clock table starts at y 32; got \(clock)")
            }
        }
        if number != 19 {
            let panelIdentifier = [29, 30].contains(number)
                ? ID.gameAnalyzeTreeScroll : (number == 18 ? "game.information" : ID.gameChatLog)
            let panel = element(panelIdentifier, in: app)
            XCTAssertGreaterThanOrEqual(panel.frame.minY, toggle.frame.maxY,
                                        "The leading panel starts below the sidebar button")
        }
    }

    /// v145: Zen on Duo Open wide has no tray: no navigation bar, toolbar or
    /// status bar; Exit Zen at (891, 24); the board 611 at (170, 24), centred
    /// on the hinge, with the clock column and the actions beside it.
    private func assertTrayFreeOpenWideZen(window: CGRect, in app: XCUIApplication) {
        guard pose == .openWide else { return }
        let board = element(ID.gameBoard, in: app).frame
        let exit = element(ID.gameZenExit, in: app, matching: .button).frame
        print("[DuoZenBoard] pose=\(pose.rawValue) board=\(board) exit=\(exit)")
        XCTAssertEqual(board.width, 611, accuracy: 2, "Open wide Zen board (design 611 at (170, 24)); got \(board)")
        XCTAssertEqual(board.minX, 170, accuracy: 2, "Open wide Zen board x; got \(board)")
        XCTAssertEqual(board.minY, 24, accuracy: 2, "Open wide Zen board top; got \(board)")
        XCTAssertEqual(board.midX, window.midX, accuracy: 2, "Centred on the hinge")
        XCTAssertEqual(exit.minX, 891, accuracy: 2, "Exit Zen x; got \(exit)")
        XCTAssertEqual(exit.minY, 24, accuracy: 2, "Exit Zen y; got \(exit)")
        XCTAssertFalse(app.buttons["BackButton"].firstMatch.isHittable, "Zen hides Back")
        XCTAssertFalse(app.buttons[ID.gameBack].firstMatch.exists, "Zen hides Back")
        for identifier in ["game.clock.black", "game.clock.white"] {
            let clock = element(identifier, in: app).frame
            XCTAssertEqual(clock.minX, 16, accuracy: 2, "Clock column x; got \(clock)")
            XCTAssertEqual(clock.width, 146, accuracy: 2, "Clock column width; got \(clock)")
        }
        // v147: the vertical toolbar Open wide uses outside Zen must not carry
        // into Zen. Pass and More share one line at the right column's bottom.
        assertZenActionLine(more: CGPoint(x: 891, y: 601), board: board, in: app)
    }

    /// v145 ZenDuoBookWide: Book wide's Zen keeps its tray (the navigation bar
    /// holds Exit Zen); the board 439.5 at (503.5, 108.75) on the right pane,
    /// the 160 pt clock column at x 143.7, and Pass and More on one line.
    private func assertBookWideZenKeepsItsTray(in app: XCUIApplication) {
        let board = element(ID.gameBoard, in: app).frame
        let exit = element(ID.gameZenExit, in: app, matching: .button).frame
        print("[DuoZenBoard] pose=\(pose.rawValue) board=\(board) exit=\(exit)")
        XCTAssertEqual(board.width, 439.5, accuracy: 2, "Book wide Zen board (v145 439.5 at (503.5, 108.75)); got \(board)")
        XCTAssertEqual(board.minX, 503.5, accuracy: 2, "Book wide Zen board x; got \(board)")
        XCTAssertEqual(board.minY, 108.75, accuracy: 2, "Book wide Zen board top; got \(board)")
        let tray = app.navigationBars.allElementsBoundByIndex.filter {
            $0.exists && $0.frame.height > 0 && $0.frame.contains(CGPoint(x: exit.midX, y: exit.midY))
        }
        XCTAssertFalse(tray.isEmpty, "Book wide Zen keeps its tray: Exit Zen sits in the navigation bar; exit=\(exit)")
        XCTAssertEqual(exit.minX, 773, accuracy: 2, "Exit Zen x; got \(exit)")
        for identifier in ["game.clock.black", "game.clock.white"] {
            let clock = element(identifier, in: app).frame
            XCTAssertEqual(clock.minX, 143.7, accuracy: 2, "Clock column x; got \(clock)")
            XCTAssertEqual(clock.width, 160, accuracy: 2, "Clock column width; got \(clock)")
        }
        assertZenActionLine(more: CGPoint(x: 899, y: 560.3), board: board, in: app)
    }

    /// Zen's action line in the wide poses: More at its v145 origin, with the
    /// pill on the same line to its left (not stacked above it).
    private func assertZenActionLine(more expected: CGPoint, board: CGRect, in app: XCUIApplication) {
        let more = element("game.actions", in: app, matching: .button).frame
        let pass = app.buttons["Pass"].firstMatch
        print("[DuoZenActions] pose=\(pose.rawValue) more=\(more) pass=\(pass.exists ? "\(pass.frame)" : "-")")
        XCTAssertEqual(more.minX, expected.x, accuracy: 2, "More x; got \(more)")
        XCTAssertEqual(more.minY, expected.y, accuracy: 2, "More y; got \(more)")
        let overlap = more.intersection(board)
        XCTAssertTrue(overlap.isNull || overlap.width <= 1 || overlap.height <= 1,
                      "More stays clear of the board; more=\(more), board=\(board)")
        if pass.exists {
            XCTAssertEqual(pass.frame.midY, more.midY, accuracy: 2, "Pass shares More's line; pass=\(pass.frame)")
            XCTAssertLessThanOrEqual(pass.frame.maxX, more.minX + 1, "Pass sits left of More; pass=\(pass.frame)")
        }
    }

    /// Our sidebar button drives the native overlay sidebar: it opens over
    /// the game without moving it, and closes again.
    private func assertSidebarOpensOverTheGame(in app: XCUIApplication) {
        let board = element(ID.gameBoard, in: app)
        let before = board.frame
        let toggle = element(ID.gameSidebarToggle, in: app, matching: .button)
        tap(toggle, description: "Open the sidebar from the game's own button", in: app)
        let home = app.descendants(matching: .any).matching(identifier: ID.navigationHome).firstMatch
        XCTAssertTrue(pollUntil(timeout: 8) { home.exists && home.isHittable },
                      "The native sidebar opens from the game's button")
        XCTAssertEqual(board.frame, before, "The sidebar slides over the game without moving it")
        attachState("duo-\(pose.rawValue)-sidebar-open", in: app)
        keepScreenshot("duo-\(pose.rawValue)-sidebar-open", in: app)
        FileHandle.standardOutput.write(Data(
            "[ArtboardCaptureReady] native-sidebar-duo-\(pose.rawValue) window=\(app.windows.firstMatch.frame)\n".utf8))
        Thread.sleep(forTimeInterval: 3)
        // Close it the way a person would: the same button when uncovered,
        // otherwise the sidebar's own toggle ("Hide Sidebar").
        let closers = app.buttons.matching(NSPredicate(
            format: "label == %@ OR identifier == %@", "Toggle sidebar", "ToggleSidebar"))
            .allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        print("[DuoSidebarClosers] \(closers.map { "\($0.identifier)@\($0.frame)" })")
        guard let closer = closers.first else {
            XCTFail("No visible control closes the sidebar")
            return
        }
        tap(closer, description: "Close the sidebar", in: app)
        XCTAssertTrue(pollUntil(timeout: 8) { !home.isHittable }, "The sidebar closes")
        XCTAssertEqual(board.frame, before)
        XCTAssertTrue(element(ID.gameSidebarToggle, in: app, matching: .button).isHittable,
                      "The game's sidebar button is back once the sidebar closes")
    }

    private func openAuditChat(in app: XCUIApplication) {
        openGameChat(in: app)
        let input = app.textFields.matching(identifier: ID.gameChatInput).firstMatch
        guard input.waitForExistence(timeout: 10) else {
            attachState("duo-\(pose.rawValue)-missing-chat-composer", in: app)
            XCTFail("Expected the Chat composer after opening Chat.")
            return
        }
        if pose == .closedPortrait && chatInputHasKeyboardFocus(in: app) {
            // Duo can report the log's frame beneath the vertical toolbar.
            // The centered board locates the actual content edge, so dismiss
            // through its visible gutter rather than the bar or a chat message.
            let chatLog = element(ID.gameChatLog, in: app, matching: .scrollView)
            let board = element(ID.gameBoard, in: app)
            let frame = chatLog.frame
            let visibleMaxX = min(frame.maxX, 2 * board.frame.midX - frame.minX)
            XCTAssertGreaterThan(visibleMaxX - frame.minX, 8)
            chatLog.coordinate(withNormalizedOffset: CGVector(
                dx: (visibleMaxX - 4 - frame.minX) / frame.width, dy: 0.5
            )).tap()
        }
        dismissSoftwareKeyboardIfNeeded(in: app)
    }

    func testPlayChat() {
        var app = launchScene(.activeGameBoard, artboard: pose.playArtboard)
        capture(pose.playArtboard, in: app)
        if pose == .bookWide || pose == .openWide {
            assertClockDetailsAtCenter(in: app)
            assertSidebarOpensOverTheGame(in: app)
        }
        if let number = pose.playChatArtboard {
            // Relaunch every artboard with its own model rather than reusing
            // Play data.
            app.terminate()
            app = launchScene(.activeGameBoard, artboard: number)
            openAuditChat(in: app)
            capture(number, in: app)
            if pose == .bookWide || pose == .openWide { assertClockDetailsAtCenter(in: app) }
            if pose == .closedPortrait {
                let options = element(ID.gameOptions, in: app)
                XCTAssertTrue(options.isHittable, "Settings remains visible in Duo Closed Chat")
                tap(options, description: "Open Game Detail settings from Duo Closed Chat", in: app)
                element(ID.screenGameOptions, in: app)
            }
        }
        if pose == .bookWide || pose == .openWide {
            // The game's own Back (the navigation bar is hidden) leaves it.
            tap(ID.gameBack, in: app, matching: .button)
            let board = app.descendants(matching: .any).matching(identifier: ID.gameBoard).firstMatch
            XCTAssertTrue(pollUntil(timeout: 5) { !board.exists }, "Back leaves the game")
            keepScreenshot("duo-\(pose.rawValue)-after-back", in: app)
        }
    }

    func testV143WidePanelsPreserveBoardAndFullClocks() throws {
        try XCTSkipUnless(pose == .bookWide || pose == .openWide,
                          "Configure the physical Duo in Book wide or Open wide for this journey.")
        let app = launchScene(.activeGameBoard, artboard: pose.playArtboard)
        let activeWindow = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(activeWindow.width, 900,
                                    "The operator-selected \(pose.rawValue) pose must use the unfolded display; got \(activeWindow)")
        XCTAssertGreaterThanOrEqual(activeWindow.height, 600,
                                    "A Closed cover-display window is not valid evidence for this wide-pose journey")
        let geometry = element("game.layout.geometry", in: app)
        let diagnostic = try XCTUnwrap(geometry.value as? String)
        XCTAssertEqual(diagnostic.contains("division(active=true"), pose == .bookWide,
                       "Book wide requires an active fold division and Open wide requires none; requested \(pose.rawValue), diagnostic=\(diagnostic)")
        let board = element(ID.gameBoard, in: app)
        let playFrame = board.frame
        let playValue = board.value as? String
        XCTAssertNotNil(playValue)

        func assertFixedBoardAndFullClocks(_ state: String) {
            XCTAssertTrue(pollUntil(timeout: 5) {
                let frame = board.frame
                return abs(frame.minX - playFrame.minX) <= 1
                    && abs(frame.minY - playFrame.minY) <= 1
                    && abs(frame.width - playFrame.width) <= 1
                    && abs(frame.height - playFrame.height) <= 1
            }, "\(state) retains Play's board frame \(playFrame); got \(board.frame)")
            XCTAssertEqual(board.value as? String, playValue,
                           "Switching panels must not change the game position")
            let window = app.windows.firstMatch.frame
            for identifier in ["game.clock.black", "game.clock.white"] {
                let clock = element(identifier, in: app, matching: .button)
                XCTAssertGreaterThanOrEqual(clock.frame.height, 80,
                                            "\(state) retains a full clock card")
                XCTAssertGreaterThanOrEqual(clock.frame.width, 44)
                XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(clock.frame))
                XCTAssertTrue(clock.isHittable)
            }
        }

        func recordWideState(_ state: String) {
            let name = "v143-duo-\(pose.rawValue)-\(state)"
            attachState(name, in: app)
            keepScreenshot(name, in: app)
            FileHandle.standardOutput.write(Data(
                "[ArtboardCaptureReady] \(name) window=\(app.windows.firstMatch.frame)\n".utf8))
            // Allow the host to capture the active display in Book/Open, where
            // XCUIScreen can still return the inactive cover display.
            Thread.sleep(forTimeInterval: 3)
        }

        XCTAssertFalse(app.scrollViews[ID.gameChatLog].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: ID.gameAnalyzeControlBar).firstMatch.exists)
        assertFixedBoardAndFullClocks("Play")
        recordWideState("play")

        openAuditChat(in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: ID.gameAnalyzeControlBar).firstMatch.exists,
                       "Chat is the only open panel")
        assertFixedBoardAndFullClocks("Chat")
        recordWideState("chat")

        setGameAnalyzing(true, in: app)
        XCTAssertFalse(app.scrollViews[ID.gameChatLog].exists, "Analyze replaces Chat")
        XCTAssertFalse(app.textFields[ID.gameChatInput].exists)
        let tree = element(ID.gameAnalyzeTreeScroll, in: app, matching: .scrollView)
        let clippingAncestors = app.scrollViews.containing(.scrollView, identifier: ID.gameAnalyzeTreeScroll)
            .allElementsBoundByIndex
        let treeViewport = ([app.windows.firstMatch.frame, tree.frame] + clippingAncestors.map { $0.frame })
            .reduce(CGRect.infinite) { $0.intersection($1) }
        XCTAssertFalse(treeViewport.isEmpty, "Analyze has a visible viewport on the active Duo display")
        assertFixedBoardAndFullClocks("Analyze")
        recordWideState("analyze")

        setGameAnalyzing(false, in: app)
        XCTAssertFalse(app.scrollViews[ID.gameChatLog].exists,
                       "Closing Analyze returns to Play rather than reopening Chat")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: ID.gameAnalyzeControlBar).firstMatch.exists)
        assertFixedBoardAndFullClocks("Play after Analyze")
    }

    private func assertClockDetailsAtCenter(in app: XCUIApplication) {
        let clock = element("game.clock.white", in: app, matching: .button)
        let clockFrame = clock.frame
        // Book wide's clocks sit in the top band, where the navigation bar
        // used to take every touch. Tap the card's upper part there (above
        // y 82) so a real touch proves nothing covers it; others at the center.
        let tapY = pose == .bookWide ? min(clockFrame.minY + 20, 74) : clockFrame.midY
        clock.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: (tapY - clockFrame.minY) / clockFrame.height)).tap()
        let details = app.descendants(matching: .any).matching(identifier: "game.details").firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 5),
                      "A tap on a wide-pane clock opens its game details")
        XCTAssertTrue(app.staticTexts["Time control"].exists)
        XCTAssertTrue(app.popovers.firstMatch.exists,
                      "Game details are a popover anchored to the tapped clock")
        guard details.exists else {
            attachState("duo-\(pose.rawValue)-clock-details-failure", in: app)
            return
        }
        let popover = app.popovers.firstMatch.frame
        let gap = max(popover.minY - clockFrame.maxY, clockFrame.minY - popover.maxY,
                      popover.minX - clockFrame.maxX, clockFrame.minX - popover.maxX)
        XCTAssertLessThanOrEqual(gap, 40,
                                 "The popover opens from the clock's edge: popover=\(popover), clock=\(clockFrame)")
        attachState("duo-\(pose.rawValue)-clock-details-popover", in: app)
        keepScreenshot("duo-\(pose.rawValue)-clock-details-popover", in: app)
        FileHandle.standardOutput.write(Data(
            "[ArtboardCaptureReady] native-popover-duo-\(pose.rawValue) window=\(app.windows.firstMatch.frame)\n".utf8))
        Thread.sleep(forTimeInterval: 3)
        dismissPopover(in: app)
        XCTAssertTrue(element(ID.gameBoard, in: app).isHittable,
                      "Closing game details restores the board")
        if pose == .openWide { assertOpponentRowRespondsInBand(in: app) }
    }

    /// Open wide's opponent row is the game's content inside the band. A real
    /// touch there must reach the profile button, not the native bar.
    private func assertOpponentRowRespondsInBand(in app: XCUIApplication) {
        let avatar = element(ID.profileBannerAvatarEntry(915_100), in: app, matching: .button)
        avatar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let profile = app.descendants(matching: .any).matching(identifier: ID.screenPlayerProfile).firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 10),
                      "A tap on the opponent's avatar in the band opens the profile")
        guard profile.exists else {
            attachState("duo-open-wide-opponent-band-failure", in: app)
            return
        }
        let back = app.buttons["BackButton"].firstMatch
        tap(back, description: "Return from the opponent's profile", in: app)
        element(ID.gameBoard, in: app)
    }

    func testAnalyze() {
        let app = launchScene(.gameAnalysis, artboard: pose.analyzeArtboard)
        XCTAssertFalse(app.scrollViews[ID.gameChatLog].exists,
                       "Analyze replaces Chat in every Duo pose")
        if pose == .bookTall { assertSelectedAuditBranchVisible(in: app) }
        capture(pose.analyzeArtboard, in: app)
    }

    private func assertSelectedAuditBranchVisible(in app: XCUIApplication,
                                                 file: StaticString = #filePath, line: UInt = #line) {
        let node = element(ID.gameAnalysisPosition(baseMoveNumber: 38, movePath: ["lj", "lk", "mk"]),
                           in: app, file: file, line: line)
        let tree = app.scrollViews[ID.gameAnalyzeTreeScroll].firstMatch
        XCTAssertTrue(pollUntil(timeout: 10) {
            guard node.exists, node.isSelected, tree.exists else { return false }
            let ancestors = app.scrollViews.containing(.scrollView, identifier: ID.gameAnalyzeTreeScroll)
                .allElementsBoundByIndex
            // Duo's app frame can retain the cover-display dimensions. The
            // active window and clipping ancestors define the visible viewport.
            let viewport = ([app.windows.firstMatch.frame, tree.frame] + ancestors.map { $0.frame })
                .reduce(CGRect.infinite) { $0.intersection($1) }
            return !viewport.isEmpty && viewport.insetBy(dx: -1, dy: -1)
                .contains(node.frame.insetBy(dx: -3, dy: -3))
        }, "The selected Analyze branch and its ring remain visible in the current pose",
                      file: file, line: line)
    }

    func testZen() {
        let app = launchScene(.zenMode, artboard: pose.zenArtboard)
        capture(pose.zenArtboard, in: app)
    }

    /// v148: where the app's connection banner lands in this pose, in stone
    /// removal with the socket down (logged with any clock or board it
    /// covers), and that Play's Reconnecting… badge stands in for it.
    func testConnectionBannerPlacement() {
        let app = launchScene(.activeGameBoard, artboard: pose.playArtboard,
                              clock: "stone-removal", socketDown: true)
        if pose == .closedLandscape { Thread.sleep(forTimeInterval: 5) }
        let banner = app.descendants(matching: .any).matching(identifier: ID.connectionBanner).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "Stone removal shows the app's connection banner")
        attachState("duo-\(pose.rawValue)-connection-banner", in: app)
        recordConnectionBannerPlacement("duo-\(pose.rawValue)-stone-removal", in: app)
        app.terminate()

        let play = launchScene(.activeGameBoard, artboard: pose.playArtboard, socketDown: true)
        let values = { ["game.clock.black", "game.clock.white"].flatMap {
            play.buttons.matching(identifier: $0).allElementsBoundByIndex
        }.filter { $0.exists }.map { $0.value as? String ?? "" } }
        XCTAssertTrue(pollUntil(timeout: 10) { values().contains { $0.hasPrefix("Reconnecting…") } },
                      "The running clock shows Reconnecting…: \(values())")
        Thread.sleep(forTimeInterval: 1)
        let playBanner = play.descendants(matching: .any).matching(identifier: ID.connectionBanner).firstMatch
        XCTAssertFalse(playBanner.exists, "Play: only the badge shows")
        recordConnectionBannerPlacement("duo-\(pose.rawValue)-play-badge", in: play)
    }

    /// v148: the wide poses' own Back sits on the vertical bar's centre line,
    /// 48 pt in from the trailing edge, centred at y 144: (881, 122) in LTR.
    /// With TEST_RUNNER_SURROUND_UI_RTL=1 the app runs in the right-to-left
    /// pseudolanguage. On iOS 27.1 the vertical bar then stays on the physical
    /// right, its leading edge, so the game draws no Back of its own and the
    /// toolbar's Back sits in the bar's lower group: the run records where.
    func testWideBackFollowsTheLayoutDirection() throws {
        try XCTSkipUnless(pose == .bookWide || pose == .openWide, "Back is the game's own only in the wide poses.")
        let rightToLeft = ProcessInfo.processInfo.environment["SURROUND_UI_RTL"] == "1"
        let app = launchScene(.activeGameBoard, artboard: pose.playArtboard, rightToLeft: rightToLeft)
        Thread.sleep(forTimeInterval: 1)
        let window = app.windows.firstMatch.frame
        let back = element(ID.gameBack, in: app, matching: .button)
        let board = element(ID.gameBoard, in: app).frame
        let sidebar = app.buttons.matching(identifier: ID.gameSidebarToggle).firstMatch
        print("[DuoWideBack] pose=\(pose.rawValue) rtl=\(rightToLeft) window=\(window) back=\(back.frame) board=\(board) sidebarButton=\(sidebar.exists ? "\(sidebar.frame)" : "absent")")
        let name = "native-wide-back-duo-\(pose.rawValue)" + (rightToLeft ? "-rtl" : "")
        attachState(name, in: app)
        keepScreenshot(name, in: app)
        FileHandle.standardOutput.write(Data("[ArtboardCaptureReady] \(name) window=\(window)\n".utf8))
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(back.isHittable, "Back is on screen")
        let barCentres = [window.maxX - 48, window.minX + 48]
        XCTAssertTrue(barCentres.contains { abs(back.frame.midX - $0) <= 2 },
                      "Back on a vertical bar's centre line; got \(back.frame)")
        if !rightToLeft {
            XCTAssertEqual(back.frame.midX, window.maxX - 48, accuracy: 2, "Back on the bar's centre line; got \(back.frame)")
            XCTAssertEqual(back.frame.midY, 144, accuracy: 2, "Back centred at y 144; got \(back.frame)")
            XCTAssertEqual(back.frame.width, 44, accuracy: 1)
        }
        let overlap = back.frame.intersection(board)
        XCTAssertTrue(overlap.isNull || overlap.width <= 1 || overlap.height <= 1,
                      "Back stays off the board; back=\(back.frame), board=\(board)")
    }

    func testChatOpensAndClosesAtItsFinalSize() throws {
        try XCTSkipUnless(pose == .bookWide || pose == .openWide || pose == .closedLandscape,
                          "Recorded in the wide poses and Closed landscape.")
        let app = launchScene(.activeGameBoard, artboard: pose.playArtboard)
        recordChatToggle("chat-toggle-duo-\(pose.rawValue)", in: app,
                         open: { setGameChatVisible(true, in: app) },
                         close: { setGameChatVisible(false, in: app) })
    }

    /// v147: every text line on both 126 pt column cards (badge, time, komi,
    /// detail) keeps its card's colours, in light and dark, with Black to
    /// move (artboard 7) and White to move (46, spectating). Each line is
    /// measured on screen: its brightest and darkest pixels must differ by at
    /// least 3:1. The v146 detail line used the system colour instead, black
    /// on the black card (and, inferred, white on white in dark mode).
    func testClosedLandscapeColumnCardTextIsReadable() throws {
        try XCTSkipUnless(pose == .closedLandscape, "The column cards belong to Duo Closed landscape.")
        continueAfterFailure = true
        for (artboard, toMove) in [(7, "black"), (46, "white")] {
            for appearance in ["light", "dark"] {
                let app = launchScene(.activeGameBoard, artboard: artboard, appearance: appearance)
                // As in capture(): let the home indicator settle in landscape.
                Thread.sleep(forTimeInterval: 10)
                let window = app.windows.firstMatch.frame
                XCTAssertGreaterThan(window.width, window.height, "Closed landscape")
                let name = String(format: "native-%03d-duo-closed-landscape-%@-%@-to-move", artboard, appearance, toMove)
                attachState(name, in: app)
                keepScreenshot(name, in: app)
                FileHandle.standardOutput.write(Data("[ArtboardCaptureReady] \(name) window=\(window)\n".utf8))
                Thread.sleep(forTimeInterval: 3)
                for side in ["black", "white"] {
                    let clock = element("game.clock.\(side)", in: app, matching: .button)
                    XCTAssertEqual(clock.frame.width, 126, accuracy: 1, "\(name): \(side) is a column card; got \(clock.frame)")
                    let texts = clock.staticTexts.allElementsBoundByIndex.filter { $0.frame.width > 4 && $0.frame.height > 4 }
                    XCTAssertTrue(texts.contains { $0.label.contains("capture") },
                                  "\(name): the \(side) card shows its detail line")
                    for (index, text) in texts.enumerated() {
                        let (ratio, crop) = onScreenContrast(of: text)
                        print("[ColumnCardContrast] \(name) \(side) '\(text.label)' frame=\(text.frame) ratio=\(String(format: "%.2f", ratio))")
                        let attachment = XCTAttachment(image: crop)
                        attachment.name = "\(name)-\(side)-line\(index)"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                        XCTAssertGreaterThanOrEqual(ratio, 3, "\(name): '\(text.label)' on the \(side) card is readable (contrast \(ratio))")
                    }
                }
                app.terminate()
            }
        }
    }

    /// Contrast between the brightest and darkest 5% of a text element's
    /// on-screen pixels (WCAG relative luminance), with the crop it measured.
    private func onScreenContrast(of element: XCUIElement) -> (Double, UIImage) {
        let image = element.screenshot().image
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let upright = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
        }
        guard let cgImage = upright.cgImage, cgImage.width > 0, cgImage.height > 0 else { return (0, upright) }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drew = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return (0, upright) }
        func linear(_ component: UInt8) -> Double {
            let value = Double(component) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        var luminance = [Double]()
        luminance.reserveCapacity(width * height)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            luminance.append(0.2126 * linear(pixels[index]) + 0.7152 * linear(pixels[index + 1])
                             + 0.0722 * linear(pixels[index + 2]))
        }
        luminance.sort()
        let low = luminance[Int(Double(luminance.count - 1) * 0.05)]
        let high = luminance[Int(Double(luminance.count - 1) * 0.95)]
        return ((high + 0.05) / (low + 0.05), upright)
    }
}
