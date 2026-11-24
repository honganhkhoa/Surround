//
//  ActivityAccessoryHost.swift
//  Surround
//
//  The Activity bar in UIKit's bottom accessory, for the UIKit tab
//  containers. One content view holds one bare hosting controller, both made
//  once, whose root view is updated in place, so the accessory keeps one
//  identity for the window's life. The container decides, from its own
//  records and the window's bar state (`ActivityBarHostState`), never from
//  geometry, and the host sets or clears the accessory accordingly and says
//  what it applied. The content draws the bar in the form its traits give:
//  where UIKit places the accessory reaches it a main-queue turn after the
//  trait changes, so nothing it draws changes inside the layout that moved
//  it. Its text stops growing at XXL, it ignores the safe area, and it gets
//  the window's environment from MainView through the same function as the
//  container's tabs.
//

#if os(iOS) && !targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

@MainActor
final class ActivityAccessoryHost {
    /// The view the accessory holds; the same one for every set.
    let contentView: ActivityAccessoryContentView
    private let container: ActivityHostPolicy.Container
    /// Bare, never a child view controller: the bar presents nothing itself.
    private let hosting: UIHostingController<AnyView>
    /// The window's environment for content hosted outside MainView's tree.
    private var environment: (AnyView) -> AnyView = { $0 }
    /// The controller the host last applied to, for what it holds now.
    private weak var controller: UITabBarController?
    private var drawn: Drawn
    private var placementReadScheduled = false

    /// The bar's size where no tab bar holds the accessory, as on a Max
    /// iPhone in landscape and in the Duo's open and tall poses: UIKit makes
    /// such an accessory as wide as its content's ideal width and as tall as
    /// its content needs, within its space. Left to the bar, the width would
    /// be its narrowest drawing, which truncates the lead, and a challenge's
    /// View would make it taller. So it is an iPhone's bar above its tab
    /// bar: 360 pt wide, and fixed at the accessory view's 48 pt. Above a tab
    /// bar, and beside a minimized one, UIKit sets the size itself.
    nonisolated static let idealSize = CGSize(width: 360, height: 48)

    /// What the content draws.
    private struct Drawn: Equatable {
        /// The bar's last content, kept while the accessory goes, so no
        /// transition draws an empty bar.
        var content: ActivityBarContent?
        /// The container's traits, with the placement UIKit last gave the
        /// accessory: inline beside a minimized tab bar, else expanded. A
        /// clear keeps it, as the tab bar keeps its minimized state through
        /// game opens and turns, so a set draws the right form at once.
        var traits: ActivityBarTraits
        var isOffline = false
        /// What the Debug element says: what the host applied, never what
        /// was asked for.
        var applied = "none"
    }

    init(container: ActivityHostPolicy.Container) {
        self.container = container
        drawn = Drawn(traits: ActivityBarTraits(bar: .uiKitAccessory, container: container, placement: .expanded))
        let hosting = UIHostingController(rootView: AnyView(EmptyView()))
        // Laid out outside the accessory first, the content would otherwise
        // keep the window's leading inset in landscape and lose that much of
        // the bar.
        hosting.safeAreaRegions = []
        // Its view's intrinsic size follows the root's fixed size, which
        // UIKit reads where no tab bar holds the accessory.
        hosting.sizingOptions = .intrinsicContentSize
        hosting.view.backgroundColor = .clear
        self.hosting = hosting
        contentView = ActivityAccessoryContentView(content: hosting.view)
        contentView.onPlacementChange = { [weak self] in self?.schedulePlacementRead() }
        #if DEBUG && MAIN_APP
        contentView.onLayout = { [weak self] in self?.logFrame() }
        #endif
    }

    /// MainView's function that gives the bar the window's environment.
    /// Called from each of the container's updates, as its tabs' root views
    /// are updated.
    func setEnvironment(_ environment: @escaping (AnyView) -> AnyView) {
        self.environment = environment
        redraw()
    }

    /// Sets the accessory on `controller` where `state` says UIKit's
    /// accessory shows, and clears it otherwise; a set to the view it already
    /// holds, or a clear with none, changes nothing. The content draws
    /// `content`, or while it is nil the content it drew last.
    /// - Parameters:
    ///   - content: The bar content `state.hasContent` came from.
    ///   - traits: The container's traits; the placement is UIKit's.
    ///   - animated: True while the controller's view is in a window.
    ///   - reason: What asked, for the Debug host log.
    func apply(_ state: ActivityBarHostState, content: ActivityBarContent?, traits: ActivityBarTraits,
               isOffline: Bool, to controller: UITabBarController, animated: Bool, reason: String) {
        self.controller = controller
        let shows = state.shownBar == .uiKitAccessory
        #if DEBUG && MAIN_APP
        let had = controller.hasActivityAccessory
        #endif
        var next = drawn
        if let content { next.content = content }
        next.traits = traits
        next.traits.placement = drawn.traits.placement
        next.isOffline = isOffline
        next.applied = appliedText(next, shows: shows)
        // Drawn before a set, so the accessory never shows what it had before.
        draw(next)
        controller.setActivityAccessory(shows ? contentView : nil, animated: animated)
        // What UIKit holds now, so a stuck accessory reports itself.
        let holds = appliedText(drawn, shows: controller.hasActivityAccessory)
        if holds != drawn.applied {
            var stuck = drawn
            stuck.applied = holds
            draw(stuck)
        }
        #if DEBUG && MAIN_APP
        log(state, reason: reason, had: had, animated: animated)
        #endif
    }

    /// Clears the accessory without animation, whatever a state says: before
    /// a size transition's set, so UIKit lays it out afresh for the new pose.
    func clearWithoutAnimation(on controller: UITabBarController, reason: String) {
        self.controller = controller
        guard controller.hasActivityAccessory else { return }
        controller.setActivityAccessory(nil, animated: false)
        var next = drawn
        next.applied = appliedText(next, shows: controller.hasActivityAccessory)
        draw(next)
        #if DEBUG && MAIN_APP
        NoticesHostProbeLog.event("bar.accessory", [
            ("container", container.rawValue), ("action", "cleared"), ("reason", reason), ("animated", "0"),
            ("applied", drawn.applied),
        ])
        #endif
    }

    // MARK: Drawing

    private func draw(_ next: Drawn) {
        guard next != drawn else { return }
        drawn = next
        redraw()
    }

    /// The root view, in place.
    private func redraw() {
        hosting.rootView = environment(AnyView(
            ActivityAccessoryHostedBar(content: drawn.content, traits: drawn.traits, isOffline: drawn.isOffline,
                                       applied: drawn.applied)
        ))
    }

    private func appliedText(_ drawn: Drawn, shows: Bool) -> String {
        #if DEBUG && MAIN_APP
        ActivityBarAppliedState.text(shows ? drawn.content : nil, host: .uiKitAccessory,
                                     form: ActivityBarForm(drawn.traits))
        #else
        "none"
        #endif
    }

    /// The placement trait changed, or the view moved: read it a main-queue
    /// turn later, outside the layout that changed it. Only an accessory in
    /// a window says where it is; the first layouts of a set say it isn't
    /// in one yet.
    private func schedulePlacementRead() {
        guard !placementReadScheduled else { return }
        placementReadScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            placementReadScheduled = false
            let placement: ActivityHostPolicy.AccessoryPlacement
            switch contentView.activityAccessoryEnvironment {
            case .inline: placement = .inline
            case .expanded: placement = .expanded
            case .notInAccessory, .unspecified, .unavailable: return
            }
            guard placement != drawn.traits.placement else { return }
            var next = drawn
            next.traits.placement = placement
            next.applied = appliedText(next, shows: controller?.hasActivityAccessory == true)
            draw(next)
            #if DEBUG && MAIN_APP
            logFrame()
            #endif
        }
    }

    #if DEBUG && MAIN_APP
    // MARK: The Debug host log

    private func log(_ state: ActivityBarHostState, reason: String, had: Bool, animated: Bool) {
        guard let controller else { return }
        let has = controller.hasActivityAccessory
        let action = has == had ? "kept" : has ? "set" : "cleared"
        let flag = NoticesHostProbeLog.flag
        // A change logs with what asked for it; a recompute that changes
        // nothing logs only when the records it read change.
        let asked = action == "kept" ? [] : [("reason", reason), ("animated", flag(animated))]
        NoticesHostProbeLog.event("bar.accessory", [("container", container.rawValue), ("action", action)] + asked + [
            ("requested", "\(state.requestedTabBar)"), ("controllerHidden", flag(controller.isTabBarHidden)),
            ("window", flag(state.isInWindow)), ("drawer", flag(state.isDrawerShown)),
            ("keyboard", flag(state.isKeyboardOverWindow)), ("bottomTabBar", flag(state.hasBottomTabBar)),
            ("compactHeight", flag(state.isCompactHeight)), ("hides", flag(state.placeHidesBar)),
            ("content", flag(state.hasContent)), ("applied", drawn.applied),
        ], key: action == "kept" ? "bar.accessory.kept.\(container.rawValue)" : nil)
    }

    /// The accessory's frame in its window, from the container's layout and
    /// the content's own, so a move that changes no size is logged too.
    func logFrame() {
        guard let controller, let window = controller.view.window else { return }
        let frame = controller.hasActivityAccessory && contentView.window != nil
            ? contentView.convert(contentView.bounds, to: window) : nil
        let tabBar = controller.tabBar
        NoticesHostProbeLog.event("bar.accessoryView", [
            ("container", container.rawValue), ("window", NoticesHostProbeLog.rect(frame)),
            ("uikit", contentView.activityAccessoryEnvironment.rawValue),
            ("drawn", drawn.traits.placement.rawValue),
            ("tabBar", NoticesHostProbeLog.rect(tabBar.window == nil || tabBar.isHidden ? nil
                                                    : tabBar.convert(tabBar.bounds, to: window))),
            ("tabBarHidden", NoticesHostProbeLog.flag(controller.isTabBarHidden)),
            ("applied", drawn.applied),
        ], key: "bar.accessoryView.\(container.rawValue)")
    }
    #endif
}

/// The view UIKit's accessory holds: the hosting controller's view, edge to
/// edge. It tells the host when its placement trait may have changed.
final class ActivityAccessoryContentView: UIView {
    var onPlacementChange: (() -> Void)?

    init(content: UIView) {
        super.init(frame: .zero)
        backgroundColor = .clear
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        // Where no tab bar holds the accessory UIKit sizes it from this view,
        // which keeps the bar's height whatever the content measures while
        // it changes, as a challenge's View did in a set after a return.
        let height = heightAnchor.constraint(equalToConstant: ActivityAccessoryHost.idealSize.height)
        height.priority = .required - 1
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            height,
        ])
        registerForActivityAccessoryEnvironmentChanges { view in
            (view as? ActivityAccessoryContentView)?.onPlacementChange?()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { ActivityAccessoryHost.idealSize }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: min(size.width, ActivityAccessoryHost.idealSize.width), height: ActivityAccessoryHost.idealSize.height)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onPlacementChange?()
    }

    #if DEBUG && MAIN_APP
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
    #endif
}

/// The hosted root: the bar in its form, or nothing before any content.
private struct ActivityAccessoryHostedBar: View {
    let content: ActivityBarContent?
    let traits: ActivityBarTraits
    let isOffline: Bool
    let applied: String

    var body: some View {
        if let content {
            ActivityBarView(content: content, traits: traits, isOffline: isOffline)
                // Where no tab bar holds it, UIKit sizes the accessory from
                // this, within its space.
                .frame(idealWidth: ActivityAccessoryHost.idealSize.width, maxWidth: .infinity,
                       minHeight: ActivityAccessoryHost.idealSize.height,
                       idealHeight: ActivityAccessoryHost.idealSize.height,
                       maxHeight: ActivityAccessoryHost.idealSize.height)
                #if DEBUG && MAIN_APP
                .background { ActivityBarStateElement(text: applied) }
                #endif
                // UIKit's accessory passes accessibility sizes through, and
                // its fixed height would clip them.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
    }
}
#endif
