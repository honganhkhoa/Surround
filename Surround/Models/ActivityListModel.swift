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
        /// Scrolled to Messages, as the Messages button opens it.
        case messages
    }

    /// The list's session, which its rows' results belong to (ActivityResults).
    var sessionID: UUID
    var source: Source
    var focus: Focus
    var style: ActivityPresentationStyle
    /// The opener's frame in the window's global coordinates, captured when
    /// it was tapped, so a popover never depends on its opener staying.
    var anchor: CGRect

    var id: UUID { sessionID }

    init(
        sessionID: UUID = UUID(),
        source: Source,
        focus: Focus = .top,
        style: ActivityPresentationStyle,
        anchor: CGRect = .zero
    ) {
        self.sessionID = sessionID
        self.source = source
        self.focus = focus
        self.style = style
        self.anchor = anchor
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
    /// after it. Gone rows with nothing to follow lead the section, in the
    /// order given; so do rows whose predecessors point back at them.
    private static func merged(_ items: [ActivityModel.Item], _ gone: [ActivityResolvedRow]) -> [Row] {
        let goneByID = Dictionary(gone.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let anchors = Set(items.map(\.id)).union(goneByID.keys)
        var followers = [String: [ActivityResolvedRow]]()
        var leading = [ActivityResolvedRow]()
        for row in gone {
            if let after = row.after, anchors.contains(after), !leadsBackToItself(row, in: goneByID) {
                followers[after, default: []].append(row)
            } else {
                leading.append(row)
            }
        }

        var rows = [Row]()
        var placed = Set<String>()
        func place(_ row: Row) {
            guard placed.insert(row.id).inserted else { return }
            rows.append(row)
            for follower in followers[row.id] ?? [] {
                place(.resolved(follower))
            }
        }
        leading.forEach { place(.resolved($0)) }
        items.forEach { place(.item($0)) }
        return rows
    }

    /// Following `after` through the gone rows comes back to `row`.
    private static func leadsBackToItself(
        _ row: ActivityResolvedRow,
        in goneByID: [String: ActivityResolvedRow]
    ) -> Bool {
        var visited = Set<String>()
        var next = row.after
        while let id = next, let predecessor = goneByID[id] {
            if id == row.id {
                return true
            }
            guard visited.insert(id).inserted else { return false }
            next = predecessor.after
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
    private static func number(in id: String, after prefix: String) -> Int? {
        guard let text = remainder(of: id, after: prefix), let number = Int(text),
              String(number) == text else {
            return nil
        }
        return number
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
