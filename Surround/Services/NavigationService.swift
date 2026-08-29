//
//  NavigationService.swift
//  Surround
//
//  Created by Anh Khoa Hong on 10/21/20.
//

import Foundation
import SwiftUI
import Combine

/// The URL schemes registered by the production and isolated beta apps.
///
/// Keeping this distinction in the typed route layer lets tests exercise both
/// variants without making one app accept links intended for the other.
enum AppURLScheme: String, CaseIterable {
    case production = "surround"
    case beta = "surround-beta"

    static var current: AppURLScheme {
        #if OGS_BETA
        return .beta
        #else
        return .production
        #endif
    }
}

/// A validated destination inside Surround.
struct AppRoute: Equatable {
    let rootView: RootView
    let ogsGameID: Int?

    init?(rootView: RootView, ogsGameID: Int? = nil) {
        if let ogsGameID {
            guard ogsGameID > 0, rootView.supportsGameRoute else { return nil }
        }

        self.rootView = rootView
        self.ogsGameID = ogsGameID
    }

    init?(url: URL, expectedScheme: AppURLScheme = .current) {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = components.scheme,
            scheme.caseInsensitiveCompare(expectedScheme.rawValue) == .orderedSame,
            components.user == nil,
            components.password == nil,
            components.port == nil,
            components.query == nil,
            components.fragment == nil,
            let host = components.host,
            let rootView = RootView.allCases.first(where: {
                $0.rawValue.caseInsensitiveCompare(host) == .orderedSame
            })
        else {
            return nil
        }

        let pathComponents = components.path.split(separator: "/", omittingEmptySubsequences: true)
        switch pathComponents.count {
        case 0:
            guard components.path.isEmpty || components.path == "/" else { return nil }
            self.init(rootView: rootView)
        case 1:
            let pathComponent = String(pathComponents[0])
            guard
                components.path == "/\(pathComponent)",
                let ogsGameID = Int(pathComponent)
            else {
                return nil
            }
            self.init(rootView: rootView, ogsGameID: ogsGameID)
        default:
            return nil
        }
    }

    func url(scheme: AppURLScheme = .current) -> URL? {
        var components = URLComponents()
        components.scheme = scheme.rawValue
        components.host = rootView.rawValue
        if let ogsGameID {
            components.path = "/\(ogsGameID)"
        }
        return components.url
    }
}

/// A unique request to resolve and present a game from an external route.
/// A new identifier is created even when the same game is tapped repeatedly,
/// allowing a `.task(id:)` consumer to retry or replace in-flight work.
struct PendingGameOpen: Identifiable, Equatable {
    let id: UUID
    let rootView: RootView
    let ogsGameID: Int

    init(rootView: RootView, ogsGameID: Int, id: UUID = UUID()) {
        self.id = id
        self.rootView = rootView
        self.ogsGameID = ogsGameID
    }
}

enum GameOpenResolutionSource: Equatable {
    case activeGame
    case sharedOverview
    case rest
}

struct GameOpenResolution<GameValue> {
    let game: GameValue
    let source: GameOpenResolutionSource
}

/// Resolves a routed game through the deterministic cache-to-network order
/// shared by Home and Public Games. Keeping this independent of SwiftUI makes
/// source precedence, failure, and cancellation directly testable.
struct GameOpenResolver<GameValue> {
    let activeGame: @MainActor (Int) -> GameValue?
    let sharedOverviewGame: @MainActor (Int) -> GameValue?
    let restGame: @MainActor (Int) async throws -> GameValue

    @MainActor
    func resolve(
        gameID: Int,
        onRESTRequired: @MainActor () -> Void = {}
    ) async throws -> GameOpenResolution<GameValue> {
        if let game = activeGame(gameID) {
            return GameOpenResolution(game: game, source: .activeGame)
        }
        if let game = sharedOverviewGame(gameID) {
            return GameOpenResolution(game: game, source: .sharedOverview)
        }

        try Task.checkCancellation()
        onRESTRequired()
        let game = try await restGame(gameID)
        try Task.checkCancellation()
        return GameOpenResolution(game: game, source: .rest)
    }
}

struct MainViewParameters {
    var rootView: RootView = .home
    var modalLiveGame: Game?
    var showWaitingGames = false
}

struct HomeViewParameters {
    var activeGame: Game?
    var activeGameShowsCarousel = true
    var showingGameHistory = false
    var showingNewGameView = false
    var showingPreferredSettings = false
    var showingSettings = false
}

struct PublicGamesViewParameter {
    var activeGame: Game?
}

struct GameHistoryViewParameters {
    var activeGame: Game?    // history → detail push
}

class NavigationService: ObservableObject {
    static var shared = NavigationService()
    static var instances = [String: NavigationService]()
    
    @Published var home = HomeViewParameters()
    @Published var main = MainViewParameters()
    @Published var publicGames = PublicGamesViewParameter()
    @Published var gameHistory = GameHistoryViewParameters()
    @Published private(set) var pendingGameOpen: PendingGameOpen?

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
        AppRoute(
            rootView: rootView,
            ogsGameID: game?.ogsID ?? ogsGameId
        )?.url()
    }

    /// Parses and applies an app URL in one place. Invalid or cross-environment
    /// URLs are ignored without disturbing the current navigation state.
    @discardableResult
    func handle(appURL: URL) -> Bool {
        guard let route = AppRoute(url: appURL) else { return false }
        handle(route: route)
        return true
    }

    func handle(route: AppRoute) {
        dismissTrackedNavigation(
            preservingActiveGameIn: route.ogsGameID == nil
                ? nil
                : route.rootView
        )

        if route.ogsGameID == nil {
            main.rootView = route.rootView
        } else {
            requestGameOpen(route)
        }
    }

    /// Publishes a game-open request without applying the broad dismissal
    /// policy used for external URLs. Internal flows such as challenge
    /// acceptance retain ownership of the sheets they intentionally dismiss.
    func requestGameOpen(_ route: AppRoute) {
        guard let ogsGameID = route.ogsGameID else { return }

        main.rootView = route.rootView
        pendingGameOpen = PendingGameOpen(
            rootView: route.rootView,
            ogsGameID: ogsGameID
        )
    }

    func clearPendingGameOpen(id: UUID? = nil) {
        guard id == nil || pendingGameOpen?.id == id else { return }
        pendingGameOpen = nil
    }

    private func dismissTrackedNavigation(
        preservingActiveGameIn rootView: RootView?
    ) {
        pendingGameOpen = nil

        main.modalLiveGame = nil
        main.showWaitingGames = false

        if rootView != .home {
            home.activeGame = nil
            home.activeGameShowsCarousel = true
        }
        home.showingGameHistory = false
        home.showingNewGameView = false
        home.showingPreferredSettings = false
        home.showingSettings = false

        if rootView != .publicGames {
            publicGames.activeGame = nil
        }
        gameHistory.activeGame = nil
    }
    
    #if MAIN_APP
    func navigateTo(rootView: RootView, game: Game? = nil, ogsGameId: Int? = nil) {
        if let url = NavigationService.appURL(rootView: rootView, game: game, ogsGameId: ogsGameId) {
            SystemPlatformServices.shared.open(url)
        }
    }
    #endif
    
    func goToActiveGame(game: Game) {
        if self.main.rootView == .home && self.home.showingNewGameView {
            self.home.showingNewGameView = false
        }
        if self.main.rootView == .home
            && !self.home.showingGameHistory
            && self.home.activeGame == nil {
            // Restore the default: the flag may still be false from a finished
            // game opened out of Game history, which would otherwise suppress
            // this live game's carousel.
            self.home.activeGameShowsCarousel = true
            self.home.activeGame = game
            return
        }
        self.main.modalLiveGame = game
    }
}

enum RootView: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }

    fileprivate var supportsGameRoute: Bool {
        switch self {
        case .home, .publicGames:
            return true
        default:
            return false
        }
    }
    
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
                SystemPlatformServices.shared.open(URL(string: "https://forums.online-go.com/")!)
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
            #if DEBUG
            if SurroundUITestContract.isEnabled {
                VStack(spacing: 12) {
                    Image(systemName: "safari")
                        .font(.largeTitle)
                    Text("Web version")
                        .font(.headline)
                    Text("The web view is unavailable in offline UI tests.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.screenBrowser)
                .navigationTitle("Web version")
            } else {
                OGSBrowserView(initialURL: URL(string: "\(OGSService.ogsRoot)/overview")!)
            }
            #else
            OGSBrowserView(initialURL: URL(string: "\(OGSService.ogsRoot)/overview")!)
            #endif
        case .forums:
            OGSBrowserView(initialURL: URL(string: "https://forums.online-go.com/")!)
        }
    }

    func navigationLink(currentView: Binding<RootView?>) -> some View {
        Button(action: {
            if self == .forums {
                SystemPlatformServices.shared.open(URL(string: "https://forums.online-go.com/")!)
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
            ToolbarItem(placement: .topBarLeading) {
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
