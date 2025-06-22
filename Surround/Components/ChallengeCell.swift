//
//  ChallengeCell.swift
//  Surround
//
//  Created by Anh Khoa Hong on 10/2/20.
//

import SwiftUI
import Combine

struct RengoPlayerCard: View {
    @EnvironmentObject var ogs: OGSService
    var challenge: any OGSChallenge
    var player: OGSUser
    var color: StoneColor?
    @State var playerAsssignCancellable: AnyCancellable?
    
    func assignPlayer(to newColor: StoneColor?) {
        if let challenge = challenge as? OGSSeekgraphChallenge {
            playerAsssignCancellable = ogs.assignRengoTeam(challenge: challenge, player: player, color: newColor).sink(receiveCompletion: { completion in
                playerAsssignCancellable = nil
            }, receiveValue: {
                playerAsssignCancellable = nil
            })
        }
    }
    
    var body: some View {
        HStack(spacing: 1) {
            Menu {
                Text(verbatim: "\(player.usernameAndRank)")
                if let userId = ogs.user?.id, challenge.challenger?.id == userId {
                    Divider()
                    if color != .black {
                        Button(action: { assignPlayer(to: .black) }) {
                            Label("Move to Black team", systemImage: "arrow.up")
                        }
                    }
                    if color != .white {
                        if color == nil {
                            Button(action: { assignPlayer(to: .white) }) {
                                Label("Move to White team", systemImage: "arrow.up")
                            }
                        } else {
                            Button(action: { assignPlayer(to: .white) }) {
                                Label("Move to White team", systemImage: "arrow.down")
                            }
                        }
                    }
                    if color != nil {
                        Button(action: { assignPlayer(to: nil) }) {
                            Label("Unassign", systemImage: "arrow.down")
                        }
                    }
                }
            } label: {
                AsyncImage(url: player.iconURL(ofSize: 40)) { $0.resizable() } placeholder: { Color.gray }
                .frame(width: 40, height: 40)
            }
            if playerAsssignCancellable == nil {
                if !Setting(.hidesRank).wrappedValue {
                    Text(verbatim: "[\(player.formattedRank)]")
                        .font(.caption).bold()
                        .foregroundColor(player.uiColor)
                }
            } else {
                ProgressView()
            }
        }
    }
}

struct RengoPlayersDetail: View {
    @EnvironmentObject var ogs: OGSService
    var challenge: any OGSChallenge
    
    @Namespace var playerCards

    var body: some View {
        if let blackTeam = challenge.game.rengoBlackTeam, let whiteTeam = challenge.game.rengoWhiteTeam, let nominees = challenge.game.rengoNominees, let userId = ogs.user?.id {
            VStack(alignment: .leading, spacing: 0) {
                Label(challenge.game.name, systemImage: "person.2.fill")
                .font(.body.bold())
                .foregroundColor(Color(.systemPurple))
                Spacer().frame(height: 10)
                if challenge.game.rengoCasualMode ?? false {
                    (Text("**Casual**").font(.subheadline) + Text(" — players may drop mid-game").font(.caption))
                        .leadingAlignedInScrollView()
                    if let autoStart = challenge.game.rengoAutoStart, autoStart > 0 {
                        Spacer().frame(height: 5)
                        Text("Game starts automatically when there are **\(autoStart)** players.")
                            .font(.subheadline)
                            .leadingAlignedInScrollView()
                    }
                    Spacer().frame(height: 10)
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Stone(color: .black, shadowRadius: 2)
                            .frame(width: 15, height: 15)
                        (Text(verbatim: "\(blackTeam.count)×") + Text(Image(systemName: "person.fill")))
                            .font(.subheadline)
                        Spacer()
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 5) {
                            Spacer().frame(width: 0)
                            Rectangle().fill(.black).frame(width: 3, height: 40)
                            ForEach(blackTeam, id: \.self) { playerId in
                                if let player = ogs.cachedUsersById[playerId] {
                                    RengoPlayerCard(challenge: challenge, player: player, color: .black)
                                        .matchedGeometryEffect(id: player.id, in: playerCards)
                                }
                            }
                            Spacer()
                        }
                    }.padding(.trailing, -16)
                    HStack {
                        Stone(color: .white, shadowRadius: 2)
                            .frame(width: 15, height: 15)
                        (Text(verbatim: "\(whiteTeam.count)×") + Text(Image(systemName: "person.fill")))
                            .font(.subheadline)
                        Spacer()
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 5) {
                            Spacer().frame(width: 0)
                            Rectangle().fill(.white).border(.black, width: 0.5 ).frame(width: 3, height: 40)
                            ForEach(whiteTeam, id: \.self) { playerId in
                                if let player = ogs.cachedUsersById[playerId] {
                                    RengoPlayerCard(challenge: challenge, player: player, color: .white)
                                        .matchedGeometryEffect(id: player.id, in: playerCards)
                                }
                            }
                            Spacer()
                        }
                    }.padding(.trailing, -16)
                    if nominees.count > 0 || challenge.challenger?.id == userId {
                        HStack {
                            Stone(color: nil, shadowRadius: 2)
                                .frame(width: 15, height: 15)
                            (Text(verbatim: "\(nominees.count)×") + Text(Image(systemName: "person.fill")))
                                .font(.subheadline)
                            Spacer()
                        }
                        ScrollView(.horizontal) {
                            HStack(spacing: 5) {
                                Spacer().frame(width: 0)
                                Rectangle().fill(.gray).frame(width: 3, height: 40)
                                ForEach(nominees, id: \.self) { playerId in
                                    if let player = ogs.cachedUsersById[playerId] {
                                        RengoPlayerCard(challenge: challenge, player: player, color: nil)
                                            .matchedGeometryEffect(id: player.id, in: playerCards)
                                    }
                                }
                                Spacer()
                            }
                        }.padding(.trailing, -16)
                    }
                }
                .animation(.easeInOut, value: challenge.game.rengoWhiteTeam)
                .animation(.easeInOut, value: challenge.game.rengoBlackTeam)
                .animation(.easeInOut, value: challenge.game.rengoNominees)
            }
        }
    }
}

struct RengoActions: View {
    var challenge: OGSSeekgraphChallenge
    @EnvironmentObject var ogs: OGSService
    @State var ogsRequestCancellable: AnyCancellable?
    @EnvironmentObject var nav: NavigationService

    func joinRengoChallenge() {
        self.ogsRequestCancellable = ogs.joinRengoChallenge(challenge: challenge)
            .sink(receiveCompletion: { completion in
                self.ogsRequestCancellable = nil
            }, receiveValue: {
                self.ogsRequestCancellable = nil
            })
    }
    
    func leaveRengoChallenge() {
        self.ogsRequestCancellable = ogs.leaveRengoChallenge(challenge: challenge)
            .sink(receiveCompletion: {  completion in
                self.ogsRequestCancellable = nil
            }, receiveValue: {
                self.ogsRequestCancellable = nil
            })
    }
    
    func cancelRengoChallenge() {
        self.ogsRequestCancellable = ogs.withdrawOrDeclineChallenge(challenge: challenge)
            .zip(ogs.$hostingRengoChallengeById.setFailureType(to: Error.self))
            .sink(receiveCompletion: { completion in
                self.ogsRequestCancellable = nil
            }, receiveValue: { _ in})
    }
    
    func startRengoGame() {
        self.ogsRequestCancellable = ogs.startRengoGame(challenge: challenge)
            .zip(ogs.$hostingRengoChallengeById.setFailureType(to: Error.self))
            .sink(receiveCompletion: { completion in
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

    var body: some View {
        if let participants = challenge.game.rengoParticipants, let userId = ogs.user?.id, let host = challenge.challenger {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    if ogsRequestCancellable != nil {
                        ProgressView()
                    } else {
                        if userId == host.id {
                            HStack {
                                Button(role: .destructive, action: { cancelRengoChallenge() }) {
                                    Text("Cancel").bold()
                                }
                                Spacer()
                                Button(action: { startRengoGame() }) {
                                    Text("Start").bold()
                                }
                                .disabled(!challenge.game.rengoReadyToStart)
                            }
                        } else {
                            if participants.firstIndex(of: userId) == nil {
                                HStack {
                                    Spacer()
                                    Button(action: { joinRengoChallenge() }) {
                                        Text("Join", comment: "joinRengoChallenge").bold()
                                    }
                                }
                            } else {
                                Button(role: .destructive, action: { leaveRengoChallenge() }) {
                                    Text("Leave", comment: "leaveRengoChallenge").bold()
                                }
                            }
                        }
                    }
                    Spacer()
                }
                if userId == host.id {
                    Text("Tap on avatars to assign players into teams.")
                        .font(.subheadline)
                        .leadingAlignedInScrollView()
                } else if participants.firstIndex(of: userId) != nil {
                    Text("Waiting for players to join and the organizer to start the game.")
                        .font(.subheadline)
                        .leadingAlignedInScrollView()
                    NavigationLink(
                        destination: PrivateMessageLog(peer: host)
                            .navigationBarTitle(host.username)
                            .navigationBarTitleDisplayMode(.inline)
                    ) {
                        (Text("Message organizer") + Text(Image(systemName: "chevron.forward")))
                            .font(.subheadline.bold())
                            .leadingAlignedInScrollView()
                    }
                }
            }
        }
    }
}

struct ChallengeCell: View {
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    var challenge: any OGSChallenge
    @State var ogsRequestCancellable: AnyCancellable?
        
    func withdrawOrDeclineChallenge(challenge: any OGSSubmittedChallenge) {
        self.ogsRequestCancellable = ogs.withdrawOrDeclineChallenge(challenge: challenge)
            .zip(ogs.$challengesSent.setFailureType(to: Error.self))
            .sink(receiveCompletion: { _ in
                self.ogsRequestCancellable = nil
            }, receiveValue: { _ in})
    }
    
    func acceptChallenge(challenge: any OGSSubmittedChallenge) {
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
        let challengerStoneColor = challenge.challengerColor
        
        return VStack {
            if let challenger = challenge.challenger ?? ogs.user {
                HStack(alignment: .top) {
                    if let iconURL = challenger.iconURL(ofSize: 64) {
                        ZStack(alignment: .bottomTrailing) {
                            AsyncImage(url: iconURL) { $0.resizable() } placeholder: { Color.gray }
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
                            Text(verbatim: challenger.usernameAndRank)
                        }
                        if challenge.game.isPrivate {
                            Text("Private")
                                .italic()
                                .font(.subheadline)
                        }
                    }
                    Spacer()
                    if let challenge = challenge as? (any OGSSubmittedChallenge) {
                        if challenger.id == ogs.user?.id {
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
            if let challenge = challenge as? (any OGSSubmittedChallenge), let challenged = challenge.challenged {
                HStack(alignment: .top) {
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(verbatim: challenged.usernameAndRank)
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
                            AsyncImage(url: iconURL) { $0.resizable() } placeholder: { Color.gray }
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
    
    var gameDetails: some View {
        let game = challenge.game
        return VStack(alignment: .leading, spacing: 3) {
            Label{
                HStack {
                    (Text(verbatim: "\(game.width)×\(game.height)") + Text(verbatim: " ") + Text(game.ranked ? "Ranked" : "Unranked"))
                        .leadingAlignedInScrollView()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Spacer()
                    Text("Handicap: ").bold()
                        .offset(x: 8)
                    if game.handicap == -1 {
                        Text("Auto")
                    } else {
                        Text(verbatim: "\(game.handicap)")
                    }
                }
            } icon: {
                Image(systemName: "squareshape.split.3x3")
            }
            Label {
                HStack {
                    (Text("Rules: ").bold() + Text(game.rules.fullName))
                        .leadingAlignedInScrollView()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    if challenge.useCustomKomi {
                        Spacer()
                        Text("Komi: ").bold()
                            .offset(x: 8)
                        Text(verbatim: String(format: "%.1f", game.komi!))
                    }
                }
            } icon: {
                Image(systemName: "text.badge.checkmark")
            }
            let timeControl = game.timeControl
            Label {
                VStack(alignment: .leading) {
                    Text(verbatim: "\(timeControl.systemName): \(timeControl.shortDescription)")
                        .leadingAlignedInScrollView()
                    if (timeControl.pauseOnWeekends ?? false) && timeControl.speed == .correspondence {
                        Text("Pause on weekend")
                    }
                }
                
            } icon: {
                Image(systemName: "clock")
            }
            if (game.disableAnalysis) {
                Label("Analysis disabled", systemImage: "arrow.triangle.branch")
            } else {
                Label("Analysis enabled", systemImage: "arrow.triangle.branch")
            }
            if let minRank = game.minRank, let maxRank = game.maxRank {
                if minRank > -1000 && maxRank < 1000 {
                    Label(String("\(RankUtils.formattedRank(Double(minRank), longFormat: true)) - \(RankUtils.formattedRank(Double(maxRank), longFormat: true))"), systemImage: "arrow.up.and.down.square")
                }
            }
        }
        .font(.subheadline)
    }
    
    var body: some View {
        VStack {
            if let challenge = challenge as? OGSSeekgraphChallenge, challenge.rengo {
                RengoPlayersDetail(challenge: challenge)
                RengoActions(challenge: challenge)
            } else {
                playerInfos
            }
            Divider()
            if challenge.isUnusual {
                HStack {
                    VStack(alignment: .leading) {
                        if challenge.useCustomKomi {
                            Label("Custom komi: \(challenge.game.komi!, specifier: "%.1f")", systemImage: "exclamationmark.triangle.fill")
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
            gameDetails
        }
    }
}

struct ChallengeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            VStack {
                ChallengeCell(challenge: OGSChallengeSampleData.sampleRengoChallenge)
                    .padding()
                    .background(Color(UIColor.systemBackground).shadow(radius: 2))
            }
            .padding()
            .environmentObject(
                OGSService.previewInstance(
                    user: OGSUser(
                        username: "honganhkhoa", id: 1526,
                        iconUrl: "https://secure.gravatar.com/avatar/4d95e45e08111986fd3fe61e1077b67d?s=32&d=retro"
//                        username: "hakhoa", id: 1765,
//                        iconUrl: "https://secure.gravatar.com/avatar/8698ff92115213ab187d31d4ee5da8ea?s=32&d=retro"
                    ),
                    cachedUsers: [
                        OGSUser(
                            username: "hakhoa2", id: 1767,
                            iconUrl: "https://secure.gravatar.com/avatar/e8fd4a8a5bab2b3785d794ab51fef55c?s=32&d=retro"
                        ),
                        OGSUser(
                            username: "hakhoa4", id: 1769,
                            iconUrl: "https://secure.gravatar.com/avatar/7eb7eabbe9bd03c2fc99881d04da9cbd?s=32&d=retro"
                        ),
                        OGSUser(
                            username: "honganhkhoa", id: 1526,
                            iconUrl: "https://secure.gravatar.com/avatar/4d95e45e08111986fd3fe61e1077b67d?s=32&d=retro"
                        )
                        
                    ]
                )
            )
            .previewDisplayName("Rengo")
            VStack {
                ChallengeCell(challenge: OGSChallengeSampleData.sampleOpenChallenge)
                    .padding()
                    .background(Color(UIColor.systemBackground).shadow(radius: 2))
            }
            .padding()
            .environmentObject(
                OGSService.previewInstance(
                    user: OGSUser(
                        username: "HongAnhKhoa",
                        id: 314459
                    )
                )
            )
            .previewDisplayName("Open challenge")
            VStack {
                ChallengeCell(challenge: OGSChallengeSampleData.sampleChallenge)
                    .padding()
                    .background(Color(UIColor.systemGray5).shadow(radius: 2))
            }
            .padding()
            .background(Color(UIColor.systemBackground))
            .environmentObject(
                OGSService.previewInstance(
                    user: OGSUser(
                        username: "HongAnhKhoa",
                        id: 314459
                    )
                )
            )
            .colorScheme(.dark)
            .previewDisplayName("Direct challenge")
            VStack {
                ChallengeCell(challenge: OGSChallengeSampleData.sampleChallengeTemplate)
                    .padding()
                    .background(Color(UIColor.systemBackground).shadow(radius: 2))
            }
            .padding()
            .environmentObject(
                OGSService.previewInstance(
                    user: OGSUser(
                        username: "HongAnhKhoa",
                        id: 314459
                    )
                )
            )
            .previewDisplayName("Challenge template")
        }
        .previewLayout(.fixed(width: 320, height: 600))
    }
}
