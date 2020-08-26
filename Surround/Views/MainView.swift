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
    @SceneStorage("currentRootView") var currentView: SubView = .home
    @State var navigationCurrentView: SubView? = .home

    enum SubView: String {
        case home
        case publicGames
    }
        
    var body: some View {
        var compactSizeClass = false
        #if os(iOS)
        compactSizeClass = horizontalSizeClass == .compact
        #endif
        return NavigationView {
            if compactSizeClass {
                switch currentView {
                case .home:
                    HomeView()
                case .publicGames:
                    PublicGamesList()
                }
            } else {
                List {
                    NavigationLink(
                        destination: HomeView(),
                        tag: SubView.home,
                        selection: $navigationCurrentView) {
                        Label("Home", systemImage: "house")
                    }
                    NavigationLink(
                        destination: PublicGamesList(),
                        tag: SubView.publicGames,
                        selection: $navigationCurrentView) {
                        Label("Public games", systemImage: "person.3")
                    }
                }
                .listStyle(SidebarListStyle())
            }
        }
        .onChange(of: currentView) { newView in
            DispatchQueue.main.async {
                withAnimation {
                    navigationCurrentView = newView
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                ogs.ensureConnect()
                if ogs.isLoggedIn {
                    ogs.updateUIConfig()
                    ogs.loadOverview()
                }
            }
        }
    }
}

struct RootViewSwitchingMenu: ViewModifier {
    @SceneStorage("currentRootView") var currentView: MainView.SubView = .home
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    func body(content: Content) -> some View {
        var compactSizeClass = false
        #if os(iOS)
        compactSizeClass = horizontalSizeClass == .compact
        #endif
        
        return content.toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button(action: { currentView = .home }) {
                        Label("Home", systemImage: "house")
                    }
                    Button(action: { currentView = .publicGames }) {
                        Label("Public games", systemImage: "person.3")
                    }
                }
                label: {
                    Label("Navigation", systemImage: currentView == .home ? "house" : "person.3")
                }
                .disabled(!compactSizeClass)
                .opacity(compactSizeClass ? 1 : 0)
            }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
            .environmentObject(OGSService.previewInstance())
    }
}
