//
//  PublicGamesList.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/1/20.
//

import SwiftUI
import Combine

struct PublicGamesList: View {
    @State var games: [Game] = []
    @State var gameDetailCancellable: AnyCancellable?
    
    @State var gameToShowDetail: Game?
    @State var showGameDetail = false
    
    var body: some View {
        Group {
            List(games) { game in
                GameCell(game: game)
            }
            .listStyle(GroupedListStyle())
            NavigationLink(destination: gameToShowDetail == nil ? nil : GameDetail(game: gameToShowDetail!), isActive: self.$showGameDetail) {
                EmptyView()
            }
        }
        .onAppear {
//            OGSWebSocket.shared.getPublicGames { games in
//                for game in games {
//                    OGSWebSocket.shared.connect(to: game)
//                }
//                self.games = games
//            }
            self.gameDetailCancellable = OGSService.shared.getGameDetail(gameID: 24129283)
                .sink(receiveCompletion: { completion in
                    
                }, receiveValue: { game in
                    OGSWebSocket.shared.connect(to: game)
                    self.gameToShowDetail = game
                    self.showGameDetail = true
                })
        }

    }
}

struct PublicGamesList_Previews: PreviewProvider {
    static var previews: some View {
        PublicGamesList()
    }
}
