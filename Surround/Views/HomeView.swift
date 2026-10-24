//
//  HomeView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 7/10/20.
//

import SwiftUI
import Combine

/// Gives the same OGS game a distinct identity in each home-screen section.
/// A game can briefly exist in both an active projection and finished history
/// while the server-side transition is settling; those rows must not share a
/// SwiftUI identity inside the same lazy grid.
private struct HomeGameEntry: Identifiable {
    enum Context: Hashable {
        case live
        case userTurn
        case opponentTurn
        case history
    }

    struct ID: Hashable {
        let context: Context
        let gameID: GameID
    }

    let game: Game
    let context: Context

    var id: ID {
        ID(context: context, gameID: game.ID)
    }
}

private enum RecentFinishedGamesLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    @Environment(\.iPadTabContext) private var iPadTabContext
    #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0)
    @Environment(\.duoTabContext) private var duoTabContext
    #endif
    @Environment(\.surroundAllowsRemoteActivity) private var allowsRemoteActivity
    @Environment(\.surroundAllowsLocalPersistence) private var allowsLocalPersistence
    @Environment(\.openPlayerProfile) private var openPlayerProfile
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    /// Home wears the theme Game Detail shows.
    @AppStorage(SettingKey<String>.gameTheme.name, store: userDefaults)
    private var gameThemeID = SurroundTheme.standard.rawValue
    
    @State var displayMode: GameCell.CellDisplayMode

    @State private var openingGameRequestID: UUID?
    @State private var failedGameOpen: PendingGameOpen?

    @State var recentFinishedGames: [Game] = []
    @State var recentFinishedCancellable: AnyCancellable?
    @State private var recentFinishedLoadState: RecentFinishedGamesLoadState
    @State private var recentFinishedRequestID: UUID?
    @State private var hasSimulatedRecentFinishedGamesFailure = false
    @StateObject private var historyPreviewLoader = FinishedGamePreviewLoader()
    @State private var isVisible = false
    /// Home's own width: beside the sidebar wherever one is shown.
    @State private var width: CGFloat = 0
    @EnvironmentObject private var stackRouter: StackRouter
    /// Saved setups being sent from the star menu, one request each.
    @State private var preferredSettingRequests: [OGSChallengeTemplate: AnyCancellable] = [:]
    @State private var preferredSettingsStartsWithNewSetting = false
    
    init(previewGames: [Game] = []) {
        _recentFinishedGames = State(initialValue: previewGames)
        _recentFinishedLoadState = State(
            initialValue: previewGames.isEmpty ? .idle : .loaded
        )
        #if os(iOS)
        if SurroundUITestContract.isCapturingAppStoreScreenshots {
            _displayMode = State(initialValue: .compact)
            return
        }
        if let savedDisplayMode = userDefaults[.homeViewDisplayMode] {
            _displayMode = State(initialValue: GameCell.CellDisplayMode(rawValue: savedDisplayMode) ?? .full)
        } else {
            if UIDevice.current.userInterfaceIdiom == .phone {
                _displayMode = State(initialValue: .compact)
            } else {
                _displayMode = State(initialValue: .full)
            }
        }
        #else
        _displayMode = State(initialValue: .full)
        #endif
    }

    func showGameDetail(game: Game, showsCarousel: Bool = true) {
        print("Opening game \(game)")
        nav.home.activeGameShowsCarousel = showsCarousel
        nav.home.activeGame = game
    }

    /// Reloads the most recent finished games.
    ///
    /// Called whenever the home screen appears and whenever a game leaves the
    /// active list (i.e. it just finished), so a game shows up here as soon as
    /// it ends rather than only after a relaunch. Only guards against
    /// overlapping requests, not against refetching.
    func loadRecentFinishedGames() {
        guard recentFinishedLoadState != .loading else {
            return
        }
        guard allowsRemoteActivity else {
            recentFinishedLoadState = .loading
            #if DEBUG && MAIN_APP
            if SurroundUITestContract.simulatesHomeHistoryFailureOnce
                && !hasSimulatedRecentFinishedGamesFailure {
                hasSimulatedRecentFinishedGamesFailure = true
                recentFinishedGames = []
                recentFinishedLoadState = .failed
                recentFinishedRequestID = nil
                return
            }
            // Offline UI tests can carry a complete, already-hydrated history
            // snapshot. Install it directly so this path remains deterministic
            // without losing the history section that the fixtures verify.
            if SurroundUITestContract.isEnabled {
                if SurroundUITestContract.simulatesHomeHistoryFailureOnce {
                    let retryFixture = TestData.Scored19x19Korean
                    precondition(
                        retryFixture.ogsID
                            == SurroundUITestContract
                                .homeHistoryRetryFixtureGameID
                    )
                    recentFinishedGames = [retryFixture]
                } else {
                    recentFinishedGames = Array(
                        ogs.offlineUITestFinishedGames.prefix(10)
                    )
                }
            }
            #endif
            recentFinishedLoadState = .loaded
            recentFinishedRequestID = nil
            return
        }
        guard ogs.isLoggedIn else {
            return
        }
        guard let playerId = ogs.user?.id else {
            recentFinishedLoadState = .failed
            return
        }
        let requestID = UUID()
        recentFinishedLoadState = .loading
        recentFinishedRequestID = requestID
        let reusableGames = Dictionary(
            recentFinishedGames.compactMap { game in game.ogsID.map { ($0, game) } },
            uniquingKeysWith: { first, _ in first }
        )
        recentFinishedCancellable = ogs.fetchFinishedGames(
            playerId: playerId,
            page: 1,
            pageSize: 10,
            reusing: reusableGames
        )
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    guard recentFinishedRequestID == requestID else {
                        return
                    }
                    recentFinishedRequestID = nil
                    recentFinishedCancellable = nil
                    guard ogs.user?.id == playerId else {
                        return
                    }
                    switch completion {
                    case .finished:
                        if recentFinishedLoadState == .loading {
                            recentFinishedLoadState = .loaded
                        }
                    case .failure:
                        recentFinishedLoadState = .failed
                    }
                },
                receiveValue: { result in
                    // Drop a response that belongs to whoever was signed in when
                    // the request went out — otherwise a user switch mid-flight
                    // installs the previous account's history.
                    guard recentFinishedRequestID == requestID,
                          ogs.user?.id == playerId else {
                        return
                    }
                    recentFinishedGames = result.games
                    recentFinishedLoadState = .loaded
                }
            )
    }

    /// Clears history state that belongs to the previous account and reloads.
    func resetRecentFinishedGames() {
        historyPreviewLoader.cancel()
        recentFinishedCancellable?.cancel()
        recentFinishedCancellable = nil
        recentFinishedRequestID = nil
        recentFinishedLoadState = .idle
        recentFinishedGames = []
        loadRecentFinishedGames()
    }

    // MARK: - Sections

    private var bandColumns: Int { HomeLayout.compactColumns(for: width) }
    private var theme: SurroundTheme { SurroundTheme.current(storedID: gameThemeID) }
    /// Section bands: full-width headers with one card per game.
    private var usesBands: Bool { bandColumns > 1 }
    private var margin: CGFloat { usesBands ? HomeLayout.bandMargin : HomeLayout.listMargin }

    /// Games whose clock gives no speed are listed by turn, after the timed
    /// ones, so no game ever drops out of Home. A turn includes accepting
    /// stone removal, as in the correspondence sections.
    private var userTurnGames: [Game] {
        ogs.sortedActiveCorrespondenceGamesOnUserTurn + ogs.unclassifiedActiveGames.filter { ogs.isOnUserTurn(game: $0) }
    }

    private var opponentTurnGames: [Game] {
        ogs.sortedActiveCorrespondenceGamesNotOnUserTurn + ogs.unclassifiedActiveGames.filter { !ogs.isOnUserTurn(game: $0) }
    }

    private var hasActiveItems: Bool {
        !ogs.challengesReceived.isEmpty || !ogs.liveGames.isEmpty
            || !userTurnGames.isEmpty || !opponentTurnGames.isEmpty
    }

    private func sectionHeader<Trailing: View>(
        _ title: String, count: Int? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: title)
                    .font(.title3.bold())
                if let count {
                    Text(verbatim: count.formatted())
                        .modifier(HomeSecondaryText())
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            // Headings scroll across the scene's brightest and darkest details.
            .modifier(HomeSceneLegibility())
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }
            trailing()
                .modifier(HomeSceneLegibility())
        }
        .padding(.horizontal, 4)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    /// One section's games: a grouped panel in one column, or a card per
    /// game in bands. Large mode always gives each tile its own card.
    @ViewBuilder
    private func gameGrid<Item: Identifiable, Cell: View>(
        _ items: [Item], large: Bool = false, @ViewBuilder cell: @escaping (Item, Bool) -> Cell
    ) -> some View {
        let columns = large ? HomeLayout.largeColumns(for: width, margin: margin) : bandColumns
        let gridItems = Array(repeating: GridItem(.flexible(), spacing: HomeLayout.columnSpacing, alignment: .top),
                              count: columns)
        if columns == 1 && !large {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    cell(item, index > 0)
                }
            }
            .modifier(HomeCard())
        } else {
            LazyVGrid(columns: gridItems, spacing: HomeLayout.rowSpacing) {
                ForEach(items) { item in
                    cell(item, false)
                        .modifier(HomeCard())
                }
            }
        }
    }

    @ViewBuilder
    private func gameCell(_ entry: HomeGameEntry, showsSeparator: Bool) -> some View {
        let identifier = SurroundUITestContract.AccessibilityID.homeGame(entry.game)
        if displayMode == .full {
            HomeGameTile(game: entry.game, opensGame: { showGameDetail(game: entry.game) },
                         navigationAccessibilityIdentifier: identifier)
        } else {
            HomeGameRow(game: entry.game, opensGame: { showGameDetail(game: entry.game) },
                        navigationAccessibilityIdentifier: identifier, showsSeparator: showsSeparator)
        }
    }

    /// A section of active games; Your move and Their move keep their
    /// heading with a note when they are empty, so the two read as a pair.
    @ViewBuilder
    private func gameSection(
        _ title: String, games: [Game], context: HomeGameEntry.Context, emptyText: String? = nil
    ) -> some View {
        if !games.isEmpty || emptyText != nil {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(title, count: games.isEmpty ? nil : games.count)
                if games.isEmpty, let emptyText {
                    Text(verbatim: emptyText)
                        .font(.subheadline)
                        .modifier(HomeSecondaryText())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                        .padding(.vertical, 28)
                        .modifier(HomeCard())
                } else {
                    gameGrid(games.map { HomeGameEntry(game: $0, context: context) },
                             large: displayMode == .full) { entry, separated in
                        gameCell(entry, showsSeparator: separated)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.homeSection(context.sectionID))
        }
    }

    /// Quick Match searches and pending Rengo games share one card.
    @ViewBuilder
    private var searchingCard: some View {
        if ogs.waitingGames > 0 || ogs.pendingRengoGames > 0 {
            Button(action: { nav.main.showWaitingGames = true }) {
                HStack(spacing: 12) {
                    Group {
                        if reduceMotion {
                            Image(systemName: "hourglass")
                        } else {
                            ProgressView()
                        }
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        if ogs.waitingGames > 0 {
                            Text(
                                ogs.waitingGames == 1
                                    ? String(localized: "Searching for a game")
                                    : String(localized: "Searching for \(ogs.waitingGames) games")
                            )
                            .font(.subheadline.bold())
                        }
                        if ogs.pendingRengoGames > 0 {
                            Text("\(ogs.pendingRengoGames) pending Rengo games ", comment: "HomeView - vary for plural")
                                .font(.subheadline)
                                .modifier(HomeSecondaryText())
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.bold())
                        .modifier(HomeSecondaryText())
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
                .modifier(HomeCard())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
    }

    /// The first load: placeholder rows where the games will be.
    private var firstLoadView: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(String(localized: "Your move", comment: "Game\nHomeview"))
                .redacted(reason: .placeholder)
            gameGrid((0..<3).map { HomeSkeletonEntry(id: $0) }) { _, separated in
                HomeSkeletonRow(showsSeparator: separated)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading your games", comment: "Homeview - VoiceOver: Home is loading for the first time"))
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.homeSkeleton)
    }

    /// No active games: one message and one way to start.
    private var firstRunView: some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                Text("No active games")
                    .font(.title2.bold())
                Text("Start a game, and it will show up here.", comment: "Homeview - first run, when the user has no active games")
                    .modifier(HomeSecondaryText())
                    .multilineTextAlignment(.center)
            }
            .modifier(HomeSceneLegibility())
            Button(action: { nav.home.showingNewGameView = true }) {
                Label("New game", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
            }
            .buttonStyle(HomeActionButtonStyle())
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.top, 72)
        .padding(.bottom, 24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.homeFirstRun)
    }

    private var challengesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(String(localized: "Challenges received", comment: "Homeview"),
                          count: ogs.challengesReceived.count)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: HomeLayout.columnSpacing, alignment: .top),
                                     count: bandColumns),
                      spacing: HomeLayout.rowSpacing) {
                ForEach(ogs.challengesReceived) { challenge in
                    ChallengeCell(challenge: challenge)
                        .padding()
                        .modifier(HomeCard())
                }
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(String(localized: "Game history", comment: "Homeview")) {
                Button(action: { nav.home.showingGameHistory = true }) {
                    HStack(spacing: 4) {
                        Text("View full history", comment: "Homeview")
                        Image(systemName: "chevron.forward")
                            .font(.footnote.bold())
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(HomeActionText())
                .accessibilityIdentifier(
                    SurroundUITestContract.AccessibilityID.homeHistoryViewAll
                )
            }
            if !recentFinishedGames.isEmpty {
                gameGrid(recentFinishedGames.map { HomeGameEntry(game: $0, context: .history) }) { entry, separated in
                    HistoryGameCell(game: entry.game, inCard: true, showsSeparator: separated, retryPreview: {
                        historyPreviewLoader.retry(game: entry.game, using: ogs)
                    }) {
                        showGameDetail(game: entry.game, showsCarousel: false)
                    }
                    .accessibilityIdentifier(
                        SurroundUITestContract.AccessibilityID.homeHistoryGame(entry.game)
                    )
                    .historyPreviewDemand(for: entry.game, loader: historyPreviewLoader, using: ogs,
                                          query: ogs.user?.id, screenIsVisible: isVisible)
                }
            }
            if let recentFinishedGamesStatus {
                GameHistoryLoadStatusView(
                    status: recentFinishedGamesStatus,
                    accessibilityIdentifiers: .init(
                        loading: SurroundUITestContract
                            .AccessibilityID.homeHistoryLoading,
                        error: SurroundUITestContract
                            .AccessibilityID.homeHistoryError,
                        retry: SurroundUITestContract
                            .AccessibilityID.homeHistoryRetry,
                        empty: SurroundUITestContract
                            .AccessibilityID.homeHistoryEmpty
                    ),
                    emptyVerticalPadding: 30,
                    retry: loadRecentFinishedGames
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .modifier(HomeCard())
                .padding(.top, recentFinishedGames.isEmpty ? 0 : HomeLayout.rowSpacing)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.homeSection("history"))
    }

    var activeGamesView: some View {
        let isFirstLoad = !hasActiveItems && ogs.isLoadingOverview
        let isFirstRun = !hasActiveItems && !ogs.isLoadingOverview
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchingCard
                if isFirstLoad {
                    firstLoadView
                } else if isFirstRun {
                    firstRunView
                    // A new account has no history, so it sees only the
                    // message. One whose last game just ended keeps its
                    // recent results and the way to its full history.
                    if !recentFinishedGames.isEmpty || recentFinishedLoadState == .failed {
                        historySection
                    }
                } else {
                    if !ogs.challengesReceived.isEmpty {
                        challengesSection
                    }
                    gameSection(String(localized: "Live games", comment: "Homeview"),
                                games: ogs.liveGames, context: .live)
                    gameSection(String(localized: "Your move", comment: "Game\nHomeview"),
                                games: userTurnGames, context: .userTurn,
                                emptyText: String(localized: "No correspondence games on your turn"))
                    gameSection(String(localized: "Their move"),
                                games: opponentTurnGames, context: .opponentTurn,
                                emptyText: String(localized: "No correspondence games on your opponents' turn"))
                    historySection
                }
            }
            .padding(.horizontal, margin)
            .padding(.bottom, 24)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .refreshable { await refresh() }
        // The scene stays put behind the scrolling games.
        .background { HomeBackdrop() }
    }

    /// Pull to refresh: the overview, then the history preview.
    private func refresh() async {
        loadRecentFinishedGames()
        guard allowsRemoteActivity, ogs.isLoggedIn else { return }
        ogs.loadOverview()
        for await loading in ogs.$isLoadingOverview.values where !loading {
            break
        }
    }

    private var recentFinishedGamesStatus: GameHistoryLoadStatus? {
        switch recentFinishedLoadState {
        case .idle, .loading:
            return recentFinishedGames.isEmpty ? .loading : nil
        case .failed:
            return .failed
        case .loaded where recentFinishedGames.isEmpty:
            return .empty
        default:
            return nil
        }
    }

    @MainActor
    private func resolvePendingGameOpen(_ request: PendingGameOpen) async {
        guard request.rootView == .home,
              nav.pendingGameOpen?.id == request.id else {
            return
        }

        // A newer token owns all transient routing UI immediately, even when
        // the cancelled request's publisher takes a moment to unwind.
        openingGameRequestID = nil
        failedGameOpen = nil

        do {
            let resolver = GameOpenResolver<Game>(
                activeGame: { gameID in
                    guard let game = ogs.activeGames[gameID],
                          game.gameData != nil else {
                        return nil
                    }
                    return game
                },
                sharedOverviewGame: { gameID in
                    ogs.cachedOverviewGame(gameID: gameID)
                },
                restGame: { gameID in
                    #if DEBUG && MAIN_APP
                    if SurroundUITestContract.simulatesWidgetDeepLinkRouting,
                       gameID == SurroundUITestContract.widgetRoutingMissingGameID {
                        try await Task.sleep(
                            nanoseconds: SurroundUITestContract
                                .widgetRoutingRESTDelayNanoseconds
                        )
                    }
                    #endif
                    for try await game in ogs.getGameDetail(
                        gameID: gameID
                    ).values {
                        return game
                    }
                    throw OGSServiceError.invalidJSON
                }
            )
            let resolution = try await resolver.resolve(
                gameID: request.ogsGameID,
                onRESTRequired: {
                    openingGameRequestID = request.id
                }
            )
            if openingGameRequestID == request.id {
                openingGameRequestID = nil
            }
            guard !Task.isCancelled,
                  nav.pendingGameOpen?.id == request.id else {
                return
            }
            finishPendingGameOpen(request, game: resolution.game)
        } catch {
            if openingGameRequestID == request.id {
                openingGameRequestID = nil
            }
            guard !Task.isCancelled,
                  nav.pendingGameOpen?.id == request.id else {
                return
            }
            failedGameOpen = request
        }
    }

    @MainActor
    private func finishPendingGameOpen(
        _ request: PendingGameOpen,
        game: Game
    ) {
        guard nav.pendingGameOpen?.id == request.id else { return }
        failedGameOpen = nil
        showGameDetail(
            game: game,
            showsCarousel: game.gamePhase != .finished
        )
        nav.clearPendingGameOpen(id: request.id)
    }

    private func retryFailedGameOpen() {
        guard let failedGameOpen,
              let route = AppRoute(
                rootView: failedGameOpen.rootView,
                ogsGameID: failedGameOpen.ogsGameID
              ) else {
            return
        }
        self.failedGameOpen = nil
        nav.handle(route: route)
    }

    private func cancelFailedGameOpen() {
        if let request = failedGameOpen {
            nav.clearPendingGameOpen(id: request.id)
        }
        failedGameOpen = nil
    }

    var shouldShowSettingsButton: Bool {
        #if os(iOS)
        if let iPadTabContext {
            return !iPadTabContext.sidebarVisible
        }
        #if !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0)
        if #available(iOS 27.0, *), let duoTabContext {
            return !duoTabContext.sidebarAvailable
        }
        #endif
        if let tabBarPlacement {
            return tabBarPlacement != .sidebar
        }
        return horizontalSizeClass == .compact
        #else
        return true
        #endif
    }

    // MARK: - Header

    private var displayModeMenu: some View {
        Menu {
            Picker(selection: $displayMode.animation(), label: Text("Display mode")) {
                Label("Compact", systemImage: "square.fill.text.grid.1x2").tag(GameCell.CellDisplayMode.compact)
                Label("Large", systemImage: "rectangle.grid.1x2").tag(GameCell.CellDisplayMode.full)
            }
            .pickerStyle(.inline)
        } label: {
            Label("Display mode",
                  systemImage: displayMode == .compact ? "square.fill.text.grid.1x2" : "rectangle.grid.1x2")
                .labelStyle(.iconOnly)
        }
        .accessibilityValue(displayMode == .compact ? Text("Compact") : Text("Large"))
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.homeDisplayMode)
    }

    private var displayModeToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            displayModeMenu
        }
    }

    /// New game with your preferred settings beside it, in the action color.
    private var newGameCapsule: some View {
        HomeNewGameCapsule(
            showsPreferredSettingsTitle: showsPreferredSettingsTitle,
            newGame: { nav.home.showingNewGameView = true }
        ) {
            preferredSettingsMenu
        }
    }

    /// The star's menu (canvas "New game and Preferred settings"): each saved
    /// setup offers the same two actions as its card in Preferred Settings,
    /// and the last item opens the editor. With none saved, it says what they
    /// are and offers to add one.
    @ViewBuilder
    private var preferredSettingsMenu: some View {
        let settings = ogs.remoteSettings[.preferredGameSettings] ?? []
        if settings.isEmpty {
            Section {
                Button(action: { openPreferredSettings(creatingNewSetting: true) }) {
                    Label {
                        Text("Add a preferred setting…", comment: "Homeview - star menu item that opens the new preferred setting form")
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.homePreferredSettingsAdd)
            } header: {
                // The sentence Preferred Settings shows when it is empty. Menu
                // items stop at three lines; the header keeps all of it.
                Text("No preferred settings yet", comment: "Homeview - star menu header when no preferred settings are saved")
                    + Text(verbatim: "\n")
                    + Text("Add your preferred game settings to create a game with the exact settings you want faster.")
            }
        } else {
            Section {
                ForEach(Array(settings.enumerated()), id: \.offset) { index, setting in
                    Menu {
                        Button("Create open challenge", systemImage: "person.2") {
                            sendPreferredSetting(setting, to: nil)
                        }
                        .disabled(preferredSettingRequests[setting] != nil)
                        if !setting.rengo {
                            Button {
                                let submit = preferredSettingSubmission(for: setting)
                                stackRouter.openSavedSettingsOpponentPicker { submit($0) }
                            } label: {
                                Label {
                                    Text("Select your opponent…", comment: "Homeview - star menu: challenge a chosen player with this preferred setting")
                                } icon: {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                }
                            }
                            .disabled(preferredSettingRequests[setting] != nil)
                        }
                    } label: {
                        Text(verbatim: preferredSettingTitle(setting))
                        Text(verbatim: preferredSettingDetail(setting))
                    }
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.homePreferredSetting(index))
                }
            } header: {
                Text("Start from a preferred setting", comment: "Homeview - star menu header above the saved preferred settings")
            }
            Section {
                Button(action: { openPreferredSettings(creatingNewSetting: false) }) {
                    Label {
                        Text("Edit Preferred Settings…", comment: "Homeview - star menu item that opens the preferred settings editor")
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.homePreferredSettingsEdit)
            }
        }
    }

    private func openPreferredSettings(creatingNewSetting: Bool) {
        preferredSettingsStartsWithNewSetting = creatingNewSetting
        nav.home.showingPreferredSettings = true
    }

    private func preferredSettingSubmission(for setting: OGSChallengeTemplate) -> (OGSUser?) -> Void {
        // A sent challenge shows up in Home's searching card; nothing to close.
        preferredSettingChallengeSubmission(for: setting, using: ogs, requests: $preferredSettingRequests) {}
    }

    private func sendPreferredSetting(_ setting: OGSChallengeTemplate, to opponent: OGSUser?) {
        preferredSettingSubmission(for: setting)(opponent)
    }

    /// "19×19 · Correspondence", as the canvas names a saved setup.
    private func preferredSettingTitle(_ setting: OGSChallengeTemplate) -> String {
        let size = "\(setting.game.width)×\(setting.game.height)"
        let speed: String? = switch setting.game.timeControl.speed {
        case .correspondence?: String(localized: "Correspondence")
        case .live?: String(localized: "Live")
        case .rapid?: String(localized: "Rapid", comment: "Name of the OGS Rapid game-speed category, between Blitz and Live.")
        case .blitz?: String(localized: "Blitz")
        case nil: nil
        }
        return [size, speed].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Ranked · 3d + 1d up to 7d": what Preferred Settings' cards show.
    private func preferredSettingDetail(_ setting: OGSChallengeTemplate) -> String {
        let ranked = setting.game.ranked
            ? String(localized: "Ranked", comment: "ChallengeCell rank status")
            : String(localized: "Unranked", comment: "ChallengeCell rank status")
        let time = setting.game.timeControl.system.shortDescription
        return time.isEmpty ? ranked : "\(ranked) · \(time)"
    }

    /// Wide bands spell out Preferred Settings, but only where the bar has
    /// room: beside a shown sidebar, not iPadOS's top tab bar.
    private var showsPreferredSettingsTitle: Bool {
        guard horizontalSizeClass == .regular, usesBands else { return false }
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return iPadTabContext?.sidebarVisible == true
        #endif
    }

    private var newGameToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            newGameCapsule
        }
    }

    private var accountMenu: some View {
        Menu {
            if let user = ogs.user {
                Text(verbatim: user.usernameAndRank)
            }
            Divider()
            Button("Profile", systemImage: "person.crop.circle") {
                if NavigationService.usesIPadAccountSheets {
                    nav.main.accountSheet = .profile
                } else if let user = ogs.user {
                    openPlayerProfile?(user)
                }
            }
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.accountMenuProfile)
            Button("Settings", systemImage: "gearshape") {
                if NavigationService.usesIPadAccountSheets {
                    nav.main.accountSheet = .settings
                } else {
                    nav.home.showingSettings = true
                }
            }
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.accountMenuSettings)
            Divider()
            Button("Log out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                ogs.logout()
            }
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.accountMenuLogout)
        } label: {
            AsyncImage(url: allowsRemoteActivity ? ogs.user?.iconURL(ofSize: 128) : nil) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .accessibilityHidden(true)
        }
        .accessibilityLabel("Account")
        .accessibilityValue(Text(verbatim: ogs.user?.usernameAndRank ?? ""))
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.accountMenu)
    }

    private var accountMenuToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            accountMenu
        }
    }

    private var initialNewGameOption: NewGameView.NewGameOption {
        switch SurroundUITestContract.compatibilityScene {
        case .quickMatch?:
            .quickMatch
        case .openChallenges?, .rengoOpenChallenges?:
            .openChallenges
        case .customGame?:
            .custom
        default:
            SurroundUITestContract.isCapturingAppStoreScreenshots
                ? .openChallenges
                : .quickMatch
        }
    }

    var body: some View {
        return VStack {
            if ogs.isLoggedIn {
                activeGamesView
            } else {
                WelcomeView()
            }
        }
        .toolbar {
            if (ogs.isLoggedIn) {
                if shouldShowSettingsButton {
                    if #available(iOS 26.0, *) {
                        accountMenuToolbarItem.sharedBackgroundVisibility(.hidden)
                    } else {
                        accountMenuToolbarItem
                    }
                }
                if #available(iOS 26.0, *) {
                    // The capsule draws its own action-colored surface.
                    newGameToolbarItem.sharedBackgroundVisibility(.hidden)
                } else {
                    newGameToolbarItem
                }
                displayModeToolbarItem
            }
        }
        .overlay {
            if openingGameRequestID != nil {
                ProgressView("Opening game…")
                    .padding()
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .accessibilityIdentifier(
                        SurroundUITestContract.AccessibilityID.openingGame
                    )
            }
        }
        .alert(
            "Unable to open game",
            isPresented: Binding(
                get: { failedGameOpen != nil },
                set: { isPresented in
                    if !isPresented {
                        cancelFailedGameOpen()
                    }
                }
            )
        ) {
            Button("Retry", action: retryFailedGameOpen)
                .accessibilityIdentifier(
                    SurroundUITestContract.AccessibilityID.openGameRetry
                )
            Button("Cancel", role: .cancel, action: cancelFailedGameOpen)
        } message: {
            Text("The game may have ended or could not be loaded. Please try again.")
        }
        .stackDestination(isPresented: Binding(
            get: { nav.home.activeGame != nil },
            set: {
                if !$0 {
                    nav.home.activeGame = nil
                    nav.home.activeGameShowsCarousel = true
                }
            }
        ), route: .homeGame)
        .stackDestination(
            isPresented: Binding(
                get: { nav.home.showingGameHistory },
                set: { presented in
                    if presented { nav.home.showingGameHistory = true }
                    else { nav.closeGameHistory() }
                }
            ),
            route: .gameHistory
        )
        .onAppear {
            isVisible = true
            loadRecentFinishedGames()
        }
        .onDisappear {
            isVisible = false
            historyPreviewLoader.cancel()
        }
        .onChange(of: ogs.user?.id) { _, _ in
            resetRecentFinishedGames()
        }
        .onChange(of: ogs.activeGames.count) { _, _ in
            // A game leaving (or joining) the active list usually means one
            // just finished — refresh so it appears here immediately.
            loadRecentFinishedGames()
        }
        .onReceive(ogs.automatchLifecycleEvents) { event in
            guard case .started(
                _,
                let gameID?,
                requestedLocally: true
            ) = event.kind,
                  let route = AppRoute(
                    rootView: .home,
                    ogsGameID: gameID
                  ) else {
                return
            }
            AccessibilityNotification.Announcement(
                String(localized: "Game found")
            ).post()
            nav.handle(route: route)
        }
        .navigationTitle(ogs.isLoggedIn ? String(localized: "Active games") : String(localized: "Welcome"))
        .surroundTheme(theme)
        .sheet(isPresented: $nav.home.showingNewGameView) {
            AppNavigationStack {
                NewGameView(newGameOption: initialNewGameOption)
                    .navigationTitle("New game")
                    .navigationBarTitleDisplayMode(.inline)
                    #if DEBUG && MAIN_APP
                    .modifier(CompatibilityScreenshotReadinessModifier(
                        scene: SurroundUITestContract.compatibilityScene
                            .flatMap { $0.isNewGame ? $0 : nil }
                    ))
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(action: { nav.home.showingNewGameView = false }) {
                                Label("Close", systemImage: "xmark")
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier(
                                SurroundUITestContract.AccessibilityID.newGameClose
                            )
                        }
                    }
                    .environmentObject(ogs)
                    .environmentObject(nav)
            }
            .presentationSizing(.page)
        }
        .sheet(isPresented: $nav.home.showingPreferredSettings) {
            AppNavigationStack {
                PreferredSettingsView(startsCreatingNewSetting: preferredSettingsStartsWithNewSetting)
                    .navigationTitle("Preferred Settings")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(action: { nav.home.showingPreferredSettings = false }) {
                                Text("Cancel")
                            }
                        }
                    }
                    .environmentObject(ogs)
                    .environmentObject(nav)
            }
        }
        .sheet(isPresented: $nav.home.showingSettings) {
            AppNavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", systemImage: "checkmark") {
                                nav.home.showingSettings = false
                            }
                        }
                    }
                    .environmentObject(ogs)
                    .environmentObject(nav)
            }
        }
        .task(id: nav.pendingGameOpen?.id) {
            guard let request = nav.pendingGameOpen,
                  request.rootView == .home else {
                return
            }
            await resolvePendingGameOpen(request)
        }
        .onChange(of: displayMode, initial: true) { _, newDisplayMode in
            guard allowsLocalPersistence else { return }
            userDefaults[.homeViewDisplayMode] = newDisplayMode.rawValue
        }
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.screenHome)
        .modifier(AppReviewHomePresentation(
            isBlocked: openingGameRequestID != nil || failedGameOpen != nil
                || recentFinishedLoadState == .loading
                || recentFinishedLoadState == .failed
        ))
    }
}

private extension HomeGameEntry.Context {
    var sectionID: String {
        switch self {
        case .live: "live"
        case .userTurn: "userTurn"
        case .opponentTurn: "opponentTurn"
        case .history: "history"
        }
    }
}

private struct HomeSkeletonEntry: Identifiable {
    let id: Int
}

/// The scene behind Home, softened under the large title: a veil in the
/// page color that fades out below it, as on the canvas, so the title reads
/// while the art still shows through. Its height follows the title's safe
/// area as it collapses and grows with Dynamic Type, without replacing the
/// navigation bar's own appearance or scroll-edge effects.
private struct HomeBackdrop: View {
    @Environment(\.surroundTheme) private var theme
    private let fadeLength: CGFloat = 72

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                GameDetailBackdrop().ignoresSafeArea(.container)
                if theme.hasScene {
                    let titleArea = geometry.safeAreaInsets.top
                    let height = titleArea + fadeLength
                    LinearGradient(
                        stops: [
                            .init(color: theme.pageBackground.opacity(0.82), location: 0),
                            .init(color: theme.pageBackground.opacity(0.62), location: titleArea / height),
                            .init(color: theme.pageBackground.opacity(0), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(.container, edges: .top)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Text set on a theme's scene rather than on a card: a thin halo in the
/// page color edges the glyphs, and a feathered patch of it, sized to the
/// words, quiets the art just behind them. It keeps text readable over the
/// scene's brightest and darkest details without hiding the art. Plain
/// pages need neither.
struct HomeSceneLegibility: ViewModifier {
    @Environment(\.surroundTheme) private var theme

    func body(content: Content) -> some View {
        if theme.hasScene {
            content
                .shadow(color: theme.pageBackground.opacity(0.9), radius: 1)
                .background {
                    Capsule()
                        .fill(theme.pageBackground.opacity(0.65))
                        .padding(-8)
                        .blur(radius: 10)
                }
        } else {
            content
        }
    }
}

/// New game with its star menu in one action-colored capsule. A view of its
/// own, so the toolbar hosts it whole instead of splitting its Menu out into
/// separate bar buttons.
private struct HomeNewGameCapsule<MenuContent: View>: View {
    let showsPreferredSettingsTitle: Bool
    let newGame: () -> Void
    @ViewBuilder let menuContent: () -> MenuContent

    var body: some View {
        HStack(spacing: 0) {
            Button(action: newGame) {
                Label("New game", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .padding(.leading, 13)
                    .padding(.trailing, 11)
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier(
                SurroundUITestContract.AccessibilityID.homeNewGame
            )
            Rectangle()
                .fill(.white.opacity(0.45))
                .frame(width: 1, height: 22)
                .accessibilityHidden(true)
            Menu {
                menuContent()
            } label: {
                Label("Preferred Settings", systemImage: "star.square.on.square")
                    .labelStyle(PreferredSettingsLabelStyle(showsTitle: showsPreferredSettingsTitle))
                    .padding(.horizontal, 11)
                    .frame(minWidth: 44, minHeight: 40)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .accessibilityIdentifier(
                SurroundUITestContract.AccessibilityID.homePreferredSettings
            )
        }
        .font(.body.weight(.semibold))
        .lineLimit(1)
        .fixedSize()
        .buttonStyle(.plain)
        .modifier(HomeActionSurface())
    }
}

/// Wide layouts spell out Preferred Settings; narrow ones keep the star.
private struct PreferredSettingsLabelStyle: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        if showsTitle {
            HStack(spacing: 6) {
                configuration.icon
                configuration.title
            }
        } else {
            configuration.icon
        }
    }
}

#if DEBUG && MAIN_APP
#Preview("Home — Signed in") {
    AppNavigationStack {
        HomeView(
            previewGames: [
                TestData.Scored19x19Korean,
                TestData.Resigned9x9Japanese,
            ]
        )
            .modifier(RootViewSwitchingMenu())
    }
    .environmentObject(
        OGSService.previewInstance(
            user: OGSUser(username: "kata-bot", id: 592684),
            activeGames: [
                TestData.Ongoing19x19wBot1,
                TestData.Ongoing19x19wBot2,
            ],
            openChallengesSent: [OGSChallengeSampleData.sampleOpenChallenge],
            automatchEntries: [OGSAutomatchEntry.sampleEntry]
        )
    )
    .environmentObject(NavigationService())
    .environment(\.surroundAllowsRemoteActivity, false)
    .environment(\.surroundAllowsLocalPersistence, false)
}

#Preview("Home — Signed out") {
    AppNavigationStack {
        HomeView()
            .modifier(RootViewSwitchingMenu())
    }
    .environmentObject(OGSService.previewInstance())
    .environmentObject(NavigationService())
    .environment(\.surroundAllowsRemoteActivity, false)
    .environment(\.surroundAllowsLocalPersistence, false)
}
#endif
