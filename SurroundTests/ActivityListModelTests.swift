//
//  ActivityListModelTests.swift
//  SurroundTests
//
//  The Activity list's pure rules: its sections and the rows the user
//  resolved, waiting ids, how it is presented, which of a row's controls
//  work, what an accepted game does, and how a Quick Match withdraw settles.
//

import CoreGraphics
import XCTest

final class ActivityListModelTests: XCTestCase {
    private typealias Item = ActivityModel.Item
    private typealias Sections = ActivityListSections
    private typealias Withdrawal = ActivityQuickMatchWithdrawal

    // MARK: Builders

    private func game(_ id: Int) -> Item {
        .liveGame(ActivityModel.LiveGame(id: id, isYourMove: true))
    }

    private func challenge(_ id: Int) -> Item {
        .challenge(ActivityModel.Challenge(id: id, isLive: true))
    }

    private func waiting(_ id: String, kind: ActivityModel.Waiting.Kind = .openChallenge) -> Item {
        .waiting(ActivityModel.Waiting(id: id, kind: kind, isLive: true, since: 0))
    }

    private func conversation(_ peer: Int) -> Item {
        .conversation(ActivityModel.Conversation(peerID: peer, isUnread: true, lastMessageTime: 100))
    }

    private let correspondence = Item.correspondenceGames(count: 2, mostUrgentID: 90)

    private func resolved(
        _ id: String, after: String?, section: ActivitySection = .waiting
    ) -> ActivityResolvedRow {
        ActivityResolvedRow(id: id, section: section, after: after,
                            display: ActivityRowDisplay(title: "Open challenge", detail: "Live · 19×19"))
    }

    private func rowIDs(_ list: [Item], _ resolved: [ActivityResolvedRow] = []) -> [[String]] {
        Sections.sections(list: list, resolved: resolved).map { $0.rows.map(\.id) }
    }

    /// Every section's rows, in order.
    private func rows(_ list: [Item], _ resolved: [ActivityResolvedRow] = []) -> [Sections.Row] {
        Sections.sections(list: list, resolved: resolved).flatMap(\.rows)
    }

    // MARK: Sections

    func testItemsSplitIntoSectionsInTheModelsOrder() {
        let list = [game(2), game(1), challenge(7), waiting("open-4"), waiting("quick-match-a", kind: .quickMatch),
                    correspondence, conversation(31), conversation(30)]
        let sections = Sections.sections(list: list, resolved: [])
        XCTAssertEqual(sections.map(\.kind), [.liveGames, .challengesReceived, .waiting, .correspondence, .messages])
        XCTAssertEqual(sections.map(\.rows), [
            [.item(game(2)), .item(game(1))],
            [.item(challenge(7))],
            [.item(waiting("open-4")), .item(waiting("quick-match-a", kind: .quickMatch))],
            [.item(correspondence)],
            [.item(conversation(31)), .item(conversation(30))],
        ], "Each section keeps the model's order.")
        XCTAssertEqual(list.map(ActivitySection.section(of:)),
                       [.liveGames, .liveGames, .challengesReceived, .waiting, .waiting, .correspondence,
                        .messages, .messages])
    }

    func testEmptySectionsAreLeftOutAndMessagesNeedAConversation() {
        XCTAssertTrue(Sections.sections(list: [], resolved: []).isEmpty, "Nothing waiting: no sections at all.")
        XCTAssertEqual(Sections.sections(list: [challenge(7), correspondence], resolved: []).map(\.kind),
                       [.challengesReceived, .correspondence], "No conversation, no Messages section.")
        XCTAssertEqual(Sections.sections(list: [conversation(30)], resolved: []).map(\.kind), [.messages])
        XCTAssertEqual(
            Sections.sections(list: [], resolved: [resolved("conversation-30", after: nil, section: .messages)])
                .map(\.kind),
            [], "Messages shows only with a listed conversation."
        )
    }

    // MARK: Waiting ids

    func testWaitingIDsParseBackToWhatTheyStandFor() {
        typealias WaitingID = ActivityModel.WaitingID
        XCTAssertEqual(ActivityWaitingRef.parse(WaitingID.quickMatch("7c1e0a52-search")), .quickMatch("7c1e0a52-search"))
        XCTAssertEqual(ActivityWaitingRef.parse(WaitingID.openChallenge(93001)), .openChallenge(93001))
        XCTAssertEqual(ActivityWaitingRef.parse(WaitingID.sentChallenge(12)), .sentChallenge(12))
        XCTAssertEqual(ActivityWaitingRef.parse(WaitingID.rengo(55)), .rengo(55))
        for id in ["", "quick-match-", "open-", "open-x", "open-+5", "open-05", "sent- 5", "rengo-5.0",
                   "challenge-5", "waiting-open-5", "Open-5"] {
            XCTAssertNil(ActivityWaitingRef.parse(id), "\(id) isn't a waiting id.")
        }
    }

    // MARK: Results merged by id

    func testAResolvedItemStillListedKeepsItsOwnRow() {
        XCTAssertEqual(
            rowIDs([waiting("open-4"), waiting("open-5")], [resolved("waiting-open-5", after: "waiting-open-4")]),
            [["waiting-open-4", "waiting-open-5"]]
        )
        XCTAssertEqual(
            rows([waiting("open-5")], [resolved("waiting-open-5", after: nil)]),
            [.item(waiting("open-5"))], "The live row shows the result, never a second row."
        )
    }

    func testAGoneItemComesBackAfterTheItemBeforeIt() {
        XCTAssertEqual(rows([waiting("open-4"), waiting("open-6")], [resolved("waiting-open-5", after: "waiting-open-4")]), [
            .item(waiting("open-4")),
            .resolved(resolved("waiting-open-5", after: "waiting-open-4")),
            .item(waiting("open-6")),
        ])
    }

    func testAGoneItemWithNothingBeforeItGoesFirstInItsSection() {
        XCTAssertEqual(
            rowIDs([game(1), waiting("open-6")], [
                resolved("waiting-open-5", after: nil),
                resolved("waiting-open-7", after: "waiting-open-3"),
            ]),
            [["game-1"], ["waiting-open-5", "waiting-open-7", "waiting-open-6"]],
            "No predecessor, or one that left without a result: first, in the order given."
        )
        XCTAssertEqual(
            rowIDs([game(1)], [resolved("challenge-7", after: nil, section: .challengesReceived)]),
            [["game-1"], ["challenge-7"]], "A resolved row keeps its section open."
        )
    }

    func testGoneItemsFollowEachOther() {
        XCTAssertEqual(
            rowIDs([waiting("open-4"), waiting("open-8")], [
                resolved("waiting-open-6", after: "waiting-open-5"),
                resolved("waiting-open-5", after: "waiting-open-4"),
            ]),
            [["waiting-open-4", "waiting-open-5", "waiting-open-6", "waiting-open-8"]]
        )
        XCTAssertEqual(
            rowIDs([waiting("open-4")], [
                resolved("waiting-open-5", after: "waiting-open-4"),
                resolved("waiting-open-6", after: "waiting-open-4"),
            ]),
            [["waiting-open-4", "waiting-open-5", "waiting-open-6"]], "Two after one item keep the order given."
        )
    }

    func testAReappearingIDShowsOnce() {
        let gone = resolved("waiting-open-5", after: "waiting-open-4")
        XCTAssertEqual(rowIDs([waiting("open-4")], [gone, gone]), [["waiting-open-4", "waiting-open-5"]],
                       "A repeated result is one row.")
        XCTAssertEqual(rowIDs([waiting("open-5"), waiting("open-4")], [gone]), [["waiting-open-5", "waiting-open-4"]],
                       "Back in the model, the item's own row takes over where the model puts it.")
        XCTAssertEqual(rowIDs([waiting("open-4"), waiting("open-4")]), [["waiting-open-4"]])
    }

    func testRowsThatPointAtEachOtherAreAllShown() {
        let rows = rowIDs([waiting("open-4")], [
            resolved("waiting-open-5", after: "waiting-open-6"),
            resolved("waiting-open-6", after: "waiting-open-5"),
            resolved("waiting-open-7", after: "waiting-open-7"),
        ])
        XCTAssertEqual(rows, [["waiting-open-5", "waiting-open-6", "waiting-open-7", "waiting-open-4"]])
    }

    // MARK: Presentation

    func testAGameAlwaysUsesAPopoverAndCompactRootsUseTheSheet() {
        let game = ActivityModel.Place.game(id: 26268404, isOwnGame: true, isLive: true, isOver: false)
        let home = ActivityModel.Place.root(isMessagesTab: false)
        func style(_ sizeClass: ActivityPresentationStyle.SizeClass, _ place: ActivityModel.Place,
                   crosses: Bool = false) -> ActivityPresentationStyle {
            .style(horizontalSizeClass: sizeClass, place: place, crossesDivision: crosses)
        }
        XCTAssertEqual(style(.compact, game), .popover)
        XCTAssertEqual(style(.regular, game), .popover)
        XCTAssertEqual(style(.regular, game, crosses: true), .popover, "A game keeps its popover across a division.")
        XCTAssertEqual(style(.compact, home), .sheet)
        XCTAssertEqual(style(.regular, home), .popover)
        XCTAssertEqual(style(.regular, home, crosses: true), .sheet, "A popover that would cross a hinge becomes the sheet.")
        XCTAssertEqual(style(.compact, .conversation), .sheet)
        XCTAssertEqual(style(.regular, .conversation), .popover)
    }

    func testARequestIsItsSession() {
        let session = UUID()
        let request = ActivityRequest(sessionID: session, source: .messagesButton, focus: .messages, style: .popover,
                                      anchor: CGRect(x: 10, y: 20, width: 44, height: 44))
        XCTAssertEqual(request.id, session)
        XCTAssertEqual(ActivityRequest(source: .homeSearching, style: .sheet).focus, .top)
        XCTAssertEqual(ActivityRequest(source: .homeSearching, style: .sheet).place, .root(isMessagesTab: false),
                       "Without a place, the list opened on a root screen.")
        XCTAssertNotEqual(ActivityRequest(source: .debug, style: .sheet).id,
                          ActivityRequest(source: .debug, style: .sheet).id)
    }

    // MARK: Row controls

    func testInlineAcceptOnlyForAUsualChallengeOutsideAGame() {
        func inline(unusual: Bool, inGame: Bool) -> Bool {
            ActivityRowActionState(isUnusual: unusual, isInGamePopover: inGame, isOffline: false, state: nil)
                .showsInlineAcceptAndReject
        }
        XCTAssertTrue(inline(unusual: false, inGame: false))
        XCTAssertFalse(inline(unusual: true, inGame: false), "An unusual challenge shows its warning and View.")
        XCTAssertFalse(inline(unusual: false, inGame: true), "A game's popover always uses View.")
        XCTAssertFalse(inline(unusual: true, inGame: true))
    }

    func testOfflineDimsTheActionsButNotViewOrOpenGame() {
        let offline = ActivityRowActionState(isUnusual: false, isInGamePopover: false, isOffline: true, state: .failed)
        for control in [ActivityRowActionState.Control.accept, .reject, .withdraw, .retry] {
            XCTAssertFalse(offline.isEnabled(control), "\(control)")
            XCTAssertEqual(offline.accessibilityValue(control), "Reconnecting…", "\(control)")
        }
        for control in [ActivityRowActionState.Control.view, .openGame] {
            XCTAssertTrue(offline.isEnabled(control), "\(control)")
            XCTAssertNil(offline.accessibilityValue(control), "\(control)")
        }

        let online = ActivityRowActionState(isUnusual: false, isInGamePopover: false, isOffline: false, state: nil)
        for control in ActivityRowActionState.Control.allCases {
            XCTAssertTrue(online.isEnabled(control), "\(control)")
            XCTAssertNil(online.accessibilityValue(control), "\(control)")
        }
    }

    func testAPendingActionDisablesTheRowsOtherActions() {
        let pending = ActivityRowActionState(isUnusual: false, isInGamePopover: false, isOffline: false,
                                             state: .pending(since: 10))
        for control in [ActivityRowActionState.Control.accept, .reject, .withdraw, .retry] {
            XCTAssertFalse(pending.isEnabled(control), "\(control)")
            XCTAssertNil(pending.accessibilityValue(control), "Pending isn't offline: \(control)")
        }
        XCTAssertTrue(pending.isEnabled(.view))
        XCTAssertTrue(pending.isEnabled(.openGame))

        let failed = ActivityRowActionState(isUnusual: false, isInGamePopover: false, isOffline: false, state: .failed)
        XCTAssertTrue(failed.isEnabled(.retry))
        let started = ActivityRowActionState(isUnusual: false, isInGamePopover: false, isOffline: false,
                                             state: .succeeded(.gameStarted(gameID: 5)))
        XCTAssertTrue(started.isEnabled(.openGame))
    }

    // MARK: Accept

    func testALiveGameClosesAndOpensAndCorrespondenceStays() {
        XCTAssertEqual(ActivityAcceptRule(isLive: true, gameID: 901), .closeAndOpen(gameID: 901))
        XCTAssertEqual(ActivityAcceptRule(isLive: false, gameID: 902), .stay(outcome: .gameStarted(gameID: 902)))
    }

    func testPendingActionsSayWhatIsBeingSent() {
        XCTAssertEqual([ActivityAction.accept, .reject, .withdraw, .leave, .start].map(\.pendingText), [
            "Accepting…", "Rejecting…", "Withdrawing…", "Leaving…", "Starting…",
        ])
    }

    func testResultsAndFailuresReadAsTheRowShowsThem() {
        XCTAssertEqual(ActivityOutcome.gameStarted(gameID: 1).text, "Game started")
        XCTAssertEqual(ActivityOutcome.rejected.text, "Rejected")
        XCTAssertEqual(ActivityOutcome.withdrawn.text, "Withdrawn")
        XCTAssertEqual(ActivityOutcome.left.text, "Left")
        XCTAssertEqual([ActivityAction.accept, .reject, .withdraw, .leave, .start].map(\.failureText), [
            "Couldn’t accept", "Couldn’t reject", "Couldn’t withdraw", "Couldn’t leave", "Couldn’t start",
        ])
    }

    // MARK: Rows and cards

    func testAnItemIDNamesTheChallengeOrWaitingItemItsCardShows() {
        XCTAssertEqual(ActivityItemRef.parse("challenge-95001"), .challenge(95_001))
        XCTAssertEqual(ActivityItemRef.parse("waiting-quick-match-a1c7"), .waiting(.quickMatch("a1c7")))
        XCTAssertEqual(ActivityItemRef.parse("waiting-open-95101"), .waiting(.openChallenge(95_101)))
        XCTAssertEqual(ActivityItemRef.parse("waiting-sent-95201"), .waiting(.sentChallenge(95_201)))
        XCTAssertEqual(ActivityItemRef.parse("waiting-rengo-95301"), .waiting(.rengo(95_301)))
        for other in ["game-91004001", "conversation-915100", "correspondence-games", "challenge-", "challenge-05",
                      "challenge-x", "waiting-", "waiting-open-x", "open-95101", "95001"] {
            XCTAssertNil(ActivityItemRef.parse(other), other)
        }

        typealias WaitingID = ActivityModel.WaitingID
        XCTAssertEqual(ActivityItemRef.parse(challenge(7).id), .challenge(7), "An item's own id reads back.")
        XCTAssertEqual(ActivityItemRef.parse(waiting(WaitingID.quickMatch("u-1"), kind: .quickMatch).id),
                       .waiting(.quickMatch("u-1")))
        XCTAssertEqual(ActivityItemRef.parse(waiting(WaitingID.rengo(9), kind: .rengo).id), .waiting(.rengo(9)))
    }

    func testAPositionIsTheRowsSectionAndTheRowBeforeIt() {
        let sections = Sections.sections(
            list: [game(1), game(2), challenge(3), waiting("open-4")],
            resolved: [resolved("waiting-open-5", after: "waiting-open-4")]
        )
        let second = Sections.position(of: "game-2", in: sections)
        XCTAssertEqual(second?.section, .liveGames)
        XCTAssertEqual(second?.after, "game-1")
        let first = Sections.position(of: "game-1", in: sections)
        XCTAssertEqual(first?.section, .liveGames)
        XCTAssertNil(first?.after, "It leads its section.")
        XCTAssertEqual(Sections.position(of: "challenge-3", in: sections)?.section, .challengesReceived)
        XCTAssertNil(Sections.position(of: "challenge-3", in: sections)?.after, "Sections don't run into each other.")
        XCTAssertEqual(Sections.position(of: "waiting-open-5", in: sections)?.after, "waiting-open-4",
                       "A resolved row has a place too.")
        XCTAssertNil(Sections.position(of: "waiting-open-9", in: sections))
    }

    func testElapsedTimeReadsMinutesThenHoursThenDays() {
        func text(_ seconds: TimeInterval) -> String {
            ActivityElapsed.text(seconds, locale: Locale(identifier: "en_US"))
        }
        XCTAssertEqual(text(0), "0:00")
        XCTAssertEqual(text(72), "1:12")
        XCTAssertEqual(text(220.9), "3:40", "Whole seconds, rounded down.")
        XCTAssertEqual(text(3_599), "59:59")
        XCTAssertEqual(text(3_600), "1h", "From an hour, hours and minutes, short enough for one line.")
        XCTAssertEqual(text(3_659), "1h", "Seconds no longer show.")
        XCTAssertEqual(text(3_900), "1h 5m")
        XCTAssertEqual(text(36_125), "10h 2m")
        XCTAssertEqual(text(86_399), "23h 59m")
        XCTAssertEqual(text(90_061), "1d 1h", "From a day, days and hours.")
        XCTAssertEqual(text(172_800 + 300), "2d")
        XCTAssertEqual(text(-3), "0:00", "A clock that went back reads no time.")
    }

    func testAQuickMatchRowWithdrawsInPlaceOnlyForOneSizeAtOneSpeed() {
        func entry(_ options: [(Int, TimeControlSpeed)]) -> OGSAutomatchEntry {
            OGSAutomatchEntry(
                sizeSpeedOptions: options.map { OGSAutomatchSizeSpeedOption(size: $0.0, speed: $0.1, system: .byoyomi) },
                uuid: "u", creationTimestamp: nil
            )
        }
        XCTAssertTrue(ActivityQuickMatchRow.withdrawsInPlace(entry([(19, .live)])))
        XCTAssertTrue(ActivityQuickMatchRow.withdrawsInPlace(entry([(19, .live), (19, .live)])),
                      "The same size and speed twice is still one search.")
        XCTAssertFalse(ActivityQuickMatchRow.withdrawsInPlace(entry([(19, .correspondence), (13, .correspondence)])))
        XCTAssertFalse(ActivityQuickMatchRow.withdrawsInPlace(entry([(19, .blitz), (19, .live)])))
    }

    // MARK: Quick Match withdraws

    func testAWithdrawIsPendingOnlyWhenTheSocketSentIt() {
        XCTAssertEqual(Withdrawal.start(uuid: "a", sent: true, at: 100), .init(uuid: "a", state: .pending(since: 100)))
        XCTAssertEqual(Withdrawal.start(uuid: "a", sent: false, at: 100), .init(uuid: "a", state: .failed))
    }

    func testLifecycleEventsSettleTheWithdrawsTheyName() {
        let entries: [String: Withdrawal.Entry] = [
            "a": .init(uuid: "a", state: .pending(since: 0)),
            "b": .init(uuid: "b", state: .pending(since: 0)),
        ]
        let cancelled = Withdrawal.apply(.cancelled(uuid: "a", removedCount: 1), to: entries)
        XCTAssertEqual(cancelled["a"]?.state, .succeeded(.withdrawn))
        XCTAssertEqual(cancelled["b"], entries["b"], "Another search's cancel changes nothing.")
        XCTAssertEqual(Withdrawal.apply(.cancelled(uuid: nil, removedCount: 2), to: entries).mapValues(\.state),
                       ["a": .succeeded(.withdrawn), "b": .succeeded(.withdrawn)], "OGS ended every search.")

        let started = Withdrawal.apply(.started(uuid: "a", gameID: 77, requestedLocally: false), to: entries)
        XCTAssertNil(started["a"], "A game was found: no withdraw result.")
        XCTAssertEqual(started["b"], entries["b"])

        XCTAssertEqual(Withdrawal.apply(.notFoundAfterReconciliation(uuid: "b"), to: entries)["b"]?.state, .failed)
        XCTAssertEqual(Withdrawal.apply(.entry(uuid: "a"), to: entries), entries, "OGS listing it again changes nothing.")
    }

    func testAFailedWithdrawStillTakesALateCancelButASettledOneDoesNot() {
        let failed: [String: Withdrawal.Entry] = ["a": .init(uuid: "a", state: .failed)]
        XCTAssertEqual(Withdrawal.apply(.cancelled(uuid: "a", removedCount: 1), to: failed)["a"]?.state,
                       .succeeded(.withdrawn))
        XCTAssertNil(Withdrawal.apply(.started(uuid: "a", gameID: nil, requestedLocally: false), to: failed)["a"])
        XCTAssertEqual(Withdrawal.apply(.notFoundAfterReconciliation(uuid: "a"), to: failed), failed)

        let withdrawn: [String: Withdrawal.Entry] = ["a": .init(uuid: "a", state: .succeeded(.withdrawn))]
        XCTAssertEqual(Withdrawal.apply(.started(uuid: "a", gameID: 1, requestedLocally: true), to: withdrawn), withdrawn)
        XCTAssertEqual(Withdrawal.apply(.notFoundAfterReconciliation(uuid: "a"), to: withdrawn), withdrawn)
    }

    func testAnUnconfirmedWithdrawFailsEightSecondsAfterItWasSent() {
        let entries: [String: Withdrawal.Entry] = [
            "a": .init(uuid: "a", state: .pending(since: 100)),
            "b": .init(uuid: "b", state: .pending(since: 103)),
            "c": .init(uuid: "c", state: .failed),
        ]
        XCTAssertEqual(Withdrawal.confirmationLimit, 8)
        XCTAssertEqual(Withdrawal.nextDeadline(entries: entries), 108)
        XCTAssertEqual(Withdrawal.expire(entries, at: 107.9), entries)
        let expired = Withdrawal.expire(entries, at: 108)
        XCTAssertEqual(expired["a"]?.state, .failed)
        XCTAssertEqual(expired["b"], entries["b"])
        XCTAssertEqual(Withdrawal.nextDeadline(entries: expired), 111)
        XCTAssertNil(Withdrawal.nextDeadline(entries: Withdrawal.expire(expired, at: 111)), "Nothing left to wait for.")
        XCTAssertNil(Withdrawal.nextDeadline(entries: [String: Withdrawal.Entry]()))
    }
}
