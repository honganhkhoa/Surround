//
//  LowTimeHapticWatcher.swift
//  Surround
//
//  One warning haptic when another of the user's live games, on their move,
//  falls through ActivityModel.lowTimeHapticThreshold seconds to timeout: a
//  clock they can't see. It reads the window's OGSService on the shared
//  one-second timer that also ticks the service's clocks, never a view, so
//  it works wherever the user is in the window. A fall counts only between
//  two reads that both found the user's own clock running on their move
//  with the socket connected, so a window that opens with less time left,
//  or whose socket was down, plays nothing. Each game plays it at most once.
//  Nothing plays for the game on screen, under the moderator cover, with
//  Settings › Haptics off or on the Mac, and AppAnnouncer plays one copy for
//  every window, from the window the user is in. One per window, held by
//  NavigationService; MainView attaches it. Main thread by convention, like
//  its owner.
//

import Combine
import Foundation

final class LowTimeHapticWatcher {
    /// The shared one-second timer, on the main run loop, as the service's
    /// clocks read it.
    static var sharedTicks: AnyPublisher<Date, Never> {
        TimeUtilities.shared.timer.receive(on: RunLoop.main).eraseToAnyPublisher()
    }

    /// The Mac plays no haptic for notices.
    static var isMac: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    /// The games whose fall was seen, played or not, so none plays twice.
    private(set) var doneGameIDs = Set<Int>()
    /// Each game's seconds to timeout at the last read, kept only while its
    /// clock ran on the user's move with the socket connected.
    private var lastTimeLeft = [Int: TimeInterval]()
    private var accountID: Int?
    private var subscription: AnyCancellable?

    /// Reads the window's service on each tick, from nothing.
    /// - Parameters:
    ///   - post: Posts once per app on behalf of the window:
    ///     `NavigationService.announce(_:)` in the app.
    ///   - isCovered: The window's account is under the moderator cover.
    ///   - gamesOnScreen: The user's own live games that a visible Game
    ///     Detail in the window shows, whose clocks the user can see.
    ///   - preferences: Where Settings › Haptics is kept.
    ///   - isMac: Nothing is read or played on the Mac.
    func attach(
        ogs: OGSService,
        post: @escaping (AppAnnouncement) -> Void,
        isCovered: @escaping () -> Bool,
        gamesOnScreen: @escaping () -> Set<Int>,
        ticks: AnyPublisher<Date, Never> = LowTimeHapticWatcher.sharedTicks,
        preferences: UserDefaults = userDefaults,
        isMac: Bool = LowTimeHapticWatcher.isMac
    ) {
        subscription = nil
        doneGameIDs = []
        lastTimeLeft = [:]
        accountID = nil
        guard !isMac else { return }
        subscription = ticks.sink { [weak self, weak ogs] _ in
            guard let self, let ogs else { return }
            let fallen = record(Self.liveGames(of: ogs), accountID: ogs.user?.id,
                                isConnected: ogs.socketStatus == .connected)
            // Each is done now, whether or not it plays.
            guard !fallen.isEmpty, !isCovered(), preferences[.hapticsFeedback] != false else { return }
            let onScreen = gamesOnScreen()
            for gameID in fallen where !onScreen.contains(gameID) {
                post(AppAnnouncement(.lowTime(gameID), audience: .frontmostWindow, haptic: .warning))
            }
        }
    }

    /// One read of the user's live games. Returns the games that fell
    /// through the threshold since the last read, which are done from now.
    /// Another account starts over.
    func record(_ games: [ActivityModel.LiveGame], accountID: Int?, isConnected: Bool) -> [Int] {
        if accountID != self.accountID {
            self.accountID = accountID
            doneGameIDs = []
            lastTimeLeft = [:]
        }
        guard isConnected else {
            // A fall while the socket is down is never seen, even once it's back.
            lastTimeLeft = [:]
            return []
        }
        let threshold = ActivityModel.lowTimeHapticThreshold
        var timeLeft = [Int: TimeInterval]()
        var fallen = [Int]()
        for game in games where game.isYourMove && game.isClockRunning && !doneGameIDs.contains(game.id) {
            guard let left = game.timeUntilTimeout else { continue }
            if let previous = lastTimeLeft[game.id], previous > threshold, left <= threshold {
                doneGameIDs.insert(game.id)
                fallen.append(game.id)
            } else {
                timeLeft[game.id] = left
            }
        }
        lastTimeLeft = timeLeft
        return fallen
    }

    /// The user's live games as Activity reads them, from their own side.
    private static func liveGames(of ogs: OGSService) -> [ActivityModel.LiveGame] {
        guard let user = ogs.user else { return [] }
        return ogs.liveGames.compactMap { ActivityModel.LiveGame(game: $0, userID: user.id) }
    }
}
