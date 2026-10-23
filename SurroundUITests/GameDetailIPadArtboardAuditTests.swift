import XCTest
import UIKit

/// Opt-in visual evidence and layout regressions through the shipping navigation route.
final class GameDetailIPadArtboardAuditTests: SurroundJourneyUITestCase {
    private typealias ID = SurroundUITestContract.AccessibilityID

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard ProcessInfo.processInfo.environment["SURROUND_ARTBOARD_AUDIT"] == "1" else {
            throw XCTSkip("Opt in to the Game Detail artboard audit.")
        }
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("These artboards require an iPad simulator.")
        }
    }

    private func launchGame(artboard: Int, dark: Bool = false, portrait: Bool = false,
                            largeText: Bool = false, players: String? = nil,
                            clock: String? = nil, socketDown: Bool = false,
                            theme: String? = nil,
                            appearance: SurroundUITestContract.Appearance? = nil,
                            opensGame: Bool = true) -> XCUIApplication {
        var arguments = [SurroundUITestContract.compatibilityScreenshotLaunchArgument,
                         SurroundUITestContract.emptyMessagesLaunchArgument,
                         SurroundUITestContract.compatibilitySceneLaunchArgument,
                         SurroundUITestContract.CompatibilityScene.home.rawValue,
                         SurroundUITestContract.gameDetailDesignArtboardLaunchArgument, String(artboard),
        ]
        if let theme {
            arguments += [SurroundUITestContract.themeLaunchArgument, theme]
        }
        if let appearance {
            arguments += [SurroundUITestContract.appearanceLaunchArgument, appearance.rawValue]
        } else if theme == nil {
            arguments += [SurroundUITestContract.appearanceLaunchArgument, dark ? "dark" : "light"]
        }
        if largeText {
            arguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraLarge.rawValue]
        }
        if let players {
            arguments += [SurroundUITestContract.gameDetailPlayersLaunchArgument, players]
        }
        if let clock {
            arguments += [SurroundUITestContract.gameDetailClockStateLaunchArgument, clock]
        }
        if socketDown {
            arguments.append(SurroundUITestContract.gameDetailSocketDownLaunchArgument)
        }
        let app = launchApp(additionalLaunchArguments: arguments,
                            orientation: portrait ? .portrait : .landscapeLeft)
        element(ID.screenHome, in: app)
        restoreFullWindow(in: app)
        if opensGame { openDesignGame(in: app) }
        return app
    }

    private func openDesignGame(in app: XCUIApplication) {
        let game = element(ID.homeGame(SurroundUITestContract.screenshotPrimaryGameID),
                           in: app, matching: .button)
        let home = app.scrollViews[ID.screenHome].firstMatch
        // Next (2) requires two ready games ahead of the waiting fixture.
        // Bring that real Home card into view without a momentum overscroll.
        for _ in 0..<4 {
            let window = app.windows.firstMatch.frame
            let top = max(window.minY + 8, app.navigationBars.firstMatch.frame.maxY + 8)
            let bottom = window.maxY - 42
            let target = game.frame
            if game.isHittable && target.minY >= top && target.maxY <= bottom { break }
            let upper = home.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35))
            let lower = home.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.70))
            let moveDown = target.minY < top
            (moveDown ? upper : lower).press(forDuration: 0.05,
                thenDragTo: moveDown ? lower : upper, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        tap(game, description: "Open the design fixture from Home", in: app)
        element(ID.gameBoard, in: app)
    }

    private func restoreFullWindow(in app: XCUIApplication) {
        let window = app.windows.firstMatch
        let before = window.frame
        guard before.minX > 4 || before.minY > 40 || min(before.width, before.height) < 700 else { return }
        // iPadOS remembers the real size from the opt-in narrow-window audit.
        // Apple's native window gesture restores it without app-side overrides:
        // https://support.apple.com/guide/ipad/ipad08c9970c/ipados
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 8)).doubleTap()
        let restored = pollUntil(timeout: 8) {
            let frame = window.frame
            return frame.minX <= 4 && frame.minY <= 40 && min(frame.width, frame.height) >= 700
        }
        if !restored { capture(0, "Full-window restoration failed", in: app, note: "Before: \(before)") }
        XCTAssertTrue(restored, "Expected a full-size native iPad window; got \(window.frame)")
    }

    private func capture(_ number: Int, _ state: String, in app: XCUIApplication,
                         note: String = "", suffix: String = "") {
        Thread.sleep(forTimeInterval: 0.7)
        let name = String(format: "artboard-%03d-ipad", number) + suffix
        recordArtboardCapture(number, screenshotName: name, in: app,
                              note: [state, note].joined(separator: " "))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let board = app.descendants(matching: .any).matching(identifier: ID.gameBoard).firstMatch
        let metadata = "Artboard \(number): \(state)\nFixture: October 15 design artboard \(number), through Home navigation\nDevice: \(UIDevice.current.model); window: \(app.windows.firstMatch.frame)\nBoard: \(board.exists ? String(describing: board.frame) : "absent")\nNote: \(note)\n\n\(app.debugDescription)"
        let hierarchy = XCTAttachment(string: metadata)
        hierarchy.name = name + "-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        print("[ArtboardCapture] \(name) \(state) window=\(app.windows.firstMatch.frame) board=\(board.exists ? String(describing: board.frame) : "absent")")
        if [24, 26].contains(number) {
            XCTAssertEqual(board.value as? String, "variation:38:lj-lk-mk",
                           "Analyze shows the design's three-move branch, not the live board")
            let viewport = assertAuditAnalysisTreeAxis(vertical: number == 24, in: app)
            let controls = element(ID.gameAnalyzeControlBar, in: app)
            XCTAssertLessThanOrEqual(viewport.maxY, controls.frame.minY + 1)
            XCTAssertFalse(app.scrollViews[ID.gameChatLog].exists,
                           "Analyze is the only open panel")
            if number == 26 {
                XCTAssertLessThanOrEqual(controls.frame.maxY, board.frame.minY + 1)
            }
        }
    }

    private func setSidebarCollapsed(_ collapsed: Bool, in app: XCUIApplication) {
        let probe = app.descendants(matching: .any).matching(identifier: ID.navigationSettings).firstMatch
        if collapsed ? !probe.isHittable : probe.isHittable { return }
        let named = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).allElementsBoundByIndex
            .first(where: { $0.isHittable })
        let window = app.windows.firstMatch.frame
        let navigationIDs = Set([ID.navigationHome, ID.navigationPublicGames,
                                 ID.navigationSettings, ID.navigationAbout, ID.navigationBrowser])
        // Query hittability only for plausible chrome controls. Offscreen
        // profile buttons can have invalid activation points during relayout.
        let fallback = named == nil ? app.buttons.allElementsBoundByIndex.filter {
            let f = $0.frame
            return $0.exists && !navigationIDs.contains($0.identifier)
                && f.width > 1 && f.height > 1 && f.width < 80 && f.height < 80
                && f.midX > window.minX + 100 && f.midX < window.midX
                && f.maxY < window.minY + 100 && $0.isHittable
        }.min { $0.frame.midX < $1.frame.midX } : nil
        guard let toggle = named ?? fallback else {
            capture(0, "Sidebar toggle missing", in: app)
            XCTFail("Could not find the native sidebar toggle.")
            return
        }
        toggle.tap()
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            collapsed ? !probe.isHittable : probe.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 8), .completed)
    }

    // iPadOS can move these native toolbar items into its overflow menu at
    // portrait widths. Exercise that real menu instead of a standalone route.
    private func auditToolbarAction(_ identifier: String, label: String, in app: XCUIApplication) {
        var control = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if !control.exists || !control.isHittable {
            let overflow = app.buttons.matching(identifier: "OverflowBarButtonItem").firstMatch
            XCTAssertTrue(overflow.waitForExistence(timeout: 5), "Expected native toolbar overflow")
            overflow.tap()
            if !control.waitForExistence(timeout: 2) {
                control = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
            }
        }
        XCTAssertTrue(control.waitForExistence(timeout: 5), "Expected toolbar action \(identifier)")
        control.tap()
        Thread.sleep(forTimeInterval: 0.4)
    }

    private func auditAnalyzing(_ visible: Bool, in app: XCUIApplication) {
        setGameAnalyzing(visible, in: app)
    }

    private func auditChat(_ visible: Bool, in app: XCUIApplication) {
        setGameChatVisible(visible, in: app)
    }

    private func connectionBanner(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: ID.connectionBanner).firstMatch
    }

    private func clockValues(in app: XCUIApplication) -> [String] {
        ["game.clock.black", "game.clock.white"].flatMap {
            app.buttons.matching(identifier: $0).allElementsBoundByIndex
        }.filter { $0.exists && $0.frame.width > 1 }.map { $0.value as? String ?? "" }
    }

    /// v148: with the socket down, stone removal shows the app's banner in
    /// both orientations (where it lands is logged); in Play the running
    /// card's Reconnecting… badge stands in for it. Portrait Chat's two title
    /// chips show only the glow, no label, so the banner returns there.
    /// Nebula & Pearl through the shipping route: its scene, board and dark
    /// window in both orientations, then Home's own appearance after Back.
    func testNebulaPearlThemeOrientations() {
        let app = launchGame(artboard: 1, theme: "nebulaPearl")
        defer {
            XCUIDevice.shared.orientation = .landscapeLeft
            app.terminate()
        }
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot("nebula-pearl-ipad-landscape", in: app)

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(pollUntil(timeout: 10) {
            let window = app.windows.firstMatch.frame
            return window.height > window.width
        })
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot("nebula-pearl-ipad-portrait", in: app)

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(pollUntil(timeout: 10) {
            let window = app.windows.firstMatch.frame
            return window.width > window.height
        })
        Thread.sleep(forTimeInterval: 1)
        tap(app.navigationBars.buttons.element(boundBy: 0), description: "Go back to Home", in: app)
        element(ID.screenHome, in: app)
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot("nebula-pearl-ipad-home-after-back", in: app)
    }

    func testRakedGardenThemeOrientations() {
        auditThemeOrientations(theme: "rakedGarden", title: "Raked Garden", suffix: "-raked-garden",
                               appearance: .light)
    }

    /// Use the real device appearance, without a fixed launch override, so
    /// both transitions happen while the existing Game Detail stays mounted.
    func testRakedGardenThemeAppearanceContinuity() {
        auditThemeAppearanceContinuity(theme: "rakedGarden", title: "Raked Garden", suffix: "raked-garden",
                                       dayBoardMinimum: 0.72, nightBoardMaximum: 0.63, minimumBoardDrop: 0.16)
    }

    func testSurroundStudioThemeAppearanceContinuity() {
        auditThemeAppearanceContinuity(theme: "surroundStudio", title: "Surround Studio", suffix: "surround-studio",
                                       dayBoardMinimum: 0.60, nightBoardMaximum: 0.57, minimumBoardDrop: 0.12,
                                       capturesPanelTransitions: true)
    }

    private func auditThemeAppearanceContinuity(theme: String, title: String, suffix: String,
                                                dayBoardMinimum: Double, nightBoardMaximum: Double,
                                                minimumBoardDrop: Double,
                                                capturesPanelTransitions: Bool = false) {
        let device = XCUIDevice.shared
        let originalAppearance = device.appearance
        let originalOrientation = device.orientation
        // A teardown block still runs when the first failure stops the test,
        // where a `defer` would not, so a failed run cannot leave the device
        // dark. It runs after the launched apps' own termination blocks.
        addTeardownBlock {
            device.appearance = originalAppearance
            device.orientation = originalOrientation
        }

        func requestAppearance(_ appearance: XCUIDevice.Appearance) {
            device.appearance = appearance
            let applied = pollUntil(timeout: 10) { device.appearance == appearance }
            print("[ThemeAppearance \(theme)] requested=\(appearance.rawValue) observed=\(device.appearance.rawValue)")
            XCTAssertTrue(applied, "The device appearance getter must confirm the requested style")
        }

        @discardableResult
        func assertRenderedAppearance(_ appearance: XCUIDevice.Appearance, in app: XCUIApplication,
                                      dayBrightness: Double? = nil) -> Double {
            XCTAssertFalse(app.launchArguments.contains(SurroundUITestContract.appearanceLaunchArgument),
                           "The continuity audit must not pin the app's fixture appearance")
            XCTAssertFalse(app.launchArguments.contains("-AppleInterfaceStyle"))
            XCTAssertEqual(device.appearance, appearance,
                           "Launching or rotating must not reset the requested device appearance")
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10),
                          "Appearance evidence must come from the foreground app")
            let board = element(ID.gameBoard, in: app)
            var brightness: Double?
            let rendered = pollUntil(timeout: 12) {
                brightness = self.meanBrightness(board)
                guard let brightness else { return false }
                // Broad bands distinguish day material from its night grade;
                // they tolerate stones, shadows, grain and native raster scale.
                if appearance == .light { return brightness > dayBoardMinimum }
                return brightness < nightBoardMaximum && dayBrightness.map { $0 - brightness > minimumBoardDrop } != false
            }
            print("[ThemeAppearance \(theme)] requested=\(appearance.rawValue) observed=\(device.appearance.rawValue) boardBrightness=\(brightness.map(String.init(describing:)) ?? "unavailable")")
            if !rendered {
                keepScreenshot("\(suffix)-appearance-not-applied-\(appearance.rawValue)", in: app)
            }
            XCTAssertTrue(rendered,
                          "The rendered board must reach the requested appearance, not only preserve game state")
            return brightness ?? .nan
        }

        func assertState(_ position: String?, clocks: [String], in app: XCUIApplication) {
            let board = element(ID.gameBoard, in: app)
            XCTAssertTrue(pollUntil(timeout: 10) {
                let window = app.windows.firstMatch.frame
                return abs(board.frame.width - board.frame.height) < 1
                    && window.insetBy(dx: -1, dy: -1).contains(board.frame)
                    && board.value as? String == position
                    && self.clockValues(in: app) == clocks
            }, "Appearance and rotation retain the square board, position and clock values")
            XCTAssertEqual(board.value as? String, position)
            XCTAssertEqual(clockValues(in: app), clocks)
        }

        // The getter reports a request even when the Simulator never applies
        // it, as throughout a newly created device's first boot. Home follows
        // the system without a theme, so a live change there first separates
        // a device that ignores requests from a scene that ignores the change.
        requestAppearance(.light)
        let home = launchGame(artboard: 17, theme: theme, opensGame: false)
        let homeScreen = element(ID.screenHome, in: home)
        let homeDay = meanBrightness(homeScreen) ?? .nan
        let deviceAdvice = "If Home also stays unchanged, the Simulator did not apply the request; reboot it and rerun"
        requestAppearance(.dark)
        XCTAssertTrue(pollUntil(timeout: 10) {
            self.meanBrightness(homeScreen).map { homeDay - $0 > 0.2 } == true
        }, "Home must follow the device into dark appearance. \(deviceAdvice)")
        requestAppearance(.light)
        XCTAssertTrue(pollUntil(timeout: 10) {
            self.meanBrightness(homeScreen).map { abs($0 - homeDay) < 0.1 } == true
        }, "Home must follow the device back to light appearance. \(deviceAdvice)")
        home.terminate()

        let play = launchGame(artboard: 17, theme: theme)
        setSidebarCollapsed(true, in: play)
        let playBoard = element(ID.gameBoard, in: play)
        let position = playBoard.value as? String
        let playClocks = clockValues(in: play)
        XCTAssertEqual(position, "position:38:kj")
        XCTAssertFalse(playClocks.isEmpty)
        XCTAssertFalse(playClocks.contains(""), "Clock continuity needs identifiable clock values")
        assertState(position, clocks: playClocks, in: play)
        let dayBrightness = assertRenderedAppearance(.light, in: play)
        let dayFrame = playBoard.frame
        if capturesPanelTransitions {
            auditStudioPanelTransitions(in: play) { step in
                self.capture(17, "\(title) day \(step)", in: play,
                             note: "Same game and appearance through native panel toggles.",
                             suffix: "-\(suffix)-day-landscape-transition-\(step)")
            }
            assertState(position, clocks: playClocks, in: play)
        } else {
            capture(17, "\(title) day Play", in: play,
                    suffix: "-\(suffix)-day-landscape")
        }

        requestAppearance(.dark)
        assertRenderedAppearance(.dark, in: play, dayBrightness: dayBrightness)
        assertState(position, clocks: playClocks, in: play)
        XCTAssertEqual(playBoard.frame.minX, dayFrame.minX, accuracy: 1)
        XCTAssertEqual(playBoard.frame.minY, dayFrame.minY, accuracy: 1)
        XCTAssertEqual(playBoard.frame.width, dayFrame.width, accuracy: 1,
                       "Switching to night changes materials, not board geometry")
        if capturesPanelTransitions {
            auditStudioPanelTransitions(in: play) { step in
                self.capture(17, "\(title) night \(step)", in: play,
                             note: "Same game after a live appearance change and native panel toggles.",
                             suffix: "-\(suffix)-night-landscape-transition-\(step)")
            }
            assertState(position, clocks: playClocks, in: play)
        } else {
            capture(17, "\(title) night Play", in: play,
                    note: "Same game after a live device-appearance change.",
                    suffix: "-\(suffix)-night-landscape")
        }

        device.orientation = .portrait
        XCTAssertTrue(pollUntil(timeout: 10) {
            play.windows.firstMatch.frame.height > play.windows.firstMatch.frame.width
        })
        assertRenderedAppearance(.dark, in: play, dayBrightness: dayBrightness)
        assertState(position, clocks: playClocks, in: play)
        capture(17, "\(title) night Play", in: play,
                note: "Same game after native rotation.",
                suffix: "-\(suffix)-night-portrait")
        play.terminate()

        // This fixture starts on the marked three-move analysis branch.
        // The subsequent night-to-day change must not rebuild its session.
        let analysis = launchGame(artboard: 26, portrait: true, theme: theme)
        setSidebarCollapsed(true, in: analysis)
        let analysisBoard = element(ID.gameBoard, in: analysis)
        let variation = analysisBoard.value as? String
        let analysisClocks = clockValues(in: analysis)
        XCTAssertEqual(variation, "variation:38:lj-lk-mk")
        XCTAssertFalse(analysisClocks.isEmpty)
        XCTAssertFalse(analysisClocks.contains(""))
        let selected = element(ID.gameAnalysisPosition(baseMoveNumber: 38,
                                                        movePath: ["lj", "lk", "mk"]), in: analysis)
        for appearance in [XCUIDevice.Appearance.dark, .light] {
            requestAppearance(appearance)
            assertRenderedAppearance(appearance, in: analysis, dayBrightness: dayBrightness)
            assertState(variation, clocks: analysisClocks, in: analysis)
            XCTAssertTrue(selected.isSelected, "Appearance changes retain the selected branch")
            let viewport = assertAuditAnalysisTreeAxis(vertical: false, in: analysis)
            XCTAssertTrue(viewport.insetBy(dx: -1, dy: -1)
                .contains(selected.frame.insetBy(dx: -3, dy: -3)),
                          "The selected analysis stone and ring stay in the visible tree")
            let name = appearance == .dark ? "night" : "day"
            capture(26, "\(title) \(name) Analyze", in: analysis,
                    note: "Selected variation retained through a live appearance change.",
                    suffix: "-\(suffix)-\(name)-analyze")
        }

        tap(analysis.navigationBars.buttons.element(boundBy: 0), description: "Go back to Home", in: analysis)
        element(ID.screenHome, in: analysis)
        XCTAssertFalse(analysis.descendants(matching: .any).matching(identifier: ID.gameBoard).firstMatch.exists,
                       "Back leaves Game Detail and its appearance scope")
        keepScreenshot("\(suffix)-ipad-day-home-after-night", in: analysis)
    }

    /// Measure rendered pixels rather than trusting a device setter or a
    /// capture's name. A small sRGB buffer keeps this check scale independent.
    private func meanBrightness(_ element: XCUIElement) -> Double? {
        guard let image = element.screenshot().image.cgImage,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: size, height: size,
                                          bitsPerComponent: 8, bytesPerRow: size * 4,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                            | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return nil }
        var sum = 0.0
        var count = 0
        // Exclude the outer margin; average a wide area so one stone, a
        // last-move ring or a local cast shadow cannot decide the result.
        for y in 6..<58 {
            for x in 6..<58 {
                let index = (y * size + x) * 4
                sum += (0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1])
                        + 0.0722 * Double(pixels[index + 2])) / 255
                count += 1
            }
        }
        return sum / Double(count)
    }

    func testFrostPineThemeOrientations() {
        auditThemeOrientations(theme: "frostPine", title: "Frost & Pine",
                         suffix: "-frost-pine", appearance: .light)
    }

    func testFrostPineNightThemeOrientations() {
        auditThemeOrientations(theme: "frostPine", title: "Frost & Pine at night",
                         suffix: "-frost-pine-night", appearance: .dark)
    }

    func testFrostPineThemePanels() {
        auditThemePanels(theme: "frostPine", title: "Frost & Pine",
                         suffix: "-frost-pine", appearance: .light)
    }

    func testFrostPineNightThemePanels() {
        auditThemePanels(theme: "frostPine", title: "Frost & Pine at night",
                         suffix: "-frost-pine-night", appearance: .dark)
    }

    func testFrostPineThemeNarrowWindow() {
        auditNarrowNativeWindowArtboard(theme: "frostPine", suffix: "-frost-pine", appearance: .light)
    }

    func testSurroundStudioThemeOrientations() {
        auditThemeOrientations(theme: "surroundStudio", title: "Surround Studio", suffix: "-surround-studio",
                               appearance: .light)
    }

    func testFeltMeadowThemeOrientations() {
        auditThemeOrientations(theme: "feltMeadow", title: "Felt Meadow", suffix: "-felt-meadow", appearance: .light)
    }

    func testFeltMeadowNightThemeOrientations() {
        auditThemeOrientations(theme: "feltMeadow", title: "Felt Meadow at night", suffix: "-felt-meadow-night",
                               appearance: .dark)
    }

    private func auditThemeOrientations(theme: String, title: String, suffix: String,
                                        appearance: SurroundUITestContract.Appearance? = nil) {
        let app = launchGame(artboard: 17, theme: theme, appearance: appearance)
        defer {
            XCUIDevice.shared.orientation = .landscapeLeft
            app.terminate()
        }
        setSidebarCollapsed(true, in: app)
        let board = element(ID.gameBoard, in: app)
        let value = board.value as? String
        XCTAssertNotNil(value, "The audit records an identifiable board position")
        for portrait in [false, true] {
            XCUIDevice.shared.orientation = portrait ? .portrait : .landscapeLeft
            XCTAssertTrue(pollUntil(timeout: 10) {
                let window = app.windows.firstMatch.frame
                return (window.height > window.width) == portrait
                    && abs(board.frame.width - board.frame.height) < 1
                    && window.insetBy(dx: -1, dy: -1).contains(board.frame)
            }, "The square themed board fits the active window after rotation")
            XCTAssertEqual(board.value as? String, value, "Rotation retains the displayed position")
            capture(17, "\(title) Play", in: app,
                    note: "The same game is retained through native rotation.",
                    suffix: portrait ? "\(suffix)-portrait" : "\(suffix)-landscape")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(pollUntil(timeout: 10) {
            let window = app.windows.firstMatch.frame
            return window.width > window.height
        })
        tap(app.navigationBars.buttons.element(boundBy: 0), description: "Go back to Home", in: app)
        element(ID.screenHome, in: app)
        keepScreenshot("\(suffix.dropFirst())-ipad-home-after-back", in: app)
    }

    func testRakedGardenThemePanels() {
        auditThemePanels(theme: "rakedGarden", title: "Raked Garden", suffix: "-raked-garden",
                         appearance: .light)
    }

    func testSurroundStudioThemePanels() {
        auditThemePanels(theme: "surroundStudio", title: "Surround Studio", suffix: "-surround-studio",
                         appearance: .light)
    }

    func testFeltMeadowThemePanels() {
        auditThemePanels(theme: "feltMeadow", title: "Felt Meadow", suffix: "-felt-meadow", appearance: .light)
    }

    func testFeltMeadowNightThemePanels() {
        auditThemePanels(theme: "feltMeadow", title: "Felt Meadow at night", suffix: "-felt-meadow-night",
                         appearance: .dark)
    }

    func testSurroundStudioThemePanelTransitions() {
        auditThemePanelTransitions(theme: "surroundStudio", title: "Surround Studio", suffix: "-surround-studio")
    }

    func testFeltMeadowThemePanelTransitions() {
        auditThemePanelTransitions(theme: "feltMeadow", title: "Felt Meadow", suffix: "-felt-meadow")
    }

    private func auditThemePanelTransitions(theme: String, title: String, suffix: String) {
        let app = launchGame(artboard: 17, portrait: true, theme: theme, appearance: .light)
        defer {
            XCUIDevice.shared.orientation = .landscapeLeft
            app.terminate()
        }
        setSidebarCollapsed(true, in: app)
        let board = element(ID.gameBoard, in: app)
        let value = board.value as? String
        for portrait in [true, false] {
            XCUIDevice.shared.orientation = portrait ? .portrait : .landscapeLeft
            XCTAssertTrue(pollUntil(timeout: 10) {
                let window = app.windows.firstMatch.frame
                return (window.height > window.width) == portrait
            })
            XCTAssertEqual(board.value as? String, value, "Rotation retains the same game position")
            let orientation = portrait ? "portrait" : "landscape"
            auditStudioPanelTransitions(in: app) { step in
                self.capture(17, "\(title) \(orientation), \(step)", in: app,
                             note: "Same session; compare fixed decoration across panel transitions.",
                             suffix: "\(suffix)-transition-\(orientation)-\(step)")
            }
        }
    }

    private func auditThemePanels(theme: String, title: String, suffix: String,
                                  appearance: SurroundUITestContract.Appearance? = nil) {
        defer { XCUIDevice.shared.orientation = .landscapeLeft }
        for (number, portrait, state) in [
            (3, false, "chat"), (14, true, "chat"),
            (24, false, "analyze"), (26, true, "analyze"),
            (38, false, "zen"), (40, true, "zen"),
        ] {
            let app = launchGame(artboard: number, portrait: portrait, theme: theme,
                                 appearance: appearance)
            setSidebarCollapsed(true, in: app)
            auditChat(state == "chat", in: app)
            if state == "chat" {
                dismissSoftwareKeyboardIfNeeded(in: app)
                element(ID.gameChatInput, in: app, matching: .textField)
                XCTAssertFalse(app.descendants(matching: .any)
                    .matching(identifier: ID.gameAnalyzeControlBar).firstMatch.exists)
            }
            if state == "zen" {
                auditToolbarAction(ID.gameZenEnter, label: "Zen mode", in: app)
                assertZenHidesChrome(in: app)
            }
            capture(number, "\(title) \(state)", in: app, suffix: suffix)
            app.terminate()
        }
    }

    func testConnectionBannerPlacement() {
        for portrait in [false, true] {
            let app = launchGame(artboard: portrait ? 14 : 3, portrait: portrait,
                                 clock: "stone-removal", socketDown: true)
            setSidebarCollapsed(true, in: app)
            let banner = connectionBanner(in: app)
            XCTAssertTrue(banner.waitForExistence(timeout: 10), "Stone removal shows the app's connection banner")
            XCTAssertFalse(clockValues(in: app).contains { $0.hasPrefix("Reconnecting…") })
            let accept = app.buttons["Accept"].firstMatch
            if accept.waitForExistence(timeout: 5) {
                XCTAssertFalse(accept.isEnabled, "Accept is disabled while disconnected")
            }
            recordConnectionBannerPlacement(portrait ? "ipad-portrait-stone-removal" : "ipad-landscape-stone-removal",
                                            in: app)
            app.terminate()
        }
        let app = launchGame(artboard: 14, portrait: true, socketDown: true)
        setSidebarCollapsed(true, in: app)
        let banner = connectionBanner(in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { self.clockValues(in: app).contains { $0.hasPrefix("Reconnecting…") } },
                      "The running card shows Reconnecting…")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(banner.exists, "Play: only the badge shows")
        recordConnectionBannerPlacement("ipad-portrait-play-badge", in: app)
        auditChat(true, in: app)
        dismissSoftwareKeyboardIfNeeded(in: app)
        let chips = app.navigationBars.buttons.matching(NSPredicate(
            format: "identifier == 'game.clock.black' OR identifier == 'game.clock.white'")).allElementsBoundByIndex
        print("[ConnectionBanner] ipad portrait chat chips \(chips.map { "\($0.identifier) \($0.frame) texts=\($0.staticTexts.allElementsBoundByIndex.map(\.label))" })")
        let labelled = chips.contains { $0.staticTexts["Reconnecting…"].exists }
        XCTAssertEqual(banner.waitForExistence(timeout: 5), !labelled,
                       "The banner shows unless a title chip renders the Reconnecting… label")
        recordConnectionBannerPlacement("ipad-portrait-chat-chips", in: app)
    }

    /// v148: the header's profile action shares the content's chat hand-off.
    /// With the composer focused, open a profile from a header clock's details
    /// and go back: no keyboard on the profile, and the draft is kept.
    func testHeaderClockProfileKeepsDraftWithoutKeyboard() {
        let app = launchGame(artboard: 71, portrait: true)
        setSidebarCollapsed(true, in: app)
        auditChat(true, in: app)
        let draft = SurroundUITestContract.gameDetailDesignChatDraft
        let input = element(ID.gameChatInput, in: app, matching: .textField)
        input.tap()
        input.typeText(draft)
        XCTAssertTrue(pollUntil(timeout: 5) { self.chatInputHasKeyboardFocus(in: app) }, "The composer is focused")
        let keyboard = app.keyboards.firstMatch
        let software = pollUntil(timeout: 3) {
            keyboard.exists && keyboard.frame.height > 100 && keyboard.frame.intersects(app.windows.firstMatch.frame)
        }
        print("[ProfileHandOff] software keyboard=\(software) keyboard=\(keyboard.exists ? "\(keyboard.frame)" : "none")")
        let chip = app.navigationBars.buttons.matching(identifier: "game.clock.white").firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "The header carries the opponent's clock chip")
        tap(chip, description: "Open the header clock's details", in: app)
        if !app.staticTexts["Time control"].waitForExistence(timeout: 2) {
            // An on-screen keyboard takes the first tap (rule 26); with a
            // hardware keyboard the first tap opens the details.
            XCTAssertTrue(software, "Only an on-screen keyboard consumes the first header tap")
            tap(chip, description: "Open the header clock's details", in: app)
        }
        XCTAssertTrue(app.staticTexts["Time control"].waitForExistence(timeout: 5), "Details open from the header chip")
        let row = app.popovers.buttons.matching(NSPredicate(format: "label CONTAINS 'tenuki_tom'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Details list the opponent")
        tap(row, description: "Open the opponent's profile", in: app)
        let profile = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", [
            ID.profileLoaded, ID.profileLoading, ID.profileError, ID.profileIdentity])).firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 10), "The profile is pushed")
        Thread.sleep(forTimeInterval: 1.5)
        let keyboardOnProfile = app.keyboards.firstMatch
        print("[ProfileHandOff] on profile: keyboard=\(keyboardOnProfile.exists ? "\(keyboardOnProfile.frame)" : "none") focused=\(chatInputHasKeyboardFocus(in: app))")
        XCTAssertFalse(keyboardOnProfile.exists && keyboardOnProfile.frame.intersects(app.windows.firstMatch.frame),
                       "No keyboard (or shortcut bar) shows on the profile")
        XCTAssertFalse(chatInputHasKeyboardFocus(in: app), "The game's composer is not focused behind the profile")
        keepScreenshot("profile-hand-off-on-profile", in: app)
        let back = app.navigationBars.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "BackButton", "Back")).allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(back, "Back is available")
        if let back { tap(back, description: "Return to the game", in: app) }
        let returned = element(ID.gameChatInput, in: app, matching: .textField)
        XCTAssertEqual(returned.value as? String, draft, "The draft is kept")
        Thread.sleep(forTimeInterval: 1)
        print("[ProfileHandOff] back in game: keyboard=\(app.keyboards.firstMatch.exists ? "\(app.keyboards.firstMatch.frame)" : "none") focused=\(chatInputHasKeyboardFocus(in: app))")
        keepScreenshot("profile-hand-off-back-in-game", in: app)
    }

    func testChatOpensAndClosesAtItsFinalSize() {
        // v145: the panel in the side column arrives at its final size and
        // fades/slides in and out; the host records the screen meanwhile.
        let app = launchGame(artboard: 3, dark: true)
        defer { app.terminate() }
        setSidebarCollapsed(true, in: app)
        auditAnalyzing(false, in: app)
        auditChat(false, in: app)
        recordChatToggle("chat-toggle-ipad-landscape", in: app,
                         open: { auditChat(true, in: app) },
                         close: { auditChat(false, in: app) })
    }

    func testV143LandscapePanelsAndSidebarPreserveBoard() {
        let app = launchGame(artboard: 3, dark: true)
        defer { app.terminate() }
        setSidebarCollapsed(true, in: app)
        auditChat(false, in: app)
        auditAnalyzing(false, in: app)
        let board = element(ID.gameBoard, in: app)
        let playFrame = board.frame
        func assertBoardUnchanged(_ state: String) {
            XCTAssertTrue(pollUntil(timeout: 5) {
                let frame = board.frame
                return abs(frame.minX - playFrame.minX) <= 1
                    && abs(frame.minY - playFrame.minY) <= 1
                    && abs(frame.width - playFrame.width) <= 1
                    && abs(frame.height - playFrame.height) <= 1
            }, "\(state) must retain Play's board frame \(playFrame); got \(board.frame)")
        }
        auditChat(true, in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: ID.gameAnalyzeControlBar).firstMatch.exists)
        assertBoardUnchanged("Chat")
        keepScreenshot("v143-ipad-landscape-chat-side-column", in: app)
        auditAnalyzing(true, in: app)
        XCTAssertFalse(app.scrollViews[ID.gameChatLog].exists, "Analyze replaces Chat")
        XCTAssertFalse(app.textFields[ID.gameChatInput].exists)
        assertBoardUnchanged("Analyze")
        let tree = assertAuditAnalysisTreeAxis(vertical: true, in: app)
        let controls = element(ID.gameAnalyzeControlBar, in: app)
        let blackClock = element("game.clock.black", in: app, matching: .button)
        let whiteClock = element("game.clock.white", in: app, matching: .button)
        XCTAssertGreaterThanOrEqual(blackClock.frame.height, 80, "Analyze retains full clocks")
        XCTAssertGreaterThanOrEqual(whiteClock.frame.height, 80)
        XCTAssertGreaterThanOrEqual(tree.minY, max(blackClock.frame.maxY, whiteClock.frame.maxY))
        XCTAssertLessThanOrEqual(tree.maxY, controls.frame.minY + 1)
        keepScreenshot("v143-ipad-landscape-analysis-side-column", in: app)
        auditChat(true, in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: ID.gameAnalyzeControlBar).firstMatch.exists,
                       "Chat replaces Analyze")
        assertBoardUnchanged("Chat after Analyze")
        auditChat(false, in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: ID.gameAnalyzeControlBar).firstMatch.exists,
                       "Closing Chat returns to Play")
        assertBoardUnchanged("Play after closing Chat")

        setSidebarCollapsed(false, in: app)
        assertBoardUnchanged("The native sidebar overlay")
        XCTAssertTrue(board.isHittable,
                      "The uncovered board stays interactive while the sidebar overlays the game")
        keepScreenshot("v143-ipad-landscape-sidebar-over-play", in: app)
        setSidebarCollapsed(true, in: app)
        assertBoardUnchanged("Closing the sidebar")
        tap("game.clock.white", in: app, matching: .button)
        element("game.details", in: app)
        XCTAssertTrue(app.staticTexts["Time control"].exists)
        XCTAssertTrue(app.popovers.firstMatch.exists, "Details are a popover anchored to the clock")
        keepScreenshot("v144-ipad-opaque-clock-details-popover", in: app)
        dismissPopover(in: app)
        assertBoardUnchanged("Closing game details")
        XCTAssertTrue(board.isHittable)
    }

    func testV143PortraitChatSitsAboveBoardWithHeaderClocks() {
        let app = launchGame(artboard: 14, portrait: true)
        defer { app.terminate() }
        setSidebarCollapsed(true, in: app)
        auditChat(true, in: app)
        let transcript = element(ID.gameChatLog, in: app, matching: .scrollView)
        let input = element(ID.gameChatInput, in: app, matching: .textField)
        let board = element(ID.gameBoard, in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: ID.gameAnalyzeControlBar).firstMatch.exists)
        XCTAssertLessThanOrEqual(transcript.frame.maxY, input.frame.minY + 1)
        XCTAssertLessThanOrEqual(input.frame.maxY, board.frame.minY + 1,
                                 "Portrait Chat occupies the space above the board")
        let clocks = ["game.clock.black", "game.clock.white"].flatMap {
            app.buttons.matching(identifier: $0).allElementsBoundByIndex
        }.filter { $0.isHittable }
        XCTAssertFalse(clocks.isEmpty)
        for clock in clocks {
            XCTAssertTrue(app.navigationBars.allElementsBoundByIndex.contains {
                $0.frame.insetBy(dx: -1, dy: -1).contains(clock.frame)
            }, "The portrait Chat clock belongs to the native header")
            XCTAssertFalse(clock.staticTexts["Your move"].exists,
                           "Two title chips rely on the glow; the turn label is for a single chip")
        }
        XCTAssertEqual(clocks.count, 2, "Portrait Chat shows both title chips")
        if clocks.count == 2 {
            let pair = clocks[0].frame.union(clocks[1].frame)
            let window = app.windows.firstMatch.frame
            XCTAssertGreaterThan(pair.minX, window.minX + window.width * 0.25,
                                 "The chips are centred in the title slot, not placed after Back; got \(pair)")
        }
        keepScreenshot("v143-ipad-portrait-chat-above-board", in: app)

        let chatBoardFrame = board.frame
        let chatBoardValue = board.value as? String
        let windowBeforeSidebar = app.windows.firstMatch.frame
        let barsBeforeSidebar = app.navigationBars.allElementsBoundByIndex.map {
            "\($0.identifier): \($0.frame)"
        }.joined(separator: "\n")
        let layoutGeometry = app.descendants(matching: .any).matching(identifier: "game.layout.geometry").firstMatch
        let geometryBeforeSidebar = layoutGeometry.exists ? String(describing: layoutGeometry.value) : "absent"
        XCTAssertNotNil(chatBoardValue)
        setSidebarCollapsed(false, in: app)
        keepScreenshot("v143-ipad-portrait-sidebar-over-chat", in: app)
        let sidebarGeometry = XCTAttachment(string: """
        Board before: \(chatBoardFrame)
        Board after: \(board.frame)
        Window before: \(windowBeforeSidebar)
        Window after: \(app.windows.firstMatch.frame)
        Native navigation bars before:
        \(barsBeforeSidebar)
        Native navigation bars after:
        \(app.navigationBars.allElementsBoundByIndex.map { "\($0.identifier): \($0.frame)" }.joined(separator: "\n"))
        Game layout geometry before: \(geometryBeforeSidebar)
        Game layout geometry after: \(layoutGeometry.exists ? String(describing: layoutGeometry.value) : "absent")
        Accessibility frames may reflect clipping; compare the layout diagnostic and screenshot.

        \(app.debugDescription)
        """)
        sidebarGeometry.name = "v143-ipad-portrait-sidebar-before-after-geometry"
        sidebarGeometry.lifetime = .keepAlways
        add(sidebarGeometry)
        let sidebarSettings = element(ID.navigationSettings, in: app)
        XCTAssertTrue(sidebarSettings.isHittable, "The native sidebar is open")
        XCTAssertTrue(pollUntil(timeout: 5) {
            let frame = board.frame
            return abs(frame.minX - chatBoardFrame.minX) <= 1
                && abs(frame.minY - chatBoardFrame.minY) <= 1
                && abs(frame.width - chatBoardFrame.width) <= 1
                && abs(frame.height - chatBoardFrame.height) <= 1
        }, "The portrait sidebar overlays the unchanged Chat board")
        let dismissPoint = CGVector(dx: 0.96, dy: 0.55)
        XCTAssertGreaterThan(board.frame.minX + board.frame.width * dismissPoint.dx,
                             sidebarSettings.frame.maxX + 8,
                             "The dismissal tap must land on the uncovered board")
        activate(board, at: dismissPoint)
        XCTAssertTrue(pollUntil(timeout: 5) { !sidebarSettings.isHittable },
                      "Tapping the uncovered board dismisses the native sidebar")
        XCTAssertEqual(board.value as? String, chatBoardValue,
                       "The sidebar dismissal tap must not change the game position")
        XCTAssertEqual(board.frame.minX, chatBoardFrame.minX, accuracy: 1)
        XCTAssertEqual(board.frame.minY, chatBoardFrame.minY, accuracy: 1)
        XCTAssertEqual(board.frame.width, chatBoardFrame.width, accuracy: 1)
        XCTAssertEqual(board.frame.height, chatBoardFrame.height, accuracy: 1)
        keepScreenshot("v143-ipad-portrait-sidebar-dismissed-by-board", in: app)
    }

    func testSidebarClosedBeforeRotationStaysClosedOverTheGame() {
        // Live Beta repro: on Home in landscape, open the sidebar; rotate to
        // portrait (it hides); open a game; rotate to landscape. UIKit used to
        // restore its landscape sidebar over the clocks and chat.
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.emptyMessagesLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.home.rawValue,
            SurroundUITestContract.gameDetailDesignArtboardLaunchArgument, "3",
            SurroundUITestContract.appearanceLaunchArgument, "light",
        ], orientation: .landscapeLeft)
        defer {
            XCUIDevice.shared.orientation = .landscapeLeft
            app.terminate()
        }
        element(ID.screenHome, in: app)
        restoreFullWindow(in: app)
        setSidebarCollapsed(false, in: app)
        let sidebarSettings = app.descendants(matching: .any).matching(identifier: ID.navigationSettings).firstMatch
        XCTAssertTrue(pollUntil(timeout: 5) { sidebarSettings.isHittable }, "The sidebar opens on Home")
        keepScreenshot("ipad-sidebar-repro-1-home-landscape-open", in: app)

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(pollUntil(timeout: 10) {
            let window = app.windows.firstMatch.frame
            return window.height > window.width
        })
        Thread.sleep(forTimeInterval: 1)
        setSidebarCollapsed(true, in: app)
        XCTAssertTrue(pollUntil(timeout: 5) { !sidebarSettings.isHittable }, "Portrait Home has the sidebar closed")
        openDesignGame(in: app)
        keepScreenshot("ipad-sidebar-repro-2-game-portrait", in: app)

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(pollUntil(timeout: 10) {
            let window = app.windows.firstMatch.frame
            return window.width > window.height
        })
        // Let UIKit finish the transition and any restored visibility.
        Thread.sleep(forTimeInterval: 2)
        let reopened = sidebarSettings.exists && sidebarSettings.isHittable
        keepScreenshot("ipad-sidebar-repro-3-game-landscape", in: app)
        print("[IPadSidebarRotation] reopened=\(reopened) board=\(element(ID.gameBoard, in: app).frame)")
        XCTAssertFalse(reopened, "Rotating a game to landscape must not reopen the sidebar over it")
        XCTAssertTrue(element(ID.gameBoard, in: app).isHittable)
    }

    func testV143SidebarRotationPreservesPanelAndBoard() {
        let app = launchGame(artboard: 3)
        defer { app.terminate() }
        setSidebarCollapsed(true, in: app)
        auditChat(true, in: app)
        setSidebarCollapsed(false, in: app)
        let sidebarSettings = element(ID.navigationSettings, in: app)
        XCTAssertTrue(sidebarSettings.isHittable)

        // UIKit owns drawer visibility and may close it during rotation. The
        // selected panel and settled portrait board must survive either policy.
        XCUIDevice.shared.orientation = .portrait
        let board = element(ID.gameBoard, in: app)
        let geometry = element("game.layout.geometry", in: app)
        var lastFrame: CGRect?
        var lastDiagnostic: String?
        var stableSince = Date()
        XCTAssertTrue(pollUntil(timeout: 10) {
            let window = app.windows.firstMatch.frame
            guard window.height > window.width else { return false }
            let frame = board.frame
            let diagnostic = geometry.value as? String
            guard frame.width > 0, frame.height > 0, diagnostic != nil else { return false }
            if frame == lastFrame && diagnostic == lastDiagnostic {
                return Date().timeIntervalSince(stableSince) >= 0.75
            }
            lastFrame = frame
            lastDiagnostic = diagnostic
            stableSince = Date()
            return false
        }, "The first portrait board layout must settle after rotation")
        let sidebarStayedOpen = sidebarSettings.isHittable
        let portraitBoardFrame = board.frame
        let portraitBoardValue = board.value as? String

        func assertPortraitBoardUnchanged(_ state: String) {
            XCTAssertTrue(pollUntil(timeout: 5) {
                let frame = board.frame
                return abs(frame.minX - portraitBoardFrame.minX) <= 1
                    && abs(frame.minY - portraitBoardFrame.minY) <= 1
                    && abs(frame.width - portraitBoardFrame.width) <= 1
                    && abs(frame.height - portraitBoardFrame.height) <= 1
            }, "\(state) preserves the settled portrait board layout")
            XCTAssertEqual(board.value as? String, portraitBoardValue)
        }

        func assertChatSelected() {
            XCTAssertTrue(app.scrollViews[ID.gameChatLog].exists, "Chat stays selected through rotation and sidebar changes")
            XCTAssertTrue(app.textFields[ID.gameChatInput].exists)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: ID.gameAnalyzeControlBar).firstMatch.exists)
        }

        func recordPortraitState(_ state: String) {
            let name = "v143-ipad-sidebar-rotation-portrait-\(state)"
            keepScreenshot(name, in: app)
            let attachment = XCTAttachment(string: """
            Sidebar stayed open after rotation: \(sidebarStayedOpen)
            Sidebar currently visible: \(sidebarSettings.isHittable)
            Board: \(board.frame)
            Board value: \(String(describing: board.value))
            Window: \(app.windows.firstMatch.frame)
            Game layout geometry: \(String(describing: geometry.value))
            Native navigation bars: \(app.navigationBars.allElementsBoundByIndex.map { "\($0.identifier): \($0.frame)" }.joined(separator: "\n"))

            \(app.debugDescription)
            """)
            attachment.name = name + "-geometry"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        assertChatSelected()
        recordPortraitState(sidebarStayedOpen ? "settled-open" : "settled-closed")
        if !sidebarStayedOpen {
            setSidebarCollapsed(false, in: app)
            recordPortraitState("reopened")
            assertPortraitBoardUnchanged("Reopening the native sidebar after UIKit closed it")
            assertChatSelected()
        }
        setSidebarCollapsed(true, in: app)
        recordPortraitState("closed")
        assertPortraitBoardUnchanged("Closing the native sidebar")
        assertChatSelected()
    }

    private func keyboardCapture(_ number: Int, in app: XCUIApplication) {
        auditAnalyzing(false, in: app)
        auditChat(true, in: app)
        let board = element(ID.gameBoard, in: app)
        let frameBeforeKeyboard = board.frame
        let opponentAvatar = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", ID.profileBannerAvatarPrefix
        )).allElementsBoundByIndex.min { $0.frame.minY < $1.frame.minY }
        let avatarFrameBeforeKeyboard = opponentAvatar?.frame
        let input = element(ID.gameChatInput, in: app, matching: .textField)
        input.tap()
        input.typeText(SurroundUITestContract.gameDetailDesignChatDraft)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        capture(number, "Chat with native software keyboard", in: app)
        XCTAssertEqual(board.frame.minX, frameBeforeKeyboard.minX, accuracy: 1)
        XCTAssertEqual(board.frame.minY, frameBeforeKeyboard.minY, accuracy: 1)
        XCTAssertEqual(board.frame.width, frameBeforeKeyboard.width, accuracy: 1,
                       "The regular-width board stays in place underneath the keyboard")
        if let opponentAvatar, let before = avatarFrameBeforeKeyboard {
            XCTAssertEqual(opponentAvatar.frame.minX, before.minX, accuracy: 1)
            XCTAssertEqual(opponentAvatar.frame.minY, before.minY, accuracy: 1,
                           "Regular-width identity chips keep their style while the keyboard overlays the board")
        }
    }

    private func clockCapture(_ number: Int, in app: XCUIApplication) {
        auditAnalyzing(false, in: app)
        auditChat(number == 61, in: app)
        tap("game.clock.white", in: app)
        element("game.details", in: app)
        XCTAssertTrue(app.popovers.firstMatch.exists, "Details are a popover anchored to the clock")
        capture(number, "Opaque clock details popover", in: app)
        dismissPopover(in: app)
    }

    func testKeyboardArtboards() {
        for number in [69, 71] {
            let app = launchGame(artboard: number, dark: number == 69,
                                 portrait: number == 71)
            setSidebarCollapsed(true, in: app)
            keyboardCapture(number, in: app)

            let board = element(ID.gameBoard, in: app)
            let frameWhileTyping = board.frame
            let clock = "game.clock.black"
            // Rule 26's "first tap only dismisses" is for an on-screen keyboard.
            // With a hardware keyboard (nothing on screen) the tap plays and
            // ends editing at the same time (live Beta, games 22237 and 22238).
            let keyboard = app.keyboards.firstMatch
            let softwareKeyboard = keyboard.exists && keyboard.frame.height > 100
                && keyboard.frame.intersects(app.windows.firstMatch.frame)
            print("[IPadKeyboardMode] artboard=\(number) software=\(softwareKeyboard) keyboard=\(keyboard.frame)")
            tap(clock, in: app, matching: .button)
            guard softwareKeyboard else {
                XCTAssertTrue(app.staticTexts["Time control"].waitForExistence(timeout: 5),
                              "With a hardware keyboard the first clock tap opens details on artboard \(number)")
                XCTAssertTrue(pollUntil(timeout: 5) { !self.chatInputHasKeyboardFocus(in: app) },
                              "That tap also ends editing")
                XCTAssertEqual(element(ID.gameChatInput, in: app, matching: .textField).value as? String,
                               SurroundUITestContract.gameDetailDesignChatDraft)
                keepScreenshot(String(format: "artboard-%03d-ipad-hardware-keyboard-tap", number), in: app)
                app.terminate()
                continue
            }
            XCTAssertTrue(pollUntil(timeout: 5) { !app.keyboards.firstMatch.exists },
                          "The first clock tap dismisses the keyboard on artboard \(number)")
            XCTAssertFalse(app.staticTexts["Time control"].exists,
                           "The dismissal tap must not also open clock details")
            XCTAssertEqual(board.frame.minX, frameWhileTyping.minX, accuracy: 1)
            XCTAssertEqual(board.frame.minY, frameWhileTyping.minY, accuracy: 1)
            XCTAssertEqual(board.frame.width, frameWhileTyping.width, accuracy: 1)
            XCTAssertEqual(board.frame.height, frameWhileTyping.height, accuracy: 1,
                           "The regular-width board retains its geometry after keyboard dismissal")
            XCTAssertEqual(element(ID.gameChatInput, in: app, matching: .textField).value as? String,
                           SurroundUITestContract.gameDetailDesignChatDraft)
            keepScreenshot(String(format: "artboard-%03d-ipad-keyboard-dismissed", number), in: app)

            tap(clock, in: app, matching: .button)
            XCTAssertTrue(app.staticTexts["Time control"].waitForExistence(timeout: 5),
                          "The second clock tap opens details on artboard \(number)")
            app.terminate()
        }
    }

    func testDarkLandscapeArtboards() {
        for number in [3, 17, 24, 38, 61, 69] {
            let app = launchGame(artboard: number, dark: true)
            setSidebarCollapsed(true, in: app)
            auditChat([3, 61, 69].contains(number), in: app)
            if number == 38 {
                auditToolbarAction(ID.gameZenEnter, label: "Zen mode", in: app)
            }
            if number == 61 { clockCapture(number, in: app) }
            else if number == 69 { keyboardCapture(number, in: app) }
            else { capture(number, "Landscape dark", in: app) }
            app.terminate()
        }
    }

    func testZenStatusArtboards() {
        for number in [17, 38, 40] {
            let app = launchGame(artboard: number, dark: [17, 38].contains(number), portrait: number == 40)
            setSidebarCollapsed(true, in: app)
            auditChat(false, in: app)
            if number != 17 { auditToolbarAction(ID.gameZenEnter, label: "Zen mode", in: app) }
            capture(number, "Focused status alignment", in: app)
            if number != 17 { assertZenHidesChrome(in: app) }
            app.terminate()
        }
    }

    func testDesignAnalysisArtboards() {
        for number in [24, 26] {
            let app = launchGame(artboard: number, dark: number != 26, portrait: number == 26)
            setSidebarCollapsed(true, in: app)
            auditChat(false, in: app)
            capture(number, "Focused design analysis history and selected variation", in: app)
            app.terminate()
        }
    }

    func testVerticalAnalysisRevealsDeepBranchSelection() throws {
        let app = launchGame(artboard: 24)
        defer { app.terminate() }
        setSidebarCollapsed(true, in: app)
        auditAnalyzing(true, in: app)
        auditChat(false, in: app)
        let viewport = assertAuditAnalysisTreeAxis(vertical: true, in: app)
        XCTAssertLessThanOrEqual(viewport.width, 401)
        XCTAssertGreaterThanOrEqual(viewport.width, 280,
                                    "Exercise the regular landscape analysis column")
        let board = element(ID.gameBoard, in: app)
        XCTAssertEqual(board.value as? String, "variation:38:lj-lk-mk")

        // Start each legal sibling at the fixture's live position. Eight
        // first-column alternatives extend beyond the 400pt analysis column.
        for _ in 0..<3 { tap(ID.gameAnalyzePrevious, in: app, matching: .button) }
        let rootBoardValue = try XCTUnwrap(board.value as? String)
        XCTAssertTrue(rootBoardValue.hasPrefix("position:38:"))
        func expectBoard(_ value: String) {
            XCTAssertTrue(pollUntil(timeout: 5) { board.value as? String == value },
                          "Expected analysis board \(value), got \(String(describing: board.value))")
        }
        for (row, move) in ["aa", "ab", "ac", "ad", "ae", "af", "ag", "ah"].enumerated() {
            if row > 0 {
                tap(ID.gameAnalyzeBackToFork, in: app, matching: .button)
                expectBoard(rootBoardValue)
            }
            activate(board, at: CGVector(dx: 0.5 / 19, dy: (CGFloat(row) + 0.5) / 19))
            expectBoard("variation:38:\(move)")
        }

        // Select through the toolbar, without a gesture that could itself
        // scroll the offscreen node into view. Returning to a prior branch must
        // reveal the complete selection ring as well as preserve its board.
        for move in ["ag", "af", "ae", "ad", "ac", "ab", "aa"] {
            tap(ID.gameAnalyzePreviousBranch, in: app, matching: .button)
            expectBoard("variation:38:\(move)")
        }
        for move in ["ab", "ac", "ad", "ae", "af", "ag", "ah"] {
            tap(ID.gameAnalyzeNextBranch, in: app, matching: .button)
            let expectedBoard = "variation:38:\(move)"
            expectBoard(expectedBoard)
            let identifier = ID.gameAnalysisPosition(baseMoveNumber: 38, movePath: [move])
            let node = element(identifier, in: app, matching: .button)
            assertSelected(identifier, in: app)
            XCTAssertTrue(pollUntil(timeout: 5) {
                // The 36pt ring extends 3pt beyond the accessible 30pt stone.
                let ring = node.frame.insetBy(dx: -3, dy: -3)
                return node.isHittable && viewport.contains(ring)
            }, "Selected branch \(move) must reveal its full ring inside \(viewport); node=\(node.frame)")
            XCTAssertEqual(board.value as? String, expectedBoard,
                           "Revealing the branch must not change the selected position")
        }
        keepScreenshot("ipad-sidebar-analysis-deep-branch-revealed", in: app)
    }

    func testBlankChatSpaceClearsVariationPreviewAndKeepsDraft() throws {
        let app = launchGame(artboard: 14, portrait: true)
        defer { app.terminate() }
        setSidebarCollapsed(true, in: app)
        auditAnalyzing(false, in: app)
        auditChat(true, in: app)
        let board = element(ID.gameBoard, in: app)
        let liveBoardValue = try XCTUnwrap(board.value as? String)
        let input = element(ID.gameChatInput, in: app, matching: .textField)
        input.tap()
        let draft = "Keep this thought after leaving the preview"
        input.typeText(draft)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        tap("game.clock.black", in: app, matching: .button)
        XCTAssertTrue(pollUntil(timeout: 5) { !app.keyboards.firstMatch.exists },
                      "The first clock tap dismisses the composer keyboard")
        XCTAssertFalse(app.staticTexts["Time control"].exists,
                       "The keyboard dismissal tap must not also open clock details")
        XCTAssertEqual(input.value as? String, draft)

        let variationID = ID.gameChatLine("app-store-chat-variation")
        let transcript = element(ID.gameChatLog, in: app, matching: .scrollView)
        let variationRow = element(variationID, in: app, matching: .button)
        let rowCenter = CGVector(dx: 0.5, dy: 0.5)
        // Chat is already open through the native overflow. The generic chat
        // reveal helper would look for its now-overflowed toolbar toggle again.
        XCTAssertTrue(pollUntil(timeout: 5) {
            variationRow.isHittable && hasTappableInteractionPoint(rowCenter,
                variationRow.frame,
                in: transcript.frame.intersection(app.windows.firstMatch.frame))
        }, "The short transcript's variation row must be visible inside Chat")
        activate(variationRow, at: rowCenter)
        XCTAssertTrue(pollUntil(timeout: 5) { board.value as? String == "variation:38:lj-lk-mk" })
        let returnToGame = element("game.chat.preview.return", in: app, matching: .button)
        assertSelected(variationID, in: app)

        // Locate actual empty transcript space: a point that no message
        // bubble, sender name or move header covers. On a short window the
        // rows can fill the viewport, so the gutter beside a bubble is as
        // blank as space above the rows. Clearing selection must come from
        // that background, without touching a row or the outside-chat overlay.
        let viewport = transcript.frame.intersection(app.windows.firstMatch.frame).insetBy(dx: 8, dy: 8)
        let rowIDs = ["app-store-chat-1", "app-store-chat-2", "app-store-chat-variation"]
        let contentIDs = rowIDs.map(ID.gameChatLine) + rowIDs.map(ID.profileChatEntry)
            + [ID.gameChatMove(1), ID.gameChatMove(38)]
        let occupied = contentIDs.flatMap { identifier -> [CGRect] in
            app.descendants(matching: .any).matching(identifier: identifier).allElementsBoundByIndex
                .filter(\.exists).map { $0.frame.insetBy(dx: -8, dy: -8) }
        }
        XCTAssertFalse(occupied.isEmpty, "The transcript rows must be visible")
        let candidates = stride(from: viewport.minY + 22, through: viewport.maxY - 22, by: 12).flatMap { y in
            stride(from: viewport.maxX - 22, through: viewport.minX + 22, by: -12).map { CGPoint(x: $0, y: y) }
        }
        let blankPoint = try XCTUnwrap(candidates.first { point in
            !occupied.contains { $0.contains(point) }
        }, "The transcript must leave a genuinely blank point beside or between its rows")
        XCTAssertTrue(viewport.contains(blankPoint))
        keepScreenshot("ipad-chat-preview-blank-transcript-before-tap", in: app)
        transcript.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: blankPoint.x - transcript.frame.minX,
            dy: blankPoint.y - transcript.frame.minY)).tap()

        XCTAssertTrue(pollUntil(timeout: 5) { board.value as? String == liveBoardValue })
        XCTAssertFalse(returnToGame.exists, "The blank-space tap clears the variation preview")
        assertNotSelected(variationID, in: app)
        XCTAssertFalse(app.keyboards.firstMatch.exists,
                       "Clearing the preview must preserve the dismissed keyboard")
        XCTAssertEqual(input.value as? String, draft, "Clearing the preview retains the chat draft")
        keepScreenshot("ipad-chat-preview-blank-transcript-after-tap", in: app)
    }

    /// iPad Zen keeps only Exit: no sidebar toggle (iPadOS adds one once the
    /// tab bar hides), no Back, no status bar.
    private func assertZenHidesChrome(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element(ID.gameZenExit, in: app, file: file, line: line).isHittable,
                      "Exit Zen stays available", file: file, line: line)
        let toggles = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'"))
            .allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        XCTAssertTrue(toggles.isEmpty, "Zen hides the sidebar toggle; found \(toggles.map(\.frame))",
                      file: file, line: line)
        XCTAssertFalse(app.buttons["BackButton"].firstMatch.isHittable, "Zen hides Back", file: file, line: line)
    }

    func testPortraitZenStatusArtboard() {
        let app = launchGame(artboard: 40, portrait: true)
        setSidebarCollapsed(true, in: app)
        auditChat(false, in: app)
        auditToolbarAction(ID.gameZenEnter, label: "Zen mode", in: app)
        capture(40, "Portrait Zen with status attached to the clock", in: app)
        assertZenHidesChrome(in: app)
        let board = element(ID.gameBoard, in: app).frame
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(board.width, board.height, accuracy: 1)
        XCTAssertEqual(board.midX, window.midX, accuracy: 1)
        XCTAssertGreaterThanOrEqual(board.minY, window.minY)
        XCTAssertLessThanOrEqual(board.maxY, window.maxY)
    }

    func testPortraitArtboards() {
        for number in [5, 14, 26, 40, 63, 71] {
            let app = launchGame(artboard: number, portrait: true)
            setSidebarCollapsed(true, in: app)
            auditChat([14, 71].contains(number), in: app)
            if number == 40 { auditToolbarAction(ID.gameZenEnter, label: "Zen mode", in: app) }
            if number == 63 { clockCapture(number, in: app) }
            else if number == 71 { keyboardCapture(number, in: app) }
            else { capture(number, "Portrait", in: app) }
            app.terminate()
        }
    }

    func testPortraitSidebarOverlayArtboard() {
        let app = launchGame(artboard: 21, portrait: true)
        setSidebarCollapsed(false, in: app)
        capture(21, "Native sidebar over portrait game", in: app)
    }

    func testSpectatorArtboards() {
        for number in [46, 48] {
            let app = launchGame(artboard: number, portrait: number == 48)
            setSidebarCollapsed(true, in: app)
            capture(number, "Spectator", in: app)
            app.terminate()
        }
    }

    func testRengoArtboards() {
        for number in [49, 51] {
            let app = launchGame(artboard: number, portrait: number == 51)
            setSidebarCollapsed(true, in: app)
            capture(number, "Rengo", in: app)
            assertTeamChipNamesFit("artboard \(number)", in: app)
            app.terminate()
        }
        // The live Beta game's names, in both orientations (rule 19: your
        // own team chip never truncates its name beside free width).
        for portrait in [false, true] {
            let app = launchGame(artboard: 3, portrait: portrait, players: "rengo-live")
            setSidebarCollapsed(true, in: app)
            assertTeamChipNamesFit("rengo-live \(portrait ? "portrait" : "landscape")", in: app)
            keepScreenshot("ipad-rengo-own-chip-\(portrait ? "portrait" : "landscape")", in: app)
            app.terminate()
        }
    }

    private func assertTeamChipNamesFit(_ context: String, in app: XCUIApplication,
                                        file: StaticString = #filePath, line: UInt = #line) {
        for side in ["black", "white"] {
            let probe = app.descendants(matching: .any).matching(identifier: "game.identity.nameFit.\(side)").firstMatch
            guard probe.waitForExistence(timeout: 5) else { continue }
            let value = probe.value as? String ?? ""
            print("[RengoNameFit] ipad \(context) \(side) \(value)")
            XCTAssertTrue(value.hasPrefix("full"), "\(context): the \(side) team chip shows its full name (\(value))",
                          file: file, line: line)
        }
    }

    func testLongNamesArtboards() {
        // 53 is the iPhone board, with the opponent as Black. The iPad boards
        // (54 landscape, 55 portrait) show the opponent as White.
        for number in [54, 55] {
            let app = launchGame(artboard: number, portrait: number == 55)
            setSidebarCollapsed(true, in: app)
            capture(number, "Long names", in: app)
            app.terminate()
        }
    }

    func testNarrowNativeWindowArtboard() {
        auditNarrowNativeWindowArtboard()
    }

    func testSurroundStudioThemeNarrowWindow() {
        auditNarrowNativeWindowArtboard(theme: "surroundStudio", suffix: "-surround-studio", appearance: .light)
    }

    func testFeltMeadowThemeNarrowWindow() {
        auditNarrowNativeWindowArtboard(theme: "feltMeadow", suffix: "-felt-meadow", appearance: .light)
    }

    private func auditNarrowNativeWindowArtboard(theme: String? = nil, suffix: String = "",
                                                 appearance: SurroundUITestContract.Appearance? = nil) {
        let app = launchGame(artboard: 84, portrait: true, theme: theme, appearance: appearance)
        setSidebarCollapsed(true, in: app)
        // iPadOS 26 exposes its native resize grabber at the lower-right corner.
        // This is a real windowing gesture, never an injected SwiftUI viewport.
        let window = app.windows.firstMatch
        let before = window.frame
        let grabber = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -3, dy: -3))
        let target = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 375, dy: 548))
        grabber.press(forDuration: 0.8, thenDragTo: target)
        Thread.sleep(forTimeInterval: 1.5)
        // Native floating windows resize about their center, with a short
        // drag activation threshold. Halve each measured size correction so
        // the two moving edges do not overshoot and oscillate around the goal.
        func resizeDelta(_ difference: CGFloat) -> CGFloat {
            guard abs(difference) > 1 else { return 0 }
            return difference / 2 + (difference > 0 ? 8 : -8)
        }
        for _ in 0..<6 {
            let current = window.frame
            guard abs(current.width - 375) > 1 || abs(current.height - 548) > 1 else { break }
            let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
                .withOffset(CGVector(dx: -3, dy: -3))
            corner.press(forDuration: 0.8, thenDragTo: corner.withOffset(
                CGVector(dx: resizeDelta(375 - current.width), dy: resizeDelta(548 - current.height))))
            Thread.sleep(forTimeInterval: 0.8)
        }
        let after = window.frame
        capture(84, "Native iPad minimum window, 375 × 548", in: app,
                note: "Requested native 375 × 548 viewport by resize grabber. Before: \(before); after: \(after).",
                suffix: suffix)
        XCTAssertEqual(after.width, 375, accuracy: 1, "Capture the design's actual native window width")
        XCTAssertEqual(after.height, 548, accuracy: 1, "Capture the design's actual native window height")
    }

    func testAccessibility3Artboards() {
        for number in [59] {
            let app = launchGame(artboard: number, portrait: number == 59, largeText: true)
            setSidebarCollapsed(true, in: app)
            capture(number, "Accessibility 3", in: app)
            // v144: 125 pt cards, 64 pt rows and a 757 pt board; More grows
            // with the large main action.
            let board = element(ID.gameBoard, in: app).frame
            XCTAssertGreaterThanOrEqual(board.width, 750, "AX3 portrait board (design 757); got \(board)")
            let clock = element("game.clock.black", in: app, matching: .button).frame
            XCTAssertLessThanOrEqual(clock.height, 130, "AX3 portrait card (design 125); got \(clock)")
            let more = element(ID.gameActionsMenu, in: app).frame
            XCTAssertGreaterThanOrEqual(more.height, 54, "More grows with the large main action; got \(more)")
            XCTAssertEqual(more.width, more.height, accuracy: 1, "More stays a circle")
            print("[AX3Portrait] board=\(board) clock=\(clock) more=\(more)")
            app.terminate()
        }
    }
}

// Inspect rendered nodes instead of trusting the layout's orientation flag. A
// Book-tall tree can be taller than it is wide and must still flow horizontally.
extension SurroundJourneyUITestCase {
    /// Keep one live fixture through real toolbar toggles so scene movement
    /// remains visible in the captures instead of being hidden by relaunches.
    func auditStudioPanelTransitions(in app: XCUIApplication, capture: (String) -> Void) {
        typealias ID = SurroundUITestContract.AccessibilityID
        let board = element(ID.gameBoard, in: app)
        let value = board.value as? String
        XCTAssertNotNil(value, "The transition audit records an identifiable game position")
        let chat = app.scrollViews[ID.gameChatLog].firstMatch
        let controls = app.descendants(matching: .any)
            .matching(identifier: ID.gameAnalyzeControlBar).firstMatch

        func record(_ step: String, chatVisible: Bool = false, analyzing: Bool = false) {
            XCTAssertTrue(pollUntil(timeout: 10) {
                let window = app.windows.firstMatch.frame
                return chat.exists == chatVisible && controls.exists == analyzing
                    && abs(board.frame.width - board.frame.height) < 1
                    && window.insetBy(dx: -1, dy: -1).contains(board.frame)
            }, "\(step): only the requested panel is visible and the square board fits")
            XCTAssertEqual(board.value as? String, value,
                           "\(step): toggling a panel preserves the displayed position")
            if chatVisible {
                element(ID.gameChatInput, in: app, matching: .textField)
            } else {
                XCTAssertFalse(app.textFields[ID.gameChatInput].exists)
            }
            Thread.sleep(forTimeInterval: 0.7)
            capture(step)
        }

        record("01-play")
        setGameChatVisible(true, in: app)
        dismissSoftwareKeyboardIfNeeded(in: app)
        record("02-chat", chatVisible: true)
        setGameChatVisible(false, in: app)
        record("03-play-after-chat")
        setGameAnalyzing(true, in: app)
        record("04-analyze", analyzing: true)
        setGameAnalyzing(false, in: app)
        record("05-play-after-analyze")
    }

    /// Names survive xcresult attachment export and join to the design matrix.
    /// The host records build/device UUID provenance separately in the run ledger.
    func recordArtboardCapture(_ number: Int, screenshotName: String,
                               in app: XCUIApplication, note: String,
                               physicalPose: String? = nil,
                               file: StaticString = #filePath, line: UInt = #line) {
        func frame(_ rect: CGRect) -> [String: Double] {
            ["x": Double(rect.minX), "y": Double(rect.minY),
             "width": Double(rect.width), "height": Double(rect.height)]
        }
        func describe(_ element: XCUIElement) -> [String: Any] {
            guard element.exists else { return ["exists": false] }
            return ["exists": true, "frame": frame(element.frame),
                    "label": element.label, "value": String(describing: element.value)]
        }
        let legacyStatus = app.descendants(matching: .any)
            .matching(identifier: "game.status").firstMatch
        let snapshot: [String: Any] = [
            "schema_version": 1,
            "artboard": number,
            "source_file": String(format: "%02d.html", number),
            "screenshot_attachment_name": screenshotName,
            "test": name,
            "runtime": UIDevice.current.systemName + " " + UIDevice.current.systemVersion,
            "device_model": UIDevice.current.model,
            "physical_pose": physicalPose.map { $0 as Any } ?? NSNull(),
            "window": frame(app.windows.firstMatch.frame),
            "app_frame": frame(app.frame),
            "black_clock": describe(app.buttons["game.clock.black"].firstMatch),
            "white_clock": describe(app.buttons["game.clock.white"].firstMatch),
            "legacy_status_present": legacyStatus.exists,
            "keyboard": describe(app.keyboards.firstMatch),
            "note": note,
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = screenshotName + "-capture.json"
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            XCTFail("Could not encode artboard capture metadata: \(error)", file: file, line: line)
        }
        XCTAssertFalse(legacyStatus.exists,
                       "Game status belongs to the clock; the retired standalone row must stay absent.",
                       file: file, line: line)
    }

    @discardableResult
    func assertAuditAnalysisTreeAxis(vertical: Bool, in app: XCUIApplication,
                                     file: StaticString = #filePath, line: UInt = #line) -> CGRect {
        let identifier = SurroundUITestContract.AccessibilityID.gameAnalyzeTreeScroll
        let tree = element(identifier, in: app, matching: .scrollView, file: file, line: line)
        let ancestors = app.scrollViews.containing(.scrollView, identifier: identifier)
            .allElementsBoundByIndex
        let viewport = ([app.frame, tree.frame] + ancestors.map { $0.frame })
            .reduce(CGRect.infinite) { $0.intersection($1) }
        XCTAssertFalse(viewport.isEmpty, "The tree has a visible viewport", file: file, line: line)
        var nodes: [(number: Int, frame: CGRect)] = []
        var followsExpectedAxis = false
        for node in app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Move "))
            .allElementsBoundByIndex {
            let label = node.label
            guard let number = Int(label.dropFirst(5)) else { continue }
            let frame = node.frame
            guard frame.width >= 20, frame.height >= 20,
                  viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) else { continue }
            nodes.append((number, frame))
            followsExpectedAxis = nodes.contains { first in
                nodes.contains { second in
                    guard second.number == first.number + 1 else { return false }
                    let dx = second.frame.midX - first.frame.midX
                    let dy = second.frame.midY - first.frame.midY
                    return vertical ? dy > 20 && abs(dx) < 4 : dx > 20 && abs(dy) < 4
                }
            }
            if followsExpectedAxis { break }
        }
        XCTAssertTrue(followsExpectedAxis,
                      "Adjacent visible moves must flow \(vertical ? "vertically" : "horizontally"); nodes=\(nodes)",
                      file: file, line: line)
        return viewport
    }
}
