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
    @EnvironmentObject var nav: NavigationService
    
    @State var gameDetailCancellable: AnyCancellable?
    
    var body: some View {
        Group {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))]) {
                    ForEach(ogs.sortedPublicGames) { game in
                        GameCell(game: game)
                            .onTapGesture {
                                nav.publicGames.activeGame = game
                            }
                            .padding()
                    }
                }
                .background(Color(colorScheme == .dark ? UIColor.systemGray5 : UIColor.white))
                NavigationLink(
                    destination: GameDetailView(currentGame: nav.publicGames.activeGame),
                    isActive: Binding(
                        get: { nav.publicGames.activeGame != nil },
                        set: { if !$0 { nav.publicGames.activeGame = nil } }
                    )) {
                    EmptyView()
                }
            }
        }
        .onAppear {
//            print("Appeared \(self)")
            ogs.fetchPublicGames()
            if nav.publicGames.ogsIdToOpen != -1 {
                self.gameDetailCancellable = ogs.getGameDetailAndConnect(gameID: nav.publicGames.ogsIdToOpen).sink(
                    receiveCompletion: { _ in
                        nav.publicGames.ogsIdToOpen = -1
                    },
                    receiveValue: { game in
                        if nav.publicGames.activeGame == nil {
                            nav.publicGames.activeGame = game
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
        .environmentObject(NavigationService.shared)
        .colorScheme(.dark)
    }
}
