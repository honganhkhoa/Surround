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
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        guard !SurroundUITestContract.isEnabled else {
            return true
        }
        
        SystemPlatformServices.shared.configureAmbientAudioSession()
        
        UNUserNotificationCenter.current().delegate = self
        if userDefaults[.notificationEnabled] == true {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if granted {
                    DispatchQueue.main.async {
                        SystemPlatformServices.shared.registerForRemoteNotifications()
                    }
                }
            }
        }

        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard !SurroundUITestContract.isEnabled else { return }
        SurroundService.shared.registerDeviceIfLoggedIn(pushToken: deviceToken)
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard !SurroundUITestContract.isEnabled else {
            completionHandler()
            return
        }
        
        let userInfo = response.notification.request.content.userInfo
        if let rootViewString = userInfo["rootView"] as? String,
           let rootView = RootView(rawValue: rootViewString),
           let ogsGameId = userInfo["ogsGameId"] as? Int {
            NavigationService.shared.navigateTo(rootView: rootView, ogsGameId: ogsGameId)
        }
        
        completionHandler()
    }
}
