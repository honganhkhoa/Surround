//
//  SeekGraphSendHold.swift
//  Surround
//
//  One challenge send's own hold on the seek graph.
//

import Combine
import Foundation

/// An open challenge reaches the waiting list, and a live one its keepalive,
/// only through the seek graph, which the screen that sent it may already
/// have released. A hold keeps the seek graph from the moment a send starts,
/// so it sees the challenge even if it is added and removed before the
/// request returns. It ends when this send's challenge has appeared (among
/// those sent, or, for Rengo, those hosted or joined), when the send fails
/// or is cancelled, when a direct challenge is sent, when the account
/// changes, or after a long timeout as a last resort. Once the challenge has
/// appeared, the service keeps the seek graph for it. Each send holds its own
/// subscription, so one ending never releases another's, and no screen owns
/// a hold: they outlive the screen that sent them.
final class SeekGraphSendHold {
    static let defaultTimeout: TimeInterval = 10 * 60

    /// Holds still waiting; each removes itself when it ends.
    private static var active = [ObjectIdentifier: SeekGraphSendHold]()

    private let service: OGSService
    private var observers = Set<AnyCancellable>()
    private var seenChallengeIDs = Set<Int>()
    private var awaitedChallengeID: Int?
    private(set) var isHeld = true

    init(service: OGSService, timeout: TimeInterval = SeekGraphSendHold.defaultTimeout) {
        self.service = service
        Self.active[ObjectIdentifier(self)] = self
        service.subscribeToSeekGraph()
        // Published collections report every change in order, so a challenge
        // added and removed within one seek-graph event is still seen.
        Publishers.Merge3(
            service.$openChallengeSentById.map { Set($0.keys) },
            service.$hostingRengoChallengeById.map { Set($0.keys) },
            service.$participatingRengoChallengeById.map { Set($0.keys) }
        )
        .sink { [weak self] ids in self?.note(ids) }
        .store(in: &observers)
        service.$user
            .map { $0?.id }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.release() }
            .store(in: &observers)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.release()
        }
    }

    /// The request returned this challenge. A direct challenge never appears
    /// in the seek graph, so only an open one is awaited.
    func challengeSent(id: Int, isOpen: Bool) {
        guard isHeld else { return }
        guard isOpen else {
            release()
            return
        }
        awaitedChallengeID = id
        if seenChallengeIDs.contains(id) {
            release()
        }
    }

    func release() {
        guard isHeld else { return }
        isHeld = false
        observers.removeAll()
        service.unsubscribeFromSeekGraphWhenDone()
        Self.active[ObjectIdentifier(self)] = nil
    }

    private func note(_ ids: Set<Int>) {
        seenChallengeIDs.formUnion(ids)
        if let awaitedChallengeID, seenChallengeIDs.contains(awaitedChallengeID) {
            // Published values arrive before the collection is set. Release
            // once it is, so the service sees the challenge it now keeps the
            // seek graph for.
            DispatchQueue.main.async { [weak self] in self?.release() }
        }
    }
}
