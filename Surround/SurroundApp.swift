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

class AppDelegate: NSObject, UIApplicationDelegate {
    // Disable portrait orientation at launch on iPad to work around a SwiftUI's split view bug.
    var allowsPortrait = false
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
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
}
