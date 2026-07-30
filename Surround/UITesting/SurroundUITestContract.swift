//
//  SurroundUITestContract.swift
//  Surround
//
//  Shared identifiers and fixture values for deterministic UI tests.
//

import Foundation

enum SurroundUITestContract {
    static let launchArgument = "--surround-ui-testing"
    static let screenshotLaunchArgument = "--surround-app-store-screenshots"
    static let screenshotDarkModeLaunchArgument = "--surround-app-store-screenshots-dark-mode"
    static let screenshotWidgetFixtureCleanupLaunchArgument =
        "--clear-app-store-screenshot-widget-fixture"
    static let preferencesSuite = "com.honganhkhoa.Surround.UITests"
    static let fixtureGameID = 26_268_404
    static let screenshotPrimaryGameID = 68_301_595
    static let screenshotFixtureGameIDs = [
        screenshotPrimaryGameID,
        18_759_438,
        62_050_416,
    ]
    static let screenshotHistoryGameIDs = [
        68_301_601,
        68_301_602,
        67_811_158,
        62_050_423,
        25_089_254,
        25_089_220,
        25_089_241,
        25_089_253,
        25_089_251,
        35_505_493,
    ]
    static let screenshotPublicGameID = 25_291_907
    static let screenshotAnalysisBaseMoveNumber = 41
    static let screenshotAnalysisSelectedMoveNumber = 46
    static let screenshotAnalysisSelectedRow = 2
    static let screenshotAnalysisSelectedColumn = 5
    static let screenshotAnalysisSelectedMovePath = [
        "bn",
        "bm",
        "bo",
        "cf",
        "fc",
    ]

    #if DEBUG && MAIN_APP
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static var isCapturingAppStoreScreenshots: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains(screenshotLaunchArgument)
    }

    static var isCapturingAppStoreScreenshotsInDarkMode: Bool {
        isCapturingAppStoreScreenshots
            && ProcessInfo.processInfo.arguments.contains(screenshotDarkModeLaunchArgument)
    }

    static var isClearingAppStoreScreenshotWidgetFixture: Bool {
        ProcessInfo.processInfo.arguments.contains(
            screenshotWidgetFixtureCleanupLaunchArgument
        )
    }
    #else
    static let isEnabled = false
    static let isCapturingAppStoreScreenshots = false
    static let isCapturingAppStoreScreenshotsInDarkMode = false
    static let isClearingAppStoreScreenshotWidgetFixture = false
    #endif

    enum AccessibilityID {
        static let navigationHome = "navigation.home"
        static let navigationPublicGames = "navigation.publicGames"
        static let navigationSettings = "navigation.settings"
        static let navigationAbout = "navigation.about"
        static let navigationBrowser = "navigation.browser"

        static let screenHome = "screen.home"
        static let screenPublicGames = "screen.publicGames"
        static let screenSettings = "screen.settings"
        static let screenAbout = "screen.about"
        static let screenBrowser = "screen.browser"
        static let screenNewGame = "screen.newGame"
        static let screenOpenChallenges = "screen.openChallenges"
        static let screenQuickMatch = "screen.quickMatch"
        static let screenCustomGame = "screen.customGame"
        static let screenGameOptions = "screen.gameOptions"
        static let screenPreferredSettings = "screen.preferredSettings"

        static func homeGame(_ id: Int) -> String {
            "home.game.\(id)"
        }

        #if MAIN_APP
        static func homeGame(_ game: Game) -> String {
            homeGame(ogsID(for: game))
        }
        #endif

        static func homeHistoryGame(_ id: Int) -> String {
            "home.historyGame.\(id)"
        }

        #if MAIN_APP
        static func homeHistoryGame(_ game: Game) -> String {
            homeHistoryGame(ogsID(for: game))
        }
        #endif

        static let homeNewGame = "home.newGame"
        static let homePreferredSettings = "home.preferredSettings"

        static func preferredSetting(_ index: Int) -> String {
            "preferredSettings.setting.\(index)"
        }

        static func publicGame(_ id: Int) -> String {
            "publicGames.game.\(id)"
        }

        #if MAIN_APP
        static func publicGame(_ game: Game) -> String {
            publicGame(ogsID(for: game))
        }
        #endif

        static func gameDetail(_ id: Int) -> String {
            "game.detail.\(id)"
        }

        #if MAIN_APP
        static func gameDetail(_ game: Game) -> String {
            gameDetail(ogsID(for: game))
        }

        private static func ogsID(for game: Game) -> Int {
            switch game.ID {
            case .OGS(let id):
                return id
            }
        }
        #endif

        static let gameBoard = "game.board"
        static let gameDisplayModePicker = "game.displayMode"
        static let gameAnalyzeToggle = "game.analyze"
        static let gameOptions = "game.options"
        static let gameZenEnter = "game.zen.enter"
        static let gameZenExit = "game.zen.exit"

        static func gameAnalysisPosition(
            baseMoveNumber: Int,
            movePath: [String]
        ) -> String {
            "game.analysis.position.\(baseMoveNumber).\(movePath.joined(separator: "-"))"
        }

        static let newGameOptionPicker = "newGame.option"
    }
}
