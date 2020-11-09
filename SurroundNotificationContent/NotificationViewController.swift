//
//  NotificationViewController.swift
//  SurroundNotificationContent
//
//  Created by Anh Khoa Hong on 11/8/20.
//

import UIKit
import UserNotifications
import UserNotificationsUI
import SwiftUI

class NotificationViewController: UIViewController, UNNotificationContentExtension {
    var hostingViewController: UIHostingController<BoardView>?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any required interface initialization here.
    }
    
    func didReceive(_ notification: UNNotification) {
        self.view.subviews.forEach { $0.removeFromSuperview() }
        
        print("****** didReceive")
        
        if let ogsGameId = notification.request.content.userInfo["ogsGameId"] as? Int {
            if let overview = userDefaults[.latestOGSOverview] {
                if let overviewData = try? JSONSerialization.jsonObject(with: overview) as? [String: Any] {
                    if let game = NotificationService.shared.activeOGSGamesById(from: overviewData)[ogsGameId] {
                        let boardView = BoardView(boardPosition: game.currentPosition)
                        hostingViewController = UIHostingController(rootView: boardView)
                        hostingViewController?.view.frame = self.view.bounds
                        if let view = hostingViewController?.view {
                            self.view.addSubview(view)
                        }
                    }
                }
            }
        }
    }

}
