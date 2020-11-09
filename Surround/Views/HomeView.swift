//
//  HomeView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 7/10/20.
//

import SwiftUI
import Combine

struct HomeView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var ogs: OGSService
    
    @State var gameDetailCancellable: AnyCancellable?
    @State var showingGameDetail = false
    @State var currentActiveOGSGameId = -1
    
    @SceneStorage("activeOGSGameIdToOpen")
    var activeOGSGameIdToOpen = -1
    
    @AppStorage(SettingKey<Any>.homeViewDisplayMode.name, store: userDefaults)
    var displayMode: GameCell.CellDisplayMode = .full
    
    init(previewGames: [Game] = []) {
        #if os(iOS)
        if userDefaults[.homeViewDisplayMode] == nil {
            if UIScreen.main.traitCollection.horizontalSizeClass == .compact {
                displayMode = .compact
            } else {
                displayMode = .full
            }
        }
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
        if let ogsID = game.ogsID {
            self.currentActiveOGSGameId = ogsID
            self.showingGameDetail = true
        }
    }
    
    var activeGamesView: some View {
        let noItem = ogs.challengesSent.count +
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320))], pinnedViews: [.sectionHeaders]) {
                        if ogs.challengesReceived.count > 0 {
                            Section(header: sectionHeader(title: "Challenges received")) {
                                ForEach(ogs.challengesReceived) { challenge in
                                    ChallengeCell(challenge: challenge)
                                        .padding()
                                        .background(Color(UIColor.systemBackground).shadow(radius: 2))
                                        .padding(.vertical, 5)
                                        .padding(.horizontal)
                                }
                            }
                        }
                        if ogs.challengesSent.count > 0 {
                            Section(header: sectionHeader(title: "Challenges sent")) {
                                ForEach(ogs.challengesSent) { challenge in
                                    ChallengeCell(challenge: challenge)
                                        .padding()
                                        .background(Color(UIColor.systemBackground).shadow(radius: 2))
                                        .padding(.vertical, 5)
                                        .padding(.horizontal)
                                }
                            }
                        }
                        if ogs.liveGames.count > 0 {
                            Section(header: sectionHeader(title: "Live games")) {
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
                        Section(header: sectionHeader(title: "Your move")) {
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
                        Section(header: sectionHeader(title: "Opponents' move")) {
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
        print("Checking game #\(activeOGSGameIdToOpen)")
        if !showingGameDetail && activeOGSGameIdToOpen != -1 && gameDetailCancellable == nil {
            print("Continue checking game #\(activeOGSGameIdToOpen)")
            if let game = ogs.activeGames[activeOGSGameIdToOpen] {
                if game.gameData != nil {
                    self.showGameDetail(game: game)
                    activeOGSGameIdToOpen = -1
                    self.gameDetailCancellable?.cancel()
                    self.gameDetailCancellable = nil
                } else {
                    print("Waiting for game data of #\(activeOGSGameIdToOpen)")
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
            } else {
                print("Waiting for #\(activeOGSGameIdToOpen) to become active")
                self.gameDetailCancellable = ogs.$activeGames.sink(receiveValue: { newActiveGames in
                    if newActiveGames[activeOGSGameIdToOpen] != nil {
                        DispatchQueue.main.async {
                            self.gameDetailCancellable?.cancel()
                            self.gameDetailCancellable = nil
                            self.openRequestedActiveGameIfReady()
                        }
                    }
                })
            }
        }
    }
        
    var body: some View {
        let currentActiveGame = ogs.activeGames[currentActiveOGSGameId]
        if let currentActiveGame = currentActiveGame {
            print("Reloading..., current active game #\(currentActiveGame) for id #\(currentActiveOGSGameId)")
        } else {
            print("Reloading..., no current active game for id #\(currentActiveOGSGameId)")
        }
        print("Waiting to open game #\(activeOGSGameIdToOpen)")
        print("Showing game detail: \(showingGameDetail)")
        return VStack {
            if ogs.isLoggedIn {
                activeGamesView
            } else {
                ScrollView {
                    LoginView()
                }
                .frame(maxWidth: 600)
            }
            NavigationLink(
                destination: currentActiveGame == nil ? nil : GameDetailView(currentGame: currentActiveGame!),
                isActive: $showingGameDetail) {
                EmptyView()
            }
        }
        .onAppear {
            if activeOGSGameIdToOpen != -1 {
                DispatchQueue.main.async {
                    openRequestedActiveGameIfReady()
                }
            }
        }
        .navigationTitle(ogs.isLoggedIn ? "Active games" : "Sign in to OGS")
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
        .modifier(RootViewSwitchingMenu())
        .onChange(of: activeOGSGameIdToOpen) { ogsGameIdToOpen in
            if ogsGameIdToOpen != -1 {
                if ogsGameIdToOpen != currentActiveOGSGameId {
                    if showingGameDetail {
                        showingGameDetail = false
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
        .onChange(of: showingGameDetail) { newValue in
            if !newValue {
                currentActiveOGSGameId = -1
            }
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        let games = [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2, TestData.Ongoing19x19wBot3]
        return Group {
            NavigationView {
                HomeView()
                    .environmentObject(
                        OGSService.previewInstance(
                            user: OGSUser(username: "kata-bot", id: 592684),
                            activeGames: games
                        )
                    )
            }
            .navigationViewStyle(StackNavigationViewStyle())
            NavigationView {
                HomeView()
                    .environmentObject(OGSService.previewInstance())
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
//        .colorScheme(.dark)
    }
}
