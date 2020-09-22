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
    @State var showCorrespondenceGameDetail = false
    @State var correspondenceGameToShowDetail: Game? = nil
    @State var showLiveGameDetail = false
    @State var liveGameToShowDetail: Game? = nil

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
            GroupBox(label: Text("Sign in to your online-go.com account to see your games here.").fixedSize(horizontal: false, vertical: true)) {
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
    
    func showCorrespondenceGameDetail(game: Game) {
        self.correspondenceGameToShowDetail = game
        self.showCorrespondenceGameDetail = true
    }

    func showLiveGameDetail(game: Game) {
        self.liveGameToShowDetail = game
        self.showLiveGameDetail = true
    }

    var activeGamesView: some View {
        Group {
            if ogs.sortedActiveCorrespondenceGames.count + ogs.liveGames.count == 0 {
                ProgressView()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], pinnedViews: [.sectionHeaders]) {
                        if ogs.liveGames.count > 0 {
                            Section(header: sectionHeader(title: "Live games")) {
                                ForEach(ogs.liveGames) { game in
                                    GameCell(game: game, displayMode: displayMode)
                                    .onTapGesture {
                                        showLiveGameDetail(game: game)
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
                                    showCorrespondenceGameDetail(game: game)
                                }
                                .padding(.vertical, displayMode == .full ? nil : 0)
                                .padding(.horizontal)
                            }
                        }
                        Section(header: sectionHeader(title: "Opponents' move")) {
                            ForEach(ogs.sortedActiveCorrespondenceGamesNotOnUserTurn) { game in
                                GameCell(game: game, displayMode: displayMode)
                                .onTapGesture {
                                    self.showCorrespondenceGameDetail(game: game)
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
        
    var body: some View {
        VStack {
            if ogs.isLoggedIn {
                activeGamesView
            } else {
                loginView
            }
            NavigationLink(destination: correspondenceGameToShowDetail == nil ? nil : CorrespondenceGamesView(currentGame: correspondenceGameToShowDetail!), isActive: $showCorrespondenceGameDetail) {
                EmptyView()
            }
            NavigationLink(destination: liveGameToShowDetail == nil ? nil : LiveGameView(game: liveGameToShowDetail!), isActive: $showLiveGameDetail) {
                EmptyView()
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
        }.colorScheme(.dark)
    }
}
