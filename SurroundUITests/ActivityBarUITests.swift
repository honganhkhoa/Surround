//
//  ActivityBarUITests.swift
//  SurroundUITests
//
//  The Activity bar and the iPad's Now section on root screens, and the
//  window's connection status there, on the offline Activity states
//  (`--surround-activity-state`, TESTING.md). Each journey says what it
//  expects on each host. Phones show the bar, in their device's host: the
//  custom bar before iOS 26.1, SwiftUI's accessory from 26.1 and UIKit's
//  on iOS 27, as the bar's Debug element says. An iPad shows the floating
//  bar in portrait with its sidebar hidden and the Now section in
//  landscape with it shown, and each journey pins the one it needs. The
//  Duo is an iOS 27 iPhone in whatever pose Device Hub set, so its steps
//  follow the layout they find; its own two journeys ask the run for the
//  poses they need. The Mac has no bar, so these journeys skip
//  there; its own, signed and under Automation Mode, check its sidebar's
//  Now section, its status and View > Activity. The waits are the app's: a
//  status shows 2 s into an outage, a result stays 4 s, an unconfirmed
//  withdrawal fails after 8 s, and Can’t reach OGS comes 30 s in. Each is
//  polled for with the shortest bound that proves it.
//

import XCTest
import UIKit

#if DEBUG
final class ActivityBarUITests: SurroundJourneyUITestCase {
    private typealias ID = SurroundUITestContract.AccessibilityID
    private typealias FixtureID = SurroundUITestContract.ActivityFixtureID
    private typealias State = SurroundUITestContract.ActivityFixtureState
    private typealias Actions = SurroundUITestContract.ActivityActions

    private static let iOSOnly = "iOS only: the Mac has no Activity bar. Its Now section, its status and "
        + "View > Activity are the testTheMacs… journeys'."

    /// The fixture's items (`ActivityFixtures.swift`).
    private let baseGame = "game-\(SurroundUITestContract.fixtureGameID)"
    private let harborMist = "game-\(FixtureID.harborMistGameID)"
    private let startedGame = "game-\(FixtureID.startedGameID)"
    private let usualChallenge = "challenge-\(FixtureID.usualChallengeID)"
    private let openChallenge = "waiting-open-\(FixtureID.openChallengeID)"
    private var liveSearch: String { "waiting-quick-match-\(FixtureID.liveQuickMatchUUID)" }
    /// CedarWave, who sends the usual challenge.
    private let cedarWaveID = 851_001
    /// `several`'s newest unread conversation.
    private let tenukiTomID = 915_100
    /// The live-game banner fixture's finished game, on Home and in its
    /// opponent's history, and that opponent, who played Black.
    private let historyGameID = SurroundUITestContract.liveBannerHistoryGameID
    private let historyOpponentID = 356
    private let historyOpponentName = "Dyonn"
    /// Home's history section, which holds the finished game's row.
    private static let historySection = ID.homeSection("history")

    private let reconnecting = "Reconnecting…"
    private let cantReachOGS = "Can’t reach OGS"

    // MARK: Leads

    /// `live-your-move` on Home: HarborMist's live game on your move leads,
    /// with its clock, the time left, as its value. Phones and the Duo: the
    /// bar's lead. An iPad, in portrait with its sidebar hidden: the floating
    /// bar's lead; the Now section's row for it is
    /// testTheNowSectionShowsTwoRowsAndAllActivity's. A tap shows the game on
    /// Home's route, where no bar shows, and Back brings the bar back.
    func testTheBarLeadsWithALiveGameAndOpensIt() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.liveYourMove)
        let lead = barLead(in: app)
        assertLeads("live \(harborMist)", in: app)
        XCTAssertTrue(lead.label.contains("HarborMist"), "The lead names the game's opponent: \(lead.label)")
        XCTAssertFalse((lead.value as? String ?? "").isEmpty, "The lead says its clock's time: \(lead.debugDescription)")
        keepScreenshot("The bar leads with HarborMist's game", in: app)

        tap(lead, description: "The bar's lead", in: app)
        element(ID.gameDetail(FixtureID.harborMistGameID), in: app)
        assertNoBar("HarborMist's game", in: app)
        keepScreenshot("HarborMist's game, with no bar", in: app)
        backToHome(from: FixtureID.harborMistGameID, in: app)
        barLead(in: app)
        assertLeads("live \(harborMist)", in: app)
        #endif
    }

    /// `several`: HarborMist's game leads with +3, CedarWave's challenge and
    /// two unread conversations, on Home, Public games and the Web version,
    /// and with +1 on Messages, whose own tab leaves its conversations out.
    /// Phones: Messages in one column with no conversation selected, and the
    /// Web version a tab. An iPad, in portrait with its sidebar hidden: Home
    /// and Public games; its Messages has two columns, whose selected
    /// conversation hides the bar, and its Web version is in the sidebar
    /// only, so those steps skip. The Duo: as a phone where its pose gives
    /// Messages one column and the Web version a tab, else as an iPad.
    func testTheBarIsTheSameOnEveryTab() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.several)
        let roots: [(entry: String, screen: String, plusN: Int)] = [
            (ID.navigationHome, ID.screenHome, 3), (ID.navigationPublicGames, ID.screenPublicGames, 3),
            (ID.navigationMessages, ID.screenMessages, 1), (ID.navigationBrowser, ID.screenBrowser, 3),
        ]
        var firstLabel: String?
        for root in roots {
            if root.entry == ID.navigationBrowser, !isTab(root.entry, in: app) {
                note("Skipped the Web version: it is in the sidebar only here")
                continue
            }
            selectMainNavigation(root.entry, in: app)
            element(root.screen, in: app)
            if root.entry == ID.navigationMessages, messagesHasTwoColumns(in: app) {
                note("Skipped Messages: its two columns select a conversation, which hides the bar")
                continue
            }
            let lead = barLead(in: app)
            assertLeads("live \(harborMist)", in: app)
            var count: Int?
            XCTAssertTrue(pollUntil(timeout: 10) {
                count = self.activityPlusN(in: app)
                return count == root.plusN
            }, "\(root.screen): +\(root.plusN), found \(String(describing: count))")
            if let firstLabel {
                XCTAssertEqual(lead.label, firstLabel, "\(root.screen) shows the same lead")
            } else {
                firstLabel = lead.label
            }
            keepScreenshot("The bar on \(root.screen)", in: app)
        }
        #endif
    }

    /// `nothing-leads` on Public games: nothing live waits, so "3 waiting"
    /// leads. Its line two names a correspondence challenge and two
    /// conversations, which XCTest reads in the lead's VoiceOver label,
    /// since the lines themselves are hidden from it. A tap opens Activity: a
    /// sheet in compact width, a popover in regular width. Phones: the bar
    /// and the sheet. An iPad, in portrait with its sidebar hidden: the
    /// floating bar and its popover. The Duo: a sheet closed upright, a
    /// popover in its wide poses.
    func testNothingLeadsOpensActivity() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.nothingLeads)
        selectMainNavigation(ID.navigationPublicGames, in: app)
        element(ID.screenPublicGames, in: app)
        let lead = barLead(in: app)
        XCTAssertTrue(barReading(in: app).state?.hasPrefix("nothingLeads ") == true,
                      "Nothing live leads: \(barReading(in: app).state ?? "no bar")")
        XCTAssertEqual(activityCount(of: lead), 3, "Three wait: \(lead.label)")
        XCTAssertTrue(lead.label.hasPrefix("3 waiting"), "The lead says 3 waiting: \(lead.label)")
        XCTAssertTrue(lead.label.contains("a correspondence challenge") && lead.label.contains("2 unread conversations"),
                      "It names a correspondence challenge and two conversations: \(lead.label)")
        keepScreenshot("3 waiting on Public games", in: app)

        tap(lead, description: "3 waiting", in: app)
        element(ID.activityList, in: app)
        assertActivityPresentation(in: app)
        keepScreenshot("Activity from 3 waiting", in: app)
        closeList(in: app)
        barLead(in: app)
        #endif
    }

    /// `game-started`: CedarWave's live game, which started elsewhere 5 s
    /// before the launch, leads with "Game started" and Open game; the
    /// frozen fixture clock keeps it inside its 30 s. Open game shows that
    /// game on Home's route. Phones, and the Duo but closed upright: the
    /// bar's lead and its action. The Duo closed upright draws its bar on
    /// one line, without Open game, so there the lead opens the game. An
    /// iPad, in landscape with its sidebar shown: the Now section's first
    /// row and its action; the floating bar's are the same view as a
    /// phone's.
    func testAStartedGameLeadsAndOpens() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.gameStarted, sidebar: .shown)
        let lead = activityLead(nowRow: startedGame, in: app)
        let openGame: XCUIElement
        if iPadSidebarIsShown(in: app) {
            XCTAssertEqual(lead.identifier, ID.activityNowRow(startedGame), "Beside the sidebar its Now section's row leads")
            XCTAssertFalse(query(ID.activityBar, in: app).exists, "Beside the sidebar there is no floating bar")
            openGame = query(ID.activityNowRowAction(startedGame), in: app)
        } else {
            XCTAssertEqual(lead.identifier, ID.activityBarLead, "The bar leads")
            assertLeads("started \(startedGame)", in: app)
            openGame = query(ID.activityBarAction, in: app)
        }
        XCTAssertTrue(lead.label.hasPrefix("Game started"), "The lead says Game started: \(lead.label)")
        if isClosedUprightDuo(in: app) {
            assertTheBarIsOneLine(withoutItsAction: "Open game", in: app)
            keepScreenshot("Game started on the Duo's one-line bar", in: app)
            tap(lead, description: "The started game's lead", in: app)
        } else {
            XCTAssertTrue(openGame.exists(within: 10), "A started game offers Open game")
            keepScreenshot("Game started with Open game", in: app)
            tap(openGame, description: "Open game", in: app)
        }
        element(ID.gameDetail(FixtureID.startedGameID), in: app)
        assertNoBar("The started game", in: app)
        backToHome(from: FixtureID.startedGameID, in: app)
        #endif
    }

    /// `challenge-received`: CedarWave's live challenge leads, and View opens
    /// Activity with that challenge's card pushed, which Back leaves for the
    /// list. Phones: the bar's View and the list's sheet. An iPad, in
    /// portrait with its sidebar hidden: the floating bar's View and a
    /// popover; the Now row's View is
    /// testTheNowSectionShowsTwoRowsAndAllActivity's. The Duo: a sheet
    /// turned sideways, a popover in its wide poses; closed upright its bar
    /// is one line, without View, so there the lead opens Activity, as a
    /// sheet, where the challenge's row waits.
    func testTheBarsViewOpensTheChallengesCard() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.challengeReceived)
        let lead = barLead(in: app)
        assertLeads("challenge \(usualChallenge)", in: app)
        if isClosedUprightDuo(in: app) {
            assertTheBarIsOneLine(withoutItsAction: "View", in: app)
            tap(lead, description: "CedarWave's challenge in the bar", in: app)
            element(ID.activityList, in: app)
            assertActivityPresentation(in: app)
            element(ID.activityRow(usualChallenge), in: app)
            keepScreenshot("CedarWave's challenge in Activity from the Duo's one-line bar", in: app)
            closeList(in: app)
            barLead(in: app)
            return
        }
        let view = element(ID.activityBarAction, in: app, matching: .button)
        tap(view, description: "The bar's View", in: app)
        challengeCard(FixtureID.usualChallengeID, challenger: cedarWaveID, in: app)
        XCTAssertEqual(app.popovers.firstMatch.exists, expectsActivityPopover(in: app),
                       "The card is in Activity's popover in regular width, its sheet in compact width")
        keepScreenshot("CedarWave's card from the bar's View", in: app)
        backToList(in: app)
        assertActivityPresentation(in: app)
        closeList(in: app)
        barLead(in: app)
        #endif
    }

    /// `waiting` with `succeed-listed`: your open 9×9 challenge, the oldest
    /// live waiting item, leads with Withdraw. OGS's reply confirms it 0.35 s
    /// later while the service keeps listing the challenge, as OGS does
    /// until its next update, so Home's Searching card still counts it. The
    /// bar says "Withdrawn" for 4 s, then leads with the next item and never
    /// the withdrawn challenge again. Then `searching`: the live search's
    /// Withdraw says "Withdrawing…" until it fails 8 s later, since the
    /// offline socket never confirms one, with "Couldn’t withdraw" and its
    /// Retry for 4 s, and then the search leads again. Phones, and the Duo
    /// but closed upright: the bar. An iPad, in portrait with its sidebar
    /// hidden: the floating bar. The Duo closed upright draws its bar on one
    /// line, without Withdraw, which waits in Activity, so the journey skips
    /// there once it has seen that.
    func testTheBarsWithdrawShowsItsResult() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        var app = launch(.waiting, actions: .succeedListed)
        barLead(in: app)
        assertLeads("openChallenge \(openChallenge)", in: app)
        if isClosedUprightDuo(in: app) {
            assertTheBarIsOneLine(withoutItsAction: "Withdraw", in: app)
            throw XCTSkip("The Duo closed upright draws its bar on one line, without Withdraw, which waits in "
                          + "Activity: no result of the bar's own shows there.")
        }
        // Home's Searching card counts the searches and challenges the
        // service lists, the open challenge among them.
        let searching = element(ID.homeSearching, in: app)
        let searchingBefore = searching.label
        tap(element(ID.activityBarAction, in: app, matching: .button), description: "Withdraw", in: app)
        let tapped = Date()
        var reading = BarReading()
        // "Withdrawing…" lasts the fixture's 0.35 s, about one read.
        XCTAssertTrue(pollUntil(timeout: 10) {
            reading = self.barReading(in: app)
            return reading.lead?.label == "Withdrawn"
        }, "Withdraw shows Withdrawn: \(reading.state ?? "no bar")")
        let withdrawnAt = Date()
        XCTAssertEqual(reading.kindAndItem, "succeeded \(openChallenge)", "The result is the challenge's")
        keepScreenshot("Withdrawn in the bar", in: app)
        XCTAssertTrue(pollUntil(timeout: 10) {
            reading = self.barReading(in: app)
            return reading.lead?.label != "Withdrawn"
        }, "The result ends")
        // A slow read delays when the result is first seen, never its end,
        // so the lower bound counts from the tap.
        let ended = Date()
        attach(String(format: "Withdrawn ended %.1f s after the tap and %.1f s after it was first read; then: %@",
                      ended.timeIntervalSince(tapped), ended.timeIntervalSince(withdrawnAt), reading.state ?? "no bar"),
               name: "The result's 4 s")
        XCTAssertGreaterThanOrEqual(ended.timeIntervalSince(tapped), 2.5, "Withdrawn stays about 4 s")
        XCTAssertLessThanOrEqual(ended.timeIntervalSince(withdrawnAt), 7, "Withdrawn stays about 4 s")
        XCTAssertFalse(reading.state?.contains(openChallenge) ?? false, "The withdrawn challenge no longer leads")
        XCTAssertFalse(pollUntil(timeout: 2) { self.barReading(in: app).state?.contains(self.openChallenge) ?? false },
                       "The withdrawn challenge never comes back")
        attach("before: \(searchingBefore)\nafter: \(searching.label)", name: "Home's Searching card")
        XCTAssertEqual(searching.label, searchingBefore, "Home's Searching card still counts it: the service lists it")
        keepScreenshot("The next lead after Withdrawn", in: app)
        app.terminate()

        app = launch(.searching)
        barLead(in: app)
        assertLeads("search \(liveSearch)", in: app)
        let sent = Date()
        tap(element(ID.activityBarAction, in: app, matching: .button), description: "The search's Withdraw", in: app)
        XCTAssertTrue(pollUntil(timeout: 5) {
            reading = self.barReading(in: app)
            return reading.lead?.label == "Withdrawing…"
        }, "Withdraw shows Withdrawing…: \(reading.state ?? "no bar")")
        XCTAssertNil(reading.action, "While pending the bar offers no action")
        keepScreenshot("Withdrawing… in the bar", in: app)
        XCTAssertTrue(pollUntil(timeout: 15) {
            reading = self.barReading(in: app)
            return reading.lead?.label == "Couldn’t withdraw"
        }, "An unconfirmed search can't be withdrawn: \(reading.state ?? "no bar")")
        let waited = Date().timeIntervalSince(sent)
        let failedAt = Date()
        attach(String(format: "Couldn’t withdraw after %.1f s", waited), name: "The search's 8 s")
        XCTAssertGreaterThanOrEqual(waited, 7.5, "The search waits 8 s for OGS to confirm")
        XCTAssertEqual(reading.kindAndItem, "failed \(liveSearch)", "The failure is the search's")
        XCTAssertEqual(reading.action?.isEnabled, true, "Couldn’t withdraw offers its Retry")
        keepScreenshot("Couldn’t withdraw with Retry in the bar", in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { self.barReading(in: app).kindAndItem == "search \(self.liveSearch)" },
                      "After its 4 s the search leads again")
        let searchLeads = Date()
        attach(String(format: "Couldn’t withdraw ended %.1f s after the tap and %.1f s after it was first read",
                      searchLeads.timeIntervalSince(sent), searchLeads.timeIntervalSince(failedAt)),
               name: "The failure's 4 s")
        XCTAssertGreaterThanOrEqual(searchLeads.timeIntervalSince(sent), 11, "Couldn’t withdraw stays about 4 s after the 8 s")
        XCTAssertLessThanOrEqual(searchLeads.timeIntervalSince(failedAt), 7, "Couldn’t withdraw stays about 4 s")
        #endif
    }

    /// `challenge-received` with `succeed-listed`: CedarWave's challenge
    /// leads, and its lead opens Activity, where Reject succeeds while the
    /// service keeps listing the challenge, as OGS does until its next
    /// update. Once the list closes, the challenge neither leads nor counts:
    /// game 26268404, on their move, leads with nothing more. Phones: the bar
    /// and the list's sheet. An iPad, in portrait with its sidebar hidden:
    /// the floating bar and its popover. The Duo: a sheet closed upright, a
    /// popover in its wide poses.
    func testARejectInTheListLeavesTheBar() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.challengeReceived, actions: .succeedListed)
        let lead = barLead(in: app)
        assertLeads("challenge \(usualChallenge)", in: app)
        tap(lead, description: "CedarWave's challenge in the bar", in: app)
        element(ID.activityList, in: app)
        assertActivityPresentation(in: app)
        tap(ID.activityRow(usualChallenge, .reject), in: app, matching: .button)
        XCTAssertTrue(query(ID.activityRowResult(usualChallenge), in: app).exists(within: stateSettleTimeout),
                      "Reject shows its result in the list")
        keepScreenshot("CedarWave's challenge rejected in the list", in: app)
        closeList(in: app)
        // Home's own card of the challenge reads the service's lists.
        XCTAssertTrue(query(ID.profileChallengeEntry(FixtureID.usualChallengeID, cedarWaveID), in: app)
            .exists(within: 10), "Home still shows the challenge's card: the service lists it")

        barLead(in: app)
        assertLeads("live \(baseGame)", in: app)
        XCTAssertNil(activityPlusN(in: app), "The rejected challenge counts in no +N")
        XCTAssertFalse(pollUntil(timeout: 2) {
            self.activityBarAppliedState(in: app)?.contains(self.usualChallenge) ?? false || self.activityPlusN(in: app) != nil
        }, "The rejected challenge never comes back, though the service lists it")
        keepScreenshot("The bar after the reject", in: app)
        #endif
    }

    // MARK: When the bar hides

    /// `several`: no bar while a conversation shows, pushed or in Messages'
    /// pane, and the bar back once none does. Phones: Messages' root shows
    /// the bar, a conversation pushed from it in portrait hides it, and in
    /// landscape Messages has two columns, whose selected conversation hides
    /// it while Home's bar shows. An iPad, in portrait with its sidebar
    /// hidden: Messages always has two columns, so the pushed step skips, and
    /// the pane's conversation hides the floating bar. The Duo: the step its
    /// pose gives, pushed or in the pane, without a turn.
    func testTheBarHidesForConversations() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.several)
        barLead(in: app)
        selectMainNavigation(ID.navigationMessages, in: app)
        element(ID.screenMessages, in: app)
        if messagesHasTwoColumns(in: app) {
            note("Skipped the pushed conversation: Messages has two columns here")
            element("messages.conversation.heading", in: app)
            assertNoBar("Messages' pane conversation", in: app)
            keepScreenshot("Messages' pane conversation, with no bar", in: app)
        } else {
            barLead(in: app)
            tap(ID.privateMessageRow(tenukiTomID), in: app)
            let conversation = element("messages.conversation", in: app)
            assertNoBar("A pushed conversation", in: app)
            keepScreenshot("A pushed conversation, with no bar", in: app)
            backFromConversation(conversation, in: app)
            barLead(in: app)
            if isPhone && !isDuo {
                turnWindow(to: .landscapeLeft, in: app)
                XCTAssertTrue(messagesHasTwoColumns(in: app), "In landscape Messages has two columns")
                element("messages.conversation.heading", in: app)
                assertNoBar("Messages' pane conversation", in: app)
                keepScreenshot("Messages' pane conversation in landscape, with no bar", in: app)
                selectMainNavigation(ID.navigationHome, in: app)
                element(ID.screenHome, in: app)
                barLead(in: app)
                turnWindow(to: .portrait, in: app)
            }
        }
        selectMainNavigation(ID.navigationHome, in: app)
        element(ID.screenHome, in: app)
        barLead(in: app)
        assertLeads("live \(harborMist)", in: app)
        #endif
    }

    /// `several`: New game's sheet covers Home, and the bar waits under it,
    /// listed but not hittable, until Close. Phones and the Duo: the bar.
    /// An iPad, in portrait with its sidebar hidden: the floating bar, under
    /// the page sheet.
    func testTheBarWaitsUnderASheet() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.several)
        let lead = barLead(in: app)
        tap(ID.homeNewGame, in: app, matching: .button)
        let newGame = element(ID.screenNewGame, in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { lead.exists && !lead.isHittable },
                      "The bar waits under the sheet: \(lead.exists ? "listed" : "not listed")")
        XCTAssertTrue(query(ID.activityBar, in: app).exists, "The bar is still there, under the sheet")
        keepScreenshot("New game's sheet over the bar", in: app)
        tap(ID.newGameClose, in: app, matching: .button)
        XCTAssertTrue(waitForAbsence(newGame, timeout: stateSettleTimeout), "Close takes the sheet away")
        barLead(in: app)
        assertLeads("live \(harborMist)", in: app)
        #endif
    }

    /// `live-your-move` on Messages, whose inbox has no conversation, so its
    /// root shows the bar in one column or two. Messages' player search,
    /// with a space typed, since XCTest disconnects the simulator's hardware
    /// keyboard as it types, raises a docked software keyboard, which the
    /// journey confirms first: with none, as where the hardware keyboard
    /// stays connected, it fails. While the keyboard shows, the bar can't be
    /// tapped, and it comes back when the keyboard goes.
    /// - Phones with a bottom tab bar: the keyboard covers the bar with the
    ///   tab bar. UIKit's accessory stays set under it, as its Debug element
    ///   says, since the keyboard is no input there; SwiftUI's hides with the
    ///   tab bar; the custom bar, before iOS 26.1, hides itself.
    /// - An iPad, in portrait with its sidebar hidden, a Max iPhone in
    ///   landscape and the Duo, none of which has a bottom tab bar: the bar
    ///   goes.
    /// Phones check portrait, then landscape, where a Max has no bottom tab
    /// bar; the Duo keeps the pose Device Hub set.
    func testTheBarHidesWithTheKeyboard() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.liveYourMove)
        selectMainNavigation(ID.navigationMessages, in: app)
        element(ID.screenMessages, in: app)
        assertTheKeyboardHidesTheBar(leadingWith: harborMist, in: app)
        guard isPhone, !isDuo else { return }
        turnWindow(to: .landscapeLeft, in: app)
        assertTheKeyboardHidesTheBar(leadingWith: harborMist, in: app)
        turnWindow(to: .portrait, in: app)
        #endif
    }

    // MARK: Root status

    /// Signed out and offline (`--surround-signed-out-offline`): nothing
    /// waits, so root screens show status only, never a lead or +N. The
    /// socket starts down, so the words are "Reconnecting…" 2 s in and
    /// "Can’t reach OGS" with Retry 30 s in. iPhones and the Duo from iOS
    /// 26: the line under Home's title, and at Can’t reach OGS the bar too,
    /// with Retry. Before iOS 26: the custom bar's status kinds. An iPad: the
    /// Now section's status row alone, in landscape with its sidebar shown,
    /// then, after a turn to portrait with the sidebar hidden, the floating
    /// bar's status kind.
    func testSignedOutRootsShowStatusOnly() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launchSignedOut(sidebar: .shown)
        let carrier = rootStatusCarrier(in: app)
        assertSays(.reconnecting, on: carrier, in: app, within: 10)
        assertStatusOnly(in: app)
        keepScreenshot("Signed out: Reconnecting…", in: app)
        assertSays(.unreachable, on: carrier, in: app, within: 40)
        assertStatusOnly(in: app)
        if carrier == .nowRow {
            let section = element(ID.activityNow, in: app).frame.insetBy(dx: -1, dy: -1)
            XCTAssertTrue(section.contains(query(ID.rootConnectionStatus, in: app).frame),
                          "The status row is the Now section's: \(section)")
        }
        keepScreenshot("Signed out: Can’t reach OGS with Retry", in: app)
        if !isPhone {
            turnWindow(to: .portrait, in: app)
            showIPadSidebar(false, in: app)
            assertSays(.unreachable, on: .floatingBar, in: app, within: 10)
            XCTAssertTrue(query(ID.activityBar, in: app).exists, "The floating bar says it")
            assertStatusOnly(in: app)
            keepScreenshot("Signed out: the floating bar's Can’t reach OGS", in: app)
        }
        #endif
    }

    /// `nothing-waiting`, offline (`--surround-activity-connection offline`):
    /// the socket starts down, so before any connection the words are
    /// "Reconnecting…" 2 s in, then "Can’t reach OGS" with Retry 30 s in, and
    /// Retry gives "Reconnecting…" for at least 2 s. iPhones and the Duo from
    /// iOS 26: the navigation bar's line, then at Can’t reach OGS the bar
    /// too, with Retry, while the line keeps the words; after Retry the line,
    /// with no bar, since nothing waits. Before iOS 26, and on an iPad in
    /// portrait with its sidebar hidden: the floating bar's status kinds,
    /// whose label says "Reconnecting to OGS". The Now section's row is
    /// testSignedOutRootsShowStatusOnly's.
    func testRootStatusTurnsToCantReachOGSAndRetries() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let launched = Date()
        let app = launch(.nothingWaiting, offline: true)
        let carrier = rootStatusCarrier(in: app)
        assertSays(.reconnecting, on: carrier, in: app, within: 10)
        keepScreenshot("Reconnecting… on Home", in: app)
        assertSays(.unreachable, on: carrier, in: app, within: 45)
        attach(String(format: "Can’t reach OGS %.1f s after the launch began", Date().timeIntervalSince(launched)),
               name: "The 30 s turn")
        keepScreenshot("Can’t reach OGS with Retry on Home", in: app)

        tap(element(ID.rootConnectionStatusRetry, in: app, matching: .button), description: "Retry", in: app)
        assertSays(.reconnecting, on: carrier, in: app, within: 5)
        XCTAssertFalse(pollUntil(timeout: 2) { !self.says(.reconnecting, on: carrier, self.rootStatusReading(in: app)) },
                       "Reconnecting… holds for at least 2 s after Retry: \(rootStatusReading(in: app))")
        keepScreenshot("Reconnecting… after Retry", in: app)
        #endif
    }

    /// `several`, online, with the connection commands: the status shows 2 s
    /// after the drop, and after the restore "Connected" shows for 2 s,
    /// then nothing. iPhones and the Duo from iOS 26: the line under Home's
    /// title, and HarborMist's lead, a game's, says it as line two, in its
    /// label; after Connected the line keeps a space, so the title stays
    /// where the words put it until the root leaves, and back after a tab
    /// switch it is as before. Before iOS 26, where the bar carries all
    /// status: the lead's line two only, and no Connected, as a lead shows.
    /// An iPad, in landscape with its sidebar shown: the Now section's first
    /// row, HarborMist's row under it and CedarWave's back after Connected.
    func testADropAndRestoreOnARootSaysConnected() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.several, sidebar: .shown)
        let carrier = rootStatusCarrier(in: app)
        if carrier == .nowRow {
            nowRow(harborMist, in: app)
            nowRow(usualChallenge, in: app)
        } else {
            barLead(in: app)
            assertLeads("live \(harborMist)", in: app)
        }
        XCTAssertNil(rootStatusReading(in: app).words, "Online, nothing says the status")
        let titleBefore = carrier == .titleLine ? rootTitleFrame(in: app) : nil

        let dropped = Date()
        post(.drop)
        var delay: TimeInterval?
        XCTAssertTrue(pollUntil(timeout: 10) {
            let says = carrier == .floatingBar ? self.leadSaysReconnecting(in: app)
                : self.rootStatusReading(in: app).words == .reconnecting
            if says { delay = Date().timeIntervalSince(dropped) }
            return says
        }, "A drop shows the status")
        attach("The status showed \(delay.map { String(format: "%.2f", $0) } ?? "never") s after the drop",
               name: "The status's delay")
        XCTAssertGreaterThanOrEqual(delay ?? 0, 1.5, "The status waits about two seconds after the drop")
        // Each part follows the window's status a moment apart.
        switch carrier {
        case .titleLine:
            XCTAssertTrue(pollUntil(timeout: 5) { self.leadSaysReconnecting(in: app) },
                          "A game's lead says it as line two too")
        case .floatingBar:
            XCTAssertNil(rootStatusReading(in: app).element, "Beside a lead, the bar says it on line two alone")
        case .nowRow:
            XCTAssertTrue(nowRow(harborMist, in: app).exists, "HarborMist's row stays under the status row")
            XCTAssertTrue(pollUntil(timeout: 5) { !self.query(ID.activityNowRow(self.usualChallenge), in: app).exists },
                          "The status row takes the second row's place")
        }
        let titleDuring = carrier == .titleLine ? rootTitleFrame(in: app) : nil
        keepScreenshot("Reconnecting… after a drop", in: app)

        post(.restore)
        if carrier == .floatingBar {
            XCTAssertTrue(pollUntil(timeout: 10) { !self.leadSaysReconnecting(in: app) }, "The restore gives line two back")
            XCTAssertFalse(pollUntil(timeout: 3) { self.rootStatusReading(in: app).words == .connected },
                           "No Connected while a lead shows")
        } else {
            XCTAssertTrue(pollUntil(timeout: 5) { self.rootStatusReading(in: app).words == .connected },
                          "Connected after the restore")
            let connectedAt = Date()
            keepScreenshot("Connected after the restore", in: app)
            XCTAssertTrue(pollUntil(timeout: 6) { self.rootStatusReading(in: app).words == nil }, "Then nothing")
            let shown = Date().timeIntervalSince(connectedAt)
            attach(String(format: "Connected showed for %.1f s after it was first read", shown), name: "Connected's 2 s")
            // A slow first read shortens what is measured; this keeps out a flash.
            XCTAssertGreaterThanOrEqual(shown, 0.5, "Connected stays about 2 s")
            XCTAssertTrue(pollUntil(timeout: 5) { !self.leadSaysReconnecting(in: app) }, "The lead's line two is back")
        }
        if carrier == .nowRow {
            nowRow(usualChallenge, in: app)
        }
        if carrier == .titleLine, let titleBefore, let titleDuring, let titleAfter = rootTitleFrame(in: app) {
            attach("before \(titleBefore)\nduring \(titleDuring)\nafter \(titleAfter)", name: "Home's title")
            XCTAssertEqual(titleAfter.minY, titleDuring.minY, accuracy: 1.5,
                           "After Connected the line keeps its space, so the title stays")
            selectMainNavigation(ID.navigationPublicGames, in: app)
            element(ID.screenPublicGames, in: app)
            selectMainNavigation(ID.navigationHome, in: app)
            element(ID.screenHome, in: app)
            XCTAssertTrue(pollUntil(timeout: 5) {
                abs((self.rootTitleFrame(in: app)?.minY ?? .infinity) - titleBefore.minY) <= 1.5
            }, "Back on Home after a tab switch the title is as before: \(String(describing: rootTitleFrame(in: app)))")
        } else if carrier == .titleLine {
            XCTFail("Expected Home's title: before \(String(describing: titleBefore)), "
                    + "during \(String(describing: titleDuring))")
        }
        XCTAssertNil(rootStatusReading(in: app).words, "Nothing says the status")
        #endif
    }

    // MARK: The iPad's Now section

    /// An iPad in landscape with its sidebar shown, `several`: the Now
    /// section's rows are HarborMist's game and CedarWave's challenge, in
    /// the lead order, then All activity with +2, the two unread
    /// conversations. HarborMist's row opens its game, View opens
    /// CedarWave's card, and All activity opens a popover. Phones and the
    /// Duo have no Now section.
    func testTheNowSectionShowsTwoRowsAndAllActivity() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        try XCTSkipIf(isPhone, "iPad only: phones and the Duo have no Now section.")
        let app = launch(.several, sidebar: .shown)
        let game = nowRow(harborMist, in: app)
        let challenge = nowRow(usualChallenge, in: app)
        let all = element(ID.activityNowAll, in: app)
        let section = element(ID.activityNow, in: app).frame.insetBy(dx: -1, dy: -1)
        XCTAssertTrue([game, challenge, all].allSatisfy { section.contains($0.frame) },
                      "The rows and All activity are the Now section's: \(section)")
        XCTAssertLessThan(game.frame.minY, challenge.frame.minY, "HarborMist's game first, then the challenge")
        XCTAssertLessThan(challenge.frame.maxY, all.frame.maxY, "All activity last")
        XCTAssertFalse(query(ID.activityBar, in: app).exists, "Beside the sidebar there is no floating bar")
        XCTAssertFalse((game.value as? String ?? "").isEmpty, "The game's row says its clock's time")
        var plusN: Int?
        XCTAssertTrue(pollUntil(timeout: 10) {
            plusN = self.activityPlusN(in: app)
            return plusN == 2
        }, "All activity's +2: \(String(describing: plusN))")
        keepScreenshot("The Now section's two rows and All activity", in: app)

        tap(game, description: "HarborMist's row", in: app)
        element(ID.gameDetail(FixtureID.harborMistGameID), in: app)
        backToHome(from: FixtureID.harborMistGameID, in: app)
        showIPadSidebar(true, in: app)
        nowRow(harborMist, in: app)

        tap(ID.activityNowRowAction(usualChallenge), in: app, matching: .button)
        challengeCard(FixtureID.usualChallengeID, challenger: cedarWaveID, in: app)
        XCTAssertTrue(app.popovers.firstMatch.exists, "View opens Activity as a popover")
        keepScreenshot("CedarWave's card from the Now row's View", in: app)
        backToList(in: app)
        closeList(in: app)

        tap(all, description: "All activity", in: app)
        element(ID.activityList, in: app)
        XCTAssertTrue(app.popovers.firstMatch.exists(within: 10), "All activity opens a popover")
        keepScreenshot("Activity from All activity", in: app)
        closeList(in: app)
        #endif
    }

    /// An iPad, `several`: HarborMist's game opens from its Now row, and with
    /// the sidebar opened over it the section leaves that game out, keeping
    /// CedarWave's challenge and All activity. A drop then shows no status
    /// row over the game, which says its status itself; back on Home the
    /// status row shows. Phones and the Duo have no Now section.
    func testTheNowSectionLeavesOutTheGameOnScreen() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        try XCTSkipIf(isPhone, "iPad only: phones and the Duo have no Now section.")
        let app = launch(.several, sidebar: .shown)
        tap(nowRow(harborMist, in: app), description: "HarborMist's row", in: app)
        element(ID.gameDetail(FixtureID.harborMistGameID), in: app)
        showIPadSidebar(true, in: app)
        nowRow(usualChallenge, in: app)
        element(ID.activityNowAll, in: app)
        XCTAssertFalse(query(ID.activityNowRow(harborMist), in: app).exists, "The section leaves the game on screen out")
        keepScreenshot("The Now section over HarborMist's game", in: app)

        let dropped = Date()
        post(.drop)
        XCTAssertFalse(pollUntil(timeout: 4) { self.query(ID.rootConnectionStatus, in: app).exists },
                       "No status row over the game")
        XCTAssertFalse(query(ID.activityNowRow(harborMist), in: app).exists, "Still no row for the game on screen")
        keepScreenshot("No status row over the game, offline", in: app)
        showIPadSidebar(false, in: app)
        backToHome(from: FixtureID.harborMistGameID, in: app)
        showIPadSidebar(true, in: app)
        // A slow runner can come back after the outage's 30 s, when the row
        // says Can’t reach OGS: either way it shows.
        XCTAssertTrue(pollUntil(timeout: 10) {
            [.reconnecting, .unreachable].contains(self.rootStatusReading(in: app).element)
        }, "Back on Home, the status row shows: the outage is \(Int(Date().timeIntervalSince(dropped))) s old")
        post(.restore)
        #endif
    }

    /// An iPad in landscape at full size with its sidebar shown, in Thai,
    /// whose lines iOS sets taller, at XL, the largest text size at which an
    /// 834 pt window lists a Now row there: `several`'s section starts below
    /// the sidebar's last tab row, Web version, never over it, and lists a
    /// row wherever the window is at least 834 pt tall. One snapshot reads
    /// the tab rows and the section. It stays on Home, as the tab titles are
    /// Thai, and the device ends in portrait. Phones and the Duo have no Now
    /// section.
    func testTheNowSectionClearsTheTabRowsInThai() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        try XCTSkipIf(isPhone, "iPad only: phones and the Duo have no Now section.")
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        let app = launch(.several, sidebar: .shown, language: "th", textSize: .extraLarge)
        let window = windowFrame(in: app)
        let listsARow = window.height >= 834
        if listsARow { nowRow(harborMist, in: app) }
        var reading = NowSectionReading()
        XCTAssertTrue(pollUntil(timeout: 5) {
            reading = self.nowSectionReading(in: app)
            return reading.lastTabRow != nil && (!listsARow || !reading.rows.isEmpty)
        }, "The sidebar's tab rows\(listsARow ? " and a Now row" : ""): \(reading)")
        attach("window \(window)\n\(reading)", name: "The last tab row and the Now section")
        keepScreenshot("The Now section below the last tab row, in Thai at XL", in: app)
        XCTAssertEqual(reading.lastTabRow?.identifier, ID.navigationBrowser, "Web version is the last tab row")
        if listsARow { XCTAssertNotNil(reading.section, "The Now section is in the snapshot: \(reading)") }
        if let section = reading.section, let lastTabRow = reading.lastTabRow {
            XCTAssertGreaterThanOrEqual(section.minY, lastTabRow.frame.maxY,
                                        "The section starts below the last tab row: \(reading)")
        }
        #endif
    }

    /// What the iPad journey's teardown gives back: the app as it was last
    /// launched, and whether its window is resized. Teardown blocks are
    /// sendable, so the journey hands them this box rather than variables it
    /// changes after adding the block.
    private final class WindowToGiveBack: @unchecked Sendable {
        var app: XCUIApplication
        var isResized = false

        init(_ app: XCUIApplication) { self.app = app }
    }

    /// An iPad from iPadOS 26, whose floating bar is UIKit's accessory, in
    /// both orientations, at full size and in a 375 × 548 window.
    /// - `several` in landscape at full size with the sidebar shown, which
    ///   27.0 launches hidden, so its toggle shows it first: no floating bar
    ///   beside the sidebar, whose Now section leads instead. The bar comes
    ///   back once the sidebar's hide completes and goes as it starts to
    ///   show, so no read lists the bar beside the sidebar, and the Debug
    ///   element says what the host applied. All activity's popover closes
    ///   as a turn to portrait hides the sidebar, and after the turn back
    ///   the sidebar's toggle is a button.
    /// - The live-game banner fixture, whose Home lists a finished game and
    ///   whose Messages has no conversation. That game opens from Home and as
    ///   a linked game from its opponent's pushed profile, in landscape with
    ///   the sidebar folded and in the 375 × 548 window: the bar clears as
    ///   soon as the game is asked for, so no read lists the board beside it,
    ///   and the board settles where the same opens put it with the custom
    ///   bar (`--surround-notices-force-custom-bar`), which draws on roots
    ///   only, never in a game. These launches log each of the board's
    ///   layouts (`--surround-activity-hidden-log`). A docked keyboard over
    ///   the full-size window, raised on Messages' root in portrait, takes
    ///   the bar away until it goes.
    /// The window ends at full size and the device in portrait, even when the
    /// journey fails. Phones and the Duo have no iPad sidebar, and iPadOS 18
    /// floats the custom bar, in windows its simulator can't resize.
    func testTheIPadSidebarAndTheFloatingBar() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        try XCTSkipIf(isPhone, "iPad only: phones and the Duo have no iPad sidebar.")
        try XCTSkipUnless(expectedBarHost == "uiKitAccessory",
                          "From iPadOS 26, whose floating bar is UIKit's accessory and whose windows resize.")
        var app = launch(.several, sidebar: .shown)
        // iPadOS keeps a window's size across launches and gives it back on a
        // later turn to portrait, even after a fill: grow the window back with
        // its grabber, after a relaunch should the app have stopped, and turn
        // the device back. The full portrait window is the launch's, turned.
        let launched = windowFrame(in: app)
        let fullWindow = CGRect(x: 0, y: 0, width: min(launched.width, launched.height),
                                height: max(launched.width, launched.height))
        let giveBack = WindowToGiveBack(app)
        addTeardownBlock { [weak self] in
            XCUIDevice.shared.orientation = .portrait
            guard giveBack.isResized else { return }
            if giveBack.app.state != .runningForeground { giveBack.app.launch() }
            self?.growWindowBack(to: fullWindow, in: giveBack.app)
        }

        // The sidebar or the floating bar, never both.
        nowRow(harborMist, in: app)
        assertNoBar("Beside the shown sidebar", in: app)
        XCTAssertNil(activityBarAppliedState(in: app), "Beside the shown sidebar the host applies no bar")
        keepScreenshot("Landscape at full size: the Now section, no floating bar", in: app)
        toggleSidebar(shown: false, in: app)
        assertLeads("live \(harborMist)", in: app)
        toggleSidebar(shown: true, in: app)
        nowRow(harborMist, in: app)
        XCTAssertNil(activityBarAppliedState(in: app), "Beside the shown sidebar the host applies no bar")

        // All activity's popover closes as a turn hides the sidebar.
        tap(element(ID.activityNowAll, in: app), description: "All activity", in: app)
        element(ID.activityList, in: app)
        XCTAssertTrue(app.popovers.firstMatch.exists(within: 10), "All activity opens a popover")
        turnWindow(to: .portrait, in: app)
        XCTAssertTrue(pollUntil(timeout: 5) { !self.iPadSidebarIsShown(in: app) }, "A turn to portrait hides the sidebar")
        XCTAssertTrue(waitForAbsence(query(ID.activityList, in: app), timeout: 5),
                      "All activity's popover closes as the turn hides the sidebar")
        barLead(in: app)
        assertLeads("live \(harborMist)", in: app)

        // Back in landscape, the sidebar's toggle is a button.
        turnWindow(to: .landscapeLeft, in: app)
        let toggleIsAButton = pollUntil(timeout: 10) { self.nativeSidebarToggle(in: app) != nil }
        if !toggleIsAButton { attach(app.debugDescription, name: "Accessibility hierarchy – no sidebar toggle") }
        XCTAssertTrue(toggleIsAButton, "After a turn to portrait and back, the sidebar's toggle is a button")
        if iPadSidebarIsShown(in: app) {
            nowRow(harborMist, in: app)
            assertNoBar("Beside the sidebar after the turns", in: app)
        } else {
            barLead(in: app)
            assertLeads("live \(harborMist)", in: app)
        }
        app.terminate()

        // The finished game's board: with the custom bar, then with the accessory.
        var opens = [Bool: [String: BoardOpen]]()
        for forcesCustomBar in [true, false] {
            let withAccessory = !forcesCustomBar
            app = launchLiveGameBanner(forcingTheCustomBar: forcesCustomBar)
            giveBack.app = app
            showIPadSidebar(false, in: app)
            if withAccessory {
                barLead(in: app)
                assertLeads("live \(baseGame)", in: app)
            }
            var boards = [String: BoardOpen]()
            boards["landscape, from Home"] = openTheFinishedGameFromHome(withAccessory: withAccessory, in: app)
            boards["landscape, linked"] = openTheFinishedGameFromItsOpponent(withAccessory: withAccessory, in: app)
            turnWindow(to: .portrait, in: app)
            showIPadSidebar(false, in: app)
            giveBack.isResized = true
            let window = resizeWindow(to: CGSize(width: 375, height: 548), in: app)
            XCTAssertEqual(window.width, 375, accuracy: 1, "The window reaches 375 pt wide")
            XCTAssertEqual(window.height, 548, accuracy: 1, "The window reaches 548 pt tall")
            if withAccessory {
                barLead(in: app)
                assertLeads("live \(baseGame)", in: app)
                if let tabBar = bottomTabBar(in: app)?.frame {
                    XCTAssertLessThanOrEqual(query(ID.activityBar, in: app).frame.maxY, tabBar.minY + 1,
                                             "In the compact window the bar floats above the bottom tab bar")
                } else {
                    XCTFail("A compact window has a bottom tab bar")
                }
                keepScreenshot("The 375 × 548 window with the floating bar", in: app)
            }
            boards["375 × 548, from Home"] = openTheFinishedGameFromHome(withAccessory: withAccessory, in: app)
            boards["375 × 548, linked"] = openTheFinishedGameFromItsOpponent(withAccessory: withAccessory, in: app)
            growWindowBack(to: fullWindow, in: app)
            giveBack.isResized = false
            // After the opens, so both passes open the game after the same steps.
            if withAccessory {
                selectMainNavigation(ID.navigationMessages, in: app)
                element(ID.screenMessages, in: app)
                assertTheKeyboardHidesTheBar(leadingWith: baseGame, in: app)
            }
            opens[forcesCustomBar] = boards
            app.terminate()
        }
        for key in ["landscape, from Home", "landscape, linked", "375 × 548, from Home", "375 × 548, linked"] {
            let accessory = opens[false]?[key], customBar = opens[true]?[key]
            attach("With UIKit's accessory: \(accessory?.summary ?? "not opened")\n"
                   + "With the custom bar: \(customBar?.summary ?? "not opened")", name: "The board, \(key)")
            guard let accessory, let customBar, let settled = accessory.settled, let control = customBar.settled else {
                XCTFail("\(key): each open reads a settled board")
                continue
            }
            // A resize lands within a point of 375 × 548 either way, and the
            // board in that window follows its height, so the two windows'
            // own difference is allowed too.
            let slack = abs(accessory.window.width - customBar.window.width)
                + abs(accessory.window.height - customBar.window.height)
            for (side, a, b) in [("left", settled.minX, control.minX), ("top", settled.minY, control.minY),
                                 ("width", settled.width, control.width), ("height", settled.height, control.height)] {
                XCTAssertEqual(a, b, accuracy: 1 + slack,
                               "\(key): the board's \(side) settles where the same open puts it with the custom bar")
            }
        }
        #endif
    }

    #if targetEnvironment(macCatalyst)
    // MARK: The Mac's Now section and its Activity command

    /// The Mac's sidebar ends in the Now section: HarborMist's game, then
    /// CedarWave's challenge with View, and All activity, below the last tab
    /// row at 900 × 600 and at the window's bottom through a live resize to
    /// 1200 × 760. XCTest reaches the rows and All activity by their
    /// identifiers, never the section's, and a click at a frame's centre
    /// acts: All activity and the challenge's row open Activity as a popover
    /// in a window of its own, which Escape closes; View pushes the
    /// challenge's card in it; the game's row opens the game, over which the
    /// section leaves it out. Every root keeps the window title the desktop
    /// capture contract pins.
    func testTheMacsNowSectionOpensActivityAndItsRows() {
        let app = launchMac([SurroundUITestContract.activityStateLaunchArgument, State.several.rawValue],
                            size: CGSize(width: 900, height: 600))
        let game = query(ID.activityNowRow(harborMist), in: app)
        let challenge = query(ID.activityNowRow(usualChallenge), in: app)
        let view = query(ID.activityNowRowAction(usualChallenge), in: app)
        let all = query(ID.activityNowAll, in: app)
        for (element, name) in [(game, "HarborMist's game"), (challenge, "CedarWave's challenge"),
                                (view, "its View"), (all, "All activity")] {
            XCTAssertTrue(element.exists(within: 10), "The Now section shows \(name)")
        }
        XCTAssertFalse(query(ID.activityNowRowAction(harborMist), in: app).exists, "A live game's row has no action")
        attach("label \(all.label)\nvalue \(String(describing: all.value))", name: "All activity")
        assertNowSection(at: "900 × 600", rows: [game, challenge], all: all, in: app)
        assertWindowTitle("Active games", in: app)
        keepWindowScreenshots("The Mac's Now section at 900 × 600", in: app)

        openPopover(byClicking: all, name: "All activity", in: app)
        openPopover(byClicking: challenge, name: "the challenge's row", in: app)
        // The card is pushed at once, so the list itself is never in sight:
        // Escape closes the card's popover, and its window goes.
        let windows = app.windows.count
        click(view, name: "View")
        let card = app.navigationBars["Challenge"].firstMatch
        XCTAssertTrue(card.exists(within: 10), "View pushes the challenge's card")
        XCTAssertGreaterThan(app.windows.count, windows, "View opens a popover, a window of its own")
        keepWindowScreenshots("The challenge's card from View", in: app)
        closeWithEscape("View's popover", leaving: card, in: app)
        XCTAssertTrue(pollUntil(timeout: stateSettleTimeout) { app.windows.count == windows },
                      "View's popover closes with its window: \(app.windows.count) windows, \(windows) before")

        click(game, name: "HarborMist's game")
        element(ID.gameDetail(FixtureID.harborMistGameID), in: app)
        XCTAssertTrue(waitForAbsence(game, timeout: stateSettleTimeout), "Over its game the section leaves it out")
        XCTAssertTrue(challenge.exists && all.exists, "The section keeps the rest over the game")
        keepWindowScreenshots("The Now section over HarborMist's game", in: app)
        goBack(in: app)
        element(ID.screenHome, in: app)
        XCTAssertTrue(game.exists(within: 10), "Back on Home, the game's row comes back")

        resizeMacWindow(toContent: CGSize(width: 1200, height: 760), in: app)
        assertNowSection(at: "1200 × 760 after a live resize", rows: [game, challenge], all: all, in: app)
        keepWindowScreenshots("The Mac's Now section at 1200 × 760", in: app)

        for (entry, title) in Self.macRootTitles {
            selectSidebarEntry(entry, in: app)
            assertWindowTitle(title, in: app)
            XCTAssertTrue(all.exists(within: 10), "The section shows beside \(title)")
        }
    }

    /// View > Activity and ⇧⌘A open Activity as All activity does: while the
    /// Now section shows, a popover where All activity's own opens, which
    /// Escape closes, and over a game too, with the game left out of it.
    /// With nothing waiting there is no section, the window's title stays,
    /// and they open the sheet, which Done closes.
    func testTheMacsActivityCommandOpensActivity() {
        var app = launchMac([SurroundUITestContract.activityStateLaunchArgument, State.several.rawValue],
                            size: CGSize(width: 900, height: 600))
        let all = query(ID.activityNowAll, in: app)
        XCTAssertTrue(all.exists(within: 10), "The Now section shows All activity")
        let fromAllActivity = openPopover(byClicking: all, name: "All activity", in: app)

        chooseActivityInViewMenu(in: app)
        let fromMenu = assertPopover("View > Activity", in: app)
        XCTAssertEqual(fromMenu.midX, fromAllActivity.midX, accuracy: 2, "The menu's popover hangs from All activity")
        XCTAssertEqual(fromMenu.midY, fromAllActivity.midY, accuracy: 2, "The menu's popover hangs from All activity")
        keepWindowScreenshots("Activity from View > Activity", in: app)
        closeWithEscape("the menu's popover", in: app)

        app.typeKey("a", modifierFlags: [.command, .shift])
        let fromShortcut = assertPopover("⇧⌘A", in: app)
        XCTAssertEqual(fromShortcut.midY, fromAllActivity.midY, accuracy: 2, "The shortcut's popover hangs from All activity")
        closeWithEscape("the shortcut's popover", in: app)

        click(query(ID.activityNowRow(harborMist), in: app), name: "HarborMist's game")
        element(ID.gameDetail(FixtureID.harborMistGameID), in: app)
        app.typeKey("a", modifierFlags: [.command, .shift])
        assertPopover("⇧⌘A over a game", in: app)
        XCTAssertFalse(query(ID.activityRow(harborMist), in: app).exists, "The game on screen isn't listed")
        keepWindowScreenshots("Activity from ⇧⌘A over a game", in: app)
        closeWithEscape("the game's popover", in: app)
        app.terminate()

        app = launchMac([SurroundUITestContract.activityStateLaunchArgument, State.nothingWaiting.rawValue],
                        size: CGSize(width: 900, height: 600))
        assertNoNowSection("Nothing waiting", in: app)
        assertWindowTitle("Active games", in: app)
        keepWindowScreenshots("No Now section with nothing waiting", in: app)
        chooseActivityInViewMenu(in: app)
        closeSheet("View > Activity with nothing waiting", in: app)
        app.typeKey("a", modifierFlags: [.command, .shift])
        closeSheet("⇧⌘A with nothing waiting", in: app)
    }

    /// Signed out nothing waits, so the sidebar's Now section has no rows and
    /// no All activity at 900 × 600 or after a live resize to 1200 × 760,
    /// only, as the launch is offline, its status row; and the roots keep
    /// the contract's window titles. There is no Activity either, so View >
    /// Activity is off and ⇧⌘A opens nothing.
    func testTheMacsSidebarHasNoNowSectionSignedOut() {
        let app = launchMac([SurroundUITestContract.signedOutOfflineLaunchArgument],
                            size: CGSize(width: 900, height: 600), screen: nil)
        assertWindowTitle("Welcome", in: app)
        assertNoNowSection("Signed out at 900 × 600", in: app)
        let status = query(ID.rootConnectionStatus, in: app)
        XCTAssertTrue(waitForLabel("Reconnecting to OGS", of: status), "Offline, the Now section's status row alone")
        keepWindowScreenshots("Signed out at 900 × 600", in: app)
        assertActivityInViewMenuIsOff(in: app)
        app.typeKey("a", modifierFlags: [.command, .shift])
        XCTAssertFalse(pollUntil(timeout: 3) { self.query(ID.activityList, in: app).exists },
                       "Signed out, ⇧⌘A opens no Activity")
        resizeMacWindow(toContent: CGSize(width: 1200, height: 760), in: app)
        assertNoNowSection("Signed out at 1200 × 760", in: app)
        keepWindowScreenshots("Signed out at 1200 × 760", in: app)
        for (entry, title) in Self.macRootTitles where entry != ID.navigationMessages && entry != ID.navigationHome {
            selectSidebarEntry(entry, in: app)
            assertWindowTitle(title, in: app)
        }
        assertNoNowSection("Signed out on Web version", in: app)
    }

    /// What the three journeys above leave out of the Now section's status,
    /// signed in and offline. The window's status takes the section's first
    /// row: "Reconnecting to OGS", and 30 s in "Can’t reach OGS" with Retry,
    /// whose click says Reconnecting to OGS again. HarborMist's row and All
    /// activity stay below it, All activity counting the challenge the row
    /// displaced. A game says its status itself, so over HarborMist's game
    /// no status row shows, and back on Home it does. With nothing waiting
    /// the status row is all the section shows. No window title changes for
    /// any of it.
    func testTheMacsNowSectionAndStatus() {
        let offline = [SurroundUITestContract.activityConnectionLaunchArgument,
                       SurroundUITestContract.ActivityFixtureConnection.offline.rawValue]
        var app = launchMac([SurroundUITestContract.activityStateLaunchArgument, State.several.rawValue] + offline,
                            size: CGSize(width: 900, height: 600))
        let status = query(ID.rootConnectionStatus, in: app)
        let game = query(ID.activityNowRow(harborMist), in: app)
        let all = query(ID.activityNowAll, in: app)
        XCTAssertTrue(waitForLabel("Reconnecting to OGS", of: status), "Offline, the first row says the status")
        XCTAssertTrue(game.exists(within: 10) && all.exists, "HarborMist's row and All activity stay below it")
        XCTAssertFalse(query(ID.activityNowRow(usualChallenge), in: app).exists,
                       "The status row takes the second row's place")
        XCTAssertEqual(Int((all.value as? String ?? "").prefix { $0.isNumber }), 3,
                       "All activity counts the challenge the status row displaced: \(String(describing: all.value))")
        assertNowSection(at: "900 × 600, offline", rows: [status, game], all: all, in: app)
        assertWindowTitle("Active games", in: app)
        keepWindowScreenshots("The Mac's status row: Reconnecting", in: app)

        XCTAssertTrue(waitForLabel("Can’t reach OGS", of: status, timeout: 40), "30 s in, Can’t reach OGS")
        let retry = query(ID.rootConnectionStatusRetry, in: app)
        XCTAssertTrue(retry.exists(within: 10), "Can’t reach OGS offers Retry")
        assertWindowTitle("Active games", in: app)
        keepWindowScreenshots("The Mac's status row: Can’t reach OGS with Retry", in: app)
        click(retry, name: "Retry")
        XCTAssertTrue(waitForLabel("Reconnecting to OGS", of: status, timeout: 10), "Retry says Reconnecting again")

        click(game, name: "HarborMist's game")
        element(ID.gameDetail(FixtureID.harborMistGameID), in: app)
        XCTAssertTrue(waitForAbsence(status, timeout: stateSettleTimeout), "Over a game no status row shows")
        XCTAssertTrue(all.exists, "The section keeps its rows over the game")
        keepWindowScreenshots("No status row over HarborMist's game", in: app)
        goBack(in: app)
        element(ID.screenHome, in: app)
        XCTAssertTrue(status.exists(within: 10), "Back on Home, the status row shows again")
        assertWindowTitle("Active games", in: app)
        app.terminate()

        app = launchMac([SurroundUITestContract.activityStateLaunchArgument, State.nothingWaiting.rawValue] + offline,
                        size: CGSize(width: 900, height: 600))
        XCTAssertTrue(waitForLabel("Reconnecting to OGS", of: query(ID.rootConnectionStatus, in: app)),
                      "With nothing waiting, offline, the section shows its status row")
        assertNoNowSection("Nothing waiting, offline", in: app)
        assertWindowTitle("Active games", in: app)
        keepWindowScreenshots("Nothing waiting, offline: the status row alone", in: app)
    }

    /// The roots the desktop capture contract pins, with their window titles
    /// (CompatibilityScreenshotTests), Home last.
    private static let macRootTitles: [(entry: String, title: String)] = [
        (ID.navigationPublicGames, "Public live games"), (ID.navigationMessages, "Messages"),
        (ID.navigationSettings, "Settings"), (ID.navigationAbout, "About"),
        (ID.navigationBrowser, "Web version"), (ID.navigationHome, "Active games"),
    ]

    /// A launch whose window content has `size`, at Home or `screen`.
    private func launchMac(_ arguments: [String], size: CGSize, screen: String? = ID.screenHome,
                           file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        let app = launchApp(additionalLaunchArguments: arguments + [
            SurroundUITestContract.catalystWindowSizeLaunchArgument, "\(Int(size.width))x\(Int(size.height))",
        ])
        XCTAssertTrue(pollUntil(timeout: 15) { self.contentSize(in: app, isAbout: size) },
                      "The window's content is \(size): \(String(describing: contentSize(in: app)))",
                      file: file, line: line)
        if let screen { element(screen, in: app, file: file, line: line) }
        return app
    }

    /// The window's content size, as the app's window geometry element says
    /// it ("900x600|…").
    private func contentSize(in app: XCUIApplication) -> CGSize? {
        let value = query(ID.catalystWindowGeometry, in: app).value as? String ?? ""
        let size = value.split(separator: "|").first?.split(separator: "x").compactMap { Double($0) } ?? []
        return size.count == 2 ? CGSize(width: size[0], height: size[1]) : nil
    }

    /// The section in the sidebar's 220 pt column: its rows in order below
    /// the last tab row, then All activity at the window's bottom.
    private func assertNowSection(at name: String, rows: [XCUIElement], all: XCUIElement, in app: XCUIApplication,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let window = mainWindow(app).frame
        let lastTab = query(ID.navigationBrowser, in: app).frame
        let frames = (rows + [all]).map(\.frame)
        attach((["window \(window)", "Web version \(lastTab)"]
                + zip(rows + [all], frames).map { "\($0.identifier) \($1)" }).joined(separator: "\n"),
               name: "The Now section at \(name)")
        for (element, frame) in zip(rows + [all], frames) {
            XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(frame),
                          "\(name): \(element.identifier) is in the window", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, window.minX + 221,
                                     "\(name): \(element.identifier) is in the sidebar", file: file, line: line)
        }
        XCTAssertEqual(frames.map(\.minY), frames.map(\.minY).sorted(), "\(name): the rows, then All activity",
                       file: file, line: line)
        XCTAssertFalse(lastTab.isEmpty, "\(name): the sidebar lists Web version", file: file, line: line)
        if let first = frames.first, !lastTab.isEmpty {
            XCTAssertGreaterThan(first.minY, lastTab.maxY, "\(name): the section is clear of the last tab row",
                                 file: file, line: line)
        }
        XCTAssertLessThanOrEqual(window.maxY - all.frame.maxY, 20, "\(name): All activity is at the window's bottom",
                                 file: file, line: line)
    }

    private func assertNoNowSection(_ name: String, in app: XCUIApplication,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let section = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "activity.now.")).firstMatch
        XCTAssertFalse(pollUntil(timeout: 3) { section.exists }, "\(name): no Now section", file: file, line: line)
    }

    /// The main window's title, exactly as the desktop capture contract pins
    /// it: no subtitle joins it.
    private func assertWindowTitle(_ expected: String, in app: XCUIApplication,
                                   file: StaticString = #filePath, line: UInt = #line) {
        var title = ""
        let found = pollUntil(timeout: 10) {
            title = self.mainWindow(app).title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title == expected
        }
        XCTAssertTrue(found, "The window's title is '\(expected)'; found '\(title)'", file: file, line: line)
    }

    /// Clicks `opener`: Activity opens as a popover in a window of its own,
    /// which Escape closes. The list's frame, where the popover hangs.
    @discardableResult
    private func openPopover(byClicking opener: XCUIElement, name: String, in app: XCUIApplication,
                             file: StaticString = #filePath, line: UInt = #line) -> CGRect {
        let windows = app.windows.count
        click(opener, name: name, file: file, line: line)
        let frame = assertPopover(name, in: app, file: file, line: line)
        XCTAssertGreaterThan(app.windows.count, windows, "\(name)'s popover is a window of its own",
                             file: file, line: line)
        keepWindowScreenshots("Activity from \(name)", in: app)
        closeWithEscape("\(name)'s popover", in: app, file: file, line: line)
        return frame
    }

    /// Activity is open as a popover, which has no Done. The list's frame.
    @discardableResult
    private func assertPopover(_ name: String, in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) -> CGRect {
        let list = element(ID.activityList, in: app, file: file, line: line)
        XCTAssertFalse(query(ID.activityDone, in: app).exists, "\(name) opens a popover, which has no Done",
                       file: file, line: line)
        var frame = CGRect.null
        _ = pollUntil(timeout: 5) {
            let current = list.frame
            defer { frame = current }
            return !current.isEmpty && current == frame
        }
        attach("\(name): list \(frame)\nwindows \(app.windows.allElementsBoundByIndex.map(\.frame))",
               name: "Activity's popover from \(name)")
        return frame
    }

    /// Escape closes the popover `name`: what it shows leaves, Activity's
    /// list unless `shown` names something else on top of it.
    private func closeWithEscape(_ name: String, leaving shown: XCUIElement? = nil, in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertTrue(waitForAbsence(shown ?? query(ID.activityList, in: app), timeout: stateSettleTimeout),
                      "Escape closes \(name)", file: file, line: line)
    }

    /// Activity is open as the sheet, with nothing waiting in it; Done
    /// closes it.
    private func closeSheet(_ name: String, in app: XCUIApplication,
                            file: StaticString = #filePath, line: UInt = #line) {
        let list = element(ID.activityList, in: app, file: file, line: line)
        let done = query(ID.activityDone, in: app)
        XCTAssertTrue(done.exists(within: 10), "\(name) opens the sheet, with Done", file: file, line: line)
        XCTAssertTrue(query(ID.activityEmpty, in: app).exists(within: 10), "\(name): nothing waiting",
                      file: file, line: line)
        keepWindowScreenshots("Activity's sheet from \(name)", in: app)
        click(done, name: "Done", file: file, line: line)
        XCTAssertTrue(waitForAbsence(list, timeout: stateSettleTimeout), "Done closes \(name)'s sheet",
                      file: file, line: line)
    }

    /// Chooses View > Activity in the menu bar.
    private func chooseActivityInViewMenu(in app: XCUIApplication, file: StaticString = #filePath,
                                          line: UInt = #line) {
        let view = app.menuBars.menuBarItems["View"].firstMatch
        XCTAssertTrue(view.exists(within: 10), "The menu bar has View", file: file, line: line)
        view.click()
        let item = view.menuItems["Activity"].firstMatch
        if !item.exists(within: 5) {
            attach(app.menuBars.firstMatch.debugDescription, name: "The menu bar")
        }
        XCTAssertTrue(item.exists, "View has Activity", file: file, line: line)
        XCTAssertTrue(item.isEnabled, "View > Activity is enabled", file: file, line: line)
        item.click()
    }

    /// View has Activity, off: the window in front has no Activity.
    private func assertActivityInViewMenuIsOff(in app: XCUIApplication, file: StaticString = #filePath,
                                               line: UInt = #line) {
        let view = app.menuBars.menuBarItems["View"].firstMatch
        XCTAssertTrue(view.exists(within: 10), "The menu bar has View", file: file, line: line)
        view.click()
        let item = view.menuItems["Activity"].firstMatch
        XCTAssertTrue(item.exists(within: 5), "View has Activity", file: file, line: line)
        XCTAssertFalse(item.isEnabled, "View > Activity is off signed out", file: file, line: line)
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
    }

    /// Drags the window's bottom right corner until its content is `size`,
    /// as a person resizes it: a live resize.
    private func resizeMacWindow(toContent size: CGSize, in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<4 {
            guard let current = contentSize(in: app), !contentSize(in: app, isAbout: size) else { break }
            let delta = CGVector(dx: size.width - current.width, dy: size.height - current.height)
            let corner = mainWindow(app).coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
                .withOffset(CGVector(dx: -2, dy: -2))
            corner.click(forDuration: 0.6, thenDragTo: corner.withOffset(delta))
            _ = pollUntil(timeout: 3) { self.contentSize(in: app, isAbout: size) }
        }
        XCTAssertTrue(contentSize(in: app, isAbout: size),
                      "A live resize brings the window's content to \(size): \(String(describing: contentSize(in: app)))",
                      file: file, line: line)
    }

    /// The window's content is `size` to within 6 points either way: a live
    /// resize stops a few points short, as it gave 1198 × 759 and 1196 × 758
    /// for 1200 × 760, and a corrective drag that small doesn't take.
    private func contentSize(in app: XCUIApplication, isAbout size: CGSize) -> Bool {
        guard let measured = contentSize(in: app) else { return false }
        return abs(measured.width - size.width) <= 6 && abs(measured.height - size.height) <= 6
    }
    #endif

    // MARK: The minimized tab bar

    /// `several` on Home, scrolled down until the tab bar minimizes: iPhones
    /// on iOS 27, whose UIKit tab container minimizes as a list scrolls down,
    /// from 27.0. Beside the minimized tab bar the bar is inline, with
    /// HarborMist's lead and +3; 30 s after a drop, its inline "Can’t reach
    /// OGS" keeps Retry. Minimized, the tab bar lists the selected tab
    /// alone, so it expands before another tab is tapped. The Duo: its rail
    /// and its drawer never minimize, so Home scrolled down leaves the bar
    /// in its own form. Nothing minimizes before iOS 27 or on an iPad, and
    /// the Mac has no bar.
    func testTheMinimizedBarKeepsItsCount() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        try XCTSkipUnless(isPhone && expectedBarHost == "uiKitAccessory",
                          "iPhones on iOS 27 only: nothing minimizes before iOS 27 or on an iPad.")
        let app = launch(.several)
        barLead(in: app)
        assertLeads("live \(harborMist)", in: app)
        if isDuo {
            for _ in 0..<2 { dragHomeUp(in: app) }
            XCTAssertFalse(pollUntil(timeout: 2) { self.activityBarAppliedState(in: app)?.hasSuffix(" inline") ?? false },
                           "The Duo's rail and drawer never minimize, so the bar keeps its form: "
                           + (activityBarAppliedState(in: app) ?? "no bar"))
            return
        }
        scrollHomeDownUntilTheTabBarMinimizes(in: app)
        var reading = BarReading()
        XCTAssertTrue(pollUntil(timeout: 10) {
            reading = self.barReading(in: app)
            return reading.state?.hasSuffix(" inline") ?? false
        }, "Beside the minimized tab bar the bar is inline: \(reading.state ?? "no bar")")
        XCTAssertEqual(reading.kindAndItem, "live \(harborMist)", "Inline, HarborMist's game leads")
        XCTAssertTrue(reading.lead?.label.contains("HarborMist") ?? false,
                      "The inline lead names HarborMist: \(reading.lead?.label ?? "no lead")")
        XCTAssertEqual(activityPlusN(in: app), 3, "Inline, +N still counts the challenge and two conversations")
        keepScreenshot("The inline bar: HarborMist's lead and +3", in: app)

        post(.drop)
        XCTAssertTrue(pollUntil(timeout: 40) {
            reading = self.barReading(in: app)
            return (reading.state?.hasPrefix("unreachable ") ?? false) && reading.retry != nil
        }, "30 s after the drop the inline bar says Can’t reach OGS, with Retry: \(reading.state ?? "no bar")")
        XCTAssertTrue(reading.state?.hasSuffix(" inline") ?? false, "Still inline: \(reading.state ?? "no bar")")
        XCTAssertEqual(reading.status?.label, cantReachOGS, "The inline status says Can’t reach OGS")
        XCTAssertEqual(reading.retry?.isEnabled, true, "The inline Can’t reach OGS keeps its Retry")
        attach("+N: \(reading.more?.label ?? "none")", name: "The inline Can’t reach OGS")
        keepScreenshot("The inline bar: Can’t reach OGS with Retry", in: app)

        XCTAssertEqual(app.tabBars.buttons.count, 1, "Minimized, the tab bar lists the selected tab alone")
        XCTAssertTrue(expandMinimizedTabBar(in: app), "The minimized tab bar expands before a tab is tapped")
        XCTAssertGreaterThan(app.tabBars.buttons.count, 1, "Expanded, the tab bar lists every tab")
        selectMainNavigation(ID.navigationPublicGames, in: app)
        element(ID.screenPublicGames, in: app)
        post(.restore)
        #endif
    }

    // MARK: The Duo

    /// `several` on the Duo, whose bar keeps its width through a game, a
    /// turn and a fold. In Closed upright UIKit's accessory sits beside the
    /// rail, 290 pt wide, in the one-line form whose line names the
    /// opponent: from launch, after a game, after a turn from sideways and
    /// after a fold from Book tall. Closed and turned sideways it is 346 pt
    /// and expanded; launched in Book tall, the host's 360 pt.
    /// - Poses, in order: Closed upright (Device Hub's Closed), where the
    ///   app launches; Closed sideways (Rotate Right) and upright again
    ///   (Rotate Left); Book tall (Partially Open, then Rotate Right), where
    ///   the app launches again; Closed sideways (Closed), the fold; and
    ///   Closed upright (Rotate Left).
    /// - How a run sets them: XCTest can't drive Device Hub, and
    ///   `XCUIDevice`'s orientation doesn't turn the Duo, so the journey asks
    ///   for each pose in the simulator's log, "[DuoPose] <pose>", and waits
    ///   up to two minutes for the app's window to take it, while the run's
    ///   script, or a person, sets it in Device Hub. It runs only where the
    ///   run says it will (`TEST_RUNNER_SURROUND_DUO_POSES=1`), and skips
    ///   everywhere but the Duo; CI has none.
    func testTheDuosBarKeepsItsWidth() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        try skipUnlessARunSetsTheDuosPoses()
        var app = launchOnTheDuo(.several, in: .closedPortrait)
        assertTheDuosBar(in: .closedPortrait, after: "the launch", in: app)
        keepScreenshot("Closed upright: the 290 pt one line with the name", in: app)

        tap(barLead(in: app), description: "The bar's lead", in: app)
        element(ID.gameDetail(FixtureID.harborMistGameID), in: app)
        assertNoBar("HarborMist's game", in: app)
        backToHome(from: FixtureID.harborMistGameID, in: app)
        assertTheDuosBar(in: .closedPortrait, after: "a game", in: app)

        setDuoPose(.closedLandscape, in: app)
        assertTheDuosBar(in: .closedLandscape, after: "a turn to sideways", in: app)
        keepScreenshot("Closed sideways: the bar at 346 pt", in: app)
        setDuoPose(.closedPortrait, in: app)
        assertTheDuosBar(in: .closedPortrait, after: "a turn from sideways", in: app)

        app = launchOnTheDuo(.several, in: .bookTall, from: app)
        assertTheDuosBar(in: .bookTall, after: "a launch in Book tall", in: app)
        setDuoPose(.closedLandscape, in: app)
        assertTheDuosBar(in: .closedLandscape, after: "a fold from Book tall", in: app)
        setDuoPose(.closedPortrait, in: app)
        assertTheDuosBar(in: .closedPortrait, after: "a fold from Book tall and a turn", in: app)
        keepScreenshot("Closed upright after a fold from Book tall and a turn", in: app)
        #endif
    }

    /// `several` on the Duo, whose drawer steps the bar aside in Book, Open
    /// wide and Book tall: the poses with regular height, where the drawer
    /// slides in beside UIKit's accessory, which UIKit would squeeze beside
    /// it, and leave narrowed in the tall poses. No bar while the drawer
    /// shows: no read lists it beside the shown drawer, nor for a second
    /// after. After the drawer closes the bar comes back at the pose's full
    /// width: 360 pt in Open wide and Book tall, the host's own, and 346 pt
    /// in Book, whose bar keeps to its leading pane. XCTest's taps wait for
    /// the app to settle, so when the bar clears (a main-queue turn after the
    /// drawer starts to show), when it comes back (about half a second after
    /// the close completes) and that each show's completion still arrives
    /// are the host log's to tell: the launches log the drawer's `bar.drawer`
    /// lines and the accessory's `bar.accessory` lines
    /// (`--surround-activity-hidden-log`), which the run keeps.
    /// - Poses, in order, each launched in: Open wide (Device Hub's Open),
    ///   Book tall (Partially Open, then Rotate Right) and Book (Rotate
    ///   Left). Each changes the window's shape, so the journey sees it
    ///   arrive.
    /// - How a run sets them: as for testTheDuosBarKeepsItsWidth.
    func testTheDuosDrawerStepsTheBarAside() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        try skipUnlessARunSetsTheDuosPoses()
        var running: XCUIApplication?
        for pose in [DuoPose.openWide, .bookTall, .bookWide] {
            let app = launchOnTheDuo(.several, in: pose, from: running)
            running = app
            assertTheDuosBar(in: pose, after: "a launch in \(pose.rawValue)", in: app)
            toggleSidebar(shown: true, in: app)
            XCTAssertFalse(pollUntil(timeout: 1) { self.query(ID.activityBar, in: app).exists },
                           "No bar while the drawer shows in \(pose.rawValue): \(barReading(in: app).state ?? "none")")
            keepTheDuosScreens("The drawer shown in \(pose.rawValue), no bar")
            toggleSidebar(shown: false, in: app)
            assertTheDuosBar(in: pose, after: "the drawer's close in \(pose.rawValue)", in: app)
            keepTheDuosScreens("The bar back at \(pose.rawValue)'s full width after the drawer")
        }
        #endif
    }

    // MARK: Launching

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    /// Where a journey pins an iPad's sidebar: hidden in portrait, where the
    /// floating bar shows, or shown in landscape, where the Now section does.
    /// Phones launch in portrait either way, and the Duo in its pose.
    private enum IPadSidebar { case hidden, shown }

    #if !targetEnvironment(macCatalyst)
    private func orientation(for sidebar: IPadSidebar) -> UIDeviceOrientation {
        !isPhone && sidebar == .shown ? .landscapeLeft : .portrait
    }

    /// An Activity state at Home, on the frozen fixture clock, in a full-size
    /// iPad window with its sidebar as the journey pins it, in English or
    /// `language`, at the device's text size or `textSize`.
    private func launch(_ state: State, sidebar: IPadSidebar = .hidden, offline: Bool = false,
                        actions: Actions? = nil, language: String? = nil, textSize: UIContentSizeCategory? = nil,
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        var arguments = [SurroundUITestContract.activityStateLaunchArgument, state.rawValue]
        if offline {
            arguments += [SurroundUITestContract.activityConnectionLaunchArgument,
                          SurroundUITestContract.ActivityFixtureConnection.offline.rawValue]
        }
        if let actions { arguments += [SurroundUITestContract.activityActionsLaunchArgument, actions.rawValue] }
        if let textSize { arguments += ["-UIPreferredContentSizeCategoryName", textSize.rawValue] }
        let app = launchApp(additionalLaunchArguments: arguments, orientation: orientation(for: sidebar),
                            language: language)
        // An iPad keeps a window another run resized.
        if !isPhone { restoreFullSizeWindow(in: app) }
        element(ID.screenHome, in: app, file: file, line: line)
        if !isPhone { showIPadSidebar(sidebar == .shown, in: app, file: file, line: line) }
        return app
    }

    /// Signed out and offline, at the Home tab's Welcome, whose root has no
    /// identifier of its own.
    private func launchSignedOut(sidebar: IPadSidebar, file: StaticString = #filePath,
                                 line: UInt = #line) -> XCUIApplication {
        let app = launchApp(additionalLaunchArguments: [SurroundUITestContract.signedOutOfflineLaunchArgument],
                            orientation: orientation(for: sidebar))
        if !isPhone { restoreFullSizeWindow(in: app) }
        XCTAssertTrue(pollUntil(timeout: 15) {
            self.query(ID.screenHome, in: app).exists || self.query(ID.navigationHome, in: app).exists
        }, "Expected the signed-out Home", file: file, line: line)
        if !isPhone { showIPadSidebar(sidebar == .shown, in: app, file: file, line: line) }
        return app
    }

    /// The host this device's bar is in, as the app's policy picks it with
    /// the SDK both are built with: the custom bar on iPhones before iOS 26.1
    /// and on iPadOS 18; SwiftUI's accessory on iPhones from 26.1; UIKit's on
    /// iOS 27 iPhones and the Duo, from the iOS 27 SDK, and on iPads from 26.
    /// Before the iOS 26.2 SDK every host is the custom bar.
    private var expectedBarHost: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let release = (os.majorVersion, os.minorVersion)
        guard appHasActivityHosts else { return "customBar" }
        if isPhone {
            #if canImport(SwiftUI, _version: 8.0)
            if release >= (27, 0) { return "uiKitAccessory" }
            #endif
            return release >= (26, 1) ? "swiftUIAccessory" : "customBar"
        }
        return release >= (26, 0) ? "uiKitAccessory" : "customBar"
    }

    // MARK: The bar

    /// The bar's parts as XCTest lists them, from one snapshot.
    private struct BarReading {
        struct Part {
            var label: String
            var value: String
            var isEnabled: Bool
        }

        var bar: CGRect?
        /// The lead, or a result in its place.
        var lead: Part?
        /// View, Open game, Withdraw, or a failure's Retry.
        var action: Part?
        var more: Part?
        /// The status kinds' lead, `root.connectionStatus`.
        var status: Part?
        var retry: Part?
        /// The Debug element: "live game-26268404 uiKitAccessory expanded".
        var state: String?

        /// The Debug element's kind and item id, such as "live game-26268404".
        var kindAndItem: String? { state.map(Self.kindAndItem) }

        /// The kind and item id an applied state names.
        static func kindAndItem(_ state: String) -> String {
            state.split(separator: " ").prefix(2).joined(separator: " ")
        }

        /// The host an applied state names.
        static func host(_ state: String) -> String? {
            state.split(separator: " ").dropFirst(2).first.map(String.init)
        }
    }

    private func barReading(in app: XCUIApplication) -> BarReading {
        var reading = BarReading()
        guard let root = try? app.snapshot() else { return reading }
        var pending: [XCUIElementSnapshot] = [root]
        while let node = pending.popLast() {
            let part = BarReading.Part(label: node.label, value: node.value as? String ?? "", isEnabled: node.isEnabled)
            switch node.identifier {
            case ID.activityBar where reading.bar == nil: reading.bar = node.frame
            case ID.activityBarLead where reading.lead == nil: reading.lead = part
            case ID.activityBarAction where reading.action == nil: reading.action = part
            case ID.activityBarMore where reading.more == nil: reading.more = part
            case ID.rootConnectionStatus where reading.status == nil: reading.status = part
            case ID.rootConnectionStatusRetry where reading.retry == nil: reading.retry = part
            case ID.activityBarState where reading.state == nil: reading.state = node.value as? String
            default: break
            }
            pending.append(contentsOf: node.children)
        }
        return reading
    }

    /// The bar's lead, once it can be tapped.
    @discardableResult
    private func barLead(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let lead = app.buttons.matching(identifier: ID.activityBarLead).firstMatch
        let shown = pollUntil(timeout: 10) { lead.exists && lead.isHittable }
        if !shown { attach(app.debugDescription, name: "Accessibility hierarchy – no bar's lead") }
        XCTAssertTrue(shown, "Expected the Activity bar's lead: \(barReading(in: app).state ?? "no bar")",
                      file: file, line: line)
        return lead
    }

    /// The Debug element names what leads, and this device's host.
    private func assertLeads(_ kindAndItem: String, in app: XCUIApplication,
                             file: StaticString = #filePath, line: UInt = #line) {
        var state: String?
        XCTAssertTrue(pollUntil(timeout: 10) {
            state = self.activityBarAppliedState(in: app)
            return state.map(BarReading.kindAndItem) == kindAndItem
        }, "The bar shows \(kindAndItem): \(state ?? "no bar")", file: file, line: line)
        XCTAssertEqual(state.flatMap(BarReading.host), expectedBarHost,
                       "The bar is in this device's host: \(state ?? "no bar")", file: file, line: line)
    }

    private func assertNoBar(_ place: String, in app: XCUIApplication,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(pollUntil(timeout: 10) { !self.query(ID.activityBar, in: app).exists },
                      "\(place) shows no Activity bar: \(barReading(in: app).state ?? "none")", file: file, line: line)
    }

    /// The Duo closed and upright, whose bar is one line beside the rail.
    private func isClosedUprightDuo(in app: XCUIApplication) -> Bool {
        let window = windowFrame(in: app)
        return isDuo && window.height > window.width && window.width < 600
    }

    /// The Duo's Closed upright bar: one line, of the tile, the name, a
    /// game's clock and +N, and no trailing action, which a lead without a
    /// clock leaves in Activity, one tap away.
    private func assertTheBarIsOneLine(withoutItsAction action: String, in app: XCUIApplication,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let reading = barReading(in: app)
        XCTAssertTrue(reading.state?.hasSuffix(" closed") ?? false,
                      "Closed upright the Duo's bar is one line: \(reading.state ?? "no bar")", file: file, line: line)
        XCTAssertNil(reading.action, "The one-line bar draws no \(action): \(reading.action?.label ?? "")",
                     file: file, line: line)
    }

    /// The lead's VoiceOver label says the window's connection is down, as a
    /// game's lead does in its line two's place.
    private func leadSaysReconnecting(in app: XCUIApplication) -> Bool {
        guard let lead = barReading(in: app).lead else { return false }
        return (lead.label + " " + lead.value).contains("Reconnecting to OGS")
    }

    /// A Now section's row, once it can be tapped.
    @discardableResult
    private func nowRow(_ itemID: String, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let row = query(ID.activityNowRow(itemID), in: app)
        let shown = pollUntil(timeout: 10) { row.exists && row.isHittable }
        if !shown { attach(app.debugDescription, name: "Accessibility hierarchy – no Now row \(itemID)") }
        XCTAssertTrue(shown, "Expected the Now section's row for \(itemID)", file: file, line: line)
        return row
    }

    // MARK: Root status

    /// Whether this carrier says `words` as it should: the line, with the
    /// bar's Can’t reach OGS and its Retry, where the line carries the
    /// status; `root.connectionStatus` alone, with Retry at Can’t reach OGS,
    /// where the floating bar or the Now row carries every word.
    private func says(_ words: RootStatusWords, on carrier: RootStatusCarrier, _ reading: RootStatusReading) -> Bool {
        guard reading.offersRetry == (words == .unreachable) else { return false }
        switch carrier {
        case .titleLine: return reading.line == words && reading.element == (words == .unreachable ? words : nil)
        case .floatingBar, .nowRow: return reading.element == words && reading.line == nil
        }
    }

    /// Waits until every part of this carrier says `words`, since the line
    /// under the title follows the bar a moment later, then asserts each
    /// part. A part that said them first is kept as an attachment.
    @discardableResult
    private func assertSays(_ words: RootStatusWords, on carrier: RootStatusCarrier, in app: XCUIApplication,
                            within timeout: TimeInterval, file: StaticString = #filePath,
                            line: UInt = #line) -> RootStatusReading {
        var reading = RootStatusReading()
        var firstPart: Date?
        let all = pollUntil(timeout: timeout) {
            reading = self.rootStatusReading(in: app)
            if firstPart == nil, reading.line == words || reading.element == words { firstPart = Date() }
            return self.says(words, on: carrier, reading)
        }
        if all, let firstPart, Date().timeIntervalSince(firstPart) > 0.1 {
            attach(String(format: "One part said %@ %.1f s before every part did: %@", "\(words)",
                          Date().timeIntervalSince(firstPart), "\(reading)"), name: "The carriers' lag")
        }
        assertSays(words, on: carrier, reading, file: file, line: line)
        return reading
    }

    /// Who says what, on this carrier: the line and the bar's Can’t reach
    /// OGS where the line carries the status; the status kind, or the Now
    /// row, where they carry every word.
    private func assertSays(_ words: RootStatusWords, on carrier: RootStatusCarrier, _ reading: RootStatusReading,
                            file: StaticString = #filePath, line: UInt = #line) {
        switch carrier {
        case .titleLine:
            XCTAssertEqual(reading.line, words, "The line under the title says it: \(reading)", file: file, line: line)
            XCTAssertEqual(reading.element, words == .unreachable ? words : nil,
                           "The bar says only Can’t reach OGS, with Retry: \(reading)", file: file, line: line)
        case .floatingBar, .nowRow:
            XCTAssertEqual(reading.element, words, "root.connectionStatus says it: \(reading)", file: file, line: line)
            XCTAssertNil(reading.line, "No line under the title here: \(reading)", file: file, line: line)
        }
        XCTAssertEqual(reading.offersRetry, words == .unreachable, "Retry only at Can’t reach OGS: \(reading)",
                       file: file, line: line)
    }

    /// No lead, +N, row or All activity: the window's status alone.
    private func assertStatusOnly(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let reading = barReading(in: app)
        XCTAssertNil(reading.lead, "No lead signed out", file: file, line: line)
        XCTAssertNil(reading.more, "No +N signed out", file: file, line: line)
        let rows = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ OR identifier == %@", "activity.now.row.", ID.activityNowAll
        ))
        XCTAssertFalse(rows.firstMatch.exists, "No Now row or All activity signed out", file: file, line: line)
    }

    /// The root's large title in the top navigation bar: its static text
    /// that isn't the line's words.
    private func rootTitleFrame(in app: XCUIApplication) -> CGRect? {
        guard let root = try? app.snapshot() else { return nil }
        let top = windowFrame(in: app).midY
        var titles = [CGRect]()
        var pending = [(node: XCUIElementSnapshot, inBar: Bool)]()
        pending.append((root, false))
        while let (node, inBar) = pending.popLast() {
            let isBar = node.elementType == .navigationBar && node.frame.midY < top
            let text = node.label.trimmingCharacters(in: .whitespaces)
            if inBar, node.elementType == .staticText, !text.isEmpty, RootStatusWords(node.label) == nil {
                titles.append(node.frame)
            }
            pending.append(contentsOf: node.children.map { (node: $0, inBar: inBar || isBar) })
        }
        return titles.max { $0.height < $1.height }
    }

    // MARK: Navigating

    /// Whether `entry` is a tab here, as the Web version is on phones: it
    /// can be tapped with no sidebar shown.
    private func isTab(_ entry: String, in app: XCUIApplication) -> Bool {
        let tab = query(entry, in: app)
        return tab.exists && tab.isHittable
    }

    /// Messages shows two columns, a conversation selected in its pane.
    private func messagesHasTwoColumns(in app: XCUIApplication) -> Bool {
        let pane = query("messages.detailPane", in: app)
        return pollUntil(timeout: 3) { !(self.listedSnapshot(of: pane)?.frame.isEmpty ?? true) }
    }

    /// Back from a pushed conversation to Messages.
    private func backFromConversation(_ conversation: XCUIElement, in app: XCUIApplication,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let back = visibleBack(NSPredicate(
            format: "identifier == %@ OR label == %@ OR label == %@", "BackButton", "Messages", "Back"
        ), in: app, description: "the conversation's Back", file: file, line: line)
        guard let back else { return }
        tap(back, description: "Back to Messages", in: app, file: file, line: line)
        XCTAssertTrue(waitForAbsence(conversation, timeout: stateSettleTimeout), "Back leaves the conversation",
                      file: file, line: line)
        element(ID.screenMessages, in: app, file: file, line: line)
    }

    /// Back from a game on Home's route to Home. iOS 18 names Back after
    /// Home's title, which the in-game control's base form shares. In the
    /// Duo's wide poses the game draws its own.
    private func backToHome(from gameID: Int, in app: XCUIApplication,
                            file: StaticString = #filePath, line: UInt = #line) {
        let back = visibleBack(NSPredicate(
            format: "identifier IN %@ OR (identifier != %@ AND (label == %@ OR label == %@))",
            ["BackButton", ID.gameBack], ID.gameActiveGamesButton, "Active games", "Back"
        ), in: app, description: "the game's Back", file: file, line: line)
        guard let back else { return }
        tap(back, description: "Back to Home", in: app, file: file, line: line)
        element(ID.screenHome, in: app, file: file, line: line)
        XCTAssertTrue(waitForAbsence(query(ID.gameDetail(gameID), in: app), timeout: stateSettleTimeout),
                      "Back leaves the game: it was on Home's route", file: file, line: line)
    }

    /// A challenge's card pushed in Activity: its challenger's entry, which
    /// names the challenge, in the popover, or the one a tap reaches over
    /// Home's own card under the sheet.
    @discardableResult
    private func challengeCard(_ challengeID: Int, challenger: Int, in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let id = ID.profileChallengeEntry(challengeID, challenger)
        let popover = app.popovers.firstMatch
        var card: XCUIElement?
        let found = pollUntil(timeout: 10) {
            card = popover.exists
                ? popover.descendants(matching: .any).matching(identifier: id).firstMatch
                : app.descendants(matching: .any).matching(identifier: id).allElementsBoundByIndex.first { $0.isHittable }
            return card?.exists == true
        }
        if !found { attach(app.debugDescription, name: "Accessibility hierarchy – no card \(id)") }
        XCTAssertTrue(found, "View pushes the challenge's card", file: file, line: line)
        return card ?? query(id, in: app)
    }

    /// Activity is a popover in regular width, on an iPad and in the Duo's
    /// open poses, wide or tall (951 × 669 or 669 × 951 pt), and a sheet in
    /// compact width, as on the closed Duo (466 × 678 pt upright, 678 × 466
    /// sideways).
    private func expectsActivityPopover(in app: XCUIApplication) -> Bool {
        let window = windowFrame(in: app)
        return !isPhone || (isDuo && min(window.width, window.height) >= 600)
    }

    /// The list is a sheet in compact width, with Done, and a popover in
    /// regular width.
    private func assertActivityPresentation(in app: XCUIApplication, file: StaticString = #filePath,
                                            line: UInt = #line) {
        if expectsActivityPopover(in: app) {
            XCTAssertTrue(app.popovers.firstMatch.exists(within: 10),
                          "In regular width Activity is a popover", file: file, line: line)
        } else {
            XCTAssertTrue(query(ID.activityDone, in: app).exists(within: 10),
                          "In compact width Activity is a sheet, with Done", file: file, line: line)
            XCTAssertFalse(app.popovers.firstMatch.exists, "In compact width there is no popover", file: file, line: line)
        }
    }

    /// Back inside the list's own stack, never the screen's under it, which
    /// a sheet covers: the list, out of the window while a card is pushed
    /// over it, shows again.
    private func backToList(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let popover = app.popovers.firstMatch
        let back = visibleBack(NSPredicate(
            format: "identifier == %@ OR label == %@ OR label == %@", "BackButton", "Activity", "Back"
        ), in: popover.exists ? popover : (app as XCUIElement), description: "the list's Back", file: file, line: line)
        guard let back else { return }
        tap(back, description: "Back to Activity", in: app, file: file, line: line)
        XCTAssertTrue(query(ID.activityList, in: app).exists(within: stateSettleTimeout),
                      "Back shows the list", file: file, line: line)
    }

    /// Done on the sheet, or a tap outside the popover.
    private func closeList(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        if app.popovers.firstMatch.exists {
            dismissPopover(in: app, file: file, line: line)
        } else {
            tap(ID.activityDone, in: app, matching: .button, file: file, line: line)
        }
        XCTAssertTrue(waitForAbsence(query(ID.activityList, in: app), timeout: stateSettleTimeout),
                      "The list closes", file: file, line: line)
    }

    // MARK: The keyboard

    /// Messages' player search raises a docked software keyboard, confirmed
    /// first as SidebarKeyboardUITests confirms it. A tap alone leaves the
    /// keyboard off screen while the simulator's hardware keyboard is
    /// connected, and XCTest disconnects it as it types, so a space is typed
    /// first. Where the window has a bottom tab bar, the keyboard covers the
    /// bar with it; elsewhere the bar goes. Cancel takes the keyboard away,
    /// and the bar comes back.
    /// - Parameter itemID: The lead's item, such as `game-26268404`.
    private func assertTheKeyboardHidesTheBar(leadingWith itemID: String, in app: XCUIApplication,
                                              file: StaticString = #filePath, line: UInt = #line) {
        let lead = barLead(in: app, file: file, line: line)
        assertLeads("live \(itemID)", in: app, file: file, line: line)
        let window = windowFrame(in: app)
        let place = "Messages in \(window.width > window.height ? "landscape" : "portrait")"
        let tabBar = bottomTabBar(in: app)
        let search = element("messages.playerSearchField", in: app, matching: .textField, file: file, line: line)
        tap(search, description: "Messages' player search", in: app, file: file, line: line)
        search.typeText(" ")
        let docked = pollUntil(timeout: 10) { self.dockedKeyboardFrame(in: app) != nil }
        if !docked { attach(app.debugDescription, name: "Accessibility hierarchy – no docked software keyboard") }
        let keyboard = listedSnapshot(of: app.keyboards.firstMatch)?.frame.size
        XCTAssertTrue(docked, "\(place): a docked software keyboard, whose rule the bar follows. Found "
                      + (keyboard.map { "only a keyboard of \($0.width) × \($0.height) pt" } ?? "no keyboard")
                      + ", as when the simulator's hardware keyboard is connected", file: file, line: line)
        guard docked, let keyboardFrame = dockedKeyboardFrame(in: app) else { return }
        // Covered: gone, not hittable, or below the keyboard's top edge. XCTest
        // calls a tab bar under the keyboard hittable on iOS 18 and 26.
        func isCovered(_ element: XCUIElement) -> Bool {
            guard let frame = listedSnapshot(of: element)?.frame else { return true }
            return !element.isHittable || frame.minY >= keyboardFrame.minY - 1
        }
        if let tabBar {
            XCTAssertTrue(pollUntil(timeout: 10) { isCovered(lead) },
                          "\(place): the keyboard covers the bar", file: file, line: line)
            XCTAssertTrue(isCovered(tabBar), "\(place): the keyboard covers the tab bar with it: \(tabBar.frame) "
                          + "against the keyboard's \(keyboardFrame)", file: file, line: line)
            switch expectedBarHost {
            case "customBar":
                XCTAssertTrue(pollUntil(timeout: 10) { !self.query(ID.activityBar, in: app).exists },
                              "\(place): the custom bar hides while a docked keyboard shows", file: file, line: line)
            case "uiKitAccessory":
                XCTAssertEqual(activityBarAppliedState(in: app).map(BarReading.kindAndItem), "live \(itemID)",
                               "\(place): UIKit's accessory stays set under the keyboard, which a bottom tab bar "
                               + "makes no input", file: file, line: line)
            default:
                break
            }
            keepScreenshot("\(place): the keyboard covers the bar with the tab bar", in: app)
        } else {
            assertNoBar("\(place), with a docked keyboard and no bottom tab bar", in: app, file: file, line: line)
            keepScreenshot("\(place): the bar goes with the keyboard", in: app)
        }
        tap("messages.cancelPlayerSearch", in: app, matching: .button, file: file, line: line)
        XCTAssertTrue(pollUntil(timeout: 10) { !self.showsDockedKeyboard(in: app) },
                      "\(place): Cancel takes the keyboard away", file: file, line: line)
        barLead(in: app, file: file, line: line)
        assertLeads("live \(itemID)", in: app, file: file, line: line)
    }

    /// Whether a docked software keyboard shows, from one snapshot of it:
    /// more than 100 pt across its shorter side, which the shortcuts bar a
    /// connected hardware keyboard leaves isn't. A keyboard that leaves as it
    /// is read, after Cancel, reads as none. A snapshot gives the keyboard's
    /// frame in its own window's coordinates, turned with a phone in
    /// landscape, so only its size is read.
    private func showsDockedKeyboard(in app: XCUIApplication) -> Bool {
        guard let size = listedSnapshot(of: app.keyboards.firstMatch)?.frame.size else { return false }
        return min(size.width, size.height) > 100
    }

    /// The docked software keyboard's frame, as SidebarKeyboardUITests reads
    /// it: taller than 100 pt, across most of the window, along its bottom
    /// edge. Nil for none, and for the shortcuts bar alone that a connected
    /// hardware keyboard leaves. Read while the keyboard rises or stays,
    /// once a snapshot has found it docked.
    private func dockedKeyboardFrame(in app: XCUIApplication) -> CGRect? {
        guard showsDockedKeyboard(in: app) else { return nil }
        let frame = app.keyboards.firstMatch.frame
        let window = windowFrame(in: app)
        guard frame.height > 100, frame.minX >= window.minX - 1, frame.maxX <= window.maxX + 1,
              frame.width >= window.width * 0.6, window.maxY - frame.maxY >= -1,
              window.maxY - frame.maxY <= 100 else { return nil }
        return frame
    }

    /// The window's tab bar along its bottom edge, which phones have. An
    /// iPad's floats at the top, the Duo's rail runs the window's height
    /// beside the content, and a Max iPhone in landscape keeps its tabs in a
    /// drawer.
    private func bottomTabBar(in app: XCUIApplication) -> XCUIElement? {
        let window = windowFrame(in: app)
        return app.tabBars.allElementsBoundByIndex.first {
            $0.exists && !$0.frame.isEmpty && $0.frame.minY > window.midY && $0.isHittable
        }
    }

    // MARK: The iPad's sidebar

    /// What one snapshot holds of the iPad's sidebar and its floating bar.
    private struct SidebarReading: CustomStringConvertible {
        /// The sidebar's Settings row is on screen.
        var sidebar = false
        /// `activity.bar` is listed.
        var bar = false
        var applied: String?

        var description: String {
            "sidebar \(sidebar ? "on screen" : "off screen"), bar \(bar ? applied ?? "listed" : "none")"
        }
    }

    private func sidebarReading(in app: XCUIApplication) -> SidebarReading {
        var reading = SidebarReading()
        guard let root = try? app.snapshot() else { return reading }
        let window = root.children.first { $0.elementType == .window }?.frame ?? root.frame
        var pending: [XCUIElementSnapshot] = [root]
        while let node = pending.popLast() {
            switch node.identifier {
            case ID.navigationSettings where node.frame.intersects(window) && node.frame.minX >= window.minX - 1:
                reading.sidebar = true
            case ID.activityBar:
                reading.bar = true
            case ID.activityBarState where reading.applied == nil:
                reading.applied = node.value as? String
            default:
                break
            }
            pending.append(contentsOf: node.children)
        }
        return reading
    }

    /// What one snapshot holds of the iPad's sidebar tab rows and its Now
    /// section: the lowest tab row at the window's leading side, the
    /// section's frame and its rows.
    private struct NowSectionReading: CustomStringConvertible {
        var lastTabRow: (identifier: String, frame: CGRect)?
        var section: CGRect?
        var rows: [String] = []

        var description: String {
            let last = lastTabRow.map { "\($0.identifier) \($0.frame)" } ?? "none"
            return "last tab row \(last); section \(section.map { "\($0)" } ?? "none"); rows \(rows)"
        }
    }

    private func nowSectionReading(in app: XCUIApplication) -> NowSectionReading {
        var reading = NowSectionReading()
        guard let root = try? app.snapshot() else { return reading }
        let window = root.children.first { $0.elementType == .window }?.frame ?? root.frame
        let tabs: Set<String> = [ID.navigationHome, ID.navigationPublicGames, ID.navigationMessages,
                                 ID.navigationProfile, ID.navigationSettings, ID.navigationAbout,
                                 ID.navigationBrowser]
        let rowPrefix = ID.activityNowRow("")
        var pending: [XCUIElementSnapshot] = [root]
        while let node = pending.popLast() {
            let frame = node.frame
            if node.elementType == .cell, tabs.contains(node.identifier), !frame.isEmpty,
               frame.minX >= window.minX - 1, frame.minX < window.midX,
               frame.maxY > reading.lastTabRow?.frame.maxY ?? -.infinity {
                reading.lastTabRow = (node.identifier, frame)
            } else if node.identifier == ID.activityNow {
                reading.section = frame
            } else if node.identifier.hasPrefix(rowPrefix), !node.identifier.hasSuffix(".action") {
                reading.rows.append(String(node.identifier.dropFirst(rowPrefix.count)))
            }
            pending.append(contentsOf: node.children)
        }
        return reading
    }

    /// Shows or hides the iPad's sidebar, or the Duo's drawer, by its toggle,
    /// reading the app from the tap until both settle: the floating bar goes
    /// as the sidebar starts to show and comes back once its hide completes,
    /// on the Duo half a second later, so no read lists the bar while the
    /// sidebar is on screen. The reads are kept as an attachment, with their
    /// time from the tap.
    private func toggleSidebar(shown: Bool, in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) {
        guard let toggle = nativeSidebarToggle(in: app) else {
            return XCTFail("Expected the sidebar's toggle", file: file, line: line)
        }
        activate(toggle)
        let tapped = Date()
        var reads = [(time: TimeInterval, reading: SidebarReading)]()
        var settled = false
        while !settled, Date().timeIntervalSince(tapped) < 10 {
            let reading = sidebarReading(in: app)
            reads.append((Date().timeIntervalSince(tapped), reading))
            settled = reading.sidebar == shown && reading.bar != shown
        }
        attach(reads.map { String(format: "+%.2f s: %@", $0.time, $0.reading.description) }.joined(separator: "\n"),
               name: "The sidebar \(shown ? "shows" : "hides"), read by read")
        XCTAssertTrue(settled, "The sidebar \(shown ? "shows with no floating bar" : "hides, and the bar comes back"): "
                      + (reads.last.map { "\($0.reading)" } ?? "no read"), file: file, line: line)
        let beside = reads.filter { $0.reading.sidebar && $0.reading.bar }
        XCTAssertTrue(beside.isEmpty, "No read lists the floating bar beside the sidebar: "
                      + beside.map { String(format: "+%.2f s %@", $0.time, $0.reading.description) }
                        .joined(separator: "; "), file: file, line: line)
        XCTAssertEqual(iPadSidebarIsShown(in: app), shown,
                       "Expected the iPad's sidebar \(shown ? "shown" : "hidden")", file: file, line: line)
    }

    // MARK: A game's board as it opens

    /// How one open laid the game's board out, as XCTest read it from the tap.
    private struct BoardOpen {
        /// Each board size in turn, from the first read that lists the board.
        var sizes: [CGSize] = []
        /// The board's frame once it held still for a second and a half.
        var settled: CGRect?
        /// The applied floating bar of each read that listed it beside the board.
        var barBesideBoard: [String] = []
        var reads = 0
        /// The window the game opened in.
        var window = CGRect.zero

        var summary: String {
            let steps = sizes.map { "\(Int($0.width.rounded()))×\(Int($0.height.rounded()))" }.joined(separator: " → ")
            return "\(steps.isEmpty ? "no board" : steps); settled \(settled.map { "\($0)" } ?? "never"); "
                + "\(reads) reads; bar beside the board: \(barBesideBoard.isEmpty ? "none" : barBesideBoard.joined(separator: ", "))"
                + "; window \(Int(window.width.rounded()))×\(Int(window.height.rounded()))"
        }
    }

    /// Reads the app from `action`, the open's tap, until the game's board
    /// has held one frame for a second and a half, one snapshot a read: each
    /// size in turn, the frame it settles at, and any applied floating bar
    /// listed beside it. With the accessory set, none may be: it clears as
    /// soon as the game is asked for, before the game's first layout.
    private func readBoard(of gameID: Int, withAccessory: Bool, in app: XCUIApplication,
                           file: StaticString = #filePath, line: UInt = #line, opening action: () -> Void) -> BoardOpen {
        var reading = BoardOpen()
        action()
        let opened = Date()
        var last: CGRect?
        var heldSince = opened
        while Date().timeIntervalSince(opened) < 15 {
            guard let root = try? app.snapshot() else { continue }
            reading.reads += 1
            var board: CGRect?
            var applied: String?
            var pending: [XCUIElementSnapshot] = [root]
            while let node = pending.popLast() {
                if node.identifier == ID.gameBoard, board == nil { board = node.frame }
                if node.identifier == ID.activityBarState, applied == nil { applied = node.value as? String }
                pending.append(contentsOf: node.children)
            }
            guard let board, !board.isEmpty else { continue }
            if let applied, applied != "none" { reading.barBesideBoard.append(applied) }
            if board != last {
                if reading.sizes.last != board.size { reading.sizes.append(board.size) }
                last = board
                heldSince = Date()
            } else if Date().timeIntervalSince(heldSince) >= 1.5 {
                break
            }
        }
        reading.settled = last
        reading.window = windowFrame(in: app)
        attach(reading.summary, name: "The board as game \(gameID) opened")
        element(ID.gameDetail(gameID), in: app, file: file, line: line)
        if withAccessory {
            XCTAssertEqual(reading.barBesideBoard, [], "The bar clears as soon as the game is asked for, so no read "
                           + "lists it beside the board: \(reading.summary)", file: file, line: line)
        }
        return reading
    }

    /// The live-game banner fixture in landscape at full size, logging each
    /// of a board's layouts: Home lists the finished game, and game 26268404,
    /// live on your move, leads. With the custom bar forced, the floating bar
    /// draws on roots only, never in a game.
    private func launchLiveGameBanner(forcingTheCustomBar forces: Bool, file: StaticString = #filePath,
                                      line: UInt = #line) -> XCUIApplication {
        var arguments = [SurroundUITestContract.liveGameBannerNavigationLaunchArgument, "--surround-activity-hidden-log"]
        if forces { arguments.append(SurroundUITestContract.noticesForceCustomBarLaunchArgument) }
        let app = launchApp(additionalLaunchArguments: arguments, orientation: .landscapeLeft)
        restoreFullSizeWindow(in: app)
        element(ID.screenHome, in: app, file: file, line: line)
        return app
    }

    /// Opens the finished game from its row on Home, reading its board, and
    /// goes Back to Home, where the bar comes back with the accessory.
    private func openTheFinishedGameFromHome(withAccessory: Bool, in app: XCUIApplication,
                                             file: StaticString = #filePath, line: UInt = #line) -> BoardOpen {
        let row = revealOnHome(ID.homeHistoryGame(historyGameID), within: Self.historySection, in: app,
                               file: file, line: line)
        let board = readBoard(of: historyGameID, withAccessory: withAccessory, in: app, file: file, line: line) {
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        backToHome(from: historyGameID, in: app, file: file, line: line)
        if withAccessory { barLead(in: app, file: file, line: line) }
        return board
    }

    /// Opens the finished game as a linked game: its row's menu on Home opens
    /// its opponent's profile, pushed in Home's stack, where the bar shows
    /// with the accessory, and the profile's history opens the game. Then
    /// Back to the profile and to Home.
    private func openTheFinishedGameFromItsOpponent(withAccessory: Bool, in app: XCUIApplication,
                                                    file: StaticString = #filePath,
                                                    line: UInt = #line) -> BoardOpen {
        let menuID = ID.profileGameMenuEntry(historyGameID, historyOpponentID)
        let menuItem = menuButton(menuID, title: "View Profile", in: app)
        for _ in 0..<2 where !menuItem.exists {
            // A press that the row takes as a tap opens the game instead.
            if query(ID.gameDetail(historyGameID), in: app).exists {
                backToHome(from: historyGameID, in: app, file: file, line: line)
            }
            revealOnHome(ID.homeHistoryGame(historyGameID), within: Self.historySection, in: app,
                         file: file, line: line)
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 2.5)
            _ = menuItem.exists(within: 5)
        }
        tap(requiredMenuButton(menuID, title: "View Profile", in: app, file: file, line: line),
            description: "View the finished game's opponent's profile", in: app, file: file, line: line)
        assertLoadedProfile(named: historyOpponentName, in: app)
        if withAccessory { barLead(in: app, file: file, line: line) }
        let profile = app.scrollViews.matching(identifier: ID.screenPlayerProfile).firstMatch
        let gameRow = elementAfterScrolling(ID.profileHistoryGame(historyGameID), in: app, within: profile,
                                            file: file, line: line)
        let board = readBoard(of: historyGameID, withAccessory: withAccessory, in: app, file: file, line: line) {
            self.tap(gameRow, description: "The finished game in its opponent's history", in: app, file: file, line: line)
        }
        backFromGame(historyGameID, to: ID.screenPlayerProfile, in: app, file: file, line: line)
        navigateBackFromPlayerProfile(in: app, file: file, line: line)
        element(ID.screenHome, in: app, file: file, line: line)
        if withAccessory { barLead(in: app, file: file, line: line) }
        return board
    }

    /// Home's content on screen, as the freeze journey measures it: Home's
    /// own frames inside the window, above the bottom chrome.
    private func homeViewport(in app: XCUIApplication) -> CGRect {
        let window = windowFrame(in: app)
        var viewport = app.descendants(matching: .any).matching(identifier: ID.screenHome)
            .allElementsBoundByIndex.map(\.frame)
            .filter { !$0.isEmpty && $0.intersects(window) }
            .reduce(window) { $0.intersection($1) }
            .insetBy(dx: 8, dy: 8)
        if let chromeTop = bottomChromeTop(over: viewport, in: app), chromeTop - 8 < viewport.maxY {
            viewport.size.height = max(0, chromeTop - 8 - viewport.minY)
        }
        return viewport
    }

    /// One of Home's rows, once slow, held drags of Home's own list, which
    /// stop where they end, have brought its centre into Home's viewport.
    /// Home lists a row only once it lies near the screen, but lists its
    /// section from the start, so the drags aim at `section` until the row
    /// is listed.
    @discardableResult
    private func revealOnHome(_ identifier: String, within section: String, in app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let home = app.scrollViews.matching(identifier: ID.screenHome).firstMatch
        XCTAssertTrue(home.exists(within: 10), "Expected Home's list", file: file, line: line)
        let row = home.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let holder = home.descendants(matching: .any).matching(identifier: section).firstMatch
        for _ in 0..<12 {
            let viewport = homeViewport(in: app)
            if row.exists, row.isHittable, viewport.contains(CGPoint(x: row.frame.midX, y: row.frame.midY)) {
                return row
            }
            guard let target = [row, holder].first(where: \.exists) else { break }
            let delta = target.frame.midY - viewport.midY
            let distance = max(40, min(abs(delta), viewport.height * 0.6))
            let startY = delta >= 0 ? viewport.maxY : viewport.minY
            let start = home.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: viewport.midX - home.frame.minX, dy: startY - home.frame.minY))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: delta >= 0 ? -distance : distance)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        attach(app.debugDescription, name: "Accessibility hierarchy – \(identifier) not revealed on Home")
        XCTFail("Expected \(identifier) in Home's viewport", file: file, line: line)
        return row
    }

    /// Back from a game to the screen under it.
    private func backFromGame(_ gameID: Int, to screen: String, in app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) {
        let backs = app.buttons.matching(NSPredicate(
            format: "identifier IN %@ OR (identifier != %@ AND label == %@)",
            ["BackButton", ID.gameBack], ID.gameActiveGamesButton, "Back"
        ))
        var back: XCUIElement?
        XCTAssertTrue(pollUntil(timeout: 10) {
            back = backs.allElementsBoundByIndex.first { $0.isHittable }
            return back != nil
        }, "Expected the game's Back", file: file, line: line)
        guard let back else { return }
        tap(back, description: "Back from the game", in: app, file: file, line: line)
        XCTAssertTrue(waitForAbsence(query(ID.gameDetail(gameID), in: app), timeout: stateSettleTimeout),
                      "Back leaves the game", file: file, line: line)
        element(screen, in: app, file: file, line: line)
    }

    // MARK: Minimizing

    /// Drags Home's list up, as a person scrolls down, until the tab bar
    /// minimizes, when it lists the selected tab alone.
    private func scrollHomeDownUntilTheTabBarMinimizes(in app: XCUIApplication, file: StaticString = #filePath,
                                                       line: UInt = #line) {
        let tabBar = app.tabBars.firstMatch
        let minimized = { tabBar.exists && tabBar.buttons.count == 1 }
        for _ in 0..<4 where !minimized() {
            dragHomeUp(in: app)
            _ = pollUntil(timeout: 2, condition: minimized)
        }
        XCTAssertTrue(minimized(), "Home scrolled down minimizes the tab bar, which then lists one tab: "
                      + "\(tabBar.exists ? tabBar.buttons.count : 0) listed", file: file, line: line)
    }

    /// One slow drag up Home's list from the window's middle, above the bar,
    /// held before lifting so the list stops where it ends.
    private func dragHomeUp(in app: XCUIApplication) {
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -windowFrame(in: app).height * 0.3)),
                    withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    // MARK: The Duo's poses

    /// The Duo's poses, by the names its other journeys take
    /// (`SURROUND_DUO_POSE`, TESTING.md), as Device Hub sets them: a fold,
    /// then Rotate Right for Closed sideways or a tall pose.
    private enum DuoPose: String {
        case closedPortrait = "closed-portrait", closedLandscape = "closed-landscape"
        case bookWide = "book-wide", bookTall = "book-tall", openWide = "open-wide"

        var deviceHub: String {
            switch self {
            case .closedPortrait: "Closed"
            case .closedLandscape: "Closed, then Rotate Right"
            case .bookWide: "Partially Open"
            case .bookTall: "Partially Open, then Rotate Right"
            case .openWide: "Open"
            }
        }

        var isClosed: Bool { self == .closedPortrait || self == .closedLandscape }

        var isLandscape: Bool { self == .closedLandscape || self == .bookWide || self == .openWide }

        /// The app's window in this pose: the closed Duo's outer display,
        /// shorter than 600 pt either way, or the inner display, wide or
        /// tall. Book and Open share theirs.
        func fits(_ window: CGRect) -> Bool {
            guard !window.isNull, !window.isEmpty else { return false }
            return (min(window.width, window.height) < 600) == isClosed && (window.width > window.height) == isLandscape
        }

        /// The bar in this pose: beside the rail in Closed, 290 pt upright in
        /// its one-line form and 346 pt sideways; where no tab bar holds it,
        /// the host's 360 pt, but in Book within its leading pane.
        var bar: (width: CGFloat, form: String) {
            switch self {
            case .closedPortrait: (290, "closed")
            case .closedLandscape, .bookWide: (346, "expanded")
            case .bookTall, .openWide: (360, "expanded")
            }
        }
    }

    /// How long a journey waits for the run to set a pose it asked for.
    private static let duoPoseWait: TimeInterval = 120

    /// The Duo's own journeys ask the run for poses: they run on the Duo
    /// only, and only where the run answers them.
    private func skipUnlessARunSetsTheDuosPoses() throws {
        try XCTSkipUnless(isDuo, "The Duo only: its poses are Device Hub's, and CI has no Duo.")
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SURROUND_DUO_POSES"] == "1",
                          "Only where the run sets each pose the journey asks for in Device Hub, as \"[DuoPose] "
                          + "<pose>\" in the simulator's log: TEST_RUNNER_SURROUND_DUO_POSES=1.")
    }

    /// An Activity state at Home, launched in one of the Duo's poses, with
    /// the host log's layout lines (`--surround-activity-hidden-log`). A
    /// device in another pose is asked for it first, with the app open to
    /// watch its window, `running` or a launch where the device is, and the
    /// app then launches again in the pose: once the app's window has moved
    /// between the Duo's displays, XCTest no longer hears when the app
    /// settles, and each tap waits a minute for it.
    private func launchOnTheDuo(_ state: State, in pose: DuoPose, from running: XCUIApplication? = nil,
                                file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        func open() -> XCUIApplication {
            let app = launchApp(additionalLaunchArguments: [SurroundUITestContract.activityStateLaunchArgument,
                                                            state.rawValue, "--surround-activity-hidden-log"],
                                orientation: pose.isLandscape ? .landscapeLeft : .portrait)
            element(ID.screenHome, in: app, file: file, line: line)
            return app
        }
        let app = running ?? open()
        if running == nil, pose.isClosed, pose.fits(windowFrame(in: app)) { return app }
        setDuoPose(pose, in: app, file: file, line: line)
        app.terminate()
        return open()
    }

    /// Asks for one of the Duo's poses and waits until the app's window has
    /// its shape and holds it. XCTest can't set a pose: the request goes to
    /// the simulator's log, where the run answers it in Device Hub. Book and
    /// Open give the window the same shapes, so a request for one whose
    /// shape the window already has goes by way of Closed upright, whose
    /// shape is its own, as Closed sideways's is: the closed pose the device
    /// already has is met at once.
    private func setDuoPose(_ pose: DuoPose, in app: XCUIApplication, file: StaticString = #filePath,
                            line: UInt = #line) {
        if !pose.isClosed, pose.fits(windowFrame(in: app)) {
            setDuoPose(.closedPortrait, in: app, file: file, line: line)
        }
        NSLog("[DuoPose] %@", pose.rawValue)
        let asked = Date()
        var window = CGRect.null
        var previous: CGRect?
        let met = pollUntil(timeout: Self.duoPoseWait) {
            window = self.windowFrame(in: app)
            defer { previous = window }
            return pose.fits(window) && window == previous
        }
        note(String(format: "The Duo in %@ (%@ in Device Hub), %.1f s after the journey asked for it", pose.rawValue,
                    pose.deviceHub, Date().timeIntervalSince(asked)))
        XCTAssertTrue(met, "The Duo didn't take \(pose.rawValue) within \(Int(Self.duoPoseWait)) s: set "
                      + "\(pose.deviceHub) in Device Hub while the journey waits. The window is \(window)",
                      file: file, line: line)
    }

    /// The Duo's bar as this pose draws it, once UIKit has set it again
    /// after the pose's transition: HarborMist's lead in this device's host,
    /// at the pose's width, 48 pt tall and in the pose's form; upright, the
    /// one-line form, whose line names the opponent as the lead's label
    /// does.
    private func assertTheDuosBar(in pose: DuoPose, after event: String, in app: XCUIApplication,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let lead = barLead(in: app, file: file, line: line)
        assertLeads("live \(harborMist)", in: app, file: file, line: line)
        var reading = BarReading()
        let drawn = pollUntil(timeout: 10) {
            reading = self.barReading(in: app)
            guard let bar = reading.bar, let state = reading.state else { return false }
            return abs(bar.width - pose.bar.width) <= 1 && state.hasSuffix(" \(pose.bar.form)")
        }
        let summary = "\(reading.bar.map { "\($0)" } ?? "no bar"), \(reading.state ?? "no state"), "
            + "window \(windowFrame(in: app))"
        attach("After \(event): \(summary)", name: "The bar in \(pose.rawValue)")
        XCTAssertTrue(drawn, "After \(event), \(pose.rawValue)'s bar is \(Int(pose.bar.width)) pt wide and "
                      + "\(pose.bar.form): \(summary)", file: file, line: line)
        XCTAssertEqual(reading.bar?.height ?? 0, 48, accuracy: 1, "The bar is 48 pt tall: \(summary)",
                       file: file, line: line)
        XCTAssertTrue(lead.label.contains("HarborMist"), "The lead names HarborMist: \(lead.label)",
                      file: file, line: line)
    }

    /// A screenshot of each of the Duo's displays: XCTest's own shows the
    /// outer one, dark while the Duo is open.
    private func keepTheDuosScreens(_ name: String) {
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let attachment = XCTAttachment(screenshot: screen.screenshot(), quality: .original)
            attachment.name = "\(name), display \(index + 1) of \(XCUIScreen.screens.count)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
    #endif

    // MARK: Helpers

    private func query(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitForLabel(_ label: String, of element: XCUIElement,
                              timeout: TimeInterval? = nil) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label == %@", label), object: element)
        return waitWithFinalCheck(for: [expectation], timeout: timeout ?? stateSettleTimeout) == .completed
    }

    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return waitWithFinalCheck(for: [gone], timeout: timeout) == .completed
    }

    private func attach(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A step the host makes moot, kept in the run's activity log.
    private func note(_ text: String) {
        XCTContext.runActivity(named: text) { _ in }
    }
}
#endif
