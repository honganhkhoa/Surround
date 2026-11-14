//
//  ActivityHostSDK.swift
//  Surround
//
//  The only file that names the Activity hosts' iOS 26 and 27 APIs. Each helper
//  is a pass-through where the SDK or platform lacks the API. Floors, read from
//  the local SDKs: SwiftUI 7.2.5 = the iOS 26.2 SDK, the oldest that declares
//  tabViewBottomAccessory(isEnabled:) and every other 26.x API here; 8.0 = the
//  iOS 27 SDK, as DuoTabContainer's gate; 8.0.85 = 27.1, as
//  GeometryProxy.messagesDivisionFrames, never for Catalyst, whose SwiftUI in
//  Xcode 27.1 is 8.0.84. The accessory and minimizing never compile for Mac
//  Catalyst.
//

import SwiftUI
import UIKit

enum ActivityHostSDK {
    #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 7.2.5)
    static let hasHostAPIs = true
    #else
    static let hasHostAPIs = false
    #endif
}

extension ActivityHostPolicy.Facts {
    /// This process's platform, OS and SDK, for `container`.
    static func current(_ container: ActivityHostPolicy.Container,
                        sidebar: ActivityHostPolicy.Sidebar = .unavailable) -> Self {
        let release: ActivityHostPolicy.Release
        if #available(iOS 26.1, *) { release = .iOS26_1 }
        else if #available(iOS 26.0, *) { release = .iOS26_0 }
        else { release = .iOS18 }
        #if targetEnvironment(macCatalyst)
        let platform = ActivityHostPolicy.Platform.mac
        #else
        let platform: ActivityHostPolicy.Platform = UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #endif
        return Self(platform: platform, container: container, release: release,
                    sdkHasHostAPIs: ActivityHostSDK.hasHostAPIs, sidebar: sidebar)
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 7.2.5)
@available(iOS 26.0, *)
private extension ActivityHostPolicy.Minimize {
    var swiftUI: TabBarMinimizeBehavior {
        switch self {
        case .automatic: .automatic
        case .never: .never
        case .onScrollDown: .onScrollDown
        case .onScrollUp: .onScrollUp
        }
    }

    var uiKit: UITabBarController.MinimizeBehavior {
        switch self {
        case .automatic: .automatic
        case .never: .never
        case .onScrollDown: .onScrollDown
        case .onScrollUp: .onScrollUp
        }
    }
}

@available(iOS 26.0, *)
private struct ActivityAccessoryPlacementReader: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let action: (ActivityHostPolicy.AccessoryPlacement) -> Void

    var body: some View {
        Color.clear.allowsHitTesting(false).accessibilityHidden(true)
            .onChange(of: placement, initial: true) { _, placement in
                action(Self.hostPlacement(placement))
            }
    }

    private static func hostPlacement(
        _ placement: TabViewBottomAccessoryPlacement?
    ) -> ActivityHostPolicy.AccessoryPlacement {
        if placement == nil { return .notInAccessory }
        if placement == .inline { return .inline }
        if placement == .expanded { return .expanded }
        return .unspecified
    }
}
#endif

extension View {
    /// SwiftUI's bottom accessory, hidden while `isEnabled` is false: iOS 26.1
    /// and later with the 26.2 SDK. Elsewhere, Catalyst included, unchanged.
    @ViewBuilder
    func activityBottomAccessory<Accessory: View>(isEnabled: Bool,
                                                  @ViewBuilder content: () -> Accessory) -> some View {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 7.2.5)
        if #available(iOS 26.1, *) { tabViewBottomAccessory(isEnabled: isEnabled, content: content) } else { self }
        #else
        self
        #endif
    }

    /// The tab bar's minimize behavior from iOS 26. Nil applies `.automatic`,
    /// the default, so going between nil and a value keeps the view's identity.
    @ViewBuilder
    func activityTabBarMinimizeBehavior(_ behavior: ActivityHostPolicy.Minimize?) -> some View {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 7.2.5)
        if #available(iOS 26.0, *) { tabBarMinimizeBehavior((behavior ?? .automatic).swiftUI) } else { self }
        #else
        self
        #endif
    }

    /// Reports where SwiftUI places this view's bottom accessory, from iOS 26.
    @ViewBuilder
    func onActivityAccessoryPlacementChange(
        _ action: @escaping (ActivityHostPolicy.AccessoryPlacement) -> Void
    ) -> some View {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 7.2.5)
        if #available(iOS 26.0, *) { background(ActivityAccessoryPlacementReader(action: action)) } else { self }
        #else
        self
        #endif
    }

    /// The navigation subtitle: from iOS 26, and on the Mac. Nil sets an empty
    /// subtitle instead of removing it, so a subtitle that comes and goes keeps
    /// its identity.
    @ViewBuilder
    func activityNavigationSubtitle(_ subtitle: Text?) -> some View {
        #if targetEnvironment(macCatalyst)
        navigationSubtitle(subtitle ?? Text(verbatim: ""))
        #elseif os(iOS) && canImport(SwiftUI, _version: 7.2.5)
        if #available(iOS 26.0, *) { navigationSubtitle(subtitle ?? Text(verbatim: "")) } else { self }
        #else
        self
        #endif
    }

    /// A toolbar item in the subtitle, or in the large title's subtitle, from
    /// iOS 26 and on the Mac.
    @ViewBuilder
    func activitySubtitleItem<Item: View>(largeTitle: Bool = false, isPresent: Bool = true,
                                          @ViewBuilder _ item: @escaping () -> Item) -> some View {
        #if os(iOS) && canImport(SwiftUI, _version: 7.2.5)
        if #available(iOS 26.0, *) {
            toolbar {
                if isPresent {
                    ToolbarItem(placement: largeTitle ? ToolbarItemPlacement.largeSubtitle : .subtitle,
                                content: item)
                }
            }
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Keeps the navigation bar full size while scrolling, from iOS 27.
    @ViewBuilder
    func activityNavigationBarNeverMinimizes(_ neverMinimizes: Bool) -> some View {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0)
        if #available(iOS 27.0, *) {
            toolbarMinimizationBehavior(neverMinimizes ? .never : .automatic, for: .navigationBar)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// The Mac sidebar's bottom bar. Apply it unconditionally and vary only
    /// its content. Elsewhere, unchanged.
    @ViewBuilder
    func activityMacSidebarBottomBar<Bar: View>(@ViewBuilder content: () -> Bar) -> some View {
        #if targetEnvironment(macCatalyst)
        tabViewSidebarBottomBar(content: content)
        #else
        self
        #endif
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst)
extension UITabBarController {
    /// Sets or clears the bottom accessory; nil hides it.
    func setActivityAccessory(_ contentView: UIView?, animated: Bool) {
        #if canImport(SwiftUI, _version: 7.2.5)
        guard #available(iOS 26.0, *) else { return }
        if let contentView {
            guard bottomAccessory?.contentView !== contentView else { return }
            setBottomAccessory(UITabAccessory(contentView: contentView), animated: animated)
        } else if bottomAccessory != nil {
            setBottomAccessory(nil, animated: animated)
        }
        #endif
    }

    /// Whether a bottom accessory is set; false before iOS 26.
    var hasActivityAccessory: Bool {
        #if canImport(SwiftUI, _version: 7.2.5)
        if #available(iOS 26.0, *) { return bottomAccessory != nil }
        #endif
        return false
    }

    /// The tab bar's minimize behavior from iOS 26; nil restores `.automatic`.
    func setActivityMinimizeBehavior(_ behavior: ActivityHostPolicy.Minimize?) {
        #if canImport(SwiftUI, _version: 7.2.5)
        guard #available(iOS 26.0, *) else { return }
        tabBarMinimizeBehavior = (behavior ?? .automatic).uiKit
        #endif
    }
}
#endif

// UIView's helpers also compile for the Mac, where they return their
// defaults, so a view that runs on every platform carries no #if.
extension UIView {
    /// Where UIKit says this view sits in a tab accessory; `.unavailable`
    /// before iOS 26 and on the Mac.
    var activityAccessoryEnvironment: ActivityHostPolicy.AccessoryPlacement {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 7.2.5)
        if #available(iOS 26.0, *) {
            switch traitCollection[UITraitTabAccessoryEnvironment.self] {
            case .regular: return .expanded
            case .inline: return .inline
            case .none: return .notInAccessory
            case .unspecified: return .unspecified
            @unknown default: return .unspecified
            }
        }
        #endif
        return .unavailable
    }

    /// Calls `handler` whenever the accessory environment trait changes, from
    /// iOS 26. Elsewhere, never.
    func registerForActivityAccessoryEnvironmentChanges(_ handler: @escaping (UIView) -> Void) {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 7.2.5)
        guard #available(iOS 26.0, *) else { return }
        registerForTraitChanges([UITraitTabAccessoryEnvironment.self]) { (view: UIView, _: UITraitCollection) in
            handler(view)
        }
        #endif
    }

    /// The Duo's fold in this view's coordinates; empty before iOS 27.1 and
    /// on the Mac.
    var activityDivisionFrames: [CGRect] {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            return reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
        }
        #endif
        return []
    }
}
