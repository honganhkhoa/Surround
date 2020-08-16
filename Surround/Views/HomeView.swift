//
//  HomeView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 7/10/20.
//

import SwiftUI
import Combine

struct HomeView: View {
    var games: [Game] = []
    @EnvironmentObject var ogs: OGSService
    
    @State var gameDetailCancellable: AnyCancellable?
    @State var showGameDetail = false
    @State var gameToShowDetail: Game? = nil
    
    @State var username = ""
    @State var password = ""
    @State var loginCancellable: AnyCancellable?
    @State var isShowingThirdPartyLogin = false

    var body: some View {
        Group {
            if ogs.isLoggedIn {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))]) {
                        ForEach(ogs.activeGames.count > 0 ? Array(ogs.activeGames.values) : games) { game in
                            GameCell(game: game)
                            .onTapGesture {
                                self.gameToShowDetail = game
                                self.showGameDetail = true
                                self.gameDetailCancellable = ogs.getGameDetailAndConnect(gameID: game.gameData!.gameId).sink(receiveCompletion: { _ in
                                }, receiveValue: { game in
                                })
                            }
                                .padding()
                        }
                    }
                    NavigationLink(destination: gameToShowDetail == nil ? nil : GameDetail(game: gameToShowDetail!), isActive: $showGameDetail) {
                        EmptyView()
                    }
                }
            } else {
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
            }
        }
        .navigationTitle("Home")
        .onChange(of: ogs.isLoggedIn) { isLoggedIn in
            if isLoggedIn {
                isShowingThirdPartyLogin = false
            }
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            HomeView()
                .environmentObject(OGSService.previewInstance())
        }
    }
}
