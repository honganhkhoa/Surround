//
//  MainView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/29/20.
//

import SwiftUI

struct MainView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var activeGames = OGSWebSocket.shared.activeGames

    var tabView: some View {
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
    }
    
    var sideBarView: some View {
        NavigationView {
            List {
                NavigationLink(destination: HomeView(games: activeGames.gameList)) {
                    Label("Home", systemImage: "house")
                }
                NavigationLink(destination: PublicGamesList()) {
                    Label("Public games", systemImage: "person.3")
                }
            }
            .listStyle(SidebarListStyle())
            Text("Detail")
        }
    }
    
    var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                tabView
            } else {
                sideBarView
            }
            #else
            sideBarView
            #endif
        }.onChange(of: scenePhase) { phase in
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
