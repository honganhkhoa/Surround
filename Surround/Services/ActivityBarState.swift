//
//  ActivityBarState.swift
//  Surround
//
//  One window's Activity bar state: what its bar, its Now section and the
//  line under its root titles show for the selected tab's place, as values
//  no tick of a clock changes. It reads the window's input
//  (`ActivityModel.Input.window(ogs:nav:place:now:)`), the chrome's results
//  and the window's connection source a main-queue turn after any of them
//  changes, and at its own deadlines, never from a view or a layout pass. So
//  every host decides from the same values, and redraws only when what it
//  shows changes. One per window, held by NavigationService; MainView
//  attaches it. Main thread by convention, like its owner; it is not
//  actor-isolated, because NavigationService makes it in a property
//  initializer.
//

import Combine
import Foundation

/// The Now section's rows, as the window's bar state publishes them: no
/// live game's ticking fields, so a clock's tick never changes it.
struct ActivityBarNowSection: Equatable {
    /// The window's status in the first row: during an outage, on every
    /// place but a game, which says its status itself.
    var statusRow: NowStatusRow?
    /// The rows in the lead order, the first what the bar leads with; or the
    /// one "N waiting" row when nothing that can lead waits. One less beside
    /// the status row.
    var rows: [ActivityBarLead] = []
    /// All activity's +N: what counts and no row shows.
    var plusN = 0
    /// What +N counts, or what the "N waiting" row counts.
    var counted: [ActivityBarCountedItem] = []
    /// Something waits, listed or not: All activity shows. Without it the
    /// section is the status row alone, as signed out, or nothing.
    var hasActivity = false

    init(statusRow: NowStatusRow? = nil, rows: [ActivityBarLead] = [], plusN: Int = 0,
         counted: [ActivityBarCountedItem] = [], hasActivity: Bool = false) {
        self.statusRow = statusRow
        self.rows = rows
        self.plusN = plusN
        self.counted = counted
        self.hasActivity = hasActivity
    }

    /// The section for the window's input (`ActivityModel.nowSection(_:rows:)`),
    /// beside `statusRow`.
    /// - Parameters:
    ///   - room: How many rows the section has room for, the status row's
    ///     included: two, one in a short window, or none in a shorter one,
    ///     which lists nothing, the status row included
    ///     (`ActivityNowSectionRows`).
    ///   - searchWithdrawsInPlace: Whether a Quick Match search's row
    ///     withdraws in place (`ActivityBarLead`).
    init(_ input: ActivityModel.Input, statusRow: NowStatusRow?, room: Int = ActivityModel.nowSectionRows,
         searchWithdrawsInPlace: (ActivityModel.Waiting) -> Bool = { _ in false }) {
        guard room > 0 else {
            self = ActivityBarNowSection()
            return
        }
        let activityRows = NowStatusRow.activityRows(beside: statusRow, of: room)
        let section = ActivityModel.nowSection(input, rows: activityRows)
        self.statusRow = statusRow
        rows = section.rows.compactMap { ActivityBarLead($0, searchWithdrawsInPlace: searchWithdrawsInPlace) }
        plusN = section.plusN
        counted = section.counted.compactMap(ActivityBarCountedItem.init)
        // With a row of room, the model lists one whenever something waits,
        // though the status row takes that room.
        hasActivity = !rows.isEmpty || plusN > 0
            || (activityRows < room && !ActivityModel.nowSection(input, rows: room).rows.isEmpty)
    }
}

/// The window's connection, as the window's bar state publishes it: what
/// every carrier says, from the window's status, whether it has connected
/// and whether its socket recovers a connection
/// (`RootConnectionLine.words(status:hasConnected:socket:)`). A change the
/// carriers draw alike, such as why OGS can't be reached, publishes nothing.
struct ActivityBarConnection: Equatable {
    /// Nil while there is nothing to say.
    var words: RootConnectionLine.Words?
    /// The window's socket has been open at least once.
    var hasConnected = false

    init(words: RootConnectionLine.Words? = nil, hasConnected: Bool = false) {
        self.words = words
        self.hasConnected = hasConnected
    }

    init(status: ConnectionStatusModel.Status, hasConnected: Bool, socket: OGSWebsocketStatus) {
        self.init(words: RootConnectionLine.words(status: status, hasConnected: hasConnected, socket: socket),
                  hasConnected: hasConnected)
    }
}

final class ActivityBarState: ObservableObject {
    /// The bar's Activity part: the latest result of the chrome's session, or
    /// the selected tab's lead with what +N counted. No lead off a root.
    @Published private(set) var activity = ActivityBarActivity()
    /// The Now section's rows and +N, for every place, a game included.
    @Published private(set) var nowSection = ActivityBarNowSection()
    /// What the window's connection says.
    @Published private(set) var connection = ActivityBarConnection()

    /// Whether the state says a lead as it first leads on a root screen,
    /// through the sink `attach` was given. MainView turns it on for its
    /// window. While off it claims nothing either, so the in-game control
    /// still says a started game.
    var postsFirstLeads = false

    /// Whether the Now section's first row says the window's status during
    /// an outage, taking one of its rows. MainView turns it off where the
    /// window's bar carries no status (`ActivityBarHosting`), so the section
    /// lists Activity alone, with all its rows. Published as it changes, as
    /// is the room below: a conversation beside the section reads both to
    /// know whether the section says its status.
    @Published var nowSectionSaysStatus = true {
        didSet { if nowSectionSaysStatus != oldValue { scheduleRecompute() } }
    }

    /// How many rows the Now section has room for: two, one in a short iPad
    /// window, or none in a shorter one (`ActivityNowSectionRows`), which
    /// the iPad's container sets as its window appears and after each resize
    /// or turn. The section's own rows follow a turn later.
    @Published private(set) var nowSectionRows = ActivityModel.nowSectionRows

    func setNowSectionRows(_ rows: Int) {
        guard rows != nowSectionRows else { return }
        nowSectionRows = rows
        scheduleRecompute()
    }

    private let scheduler: OGSWebsocketScheduling
    private let now: () -> TimeInterval
    private weak var ogs: OGSService?
    private weak var nav: NavigationService?
    private weak var connectionSource: ConnectionStatusSource?
    private var announce: ((ActivityBarAnnouncement) -> Void)?
    private var subscriptions = Set<AnyCancellable>()
    private var recomputeIsScheduled = false
    private var deadline: Cancellable?
    private var firstLeads = ActivityBarFirstLeads()

    /// - Parameters:
    ///   - scheduler: Runs the turn after a change, and the state's deadlines.
    ///   - now: Seconds since 1970, the window's input's time base.
    init(scheduler: OGSWebsocketScheduling = OGSMainQueueWebsocketScheduler.shared,
         now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.scheduler = scheduler
        self.now = now
    }

    deinit {
        deadline?.cancel()
    }

    /// Follows the window's service, its stores, its registry, its selected
    /// tab and its connection source, and computes the first value at once,
    /// so the hosts' first pass already has it. Attaching again follows the
    /// new ones instead.
    /// - Parameters:
    ///   - source: The window's connection source; nil where no root hosts
    ///     one, and then nothing is said.
    ///   - announce: Says a lead that first leads on a root screen, while
    ///     `postsFirstLeads` is on.
    func attach(ogs: OGSService, nav: NavigationService, connection source: ConnectionStatusSource?,
                announce: ((ActivityBarAnnouncement) -> Void)? = nil) {
        self.ogs = ogs
        self.nav = nav
        connectionSource = source
        self.announce = announce
        subscriptions = []
        // Each of these sends before its change is stored, or right after;
        // the turn later reads every store as it is then.
        var changes: [AnyPublisher<Void, Never>] = [
            ogs.objectWillChange.eraseToAnyPublisher(),
            nav.activityResults.objectWillChange.eraseToAnyPublisher(),
            nav.activityLastKnown.objectWillChange.eraseToAnyPublisher(),
            nav.activityPlaces.stateDidChange.map { _ in }.eraseToAnyPublisher(),
            nav.$main.map(\.rootView).removeDuplicates().dropFirst().map { _ in }.eraseToAnyPublisher(),
            // The window's started games change as it opens one, and the
            // recorder publishes nothing.
            StartedGamesRecorder.openedGameIDs(in: nav).dropFirst().map { _ in }.eraseToAnyPublisher(),
        ]
        if let source {
            changes.append(source.objectWillChange.eraseToAnyPublisher())
        }
        Publishers.MergeMany(changes)
            .sink { [weak self] in self?.scheduleRecompute() }
            .store(in: &subscriptions)
        recompute()
    }

    // MARK: Recomputing

    private func scheduleRecompute() {
        guard !recomputeIsScheduled else { return }
        recomputeIsScheduled = true
        scheduler.async { [weak self] in self?.recompute() }
    }

    private func recompute() {
        recomputeIsScheduled = false
        guard let ogs, let nav else { return }
        let place = nav.activityPlaces.place(in: nav.main.rootView)
        let input = ActivityModel.Input.window(ogs: ogs, nav: nav, place: place, now: now())
        let results = nav.activityResults
        // As the list does: once the service no longer lists a hidden item,
        // it needs no hiding.
        for id in results.hiddenIDs.subtracting(input.hiddenListedIDs).sorted() {
            results.forget(hidden: id)
        }
        let withdrawsInPlace = Self.searchWithdrawsInPlace(ogs)
        let nextConnection = connectionSource.map {
            ActivityBarConnection(status: $0.status, hasConnected: $0.hasConnected, socket: ogs.socketStatus)
        } ?? ActivityBarConnection()
        let nextActivity = ActivityBarActivity(ActivityModel.snapshot(input), result: results.chromeResults.last,
                                               searchWithdrawsInPlace: withdrawsInPlace)
        let statusRow = nowSectionSaysStatus ? NowStatusRow(nextConnection.words, place: place) : nil
        let nextNowSection = ActivityBarNowSection(input, statusRow: statusRow, room: nowSectionRows,
                                                   searchWithdrawsInPlace: withdrawsInPlace)
        if connection != nextConnection {
            connection = nextConnection
        }
        if activity != nextActivity {
            activity = nextActivity
        }
        if nowSection != nextNowSection {
            nowSection = nextNowSection
        }
        sayFirstLead(on: place, ogs: ogs, nav: nav)
        scheduleDeadline(input)
    }

    /// A Quick Match search's row withdraws in place when its search is one
    /// size at one speed, from the service's own entry.
    private static func searchWithdrawsInPlace(_ ogs: OGSService) -> (ActivityModel.Waiting) -> Bool {
        { waiting in
            guard case .quickMatch(let uuid)? = ActivityWaitingRef.parse(waiting.id),
                  let entry = ogs.autoMatchEntryById[uuid] else { return false }
            return ActivityQuickMatchRow.withdrawsInPlace(entry)
        }
    }

    // MARK: First leads

    /// What the app posts for `announcement` in this window, with the name
    /// its service holds: the started game's opponent, or the challenger.
    /// Nil once the service no longer lists it.
    static func appAnnouncement(_ announcement: ActivityBarAnnouncement, in ogs: OGSService) -> AppAnnouncement? {
        let name: String? = switch announcement {
        case .gameStarted(let gameID):
            ogs.liveGames.first { $0.ogsID == gameID }.flatMap { game in
                game.userStoneColor.flatMap { game.currentPlayer(with: $0.opponentColor())?.username }
            }
        case .challenge(let challengeID):
            ogs.challengesReceived.first { $0.id == challengeID }?.challenger?.username
        }
        return name.map { announcement.appAnnouncement(name: $0) }
    }

    /// "Game started with …" or "Challenge from …" as the root's lead first
    /// leads, claimed so each is said once. A game or a conversation on top,
    /// or the superchat cover, holds it until the root shows again; a sheet
    /// doesn't.
    private func sayFirstLead(on place: ActivityModel.Place, ogs: OGSService, nav: NavigationService) {
        guard postsFirstLeads, let announce else { return }
        let recorder = nav.startedGamesRecorder
        if let announcement = firstLeads.announcement(
            for: activity.lead, isRootOnScreen: !place.hidesBar, isCovered: ogs.superchatCover != nil,
            claimStartedGame: { recorder.claimAnnouncement(for: $0) }
        ) {
            announce(announcement)
        }
    }

    // MARK: Deadlines

    /// Wakes the state when time alone could change what it publishes.
    private func scheduleDeadline(_ input: ActivityModel.Input) {
        deadline?.cancel()
        deadline = nil
        guard !Self.clockStandsStill, let delay = Self.nextDeadline(input, startedLeads: startedLeads) else { return }
        deadline = scheduler.schedule(after: max(0, delay)) { [weak self] in
            self?.recompute()
        }
    }

    /// A game that started elsewhere leads the bar or a Now row.
    private var startedLeads: Bool {
        ([activity.lead].compactMap { $0 } + nowSection.rows).contains {
            if case .gameStarted = $0 { return true }
            return false
        }
    }

    /// How long until time alone could change what the state publishes, in
    /// seconds; nil when nothing could.
    /// - Each second while two or more live games on your move, other than
    ///   the game on screen, can change order as their clocks run.
    /// - Each second while a game that started elsewhere leads and a live
    ///   game on your move has a running clock, whose low time would end the
    ///   started game's lead.
    /// - Otherwise at the end of the first started game's 30 s, since the
    ///   window's recorder publishes nothing.
    static func nextDeadline(_ input: ActivityModel.Input, startedLeads: Bool) -> TimeInterval? {
        let onScreen = input.place.gameID
        let othersOnYourMove = input.liveGames.filter { $0.id != onScreen && $0.isYourMove }
        if othersOnYourMove.count >= 2
            || (startedLeads && input.liveGames.contains { $0.isYourMove && $0.isClockRunning }) {
            return 1
        }
        let ends = input.startedGames.values
            .map { $0 + ActivityModel.startedLeadDuration }
            .filter { $0 > input.now }
        return ends.min().map { $0 - input.now }
    }

    /// A Debug Activity state's clock may stand still, and then no deadline
    /// ever comes.
    private static var clockStandsStill: Bool {
        #if DEBUG && MAIN_APP
        return ActivityFixtures.selected?.clock.isFrozen ?? false
        #else
        return false
        #endif
    }
}
