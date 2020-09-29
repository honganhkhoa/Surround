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
    var reducesVerticalPadding = false
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
        let playerId = color == .black ? game.blackId : game.whiteId
        let pauseReason = game.pauseControl?.pauseReason(playerId: playerId)
        let clockStatus = { () -> AnyView in
            if pauseReason?.count ?? 0 > 0 {
                return AnyView(
                    erasing: Text(pauseReason ?? "").font(Font.footnote.bold())
                )
            } else if game.clock?.currentPlayerId == playerId {
                return AnyView(erasing: Image(systemName: "hourglass"))
            }
            return AnyView(EmptyView())
        }()
        
        return VStack(alignment: leftSide ? .leading : .trailing) {
            if showsPlayersName {
                HStack {
                    Text(playerName).font(Font.body.bold())
                    Text("[\(playerRank)]").font(Font.caption.bold())
                }
            }
            HStack {
                if !leftSide {
                    clockStatus
                }
                VStack(alignment: .trailing) {
                    TimerView(timeControl: game.gameData?.timeControl, clock: game.clock, player: color)
                    Text("\(captures) capture\(captures != 1 ? "s" : "")")
                        .font(Font.caption.monospacedDigit())
                    if let komi = game.gameData?.komi {
                        if color == .white && komi != 0 {
                            Text("\(String(format: "%.1f", komi)) komi")
                                .font(Font.caption.monospacedDigit())
                        }
                    }
                }
                if leftSide {
                    clockStatus
                }
            }
        }
    }
    
    func scoreColumn(color: StoneColor, leftSide: Bool) -> some View {
        let playerName = color == .black ? game.blackName : game.whiteName
        let playerRank = color == .black ? game.blackFormattedRank : game.whiteFormattedRank
        let scores = game.currentPosition.gameScores ?? game.gameData?.score
        let score = color == .black ? scores?.black : scores?.white
        
        let stoneRemovalStatus = { () -> AnyView in
            if let removedStonesAccepted = game.removedStonesAccepted[color] {
                if removedStonesAccepted == game.currentPosition.removedStones {
                    return AnyView(erasing: Image(systemName: "checkmark.circle.fill")
                        .font(Font.title3)
                        .foregroundColor(Color(UIColor.systemGreen))
                    )
                }
            }
            let stoneRemovalExpiration = { () -> AnyView in
                if let stoneRemovalTimeLeft = game.clock?.timeUntilExpiration {
                    return AnyView(
                        erasing: Text(timeString(timeLeft: stoneRemovalTimeLeft)).font(Font.footnote.bold())
                    )
                } else {
                    return AnyView(erasing: EmptyView())
                }
            }()
            return AnyView(erasing: HStack {
                if !leftSide {
                    stoneRemovalExpiration
                }
                Image(systemName: "hourglass")
                    .font(Font.title3)
                if leftSide {
                    stoneRemovalExpiration
                }
            })
        }()

        return VStack(alignment: leftSide ? .leading : .trailing) {
            if showsPlayersName {
                HStack {
                    Text(playerName).font(Font.body.bold())
                    Text("[\(playerRank)]").font(Font.caption.bold())
                }
            }
            if let score = score, let gameData = game.gameData {
                HStack {
                    if !leftSide && game.gamePhase == .stoneRemoval {
                        stoneRemovalStatus
                    }
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
                                Text("Stones")
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
                    if leftSide && game.gamePhase == .stoneRemoval {
                        stoneRemovalStatus
                    }
                }.padding([leftSide ? .leading : .trailing], 15)
            }
        }
    }
    
    var isPaused: Bool {
        game.pauseControl?.isPaused() ?? false
    }

    var body: some View {
        let foregroundColor = game.clock?.started ?? false ? UIColor.label : UIColor.systemIndigo
        return VStack(spacing: 0) {
            HStack {
                playerIcon(color: topLeftPlayerColor)
                Group {
                    if game.gamePhase == .play {
                        playerInfoColumn(color: topLeftPlayerColor, leftSide: true)
                            .foregroundColor(Color(foregroundColor))
                    } else {
                        scoreColumn(color: topLeftPlayerColor, leftSide: true)
                    }
                }.frame(height: playerIconSize)
                Spacer()
            }
            HStack {
                Spacer()
                Group {
                    if game.gamePhase == .play {
                        playerInfoColumn(color: topLeftPlayerColor.opponentColor(), leftSide: false)
                            .foregroundColor(Color(foregroundColor))
                    } else {
                        scoreColumn(color: topLeftPlayerColor.opponentColor(), leftSide: false)
                    }
                }.frame(height: playerIconSize)
                playerIcon(color: topLeftPlayerColor.opponentColor())
            }
            .offset(y: playerIconsOffset)
            .padding(.bottom, playerIconsOffset)
        }
        .padding(.vertical, reducesVerticalPadding ? 12 : 15)
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
