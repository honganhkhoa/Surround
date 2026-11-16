//
//  ActivityLastKnown.swift
//  Surround
//
//  The user's own open challenges and Rengo challenges as the seek graph last
//  listed them while the socket was connected. Closing the socket clears the
//  service's own copies, which Home's count and the keepalive rely on, and
//  reconnecting clears them again until the seek graph lists, so Activity
//  reads this copy instead until then and its rows stay as last known. One
//  per window, held by NavigationService. Main thread by convention, like
//  its owner.
//

import Combine
import Foundation

final class ActivityLastKnown: ObservableObject {
    /// The seek graph's rows of the user's own, named as OGSService names
    /// them.
    struct OpenChallenges: Equatable {
        var openChallengeSentById: [Int: OGSSeekgraphChallenge] = [:]
        var participatingRengoChallengeById: [Int: OGSSeekgraphChallenge] = [:]
        var hostingRengoChallengeById: [Int: OGSSeekgraphChallenge] = [:]
    }

    /// The latest rows the service listed while connected: the seek graph's
    /// latest listing, or what the service held when a grace ended.
    @Published private(set) var copy = OpenChallenges()
    /// After a reconnect the service lists nothing until the seek graph's
    /// first update, a round trip later, or never while nothing subscribes
    /// to it. Until that update, or for at most `reconnectGrace`, the copy
    /// stands in, so the rows don't blink out as the socket comes back.
    /// Either way the copy then takes what the service lists, so a later
    /// drop doesn't bring back a challenge that went while offline.
    @Published private(set) var awaitsUpdate = false
    static let reconnectGrace: TimeInterval = 10

    private let scheduler: OGSWebsocketScheduling
    private weak var ogs: OGSService?
    private var subscriptions = Set<AnyCancellable>()
    private var grace: Cancellable?

    init(scheduler: OGSWebsocketScheduling = OGSMainQueueWebsocketScheduler.shared) {
        self.scheduler = scheduler
    }

    /// Follows the window's service. The copy starts from what the service
    /// lists now, whatever its connection, since that is the best known.
    func attach(ogs: OGSService) {
        self.ogs = ogs
        subscriptions = []
        update(Self.listed(by: ogs))
        if !Self.isConnected(ogs), !awaitsUpdate { awaitsUpdate = true }
        // Only the seek graph's listing counts. The service also empties
        // these rows when the socket closes, and again before it asks the
        // seek graph after a reconnect, and neither says they went.
        Publishers.CombineLatest4(
            ogs.$openChallengeSentById,
            ogs.$participatingRengoChallengeById,
            ogs.$hostingRengoChallengeById,
            ogs.$seekGraphHasListed
        )
        .dropFirst()
        .sink { [weak self, weak ogs] sent, participating, hosting, hasListed in
            guard let self, let ogs, hasListed, Self.isConnected(ogs) else { return }
            update(OpenChallenges(
                openChallengeSentById: sent,
                participatingRengoChallengeById: participating,
                hostingRengoChallengeById: hosting
            ))
            endGrace()
        }
        .store(in: &subscriptions)
        ogs.$socketStatus
            .dropFirst()
            .sink { [weak self] status in
                guard let self else { return }
                if status == .connected {
                    // The rows may already be back; if not, wait for them.
                    guard awaitsUpdate, grace == nil else { return }
                    grace = scheduler.schedule(after: Self.reconnectGrace) { [weak self] in
                        self?.graceEnded()
                    }
                } else {
                    grace?.cancel()
                    grace = nil
                    if !awaitsUpdate { awaitsUpdate = true }
                }
            }
            .store(in: &subscriptions)
    }

    /// What Activity lists: the service's own rows while it is connected and
    /// has listed them since reconnecting, and the copy otherwise.
    func openChallenges(live ogs: OGSService) -> OpenChallenges {
        Self.isConnected(ogs) && !awaitsUpdate ? Self.listed(by: ogs) : copy
    }

    /// Forgets the copy, for an account change.
    func reset() {
        endGrace()
        update(OpenChallenges())
    }

    private func endGrace() {
        grace?.cancel()
        grace = nil
        if awaitsUpdate { awaitsUpdate = false }
    }

    /// No listing came in time. Activity now lists what the service lists,
    /// and while connected the copy takes it too.
    private func graceEnded() {
        if let ogs, Self.isConnected(ogs) {
            update(Self.listed(by: ogs))
        }
        endGrace()
    }

    /// Connected, with authentication sent. The service learns of a closed
    /// socket one main-queue turn late, but clears the seek graph at once:
    /// `socketStatus` still says connected while the rows go, and only the
    /// socket's own authentication is already off. The seek graph lists
    /// nothing before authentication either.
    private static func isConnected(_ ogs: OGSService) -> Bool {
        ogs.socketStatus == .connected && ogs.isWebsocketAuthenticated
    }

    private static func listed(by ogs: OGSService) -> OpenChallenges {
        OpenChallenges(
            openChallengeSentById: ogs.openChallengeSentById,
            participatingRengoChallengeById: ogs.participatingRengoChallengeById,
            hostingRengoChallengeById: ogs.hostingRengoChallengeById
        )
    }

    private func update(_ latest: OpenChallenges) {
        if copy != latest {
            copy = latest
        }
    }
}
