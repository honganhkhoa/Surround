import XCTest
import UIKit

/// Bounded, offline checks of the app's Malay and Indonesian catalogs.
/// Locale overrides belong to each app launch, never to simulator settings.
/// Screenshots still need visual review: accessibility frames do not prove that
/// every glyph fits, and fixture usernames/message bodies are verbatim content.
final class LocalizationUITests: SurroundJourneyUITestCase {
    private enum Language: String {
        case malay = "ms"
        case indonesian = "id"

        var localeIdentifier: String {
            self == .malay ? "ms_MY" : "id_ID"
        }

        func text(_ key: String) -> String {
            let translations = self == .malay ? Self.malayText : Self.indonesianText
            guard let value = translations[key] else {
                preconditionFailure("Missing localization test expectation for \(rawValue): \(key)")
            }
            return value
        }

        func text(_ key: String, username: String) -> String {
            text(key).replacingOccurrences(of: "%@", with: username)
        }

        // Explicit expected translations keep these assertions independent of
        // the runner's own language and of app-side localization lookup.
        private static let malayText: [String: String] = [
            "Active games": "Permainan aktif",
            "Settings": "Tetapan",
            "General": "Umum",
            "View your profile": "Lihat profil anda",
            "Advanced time settings": "Tetapan masa lanjutan",
            "Live": "Langsung",
            "Correspondence": "Surat-menyurat",
            "Main time": "Masa utama",
            "Periods: ": "Tempoh: ",
            "Advanced rules settings": "Tetapan peraturan lanjutan",
            "Japanese": "Jepun",
            "Standard komi: **%.1f**": "Komi standard: **%.1f**",
            "Conditional moves": "Langkah bersyarat",
            "Conditional moves plan": "Pelan langkah bersyarat",
            "Messages": "Mesej",
            "Friends": "Rakan",
            "Search players": "Cari pemain",
            "Search friends": "Cari rakan",
            "See all": "Lihat semua",
            "%lld friends": "%lld rakan",
            "Message %@": "Hantar mesej kepada %@",
            "Challenge %@": "Cabar %@",
            "View %@’s profile": "Lihat profil %@",
            "Send message": "Hantar mesej",
            "Unread conversation": "Perbualan belum dibaca",
            "Challenge": "Cabaran",
            "Message": "Mesej",
            "Opponent": "Lawan",
            "Never play with handicap stones.": "Sentiasa bermain tanpa batu handicap.",
        ]

        private static let indonesianText: [String: String] = [
            "Active games": "Permainan aktif",
            "Settings": "Pengaturan",
            "General": "Umum",
            "View your profile": "Lihat profil Anda",
            "Advanced time settings": "Pengaturan waktu lanjutan",
            "Live": "Langsung",
            "Correspondence": "Korespondensi",
            "Main time": "Waktu utama",
            "Periods: ": "Periode: ",
            "Advanced rules settings": "Pengaturan aturan lanjutan",
            "Japanese": "Jepang",
            "Standard komi: **%.1f**": "Komi standar: **%.1f**",
            "Conditional moves": "Langkah bersyarat",
            "Conditional moves plan": "Rencana langkah bersyarat",
            "Messages": "Pesan",
            "Friends": "Teman",
            "Search players": "Cari pemain",
            "Search friends": "Cari teman",
            "See all": "Lihat semua",
            "%lld friends": "%lld teman",
            "Message %@": "Kirim pesan ke %@",
            "Challenge %@": "Tantang %@",
            "View %@’s profile": "Lihat profil %@",
            "Send message": "Kirim pesan",
            "Unread conversation": "Percakapan belum dibaca",
            "Challenge": "Tantangan",
            "Message": "Pesan",
            "Opponent": "Lawan",
            "Either clock": "Mana saja",
            "Withdraw live game search": "Batalkan pencarian permainan langsung",
            "Withdraw quick match search": "Batalkan pencarian lawan cepat",
            "Searching for a game…": "Mencari permainan…",
        ]
    }

    func testMalayLocalization() throws {
        try verifyLocalization(.malay)
    }

    func testIndonesianLocalization() throws {
        try verifyLocalization(.indonesian)
    }

    func testMalayReviewedQuickMatchWording() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("These captures use the regular iPhone/iPad Simulator layouts.")
        #else
        executionTimeAllowance = 180
        verifyReviewedQuickMatchPreferences(.malay)
        #endif
    }

    func testIndonesianReviewedQuickMatchWording() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("These captures use the regular iPhone/iPad Simulator layouts.")
        #else
        executionTimeAllowance = 240
        verifyReviewedQuickMatchPreferences(.indonesian)
        verifyPendingWaitingWithdrawal(.indonesian)
        verifyRestoredLiveWithdrawal(.indonesian)
        #endif
    }

    private func verifyLocalization(_ language: Language) throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("These captures use the regular iPhone/iPad Simulator layouts.")
        #else
        executionTimeAllowance = 600
        verifyHomeAndConditionalMoves(language)
        verifySettings(language)
        verifyAdvancedTime(language)
        verifyAdvancedRules(language)
        verifyStandaloneThread(language)
        verifyMessagesFriendsAndProfile(language)
        #endif
    }

    private func launchLocalizedApp(
        _ language: Language,
        scene: SurroundUITestContract.CompatibilityScene,
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .phone
            ? .portrait : .landscapeLeft
        #endif
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(\(language.rawValue))",
            "-AppleLocale", language.localeIdentifier,
            "-AppleInterfaceStyle", "Light",
            SurroundUITestContract.launchArgument,
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            scene.rawValue,
        ] + additionalArguments
        registerAppTermination(app)
        app.launch()
        element(SurroundUITestContract.AccessibilityID.compatibilityScreen(scene), in: app)
        return app
    }

    private func verifyReviewedQuickMatchPreferences(_ language: Language) {
        let app = launchLocalizedApp(language, scene: .quickMatch)
        defer { app.terminate() }
        let find = element(SurroundUITestContract.AccessibilityID.quickMatchFind,
                           in: app, matching: .button)
        XCTAssertTrue(find.exists, "The Quick Match fixture must start with its idle editor.")

        if language == .malay {
            let rapid = elementAfterScrolling(
                SurroundUITestContract.AccessibilityID.quickMatchSpeed("rapid"), in: app)
            scrollIntoTappableArea(rapid, in: app)
            assertVisible(rapid, in: app)
            // The formatted total is visible in speedDetails and supplied as
            // the switch's accessibilityHint. XCTest has no public hint lookup;
            // this capture supplements the compiled-resource format check.
            capture("quick-match-duration", language: language, in: app)

            let allow = elementAfterScrolling(
                SurroundUITestContract.AccessibilityID.quickMatchAllowHandicap, in: app)
            scrollIntoTappableArea(allow, in: app)
            let initialValue = allow.value as? String
            XCTAssertTrue(initialValue == "0" || initialValue == "1")
            if initialValue == "1" {
                // Change only this offline editor preference; never press Find.
                activate(allow, at: CGVector(dx: 0.95, dy: 0.5))
            }
            XCTAssertTrue(waitForValue("0", in: allow, timeout: 10))
            let footnote = localizedLabelAfterScrolling(
                language.text("Never play with handicap stones."), in: app)
            assertVisible(footnote, in: app)
            capture("quick-match-no-handicap", language: language, in: app)
        } else {
            let advanced = elementAfterScrolling(
                SurroundUITestContract.AccessibilityID.quickMatchAdvanced,
                in: app, matching: .button)
            scrollIntoTappableArea(advanced, in: app)
            let clockSystem = app.descendants(matching: .any)
                .matching(identifier: SurroundUITestContract.AccessibilityID.quickMatchClockSystem)
                .firstMatch
            if !clockSystem.exists {
                tap(advanced, description: "Open offline Quick Match clock preferences", in: app)
            }
            XCTAssertTrue(clockSystem.waitForExistence(timeout: 10))
            let either = elementAfterScrolling(
                SurroundUITestContract.AccessibilityID.quickMatchClockPreference("flexible"),
                in: app, matching: .button)
            scrollIntoTappableArea(either, in: app)
            XCTAssertEqual(either.label, language.text("Either clock"))
            assertVisible(either, in: app)
            capture("quick-match-either-clock", language: language, in: app)
        }
    }

    private func verifyPendingWaitingWithdrawal(_ language: Language) {
        let app = launchLocalizedApp(language, scene: .waitingGames)
        defer { app.terminate() }
        let fixtureID = "f0050bcf-f5fc-46c8-9ed6-01dfd898e0d0"
        element(SurroundUITestContract.AccessibilityID.waitingGamesAutomatchEntry(fixtureID),
                in: app)
        let withdraw = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID.waitingGamesAutomatchWithdraw(fixtureID),
            in: app, matching: .button)
        scrollIntoTappableArea(withdraw, in: app)
        XCTAssertEqual(withdraw.label, language.text("Withdraw quick match search"))
        XCTAssertTrue(withdraw.isEnabled, "The untouched pending fixture must expose its withdrawal action.")
        assertVisible(withdraw, in: app)
        // The visible title uses Withdraw; its AX label intentionally describes
        // the full action. Capture both without initiating cancellation.
        capture("waiting-games-pending-withdrawal", language: language, in: app)
    }

    private func verifyRestoredLiveWithdrawal(_ language: Language) {
        let app = launchLocalizedApp(language, scene: .home)
        defer { app.terminate() }
        let newGame = elementAfterScrolling(SurroundUITestContract.AccessibilityID.homeNewGame,
                                           in: app, matching: .button)
        scrollIntoTappableArea(newGame, in: app)
        tap(newGame, description: "Open the restored offline Quick Match search", in: app)
        let status = element(SurroundUITestContract.AccessibilityID.quickMatchSearching, in: app)
        XCTAssertEqual(status.label, language.text("Searching for a game…"))
        let withdraw = element(SurroundUITestContract.AccessibilityID.quickMatchCancel,
                               in: app, matching: .button)
        XCTAssertEqual(withdraw.label, language.text("Withdraw live game search"))
        assertVisible(withdraw, in: app)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.quickMatchFind].exists,
                       "The fixture must expose the restored search, not an idle Find action.")
        capture("quick-match-restored-withdrawal", language: language, in: app)
    }

    private func localizedLabelAfterScrolling(_ text: String, in app: XCUIApplication) -> XCUIElement {
        let target = app.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label == %@", text)).firstMatch
        let scroll = app.scrollViews[SurroundUITestContract.AccessibilityID.quickMatchScroll]
        for _ in 0..<8 {
            if target.exists && target.isHittable { break }
            scroll.swipeUp()
        }
        return localizedLabel(text, in: app, matching: .staticText)
    }

    private func verifyHomeAndConditionalMoves(_ language: Language) {
        let app = launchLocalizedApp(language, scene: .home)
        defer { app.terminate() }
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        assertVisible(localizedLabel(language.text("Active games"), in: app), in: app)
        element(SurroundUITestContract.AccessibilityID.homeGame(
            SurroundUITestContract.screenshotPrimaryGameID), in: app)
        capture("home", language: language, in: app)

        // This read-only popover opens existing fixture plans without opening a
        // game or creating/updating conditional moves.
        let gameID = SurroundUITestContract.conditionalMovesFixtureGameID
        let button = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID.homeConditionalButton(gameID),
            in: app, matching: .button)
        XCTAssertEqual(button.label, language.text("Conditional moves"))
        guard positionConditionalButtonInVisibleContent(button, in: app) else { return }
        assertVisible(button, in: app)
        tap(button, description: "Open the offline conditional-moves plan", in: app)
        element(SurroundUITestContract.AccessibilityID.homeConditionalPopover(gameID), in: app)
        let title = element(SurroundUITestContract.AccessibilityID.homeConditionalPopoverTitle(gameID), in: app)
        XCTAssertEqual(title.label, language.text("Conditional moves plan"))
        assertVisible(title, in: app)
        for branchID in SurroundUITestContract.conditionalMovesFixtureBranchIDs {
            element(SurroundUITestContract.AccessibilityID.homeConditionalVariation(
                gameID, branchID: branchID), in: app)
        }
        capture("conditional-moves-plan", language: language, in: app)
    }

    private func verifySettings(_ language: Language) {
        let app = launchLocalizedApp(language, scene: .settings)
        defer { app.terminate() }
        element(SurroundUITestContract.AccessibilityID.screenSettings, in: app)
        assertVisible(localizedLabel(language.text("Settings"), in: app), in: app)
        localizedLabel(language.text("General"), in: app)
        let profile = element(SurroundUITestContract.AccessibilityID.profileSettingsEntry,
                              in: app, matching: .button)
        XCTAssertEqual(profile.label, language.text("View your profile"))
        assertVisible(profile, in: app)
        capture("settings", language: language, in: app)
    }

    private func verifyAdvancedTime(_ language: Language) {
        let app = launchLocalizedApp(language, scene: .advancedTime)
        defer { app.terminate() }
        assertVisible(localizedLabel(language.text("Advanced time settings"), in: app), in: app)
        localizedLabel(language.text("Live"), in: app)
        localizedLabel(language.text("Correspondence"), in: app)
        let mainTime = localizedLabel(language.text("Main time") + ": ", in: app, hasPrefix: true)
        assertVisible(mainTime, in: app)
        localizedLabel(language.text("Periods: ") + "5", in: app)
        capture("advanced-time", language: language, in: app)
    }

    private func verifyAdvancedRules(_ language: Language) {
        let app = launchLocalizedApp(language, scene: .advancedRules)
        defer { app.terminate() }
        assertVisible(localizedLabel(language.text("Advanced rules settings"), in: app), in: app)
        localizedLabel(language.text("Japanese"), in: app)
        let komiPrefix = language.text("Standard komi: **%.1f**")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "%.1f", with: "")
        let komi = localizedLabel(komiPrefix, in: app, hasPrefix: true)
        XCTAssertTrue(komi.label.contains("6.5") || komi.label.contains("6,5"),
                      "The localized komi label must resolve its numeric format specifier.")
        assertVisible(komi, in: app)
        capture("advanced-rules", language: language, in: app)
    }

    private func verifyStandaloneThread(_ language: Language) {
        let app = launchLocalizedApp(language, scene: .messageThread)
        defer { app.terminate() }
        verifyComposer(for: "hakhoa", language: language, in: app)
        capture("message-thread", language: language, in: app)
    }

    private func verifyMessagesFriendsAndProfile(_ language: Language) {
        let app = launchLocalizedApp(language, scene: .messagesInbox, additionalArguments: [
            SurroundUITestContract.profileContentLaunchArgument,
            SurroundUITestContract.messagesContentLaunchArgument,
        ])
        defer { app.terminate() }
        element(SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        localizedLabel(language.text("Messages"), in: app)
        let search = element("messages.playerSearchField", in: app, matching: .textField)
        XCTAssertEqual(search.placeholderValue, language.text("Search players"))
        assertVisible(search, in: app)
        // The second fixture remains unread even if the wide layout selected
        // and marked the first conversation as read on appearance.
        let unread = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID.privateMessageRow(955_348),
            in: app, matching: .button)
        XCTAssertEqual(unread.value as? String, language.text("Unread conversation"))
        capture("messages-inbox", language: language, in: app)

        let seeAll = element("messages.seeAllFriends", in: app, matching: .button)
        XCTAssertEqual(seeAll.label, language.text("See all"))
        scrollIntoTappableArea(seeAll, in: app)
        tap(seeAll, description: "Open offline Friends", in: app)
        element("messages.friends", in: app)
        localizedLabel(language.text("Friends"), in: app)
        let count = language.text("%lld friends").replacingOccurrences(of: "%lld", with: "6")
        assertVisible(localizedLabel(count, in: app), in: app)
        let filter = element("messages.friends.filter", in: app, matching: .textField)
        XCTAssertEqual(filter.placeholderValue, language.text("Search friends"))
        assertVisible(filter, in: app)

        let friendID = SurroundUITestContract.profileFixturePickerFriendID
        let username = "BambooPath"
        let profile = element("messages.friend.profile.\(friendID)", in: app, matching: .button)
        let message = element("messages.friend.message.\(friendID)", in: app, matching: .button)
        let challenge = element("messages.friend.challenge.\(friendID)", in: app, matching: .button)
        XCTAssertEqual(profile.label, language.text("View %@’s profile", username: username))
        XCTAssertEqual(message.label, language.text("Message %@", username: username))
        XCTAssertEqual(challenge.label, language.text("Challenge %@", username: username))
        assertVisible(profile, in: app)
        assertVisible(message, in: app)
        assertVisible(challenge, in: app)
        capture("friends", language: language, in: app)

        // Exercise the localized filter after preserving the full six-friend
        // screen. This also gives native Friends navigation a real focus and
        // layout transition before the profile interaction.
        tap(filter, description: "Focus the localized offline Friends filter", in: app)
        filter.typeText("Bamboo")
        XCTAssertTrue(waitForValue("Bamboo", in: filter, timeout: 10))
        let filteredProfiles = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "messages.friend.profile."))
        let onlyFixture = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            filteredProfiles.count == 1 && profile.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [onlyFixture], timeout: 10), .completed,
                       "The Friends filter must retain only the BambooPath fixture profile.")
        XCTAssertEqual(filteredProfiles.firstMatch.identifier,
                       "messages.friend.profile.\(friendID)")
        tap(profile, description: "Open the offline friend's profile", in: app)
        assertLoadedProfile(named: username, in: app)
        let profileMessage = element(SurroundUITestContract.AccessibilityID.profileMessage,
                                     in: app, matching: .button)
        XCTAssertEqual(profileMessage.label, language.text("Message"))
        assertVisible(profileMessage, in: app)
        let profileChallenge = element(SurroundUITestContract.AccessibilityID.profileChallenge,
                                       in: app, matching: .button)
        XCTAssertEqual(profileChallenge.label, language.text("Challenge"))
        assertVisible(profileChallenge, in: app)
        capture("profile", language: language, in: app)

        // Opening the form checks routing and language without submitting it.
        tap(profileChallenge, description: "Open an offline challenge form", in: app)
        element(SurroundUITestContract.AccessibilityID.screenCustomGame, in: app)
        assertVisible(localizedLabel(language.text("Challenge"), in: app), in: app)
        localizedLabel(language.text("Opponent"), in: app)
        let opponent = element(SurroundUITestContract.AccessibilityID.customGameOpponent, in: app)
        XCTAssertTrue(opponent.label.contains(username))
        assertVisible(opponent, in: app)
        capture("challenge-form", language: language, in: app)
    }

    private func positionConditionalButtonInVisibleContent(
        _ button: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        // Home scrolls beneath its native navigation bar. Checking only the
        // application's bounds can leave this small button near the header,
        // where a tap may instead activate the containing game row.
        func visibleContentFrame() -> CGRect {
            let window = app.windows.firstMatch.frame
            let barBottom = app.navigationBars.allElementsBoundByIndex
                .filter {
                    $0.exists && $0.frame.width > 1 && $0.frame.height > 1
                        && window.intersects($0.frame)
                }
                .map { $0.frame.maxY }
                .max() ?? window.minY
            let top = max(window.minY, barBottom) + 24
            let bottom = window.maxY - 120
            return CGRect(x: window.minX, y: top, width: window.width,
                          height: max(0, bottom - top))
        }

        for _ in 0..<8 {
            let visible = visibleContentFrame()
            let frame = button.frame
            if button.isHittable && visible.contains(frame) { break }
            let distance = min(120, visible.height * 0.18)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.55))
            let end = start.withOffset(CGVector(
                dx: 0, dy: frame.minY < visible.minY ? distance : -distance))
            start.press(forDuration: 0.05, thenDragTo: end)
        }

        var previousFrame: CGRect?
        var stableSince: Date?
        var stableSamples = 0
        let stable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard button.exists, button.isHittable else {
                previousFrame = nil
                stableSince = nil
                stableSamples = 0
                return false
            }
            let frame = button.frame
            guard frame.width > 1, frame.height > 1,
                  visibleContentFrame().contains(frame) else {
                previousFrame = nil
                stableSince = nil
                stableSamples = 0
                return false
            }
            if let previousFrame,
               abs(previousFrame.minX - frame.minX) <= 0.5,
               abs(previousFrame.minY - frame.minY) <= 0.5,
               abs(previousFrame.width - frame.width) <= 0.5,
               abs(previousFrame.height - frame.height) <= 0.5 {
                stableSamples += 1
            } else {
                stableSince = Date()
                stableSamples = 1
            }
            previousFrame = frame
            return stableSamples >= 3
                && Date().timeIntervalSince(stableSince ?? Date()) >= 0.75
        }, object: nil)
        let settled = XCTWaiter.wait(for: [stable], timeout: 10) == .completed
        XCTAssertTrue(settled,
                      "The conditional-moves button must retain a stable frame inside visible Home content before tapping.")
        return settled
    }

    private func verifyComposer(for username: String, language: Language, in app: XCUIApplication) {
        let composer = element(SurroundUITestContract.AccessibilityID.privateMessageComposer,
                               in: app, matching: .textField)
        XCTAssertEqual(composer.placeholderValue, language.text("Message %@", username: username))
        assertVisible(composer, in: app)
        let send = localizedLabel(language.text("Send message"), in: app, matching: .button)
        XCTAssertFalse(send.isEnabled, "The offline empty composer must not offer a send action.")
        assertVisible(send, in: app)
    }

    @discardableResult
    private func localizedLabel(
        _ text: String,
        in app: XCUIApplication,
        matching elementType: XCUIElement.ElementType = .any,
        hasPrefix: Bool = false
    ) -> XCUIElement {
        let query = app.descendants(matching: elementType).matching(
            NSPredicate(format: hasPrefix ? "label BEGINSWITH %@" : "label == %@", text))
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 10),
                      "Expected the resolved localized label: \(text)")
        // Prefer the visible copy when an inactive retained tab or its title
        // exposes another accessibility element with the same label.
        return query.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? query.firstMatch
    }

    private func assertVisible(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let frame = element.frame
        XCTAssertGreaterThan(frame.width, 1)
        XCTAssertGreaterThan(frame.height, 1)
        XCTAssertTrue(window.frame.insetBy(dx: -2, dy: -2).contains(frame),
                      "Representative localized content must fit inside its window: \(element.label), \(frame)")
        XCTAssertTrue(element.isHittable,
                      "Representative localized content must be visibly accessible: \(element.label)")
    }

    private func capture(_ scene: String, language: Language, in app: XCUIApplication) {
        let name = "localization-\(language.rawValue)-\(scene)"
        keepScreenshot(name, in: app)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name)-accessibility-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
