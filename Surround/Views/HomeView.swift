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
private struct HomeGameRow: Identifiable {
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    @Environment(\.surroundAllowsRemoteActivity) private var allowsRemoteActivity
    @Environment(\.surroundAllowsLocalPersistence) private var allowsLocalPersistence
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    
    @State var displayMode: GameCell.CellDisplayMode

    @State private var openingGameRequestID: UUID?
    @State private var failedGameOpen: PendingGameOpen?

    @State var recentFinishedGames: [Game] = []
    @State var recentFinishedCancellable: AnyCancellable?
    @State private var recentFinishedLoadState: RecentFinishedGamesLoadState
    @State private var recentFinishedRequestID: UUID?
    @State private var hasSimulatedRecentFinishedGamesFailure = false
    
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

    func sectionHeader(title: String) -> some View {
        sectionHeader(title: title, trailing: { EmptyView() })
    }

    func sectionHeader<Trailing: View>(title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
                .font(Font.title3.bold())
            Spacer()
            trailing()
        }
        .padding([.vertical], 5)
        .padding([.horizontal])
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.systemGray3).shadow(radius: 2))
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
        recentFinishedCancellable = ogs.fetchHydratedFinishedGames(
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
        recentFinishedCancellable?.cancel()
        recentFinishedCancellable = nil
        recentFinishedRequestID = nil
        recentFinishedLoadState = .idle
        recentFinishedGames = []
        loadRecentFinishedGames()
    }
    
    var activeGamesView: some View {
        let noItem = 
            ogs.challengesReceived.count +
            ogs.liveGames.count +
            ogs.sortedActiveCorrespondenceGamesOnUserTurn.count +
            ogs.sortedActiveCorrespondenceGamesNotOnUserTurn.count == 0
        let isLoading = noItem && ogs.isLoadingOverview
        return Group {
            ScrollView {
                if isLoading {
                    ProgressView()
                } else {
                    if ogs.waitingGames > 0 {
                        Button(action: { nav.main.showWaitingGames = true }) {
                            HStack(spacing: 6) {
                                Text(
                                    ogs.waitingGames == 1
                                        ? String(localized: "Searching for a game")
                                        : String(localized: "Searching for \(ogs.waitingGames) games")
                                )
                                Image(systemName: "chevron.forward")
                                Spacer()
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .frame(minHeight: 44)
                            .padding(.horizontal)
                            .background(Color(.systemIndigo))
                        }
                    }
                    if ogs.pendingRengoGames > 0 {
                        Button(action: { nav.main.showWaitingGames = true }) {
                            HStack {
                                HStack {
                                    Text("\(ogs.pendingRengoGames) pending Rengo games ", comment: "HomeView - vary for plural")
                                        .font(.subheadline)
                                        .bold()
                                        .foregroundColor(.white)
                                    Spacer().frame(width: 10)
                                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color(.systemPurple))
                            }
                        }
                    }
                    HStack {
                        Button(action: { nav.home.showingNewGameView = true }) {
                            HStack {
                                Label("New game", systemImage: "plus.app.fill")
                                    .font(.body.bold())
                            }.padding()
                            Spacer()
                        }
                        .accessibilityIdentifier(
                            SurroundUITestContract.AccessibilityID.homeNewGame
                        )
                        Button("Preferred Settings", systemImage: "star.square.on.square") {
                            nav.home.showingPreferredSettings = true
                        }
                        .accessibilityIdentifier(
                            SurroundUITestContract.AccessibilityID.homePreferredSettings
                        )
                        .labelStyle(.iconOnly)
                        .font(.body.bold())
                        .padding()
                        .padding(.leading, 10)
                        .tint(.mint)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), alignment: .top)], pinnedViews: [.sectionHeaders]) {
                        if ogs.challengesReceived.count > 0 {
                            Section(header: sectionHeader(title: String(localized: "Challenges received", comment: "Homeview"))) {
                                ForEach(ogs.challengesReceived) { challenge in
                                    ChallengeCell(challenge: challenge)
                                        .padding()
                                        .background(Color(UIColor.systemBackground).shadow(radius: 2))
                                        .padding(.vertical, 5)
                                        .padding(.horizontal)
                                }
                            }
                        }
                        if ogs.liveGames.count > 0 {
                            Section(header: sectionHeader(title: String(localized: "Live games", comment: "Homeview"))) {
                                ForEach(
                                    ogs.liveGames.map { HomeGameRow(game: $0, context: .live) }
                                ) { row in
                                    GameCell(
                                        game: row.game,
                                        displayMode: displayMode,
                                        opensGame: {
                                            showGameDetail(game: row.game)
                                        },
                                        showsConditionalMoves: true,
                                        navigationAccessibilityIdentifier:
                                            SurroundUITestContract
                                                .AccessibilityID.homeGame(row.game)
                                    )
                                    .padding(.vertical, displayMode == .full ? nil : 0)
                                    .padding(.horizontal)
                                }
                            }
                        }
                        Section(header: sectionHeader(title: String(localized: "Your move", comment: "Homeview"))) {
                            ForEach(
                                ogs.sortedActiveCorrespondenceGamesOnUserTurn.map {
                                    HomeGameRow(game: $0, context: .userTurn)
                                }
                            ) { row in
                                GameCell(
                                    game: row.game,
                                    displayMode: displayMode,
                                    opensGame: {
                                        showGameDetail(game: row.game)
                                    },
                                    showsConditionalMoves: true,
                                    navigationAccessibilityIdentifier:
                                        SurroundUITestContract
                                            .AccessibilityID.homeGame(row.game)
                                )
                                .padding(.vertical, displayMode == .full ? nil : 0)
                                .padding(.horizontal)
                            }
                            if ogs.sortedActiveCorrespondenceGamesOnUserTurn.count == 0 {
                                Text("No correspondence games on your turn")
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                    .padding(.vertical, 30)
                            }
                        }
                        Section(header: sectionHeader(title: String(localized: "Waiting for opponents/teammates", comment: "Homeview"))) {
                            ForEach(
                                ogs.sortedActiveCorrespondenceGamesNotOnUserTurn.map {
                                    HomeGameRow(game: $0, context: .opponentTurn)
                                }
                            ) { row in
                                GameCell(
                                    game: row.game,
                                    displayMode: displayMode,
                                    opensGame: {
                                        showGameDetail(game: row.game)
                                    },
                                    showsConditionalMoves: true,
                                    navigationAccessibilityIdentifier:
                                        SurroundUITestContract
                                            .AccessibilityID.homeGame(row.game)
                                )
                                .padding(.vertical, displayMode == .full ? nil : 0)
                                .padding(.horizontal)
                            }
                            if ogs.sortedActiveCorrespondenceGamesNotOnUserTurn.count == 0 {
                                Text("No correspondence games on your opponents' turn")
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                    .padding(.vertical, 30)
                            }
                        }
                        Section(header: sectionHeader(title: String(localized: "Game history", comment: "Homeview"))) {
                            ForEach(
                                recentFinishedGames.map {
                                    HomeGameRow(game: $0, context: .history)
                                }
                            ) { row in
                                HistoryGameCell(game: row.game) {
                                    showGameDetail(game: row.game, showsCarousel: false)
                                }
                                .accessibilityIdentifier(
                                    SurroundUITestContract.AccessibilityID.homeHistoryGame(row.game)
                                )
                                .padding(.horizontal)
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
                            }
                            Button(action: { nav.home.showingGameHistory = true }) {
                                HStack {
                                    Spacer()
                                    Text("View full history", comment: "Homeview")
                                        .font(.body.bold())
                                    Image(systemName: "chevron.right")
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .accessibilityIdentifier(
                                SurroundUITestContract.AccessibilityID.homeHistoryViewAll
                            )
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        }
                        Spacer()
                    }
                    .background(colorScheme == .dark ? Color(UIColor.systemGray5) : Color.white)
                }
            }
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
        if let tabBarPlacement {
            return tabBarPlacement != .sidebar
        }
        return horizontalSizeClass == .compact
        #else
        return true
        #endif
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
                ToolbarItemGroup(placement: .topBarLeading) {
                    if shouldShowSettingsButton {
                        Button(action: { nav.home.showingSettings = true }) {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Picker(selection: $displayMode.animation(), label: Text("Display mode")) {
                        Label("Compact", systemImage: "square.fill.text.grid.1x2").tag(GameCell.CellDisplayMode.compact)
                        Label("Large", systemImage: "rectangle.grid.1x2").tag(GameCell.CellDisplayMode.full)
                    }
                    .fixedSize()
                    .pickerStyle(SegmentedPickerStyle())
                    
                }
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
        .navigationDestination(isPresented: Binding(
            get: { nav.home.activeGame != nil },
            set: {
                if !$0 {
                    nav.home.activeGame = nil
                    nav.home.activeGameShowsCarousel = true
                }
            }
        ), destination: {
            GameDetailView(
                currentGame: $nav.home.activeGame,
                allowsActiveGamesCarousel: nav.home.activeGameShowsCarousel
            )
        })
        .navigationDestination(isPresented: $nav.home.showingGameHistory) {
            GameHistoryView()
        }
        .onAppear {
            loadRecentFinishedGames()
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
        .sheet(isPresented: $nav.home.showingNewGameView) {
            NavigationStack {
                NewGameView(
                    newGameOption: SurroundUITestContract.isCapturingAppStoreScreenshots
                        ? .openChallenges
                        : .quickMatch
                )
                    .navigationTitle("New game")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(action: { nav.home.showingNewGameView = false }) {
                                Text("Cancel")
                            }
                        }
                    }
                    .environmentObject(ogs)
                    .environmentObject(nav)
            }
        }
        .sheet(isPresented: $nav.home.showingPreferredSettings) {
            NavigationStack {
                PreferredSettingsView()
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
            NavigationStack {
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
    }
}

#if DEBUG && MAIN_APP
#Preview("Home — Signed in") {
    NavigationStack {
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
    NavigationStack {
        HomeView()
            .modifier(RootViewSwitchingMenu())
    }
    .environmentObject(OGSService.previewInstance())
    .environmentObject(NavigationService())
    .environment(\.surroundAllowsRemoteActivity, false)
    .environment(\.surroundAllowsLocalPersistence, false)
}
#endif
