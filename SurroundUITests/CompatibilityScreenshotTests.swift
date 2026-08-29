//
//  CompatibilityScreenshotTests.swift
//  SurroundUITests
//
//  Deterministic iOS 18/iOS 26 route and widget comparison captures.
//

import XCTest
import UIKit
import WidgetKit

final class CompatibilityScreenshotTests: SurroundUITestCase {
    private enum WidgetFamily: String, CaseIterable {
        case small
        case medium
        case large
        case extraLarge = "extra-large"

        static let legacyFamilies: [Self] = [
            .small,
            .medium,
            .large,
        ]

        var systemFamily: WidgetKit.WidgetFamily {
            switch self {
            case .small: return .systemSmall
            case .medium: return .systemMedium
            case .large: return .systemLarge
            case .extraLarge: return .systemExtraLarge
            }
        }

        var gallerySwipeCount: Int {
            switch self {
            case .small: 0
            case .medium: 1
            case .large: 2
            case .extraLarge: 3
            }
        }

        var sceneName: String {
            "widget-\(rawValue)"
        }

        func readinessIdentifierPrefix(
            proofToken: String,
            gameCount: Int
        ) -> String {
            [
                "surround.compatibility.widget.ready",
                rawValue,
                "games-\(gameCount)",
                "rendering-fullColor",
                "token-\(proofToken)",
                "expires-",
            ].joined(separator: ".")
        }
    }

    private struct WidgetVariant {
        let family: WidgetFamily
        let gameCount: Int
        let sceneName: String
    }

    private struct WidgetHorizontalTapRegions {
        let firstCellCenter: CGFloat
        let secondCellCenter: CGFloat
        let gridGap: CGFloat
        let outerBackground: CGFloat
        let railCenter: CGFloat
    }

    private struct WidgetRenderedLayout {
        let cellFrames: [CGRect]
        let boardFrames: [CGRect]
    }

    private struct BoardVisualStatistics {
        let luminanceRange: Double
        let luminanceStandardDeviation: Double
    }

    private struct HomeScreenPage: Equatable {
        let current: Int
        let total: Int
    }

    private struct IconParking {
        let capturePage: Int
        let parkingPage: Int
    }

    private struct CatalystWindowProfile {
        let name: String
        let size: CGSize
    }

    private var capturedSceneNames = [String]()
    private var smallWidgetSize: CGSize?
    private var compatibilityWidgetProofToken = ""
    private var activeApp: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 2_400
        capturedSceneNames = []
        smallWidgetSize = nil
        compatibilityWidgetProofToken = UUID().uuidString
        activeApp = nil
    }

    override func tearDownWithError() throws {
        activeApp?.terminate()
        activeApp = nil
        try super.tearDownWithError()
    }

    func testCompatibilityScreenshots() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(
            "Compatibility screenshot capture requires an iOS Simulator because it drives SpringBoard and Home Screen widgets."
        )
        #else
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        let nativeScenes = SurroundUITestContract.CompatibilityScene.allCases
            .filter { isPhone || $0 != .gameChat }

        XCTAssertEqual(
            nativeScenes.count,
            isPhone ? 29 : 28,
            "The native compatibility route contract changed unexpectedly."
        )

        for scene in nativeScenes {
            let app = launchApp(for: scene)
            capture(scene.rawValue, in: app)
            app.terminate()
        }

        captureWidgetFamilies(
            WidgetFamily.legacyFamilies.map {
                WidgetVariant(
                    family: $0,
                    gameCount: SurroundUITestContract
                        .compatibilityWidgetGameCount,
                    sceneName: $0.sceneName
                )
            }
        )

        let expectedNames = nativeScenes.map(\.rawValue)
            + WidgetFamily.legacyFamilies.map(\.sceneName)
        XCTAssertEqual(
            capturedSceneNames,
            expectedNames,
            "Compatibility capture must keep every scene exactly once and in manifest order."
        )
        XCTAssertEqual(
            capturedSceneNames.count,
            isPhone ? 32 : 31,
            "Compatibility capture produced an unexpected scene count."
        )
        #endif
    }

    func testAdaptiveWidgetRegressionScreenshots() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(
            "Adaptive widget regression capture requires an iOS Simulator."
        )
        #else
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        var variants = [
            WidgetVariant(
                family: .small,
                gameCount: 1,
                sceneName: "widget-small-full-capacity"
            ),
            WidgetVariant(
                family: .large,
                gameCount: 1,
                sceneName: "widget-large-one-game"
            ),
            WidgetVariant(
                family: .large,
                gameCount: 3,
                sceneName: "widget-large-three-games"
            ),
        ]
        if !isPhone {
            variants += [
                WidgetVariant(
                    family: .extraLarge,
                    gameCount: 1,
                    sceneName: "widget-extra-large-one-game"
                ),
                WidgetVariant(
                    family: .extraLarge,
                    gameCount: 4,
                    sceneName: "widget-extra-large-four-games"
                ),
                WidgetVariant(
                    family: .extraLarge,
                    gameCount: 6,
                    sceneName: "widget-extra-large-six-games"
                ),
            ]
        }

        captureWidgetFamilies(variants)
        XCTAssertEqual(capturedSceneNames, variants.map(\.sceneName))
        #endif
    }

    func testWidgetTapTargets() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(
            "Widget hit-region interaction requires an iOS Simulator."
        )
        #else
        let variants = [
            WidgetVariant(
                family: .large,
                gameCount: 1,
                sceneName: "widget-large-tap-targets"
            ),
            WidgetVariant(
                family: .medium,
                gameCount: 2,
                sceneName: "widget-medium-tap-targets"
            ),
        ]

        captureWidgetFamilies(
            variants,
            capturesScreenshots: false
        ) { variant, springboard in
            guard let regions = self.widgetHorizontalTapRegions(
                for: variant.family,
                gameCount: variant.gameCount,
                in: springboard
            ) else {
                XCTFail(
                    "Expected the \(variant.family.rawValue) widget before calculating its hit regions."
                )
                return
            }
            switch variant.family {
            case .large:
                let gameID = SurroundUITestContract.screenshotPrimaryGameID
                // A one-game widget has one URL across its entire surface.
                // Sample the board, lower timer region, outer grid
                // background, and the rail using the rendered widget width.
                for point in [
                    CGVector(dx: regions.gridGap, dy: 0.42),
                    CGVector(dx: regions.gridGap, dy: 0.92),
                    CGVector(dx: regions.outerBackground, dy: 0.50),
                    CGVector(dx: regions.railCenter, dy: 0.50),
                ] {
                    self.assertWidgetTap(
                        point,
                        opensGame: gameID,
                        family: variant.family,
                        in: springboard
                    )
                }
            case .medium:
                let firstGameID =
                    SurroundUITestContract.screenshotNextGameID
                let secondGameID =
                    SurroundUITestContract.screenshotPrimaryGameID
                let cellTargets: [(CGVector, Int)] = [
                    // Board and lower timer region in the first linked cell.
                    (
                        CGVector(dx: regions.firstCellCenter, dy: 0.38),
                        firstGameID
                    ),
                    (
                        CGVector(dx: regions.firstCellCenter, dy: 0.91),
                        firstGameID
                    ),
                    // The same linked regions in the second cell.
                    (
                        CGVector(dx: regions.secondCellCenter, dy: 0.38),
                        secondGameID
                    ),
                    (
                        CGVector(dx: regions.secondCellCenter, dy: 0.91),
                        secondGameID
                    ),
                ]
                for (point, gameID) in cellTargets {
                    self.assertWidgetTap(
                        point,
                        opensGame: gameID,
                        family: variant.family,
                        in: springboard
                    )
                }
                // Grid outer padding, the inter-cell gap, and the rail are
                // outside the cell Links. Each must follow the widget-wide
                // Home fallback instead of inheriting a nearby game URL.
                for backgroundX in [
                    regions.outerBackground,
                    regions.gridGap,
                    regions.railCenter,
                ] {
                    self.assertWidgetTapOpensHome(
                        CGVector(dx: backgroundX, dy: 0.50),
                        family: variant.family,
                        in: springboard
                    )
                }
            default:
                XCTFail("Unexpected widget interaction family")
            }
        }
        XCTAssertTrue(
            capturedSceneNames.isEmpty,
            "Hit-region coverage must not change the screenshot manifest."
        )
        #endif
    }

    func testMacDesktopLayoutScreenshots() throws {
        #if targetEnvironment(macCatalyst)
        let defaultSize = CGSize(width: 1_200, height: 760)
        let profiles = [
            CatalystWindowProfile(
                name: "900x600",
                size: CGSize(width: 900, height: 600)
            ),
            CatalystWindowProfile(
                name: "1200x760",
                size: CGSize(width: 1_200, height: 760)
            ),
            CatalystWindowProfile(
                name: "1440x760",
                size: CGSize(width: 1_440, height: 760)
            ),
            CatalystWindowProfile(
                name: "1000x900",
                size: CGSize(width: 1_000, height: 900)
            ),
        ]
        let scenes: [SurroundUITestContract.CompatibilityScene] = [
            .home,
            .publicGames,
            .messagesInbox,
            .settings,
            .about,
            .browser,
            .activeGameBoard,
        ]
        var expectedNames = [String]()

        for profile in profiles {
            for scene in scenes {
                let captureName = [
                    "mac",
                    profile.name,
                    scene.rawValue,
                ].joined(separator: "-")
                expectedNames.append(captureName)

                let app = launchApp(
                    for: scene,
                    catalystWindowSize: profile.size
                )

                let appWindow = stableAppWindow(
                    in: app,
                    requestedSize: profile.size,
                    captureName: captureName
                )
                assertExpectedWindowTitle(
                    appWindow,
                    in: app,
                    scene: scene,
                    captureName: captureName
                )
                keepWindowScreenshot(
                    captureName,
                    appWindow: appWindow
                )
                app.terminate()
            }
        }

        for scene in [
            SurroundUITestContract.CompatibilityScene.home,
            .activeGameBoard,
        ] {
            let captureName = "mac-native-full-screen-\(scene.rawValue)"
            expectedNames.append(captureName)

            let app = launchApp(
                for: scene,
                catalystWindowSize: defaultSize
            )

            let appWindow = stableAppWindow(
                in: app,
                requestedSize: defaultSize,
                captureName: captureName
            )
            assertExpectedWindowTitle(
                appWindow,
                in: app,
                scene: scene,
                captureName: captureName
            )
            enterNativeFullScreen(
                appWindow,
                in: app,
                captureName: captureName
            )
            assertExpectedWindowTitle(
                appWindow,
                in: app,
                scene: scene,
                captureName: captureName
            )
            keepWindowScreenshot(
                captureName,
                appWindow: appWindow
            )
            exitNativeFullScreen(
                appWindow,
                in: app,
                requestedSize: defaultSize,
                captureName: captureName
            )
            app.terminate()
        }

        // The fixed game captures exercise the normal navigation title. This
        // additional assertion protects the Catalyst title while Zen mode
        // hides the in-window navigation chrome without adding a 31st image.
        let zenApp = launchApp(
            for: .zenMode,
            catalystWindowSize: defaultSize
        )
        let zenWindow = stableAppWindow(
            in: zenApp,
            requestedSize: defaultSize,
            captureName: "mac-title-zen-mode"
        )
        assertExpectedWindowTitle(
            zenWindow,
            in: zenApp,
            scene: .zenMode,
            captureName: "mac-title-zen-mode"
        )
        zenApp.terminate()

        XCTAssertEqual(
            capturedSceneNames,
            expectedNames,
            "Mac layout capture must keep every requested scene exactly once and in matrix order."
        )
        #else
        throw XCTSkip(
            "The explicit window-size screenshot matrix requires Mac Catalyst."
        )
        #endif
    }

    func testMacWindowSizingContract() throws {
        #if targetEnvironment(macCatalyst)
        assertCatalystWindowSizeContract(
            defaultSize: CGSize(width: 1_200, height: 760),
            minimumSize: CGSize(width: 900, height: 600)
        )
        #else
        throw XCTSkip(
            "The explicit window-size contract requires Mac Catalyst."
        )
        #endif
    }

    private func launchApp(
        for scene: SurroundUITestContract.CompatibilityScene,
        widgetProofToken: String? = nil,
        widgetGameCount: Int? = nil,
        catalystWindowSize: CGSize? = nil,
        useCatalystDefaultWindowSize: Bool = false
    ) -> XCUIApplication {
        setCaptureOrientation()

        let app = XCUIApplication()
        var launchArguments = [
            SurroundUITestContract.launchArgument,
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            scene.rawValue,
            "-AppleInterfaceStyle",
            "Light",
        ]
        if let widgetProofToken {
            launchArguments += [
                SurroundUITestContract
                    .compatibilityWidgetProofTokenLaunchArgument,
                widgetProofToken,
            ]
        }
        if let widgetGameCount {
            launchArguments += [
                SurroundUITestContract
                    .compatibilityWidgetGameCountLaunchArgument,
                String(widgetGameCount),
            ]
        }
        if let catalystWindowSize {
            launchArguments += [
                SurroundUITestContract.catalystWindowSizeLaunchArgument,
                "\(Int(catalystWindowSize.width))x\(Int(catalystWindowSize.height))",
            ]
        }
        if useCatalystDefaultWindowSize {
            precondition(
                catalystWindowSize == nil,
                "The Catalyst default-size check cannot also request a size."
            )
            launchArguments += [
                SurroundUITestContract
                    .catalystDefaultWindowSizeLaunchArgument,
            ]
        }
        app.launchArguments = launchArguments
        app.launch()
        activeApp = app
        #if targetEnvironment(macCatalyst)
        app.activate()
        #endif
        element(
            SurroundUITestContract.AccessibilityID.compatibilityScreen(scene),
            in: app
        )
        waitForSceneContent(scene, in: app)
        return app
    }

    #if targetEnvironment(macCatalyst)
    private func assertCatalystWindowSizeContract(
        defaultSize: CGSize,
        minimumSize: CGSize
    ) {
        let defaultApp = launchApp(
            for: .home,
            useCatalystDefaultWindowSize: true
        )
        // `.defaultSize` applies to a newly created scene, while a relaunch
        // correctly restores the user's latest geometry. The Debug fixture
        // replaces its restored bootstrap with a fresh WindowGroup scene and
        // marks only that scene's geometry probe. Require one root-content
        // outcome and corroborate its outer size through UIWindow bounds,
        // effectiveGeometry.systemFrame, and XCTest's application-window frame.
        _ = stableAppWindow(
            in: defaultApp,
            requestedSize: defaultSize,
            captureName: "mac-default-window-size-contract",
            geometryIdentifier: SurroundUITestContract.AccessibilityID
                .catalystFreshWindowGeometry,
            geometryMatches: { value, outerFrame in
                let rootGeometry = self.catalystWindowGeometryValue(
                    for: defaultSize
                )
                let outerGeometry = self.catalystWindowGeometryValue(
                    for: outerFrame.size
                )
                return value == [
                    rootGeometry,
                    "window-\(outerGeometry)",
                    "system-\(outerGeometry)",
                    "windowed",
                ].joined(separator: "|")
            },
            requiredStableFrameCount: 10
        )
        defaultApp.terminate()

        let belowMinimumSize = CGSize(width: 800, height: 500)
        let minimumApp = launchApp(
            for: .home,
            catalystWindowSize: belowMinimumSize
        )
        _ = stableAppWindow(
            in: minimumApp,
            requestedSize: minimumSize,
            captureName: "mac-minimum-window-size-contract",
            requiredStableFrameCount: 10
        )
        minimumApp.terminate()
    }
    #endif

    private func waitForSceneContent(
        _ scene: SurroundUITestContract.CompatibilityScene,
        in app: XCUIApplication
    ) {
        switch scene {
        case .welcome:
            labeledElement("Sign in to your OGS account", in: app)
        case .home:
            element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
            element(
                SurroundUITestContract.AccessibilityID.homeGame(
                    SurroundUITestContract.screenshotPrimaryGameID
                ),
                in: app
            )
        case .publicGames:
            element(
                SurroundUITestContract.AccessibilityID.screenPublicGames,
                in: app
            )
            element(
                SurroundUITestContract.AccessibilityID.publicGame(
                    SurroundUITestContract.screenshotPublicGameID
                ),
                in: app
            )
        case .gameHistory:
            labeledElement("Game history", in: app)
            element(
                SurroundUITestContract.AccessibilityID.homeHistoryGame(
                    SurroundUITestContract.screenshotHistoryGameIDs[0]
                ),
                in: app
            )
        case .messagesInbox, .messageThread:
            labeledElement("hakhoa", in: app)
        case .settings:
            element(
                SurroundUITestContract.AccessibilityID.screenSettings,
                in: app
            )
        case .about:
            element(
                SurroundUITestContract.AccessibilityID.screenAbout,
                in: app
            )
        case .thanks:
            labeledElement("Thanks to", in: app)
        case .supporter:
            labeledElement("All Supporter tiers includes:", in: app)
        case .browser:
            element(
                SurroundUITestContract.AccessibilityID.screenBrowser,
                in: app
            )
        case .unsupportedGoogle:
            labeledElement("Open OGS Account Settings", in: app)
        case .activeGameBoard, .gameAnalysis, .zenMode, .gameOptions,
             .finishedGamePlayback, .publicGameSpectator, .gameChat:
            waitForGameSceneContent(scene, in: app)
        case .quickMatch:
            element(
                SurroundUITestContract.AccessibilityID.screenQuickMatch,
                in: app
            )
        case .openChallenges, .rengoOpenChallenges:
            element(
                SurroundUITestContract.AccessibilityID.screenOpenChallenges,
                in: app
            )
        case .customGame, .preferredSettingEditor:
            element(
                SurroundUITestContract.AccessibilityID.screenCustomGame,
                in: app
            )
        case .opponentPicker:
            labeledElement("Friends", in: app)
        case .advancedTime:
            labeledElement("Advanced time settings", in: app)
        case .advancedRules:
            labeledElement("Advanced rules settings", in: app)
        case .waitingGames:
            labeledElement("Weekend 19×19", in: app)
        case .preferredSettings:
            element(
                SurroundUITestContract.AccessibilityID
                    .screenPreferredSettings,
                in: app
            )
            element(
                SurroundUITestContract.AccessibilityID.preferredSetting(0),
                in: app
            )
        }
    }

    private func waitForGameSceneContent(
        _ scene: SurroundUITestContract.CompatibilityScene,
        in app: XCUIApplication
    ) {
        if scene == .gameOptions {
            labeledElement("Settings", in: app)
            return
        }

        let gameID: Int
        switch scene {
        case .finishedGamePlayback:
            gameID = SurroundUITestContract.screenshotHistoryGameIDs[0]
        case .publicGameSpectator:
            gameID = SurroundUITestContract.screenshotPublicGameID
        default:
            gameID = SurroundUITestContract.screenshotPrimaryGameID
        }
        element(
            SurroundUITestContract.AccessibilityID.gameDetail(gameID),
            in: app
        )
        if scene == .gameChat {
            dismissCompactChatInputAndWaitForLayout(
                in: app,
                timeout: 15
            )
        } else {
            element(
                SurroundUITestContract.AccessibilityID.gameBoard,
                in: app
            )
        }
        if scene == .zenMode {
            element(
                SurroundUITestContract.AccessibilityID.gameZenExit,
                in: app
            )
        }
    }

    private func seedWidgetFixture(
        gameCount: Int,
        keepsAppRunning: Bool = false
    ) {
        let app = launchApp(
            for: .home,
            widgetProofToken: compatibilityWidgetProofToken,
            widgetGameCount: gameCount
        )
        if keepsAppRunning {
            #if !targetEnvironment(macCatalyst)
            XCUIDevice.shared.press(.home)
            #endif
        } else {
            app.terminate()
        }
    }

    private func capture(
        _ name: String,
        in app: XCUIApplication
    ) {
        let appWindow = app.windows.firstMatch
        XCTAssertTrue(
            appWindow.waitForExistence(timeout: 10),
            "Expected an application window before capturing \(name)."
        )
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertGreaterThan(
                appWindow.frame.height,
                appWindow.frame.width,
                "The iPhone app must be portrait for \(name)."
            )
        } else {
            XCTAssertGreaterThan(
                appWindow.frame.width,
                appWindow.frame.height,
                "The iPad app must be landscape for \(name)."
            )
        }

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.75))
        keepScreenshot(name)
    }

    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(
            screenshot: XCUIScreen.main.screenshot(),
            quality: .original
        )
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        capturedSceneNames.append(name)
    }

    private func stableAppWindow(
        in app: XCUIApplication,
        requestedSize: CGSize,
        captureName: String,
        geometryIdentifier: String = SurroundUITestContract.AccessibilityID
            .catalystWindowGeometry,
        geometryMatches: ((String, CGRect) -> Bool)? = nil,
        requiredStableFrameCount: Int = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let appWindow = app.windows.firstMatch
        XCTAssertTrue(
            appWindow.waitForExistence(timeout: 15),
            "Expected an application window before capturing \(captureName).",
            file: file,
            line: line
        )
        let geometryProbe = catalystWindowGeometryProbe(
            in: appWindow,
            identifier: geometryIdentifier
        )
        XCTAssertTrue(
            geometryProbe.waitForExistence(timeout: 15),
            "Expected the Catalyst content-geometry probe before capturing \(captureName).",
            file: file,
            line: line
        )
        let expectedGeometry = catalystWindowGeometryValue(
            for: requestedSize
        )

        let stableFrame = waitForStableWindowFrame(
            appWindow,
            timeout: 20,
            requiredMatchingFrameCount: requiredStableFrameCount
        ) { currentFrame in
            let geometryValue = geometryProbe.value as? String
                ?? "unavailable"
            if let geometryMatches {
                return geometryMatches(geometryValue, currentFrame)
            }
            return self.catalystWindowGeometryValue(of: geometryProbe)
                == expectedGeometry
        }
        if stableFrame == nil {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name =
                "Accessibility hierarchy – unstable window \(captureName)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertNotNil(
            stableFrame,
            "Expected \(captureName) geometry to settle for the \(expectedGeometry) contract; probe was '\(geometryProbe.value as? String ?? "unavailable")' and the last outer frame was \(appWindow.frame).",
            file: file,
            line: line
        )
        return appWindow
    }

    private func waitForStableWindowFrame(
        _ appWindow: XCUIElement,
        timeout: TimeInterval,
        requiredMatchingFrameCount: Int = 3,
        matching condition: (CGRect) -> Bool
    ) -> CGRect? {
        var previousFrame: CGRect?
        var matchingFrameCount = 0

        let settled = waitUntil(timeout: timeout) {
            let currentFrame = appWindow.frame
            guard condition(currentFrame) else {
                previousFrame = currentFrame
                matchingFrameCount = 0
                return false
            }

            if let previousFrame,
               framesApproximatelyEqual(previousFrame, currentFrame) {
                matchingFrameCount += 1
            } else {
                matchingFrameCount = 1
            }
            previousFrame = currentFrame
            return matchingFrameCount >= requiredMatchingFrameCount
        }
        return settled ? previousFrame : nil
    }

    private func framesApproximatelyEqual(
        _ first: CGRect,
        _ second: CGRect,
        tolerance: CGFloat = 0.5
    ) -> Bool {
        abs(first.minX - second.minX) <= tolerance
            && abs(first.minY - second.minY) <= tolerance
            && abs(first.width - second.width) <= tolerance
            && abs(first.height - second.height) <= tolerance
    }

    private func catalystWindowGeometryProbe(
        in appWindow: XCUIElement,
        identifier: String = SurroundUITestContract.AccessibilityID
            .catalystWindowGeometry
    ) -> XCUIElement {
        appWindow.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    private func catalystWindowGeometryValue(
        of geometryProbe: XCUIElement
    ) -> String {
        let rawValue = geometryProbe.value as? String ?? "unavailable"
        return rawValue.split(separator: "|", maxSplits: 1)
            .first
            .map(String.init)
            ?? "unavailable"
    }

    private func catalystWindowGeometryValue(for size: CGSize) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    private func catalystWindowIsFullScreen(
        _ geometryProbe: XCUIElement
    ) -> Bool {
        (geometryProbe.value as? String)?.hasSuffix("|full-screen") == true
    }

    private func assertExpectedWindowTitle(
        _ appWindow: XCUIElement,
        in app: XCUIApplication,
        scene: SurroundUITestContract.CompatibilityScene,
        captureName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectedTitle: String
        switch scene {
        case .home:
            expectedTitle = "Active games"
        case .publicGames:
            expectedTitle = "Public live games"
        case .messagesInbox:
            expectedTitle = "Private messages"
        case .settings:
            expectedTitle = "Settings"
        case .about:
            expectedTitle = "About"
        case .browser:
            expectedTitle = "Web version"
        case .activeGameBoard, .zenMode:
            expectedTitle = "vs CopperKoi [4k]"
        default:
            XCTFail(
                "No desktop window-title contract exists for \(scene.rawValue).",
                file: file,
                line: line
            )
            return
        }
        var title = ""
        let foundExpectedTitle = waitUntil(timeout: 10) {
            title = appWindow.title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return title == expectedTitle
        }
        if !foundExpectedTitle {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name =
                "Accessibility hierarchy – unexpected window title \(captureName)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(
            foundExpectedTitle,
            "Expected \(captureName) to have window title '\(expectedTitle)'; found '\(title)'.",
            file: file,
            line: line
        )
    }

    private func keepWindowScreenshot(
        _ name: String,
        appWindow: XCUIElement
    ) {
        let attachment = XCTAttachment(
            screenshot: appWindow.screenshot(),
            quality: .original
        )
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        capturedSceneNames.append(name)
    }

    #if targetEnvironment(macCatalyst)
    private func enterNativeFullScreen(
        _ appWindow: XCUIElement,
        in app: XCUIApplication,
        captureName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let fullScreenButton = appWindow.buttons[
            XCUIIdentifierFullScreenWindow
        ]
        let appeared = fullScreenButton.waitForExistence(timeout: 10)
        XCTAssertTrue(
            appeared && fullScreenButton.isHittable,
            "Expected the native full-screen control for \(captureName).",
            file: file,
            line: line
        )
        guard appeared && fullScreenButton.isHittable else { return }

        fullScreenButton.click()
        registerFullScreenRestoration(
            appWindow,
            in: app
        )
        let geometryProbe = catalystWindowGeometryProbe(in: appWindow)
        let stableFullScreenFrame = waitForStableWindowFrame(
            appWindow,
            timeout: 20
        ) { _ in
            self.catalystWindowIsFullScreen(geometryProbe)
        }
        if stableFullScreenFrame == nil {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name =
                "Accessibility hierarchy – full-screen transition \(captureName)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertNotNil(
            stableFullScreenFrame,
            "Expected \(captureName) to settle in native full screen; probe was '\(geometryProbe.value as? String ?? "unavailable")' and the last frame was \(appWindow.frame).",
            file: file,
            line: line
        )
    }

    private func exitNativeFullScreen(
        _ appWindow: XCUIElement,
        in app: XCUIApplication,
        requestedSize: CGSize,
        captureName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // The native titlebar controls disappear once the window enters its
        // full-screen Space, so use the standard macOS toggle to restore it.
        app.typeKey("f", modifierFlags: [.control, .command])
        let geometryProbe = catalystWindowGeometryProbe(in: appWindow)
        let expectedGeometry = catalystWindowGeometryValue(
            for: requestedSize
        )
        let restoredFrame = waitForStableWindowFrame(
            appWindow,
            timeout: 20
        ) { _ in
            !self.catalystWindowIsFullScreen(geometryProbe)
                && self.catalystWindowGeometryValue(of: geometryProbe)
                    == expectedGeometry
        }
        if restoredFrame == nil {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name =
                "Accessibility hierarchy – full-screen restore \(captureName)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertNotNil(
            restoredFrame,
            "Expected \(captureName) content to restore to \(expectedGeometry); probe was '\(catalystWindowGeometryValue(of: geometryProbe))' and the last outer frame was \(appWindow.frame).",
            file: file,
            line: line
        )
    }

    private func registerFullScreenRestoration(
        _ appWindow: XCUIElement,
        in app: XCUIApplication
    ) {
        addTeardownBlock { [weak self] in
            guard let self,
                  app.state != .notRunning else { return }
            let geometryProbe = self.catalystWindowGeometryProbe(
                in: appWindow
            )
            guard geometryProbe.exists,
                  self.catalystWindowIsFullScreen(geometryProbe) else { return }

            app.activate()
            app.typeKey("f", modifierFlags: [.control, .command])
            _ = self.waitUntil(timeout: 10) {
                !self.catalystWindowIsFullScreen(geometryProbe)
            }
        }
    }
    #endif

    private func setCaptureOrientation() {
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.orientation =
            UIDevice.current.userInterfaceIdiom == .phone
                ? .portrait
                : .landscapeRight
        #endif
    }

    // MARK: - Widgets

    private func captureWidgetFamilies(
        _ variants: [WidgetVariant],
        capturesScreenshots: Bool = true,
        interaction: ((WidgetVariant, XCUIApplication) -> Void)? = nil
    ) {
        setCaptureOrientation()
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.press(.home)
        #endif

        let springboard = XCUIApplication(
            bundleIdentifier: "com.apple.springboard"
        )
        XCTAssertTrue(
            springboard.wait(for: .runningForeground, timeout: 10),
            "Expected SpringBoard before capturing widgets."
        )
        for _ in 0..<3 where homeScreenPage(in: springboard) == nil {
            #if !targetEnvironment(macCatalyst)
            XCUIDevice.shared.press(.home)
            #endif
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.75))
        }

        let expectedLandscape =
            UIDevice.current.userInterfaceIdiom != .phone
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                let frame = springboard.windows.firstMatch.frame
                return expectedLandscape
                    ? frame.width > frame.height
                    : frame.height > frame.width
            },
            "Expected SpringBoard to settle into the capture orientation."
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

        removeVisibleWidgets(
            from: springboard,
            homeScreenIcons: homeScreenIcons
        )
        guard navigateToSurroundHomeScreenPage(
            in: springboard,
            homeScreenIcons: homeScreenIcons
        ) else {
            keepSpringBoardDiagnostics(
                springboard,
                name: "Surround Home Screen page missing"
            )
            XCTFail("Expected to find Surround on a Home Screen page.")
            return
        }
        // The initially visible page may not be the page containing Surround.
        // Clear again after navigation so a stale fixture widget cannot survive
        // on the page that will be isolated.
        removeVisibleWidgets(
            from: springboard,
            homeScreenIcons: homeScreenIcons
        )
        guard isolateSurroundHomeScreenPage(
            in: springboard,
            homeScreenIcons: homeScreenIcons
        ) else {
            keepSpringBoardDiagnostics(
                springboard,
                name: "Surround Home Screen page was not isolated"
            )
            XCTFail(
                "Expected a Home Screen page containing only the Surround app icon."
            )
            return
        }

        for variant in variants {
            let family = variant.family
            seedWidgetFixture(
                gameCount: variant.gameCount,
                keepsAppRunning: interaction != nil
            )
            #if !targetEnvironment(macCatalyst)
            XCUIDevice.shared.press(.home)
            #endif
            XCTAssertTrue(
                springboard.wait(for: .runningForeground, timeout: 10),
                "Expected SpringBoard after seeding the widget fixture."
            )
            addWidget(
                family,
                to: springboard,
                homeScreenIcons: homeScreenIcons
            )

            guard let addedWidget = waitForWidget(
                family,
                in: springboard
            ) else {
                keepSpringBoardDiagnostics(
                    springboard,
                    name: "\(family.rawValue) widget missing or wrong size"
                )
                XCTFail(
                    "Expected the \(family.rawValue) Surround widget with the correct geometry."
                )
                return
            }
            if family == .small {
                smallWidgetSize = addedWidget.frame.size
            }

            guard let iconParking = parkSurroundAppIconOffWidgetPage(
                in: springboard,
                homeScreenIcons: homeScreenIcons
            ) else {
                keepSpringBoardDiagnostics(
                    springboard,
                    name: "\(family.rawValue) widget page still contains the app icon"
                )
                XCTFail(
                    "Expected the \(family.rawValue) widget to remain alone on its Home Screen page."
                )
                return
            }

            guard let widget = waitForWidget(
                family,
                in: springboard
            ) else {
                keepSpringBoardDiagnostics(
                    springboard,
                    name: "\(family.rawValue) widget missing after isolating its page"
                )
                XCTFail(
                    "Expected the \(family.rawValue) widget after moving the app icon away."
                )
                return
            }

            assertOnlyWidget(
                widget,
                family: family,
                in: springboard,
                homeScreenIcons: homeScreenIcons
            )
            assertFreshCompatibilityFixture(
                family,
                gameCount: variant.gameCount,
                in: springboard
            )
            assertWidgetBoardsHaveVisualDetail(
                widget,
                family: family,
                gameCount: variant.gameCount,
                in: springboard
            )
            interaction?(variant, springboard)
            guard waitForWidget(family, in: springboard) != nil else {
                keepSpringBoardDiagnostics(
                    springboard,
                    name: "\(family.rawValue) widget missing after interaction"
                )
                XCTFail(
                    "Expected the \(family.rawValue) widget after exercising its hit regions."
                )
                return
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.5))
            if capturesScreenshots {
                keepScreenshot(variant.sceneName)
            }

            guard restoreSurroundAppIcon(
                from: iconParking,
                in: springboard,
                homeScreenIcons: homeScreenIcons
            ), let restoredWidget = waitForWidget(
                family,
                in: springboard
            ) else {
                keepSpringBoardDiagnostics(
                    springboard,
                    name: "Surround app icon was not restored after \(family.rawValue)"
                )
                XCTFail(
                    "Expected to restore the Surround app icon before removing the \(family.rawValue) widget."
                )
                return
            }
            removeWidget(
                restoredWidget,
                from: springboard,
                homeScreenIcons: homeScreenIcons
            )
        }
    }

    private func widgetCandidates(
        in springboard: XCUIApplication
    ) -> [XCUIElement] {
        springboard.icons
            .matching(identifier: "Surround")
            .allElementsBoundByIndex
            .filter {
                isVisibleOnScreen($0, in: springboard)
                    && $0.frame.width >= 110
                    && $0.frame.height >= 110
            }
    }

    private func waitForWidget(
        _ family: WidgetFamily,
        in springboard: XCUIApplication
    ) -> XCUIElement? {
        var result: XCUIElement?
        _ = waitUntil(timeout: 20) {
            result = self.widgetCandidates(in: springboard)
                .first {
                    self.hasExpectedGeometry(
                        $0.frame.size,
                        for: family
                    )
                }
            return result != nil
        }
        return result
    }

    private func hasExpectedGeometry(
        _ size: CGSize,
        for family: WidgetFamily
    ) -> Bool {
        guard size.width > 0, size.height > 0 else {
            return false
        }
        let ratio = size.width / size.height

        switch family {
        case .small:
            return ratio >= 0.75 && ratio <= 1.35
        case .medium:
            guard let smallWidgetSize else {
                return false
            }
            return ratio >= 1.55
                && size.width >= smallWidgetSize.width * 1.55
                && size.height <= smallWidgetSize.height * 1.35
        case .large:
            guard let smallWidgetSize else {
                return false
            }
            return ratio >= 0.75
                && ratio <= 1.35
                && size.width >= smallWidgetSize.width * 1.55
                && size.height >= smallWidgetSize.height * 1.55
        case .extraLarge:
            guard let smallWidgetSize else {
                return false
            }
            return ratio >= 1.55
                && size.width >= smallWidgetSize.width * 3
                && size.height >= smallWidgetSize.height * 1.55
        }
    }

    private func removeVisibleWidgets(
        from springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) {
        for _ in 0..<6 {
            guard let widget = widgetCandidates(in: springboard).first else {
                return
            }
            removeWidget(
                widget,
                from: springboard,
                homeScreenIcons: homeScreenIcons
            )
        }
        XCTAssertTrue(
            widgetCandidates(in: springboard).isEmpty,
            "Expected all pre-existing Surround widgets to be removed."
        )
    }

    private func removeWidget(
        _ widget: XCUIElement,
        from springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) {
        let originalFrame = widget.frame
        let removeAction: XCUIElement?
        if #available(iOS 26.0, *) {
            guard enterHomeScreenEditMode(
                in: springboard,
                homeScreenIcons: homeScreenIcons
            ) else {
                keepSpringBoardDiagnostics(
                    springboard,
                    name: "Edit Home Screen action missing before widget removal"
                )
                XCTFail("Expected Home Screen edit mode before removing the widget.")
                return
            }
            removeAction = waitForFirstHittable(
                [
                    widget.buttons["DeleteButton"].firstMatch,
                    springboard.buttons["DeleteButton"],
                    springboard.buttons["Remove Widget"],
                    springboard.buttons
                        .matching(
                            NSPredicate(
                                format: "label CONTAINS[c] %@",
                                "Remove Widget"
                            )
                        )
                        .firstMatch,
                ],
                timeout: 5
            )
        } else {
            finishEditingHomeScreen(in: springboard)
            widget.press(forDuration: 0.8)
            removeAction = waitForFirstHittable(
                [
                    springboard.buttons["Remove Widget"],
                    springboard.menuItems["Remove Widget"],
                    springboard.buttons
                        .matching(
                            NSPredicate(
                                format: "label CONTAINS[c] %@",
                                "Remove Widget"
                            )
                        )
                        .firstMatch,
                ],
                timeout: 5
            )
        }
        guard let removeAction else {
            keepSpringBoardDiagnostics(
                springboard,
                name: "Remove Widget action missing"
            )
            XCTFail("Expected the Remove Widget action.")
            return
        }
        removeAction.tap()

        let removalAlert = springboard.alerts.firstMatch
        guard removalAlert.waitForExistence(timeout: 10) else {
            keepSpringBoardDiagnostics(
                springboard,
                name: "Remove Widget confirmation missing"
            )
            XCTFail("Expected the Remove Widget confirmation.")
            return
        }
        guard let confirm = waitForFirstHittable(
            [removalAlert.buttons["Remove"]],
            timeout: 5
        ) else {
            keepSpringBoardDiagnostics(
                springboard,
                name: "Remove Widget confirmation action missing"
            )
            XCTFail("Expected the Remove button in the widget confirmation.")
            return
        }
        confirm.tap()

        guard waitUntil(timeout: 10, condition: {
            !removalAlert.exists
        }) else {
            keepSpringBoardDiagnostics(
                springboard,
                name: "Remove Widget confirmation did not close"
            )
            XCTFail("Expected the Remove Widget confirmation to close.")
            return
        }

        XCTAssertTrue(
            waitUntil(timeout: 10) {
                !self.widgetCandidates(in: springboard)
                    .contains {
                        abs($0.frame.width - originalFrame.width) < 2
                            && abs($0.frame.height - originalFrame.height) < 2
                    }
            },
            "Expected the widget to be removed before the next family."
        )
        finishEditingHomeScreen(in: springboard)
    }

    private func addWidget(
        _ family: WidgetFamily,
        to springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) {
        XCTAssertTrue(
            widgetCandidates(in: springboard).isEmpty,
            "A previous widget must not remain before adding \(family.rawValue)."
        )
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

        guard let addWidget else {
            keepSpringBoardDiagnostics(
                springboard,
                name: "Add Widget action missing"
            )
            XCTFail("Expected the Add Widget action.")
            return
        }
        addWidget.tap()

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

        let addSelectedWidget = springboard.buttons
            .matching(
                NSPredicate(
                    format: "label CONTAINS[c] %@",
                    "Add Widget"
                )
            )
            .firstMatch
        guard addSelectedWidget.waitForExistence(timeout: 10) else {
            keepSpringBoardDiagnostics(
                springboard,
                name: "Widget family picker missing"
            )
            XCTFail("Expected the widget family picker.")
            return
        }

        for _ in 0..<family.gallerySwipeCount {
            springboard.swipeLeft()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.75))
        }
        addSelectedWidget.tap()
    }

    private func assertOnlyWidget(
        _ widget: XCUIElement,
        family: WidgetFamily,
        in springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) {
        let visibleContent = visibleHomeScreenContent(
            in: springboard,
            homeScreenIcons: homeScreenIcons
        )
        let hasOnlyExpectedWidget = visibleContent.count == 1
            && visibleContent[0].identifier == "Surround"
            && abs(visibleContent[0].frame.width - widget.frame.width) < 2
            && abs(visibleContent[0].frame.height - widget.frame.height) < 2
            && hasExpectedGeometry(
                visibleContent[0].frame.size,
                for: family
            )
            && visibleSurroundAppIcon(
                in: springboard,
                homeScreenIcons: homeScreenIcons
            ) == nil
        if !hasOnlyExpectedWidget {
            keepSpringBoardDiagnostics(
                springboard,
                name: "Unexpected content on isolated Home Screen page"
            )
        }
        XCTAssertTrue(
            hasOnlyExpectedWidget,
            "Expected the selected Surround widget to be the page's only content."
        )
    }

    private func assertFreshCompatibilityFixture(
        _ family: WidgetFamily,
        gameCount: Int,
        in springboard: XCUIApplication
    ) {
        let identifierPrefix = family.readinessIdentifierPrefix(
            proofToken: compatibilityWidgetProofToken,
            gameCount: gameCount
        )
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
                        "surround.compatibility.widget.unready.\(family.rawValue)."
                    )
                )
                .firstMatch
            keepSpringBoardDiagnostics(
                springboard,
                name: "\(family.rawValue) widget fixture was not ready"
            )
            let unreadyDetail = unreadyContent.exists
                ? " Widget reported '\(unreadyContent.identifier)'."
                : ""
            XCTFail(
                "Expected fresh "
                    + "\(gameCount)-game "
                    + "compatibility content in the \(family.rawValue) widget."
                    + unreadyDetail
            )
            return
        }

        let expiryText = readyContent.identifier
            .dropFirst(identifierPrefix.count)
        guard let expiry = TimeInterval(expiryText) else {
            XCTFail(
                "The \(family.rawValue) widget readiness identifier had an invalid expiry."
            )
            return
        }
        XCTAssertGreaterThan(
            Date(timeIntervalSince1970: expiry),
            Date().addingTimeInterval(5 * 60 * 60),
            "The \(family.rawValue) widget fixture must come from this capture run, not a stale timeline."
        )
    }

    private func assertWidgetTap(
        _ normalizedPoint: CGVector,
        opensGame gameID: Int,
        family: WidgetFamily,
        in springboard: XCUIApplication
    ) {
        guard let widget = waitForWidget(family, in: springboard) else {
            XCTFail("Expected the \(family.rawValue) widget before tapping it.")
            return
        }
        widget.coordinate(withNormalizedOffset: normalizedPoint).tap()

        guard let app = activeApp else {
            XCTFail("Expected the fixture app to remain available.")
            return
        }
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 10),
            "Expected a widget tap to foreground Surround."
        )
        element(
            SurroundUITestContract.AccessibilityID.gameDetail(gameID),
            in: app
        )
        returnToWidget(family, in: springboard)
    }

    private func widgetHorizontalTapRegions(
        for family: WidgetFamily,
        gameCount: Int,
        in springboard: XCUIApplication
    ) -> WidgetHorizontalTapRegions? {
        guard let widget = waitForWidget(family, in: springboard),
              let layout = widgetRenderedLayout(
                family: family,
                gameCount: gameCount,
                widgetSize: widget.frame.size
              ),
              let firstCell = layout.cellFrames.first else {
            return nil
        }

        let width = widget.frame.width
        let boardContentWidth = width
            - CorrespondenceWidgetGridLayout.turnRailWidth
        let secondCell = layout.cellFrames.dropFirst().first ?? firstCell
        let gridGap = layout.cellFrames.count > 1
            ? (firstCell.maxX + secondCell.minX) / 2
            : firstCell.midX
        let outerBackground = max(1, firstCell.minX / 2)

        return WidgetHorizontalTapRegions(
            firstCellCenter: firstCell.midX / width,
            secondCellCenter: secondCell.midX / width,
            gridGap: gridGap / width,
            outerBackground: outerBackground / width,
            railCenter: (
                boardContentWidth
                    + CorrespondenceWidgetGridLayout.turnRailWidth / 2
            ) / width
        )
    }

    private func widgetRenderedLayout(
        family: WidgetFamily,
        gameCount: Int,
        widgetSize: CGSize
    ) -> WidgetRenderedLayout? {
        let displayedCount = min(
            max(gameCount, 0),
            CorrespondenceWidgetGridLayout.maximumGameCount(
                for: family.systemFamily
            )
        )
        let availableSize = CGSize(
            width: widgetSize.width
                - CorrespondenceWidgetGridLayout.turnRailWidth,
            height: widgetSize.height
        )
        guard displayedCount > 0,
              availableSize.width > 0,
              availableSize.height > 0 else {
            return nil
        }

        let layout = CorrespondenceWidgetGridLayout.make(
            family: family.systemFamily,
            gameCount: displayedCount,
            availableSize: availableSize
        )

        return WidgetRenderedLayout(
            cellFrames: layout.itemFrames(
                gameCount: displayedCount,
                in: availableSize
            ),
            boardFrames: layout.boardFrames(
                gameCount: displayedCount,
                in: availableSize
            )
        )
    }

    private func assertWidgetBoardsHaveVisualDetail(
        _ widget: XCUIElement,
        family: WidgetFamily,
        gameCount: Int,
        in springboard: XCUIApplication
    ) {
        guard let layout = widgetRenderedLayout(
            family: family,
            gameCount: gameCount,
            widgetSize: widget.frame.size
        ) else {
            XCTFail(
                "Expected board regions for the \(family.rawValue) widget."
            )
            return
        }

        let image = widget.screenshot().image
        var failures = [String]()
        for (index, boardFrame) in layout.boardFrames.enumerated() {
            // Stay well inside the board so timer text, highlight chrome,
            // rounded corners, and screenshot row orientation cannot make a
            // blank board look detailed.
            let sampleInset = max(6, boardFrame.width * 0.22)
            let sampleFrame = boardFrame.insetBy(
                dx: sampleInset,
                dy: sampleInset
            )
            guard let statistics = boardVisualStatistics(
                in: image,
                pointRect: sampleFrame,
                referenceSize: widget.frame.size
            ) else {
                failures.append("board \(index + 1) could not be sampled")
                continue
            }
            if statistics.luminanceRange <= 0.06
                || statistics.luminanceStandardDeviation <= 0.015
            {
                let range = String(
                    format: "%.3f",
                    statistics.luminanceRange
                )
                let deviation = String(
                    format: "%.3f",
                    statistics.luminanceStandardDeviation
                )
                failures.append(
                    "board \(index + 1) was visually uniform "
                        + "(range \(range), deviation \(deviation))"
                )
            }
        }

        if !failures.isEmpty {
            keepSpringBoardDiagnostics(
                springboard,
                name: "\(family.rawValue) widget board visual integrity failed"
            )
            XCTFail(
                "The \(family.rawValue) widget must render grid or stone "
                    + "detail in every board region: "
                    + failures.joined(separator: "; ")
            )
        }
    }

    private func boardVisualStatistics(
        in image: UIImage,
        pointRect: CGRect,
        referenceSize: CGSize
    ) -> BoardVisualStatistics? {
        guard let cgImage = image.cgImage,
              referenceSize.width > 0,
              referenceSize.height > 0 else {
            return nil
        }

        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        let bytesPerRow = pixelWidth * 4
        var pixels = [UInt8](
            repeating: 0,
            count: bytesPerRow * pixelHeight
        )
        let drewImage = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(
                cgImage,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: pixelWidth,
                    height: pixelHeight
                )
            )
            return true
        }
        guard drewImage else { return nil }

        let scaleX = CGFloat(pixelWidth) / referenceSize.width
        let scaleY = CGFloat(pixelHeight) / referenceSize.height
        let pixelRect = CGRect(
            x: pointRect.minX * scaleX,
            y: pointRect.minY * scaleY,
            width: pointRect.width * scaleX,
            height: pointRect.height * scaleY
        ).intersection(
            CGRect(
                x: 0,
                y: 0,
                width: pixelWidth,
                height: pixelHeight
            )
        )
        guard !pixelRect.isNull,
              pixelRect.width >= 2,
              pixelRect.height >= 2 else {
            return nil
        }

        let minX = max(0, Int(floor(pixelRect.minX)))
        let maxX = min(pixelWidth, Int(ceil(pixelRect.maxX)))
        let minY = max(0, Int(floor(pixelRect.minY)))
        let maxY = min(pixelHeight, Int(ceil(pixelRect.maxY)))
        let sampleStep = max(
            1,
            Int(min(pixelRect.width, pixelRect.height) / 96)
        )
        var minimumLuminance = Double.greatestFiniteMagnitude
        var maximumLuminance = -Double.greatestFiniteMagnitude
        var sum = 0.0
        var squaredSum = 0.0
        var sampleCount = 0

        for y in stride(from: minY, to: maxY, by: sampleStep) {
            for x in stride(from: minX, to: maxX, by: sampleStep) {
                let offset = y * bytesPerRow + x * 4
                let red = Double(pixels[offset]) / 255
                let green = Double(pixels[offset + 1]) / 255
                let blue = Double(pixels[offset + 2]) / 255
                let luminance = 0.2126 * red
                    + 0.7152 * green
                    + 0.0722 * blue
                minimumLuminance = min(minimumLuminance, luminance)
                maximumLuminance = max(maximumLuminance, luminance)
                sum += luminance
                squaredSum += luminance * luminance
                sampleCount += 1
            }
        }
        guard sampleCount > 1 else { return nil }

        let mean = sum / Double(sampleCount)
        let variance = max(
            0,
            squaredSum / Double(sampleCount) - mean * mean
        )
        return BoardVisualStatistics(
            luminanceRange: maximumLuminance - minimumLuminance,
            luminanceStandardDeviation: sqrt(variance)
        )
    }

    private func assertWidgetTapOpensHome(
        _ normalizedPoint: CGVector,
        family: WidgetFamily,
        in springboard: XCUIApplication
    ) {
        guard let widget = waitForWidget(family, in: springboard) else {
            XCTFail("Expected the \(family.rawValue) widget before tapping it.")
            return
        }
        widget.coordinate(withNormalizedOffset: normalizedPoint).tap()

        guard let app = activeApp else {
            XCTFail("Expected the fixture app to remain available.")
            return
        }
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 10),
            "Expected the widget background to foreground Surround."
        )
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        returnToWidget(family, in: springboard)
    }

    private func returnToWidget(
        _ family: WidgetFamily,
        in springboard: XCUIApplication
    ) {
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.press(.home)
        #endif
        XCTAssertTrue(
            springboard.wait(for: .runningForeground, timeout: 10),
            "Expected to return to SpringBoard after a widget route."
        )
        XCTAssertNotNil(
            waitForWidget(family, in: springboard),
            "Expected the widget to remain available for the next hit-region assertion."
        )
    }

    // MARK: - SpringBoard page setup

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

    private func parkSurroundAppIconOffWidgetPage(
        in springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) -> IconParking? {
        guard let widgetPage = homeScreenPage(in: springboard),
              enterHomeScreenEditMode(
                  in: springboard,
                  homeScreenIcons: homeScreenIcons
              ),
              dragVisibleSurroundAppIcon(
                  towardRight: widgetPage.current == 1,
                  in: springboard,
                  homeScreenIcons: homeScreenIcons
              ) else {
            return nil
        }

        guard waitUntil(timeout: 8, condition: {
            guard let currentPage = self.homeScreenPage(
                in: springboard
            ) else {
                return false
            }
            return currentPage.current != widgetPage.current
                && self.visibleSurroundAppIcon(
                    in: springboard,
                    homeScreenIcons: homeScreenIcons
                ) != nil
        }), let parkingPage = homeScreenPage(in: springboard) else {
            return nil
        }

        finishEditingHomeScreen(in: springboard)
        guard navigate(
            from: homeScreenPage(in: springboard),
            to: widgetPage.current,
            in: springboard
        ) else {
            return nil
        }

        guard visibleSurroundAppIcon(
            in: springboard,
            homeScreenIcons: homeScreenIcons
        ) == nil
            && !widgetCandidates(in: springboard).isEmpty else {
            return nil
        }
        return IconParking(
            capturePage: widgetPage.current,
            parkingPage: parkingPage.current
        )
    }

    private func restoreSurroundAppIcon(
        from parking: IconParking,
        in springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) -> Bool {
        guard navigate(
            from: homeScreenPage(in: springboard),
            to: parking.parkingPage,
            in: springboard
        ),
            enterHomeScreenEditMode(
                in: springboard,
                homeScreenIcons: homeScreenIcons
            ),
            dragVisibleSurroundAppIcon(
                towardRight: parking.capturePage > parking.parkingPage,
                in: springboard,
                homeScreenIcons: homeScreenIcons
            ) else {
            return false
        }

        guard waitUntil(timeout: 8, condition: {
            guard let currentPage = self.homeScreenPage(
                in: springboard
            ) else {
                return false
            }
            return currentPage.current == parking.capturePage
                && self.visibleSurroundAppIcon(
                    in: springboard,
                    homeScreenIcons: homeScreenIcons
                ) != nil
        }) else {
            return false
        }

        finishEditingHomeScreen(in: springboard)
        return !widgetCandidates(in: springboard).isEmpty
            && visibleSurroundAppIcon(
                in: springboard,
                homeScreenIcons: homeScreenIcons
            ) != nil
    }

    private func dragVisibleSurroundAppIcon(
        towardRight: Bool,
        in springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) -> Bool {
        guard let surroundIcon = visibleSurroundAppIcon(
            in: springboard,
            homeScreenIcons: homeScreenIcons
        ) else {
            return false
        }

        return dragHomeScreenIcon(
            surroundIcon,
            towardRight: towardRight,
            in: springboard
        )
    }

    private func dragHomeScreenIcon(
        _ icon: XCUIElement,
        towardRight: Bool,
        in springboard: XCUIApplication
    ) -> Bool {
        guard isVisibleOnScreen(icon, in: springboard) else {
            return false
        }

        let window = springboard.windows.firstMatch
        let windowFrame = window.frame
        let normalizedY = crossPageIconDropY(
            for: icon,
            in: windowFrame
        )
        let destinationEdge = window.coordinate(
            withNormalizedOffset: CGVector(
                dx: towardRight ? 0.98 : 0.02,
                dy: normalizedY
            )
        )
        icon.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)
        )
        .press(
            forDuration: 0.12,
            thenDragTo: destinationEdge,
            withVelocity: .slow,
            thenHoldForDuration: 0.7
        )
        return true
    }

    private func isolateSurroundHomeScreenPage(
        in springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) -> Bool {
        guard homeScreenPage(in: springboard) != nil else {
            return false
        }

        let unwantedContent = visibleHomeScreenContent(
            in: springboard,
            homeScreenIcons: homeScreenIcons
        )
        .filter { $0.identifier != "Surround" }
        if unwantedContent.isEmpty {
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

        for _ in 0..<24 {
            guard let startingPage = homeScreenPage(in: springboard),
                  isHomeScreenEditing(in: springboard) else {
                return false
            }

            let visibleContent = visibleHomeScreenContent(
                in: springboard,
                homeScreenIcons: homeScreenIcons
            )
            let unwantedContent = visibleContent.filter {
                $0.identifier != "Surround"
            }
            if unwantedContent.isEmpty {
                return visibleSurroundAppIcon(
                    in: springboard,
                    homeScreenIcons: homeScreenIcons
                ) != nil
            }

            // Keep Surround on its installed page and move every other icon
            // toward an existing neighboring page. Moving Surround right
            // from the last page reaches App Library on iOS 18 instead of
            // creating a new blank Home Screen page.
            guard dragHomeScreenIcon(
                unwantedContent[0],
                towardRight: startingPage.current == 1,
                in: springboard
            ) else {
                return false
            }

            guard waitUntil(timeout: 8, condition: {
                guard let updatedPage = self.homeScreenPage(
                    in: springboard
                ) else {
                    return false
                }
                return updatedPage.current != startingPage.current
            }), navigate(
                from: homeScreenPage(in: springboard),
                to: startingPage.current,
                in: springboard
            ) else {
                return false
            }

            let remainingContent = visibleHomeScreenContent(
                in: springboard,
                homeScreenIcons: homeScreenIcons
            )
            if remainingContent.count == 1,
               remainingContent.first?.identifier == "Surround" {
                return true
            }
        }
        return false
    }

    private func crossPageIconDropY(
        for icon: XCUIElement,
        in windowFrame: CGRect
    ) -> CGFloat {
        if UIDevice.current.userInterfaceIdiom == .phone {
            // Xcode installs the UI-test runner near the app icon on iPhone.
            // Preserve a lower empty grid band so a cross-page drop cannot
            // combine Surround with the runner into a folder.
            return 0.68
        }
        return min(
            max(
                (icon.frame.midY - windowFrame.minY) / windowFrame.height,
                0.22
            ),
            0.68
        )
    }

    private func enterHomeScreenEditMode(
        in springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) -> Bool {
        if isHomeScreenEditing(in: springboard) {
            return true
        }

        // Enter edit mode from an empty grid cell. On iOS 26, selecting
        // "Edit Home Screen" from an app-icon context menu can leave the
        // XCTest gesture waiting indefinitely for SpringBoard quiescence.
        guard let emptyGridCoordinate = emptyHomeScreenCoordinate(
            in: springboard,
            homeScreenIcons: homeScreenIcons
        ) else {
            return false
        }
        emptyGridCoordinate.press(forDuration: 1.5)
        if waitUntil(timeout: 5, condition: {
            self.isHomeScreenEditing(in: springboard)
        }) {
            return true
        }

        // The menu fallback is retained for iOS 18, where it is bounded and
        // already exercised by the minimum-OS capture. Never enter it on
        // iOS 26, where a failed empty-grid gesture should fail promptly.
        if #available(iOS 26.0, *) {
            return false
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

    private func emptyHomeScreenCoordinate(
        in springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) -> XCUICoordinate? {
        let gridFrame = homeScreenIcons.frame
        guard gridFrame.width > 1, gridFrame.height > 1 else {
            return nil
        }

        let occupiedFrames = visibleHomeScreenContent(
            in: springboard,
            homeScreenIcons: homeScreenIcons
        )
        .map {
            $0.frame.insetBy(dx: -12, dy: -12)
        }
        let candidates = [
            CGVector(dx: 0.5, dy: 0.5),
            CGVector(dx: 0.72, dy: 0.72),
            CGVector(dx: 0.28, dy: 0.72),
            CGVector(dx: 0.72, dy: 0.5),
            CGVector(dx: 0.28, dy: 0.5),
            CGVector(dx: 0.5, dy: 0.72),
            CGVector(dx: 0.5, dy: 0.28),
            CGVector(dx: 0.72, dy: 0.28),
            CGVector(dx: 0.28, dy: 0.28),
        ]

        for candidate in candidates {
            let possibleOffsets: [CGVector]
            if UIDevice.current.userInterfaceIdiom == .pad {
                // XCTest can rotate normalized element coordinates with the
                // landscape iPad interface. Require the candidate and every
                // rotated or mirrored equivalent to miss visible content.
                possibleOffsets = [
                    candidate,
                    CGVector(dx: 1 - candidate.dx, dy: candidate.dy),
                    CGVector(dx: candidate.dx, dy: 1 - candidate.dy),
                    CGVector(
                        dx: 1 - candidate.dx,
                        dy: 1 - candidate.dy
                    ),
                    CGVector(dx: candidate.dy, dy: candidate.dx),
                    CGVector(dx: 1 - candidate.dy, dy: candidate.dx),
                    CGVector(dx: candidate.dy, dy: 1 - candidate.dx),
                    CGVector(
                        dx: 1 - candidate.dy,
                        dy: 1 - candidate.dx
                    ),
                ]
            } else {
                // Portrait iPhone coordinates are not transformed. Requiring
                // mirrored points to be empty would reject every usable cell
                // below a large widget that fills the upper grid.
                possibleOffsets = [candidate]
            }
            let missesVisibleContent = possibleOffsets.allSatisfy { offset in
                let point = CGPoint(
                    x: gridFrame.minX + (gridFrame.width * offset.dx),
                    y: gridFrame.minY + (gridFrame.height * offset.dy)
                )
                return !occupiedFrames.contains {
                    $0.contains(point)
                }
            }
            if missesVisibleContent {
                return homeScreenIcons.coordinate(
                    withNormalizedOffset: candidate
                )
            }
        }
        return nil
    }

    private func isHomeScreenEditing(
        in springboard: XCUIApplication
    ) -> Bool {
        let doneButton = springboard.buttons["Done"]
        return doneButton.exists && doneButton.isHittable
    }

    private func visibleHomeScreenContent(
        in springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) -> [XCUIElement] {
        let screenFrame = springboard.windows.firstMatch.frame
        let homeScreenBottom =
            screenFrame.minY + (screenFrame.height * 0.84)
        return homeScreenIcons.icons.allElementsBoundByIndex.filter {
            isVisibleOnScreen($0, in: springboard)
                && $0.frame.midY < homeScreenBottom
        }
    }

    private func visibleSurroundAppIcon(
        in springboard: XCUIApplication,
        homeScreenIcons: XCUIElement
    ) -> XCUIElement? {
        homeScreenIcons.icons
            .matching(identifier: "Surround")
            .allElementsBoundByIndex
            .first {
                isVisibleOnScreen($0, in: springboard)
                    && $0.frame.width < 110
                    && $0.frame.height < 110
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
        let indicator = springboard.pageIndicators["Page control"].firstMatch
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
        // Captures force en-US, whose value is "Page 1 of 2". SpringBoard
        // reports App Library as the page after the final Home Screen page
        // (for example "Page 4 of 3"); reject it as a capture destination.
        guard numbers[0] <= numbers[1] else {
            return nil
        }
        return HomeScreenPage(current: numbers[0], total: numbers[1])
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
        if let done = waitForFirstHittable([doneButton], timeout: 5) {
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

    // MARK: - Assertions and diagnostics

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
    private func labeledElement(
        _ label: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
        let appeared = element.waitForExistence(timeout: 15)
        if !appeared {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name =
                "Accessibility hierarchy – missing label \(label)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(
            appeared,
            "Expected an element labelled \(label)",
            file: file,
            line: line
        )
        return element
    }

    @discardableResult
    private func element(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let element = app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
        let appeared = element.waitForExistence(timeout: 15)
        if !appeared {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name =
                "Accessibility hierarchy – missing \(identifier)"
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
}
