//
//  SurroundUITestContract.swift
//  Surround
//
//  Shared identifiers and fixture values for deterministic UI tests.
//

import Foundation

enum SurroundUITestContract {
    static let launchArgument = "--surround-ui-testing"
    static let preferencesSuite = "com.honganhkhoa.Surround.UITests"
    static let fixtureGameID = 26_268_404

    #if DEBUG && MAIN_APP
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
    #else
    static let isEnabled = false
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

        static func homeGame(_ id: Int) -> String {
            "home.game.\(id)"
        }

        static func gameDetail(_ id: Int) -> String {
            "game.detail.\(id)"
        }

        static let gameBoard = "game.board"
        static let gameOptions = "game.options"
        static let gameZenEnter = "game.zen.enter"
        static let gameZenExit = "game.zen.exit"
    }
}
