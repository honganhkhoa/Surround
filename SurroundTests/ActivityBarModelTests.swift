//
//  ActivityBarModelTests.swift
//  SurroundTests
//
//  The Activity bar's pure rules: what it shows, from the window's Activity,
//  its connection and the status its host carries; the words every carrier
//  says, the line under root titles and the Now section's status row; the
//  forms from traits, and the parts each form draws and drops; which host
//  shows the bar, from container state; the order a UIKit container follows
//  around its tab bar; and what VoiceOver hears as a lead first leads.
//

import CoreGraphics
import XCTest

final class ActivityBarModelTests: XCTestCase {
    private typealias Model = ActivityModel
    private typealias Policy = ActivityHostPolicy
    private typealias Words = RootConnectionLine.Words
    private typealias Lead = ActivityBarLead
    private typealias Counted = ActivityBarCountedItem
    private typealias Content = ActivityBarContent
    private typealias Activity = ActivityBarActivity
    private typealias Order = ActivityAccessoryOrder

    // MARK: Builders

    private func yourMove(_ id: Int, left: TimeInterval = 300) -> Model.LiveGame {
        Model.LiveGame(id: id, isYourMove: true, isClockRunning: true, timeUntilTimeout: left)
    }

    private func theirMove(_ id: Int) -> Model.LiveGame {
        Model.LiveGame(id: id, isYourMove: false)
    }

    private func liveChallenge(_ id: Int) -> Model.Challenge {
        Model.Challenge(id: id, isLive: true)
    }

    private func unread(_ peer: Int) -> Model.Conversation {
        Model.Conversation(peerID: peer, isUnread: true, lastMessageTime: 100)
    }

    private func waiting(_ id: String, _ kind: Model.Waiting.Kind) -> Model.Waiting {
        Model.Waiting(id: id, kind: kind, isLive: true, since: 0)
    }

    private var search: Model.Waiting { waiting("quick-match-a", .quickMatch) }

    private func result(_ state: ActivityActionState) -> ActivityBarResult {
        ActivityBarResult(itemID: "waiting-open-4", action: .withdraw, state: state,
                          display: ActivityRowDisplay(title: "Open challenge", detail: "Live · 19×19"))
    }

    private var withdrawing: ActivityBarResult { result(.pending(since: 10)) }
    private var failed: ActivityBarResult { result(.failed) }

    /// Every lead kind the bar draws.
    private var everyLead: [Lead] {
        [.liveGame(gameID: 1), .gameStarted(gameID: 7), .challenge(liveChallenge(9)),
         .waiting(search, withdrawsInPlace: true), .nothingLeads(count: 2)]
    }

    private let everyPlacement: [Policy.ConnectionStatus] = [.floatingBar, .rootSubtitle, .nowSectionFirstRow]
    private let everyWords: [Words?] = [nil, .connecting, .reconnecting, .unreachable, .connected]

    private func content(_ activity: Activity, _ words: Words?, _ placement: Policy.ConnectionStatus) -> Content? {
        Content(activity, words: words, placement: placement)
    }

    // MARK: The words every carrier says

    func testEachStatusSaysItsWordsBeforeAndAfterTheFirstConnection() {
        for socket in [OGSWebsocketStatus.disconnected, .connecting, .connected, .reconnecting] {
            for hasConnected in [false, true] {
                func words(_ status: ConnectionStatusModel.Status) -> Words? {
                    RootConnectionLine.words(status: status, hasConnected: hasConnected, socket: socket)
                }
                let label = "\(socket) hasConnected=\(hasConnected)"
                XCTAssertNil(words(.hidden), label)
                XCTAssertEqual(words(.unreachable(.timedOut)), .unreachable, label)
                XCTAssertEqual(words(.unreachable(.noNetwork)), .unreachable, label)
                XCTAssertEqual(words(.connected), .connected, label)
                XCTAssertEqual(words(.reconnecting), hasConnected || socket == .reconnecting ? .reconnecting : .connecting,
                               "As the clocks say it: \(label)")
            }
        }
    }

    func testAFirstAttemptConnectsAndAFailedOneReconnects() {
        XCTAssertEqual(RootConnectionLine.words(status: .reconnecting, hasConnected: false, socket: .connecting),
                       .connecting)
        XCTAssertEqual(RootConnectionLine.words(status: .reconnecting, hasConnected: false, socket: .reconnecting),
                       .reconnecting, "The socket reports reconnecting after any failed attempt, a first one too.")
        XCTAssertEqual(RootConnectionLine.words(status: .reconnecting, hasConnected: true, socket: .connecting),
                       .reconnecting, "Retry starts a fresh attempt, which still recovers a connection.")
    }

    func testTheLineIsBlankAsASpaceAfterWordsThisVisitAndEmptyOtherwise() {
        for shown in [false, true] {
            XCTAssertEqual(RootConnectionLine(status: .reconnecting, hasConnected: true, socket: .reconnecting,
                                              shownThisVisit: shown), .says(.reconnecting))
            XCTAssertEqual(RootConnectionLine(status: .unreachable(.timedOut), hasConnected: true, socket: .reconnecting,
                                              shownThisVisit: shown), .says(.unreachable))
            XCTAssertEqual(RootConnectionLine(status: .connected, hasConnected: true, socket: .connected,
                                              shownThisVisit: shown), .says(.connected))
            XCTAssertEqual(RootConnectionLine(status: .reconnecting, hasConnected: false, socket: .connecting,
                                              shownThisVisit: shown), .says(.connecting))
        }
        XCTAssertEqual(RootConnectionLine(status: .hidden, hasConnected: true, socket: .connected, shownThisVisit: true),
                       .space, "After Connected, a space keeps the line and the title still.")
        XCTAssertEqual(RootConnectionLine(status: .hidden, hasConnected: true, socket: .connected, shownThisVisit: false),
                       .empty, "A connected root reserves nothing.")
        XCTAssertEqual(RootConnectionLine.says(.connecting).words, .connecting)
        XCTAssertNil(RootConnectionLine.space.words)
        XCTAssertNil(RootConnectionLine.empty.words)
    }

    // MARK: The Now section's status row

    func testTheStatusRowShowsWheneverThereAreWordsButOverAGame() {
        let root = Model.Place.root(isMessagesTab: false)
        XCTAssertNil(NowStatusRow(nil, place: root), "Nothing to say, no row.")
        for words in [Words.connecting, .reconnecting, .unreachable, .connected] {
            XCTAssertEqual(NowStatusRow(words, place: root)?.words, words, "\(words)")
            XCTAssertEqual(NowStatusRow(words, place: .root(isMessagesTab: true))?.words, words, "\(words)")
            XCTAssertEqual(NowStatusRow(words, place: .conversation)?.words, words, "Beside a conversation: \(words)")
            for place: Model.Place in [.game(id: 3, isOwnGame: true, isLive: true, isOver: false),
                                       .game(id: 500, isOwnGame: false, isLive: true, isOver: false)] {
                XCTAssertNil(NowStatusRow(words, place: place), "A game says its status itself: \(words)")
            }
            XCTAssertEqual(NowStatusRow(words, place: root)?.offersRetry, words == .unreachable,
                           "Retry at Can’t reach OGS only: \(words)")
        }
        XCTAssertEqual(NowStatusRow(status: .connected, hasConnected: true, socket: .connected, place: root)?.words,
                       .connected, "Connected for 2 s after an outage someone saw.")
        XCTAssertEqual(NowStatusRow(status: .reconnecting, hasConnected: false, socket: .connecting, place: root)?.words,
                       .connecting)
        XCTAssertNil(NowStatusRow(status: .hidden, hasConnected: true, socket: .connected, place: root))
    }

    func testTheStatusRowTakesTheFirstOfTheSectionsRows() {
        let row = NowStatusRow(.unreachable, place: .root(isMessagesTab: false))
        XCTAssertEqual(NowStatusRow.activityRows(beside: nil), 2)
        XCTAssertEqual(NowStatusRow.activityRows(beside: row), 1)
        XCTAssertEqual(NowStatusRow.activityRows(beside: row, of: 1), 0, "A short window's one row goes to it.")
        XCTAssertEqual(NowStatusRow.activityRows(beside: row, of: 0), 0)

        var input = Model.Input()
        input.liveGames = [yourMove(1, left: 100), yourMove(2, left: 200)]
        let section = Model.nowSection(input, rows: NowStatusRow.activityRows(beside: row))
        XCTAssertEqual(section.rows, [.item(.liveGame(yourMove(1, left: 100)))], "Beside a lead.")
        XCTAssertEqual(section.plusN, 1, "All activity's +N takes the item the status row displaced.")
        XCTAssertEqual(Model.nowSection(Model.Input(), rows: NowStatusRow.activityRows(beside: row)).rows, [],
                       "With nothing waiting the status row shows alone.")
    }

    // MARK: The bar's Activity

    func testTheBarsActivityKeepsNoTickingField() {
        var input = Model.Input()
        input.liveGames = [yourMove(1, left: 42), yourMove(2)]
        input.conversations = [unread(30)]
        let first = Activity(Model.snapshot(input))
        input.liveGames = [yourMove(1, left: 41), yourMove(2, left: 299)]
        XCTAssertEqual(Activity(Model.snapshot(input)), first, "A clock's tick changes nothing the bar state publishes.")
        XCTAssertEqual(first.lead, .liveGame(gameID: 1))
        XCTAssertEqual(first.counted, [.liveGame(gameID: 2), .conversation(peerID: 30)])
        XCTAssertEqual(first.countedLead, .liveGame(gameID: 1))
        XCTAssertEqual(first.plusN, 2)
        XCTAssertNil(first.result)
        XCTAssertEqual(Activity(Model.snapshot(input), result: withdrawing).result, withdrawing)
        XCTAssertEqual(Activity(Model.snapshot(Model.Input())), Activity(), "Nothing waits: nothing to show.")
    }

    func testEachLeadKeepsItsKindAndItsItem() {
        XCTAssertEqual(Lead(.gameStarted(theirMove(7))), .gameStarted(gameID: 7))
        XCTAssertEqual(Lead(.item(.liveGame(yourMove(1)))), .liveGame(gameID: 1))
        XCTAssertEqual(Lead(.item(.liveGame(theirMove(3)))), .liveGame(gameID: 3))
        XCTAssertEqual(Lead(.item(.challenge(liveChallenge(9)))), .challenge(liveChallenge(9)))
        XCTAssertEqual(Lead(.waiting(count: 3)), .nothingLeads(count: 3))
        XCTAssertNil(Lead(.item(.conversation(unread(30)))), "A conversation never leads.")
        XCTAssertNil(Lead(.item(.correspondenceGames(count: 1, mostUrgentID: 90))))

        XCTAssertEqual(Lead.liveGame(gameID: 1).itemID, "game-1")
        XCTAssertEqual(Lead.gameStarted(gameID: 7).itemID, "game-7")
        XCTAssertEqual(Lead.challenge(liveChallenge(9)).itemID, "challenge-9")
        XCTAssertEqual(Lead.waiting(search, withdrawsInPlace: true).itemID, "waiting-quick-match-a")
        XCTAssertNil(Lead.nothingLeads(count: 3).itemID)

        XCTAssertEqual(everyLead.filter(\.isGame), [.liveGame(gameID: 1), .gameStarted(gameID: 7)],
                       "A game's lead has a clock or Open game.")
    }

    func testWithdrawShowsWhereTheListsRowWithdrawsInPlace() {
        let open = waiting("open-4", .openChallenge)
        let sent = waiting("sent-5", .sentChallenge)
        let rengo = waiting("rengo-1", .rengo)
        XCTAssertEqual(Lead(.item(.waiting(open))), .waiting(open, withdrawsInPlace: true))
        XCTAssertEqual(Lead(.item(.waiting(sent))), .waiting(sent, withdrawsInPlace: true))
        XCTAssertEqual(Lead(.item(.waiting(rengo)), searchWithdrawsInPlace: { _ in true }),
                       .waiting(rengo, withdrawsInPlace: false), "Rengo's card holds Start and Leave.")
        XCTAssertEqual(Lead(.item(.waiting(search))), .waiting(search, withdrawsInPlace: false))
        XCTAssertEqual(Lead(.item(.waiting(search)), searchWithdrawsInPlace: { $0 == self.search }),
                       .waiting(search, withdrawsInPlace: true), "A search of one size at one speed.")
    }

    func testTheLeadCountsOnlyWhereItWaitsForYou() {
        func activity(_ build: (inout Model.Input) -> Void) -> Activity {
            var input = Model.Input()
            build(&input)
            return Activity(Model.snapshot(input))
        }
        XCTAssertEqual(activity { $0.liveGames = [yourMove(1)] }.countedLead, .liveGame(gameID: 1))
        XCTAssertNil(activity { $0.liveGames = [theirMove(3)] }.countedLead, "A live game on their move never counts.")
        XCTAssertEqual(activity { $0.challengesReceived = [liveChallenge(9)] }.countedLead, .challenge(liveChallenge(9)))
        XCTAssertNil(activity { $0.waiting = [search] }.countedLead, "Your own search never counts.")
        let startedOnYourMove = activity {
            $0.liveGames = [yourMove(7)]
            $0.startedGames = [7: 1_000]
            $0.now = 1_005
        }
        XCTAssertEqual(startedOnYourMove.lead, .gameStarted(gameID: 7))
        XCTAssertEqual(startedOnYourMove.countedLead, .liveGame(gameID: 7))
        let nothingLeads = activity { $0.challengesReceived = [Model.Challenge(id: 8, isLive: false)] }
        XCTAssertEqual(nothingLeads.lead, .nothingLeads(count: 1))
        XCTAssertNil(nothingLeads.countedLead, "N waiting counts its items itself.")
        XCTAssertEqual(nothingLeads.counted, [.challenge(Model.Challenge(id: 8, isLive: false))])
        XCTAssertEqual(nothingLeads.plusN, 0)
    }

    // MARK: What the bar shows

    func testTheFirstRowThatAppliesWins() {
        let lead = Activity(lead: .liveGame(gameID: 1), counted: [.conversation(peerID: 30)],
                            countedLead: .liveGame(gameID: 1))
        var withResult = lead
        withResult.result = withdrawing
        for placement in everyPlacement {
            for words in everyWords {
                XCTAssertEqual(content(withResult, words, placement), .result(withdrawing),
                               "A result comes first: \(placement) \(String(describing: words))")
            }
        }
        XCTAssertEqual(content(lead, .unreachable, .floatingBar),
                       .unreachable(counted: [.liveGame(gameID: 1), .conversation(peerID: 30)]))
        XCTAssertEqual(content(lead, .reconnecting, .floatingBar),
                       .lead(.liveGame(gameID: 1), counted: [.conversation(peerID: 30)], status: .reconnecting))
        XCTAssertEqual(content(Activity(), .reconnecting, .floatingBar), .status(.reconnecting))
        XCTAssertNil(content(Activity(), nil, .floatingBar), "Otherwise no bar.")
    }

    func testAResultStaysThoughTheModelHasNoLead() {
        let withdrawn = result(.succeeded(.withdrawn))
        for state in [withdrawing, withdrawn, failed] {
            for placement in everyPlacement {
                XCTAssertEqual(content(Activity(result: state), nil, placement), .result(state), "\(placement)")
            }
        }
        XCTAssertEqual(content(Activity(result: failed), nil, .rootSubtitle)?.plusN, 0)
    }

    func testEveryLeadKindShowsWithWhatElseWaits() {
        for lead in everyLead {
            let isNothingLeads = lead == .nothingLeads(count: 2)
            let counted: [Counted] = isNothingLeads
                ? [.conversation(peerID: 30), .conversation(peerID: 31)] : [.conversation(peerID: 30)]
            for placement in everyPlacement {
                let shown = content(Activity(lead: lead, counted: counted), nil, placement)
                XCTAssertEqual(shown, .lead(lead, counted: counted, status: nil), "\(lead) \(placement)")
                XCTAssertEqual(shown?.plusN, isNothingLeads ? 0 : 1, "\(lead) \(placement)")
            }
        }
    }

    func testWhereTheBarCarriesAllStatusEveryLeadSaysTheOutage() {
        for lead in everyLead {
            for words in [Words.connecting, .reconnecting] {
                XCTAssertEqual(content(Activity(lead: lead), words, .floatingBar),
                               .lead(lead, counted: [], status: words), "\(lead) \(words)")
            }
            XCTAssertEqual(content(Activity(lead: lead), .connected, .floatingBar), .lead(lead, counted: [], status: nil),
                           "Line two just returns: \(lead)")
        }
    }

    func testFromIOS26OnlyAGamesLeadSaysTheOutage() {
        for lead in everyLead {
            for words in [Words.connecting, .reconnecting] {
                for placement in [Policy.ConnectionStatus.rootSubtitle, .nowSectionFirstRow] {
                    XCTAssertEqual(content(Activity(lead: lead), words, placement),
                                   .lead(lead, counted: [], status: lead.isGame ? words : nil),
                                   "The title says it; a game's clock can't move: \(lead) \(words) \(placement)")
                }
            }
        }
    }

    func testCantReachOGSFoldsTheLeadIntoPlusNOnlyWhereItCounts() {
        func unreachable(_ build: (inout Model.Input) -> Void) -> Content? {
            var input = Model.Input()
            build(&input)
            return content(Activity(Model.snapshot(input)), .unreachable, .rootSubtitle)
        }
        let yours = unreachable {
            $0.liveGames = [yourMove(1)]
            $0.challengesReceived = [liveChallenge(9)]
        }
        XCTAssertEqual(yours, .unreachable(counted: [.liveGame(gameID: 1), .challenge(liveChallenge(9))]))
        XCTAssertEqual(yours?.plusN, 2)
        XCTAssertEqual(unreachable {
            $0.liveGames = [theirMove(3)]
            $0.conversations = [unread(30)]
        }, .unreachable(counted: [.conversation(peerID: 30)]), "A game on their move doesn't count.")
        XCTAssertEqual(unreachable { $0.waiting = [search] }, .unreachable(counted: []), "Nor does your own search.")
        XCTAssertEqual(unreachable { $0.challengesReceived = [liveChallenge(9)] },
                       .unreachable(counted: [.challenge(liveChallenge(9))]))
        XCTAssertEqual(unreachable {
            $0.challengesReceived = [Model.Challenge(id: 8, isLive: false)]
            $0.conversations = [unread(30)]
        }, .unreachable(counted: [.challenge(Model.Challenge(id: 8, isLive: false)), .conversation(peerID: 30)]),
                       "What N waiting counted.")
    }

    func testCantReachOGSShowsWithNothingWaitingWhereTheBarCarriesIt() {
        // Offline at a cold launch Activity is empty.
        let empty = Activity(Model.snapshot(Model.Input()))
        for placement in [Policy.ConnectionStatus.floatingBar, .rootSubtitle] {
            XCTAssertEqual(content(empty, .unreachable, placement), .unreachable(counted: []), "\(placement)")
            XCTAssertEqual(content(empty, .unreachable, placement)?.plusN, 0)
        }
        XCTAssertNil(content(empty, .unreachable, .nowSectionFirstRow), "The Now section's row says it there.")
    }

    func testFromIOS26TheBarShowsOnlyActivityOrCantReachOGS() {
        for words in [Words.connecting, .reconnecting, .connected] {
            XCTAssertNil(content(Activity(), words, .rootSubtitle), "The line under the title says it: \(words)")
            XCTAssertNil(content(Activity(), words, .nowSectionFirstRow), "The Now row says it: \(words)")
        }
        XCTAssertNil(content(Activity(), nil, .rootSubtitle))
    }

    func testWhereTheBarCarriesAllStatusItSaysEachKindWithNothingWaiting() {
        for words in [Words.connecting, .reconnecting, .connected] {
            XCTAssertEqual(content(Activity(), words, .floatingBar), .status(words), "\(words)")
            XCTAssertEqual(content(Activity(), words, .floatingBar)?.plusN, 0)
        }
    }

    func testConnectedShowsOnlyWithNothingElseToShow() {
        XCTAssertEqual(content(Activity(), .connected, .floatingBar), .status(.connected))
        XCTAssertEqual(content(Activity(lead: .challenge(liveChallenge(9))), .connected, .floatingBar),
                       .lead(.challenge(liveChallenge(9)), counted: [], status: nil))
        XCTAssertEqual(content(Activity(result: withdrawing), .connected, .floatingBar), .result(withdrawing))
    }

    func testTheContentReadsTheWindowsConnection() {
        func shown(_ status: ConnectionStatusModel.Status, _ hasConnected: Bool,
                   _ socket: OGSWebsocketStatus) -> Content? {
            Content(Activity(), status: status, hasConnected: hasConnected, socket: socket, placement: .floatingBar)
        }
        XCTAssertEqual(shown(.reconnecting, false, .connecting), .status(.connecting), "Before the first connection.")
        XCTAssertEqual(shown(.reconnecting, true, .reconnecting), .status(.reconnecting))
        XCTAssertEqual(shown(.unreachable(.noNetwork), false, .connecting), .unreachable(counted: []))
        XCTAssertEqual(shown(.connected, true, .connected), .status(.connected))
        XCTAssertNil(shown(.hidden, true, .connected))
    }

    func testWhatEachHostCarries() {
        XCTAssertTrue(Policy.ConnectionStatus.floatingBar.barCarriesAllStatus)
        XCTAssertTrue(Policy.ConnectionStatus.floatingBar.barCarriesUnreachable)
        XCTAssertFalse(Policy.ConnectionStatus.rootSubtitle.barCarriesAllStatus)
        XCTAssertTrue(Policy.ConnectionStatus.rootSubtitle.barCarriesUnreachable)
        XCTAssertFalse(Policy.ConnectionStatus.nowSectionFirstRow.barCarriesAllStatus)
        XCTAssertFalse(Policy.ConnectionStatus.nowSectionFirstRow.barCarriesUnreachable)

        func placement(_ platform: Policy.Platform, _ container: Policy.Container, _ release: Policy.Release,
                       sidebar: Policy.Sidebar = .unavailable) -> Policy.ConnectionStatus {
            Policy.hosts(for: .init(platform: platform, container: container, release: release, sdkHasHostAPIs: true,
                                    sidebar: sidebar)).connectionStatus
        }
        XCTAssertTrue(placement(.iPhone, .swiftUITabView, .iOS18).barCarriesAllStatus, "The custom bar before iOS 26.")
        for release in Policy.Release.allCases {
            for sidebar in [Policy.Sidebar.hidden, .unavailable] {
                XCTAssertTrue(placement(.iPad, .iPadTabContainer, release, sidebar: sidebar).barCarriesAllStatus,
                              "The iPad's floating bar on every iPadOS: \(release) \(sidebar)")
            }
        }
        for (container, release) in [(Policy.Container.swiftUITabView, Policy.Release.iOS26_0),
                                      (.swiftUITabView, .iOS26_1), (.duoTabContainer, .iOS27_0),
                                      (.duoTabContainer, .iOS27_2)] {
            let carries = placement(.iPhone, container, release)
            XCTAssertFalse(carries.barCarriesAllStatus, "\(container) \(release)")
            XCTAssertTrue(carries.barCarriesUnreachable, "Can’t reach OGS with Retry: \(container) \(release)")
        }
    }

    // MARK: Forms

    private func form(_ bar: Policy.Bar, _ container: Policy.Container,
                      _ placement: Policy.AccessoryPlacement = .unavailable, compactWidth: Bool = true,
                      compactHeight: Bool = false, verticalEdge: Bool = false) -> ActivityBarForm {
        ActivityBarForm(ActivityBarTraits(bar: bar, container: container, placement: placement,
                                          isCompactWidth: compactWidth, isCompactHeight: compactHeight,
                                          hasVerticalBarEdge: verticalEdge))
    }

    func testTheFormComesFromTheHostAndItsTraits() {
        XCTAssertEqual(form(.customBar, .swiftUITabView), .expanded)
        XCTAssertEqual(form(.customBar, .swiftUITabView, compactHeight: true), .compactHeight, "A phone in landscape.")
        XCTAssertEqual(form(.customBar, .iPadTabContainer, compactWidth: false), .expanded)
        XCTAssertEqual(form(.customBar, .swiftUITabView, .inline), .expanded, "The custom bar never minimizes.")
        for placement in [Policy.AccessoryPlacement.expanded, .notInAccessory, .unspecified, .unavailable] {
            XCTAssertEqual(form(.swiftUIAccessory, .swiftUITabView, placement), .expanded, "\(placement)")
            XCTAssertEqual(form(.uiKitAccessory, .duoTabContainer, placement), .expanded,
                           "The first layouts report no placement: \(placement)")
            XCTAssertEqual(form(.uiKitAccessory, .duoTabContainer, placement, compactHeight: true), .expanded,
                           "A Max in landscape: \(placement)")
            XCTAssertEqual(form(.uiKitAccessory, .iPadTabContainer, placement, compactWidth: false), .expanded)
        }
        XCTAssertEqual(form(.swiftUIAccessory, .swiftUITabView, .inline), .inline)
        XCTAssertEqual(form(.uiKitAccessory, .duoTabContainer, .inline), .inline, "Beside the Home circle.")
        XCTAssertEqual(form(.uiKitAccessory, .duoTabContainer, .inline, compactHeight: true), .inline,
                       "In the landscape tab bar's row.")
    }

    func testTheDuosClosedTraitsGiveTheOneLineFormWithTheName() {
        for placement in [Policy.AccessoryPlacement.expanded, .notInAccessory] {
            XCTAssertEqual(form(.uiKitAccessory, .duoTabContainer, placement, verticalEdge: true), .closed,
                           "Compact width, regular height and a vertical bar edge: \(placement)")
        }
        XCTAssertEqual(form(.uiKitAccessory, .duoTabContainer, .expanded, compactHeight: true, verticalEdge: true),
                       .expanded, "Closed sideways is 346 pt, expanded.")
        XCTAssertEqual(form(.uiKitAccessory, .duoTabContainer, .expanded, compactWidth: false, verticalEdge: true),
                       .expanded, "Book and Open are wide.")
        XCTAssertEqual(form(.uiKitAccessory, .duoTabContainer, .expanded), .expanded, "An iPhone in portrait.")
        XCTAssertEqual(form(.uiKitAccessory, .iPadTabContainer, .expanded, verticalEdge: true), .expanded,
                       "Only the Duo's container is Closed.")
        XCTAssertEqual(form(.customBar, .duoTabContainer, verticalEdge: true), .expanded, "A forced custom bar.")
        XCTAssertEqual([ActivityBarForm.expanded, .compactHeight, .inline, .closed].filter(\.isOneLine),
                       [.inline, .closed])
    }

    // MARK: What each form draws

    private func parts(_ content: Content, _ form: ActivityBarForm) -> [ActivityBarPart] {
        ActivityBarDrawing(content, form: form).parts
    }

    private let one: [Counted] = [.conversation(peerID: 30)]

    /// One of each kind of content.
    private var everyContent: [Content] {
        var contents: [Content] = everyLead.map { Content.lead($0, counted: one, status: nil) }
        let rengo = Lead.waiting(waiting("rengo-1", .rengo), withdrawsInPlace: false)
        contents.append(Content.lead(rengo, counted: [], status: nil))
        contents += [Content.unreachable(counted: one), Content.unreachable(counted: [])]
        contents += [Content.status(.reconnecting), Content.status(.connected)]
        contents += [Content.result(withdrawing), Content.result(failed)]
        return contents
    }

    func testExpandedDrawsBothLinesTheTrailingActionAndPlusN() {
        XCTAssertEqual(parts(.lead(.liveGame(gameID: 1), counted: one, status: nil), .expanded),
                       [.tile, .lineOne, .lineTwo, .hourglass, .clock, .plusN])
        XCTAssertEqual(parts(.lead(.gameStarted(gameID: 7), counted: [], status: nil), .expanded),
                       [.tile, .lineOne, .lineTwo, .action(.openGame)])
        XCTAssertEqual(parts(.lead(.challenge(liveChallenge(9)), counted: one, status: nil), .expanded),
                       [.tile, .lineOne, .lineTwo, .action(.view), .plusN], "Never an inline Accept.")
        XCTAssertEqual(parts(.lead(.waiting(search, withdrawsInPlace: true), counted: [], status: nil), .expanded),
                       [.tile, .lineOne, .lineTwo, .action(.withdraw)])
        XCTAssertEqual(parts(.lead(.waiting(waiting("rengo-1", .rengo), withdrawsInPlace: false), counted: [],
                                   status: nil), .expanded),
                       [.tile, .lineOne, .lineTwo], "Rengo's card holds its actions.")
        XCTAssertEqual(parts(.lead(.nothingLeads(count: 2), counted: one + one, status: nil), .expanded),
                       [.tile, .lineOne, .lineTwo], "N waiting has no action and no +N.")
        XCTAssertEqual(parts(.unreachable(counted: one), .expanded), [.tile, .lineOne, .action(.retry), .plusN])
        XCTAssertEqual(parts(.unreachable(counted: []), .expanded), [.tile, .lineOne, .action(.retry)])
        XCTAssertEqual(parts(.status(.reconnecting), .expanded), [.tile, .lineOne], "Status, not a button.")
        XCTAssertEqual(parts(.result(withdrawing), .expanded), [.tile, .lineOne, .lineTwo])
        XCTAssertEqual(parts(.result(failed), .expanded), [.tile, .lineOne, .lineTwo, .action(.retry)])
        for content in everyContent {
            XCTAssertEqual(ActivityBarDrawing(content, form: .expanded).dropOrder, [],
                           "Lines truncate; nothing drops: \(content)")
        }
    }

    func testTheCompactHeightLineDropsLineTwoAndKeepsActionsRetryAndPlusN() {
        for content in everyContent {
            let drawing = ActivityBarDrawing(content, form: .compactHeight)
            XCTAssertEqual(drawing.parts, parts(content, .expanded).filter { $0 != .lineTwo }, "\(content)")
            XCTAssertEqual(drawing.dropOrder, [], "\(content)")
        }
        XCTAssertTrue(parts(.unreachable(counted: []), .compactHeight).contains(.action(.retry)),
                      "Every root offers Retry in landscape.")
    }

    func testTheOneLineFormsDrawTheTileLineOneAGamesClockAndPlusN() {
        for form in [ActivityBarForm.inline, .closed] {
            XCTAssertEqual(parts(.lead(.liveGame(gameID: 1), counted: one, status: .reconnecting), form),
                           [.tile, .lineOne, .hourglass, .clock, .plusN], "\(form)")
            XCTAssertEqual(parts(.lead(.gameStarted(gameID: 7), counted: one, status: nil), form),
                           [.tile, .lineOne, .plusN], "Its action waits in Activity: \(form)")
            XCTAssertEqual(parts(.lead(.challenge(liveChallenge(9)), counted: one, status: nil), form),
                           [.tile, .lineOne, .plusN], "\(form)")
            XCTAssertEqual(parts(.lead(.waiting(search, withdrawsInPlace: true), counted: [], status: nil), form),
                           [.tile, .lineOne], "\(form)")
            XCTAssertEqual(parts(.unreachable(counted: one), form), [.tile, .lineOne, .action(.retry), .plusN],
                           "Can’t reach OGS keeps Retry: \(form)")
            XCTAssertEqual(parts(.result(failed), form), [.tile, .lineOne, .action(.retry)],
                           "Couldn’t withdraw keeps Retry: \(form)")
            XCTAssertEqual(parts(.result(withdrawing), form), [.tile, .lineOne], "\(form)")
        }
    }

    /// Widths that make each drop visible: the tile 30, line one at its
    /// narrowest 20, the hourglass 12, the clock 50, an action 44, +N 36.
    private func width(_ part: ActivityBarPart) -> CGFloat {
        switch part {
        case .tile: 30
        case .lineOne: 20
        case .lineTwo: 0
        case .hourglass: 12
        case .clock: 50
        case .action: 44
        case .plusN: 36
        }
    }

    private let spacing = ActivityBarSpacing(leading: 8, trailing: 8, between: 6)

    func testTheOneLineFormsDropTheHourglassThenTheTileThenPlusN() {
        let drawing = ActivityBarDrawing(.lead(.liveGame(gameID: 1), counted: one, status: nil), form: .inline)
        XCTAssertEqual(drawing.dropOrder, [.hourglass, .tile, .plusN])
        // 16 of padding, 148 of parts and 24 of spacing.
        XCTAssertEqual(drawing.fit(in: 188, spacing: spacing, partWidth: width).parts, drawing.parts)
        XCTAssertEqual(drawing.fit(in: 187, spacing: spacing, partWidth: width).parts, [.tile, .lineOne, .clock, .plusN])
        XCTAssertEqual(drawing.fit(in: 169, spacing: spacing, partWidth: width).parts, [.lineOne, .clock, .plusN])
        XCTAssertEqual(drawing.fit(in: 133, spacing: spacing, partWidth: width).parts, [.lineOne, .clock])
        let overflow = drawing.fit(in: 91, spacing: spacing, partWidth: width)
        XCTAssertEqual(overflow.parts, [.lineOne, .clock], "The clock never drops.")
        XCTAssertEqual(overflow.width, 92)
        XCTAssertFalse(overflow.fits, "An overflow is reported.")
        XCTAssertTrue(drawing.fit(in: 92, spacing: spacing, partWidth: width).fits)
    }

    func testCantReachOGSKeepsRetryInTheOneLineForms() {
        for form in [ActivityBarForm.inline, .closed] {
            let drawing = ActivityBarDrawing(.unreachable(counted: one), form: form)
            XCTAssertEqual(drawing.dropOrder, [.tile, .plusN], "\(form)")
            let fit = drawing.fit(in: 0, spacing: spacing, partWidth: width)
            XCTAssertEqual(fit.parts, [.lineOne, .action(.retry)], "Retry never drops: \(form)")
            XCTAssertFalse(fit.fits)
        }
    }

    /// Where the bar says all status, the custom bar and the iPad's floating
    /// bar, the two-line and compact-height forms drop the hourglass, then
    /// the tile, then +N, so that the status words and a lead's status badge
    /// read whole; the status words take line two's place in the two-line
    /// form. Retry and the clock never drop, and a phone's accessory from
    /// iOS 26, under a title that says the words, drops nothing.
    func testTheBarsThatSayAllStatusMakeRoomForTheStatusWords() {
        XCTAssertTrue(ActivityBarTraits(bar: .customBar, container: .swiftUITabView).saysAllStatus)
        XCTAssertTrue(ActivityBarTraits(bar: .customBar, container: .iPadTabContainer).saysAllStatus)
        XCTAssertTrue(ActivityBarTraits(bar: .uiKitAccessory, container: .iPadTabContainer).saysAllStatus)
        XCTAssertFalse(ActivityBarTraits(bar: .swiftUIAccessory, container: .swiftUITabView).saysAllStatus)
        XCTAssertFalse(ActivityBarTraits(bar: .uiKitAccessory, container: .duoTabContainer).saysAllStatus)
        for content in everyContent {
            for form in [ActivityBarForm.expanded, .compactHeight] {
                let drawing = ActivityBarDrawing(content, form: form, saysAllStatus: true)
                XCTAssertEqual(drawing.parts, parts(content, form), "The same parts: \(content) \(form)")
                XCTAssertEqual(drawing.dropOrder, [.hourglass, .tile, .plusN].filter(drawing.parts.contains),
                               "\(content) \(form)")
                XCTAssertEqual(drawing.lineOneLines, form == .expanded && !drawing.parts.contains(.lineTwo) ? 2 : 1,
                               "The status words take line two's place: \(content) \(form)")
                XCTAssertEqual(ActivityBarDrawing(content, form: form).lineOneLines, 1, "\(content) \(form)")
            }
        }
        let unreachable = ActivityBarDrawing(.unreachable(counted: one), form: .expanded, saysAllStatus: true)
        XCTAssertEqual(unreachable.fit(in: 0, spacing: spacing, partWidth: width).parts, [.lineOne, .action(.retry)],
                       "Retry never drops")
        let live = ActivityBarDrawing(.lead(.liveGame(gameID: 1), counted: one, status: .reconnecting), form: .expanded,
                                      saysAllStatus: true)
        XCTAssertEqual(live.fit(in: 0, spacing: spacing, partWidth: width).parts, [.lineOne, .lineTwo, .clock],
                       "The clock never drops")
    }

    func testTheClosedBarTruncatesTheNameBeforeAnythingDrops() {
        let drawing = ActivityBarDrawing(.lead(.liveGame(gameID: 1), counted: one, status: nil), form: .closed)
        // The name measures 200, but line one counts at its narrowest, so in
        // 290 pt the name truncates and every part stays.
        func named(_ part: ActivityBarPart) -> CGFloat { part == .lineOne ? 20 : width(part) }
        XCTAssertEqual(drawing.fit(in: 290, spacing: spacing, partWidth: named).parts, drawing.parts)
        XCTAssertGreaterThan(spacing.width(of: drawing.parts) { $0 == .lineOne ? 200 : width($0) }, 290,
                             "At its full width the name wouldn't fit.")
    }

    // MARK: Who shows the bar

    private func facts(_ platform: Policy.Platform, _ container: Policy.Container, _ release: Policy.Release,
                       sidebar: Policy.Sidebar = .unavailable, sdk: Bool = true) -> Policy.Facts {
        Policy.Facts(platform: platform, container: container, release: release, sdkHasHostAPIs: sdk, sidebar: sidebar)
    }

    /// A host ready to show the bar: content on a root, the tab bar shown, in
    /// a window.
    private func host(_ facts: Policy.Facts) -> ActivityBarHostState {
        var state = ActivityBarHostState(facts: facts)
        state.hasContent = true
        state.isInWindow = true
        return state
    }

    private var customBarHosts: [Policy.Facts] {
        [facts(.iPhone, .swiftUITabView, .iOS18), facts(.iPhone, .swiftUITabView, .iOS26_0),
         facts(.iPhone, .swiftUITabView, .iOS26_1, sdk: false), facts(.iPad, .iPadTabContainer, .iOS18, sidebar: .hidden),
         facts(.iPad, .iPadTabContainer, .iOS18)]
    }

    private var duo: Policy.Facts { facts(.iPhone, .duoTabContainer, .iOS27_2) }
    private var iPad: Policy.Facts { facts(.iPad, .iPadTabContainer, .iOS26_1, sidebar: .hidden) }

    func testTheCustomBarShowsOnScreensTheRegistryLeavesUntilAKeyboardDocks() {
        for facts in customBarHosts {
            var state = host(facts)
            XCTAssertEqual(state.shownBar, .customBar, "\(facts)")
            state.isKeyboardOverWindow = true
            XCTAssertNil(state.shownBar, "It hides with the keyboard, as the tab bar does: \(facts)")
            state.isKeyboardOverWindow = false
            state.placeHidesBar = true
            XCTAssertNil(state.shownBar, "Game Detail, or a conversation, a pane's included: \(facts)")
            state.placeHidesBar = false
            state.hasContent = false
            XCTAssertNil(state.shownBar, "No content, no bar: \(facts)")
            state.hasContent = true
            state.requestedTabBar = .hidden
            state.isInWindow = false
            XCTAssertEqual(state.shownBar, .customBar, "Each screen draws its own, so neither is an input: \(facts)")
        }
        XCTAssertNil(host(facts(.iPad, .iPadTabContainer, .iOS18, sidebar: .shown)).shownBar,
                     "Never beside a shown sidebar.")
    }

    func testSwiftUIsAccessoryFollowsTheRegistryAndTheContent() {
        var state = host(facts(.iPhone, .swiftUITabView, .iOS26_1))
        XCTAssertEqual(state.shownBar, .swiftUIAccessory)
        state.isKeyboardOverWindow = true
        state.hasBottomTabBar = true
        XCTAssertEqual(state.shownBar, .swiftUIAccessory, "A docked keyboard hides it with the tab bar: no input.")
        state.placeHidesBar = true
        XCTAssertNil(state.shownBar)
        state.placeHidesBar = false
        state.hasContent = false
        XCTAssertNil(state.shownBar)
        XCTAssertEqual(host(facts(.iPhone, .swiftUITabView, .iOS27_2)).shownBar, .swiftUIAccessory,
                       "iOS 27 built without its SDK.")
    }

    func testUIKitsAccessoryOnIOS27IPhonesAndTheDuo() {
        var state = host(duo)
        XCTAssertEqual(state.shownBar, .uiKitAccessory)
        state.requestedTabBar = .hidden
        XCTAssertNil(state.shownBar, "The requested tab-bar state, whatever the registry or isTabBarHidden says.")
        state.requestedTabBar = .shown
        state.isInWindow = false
        XCTAssertNil(state.shownBar, "Never set before the container's view is in a window.")
        state.isInWindow = true
        state.isDrawerShown = true
        XCTAssertNil(state.shownBar, "It steps aside while the drawer shows.")
        state.isCompactHeight = true
        XCTAssertEqual(state.shownBar, .uiKitAccessory, "A Max in landscape keeps its bar beside the drawer.")
        state.isDrawerShown = false
        state.isCompactHeight = false
        state.isKeyboardOverWindow = true
        XCTAssertEqual(state.shownBar, .uiKitAccessory, "With a bottom tab bar the keyboard covers both: no code.")
        state.hasBottomTabBar = false
        XCTAssertNil(state.shownBar, "The Duo's poses and a Max in landscape clear it under the keyboard.")
        state.isKeyboardOverWindow = false
        XCTAssertEqual(state.shownBar, .uiKitAccessory)
        state.isGameAskedFor = true
        XCTAssertEqual(state.shownBar, .uiKitAccessory, "The early clear is the iPad's: an iPhone hides its tab bar.")
        state.placeHidesBar = true
        XCTAssertNil(state.shownBar)
        state.placeHidesBar = false
        state.overrides.forcesCustomBar = true
        XCTAssertEqual(state.shownBar, .customBar)
    }

    func testTheIPadsSystemBar() {
        var state = host(iPad)
        XCTAssertEqual(state.shownBar, .uiKitAccessory)
        state.isGameAskedFor = true
        XCTAssertNil(state.shownBar, "Cleared as soon as a game is asked for, before the game's first layout.")
        state.isGameAskedFor = false
        state.facts.sidebar = .shown
        XCTAssertNil(state.shownBar, "The sidebar record says shown.")
        state.facts.sidebar = .unavailable
        XCTAssertEqual(state.shownBar, .uiKitAccessory, "A compact window's bar sits above the bottom tab bar.")
        state.isKeyboardOverWindow = true
        XCTAssertNil(state.shownBar, "The keyboard over the window clears it, a bottom tab bar or not.")
        state.isKeyboardOverWindow = false
        state.isDrawerShown = true
        XCTAssertEqual(state.shownBar, .uiKitAccessory, "The drawer record is the Duo's.")
        state.requestedTabBar = .hidden
        XCTAssertNil(state.shownBar)
        state.requestedTabBar = .shown
        state.isInWindow = false
        XCTAssertNil(state.shownBar)
        for release in Policy.Release.allCases where release >= .iOS26_0 {
            XCTAssertEqual(host(facts(.iPad, .iPadTabContainer, release, sidebar: .hidden)).shownBar, .uiKitAccessory,
                           "\(release)")
        }
    }

    func testTheMacShowsNoBar() {
        for release in Policy.Release.allCases {
            XCTAssertNil(host(facts(.mac, .swiftUITabView, release)).shownBar, "\(release)")
        }
    }

    /// The table of where the bar hides: a game or a conversation on top
    /// (the registry's place, a pane's included), sheets, alerts and the
    /// superchat cover (no input: the bar waits underneath), the keyboard,
    /// and signed out (only status content).
    func testEveryHostFollowsWhereTheBarHides() {
        let hosts = customBarHosts + [facts(.iPhone, .swiftUITabView, .iOS26_1), duo,
                                      facts(.iPhone, .duoTabContainer, .iOS27_0), iPad,
                                      facts(.iPad, .iPadTabContainer, .iOS27_0)]
        for facts in hosts {
            let shown = host(facts)
            XCTAssertNotNil(shown.shownBar, "On a root with content, under any sheet: \(facts)")
            var onTop = shown
            onTop.placeHidesBar = true
            XCTAssertNil(onTop.shownBar, "A game or a conversation on top of the selected tab: \(facts)")
            var signedOut = shown
            signedOut.hasContent = Content(Activity(), words: .unreachable,
                                           placement: Policy.hosts(for: facts).connectionStatus) != nil
            XCTAssertNotNil(signedOut.shownBar, "Signed out, Can’t reach OGS still shows: \(facts)")
            signedOut.hasContent = Content(Activity(), words: nil,
                                           placement: Policy.hosts(for: facts).connectionStatus) != nil
            XCTAssertNil(signedOut.shownBar, "Signed out and connected, nothing shows: \(facts)")
        }
    }

    // MARK: The order around the tab bar

    /// A UIKit container as the order drives it, recording each UIKit call.
    private struct UIKitContainer {
        var state: ActivityBarHostState
        var accessory = false
        var calls = [String]()
        /// A recompute during each tab-bar change, as a registry turn or an
        /// update inside its layout would make.
        var reentrantAnswers = [Bool]()

        init(_ state: ActivityBarHostState) {
            self.state = state
        }

        mutating func run(_ steps: [ActivityAccessoryStep]) {
            for step in steps {
                switch step {
                case .record(let record):
                    state.requestedTabBar = record
                case .recompute:
                    apply(state.shownBar == .uiKitAccessory)
                case .clearWithoutAnimation:
                    apply(false)
                case .changeTabBar(let hidden):
                    calls.append("tab bar \(hidden ? "hidden" : "shown"), accessory \(accessory ? "set" : "clear")")
                    reentrantAnswers.append(state.shownBar == .uiKitAccessory)
                }
            }
        }

        mutating func recompute() { run([.recompute]) }

        private mutating func apply(_ wanted: Bool) {
            guard wanted != accessory else { return }
            accessory = wanted
            calls.append(wanted ? "set" : "clear")
        }
    }

    func testAHideRecordsClearsThenCallsAndAShowCallsRecordsThenSets() {
        XCTAssertEqual(Order.tabBar(from: .shown, to: .hidden),
                       [.record(.hidden), .recompute, .changeTabBar(hidden: true), .recompute])
        XCTAssertEqual(Order.tabBar(from: .hidden, to: .shown), [.changeTabBar(hidden: false), .record(.shown), .recompute])
        XCTAssertEqual(Order.tabBar(from: .shown, to: .shown), [.recompute], "Every call recomputes at the end.")
        XCTAssertEqual(Order.tabBar(from: .hidden, to: .hidden), [.recompute])
        XCTAssertEqual(Order.sizeTransitionCompleted, [.clearWithoutAnimation, .recompute])
        XCTAssertEqual(Order.drawerReturnDelay, 0.5)
    }

    func testAHideClearsBeforeTheCallThoughTheRegistryHasntSettled() {
        for facts in [duo, iPad] {
            var container = UIKitContainer(host(facts))
            container.recompute()
            // A game is pushed; its registration settles a turn later, so the
            // place still hides nothing as the tab bar hides.
            container.run(Order.tabBar(from: .shown, to: .hidden))
            XCTAssertEqual(container.calls, ["set", "clear", "tab bar hidden, accessory clear"], "\(facts)")
        }
    }

    func testARecomputeDuringEitherCallGivesTheSameAnswer() {
        var container = UIKitContainer(host(duo))
        container.recompute()
        container.run(Order.tabBar(from: .shown, to: .hidden))
        container.run(Order.tabBar(from: .hidden, to: .shown))
        XCTAssertEqual(container.reentrantAnswers, [false, false],
                       "Mid-hide and mid-show the record says hidden, as just before each call.")
        XCTAssertEqual(container.calls, ["set", "clear", "tab bar hidden, accessory clear",
                                         "tab bar shown, accessory clear", "set"])
    }

    func testAGameClosingSetsTheBarOnceTheTabBarShowsAndTheSidebarHasSettled() {
        var container = UIKitContainer(host(iPad))
        container.state.requestedTabBar = .hidden
        container.state.facts.sidebar = .shown
        container.run(Order.tabBar(from: .hidden, to: .shown))
        XCTAssertEqual(container.calls, ["tab bar shown, accessory clear"], "No set beside a sidebar opened over the game.")
        // The sidebar's hide completes: the record turns hidden, and the set follows.
        container.state.facts.sidebar = .hidden
        container.recompute()
        XCTAssertEqual(container.calls.last, "set")

        var duoContainer = UIKitContainer(host(duo))
        duoContainer.state.requestedTabBar = .hidden
        duoContainer.run(Order.tabBar(from: .hidden, to: .shown))
        XCTAssertEqual(duoContainer.calls, ["tab bar shown, accessory clear", "set"])
    }

    func testATabSwitchAndAPaneConversationRecompute() {
        var container = UIKitContainer(host(duo))
        container.recompute()
        // A switch to Messages with a conversation in its pane changes no tab
        // bar but clears the bar.
        container.state.placeHidesBar = true
        container.run(Order.tabBar(from: .shown, to: .shown))
        XCTAssertEqual(container.calls, ["set", "clear"])
        // The pane's conversation goes: the registry's change recomputes.
        container.state.placeHidesBar = false
        container.recompute()
        XCTAssertEqual(container.calls.last, "set")
        // A switch to a tab whose top screen is a game hides the tab bar, so the
        // bar clears first.
        container.run(Order.tabBar(from: .shown, to: .hidden))
        XCTAssertEqual(Array(container.calls.suffix(2)), ["clear", "tab bar hidden, accessory clear"])
    }

    func testTheSidebarsTogglesClearAsItStartsToShowAndSetAtTheHidesCompletion() {
        var container = UIKitContainer(host(iPad))
        container.recompute()
        container.state.facts.sidebar = .shown   // as it starts to show
        container.recompute()
        XCTAssertEqual(container.calls, ["set", "clear"])
        container.recompute()                    // a turn, or a tab picked in the sidebar
        XCTAssertEqual(container.calls, ["set", "clear"], "Nothing changes while it shows or slides away.")
        container.state.facts.sidebar = .hidden  // at the hide's completion
        container.recompute()
        XCTAssertEqual(container.calls, ["set", "clear", "set"])
    }

    func testTheIPadsEarlyClearIsOneWayUntilTheGamesRouteGoes() {
        var container = UIKitContainer(host(iPad))
        container.recompute()
        container.state.isGameAskedFor = true
        container.recompute()
        XCTAssertEqual(container.calls, ["set", "clear"], "Cleared before the game's first layout.")
        // Recomputes from the registry or update(...), inside the game's first
        // layout too, keep it cleared.
        container.recompute()
        container.recompute()
        container.run(Order.tabBar(from: .shown, to: .hidden))
        XCTAssertEqual(container.calls, ["set", "clear", "tab bar hidden, accessory clear"])
        // The game closes: its route goes, then the tab bar shows.
        container.state.isGameAskedFor = false
        container.recompute()
        container.run(Order.tabBar(from: .hidden, to: .shown))
        XCTAssertEqual(container.calls.suffix(2), ["tab bar shown, accessory clear", "set"])
    }

    func testTheEarlyClearsUndoWhenTheGamesRouteGoesBeforeTheTabBarHides() {
        var container = UIKitContainer(host(iPad))
        container.recompute()
        container.state.isGameAskedFor = true
        container.recompute()
        container.state.isGameAskedFor = false
        container.recompute()
        XCTAssertEqual(container.calls, ["set", "clear", "set"])
    }

    func testEachSizeTransitionClearsTheBarAndSetsItAgain() {
        var container = UIKitContainer(host(duo))
        container.recompute()
        container.run(Order.sizeTransitionCompleted)
        XCTAssertEqual(container.calls, ["set", "clear", "set"], "Set again for the new pose.")

        var held = UIKitContainer(host(duo))
        held.recompute()
        held.state.isDrawerShown = true
        held.run(Order.sizeTransitionCompleted)
        XCTAssertEqual(held.calls, ["set", "clear"], "The drawer record holds it cleared.")
        var hidden = UIKitContainer(host(duo))
        hidden.recompute()
        hidden.run(Order.tabBar(from: .shown, to: .hidden))
        hidden.run(Order.sizeTransitionCompleted)
        XCTAssertEqual(hidden.calls, ["set", "clear", "tab bar hidden, accessory clear"],
                       "The requested tab-bar state holds it cleared.")
    }

    func testNothingChangesBeforeTheFirstSetWhileTheDrawerShowsOrDuringItsReturn() {
        var container = UIKitContainer(host(duo))
        container.state.isInWindow = false
        container.recompute()
        container.run(Order.tabBar(from: .shown, to: .shown))
        XCTAssertEqual(container.calls, [], "Never set in makeController, before the view is in a window.")
        container.state.isInWindow = true
        container.recompute()
        XCTAssertEqual(container.calls, ["set"], "The first set, once the view is in a window.")

        // A main-queue turn after the drawer starts to show, its record turns shown.
        container.state.isDrawerShown = true
        container.recompute()
        // update(...), the registry and a tab picked in the drawer, while it
        // shows and for the 0.5 s after its close completes.
        container.state.placeHidesBar = true
        container.recompute()
        container.state.placeHidesBar = false
        container.recompute()
        container.run(Order.tabBar(from: .shown, to: .shown))
        XCTAssertEqual(container.calls, ["set", "clear"])
        container.state.isDrawerShown = false
        container.recompute()
        XCTAssertEqual(container.calls, ["set", "clear", "set"])
    }

    // MARK: What VoiceOver hears on root screens

    func testAStartedGameIsSaidOncePerClaim() {
        var leads = ActivityBarFirstLeads()
        var claimed = Set<Int>()
        let claim: (Int) -> Bool = { claimed.insert($0).inserted }
        XCTAssertEqual(leads.announcement(for: .gameStarted(gameID: 7), isRootOnScreen: true, claimStartedGame: claim),
                       .gameStarted(gameID: 7))
        XCTAssertNil(leads.announcement(for: .gameStarted(gameID: 7), isRootOnScreen: true, claimStartedGame: claim))
        claimed.insert(8)
        XCTAssertNil(leads.announcement(for: .gameStarted(gameID: 8), isRootOnScreen: true, claimStartedGame: claim),
                     "Game Detail's control or Game found said it.")
    }

    func testALiveChallengeIsSaidOnceThoughItLosesTheLeadAndRegainsIt() {
        var leads = ActivityBarFirstLeads()
        let unclaimed: (Int) -> Bool = { _ in true }
        XCTAssertEqual(leads.announcement(for: .challenge(liveChallenge(9)), isRootOnScreen: true,
                                          claimStartedGame: unclaimed), .challenge(challengeID: 9))
        XCTAssertNil(leads.announcement(for: .liveGame(gameID: 1), isRootOnScreen: true, claimStartedGame: unclaimed))
        XCTAssertNil(leads.announcement(for: .challenge(liveChallenge(9)), isRootOnScreen: true,
                                        claimStartedGame: unclaimed))
        XCTAssertEqual(leads.claimedChallengeIDs, [9])
        XCTAssertEqual(leads.announcement(for: .challenge(liveChallenge(10)), isRootOnScreen: true,
                                          claimStartedGame: unclaimed), .challenge(challengeID: 10))
    }

    func testALeadBehindAGameOrAConversationIsSaidWhenTheRootShowsAgain() {
        var leads = ActivityBarFirstLeads()
        var claimed = Set<Int>()
        let claim: (Int) -> Bool = { claimed.insert($0).inserted }
        XCTAssertNil(leads.announcement(for: .challenge(liveChallenge(9)), isRootOnScreen: false, claimStartedGame: claim))
        XCTAssertNil(leads.announcement(for: .gameStarted(gameID: 7), isRootOnScreen: false, claimStartedGame: claim))
        XCTAssertEqual(claimed, [], "Held, not claimed.")
        XCTAssertEqual(leads.claimedChallengeIDs, [])
        XCTAssertEqual(leads.announcement(for: .challenge(liveChallenge(9)), isRootOnScreen: true, claimStartedGame: claim),
                       .challenge(challengeID: 9))
    }

    func testALeadUnderASheetIsSaidAndUnderTheCoverHeld() {
        var leads = ActivityBarFirstLeads()
        let unclaimed: (Int) -> Bool = { _ in true }
        // A sheet leaves the registry's place a root's, so the root is on screen.
        XCTAssertEqual(leads.announcement(for: .gameStarted(gameID: 7), isRootOnScreen: true,
                                          claimStartedGame: unclaimed), .gameStarted(gameID: 7))
        XCTAssertNil(leads.announcement(for: .challenge(liveChallenge(9)), isRootOnScreen: true, isCovered: true,
                                        claimStartedGame: unclaimed))
        XCTAssertEqual(leads.announcement(for: .challenge(liveChallenge(9)), isRootOnScreen: true,
                                          claimStartedGame: unclaimed), .challenge(challengeID: 9))
    }

    func testNothingElseIsSaid() {
        var leads = ActivityBarFirstLeads()
        let unclaimed: (Int) -> Bool = { _ in true }
        for lead in [Lead.liveGame(gameID: 1), .waiting(search, withdrawsInPlace: true), .nothingLeads(count: 3),
                     .challenge(Model.Challenge(id: 8, isLive: false))] {
            XCTAssertNil(leads.announcement(for: lead, isRootOnScreen: true, claimStartedGame: unclaimed), "\(lead)")
        }
        XCTAssertNil(leads.announcement(for: nil, isRootOnScreen: true, claimStartedGame: unclaimed))
    }

    // MARK: What VoiceOver hears from the bar

    private let english = Locale(identifier: "en")
    private typealias Spoken = ActivityBarAccessibility

    func testTheBarIsAnActivityContainer() {
        XCTAssertEqual(Spoken.barLabel, "Activity")
    }

    func testAGamesLeadSaysTheGameWithItsTimeAsTheValue() {
        let live = Spoken.liveGame(opponent: "HarborMist", rank: "1d", isYourMove: true, timeLeft: 42, ticks: true,
                                   locale: english)
        XCTAssertEqual(live.label, "Live game with HarborMist, 1d. Your move")
        XCTAssertEqual(live.value, "42 seconds left")
        XCTAssertEqual(live.hint, "Opens that game.")
        XCTAssertTrue(live.updatesFrequently, "The time is the value, so the label holds still as it ticks.")

        let suddenDeath = Spoken.liveGame(opponent: "HarborMist", rank: "1d", isYourMove: true, isSuddenDeath: true,
                                          timeLeft: 8, ticks: true, locale: english)
        XCTAssertEqual(suddenDeath.label, "Live game with HarborMist, 1d. Your move, sudden death")
        XCTAssertEqual(suddenDeath.value, "8 seconds left")

        let theirs = Spoken.liveGame(opponent: "HarborMist", rank: "1d", isYourMove: false, timeLeft: 190, ticks: true,
                                     locale: english)
        XCTAssertEqual(theirs.label, "Live game with HarborMist, 1d. Their move")
        XCTAssertEqual(theirs.value, "", "Their move has no time.")
        XCTAssertFalse(theirs.updatesFrequently)

        let offline = Spoken.liveGame(opponent: "HarborMist", rank: "1d", isYourMove: true, timeLeft: 42, ticks: true,
                                      isOffline: true, locale: english)
        XCTAssertEqual(offline.value, "42 seconds left, Reconnecting to OGS")
        XCTAssertEqual(Spoken.liveGame(opponent: "HarborMist", rank: "1d", isYourMove: false, isOffline: true,
                                       locale: english).value, "Reconnecting to OGS")

        XCTAssertEqual(Spoken.liveGame(opponent: "HarborMist", rank: nil, isYourMove: true, locale: english).label,
                       "Live game with HarborMist. Your move", "No rank while ranks are hidden.")
        let stopped = Spoken.liveGame(opponent: "HarborMist", rank: "1d", isYourMove: true, timeLeft: 42, ticks: false,
                                      locale: english)
        XCTAssertEqual(stopped.value, "42 seconds left")
        XCTAssertFalse(stopped.updatesFrequently, "A clock that doesn't run doesn't tick.")
    }

    func testAStartedGameAChallengeAndYourOwnItems() {
        let started = Spoken.gameStarted(opponent: "CedarWave")
        XCTAssertEqual(started.label, "Game started with CedarWave")
        XCTAssertEqual(started.hint, "Opens that game.")

        let challenge = Spoken.challenge(challenger: "CedarWave", rank: "5k", details: ["19×19", "Ranked", "Live"])
        XCTAssertEqual(challenge.label, "Challenge from CedarWave, 5k: 19×19, Ranked, Live")
        XCTAssertEqual(challenge.hint, "Opens Activity.")

        let search = Spoken.waiting(.search, details: ["Quick match", "Live", "19×19"], waited: 72, ticks: true,
                                    locale: english)
        XCTAssertEqual(search.label, "Searching for a game: Quick match, Live, 19×19")
        XCTAssertEqual(search.value, "1 minute, 12 seconds", "The time searched is the value.")
        XCTAssertTrue(search.updatesFrequently)
        XCTAssertEqual(search.hint, "Opens Activity.")
        XCTAssertFalse(Spoken.waiting(.search, details: ["Quick match"], waited: 72, ticks: false,
                                      locale: english).updatesFrequently, "UI tests stop the time searched.")

        let open = Spoken.waiting(.openChallenge, details: ["Live", "19×19"], waited: 45, ticks: true, locale: english)
        XCTAssertEqual(open.label, "Open challenge: Live, 19×19")
        XCTAssertEqual(open.value, "45 seconds")
        let sent = Spoken.waiting(.sentChallenge(to: "QuietPine"), details: ["Live", "19×19"], locale: english)
        XCTAssertEqual(sent.label, "Challenge to QuietPine: Live, 19×19")
        XCTAssertEqual(sent.value, "")
        XCTAssertEqual(Spoken.waiting(.rengo("Weekend 19×19"), details: ["Live", "19×19", "3 players"],
                                      locale: english).label,
                       "Rengo · Weekend 19×19: Live, 19×19, 3 players")
    }

    func testNothingLeadsPlusNAndAllActivitySayWhatWaits() {
        let names: (Int) -> String? = { $0 == 5 ? "CedarWave" : nil }
        let waiting = ActivityBarBreakdown([.challenge(Model.Challenge(id: 5, isLive: false)), .conversation(peerID: 1),
                                            .conversation(peerID: 2)], challenger: names)
        let nothingLeads = Spoken.nothingLeads(count: 3, waiting, locale: english)
        XCTAssertEqual(nothingLeads.label,
                       "3 waiting for you: a correspondence challenge from CedarWave and 2 unread conversations")
        XCTAssertEqual(nothingLeads.hint, "Opens Activity.")

        let beyond = ActivityBarBreakdown([.challenge(liveChallenge(5)), .conversation(peerID: 1),
                                           .conversation(peerID: 2)], challenger: names)
        let plusN = Spoken.plusN(3, beyond, locale: english)
        XCTAssertEqual(plusN.label, "3 more waiting for you: a challenge from CedarWave and 2 unread conversations")
        XCTAssertEqual(plusN.hint, "Opens Activity.")

        let conversations = ActivityBarBreakdown([.conversation(peerID: 1), .conversation(peerID: 2)], challenger: names)
        let all = Spoken.allActivity(plusN: 2, conversations, locale: english)
        XCTAssertEqual(all.label, "All activity")
        XCTAssertEqual(all.value, "2 more waiting for you: 2 unread conversations")
        XCTAssertEqual(all.hint, "Opens Activity.")
        XCTAssertEqual(Spoken.allActivity(plusN: 0, ActivityBarBreakdown(), locale: english).value, "")
    }

    /// Counts of two or more: the catalog's singular forms are
    /// ActivityBarFitTests', which reads the app's own bundle.
    func testTheBreakdownsPhrasesCountEachKind() {
        let none: (Int) -> String? = { _ in nil }
        XCTAssertEqual(ActivityBarBreakdown([.liveGame(gameID: 1), .liveGame(gameID: 2)], challenger: none)
            .spoken(locale: english), "2 live games on your move")
        XCTAssertEqual(ActivityBarBreakdown([.challenge(liveChallenge(1)), .challenge(liveChallenge(2))], challenger: none)
            .spoken(locale: english), "2 challenges")
        XCTAssertEqual(ActivityBarBreakdown([.challenge(liveChallenge(1)), .challenge(liveChallenge(2))],
                                            challenger: { _ in "CedarWave" }).spoken(locale: english),
                       "2 challenges", "Only a single challenge names its challenger.")
        XCTAssertEqual(ActivityBarBreakdown([.conversation(peerID: 1), .conversation(peerID: 2)], challenger: none)
            .spoken(locale: english), "2 unread conversations")
        XCTAssertEqual(ActivityBarBreakdown([.liveGame(gameID: 1), .liveGame(gameID: 2), .challenge(liveChallenge(1)),
                                             .challenge(liveChallenge(2)), .conversation(peerID: 1),
                                             .conversation(peerID: 2)], challenger: none)
            .spoken(locale: english), "2 live games on your move, 2 challenges, and 2 unread conversations")
        XCTAssertEqual(ActivityBarBreakdown([.challenge(liveChallenge(1))], challenger: { _ in "CedarWave" })
            .spoken(locale: english), "a challenge from CedarWave")
        XCTAssertEqual(ActivityBarBreakdown([.challenge(Model.Challenge(id: 1, isLive: false))], challenger: { _ in "CedarWave" })
            .spoken(locale: english), "a correspondence challenge from CedarWave")

        XCTAssertEqual(ActivityBarBreakdown([.challenge(Model.Challenge(id: 5, isLive: false)),
                                             .challenge(Model.Challenge(id: 6, isLive: false)), .conversation(peerID: 1),
                                             .conversation(peerID: 2)], challenger: none).lineTwo,
                       "2 correspondence challenges · 2 conversations")
        XCTAssertEqual(ActivityBarBreakdown([.conversation(peerID: 1), .conversation(peerID: 2)], challenger: none).lineTwo,
                       "2 conversations", "Line two names what waits, and only that.")
        XCTAssertEqual(ActivityBarBreakdown([.challenge(liveChallenge(1))], challenger: none).lineTwo, "",
                       "A live challenge leads, so it never waits under N waiting.")
    }

    func testTheButtonsSayWhatTheyActOn() {
        XCTAssertEqual(Spoken.openGame(opponent: "CedarWave"), "Open the game with CedarWave")
        XCTAssertEqual(Spoken.view(challenger: "CedarWave"), "View the challenge from CedarWave")
        XCTAssertEqual(Spoken.withdraw(title: "Quick match", details: ["Live", "19×19"]), "Withdraw Quick match, Live, 19×19")
        XCTAssertEqual(Spoken.retry, "Retry connecting to OGS")
    }

    func testTheStatusKindsAndTheResultsSayTheirWords() {
        XCTAssertEqual(Spoken.status(.reconnecting).label, "Reconnecting to OGS")
        XCTAssertEqual(Spoken.status(.connecting).label, "Connecting…")
        XCTAssertEqual(Spoken.status(.unreachable).label, "Can’t reach OGS")
        XCTAssertEqual(Spoken.status(.connected).label, "Connected")
        for words in [Words.reconnecting, .connecting, .unreachable, .connected] {
            XCTAssertEqual(Spoken.status(words).hint, "", "\(words) is status, not a button.")
        }
        let display = ActivityRowDisplay(title: "Quick match", detail: "Live · 19×19")
        func result(_ state: ActivityActionState) -> Spoken {
            Spoken.result(ActivityBarResult(itemID: "waiting-quick-match-1", action: .withdraw, state: state,
                                            display: display))
        }
        XCTAssertEqual(result(.pending(since: 0)), Spoken(label: "Withdrawing…", value: "Quick match"))
        XCTAssertEqual(result(.succeeded(.withdrawn)), Spoken(label: "Withdrawn", value: "Quick match"))
        XCTAssertEqual(result(.failed), Spoken(label: "Couldn’t withdraw", value: "Quick match"))
    }

    func testTheNowSectionsWords() {
        XCTAssertEqual(Spoken.nowHeader, "Now")
        XCTAssertEqual(Spoken.allActivityTitle, "All activity")
    }

    func testTheBarsIdentifiersAreTheSameOnEveryHost() {
        typealias ID = SurroundUITestContract.AccessibilityID
        XCTAssertEqual([ID.activityBar, ID.activityBarLead, ID.activityBarAction, ID.activityBarMore],
                       ["activity.bar", "activity.bar.lead", "activity.bar.action", "activity.bar.more"])
        XCTAssertEqual([ID.activityNow, ID.activityNowRow("game-1"), ID.activityNowRowAction("game-1"), ID.activityNowAll],
                       ["activity.now", "activity.now.row.game-1", "activity.now.row.game-1.action", "activity.now.all"])
        XCTAssertEqual([ID.rootConnectionStatus, ID.rootConnectionStatusRetry],
                       ["root.connectionStatus", "root.connectionStatus.retry"])
        XCTAssertEqual(ID.activityBarState, "activity.bar.state")
        XCTAssertEqual(GameControlItemRole.conversation.accessibilityIdentifier, ID.messagesConversationGameControl)
    }

    func testTheDebugStateNamesTheKindTheLeadTheHostAndTheForm() {
        XCTAssertEqual(ActivityBarAppliedState.text(.lead(.liveGame(gameID: 26268404), counted: [], status: nil),
                                                    host: .uiKitAccessory, form: .expanded),
                       "live game-26268404 uiKitAccessory expanded")
        XCTAssertEqual(ActivityBarAppliedState.text(.lead(.waiting(search, withdrawsInPlace: true), counted: [],
                                                          status: .reconnecting), host: .customBar, form: .compactHeight),
                       "search waiting-\(search.id) customBar compactHeight")
        XCTAssertEqual(ActivityBarAppliedState.text(.lead(.nothingLeads(count: 3), counted: [], status: nil),
                                                    host: .swiftUIAccessory, form: .expanded),
                       "nothingLeads none swiftUIAccessory expanded")
        XCTAssertEqual(ActivityBarAppliedState.text(.unreachable(counted: []), host: .uiKitAccessory, form: .closed),
                       "unreachable none uiKitAccessory closed")
        XCTAssertEqual(ActivityBarAppliedState.text(.status(.reconnecting), host: .customBar, form: .expanded),
                       "reconnecting none customBar expanded")
        XCTAssertEqual(ActivityBarAppliedState.text(nil, host: .uiKitAccessory, form: .expanded), "none")
        XCTAssertEqual(ActivityBarAppliedState.text(.status(.connected), host: nil, form: .expanded), "none",
                       "A host that applied nothing says so, whatever MainView asked for.")
    }
}
