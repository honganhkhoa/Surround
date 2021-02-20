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
    
    func goToLiveGames() {
        if let game = ogs.liveGames.first {
            if nav.main.rootView == .home && nav.home.activeGame == nil {
                nav.home.activeGame = game
                return
            }
            nav.main.gameInModal = game
        }
    }

    @ViewBuilder
    var liveGamesPopup: some View {
        if ogs.socketStatus == .connected && ogs.liveGames.count > 0 && !viewingLiveGames {
            Button(action: goToLiveGames) {
                VStack {
                    Text("Live games in progress...").bold().foregroundColor(.white)
                    Text("Tap to go to games").font(.subheadline).foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.systemIndigo))
                .cornerRadius(10)
            }
        }
    }
    
    var body: some View {
        ZStack {
            connectionPopup
            liveGamesPopup
        }
    }
}

struct NotificationPopup_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ZStack(alignment: .top) {
                Color(.systemBackground)
                NotificationPopup()
            }
            .environmentObject(OGSService.previewInstance(
                user: OGSUser(username: "kata-bot", id: 592684),
                activeGames: [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2]
            ))
            ZStack(alignment: .top) {
                Color(.systemBackground)
                NotificationPopup()
            }
            .environmentObject(OGSService.previewInstance(socketStatus: .connecting))
        }
        .environmentObject(NavigationService.shared)
    }
}
