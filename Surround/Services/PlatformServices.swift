//
//  PlatformServices.swift
//  Surround
//

import AVFAudio
import Combine
import Foundation
import UIKit

struct PlatformBackgroundTask {
    fileprivate let identifier: UIBackgroundTaskIdentifier
}

protocol PlatformServicing: AnyObject {
    var keyboardWillChangeFramePublisher: AnyPublisher<Notification, Never> { get }
    var keyboardDidChangeFramePublisher: AnyPublisher<Notification, Never> { get }

    func configureAmbientAudioSession()
    func beginBackgroundTask(expirationHandler: @escaping () -> Void) -> PlatformBackgroundTask?
    func endBackgroundTask(_ task: PlatformBackgroundTask?)
    func setPreventsDisplaySleep(_ preventsSleep: Bool)

    func isAttachedSoftwareKeyboardVisible(from notification: Notification) -> Bool
    func open(_ url: URL)
    func registerForRemoteNotifications()

    func makeSelectionFeedbackGenerator() -> UISelectionFeedbackGenerator?
    func playNotificationFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType)
}

final class SystemPlatformServices: PlatformServicing {
    static let shared = SystemPlatformServices()

    private var displaySleepActivity: NSObjectProtocol?

    private init() {}

    var keyboardWillChangeFramePublisher: AnyPublisher<Notification, Never> {
        #if targetEnvironment(macCatalyst)
        Empty<Notification, Never>(completeImmediately: false).eraseToAnyPublisher()
        #else
        NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .eraseToAnyPublisher()
        #endif
    }

    var keyboardDidChangeFramePublisher: AnyPublisher<Notification, Never> {
        #if targetEnvironment(macCatalyst)
        Empty<Notification, Never>(completeImmediately: false).eraseToAnyPublisher()
        #else
        NotificationCenter.default
            .publisher(for: UIResponder.keyboardDidChangeFrameNotification)
            .eraseToAnyPublisher()
        #endif
    }

    func configureAmbientAudioSession() {
        #if !targetEnvironment(macCatalyst)
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        #endif
    }

    func beginBackgroundTask(expirationHandler: @escaping () -> Void) -> PlatformBackgroundTask? {
        #if targetEnvironment(macCatalyst)
        return nil
        #else
        let identifier = UIApplication.shared.beginBackgroundTask(
            expirationHandler: expirationHandler
        )
        guard identifier != .invalid else {
            return nil
        }
        return PlatformBackgroundTask(identifier: identifier)
        #endif
    }

    func endBackgroundTask(_ task: PlatformBackgroundTask?) {
        #if !targetEnvironment(macCatalyst)
        guard let task else {
            return
        }
        UIApplication.shared.endBackgroundTask(task.identifier)
        #endif
    }

    func setPreventsDisplaySleep(_ preventsSleep: Bool) {
        #if targetEnvironment(macCatalyst)
        if preventsSleep {
            guard displaySleepActivity == nil else {
                return
            }
            displaySleepActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled],
                reason: "Keep a live Go game visible"
            )
        } else if let displaySleepActivity {
            ProcessInfo.processInfo.endActivity(displaySleepActivity)
            self.displaySleepActivity = nil
        }
        #else
        UIApplication.shared.isIdleTimerDisabled = preventsSleep
        #endif
    }

    func isAttachedSoftwareKeyboardVisible(from notification: Notification) -> Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return false
        }
        let screenBounds = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .screen.bounds ?? keyboardFrame
        return !keyboardFrame.isEmpty &&
            keyboardFrame.height > 100 &&
            screenBounds.maxX == keyboardFrame.maxX &&
            screenBounds.maxY == keyboardFrame.maxY &&
            screenBounds.width == keyboardFrame.width
        #endif
    }

    func open(_ url: URL) {
        UIApplication.shared.open(url)
    }

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func makeSelectionFeedbackGenerator() -> UISelectionFeedbackGenerator? {
        #if targetEnvironment(macCatalyst)
        return nil
        #else
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        return generator
        #endif
    }

    func playNotificationFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        #if !targetEnvironment(macCatalyst)
        UINotificationFeedbackGenerator().notificationOccurred(type)
        #endif
    }
}
