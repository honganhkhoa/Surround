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
import DictionaryCoding

class NotificationViewController: UIViewController, UNNotificationContentExtension {
    var hostingViewController: UIHostingController<BoardView>?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any required interface initialization here.
    }
    
    func addBoardView(game: Game) {
        let boardView = BoardView(boardPosition: game.currentPosition)
        hostingViewController = UIHostingController(rootView: boardView)
        hostingViewController?.view.frame = self.view.bounds
        if let view = hostingViewController?.view {
            self.view.addSubview(view)
        }
    }
    
    func didReceive(_ notification: UNNotification) {
        self.view.subviews.forEach { $0.removeFromSuperview() }
        
        if let ogsGameId = notification.request.content.userInfo["ogsGameId"] as? Int {
            if let overview = userDefaults[.latestOGSOverview] {
                if let overviewData = try? JSONSerialization.jsonObject(with: overview) as? [String: Any] {
                    if let game = SurroundNotificationService.shared.activeOGSGamesById(from: overviewData)[ogsGameId] {
                        self.addBoardView(game: game)
                        return
                    }
                }
            }
            if let cachedGameData = userDefaults[.cachedOGSGames]?[ogsGameId] {
                if let cachedGameValue = try? JSONSerialization.jsonObject(with: cachedGameData) as? [String: Any] {
                    let decoder = DictionaryDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    if let ogsGame = try? decoder.decode(OGSGame.self, from: cachedGameValue) {
                        let game = Game(ogsGame: ogsGame)
                        self.addBoardView(game: game)
                        return
                    }
                }
            }
        }
    }

}
