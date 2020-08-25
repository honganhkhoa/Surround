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
    @EnvironmentObject var ogs: OGSService
    
    @State var gameDetailCancellable: AnyCancellable?
    @State var showGameDetail = false
    @State var gameToShowDetail: Game? = nil
    
    @State var username = ""
    @State var password = ""
    @State var loginCancellable: AnyCancellable?
    @State var isShowingThirdPartyLogin = false
    
    @AppStorage("homeViewDisplayMode") var displayMode: GameCell.CellDisplayMode = .full
    
    init(previewGames: [Game] = []) {
        #if os(iOS)
        if UserDefaults.standard.string(forKey: "homeViewDisplayMode") == nil {
            if UIScreen.main.traitCollection.horizontalSizeClass == .compact {
                displayMode = .compact
            } else {
                displayMode = .full
            }
        }
        #endif
    }

    var loginView: some View {
        ScrollView {
            GroupBox(label: Text("Sign in to your online-go.com account to see your games here.")) {
                EmptyView()
            }.padding(.horizontal)
            GroupBox() {
                TextField("Username", text: $username)
                    .autocapitalization(.none)
                SecureField("Password", text: $password)
                Button(action: {
                    loginCancellable = ogs.login(username: username, password: password)
                        .sink(receiveCompletion: { completion in
                            if case .failure(let error) = completion {
                                print(error)
                            }
                            loginCancellable = nil
                        }, receiveValue: { config in
                        })
                }) {
                    Text("Sign in")
                }.disabled(username.count == 0 || password.count == 0)
            }.padding(.horizontal)
            GroupBox {
                NavigationLink(destination: ThirdPartyLoginView(type: .facebook), isActive: $isShowingThirdPartyLogin) {
                    Text("Sign in with Facebook")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                ZStack {
                    Button(action: {}) {
                        Text("Sign in with Google")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: 600)
        .onChange(of: ogs.isLoggedIn) { isLoggedIn in
            if isLoggedIn {
                isShowingThirdPartyLogin = false
            }
        }
    }

    func gameCell(game: Game, displayMode: GameCell.CellDisplayMode) -> some View {
        GameCell(game: game, displayMode: displayMode)
        .onTapGesture {
            self.gameToShowDetail = game
            self.showGameDetail = true
            self.gameDetailCancellable = ogs.getGameDetailAndConnect(gameID: game.gameData!.gameId).sink(receiveCompletion: { _ in
            }, receiveValue: { game in
            })
        }
            .padding(.vertical, displayMode == .full ? nil : 0)
            .padding(.horizontal)
    }
    
    func sectionHeader(title: String) -> some View {
        Text(title)
            .font(Font.title3.bold())
            .padding([.vertical], 5)
            .frame(maxWidth: .infinity)
            .background(Color(UIColor.systemGray3).shadow(radius: 2))
    }
    
    var activeGamesView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], pinnedViews: [.sectionHeaders]) {
                if ogs.sortedActiveGamesOnUserTurn.count + ogs.sortedActiveGamesNotOnUserTurn.count == 0 {
                    ProgressView()
                } else {
                    Section(header: sectionHeader(title: "Your move")) {
                        ForEach(ogs.sortedActiveGamesOnUserTurn) { game in
                            gameCell(game: game, displayMode: displayMode)
                        }
                    }
                    Section(header: sectionHeader(title: "Opponents' move")) {
                        ForEach(ogs.sortedActiveGamesNotOnUserTurn) { game in
                            gameCell(game: game, displayMode: displayMode)
                        }
                    }
                }
            }
            NavigationLink(destination: gameToShowDetail == nil ? nil : GameDetail(game: gameToShowDetail!), isActive: $showGameDetail) {
                EmptyView()
            }
        }
        .background(Color(UIColor.systemGray4))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Picker(selection: $displayMode.animation(), label: Text("Display mode")) {
                    Label("Compact", systemImage: "square.fill.text.grid.1x2").tag(GameCell.CellDisplayMode.compact)
                    Label("Large", systemImage: "rectangle.grid.1x2").tag(GameCell.CellDisplayMode.full)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
        }
    }
        
    var body: some View {
        Group {
            if ogs.isLoggedIn {
                activeGamesView
            } else {
                loginView
            }
        }
        .navigationTitle(ogs.isLoggedIn ? "Active games" : "Sign in to OGS")
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationView {
                HomeView()
                    .environmentObject(
                        OGSService.previewInstance(
                            user: OGSUser(username: "kata-bot", id: 592684),
                            activeGames: [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2, TestData.Ongoing19x19wBot3]
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
    }
}
