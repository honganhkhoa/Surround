//
//  ActivityBarModel.swift
//  Surround
//
//  The Activity bar's rules that need no view: what the bar shows, from the
//  window's Activity, its connection and the status its host carries; the
//  bar's forms from traits, and the parts each form draws and drops; which
//  host shows the bar, from container state, and the order a UIKit
//  container follows around its tab bar; the line under root titles; the
//  Now section's status row; and what VoiceOver hears as a lead first
//  leads. Each reads only values a host has before it draws, never a view's
//  geometry, so SurroundTests checks every rule without a socket or a view.
//

import CoreGraphics
import Foundation

// MARK: - The connection's words

/// The line under a root's title on iPhones and the Duo from iOS 26, and the
/// words every carrier of the window's connection status says: the line, the
/// bar's status kinds and the Now section's status row.
enum RootConnectionLine: Equatable {
    /// What a carrier says.
    enum Words: Equatable {
        /// "Connecting…": before the window's first connection, while its
        /// socket is still on its first attempt.
        case connecting
        /// "Reconnecting…".
        case reconnecting
        /// "Can’t reach OGS". Retry is the bar's or the Now row's, never the
        /// line's.
        case unreachable
        /// "Connected", for 2 s after an outage someone saw.
        case connected
    }

    case says(Words)
    /// A space, after words showed during this visit: the line keeps its
    /// room and the title stays still until the root leaves the screen.
    case space
    /// Empty: nothing showed during this visit, so the line reserves nothing.
    case empty

    /// - Parameter shownThisVisit: Words have shown since the root last came
    ///   on screen. The root sets it as words show and clears it as the root
    ///   leaves the screen: a push or a tab switch, not a sheet, a turn or the
    ///   background.
    init(status: ConnectionStatusModel.Status, hasConnected: Bool, socket: OGSWebsocketStatus,
         shownThisVisit: Bool) {
        if let words = Self.words(status: status, hasConnected: hasConnected, socket: socket) {
            self = .says(words)
        } else {
            self = shownThisVisit ? .space : .empty
        }
    }

    /// What every carrier says for the window's status; nil while there is
    /// nothing to say. A lost connection reads as the clocks read it
    /// (`GameDetailClockState.recoversConnection(hasConnected:socket:)`):
    /// "Reconnecting…" once the window has connected or an attempt has
    /// failed, and "Connecting…" before that.
    static func words(status: ConnectionStatusModel.Status, hasConnected: Bool,
                      socket: OGSWebsocketStatus) -> Words? {
        switch status {
        case .hidden:
            nil
        case .reconnecting:
            GameDetailClockState.recoversConnection(hasConnected: hasConnected, socket: socket)
                ? .reconnecting : .connecting
        case .unreachable:
            .unreachable
        case .connected:
            .connected
        }
    }

    /// What the line says; nil for a blank.
    var words: Words? {
        if case .says(let words) = self { return words }
        return nil
    }
}

// MARK: - The bar's Activity

/// An action taken in the bar or a Now section, from the window's standing
/// session for its chrome: pending, then its result, which the results store
/// keeps for 4 s after it settles.
struct ActivityBarResult: Equatable {
    /// The item it acted on (`ActivityModel.Item.id`).
    var itemID: String
    var action: ActivityAction
    var state: ActivityActionState
    /// The item as it was when the action started, so the bar still shows
    /// what it was once the item has gone.
    var display: ActivityRowDisplay
}

/// What leads the bar or a Now row: the lead's kind and item, without a live
/// game's ticking fields. A clock ticks inside its chip, which observes its
/// game.
enum ActivityBarLead: Equatable {
    /// A live game: on your move, low on time, on their move, in stone
    /// removal or paused. Its trailing part is its clock.
    case liveGame(gameID: Int)
    /// A live game that started elsewhere, during its first 30 s: Open game.
    case gameStarted(gameID: Int)
    /// A live challenge sent to you: View, never an inline Accept.
    case challenge(ActivityModel.Challenge)
    /// Your own live search or challenge, with Withdraw where its row in the
    /// list withdraws in place.
    case waiting(ActivityModel.Waiting, withdrawsInPlace: Bool)
    /// Nothing live leads: the inbox glyph and "N waiting".
    case nothingLeads(count: Int)

    /// Nil for an item the model never leads with.
    /// - Parameter searchWithdrawsInPlace: Whether a Quick Match search
    ///   withdraws in place, as its row does when it is one size at one speed
    ///   (`ActivityQuickMatchRow.withdrawsInPlace`). Open and sent challenges
    ///   always do; Rengo never, since its card holds Start and Leave.
    init?(_ lead: ActivityModel.Lead, searchWithdrawsInPlace: (ActivityModel.Waiting) -> Bool = { _ in false }) {
        switch lead {
        case .gameStarted(let game):
            self = .gameStarted(gameID: game.id)
        case .item(.liveGame(let game)):
            self = .liveGame(gameID: game.id)
        case .item(.challenge(let challenge)):
            self = .challenge(challenge)
        case .item(.waiting(let waiting)):
            let inPlace = switch waiting.kind {
            case .openChallenge, .sentChallenge: true
            case .quickMatch: searchWithdrawsInPlace(waiting)
            case .rengo: false
            }
            self = .waiting(waiting, withdrawsInPlace: inPlace)
        case .waiting(let count):
            self = .nothingLeads(count: count)
        case .item(.correspondenceGames), .item(.conversation):
            return nil
        }
    }

    /// The leading item's id (`ActivityModel.Item.id`); nil for "N waiting".
    var itemID: String? {
        switch self {
        case .liveGame(let gameID), .gameStarted(let gameID):
            ActivityModel.Item.liveGame(ActivityModel.LiveGame(id: gameID, isYourMove: false)).id
        case .challenge(let challenge): ActivityModel.Item.challenge(challenge).id
        case .waiting(let waiting, _): ActivityModel.Item.waiting(waiting).id
        case .nothingLeads: nil
        }
    }

    /// A game's lead, whose trailing part is a clock or Open game: its line
    /// two says the window's status on every host, since its clock can't
    /// move.
    var isGame: Bool {
        switch self {
        case .liveGame, .gameStarted: true
        case .challenge, .waiting, .nothingLeads: false
        }
    }
}

/// One item that +N or "N waiting" counts, without a live game's ticking
/// fields: what its VoiceOver breakdown names.
enum ActivityBarCountedItem: Equatable {
    /// A live game on your move.
    case liveGame(gameID: Int)
    /// A challenge sent to you, live or correspondence.
    case challenge(ActivityModel.Challenge)
    /// An unread conversation.
    case conversation(peerID: Int)

    /// Nil for an item +N never counts.
    init?(_ item: ActivityModel.Item) {
        switch item {
        case .liveGame(let game): self = .liveGame(gameID: game.id)
        case .challenge(let challenge): self = .challenge(challenge)
        case .conversation(let conversation): self = .conversation(peerID: conversation.peerID)
        case .waiting, .correspondenceGames: return nil
        }
    }
}

/// The bar's Activity part, as the window's bar state publishes it: a
/// result, or the lead with what +N counted. A stable value: no tick of a
/// clock changes it, so the hosts redraw only when what they show changes.
struct ActivityBarActivity: Equatable {
    var result: ActivityBarResult?
    var lead: ActivityBarLead?
    /// What +N counted beside the lead, or what "N waiting" counts. The lead
    /// never counts itself.
    var counted: [ActivityBarCountedItem] = []
    /// The lead as +N would count it, where it counts: a live game on your
    /// move or a challenge. "Can’t reach OGS" folds it into +N.
    var countedLead: ActivityBarCountedItem?

    init(result: ActivityBarResult? = nil, lead: ActivityBarLead? = nil, counted: [ActivityBarCountedItem] = [],
         countedLead: ActivityBarCountedItem? = nil) {
        self.result = result
        self.lead = lead
        self.counted = counted
        self.countedLead = countedLead
    }

    /// A root screen's snapshot (`ActivityModel.snapshot(_:)`), with the
    /// bar's result.
    init(_ snapshot: ActivityModel.Snapshot, result: ActivityBarResult? = nil,
         searchWithdrawsInPlace: (ActivityModel.Waiting) -> Bool = { _ in false }) {
        self.result = result
        if let lead = snapshot.lead {
            self.lead = ActivityBarLead(lead, searchWithdrawsInPlace: searchWithdrawsInPlace)
        } else {
            self.lead = nil
        }
        counted = snapshot.counted.compactMap(ActivityBarCountedItem.init)
        // A lead is never a conversation, so the Messages tab can't matter.
        countedLead = snapshot.lead?.item
            .flatMap { ActivityModel.counts($0, onMessagesTab: false) ? ActivityBarCountedItem($0) : nil }
    }

    /// +N beside the lead: none beside "N waiting", which counts the items
    /// itself, or without a lead.
    var plusN: Int {
        switch lead {
        case .nothingLeads?, nil: 0
        case .liveGame?, .gameStarted?, .challenge?, .waiting?: counted.count
        }
    }
}

// MARK: - What the bar shows

extension ActivityHostPolicy.ConnectionStatus {
    /// The window's bar says every status kind, and line two of every lead
    /// says the status: the custom bar before iOS 26, and the iPad's
    /// floating bar.
    var barCarriesAllStatus: Bool { self == .floatingBar }

    /// The window's bar says "Can’t reach OGS" with Retry: where it carries
    /// all status, and on iPhones and the Duo from iOS 26, whose line under
    /// the title has no Retry.
    var barCarriesUnreachable: Bool { self != .nowSectionFirstRow }
}

/// What the bar shows, from the window's Activity, its connection and the
/// status its host carries: one value, so a host's decision that the bar
/// exists and what the bar draws never disagree. The first that applies:
/// 1. an action taken in the bar or a Now section, pending or for 4 s after
///    it settles;
/// 2. "Can’t reach OGS", Retry and +N where the bar carries it, the lead
///    folded into +N where it counts, and with nothing waiting too;
/// 3. the lead, whose line two says "Connecting…" or "Reconnecting…" while
///    the window's status shows: on a game's lead on every host, and on
///    every lead where the bar carries all status;
/// 4. where the bar carries all status and nothing waits: "Connecting…" or
///    "Reconnecting…", or "Connected" for 2 s after an outage someone saw;
/// 5. otherwise nothing, and no bar.
enum ActivityBarContent: Equatable {
    case result(ActivityBarResult)
    /// "Can’t reach OGS", Retry and +N.
    case unreachable(counted: [ActivityBarCountedItem])
    /// The lead with +N. `status` is what line two says in its place.
    case lead(ActivityBarLead, counted: [ActivityBarCountedItem], status: RootConnectionLine.Words?)
    /// The status alone, which isn't a button.
    case status(RootConnectionLine.Words)

    /// - Parameters:
    ///   - words: What the window's connection says
    ///     (`RootConnectionLine.words(status:hasConnected:socket:)`).
    ///   - placement: Where the window says its status
    ///     (`ActivityHostPolicy.Hosts.connectionStatus`).
    init?(_ activity: ActivityBarActivity, words: RootConnectionLine.Words?,
          placement: ActivityHostPolicy.ConnectionStatus) {
        if let result = activity.result {
            self = .result(result)
        } else if words == .unreachable, placement.barCarriesUnreachable {
            self = .unreachable(counted: (activity.countedLead.map { [$0] } ?? []) + activity.counted)
        } else if let lead = activity.lead {
            let outage = words == .connecting || words == .reconnecting ? words : nil
            let says = lead.isGame || placement.barCarriesAllStatus
            self = .lead(lead, counted: activity.counted, status: says ? outage : nil)
        } else if placement.barCarriesAllStatus, let words, words != .unreachable {
            self = .status(words)
        } else {
            return nil
        }
    }

    init?(_ activity: ActivityBarActivity, status: ConnectionStatusModel.Status, hasConnected: Bool,
          socket: OGSWebsocketStatus, placement: ActivityHostPolicy.ConnectionStatus) {
        self.init(activity, words: RootConnectionLine.words(status: status, hasConnected: hasConnected, socket: socket),
                  placement: placement)
    }

    /// The count +N shows: none beside "N waiting" or without Activity.
    var plusN: Int {
        switch self {
        case .unreachable(let counted): counted.count
        case .lead(.nothingLeads, _, _): 0
        case .lead(_, let counted, _): counted.count
        case .result, .status: 0
        }
    }
}

// MARK: - The Now section's status row

/// The Now section's first row during an outage: on iPad while the sidebar
/// shows over a root or beside the content, on every iPadOS, and on the Mac
/// on every screen but a game. A game says its status itself, so its place
/// gets none. While the row shows, the section lists one Activity row less.
struct NowStatusRow: Equatable {
    var words: RootConnectionLine.Words

    /// Retry, at "Can’t reach OGS".
    var offersRetry: Bool { words == .unreachable }

    /// Nil with nothing to say, and over a game.
    init?(_ words: RootConnectionLine.Words?, place: ActivityModel.Place) {
        guard let words, place.gameID == nil else { return nil }
        self.words = words
    }

    init?(status: ConnectionStatusModel.Status, hasConnected: Bool, socket: OGSWebsocketStatus,
          place: ActivityModel.Place) {
        self.init(RootConnectionLine.words(status: status, hasConnected: hasConnected, socket: socket), place: place)
    }

    /// How many Activity rows the section lists beside `row`, which takes the
    /// first of them (`ActivityModel.nowSection(_:rows:)`).
    static func activityRows(beside row: NowStatusRow?, of rows: Int = ActivityModel.nowSectionRows) -> Int {
        max(0, row == nil ? rows : rows - 1)
    }
}

// MARK: - The Now section's rows

/// One Activity row of the Now section: what the window's bar state lists,
/// or the result of an action the bar or the section took on its item,
/// pending and then for 4 s after it settles. A withdrawn item leaves the
/// list as OGS confirms it, and its result keeps the row's place meanwhile.
enum ActivityNowEntry: Equatable {
    case lead(ActivityBarLead)
    case result(ActivityBarResult)

    /// The "N waiting" row's id, which stands for no one item.
    static let waitingID = "waiting"

    /// The row's item (`ActivityModel.Item.id`), or `waitingID`.
    var id: String {
        switch self {
        case .lead(let lead): lead.itemID ?? Self.waitingID
        case .result(let result): result.itemID
        }
    }

    /// The rows to draw, at most `room`: each of `rows`, with the result in
    /// its place where the chrome acted on its item, and a result whose item
    /// has left `rows` where its row was drawn before. A result for an item
    /// the section never drew is the bar's alone.
    /// - Parameters:
    ///   - results: The chrome's results, in the order they were sent
    ///     (`ActivityResults.chromeResults`).
    ///   - previous: The ids of the rows drawn last, in order.
    static func entries(rows: [ActivityBarLead], results: [ActivityBarResult], room: Int,
                        previous: [String]) -> [ActivityNowEntry] {
        var byItem = [String: ActivityBarResult]()
        for result in results { byItem[result.itemID] = result }
        var entries: [ActivityNowEntry] = rows.map { lead in
            if let id = lead.itemID, let result = byItem[id] { .result(result) } else { .lead(lead) }
        }
        var shown = Set(entries.map(\.id))
        for result in results where !shown.contains(result.itemID) {
            guard let index = previous.firstIndex(of: result.itemID) else { continue }
            entries.insert(.result(byItem[result.itemID] ?? result), at: min(index, entries.count))
            shown.insert(result.itemID)
        }
        return Array(entries.prefix(max(0, room)))
    }
}

// MARK: - Forms

/// What a bar's form comes from: its host, the accessory's placement trait
/// and the container's traits. Never the bar's measured width, which inside
/// an accessory is UIKit's.
struct ActivityBarTraits: Equatable {
    var bar: ActivityHostPolicy.Bar
    var container: ActivityHostPolicy.Container
    /// Where the system says its accessory sits; `.unavailable` for the
    /// custom bar.
    var placement = ActivityHostPolicy.AccessoryPlacement.unavailable
    var isCompactWidth = true
    var isCompactHeight = false
    /// The container's tabs run along a vertical edge, as the Duo's rail.
    var hasVerticalBarEdge = false

    /// The host says all of the window's status, so the status words and a
    /// lead's status badge read whole: the custom bar, before iOS 26 and on
    /// iPadOS 18, and the iPad's floating bar on every iPadOS. From iOS 26 an
    /// iPhone's line under the title says the words, and its bar may cut
    /// them short.
    var saysAllStatus: Bool { bar == .customBar || container == .iPadTabContainer }
}

enum ActivityBarForm: Equatable {
    /// Two lines: the tile, line one and line two, the trailing action and
    /// +N.
    case expanded
    /// The custom bar in compact height: one 48 pt line. Line two drops;
    /// the trailing action, Retry and +N stay.
    case compactHeight
    /// Beside a minimized tab bar: the tile, line one, a game's clock and a
    /// compact +N, without line two.
    case inline
    /// The Duo's Closed upright bar, 290 pt: the inline form's one line,
    /// with the opponent's name as line one.
    case closed

    init(_ traits: ActivityBarTraits) {
        switch traits.bar {
        case .customBar:
            self = traits.isCompactHeight ? .compactHeight : .expanded
        case .swiftUIAccessory:
            self = traits.placement == .inline ? .inline : .expanded
        case .uiKitAccessory:
            // The Duo's Closed traits: compact width, regular height and a
            // vertical bar edge. Neither the hinge nor the sidebar's
            // availability marks Closed alone, and its rail never minimizes.
            if traits.container == .duoTabContainer, traits.isCompactWidth, !traits.isCompactHeight,
               traits.hasVerticalBarEdge {
                self = .closed
            } else {
                // The first layouts report no placement, so anything but
                // inline draws expanded.
                self = traits.placement == .inline ? .inline : .expanded
            }
        }
    }

    /// One line: the inline form and the Duo's Closed bar, which drop parts
    /// when they don't fit.
    var isOneLine: Bool { self == .inline || self == .closed }
}

// MARK: - What each form draws

/// The bar's one trailing action.
enum ActivityBarAction: Equatable {
    case openGame
    case view
    case withdraw
    case retry
}

/// A part of the bar, from leading to trailing.
enum ActivityBarPart: Equatable {
    /// The opponent, the challenger, the inbox glyph, a waiting kind's
    /// glyph or the status glyph.
    case tile
    case lineOne
    case lineTwo
    /// Before a game's clock as it counts down.
    case hourglass
    case clock
    case action(ActivityBarAction)
    /// What else waits, in a neutral capsule that opens Activity.
    case plusN
}

/// What the bar draws for its content in a form, before it fits: the parts,
/// and those that drop when the rest doesn't fit, the first to drop first.
/// Line one and line two truncate at their tail; nothing else shrinks, and
/// the clock and Retry never drop.
///
/// - Expanded: the tile, both lines, the trailing action and +N.
/// - Compact height: the same on one line, without line two.
/// - Inline and the Duo's Closed bar: the tile, line one, a game's clock and
///   +N. A lead without a clock waits for its action in Activity, one tap
///   away; "Can’t reach OGS" and "Couldn’t withdraw" keep Retry. The
///   hourglass drops first, then the tile, then +N, whose count stays in
///   VoiceOver and Activity.
/// - Where the host says all status, the two-line and compact-height forms
///   drop the same parts in the same order, so that the status words and a
///   lead's status badge read whole, since nothing else on screen says
///   them. In the two-line form the status words take line two's place too.
struct ActivityBarDrawing: Equatable {
    var parts: [ActivityBarPart]
    /// The parts that may drop, the first to drop first.
    var dropOrder: [ActivityBarPart]
    /// The lines line one may take: two where the status words take line
    /// two's place, else one.
    var lineOneLines = 1

    /// - Parameter saysAllStatus: The host says all of the window's status
    ///   (`ActivityBarTraits.saysAllStatus`).
    init(_ content: ActivityBarContent, form: ActivityBarForm, saysAllStatus: Bool = false) {
        var drawn: [ActivityBarPart] = [.tile, .lineOne]
        switch content {
        case .result(let result):
            if form == .expanded { drawn.append(.lineTwo) }
            if result.state == .failed { drawn.append(.action(.retry)) }
        case .unreachable:
            // The status says itself on line one alone.
            drawn.append(.action(.retry))
        case .lead(let lead, _, _):
            if form == .expanded { drawn.append(.lineTwo) }
            if lead.hasClock { drawn += [.hourglass, .clock] }
            if !form.isOneLine, let action = lead.action { drawn.append(.action(action)) }
        case .status:
            break
        }
        if content.plusN > 0 { drawn.append(.plusN) }
        parts = drawn
        let drops: [ActivityBarPart] = [.hourglass, .tile, .plusN]
        dropOrder = form.isOneLine || saysAllStatus ? drops.filter { drawn.contains($0) } : []
        if saysAllStatus, form == .expanded, !drawn.contains(.lineTwo) { lineOneLines = 2 }
    }
}

private extension ActivityBarLead {
    /// A live game's lead, whose trailing part is its clock.
    var hasClock: Bool {
        if case .liveGame = self { return true }
        return false
    }

    /// The trailing action beside the lead's lines, where it has one.
    var action: ActivityBarAction? {
        switch self {
        case .liveGame, .nothingLeads: nil
        case .gameStarted: .openGame
        case .challenge: .view
        case .waiting(_, let withdrawsInPlace): withdrawsInPlace ? .withdraw : nil
        }
    }
}

/// The padding and spacing of the bar's parts, in points.
struct ActivityBarSpacing: Equatable {
    var leading: CGFloat
    var trailing: CGFloat
    /// Between two parts.
    var between: CGFloat

    func width(of parts: [ActivityBarPart], _ width: (ActivityBarPart) -> CGFloat) -> CGFloat {
        guard !parts.isEmpty else { return 0 }
        return leading + trailing + parts.map(width).reduce(0, +) + between * CGFloat(parts.count - 1)
    }
}

/// The parts a drawing keeps in its width, after its drop order.
struct ActivityBarFit: Equatable {
    var parts: [ActivityBarPart]
    /// The kept parts with their padding and spacing, line one at its
    /// narrowest.
    var width: CGFloat
    /// The parts that never drop fit.
    var fits: Bool
}

extension ActivityBarDrawing {
    /// Drops parts in `dropOrder` until the rest fit `width`. Line one
    /// truncates first, down to the narrowest `partWidth(.lineOne)` gives,
    /// as the Duo's Closed bar truncates the name before anything drops.
    func fit(in width: CGFloat, spacing: ActivityBarSpacing,
             partWidth: (ActivityBarPart) -> CGFloat) -> ActivityBarFit {
        var kept = parts
        var drops = dropOrder[...]
        var total = spacing.width(of: kept, partWidth)
        while total > width, let next = drops.popFirst() {
            kept.removeAll { $0 == next }
            total = spacing.width(of: kept, partWidth)
        }
        return ActivityBarFit(parts: kept, width: total, fits: total <= width)
    }
}

// MARK: - Who shows the bar

/// The tab-bar state a UIKit container last asked for. Its accessory follows
/// this record, never `isTabBarHidden`, which still reads shown while a
/// hide's layout runs.
enum ActivityTabBarRecord: Equatable {
    case shown
    case hidden
}

/// What decides whether a window's host shows the bar now: container state,
/// the keyboard's notifications, the registry and the window's bar content,
/// never geometry. A UIKit container keeps one, with its own records, and
/// reads it at every decision point; a re-entrant read during a tab-bar
/// change reads the same records, so it gives the same answer.
struct ActivityBarHostState: Equatable {
    /// The window's platform, container, OS and SDK, with the sidebar as this
    /// host reads it: for UIKit's accessory the coordinator's sidebar record,
    /// shown as the sidebar starts to show and hidden at the hide's
    /// completion; for the custom bar the observable copy.
    var facts: ActivityHostPolicy.Facts
    var overrides = ActivityHostPolicy.Overrides()
    /// The registry's settled place for the selected tab hides the bar: Game
    /// Detail, or a conversation, pushed or in Messages' side pane.
    var placeHidesBar = false
    /// The window's bar content isn't nil (`ActivityBarContent`).
    var hasContent = false
    /// UIKit's accessory: the tab-bar state the coordinator last asked for.
    var requestedTabBar = ActivityTabBarRecord.shown
    /// UIKit's accessory: the container's view is in a window. Set before,
    /// the Duo's Closed accessory is a 206 pt capsule.
    var isInWindow = false
    /// The Duo: the coordinator's drawer record, shown from a main-queue
    /// turn after the drawer starts to show until
    /// `ActivityAccessoryOrder.drawerReturnDelay` after its close completes.
    var isDrawerShown = false
    /// The iPad: the selected tab's stack has a route that shows Game Detail
    /// on top, from the stack's own signal before the game's first layout.
    var isGameAskedFor = false
    /// A docked software keyboard shows over the window: the keyboard
    /// notification's end frame against the window's bounds.
    var isKeyboardOverWindow = false
    /// The container has a bottom tab bar, which a docked keyboard covers
    /// together with the bar.
    var hasBottomTabBar = true
    /// Compact height, as a Max iPhone in landscape, which UIKit moves beside
    /// the drawer without covering.
    var isCompactHeight = false

    /// The floating bar the window shows now; nil for none.
    /// - The custom bar: on a screen the registry doesn't hide, while no
    ///   docked keyboard shows. The iPadOS 18 sidebar's copy takes it away
    ///   through the policy.
    /// - SwiftUI's accessory: on a screen the registry doesn't hide. A docked
    ///   keyboard hides it with the tab bar.
    /// - UIKit's accessory: also while the requested tab bar is shown and the
    ///   container's view is in a window. On the iPad, while no game is asked
    ///   for in the selected tab and no docked keyboard shows; its sidebar
    ///   record takes it away through the policy. Elsewhere, while the drawer
    ///   record is hidden, but for compact height, and while no docked
    ///   keyboard shows where it isn't covered with a bottom tab bar.
    var shownBar: ActivityHostPolicy.Bar? {
        guard hasContent, !placeHidesBar,
              let bar = ActivityHostPolicy.hosts(for: facts, overrides: overrides).bar else { return nil }
        switch bar {
        case .customBar:
            return isKeyboardOverWindow ? nil : bar
        case .swiftUIAccessory:
            return bar
        case .uiKitAccessory:
            guard requestedTabBar == .shown, isInWindow else { return nil }
            if facts.container == .iPadTabContainer {
                return isGameAskedFor || isKeyboardOverWindow ? nil : bar
            }
            if isDrawerShown, !isCompactHeight { return nil }
            if isKeyboardOverWindow, !hasBottomTabBar { return nil }
            return bar
        }
    }

    /// Whether a docked software keyboard shows over the window, from the
    /// keyboard's notification: its end frame, in the window's coordinates,
    /// overlaps the window's bounds. A small iPad window can sit above a
    /// keyboard docked at the screen's bottom, and keeps its bar then, as it
    /// keeps its tab bar.
    /// - Parameters:
    ///   - docked: The notification shows a docked software keyboard
    ///     (`isAttachedSoftwareKeyboardVisible(from:)`).
    ///   - keyboardEnd: The notification's end frame, in the window's
    ///     coordinates.
    ///   - window: The window's bounds.
    static func keyboardIsOverWindow(docked: Bool, keyboardEnd: CGRect, window: CGRect) -> Bool {
        guard docked, !keyboardEnd.isNull, !keyboardEnd.isEmpty else { return false }
        let overlap = keyboardEnd.intersection(window)
        return !overlap.isNull && overlap.width > 0 && overlap.height > 0
    }
}

// MARK: - The order around the tab bar

/// One step of a UIKit container's order around its tab bar and accessory.
enum ActivityAccessoryStep: Equatable {
    /// The coordinator records the tab-bar state it asks for.
    case record(ActivityTabBarRecord)
    /// Sets the accessory where `ActivityBarHostState.shownBar` says UIKit's
    /// accessory shows, and clears it otherwise.
    case recompute
    /// Clears the accessory without animation, whatever the state says.
    case clearWithoutAnimation
    /// The container's own tab-bar change and what goes with it: on iPad,
    /// dropping its closed baselines, `setTabBarHidden`, then closing the
    /// sidebar and restoring the person's choice; on the Duo, closing the
    /// drawer and dropping its baselines first.
    case changeTabBar(hidden: Bool)
}

/// The order a UIKit container follows so its accessory is never set while a
/// hide's layout runs: a hide records, clears, then changes the tab bar; a
/// show changes it, records, then sets. On iPad the set waits for the
/// sidebar record, read through the policy. Every other change (the
/// registry, `update(...)`, a sidebar or drawer record, the keyboard, a game
/// asked for, the view coming into a window) updates the host state, then
/// recomputes.
enum ActivityAccessoryOrder {
    /// `applyTabBarVisibility`'s steps, from the record to the state the
    /// selected tab asks for. Every call recomputes at the end, since a tab
    /// switch to Messages with a conversation in its pane changes no tab bar
    /// but clears the bar.
    static func tabBar(from record: ActivityTabBarRecord, to requested: ActivityTabBarRecord) -> [ActivityAccessoryStep] {
        switch (record, requested) {
        case (.shown, .hidden): [.record(.hidden), .recompute, .changeTabBar(hidden: true), .recompute]
        case (.hidden, .shown): [.changeTabBar(hidden: false), .record(.shown), .recompute]
        case (.shown, .shown), (.hidden, .hidden): [.recompute]
        }
    }

    /// After each size transition's completion: the accessory clears without
    /// animation, and the recompute sets it again sized for the new pose,
    /// unless something holds it cleared.
    static let sizeTransitionCompleted: [ActivityAccessoryStep] = [.clearWithoutAnimation, .recompute]

    /// How long after the Duo's drawer closes its record turns hidden and the
    /// bar comes back. The close's completion fires as the slide starts, and
    /// a set then would snap the drawer shut.
    static let drawerReturnDelay: TimeInterval = 0.5
}

// MARK: - What VoiceOver hears on root screens

/// What VoiceOver hears from Activity on root screens, from the bar or the
/// Now section's first row: "Game started with CedarWave" as a started game
/// first leads, and "Challenge from CedarWave" as a live challenge sent to
/// you first leads. Nothing else: the bar coming and going, +N and the
/// order stay silent.
enum ActivityBarAnnouncement: Equatable {
    case gameStarted(gameID: Int)
    case challenge(challengeID: Int)
}

/// The window's claims on what a lead has said, so each is said once: a
/// challenge in this set, and a started game through the window's recorder,
/// which Game Detail's control and "Game found" claim too. The claims stand
/// for the leads said before, so a lead that keeps the bar, or loses it and
/// comes back, says nothing again.
struct ActivityBarFirstLeads: Equatable {
    private(set) var claimedChallengeIDs: Set<Int> = []

    /// What to say as `lead` leads, claiming it; nil for nothing.
    /// - Parameters:
    ///   - isRootOnScreen: The registry's place for the selected tab is a
    ///     root's, a sheet over it included, since the bar waits underneath.
    ///     A lead that comes while a game or a conversation is on top is
    ///     said when the root shows again, if it still leads unclaimed.
    ///   - isCovered: The superchat cover is up, which holds it the same way.
    ///   - claimStartedGame: The window's claim for a game
    ///     (`StartedGamesRecorder.claimAnnouncement(for:)`): true the first
    ///     time.
    mutating func announcement(for lead: ActivityBarLead?, isRootOnScreen: Bool, isCovered: Bool = false,
                               claimStartedGame: (Int) -> Bool) -> ActivityBarAnnouncement? {
        guard isRootOnScreen, !isCovered, let lead else { return nil }
        switch lead {
        case .gameStarted(let gameID):
            return claimStartedGame(gameID) ? .gameStarted(gameID: gameID) : nil
        case .challenge(let challenge):
            guard challenge.isLive, claimedChallengeIDs.insert(challenge.id).inserted else { return nil }
            return .challenge(challengeID: challenge.id)
        case .liveGame, .waiting, .nothingLeads:
            return nil
        }
    }
}
