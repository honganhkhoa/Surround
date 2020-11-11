//
//  NotificationService.swift
//  SurroundNotificationService
//
//  Created by Anh Khoa Hong on 11/10/20.
//

import UserNotifications
import Combine
import Alamofire
import DictionaryCoding
import WidgetKit

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var notificationContent: UNMutableNotificationContent?
    var overviewLoadingCancellable: AnyCancellable?
    var activeOGSGamesByIdFromOverview = [Int: Game]()

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        self.notificationContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        overviewLoadingCancellable = SurroundService.shared.getOGSOverview(allowsCache: true).sink(receiveCompletion: { result in
            if case .failure = result {
                self.triggerContentHandler()
            }
        }, receiveValue: { overviewValue in
            if let overviewData = try? JSONSerialization.data(withJSONObject: overviewValue) {
                userDefaults[.latestOGSOverview] = overviewData
                userDefaults[.latestOGSOverviewTime] = Date()
                WidgetCenter.shared.reloadAllTimelines()
            }

            let userInfo = self.notificationContent?.userInfo
            
            guard let ogsGameId = userInfo?["ogsGameId"] as? Int else {
                self.triggerContentHandler()
                return
            }

            self.activeOGSGamesByIdFromOverview = SurroundNotificationService.shared.activeOGSGamesById(from: overviewValue)
            guard self.activeOGSGamesByIdFromOverview[ogsGameId] == nil else {
                self.triggerContentHandler()
                return
            }

            guard let csrfToken = userDefaults[.ogsUIConfig]?.csrfToken, let sessionId = userDefaults[.ogsSessionId] else {
                self.triggerContentHandler()
                return
            }
            
            let ogsDomain = URL(string: OGSService.ogsRoot)!.host!
            let _csrfCookie = HTTPCookie(properties: [.name: "csrftoken", .value: csrfToken, .domain: ogsDomain, .path: "/"])
            let _sessionIdCookie = HTTPCookie(properties: [.name: "sessionid", .value: sessionId, .domain: ogsDomain, .path: "/"])
            guard let csrfCookie = _csrfCookie, let sessionIdCookie = _sessionIdCookie else {
                self.triggerContentHandler()
                return
            }

            Session.default.sessionConfiguration.httpCookieStorage?.setCookie(csrfCookie)
            Session.default.sessionConfiguration.httpCookieStorage?.setCookie(sessionIdCookie)
            AF.request("\(OGSService.ogsRoot)/api/v1/games/\(ogsGameId)").validate().responseJSON { response in
                if let responseData = response.value as? [String: Any] {
                    if let gameData = responseData["gamedata"] as? [String: Any] {
                        if let cachedData = try? JSONSerialization.data(withJSONObject: gameData) {
                            var cachedGames = userDefaults[.cachedOGSGames] ?? [Int: Data]()
                            cachedGames[ogsGameId] = cachedData
                            userDefaults[.cachedOGSGames] = cachedGames
                            self.triggerContentHandler()
                            return
                        }
                    }
                }
                self.triggerContentHandler()
            }
        })
    }
    
    func triggerContentHandler() {
        if let contentHandler = self.contentHandler, let notificationContent = self.notificationContent {
            if notificationContent.userInfo["notificationCategory"] as? String == SettingKey<Any>.notiticationOnGameEnd.mainName {
                if let ogsGameId = notificationContent.userInfo["ogsGameId"] as? Int {
                    var game = self.activeOGSGamesByIdFromOverview[ogsGameId]
                    if game == nil {
                        if let cachedGameData = userDefaults[.cachedOGSGames]?[ogsGameId] {
                            if let cachedGameValue = try? JSONSerialization.jsonObject(with: cachedGameData) as? [String: Any] {
                                let decoder = DictionaryDecoder()
                                decoder.keyDecodingStrategy = .convertFromSnakeCase
                                if let ogsGame = try? decoder.decode(OGSGame.self, from: cachedGameValue) {
                                    game = Game(ogsGame: ogsGame)
                                }
                            }
                        }
                    }
                    if let game = game {
                        if let userId = userDefaults[.ogsUIConfig]?.user.id {
                            if let outcome = game.gameData?.outcome {
                                let result = game.gameData?.winner == userId ? "won" : "lost"
                                notificationContent.body += " You \(result) by \(outcome)."
                            }
                        }
                    }
                }
            }
            contentHandler(notificationContent)
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let notificationContent = notificationContent {
            contentHandler(notificationContent)
        }
    }

}
