//
//  AppAnnouncer+System.swift
//  Surround
//
//  The app's announcer: VoiceOver and the Taptic Engine as its output, and
//  an anchor in each window that tells it which window the user is in.
//  App target only; SurroundTests drives AppAnnouncer.swift with fakes.
//

import Accessibility
import OSLog
import SwiftUI
import UIKit

extension AppAnnouncer {
    /// Every window's state, from AppAnnouncerWindowAnchor.
    static let windows = AppAnnouncerWindowRegistry()
    static let shared = AppAnnouncer(scenes: windows, output: SystemAnnouncerOutput())

    #if DEBUG && MAIN_APP
    /// `--surround-announcer-diagnostics` logs each post, each window report
    /// and each change of a window's active appearance: keys, outcomes and
    /// short window IDs, never the spoken text.
    static let logsDiagnostics = ProcessInfo.processInfo.arguments
        .contains("--surround-announcer-diagnostics")
    private static let diagnostics = Logger(
        subsystem: "com.honganhkhoa.Surround", category: "AppAnnouncer"
    )

    static func logDiagnostic(_ line: @autoclosure () -> String) {
        guard logsDiagnostics else { return }
        let message = line()
        diagnostics.notice("\(message, privacy: .public)")
    }

    static func shortID(_ window: UUID?) -> String {
        window.map { String($0.uuidString.prefix(8)) } ?? "none"
    }
    #endif
}

extension NavigationService {
    /// Speaks or plays `announcement` once per app, on behalf of this window.
    func announce(_ announcement: AppAnnouncement) {
        #if DEBUG && MAIN_APP
        let outcome = AppAnnouncer.shared.post(announcement, from: announcerWindow)
        AppAnnouncer.logDiagnostic(
            "post key=\(announcement.key.rawValue) outcome=\(outcome) "
                + "window=\(AppAnnouncer.shortID(announcerWindow)) "
                + "frontmost=\(AppAnnouncer.shortID(AppAnnouncer.windows.frontmostWindow))"
        )
        #else
        AppAnnouncer.shared.post(announcement, from: announcerWindow)
        #endif
    }
}

/// VoiceOver and haptics, as the app posted them before AppAnnouncer.
struct SystemAnnouncerOutput: AppAnnouncerOutput {
    func speak(_ text: String, priority: AppAnnouncement.Priority) {
        switch priority {
        case .normal:
            // The call every announcement made before, unchanged.
            AccessibilityNotification.Announcement(text).post()
        case .low, .high:
            var attributed = AttributedString(text)
            attributed.accessibilitySpeechAnnouncementPriority = priority == .low ? .low : .high
            AccessibilityNotification.Announcement(attributed).post()
        }
    }

    func play(_ haptic: AppAnnouncement.Haptic) {
        // Settings › Haptics turns these off too, as it does the board's.
        guard userDefaults[.hapticsFeedback] != false else { return }
        let type: UINotificationFeedbackGenerator.FeedbackType = switch haptic {
        case .success: .success
        case .warning: .warning
        case .error: .error
        }
        // Does nothing on Mac, which gets no haptic for notices.
        SystemPlatformServices.shared.playNotificationFeedback(type)
    }
}

/// Registers the window it is applied to with AppAnnouncer. MainView
/// applies it once per window.
struct AppAnnouncerWindowRegistration: ViewModifier {
    let window: UUID

    func body(content: Content) -> some View {
        content.background {
            AppAnnouncerWindowAnchor(window: window)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

/// Tells AppAnnouncer whether its window is in front, behind or gone. It is
/// zero-size, hidden and inert, and changes no SwiftUI state, so it takes
/// no part in a layout pass. It must stay in content: inside a toolbar it
/// would sit in an offscreen host with no window.
struct AppAnnouncerWindowAnchor: UIViewRepresentable {
    let window: UUID

    func makeUIView(context: Context) -> AnchorView {
        AnchorView(announcerWindow: window)
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        view.announcerWindow = window
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: ()) {
        view.withdraw()
    }

    final class AnchorView: UIView {
        private let owner = UUID()
        /// The scene last reported, for didDisconnect, when the window may
        /// already have left it.
        private weak var reportedScene: UIScene?

        var announcerWindow: UUID {
            didSet {
                guard announcerWindow != oldValue else { return }
                AppAnnouncer.windows.remove(oldValue, owner: owner)
                report()
            }
        }

        init(announcerWindow: UUID) {
            self.announcerWindow = announcerWindow
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            accessibilityElementsHidden = true
            // Selector observers, as SceneActivationUITestProbe uses: no
            // Sendable closure calling into the main actor, and removed
            // automatically when the view goes.
            for name in [
                UIScene.didActivateNotification,
                UIScene.willDeactivateNotification,
                UIScene.willEnterForegroundNotification,
                UIScene.didEnterBackgroundNotification,
                UIScene.didDisconnectNotification,
            ] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(sceneChanged(_:)), name: name, object: nil
                )
            }
            // The focused window appears active: on Mac, and on iPad in Stage
            // Manager and windowed apps.
            registerForTraitChanges(
                [UITraitActiveAppearance.self], action: #selector(activeAppearanceChanged)
            )
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func withdraw() {
            AppAnnouncer.windows.remove(announcerWindow, owner: owner)
            #if DEBUG && MAIN_APP
            AppAnnouncer.logDiagnostic("withdraw window=\(AppAnnouncer.shortID(announcerWindow))")
            #endif
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        @objc private func sceneChanged(_ notification: Notification) {
            guard let scene = notification.object as? UIScene, scene === reportedScene else { return }
            switch notification.name {
            case UIScene.didActivateNotification:
                report(.active)
            case UIScene.willDeactivateNotification, UIScene.willEnterForegroundNotification:
                // Posted before activationState changes, so pass the state
                // the notification announces.
                report(.inactive)
            case UIScene.didEnterBackgroundNotification:
                report(.background)
            default:
                withdraw()
            }
        }

        @objc private func activeAppearanceChanged() {
            #if DEBUG && MAIN_APP
            AppAnnouncer.logDiagnostic(
                "appearance window=\(AppAnnouncer.shortID(announcerWindow)) "
                    + "activeAppearance=\(Self.describe(traitCollection.activeAppearance)) "
                    + "scene=\(window?.windowScene.map { "\(Self.activation(of: $0))" } ?? "none") "
                    + "frontmost=\(AppAnnouncer.shortID(AppAnnouncer.windows.frontmostWindow))"
            )
            #endif
            guard traitCollection.activeAppearance == .active else { return }
            report(focused: true)
        }

        #if DEBUG && MAIN_APP
        private static func describe(_ appearance: UIUserInterfaceActiveAppearance) -> String {
            switch appearance {
            case .active: "active"
            case .inactive: "inactive"
            default: "unspecified"
            }
        }
        #endif

        private func report(
            _ activation: AppAnnouncerWindows.Activation? = nil,
            focused: Bool = false
        ) {
            guard let scene = window?.windowScene else {
                withdraw()
                reportedScene = nil
                return
            }
            reportedScene = scene
            let state = activation ?? Self.activation(of: scene)
            AppAnnouncer.windows.update(
                announcerWindow, owner: owner, activation: state, focused: focused
            )
            #if DEBUG && MAIN_APP
            AppAnnouncer.logDiagnostic(
                "window=\(AppAnnouncer.shortID(announcerWindow)) activation=\(state) "
                    + "appearance=\(Self.describe(traitCollection.activeAppearance)) "
                    + "focused=\(focused) frontmost=\(AppAnnouncer.shortID(AppAnnouncer.windows.frontmostWindow))"
            )
            #endif
        }

        private static func activation(of scene: UIScene) -> AppAnnouncerWindows.Activation {
            switch scene.activationState {
            case .foregroundActive: .active
            case .foregroundInactive: .inactive
            default: .background
            }
        }
    }
}
