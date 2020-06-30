//
//  GameDetail.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/13/20.
//

import SwiftUI
import URLImage

struct PlayerInfo: View {
    @ObservedObject var game: Game
    var player: StoneColor
    
    var body: some View {
        let icon: String? = game.playerIcon(for: player, size: 64)
        return VStack(alignment: .leading) {
            HStack(alignment: .top) {
                ZStack {
                    if icon != nil {
                        URLImage(URL(string: icon!)!)
                            .frame(width: 64, height: 64)
                    }
                }
                Spacer()
                TimerView(timeControl: game.gameData?.timeControl, clock: game.clock, player: player)
            }
            Text(player == .black ? game.blackName : game.whiteName)
                .font(Font.caption.bold())
            +
            Text(" (\(player == .black ? game.blackFormattedRank : game.whiteFormattedRank))")
                .font(.caption)
        }

    }
}

struct GameDetail: View {
    @ObservedObject var game: Game
    
    var body: some View {
        return VStack(alignment: .center) {
            HStack {
                PlayerInfo(game: game, player: .black)
                Spacer()
                Divider()
                PlayerInfo(game: game, player: .white)
                Spacer()
            }.padding()
            BoardView(boardPosition: $game.currentPosition).layoutPriority(1)
            Spacer()
        }
    }
}

struct GameDetail_Previews: PreviewProvider {
    static var previews: some View {
        let game = TestData.Resigned19x19HandicappedWithInitialState
        return NavigationView {
            GameDetail(game: game)
                .navigationBarItems(trailing: Button(action: {}) {Text("Something...")})
        }
        
    }    
}
