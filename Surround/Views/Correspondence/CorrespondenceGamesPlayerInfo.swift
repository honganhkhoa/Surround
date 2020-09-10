//
//  CorrespondenceGamesPlayerInfo.swift
//  Surround
//
//  Created by Anh Khoa Hong on 9/9/20.
//

import SwiftUI
import URLImage

struct CorrespondenceGamesPlayerInfo: View {
    @EnvironmentObject var ogs: OGSService
    @ObservedObject var currentGame: Game
    @Environment(\.colorScheme) private var colorScheme
    var reduceVerticalPadding = false
    var playerIconSize: CGFloat = 64
    var playerIconsOffset: CGFloat = -10
    var showsPlayersName = false

    func playerIcon(color: StoneColor) -> some View {
        let icon = currentGame.playerIcon(for: color, size: Int(playerIconSize))
        return VStack {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if icon != nil {
                        URLImage(URL(string: icon!)!)
                    } else {
                        Color.gray
                    }
                }
                .shadow(radius: 2)
                .frame(width: playerIconSize, height: playerIconSize)
                Stone(color: color, shadowRadius: 1)
                    .frame(width: 20, height: 20)
                    .offset(x: 10, y: 10)
            }
            .background(Color.gray)
            .frame(width: playerIconSize, height: playerIconSize)
        }
    }

    var body: some View {
        let userColor: StoneColor = currentGame.blackId == ogs.user?.id ? .black : .white
        let userCaptures = currentGame.currentPosition.captures[userColor] ?? 0
        let opponentCaptures = currentGame.currentPosition.captures[userColor.opponentColor()] ?? 0
        let users = [
            StoneColor.black: ["name": currentGame.blackName, "rank": currentGame.blackFormattedRank],
            StoneColor.white: ["name": currentGame.whiteName, "rank": currentGame.whiteFormattedRank]
        ]
        let user = users[userColor]!
        let opponent = users[userColor.opponentColor()]!

        return VStack(spacing: 0) {
            HStack {
                playerIcon(color: userColor)
                VStack(alignment: .leading) {
                    if showsPlayersName {
                        HStack {
                            Text(user["name"]!).font(Font.body.bold())
                            Text("[\(user["rank"]!)]").font(Font.caption.bold())
                        }
                    }
                    VStack(alignment: .trailing) {
                        TimerView(timeControl: currentGame.gameData?.timeControl, clock: currentGame.clock, player: userColor)
                        if userCaptures > 0 {
                            Text("\(userCaptures) capture\(userCaptures > 1 ? "s" : "")")
                                .font(Font.caption.monospacedDigit())
                        }
                        if let komi = currentGame.gameData?.komi {
                            if userColor == .white && komi != 0 {
                                Text("\(String(format: "%.1f", komi)) komi")
                                    .font(Font.caption.monospacedDigit())
                            }
                        }
                    }
                }
                if currentGame.clock?.currentPlayer == userColor {
                    Image(systemName: "hourglass")
                }
                Spacer()
            }
            HStack {
                Spacer()
                if currentGame.clock?.currentPlayer != userColor {
                    Image(systemName: "hourglass")
                }
                VStack(alignment: .trailing) {
                    if showsPlayersName {
                        HStack {
                            Text(opponent["name"]!).font(Font.body.bold())
                            Text("[\(opponent["rank"]!)]").font(Font.caption.bold())
                        }
                    }
                    TimerView(timeControl: currentGame.gameData?.timeControl, clock: currentGame.clock, player: userColor.opponentColor())
                    if opponentCaptures > 0 {
                        Text("\(opponentCaptures) capture\(opponentCaptures > 1 ? "s" : "")")
                            .font(.caption)
                    }
                    if let komi = currentGame.gameData?.komi {
                        if userColor.opponentColor() == .white && komi != 0 {
                            Text("\(String(format: "%.1f", komi)) komi")
                                .font(Font.caption.monospacedDigit())
                        }
                    }
                }
                playerIcon(color: userColor.opponentColor())
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
                startPoint: userColor == .black ? .topLeading : .bottomTrailing,
                endPoint: userColor == .black ? .bottomTrailing : .topLeading)
                .shadow(radius: 2)
        )
    }
}

struct CorrespondenceGamesPlayerInfo_Previews: PreviewProvider {
    static var previews: some View {
        let games = [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2, TestData.Ongoing19x19wBot3]
        return Group {
            CorrespondenceGamesPlayerInfo(currentGame: games[0])
                .previewLayout(.fixed(width: 320, height: 200))
            CorrespondenceGamesPlayerInfo(currentGame: games[0], playerIconSize: 96, showsPlayersName: true)
                .previewLayout(.fixed(width: 500, height: 300))
                .colorScheme(.dark)
        }
        .environmentObject(
            OGSService.previewInstance(
                user: OGSUser(username: "kata-bot", id: 592684),
                activeGames: games
            )
        )

    }
}
