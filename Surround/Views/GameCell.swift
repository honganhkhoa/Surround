//
//  GameCell.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/1/20.
//

import SwiftUI

struct GameCell: View {
    @ObservedObject var game: Game

    var body: some View {
        VStack {
            HStack {
                HStack {
                    Circle().fill(Color.black).frame(width: 15, height: 15)
                    VStack {
                        HStack {
                            Text(game.blackName)
                                .bold().lineLimit(1).font(.caption)
                            Text("(\(game.blackFormattedRank))")
                                .bold().lineLimit(1).font(.caption)
                        }
                        TimerView(timeControl: game.gameData?.timeControl, clock: game.clock, player: .black)
                    }
                    Spacer()
                }
                
                Divider()

                HStack {
                    ZStack {
                        Circle().fill(Color.white)
                        Circle().stroke(Color.black)
                    }.frame(width: 15, height: 15)
                    VStack {
                        HStack {
                            Text(game.whiteName)
                                .bold().lineLimit(1).font(.caption)
                            Text("(\(game.whiteFormattedRank))")
                                .bold().lineLimit(1).font(.caption)
                        }
                        TimerView(timeControl: game.gameData?.timeControl, clock: game.clock, player: .white)
                    }
                    Spacer()
                }
            }.layoutPriority(-1)
            ZStack {
                BoardView(boardPosition: $game.currentPosition)
                    .scaledToFit()
                if game.gameData?.outcome != nil {
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
            }
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
