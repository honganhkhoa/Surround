//
//  LowTimeHapticWatcher.swift
//  Surround
//
//  One warning haptic when another of the user's live games, on their move,
//  falls through ActivityModel.lowTimeHapticThreshold seconds to timeout: a
//  clock they can't see. In byo-yomi only the last period counts: entering
//  it with that much left or less is a fall, and so is a turn that starts
//  in it. It reads the window's OGSService on the shared one-second timer
//  that also ticks the service's clocks, never a view, so it works wherever
//  the user is in the window. A fall counts only between two reads with the
//  socket connected that both found the user's own clock running on their
//  move, or in byo-yomi a first read on the opponent's move. So a window
//  that opens with less time left, or whose socket was down, plays nothing.
//  A fall plays nothing for the game on screen, under the moderator cover or
//  with Settings › Haptics off, and leaves the game to play at a later
//  fall. Once its haptic has played, a game never plays again. Nothing
//  plays on the Mac, and AppAnnouncer plays one copy for every window, from
//  the window the user is in. One per window, held by NavigationService;
//  MainView attaches it. Main thread by convention, like its owner.
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

    /// The games whose haptic played, so none plays twice.
    private(set) var doneGameIDs = Set<Int>()
    /// Each game's seconds to timeout at the last read, as `timeToCompare`
    /// gives them, kept only while the socket is connected.
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
            let playing = record(Self.liveGames(of: ogs), accountID: ogs.user?.id,
                                 isConnected: ogs.socketStatus == .connected) { gameID in
                !isCovered() && preferences[.hapticsFeedback] != false && !gamesOnScreen().contains(gameID)
            }
            for gameID in playing {
                post(AppAnnouncement(.lowTime(gameID), audience: .frontmostWindow, haptic: .warning))
            }
        }
    }

    /// One read of the user's live games. Returns the games whose haptic
    /// plays now: each fell through the threshold since the last read, and
    /// `plays` lets it play. Those are done from now. A fall that doesn't
    /// play keeps its time, so the next read isn't a fall too, and leaves
    /// the game to play at a later one. Another account starts over.
    /// - Parameter plays: Whether a game's fall can play now; by default
    ///   every fall can.
    func record(_ games: [ActivityModel.LiveGame], accountID: Int?, isConnected: Bool,
                plays: (Int) -> Bool = { _ in true }) -> [Int] {
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
        var playing = [Int]()
        for game in games where !doneGameIDs.contains(game.id) {
            guard let left = Self.timeToCompare(game) else { continue }
            if let previous = lastTimeLeft[game.id], previous > threshold, left <= threshold, plays(game.id) {
                doneGameIDs.insert(game.id)
                playing.append(game.id)
            } else {
                timeLeft[game.id] = left
            }
        }
        lastTimeLeft = timeLeft
        return playing
    }

    /// What a read compares with the threshold: the seconds to timeout while
    /// the user's own clock runs on their move, or nil, which leaves the game
    /// out until a read can count it. In byo-yomi only the last period
    /// counts. Until it starts, and on the opponent's move, the game reads as
    /// above the threshold, so entering the last period with the threshold or
    /// less left is a fall, and so is a turn that starts in it. Other clocks
    /// fall only while they run on the user's move.
    private static func timeToCompare(_ game: ActivityModel.LiveGame) -> TimeInterval? {
        guard game.isYourMove else { return game.usesByoyomi ? .infinity : nil }
        guard game.isClockRunning, let left = game.timeUntilTimeout else { return nil }
        return game.usesByoyomi && !game.isInLastByoyomiPeriod ? .infinity : left
    }

    /// The user's live games as Activity reads them, from their own side.
    private static func liveGames(of ogs: OGSService) -> [ActivityModel.LiveGame] {
        guard let user = ogs.user else { return [] }
        return ogs.liveGames.compactMap { ActivityModel.LiveGame(game: $0, userID: user.id) }
    }
}
