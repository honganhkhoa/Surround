import XCTest
import UIKit

/// Opt-in: Game Detail's CPU, memory and time under one theme, through fixed
/// journeys, so runs under different themes can be compared. Set
/// TEST_RUNNER_SURROUND_THEME_PERFORMANCE=1 and choose the theme with
/// TEST_RUNNER_SURROUND_PERFORMANCE_THEME (`standard`, the default, or
/// `nebulaPearl`, `rakedGarden`, `surroundStudio` or `feltMeadow`). Standard runs in dark
/// mode, or light as `standardLight` to compare light scene themes fairly;
/// each scene theme chooses its own appearance. Append `Night` to an adaptive
/// scene theme to fix its appearance in dark mode.
///
/// Taps go to coordinates resolved before measuring, so XCUITest's element
/// queries stay out of the measured blocks as far as possible. Each block
/// prints wall-clock markers for host-side samplers (the render server).
final class GameDetailThemePerformanceTests: SurroundJourneyUITestCase {
    private typealias ID = SurroundUITestContract.AccessibilityID

    private var theme = "standard"

    override func setUpWithError() throws {
        try super.setUpWithError()
        let environment = ProcessInfo.processInfo.environment
        guard environment["SURROUND_THEME_PERFORMANCE"] == "1" else {
            throw XCTSkip("Opt in to the Game Detail theme performance runs.")
        }
        theme = environment["SURROUND_PERFORMANCE_THEME"] ?? "standard"
    }

    /// Board redraws: step back and forward through the game in Analyze.
    func testStepThroughMoves() {
        let app = launchAtHome()
        defer { app.terminate() }
        openGame(in: app)
        setGameAnalyzing(true, in: app)
        let previous = center(of: element(ID.gameAnalyzePrevious, in: app, matching: .button), in: app)
        let next = center(of: element(ID.gameAnalyzeNext, in: app, matching: .button), in: app)
        measureJourney("step-moves", app: app) {
            for _ in 0..<8 { previous.tap() }
            for _ in 0..<8 { next.tap() }
        }
    }

    /// Entering and leaving the game: scene setup, window style and the push.
    func testOpenAndCloseGame() {
        let app = launchAtHome()
        defer { app.terminate() }
        openGame(in: app)
        let back = center(of: app.navigationBars.buttons.element(boundBy: 0), in: app)
        tap(app.navigationBars.buttons.element(boundBy: 0), description: "Back to Home", in: app)
        element(ID.screenHome, in: app)
        let game = center(of: revealedGame(in: app), in: app)
        let board = app.descendants(matching: .any).matching(identifier: ID.gameBoard).firstMatch
        let home = app.descendants(matching: .any).matching(identifier: ID.screenHome).firstMatch
        measureJourney("open-close", app: app) {
            for _ in 0..<2 {
                game.tap()
                XCTAssertTrue(board.waitForExistence(timeout: 10))
                Thread.sleep(forTimeInterval: 0.5)
                back.tap()
                XCTAssertTrue(pollUntil(timeout: 10) { !board.exists && home.exists })
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }

    /// Relayout of the board, the scene and the controls.
    func testRotate() {
        let app = launchAtHome()
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
        openGame(in: app)
        let window = app.windows.firstMatch
        measureJourney("rotate", app: app) {
            for landscape in [true, false, true, false] {
                XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
                XCTAssertTrue(pollUntil(timeout: 10) {
                    let frame = window.frame
                    return landscape == (frame.width > frame.height)
                })
                Thread.sleep(forTimeInterval: 1)
            }
        }
    }

    /// Chat opening and closing resizes the board.
    func testToggleChat() {
        let app = launchAtHome()
        defer { app.terminate() }
        openGame(in: app)
        let chat = center(of: gameChatControl(in: app), in: app)
        measureJourney("toggle-chat", app: app) {
            for _ in 0..<2 {
                chat.tap()
                Thread.sleep(forTimeInterval: 1.2)
                chat.tap()
                Thread.sleep(forTimeInterval: 1.2)
            }
        }
    }

    /// The game at rest: anything still drawing shows up here.
    func testIdle() {
        let app = launchAtHome()
        defer { app.terminate() }
        openGame(in: app)
        Thread.sleep(forTimeInterval: 2)
        measureJourney("idle", app: app) {
            Thread.sleep(forTimeInterval: 10)
        }
    }

    // MARK: - Helpers

    private func measureJourney(_ name: String, app: XCUIApplication, block: () -> Void) {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        var iteration = 0
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app),
                          XCTClockMetric()],
                options: options) {
            iteration += 1
            mark("begin", name, iteration)
            block()
            mark("end", name, iteration)
        }
    }

    private func mark(_ event: String, _ journey: String, _ iteration: Int) {
        let line = String(format: "[ThemePerf] %@ theme=%@ journey=%@ iteration=%d epoch=%.3f\n",
                          event, theme, journey, iteration, Date().timeIntervalSince1970)
        FileHandle.standardOutput.write(Data(line.utf8))
    }

    private func launchAtHome() -> XCUIApplication {
        var arguments = [SurroundUITestContract.compatibilityScreenshotLaunchArgument,
                         SurroundUITestContract.emptyMessagesLaunchArgument,
                         SurroundUITestContract.compatibilitySceneLaunchArgument,
                         SurroundUITestContract.CompatibilityScene.home.rawValue,
                         SurroundUITestContract.gameDetailDesignArtboardLaunchArgument, "1"]
        if theme == "standard" || theme == "standardLight" {
            arguments += [SurroundUITestContract.appearanceLaunchArgument,
                          theme == "standard" ? "dark" : "light"]
        } else if ["rakedGardenNight", "surroundStudioNight", "feltMeadowNight"].contains(theme) {
            arguments += [SurroundUITestContract.themeLaunchArgument, String(theme.dropLast("Night".count)),
                          SurroundUITestContract.appearanceLaunchArgument, "dark"]
        } else {
            arguments += [SurroundUITestContract.themeLaunchArgument, theme]
        }
        let app = launchApp(additionalLaunchArguments: arguments, orientation: .portrait)
        element(ID.screenHome, in: app)
        return app
    }

    private func openGame(in app: XCUIApplication) {
        tap(revealedGame(in: app), description: "Open the design fixture from Home", in: app)
        element(ID.gameBoard, in: app)
        Thread.sleep(forTimeInterval: 1)
    }

    /// The fixture's Home card, scrolled fully into view.
    private func revealedGame(in app: XCUIApplication) -> XCUIElement {
        let game = element(ID.homeGame(SurroundUITestContract.screenshotPrimaryGameID),
                           in: app, matching: .button)
        let home = app.scrollViews[ID.screenHome].firstMatch
        for _ in 0..<4 {
            let window = app.windows.firstMatch.frame
            let top = max(window.minY + 8, app.navigationBars.firstMatch.frame.maxY + 8)
            let bottom = window.maxY - 90
            let target = game.frame
            if game.isHittable && target.minY >= top && target.maxY <= bottom { break }
            let upper = home.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35))
            let lower = home.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.70))
            let moveDown = target.minY < top
            (moveDown ? upper : lower).press(forDuration: 0.05,
                thenDragTo: moveDown ? lower : upper, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        return game
    }

    /// A coordinate fixed from the element's current frame.
    private func center(of element: XCUIElement, in app: XCUIApplication) -> XCUICoordinate {
        XCTAssertTrue(waitUntilHittable(element, timeout: 10))
        let frame = element.frame
        return app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
    }
}
