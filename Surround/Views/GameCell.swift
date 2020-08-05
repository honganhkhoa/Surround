//
//  GameCell.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/1/20.
//

import SwiftUI

struct PlayerInfoLine: View {
    @ObservedObject var game: Game
    var color: StoneColor
    
    var body: some View {
        HStack {
            Stone(color: color, shadowRadius: 1).frame(width: 15, height: 15)
            HStack(alignment: .firstTextBaseline) {
                Text(color == .black ? game.blackName : game.whiteName)
                    .bold().lineLimit(1).font(.subheadline)
                Text("[\(color == .black ? game.blackFormattedRank : game.whiteFormattedRank)]")
                    .bold().lineLimit(1).font(.caption)
                Spacer()
                InlineTimerView(timeControl: game.gameData?.timeControl, clock: game.clock, player: color)
            }
        }
    }
}

struct GameCell: View {
    @ObservedObject var game: Game

    var gameOutCome: some View {
        VStack {
            if game.gameData?.winner == game.gameData?.players.black.id {
                Text("B+").font(.title).bold()
            } else {
                Text("W+").font(.title).bold()
            }
            Text(game.gameData?.outcome ?? "")
        }
        .padding()
        .background(Color.gray.opacity(0.9))
        .cornerRadius(5)
    }
    
    var body: some View {
        VStack {
            PlayerInfoLine(game: game, color: .black)
            ZStack {
                BoardView(boardPosition: game.currentPosition)
                    .scaledToFit()
                if game.gameData?.outcome != nil {
                    gameOutCome
                }
            }
            .frame(maxHeight: .infinity)
            PlayerInfoLine(game: game, color: .white)
        }
    }
}

struct GameCell_Previews: PreviewProvider {
    static var previews: some View {
        let game = TestData.Resigned19x19HandicappedWithInitialState
        return Group{
            List([game]) { _ in
                GameCell(game: game)
            }.listStyle(GroupedListStyle())
            List([game]) { _ in
                GameCell(game: game)
            }.listStyle(GroupedListStyle()).colorScheme(.dark)
        }.previewLayout(.fixed(width: 375, height: 500))
    }
}
