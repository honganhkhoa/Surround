//
//  NavigationService.swift
//  Surround
//
//  Created by Anh Khoa Hong on 10/21/20.
//

import Foundation
import SwiftUI
import Combine

struct MainViewParameters {
    var rootView: RootView = .home
}

struct HomeViewParameters {
    var activeGame: Game?
    var ogsIdToOpen = -1
    var showingNewGameView = false
}

struct PublicGamesViewParameter {
    var activeGame: Game?
    var ogsIdToOpen = -1
}

class NavigationService: ObservableObject {
    static var shared = NavigationService()
    static var instances = [String: NavigationService]()
    
    @Published var home = HomeViewParameters()
    @Published var main = MainViewParameters()
    @Published var publicGames = PublicGamesViewParameter()

    static func instance(forSceneWithID sceneID: String) -> NavigationService {
        if let result = instances[sceneID] {
            return result
        } else {
            let result = NavigationService()
            instances[sceneID] = result
            return result
        }
    }
    
    static func appURL(rootView: RootView, game: Game? = nil, ogsGameId: Int? = nil) -> URL? {
        var urlString = "surround://\(rootView)"
        if let ogsId = game?.ogsID {
            urlString += "/\(ogsId)"
        } else if let ogsGameId = ogsGameId {
            urlString += "/\(ogsGameId)"
        }
        return URL(string: urlString)
    }
    
    #if MAIN_APP
    func navigateTo(rootView: RootView, game: Game? = nil, ogsGameId: Int? = nil) {
        if let url = NavigationService.appURL(rootView: rootView, game: game, ogsGameId: ogsGameId) {
            UIApplication.shared.open(url)
        }
    }
    #endif
}

enum RootView: String {
    case home
    case publicGames
    case settings
    case browser
    
    var systemImage: String {
        switch self {
        case .home:
            return "house"
        case .publicGames:
            return "person.2"
        case .settings:
            return "gearshape.2"
        case .browser:
            return "safari"
        }
    }
    
    var title: String {
        switch self {
        case .home:
            return "Home"
        case .publicGames:
            return "Public games"
        case .settings:
            return "Settings"
        case .browser:
            return "Web version"
        }
    }
    
    var label: some View {
        Label(self.title, systemImage: self.systemImage)
    }
    
    func menuButton(currentView: Binding<RootView>) -> some View {
        Button(action: { currentView.wrappedValue = self }) {
            self.label
        }
    }

    #if MAIN_APP
    var view: some View {
        switch self {
        case .home:
            return AnyView(HomeView())
        case .publicGames:
            return AnyView(PublicGamesList())
        case .settings:
            return AnyView(SettingsView())
        case .browser:
            return AnyView(OGSBrowserView())
        }
    }

    func navigationLink(currentView: Binding<RootView?>) -> some View {
        NavigationLink(
            destination: self.view,
            tag: self,
            selection: currentView) {self.label}
    }
    #endif
}

struct RootViewSwitchingMenu: ViewModifier {
    @SceneStorage("currentRootView") var currentView: RootView = .home
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
                    Section {
                        RootView.home.menuButton(currentView: $currentView)
                        RootView.publicGames.menuButton(currentView: $currentView)
                    }
                    Section {
                        RootView.settings.menuButton(currentView: $currentView)
                    }
                    Section {
                        RootView.browser.menuButton(currentView: $currentView)
                    }
                }
                label: {
                    Label("Navigation", systemImage: currentView.systemImage)
                        .font(.title2)
                        .padding(10)
                        .offset(x: -8)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!compactSizeClass)
                .opacity(compactSizeClass ? 1 : 0)
            }
        }
    }
}
