//
//  RootConnectionStatus.swift
//  Surround
//
//  The line under root titles on iPhones and the Duo from iOS 26: the
//  window's connection status under each tab's root title, as the
//  navigation item's subtitle text, never an item. It is empty while the
//  window is connected, so it reserves nothing; it says the words during an
//  outage, then a space after "Connected", which keeps the line and the
//  title still, until the root leaves the screen with a push or a tab
//  switch; and it is empty again for the root's next visit. A root whose
//  title is the theme's scene title draws the same line under that title
//  instead (`ThemeSceneNavigationTitle`). The words are the window's bar
//  state's (`ActivityBarState.connection`), which the bar and the Now
//  section say too, so a root never shows two statuses in different words;
//  Retry is the bar's. The line comes from container facts, never geometry,
//  and a change redraws the line alone, never the root. No line on iPad,
//  the Mac, iPhones before iOS 26, pushed screens, Game Detail or a
//  conversation's title area.
//

import SwiftUI

private struct SceneTitleConnectionLineKey: EnvironmentKey {
    static let defaultValue: RootConnectionLine? = nil
}

extension EnvironmentValues {
    /// A tab's root's line, where the theme's scene title draws it under
    /// itself (`RootConnectionLineCarrier.sceneTitle`); nil everywhere else,
    /// screens pushed on the root included.
    var sceneTitleConnectionLine: RootConnectionLine? {
        get { self[SceneTitleConnectionLineKey.self] }
        set { self[SceneTitleConnectionLineKey.self] = newValue }
    }
}

extension View {
    /// The line under this root's title, where the window says its status
    /// there. AppNavigationStack applies it to its root content; nil, the
    /// root of no tab, as in a presented stack, leaves the content as it is.
    func rootConnectionLine(_ root: RootView?) -> some View {
        modifier(RootConnectionStatus(root: root))
    }
}

/// Decides who draws the root's line from the window's container, platform,
/// OS and SDK, and the theme: values that stay the same for the window's
/// life, but the theme, which the person changes in Settings. So the root
/// keeps one identity.
private struct RootConnectionStatus: ViewModifier {
    let root: RootView?
    @EnvironmentObject private var nav: NavigationService
    @Environment(\.iPadTabContext) private var iPadTabContext
    #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0)
    @Environment(\.duoTabContext) private var duoTabContext
    #endif
    @AppStorage(SettingKey<String>.gameTheme.name, store: userDefaults)
    private var gameThemeID = SurroundTheme.standard.rawValue
    @AppStorage(SettingKey<Bool>.themeAppliesToWholeApp.name, store: userDefaults)
    private var themeAppliesToWholeApp = true

    /// The root's container. On iPad never the sidebar's state: no iPad
    /// root has a line, whatever the sidebar does.
    private var container: ActivityHostPolicy.Container {
        if iPadTabContext != nil { return .iPadTabContainer }
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0)
        if duoTabContext != nil { return .duoTabContainer }
        #endif
        return .swiftUITabView
    }

    private var carrier: RootConnectionLineCarrier {
        let facts = ActivityHostPolicy.Facts.current(container)
        let placement = ActivityHostPolicy.hosts(for: facts, overrides: ActivityBarHosting.overrides(afterLaunch: true))
            .connectionStatus
        let theme = SurroundTheme.current(storedID: gameThemeID, appliesToWholeApp: themeAppliesToWholeApp)
        return RootConnectionLineCarrier(placement: placement, root: root, theme: theme)
    }

    func body(content: Content) -> some View {
        let carrier = carrier
        if carrier == .none {
            content
        } else {
            content.modifier(RootConnectionLineHost(carrier: carrier, bar: nav.activityBar))
        }
    }
}

/// The line itself: it observes only the window's bar state, so a change
/// of status redraws the line, not the root. Its subtitle is always set,
/// and a scene title's line is always in that title's item; only the text
/// changes.
private struct RootConnectionLineHost: ViewModifier {
    let carrier: RootConnectionLineCarrier
    @ObservedObject var bar: ActivityBarState
    /// Words showed while the root was on screen, since it last came on
    /// screen. A push or a tab switch ends the visit; a sheet, a turn and the
    /// background don't, as they send no `onDisappear`.
    @State private var shownThisVisit = false
    /// Whether the root is on screen, held by reference: a push's or a pop's
    /// appearance changes nothing drawn, so it redraws nothing.
    @State private var visit = RootConnectionVisit()

    func body(content: Content) -> some View {
        let words = bar.connection.words
        let line = RootConnectionLine(words: words, shownThisVisit: shownThisVisit)
        let visit = visit
        content
            .environment(\.sceneTitleConnectionLine, carrier == .sceneTitle ? line : nil)
            .activityNavigationSubtitle(Text(verbatim: carrier == .navigationSubtitle ? line.text : ""))
            .onChange(of: words != nil) { _, says in
                if says, visit.isOnScreen, !shownThisVisit { shownThisVisit = true }
            }
            .onAppear {
                visit.isOnScreen = true
                if words != nil, !shownThisVisit { shownThisVisit = true }
            }
            .onDisappear {
                visit.isOnScreen = false
                if shownThisVisit { shownThisVisit = false }
            }
    }
}

/// Whether a root is on screen, between its `onAppear` and `onDisappear`.
private final class RootConnectionVisit {
    var isOnScreen = false
}
