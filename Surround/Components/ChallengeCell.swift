//
//  ChallengeCell.swift
//  Surround
//
//  Created by Anh Khoa Hong on 10/2/20.
//

import SwiftUI
import URLImage
import Combine

struct ChallengeCell: View {
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    var challenge: OGSChallenge
    @State var ogsRequestCancellable: AnyCancellable?
    
    func withdrawOrDeclineChallenge(challenge: OGSChallenge) {
        self.ogsRequestCancellable = ogs.withdrawOrDeclineChallenge(challenge: challenge)
            .zip(ogs.$challengesSent.setFailureType(to: Error.self))
            .sink(receiveCompletion: { _ in
                self.ogsRequestCancellable = nil
            }, receiveValue: { _ in})
    }
    
    func acceptChallenge(challenge: OGSChallenge) {
        self.ogsRequestCancellable = ogs.acceptChallenge(challenge: challenge)
            .zip(ogs.$challengesReceived.setFailureType(to: Error.self))
            .sink(receiveCompletion: { completion in
                print(completion)
                self.ogsRequestCancellable = nil
            }, receiveValue: { value in
                let newGameId = value.0
                self.ogsRequestCancellable?.cancel()
                self.ogsRequestCancellable = nil
                if !nav.main.showWaitingGames {  // Waiting games list view is meant to preserve context, so don't perform navigation when accepting games from there
                    withAnimation {
                        nav.home.ogsIdToOpen = newGameId
                        if challenge.challenged == nil {
                            nav.home.showingNewGameView = false
                        }
                    }
                }
            })
    }
    
    var playerInfos: some View {
        let isUserTheChallenger = challenge.challenger?.id == ogs.user?.id
        let challengerStoneColor = challenge.challengerColor
        
        return VStack {
            if let challenger = challenge.challenger {
                HStack(alignment: .top) {
                    if let iconURL = challenger.iconURL(ofSize: 64) {
                        ZStack(alignment: .bottomTrailing) {
                            URLImage(url: iconURL) { $0.resizable() }
                                .frame(width: 64, height: 64)
                                .background(Color.gray)
                            Stone(color: challengerStoneColor, shadowRadius: 1)
                                .frame(width: 20, height: 20)
                                .offset(x: 10, y: 10)
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(challenge.game.name)
                            .font(.headline)
                        HStack {
                            if challenger.icon == nil {
                                Stone(color: challengerStoneColor, shadowRadius: 1)
                                    .frame(width: 20, height: 20)
                            }
                            Text(challenger.username) +
                            Text(" [\(challenger.formattedRank)]")
                        }
                        if challenge.game.isPrivate {
                            Text("Private")
                                .italic()
                                .font(.subheadline)
                        }
                    }
                    Spacer()
                    if challenge.id != 0 {
                        if isUserTheChallenger {
                            if ogsRequestCancellable != nil {
                                ProgressView()
                            } else {
                                Button(action: { self.withdrawOrDeclineChallenge(challenge: challenge) }) {
                                    Text("Withdraw")
                                        .bold()
                                        .foregroundColor(.red)
                                }
                            }
                        } else if challenge.challenged == nil {
                            if ogsRequestCancellable != nil {
                                ProgressView()
                            } else {
                                Button(action: { acceptChallenge(challenge: challenge) }) {
                                    Text("Accept")
                                        .bold()
                                }
                            }
                        }
                    }
                }
                Spacer().frame(height: 15)
            }
            if let challenged = challenge.challenged {
                HStack(alignment: .top) {
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(challenged.username) +
                        Text(" [\(challenged.formattedRank)]")
                        if challenged.id == ogs.user?.id {
                            HStack {
                                Button(action: { self.withdrawOrDeclineChallenge(challenge: challenge) }) {
                                    Text("Reject")
                                        .bold()
                                        .foregroundColor(.red)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                                .hoverEffect(.highlight)
                                Button(action: { self.acceptChallenge(challenge: challenge) }) {
                                    Text("Accept")
                                        .bold()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                                .hoverEffect(.highlight)
                            }.offset(x: 10)
                        }
                    }
                    if let iconURL = challenged.iconURL(ofSize: 64) {
                        ZStack(alignment: .bottomLeading) {
                            URLImage(url: iconURL) { $0.resizable() }
                                .frame(width: 64, height: 64)
                                .background(Color.gray)
                            Stone(color: challengerStoneColor?.opponentColor(), shadowRadius: 1)
                                .frame(width: 20, height: 20)
                                .offset(x: -10, y: 10)
                        }
                    }
                }
                Spacer().frame(height: 15)
            }
        }
    }
    
    var body: some View {
        VStack {
            playerInfos
            Divider()
            if challenge.isUnusual {
                HStack {
                    VStack(alignment: .leading) {
                        if challenge.useCustomKomi {
                            Label("Custom komi: \(String(format: "%.1f", challenge.game.komi!))", systemImage: "exclamationmark.triangle.fill")
                        }
                        if challenge.hasHandicap {
                            Label("Has handicap: \(challenge.game.handicap)", systemImage: "exclamationmark.triangle.fill")
                        }
                        if challenge.game.timeControl.system.isUnusual {
                            Label("Unusual time settings", systemImage: "exclamationmark.triangle.fill")
                        }
                        if challenge.unusualBoardSize {
                            Label("Unusual board size: \(challenge.game.width)×\(challenge.game.height)", systemImage: "exclamationmark.triangle.fill")
                        }
                        Spacer().frame(height: 10)
                    }
                    .font(Font.subheadline.bold())
                    .foregroundColor(Color(.systemOrange))
                    Spacer()
                }
            }
            if let game = challenge.game {
                VStack(alignment: .leading, spacing: 3) {
                    Label{
                        HStack {
                            Text("\(game.width)×\(game.height) \(game.ranked ? "Ranked" : "Unranked")")
                            Spacer()
                            Text("Handicap: ").bold()
                                .offset(x: 8)
                            Text(game.handicap == -1 ? "Auto" : "\(game.handicap)")
                        }
                    } icon: {
                        Image(systemName: "squareshape.split.3x3")
                    }
                    Label {
                        HStack {
                            Text("Rules: ").bold() + Text(game.rules.fullName)
                            if game.komi != nil && game.komi != game.rules.defaultKomi {
                                Spacer()
                                Text("Komi: ").bold()
                                    .offset(x: 8)
                                Text(String(format: "%.1f", game.komi!))
                            }
                        }
                    } icon: {
                        Image(systemName: "text.badge.checkmark")
                    }
                    if let timeControl = game.timeControl {
                        Label {
                            VStack(alignment: .leading) {
                                Text("\(timeControl.systemName): \(timeControl.shortDescription)")
                                if (timeControl.pauseOnWeekends ?? false) && timeControl.speed == .correspondence {
                                    Text("Pause on weekend")
                                }
                            }
                            
                        } icon: {
                            Image(systemName: "clock")
                        }
                    } else {
                        Label("No time limits", systemImage: "clock")
                    }
                    Label("Analysis \(game.disableAnalysis ? "disabled" : "enabled")", systemImage: "arrow.triangle.branch")
                    if let minRank = game.minRank, let maxRank = game.maxRank {
                        if minRank > -1000 && maxRank < 1000 {
                            Label("\(RankUtils.formattedRank(Double(minRank), longFormat: true)) - \(RankUtils.formattedRank(Double(maxRank), longFormat: true))", systemImage: "arrow.up.and.down.square")
                        }
                    }
                }
                .font(.subheadline)
            }
        }
    }
}

struct ChallengeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            VStack {
                ChallengeCell(challenge: OGSChallenge.sampleOpenChallenge)
                    .padding()
                    .background(Color(UIColor.systemBackground).shadow(radius: 2))
            }
            .padding()
            VStack {
                ChallengeCell(challenge: OGSChallenge.sampleChallenge)
                    .padding()
                    .background(Color(UIColor.systemGray5).shadow(radius: 2))
            }
            .padding()
            .background(Color(UIColor.systemBackground))
            .colorScheme(.dark)
        }
        .previewLayout(.fixed(width: 320, height: 380))
        .environmentObject(
            OGSService.previewInstance(
                user: OGSUser(
                    username: "HongAnhKhoa",
                    id: 314459
                )
            )
        )
    }
}
