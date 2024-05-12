//
//  NotificationPopup.swift
//  Surround
//
//  Created by Anh Khoa Hong on 20/02/2021.
//

import SwiftUI

struct NotificationPopup: View {
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    @Environment(\.colorScheme) private var colorScheme
    
    @State var showingPrivateChatView = false
    
    var connectionPopup: some View {
        ZStack {
            HStack(spacing: 5) {
                if ogs.socketStatus == .connecting || ogs.socketStatus == .reconnecting {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    EmptyView()
                }
                Text(ogs.socketStatus.localizedString).bold().foregroundColor(.white)
            }
            .animation(.easeInOut, value: ogs.socketStatus.localizedString)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.systemIndigo))
        .cornerRadius(10)
        .opacity(ogs.socketStatus == .connected ? 0 : 1)
        .animation(Animation.easeInOut.delay(2), value: ogs.socketStatus)
    }
    
    var viewingLiveGames: Bool {
        if nav.main.rootView == .home {
            if let gameSpeed = nav.home.activeGame?.gameData?.timeControl.speed {
                return gameSpeed == .live || gameSpeed == .blitz
            }
        }
        
        return nav.main.modalLiveGame != nil
    }
    
    var viewingHomeView: Bool {
        return nav.main.rootView == .home && nav.home.activeGame == nil
    }
    
    func goToLiveGames() {
        if let game = ogs.liveGames.first {
            nav.goToActiveGame(game: game)
        }
    }

    var liveGamesPopup: some View {
        Button(action: goToLiveGames) {
            VStack {
                if (ogs.liveGames.count == 1) {
                    Text("Live game in progress...", comment: "In Popup. When only 1 game in progress.").bold().foregroundColor(.white)
                    Text("Tap to go to game", comment: "Popup. When a single game is in progress.").font(.subheadline).foregroundColor(.white)
                } else {
                    Text("Live games in progress...", comment: "In Popup. When multiple games are in progress.").bold().foregroundColor(.white)
                    Text("Tap to go to games", comment: "Popup. When multiplpe games are in progress.").font(.subheadline).foregroundColor(.white)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.systemTeal))
            .cornerRadius(10)
        }
    }
    
    var waitingGamesPopup: some View {
        Button(action: { nav.main.showWaitingGames = true }) {
            HStack(spacing: 0) {
                VStack {
                    Text("Waiting...").bold().foregroundColor(.white)
                    Text("\(ogs.waitingLiveGames) live games", comment: "NotificationPopup - vary for plural").font(.subheadline).foregroundColor(.white)
                }
                Spacer().frame(width: 10)
                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.systemIndigo))
            .cornerRadius(10)
        }
    }
    
    var shouldShowChallengeReceivedPopup: Bool {
        guard !viewingHomeView && !viewingLiveGames else {
            return false
        }
        return ogs.challengesReceived.count > 0
    }
    
    var challengeReceivedPopup: some View {
        Button(action: { nav.main.showWaitingGames = true }) {
            VStack {
                Text("Challenge received!").bold().foregroundColor(.white)
                Text("Tap to view").font(.subheadline).foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.systemIndigo))
            .cornerRadius(10)
        }
    }
    
    var shouldShowMessageNotificationIcon: Bool {
        if ogs.superchatPeerIds.count > 0 {
            return true
        }
        
        if showingPrivateChatView {
            return true
        }
        
        if nav.main.rootView == .privateMessages {
            return false
        }
        
        return ogs.privateMessagesUnreadCount > 0
    }
    
    func closeChatWindow() {
        guard ogs.superchatPeerIds.count == 0 else {
            return
        }
        
        self.showingPrivateChatView = false
    }
    
    func toggleChatWindow() {
        if showingPrivateChatView {
            closeChatWindow()
        } else {
            showingPrivateChatView = true
        }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            if showingPrivateChatView {
                Color.white
                    .opacity(0.01)
                    .contentShape(Rectangle())
                    .onTapGesture { closeChatWindow() }
            }
            if ogs.socketStatus == .connected {
                VStack {
                    HStack {
                        if ogs.liveGames.filter({ $0.gameData?.outcome == nil }).count > 0 && !viewingLiveGames {
                            liveGamesPopup
                        } else if ogs.waitingLiveGames > 0 && !viewingHomeView {
                            waitingGamesPopup
                        } else if shouldShowChallengeReceivedPopup {
                            challengeReceivedPopup
                        }
                        if shouldShowMessageNotificationIcon {
                            Button(action: toggleChatWindow) {
                                ZStack(alignment: .topTrailing) {
                                    Text(Image(systemName: "message.fill"))
                                    if ogs.privateMessagesUnreadCount > 0 {
                                        ZStack {
                                            Circle().fill(Color.red)
                                            Text(verbatim: "\(ogs.privateMessagesUnreadCount)")
                                                .font(.caption2).bold()
                                                .minimumScaleFactor(0.2)
                                                .foregroundColor(.white)
                                                .frame(width: 15, height: 15)
                                        }
                                        .frame(width: 15, height: 15)
                                        .offset(x: 6, y: -6)
                                    }
                                }
                                .padding()
                                .foregroundColor(.white)
                                .background(Color.orange)
                                .cornerRadius(10)
                            }
                        }
                    }
                    if showingPrivateChatView {
                        ZStack {
                            PrivateMessageNotificationView()
                                .frame(maxWidth: 540)
                                .background(
                                    Color(colorScheme == .dark ? .systemGray6 : .systemBackground)
                                        .shadow(radius: 2)
                                )
                                .padding(.horizontal)
                                .padding(.bottom)
                        }
                    }
                }
            }
            connectionPopup
        }
        .onChange(of: ogs.superchatPeerIds) { superchatPeerIds in
            if superchatPeerIds.count > 0 {
                DispatchQueue.main.async {
                    self.showingPrivateChatView = true
                }
            }
        }
    }
}

struct NotificationPopup_Previews: PreviewProvider {
    static var previews: some View {
        let nav = NavigationService.shared
        nav.main.rootView = .publicGames
        return Group {
            ZStack(alignment: .top) {
                NavigationView {
                    Text("View")
                        .navigationTitle("View")
                        .navigationBarTitleDisplayMode(.inline)
                        .navigationBarItems(leading: Text("Back"))
                }.navigationViewStyle(StackNavigationViewStyle())
                NotificationPopup(showingPrivateChatView: true)
            }
            .environmentObject(OGSService.previewInstance(
                user: OGSUser(username: "hakhoa", id: 765826),
                openChallengesSent: [OGSChallengeSampleData.sampleOpenChallenge]
            ))
            .colorScheme(.dark)

            ZStack(alignment: .top) {
                NavigationView {
                    Text("View")
                        .navigationTitle("View")
                        .navigationBarTitleDisplayMode(.inline)
                        .navigationBarItems(leading: Text("Back"))
                }.navigationViewStyle(StackNavigationViewStyle())
                NotificationPopup(showingPrivateChatView: true)
            }
            .environmentObject(OGSService.previewInstance(
                user: OGSUser(username: "hakhoa", id: 765826),
                activeGames: [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2]
            ))

            ZStack(alignment: .top) {
                NavigationView {
                    Text("View")
                        .navigationTitle("View")
                        .navigationBarTitleDisplayMode(.inline)
                        .navigationBarItems(leading: Text("Back"))
                }.navigationViewStyle(StackNavigationViewStyle())
                NotificationPopup()
            }
            .environmentObject(OGSService.previewInstance(
                user: OGSUser(username: "hakhoa", id: 765826),
                challengesReceived: [OGSChallengeSampleData.sampleChallenge]
            ))

            ZStack(alignment: .top) {
                Color(.systemBackground)
                NotificationPopup()
            }
            .environmentObject(OGSService.previewInstance(socketStatus: .connecting))
        }
        .environmentObject(nav)
    }
}
