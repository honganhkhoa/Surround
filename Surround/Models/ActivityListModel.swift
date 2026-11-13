//
//  ActivityListModel.swift
//  Surround
//
//  The rules behind Activity's list that need no view: how a request to show
//  the list is shaped and presented, how the model's items split into
//  sections and take back the rows the user resolved, which of a row's
//  controls work, and how an action on a challenge or a search moves from
//  pending to its result. Pure value types, so every rule is tested without a
//  socket or a view. CoreGraphics is here only for the anchor's CGRect.
//

import CoreGraphics
import Foundation

// MARK: - Presenting the list

/// How a window shows its Activity list.
enum ActivityPresentationStyle: Equatable {
    case sheet
    /// Anchored where its opener was.
    case popover

    /// The window's horizontal size class, without SwiftUI.
    enum SizeClass: Equatable {
        case compact
        case regular
    }

    /// In a game the list is always a popover, so the game stays in view.
    /// Elsewhere a compact width gets the sheet, and so does a window whose
    /// division would split a popover, such as a Duo's hinge; a regular width
    /// gets a popover.
    static func style(
        horizontalSizeClass: SizeClass,
        place: ActivityModel.Place,
        crossesDivision: Bool
    ) -> ActivityPresentationStyle {
        if place.gameID != nil {
            return .popover
        }
        if horizontalSizeClass == .compact || crossesDivision {
            return .sheet
        }
        return .popover
    }
}

/// One request to show a window's Activity list. Its style is decided when
/// the request is made and kept until the list closes.
struct ActivityRequest: Identifiable, Equatable {
    /// What opened the list.
    enum Source: Equatable {
        case homeSearching
        case waitingPill
        case challengePill
        case livePill
        case messagesButton
        case debug
    }

    /// Where the list starts.
    enum Focus: Equatable {
        case top
        /// Scrolled to Messages, as the Messages button opens it. With
        /// exactly one unread conversation, that one opens at once.
        case messages

        /// The peer whose conversation the list opens at once: with
        /// Messages in focus and exactly one unread conversation listed.
        func conversationToOpen(in list: [ActivityModel.Item]) -> Int? {
            guard self == .messages else { return nil }
            let unread = list.compactMap { item -> Int? in
                guard case .conversation(let conversation) = item, conversation.isUnread else { return nil }
                return conversation.peerID
            }
            return unread.count == 1 ? unread[0] : nil
        }
    }

    /// The list's session, which its rows' results belong to (ActivityResults).
    var sessionID: UUID
    var source: Source
    var focus: Focus
    var style: ActivityPresentationStyle
    /// The opener's frame in the window's global coordinates, captured when
    /// it was tapped, so a popover never depends on its opener staying.
    var anchor: CGRect
    /// Where the window was when the list opened. Over a game the list is a
    /// game's popover, with denser rows and View instead of inline Accept.
    var place: ActivityModel.Place

    var id: UUID { sessionID }

    init(
        sessionID: UUID = UUID(),
        source: Source,
        focus: Focus = .top,
        style: ActivityPresentationStyle,
        anchor: CGRect = .zero,
        place: ActivityModel.Place = .root(isMessagesTab: false)
    ) {
        self.sessionID = sessionID
        self.source = source
        self.focus = focus
        self.style = style
        self.anchor = anchor
        self.place = place
    }
}

// MARK: - Sections and rows

/// The list's sections, in the order they show.
enum ActivitySection: CaseIterable, Hashable {
    case liveGames
    case challengesReceived
    /// The user's own searches and challenges: "Waiting for opponents".
    case waiting
    /// The one row for the correspondence games on the user's move.
    case correspondence
    case messages

    static func section(of item: ActivityModel.Item) -> ActivitySection {
        switch item {
        case .liveGame: .liveGames
        case .challenge: .challengesReceived
        case .waiting: .waiting
        case .correspondenceGames: .correspondence
        case .conversation: .messages
        }
    }
}

/// A row's text and art as they were when an action started, so a row whose
/// object has gone can still show what it was.
struct ActivityRowDisplay: Equatable {
    var title: String
    var detail: String
    var avatarURL: URL?
    /// The initial tile's letter, for a player without an avatar.
    var initial: String?
    /// The SF Symbol in a waiting row's glyph circle.
    var kindSymbol: String?

    init(
        title: String,
        detail: String,
        avatarURL: URL? = nil,
        initial: String? = nil,
        kindSymbol: String? = nil
    ) {
        self.title = title
        self.detail = detail
        self.avatarURL = avatarURL
        self.initial = initial
        self.kindSymbol = kindSymbol
    }
}

/// A row the user acted on, which stays in the list until it closes even
/// after its item has gone.
struct ActivityResolvedRow: Equatable, Identifiable {
    /// The item's `ActivityModel.Item.id`.
    var id: String
    var section: ActivitySection
    /// The id before it in its section when the action started.
    var after: String?
    var display: ActivityRowDisplay
}

enum ActivityListSections {
    enum Row: Equatable, Identifiable {
        case item(ActivityModel.Item)
        /// An item that left the model's list after the user acted on it.
        case resolved(ActivityResolvedRow)

        var id: String {
            switch self {
            case .item(let item): item.id
            case .resolved(let row): row.id
            }
        }
    }

    struct Section: Equatable, Identifiable {
        var kind: ActivitySection
        var rows: [Row]

        var id: ActivitySection { kind }
    }

    /// Splits the model's list into sections, keeping its order, and puts
    /// back the resolved rows whose items have gone.
    /// - An item still in `list` keeps its own row, which shows its result.
    /// - A resolved row whose item has gone follows the id that preceded it
    ///   in its section, or comes first in its section when that id is no
    ///   longer there.
    /// - No id shows twice.
    /// - Empty sections are left out, and Messages shows only with a
    ///   conversation.
    static func sections(list: [ActivityModel.Item], resolved: [ActivityResolvedRow]) -> [Section] {
        var seen = Set<String>()
        let items = list.filter { seen.insert($0.id).inserted }
        // A listed item takes over its id; a repeated resolved id counts once.
        let gone = resolved.filter { seen.insert($0.id).inserted }
        return ActivitySection.allCases.compactMap { kind -> Section? in
            let sectionItems = items.filter { ActivitySection.section(of: $0) == kind }
            if kind == .messages, sectionItems.isEmpty {
                return nil
            }
            let rows = merged(sectionItems, gone.filter { $0.section == kind })
            return rows.isEmpty ? nil : Section(kind: kind, rows: rows)
        }
    }

    /// One section's items in order, each followed by the gone rows that came
    /// after it, by `ResolvedRowOrder`.
    private static func merged(_ items: [ActivityModel.Item], _ gone: [ActivityResolvedRow]) -> [Row] {
        let itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let goneByID = Dictionary(gone.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let order = ResolvedRowOrder.merge(
            live: items.map(\.id), resolved: gone.map { (id: $0.id, after: $0.after) })
        return order.compactMap { id in itemsByID[id].map(Row.item) ?? goneByID[id].map(Row.resolved) }
    }

    /// Where a row sits: its section and the id before it there, nil when it
    /// leads its section. Nil when no section lists it.
    static func position(of id: String, in sections: [Section]) -> (section: ActivitySection, after: String?)? {
        for section in sections {
            guard let index = section.rows.firstIndex(where: { $0.id == id }) else { continue }
            return (section.kind, index > 0 ? section.rows[index - 1].id : nil)
        }
        return nil
    }
}

/// Where rows that act in place go once their live row has gone: after the
/// id that preceded them when the user acted, or first when that id has gone
/// too. Activity's sections and Messages' friend requests both use it.
enum ResolvedRowOrder {
    /// The live ids in order, each followed by the resolved ids that came
    /// after it. Resolved ids with nothing to follow lead, in the order
    /// given; so do ids whose predecessors point back at them. No id shows
    /// twice: a live id keeps its own place.
    static func merge<ID: Hashable>(live: [ID], resolved: [(id: ID, after: ID?)]) -> [ID] {
        var seen = Set<ID>()
        let liveIDs = live.filter { seen.insert($0).inserted }
        let gone = resolved.filter { seen.insert($0.id).inserted }
        let afterByID = Dictionary(gone.map { ($0.id, $0.after) }, uniquingKeysWith: { first, _ in first })
        let anchors = Set(liveIDs).union(afterByID.keys)
        var followers = [ID: [ID]]()
        var leading = [ID]()
        for row in gone {
            if let after = row.after, anchors.contains(after), !leadsBackToItself(row.id, in: afterByID) {
                followers[after, default: []].append(row.id)
            } else {
                leading.append(row.id)
            }
        }

        var order = [ID]()
        var placed = Set<ID>()
        func place(_ id: ID) {
            guard placed.insert(id).inserted else { return }
            order.append(id)
            for follower in followers[id] ?? [] {
                place(follower)
            }
        }
        leading.forEach(place)
        liveIDs.forEach(place)
        return order
    }

    /// Following `after` through the resolved ids comes back to `id`.
    private static func leadsBackToItself<ID: Hashable>(_ id: ID, in afterByID: [ID: ID?]) -> Bool {
        var visited = Set<ID>()
        var next = afterByID[id] ?? nil
        while let current = next, let predecessorAfter = afterByID[current] {
            if current == id {
                return true
            }
            guard visited.insert(current).inserted else { return false }
            next = predecessorAfter
        }
        return false
    }
}

/// What a waiting item's id stands for: the reverse of
/// `ActivityModel.WaitingID`.
enum ActivityWaitingRef: Equatable {
    /// A Quick Match search, by its uuid.
    case quickMatch(String)
    case openChallenge(Int)
    case sentChallenge(Int)
    case rengo(Int)

    /// Nil for anything `ActivityModel.WaitingID` doesn't make.
    static func parse(_ id: String) -> ActivityWaitingRef? {
        if let uuid = remainder(of: id, after: "quick-match-"), !uuid.isEmpty {
            return .quickMatch(uuid)
        }
        if let number = number(in: id, after: "open-") {
            return .openChallenge(number)
        }
        if let number = number(in: id, after: "sent-") {
            return .sentChallenge(number)
        }
        if let number = number(in: id, after: "rengo-") {
            return .rengo(number)
        }
        return nil
    }

    private static func remainder(of id: String, after prefix: String) -> String? {
        id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : nil
    }

    /// Only the digits `"\(id)"` writes, so "open-05" and "open-+5" are not
    /// challenge 5.
    fileprivate static func number(in id: String, after prefix: String) -> Int? {
        guard let text = remainder(of: id, after: prefix), let number = Int(text),
              String(number) == text else {
            return nil
        }
        return number
    }
}

/// What an `ActivityModel.Item.id` names, for a card pushed from the list:
/// a challenge someone sent the user, or one of the user's own waiting items.
enum ActivityItemRef: Equatable {
    case challenge(Int)
    case waiting(ActivityWaitingRef)

    /// Nil for the other items, which push no card, and for anything the
    /// model doesn't make.
    static func parse(_ itemID: String) -> ActivityItemRef? {
        if let id = ActivityWaitingRef.number(in: itemID, after: "challenge-") {
            return .challenge(id)
        }
        let waitingPrefix = "waiting-"
        guard itemID.hasPrefix(waitingPrefix),
              let ref = ActivityWaitingRef.parse(String(itemID.dropFirst(waitingPrefix.count))) else {
            return nil
        }
        return .waiting(ref)
    }
}

/// How long a search or open challenge has waited, as the list shows it:
/// m:ss under an hour, then hours and minutes, then days and hours, each in
/// the locale's abbreviated units, so a long wait stays on one line.
enum ActivityElapsed {
    static func text(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        let whole = max(0, seconds).rounded(.down)
        guard whole >= 3_600 else {
            return Duration.seconds(Int64(whole)).formatted(.time(pattern: .minuteSecond).locale(locale))
        }
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = whole < 86_400 ? [.hour, .minute] : [.day, .hour]
        formatter.maximumUnitCount = 2
        return formatter.string(from: whole) ?? ""
    }
}

/// A Quick Match row withdraws in place only when its search is one size at
/// one speed. A search across several opens its card instead, which shows
/// each one.
enum ActivityQuickMatchRow {
    static func withdrawsInPlace(_ entry: OGSAutomatchEntry) -> Bool {
        Set(entry.sizeSpeedOptions.map(\.size)).count <= 1
            && Set(entry.sizeSpeedOptions.map(\.speed)).count <= 1
    }
}

// MARK: - Actions and their results

/// What the user did to a row.
enum ActivityAction: String, Equatable {
    case accept
    case reject
    case withdraw
    case leave
    case start

    /// What a row shows, and VoiceOver says, when the action failed.
    var failureText: String {
        switch self {
        case .accept:
            String(localized: "Couldn’t accept", comment: "Activity: accepting a challenge failed; shown with Retry")
        case .reject:
            String(localized: "Couldn’t reject", comment: "Activity: rejecting a challenge failed; shown with Retry")
        case .withdraw:
            String(
                localized: "Couldn’t withdraw",
                comment: "Activity: withdrawing your own challenge or Quick Match search failed; shown with Retry"
            )
        case .leave:
            String(
                localized: "Couldn’t leave",
                comment: "Activity: leaving a Rengo challenge you joined failed; shown with Retry"
            )
        case .start:
            String(
                localized: "Couldn’t start",
                comment: "Activity: starting a Rengo game you host failed; shown with Retry"
            )
        }
    }

    /// What VoiceOver says of the spinner that replaces the action's button
    /// while it is sent.
    var pendingText: String {
        switch self {
        case .accept:
            String(localized: "Accepting…", comment: "Activity: VoiceOver, a challenge's Accept is being sent")
        case .reject:
            String(localized: "Rejecting…", comment: "Activity: VoiceOver, a challenge's Reject is being sent")
        case .withdraw:
            String(
                localized: "Withdrawing…",
                comment: "Activity: VoiceOver, withdrawing your own challenge or Quick Match search is being sent"
            )
        case .leave:
            String(localized: "Leaving…", comment: "Activity: VoiceOver, leaving a Rengo challenge you joined is being sent")
        case .start:
            String(localized: "Starting…", comment: "Activity: VoiceOver, starting a Rengo game you host is being sent")
        }
    }
}

/// What a finished action left.
enum ActivityOutcome: Equatable {
    /// An accepted challenge or a started Rengo game.
    case gameStarted(gameID: Int)
    case rejected
    case withdrawn
    case left

    /// What a row shows, and VoiceOver says, in place of its actions.
    var text: String {
        switch self {
        case .gameStarted:
            String(localized: "Game started")
        case .rejected:
            String(localized: "Rejected", comment: "Activity: you rejected a challenge sent to you")
        case .withdrawn:
            String(localized: "Withdrawn", comment: "Activity: you withdrew your own challenge or Quick Match search")
        case .left:
            String(localized: "Left", comment: "Activity: you left a Rengo challenge you had joined")
        }
    }
}

enum ActivityActionState: Equatable {
    /// Sent at `since`, in seconds on the results store's clock.
    case pending(since: TimeInterval)
    case succeeded(ActivityOutcome)
    case failed

    var isPending: Bool {
        if case .pending = self {
            return true
        }
        return false
    }
}

/// Which of a row's controls work, and what VoiceOver says of them.
struct ActivityRowActionState: Equatable {
    enum Control: CaseIterable {
        case accept, reject, withdraw, retry, view, openGame
    }

    /// Inline Reject and Accept show only for a usual challenge outside a
    /// game's popover. Otherwise the row shows its warning and View, and the
    /// full challenge card decides.
    let showsInlineAcceptAndReject: Bool
    private let isOffline: Bool
    private let isPending: Bool

    /// - Parameter state: The row's latest action, if any.
    init(isUnusual: Bool, isInGamePopover: Bool, isOffline: Bool, state: ActivityActionState?) {
        showsInlineAcceptAndReject = !isUnusual && !isInGamePopover
        self.isOffline = isOffline
        isPending = state?.isPending ?? false
    }

    /// View and Open game always work, offline too. The row's actions need
    /// the connection, and wait while one of them is pending.
    func isEnabled(_ control: Control) -> Bool {
        guard Self.needsConnection(control) else { return true }
        return !isOffline && !isPending
    }

    /// "Reconnecting…" on a control that is off for being offline.
    func accessibilityValue(_ control: Control) -> String? {
        guard isOffline, Self.needsConnection(control) else { return nil }
        return String(localized: "Reconnecting…")
    }

    private static func needsConnection(_ control: Control) -> Bool {
        switch control {
        case .accept, .reject, .withdraw, .retry: true
        case .view, .openGame: false
        }
    }
}

// MARK: - VoiceOver focus on results

/// Where VoiceOver is among the places of rows that act in place, as a
/// view's `@AccessibilityFocusState` reads it: Activity's rows and pushed
/// cards, and Messages' friend request rows. A result that arrives while
/// VoiceOver is on one of its row's controls, or on the spinner standing in
/// for one, takes focus there and isn't announced as well; anywhere else,
/// the window announces it.
enum ResultFocus<Row: Hashable, Control: Hashable>: Hashable {
    /// A control that acts on the row.
    case control(Row, Control)
    /// The spinner that stands in for a control while its request is sent.
    case pending(Row)
    /// The row's result, or its failure.
    case result(Row)

    /// Where VoiceOver goes as `control` sends its request: to the spinner
    /// standing in for it, when VoiceOver was on that control. Nil leaves
    /// focus where it is.
    static func sending(_ control: Control, of row: Row, from focus: Self?) -> Self? {
        focus == .control(row, control) ? .pending(row) : nil
    }

    /// Whether `row`'s result, arriving now, takes VoiceOver focus: focus is
    /// on one of the row's controls, or on its spinner. Not from the row's
    /// earlier result, whose changed text VoiceOver wouldn't read again.
    static func resultTakesFocus(from focus: Self?, row: Row) -> Bool {
        switch focus {
        case .control(let focused, _), .pending(let focused): focused == row
        case .result, nil: false
        }
    }
}

/// The controls that act on an Activity item, in a row or its pushed card.
enum ActivityFocusControl: Hashable {
    case action(ActivityAction)
    case retry
}

typealias ActivityFocus = ResultFocus<String, ActivityFocusControl>

/// What an accepted challenge, or a started Rengo game, does next.
enum ActivityAcceptRule: Equatable {
    /// A live game: the list closes, then the game opens with
    /// `closesNewGame: true`.
    case closeAndOpen(gameID: Int)
    /// A correspondence game: the list stays, showing the outcome.
    case stay(outcome: ActivityOutcome)

    init(isLive: Bool, gameID: Int) {
        self = isLive ? .closeAndOpen(gameID: gameID) : .stay(outcome: .gameStarted(gameID: gameID))
    }
}

/// A Quick Match withdraw. The socket's cancel gets no reply of its own, so
/// OGS's lifecycle events or a deadline settle it. HTTP withdraws never use
/// the deadline: their reply settles them.
enum ActivityQuickMatchWithdrawal {
    /// How long OGS has to confirm a cancel that was sent.
    static let confirmationLimit: TimeInterval = 8

    struct Entry: Equatable {
        /// The search's uuid.
        var uuid: String
        var state: ActivityActionState
    }

    /// After asking the socket to cancel the search: pending from `now` when
    /// the cancel was sent, and failed at once when it couldn't be.
    static func start(uuid: String, sent: Bool, at now: TimeInterval) -> Entry {
        Entry(uuid: uuid, state: sent ? .pending(since: now) : .failed)
    }

    /// What one lifecycle event does to the withdraws it names. A cancel
    /// withdraws them; OGS's cancel without a uuid ends every search. A game
    /// that started from the search removes its withdraw with no outcome,
    /// since the game lists or opens instead. A search OGS didn't confirm
    /// after a reconnect fails. A failed withdraw still takes a late cancel
    /// or start; one that succeeded is settled.
    static func apply<ID: Hashable>(
        _ event: OGSAutomatchLifecycleEvent.Kind,
        to entries: [ID: Entry]
    ) -> [ID: Entry] {
        var result = entries
        for (id, entry) in entries where entry.state.isPending || entry.state == .failed {
            switch event {
            case .cancelled(let uuid, _) where uuid == nil || uuid == entry.uuid:
                result[id]?.state = .succeeded(.withdrawn)
            case .started(let uuid, _, _) where uuid == entry.uuid:
                result[id] = nil
            case .notFoundAfterReconciliation(let uuid) where uuid == entry.uuid:
                result[id]?.state = .failed
            default:
                break
            }
        }
        return result
    }

    /// Fails each pending withdraw whose deadline has come.
    static func expire<ID: Hashable>(_ entries: [ID: Entry], at now: TimeInterval) -> [ID: Entry] {
        entries.mapValues { entry in
            guard case .pending(let since) = entry.state, now >= since + confirmationLimit else {
                return entry
            }
            var expired = entry
            expired.state = .failed
            return expired
        }
    }

    /// The earliest deadline among the pending withdraws.
    static func nextDeadline<ID: Hashable>(entries: [ID: Entry]) -> TimeInterval? {
        entries.values.compactMap { entry -> TimeInterval? in
            guard case .pending(let since) = entry.state else { return nil }
            return since + confirmationLimit
        }.min()
    }
}
