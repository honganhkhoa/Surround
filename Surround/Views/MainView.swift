//
//  MainView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/29/20.
//

import SwiftUI
import WidgetKit

struct MainView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var ogs: OGSService
    @SceneStorage("currentRootView") var currentView: RootView = .home
    @State var navigationCurrentView: RootView? = .home
    
    @SceneStorage("activeOGSGameIdToOpen")
    var activeOGSGameIdToOpen = -1
    @State var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    func navigateTo(appURL: URL) {
        if let rootViewName = appURL.host, let rootView = RootView(rawValue: rootViewName) {
            currentView = rootView
            switch rootView {
            case .home:
                if appURL.pathComponents.count > 1 {
                    if let ogsGameId = Int(appURL.pathComponents[1]) {
                        activeOGSGameIdToOpen = ogsGameId
                    }
                }
            default:
                break
            }
        }
    }
    
    var body: some View {
        var compactSizeClass = false
        #if os(iOS)
        compactSizeClass = horizontalSizeClass == .compact
        #endif
        return ZStack(alignment: .top) {
            NavigationView {
                if compactSizeClass {
                    currentView.view
                } else {
                    List(selection: $navigationCurrentView) {
                        RootView.home.navigationLink(currentView: $navigationCurrentView)
                        RootView.publicGames.navigationLink(currentView: $navigationCurrentView)
                        Divider()
                        RootView.settings.navigationLink(currentView: $navigationCurrentView)
                        Divider()
                        RootView.browser.navigationLink(currentView: $navigationCurrentView)
                    }
                    .listStyle(SidebarListStyle())
                    .navigationTitle("Surround")
                    if let navigationCurrentView = navigationCurrentView {
                        navigationCurrentView.view
                    }
                }
            }
            if ogs.isLoggedIn {
                ZStack {
                    HStack(spacing: 5) {
                        Group {
                            if ogs.socketStatus == .connecting {
                                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                EmptyView()
                            }
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
            } else if phase == .background {
                NotificationService.shared.scheduleAppRefresh()
                self.backgroundTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: {
                    WidgetCenter.shared.reloadAllTimelines()
                    UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                    self.backgroundTaskID = .invalid
                })
                ogs.loadOverview(finishCallback: {
                    WidgetCenter.shared.reloadAllTimelines()
                    UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                    self.backgroundTaskID = .invalid
                })
            }
        }
        .onOpenURL { url in
            navigateTo(appURL: url)
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
            .environmentObject(OGSService.previewInstance())
    }
}
