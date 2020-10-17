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
    
    @SceneStorage("activeOGSGameIdToOpen")
    var activeOGSGameIdToOpen = -1

    enum SubView: String {
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

        var label: some View {
            Label(self.title, systemImage: self.systemImage)
        }
        
        func navigationLink(currentView: Binding<SubView?>) -> some View {
            NavigationLink(
                destination: self.view,
                tag: self,
                selection: currentView) {self.label}
        }
        
        func menuButton(currentView: Binding<SubView>) -> some View {
            Button(action: { currentView.wrappedValue = self }) {
                self.label
            }
        }
    }
        
    var body: some View {
        var compactSizeClass = false
        #if os(iOS)
        compactSizeClass = horizontalSizeClass == .compact
        #endif
        return NavigationView {
            if compactSizeClass {
                currentView.view
            } else {
                List(selection: $navigationCurrentView) {
                    SubView.home.navigationLink(currentView: $navigationCurrentView)
                    SubView.publicGames.navigationLink(currentView: $navigationCurrentView)
                    Divider()
                    SubView.settings.navigationLink(currentView: $navigationCurrentView)
                    Divider()
                    SubView.browser.navigationLink(currentView: $navigationCurrentView)
                }
                .listStyle(SidebarListStyle())
                .navigationTitle("Surround")
                if let navigationCurrentView = navigationCurrentView {
                    navigationCurrentView.view
                }
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
                ogs.ensureConnect(thenExecute: {
                    if ogs.isLoggedIn {
                        ogs.updateUIConfig()
                        ogs.loadOverview()
                    }
                    if currentView == .publicGames {
                        ogs.fetchPublicGames()
                    }
                })
            }
        }
        .onOpenURL { url in
            if let rootViewName = url.host, let rootView = SubView(rawValue: rootViewName) {
                currentView = rootView
                switch rootView {
                case .home:
                    if url.pathComponents.count > 1 {
                        if let ogsGameId = Int(url.pathComponents[1]) {
                            activeOGSGameIdToOpen = ogsGameId
                        }
                    }
                default:
                    break
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
                    Section {
                        MainView.SubView.home.menuButton(currentView: $currentView)
                        MainView.SubView.publicGames.menuButton(currentView: $currentView)
                    }
                    Section {
                        MainView.SubView.settings.menuButton(currentView: $currentView)
                    }
                    Section {
                        MainView.SubView.browser.menuButton(currentView: $currentView)
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

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
            .environmentObject(OGSService.previewInstance())
    }
}
