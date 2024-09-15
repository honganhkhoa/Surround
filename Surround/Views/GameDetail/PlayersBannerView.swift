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
    @State var showsRengoTeamDetail = false
    
    @Namespace var avatars
    
    var showCompactModeSwitcher: Binding<Bool> = .constant(true)
    
    var shouldShowNamesOutOfColumn: Bool {
        return playerIconsOffset + playerIconSize >= 30 && playerIconSize < 80
    }

    func singlePlayerIcon(color: StoneColor) -> some View {
        let icon = game.playerIcon(for: color, size: Int(playerIconSize))
        let player = color == .black ? game.blackPlayer : game.whitePlayer
        return VStack {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let icon = icon {
                        AsyncImage(url: URL(string: icon)!) {
                            $0.resizable()
                        } placeholder: {
                            Color.gray
                        }
                    } else {
                        Color.gray
                    }
                }
                .background(Color.gray)
                .frame(width: playerIconSize, height: playerIconSize)
                .border(player?.uiColor ?? .black, width: 1)
                .shadow(radius: 2)
                .matchedGeometryEffect(id: player?.id ?? 0, in: avatars)
                Stone(color: color, shadowRadius: 1)
                    .frame(width: 20, height: 20)
                    .offset(x: 10, y: 10)
            }
        }
    }
    
    @ViewBuilder
    func rengoTeamIcon(color: StoneColor) -> some View {
        if let players = game.orderedRengoTeam[color], let originalRengoTeam = game.gameData?.rengoTeams?[color] {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    ForEach(originalRengoTeam, id: \.id) { player in
                        if let index = players.firstIndex(where: { $0.id == player.id }) {
                            Group {
                                if let icon = player.iconURL(ofSize: Int(playerIconSize)) {
                                    AsyncImage(url: icon) { $0.resizable() } placeholder: { Color.gray }
                                }
                            }
                            .frame(
                                width: playerIconSize * (index == 1 ? 0.6 : index == 0 ? 0.7 : 0.1),
                                height: playerIconSize * (index == 1 ? 0.6 : index == 0 ? 0.7 : 0.1))
                            .border(player.uiColor, width: 1)
                            .offset(
                                x: playerIconSize * (index == 1 ? -0.2 : index == 0 ? 0.15 : 0.4),
                                y: playerIconSize * (index == 1 ? -0.2 : index == 0 ? 0.15 : -0.4)
                            )
                            .zIndex(-CGFloat(index))
                            .shadow(radius: 2)
                            .id(player.id)
                            .matchedGeometryEffect(id: player.id, in: avatars)
                        }
                    }
                }
                .frame(width: playerIconSize, height: playerIconSize)
                Stone(color: color, shadowRadius: 1)
                    .frame(width: 20, height: 20)
                    .offset(x: 10, y: playerIconSize - 10)

                if players.count > 2 {
                    Text(verbatim: "+\(players.count - 2)")
                        .font(.caption.bold().monospacedDigit())
                        .padding(.horizontal, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(.black, lineWidth: 0.5)
                                .shadow(radius: 2)
                        )
                        .background(Color.gray.cornerRadius(5).shadow(radius: 2))
                }
            }
            .onTapGesture {
                self.showsRengoTeamDetail = true
                self.showCompactModeSwitcher.wrappedValue = false
            }
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    func playerIcon(color: StoneColor) -> some View {
        if !game.rengo || game.orderedRengoTeam[color]?.count == 1 {
            singlePlayerIcon(color: color)
        } else {
            rengoTeamIcon(color: color)
        }
    }
    
    @ViewBuilder
    func playerName(color: StoneColor) -> some View {
        if game.rengo {
            if let player = game.orderedRengoTeam[color]?.first, let teamSize = game.orderedRengoTeam[color]?.count {
                Text(verbatim: player.usernameAndRank).font(Font.body.bold()) +
                 (teamSize <= 1 ? Text(verbatim: "") : (Text(verbatim: " + \(teamSize - 1)×") + Text(Image(systemName: "person.fill"))))
            } else {
                EmptyView()
            }
        } else if let player = color == .black ? game.blackPlayer : game.whitePlayer {
            Text(verbatim: player.usernameAndRank).font(Font.body.bold())
        } else {
            EmptyView()
        }
    }

    func playerInfoColumn(color: StoneColor, leftSide: Bool) -> some View {
        let captures = game.currentPosition.captures[color] ?? 0
        let playerId = game.currentPlayer(with: color)?.id ?? -1
        let pauseReason = game.pauseControl?.pauseReason(playerId: playerId)
        let timeUntilAutoResign = color == .black ? game.clock?.blackTimeUntilAutoResign : game.clock?.whiteTimeUntilAutoResign
        let clockStatus = { () -> AnyView in
            if pauseReason?.count ?? 0 > 0 {
                return AnyView(
                    erasing: Text(pauseReason ?? "").font(Font.footnote.bold())
                )
            } else if game.clock?.currentPlayerColor == color {
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
                    Text("\(captures) captures", comment: "show captures in player banner view")
                        .font(Font.caption.monospacedDigit())
                    if let komi = game.gameData?.komi {
                        if color == .white && komi != 0 {
                            Text("\(komi, specifier: "%.1f") komi")
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
    
    @ViewBuilder
    var stoneRemovalExpiration: some View {
        if let stoneRemovalTimeLeft = game.clock?.timeUntilExpiration {
            Text(timeString(timeLeft: stoneRemovalTimeLeft))
                .font(Font.footnote.bold())
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    @ViewBuilder
    func stoneRemovalStatus(color: StoneColor, leftSide: Bool) -> some View {
        if let removedStonesAccepted = game.removedStonesAccepted[color], removedStonesAccepted == game.currentPosition.removedStones {
            Image(systemName: "checkmark.circle.fill")
                .font(Font.title3)
                .foregroundColor(Color(UIColor.systemGreen))
        } else {
            HStack {
                if leftSide {
                    Image(systemName: "hourglass")
                        .font(Font.title3)
                } else {
                    Spacer()
                }
                stoneRemovalExpiration
                if !leftSide {
                    Image(systemName: "hourglass")
                        .font(Font.title3)
                } else {
                    Spacer()
                }
            }.frame(maxWidth: .infinity)
        }
    }
    
    func scoreColumn(color: StoneColor, leftSide: Bool) -> some View {
        let scores = game.currentPosition.gameScores ?? game.gameData?.score
        let score = color == .black ? scores?.black : scores?.white
        
        return VStack(alignment: leftSide ? .leading : .trailing) {
            if showsPlayersName && !shouldShowNamesOutOfColumn {
                playerName(color: color)
            }
            if let score = score, let gameData = game.gameData {
                HStack {
                    if !leftSide && game.gamePhase == .stoneRemoval {
                        stoneRemovalStatus(color: color, leftSide: leftSide)
                    }
                    VStack(alignment: .trailing) {
                        Group {
                            if gameData.scoreTerritory {
                                Text(verbatim: "\(score.territory)")
                            }
                            if gameData.scoreStones {
                                Text(verbatim: "\(score.stones)")
                            }
                            if gameData.scorePrisoners {
                                Text(verbatim: "\(score.prisoners)")
                            }
                            if score.komi > 0 {
                                Text(verbatim: "\(String(format: "%.1f", score.komi))")
                            }
                        }.font(Font.footnote.monospacedDigit())
                        Text(verbatim: "\((String(format: score.komi > 0 ? "%.1f" : "%.0f", score.total)))")
                            .font(Font.footnote.monospacedDigit().bold())
                    }
                    VStack(alignment: .leading) {
                        Group {
                            if gameData.scoreTerritory {
                                Text("Territory", comment: "In PlayersBannerView, label for territory count")
                            }
                            if gameData.scoreStones {
                                Text("Stones", comment: "In PlayersBannerView, label for stone count")
                            }
                            if gameData.scorePrisoners {
                                Text("Captures")
                            }
                            if score.komi > 0 {
                                Text("Komi")
                            }
                        }.font(Font.footnote)
                        Text("Total", comment: "In PlayersBannerView, label for total points").font(Font.footnote.bold())
                    }
                    if leftSide && game.gamePhase == .stoneRemoval {
                        stoneRemovalStatus(color: color, leftSide: leftSide)
                    }
                }
                .padding([leftSide ? .leading : .trailing], 15)
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
    
    @ViewBuilder
    func rengoPlayerDetails(for player: OGSUser, alignment: HorizontalAlignment = .leading) -> some View {
        HStack {
            if alignment == .trailing {
                Text(verbatim: player.usernameAndRank).font(.subheadline.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

            }
            Group {
                if let iconURL = player.iconURL(ofSize: 40) {
                    AsyncImage(url: iconURL) {
                        $0.resizable()
                    } placeholder: {
                        Color.gray
                    }
                } else {
                    Color.gray
                }
            }
            .border(player.uiColor, width: 1)
            .frame(width: 40, height: 40)
            .shadow(radius: 2)
            .matchedGeometryEffect(id: player.id, in: avatars)
            if alignment != .trailing {
                Text(verbatim: player.usernameAndRank).font(.subheadline.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
    
    @ViewBuilder
    var rengoTeamDetails: some View {
        if let leftTeam = game.orderedRengoTeam[topLeftPlayerColor], let rightTeam = game.orderedRengoTeam[topLeftPlayerColor.opponentColor()] {
            VStack(spacing: 0) {
                Spacer().frame(height: verticalPadding)
                HStack(spacing: 0) {
                    VStack(alignment: .leading) {
                        HStack {
                            (Text(verbatim: "\(leftTeam.count)×") + Text(Image(systemName: "person.fill")))
                                .font(.subheadline)
                            Stone(color: topLeftPlayerColor, shadowRadius: 2)
                                .frame(width: 20, height: 20)
                            InlineTimerView(
                                timeControl: game.gameData?.timeControl,
                                clock: game.clock,
                                player: topLeftPlayerColor,
                                mainFont: .subheadline,
                                subFont: .footnote,
                                pauseControl: game.pauseControl,
                                showsPauseReason: true)
                        }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(leftTeam, id: \.id) { player in
                                    rengoPlayerDetails(for: player)
                                }
                            }
                            Spacer()
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing) {
                        HStack {
                            InlineTimerView(
                                timeControl: game.gameData?.timeControl,
                                clock: game.clock,
                                player: topLeftPlayerColor.opponentColor(),
                                mainFont: .subheadline,
                                subFont: .footnote,
                                pauseControl: game.pauseControl,
                                showsPauseReason: true
                            )
                            Stone(color: topLeftPlayerColor.opponentColor(), shadowRadius: 2)
                                .frame(width: 20, height: 20)
                            (Text(verbatim: "\(rightTeam.count)×") + Text(Image(systemName: "person.fill")))
                                .font(.subheadline)
                        }
                        ScrollView {
                            VStack(alignment: .trailing, spacing: 5) {
                                ForEach(rightTeam, id: \.id) { player in
                                    rengoPlayerDetails(for: player, alignment: .trailing)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
            .onTapGesture {
                self.showCompactModeSwitcher.wrappedValue = true
                self.showsRengoTeamDetail = false
            }
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    var playersSummary: some View {
        VStack(spacing: 0) {
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
    }
    
    var foregroundColor: UIColor {
        return game.clock?.started ?? false ? UIColor.label : UIColor.systemIndigo
    }
    
    var playersNameOutsideOfColumn: Bool {
        showsPlayersName && shouldShowNamesOutOfColumn
    }
    
    var verticalPadding: CGFloat {
        reducesVerticalPadding ? 12 : 15
    }

    var body: some View {
        Group {
            if showsRengoTeamDetail {
                rengoTeamDetails
            } else {
                playersSummary
            }
        }
        .animation(.linear, value: game.orderedRengoTeam)
        .animation(.linear, value: showsRengoTeamDetail)
        .padding(.vertical, showsRengoTeamDetail ? 0 : verticalPadding)
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
                    let time = game.userStoneColor == .black ? clock.blackTime : clock.whiteTime
                    if let timeLeft = time.timeLeft {
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
        let game3 = TestData.Scored19x19Korean
        game3.gamePhase = .stoneRemoval
        return Group {
            PlayersBannerView(game: TestData.Rengo2v2, showsRengoTeamDetail: false)
                .previewLayout(.fixed(width: 320, height: 200))
//                .colorScheme(.dark)
            PlayersBannerView(game: TestData.Rengo3v1, showsPlayersName: true)
                .previewLayout(.fixed(width: 320, height: 200))
//            PlayersBannerView(game: TestData.Ongoing19x19wBot1)
//                .previewLayout(.fixed(width: 320, height: 200))
//            PlayersBannerView(game: TestData.Ongoing19x19wBot1, showsPlayersName: true)
//                .previewLayout(.fixed(width: 320, height: 200))
//            PlayersBannerView(game: game3, playerIconSize: 96, showsPlayersName: true)
//                .previewLayout(.fixed(width: 500, height: 300))
//                .colorScheme(.dark)
        }
    }
}
