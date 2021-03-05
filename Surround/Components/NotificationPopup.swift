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
                if ogs.socketStatus == .connecting {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    EmptyView()
                }
                Text(ogs.socketStatusString).bold().foregroundColor(.white)
            }
            .animation(.easeInOut, value: ogs.socketStatusString)
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
        
        return false
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
                Text("Game\(ogs.liveGames.count == 1 ? "" : "s") in progress...").bold().foregroundColor(.white)
                Text("Tap to go to game\(ogs.liveGames.count == 1 ? "" : "s")").font(.subheadline).foregroundColor(.white)
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
                    Text("\(ogs.waitingLiveGames) live game\(ogs.waitingLiveGames == 1 ? "" : "s")").font(.subheadline).foregroundColor(.white)
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
    
    var body: some View {
        ZStack(alignment: .top) {
            if ogs.socketStatus == .connected {
                VStack {
                    HStack {
                        if ogs.liveGames.filter { $0.gameData?.outcome == nil }.count > 0 && !viewingLiveGames {
                            liveGamesPopup
                        } else if ogs.waitingLiveGames > 0 && !viewingHomeView {
                            waitingGamesPopup
                        }
                        if (ogs.privateMessagesUnreadCount > 0 || showingPrivateChatView) && nav.main.rootView != .privateMessages {
                            Button(action: { showingPrivateChatView.toggle() }) {
                                ZStack(alignment: .topTrailing) {
                                    Text(Image(systemName: "message.fill"))
                                    if ogs.privateMessagesUnreadCount > 0 {
                                        ZStack {
                                            Circle().fill(Color.red)
                                            Text("\(ogs.privateMessagesUnreadCount)")
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
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { self.showingPrivateChatView = false }
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
                openChallengesSent: [OGSChallenge.sampleOpenChallenge]
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
                Color(.systemBackground)
                NotificationPopup()
            }
            .environmentObject(OGSService.previewInstance(socketStatus: .connecting))
        }
        .environmentObject(nav)
    }
}
