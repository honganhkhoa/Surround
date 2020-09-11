//
//  LiveGameView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 9/11/20.
//

import SwiftUI

struct LiveGameView: View {
    @EnvironmentObject var ogs: OGSService
    @ObservedObject var game: Game
    
    var userColor: StoneColor {
        ogs.user?.id == game.blackId ? .black : .white
    }
    
    var body: some View {
        return VStack {
            PlayersBannerView(game: game, topLeftPlayerColor: userColor)
            
            BoardView(boardPosition: game.currentPosition)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LiveGameView_Previews: PreviewProvider {
    static var previews: some View {
        let games = [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2, TestData.Ongoing19x19wBot3]
        return Group {
            NavigationView {
                LiveGameView(game: games[0])
            }
        }
        .environmentObject(
            OGSService.previewInstance(
                user: OGSUser(username: "kata-bot", id: 592684),
                activeGames: games
            )
        )
    }
}
