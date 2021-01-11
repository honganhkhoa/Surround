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
    @SceneStorage("publicOGSGameIdToOpen")
    var publicOGSGameIdToOpen = -1 //27671778 //-1
    @State var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    @State var widgetInfos = [WidgetInfo]()
    @State var firstLaunch = true
    
    func onAppActive(newLaunch: Bool) {
        WidgetCenter.shared.getCurrentConfigurations { result in
            if case .success(let widgetInfos) = result {
                self.widgetInfos = widgetInfos
            }
        }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        ogs.ensureConnect(thenExecute: {
            if ogs.isLoggedIn {
                ogs.updateUIConfig()
                if newLaunch {
                    if let latestOverview = userDefaults[.latestOGSOverview] {
                        if let overviewData = try? JSONSerialization.jsonObject(with: latestOverview) as? [String: Any] {
                            ogs.processOverview(overview: overviewData)
                        }
                    }
                }
                ogs.loadOverview()
            }
            if currentView == .publicGames {
                ogs.fetchPublicGames()
            }
        })

    }
    
    func navigateTo(appURL: URL) {
        if let rootViewName = appURL.host, let rootView = RootView(rawValue: rootViewName) {
            currentView = rootView
            navigationCurrentView = rootView
            switch rootView {
            case .home:
                if appURL.pathComponents.count > 1 {
                    if let ogsGameId = Int(appURL.pathComponents[1]) {
                        activeOGSGameIdToOpen = ogsGameId
                    }
                }
            case .publicGames:
                if appURL.pathComponents.count > 1 {
                    if let ogsGameId = Int(appURL.pathComponents[1]) {
                        publicOGSGameIdToOpen = ogsGameId
                    }
                }
            default:
                break
            }
        }
    }
    
    var body: some View {
        if firstLaunch {
            DispatchQueue.main.async {
                if self.firstLaunch {
                    self.firstLaunch = false
                    self.onAppActive(newLaunch: true)
                }
            }
        }
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
                self.onAppActive(newLaunch: false)
            } else if phase == .background {
                self.backgroundTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: {
                    UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                    self.backgroundTaskID = .invalid
                })
                userDefaults[.cachedOGSGames] = [Int: Data]()
                if self.widgetInfos.count > 0 {
                    WidgetCenter.shared.reloadAllTimelines()
                    UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                    self.backgroundTaskID = .invalid
                } else {
                    ogs.loadOverview(finishCallback: {
                        UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                        self.backgroundTaskID = .invalid
                    })
                }
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
