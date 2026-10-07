import SwiftUI
import UIKit
import Observation

/// The small chrome bridge needed by roots hosted outside SwiftUI's TabView.
@MainActor
@Observable
final class IPadTabContext {
    private(set) var sidebarVisible = false
    @ObservationIgnored private var hiddenTabBarOwners = Set<UUID>()
    @ObservationIgnored var onTabBarVisibilityChange: (() -> Void)?

    func setTabBarHidden(_ hidden: Bool, owner: UUID) {
        let previous = prefersTabBarHidden
        if hidden { hiddenTabBarOwners.insert(owner) }
        else { hiddenTabBarOwners.remove(owner) }
        if previous != prefersTabBarHidden { onTabBarVisibilityChange?() }
    }

    func removeTabBarHiddenRequest(owner: UUID) { setTabBarHidden(false, owner: owner) }
    fileprivate var prefersTabBarHidden: Bool { !hiddenTabBarOwners.isEmpty }
    fileprivate func setSidebarVisible(_ visible: Bool) { sidebarVisible = visible }
}

private struct IPadTabContextKey: EnvironmentKey {
    static let defaultValue: IPadTabContext? = nil
}

extension EnvironmentValues {
    var iPadTabContext: IPadTabContext? {
        get { self[IPadTabContextKey.self] }
        set { self[IPadTabContextKey.self] = newValue }
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst)
/// Prototype: native sidebar ordering with account rows that open the shared
/// sheet presenter. Each SwiftUI root retains its own navigation stack.
@available(iOS 18.0, *)
struct IPadTabContainer: UIViewControllerRepresentable {
    @Binding var selection: RootView
    let isLoggedIn: Bool
    var messagesBadgeCount = 0
    let onAccountSheet: (AccountSheet) -> Void
    let content: (RootView) -> AnyView

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UITabBarController {
        context.coordinator.makeController(
            regularWidth: context.environment.horizontalSizeClass == .regular,
            layoutDirection: context.environment.layoutDirection
        )
    }

    func updateUIViewController(_ controller: UITabBarController, context: Context) {
        context.coordinator.update(
            self, regularWidth: context.environment.horizontalSizeClass == .regular,
            layoutDirection: context.environment.layoutDirection
        )
    }

    @MainActor
    final class Coordinator: NSObject, UITabBarControllerDelegate, UITabBarController.Sidebar.Delegate {
        private var parent: IPadTabContainer
        private weak var controller: IPadTabBarController?
        private var hosts = [RootView: UIHostingController<AnyView>]()
        private var tabs = [RootView: UITab]()
        private var contexts = [RootView: IPadTabContext]()
        private let surroundContent = IPadTabGroupContentController()
        private let ogsContent = IPadTabGroupContentController()
        private var surroundGroup: UITabGroup!
        private var ogsGroup: UITabGroup!
        private var topology: [String] = []
        private var changingTabs = false
        private var regularWidth = false

        init(_ parent: IPadTabContainer) { self.parent = parent }

        func makeController(regularWidth: Bool, layoutDirection: LayoutDirection) -> UITabBarController {
            let controller = IPadTabBarController()
            self.controller = controller
            controller.view.accessibilityIdentifier = "navigation.container.ipad"
            controller.delegate = self
            controller.mode = .tabSidebar
            controller.sidebar.delegate = self
            controller.onHorizontalSizeClassChange = { [weak self] in self?.applyTabs(regularWidth: $0) }
            controller.onDidAppear = { [weak self] in self?.updateSidebarVisibility() }
            for root in RootView.allCases {
                let tabContext = IPadTabContext()
                tabContext.onTabBarVisibilityChange = { [weak self] in self?.applyTabBarVisibility() }
                contexts[root] = tabContext
                let host = UIHostingController(rootView: hostedContent(root))
                hosts[root] = host
                let tab = UITab(title: root == .about ? String(localized: "About") : root.title,
                                image: UIImage(systemName: root.systemImage),
                                identifier: root.rawValue) { _ in host }
                tab.preferredPlacement = isPrimary(root) ? .fixed : .sidebarOnly
                tab.allowsHiding = false
                tab.accessibilityIdentifier = accessibilityIdentifier(root)
                tabs[root] = tab
            }
            surroundGroup = UITabGroup(title: "Surround", image: nil, identifier: "surround.group",
                                      children: []) { [surroundContent] _ in surroundContent }
            surroundGroup.defaultChildIdentifier = RootView.about.rawValue
            ogsGroup = UITabGroup(title: "OGS", image: nil, identifier: "ogs.group",
                                 children: []) { [ogsContent] _ in ogsContent }
            ogsGroup.defaultChildIdentifier = RootView.browser.rawValue
            for group in [surroundGroup!, ogsGroup!] {
                group.preferredPlacement = .fixed
                group.sidebarAppearance = .rootSection
                group.allowsHiding = false
                group.allowsReordering = false
            }
            // Keep Surround as the sidebar section, with its existing About
            // child representing the destination in the top tab bar.
            surroundGroup.preferredPlacement = .sidebarOnly
            tabs[.about]?.preferredPlacement = .fixed
            applyLayoutDirection(layoutDirection)
            applyTabs(regularWidth: regularWidth)
            return controller
        }

        func update(_ parent: IPadTabContainer, regularWidth: Bool, layoutDirection: LayoutDirection) {
            self.parent = parent
            applyLayoutDirection(layoutDirection)
            for (root, host) in hosts {
                host.rootView = hostedContent(root)
                tabs[root]?.title = root == .about ? String(localized: "About") : root.title
            }
            tabs[.privateMessages]?.badgeValue = parent.messagesBadgeCount > 0
                ? String(parent.messagesBadgeCount) : nil
            applyTabs(regularWidth: regularWidth)
        }

        private func hostedContent(_ root: RootView) -> AnyView {
            AnyView(parent.content(root).environment(\.iPadTabContext, contexts[root]))
        }

        private func isPrimary(_ root: RootView) -> Bool {
            [.home, .publicGames, .privateMessages].contains(root)
        }

        private var selectedRoot: RootView {
            let root = parent.selection
            return !parent.isLoggedIn && (root == .profile || root == .privateMessages) ? .home : root
        }

        private func applyLayoutDirection(_ direction: LayoutDirection) {
            controller?.view.semanticContentAttribute = direction == .rightToLeft
                ? .forceRightToLeft : .forceLeftToRight
        }

        private func applyTabs(regularWidth: Bool) {
            guard let controller, surroundGroup != nil, ogsGroup != nil, !changingTabs else { return }
            self.regularWidth = regularWidth
            tabs[.browser]?.preferredPlacement = regularWidth ? .sidebarOnly : .fixed
            let root = selectedRoot
            var primary: [RootView] = [.home, .publicGames]
            if parent.isLoggedIn { primary.append(.privateMessages) }
            var roots = primary
            if regularWidth {
                if parent.isLoggedIn || root == .profile { roots.append(.profile) }
            } else {
                roots.append(.browser)
                // Compact width keeps a selected legacy secondary destination,
                // without exposing account actions in its bottom tab bar.
                if !isPrimary(root), root != .browser { roots.append(root) }
            }
            let desiredTopology = roots.map(\.rawValue)
                + (regularWidth ? ["surround.group", "ogs.group"] : [])
                + (regularWidth && root == .forums ? ["ogs.forums"] : [])
            changingTabs = true
            defer { changingTabs = false }
            if topology != desiredTopology {
                let reparent = {
                    controller.setTabs(primary.compactMap { self.tabs[$0] }, animated: false)
                    self.surroundContent.show(nil)
                    self.ogsContent.show(nil)
                    self.surroundGroup.children = []
                    self.ogsGroup.children = []
                    var desired = roots.compactMap { self.tabs[$0] }
                    if regularWidth {
                        let surroundRoots: [RootView] = [.settings, .about]
                        self.surroundGroup.children = surroundRoots.compactMap { self.tabs[$0] }
                        self.surroundGroup.selectedChild = self.tabs[root == .settings ? .settings : .about]
                        let ogsRoots: [RootView] = root == .forums ? [.browser, .forums] : [.browser]
                        self.ogsGroup.children = ogsRoots.compactMap { self.tabs[$0] }
                        self.ogsGroup.selectedChild = self.tabs[root == .forums ? .forums : .browser]
                        desired += [self.surroundGroup, self.ogsGroup]
                    }
                    controller.setTabs(desired, animated: false)
                    controller.selectedTab = self.tabs[root]
                }
                #if canImport(SwiftUI, _version: 8.0)
                if #available(iOS 27.0, *) { controller.performBatchUpdates(reparent) }
                else { reparent() }
                #else
                reparent()
                #endif
                topology = desiredTopology
            } else if controller.selectedTab !== tabs[root] {
                controller.selectedTab = tabs[root]
            }
            if regularWidth {
                surroundGroup.selectedChild = tabs[root == .settings ? .settings : .about]
                if root == .settings || root == .about { surroundContent.show(hosts[root]) }
                if root == .browser || root == .forums {
                    ogsGroup.selectedChild = tabs[root]
                    ogsContent.show(hosts[root])
                }
            }
            applyTabBarVisibility()
            // Trait and representable updates both use this path. Publish the
            // current visibility after SwiftUI finishes its controller update.
            DispatchQueue.main.async { [weak self] in self?.updateSidebarVisibility() }
        }

        private func effectiveRoot(_ tab: UITab) -> RootView? {
            if let group = tab as? UITabGroup {
                let child = group.selectedChild
                    ?? group.defaultChildIdentifier.flatMap { group.tab(forIdentifier: $0) }
                    ?? group.children.first
                return child.flatMap(effectiveRoot)
            }
            return RootView(rawValue: tab.identifier)
        }

        func tabBarController(_ controller: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
            switch effectiveRoot(tab) {
            case .profile:
                if parent.isLoggedIn { parent.onAccountSheet(.profile) }
                return false
            case .settings:
                parent.onAccountSheet(.settings)
                return false
            default: return true
            }
        }

        func tabBarController(_ controller: UITabBarController, didSelectTab tab: UITab, previousTab: UITab?) {
            guard !changingTabs, let root = effectiveRoot(tab) else { return }
            if parent.selection != root { parent.selection = root }
            applyTabs(regularWidth: regularWidth)
        }

        func tabBarController(_ controller: UITabBarController, sidebarAvailabilityDidChange sidebar: UITabBarController.Sidebar) {
            applyTabs(regularWidth: controller.traitCollection.horizontalSizeClass == .regular)
            updateSidebarVisibility()
        }

        func tabBarController(_ controller: UITabBarController, sidebarVisibilityWillChange sidebar: UITabBarController.Sidebar,
                              animator: any UITabBarController.Sidebar.Animating) {
            animator.addCompletion { [weak self] in self?.updateSidebarVisibility() }
        }

        func tabBarController(_ controller: UITabBarController, sidebar: UITabBarController.Sidebar,
                              itemFor request: UITabSidebarItem.Request) -> UITabSidebarItem {
            let item = UITabSidebarItem(request: request)
            tabBarController(controller, sidebar: sidebar, update: item)
            return item
        }

        func tabBarController(_ controller: UITabBarController, sidebar: UITabBarController.Sidebar,
                              update item: UITabSidebarItem) {
            guard case .tab(let tab) = item.content, tab === tabs[.about] else { return }
            var configuration = item.defaultContentConfiguration()
            configuration.text = RootView.about.title
            item.contentConfiguration = configuration
        }

        private func updateSidebarVisibility() {
            guard let controller else { return }
            let visible = regularWidth && controller.mode != .tabBar && !controller.sidebar.isHidden
            for context in contexts.values where context.sidebarVisible != visible { context.setSidebarVisible(visible) }
        }

        private func applyTabBarVisibility() {
            guard let controller else { return }
            let hidden = contexts[selectedRoot]?.prefersTabBarHidden ?? false
            if controller.isTabBarHidden != hidden {
                controller.setTabBarHidden(hidden, animated: controller.view.window != nil)
            }
        }

        private func accessibilityIdentifier(_ root: RootView) -> String? {
            switch root {
            case .home: SurroundUITestContract.AccessibilityID.navigationHome
            case .publicGames: SurroundUITestContract.AccessibilityID.navigationPublicGames
            case .privateMessages: SurroundUITestContract.AccessibilityID.navigationMessages
            case .profile: SurroundUITestContract.AccessibilityID.navigationProfile
            case .settings: SurroundUITestContract.AccessibilityID.navigationSettings
            case .about: SurroundUITestContract.AccessibilityID.navigationAbout
            case .browser: SurroundUITestContract.AccessibilityID.navigationBrowser
            case .forums: nil
            }
        }
    }
}

@available(iOS 18.0, *)
private final class IPadTabGroupContentController: UIViewController {
    private var displayedHost: UIViewController?
    private var hasAppeared = false

    func show(_ host: UIViewController?) {
        guard displayedHost !== host else { return }
        let previous = displayedHost
        if hasAppeared {
            previous?.beginAppearanceTransition(false, animated: false)
            host?.beginAppearanceTransition(true, animated: false)
        }
        if let previous, previous.parent === self {
            previous.willMove(toParent: nil)
            previous.view.removeFromSuperview()
            previous.removeFromParent()
        }
        displayedHost = host
        if let host {
            if host.parent != nil {
                host.willMove(toParent: nil)
                host.view.removeFromSuperview()
                host.removeFromParent()
            }
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }
        if hasAppeared { previous?.endAppearanceTransition(); host?.endAppearanceTransition() }
        setNeedsStatusBarAppearanceUpdate()
    }

    override var childForStatusBarStyle: UIViewController? { displayedHost }
    override var childForStatusBarHidden: UIViewController? { displayedHost }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); hasAppeared = true }
    override func viewWillDisappear(_ animated: Bool) { hasAppeared = false; super.viewWillDisappear(animated) }
}

@available(iOS 18.0, *)
private final class IPadTabBarController: UITabBarController {
    var onHorizontalSizeClassChange: ((Bool) -> Void)?
    var onDidAppear: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (controller: IPadTabBarController, _: UITraitCollection) in
            controller.onHorizontalSizeClassChange?(controller.traitCollection.horizontalSizeClass == .regular)
        }
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); onDidAppear?() }
}
#endif
