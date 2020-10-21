//
//  NotificationService.swift
//  Surround
//
//  Created by Anh Khoa Hong on 10/19/20.
//

import Foundation
import UIKit
import DictionaryCoding
import Alamofire

class NotificationService {
    static let shared = NotificationService()
    
    var userId: Int? { userDefaults[.ogsUIConfig]?.user.id }
    
    func activeOGSGamesById(from data: [String: Any]) -> [Int: Game] {
        var result = [Int: Game]()
        if let activeGamesData = data["active_games"] as? [[String: Any]] {
            let decoder = DictionaryDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            for gameData in activeGamesData {
                if let jsonData = gameData["json"] as? [String: Any] {
                    if let ogsGame = try? decoder.decode(OGSGame.self, from: jsonData) {
                        let game = Game(ogsGame: ogsGame)
                        result[game.ogsID!] = game
                    }
                }
            }
        }
        return result
    }
    
    func scheduleNotification(title: String, message: String, game: Game, setting: SettingKey<Bool>) {
        guard userDefaults[setting] == true else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.userInfo = [
            "rootView": RootView.home.rawValue,
            "ogsGameId": game.ogsID!
        ]

        let uuidString = UUID().uuidString
        let request = UNNotificationRequest(
            identifier: uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { (error) in
           if let error = error {
              print(error)
           }
        }
    }
    
    func scheduleNewMoveNotificationIfNecessary(oldGame: Game, newGame: Game) {
        let opponentName = userId == newGame.blackId ? newGame.whiteName : newGame.blackName
        if oldGame.clock?.currentPlayerId != newGame.clock?.currentPlayerId
            && newGame.clock?.currentPlayerId == userId
            && userId != nil {
            self.scheduleNotification(
                title: "Your turn",
                message: "It is your turn in the game with \(opponentName)",
                game: newGame,
                setting: .notificationOnUserTurn
            )
        }
    }
    
    func scheduleTimeRunningOutNotificationIfNecessary(oldGame: Game, newGame: Game) {
        if let lastCheck = userDefaults[.latestOGSOverviewTime] {
            if oldGame.clock?.currentPlayerId == userId
                && newGame.clock?.currentPlayerId == userId
                && userId != nil {
                let thinkingTime = userId == newGame.blackId ? newGame.clock?.blackTime : newGame.clock?.whiteTime
                if let timeLeft = thinkingTime?.timeLeft {
                    let lastTimeLeft = timeLeft.advanced(by: -Date().timeIntervalSince(lastCheck))
                    let twelveHours = Double(12 * 3600)
                    let threeHours = Double(3 * 3600)
                    let opponentName = userId == newGame.blackId ? newGame.whiteName : newGame.blackName
                    if lastTimeLeft > twelveHours && timeLeft <= twelveHours {
                        self.scheduleNotification(
                            title: "Time running out",
                            message: "You have 12 hours to make your move in the game with \(opponentName)",
                            game: newGame,
                            setting: .notificationOnTimeRunningOut
                        )
                    } else if lastTimeLeft > threeHours && timeLeft <= threeHours {
                        self.scheduleNotification(
                            title: "Time running out",
                            message: "You have 3 hours to make your move in the game with \(opponentName)",
                            game: newGame,
                            setting: .notificationOnTimeRunningOut
                        )
                    }
                }
            }
        }
    }
    
    func scheduleGameEndNotificationIfNecessary(oldGame: Game, newGame: Game) {
        if let outcome = newGame.gameData?.outcome {
            if oldGame.gameData?.outcome == nil {
                let opponentName = userId == newGame.blackId ? newGame.whiteName : newGame.blackName
                let result = newGame.gameData?.winner == userId ? "won" : "lost"
                self.scheduleNotification(
                    title: "Game has ended",
                    message: "Your game with \(opponentName) has ended. You \(result) by \(outcome).",
                    game: newGame,
                    setting: .notiticationOnGameEnd
                )
            }
        }
    }
    
    func scheduleGameEndNotificationIfNecessary(oldGame: Game) {
        if let ogsId = oldGame.ogsID {
            AF.request("\(OGSService.ogsRoot)/api/v1/games/\(ogsId)").responseJSON { response in
                if case .success = response.result {
                    if let data = response.value as? [String: Any] {
                        if let gameData = data["gamedata"] as? [String: Any] {
                            let decoder = DictionaryDecoder()
                            decoder.keyDecodingStrategy = .convertFromSnakeCase
                            if let ogsGame = try? decoder.decode(OGSGame.self, from: gameData) {
                                let newGame = Game(ogsGame: ogsGame)
                                self.scheduleGameEndNotificationIfNecessary(oldGame: oldGame, newGame: newGame)
                            }
                        }
                    }
                }
            }
        }
    }
    
    func scheduleNotificationsIfNecessary(withOldOverviewData oldData: Data, newOverviewData newData: Data) {
        guard userDefaults[.notificationEnabled] == true else {
            return
        }
        
        if let oldData = try? JSONSerialization.jsonObject(with: oldData) as? [String: Any],
           let newData = try? JSONSerialization.jsonObject(with: newData) as? [String: Any] {
            let oldActiveGamesById = activeOGSGamesById(from: oldData)
            let newActiveGamesById = activeOGSGamesById(from: newData)
//            self.scheduleNotification(title: "Test", message: "Testing...", game: newActiveGamesById.values.first!, setting: .notificationEnabled)
            for oldGame in oldActiveGamesById.values {
                if let newGame = newActiveGamesById[oldGame.ogsID!] {
                    self.scheduleNewMoveNotificationIfNecessary(oldGame: oldGame, newGame: newGame)
                    self.scheduleTimeRunningOutNotificationIfNecessary(oldGame: oldGame, newGame: newGame)
                    self.scheduleGameEndNotificationIfNecessary(oldGame: oldGame, newGame: newGame)
                } else {
                    self.scheduleGameEndNotificationIfNecessary(oldGame: oldGame)
                }
            }
        }
    }
}
