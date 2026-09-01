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
    static let compatibilityScreenshotLaunchArgument =
        "--surround-compatibility-screenshots"
    static let compatibilitySceneLaunchArgument =
        "--surround-compatibility-scene"
    static let compatibilityWidgetProofTokenLaunchArgument =
        "--surround-compatibility-widget-proof-token"
    static let compatibilityWidgetGameCountLaunchArgument =
        "--surround-compatibility-widget-game-count"
    static let catalystWindowSizeLaunchArgument =
        "--surround-catalyst-window-size"
    static let catalystDefaultWindowSizeLaunchArgument =
        "--surround-catalyst-default-window-size"
    static let appStoreScreenshotWidgetProofTokenLaunchArgument =
        "--surround-app-store-screenshot-widget-proof-token"
    static let screenshotWidgetFixtureCleanupLaunchArgument =
        "--clear-app-store-screenshot-widget-fixture"
    static let homeHistoryFailsOnceLaunchArgument =
        "--surround-home-history-fails-once"
    static let analysisDisabledLaunchArgument =
        "--surround-analysis-disabled"
    static let compactGameLayoutLaunchArgument =
        "--surround-compact-game-layout"
    static let homeBoardAlignmentLaunchArgument =
        "--surround-home-board-alignment"
    static let widgetDeepLinkRoutingLaunchArgument =
        "--surround-widget-deep-link-routing"
    static let attachedSoftwareKeyboardVisibleLaunchArgument =
        "--surround-attached-software-keyboard-visible"
    static let structuredChatFormatsLaunchArgument =
        "--surround-structured-chat-formats"
    static let preferencesSuite = "com.honganhkhoa.Surround.UITests"
    static let appStoreScreenshotWidgetGameCount = 3
    static let compatibilityWidgetGameCount = 4
    static let compatibilityWidgetGameID = 25_089_235
    static let fixtureGameID = 26_268_404
    static let widgetRoutingSecondGameID = 26_268_396
    static let widgetRoutingMissingGameID = 999_999_999
    static let widgetRoutingRESTDelayNanoseconds: UInt64 = 1_000_000_000
    static let homeHistoryRetryFixtureGameID = 18_759_438
    static let screenshotNextGameID = 18_759_438
    static let screenshotPrimaryGameID = 68_301_595
    static let conditionalMovesFixtureGameID = 62_050_416
    static let conditionalMovesFixtureRootMoveNumber = 60
    static let conditionalMovesFixturePaths = [
        ["..", "ll"],
        ["jj", "kj", "ji", "ki"],
        ["jj", "kj", "jk", "kk"],
    ]
    static let conditionalMovesFixtureConflictingPath = ["jj", "lj"]
    static let conditionalMovesFixtureBranchIDs =
        conditionalMovesFixturePaths.map {
            "\(conditionalMovesFixtureRootMoveNumber):\($0.joined())"
        }
    static let screenshotFixtureGameIDs = [
        screenshotPrimaryGameID,
        screenshotNextGameID,
        conditionalMovesFixtureGameID,
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
    static let screenshotConditionalMoveRootMoveNumber = 101
    static let screenshotConditionalMovePaths = [
        ["bo", "er", "eq", "dr", "fr", "br"],
        ["bo", "er", "dq", "dr", "bq", "br", "cp", "cr"],
    ]
    static let screenshotConditionalMoveBranchIDs =
        screenshotConditionalMovePaths.map {
            "\(screenshotConditionalMoveRootMoveNumber):\($0.joined())"
        }
    static let structuredChatTranslatedLineID =
        "ui-test-chat-translated"
    static let structuredChatTranslatedText =
        "/me Translated system announcement"
    static let structuredChatAnalysisLineID =
        "ui-test-chat-analysis"
    static let structuredChatAnalysisText =
        "/me Literal variation name"
    static let structuredChatReviewLineID = "ui-test-chat-review"
    static let structuredChatReviewID = 90_212_712
    static let structuredChatHiddenLineID = "ui-test-chat-hidden"
    static let structuredChatHiddenText = "Moderator fixture note"
    static let structuredChatThirdPersonLineID =
        "ui-test-chat-third-person"
    static let structuredChatThirdPersonText =
        "checks the third-person format"

    enum CompatibilityScene: String, CaseIterable {
        case welcome
        case home
        case publicGames = "public-games"
        case gameHistory = "game-history"
        case messagesInbox = "messages-inbox"
        case messageThread = "message-thread"
        case settings
        case about
        case thanks
        case supporter
        case browser
        case unsupportedGoogle = "unsupported-google"
        case activeGameBoard = "active-game-board"
        case gameAnalysis = "game-analysis"
        case zenMode = "zen-mode"
        case gameOptions = "game-options"
        case finishedGamePlayback = "finished-game-playback"
        case publicGameSpectator = "public-game-spectator"
        case quickMatch = "quick-match"
        case openChallenges = "open-challenges"
        case rengoOpenChallenges = "rengo-open-challenges"
        case customGame = "custom-game"
        case opponentPicker = "opponent-picker"
        case advancedTime = "advanced-time"
        case advancedRules = "advanced-rules"
        case waitingGames = "waiting-games"
        case preferredSettings = "preferred-settings"
        case preferredSettingEditor = "preferred-setting-editor"
        case gameChat = "game-chat"
    }

    #if DEBUG && MAIN_APP
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static var isCapturingAppStoreScreenshots: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains(screenshotLaunchArgument)
    }

    static var isCapturingCompatibilityScreenshots: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains(
                compatibilityScreenshotLaunchArgument
            )
    }

    static var simulatesHomeHistoryFailureOnce: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains(
                homeHistoryFailsOnceLaunchArgument
            )
    }

    static var simulatesAnalysisDisabled: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains(
                analysisDisabledLaunchArgument
            )
    }

    static var forcesCompactGameLayout: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains(
                compactGameLayoutLaunchArgument
            )
    }

    static var simulatesHomeBoardAlignment: Bool {
        isCapturingCompatibilityScreenshots
            && ProcessInfo.processInfo.arguments.contains(
                homeBoardAlignmentLaunchArgument
            )
    }

    static var simulatesWidgetDeepLinkRouting: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains(
                widgetDeepLinkRoutingLaunchArgument
            )
    }

    static var simulatesAttachedSoftwareKeyboardVisible: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains(
                attachedSoftwareKeyboardVisibleLaunchArgument
            )
    }

    static var addsStructuredChatFormatsToCompatibilityFixture: Bool {
        isCapturingCompatibilityScreenshots
            && !isCapturingAppStoreScreenshots
            && ProcessInfo.processInfo.arguments.contains(
                structuredChatFormatsLaunchArgument
            )
    }

    static var compatibilityScene: CompatibilityScene? {
        guard isCapturingCompatibilityScreenshots else {
            return nil
        }
        let arguments = ProcessInfo.processInfo.arguments
        guard let argumentIndex = arguments.firstIndex(
            of: compatibilitySceneLaunchArgument
        ),
        arguments.indices.contains(argumentIndex + 1) else {
            preconditionFailure(
                "\(compatibilitySceneLaunchArgument) requires a scene raw value."
            )
        }
        guard let scene = CompatibilityScene(
            rawValue: arguments[argumentIndex + 1]
        ) else {
            preconditionFailure(
                "Unknown compatibility screenshot scene: "
                    + arguments[argumentIndex + 1]
            )
        }
        return scene
    }

    static var catalystWindowSize: CGSize? {
        guard isEnabled else { return nil }

        let arguments = ProcessInfo.processInfo.arguments
        guard let argumentIndex = arguments.firstIndex(
            of: catalystWindowSizeLaunchArgument
        ) else {
            return nil
        }
        guard arguments.indices.contains(argumentIndex + 1) else {
            preconditionFailure(
                "\(catalystWindowSizeLaunchArgument) requires WIDTHxHEIGHT."
            )
        }

        let components = arguments[argumentIndex + 1].split(separator: "x")
        guard components.count == 2,
              let width = Double(components[0]),
              let height = Double(components[1]),
              width > 0,
              height > 0 else {
            preconditionFailure(
                "Invalid Catalyst window size: \(arguments[argumentIndex + 1])."
            )
        }
        return CGSize(width: width, height: height)
    }

    static var shouldUseCatalystDefaultWindowSize: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains(
                catalystDefaultWindowSizeLaunchArgument
            )
    }

    static var compatibilityWidgetProofToken: String? {
        guard isCapturingCompatibilityScreenshots else {
            return nil
        }
        let arguments = ProcessInfo.processInfo.arguments
        guard let argumentIndex = arguments.firstIndex(
            of: compatibilityWidgetProofTokenLaunchArgument
        ) else {
            return nil
        }
        guard arguments.indices.contains(argumentIndex + 1),
              let token = UUID(uuidString: arguments[argumentIndex + 1]) else {
            preconditionFailure(
                "\(compatibilityWidgetProofTokenLaunchArgument) requires a UUID value."
            )
        }
        return token.uuidString
    }

    static var compatibilityWidgetFixtureGameCount: Int {
        guard isCapturingCompatibilityScreenshots else {
            return compatibilityWidgetGameCount
        }
        let arguments = ProcessInfo.processInfo.arguments
        guard let argumentIndex = arguments.firstIndex(
            of: compatibilityWidgetGameCountLaunchArgument
        ) else {
            return compatibilityWidgetGameCount
        }
        guard arguments.indices.contains(argumentIndex + 1),
              let count = Int(arguments[argumentIndex + 1]),
              (1...6).contains(count) else {
            preconditionFailure(
                "\(compatibilityWidgetGameCountLaunchArgument) requires a value from 1 through 6."
            )
        }
        return count
    }

    static var appStoreScreenshotWidgetProofToken: String? {
        guard isCapturingAppStoreScreenshots else {
            return nil
        }
        let arguments = ProcessInfo.processInfo.arguments
        guard let argumentIndex = arguments.firstIndex(
            of: appStoreScreenshotWidgetProofTokenLaunchArgument
        ) else {
            return nil
        }
        guard arguments.indices.contains(argumentIndex + 1),
              let token = UUID(uuidString: arguments[argumentIndex + 1]) else {
            preconditionFailure(
                "\(appStoreScreenshotWidgetProofTokenLaunchArgument) requires a UUID value."
            )
        }
        return token.uuidString
    }

    static var isClearingAppStoreScreenshotWidgetFixture: Bool {
        ProcessInfo.processInfo.arguments.contains(
            screenshotWidgetFixtureCleanupLaunchArgument
        )
    }
    #else
    static let isEnabled = false
    static let isCapturingAppStoreScreenshots = false
    static let isCapturingCompatibilityScreenshots = false
    static let simulatesHomeBoardAlignment = false
    static let simulatesWidgetDeepLinkRouting = false
    static let compatibilityWidgetFixtureGameCount =
        compatibilityWidgetGameCount
    static let compatibilityScene: CompatibilityScene? = nil
    static let compatibilityWidgetProofToken: String? = nil
    static let appStoreScreenshotWidgetProofToken: String? = nil
    static let isClearingAppStoreScreenshotWidgetFixture = false
    #endif

    enum AccessibilityID {
        static let catalystWindowGeometry = "window.catalyst.geometry"
        static let catalystFreshWindowGeometry =
            "window.catalyst.geometry.fresh-default"

        static let navigationHome = "navigation.home"
        static let navigationPublicGames = "navigation.publicGames"
        static let navigationMessages = "navigation.messages"
        static let navigationSettings = "navigation.settings"
        static let navigationAbout = "navigation.about"
        static let navigationBrowser = "navigation.browser"

        static let screenHome = "screen.home"
        static let screenGameHistory = "screen.gameHistory"
        static let screenPublicGames = "screen.publicGames"
        static let screenMessages = "screen.messages"
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

        static func homeGamePlayerInfo(_ id: Int) -> String {
            "\(homeGame(id)).playerInfo"
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

        static let homeHistoryLoading = "home.history.loading"
        static let homeHistoryError = "home.history.error"
        static let homeHistoryRetry = "home.history.retry"
        static let homeHistoryEmpty = "home.history.empty"
        static let homeHistoryViewAll = "home.history.viewAll"
        static let openingGame = "home.openingGame"
        static let openGameRetry = "home.openGame.retry"

        static let gameHistoryLoading = "gameHistory.loading"
        static let gameHistoryError = "gameHistory.error"
        static let gameHistoryRetry = "gameHistory.retry"
        static let gameHistoryEmpty = "gameHistory.empty"

        static let homeNewGame = "home.newGame"
        static let homePreferredSettings = "home.preferredSettings"

        static let quickMatchMode = "quickMatch.mode"
        static let quickMatchRecap = "quickMatch.recap"
        static let quickMatchFind = "quickMatch.find"
        static let quickMatchCancel = "quickMatch.cancel"
        static let quickMatchSearching = "quickMatch.searching"
        static let quickMatchConnectionReason = "quickMatch.connectionReason"
        static let quickMatchWaitingBanner = "quickMatch.waitingBanner"
        static let quickMatchHandicap = "quickMatch.handicap"
        static let quickMatchMatchingChallenges =
            "quickMatch.matchingChallenges"

        static func quickMatchBoardSize(_ size: Int) -> String {
            "quickMatch.board.\(size)"
        }

        static func quickMatchClock(speed: String, system: String) -> String {
            "quickMatch.clock.\(speed).\(system)"
        }

        static func quickMatchOpenChallenge(_ id: Int) -> String {
            "quickMatch.openChallenge.\(id)"
        }

        static func waitingGamesAutomatchEntry(_ uuid: String) -> String {
            "waitingGames.automatchEntry.\(uuid)"
        }

        static func waitingGamesAutomatchWithdraw(_ uuid: String) -> String {
            "waitingGames.automatchWithdraw.\(uuid)"
        }

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
        static func homeConditionalButton(_ id: Int) -> String {
            "home.game.\(id).conditional.button"
        }
        static func homeConditionalPopover(_ id: Int) -> String {
            "home.game.\(id).conditional.popover"
        }
        static func homeConditionalPopoverTitle(_ id: Int) -> String {
            "home.game.\(id).conditional.popover.title"
        }
        static func homeConditionalVariation(
            _ id: Int,
            branchID: String
        ) -> String {
            "home.game.\(id).conditional.variation.\(branchID)"
        }
        static let gameConditionalButton = "game.conditional.button"
        static let gameConditionalPopover = "game.conditional.popover"
        static let gameConditionalPopoverTitle =
            "game.conditional.popover.title"
        static func gameConditionalVariation(_ branchID: String) -> String {
            "game.conditional.variation.\(branchID)"
        }
        static let gameDisplayModePicker = "game.displayMode"
        static let gameAnalyzeToggle = "game.analyze"
        static let gameAnalyzeControlBar = "game.analyze.controls"
        static let gameAnalyzeTreeScroll = "game.analyze.tree.scroll"
        static let gameAnalyzeActionsMenu = "game.analyze.actions"
        static let gameAnalyzeMarkerMenu = "game.analyze.markers"
        static func gameAnalyzeMarkerTool(_ tool: String) -> String {
            "game.analyze.markers.\(tool)"
        }
        static let gameAnalyzePreviousBranch = "game.analyze.previousBranch"
        static let gameAnalyzeNextBranch = "game.analyze.nextBranch"
        static let gameAnalyzeBackToFork = "game.analyze.backToFork"
        static let gameAnalyzePrevious = "game.analyze.previous"
        static let gameAnalyzeNext = "game.analyze.next"
        static let gameAnalyzeShare = "game.analyze.share"
        static let gameAnalyzeAddConditional = "game.analyze.addConditional"
        static let gameAnalyzeRemoveConditional =
            "game.analyze.removeConditional"
        static let gameAnalyzeQuickAddConditional =
            "game.analyze.quickAddConditional"
        static let gameAnalyzeQuickRemoveConditional =
            "game.analyze.quickRemoveConditional"
        static let gameAnalyzeDeleteBranch = "game.analyze.deleteBranch"
        static let gameAnalyzeConfirmDelete = "game.analyze.confirmDelete"
        static let gameChatChannelPicker = "game.chat.channelPicker"
        static let gameChatChannelMain = "game.chat.channel.main"
        static let gameChatChannelMalkovich = "game.chat.channel.malkovich"
        static let gameChatChannelPersonal = "game.chat.channel.personal"
        static let gameChatLog = "game.chat.log"
        static func gameChatMove(_ moveNumber: Int) -> String {
            "game.chat.move.\(moveNumber)"
        }
        static func gameChatLine(_ id: String) -> String {
            "game.chat.line.\(id)"
        }
        static let gameChatInput = "game.chat.input"
        static let gameChatSend = "game.chat.send"
        static let gameVariationSharePreview = "game.variationShare.preview"
        static let gameVariationShareStatus = "game.variationShare.status"
        static let gameVariationShareCancel = "game.variationShare.cancel"
        static let gameChatBoardHide = "game.chat.board.hide"
        static let gameChatBoardShow = "game.chat.board.show"
        static let gameOptions = "game.options"
        static let gameActionsMenu = "game.actions"
        static let gameNext = "game.next"
        static let gameRematch = "game.rematch"
        static let gameRematchOpponent = "game.rematch.opponent"
        static let gameResign = "game.resign"
        static let gameZenEnter = "game.zen.enter"
        static let gameZenExit = "game.zen.exit"

        static func compatibilityScreen(
            _ scene: CompatibilityScene
        ) -> String {
            "screen.compatibility.\(scene.rawValue)"
        }

        static func gameAnalysisPosition(
            baseMoveNumber: Int,
            movePath: [String]
        ) -> String {
            "game.analysis.position.\(baseMoveNumber).\(movePath.joined(separator: "-"))"
        }

        static let newGameOptionPicker = "newGame.option"
    }
}
