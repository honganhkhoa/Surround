//
//  SurroundApp.swift
//  Surround
//
//  Created by Anh Khoa Hong on 6/30/20.
//

import SwiftUI

#if targetEnvironment(macCatalyst)
enum CatalystDesktopWindowMetrics {
    static let defaultContentWidth: CGFloat = 1_200
    static let defaultContentHeight: CGFloat = 760
    static let minimumWidth: CGFloat = 900
    static let minimumHeight: CGFloat = 600
}
#endif

@main
struct SurroundApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        #if DEBUG && MAIN_APP
        if SurroundUITestContract
            .isClearingAppStoreScreenshotWidgetFixture
        {
            OGSService.clearAppStoreScreenshotWidgetFixture()
        }
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            #if DEBUG && MAIN_APP
            if SurroundUITestContract
                .isClearingAppStoreScreenshotWidgetFixture
            {
                EmptyView()
            } else {
                appContent
            }
            #else
            appContent
            #endif
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(
            width: CatalystDesktopWindowMetrics.defaultContentWidth,
            height: CatalystDesktopWindowMetrics.defaultContentHeight
        )
        .windowResizability(.contentMinSize)
        #endif
    }

    private var appContent: some View {
        MainViewWrapper()
            #if targetEnvironment(macCatalyst)
            .frame(
                minWidth: CatalystDesktopWindowMetrics.minimumWidth,
                idealWidth: CatalystDesktopWindowMetrics.defaultContentWidth,
                maxWidth: .infinity,
                minHeight: CatalystDesktopWindowMetrics.minimumHeight,
                idealHeight: CatalystDesktopWindowMetrics.defaultContentHeight,
                maxHeight: .infinity
            )
            .background(CatalystWindowResizeConfigurator())
            #endif
            .preferredColorScheme(
                (
                    SurroundUITestContract.isCapturingAppStoreScreenshots
                        || SurroundUITestContract
                            .isCapturingCompatibilityScreenshots
                )
                    ? .light
                    : nil
            )
    }
}

#if targetEnvironment(macCatalyst)
/// Keeps the SwiftUI-derived content minimum while correcting Catalyst's
/// transient default-size ceiling as the scene moves between displays.
private struct CatalystWindowResizeConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        ConfigurationView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class ConfigurationView: UIView {
        private var geometryObservation: NSKeyValueObservation?
        private var maximumSizeFloor = CGSize.zero
        private var updateScheduled = false

        override func didMoveToWindow() {
            super.didMoveToWindow()

            geometryObservation?.invalidate()
            geometryObservation = nil
            maximumSizeFloor = .zero
            guard let windowScene = window?.windowScene else { return }

            applyMaximumSize(to: windowScene)
            geometryObservation = windowScene.observe(
                \.effectiveGeometry,
                options: [.initial, .new]
            ) { [weak self, weak windowScene] _, _ in
                DispatchQueue.main.async {
                    guard let self,
                          let windowScene,
                          self.window?.windowScene === windowScene else {
                        return
                    }
                    self.applyMaximumSize(to: windowScene)
                }
            }
            scheduleMaximumSizeUpdate()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyMaximumSize()
            scheduleMaximumSizeUpdate()
        }

        private func scheduleMaximumSizeUpdate() {
            guard !updateScheduled else { return }
            updateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                updateScheduled = false
                applyMaximumSize()
            }
        }

        private func applyMaximumSize(
            to suppliedScene: UIWindowScene? = nil
        ) {
            guard let windowScene = suppliedScene ?? window?.windowScene,
                  let sizeRestrictions = windowScene.sizeRestrictions else {
                return
            }

            // This target uses the Mac UI idiom (`UIDeviceFamily` 6), where
            // UIKit screen points are 1:1 with macOS system-space points. If
            // it ever switches to Scale Interface to Match iPad, convert
            // `displaySize` before combining these values.
            let displaySize = windowScene.screen.bounds.size
            let systemFrame = windowScene.effectiveGeometry.systemFrame
                .standardized
            let minimumSize = sizeRestrictions.minimumSize
            let currentMaximumSize = sizeRestrictions.maximumSize
            guard !systemFrame.isNull,
                  !systemFrame.isInfinite,
                  systemFrame.width.isFinite,
                  systemFrame.height.isFinite,
                  systemFrame.width > 0,
                  systemFrame.height > 0,
                  displaySize.width.isFinite,
                  displaySize.height.isFinite,
                  displaySize.width > 0,
                  displaySize.height > 0,
                  currentMaximumSize.width.isFinite,
                  currentMaximumSize.height.isFinite,
                  currentMaximumSize.width > 0,
                  currentMaximumSize.height > 0 else {
                return
            }

            // `maximumSize` declares the largest size the app supports; it
            // does not resize the window. The scene can briefly report its
            // previous display while macOS restores or moves a window. Keep
            // this per-scene floor monotonic, including on smaller displays,
            // so neither the handoff nor a later SwiftUI layout pass clamps a
            // restored wide window. macOS still applies its system limits.
            maximumSizeFloor = CGSize(
                width: largest(
                    maximumSizeFloor.width,
                    currentMaximumSize.width,
                    displaySize.width,
                    systemFrame.width,
                    minimumSize.width
                ),
                height: largest(
                    maximumSizeFloor.height,
                    currentMaximumSize.height,
                    displaySize.height,
                    systemFrame.height,
                    minimumSize.height
                )
            )
            guard currentMaximumSize != maximumSizeFloor else { return }
            sizeRestrictions.maximumSize = maximumSizeFloor
        }

        private func largest(_ values: CGFloat...) -> CGFloat {
            values.max() ?? 0
        }

        deinit {
            geometryObservation?.invalidate()
        }
    }
}
#endif

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        #if DEBUG && MAIN_APP
        if SurroundUITestContract
            .isClearingAppStoreScreenshotWidgetFixture
        {
            return false
        }
        #endif

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
