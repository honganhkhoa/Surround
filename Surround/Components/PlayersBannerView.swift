//
//  PlayersBannerView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 9/11/20.
//

import SwiftUI
import URLImage
import AVFoundation
import Combine

struct PlayersBannerView: View {
    @EnvironmentObject var ogs: OGSService
    @ObservedObject var game: Game
    @Environment(\.colorScheme) private var colorScheme
    var topLeftPlayerColor = StoneColor.black
    var reducesVerticalPadding = false
    var playerIconSize: CGFloat = 64
    var playerIconsOffset: CGFloat = -10
    var showsPlayersName = false
    @State var speechSynthesizer: AVSpeechSynthesizer?
    @State var lastUtterance: String?
    @State var clearLastUtteranceCancellable: AnyCancellable?
    @Setting(.voiceCountdown) var voiceCountdown: Bool
    
    var shouldShowNamesOutOfColumn: Bool {
        return playerIconsOffset + playerIconSize >= 30 && playerIconSize < 80
    }

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
    
    func playerName(color: StoneColor) -> some View {
        let playerName = color == .black ? game.blackName : game.whiteName
        let playerRank = color == .black ? game.blackFormattedRank : game.whiteFormattedRank
        
        return HStack {
            Text(playerName).font(Font.body.bold())
            Text("[\(playerRank)]").font(Font.caption.bold())
        }
    }

    func playerInfoColumn(color: StoneColor, leftSide: Bool) -> some View {
        let captures = game.currentPosition.captures[color] ?? 0
        let playerId = color == .black ? game.blackId : game.whiteId
        let pauseReason = game.pauseControl?.pauseReason(playerId: playerId)
        let timeUntilAutoResign = color == .black ? game.clock?.blackTimeUntilAutoResign : game.clock?.whiteTimeUntilAutoResign
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
            if showsPlayersName && !shouldShowNamesOutOfColumn {
                playerName(color: color)
            }
            HStack {
                if !leftSide {
                    clockStatus
                }
                VStack(alignment: .trailing) {
                    if let timeUntilAutoResign = timeUntilAutoResign {
                        Group {
                            Text("Disconnected")
                                .font(Font.subheadline.bold())
                            Label(timeString(timeLeft: timeUntilAutoResign), systemImage: "bolt.slash")
                                .font(Font.subheadline.bold().monospacedDigit())
                        }
                    } else {
                        TimerView(timeControl: game.gameData?.timeControl, clock: game.clock, player: color)
                    }
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
            if showsPlayersName && !shouldShowNamesOutOfColumn {
                playerName(color: color)
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
    
    func initializeSpeechSynthesizerIfNecessary() {
        if voiceCountdown && game.isUserPlaying && self.speechSynthesizer == nil {
            self.speechSynthesizer = AVSpeechSynthesizer()
        }
    }

    var body: some View {
        let foregroundColor = game.clock?.started ?? false ? UIColor.label : UIColor.systemIndigo
        let playersNameOutsideOfColumn = showsPlayersName && shouldShowNamesOutOfColumn
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
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
                if playersNameOutsideOfColumn {
                    playerName(color: topLeftPlayerColor)
                        .frame(height: 20)
                }
            }.padding(.bottom, playersNameOutsideOfColumn ? -30 : 0)
            VStack(alignment: .trailing, spacing: 5) {
                if playersNameOutsideOfColumn {
                    playerName(color: topLeftPlayerColor.opponentColor())
                        .frame(height: 20)
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
            }
            .offset(y: playerIconsOffset - (playersNameOutsideOfColumn ? 25 : 0))
            .padding(.bottom, playerIconsOffset - (playersNameOutsideOfColumn ? 25 : 0))
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
        .onAppear {
            initializeSpeechSynthesizerIfNecessary()
        }
        .onChange(of: voiceCountdown) { _ in
            DispatchQueue.main.async {
                initializeSpeechSynthesizerIfNecessary()
            }
        }
        .onDisappear {
            speechSynthesizer = nil
        }
        .onReceive(game.$clock) { clock in
            if let clock = clock {
                if voiceCountdown && game.isUserTurn {
                    let time = ogs.user?.id == game.blackId ? clock.blackTime : clock.whiteTime
                    var timeLeft = time.thinkingTimeLeft ?? .infinity
                    if timeLeft.isZero || timeLeft.isInfinite {
                        timeLeft = time.blockTimeLeft ?? .infinity
                    }
                    if timeLeft.isZero || timeLeft.isInfinite {
                        timeLeft = time.periodTimeLeft ?? .infinity
                    }
                    if timeLeft <= 10 {
                        let utteranceString = "\(Int(timeLeft))"
                        if utteranceString != lastUtterance {
                            lastUtterance = utteranceString
                            let utterance = AVSpeechUtterance(string: utteranceString)
                            self.speechSynthesizer?.speak(utterance)
                        }
                    }
                }
            }
        }
        .onChange(of: lastUtterance) { _ in
            if clearLastUtteranceCancellable != nil {
                clearLastUtteranceCancellable?.cancel()
            }
            clearLastUtteranceCancellable = Timer.publish(every: 3, on: .main, in: .common).autoconnect().sink(receiveValue: { _ in
                self.lastUtterance = nil
                self.clearLastUtteranceCancellable?.cancel()
                self.clearLastUtteranceCancellable = nil
            })
        }
    }}

struct PlayersBannerView_Previews: PreviewProvider {
    static var previews: some View {
        return Group {
            PlayersBannerView(game: TestData.Ongoing19x19wBot1)
                .previewLayout(.fixed(width: 320, height: 200))
            PlayersBannerView(game: TestData.Ongoing19x19wBot1, showsPlayersName: true)
                .previewLayout(.fixed(width: 320, height: 200))
            PlayersBannerView(game: TestData.Scored19x19Korean, playerIconSize: 96, showsPlayersName: true)
                .previewLayout(.fixed(width: 500, height: 300))
                .colorScheme(.dark)
        }
    }
}
