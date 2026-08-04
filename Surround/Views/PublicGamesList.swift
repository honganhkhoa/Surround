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
                        Button(action: { nav.publicGames.activeGame = game }) {
                            GameCell(game: game)
                        }
                        .accessibilityIdentifier(
                            SurroundUITestContract.AccessibilityID.publicGame(game)
                        )
                        .buttonStyle(.plain)
                        .padding()
                    }
                }
                .background(Color(colorScheme == .dark ? UIColor.systemGray5 : UIColor.white))
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { nav.publicGames.activeGame != nil },
            set: { if !$0 { nav.publicGames.activeGame = nil } }
        ), destination: {
            GameDetailView(currentGame: nav.publicGames.activeGame)
        })
        .onAppear {
//            print("Appeared \(self)")
            ogs.fetchPublicGames()
            if nav.publicGames.ogsIdToOpen != -1 {
                self.gameDetailCancellable = ogs.getGameDetail(gameID: nav.publicGames.ogsIdToOpen).sink(
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
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.screenPublicGames)
    }
}

#if DEBUG
private func publicGamesPreview(games: [Game]) -> some View {
    let nav = NavigationService()
    nav.main.rootView = .publicGames
    return NavigationStack {
        PublicGamesList()
            .modifier(RootViewSwitchingMenu())
    }
    .environmentObject(OGSService.previewInstance(publicGames: games))
    .environmentObject(nav)
}

#Preview("Public games — Loaded") {
    publicGamesPreview(
        games: [
            TestData.Ongoing19x19HandicappedWithNoInitialState,
            TestData.Scored15x17,
            TestData.Resigned9x9Japanese,
            TestData.StoneRemoval9x9,
        ]
    )
    .preferredColorScheme(.dark)
}

#Preview("Public games — Empty") {
    publicGamesPreview(games: [])
}
#endif
