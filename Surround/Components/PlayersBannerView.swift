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

    var body: some View {
        let topLeftCaptures = game.currentPosition.captures[topLeftPlayerColor] ?? 0
        let bottomRightCaptures = game.currentPosition.captures[topLeftPlayerColor.opponentColor()] ?? 0
        let players = [
            StoneColor.black: ["name": game.blackName, "rank": game.blackFormattedRank],
            StoneColor.white: ["name": game.whiteName, "rank": game.whiteFormattedRank]
        ]
        let topLeftPlayer = players[topLeftPlayerColor]!
        let bottomRightPlayer = players[topLeftPlayerColor.opponentColor()]!

        return VStack(spacing: 0) {
            HStack {
                playerIcon(color: topLeftPlayerColor)
                VStack(alignment: .leading) {
                    if showsPlayersName {
                        HStack {
                            Text(topLeftPlayer["name"]!).font(Font.body.bold())
                            Text("[\(topLeftPlayer["rank"]!)]").font(Font.caption.bold())
                        }
                    }
                    VStack(alignment: .trailing) {
                        TimerView(timeControl: game.gameData?.timeControl, clock: game.clock, player: topLeftPlayerColor)
                        if topLeftCaptures > 0 {
                            Text("\(topLeftCaptures) capture\(topLeftCaptures > 1 ? "s" : "")")
                                .font(Font.caption.monospacedDigit())
                        }
                        if let komi = game.gameData?.komi {
                            if topLeftPlayerColor == .white && komi != 0 {
                                Text("\(String(format: "%.1f", komi)) komi")
                                    .font(Font.caption.monospacedDigit())
                            }
                        }
                    }
                }.frame(height: playerIconSize)
                if game.clock?.currentPlayer == topLeftPlayerColor {
                    Image(systemName: "hourglass")
                }
                Spacer()
            }
            HStack {
                Spacer()
                if game.clock?.currentPlayer != topLeftPlayerColor {
                    Image(systemName: "hourglass")
                }
                VStack(alignment: .trailing) {
                    if showsPlayersName {
                        HStack {
                            Text(bottomRightPlayer["name"]!).font(Font.body.bold())
                            Text("[\(bottomRightPlayer["rank"]!)]").font(Font.caption.bold())
                        }
                    }
                    TimerView(timeControl: game.gameData?.timeControl, clock: game.clock, player: topLeftPlayerColor.opponentColor())
                    if bottomRightCaptures > 0 {
                        Text("\(bottomRightCaptures) capture\(bottomRightCaptures > 1 ? "s" : "")")
                            .font(.caption)
                    }
                    if let komi = game.gameData?.komi {
                        if topLeftPlayerColor.opponentColor() == .white && komi != 0 {
                            Text("\(String(format: "%.1f", komi)) komi")
                                .font(Font.caption.monospacedDigit())
                        }
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
            PlayersBannerView(game: TestData.Ongoing19x19wBot2, playerIconSize: 96, showsPlayersName: true)
                .previewLayout(.fixed(width: 500, height: 300))
                .colorScheme(.dark)
        }
    }
}
