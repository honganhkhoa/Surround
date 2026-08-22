//
//  AppStoreScreenshotTests.swift
//  SurroundUITests
//
//  Deterministic, localized captures matching the current App Store listing.
//

import XCTest
import UIKit

final class AppStoreScreenshotTests: SurroundUITestCase {
    private enum InterfaceStyle {
        case light
        case dark
    }

    private var capturedSceneNames = [String]()
    private var appStoreWidgetProofToken = ""

    private let expectedPhoneSceneNames = [
        "01-game-board",
        "02-active-games",
        "03-game-chat",
        "04-open-challenges",
        "05-game-analysis",
        "06-zen-mode",
        "07-preferred-settings",
        "08-public-games",
        "09-game-board-dark",
        "10-home-screen-widget",
    ]

    private let expectedPadSceneNames = [
        "01-game-board",
        "02-active-games",
        "03-game-analysis",
        "04-zen-mode",
        "05-game-board-dark",
        "06-public-games",
        "07-quick-match",
        "08-open-challenges",
        "09-preferred-settings",
        "10-home-screen-widget",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        capturedSceneNames = []
        appStoreWidgetProofToken = UUID().uuidString
    }

    func testAppStoreScreenshots() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(
            "App Store screenshot capture requires an iOS Simulator because it drives SpringBoard and the Home Screen widget."
        )
        #else
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone

        let gameApp = launchApp()
        openFixtureGame(in: gameApp)
        capture("01-game-board", in: gameApp)

        if isPhone {
            selectSegment(
                at: 2,
                in: SurroundUITestContract.AccessibilityID.gameDisplayModePicker,
                app: gameApp
            )
            dismissCompactChatInputAndWaitForLayout(in: gameApp)
            capture("03-game-chat", in: gameApp)

            selectSegment(
                at: 0,
                in: SurroundUITestContract.AccessibilityID.gameDisplayModePicker,
                app: gameApp
            )
            selectScreenshotAnalysisVariation(in: gameApp)
            capture("05-game-analysis", in: gameApp)

            selectSegment(
                at: 1,
                in: SurroundUITestContract.AccessibilityID.gameDisplayModePicker,
                app: gameApp
            )
        } else {
            tap(
                SurroundUITestContract.AccessibilityID.gameAnalyzeToggle,
                in: gameApp
            )
            selectScreenshotAnalysisVariation(in: gameApp)
            capture("03-game-analysis", in: gameApp)
            tap(
                SurroundUITestContract.AccessibilityID.gameAnalyzeToggle,
                in: gameApp
            )
        }

        tap(
            SurroundUITestContract.AccessibilityID.gameZenEnter,
            in: gameApp,
            matching: .button
        )
        element(
            SurroundUITestContract.AccessibilityID.gameZenExit,
            in: gameApp,
            matching: .button
        )
        if !isPhone {
            setSidebarCollapsed(true, in: gameApp)
        }
        capture(isPhone ? "06-zen-mode" : "04-zen-mode", in: gameApp)
        tap(
            SurroundUITestContract.AccessibilityID.gameZenExit,
            in: gameApp,
            matching: .button
        )
        if !isPhone {
            // Zen mode hides the navigation toolbar that owns the collapsed
            // sidebar's reveal control. Exit Zen first, then restore the
            // sidebar so its state cannot leak into later app launches.
            let zenEnter = element(
                SurroundUITestContract.AccessibilityID.gameZenEnter,
                in: gameApp,
                matching: .button
            )
            XCTAssertTrue(
                waitUntil(timeout: 10) { zenEnter.isHittable },
                "Expected the game toolbar after exiting Zen mode."
            )
            setSidebarCollapsed(false, in: gameApp)
        }

        if isPhone {
            gameApp.terminate()

            let darkGameApp = launchApp(interfaceStyle: .dark)
            openFixtureGame(in: darkGameApp)
            // Force one compact-mode layout transition after the dark
            // appearance is applied. Without it, SwiftUI can briefly retain a
            // zero-height board geometry from the launch-time color-scheme
            // transition even though the board accessibility element exists.
            selectSegment(
                at: 2,
                in: SurroundUITestContract.AccessibilityID.gameDisplayModePicker,
                app: darkGameApp
            )
            selectSegment(
                at: 1,
                in: SurroundUITestContract.AccessibilityID.gameDisplayModePicker,
                app: darkGameApp
            )
            capture("09-game-board-dark", in: darkGameApp)
            darkGameApp.terminate()
        } else {
            gameApp.terminate()

            let darkGameApp = launchApp(interfaceStyle: .dark)
            openFixtureGame(in: darkGameApp)
            capture("05-game-board-dark", in: darkGameApp)
            darkGameApp.terminate()
        }

        let homeApp = launchApp()
        waitForHomeGames(in: homeApp)
        capture("02-active-games", in: homeApp)
        tap(
            SurroundUITestContract.AccessibilityID.homePreferredSettings,
            in: homeApp
        )
        element(
            SurroundUITestContract.AccessibilityID.screenPreferredSettings,
            in: homeApp
        )
        for settingIndex in 0..<2 {
            element(
                SurroundUITestContract.AccessibilityID.preferredSetting(
                    settingIndex
                ),
                in: homeApp
            )
        }
        capture(
            isPhone ? "07-preferred-settings" : "09-preferred-settings",
            in: homeApp
        )
        homeApp.terminate()

        let newGameApp = launchApp()
        tap(
            SurroundUITestContract.AccessibilityID.homeNewGame,
            in: newGameApp
        )
        element(
            SurroundUITestContract.AccessibilityID.screenNewGame,
            in: newGameApp
        )
        element(
            SurroundUITestContract.AccessibilityID.screenOpenChallenges,
            in: newGameApp
        )
        capture(
            isPhone ? "04-open-challenges" : "08-open-challenges",
            in: newGameApp
        )

        if !isPhone {
            selectSegment(
                at: 0,
                in: SurroundUITestContract.AccessibilityID.newGameOptionPicker,
                app: newGameApp
            )
            element(
                SurroundUITestContract.AccessibilityID.screenQuickMatch,
                in: newGameApp
            )
            capture("07-quick-match", in: newGameApp)
        }
        newGameApp.terminate()

        let publicGamesApp = launchApp()
        openPublicGames(in: publicGamesApp)
        element(
            SurroundUITestContract.AccessibilityID.screenPublicGames,
            in: publicGamesApp
        )
        element(
            SurroundUITestContract.AccessibilityID.publicGame(
                SurroundUITestContract.screenshotPublicGameID
            ),
            in: publicGamesApp
        )
        capture(isPhone ? "08-public-games" : "06-public-games", in: publicGamesApp)
        publicGamesApp.terminate()

        captureHomeScreenWidget()

        XCTAssertEqual(
            capturedSceneNames.sorted(),
            isPhone ? expectedPhoneSceneNames : expectedPadSceneNames,
            "The screenshot journey must capture exactly ten ordered App Store scenes."
        )
        #endif
    }

    private func launchApp(interfaceStyle: InterfaceStyle = .light) -> XCUIApplication {
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .phone
            ? .portrait
            // XCUIScreen stores iPad landscape captures on a portrait pixel
            // canvas and describes the display orientation in image metadata.
            // The capture runner bakes that metadata into landscape pixels.
            : .landscapeRight
        #endif

        let app = XCUIApplication()
        app.launchArguments = [
            SurroundUITestContract.launchArgument,
            SurroundUITestContract.screenshotLaunchArgument,
            SurroundUITestContract
                .appStoreScreenshotWidgetProofTokenLaunchArgument,
            appStoreWidgetProofToken,
        ]
        if interfaceStyle == .dark {
            app.launchArguments.append(
                SurroundUITestContract.screenshotDarkModeLaunchArgument
            )
        }
        app.launch()
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        if UIDevice.current.userInterfaceIdiom == .pad {
            setSidebarCollapsed(false, in: app)
            XCTAssertTrue(
                sidebarSettingsTab(in: app).isHittable,
                "Expected every iPad app journey to start with the sidebar visible."
            )
        }
        return app
    }

    private func selectScreenshotAnalysisVariation(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let identifier =
            SurroundUITestContract.AccessibilityID.gameAnalysisPosition(
                baseMoveNumber:
                    SurroundUITestContract.screenshotAnalysisBaseMoveNumber,
                movePath:
                    SurroundUITestContract.screenshotAnalysisSelectedMovePath
            )
        tap(identifier, in: app, file: file, line: line)

        let selectedPosition = element(
            identifier,
            in: app,
            file: file,
            line: line
        )
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"),
            object: selectedPosition
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [selected], timeout: 10),
            .completed,
            "Expected the screenshot analysis variation to be selected",
            file: file,
            line: line
        )
    }

    private func openFixtureGame(in app: XCUIApplication) {
        tap(
            SurroundUITestContract.AccessibilityID.homeGame(
                SurroundUITestContract.screenshotPrimaryGameID
            ),
            in: app
        )
        element(
            SurroundUITestContract.AccessibilityID.gameDetail(
                SurroundUITestContract.screenshotPrimaryGameID
            ),
            in: app
        )
        element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
    }

    private func openPublicGames(in app: XCUIApplication) {
        if UIDevice.current.userInterfaceIdiom == .phone {
            // SwiftUI's Tab identifier is not consistently forwarded to the
            // underlying iPhone UITabBarButton after repeated relaunches.
            // Public Games is the second fixed tab in the screenshot fixture.
            let publicGamesTab = app.tabBars.buttons.element(boundBy: 1)
            XCTAssertTrue(
                publicGamesTab.waitForExistence(timeout: 10),
                "Expected the Public Games tab."
            )
            publicGamesTab.tap()
        } else {
            tap(
                SurroundUITestContract.AccessibilityID.navigationPublicGames,
                in: app
            )
        }
    }

    private func setSidebarCollapsed(
        _ collapsed: Bool,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sidebarProbe = sidebarSettingsTab(in: app)
        let shouldToggle = collapsed
            ? sidebarProbe.isHittable
            : !sidebarProbe.isHittable
        guard shouldToggle else {
            return
        }

        let appWindow = app.windows.firstMatch
        XCTAssertTrue(
            appWindow.waitForExistence(timeout: 10),
            "Expected an application window before changing the sidebar.",
            file: file,
            line: line
        )
        let windowFrame = appWindow.frame
        let navigationIdentifiers = Set([
            SurroundUITestContract.AccessibilityID.navigationHome,
            SurroundUITestContract.AccessibilityID.navigationPublicGames,
            SurroundUITestContract.AccessibilityID.navigationSettings,
            SurroundUITestContract.AccessibilityID.navigationAbout,
            SurroundUITestContract.AccessibilityID.navigationBrowser,
        ])
        var sidebarToggle: XCUIElement?
        let foundSidebarToggle = waitUntil(timeout: 10) {
            sidebarToggle = app.buttons.allElementsBoundByIndex
                .filter {
                    let frame = $0.frame
                    return $0.exists
                        && $0.isHittable
                        && !navigationIdentifiers.contains($0.identifier)
                        && frame.width > 1
                        && frame.height > 1
                        && frame.width < 80
                        && frame.height < 80
                        && frame.midX > windowFrame.minX + 100
                        && frame.midX < windowFrame.midX
                        && frame.maxY < windowFrame.minY + 100
                }
                .min { $0.frame.midX < $1.frame.midX }
            return sidebarToggle != nil
        }

        guard foundSidebarToggle, let sidebarToggle else {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Accessibility hierarchy – sidebar toggle missing"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            XCTFail(
                "Expected the iPad sidebar toggle in the top-leading toolbar.",
                file: file,
                line: line
            )
            return
        }

        sidebarToggle.tap()
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                collapsed
                    ? !sidebarProbe.isHittable
                    : sidebarProbe.exists && sidebarProbe.isHittable
            },
            collapsed
                ? "Expected the iPad sidebar to collapse."
                : "Expected the iPad sidebar to expand.",
            file: file,
            line: line
        )
    }

    private func sidebarSettingsTab(in app: XCUIApplication) -> XCUIElement {
        app
            .descendants(matching: .any)
            .matching(
                identifier:
                    SurroundUITestContract.AccessibilityID.navigationSettings
            )
            .firstMatch
    }

    private func waitForHomeGames(in app: XCUIApplication) {
        for gameID in SurroundUITestContract.screenshotFixtureGameIDs {
            element(
                SurroundUITestContract.AccessibilityID.homeGame(gameID),
                in: app
            )
        }

        let finalHistoryID = SurroundUITestContract.screenshotHistoryGameIDs.last!
        let finalHistoryGame = app
            .descendants(matching: .any)
            .matching(
                identifier: SurroundUITestContract.AccessibilityID.homeHistoryGame(
                    finalHistoryID
                )
            )
            .firstMatch
        for _ in 0..<12 where !finalHistoryGame.isHittable {
            app.swipeUp(velocity: .slow)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
        }
        XCTAssertTrue(
            finalHistoryGame.isHittable,
            "Expected all screenshot history rows to be reachable."
        )

        // Prove the complete lazy history grid was populated, then return to
        // the top so 02-active-games keeps the active sections and the first
        // history rows in the curated composition.
        let topAnchor = app
            .descendants(matching: .any)
            .matching(
                identifier: SurroundUITestContract.AccessibilityID.homeNewGame
            )
            .firstMatch
        for _ in 0..<12 where !topAnchor.isHittable {
            app.swipeDown(velocity: .slow)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
        }
        XCTAssertTrue(topAnchor.isHittable, "Expected to return to the top of the home screen.")
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let appWindow = app.windows.firstMatch
        XCTAssertTrue(
            appWindow.waitForExistence(timeout: 10),
            "Expected an application window before capturing \(name)."
        )
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertGreaterThan(
                appWindow.frame.height,
                appWindow.frame.width,
                "The iPhone app content must be portrait for \(name)."
            )
        } else {
            XCTAssertGreaterThan(
                appWindow.frame.width,
                appWindow.frame.height,
                "The iPad app content must be landscape for \(name)."
            )
        }

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.75))

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot, quality: .original)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        capturedSceneNames.append(name)
    }

    private func captureHomeScreenWidget() {
        let sceneName = "10-home-screen-widget"
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .phone
            ? .portrait
            : .landscapeRight
        #endif
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.press(.home)
        #endif

        let springboard = XCUIApplication(
            bundleIdentifier: "com.apple.springboard"
        )
        XCTAssertTrue(
            springboard.wait(for: .runningForeground, timeout: 10),
            "Expected SpringBoard before capturing \(sceneName)."
        )
        for _ in 0..<3 where homeScreenPage(in: springboard) == nil {
            #if !targetEnvironment(macCatalyst)
            XCUIDevice.shared.press(.home)
            #endif
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.75))
        }

        let expectedLandscape = UIDevice.current.userInterfaceIdiom != .phone
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                let frame = springboard.windows.firstMatch.frame
                return expectedLandscape
                    ? frame.width > frame.height
                    : frame.height > frame.width
            },
            "Expected SpringBoard to settle into the screenshot orientation."
        )

        let homeScreenIcons = springboard
            .otherElements["Home screen icons"]
            .firstMatch
        guard homeScreenIcons.waitForExistence(timeout: 10) else {
            keepSpringBoardDiagnostics(
                springboard,
                name: "Home Screen icon grid missing"
            )
            XCTFail("Expected the Home Screen icon grid.")
            return
        }

        guard navigateToSurroundHomeScreenPage(
            in: springboard,
            homeScreenIcons: homeScreenIcons
        ) else {
            keepSpringBoardDiagnostics(
                springboard,
                name: "Surround Home Screen page missing"
            )
            XCTFail("Expected to find the Surround app on a Home Screen page.")
            return
        }

        guard isolateSurroundHomeScreenPage(
            in: springboard,
            homeScreenIcons: homeScreenIcons
        ) else {
            keepSpringBoardDiagnostics(
                springboard,
                name: "Surround Home Screen page was not isolated"
            )
            XCTFail("Expected a Home Screen page containing only Surround.")
            return
        }

        if !isScreenshotWidgetVisible(in: springboard) {
            addScreenshotWidget(
                to: springboard,
                homeScreenIcons: homeScreenIcons
            )
        }
        finishEditingHomeScreen(in: springboard)

        let widgetAppeared = waitUntil(timeout: 20) {
            self.isScreenshotWidgetVisible(in: springboard)
        }
        if !widgetAppeared {
            keepSpringBoardDiagnostics(
                springboard,
                name: "Widget missing after placement"
            )
        }
        guard widgetAppeared else {
            XCTFail("Expected the Surround widget to render its screenshot fixture.")
            return
        }
        assertFreshAppStoreWidgetFixture(in: springboard)

        let unwantedContent = visibleHomeScreenContent(
            in: springboard,
            homeScreenIcons: homeScreenIcons
        )
        .filter { $0.identifier != "Surround" }
        if !unwantedContent.isEmpty {
            keepSpringBoardDiagnostics(
                springboard,
                name: "Unexpected content on Surround Home Screen page"
            )
        }
        XCTAssertTrue(
            unwantedContent.isEmpty,
            "Expected no other apps or widgets on the Surround Home Screen page."
        )

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.5))

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(
            screenshot: screenshot,
            quality: .original
        )
        attachment.name = sceneName
        attachment.lifetime = .keepAlways
        add(attachment)
        capturedSceneNames.append(sceneName)
    }

    private func assertFreshAppStoreWidgetFixture(
        in springboard: XCUIApplication
    ) {
        let identifierPrefix = [
            "surround.appstore.widget.ready",
            "medium",
            "games-\(SurroundUITestContract.appStoreScreenshotWidgetGameCount)",
            "displaying-2",
            "rendering-fullColor",
            "token-\(appStoreWidgetProofToken)",
            "locale-",
        ].joined(separator: ".")
        let readyContent = springboard
            .descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    identifierPrefix
                )
            )
            .firstMatch

        guard readyContent.waitForExistence(timeout: 30) else {
            let unreadyContent = springboard
                .descendants(matching: .any)
                .matching(
                    NSPredicate(
                        format: "identifier BEGINSWITH %@",
                        "surround.appstore.widget.unready.medium."
                    )
                )
                .firstMatch
            keepSpringBoardDiagnostics(
                springboard,
                name: "App Store widget fixture was not ready"
            )
            let unreadyDetail = unreadyContent.exists
                ? " Widget reported '\(unreadyContent.identifier)'."
                : ""
            XCTFail(
                "Expected fresh, localized App Store screenshot content in "
                    + "the medium widget."
                    + unreadyDetail
            )
            return
        }

        let identifierSuffix = String(
            readyContent.identifier.dropFirst(identifierPrefix.count)
        )
        guard let expiryMarker = identifierSuffix.range(
            of: ".expires-",
            options: .backwards
        ) else {
            XCTFail("The App Store widget readiness identifier had no expiry.")
            return
        }
        let localeIdentifier = String(
            identifierSuffix[..<expiryMarker.lowerBound]
        )
        let expiryText = String(
            identifierSuffix[expiryMarker.upperBound...]
        )
        guard !localeIdentifier.isEmpty,
              let expiry = TimeInterval(expiryText) else {
            XCTFail(
                "The App Store widget readiness identifier had invalid locale or expiry metadata."
            )
            return
        }
        XCTAssertGreaterThan(
            Date(timeIntervalSince1970: expiry),
            Date().addingTimeInterval(5 * 60 * 60),
            "The App Store widget fixture must come from this capture run, not a stale timeline."
        )
    }

    private func isScreenshotWidgetVisible(
        in springboard: XCUIApplication
    ) -> Bool {
        springboard
            .icons
            .matching(identifier: "Surround")
            .allElementsBoundByIndex
            .contains {
                isVisibleOnScreen($0, in: springboard)
                    && ($0.frame.width >= 160 || $0.frame.height >= 160)
            }
    }

    private struct HomeScreenPage: Equatable {
        let current: Int
        let total: Int
    }

    private func navigateToSurroundHomeScreenPage(
        in springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) -> Bool {
        guard let initialPage = homeScreenPage(in: springboard) else {
            return false
        }
        if initialPage.current != 1,
           !navigate(
               from: initialPage,
               to: 1,
               in: springboard
           ) {
            return false
        }

        for _ in 0..<12 {
            if visibleSurroundAppIcon(
                in: springboard,
                homeScreenIcons: homeScreenIcons
            ) != nil {
                return true
            }

            guard let page = homeScreenPage(in: springboard),
                  page.current < page.total else {
                return false
            }
            guard navigate(
                from: page,
                to: page.current + 1,
                in: springboard
            ) else {
                return false
            }
        }
        return false
    }

    private func isolateSurroundHomeScreenPage(
        in springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) -> Bool {
        guard homeScreenPage(in: springboard) != nil else {
            return false
        }
        if UIDevice.current.userInterfaceIdiom == .phone {
            let visibleContent = visibleHomeScreenContent(
                in: springboard,
                homeScreenIcons: homeScreenIcons
            )
            return !visibleContent.isEmpty
                && visibleContent.allSatisfy { $0.identifier == "Surround" }
                && visibleSurroundAppIcon(
                    in: springboard,
                    homeScreenIcons: homeScreenIcons
                ) != nil
        }
        return isolateSurroundHomeScreenPageOnPad(
            in: springboard,
            homeScreenIcons: homeScreenIcons
        )
    }

    private func isolateSurroundHomeScreenPageOnPad(
        in springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) -> Bool {
        let unwantedIcons = visibleHomeScreenIcons(
            in: springboard,
            homeScreenIcons: homeScreenIcons
        )
        .filter { $0.identifier != "Surround" }
        if unwantedIcons.isEmpty {
            return visibleSurroundAppIcon(
                in: springboard,
                homeScreenIcons: homeScreenIcons
            ) != nil
        }

        guard enterHomeScreenEditMode(
            in: springboard,
            homeScreenIcons: homeScreenIcons
        ) else {
            return false
        }

        for _ in 0..<12 {
            guard let startingPage = homeScreenPage(in: springboard),
                  let surroundIcon = visibleSurroundAppIcon(
                      in: springboard,
                      homeScreenIcons: homeScreenIcons
                  ),
                  isHomeScreenEditing(in: springboard) else {
                return false
            }

            let window = springboard.windows.firstMatch
            let windowFrame = window.frame
            let iconCenterY = surroundIcon.frame.midY
            let destinationY = min(
                max(
                    iconCenterY,
                    windowFrame.minY + (windowFrame.height * 0.22)
                ),
                windowFrame.minY + (windowFrame.height * 0.68)
            )
            let normalizedY = (destinationY - windowFrame.minY)
                / windowFrame.height
            let source = surroundIcon.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)
            )
            let rightEdge = window.coordinate(
                withNormalizedOffset: CGVector(dx: 0.98, dy: normalizedY)
            )
            source.press(
                forDuration: 0.12,
                thenDragTo: rightEdge,
                withVelocity: .slow,
                thenHoldForDuration: 0.7
            )

            guard waitUntil(timeout: 8, condition: {
                guard let updatedPage = self.homeScreenPage(
                    in: springboard
                ) else {
                    return false
                }
                return updatedPage.current != startingPage.current
                    && self.visibleSurroundAppIcon(
                        in: springboard,
                        homeScreenIcons: homeScreenIcons
                    ) != nil
            }) else {
                return false
            }

            let visibleIcons = visibleHomeScreenIcons(
                in: springboard,
                homeScreenIcons: homeScreenIcons
            )
            if visibleIcons.count == 1,
               visibleIcons.first?.identifier == "Surround" {
                return true
            }
        }
        return false
    }

    private func enterHomeScreenEditMode(
        in springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) -> Bool {
        if isHomeScreenEditing(in: springboard) {
            return true
        }
        if UIDevice.current.userInterfaceIdiom != .phone {
            homeScreenIcons.coordinate(
                withNormalizedOffset: CGVector(dx: 0.72, dy: 0.72)
            )
            .press(forDuration: 1.5)
            return waitUntil(timeout: 5) {
                self.isHomeScreenEditing(in: springboard)
            }
        }

        guard let surroundIcon = visibleSurroundAppIcon(
            in: springboard,
            homeScreenIcons: homeScreenIcons
        ) else {
            return false
        }

        surroundIcon.press(forDuration: 0.8)
        guard let editHomeScreen = waitForFirstHittable(
            [
                springboard.buttons["Edit Home Screen"],
                springboard.menuItems["Edit Home Screen"],
            ],
            timeout: 5
        ) else {
            return false
        }
        editHomeScreen.tap()
        return waitUntil(timeout: 5) {
            self.isHomeScreenEditing(in: springboard)
        }
    }

    private func isHomeScreenEditing(
        in springboard: XCUIApplication
    ) -> Bool {
        let doneButton = springboard.buttons["Done"]
        return doneButton.exists && doneButton.isHittable
    }

    private func addScreenshotWidget(
        to springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) {
        if !isHomeScreenEditing(in: springboard) {
            guard enterHomeScreenEditMode(
                in: springboard,
                homeScreenIcons: homeScreenIcons
            ) else {
                keepSpringBoardDiagnostics(
                    springboard,
                    name: "Edit Home Screen action missing"
                )
                XCTFail("Expected the Edit Home Screen action.")
                return
            }
        }

        guard openWidgetGallery(
            in: springboard
        ) else {
            return
        }

        guard let searchField = waitForFirstHittable(
            [
                springboard.searchFields["Search Widgets"],
                springboard.searchFields
                    .matching(
                        NSPredicate(
                            format: "placeholderValue CONTAINS[c] %@",
                            "Widgets"
                        )
                    )
                    .firstMatch,
            ],
            timeout: 10
        ) else {
            keepSpringBoardDiagnostics(
                springboard,
                name: "Widget search missing"
            )
            XCTFail("Expected the widget gallery search field.")
            return
        }
        searchField.tap()
        searchField.typeText("Surround")

        guard let surroundResult = waitForFirstHittable(
            [
                springboard.cells["Surround"],
                springboard.buttons["Surround"],
                springboard.staticTexts["Surround"],
            ],
            timeout: 10
        ) else {
            keepSpringBoardDiagnostics(
                springboard,
                name: "Surround widget result missing"
            )
            XCTFail("Expected Surround in the widget gallery.")
            return
        }
        surroundResult.tap()

        guard let addSelectedWidget = waitForFirstHittable(
            [
                springboard.buttons
                    .matching(
                        NSPredicate(
                            format: "label CONTAINS[c] %@",
                            "Add Widget"
                        )
                    )
                    .firstMatch,
            ],
            timeout: 10
        ) else {
            keepSpringBoardDiagnostics(
                springboard,
                name: "Widget size picker missing"
            )
            XCTFail("Expected the widget size picker.")
            return
        }

        springboard.swipeLeft()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.75))
        addSelectedWidget.tap()
    }

    private func openWidgetGallery(
        in springboard: XCUIApplication
    ) -> Bool {
        guard let addWidget = findAddWidgetAction(in: springboard) else {
            keepSpringBoardDiagnostics(
                springboard,
                name: "Add Widget action missing"
            )
            XCTFail("Expected the Add Widget action.")
            return false
        }

        let tapStarted = Date()
        addWidget.tap()
        let tapDuration = Date().timeIntervalSince(tapStarted)
        if tapDuration >= 30 {
            let stall = XCTAttachment(
                string: "Add Widget tap took \(tapDuration) seconds."
            )
            stall.name = "Widget gallery SpringBoard stall"
            stall.lifetime = .keepAlways
            add(stall)
            XCTFail(
                "The iPadOS SpringBoard widget gallery did not become quiescent."
            )
            return false
        }
        return true
    }

    private func findAddWidgetAction(
        in springboard: XCUIApplication
    ) -> XCUIElement? {
        var addWidget = waitForFirstHittable(
            [
                springboard.buttons
                    .matching(
                        NSPredicate(
                            format: "label CONTAINS[c] %@",
                            "Add Widget"
                        )
                    )
                    .firstMatch,
                springboard.buttons["Add Widget"],
                springboard.buttons["Add"],
            ],
            timeout: 3
        )
        if addWidget == nil,
           let edit = waitForFirstHittable(
               [springboard.buttons["Edit"]],
               timeout: 3
           ) {
            edit.tap()
            addWidget = waitForFirstHittable(
                [
                    springboard.buttons
                        .matching(
                            NSPredicate(
                                format: "label CONTAINS[c] %@",
                                "Add Widget"
                            )
                        )
                        .firstMatch,
                    springboard.buttons["Add Widget"],
                    springboard.menuItems["Add Widget"],
                ],
                timeout: 5
            )
        }
        return addWidget
    }

    private func visibleHomeScreenContent(
        in springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) -> [XCUIElement] {
        let screenFrame = springboard.windows.firstMatch.frame
        let homeScreenBottom = screenFrame.minY
            + (screenFrame.height * 0.84)
        return homeScreenIcons.icons.allElementsBoundByIndex.filter {
            isVisibleOnScreen($0, in: springboard)
                && $0.frame.midY < homeScreenBottom
        }
    }

    private func visibleHomeScreenIcons(
        in springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) -> [XCUIElement] {
        visibleHomeScreenContent(
            in: springboard,
            homeScreenIcons: homeScreenIcons
        )
        .filter {
            $0.frame.width < 160
                && $0.frame.height < 160
        }
    }

    private func visibleSurroundAppIcon(
        in springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) -> XCUIElement? {
        homeScreenIcons
            .icons
            .matching(identifier: "Surround")
            .allElementsBoundByIndex
            .first {
                isVisibleOnScreen($0, in: springboard)
                    && $0.frame.width < 160
                    && $0.frame.height < 160
            }
    }

    private func isVisibleOnScreen(
        _ element: XCUIElement,
        in springboard: XCUIApplication
    ) -> Bool {
        guard element.exists else {
            return false
        }
        let frame = element.frame
        let screenFrame = springboard.windows.firstMatch.frame
        return frame.width > 1
            && frame.height > 1
            && frame.intersects(screenFrame)
    }

    private func homeScreenPage(
        in springboard: XCUIApplication
    ) -> HomeScreenPage? {
        let indicator = springboard
            .pageIndicators["Page control"]
            .firstMatch
        guard indicator.exists else {
            return nil
        }
        let numbers = String(describing: indicator.value ?? "")
            .components(
                separatedBy: CharacterSet.decimalDigits.inverted
            )
            .compactMap(Int.init)
        guard numbers.count >= 2 else {
            return nil
        }
        guard numbers[0] <= numbers[1] else {
            return nil
        }
        return HomeScreenPage(
            current: numbers[0],
            total: numbers[1]
        )
    }

    private func navigate(
        from startingPage: HomeScreenPage?,
        to target: Int,
        in springboard: XCUIApplication
    ) -> Bool {
        guard var page = startingPage ?? homeScreenPage(in: springboard),
              target >= 1,
              target <= page.total else {
            return false
        }

        while page.current != target {
            let previousPage = page
            if page.current < target {
                springboard.swipeLeft()
            } else {
                springboard.swipeRight()
            }
            guard waitUntil(timeout: 5, condition: {
                guard let updatedPage = self.homeScreenPage(
                    in: springboard
                ) else {
                    return false
                }
                return updatedPage.current != previousPage.current
            }), let updatedPage = homeScreenPage(in: springboard) else {
                return false
            }
            page = updatedPage
        }
        return true
    }

    private func finishEditingHomeScreen(
        in springboard: XCUIApplication
    ) {
        let doneButton = springboard.buttons["Done"]
        let wasEditing = isHomeScreenEditing(in: springboard)
            || doneButton.waitForExistence(timeout: 2)
        guard wasEditing else {
            return
        }
        if let done = waitForFirstHittable(
            [doneButton],
            timeout: 5
        ) {
            done.tap()
            if !waitUntil(timeout: 5, condition: {
                !doneButton.exists
            }) {
                #if !targetEnvironment(macCatalyst)
                XCUIDevice.shared.press(.home)
                #endif
                _ = waitUntil(timeout: 5) {
                    !doneButton.exists
                }
            }
        } else {
            #if !targetEnvironment(macCatalyst)
            XCUIDevice.shared.press(.home)
            #endif
            _ = waitUntil(timeout: 5) {
                !doneButton.exists
            }
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
    }

    private func waitForFirstHittable(
        _ elements: [XCUIElement],
        timeout: TimeInterval
    ) -> XCUIElement? {
        var result: XCUIElement?
        _ = waitUntil(timeout: timeout) {
            result = elements.first(where: { $0.exists && $0.isHittable })
            return result != nil
        }
        return result
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        } while Date() < deadline
        return condition()
    }

    private func keepSpringBoardDiagnostics(
        _ springboard: XCUIApplication,
        name: String
    ) {
        let hierarchy = XCTAttachment(string: springboard.debugDescription)
        hierarchy.name = "SpringBoard hierarchy – \(name)"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)

        let screenshot = XCTAttachment(
            screenshot: XCUIScreen.main.screenshot(),
            quality: .original
        )
        screenshot.name = "SpringBoard screenshot – \(name)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
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
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: element
        )
        let result = XCTWaiter.wait(for: [hittable], timeout: 10)
        XCTAssertEqual(
            result,
            .completed,
            "Expected element with identifier \(identifier) to be hittable",
            file: file,
            line: line
        )
        element.tap()
    }
}
