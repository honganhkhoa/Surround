//
//  HomeView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 7/10/20.
//

import SwiftUI
import Combine

struct HomeView: View {
    var games: [Game]
    @State var gameDetailCancellable: AnyCancellable?
    @State var showGameDetail = false
    @State var gameToShowDetail: Game? = nil

    var body: some View {
        Group {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))]) {
                    ForEach(games) { game in
                        GameCell(game: game)
                        .onTapGesture {
                            self.gameToShowDetail = game
                            self.showGameDetail = true
                            self.gameDetailCancellable = OGSService.shared.getGameDetailAndConnect(gameID: game.gameData!.gameId).sink(receiveCompletion: { _ in
                            }, receiveValue: { game in
                            })
                        }
                    }
                }.padding()
                NavigationLink(destination: gameToShowDetail == nil ? nil : GameDetail(game: gameToShowDetail!), isActive: $showGameDetail) {
                    EmptyView()
                }
            }
        }
        .navigationTitle("Home")
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView(games:[
            TestData.Ongoing19x19HandicappedWithNoInitialState,
            TestData.Resigned9x9Japanese
        ])
    }
}
