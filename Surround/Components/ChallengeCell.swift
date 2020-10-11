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
    var challenge: OGSChallenge
    @State var ogsRequestCancellable: AnyCancellable?
    
    @SceneStorage("activeOGSGameIdToOpen")
    var activeOGSGameIdToOpen = -1

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
            .sink(receiveCompletion: { _ in
                self.ogsRequestCancellable = nil
            }, receiveValue: { value in
                let newGameId = value.0
                activeOGSGameIdToOpen = newGameId
                self.ogsRequestCancellable?.cancel()
                self.ogsRequestCancellable = nil
            })
    }
    
    var body: some View {
        let isUserTheChallenger = challenge.challenger?.id == ogs.user?.id
        let opponent = isUserTheChallenger ? challenge.challenged : challenge.challenger
        let opponentStoneColor = isUserTheChallenger ? challenge.challengerColor : challenge.challengerColor?.opponentColor() ?? nil
        
        return VStack {
            if let opponent = opponent {
                HStack(alignment: .top) {
                    if let iconURL = opponent.iconURL(ofSize: 64) {
                        ZStack(alignment: .bottomTrailing) {
                            URLImage(iconURL)
                                .frame(width: 64, height: 64)
                                .background(Color.gray)
                            if let opponentStoneColor = opponentStoneColor {
                                Stone(color: opponentStoneColor, shadowRadius: 1)
                                    .frame(width: 20, height: 20)
                                    .offset(x: 10, y: 10)
                            }
                        }
                    }
                    VStack(alignment: .leading) {
                        if let gameName = challenge.game?.name {
                            Text(gameName)
                                .font(.title3)
                                .bold()
                        }
                        HStack {
                            Text(opponent.username)
                            Text("[\(opponent.formattedRank)]")
                        }
                    }
                    Spacer()
                }
                Spacer().frame(height: 15)
            }
            if let game = challenge.game {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: "squareshape.split.3x3")
                        Text("\(game.width)×\(game.height) \(game.ranked ? "Ranked" : "Unranked")")
                        Spacer()
                        Text("Handicap: ").bold()
                            .offset(x: 8)
                        Text(game.handicap == -1 ? "Automatic" : "\(game.handicap)")
                    }
                    HStack {
                        Image(systemName: "text.badge.checkmark")
                        Text("Rules: ").bold()
                        Text(game.rules.fullName)
                            .offset(x: -8)
                        if let komi = game.komi {
                            Spacer()
                            Text("Komi: ").bold()
                                .offset(x: 8)
                            Text(String(format: "%.1f", komi))
                        }
                    }
                    if let timeControl = game.timeControl {
                        Label("\(timeControl.systemName): \(timeControl.shortDescription)", systemImage: "clock")
                        if timeControl.pauseOnWeekends ?? false {
                            HStack {
                                Image(systemName: "clock").foregroundColor(.clear)
                                Text("Pause on weekend")
                            }
                        }
                    } else {
                        Label("No time limits", systemImage: "clock")
                    }
                    Label("Analysis \(game.disableAnalysis ? "disabled" : "enabled")", systemImage: "arrow.triangle.branch")
                }
                .font(.subheadline)
            }
            HStack {
                Spacer()
                if ogsRequestCancellable != nil {
                    ProgressView().padding(10)
                } else {
                    if isUserTheChallenger {
                        Button(action: { self.withdrawOrDeclineChallenge(challenge: challenge) }) {
                            Text("Withdraw")
                                .foregroundColor(.red)
                        }
                        .padding(10)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                        .hoverEffect(.highlight)
                    } else {
                        Button(action: { self.withdrawOrDeclineChallenge(challenge: challenge) }) {
                            Text("Reject").foregroundColor(.red)
                        }
                        .padding(10)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                        .hoverEffect(.highlight)
                        Button(action: { self.acceptChallenge(challenge: challenge) }) {
                            Text("Accept")
                        }
                        .padding(10)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                        .hoverEffect(.highlight)
                    }
                }
            }
        }
    }
}

struct ChallengeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ChallengeCell(challenge: OGSChallenge.sampleChallenge)
                .padding()
        }
        .previewLayout(.fixed(width: 320, height: 300))
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
