//
//  MainView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/29/20.
//

import SwiftUI

struct MainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var activeGames = OGSWebSocket.shared.activeGames

    var body: some View {
        TabView {
            NavigationView {
                HomeView(games: activeGames.gameList)
            }
            .tabItem {
                Image(systemName: "house")
                Text("Home")
            }

            NavigationView {
                PublicGamesList()
            }
            .tabItem {
                Image(systemName: "person.3")
                Text("Public games")
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                OGSWebSocket.shared.ensureConnect()
            }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
