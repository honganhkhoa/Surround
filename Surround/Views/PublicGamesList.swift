//
//  PublicGamesList.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/1/20.
//

import SwiftUI
import Combine

struct PublicGamesList: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var ogs: OGSService
    @State var gameToShowDetail: Game? = nil
    @State var showDetail = false
    
    @SceneStorage("publicOGSGameIdToOpen")
    var publicOGSGameIdToOpen = -1 //27671778 //-1
    @State var gameDetailCancellable: AnyCancellable?
    
    var body: some View {
        Group {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))]) {
                    ForEach(ogs.sortedPublicGames) { game in
                        GameCell(game: game)
                            .onTapGesture {
                                self.gameToShowDetail = game
                                self.showDetail = true
                            }
                            .padding()
                    }
                }
                .background(Color(colorScheme == .dark ? UIColor.systemGray5 : UIColor.white))
                NavigationLink(destination: gameToShowDetail == nil ? nil : GameDetailView(currentGame: gameToShowDetail!), isActive: $showDetail) {
                    EmptyView()
                }
            }
        }
        .onAppear {
//            print("Appeared \(self)")
            ogs.fetchPublicGames()
            if publicOGSGameIdToOpen != -1 {
                self.gameDetailCancellable = ogs.getGameDetailAndConnect(gameID: publicOGSGameIdToOpen).sink(
                    receiveCompletion: { _ in
                        self.publicOGSGameIdToOpen = -1
                    },
                    receiveValue: { game in
                        if gameToShowDetail == nil {
                            gameToShowDetail = game
                            self.showDetail = true
                        }
                    })
            }
        }
        .navigationBarTitle(Text("Public live games"))
        .modifier(RootViewSwitchingMenu())
    }
}

struct PublicGamesList_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PublicGamesList()
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .environmentObject(
            OGSService.previewInstance(
                publicGames: [
                    TestData.Ongoing19x19HandicappedWithNoInitialState,
                    TestData.Scored15x17,
                    TestData.Resigned9x9Japanese,
                    TestData.StoneRemoval9x9
                ]
            )
        )
        .colorScheme(.dark)
    }
}
