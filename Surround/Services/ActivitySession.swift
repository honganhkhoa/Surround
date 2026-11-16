//
//  ActivitySession.swift
//  Surround
//
//  When each of the user's own waiting items was first seen in this run of
//  the app. Activity lists waiting items oldest first, and a challenge sent
//  to another player carries no creation time, so its first sighting stands
//  in. Main thread only.
//

import Combine
import Foundation

enum ActivitySession {
    /// When each waiting item was first seen, in seconds since 1970, keyed
    /// by `ActivityModel.Waiting.id`.
    private(set) static var firstSeen: [String: TimeInterval] = [:]

    /// Keeps the first time each id was seen.
    static func record(_ ids: some Sequence<String>, at now: TimeInterval) {
        for id in ids where firstSeen[id] == nil {
            firstSeen[id] = now
        }
    }

    #if DEBUG
    static func reset() {
        firstSeen = [:]
    }
    #endif
}

/// Records one service's waiting items as they arrive, so an item without a
/// creation time sorts from when it appeared, not from when a list first
/// showed it.
final class ActivityFirstSeenObserver {
    private var subscription: AnyCancellable?

    init(ogs: OGSService, now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        typealias WaitingID = ActivityModel.WaitingID
        subscription = Publishers.CombineLatest4(
            ogs.$challengesSent,
            ogs.$openChallengeSentById,
            ogs.$autoMatchEntryById,
            ogs.$participatingRengoChallengeById.combineLatest(ogs.$hostingRengoChallengeById)
        )
        .sink { sent, open, quickMatch, rengo in
            var ids = sent.map { WaitingID.sentChallenge($0.id) }
            ids += open.keys.map(WaitingID.openChallenge)
            ids += quickMatch.values.map { WaitingID.quickMatch($0.uuid) }
            ids += rengo.0.keys.map(WaitingID.rengo)
            ids += rengo.1.keys.map(WaitingID.rengo)
            ActivitySession.record(ids, at: now())
        }
    }
}
