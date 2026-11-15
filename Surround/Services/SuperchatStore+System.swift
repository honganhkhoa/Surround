//
//  SuperchatStore+System.swift
//  Surround
//
//  The app's superchat store, and the observer that tells it when the app
//  enters the background and when it returns. App target only;
//  SurroundTests builds its own stores from SuperchatStore.swift.
//

import UIKit

extension SuperchatStore {
    /// Every window's store. It saves to the shared preferences: the app
    /// group's suite, or the UI-test suite wiped at each launch. Its first
    /// use is on the main thread, from OGSService.instance(forSceneWithID:),
    /// the offline fixture factory, a window root's navigation hold (the App
    /// Review run, whose service has no store) or the Superchat (Debug) menu.
    static let shared = SuperchatStoreAppLifecycle.shared.store
}

/// Tells the app's store when the app enters the background and when it
/// returns: a suspended socket can miss the re-send without closing first.
/// Selector observers, as AppAnnouncerWindowAnchor uses, so no Sendable
/// closure calls into the store.
private final class SuperchatStoreAppLifecycle: NSObject {
    /// Made on the store's first use, and kept while the app runs.
    static let shared = SuperchatStoreAppLifecycle()

    let store = SuperchatStore(preferences: userDefaults)

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(didEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        // The first use can come from a window's first body, before that
        // window reaches the foreground, while the app still reads as in the
        // background. Any window coming forward, and the app becoming active,
        // end that state too, so a cold launch can't leave the store in the
        // background. Returning when already in the foreground changes nothing.
        for name in [
            UIApplication.willEnterForegroundNotification,
            UIScene.willEnterForegroundNotification,
            UIApplication.didBecomeActiveNotification,
        ] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(returnedToForeground), name: name, object: nil
            )
        }
        // A launch for a background refresh or a push starts in the background.
        if UIApplication.shared.applicationState == .background {
            store.enterBackground()
        }
    }

    @objc private func didEnterBackground() {
        store.enterBackground()
    }

    @objc private func returnedToForeground() {
        store.enterForeground()
    }
}
