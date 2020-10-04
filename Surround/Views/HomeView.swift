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
    @State var showGameDetail = false
    
    @SceneStorage("currentActiveOGSGameId")
    var currentActiveOGSGameId = -1
    
    @AppStorage(SettingKey<Any>.homeViewDisplayMode.name) var displayMode: GameCell.CellDisplayMode = .full
    
    init(previewGames: [Game] = []) {
        #if os(iOS)
        if UserDefaults.standard[.homeViewDisplayMode] == nil {
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
        if let ogsID = game.ogsID {
            self.currentActiveOGSGameId = ogsID
            self.showGameDetail = true
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
                        }
                        Spacer()
                    }
                    .background(colorScheme == .dark ? Color(UIColor.systemGray5) : Color.white)
                }
            }
        }
    }
    
    func goToCurrentActiveGameIfReady() {
        if currentActiveOGSGameId != -1 && gameDetailCancellable == nil {
            if let currentActiveGame = ogs.activeGames[currentActiveOGSGameId] {
                if currentActiveGame.gameData != nil {
                    showGameDetail = true
                } else {
                    self.gameDetailCancellable = currentActiveGame.$gameData.sink(receiveValue: { _ in
                        DispatchQueue.main.async {
                            self.gameDetailCancellable?.cancel()
                            self.gameDetailCancellable = nil
                            self.goToCurrentActiveGameIfReady()
                        }
                    })
                }
            } else {
                self.gameDetailCancellable = ogs.$activeGames.sink(receiveValue: { _ in
                    DispatchQueue.main.async {
                        self.gameDetailCancellable?.cancel()
                        self.gameDetailCancellable = nil
                        self.goToCurrentActiveGameIfReady()
                    }
                })
            }
        }
    }
        
    var body: some View {
        let currentActiveGame = ogs.activeGames[currentActiveOGSGameId]
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
                isActive: $showGameDetail) {
                EmptyView()
            }
        }
        .onAppear {
            goToCurrentActiveGameIfReady()
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
        .onChange(of: currentActiveOGSGameId) { _ in
            DispatchQueue.main.async {
                goToCurrentActiveGameIfReady()
            }
        }
        .onChange(of: showGameDetail) { newValue in
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
