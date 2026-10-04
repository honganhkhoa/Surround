//
//  DuoTabContainer.swift
//  Surround
//

import SwiftUI
import UIKit
import Observation

/// A tab's bridge to the chrome owned by the UIKit container. Optional in the
/// environment so the existing iPad and Catalyst tab roots keep their behavior.
@MainActor
@Observable
final class DuoTabContext {
    private(set) var sidebarAvailable = false
    private(set) var sidebarVisible = false
    private(set) var sidebarTransitionInProgress = false
    private(set) var horizontalSidebarInsets = EdgeInsets()
    private(set) var physicalHorizontalInsets = EdgeInsets()
    private(set) var layoutSize = CGSize.zero

    @ObservationIgnored private var hiddenTabBarOwners = Set<UUID>()
    @ObservationIgnored var onTabBarVisibilityChange: (() -> Void)?

    func setTabBarHidden(_ hidden: Bool, owner: UUID) {
        let wasHidden = prefersTabBarHidden
        if hidden {
            hiddenTabBarOwners.insert(owner)
        } else {
            hiddenTabBarOwners.remove(owner)
        }
        if wasHidden != prefersTabBarHidden { onTabBarVisibilityChange?() }
    }

    func removeTabBarHiddenRequest(owner: UUID) {
        setTabBarHidden(false, owner: owner)
    }

    fileprivate var prefersTabBarHidden: Bool { !hiddenTabBarOwners.isEmpty }

    fileprivate func setSidebarTransitionInProgress(_ inProgress: Bool) {
        sidebarTransitionInProgress = inProgress
    }

    fileprivate func update(_ metrics: DuoTabMetrics) {
        sidebarAvailable = metrics.sidebarAvailable
        sidebarVisible = metrics.sidebarVisible
        horizontalSidebarInsets = metrics.horizontalSidebarInsets
        physicalHorizontalInsets = metrics.physicalHorizontalInsets
        layoutSize = metrics.layoutSize
    }
}

private struct DuoTabContextKey: EnvironmentKey {
    static let defaultValue: DuoTabContext? = nil
}

extension EnvironmentValues {
    var duoTabContext: DuoTabContext? {
        get { self[DuoTabContextKey.self] }
        set { self[DuoTabContextKey.self] = newValue }
    }
}

fileprivate struct DuoTabMetrics: Equatable {
    var sidebarAvailable = false
    var sidebarVisible = false
    var horizontalSidebarInsets = EdgeInsets()
    var physicalHorizontalInsets = EdgeInsets()
    var layoutSize = CGSize.zero
}

private struct DuoHostBaselineKey: Hashable {
    let root: RootView
    let width: CGFloat
    let height: CGFloat
    let physicalLeft: CGFloat
    let physicalRight: CGFloat
    let rightToLeft: Bool
}

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0)
/// Owns the native groups while the hosted SwiftUI stacks continue to own all
/// navigation. Neither the tabs nor their hosting controllers are recreated
/// when the phone folds or a different account destination becomes available.
@available(iOS 27.0, *)
struct DuoTabContainer: UIViewControllerRepresentable {
    @Binding var selection: RootView
    let isLoggedIn: Bool
    var messagesBadgeCount = 0
    let content: (RootView) -> AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, isLoggedIn: isLoggedIn, content: content)
    }

    func makeUIViewController(context: Context) -> UITabBarController {
        context.coordinator.makeController(
            regularWidth: context.environment.horizontalSizeClass == .regular,
            layoutDirection: context.environment.layoutDirection
        )
    }

    func updateUIViewController(_ controller: UITabBarController, context: Context) {
        context.coordinator.update(
            selection: $selection,
            isLoggedIn: isLoggedIn,
            messagesBadgeCount: messagesBadgeCount,
            content: content,
            regularWidth: context.environment.horizontalSizeClass == .regular,
            layoutDirection: context.environment.layoutDirection
        )
    }

    @MainActor
    final class Coordinator: NSObject, UITabBarControllerDelegate, UITabBarController.Sidebar.Delegate {
        private var selection: Binding<RootView>
        private var isLoggedIn: Bool
        private var content: (RootView) -> AnyView
        private weak var controller: DuoTabBarController?
        private var hosts = [RootView: DuoTabHostingController]()
        private var tabs = [RootView: UITab]()
        private var contexts = [RootView: DuoTabContext]()
        private let surroundContent = DuoTabGroupContentController()
        private let ogsContent = DuoTabGroupContentController()
        private var surroundGroup: UITabGroup!
        private var ogsGroup: UITabGroup!
        private var topology: [String] = []
        private var changingTabs = false
        private var regularWidth = false
        private var previousBoundsSize: CGSize?
        private var pendingMetrics: DuoTabMetrics?
        private var deliveredMetrics: DuoTabMetrics?
        private var metricsDeliveryScheduled = false
        private var sidebarTransitionID = UUID()
        private var sidebarTransitionInProgress = false
        private var hiddenHostBaselines = [DuoHostBaselineKey: UIEdgeInsets]()
        #if DEBUG
        private var previousDiagnostic = ""
        #endif

        init(selection: Binding<RootView>, isLoggedIn: Bool, content: @escaping (RootView) -> AnyView) {
            self.selection = selection
            self.isLoggedIn = isLoggedIn
            self.content = content
        }

        func makeController(regularWidth: Bool, layoutDirection: LayoutDirection) -> UITabBarController {
            let controller = DuoTabBarController()
            self.controller = controller
            #if DEBUG
            controller.view.accessibilityIdentifier = "navigation.container.duo"
            #endif
            controller.delegate = self
            controller.mode = .tabSidebar
            controller.sidebar.preferredPlacement = .sidebar
            controller.sidebar.preferredLayout = .overlap
            controller.sidebar.isHidden = true
            controller.sidebar.delegate = self
            controller.onLayout = { [weak self] in self?.layoutDidChange() }
            controller.onHorizontalSizeClassChange = { [weak self] regular in
                self?.hiddenHostBaselines.removeAll()
                self?.applyTabs(regularWidth: regular)
            }
            controller.onWillTransition = { [weak controller] in
                controller?.sidebar.isHidden = true
            }

            for root in RootView.allCases {
                let tabContext = DuoTabContext()
                tabContext.onTabBarVisibilityChange = { [weak self] in
                    self?.applyTabBarVisibility()
                }
                contexts[root] = tabContext
                let host = DuoTabHostingController(rootView: hostedContent(root))
                host.onLayout = { [weak self] in self?.measureLayout() }
                hosts[root] = host
                let tab = UITab(
                    title: root.title,
                    image: UIImage(systemName: root.systemImage),
                    identifier: root.rawValue
                ) { _ in host }
                // The app owns destination order; there is no sidebar editing.
                tab.preferredPlacement = .fixed
                tab.accessibilityIdentifier = accessibilityIdentifier(root)
                tabs[root] = tab
            }
            surroundGroup = UITabGroup(
                title: "Surround", image: nil, identifier: "surround.group", children: []
            ) { [surroundContent] _ in surroundContent }
            surroundGroup.preferredPlacement = .fixed
            surroundGroup.sidebarAppearance = .rootSection
            ogsGroup = UITabGroup(
                title: "OGS", image: nil, identifier: "ogs.group", children: []
            ) { [ogsContent] _ in ogsContent }
            ogsGroup.preferredPlacement = .fixed
            ogsGroup.sidebarAppearance = .rootSection
            applyLayoutDirection(layoutDirection)
            applyTabs(regularWidth: regularWidth)
            return controller
        }

        func update(
            selection: Binding<RootView>,
            isLoggedIn: Bool,
            messagesBadgeCount: Int,
            content: @escaping (RootView) -> AnyView,
            regularWidth: Bool,
            layoutDirection: LayoutDirection
        ) {
            self.selection = selection
            self.isLoggedIn = isLoggedIn
            self.content = content
            applyLayoutDirection(layoutDirection)
            for (root, host) in hosts {
                host.rootView = hostedContent(root)
                tabs[root]?.title = root.title
            }
            tabs[.privateMessages]?.badgeValue = messagesBadgeCount > 0 ? String(messagesBadgeCount) : nil
            applyTabs(regularWidth: regularWidth)
            measureLayout()
        }

        private func hostedContent(_ root: RootView) -> AnyView {
            AnyView(content(root).environment(\.duoTabContext, contexts[root]))
        }

        private var selectedRoot: RootView {
            let root = selection.wrappedValue
            return !isLoggedIn && (root == .profile || root == .privateMessages) ? .home : root
        }

        private func applyLayoutDirection(_ direction: LayoutDirection) {
            guard let controller else { return }
            let attribute: UISemanticContentAttribute = direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
            if controller.view.semanticContentAttribute != attribute {
                controller.sidebar.isHidden = true
                hiddenHostBaselines.removeAll()
                controller.view.semanticContentAttribute = attribute
            }
        }

        private func applyTabs(regularWidth: Bool) {
            guard let controller, let surroundGroup, let ogsGroup, !changingTabs else { return }
            self.regularWidth = regularWidth
            let root = selectedRoot
            if let currentTab = controller.selectedTab, currentTab.identifier != root.rawValue {
                // External routes and account redirects use the same close
                // policy as a user selecting a destination in the sidebar.
                controller.sidebar.isHidden = true
            }
            var primaryRoots: [RootView] = [.home, .publicGames]
            if isLoggedIn { primaryRoots.append(.privateMessages) }
            var desiredRoots = primaryRoots
            if regularWidth {
                if isLoggedIn { desiredRoots.append(.profile) }
            } else {
                desiredRoots.append(.browser)
                if [.profile, .settings, .about, .forums].contains(root) {
                    desiredRoots.append(root)
                }
            }
            let desiredTopology = desiredRoots.map(\.rawValue)
                + (regularWidth ? ["surround.group", "ogs.group"] : [])
                + (regularWidth && root == .forums ? ["ogs.forums"] : [])

            changingTabs = true
            defer { changingTabs = false }
            if topology != desiredTopology {
                controller.performBatchUpdates {
                    // Detach before reparenting: a UITab cannot simultaneously
                    // be a root tab and a child of a group.
                    controller.setTabs(primaryRoots.compactMap { tabs[$0] }, animated: false)
                    surroundContent.show(nil)
                    ogsContent.show(nil)
                    surroundGroup.children = []
                    ogsGroup.children = []
                    var desiredTabs = desiredRoots.compactMap { tabs[$0] }
                    if regularWidth {
                        let surroundRoots: [RootView] = [.settings, .about]
                        let ogsRoots: [RootView] = root == .forums ? [.browser, .forums] : [.browser]
                        surroundGroup.children = surroundRoots.compactMap { tabs[$0] }
                        ogsGroup.children = ogsRoots.compactMap { tabs[$0] }
                        desiredTabs += [surroundGroup, ogsGroup]
                    }
                    controller.setTabs(desiredTabs, animated: false)
                    controller.selectedTab = tabs[root]
                }
                topology = desiredTopology
            } else if controller.selectedTab !== tabs[root] {
                controller.selectedTab = tabs[root]
            }
            if regularWidth {
                // A group's provider supplies its displayed root when no
                // managing navigation controller is set. Forward its selected
                // leaf here; SwiftUI remains the sole navigation-stack owner.
                if root == .settings || root == .about {
                    surroundGroup.selectedChild = tabs[root]
                    surroundContent.show(hosts[root])
                } else if root == .browser || root == .forums {
                    ogsGroup.selectedChild = tabs[root]
                    ogsContent.show(hosts[root])
                }
            }
            applyTabBarVisibility()
            #if DEBUG
            if ProcessInfo.processInfo.environment["SURROUND_DUO_SIDEBAR_DIAGNOSTICS"] == "1" {
                let selectedController = controller.selectedViewController.map { String(describing: type(of: $0)) } ?? "none"
                let host = hosts[root]
                let parent = host?.parent.map { String(describing: type(of: $0)) } ?? "none"
                let group = tabs[root]?.parent
                let groupController = group?.viewController
                print("DUO-SELECTION root=\(root.rawValue) selectedController=\(selectedController) hostParent=\(parent) hostWindow=\(host?.viewIfLoaded?.window != nil) groupWindow=\(groupController?.viewIfLoaded?.window != nil)")
            }
            #endif
        }

        private func applyTabBarVisibility() {
            guard let controller else { return }
            let root = controller.selectedTab.flatMap { RootView(rawValue: $0.identifier) } ?? selectedRoot
            let hidden = contexts[root]?.prefersTabBarHidden ?? false
            if controller.isTabBarHidden != hidden {
                // Toolbar changes require their own closed baseline; they must
                // never be misclassified as sidebar occlusion.
                controller.sidebar.isHidden = true
                hiddenHostBaselines.removeAll()
                controller.setTabBarHidden(hidden, animated: controller.view.window != nil)
            }
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
            guard !changingTabs, let root = RootView(rawValue: selectedTab.identifier) else { return }
            if selection.wrappedValue != root { selection.wrappedValue = root }
            tabBarController.sidebar.isHidden = true
            applyTabs(regularWidth: regularWidth)
            measureLayout()
        }

        func tabBarController(_ tabBarController: UITabBarController, sidebarAvailabilityDidChange sidebar: UITabBarController.Sidebar) {
            if !sidebar.isAvailable { sidebar.isHidden = true }
            applyTabs(regularWidth: tabBarController.traitCollection.horizontalSizeClass == .regular)
            measureLayout()
        }

        func tabBarController(_ tabBarController: UITabBarController, sidebarVisibilityWillChange sidebar: UITabBarController.Sidebar, animator: any UITabBarController.Sidebar.Animating) {
            // Set the guard before native layout starts. Publishing geometry
            // later must not let content cache an animated inset as its hidden
            // baseline, including the last frame of a closing animation.
            sidebarTransitionID = UUID()
            sidebarTransitionInProgress = true
            let transitionID = sidebarTransitionID
            for context in contexts.values { context.setSidebarTransitionInProgress(true) }
            animator.addAnimations { [weak self] in self?.measureLayout() }
            animator.addCompletion { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.sidebarTransitionID == transitionID else { return }
                    // Nonanimated completions may run before UIKit has
                    // finished the setter's layout pass. Read settled geometry
                    // on the next main turn before releasing the guard.
                    self.controller?.view.layoutIfNeeded()
                    self.measureLayout()
                    self.deliverMetrics()
                    self.sidebarTransitionInProgress = false
                    for context in self.contexts.values { context.setSidebarTransitionInProgress(false) }
                    self.measureLayout()
                }
            }
        }

        private func layoutDidChange() {
            guard let controller else { return }
            let size = controller.view.bounds.size
            if let previousBoundsSize, previousBoundsSize != size {
                controller.sidebar.isHidden = true
                hiddenHostBaselines.removeAll()
            }
            previousBoundsSize = size
            measureLayout()
        }

        private func measureLayout() {
            guard let controller, controller.isViewLoaded else { return }
            let root = controller.selectedTab.flatMap { RootView(rawValue: $0.identifier) } ?? selectedRoot
            guard let host = hosts[root],
                  host.isViewLoaded, let window = host.view.window else { return }
            let bounds = host.view.bounds
            let physicalFrame = host.view.convert(window.safeAreaLayoutGuide.layoutFrame, from: window)
            let physicalLeft = max(0, physicalFrame.minX - bounds.minX)
            let physicalRight = max(0, bounds.maxX - physicalFrame.maxX)
            let hostInsets = host.view.safeAreaInsets
            let sidebarVisible = controller.sidebar.isAvailable && !controller.sidebar.isHidden
            let rightToLeft = host.view.effectiveUserInterfaceLayoutDirection == .rightToLeft
            let baselineKey = DuoHostBaselineKey(
                root: root,
                width: bounds.width,
                height: bounds.height,
                physicalLeft: physicalLeft,
                physicalRight: physicalRight,
                rightToLeft: rightToLeft
            )
            if !sidebarVisible && !sidebarTransitionInProgress {
                hiddenHostBaselines[baselineKey] = hostInsets
            }
            let closedInsets = hiddenHostBaselines[baselineKey]
            if sidebarVisible && closedInsets == nil && !sidebarTransitionInProgress {
                // A new pose or chrome configuration needs one settled hidden
                // measurement before we can attribute any inset to its drawer.
                controller.sidebar.isHidden = true
                return
            }
            let sidebarLeft = sidebarVisible ? max(0, hostInsets.left - (closedInsets?.left ?? hostInsets.left)) : 0
            let sidebarRight = sidebarVisible ? max(0, hostInsets.right - (closedInsets?.right ?? hostInsets.right)) : 0
            let metrics = DuoTabMetrics(
                sidebarAvailable: controller.sidebar.isAvailable,
                sidebarVisible: sidebarVisible,
                horizontalSidebarInsets: EdgeInsets(
                    top: 0,
                    leading: rightToLeft ? sidebarRight : sidebarLeft,
                    bottom: 0,
                    trailing: rightToLeft ? sidebarLeft : sidebarRight
                ),
                physicalHorizontalInsets: EdgeInsets(
                    top: 0,
                    leading: rightToLeft ? physicalRight : physicalLeft,
                    bottom: 0,
                    trailing: rightToLeft ? physicalLeft : physicalRight
                ),
                layoutSize: bounds.size
            )
            pendingMetrics = metrics
            if !metricsDeliveryScheduled {
                metricsDeliveryScheduled = true
                // Layout callbacks run during SwiftUI updates. Coalesce to the
                // current geometry and deliver after that update completes.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.metricsDeliveryScheduled = false
                    self.deliverMetrics()
                }
            }
            #if DEBUG
            if ProcessInfo.processInfo.environment["SURROUND_DUO_SIDEBAR_DIAGNOSTICS"] == "1" {
                let contentFrame = host.view.convert(controller.contentLayoutGuide.layoutFrame, from: controller.view)
                let selectedController = controller.selectedViewController.map { String(describing: type(of: $0)) } ?? "none"
                let hostParent = host.parent.map { String(describing: type(of: $0)) } ?? "none"
                let group = controller.selectedTab?.parent
                let groupController = group?.viewController.map { String(describing: type(of: $0)) } ?? "none"
                let diagnostic = "root=\(controller.selectedTab?.identifier ?? "none") selectedController=\(selectedController) hostParent=\(hostParent) groupController=\(groupController) bounds=\(bounds) safe=\(hostInsets) closed=\(String(describing: closedInsets)) sidebarDelta=(left:\(sidebarLeft),right:\(sidebarRight)) margins=\(host.view.layoutMargins) physical=\(physicalFrame) content=\(contentFrame) available=\(metrics.sidebarAvailable) visible=\(sidebarVisible) transitioning=\(sidebarTransitionInProgress)"
                if diagnostic != previousDiagnostic {
                    previousDiagnostic = diagnostic
                    print("DUO-SIDEBAR \(diagnostic)")
                }
            }
            #endif
        }

        private func deliverMetrics() {
            guard let latest = pendingMetrics, latest != deliveredMetrics else { return }
            deliveredMetrics = latest
            for context in contexts.values { context.update(latest) }
        }

        private func accessibilityIdentifier(_ root: RootView) -> String? {
            switch root {
            case .home: return SurroundUITestContract.AccessibilityID.navigationHome
            case .publicGames: return SurroundUITestContract.AccessibilityID.navigationPublicGames
            case .privateMessages: return SurroundUITestContract.AccessibilityID.navigationMessages
            case .profile: return SurroundUITestContract.AccessibilityID.navigationProfile
            case .settings: return SurroundUITestContract.AccessibilityID.navigationSettings
            case .about: return SurroundUITestContract.AccessibilityID.navigationAbout
            case .browser: return SurroundUITestContract.AccessibilityID.navigationBrowser
            case .forums: return nil
            }
        }
    }
}

@available(iOS 27.0, *)
private final class DuoTabGroupContentController: UIViewController {
    private var displayedHost: UIViewController?
    private var childConstraints: [NSLayoutConstraint] = []
    private var childTranslatedAutoresizingMask = true
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
            NSLayoutConstraint.deactivate(childConstraints)
            previous.view.removeFromSuperview()
            previous.view.translatesAutoresizingMaskIntoConstraints = childTranslatedAutoresizingMask
            previous.removeFromParent()
        }
        displayedHost = host
        childConstraints = []
        if let host {
            // Native selection may already have attached the leaf while
            // displaying its group root. This container owns the forwarding
            // relationship, and releases it before compact promotion.
            if host.parent != nil {
                host.willMove(toParent: nil)
                host.view.removeFromSuperview()
                host.removeFromParent()
            }
            addChild(host)
            childTranslatedAutoresizingMask = host.view.translatesAutoresizingMaskIntoConstraints
            host.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host.view)
            childConstraints = [
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: view.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ]
            NSLayoutConstraint.activate(childConstraints)
            host.didMove(toParent: self)
        }
        if hasAppeared {
            previous?.endAppearanceTransition()
            host?.endAppearanceTransition()
        }
        setNeedsStatusBarAppearanceUpdate()
    }

    override var childForStatusBarStyle: UIViewController? { displayedHost }
    override var childForStatusBarHidden: UIViewController? { displayedHost }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        hasAppeared = false
        super.viewWillDisappear(animated)
    }
}

@available(iOS 27.0, *)
private final class DuoTabBarController: UITabBarController {
    var onLayout: (() -> Void)?
    var onHorizontalSizeClassChange: ((Bool) -> Void)?
    var onWillTransition: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (controller: DuoTabBarController, _: UITraitCollection) in
            controller.onHorizontalSizeClassChange?(controller.traitCollection.horizontalSizeClass == .regular)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onLayout?()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        onWillTransition?()
        super.viewWillTransition(to: size, with: coordinator)
    }
}

@available(iOS 27.0, *)
private final class DuoTabHostingController: UIHostingController<AnyView> {
    var onLayout: (() -> Void)?

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        onLayout?()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onLayout?()
    }
}
#endif
