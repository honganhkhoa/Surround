//
//  HomeView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 7/10/20.
//

import SwiftUI
import Combine
import DictionaryCoding

struct HomeView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    
    @State var showRegisterWebView = false
    @State var gameDetailCancellable: AnyCancellable?
    
    @State var displayMode: GameCell.CellDisplayMode
    
    init(previewGames: [Game] = []) {
        #if os(iOS)
        if let savedDisplayMode = userDefaults[.homeViewDisplayMode] {
            _displayMode = State(initialValue: GameCell.CellDisplayMode(rawValue: savedDisplayMode) ?? .full)
        } else {
            if UIScreen.main.traitCollection.horizontalSizeClass == .compact {
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
        HStack {
            Text(title)
                .font(Font.title3.bold())
            Spacer()
        }
        .padding([.vertical], 5)
        .padding([.horizontal])
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.systemGray3).shadow(radius: 2))
    }
    
    func showGameDetail(game: Game) {
        print("Opening game \(game)")
        nav.home.activeGame = game
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
                                Text("Waiting for opponent: \(ogs.waitingGames) game\(ogs.waitingGames == 1 ? "" : "s") ")
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
                                    Text("\(ogs.pendingRengoGames) pending Rengo game\(ogs.pendingRengoGames == 1 ? "" : "s") ")
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
                    Button(action: { nav.home.showingNewGameView = true }) {
                        HStack {
                            Label {
                                Text("New game").font(Font.body.bold())
                            } icon: {
                                Image(systemName: "plus.app.fill").font(Font.body.bold())
                            }
                        }.padding()
                        Spacer()
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
                                ForEach(ogs.liveGames) { game in
                                    GameCell(game: game, displayMode: displayMode)
                                    .onTapGesture {
                                        showGameDetail(game: game)
                                    }
                                    .padding(.vertical, displayMode == .full ? nil : 0)
                                    .padding(.horizontal)
                                }
                            }
                        }
                        Section(header: sectionHeader(title: String(localized: "Your move", comment: "Homeview"))) {
                            ForEach(ogs.sortedActiveCorrespondenceGamesOnUserTurn) { game in
                                GameCell(game: game, displayMode: displayMode)
                                .onTapGesture {
                                    showGameDetail(game: game)
                                }
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
                            ForEach(ogs.sortedActiveCorrespondenceGamesNotOnUserTurn) { game in
                                GameCell(game: game, displayMode: displayMode)
                                .onTapGesture {
                                    self.showGameDetail(game: game)
                                }
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
            NavigationLink(
                destination: GameDetailView(currentGame: nav.home.activeGame),
                isActive: Binding(
                    get: { nav.home.activeGame != nil },
                    set: { if !$0 { nav.home.activeGame = nil } }
                )) {
                EmptyView()
            }
            NavigationLink(
                destination: OGSBrowserView(initialURL: URL(string: "\(OGSService.ogsRoot)/register")!),
                isActive: $showRegisterWebView
            ) {
                EmptyView()
            }
            // Workaround for an issue on iOS 14.5 where the NavigationLink pops out by itself.
            // https://developer.apple.com/forums/thread/677333#672042022
            NavigationLink(destination: EmptyView()) {
                EmptyView()
            }
        }
        .onAppear {
            if nav.home.ogsIdToOpen != -1 {
                DispatchQueue.main.async {
                    openRequestedActiveGameIfReady()
                }
            }
        }
        .navigationTitle(ogs.isLoggedIn ? String(localized: "Active games") : String(localized: "Welcome"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Picker(selection: $displayMode.animation(), label: Text("Display mode")) {
                    Label("Compact", systemImage: "square.fill.text.grid.1x2").tag(GameCell.CellDisplayMode.compact)
                    Label("Large", systemImage: "rectangle.grid.1x2").tag(GameCell.CellDisplayMode.full)
                }
                .pickerStyle(SegmentedPickerStyle())
                .disabled(!ogs.isLoggedIn)
                .opacity(ogs.isLoggedIn ? 1 : 0)
            }
        }
        .sheet(isPresented: $nav.home.showingNewGameView) {
            NavigationView {
                NewGameView()
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
        .onChange(of: nav.home.ogsIdToOpen) { ogsGameIdToOpen in
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
        .onChange(of: displayMode) { newDisplayMode in
            userDefaults[.homeViewDisplayMode] = newDisplayMode.rawValue
        }
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
                            openChallengesSent: [OGSChallenge.sampleOpenChallenge],
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
