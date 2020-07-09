//
//  GameDetail.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/13/20.
//

import SwiftUI
import URLImage
import Combine

struct PlayerInfo: View {
    @ObservedObject var game: Game
    var player: StoneColor
    
    var body: some View {
        let icon: String? = game.playerIcon(for: player, size: 64)
        return VStack(alignment: .leading) {
            HStack(alignment: .top) {
                ZStack(alignment: .topLeading) {
                    if icon != nil {
                        URLImage(URL(string: icon!)!)
                            .frame(width: 64, height: 64)
                    }
                    Stone(color: player)
                        .background(Color.white.cornerRadius(10).shadow(radius: 1))
                        .frame(width: 20, height: 20)
                        .position(x: 62, y: 62)
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
    @State var gameDetailCancellable: AnyCancellable?
    
    var body: some View {
        var status = ""
        if let outcome = game.gameData?.outcome {
            if game.gameData?.winner == game.gameData?.blackPlayerId {
                status = "Black wins by \(outcome)"
            } else {
                status = "White wins by \(outcome)"
            }
        } else {
            if let currentPlayer = game.clock?.currentPlayer {
                status = "\(currentPlayer == .black ? "Black" : "White") to move"
            }
        }
        return VStack(alignment: .center) {
            HStack {
                PlayerInfo(game: game, player: .black)
                Spacer()
                Divider()
                PlayerInfo(game: game, player: .white)
                Spacer()
            }.padding()
            Text(status)
                .font(.headline).bold()
            BoardView(boardPosition: $game.currentPosition).layoutPriority(1)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GameDetail_Previews: PreviewProvider {
    static var previews: some View {
        let game = TestData.Resigned19x19HandicappedWithInitialState
        return GameDetail(game: game)
    }    
}
