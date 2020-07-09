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
    @State var publicGamesCancellable: AnyCancellable?    
    @State var selectedGameID: GameID? = nil
    
    var body: some View {
        Group {
            List(games) { game in
                NavigationLink(destination: GameDetail(game: game), tag: game.ID, selection: $selectedGameID) {
                    GameCell(game: game)
                }
                .onTapGesture {
                    self.selectedGameID = game.ID
                    self.gameDetailCancellable = OGSService.shared.getGameDetailAndConnect(gameID: game.gameData!.gameId).sink(receiveCompletion: { _ in
                    }, receiveValue: { value in
                    })
                }
            }
            .listStyle(GroupedListStyle())
        }
        .onAppear {
            print("Appeared \(self)")
            if self.games.count == 0 && self.publicGamesCancellable == nil {
                self.publicGamesCancellable = OGSWebSocket.shared.getPublicGamesAndConnect().sink(receiveCompletion: { completion in

                }) { games in
                    self.games = games
                }
            }
        }
        .onDisappear {
            print("Disappeared \(self) \(selectedGameID)")
            for game in games {
                if game.ID != selectedGameID {
                    OGSWebSocket.shared.disconnect(from: game)
                } else {
                    print("Skipped")
                }
            }
            DispatchQueue.main.async {
                games = []
                publicGamesCancellable = nil
                selectedGameID = nil
            }
        }
        .navigationBarTitle(Text("Public live games"))
        .navigationBarItems(trailing: Button(action: {
            OGSService.shared.logout()
        }, label: {
            Text("Logout")
        }))

    }
}

struct PublicGamesList_Previews: PreviewProvider {
    static var previews: some View {
        PublicGamesList()
    }
}
