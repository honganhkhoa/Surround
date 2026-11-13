//
//  SurroundUITestContract.swift
//  Surround
//
//  Shared identifiers and fixture values for deterministic UI tests.
//

import Foundation

enum SurroundUITestContract {
    static let launchArgument = "--surround-ui-testing"
    static let sceneActivationLaunchArgument = "--surround-scene-activation"
    /// DEBUG: shows and logs each window's connection status from the real
    /// socket and network path (in-app notices). Production root only.
    static let connectionStatusProbeLaunchArgument = "--surround-connection-status-probe"
    static let animationDiagnosticsLaunchArgument =
        "--surround-animation-diagnostics"
    static let screenshotLaunchArgument = "--surround-app-store-screenshots"
    static let compatibilityScreenshotLaunchArgument =
        "--surround-compatibility-screenshots"
    static let compatibilitySceneLaunchArgument =
        "--surround-compatibility-scene"
    static let gameDetailClockStateLaunchArgument = "--surround-game-detail-clock-state"
    static let gameDetailPlayersLaunchArgument = "--surround-game-detail-players"
    /// DEBUG review switch: the design fixture opens with the socket down
    /// (`.reconnecting`) and its game clock ticking locally each second, as
    /// the service's timer can while disconnected.
    static let gameDetailSocketDownLaunchArgument = "--surround-game-detail-socket-down"
    static let gameDetailDesignArtboardLaunchArgument = "--surround-game-detail-design-artboard"
    /// DEBUG toolbar-item probe: Game Detail's Active games slot shows
    /// GameControlProbeItem.
    static let gameControlProbeLaunchArgument = "--surround-notices-placeholder-game-control"
    static let gameControlProbeVariantLaunchArgument = "--surround-notices-placeholder-game-control-variant"
    static let gameControlProbeSizeLaunchArgument = "--surround-notices-placeholder-game-control-size"
    static let gameDetailDesignAnalysisBaseMoveNumber = 38
    static let gameDetailDesignAnalysisSelectedMoveNumber = 41
    static let gameDetailDesignAnalysisSelectedRow = 10
    static let gameDetailDesignAnalysisSelectedColumn = 12
    static let gameDetailDesignChatDraft = "Probably not, the hane at 2-2 kills it"

    /// A separate, explicit fixture contract for the October 15 Game Detail design.
    /// App Store captures must never inherit these illustrative game snapshots.
    static func gameDetailDesignArtboard(in arguments: [String]) -> Int? {
        guard arguments.contains(launchArgument),
              arguments.contains(compatibilityScreenshotLaunchArgument),
              !arguments.contains(screenshotLaunchArgument),
              let index = arguments.firstIndex(of: gameDetailDesignArtboardLaunchArgument),
              arguments.indices.contains(index + 1),
              let artboard = Int(arguments[index + 1]),
              (1...91).contains(artboard) else { return nil }
        return artboard
    }
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
    static let unavailableProfileLaunchArgument =
        "--surround-profile-unavailable"
    static let profileSectionsUnavailableLaunchArgument =
        "--surround-profile-sections-unavailable"
    static let profileContentLaunchArgument = "--surround-profile-content"
    static let profileBiographyLaunchArgument = "--surround-profile-biography"
    static let profileShortHistoryLaunchArgument = "--surround-profile-short-history"
    static let historyPreviewUnavailableLaunchArgument = "--surround-history-preview-unavailable"
    static let friendshipLaunchArgument = "--surround-friendship"
    static let friendshipFailsOnceLaunchArgument = "--surround-friendship-fails-once"
    static let friendshipGatedResponseLaunchArgument = "--surround-friendship-gated-response"
    static let emptyMessagesLaunchArgument = "--surround-empty-messages"
    static let messagesContentLaunchArgument = "--surround-messages-content"
    static let messagesMarketingLaunchArgument = "--surround-messages-marketing"
    static let messagesOverflowLaunchArgument = "--surround-messages-overflow"
    static let messagesShortHistoryLaunchArgument = "--surround-messages-short-history"
    static let messagesDelayedHistoryLaunchArgument = "--surround-messages-delayed-history"
    static let messagesInitialOpeningLaunchArgument = "--surround-messages-initial-opening"
    static let messagesIncomingLaunchArgument = "--surround-messages-incoming"
    static let messagesLoadingLaunchArgument = "--surround-messages-loading"

    enum MessagesLoadingUITestAction {
        case beginRead, finishFriends, finishRequests, failRead
    }
    static let messagesShortHistoryLatestText = "Short conversation reference 2/2. This incoming reply also wraps to several lines. Keep the final line visible above the composer after opening the conversation."
    static let messagesVideoHistoryLatestText = "[surround way surround-e2e-browser-msg-20261002t123634z-def9830c 2/2] duo reply and same-account iPad test message. echo check."
    static let messagesIncomingFirstText = "Offline incoming reply 1/2. A new message should follow the latest conversation while keeping the composer usable."
    static let messagesIncomingLatestText = "Offline incoming reply 2/2. The latest reply stays above the composer; a reader of older history keeps that reading position."
    static let appearanceLaunchArgument = "--surround-ui-appearance"
    /// Starts the isolated UI-test preferences suite with "Hide ranks and
    /// ratings" on. It never reaches a signed-in app's preferences.
    static let hidesRankLaunchArgument = "--surround-ui-hides-rank"
    /// Starts the isolated UI-test preferences suite with a Game Detail
    /// theme selected: `--surround-ui-theme nebulaPearl`.
    static let themeLaunchArgument = "--surround-ui-theme"
    /// Starts the isolated preferences suite with the theme on Games only.
    static let themeGamesOnlyLaunchArgument = "--surround-ui-theme-games-only"
    /// Starts the isolated preferences suite with Home in this layout:
    /// `--surround-ui-home-display-mode compact` or `full`.
    static let homeDisplayModeLaunchArgument = "--surround-ui-home-display-mode"
    /// Ticks every fixture game's clock each second, as OGSService's timer
    /// does for connected games, so performance runs see live clocks.
    static let fixtureClockTicksLaunchArgument = "--surround-fixture-clock-ticks"
    /// Caps Home's Appearance popover at this many points, as a short screen
    /// or window does: `--surround-ui-appearance-popover-height 360`.
    static let appearancePopoverHeightLaunchArgument = "--surround-ui-appearance-popover-height"
    static let holdQuickMatchAcknowledgementsLaunchArgument =
        "--surround-hold-quick-match-acknowledgements"
    static let analysisDisabledLaunchArgument =
        "--surround-analysis-disabled"
    static let compactGameLayoutLaunchArgument =
        "--surround-compact-game-layout"
    static let homeBoardAlignmentLaunchArgument =
        "--surround-home-board-alignment"
    /// Adds Home rows in states the plain fixture lacks: low time, paused,
    /// stone removal, no speed tag, and an unknown clock.
    static let homeStatesLaunchArgument = "--surround-home-states"
    /// No active games, one finished game: Home's empty message with history.
    static let homeFinishedOnlyLaunchArgument = "--surround-home-finished-only"
    /// Replaces a plain offline journey's Activity data with one fixed state,
    /// game 26268404 kept: `--surround-activity-state several`. ActivityFixtures.swift.
    static let activityStateLaunchArgument = "--surround-activity-state"
    /// `frozen` (default): no fixture time moves. `running`: time passes from the
    /// launch second; add `--surround-fixture-clock-ticks` to move clocks too.
    static let activityClockLaunchArgument = "--surround-activity-clock"
    /// `online` (default), or `offline`: an Activity state's socket starts down
    /// (`.reconnecting`), as after the connection is lost.
    static let activityConnectionLaunchArgument = "--surround-activity-connection"
    static let widgetDeepLinkRoutingLaunchArgument =
        "--surround-widget-deep-link-routing"
    static let liveGameBannerNavigationLaunchArgument =
        "--surround-live-game-banner-navigation"
    static let automatchRestorationLaunchArgument =
        "--surround-automatch-restoration"
    static let attachedSoftwareKeyboardVisibleLaunchArgument =
        "--surround-attached-software-keyboard-visible"
    static let structuredChatFormatsLaunchArgument =
        "--surround-structured-chat-formats"
    static let appReviewPresentationLaunchArgument =
        "--surround-app-review-presentation"
    /// DEBUG notices host probes (TESTING.md); any Debug run, with or without
    /// `--surround-ui-testing`.
    static let noticesPlaceholderBarLaunchArgument = "--surround-notices-placeholder-bar"
    static let noticesPlaceholderBarOrderLaunchArgument = "--surround-notices-placeholder-bar-order"
    static let noticesPlaceholderBarKeyboardLaunchArgument = "--surround-notices-placeholder-bar-keyboard"
    static let noticesForceCustomBarLaunchArgument = "--surround-notices-force-custom-bar"
    static let noticesTabBarMinimizeLaunchArgument = "--surround-notices-tab-bar-minimize"
    static let noticesPlaceholderNowLaunchArgument = "--surround-notices-placeholder-now"
    static let noticesPlaceholderSubtitleLaunchArgument = "--surround-notices-placeholder-subtitle"
    static let noticesNavigationBarMinimizeLaunchArgument = "--surround-notices-navigation-bar-minimize"
    static let preferencesSuite = "com.honganhkhoa.Surround.UITests"
    static let appStoreScreenshotWidgetGameCount = 3
    static let compatibilityWidgetGameCount = 4
    static let compatibilityWidgetGameID = 25_089_235
    static let fixtureGameID = 26_268_404
    static let profileFixtureOwnerID = 314_459
    static let profileFixtureOpponentID = 429_553
    static let profileFixturePickerFriendID = 801_001
    static let friendshipFixtureRequestPlayerIDs = [912_001, 912_002, 912_003]
    static let friendshipFixtureRequestUsernames = ["RiverWillow", "SilverHeron", "CloudPebble"]
    // Opt-in Messages fixtures stay behind the rejecting offline transports.
    // Sixty-four friends overflow the expanded grid even in a tall iPad inbox.
    static let messagesOverflowFriendIDs = Array(914_001...914_064)
    static let messagesOverflowHistoryCount = 50
    static let messagesOverflowRecentFriendID = 801_006

    static func messagesOverflowFriendUsername(index: Int) -> String {
        "OverflowFriend\(String(format: "%02d", index))"
    }

    static func messagesOverflowHistoryID(peerID: Int, index: Int) -> String {
        "messages-history-\(peerID)-\(index)"
    }

    static func messagesOverflowHistoryText(username: String, index: Int) -> String {
        "Offline history \(String(format: "%02d", index)) for \(username)\n"
            + "This older message remains in its own conversation.\n"
            + "Return here after changing peers or opening a profile."
    }
    static let profileFixtureActiveGameIDs = [91_001_001, 91_001_002, 91_001_003, 91_001_004]
    // Both the complete feed (12) and the pairwise feed (11) exceed a
    // ten-game page; the sixth game alone has a different opponent.
    static let profileFixtureHistoryGameIDs = Array(91_002_001...91_002_012)
    static let widgetRoutingSecondGameID = 26_268_396
    static let liveBannerCorrespondenceGameIDs = [26_268_398, 26_268_399]
    static let liveBannerHistoryGameID = 26_268_397
    static let restorationLiveChallengeID = 94_001
    static let widgetRoutingMissingGameID = 999_999_999
    static let widgetRoutingRESTDelayNanoseconds: UInt64 = 1_000_000_000
    static let homeHistoryRetryFixtureGameID = 18_759_438
    static let homeStatesLowTimeGameID = 91_003_001
    static let homeStatesPausedGameID = 91_003_002
    static let homeStatesStoneRemovalGameID = 91_003_003
    static let homeStatesNoSpeedGameID = 91_003_004
    static let homeStatesUnknownClockGameID = 91_003_005
    static let homeStatesUnknownClockScoringGameID = 91_003_006
    static let homeFinishedOnlyHistoryGameID = 91_003_007
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

    enum Appearance: String, CaseIterable {
        case light
        case dark
    }

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
        // Regression-only scene: start Analyze without a screenshot position.
        case initialGameAnalysis = "initial-game-analysis"
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

        var isNewGame: Bool {
            switch self {
            case .quickMatch, .openChallenges, .rengoOpenChallenges, .customGame:
                true
            default:
                false
            }
        }
    }

    enum ActivityFixtureState: String, CaseIterable {
        case nothingWaiting = "nothing-waiting", liveYourMove = "live-your-move"
        case liveTheirMove = "live-their-move", lowTime = "low-time", stoneRemoval = "stone-removal"
        case gameStarted = "game-started", challengeReceived = "challenge-received"
        case unusualChallenge = "unusual-challenge", searching, waiting
        case correspondenceYourMove = "correspondence-your-move", nothingLeads = "nothing-leads"
        case several, superchat, rematchOffered = "rematch-offered", rematchBothAsked = "rematch-both-asked"
    }

    enum ActivityFixtureClock: String {
        case frozen, running
    }

    enum ActivityFixtureConnection: String {
        case online, offline
    }

    /// Ids in the Activity fixture states (ActivityFixtures.swift).
    enum ActivityFixtureID {
        static let harborMistGameID = 91_004_001, startedGameID = 91_004_002, stoneRemovalGameID = 91_004_003
        static let correspondenceGameIDs = [91_004_004, 91_004_005, 91_004_006]
        static let usualChallengeID = 95_001, unusualChallengeID = 95_002
        static let correspondenceChallengeID = 95_003, rematchChallengeID = 95_004
        static let openChallengeID = 95_101, sentChallengeID = 95_201, rematchSentChallengeID = 95_202
        static let rengoChallengeID = 95_301
        /// The game an accepted challenge starts under `--surround-activity-actions`.
        static func acceptedGameID(_ challengeID: Int) -> Int { challengeID + 900_000 }
        static let liveQuickMatchUUID = "a1c7f100-0000-4000-8000-000000000001"
        static let correspondenceQuickMatchUUID = "a1c7f100-0000-4000-8000-000000000002"
        static let moderatorID = 916_002
        static let secondModeratorID = 916_003
    }

    #if DEBUG
    /// Darwin notifications standing in for OGS in offline UI-test runs:
    /// every window's service hears each one.
    enum SuperchatCommand: String, CaseIterable {
        case start = "com.honganhkhoa.Surround.debug.superchat.start"
        case end = "com.honganhkhoa.Surround.debug.superchat.end"
        case startSecond = "com.honganhkhoa.Surround.debug.superchat.start-second"
        case endSecond = "com.honganhkhoa.Surround.debug.superchat.end-second"
        /// The moderator's own echo (moderator_id is the user's id): never covers.
        case echo = "com.honganhkhoa.Surround.debug.superchat.echo"
        /// Every window's socket authenticates again and OGS confirms it,
        /// with no re-send: the cover lifts after the re-send window.
        case reconnect = "com.honganhkhoa.Surround.debug.superchat.reconnect"
    }
    /// `start@0,end@30,start@60`: the commands at those seconds after launch,
    /// for runs that can't post Darwin notifications (a device, the Mac).
    static let superchatDebugScriptLaunchArgument = "--surround-superchat-debug-script"
    #endif

    #if DEBUG && MAIN_APP
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static var isCapturingAppStoreScreenshots: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains(screenshotLaunchArgument)
    }

    static var testsAppReviewPresentation: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains(appReviewPresentationLaunchArgument)
    }

    static var isCapturingCompatibilityScreenshots: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains(
                compatibilityScreenshotLaunchArgument
            )
    }

    static var gameDetailDesignArtboard: Int? {
        gameDetailDesignArtboard(in: ProcessInfo.processInfo.arguments)
    }

    /// Opt-in review variants never change the default compatibility/App Store scenes.
    static var gameDetailClockState: String? {
        guard isCapturingCompatibilityScreenshots || isCapturingAppStoreScreenshots else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: gameDetailClockStateLaunchArgument),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static var simulatesGameDetailSocketDown: Bool {
        (isCapturingCompatibilityScreenshots || isCapturingAppStoreScreenshots)
            && ProcessInfo.processInfo.arguments.contains(gameDetailSocketDownLaunchArgument)
    }

    static var ticksFixtureClocks: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains(fixtureClockTicksLaunchArgument)
    }

    /// Comma-separated audit variants, usable with either offline capture route.
    static var gameDetailPlayers: Set<String> {
        guard isCapturingCompatibilityScreenshots || isCapturingAppStoreScreenshots else { return [] }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: gameDetailPlayersLaunchArgument),
              arguments.indices.contains(index + 1) else { return [] }
        return Set(arguments[index + 1].split(separator: ",").map(String.init))
    }

    static var appearancePopoverHeight: CGFloat? {
        guard isEnabled else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: appearancePopoverHeightLaunchArgument),
              arguments.indices.contains(index + 1),
              let height = Double(arguments[index + 1]), height.isFinite, height > 0 else { return nil }
        return CGFloat(height)
    }

    static var simulatesHomeHistoryFailureOnce: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains(
                homeHistoryFailsOnceLaunchArgument
            )
    }

    static var simulatesUnavailableProfile: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains(
                unavailableProfileLaunchArgument
            )
    }

    static var simulatesUnavailableProfileSections: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains(profileSectionsUnavailableLaunchArgument)
    }

    static var includesProfileContent: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains(profileContentLaunchArgument)
    }

    static var includesProfileBiography: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains(profileBiographyLaunchArgument)
    }

    static var usesShortProfileHistory: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains(profileShortHistoryLaunchArgument)
    }

    static var simulatesUnavailableHistoryPreview: Bool {
        includesProfileContent
            && ProcessInfo.processInfo.arguments.contains(historyPreviewUnavailableLaunchArgument)
    }

    static var includesMessagesContent: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains(messagesContentLaunchArgument)
    }

    /// Marketing captures use the real Messages inbox and conversation through
    /// this separate, opt-in compatibility launch, including the App Store scene.
    static var includesMessagesMarketing: Bool {
        isCapturingCompatibilityScreenshots
            && compatibilityScene == .messagesInbox
            && ProcessInfo.processInfo.arguments.contains(messagesMarketingLaunchArgument)
    }

    static var includesMessagesOverflow: Bool {
        includesMessagesContent
            && ProcessInfo.processInfo.arguments.contains(messagesOverflowLaunchArgument)
    }

    static var includesMessagesShortHistory: Bool {
        includesMessagesContent
            && ProcessInfo.processInfo.arguments.contains(messagesShortHistoryLaunchArgument)
    }

    static var includesMessagesDelayedHistory: Bool {
        includesMessagesShortHistory
            && ProcessInfo.processInfo.arguments.contains(messagesDelayedHistoryLaunchArgument)
    }

    static var includesMessagesIncoming: Bool {
        includesMessagesContent
            && ProcessInfo.processInfo.arguments.contains(messagesIncomingLaunchArgument)
    }

    static var includesMessagesLoading: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains(messagesLoadingLaunchArgument)
    }

    static var includesFriendshipRequests: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains(friendshipLaunchArgument)
    }

    static var simulatesFriendshipFailureOnce: Bool {
        includesFriendshipRequests && ProcessInfo.processInfo.arguments.contains(friendshipFailsOnceLaunchArgument)
    }

    static var gatesFriendshipResponse: Bool {
        includesFriendshipRequests && ProcessInfo.processInfo.arguments.contains(friendshipGatedResponseLaunchArgument)
    }

    static var appearanceOverride: Appearance? {
        guard isEnabled else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let argumentIndex = arguments.firstIndex(of: appearanceLaunchArgument) else {
            return nil
        }
        guard arguments.indices.contains(argumentIndex + 1),
              let appearance = Appearance(rawValue: arguments[argumentIndex + 1]) else {
            preconditionFailure("\(appearanceLaunchArgument) requires light or dark.")
        }
        return appearance
    }

    static var holdsQuickMatchAcknowledgements: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains(
                holdQuickMatchAcknowledgementsLaunchArgument
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

    static var simulatesHomeStates: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains(
                homeStatesLaunchArgument
            )
    }

    static var simulatesHomeFinishedOnly: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains(
                homeFinishedOnlyLaunchArgument
            )
    }

    static var simulatesWidgetDeepLinkRouting: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains(
                widgetDeepLinkRoutingLaunchArgument
            )
    }

    static var simulatesLiveGameBannerNavigation: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains(
                liveGameBannerNavigationLaunchArgument
            )
    }

    /// Holds the automatch restoration window open so the offline tests can
    /// check what Quick Match allows while reconciliation is still in flight.
    static var simulatesAutomatchRestoration: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains(
                automatchRestorationLaunchArgument
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

    static let noticesHostProbe: NoticesHostProbe? = {
        do { return try NoticesHostProbe.parse(ProcessInfo.processInfo.arguments) }
        catch { preconditionFailure("Invalid notices host probe flags: \(error)") }
    }()

    /// The launch's Activity opener, read once. A malformed flag, or one
    /// without a UI-testing Activity state, stops the launch.
    static let activityOpen: ActivityOpen? = {
        let open: ActivityOpen?
        do { open = try parseActivityOpen(ProcessInfo.processInfo.arguments) }
        catch { preconditionFailure("\(error)") }
        guard let open else { return nil }
        guard ActivityFixtures.selected != nil else {
            preconditionFailure("\(activityOpenLaunchArgument) needs \(launchArgument) with \(activityStateLaunchArgument).")
        }
        return open
    }()

    /// The launch's answers to Accept, Reject and Withdraw, read once. A
    /// malformed flag, or one without a UI-testing Activity state, stops the
    /// launch.
    static let activityActions: ActivityActions? = {
        let actions: ActivityActions?
        do { actions = try parseActivityActions(ProcessInfo.processInfo.arguments) }
        catch { preconditionFailure("\(error)") }
        guard let actions else { return nil }
        guard ActivityFixtures.selected != nil else {
            preconditionFailure("\(activityActionsLaunchArgument) needs \(launchArgument) with \(activityStateLaunchArgument).")
        }
        return actions
    }()
    #else
    static let isEnabled = false
    static let isCapturingAppStoreScreenshots = false
    static let isCapturingCompatibilityScreenshots = false
    static let gameDetailDesignArtboard: Int? = nil
    static let simulatesGameDetailSocketDown = false
    static let ticksFixtureClocks = false
    static let simulatesUnavailableProfile = false
    static let simulatesUnavailableProfileSections = false
    static let includesProfileContent = false
    static let usesShortProfileHistory = false
    static let simulatesUnavailableHistoryPreview = false
    static let includesFriendshipRequests = false
    static let simulatesFriendshipFailureOnce = false
    static let gatesFriendshipResponse = false
    static let appearanceOverride: Appearance? = nil
    static let holdsQuickMatchAcknowledgements = false
    static let simulatesHomeBoardAlignment = false
    static let simulatesHomeStates = false
    static let simulatesHomeFinishedOnly = false
    static let simulatesWidgetDeepLinkRouting = false
    static let compatibilityWidgetFixtureGameCount =
        compatibilityWidgetGameCount
    static let compatibilityScene: CompatibilityScene? = nil
    static let compatibilityWidgetProofToken: String? = nil
    static let appStoreScreenshotWidgetProofToken: String? = nil
    static let isClearingAppStoreScreenshotWidgetFixture = false
    static let testsAppReviewPresentation = false
    static let appearancePopoverHeight: CGFloat? = nil
    #endif

    enum AccessibilityID {
        static let appReviewContext = "fixture.app-review.context"
        static let appReviewPendingToggle = "fixture.app-review.pending-toggle"
        static func appReviewHostedCoordinator(_ root: String) -> String {
            "fixture.app-review.hosted-coordinator.\(root)"
        }
        static let catalystWindowGeometry = "window.catalyst.geometry"
        static let catalystFreshWindowGeometry =
            "window.catalyst.geometry.fresh-default"

        static let navigationHome = "navigation.home"
        static let navigationPublicGames = "navigation.publicGames"
        static let navigationMessages = "navigation.messages"
        static let navigationProfile = "navigation.profile"
        static let navigationSettings = "navigation.settings"
        static let navigationAbout = "navigation.about"
        static let navigationBrowser = "navigation.browser"

        static let screenHome = "screen.home"
        static let screenGameHistory = "screen.gameHistory"
        static let screenPublicGames = "screen.publicGames"
        static let screenMessages = "screen.messages"
        static let screenSettings = "screen.settings"
        static let screenPlayerProfile = "screen.player-profile"
        static let profileLoaded = "profile.loaded"
        static let profileBiographySummary = "profile.biography.summary"
        static let profileAbout = "profile.about"
        static let screenPlayerAbout = "screen.player-about"
        static let profileBiographyContent = "profile.biography.content"
        static let profileRatingKey = "profile.rating-key"
        static let profileIdentity = "profile.identity"
        static let profileLoading = "profile.loading"
        static let profileError = "profile.error"
        static let profileRetry = "profile.retry"
        static let profileChallenge = "profile.challenge"
        static let profileMessage = "profile.message"
        static let profileFriendshipAction = "profile.friendship.action"
        static let profileFriendshipError = "profile.friendship.error"
        static let profileFriendshipRetry = "profile.friendship.retry"
        static let profileFriendshipLoading = "profile.friendship.loading"
        static let profileFriendRequest = "profile.friend-request"
        static let profileRemoveFriend = "profile.friendship.remove"
        static let friendshipRemoveConfirm = "friendship.remove.confirm"
        static let friendshipReleaseResponse = "fixture.friendship.release-response"
        static let messagesLoadingStartRead = "fixture.messages.start-read"
        static let messagesLoadingEndFriends = "fixture.messages.end-friends"
        static let messagesLoadingEndRequests = "fixture.messages.end-requests"
        static let messagesLoadingFailRead = "fixture.messages.fail-read"
        static let messagesLoadingReleaseSearch = "fixture.messages.release-search"
        static let friendshipRejectNotify = "friendship.reject.notify"
        static let friendshipRejectQuietly = "friendship.reject.quietly"
        static let accountMenu = "home.account-menu"
        static let accountMenuProfile = "account.profile"
        static let accountMenuSettings = "account.settings"
        static let accountMenuLogout = "account.logout"

        static func friendRequestProfile(_ playerID: Int) -> String {
            "friend-request.profile.\(playerID)"
        }

        static func friendRequestAccept(_ playerID: Int) -> String {
            "friend-request.accept.\(playerID)"
        }

        static func friendRequestReject(_ playerID: Int) -> String {
            "friend-request.reject.\(playerID)"
        }

        static func friendRequestBusy(_ playerID: Int) -> String {
            "friend-request.busy.\(playerID)"
        }

        static func friendRequestError(_ playerID: Int) -> String {
            "friend-request.error.\(playerID)"
        }

        static func friendRequestRetry(_ playerID: Int) -> String {
            "friend-request.retry.\(playerID)"
        }

        /// The result an accepted or rejected request shows in its inbox row.
        static func friendRequestResult(_ playerID: Int) -> String {
            "friend-request.result.\(playerID)"
        }

        /// View profile, under an accepted request's result.
        static func friendRequestViewProfile(_ playerID: Int) -> String {
            "friend-request.view-profile.\(playerID)"
        }
        static let profileSettingsEntry = "profile.entry.settings"
        static let profileEdit = "profile.edit"
        static let profileShare = "profile.share"
        static let profileConversation = "profile.conversation"
        static let profileSelectOpponent = "profile.select-opponent"
        static let profileChallengeWithSettings = "profile.challenge-with-settings"
        static let profileBannerAvatarPrefix = "profile.entry.banner.avatar."
        static let privateMessageComposer = "messages.composer"

        /// The moderator superchat cover (SuperchatCover.swift).
        static let superchatCover = "superchat.cover"
        static let superchatCoverStatus = "superchat.cover.status"
        static let superchatCoverTitle = "superchat.cover.title"
        static let superchatCoverSubtitle = "superchat.cover.subtitle"
        static let superchatCoverReply = "superchat.cover.reply"
        static let superchatCoverSend = "superchat.cover.send"
        static let superchatCoverEnded = "superchat.cover.ended"
        static let superchatCoverDone = "superchat.cover.done"
        static let messagesSuperchatEnded = "messages.superchatEnded"
        static func superchatCoverModerator(_ id: Int) -> String { "superchat.cover.moderator.\(id)" }
        static func superchatCoverLiveGame(_ id: Int) -> String { "superchat.cover.liveGame.\(id)" }

        /// The Activity list (ActivityListView.swift). Rows and their
        /// controls take the item's id as a string, such as "challenge-95001"
        /// or "waiting-open-95101": this file also builds into the widget.
        static let activityList = "activity.list"
        static let activityEmpty = "activity.empty"
        static let activityAllMessages = "activity.allMessages"
        static let activityDone = "activity.done"
        /// "Reconnecting…", or "Can’t reach OGS" with its Retry.
        static let activityStatus = "activity.status"
        static let activityStatusRetry = "activity.status.retry"
        /// The same line above the composer of a conversation the list pushed.
        static let activityConversationStatus = "activity.conversation.status"
        static let activityConversationStatusRetry = "activity.conversation.status.retry"
        enum ActivityRowControl: String {
            case accept, reject, view, withdraw, openGame, retry
        }
        /// `liveGames`, `challengesReceived`, `waiting`, `correspondence` or `messages`.
        static func activitySection(_ name: String) -> String { "activity.section.\(name)" }
        static func activityRow(_ itemID: String) -> String { "activity.row.\(itemID)" }
        static func activityRow(_ itemID: String, _ control: ActivityRowControl) -> String {
            "activity.row.\(itemID).\(control.rawValue)"
        }
        /// A row's result or failure line, which replaces its actions.
        static func activityRowResult(_ itemID: String) -> String { "activity.row.\(itemID).result" }

        static let profileRengoMenuPrefix = "profile.menu.rengo."
        static let profileActiveGames = "profile.active-games"
        static let profileActiveGamesRetry = "profile.active-games.retry"
        static let profileActiveGamesLoading = "profile.active-games.loading"
        static let profileAllActiveGames = "profile.all-active-games"
        static let profileGameHistory = "profile.game-history"
        static let profileAllHistory = "profile.all-history"
        static let profileHeadToHead = "profile.head-to-head"
        static let profileHeadToHeadRetry = "profile.head-to-head.retry"
        static let profileHeadToHeadLoading = "profile.head-to-head.loading"
        static let profileHeadToHeadSummary = "profile.head-to-head-summary"
        static let profileHeadToHeadHistory = "profile.head-to-head-history"
        static let screenProfileActiveGames = "screen.profile-active-games"
        static let screenProfileGameHistory = "screen.profile-game-history"
        static let profileRatings = "profile.ratings"
        static let profileRatingMode = "profile.rating-mode"

        static func profileActiveGame(_ gameID: Int) -> String {
            "profile.active-game.\(gameID)"
        }

        static func profileHistoryGame(_ gameID: Int) -> String {
            "profile.history-game.\(gameID)"
        }

        static func gameHistoryBoardLoading(_ gameID: Int) -> String {
            "gameHistory.board.loading.\(gameID)"
        }

        static func gameHistoryBoardUnavailable(_ gameID: Int) -> String {
            "gameHistory.board.unavailable.\(gameID)"
        }

        static func gameHistoryBoardRetry(_ gameID: Int) -> String {
            "gameHistory.board.retry.\(gameID)"
        }

        static func profileHeadToHeadRecent(_ gameID: Int) -> String {
            "profile.head-to-head-recent.\(gameID)"
        }

        static func profileRatingCategory(_ category: String) -> String {
            "profile.rating-category.\(category)"
        }

        static func privateMessageRow(_ playerID: Int) -> String {
            "messages.row.\(playerID)"
        }

        static func profileGameMenuEntry(_ gameID: Int, _ playerID: Int) -> String {
            "profile.entry.game-menu.\(gameID).\(playerID)"
        }

        static func profileChallengeEntry(_ challengeID: some CustomStringConvertible, _ playerID: Int) -> String {
            "profile.entry.challenge.\(challengeID).\(playerID)"
        }

        static func profileChallengeAvatarEntry(_ challengeID: some CustomStringConvertible, _ playerID: Int) -> String {
            "profile.entry.challenge-avatar.\(challengeID).\(playerID)"
        }

        static func profileRengoEntry(_ challengeID: some CustomStringConvertible, _ playerID: Int) -> String {
            "profile.entry.rengo.\(challengeID).\(playerID)"
        }

        static func profileRengoMenu(_ challengeID: some CustomStringConvertible, _ playerID: Int) -> String {
            "\(profileRengoMenuPrefix)\(challengeID).\(playerID)"
        }

        static func profileMessageToolbarEntry(_ playerID: Int) -> String {
            "profile.entry.message-toolbar.\(playerID)"
        }

        static func profileMessageMenuEntry(_ playerID: Int) -> String {
            "profile.entry.message-menu.\(playerID)"
        }
        static let screenOpponentPicker = "screen.opponent-picker"
        static let opponentSearch = "opponent.search"
        static let customGameName = "customGame.name"
        static let customGameSpeed = "customGame.speed"
        static let customGameOpponentMode = "customGame.opponent-mode"
        static let customGameOpponent = "customGame.opponent"

        static func opponentSelection(_ id: Int) -> String {
            "opponent.select.\(id)"
        }

        static func profileBannerAvatarEntry(_ id: Int) -> String {
            "\(profileBannerAvatarPrefix)\(id)"
        }

        static func profileBannerNameEntry(_ id: Int) -> String {
            "profile.entry.banner.name.\(id)"
        }

        static func profileChatEntry(_ id: String) -> String {
            "profile.entry.chat.\(id)"
        }

        static func profilePickerEntry(_ id: Int) -> String {
            "profile.entry.picker.\(id)"
        }
        static let screenAbout = "screen.about"
        static let aboutWriteReview = "about.writeReview"
        static let screenBrowser = "screen.browser"
        static let screenNewGame = "screen.newGame"
        static let screenOpenChallenges = "screen.openChallenges"
        static let screenCustomGame = "screen.customGame"
        static let screenGameOptions = "screen.gameOptions"
        static let screenPreferredSettings = "screen.preferredSettings"

        static func themeOption(_ theme: String) -> String {
            "theme.option.\(theme)"
        }
        /// A tile's preview square; hidden from VoiceOver, listed for geometry.
        static func themePreview(_ theme: String) -> String {
            "theme.preview.\(theme)"
        }
        static let themeScope = "theme.scope"

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
        /// Home's Appearance button.
        static let homeAppearance = "home.appearance"
        /// The Compact/Large display mode inside Appearance's popover.
        static let homeDisplayMode = "home.displayMode"
        static let homeFirstRun = "home.firstRun"
        static let homeSkeleton = "home.skeleton"
        /// Home sections: live, userTurn, opponentTurn and history.
        static func homeSection(_ id: String) -> String {
            "home.section.\(id)"
        }
        static let newGameClose = "newGame.close"
        /// New game's pending Rengo link, which opens Activity in its stack.
        static let newGameRengoWaiting = "newGame.rengoWaiting"
        /// Home's Searching card, which opens Activity.
        static let homeSearching = "home.searching"
        static let liveGameBanner = "notification.liveGame"
        /// The waiting and challenge pills, which open Activity.
        static let waitingBanner = "notification.waiting"
        static let challengeBanner = "notification.challenge"
        /// The Messages button beside the pills, with the unread count as its
        /// value. It opens Activity at Messages.
        static let messagesButton = "global.privateMessages"
        static let connectionBanner = "notification.connection"
        static let homePreferredSettings = "home.preferredSettings"
        static let homePreferredSettingsEdit = "home.preferredSettings.edit"
        static let homePreferredSettingsAdd = "home.preferredSettings.add"
        static func homePreferredSetting(_ index: Int) -> String {
            "home.preferredSettings.setting.\(index)"
        }

        static let quickMatchScroll = "quickMatch.scroll"
        static let quickMatchRecap = "quickMatch.recap"
        static let quickMatchFind = "quickMatch.find"
        static let quickMatchCancel = "quickMatch.cancel"
        static let quickMatchSearching = "quickMatch.searching"
        static let quickMatchConnectionReason = "quickMatch.connectionReason"
        static let quickMatchWaitingBanner = "quickMatch.waitingBanner"
        static let quickMatchAdvanced = "quickMatch.advanced"
        static let quickMatchClockSystem = "quickMatch.clockSystem"
        static let quickMatchGameCount = "quickMatch.gameCount"
        static let quickMatchSpeedTabs = "quickMatch.speedTabs"
        static let quickMatchAllowHandicap = "quickMatch.allowHandicap"
        static let quickMatchStrictHandicap = "quickMatch.strictHandicap"
        static let quickMatchMatchingChallenges =
            "quickMatch.matchingChallenges"

        static func quickMatchBoardSize(_ size: Int) -> String {
            "quickMatch.board.\(size)"
        }

        static func quickMatchSpeed(_ speed: String) -> String {
            "quickMatch.speed.\(speed)"
        }

        static func quickMatchClockValues(_ speed: String) -> String {
            "quickMatch.clockValues.\(speed)"
        }

        static func quickMatchSpeedTab(_ speed: String) -> String {
            "quickMatch.speedTab.\(speed)"
        }

        static func quickMatchClockPreference(_ preference: String) -> String {
            "quickMatch.clockPreference.\(preference)"
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
        static let gameActiveGamesCarousel = "game.activeGamesCarousel"
        static let gameActiveGamesButton = "game.activeGames.button"
        static let gameActiveGamesPopover = "game.activeGames.popover"
        static let gameControlProbeEvents = "game.controlProbe.events"
        static let gameControlProbeComposer = "game.controlProbe.composer"
        static func gameActiveGamesEntry(_ id: Int) -> String {
            "game.activeGames.entry.\(id)"
        }
        #if MAIN_APP
        static func gameActiveGamesEntry(_ game: Game) -> String {
            gameActiveGamesEntry(ogsID(for: game))
        }
        #endif
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
        static let gameSidebarToggle = "game.sidebar.toggle"
        static let gameBack = "game.back"

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

#if DEBUG
extension SurroundUITestContract {
    /// The notices host probe flags, parsed. Foundation only: this file also
    /// builds into SurroundTests, SurroundUITests and the widget extension.
    struct NoticesHostProbe: Equatable {
        enum TabBarMinimize: String, CaseIterable {
            case automatic, never, onScrollDown = "on-scroll-down", onScrollUp = "on-scroll-up"
            /// .never until the window first appears, then .onScrollDown, a
            /// workaround to try for the first tab's animation at launch.
            case onScrollDownAfterLaunch = "on-scroll-down-after-launch"
        }
        /// When a UIKit container sets or clears its accessory, relative to
        /// setTabBarHidden. Deferred also stops IPadTabContainer sampling closed
        /// baselines until the change lands.
        enum BarOrder: String, CaseIterable { case before, after, deferred }
        /// The custom bar with a docked software keyboard: a plain safeAreaInset;
        /// the root ignoring the keyboard safe area; hidden while it shows.
        enum BarKeyboard: String, CaseIterable { case standard, ignore, hide }
        /// "Reconnecting…"; "Can’t reach OGS" + Retry; or the status alternating
        /// with an empty subtitle every 4 s.
        enum Subtitle: String, CaseIterable { case status, retry, cycle }
        enum NavigationBarMinimize: String, CaseIterable { case automatic, never }
        enum ParseError: Error, Equatable {
            case missingValue(flag: String), invalidValue(flag: String, value: String)
            case needs(flag: String, primary: String)
        }
        enum AccessibilityID {
            static let bar = "notices.placeholderBar", barLine1 = "notices.placeholderBar.line1"
            static let barLine2 = "notices.placeholderBar.line2", barSheet = "notices.placeholderBar.sheet"
            static let barPopover = "notices.placeholderBar.popover", barPresented = "notices.placeholderBar.presented"
            static let now = "notices.placeholderNow", nowRetry = "notices.placeholderNow.retry"
            static func nowRow(_ index: Int) -> String { "notices.placeholderNow.row.\(index)" }
            static let nowAdd = "notices.placeholderNow.add", nowRemove = "notices.placeholderNow.remove"
            static let nowReassign = "notices.placeholderNow.reassign", nowAll = "notices.placeholderNow.all"
            static let nowAllContent = "notices.placeholderNow.allContent"
            static let subtitleRetry = "notices.placeholderSubtitle.retry"
            static let subtitleLargeRetry = "notices.placeholderSubtitle.largeRetry"
        }

        var showsBar = false
        var forcesCustomBar = false
        var barOrder = BarOrder.before
        var barKeyboard = BarKeyboard.standard
        var tabBarMinimize: TabBarMinimize?
        var showsNow = false
        var subtitle: Subtitle?
        var navigationBarMinimize: NavigationBarMinimize?

        /// Nil without any notices host flag. A malformed value, or a companion
        /// flag without its primary, throws. The first occurrence of a flag wins.
        static func parse(_ arguments: [String]) throws -> NoticesHostProbe? {
            typealias C = SurroundUITestContract
            var probe = NoticesHostProbe()
            probe.forcesCustomBar = arguments.contains(C.noticesForceCustomBarLaunchArgument)
            probe.showsBar = probe.forcesCustomBar || arguments.contains(C.noticesPlaceholderBarLaunchArgument)
            probe.showsNow = arguments.contains(C.noticesPlaceholderNowLaunchArgument)
            probe.tabBarMinimize = try value(C.noticesTabBarMinimizeLaunchArgument, in: arguments)
            probe.subtitle = try value(C.noticesPlaceholderSubtitleLaunchArgument, in: arguments)
            if let order: BarOrder = try value(C.noticesPlaceholderBarOrderLaunchArgument, in: arguments) {
                try require(probe.showsBar, C.noticesPlaceholderBarOrderLaunchArgument, C.noticesPlaceholderBarLaunchArgument)
                probe.barOrder = order
            }
            if let keyboard: BarKeyboard = try value(C.noticesPlaceholderBarKeyboardLaunchArgument, in: arguments) {
                try require(probe.showsBar, C.noticesPlaceholderBarKeyboardLaunchArgument, C.noticesPlaceholderBarLaunchArgument)
                probe.barKeyboard = keyboard
            }
            if let bar: NavigationBarMinimize = try value(C.noticesNavigationBarMinimizeLaunchArgument, in: arguments) {
                try require(probe.subtitle != nil, C.noticesNavigationBarMinimizeLaunchArgument,
                            C.noticesPlaceholderSubtitleLaunchArgument)
                probe.navigationBarMinimize = bar
            }
            return probe == NoticesHostProbe() ? nil : probe
        }

        private static func require(_ condition: Bool, _ flag: String, _ primary: String) throws {
            guard condition else { throw ParseError.needs(flag: flag, primary: primary) }
        }

        private static func value<Value: RawRepresentable>(_ flag: String, in arguments: [String]) throws -> Value?
        where Value.RawValue == String {
            guard let index = arguments.firstIndex(of: flag) else { return nil }
            guard arguments.indices.contains(index + 1) else { throw ParseError.missingValue(flag: flag) }
            guard let value = Value(rawValue: arguments[index + 1]) else {
                throw ParseError.invalidValue(flag: flag, value: arguments[index + 1])
            }
            return value
        }
    }

    /// UI tests: extra probe flags from SURROUND_UI_NOTICES_HOST_PROBE (Xcode
    /// passes TEST_RUNNER_SURROUND_UI_NOTICES_HOST_PROBE), split on whitespace.
    static func noticesHostProbeArguments(_ environment: [String: String]) -> [String] {
        (environment["SURROUND_UI_NOTICES_HOST_PROBE"] ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Opens the Activity list once at launch, over the offline root:
    /// `--surround-activity-open sheet`, or `game-popover`, which opens game
    /// 26268404 and then the game's popover. It needs an Activity state
    /// (`--surround-activity-state`).
    static let activityOpenLaunchArgument = "--surround-activity-open"

    enum ActivityOpen: String, CaseIterable {
        case sheet
        case gamePopover = "game-popover"
    }

    enum ActivityOpenError: Error, Equatable, CustomStringConvertible {
        case missingValue, unknownValue(String), needsActivityState

        var description: String {
            switch self {
            case .missingValue:
                "\(activityOpenLaunchArgument) needs a value: "
                    + ActivityOpen.allCases.map(\.rawValue).joined(separator: ", ")
            case .unknownValue(let raw):
                "Unknown \(activityOpenLaunchArgument) value '\(raw)'. Use one of: "
                    + ActivityOpen.allCases.map(\.rawValue).joined(separator: ", ")
            case .needsActivityState:
                "\(activityOpenLaunchArgument) needs \(activityStateLaunchArgument)."
            }
        }
    }

    /// Nil without `--surround-activity-open`. A missing or unknown value,
    /// or no Activity state, throws.
    static func parseActivityOpen(_ arguments: [String]) throws -> ActivityOpen? {
        guard let index = arguments.firstIndex(of: activityOpenLaunchArgument) else { return nil }
        guard arguments.indices.contains(index + 1) else { throw ActivityOpenError.missingValue }
        let raw = arguments[index + 1]
        guard let open = ActivityOpen(rawValue: raw) else { throw ActivityOpenError.unknownValue(raw) }
        guard arguments.contains(activityStateLaunchArgument) else { throw ActivityOpenError.needsActivityState }
        return open
    }

    /// The offline service answers Accept, Reject and Withdraw itself, 0.35 s
    /// after each is sent, where it would fail at once: `--surround-activity-actions
    /// succeed`, or `fail-once`, where each challenge's first action fails and
    /// later ones succeed. An accepted challenge starts an active game
    /// (`ActivityFixtureID.acceptedGameID`); a rejected or withdrawn one leaves
    /// its list. A Quick Match withdraw still goes to the socket, which never
    /// confirms it. It needs an Activity state (`--surround-activity-state`).
    static let activityActionsLaunchArgument = "--surround-activity-actions"

    enum ActivityActions: String, CaseIterable {
        case succeed
        case failOnce = "fail-once"
    }

    enum ActivityActionsError: Error, Equatable, CustomStringConvertible {
        case missingValue, unknownValue(String), needsActivityState

        var description: String {
            switch self {
            case .missingValue:
                "\(activityActionsLaunchArgument) needs a value: "
                    + ActivityActions.allCases.map(\.rawValue).joined(separator: ", ")
            case .unknownValue(let raw):
                "Unknown \(activityActionsLaunchArgument) value '\(raw)'. Use one of: "
                    + ActivityActions.allCases.map(\.rawValue).joined(separator: ", ")
            case .needsActivityState:
                "\(activityActionsLaunchArgument) needs \(activityStateLaunchArgument)."
            }
        }
    }

    /// Nil without `--surround-activity-actions`. A missing or unknown value,
    /// or no Activity state, throws.
    static func parseActivityActions(_ arguments: [String]) throws -> ActivityActions? {
        guard let index = arguments.firstIndex(of: activityActionsLaunchArgument) else { return nil }
        guard arguments.indices.contains(index + 1) else { throw ActivityActionsError.missingValue }
        let raw = arguments[index + 1]
        guard let actions = ActivityActions(rawValue: raw) else { throw ActivityActionsError.unknownValue(raw) }
        guard arguments.contains(activityStateLaunchArgument) else { throw ActivityActionsError.needsActivityState }
        return actions
    }
}
#endif
