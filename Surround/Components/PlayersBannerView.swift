//
//  PlayersBannerView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 9/11/20.
//

import SwiftUI
import URLImage

struct PlayersBannerView: View {
    @EnvironmentObject var ogs: OGSService
    @ObservedObject var game: Game
    @Environment(\.colorScheme) private var colorScheme
    var topLeftPlayerColor = StoneColor.black
    var reduceVerticalPadding = false
    var playerIconSize: CGFloat = 64
    var playerIconsOffset: CGFloat = -10
    var showsPlayersName = false

    func playerIcon(color: StoneColor) -> some View {
        let icon = game.playerIcon(for: color, size: Int(playerIconSize))
        return VStack {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if icon != nil {
                        URLImage(URL(string: icon!)!)
                    } else {
                        Color.gray
                    }
                }
                .background(Color.gray)
                .frame(width: playerIconSize, height: playerIconSize)
                .shadow(radius: 2)
                Stone(color: color, shadowRadius: 1)
                    .frame(width: 20, height: 20)
                    .offset(x: 10, y: 10)
            }
        }
    }

    func playerInfoColumn(color: StoneColor, leftSide: Bool) -> some View {
        let playerName = color == .black ? game.blackName : game.whiteName
        let playerRank = color == .black ? game.blackFormattedRank : game.whiteFormattedRank
        let captures = game.currentPosition.captures[color] ?? 0
        return VStack(alignment: leftSide ? .leading : .trailing) {
            if showsPlayersName {
                HStack {
                    Text(playerName).font(Font.body.bold())
                    Text("[\(playerRank)]").font(Font.caption.bold())
                }
            }
            VStack(alignment: .trailing) {
                TimerView(timeControl: game.gameData?.timeControl, clock: game.clock, player: color)
                if captures > 0 {
                    Text("\(captures) capture\(captures > 1 ? "s" : "")")
                        .font(Font.caption.monospacedDigit())
                }
                if let komi = game.gameData?.komi {
                    if color == .white && komi != 0 {
                        Text("\(String(format: "%.1f", komi)) komi")
                            .font(Font.caption.monospacedDigit())
                    }
                }
            }
        }
    }
    
    func scoreColumn(color: StoneColor, leftSide: Bool) -> some View {
        let playerName = color == .black ? game.blackName : game.whiteName
        let playerRank = color == .black ? game.blackFormattedRank : game.whiteFormattedRank
        let scores = game.currentPosition.gameScores ?? game.gameData?.score
        let score = color == .black ? scores?.black : scores?.white

        return VStack(alignment: leftSide ? .leading : .trailing) {
            if showsPlayersName {
                HStack {
                    Text(playerName).font(Font.body.bold())
                    Text("[\(playerRank)]").font(Font.caption.bold())
                }
            }
            if let score = score, let gameData = game.gameData {
                HStack {
                    VStack(alignment: .trailing) {
                        Group {
                            if gameData.scoreTerritory {
                                Text("\(score.territory)")
                            }
                            if gameData.scoreStones {
                                Text("\(score.stones)")
                            }
                            if gameData.scorePrisoners {
                                Text("\(score.prisoners)")
                            }
                            if score.komi > 0 {
                                Text("\(String(format: "%.1f", score.komi))")
                            }
                        }.font(Font.footnote.monospacedDigit())
                        Text("\((String(format: score.komi > 0 ? "%.1f" : "%.0f", score.total)))")
                            .font(Font.footnote.monospacedDigit().bold())
                    }
                    VStack(alignment: .leading) {
                        Group {
                            if gameData.scoreTerritory {
                                Text("Territory")
                            }
                            if gameData.scoreStones {
                                Text("Stone")
                            }
                            if gameData.scorePrisoners {
                                Text("Captures")
                            }
                            if score.komi > 0 {
                                Text("Komi")
                            }
                        }.font(Font.footnote)
                        Text("Total").font(Font.footnote.bold())
                    }
                }.padding([leftSide ? .leading : .trailing], 15)
            }
        }
    }
    
    var body: some View {
        var isPaused: Bool {
            game.gameData?.pauseControl?.isPaused() ?? false
        }
        
        return VStack(spacing: 0) {
            HStack {
                playerIcon(color: topLeftPlayerColor)
                Group {
                    if game.gameData?.phase == .play {
                        playerInfoColumn(color: topLeftPlayerColor, leftSide: true)
                    } else {
                        scoreColumn(color: topLeftPlayerColor, leftSide: true)
                    }
                }.frame(height: playerIconSize)
                if !isPaused && game.clock?.currentPlayer == topLeftPlayerColor {
                    Image(systemName: "hourglass")
                }
                Spacer()
            }
            HStack {
                Spacer()
                if !isPaused && game.clock?.currentPlayer != topLeftPlayerColor {
                    Image(systemName: "hourglass")
                }
                Group {
                    if game.gameData?.phase == .play {
                        playerInfoColumn(color: topLeftPlayerColor.opponentColor(), leftSide: false)
                    } else {
                        scoreColumn(color: topLeftPlayerColor.opponentColor(), leftSide: false)
                    }
                }.frame(height: playerIconSize)
                playerIcon(color: topLeftPlayerColor.opponentColor())
            }
            .offset(y: playerIconsOffset)
            .padding(.bottom, playerIconsOffset)
        }
        .padding(.vertical, reduceVerticalPadding ? 10 : 15)
        .padding(.horizontal)
        .background(
            LinearGradient(
                gradient: Gradient(
                    colors: colorScheme == .dark ?
                        [Color.black, Color(UIColor.darkGray)] :
                        [Color(UIColor.darkGray), Color.white]
                ),
                startPoint: topLeftPlayerColor == .black ? .topLeading : .bottomTrailing,
                endPoint: topLeftPlayerColor == .black ? .bottomTrailing : .topLeading)
                .shadow(radius: 2)
        )
    }}

struct PlayersBannerView_Previews: PreviewProvider {
    static var previews: some View {
        return Group {
            PlayersBannerView(game: TestData.Ongoing19x19wBot1)
                .previewLayout(.fixed(width: 320, height: 200))
            PlayersBannerView(game: TestData.Scored19x19Korean, playerIconSize: 96, showsPlayersName: true)
                .previewLayout(.fixed(width: 500, height: 300))
                .colorScheme(.dark)
        }
    }
}
