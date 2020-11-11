//
//  NotificationService.swift
//  SurroundNotificationService
//
//  Created by Anh Khoa Hong on 11/10/20.
//

import UserNotifications
import Combine

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var notificationContent: UNMutableNotificationContent?
    var overviewLoadingCancellable: AnyCancellable?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        self.notificationContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        overviewLoadingCancellable = SurroundService.shared.getOGSOverview(allowsCache: true).sink(receiveCompletion: { error in
            if let contentHandler = self.contentHandler, let notificationContent = self.notificationContent {
                contentHandler(notificationContent)
            }
        }, receiveValue: { _ in
            
        })
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let notificationContent = notificationContent {
            contentHandler(notificationContent)
        }
    }

}
