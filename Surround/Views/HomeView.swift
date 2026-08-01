//
//  HomeView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 7/10/20.
//

import SwiftUI
import Combine
import DictionaryCoding

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

struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    
    @State var gameDetailCancellable: AnyCancellable?
    @State var displayMode: GameCell.CellDisplayMode

    @State var recentFinishedGames: [Game] = []
    @State var recentFinishedCancellable: AnyCancellable?
    @State var isLoadingRecentFinished = false
    
    init(previewGames: [Game] = []) {
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
        guard ogs.isLoggedIn, let playerId = ogs.user?.id, !isLoadingRecentFinished else {
            return
        }
        isLoadingRecentFinished = true
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
                receiveCompletion: { _ in
                    isLoadingRecentFinished = false
                    recentFinishedCancellable = nil
                },
                receiveValue: { result in
                    // Drop a response that belongs to whoever was signed in when
                    // the request went out — otherwise a user switch mid-flight
                    // installs the previous account's history.
                    guard ogs.user?.id == playerId else {
                        return
                    }
                    recentFinishedGames = result.games
                }
            )
    }

    /// Clears history state that belongs to the previous account and reloads.
    func resetRecentFinishedGames() {
        recentFinishedCancellable?.cancel()
        recentFinishedCancellable = nil
        isLoadingRecentFinished = false
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
                            HStack {
                                Text("Waiting for opponent: \(ogs.waitingGames) games ", comment: "HomeView - vary for plural")
                                    .font(.subheadline)
                                    .bold()
                                    .foregroundColor(.white)
                                Spacer().frame(width: 10)
                                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
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
                                    Button(action: { showGameDetail(game: row.game) }) {
                                        GameCell(game: row.game, displayMode: displayMode)
                                    }
                                    .accessibilityIdentifier(
                                        SurroundUITestContract.AccessibilityID.homeGame(row.game)
                                    )
                                    .buttonStyle(.plain)
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
                                Button(action: { showGameDetail(game: row.game) }) {
                                    GameCell(game: row.game, displayMode: displayMode)
                                }
                                .accessibilityIdentifier(
                                    SurroundUITestContract.AccessibilityID.homeGame(row.game)
                                )
                                .buttonStyle(.plain)
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
                                Button(action: { showGameDetail(game: row.game) }) {
                                    GameCell(game: row.game, displayMode: displayMode)
                                }
                                .accessibilityIdentifier(
                                    SurroundUITestContract.AccessibilityID.homeGame(row.game)
                                )
                                .buttonStyle(.plain)
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
                        if recentFinishedGames.count > 0 {
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
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                            }
                        }
                        Spacer()
                    }
                    .background(colorScheme == .dark ? Color(UIColor.systemGray5) : Color.white)
                }
            }
        }
    }

    func openRequestedActiveGameIfReady() {
        print("Checking game #\(nav.home.ogsIdToOpen)")
        if nav.home.activeGame == nil && nav.home.ogsIdToOpen != -1 && gameDetailCancellable == nil {
            print("Continue checking game #\(nav.home.ogsIdToOpen)")
            if let game = ogs.activeGames[nav.home.ogsIdToOpen] {
                if game.gameData != nil {
                    self.showGameDetail(game: game)
                    nav.home.ogsIdToOpen = -1
                    self.gameDetailCancellable?.cancel()
                    self.gameDetailCancellable = nil
                } else {
                    print("Waiting for game data of #\(nav.home.ogsIdToOpen)")
                    self.gameDetailCancellable = game.$gameData.sink(receiveValue: { newGameData in
                        if newGameData != nil {
                            DispatchQueue.main.async {
                                self.gameDetailCancellable?.cancel()
                                self.gameDetailCancellable = nil
                                self.openRequestedActiveGameIfReady()
                            }
                        }
                    })
                }
                return
            }

            if let cachedGameData = userDefaults[.cachedOGSGames]?[nav.home.ogsIdToOpen] {
                if let ogsGame = try? JSONSerialization.jsonObject(with: cachedGameData) as? [String: Any] {
                    let decoder = DictionaryDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    if let ogsGame = try? decoder.decode(OGSGame.self, from: ogsGame) {
                        let game = Game(ogsGame: ogsGame)
                        self.showGameDetail(game: game)
                        nav.home.ogsIdToOpen = -1
                        return
                    }
                }
            }

            print("Waiting for #\(nav.home.ogsIdToOpen) to become active")
            self.gameDetailCancellable = ogs.$activeGames.sink(receiveValue: { newActiveGames in
                if newActiveGames[nav.home.ogsIdToOpen] != nil {
                    DispatchQueue.main.async {
                        self.gameDetailCancellable?.cancel()
                        self.gameDetailCancellable = nil
                        self.openRequestedActiveGameIfReady()
                    }
                }
            })
        }
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
        if let currentActiveGame = nav.home.activeGame {
            print("Reloading..., current active game #\(currentActiveGame)")
        } else {
            print("Reloading..., no current active game")
        }
        print("Waiting to open game #\(nav.home.ogsIdToOpen)")
        print("Showing game detail: \(nav.home.activeGame != nil)")
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
                currentGame: nav.home.activeGame,
                allowsActiveGamesCarousel: nav.home.activeGameShowsCarousel
            )
        })
        .navigationDestination(isPresented: $nav.home.showingGameHistory) {
            GameHistoryView()
        }
        .onAppear {
            if nav.home.ogsIdToOpen != -1 {
                DispatchQueue.main.async {
                    openRequestedActiveGameIfReady()
                }
            }
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
        .onChange(of: nav.home.ogsIdToOpen, initial: true) { _, ogsGameIdToOpen in
            if ogsGameIdToOpen != -1 {
                if ogsGameIdToOpen != nav.home.activeGame?.ogsID {
                    if nav.home.activeGame != nil {
                        nav.home.activeGame = nil
                        DispatchQueue.main.asyncAfter(
                            deadline: DispatchTime.now().advanced(by: .seconds(1)),
                            execute: {
                                openRequestedActiveGameIfReady()
                            }
                        )
                    } else {
                        DispatchQueue.main.async {
                            openRequestedActiveGameIfReady()
                        }
                    }
                }
            }
        }
        .onChange(of: displayMode, initial: true) { _, newDisplayMode in
            userDefaults[.homeViewDisplayMode] = newDisplayMode.rawValue
        }
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.screenHome)
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        let games = [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2]
        return Group {
            NavigationView {
                HomeView()
                    .modifier(RootViewSwitchingMenu())
                    .environmentObject(
                        OGSService.previewInstance(
                            user: OGSUser(username: "kata-bot", id: 592684),
                            activeGames: games,
                            openChallengesSent: [OGSChallengeSampleData.sampleOpenChallenge],
                            automatchEntries: [OGSAutomatchEntry.sampleEntry]
                        )
                    )
            }
            .navigationViewStyle(StackNavigationViewStyle())
            NavigationView {
                HomeView()
                    .modifier(RootViewSwitchingMenu())
                    .environmentObject(OGSService.previewInstance())
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
        .environmentObject(NavigationService.shared)
//        .colorScheme(.dark)
    }
}
