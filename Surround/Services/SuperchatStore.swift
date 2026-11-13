//
//  SuperchatStore.swift
//  Surround
//
//  Moderator superchats once per app and per OGS account (in-app
//  notices). Every window's OGSService reports what its own socket hears
//  and how its authentication went; every window's cover shows the result,
//  so a superchat covers every window and Done in any window clears them
//  all. Superchats still on are saved per account, so a relaunch or a new
//  window opens covered. Main thread only, like OGSService. The app's
//  instance and its lifecycle hooks are in SuperchatStore+System.swift.
//

import Combine
import Foundation

/// One moderator's superchat with the account.
struct SuperchatModerator: Codable, Equatable, Identifiable {
    let id: Int
    /// From the event, so the cover can name the moderator before any history loads.
    var username: String
    /// When the app first heard this run of the superchat (seconds since 1970).
    var startedAt: TimeInterval
    /// Nil while it is on.
    var endedAt: TimeInterval?
    /// OGS didn't re-send it after a connection: it ended while Surround wasn't listening.
    var endWasMissed = false

    var isOn: Bool { endedAt == nil }
}

/// What one account's cover shows, from the first start until Done.
struct SuperchatCover: Equatable {
    /// Newest start first.
    var moderators: [SuperchatModerator]

    var isOn: Bool { moderators.contains(where: \.isOn) }
    /// Nothing is on, and something ended while Surround listened: the end card and Done.
    var awaitsDone: Bool { !isOn && moderators.contains { !$0.endWasMissed } }
}

/// An end this session, for the line Messages shows in that conversation.
struct SuperchatEnding: Equatable {
    /// A live end by OGS's clock, as the window that heard it estimates, so
    /// it compares with the times OGS gives messages; a missed one by the
    /// store's own clock.
    var at: TimeInterval
    var wasMissed: Bool
}

final class SuperchatStore: ObservableObject {
    /// How long, after OGS answers a connection's `authenticate`, a cover
    /// waits for the re-send of each superchat still on. On Beta the slowest
    /// re-send came 0.785 s after its `authenticate` (11 Nov 2026).
    static let resendWindow: TimeInterval = 10

    /// By OGS account id.
    @Published private(set) var covers: [Int: SuperchatCover] = [:]
    /// This session's ends, by account id, then moderator id.
    @Published private(set) var endings: [Int: [Int: SuperchatEnding]] = [:]
    /// An account whose cover went away without Done, so the window the
    /// user is in can say why.
    let coverLiftedWithoutDone = PassthroughSubject<Int, Never>()
    /// While the app is in the background no deadline starts or lifts a
    /// cover. Waits still open, and are kept for the return.
    private(set) var isInBackground = false

    private let preferences: UserDefaults?
    private let scheduler: OGSWebsocketScheduling
    private let now: () -> TimeInterval
    /// By connection: each service's own UUID, never reused.
    private var waits = [UUID: ResendWait]()
    private var latestHoldTicket = 0

    private struct ResendWait {
        let accountID: Int
        /// Superchats still on that no connection of the account has heard again.
        var awaiting: Set<Int>
        /// The connection answered a ping since it authenticated, and since
        /// the app last came back to the foreground.
        var answeredPing = false
        /// OGS didn't answer, or answered before or during a stay in the
        /// background: the deadline starts at the next answered ping.
        var startsAtPing = false
        var deadline: Cancellable?
    }

    /// - Parameter preferences: Where superchats still on are saved; nil
    ///   keeps them in memory only.
    init(
        preferences: UserDefaults?,
        scheduler: OGSWebsocketScheduling = OGSMainQueueWebsocketScheduler.shared,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) {
        self.preferences = preferences
        self.scheduler = scheduler
        self.now = now
        for (accountID, saved) in preferences?[.superchatModeratorsByOGSAccountID] ?? [:] {
            let on = saved.filter(\.isOn).sorted { $0.startedAt > $1.startedAt }
            if accountID > 0, !on.isEmpty { covers[accountID] = SuperchatCover(moderators: on) }
        }
    }

    // MARK: What a window's socket hears

    /// A `private-superchat` that passed the window's checks (OGSService.handleSuperchat).
    /// - Parameter endedAt: For an end, when it happened by OGS's clock, as
    ///   the window estimates it. Without one, the store's own clock.
    func receive(
        enable: Bool, moderatorID: Int, username: String?, accountID: Int, endedAt: TimeInterval? = nil
    ) {
        guard accountID > 0, moderatorID > 0, moderatorID != accountID else { return }
        let name = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var cover = covers[accountID] ?? SuperchatCover(moderators: [])
        let index = cover.moderators.firstIndex { $0.id == moderatorID }
        if enable {
            // Heard again: it counts for every open wait of this account.
            markHeard(moderatorID, accountID: accountID)
            if let index, cover.moderators[index].isOn {
                // A copy from another window, or OGS's re-send.
                guard !name.isEmpty, cover.moderators[index].username != name else { return }
                cover.moderators[index].username = name
            } else {
                // A new superchat, or a new one after the last ended: newest first.
                if let index { cover.moderators.remove(at: index) }
                cover.moderators.insert(
                    SuperchatModerator(id: moderatorID, username: name, startedAt: now()), at: 0)
                endings[accountID]?[moderatorID] = nil
            }
        } else {
            // Copies, and ends the app never saw start, change nothing.
            guard let index, cover.moderators[index].isOn else { return }
            let time = endedAt ?? now()
            cover.moderators[index].endedAt = time
            endings[accountID, default: [:]][moderatorID] = SuperchatEnding(at: time, wasMissed: false)
        }
        covers[accountID] = cover
        save()
    }

    /// The window's socket sent `authenticate` as `accountID`; a re-send
    /// from now on counts for it. In the background too: a socket that
    /// reconnects there can still be open when the app comes back.
    func connectionAuthenticating(_ connection: UUID, accountID: Int) {
        waits.removeValue(forKey: connection)?.deadline?.cancel()
        guard let cover = covers[accountID], cover.isOn else { return }
        waits[connection] = ResendWait(
            accountID: accountID, awaiting: Set(cover.moderators.filter(\.isOn).map(\.id)))
    }

    /// How OGS answered that `authenticate` (OGSWebsocket).
    func connectionAnswered(
        _ connection: UUID, accountID: Int, _ outcome: OGSWebsocketAuthenticationAnswer.Outcome
    ) {
        guard var wait = waits[connection], wait.accountID == accountID,
              wait.deadline == nil else { return }
        switch outcome {
        case .confirmed where !isInBackground:
            startDeadline(&wait, connection)
        case .confirmed, .unanswered:
            // No answer within the callback timeout, or an answer in the
            // background. Start once the connection has shown it is alive in
            // the foreground, so a deaf or suspended one never lifts.
            if wait.answeredPing, !isInBackground {
                startDeadline(&wait, connection)
            } else {
                wait.startsAtPing = true
            }
        case .rejected:
            // OGS isn't listening as this account, so no re-send can come.
            waits[connection] = nil
            return
        }
        waits[connection] = wait
    }

    /// A `net/pong` arrived on the connection. In the background it counts
    /// for nothing: only a pong after the return shows the socket survived.
    func connectionAnsweredPing(_ connection: UUID) {
        guard !isInBackground, var wait = waits[connection] else { return }
        wait.answeredPing = true
        if wait.startsAtPing, wait.deadline == nil { startDeadline(&wait, connection) }
        waits[connection] = wait
    }

    /// The socket closed or changed account, or its service went away:
    /// it can no longer show that a superchat ended.
    func connectionEnded(_ connection: UUID) {
        waits.removeValue(forKey: connection)?.deadline?.cancel()
    }

    /// The app left the foreground. A suspended socket can miss the re-send
    /// without closing first, and a deadline that came due during the
    /// suspension would run before the socket's buffered frames. So every
    /// deadline stops, and each wait OGS has answered starts again at its
    /// connection's first answered ping after the return. That pong comes
    /// after every frame OGS sent before it, and a socket the system
    /// dropped answers none and closes. A socket that survives the
    /// background never authenticates again, so its wait must not go.
    func enterBackground() {
        isInBackground = true
        for (connection, var wait) in waits {
            let wasAnswered = wait.deadline != nil || wait.startsAtPing
            wait.deadline?.cancel()
            wait.deadline = nil
            wait.answeredPing = false
            wait.startsAtPing = wasAnswered
            waits[connection] = wait
        }
    }

    /// The app is back in the foreground: each wait starts at its
    /// connection's next answered ping, or at OGS's answer if none came yet.
    func enterForeground() {
        isInBackground = false
    }

    private func markHeard(_ moderatorID: Int, accountID: Int) {
        for (connection, wait) in waits where wait.accountID == accountID {
            var wait = wait
            wait.awaiting.remove(moderatorID)
            if wait.awaiting.isEmpty {
                wait.deadline?.cancel()
                waits[connection] = nil
            } else {
                waits[connection] = wait
            }
        }
    }

    private func startDeadline(_ wait: inout ResendWait, _ connection: UUID) {
        wait.startsAtPing = false
        wait.deadline = scheduler.schedule(after: Self.resendWindow) { [weak self] in
            self?.resendWindowEnded(connection)
        }
    }

    private func resendWindowEnded(_ connection: UUID) {
        guard !isInBackground, let wait = waits.removeValue(forKey: connection),
              var cover = covers[wait.accountID] else { return }
        let time = now()
        var missedAny = false
        for index in cover.moderators.indices
        where cover.moderators[index].isOn && wait.awaiting.contains(cover.moderators[index].id) {
            cover.moderators[index].endedAt = time
            cover.moderators[index].endWasMissed = true
            endings[wait.accountID, default: [:]][cover.moderators[index].id] =
                SuperchatEnding(at: time, wasMissed: true)
            missedAny = true
        }
        guard missedAny else { return }
        if cover.isOn || cover.awaitsDone {
            covers[wait.accountID] = cover
        } else {
            // Every superchat ended unseen: no end card to dismiss.
            removeCover(for: wait.accountID)
            coverLiftedWithoutDone.send(wait.accountID)
        }
        save()
    }

    // MARK: What the cover does

    /// Done, from any window, once nothing is on.
    func done(accountID: Int) {
        guard let cover = covers[accountID], !cover.isOn else { return }
        removeCover(for: accountID)
        save()
    }

    /// Numbers held taps app-wide; only the latest runs when its cover lowers.
    func nextHoldTicket() -> Int {
        latestHoldTicket += 1
        return latestHoldTicket
    }

    func isLatestHold(_ ticket: Int) -> Bool { ticket == latestHoldTicket }

    private func removeCover(for accountID: Int) {
        covers[accountID] = nil
        for (connection, wait) in waits where wait.accountID == accountID {
            wait.deadline?.cancel()
            waits[connection] = nil
        }
    }

    private func save() {
        guard let preferences else { return }
        var saved = [Int: [SuperchatModerator]]()
        for (accountID, cover) in covers {
            let on = cover.moderators.filter(\.isOn)
            if !on.isEmpty { saved[accountID] = on }
        }
        if preferences[.superchatModeratorsByOGSAccountID] != saved {
            preferences[.superchatModeratorsByOGSAccountID] = saved
        }
    }
}

/// Lets one window's navigation wait while its account is covered. The
/// window's root makes one (SuperchatCover.swift).
final class NavigationHold {
    private let store: SuperchatStore
    private let covered: () -> Bool

    init(store: SuperchatStore, isCovered: @escaping () -> Bool) {
        self.store = store
        self.covered = isCovered
    }

    var isCovered: Bool { covered() }
    /// For a tap: app-wide, so only the latest one ever runs.
    func nextTicket() -> Int { store.nextHoldTicket() }
    func isLatest(_ ticket: Int) -> Bool { store.isLatestHold(ticket) }
}

/// What one window's cover shows (SuperchatCoverView). Pure, so
/// SurroundTests can check every state, stale windows included.
struct SuperchatCoverPresentation: Equatable {
    enum EndCard: Equatable {
        case none
        /// The selected moderator ended while another is still on.
        case endedLine
        /// Nothing is on: the end card with Done, in every window.
        case done
    }

    let moderator: SuperchatModerator
    let showsChips: Bool
    /// The window kept another account: no conversation, games or field.
    let isStale: Bool
    let endCard: EndCard

    var showsLiveGames: Bool { !isStale }
    var showsReplyField: Bool { !isStale }

    /// Nil only for an empty cover, which the store never keeps.
    init?(cover: SuperchatCover, selectedModeratorID: Int?, windowUserID: Int?, accountID: Int) {
        guard let first = cover.moderators.first else { return nil }
        moderator = cover.moderators.first { $0.id == selectedModeratorID } ?? first
        showsChips = cover.moderators.count > 1
        isStale = windowUserID != accountID
        endCard = cover.awaitsDone ? .done : (moderator.isOn ? .none : .endedLine)
    }

    /// Whether a rise focuses the reply field, and so moves VoiceOver to it.
    /// The mount and the content both ask.
    static func focusesReply(isCompactHeight: Bool, isStale: Bool) -> Bool {
        !isCompactHeight && !isStale
    }
}

extension SettingKey {
    /// Superchats still on, per OGS account. Kept on sign-out: the next
    /// sign-in as that account covers again until OGS re-sends or not.
    static var superchatModeratorsByOGSAccountID: SettingKey<[Int: [SuperchatModerator]]> {
        .init(name: "superchatModeratorsByOGSAccountID", encoded: true, defaultValue: [:])
    }
}
