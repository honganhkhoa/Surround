//
//  StartedGamesRecorder.swift
//  Surround
//
//  The live games that start while a window is open, for the in-game
//  control's "Game started" (ActivityModel.gameControl). A game counts from
//  when it first appears among the window's live games until the window
//  shows or opens it, or for ActivityModel.startedLeadDuration. The games of
//  the window's first overview load, and of the first load after an account
//  change, were already running, so they never count. One per window, held
//  by NavigationService; MainView attaches it. Main thread by convention,
//  like its owner.
//

import Combine
import Foundation

final class StartedGamesRecorder {
    /// What the recorder follows, each publisher sending its current value
    /// first: a window's OGSService and NavigationService, or a test's
    /// subjects.
    struct Feed {
        /// The signed-in account.
        var accountID: AnyPublisher<Int?, Never>
        /// An overview load is in progress. Each load sends true as it starts
        /// and false as it ends.
        var isLoadingOverview: AnyPublisher<Bool, Never>
        /// The user's live games.
        var liveGameIDs: AnyPublisher<Set<Int>, Never>
        /// The games the window shows or is about to open.
        var openedGameIDs: AnyPublisher<Set<Int>, Never>
    }

    /// When the window's live games so far are taken as already running.
    private enum Seeding {
        /// When the load in progress ends, or at once if none is.
        case atLoadEnd
        /// After an account change a load that was already running would
        /// list the old account's games, so a new one has to start first.
        case atNextLoad
        case seeded
    }

    private var seeding = Seeding.atLoadEnd
    /// Every live game seen since the seed, so none counts twice.
    private var knownGameIDs = Set<Int>()
    /// When each game that counts appeared, in seconds since 1970.
    private var appeared = [Int: TimeInterval]()
    private var announcedGameIDs = Set<Int>()
    private var latestLiveGameIDs = Set<Int>()
    private var latestOpenedGameIDs = Set<Int>()
    private var now: () -> TimeInterval = { Date().timeIntervalSince1970 }
    private var subscriptions = Set<AnyCancellable>()

    /// The games that started in the last `ActivityModel.startedLeadDuration`
    /// without this window showing or opening them, by when each appeared,
    /// in seconds since 1970, as `ActivityModel.Input.startedGames` takes
    /// them.
    var startedGames: [Int: TimeInterval] {
        let time = now()
        return appeared.filter { time - $0.value < ActivityModel.startedLeadDuration }
    }

    /// Follows the window's service and navigation, from nothing.
    func attach(ogs: OGSService, navigation: NavigationService,
                now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        attach(Feed(
            accountID: ogs.$user.map { $0?.id }.eraseToAnyPublisher(),
            isLoadingOverview: ogs.$isLoadingOverview.eraseToAnyPublisher(),
            liveGameIDs: ogs.$liveGames.map { Set($0.compactMap(\.ogsID)) }.eraseToAnyPublisher(),
            openedGameIDs: Self.openedGameIDs(in: navigation)
        ), now: now)
    }

    /// Follows `feed`, from nothing.
    func attach(_ feed: Feed, now: @escaping () -> TimeInterval) {
        subscriptions = []
        self.now = now
        startOver(.atLoadEnd)
        // The live games first, so a seed at once takes them.
        feed.liveGameIDs
            .sink { [weak self] in self?.receiveLiveGames($0) }
            .store(in: &subscriptions)
        feed.openedGameIDs
            .sink { [weak self] in self?.receiveOpenedGames($0) }
            .store(in: &subscriptions)
        feed.accountID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.startOver(.atNextLoad) }
            .store(in: &subscriptions)
        feed.isLoadingOverview
            .sink { [weak self] in self?.receiveLoading($0) }
            .store(in: &subscriptions)
    }

    /// Whether "Game started" is still to be said for `gameID`: true the
    /// first time each game is asked about, so the window says it once.
    func claimAnnouncement(for gameID: Int) -> Bool {
        announcedGameIDs.insert(gameID).inserted
    }

    /// The games a window shows or is about to open: the user's own live
    /// games a visible Game Detail shows, a pending open, and Home's game.
    static func openedGameIDs(in navigation: NavigationService) -> AnyPublisher<Set<Int>, Never> {
        Publishers.CombineLatest3(
            navigation.$gameDetailNotificationContexts.map(NavigationService.ownLiveGameIDs(in:)),
            navigation.$pendingGameOpen.map { $0?.ogsGameID },
            navigation.$home.map { $0.activeGame?.ogsID }
        )
        .map { shown, pending, home in shown.union([pending, home].compactMap { $0 }) }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }

    // MARK: Following

    private func startOver(_ next: Seeding) {
        seeding = next
        knownGameIDs = []
        appeared = [:]
        announcedGameIDs = []
    }

    private func receiveLoading(_ isLoading: Bool) {
        switch (seeding, isLoading) {
        case (.atNextLoad, true):
            seeding = .atLoadEnd
        case (.atLoadEnd, false):
            // Silently: these were running before the window heard of them.
            knownGameIDs = latestLiveGameIDs
            seeding = .seeded
        default:
            break
        }
    }

    private func receiveLiveGames(_ gameIDs: Set<Int>) {
        latestLiveGameIDs = gameIDs
        guard seeding == .seeded else { return }
        let time = now()
        for gameID in gameIDs.subtracting(knownGameIDs) where !latestOpenedGameIDs.contains(gameID) {
            appeared[gameID] = time
        }
        knownGameIDs.formUnion(gameIDs)
        appeared = appeared.filter { time - $0.value < ActivityModel.startedLeadDuration }
    }

    private func receiveOpenedGames(_ gameIDs: Set<Int>) {
        latestOpenedGameIDs = gameIDs
        for gameID in gameIDs {
            appeared[gameID] = nil
        }
    }
}

extension NavigationService {
    /// The user's own unfinished live games that a visible Game Detail in
    /// this window shows.
    var ownLiveGameIDsOnScreen: Set<Int> {
        Self.ownLiveGameIDs(in: gameDetailNotificationContexts)
    }

    static func ownLiveGameIDs(in contexts: [UUID: GameDetailNotificationContext]) -> Set<Int> {
        Set(contexts.values.compactMap { context in
            guard case .OGS(let id)? = context.ownLiveGame else { return nil }
            return id
        })
    }
}
