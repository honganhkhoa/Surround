//
//  ContentView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/18/20.
//

import SwiftUI

struct MainViewWrapper: View {
    @SceneStorage("sceneID") var sceneID = UUID().uuidString

    @ViewBuilder
    var body: some View {
        #if DEBUG && MAIN_APP
        if SurroundUITestContract.isEnabled {
            OfflineUITestRootView()
        } else {
            productionRootView
        }
        #else
        productionRootView
        #endif
    }

    private var productionRootView: some View {
        let ogs = OGSService.instance(forSceneWithID: sceneID)
        let sgs = SurroundService.shared
        let nav = NavigationService.instance(forSceneWithID: sceneID)
        return MainView()
            .environmentObject(ogs)
            .environmentObject(sgs)
            .environmentObject(nav)
    }
}

#if DEBUG && MAIN_APP
private struct OfflineUITestRootView: View {
    @StateObject private var ogs: OGSService
    @StateObject private var sgs: SurroundService
    @StateObject private var nav: NavigationService

    init() {
        _ogs = StateObject(wrappedValue: OGSService.offlineUITestInstance())
        _sgs = StateObject(wrappedValue: SurroundService.offlineUITestInstance)
        _nav = StateObject(wrappedValue: NavigationService())
    }

    var body: some View {
        MainView(allowsRemoteActivity: false)
            .environmentObject(ogs)
            .environmentObject(sgs)
            .environmentObject(nav)
            .environment(\.openURL, OpenURLAction { _ in .discarded })
            #if targetEnvironment(macCatalyst)
            .background(CatalystUITestWindowPositioner())
            #endif
    }
}

#if targetEnvironment(macCatalyst)
private struct CatalystUITestWindowPositioner: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        PositioningView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class PositioningView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let windowScene = window?.windowScene else { return }

            DispatchQueue.main.async {
                guard OfflineUITestWindowCoordinator.claim(windowScene) else {
                    UIApplication.shared.requestSceneSessionDestruction(
                        windowScene.session,
                        options: nil
                    )
                    return
                }

                for session in UIApplication.shared.openSessions
                    where session.persistentIdentifier != windowScene.session.persistentIdentifier {
                    UIApplication.shared.requestSceneSessionDestruction(session, options: nil)
                }

                guard windowScene.activationState != .unattached else { return }

                let preferences = UIWindowScene.GeometryPreferences.Mac(
                    systemFrame: CGRect(x: 100, y: 100, width: 1200, height: 760)
                )
                windowScene.requestGeometryUpdate(preferences)
            }
        }
    }
}

private enum OfflineUITestWindowCoordinator {
    private static var claimedSessionIdentifier: String?

    static func claim(_ windowScene: UIWindowScene) -> Bool {
        let sessionIdentifier = windowScene.session.persistentIdentifier
        if let claimedSessionIdentifier {
            return claimedSessionIdentifier == sessionIdentifier
        } else {
            claimedSessionIdentifier = sessionIdentifier
            return true
        }
    }
}
#endif
#endif

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        MainViewWrapper()
    }
}
