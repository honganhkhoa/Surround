//
//  ThemePickerUITests.swift
//  SurroundUITests
//
//  The theme pickers in Settings, a game's Options sheet and Home's
//  Appearance popover on the compact iPhone layout, plus the popover's tile
//  geometry on iPad.
//

import XCTest
import UIKit

final class ThemePickerUITests: SurroundJourneyUITestCase {
    private typealias ID = SurroundUITestContract.AccessibilityID

    private func skipUnlessCompactPhone() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Settings opens from the sidebar on Mac.")
        #else
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone,
                      "Settings opens from the avatar menu on the compact iPhone layout.")
        #endif
    }

    private func openSettings(in app: XCUIApplication) {
        tap(ID.accountMenu, in: app, matching: .button)
        tap(requiredMenuButton(ID.accountMenuSettings, title: "Settings", in: app),
            description: "Open Settings", in: app)
        element(ID.screenSettings, in: app)
    }

    private func themeOption(_ theme: String, in app: XCUIApplication) -> XCUIElement {
        revealed(elementAfterScrolling(ID.themeOption(theme), in: app, matching: .button), in: app)
    }

    private func scopeControl(in app: XCUIApplication) -> XCUIElement {
        revealed(elementAfterScrolling(ID.themeScope, in: app, matching: .segmentedControl), in: app)
    }

    /// Scrolls until the element can be tapped. Settings lays out all its
    /// groups at once, so on a small phone they exist below the fold. It
    /// swipes down only toward an element above the view, so it never
    /// dismisses the sheet.
    private func revealed(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        let window = app.windows.firstMatch.frame
        for _ in 0..<6 where !element.isHittable {
            if element.frame.maxY > window.maxY - 40 {
                app.swipeUp()
            } else if element.frame.minY < window.minY + 100 {
                app.swipeDown()
            } else {
                break
            }
        }
        return element
    }

    private func assertSelected(_ option: XCUIElement, _ selected: Bool,
                                file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == %@", NSNumber(value: selected)), object: option
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "\(option.identifier) should\(selected ? "" : " not") be selected", file: file, line: line)
    }

    /// The themes a Debug build offers, in the pickers' order.
    private let debugThemes = ["standard", "surroundStudio", "rakedGarden", "nebulaPearl", "frostPine", "feltMeadow", "nightGarden"]

    /// Every tile's preview keeps the full width of its column, whatever
    /// height the picker's host can give: a host shorter than the picker
    /// scrolls it rather than squeezing some tiles more than others. The
    /// expected side comes from the column pitch (12 pt spacing, 4 pt padding
    /// each side), so a squeeze that hits every tile equally fails too.
    private func assertPreviewTilesKeepTheirColumnWidth(in host: XCUIElement, context: String,
                                                        file: StaticString = #filePath, line: UInt = #line) {
        let previews = debugThemes.map {
            host.descendants(matching: .any).matching(identifier: ID.themePreview($0)).firstMatch
        }
        for (theme, preview) in zip(debugThemes, previews) {
            XCTAssertTrue(preview.waitForExistence(timeout: 10), "\(context): \(theme)'s preview is listed",
                          file: file, line: line)
        }
        let frames = previews.map(\.frame)
        let evidence = XCTAttachment(string: zip(debugThemes, frames).map { "\($0): \($1)" }.joined(separator: "\n"))
        evidence.name = "Theme preview frames – \(context)"
        evidence.lifetime = .keepAlways
        add(evidence)
        guard frames.count > 1, abs(frames[1].minY - frames[0].minY) < 1 else {
            XCTFail("\(context): the first two previews should share a row", file: file, line: line)
            return
        }
        let expected = frames[1].midX - frames[0].midX - 12 - 8
        XCTAssertGreaterThanOrEqual(expected, 44, "\(context): columns stay usable", file: file, line: line)
        for (theme, frame) in zip(debugThemes, frames) {
            XCTAssertEqual(frame.width, frame.height, accuracy: 1, "\(context): \(theme)'s preview is square",
                           file: file, line: line)
            XCTAssertEqual(frame.width, expected, accuracy: 1,
                           "\(context): \(theme)'s preview fills its column", file: file, line: line)
        }
    }

    /// The bar's More button, where it folds trailing items away:
    /// OverflowBarButtonItem on iPadOS 26, TopOverflowBarButtonItem on
    /// iPadOS 27, labelled More everywhere.
    private func moreButton(in app: XCUIApplication) -> XCUIElement {
        app.navigationBars.buttons.matching(NSPredicate(
            format: "identifier ENDSWITH 'OverflowBarButtonItem' OR label == 'More'"
        )).firstMatch
    }

    /// Opens Home's Appearance popover from its bar button and returns it.
    @discardableResult
    private func openHomeAppearance(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        element(ID.screenHome, in: app, file: file, line: line)
        let appearance = app.navigationBars.buttons.matching(identifier: ID.homeAppearance).firstMatch
        XCTAssertTrue(appearance.waitForExistence(timeout: 10), "The bar shows Appearance", file: file, line: line)
        XCTAssertFalse(moreButton(in: app).exists, "The bar has no More menu", file: file, line: line)
        // iPadOS 27 stops reporting the button as one while its popover is
        // open, so measure it first.
        let button = appearance.frame
        tap(appearance, description: "Open Appearance", in: app, file: file, line: line)
        element(ID.homeDisplayMode, in: app, matching: .segmentedControl, file: file, line: line)
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.exists, "Appearance opens as a popover", file: file, line: line)
        assertAppearancePopover(popover.frame, hangsFrom: button, file: file, line: line)
        return popover
    }

    /// The popover hangs from the button: across from it, starting at it or
    /// just below it, never below the large title. iOS 26 and later grow it
    /// from the button, over it and a little above (iPadOS 27), without an
    /// arrow; earlier systems point an arrow at it. A fold into More, which
    /// would open it at the top left, is caught by `openHomeAppearance`'s bar
    /// checks: on a compact phone the popover spans the button from there too.
    private func assertAppearancePopover(_ popover: CGRect, hangsFrom button: CGRect,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let placement = XCTAttachment(string: "Button: \(button)\nPopover: \(popover)")
        placement.name = "Appearance popover placement"
        placement.lifetime = .keepAlways
        add(placement)
        XCTAssertTrue(popover.minX <= button.midX && button.midX <= popover.maxX,
                      "The popover sits across from Appearance", file: file, line: line)
        XCTAssertTrue(((button.minY - 20)...(button.maxY + 12)).contains(popover.minY),
                      "The popover hangs from Appearance (top \(popover.minY), button \(button))",
                      file: file, line: line)
    }

    /// Closes Appearance, visits the fixture game and comes Back, then opens
    /// Appearance again: leaving Home must not change where it opens from.
    @discardableResult
    private func reopenHomeAppearanceAfterAGame(in app: XCUIApplication,
                                                file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        dismissPopover(in: app, file: file, line: line)
        let game = element(ID.homeGame(SurroundUITestContract.fixtureGameID), in: app, matching: .button,
                           file: file, line: line)
        tap(game, description: "Open the fixture game", in: app, file: file, line: line)
        element(ID.gameBoard, in: app, file: file, line: line)
        // The system's Back: identified on recent systems, labelled on older ones.
        let back = app.navigationBars.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "BackButton", "Back"
        )).firstMatch
        tap(back.exists ? back : app.navigationBars.buttons.firstMatch,
            description: "Return to Home", in: app, file: file, line: line)
        return openHomeAppearance(in: app, file: file, line: line)
    }

    func testSettingsChoosesTheThemeAndWhereItApplies() throws {
        try skipUnlessCompactPhone()
        let app = launchApp(orientation: .portrait)
        openSettings(in: app)

        let classic = themeOption("standard", in: app)
        assertSelected(classic, true)
        XCTAssertFalse(scopeControl(in: app).isEnabled,
                       "Classic looks the same everywhere, so where it applies waits for another theme.")
        #if DEBUG
        XCTAssertTrue(themeOption("frostPine", in: app).exists, "Debug builds offer the unreleased themes.")
        XCTAssertTrue(themeOption("feltMeadow", in: app).exists, "Debug builds offer the unreleased themes.")
        XCTAssertTrue(themeOption("nightGarden", in: app).exists, "Debug builds offer the unreleased themes.")
        #endif

        // Settings has one picker; its screen identifier spans several elements.
        assertPreviewTilesKeepTheirColumnWidth(in: app, context: "Settings")

        let garden = themeOption("rakedGarden", in: app)
        tap(garden, description: "Choose Raked Garden", in: app)
        assertSelected(garden, true)
        assertSelected(classic, false)

        let scope = scopeControl(in: app)
        XCTAssertTrue(scope.isEnabled)
        XCTAssertTrue(scope.buttons["Whole app"].isSelected, "Whole app is the default.")
        XCTAssertTrue(app.staticTexts["Home and Settings use it too."].exists)
        keepScreenshot("Settings – Raked Garden on the whole app", in: app)

        tap(scope.buttons["Games only"], description: "Keep the theme to games", in: app)
        XCTAssertTrue(scope.buttons["Games only"].isSelected)
        XCTAssertTrue(app.staticTexts["Only games use it. Home and Settings stay Classic."].waitForExistence(timeout: 5))
        keepScreenshot("Settings – Raked Garden in games only", in: app)

        let nebula = themeOption("nebulaPearl", in: app)
        tap(nebula, description: "Choose Nebula & Pearl", in: app)
        assertSelected(nebula, true)
        XCTAssertEqual(nebula.value as? String, "Always dark")
        XCTAssertTrue(app.staticTexts["Nebula & Pearl is always dark, even in Light Mode."].waitForExistence(timeout: 5))
    }

    func testGameOptionsOffersTheThemes() throws {
        try skipUnlessCompactPhone()
        let app = launchApp(orientation: .portrait)
        let gameID = SurroundUITestContract.fixtureGameID
        tap(ID.homeGamePlayerInfo(gameID), in: app)
        element(ID.gameBoard, in: app)
        tap(ID.gameOptions, in: app)
        element(ID.screenGameOptions, in: app)

        let studio = element(ID.themeOption("surroundStudio"), in: app, matching: .button)
        tap(studio, description: "Choose Surround Studio for games", in: app)
        assertSelected(studio, true)
        assertPreviewTilesKeepTheirColumnWidth(in: app, context: "Game Options")
        XCTAssertFalse(app.segmentedControls[ID.themeScope].exists,
                       "Where the theme applies stays a Settings choice.")
        keepScreenshot("Game Options – Surround Studio chosen", in: app)
    }

    func testHomeAppearanceChoosesLayoutAndTheme() throws {
        try skipUnlessCompactPhone()
        let app = launchApp(orientation: .portrait)
        let board = element(ID.homeGame(SurroundUITestContract.fixtureGameID), in: app, matching: .button)
        XCTAssertEqual(board.frame.width, 120, accuracy: 1, "Compact rows are the phone default.")

        let popover = openHomeAppearance(in: app)
        let mode = element(ID.homeDisplayMode, in: app, matching: .segmentedControl)
        tap(mode.buttons["Large"], description: "Show Large games", in: app)
        XCTAssertTrue(pollUntil(timeout: 5) { board.frame.width >= 266 },
                      "Large tiles keep Home's boards at 266 pt or more.")

        assertPreviewTilesKeepTheirColumnWidth(in: popover, context: "iPhone portrait popover")
        let studio = element(ID.themeOption("surroundStudio"), in: app, matching: .button)
        tap(studio, description: "Choose Surround Studio from Home", in: app)
        assertSelected(studio, true)
        XCTAssertFalse(app.staticTexts["Only games use the theme. Change this in Settings."].exists,
                       "With Whole app, Home restyles and needs no note.")
        keepScreenshot("Home – Appearance popover with Surround Studio", in: app)
        reopenHomeAppearanceAfterAGame(in: app)
        dismissPopover(in: app)

        openSettings(in: app)
        assertSelected(themeOption("surroundStudio", in: app), true)
    }

    func testHomeAppearanceExplainsGamesOnly() throws {
        try skipUnlessCompactPhone()
        let app = launchApp(additionalLaunchArguments: [SurroundUITestContract.themeGamesOnlyLaunchArgument],
                            orientation: .portrait)
        openHomeAppearance(in: app)
        let garden = element(ID.themeOption("rakedGarden"), in: app, matching: .button)
        tap(garden, description: "Choose Raked Garden from Home", in: app)
        assertSelected(garden, true)
        XCTAssertTrue(app.staticTexts["Only games use the theme. Change this in Settings."].waitForExistence(timeout: 5),
                      "With Games only, Home keeps Classic and says why.")
        keepScreenshot("Home – Appearance popover on Games only", in: app)
    }

    /// A short popover, here capped at 360 pt like an iPhone's in landscape,
    /// gives the Debug picker and Games-only note less height than they need,
    /// as reported. It scrolls, and the tiles keep their size.
    func testHomeAppearanceKeepsTileSizeInShortPopover() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("This checks the iPhone popover.")
        #else
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "This checks the iPhone popover.")
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.themeGamesOnlyLaunchArgument,
            SurroundUITestContract.appearancePopoverHeightLaunchArgument, "360",
        ], orientation: .portrait)
        let popover = openHomeAppearance(in: app)
        // The hook took effect: the popover is short, and its options scroll.
        XCTAssertLessThanOrEqual(popover.frame.height, 380, "The hook caps the popover near 360 pt")
        XCTAssertTrue(popover.scrollViews.firstMatch.exists, "Options that do not fit scroll")
        assertPreviewTilesKeepTheirColumnWidth(in: popover, context: "iPhone popover capped at 360 pt")
        keepScreenshot("iPhone Home – Appearance popover capped at 360 pt", in: app)
        #endif
    }

    /// Right to left, the bar puts Appearance on the left, and it opens its
    /// popover there.
    func testHomeAppearancePointsAtItsButtonRightToLeft() throws {
        try skipUnlessCompactPhone()
        let app = launchApp(additionalLaunchArguments: [
            "-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES",
        ], orientation: .portrait)
        let appearance = element(ID.homeAppearance, in: app, matching: .button)
        XCTAssertLessThan(appearance.frame.midX, app.windows.firstMatch.frame.midX,
                          "Right to left, Appearance sits on the left of the bar")
        openHomeAppearance(in: app)
        keepScreenshot("iPhone Home – Appearance popover, right to left", in: app)
    }

    /// At an accessibility text size the picker drops to two wider columns,
    /// and its tiles still fill them.
    func testHomeAppearanceKeepsTileSizeAtLargeTextOnIPhone() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("This checks the iPhone popover.")
        #else
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "This checks the iPhone popover.")
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.themeGamesOnlyLaunchArgument,
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraLarge.rawValue,
        ], orientation: .portrait)
        let popover = openHomeAppearance(in: app)
        assertPreviewTilesKeepTheirColumnWidth(in: popover, context: "iPhone popover, accessibility text")
        keepScreenshot("iPhone Home – Appearance popover, accessibility text", in: app)
        #endif
    }

    /// The iPad popover in both orientations, and at larger text sizes with
    /// fewer columns. Every opening checks that the popover hangs from its
    /// button.
    func testHomeAppearanceTilesKeepTheirSizeOnIPad() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("This checks the iPad popover; Mac shares its layout but not its window.")
        #else
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "This checks the iPad popover.")
        let cases: [(String, UIDeviceOrientation, [String])] = [
            ("landscape, xxxLarge text", .landscapeLeft,
             ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.extraExtraExtraLarge.rawValue]),
            ("landscape, accessibility text", .landscapeLeft,
             ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraLarge.rawValue]),
            ("landscape", .landscapeLeft, []),
            ("portrait", .portrait, []),
        ]
        for (name, orientation, arguments) in cases {
            let app = launchApp(additionalLaunchArguments: [SurroundUITestContract.themeGamesOnlyLaunchArgument] + arguments,
                                orientation: orientation)
            element(ID.screenHome, in: app)
            restoreFullWindow(in: app)
            let popover = openHomeAppearance(in: app)
            assertPreviewTilesKeepTheirColumnWidth(in: popover, context: "iPad \(name) popover")
            keepScreenshot("iPad Home – Appearance popover, \(name)", in: app)
            if name == "landscape" {
                reopenHomeAppearanceAfterAGame(in: app)
            }
            app.terminate()
        }

        // Turning while the app runs keeps the button, and its popover, in
        // place.
        let app = launchApp(additionalLaunchArguments: [SurroundUITestContract.themeGamesOnlyLaunchArgument],
                            orientation: .landscapeLeft)
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        element(ID.screenHome, in: app)
        restoreFullWindow(in: app)
        openHomeAppearance(in: app)
        dismissPopover(in: app)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(pollUntil(timeout: 10) { app.frame.height > app.frame.width }, "Home turns to portrait")
        openHomeAppearance(in: app)
        let compact = element(ID.homeDisplayMode, in: app, matching: .segmentedControl).buttons["Compact"]
        tap(compact, description: "Show Compact games", in: app)
        assertSelected(compact, true)
        keepScreenshot("iPad Home – Appearance popover, landscape then portrait", in: app)
        dismissPopover(in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(pollUntil(timeout: 10) { app.frame.width > app.frame.height }, "Home turns back to landscape")
        let popover = openHomeAppearance(in: app)
        assertSelected(element(ID.homeDisplayMode, in: app, matching: .segmentedControl).buttons["Compact"], true)
        keepScreenshot("iPad Home – Appearance popover, back to landscape", in: app)

        // Turned while open, it stays with the button. iPadOS 27 hides the
        // button while its popover is open, so measure it after closing.
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(pollUntil(timeout: 10) { app.frame.height > app.frame.width }, "Home turns to portrait")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(popover.exists, "The popover stays open through the turn")
        let turned = popover.frame
        keepScreenshot("iPad Home – Appearance popover, turned to portrait while open", in: app)
        dismissPopover(in: app)
        let button = app.navigationBars.buttons.matching(identifier: ID.homeAppearance).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "The bar still shows Appearance after the turn")
        assertAppearancePopover(turned, hangsFrom: button.frame)
        #endif
    }

    /// Home's bar holds only the account menu and Appearance, so it never
    /// folds Appearance into a More menu and Appearance can open its popover
    /// from the button itself. Checked at the largest text size, right to
    /// left, scrolled (the inline title then shares the bar), and on iPad in
    /// both orientations and in the system's narrowest window.
    func testHomeBarNeverFoldsAppearance() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("The Mac bar does not fold items into a More menu this way.")
        #else
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let largest = ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        let rightToLeft = ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"]
        var cases: [(String, UIDeviceOrientation, [String])] = [
            ("portrait", .portrait, []),
            ("portrait, largest text", .portrait, largest),
            ("portrait, largest text, right to left", .portrait, largest + rightToLeft),
        ]
        if isPad {
            cases += [
                ("landscape", .landscapeLeft, []),
                ("landscape, largest text", .landscapeLeft, largest),
            ]
        }
        for (name, orientation, arguments) in cases {
            let app = launchApp(additionalLaunchArguments: arguments, orientation: orientation)
            element(ID.screenHome, in: app)
            if isPad { restoreFullWindow(in: app) }
            assertBarShowsAppearance(in: app, context: name)
            app.terminate()
        }
        // iPadOS 26 resizes app windows; earlier systems keep them full size.
        if isPad, #available(iOS 26.0, *) {
            for (name, arguments) in [("narrowest window", [String]()), ("narrowest window, largest text", largest)] {
                let app = launchApp(additionalLaunchArguments: arguments, orientation: .portrait)
                element(ID.screenHome, in: app)
                // A failure must not leave the window narrow for later runs; a
                // passing case restores it and quits first.
                addTeardownBlock { [weak self] in
                    if app.state == .runningForeground { self?.restoreFullWindow(in: app) }
                }
                let window = resizeWindow(to: CGSize(width: 375, height: 548), in: app)
                XCTAssertEqual(window.width, 375, accuracy: 1, "The native window reaches its minimum width")
                assertBarShowsAppearance(in: app, context: name)
                restoreFullWindow(in: app)
                app.terminate()
            }
        }
        #endif
    }

    /// Appearance is a button laid out in the bar, and the bar has no More
    /// menu, at the top of Home and, where Home has more than fits, scrolled
    /// down. (The fixture's live-game banner can cover the bar at the largest
    /// text sizes, so the button need not be hittable.)
    private func assertBarShowsAppearance(in app: XCUIApplication, context: String,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let bar = app.navigationBars.firstMatch
        let appearance = bar.buttons.matching(identifier: ID.homeAppearance).firstMatch
        for position in ["top", "scrolled"] {
            if position == "scrolled", !scrollHomeDown(in: app, file: file, line: line) {
                // Home fits: its large title never gives way to the inline one.
                continue
            }
            XCTAssertTrue(appearance.waitForExistence(timeout: 10), "\(context), \(position): the bar shows Appearance",
                          file: file, line: line)
            let frame = appearance.frame
            XCTAssertTrue(!frame.isEmpty && bar.frame.contains(CGPoint(x: frame.midX, y: frame.midY)),
                          "\(context), \(position): Appearance is laid out in the bar (\(frame) in \(bar.frame))",
                          file: file, line: line)
            XCTAssertFalse(moreButton(in: app).exists,
                           "\(context), \(position): the bar has no More menu", file: file, line: line)
            keepScreenshot("Home bar – \(context), \(position)", in: app)
        }
    }

    /// Scrolls Home down by dragging inside its content: below the live-game
    /// banner, which can cover most of a small window at large text sizes
    /// (and opens the game when touched), and clear of a bottom tab bar and
    /// of the window's bottom edge, where a drag goes to the Home Screen.
    /// Returns whether Home moved; when it all fits there is nothing to scroll.
    private func scrollHomeDown(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let window = app.windows.firstMatch
        let frame = window.frame
        let home = app.scrollViews.matching(identifier: ID.screenHome).firstMatch.frame
        let banner = app.buttons.matching(identifier: ID.liveGameBanner).firstMatch
        // A tab bar counts only at the bottom: iPad floats its tab bar at the top.
        let tabBar = app.tabBars.firstMatch
        let tabBarTop = tabBar.exists && tabBar.frame.minY > frame.midY ? tabBar.frame.minY : frame.maxY - 60
        let top = max(home.minY, banner.exists ? banner.frame.maxY : home.minY) + 12
        let bottom = min(home.maxY, tabBarTop) - 12
        guard bottom - top > 40 else { return false }
        let newGame = app.descendants(matching: .any).matching(identifier: ID.homeNewGame).firstMatch
        let before = newGame.frame.minY
        // Offsets from the window's origin: a floating window is not at the screen's.
        let origin = window.coordinate(withNormalizedOffset: .zero)
        let x = home.midX - frame.minX
        origin.withOffset(CGVector(dx: x, dy: bottom - frame.minY))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: x, dy: top - frame.minY)),
                   withVelocity: .fast, thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(app.state, .runningForeground, "Scrolling Home keeps Surround in front", file: file, line: line)
        return newGame.frame.minY < before - 1
    }

    /// Resizes the real iPad window with its native grabber, as the
    /// narrow-window artboard audit does: never an injected viewport.
    private func resizeWindow(to size: CGSize, in app: XCUIApplication) -> CGRect {
        let window = app.windows.firstMatch
        let grabber = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -3, dy: -3))
        grabber.press(forDuration: 0.8, thenDragTo: window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: size.width, dy: size.height)))
        Thread.sleep(forTimeInterval: 1.5)
        // Floating windows resize about their center: halve each correction.
        func delta(_ difference: CGFloat) -> CGFloat {
            abs(difference) > 1 ? difference / 2 + (difference > 0 ? 8 : -8) : 0
        }
        for _ in 0..<6 {
            let current = window.frame
            guard abs(current.width - size.width) > 1 || abs(current.height - size.height) > 1 else { break }
            let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
                .withOffset(CGVector(dx: -3, dy: -3))
            corner.press(forDuration: 0.8, thenDragTo: corner.withOffset(
                CGVector(dx: delta(size.width - current.width), dy: delta(size.height - current.height))))
            Thread.sleep(forTimeInterval: 0.8)
        }
        return window.frame
    }

    /// iPadOS remembers a resized window across launches. Each case needs the
    /// full screen, so restore it with the system's double tap on the window's
    /// top edge, away from Home's live-game banner at the top center.
    private func restoreFullWindow(in app: XCUIApplication) {
        let window = app.windows.firstMatch
        func isFull() -> Bool {
            let frame = window.frame
            return frame.minX <= 4 && frame.minY <= 40 && min(frame.width, frame.height) >= 700
        }
        guard window.exists, !isFull() else { return }
        for x in [0.75, 0.25] where !isFull() {
            window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0))
                .withOffset(CGVector(dx: 0, dy: 6)).doubleTap()
            _ = pollUntil(timeout: 5) { isFull() }
        }
        // iPadOS 27 ignores the double tap in a small window: open the
        // window's controls at its top left, then take the green full-screen
        // one beside them.
        if !isFull() {
            let origin = window.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: 42, dy: 31)).tap()
            Thread.sleep(forTimeInterval: 1)
            origin.withOffset(CGVector(dx: 92, dy: 31)).tap()
            _ = pollUntil(timeout: 5) { isFull() }
        }
        XCTAssertTrue(isFull(), "Expected the full-size iPad window; got \(window.frame)")
    }
}
