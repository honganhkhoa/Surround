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
                userDefaults.updateLatestOGSOverview(overviewData: overviewData)
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
            if let category = notificationContent.userInfo["notificationCategory"] as? String,
               let opponentName = notificationContent.userInfo["opponentName"] as? String {
                switch category {
                case SettingKey<Any>.notificationOnNewGame.mainName:
                    notificationContent.title = String(localized: "Game started", comment: "Notification title")
                    notificationContent.body = String(localized: "Your game with \(opponentName) has started.", comment: "Notification body")
                case SettingKey<Any>.notificationOnUserTurn.mainName:
                    notificationContent.title = String(localized: "Your turn", comment: "Notification title")
                    notificationContent.body = String(localized: "It is your turn in the game with \(opponentName).", comment: "Notification body")
                case SettingKey<Any>.notificationOnTimeRunningOut.mainName:
                    let hoursLeft = notificationContent.body.hasPrefix("You have 3 hours") ? 3 : 12
                    notificationContent.title = String(localized: "Time running out", comment: "Notification title")
                    notificationContent.body = String(localized: "You have \(hoursLeft) hours to make your move in the game with \(opponentName).", comment: "Notification body")
                case SettingKey<Any>.notiticationOnGameEnd.mainName:
                    notificationContent.title = String(localized: "Game ended", comment: "Notification title")
                    notificationContent.body = String(localized: "Your game with \(opponentName) has ended.", comment: "Notification body")
                default:
                    break
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
