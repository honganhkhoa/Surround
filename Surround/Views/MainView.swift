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
    @EnvironmentObject var ogs: OGSService
    @SceneStorage("currentView") var currentView: SubView = .home
    @State var navigationCurrentView: SubView? = .home

    enum SubView: String {
        case home
        case publicGames
    }
    
    var tabView: some View {
        TabView(selection: $currentView) {
            NavigationView {
                HomeView()
            }
            .tabItem {
                Image(systemName: "house")
                Text("Home")
            }.tag(SubView.home)

            NavigationView {
                PublicGamesList()
            }
            .tabItem {
                Image(systemName: "person.3")
                Text("Public games")
            }.tag(SubView.publicGames)
        }
    }
    
    var sideBarView: some View {
        NavigationView {
            List {
                NavigationLink(destination: HomeView(), tag: SubView.home, selection: $navigationCurrentView) {
                    Label("Home", systemImage: "house")
                }
                NavigationLink(destination: PublicGamesList()) {
                    Label("Public games", systemImage: "person.3")
                }
            }
            .listStyle(SidebarListStyle())
            Text("Detail")
        }
        .onChange(of: currentView) { newView in
            navigationCurrentView = newView
        }
        .onChange(of: navigationCurrentView) { newView in
            if let navigationCurrentView = newView {
                currentView = navigationCurrentView
            }
        }
    }
    
    var body: some View {
        return Group {
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
                ogs.ensureConnect()
                ogs.loadOverview()
            }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
