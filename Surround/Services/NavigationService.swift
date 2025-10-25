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
    var modalLiveGame: Game?
    var showWaitingGames = false
}

struct HomeViewParameters {
    var activeGame: Game?
    var ogsIdToOpen = -1
    var showingNewGameView = false
    var showingPreferredSettings = false
    var showingSettings = false
}

struct PublicGamesViewParameter {
    var activeGame: Game?
    var ogsIdToOpen = -1
}

enum NavigationSplitViewVisibilityProxy: String {
    case automatic
    case all
    case doubleColumn
    case detailOnly
    
    @available(iOS 16.0, *)
    var target: NavigationSplitViewVisibility {
        get {
            switch self {
            case .automatic:
                NavigationSplitViewVisibility.automatic
            case .all:
                NavigationSplitViewVisibility.all
            case .doubleColumn:
                NavigationSplitViewVisibility.doubleColumn
            case .detailOnly:
                NavigationSplitViewVisibility.detailOnly
            }
        }
    }
    
    @available(iOS 16.0, *)
    init?(from: NavigationSplitViewVisibility) {
        switch from {
        case .automatic:
            self.init(rawValue: "automatic")
        case .all:
            self.init(rawValue: "all")
        case .doubleColumn:
            self.init(rawValue: "doubleColumn")
        case .detailOnly:
            self.init(rawValue: "detailOnly")
        default:
            return nil
        }
    }
}

class NavigationService: ObservableObject {
    static var shared = NavigationService()
    static var instances = [String: NavigationService]()
    
    @Published var home = HomeViewParameters()
    @Published var main = MainViewParameters()
    @Published var publicGames = PublicGamesViewParameter()
    
    @Published var columnVisibility = NavigationSplitViewVisibilityProxy.automatic

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
        self.main.modalLiveGame = game
    }
}

enum RootView: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }
    
    case home
    case publicGames
    case privateMessages
    case settings
    case about
    case browser
    case forums
    
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
        case .about:
            return "info.circle"
        case .browser:
            return "safari"
        case .forums:
            return "bubble.left.and.bubble.right"
        }
    }
    
    var title: String {
        switch self {
        case .home:
            return String(localized: "Home", comment: "in navigation menu")
        case .publicGames:
            return String(localized: "Public games", comment: "in navigation menu")
        case .privateMessages:
            return String(localized: "Private messages", comment: "in navigation menu")
        case .settings:
            return String(localized: "Settings", comment: "in navigation menu")
        case .about:
            return String(localized: "About & Support", comment: "in navigation menu")
        case .browser:
            return String(localized: "Web version", comment: "in navigation menu")
        case .forums:
            return String(localized: "Forums", comment: "in navigation menu")
        }
    }
    
    var label: some View {
        Label(self.title, systemImage: self.systemImage)
    }
    
    #if MAIN_APP
    func menuButton(currentView: Binding<RootView>) -> some View {
        Button(action: {
            if self == .forums {
                UIApplication.shared.open(URL(string: "https://forums.online-go.com/")!)
            } else {
                currentView.wrappedValue = self
            }
        }) {
            self.label
        }
    }
    
    @ViewBuilder
    var navigationView : some View {
        NavigationStack {
            self.view
        }
    }

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
        case .about:
            AboutView()
        case .browser:
            OGSBrowserView(initialURL: URL(string: "\(OGSService.ogsRoot)/overview")!)
        case .forums:
            OGSBrowserView(initialURL: URL(string: "https://forums.online-go.com/")!)
        }
    }

    func navigationLink(currentView: Binding<RootView?>) -> some View {
        Button(action: {
            if self == .forums {
                UIApplication.shared.open(URL(string: "https://forums.online-go.com/")!)
            } else {
                currentView.wrappedValue = self
            }
        }) {
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

#if MAIN_APP
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
                        RootView.about.menuButton(currentView: $nav.main.rootView)
                    }
                    Section {
                        RootView.browser.menuButton(currentView:$nav.main.rootView)
                        RootView.forums.menuButton(currentView: $nav.main.rootView)
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
#endif
