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
    var gameInModal: Game?
    var showWaitingGames = false
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
    
    func goToActiveGame(game: Game) {
        if self.main.rootView == .home && self.home.showingNewGameView {
            self.home.showingNewGameView = false
        }
        if self.main.rootView == .home && self.home.activeGame == nil {
            self.home.activeGame = game
            return
        }
        self.main.gameInModal = game
    }
}

enum RootView: String {
    case home
    case publicGames
    case privateMessages
    case settings
    case browser
    
    var systemImage: String {
        switch self {
        case .home:
            return "house"
        case .publicGames:
            return "person.2"
        case .privateMessages:
            return "message"
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
        case .privateMessages:
            return "Private messages"
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
    @ViewBuilder
    var view: some View {
        switch self {
        case .home:
            HomeView()
        case .publicGames:
            PublicGamesList()
        case .privateMessages:
            PrivateMessagesView()
        case .settings:
            SettingsView()
        case .browser:
            OGSBrowserView()
        }
    }

    func navigationLink(currentView: Binding<RootView?>) -> some View {
        Button(action: { currentView.wrappedValue = self }) {
            if currentView.wrappedValue == self {
                HStack {
                    self.label
                    Spacer()
                    Image(systemName: "checkmark")
                }
                .font(Font.body.bold())
            } else {
                self.label
            }
        }

        // Using the NavigationLink like below (seen in many SwiftUI examples) breaks so many things on iPad
        // (One example: https://stackoverflow.com/questions/62761404/create-a-swiftui-sidebar).
//        NavigationLink(
//            destination: self.view,
//            tag: self,
//            selection: currentView) {self.label}
    }
    #endif
}

struct RootViewSwitchingMenu: ViewModifier {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @EnvironmentObject var nav: NavigationService
    @EnvironmentObject var ogs: OGSService

    func body(content: Content) -> some View {
        var compactSizeClass = false
        #if os(iOS)
        compactSizeClass = horizontalSizeClass == .compact
        #endif
        
        return content.toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Section {
                        RootView.home.menuButton(currentView: $nav.main.rootView)
                        RootView.publicGames.menuButton(currentView: $nav.main.rootView)
                        if ogs.privateMessagesActivePeerIds.count > 0 {
                            RootView.privateMessages.menuButton(currentView: $nav.main.rootView)
                        }
                    }
                    Section {
                        RootView.settings.menuButton(currentView: $nav.main.rootView)
                    }
                    Section {
                        RootView.browser.menuButton(currentView:$nav.main.rootView)
                    }
                }
                label: {
                    Label("Navigation", systemImage: nav.main.rootView.systemImage)
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
