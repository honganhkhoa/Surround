//
//  SurroundApp.swift
//  Surround
//
//  Created by Anh Khoa Hong on 6/30/20.
//

import SwiftUI

@main
struct SurroundApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MainViewWrapper()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    // Disable portrait orientation at launch on iPad to work around a SwiftUI's split view bug.
    var allowsPortrait = false
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        if userDefaults[.notificationEnabled] == true {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                UNUserNotificationCenter.current().delegate = self
            }
        }
        DispatchQueue.main.async {
            self.allowsPortrait = true
        }
        return true
    }
        
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .portrait
        } else {
            if allowsPortrait {
                return .all
            } else {
                return .landscape
            }
        }
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {

        completionHandler(.noData)
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let rootViewString = userInfo["rootView"] as? String,
           let rootView = RootView(rawValue: rootViewString),
           let ogsGameId = userInfo["ogsGameId"] as? Int {
            NavigationService.shared.navigateTo(rootView: rootView, ogsGameId: ogsGameId)
        }
        
        completionHandler()
    }
}
