import Combine
import SwiftUI
import UIKit
import Observation

/// The small chrome bridge needed by roots hosted outside SwiftUI's TabView.
@MainActor
@Observable
final class IPadTabContext {
    private(set) var sidebarAvailable = false
    private(set) var sidebarVisible = false
    private(set) var sidebarInsets = EdgeInsets()
    private(set) var physicalHorizontalInsets = EdgeInsets()
    /// The sidebar as the window's SwiftUI chrome reads it: the custom
    /// Activity bar and the host policy's facts. It is the coordinator's
    /// sidebar record a main-queue turn later (shown as the sidebar starts to
    /// show, hidden once its hide completes) and unavailable without a
    /// sidebar. Never `sidebarVisible`, which follows layout a turn late.
    private(set) var activitySidebar = ActivityHostPolicy.Sidebar.unavailable
    @ObservationIgnored private var hiddenTabBarOwners = Set<UUID>()
    @ObservationIgnored var onTabBarVisibilityChange: (() -> Void)?
    @ObservationIgnored var onToggleSidebar: (() -> Void)?
    /// This tab's top route shows Game Detail, from its stack's own path:
    /// set as soon as a game is asked for, before the game's first layout.
    @ObservationIgnored private(set) var isGameAskedFor = false
    @ObservationIgnored var onGameAskedForChange: (() -> Void)?

    /// Before iPadOS 27, the sidebar toggle lives in the tab bar; a screen
    /// that hides the tab bar draws its own.
    func toggleSidebar() {
        onToggleSidebar?()
    }

    func setTabBarHidden(_ hidden: Bool, owner: UUID) {
        let previous = prefersTabBarHidden
        if hidden { hiddenTabBarOwners.insert(owner) }
        else { hiddenTabBarOwners.remove(owner) }
        if previous != prefersTabBarHidden { onTabBarVisibilityChange?() }
    }

    func removeTabBarHiddenRequest(owner: UUID) { setTabBarHidden(false, owner: owner) }

    /// From the tab's StackRouter, as its top route starts or stops showing a
    /// game: handed to the coordinator at once.
    func setGameAskedFor(_ asked: Bool) {
        guard asked != isGameAskedFor else { return }
        isGameAskedFor = asked
        onGameAskedForChange?()
    }

    fileprivate var prefersTabBarHidden: Bool { !hiddenTabBarOwners.isEmpty }
    fileprivate func update(_ metrics: IPadTabMetrics) {
        sidebarAvailable = metrics.sidebarAvailable
        sidebarVisible = metrics.sidebarVisible
        sidebarInsets = metrics.insets.occlusion
        physicalHorizontalInsets = metrics.insets.physical
    }

    fileprivate func setActivitySidebar(_ sidebar: ActivityHostPolicy.Sidebar) {
        guard sidebar != activitySidebar else { return }
        activitySidebar = sidebar
    }
}

fileprivate struct IPadTabMetrics: Equatable {
    let sidebarAvailable: Bool
    let sidebarVisible: Bool
    let insets: AppSidebarInsets
}

private struct IPadHostBaselineKey: Hashable {
    let root: RootView
    let width: CGFloat
    let height: CGFloat
    let physicalLeft: CGFloat
    let physicalRight: CGFloat
    let rightToLeft: Bool
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
/// Native overlay navigation with account rows that open the shared
/// sheet presenter. Each SwiftUI root retains its own navigation stack.
/// It also hosts the window's Activity: the floating bar in UIKit's bottom
/// accessory from iPadOS 26 while the sidebar is hidden or the window is
/// compact, and the Now section in the sidebar's bottom bar.
@available(iOS 18.0, *)
struct IPadTabContainer: UIViewControllerRepresentable {
    @Binding var selection: RootView
    let isLoggedIn: Bool
    var messagesBadgeCount = 0
    let onAccountSheet: (AccountSheet) -> Void
    let content: (RootView) -> AnyView
    /// The window's registry: its settled place for the selected tab hides
    /// the Activity bar.
    let activityPlaces: ActivityPlaceRegistry
    /// The window's bar state, observed, so each change of it calls the
    /// coordinator's `update(...)`.
    @ObservedObject var activityBar: ActivityBarState
    /// Gives the bar and the Now section the window's environment: MainView's
    /// function, the one its tabs' content goes through.
    let accessoryContent: (AnyView) -> AnyView
    /// Closes the window's Activity popover where the Now section opened it,
    /// as the sidebar it hangs from goes.
    let closeNowSectionPopover: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UITabBarController {
        context.coordinator.persistsSidebarChoice = context.environment.surroundAllowsLocalPersistence
        return context.coordinator.makeController(
            regularWidth: context.environment.horizontalSizeClass == .regular,
            layoutDirection: context.environment.layoutDirection
        )
    }

    func updateUIViewController(_ controller: UITabBarController, context: Context) {
        context.coordinator.persistsSidebarChoice = context.environment.surroundAllowsLocalPersistence
        context.coordinator.update(
            self, regularWidth: context.environment.horizontalSizeClass == .regular,
            layoutDirection: context.environment.layoutDirection
        )
    }

    @MainActor
    final class Coordinator: NSObject, UITabBarControllerDelegate, UITabBarController.Sidebar.Delegate {
        private var parent: IPadTabContainer
        private weak var controller: IPadTabBarController?
        private var hosts = [RootView: IPadTabHostingController]()
        private var tabs = [RootView: UITab]()
        private var contexts = [RootView: IPadTabContext]()
        private let surroundContent = IPadTabGroupContentController()
        private let ogsContent = IPadTabGroupContentController()
        private var surroundGroup: UITabGroup!
        private var ogsGroup: UITabGroup!
        private var topology: [String] = []
        private var changingTabs = false
        private var regularWidth = false
        private var hiddenHostBaselines = [IPadHostBaselineKey: UIEdgeInsets]()
        private var sidebarTransitionID = UUID()
        private var sidebarTransitionInProgress = false
        private var pendingMetrics: IPadTabMetrics?
        private var deliveredMetrics: IPadTabMetrics?
        private var metricsDeliveryScheduled = false
        /// Where the sidebar sits beside content, the person's choice between
        /// it and the top tab bar. It outlives games and launches.
        private var prefersSidebarHidden = userDefaults[.iPadSidebarHidden] ?? false
        var persistsSidebarChoice = true
        /// The window size at which the open sidebar last sat beside content.
        private var sidebarBesideContentSize: CGSize?
        private var changingSidebar = false
        private var selectingTab = false
        private var revealedByPerson = false

        // MARK: The Activity bar's records
        //
        // UIKit's accessory follows these and the window's bar state
        // (`ActivityBarHostState`), never isTabBarHidden, the sidebar's
        // isHidden or a frame. Each changes only outside layout: around
        // setTabBarHidden, as a tab's stack asks for a game, as the sidebar
        // starts to show or its hide completes, a main-queue turn after a
        // keyboard notification, or as the view comes into a window.

        private let accessory = ActivityAccessoryHost(container: .iPadTabContainer)
        /// The Now section's host in the sidebar's bottom bar, made once. It
        /// sizes itself to its content, down to nothing, and its root view is
        /// updated in place.
        private let nowSection = UIHostingController(rootView: AnyView(EmptyView()))
        private weak var subscribedPlaces: ActivityPlaceRegistry?
        private var registrySubscription: AnyCancellable?
        private var keyboardSubscription: AnyCancellable?
        /// The tab-bar state last asked of UIKit: hidden just before
        /// setTabBarHidden(true), shown once setTabBarHidden(false) has
        /// returned and the person's sidebar choice is restored.
        private var requestedTabBar = ActivityTabBarRecord.shown
        /// A setTabBarHidden call runs. A request made inside its layout
        /// waits for it to return, so the record never changes mid-call.
        private var tabBarChangeInProgress = false
        private var tabBarRequestWaits = false
        /// The container's view has come into a window: the first set waits
        /// for it.
        private var isInWindow = false
        /// The sidebar as the accessory sees it: shown as it starts to show,
        /// hidden once its hide completes, or at once for a change that
        /// starts no transition. Never the sidebar's isHidden, which already
        /// holds where a slide goes as it starts.
        private var isSidebarRecordShown = false
        /// A sidebar change made here started a transition.
        private var sidebarChangeStartedTransition = false
        /// The show whose animator takes the bar away, until it does.
        private var sidebarClearWaits: UUID?
        private var isKeyboardOverWindow = false
        private var sidebarCopyScheduled = false
        #if DEBUG && MAIN_APP
        private var nowSectionFocusObserver: NSObjectProtocol?
        #endif

        init(_ parent: IPadTabContainer) { self.parent = parent }

        func makeController(regularWidth: Bool, layoutDirection: LayoutDirection) -> UITabBarController {
            let controller = IPadTabBarController()
            self.controller = controller
            controller.view.accessibilityIdentifier = "navigation.container.ipad"
            controller.delegate = self
            controller.mode = .tabSidebar
            controller.sidebar.preferredLayout = .overlap
            // From iPadOS 26, UIKit restores the sidebar's last toggled
            // visibility under this identifier. UI tests start from its default.
            if SurroundUITestContract.isEnabled { controller.customizationIdentifier = UUID().uuidString }
            if prefersSidebarHidden { controller.sidebar.isHidden = true }
            controller.sidebar.delegate = self
            controller.onHorizontalSizeClassChange = { [weak self] in self?.horizontalSizeClassDidChange($0) }
            controller.onLayout = { [weak self] in self?.layoutDidChange() }
            controller.onIsAppearing = { [weak self] in self?.viewIsAppearing() }
            controller.onTransitionCompleted = { [weak self] in self?.sizeTransitionCompleted() }
            controller.onTextSizeChange = { [weak self] in
                DispatchQueue.main.async { [weak self] in self?.readWindowForNowSection() }
            }
            // The bar's environment before any recompute draws it.
            connect()
            keyboardSubscription = SystemPlatformServices.shared.keyboardWillChangeFramePublisher
                // A main-queue turn after each notification, outside the
                // layout it may arrive in.
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in self?.keyboardDidChange(notification) }
            for root in RootView.allCases {
                let tabContext = IPadTabContext()
                tabContext.onTabBarVisibilityChange = { [weak self] in self?.applyTabBarVisibility() }
                tabContext.onToggleSidebar = { [weak self] in self?.toggleSidebar() }
                tabContext.onGameAskedForChange = { [weak self] in self?.gameAskedForDidChange(root) }
                contexts[root] = tabContext
                let host = IPadTabHostingController(rootView: hostedContent(root))
                host.onLayout = { [weak self] in self?.measureLayout() }
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
            // Seeded once the tabs are in place: from iPadOS 26 UIKit
            // restores the sidebar itself. No view has read the copies yet.
            seedSidebarRecord(reason: "make", recomputes: false)
            for context in contexts.values { context.setActivitySidebar(accessorySidebar) }
            // The Now section, in the sidebar's bottom bar on every iPadOS.
            nowSection.sizingOptions = .intrinsicContentSize
            // The sidebar's own insets, but not the keyboard's. A keyboard
            // over the sidebar would otherwise change the section's size,
            // the sidebar would lay its bottom bar out again at that size,
            // which changes how much of it the keyboard covers, and so on
            // without end: the app would stop responding.
            nowSection.safeAreaRegions = .container
            nowSection.view.backgroundColor = .clear
            nowSection.rootView = nowSectionRoot()
            controller.sidebar.bottomBarView = nowSection.view
            #if DEBUG && MAIN_APP
            observeNowSectionFocus()
            #endif
            return controller
        }

        func update(_ parent: IPadTabContainer, regularWidth: Bool, layoutDirection: LayoutDirection) {
            self.parent = parent
            connect()
            applyLayoutDirection(layoutDirection)
            for (root, host) in hosts {
                host.rootView = hostedContent(root)
                tabs[root]?.title = root == .about ? String(localized: "About") : root.title
            }
            tabs[.privateMessages]?.badgeValue = parent.messagesBadgeCount > 0
                ? String(parent.messagesBadgeCount) : nil
            applyTabs(regularWidth: regularWidth)
            nowSection.rootView = nowSectionRoot()
            // The bar state, sign-in or a tab's content changed.
            recomputeAccessory(reason: "update")
        }

        /// MainView's inputs; the registry is subscribed to once.
        private func connect() {
            accessory.setEnvironment(parent.accessoryContent)
            guard subscribedPlaces !== parent.activityPlaces else { return }
            subscribedPlaces = parent.activityPlaces
            // Sent after the settled state is stored, a main-queue turn after
            // the screens change.
            registrySubscription = parent.activityPlaces.stateDidChange
                .sink { [weak self] _ in self?.recomputeAccessory(reason: "registry") }
        }

        private func hostedContent(_ root: RootView) -> AnyView {
            AnyView(parent.content(root).environment(\.iPadTabContext, contexts[root]))
        }

        private func nowSectionRoot() -> AnyView {
            parent.accessoryContent(AnyView(ActivityNowSection(bar: parent.activityBar)))
        }

        private func isPrimary(_ root: RootView) -> Bool {
            [.home, .publicGames, .privateMessages].contains(root)
        }

        private var selectedRoot: RootView {
            let root = parent.selection
            return !parent.isLoggedIn && (root == .profile || root == .privateMessages) ? .home : root
        }

        /// Whether the window has a sidebar, from the controller's state:
        /// none in compact width, where a bottom tab bar takes its place.
        private var isSidebarAvailable: Bool {
            guard let controller else { return false }
            #if canImport(SwiftUI, _version: 8.0)
            if #available(iOS 27.0, *) { return controller.sidebar.isAvailable }
            #endif
            return regularWidth && controller.mode != .tabBar
        }

        private func applyLayoutDirection(_ direction: LayoutDirection) {
            guard let controller else { return }
            let attribute: UISemanticContentAttribute = direction == .rightToLeft
                ? .forceRightToLeft : .forceLeftToRight
            let current = controller.view.semanticContentAttribute
            guard current != attribute else { return }
            // The first direction is set at creation; only a later flip moves
            // the sidebar to the other edge.
            if current != .unspecified {
                setSidebarHidden(true)
                hiddenHostBaselines.removeAll()
            }
            controller.view.semanticContentAttribute = attribute
        }

        /// The sidebar stays open beside other screens after a selection. It
        /// overlays only a game, which hides the tab bar, so close it there.
        /// In overlay widths (portrait) UIKit closes it after a selection.
        private func closeSidebarOverGame() {
            guard let controller, controller.isTabBarHidden else { return }
            setSidebarHidden(true)
        }

        /// The app's own changes never count as the person's choice.
        private func setSidebarHidden(_ hidden: Bool) {
            guard let controller, controller.sidebar.isHidden != hidden else { return }
            changingSidebar = true
            sidebarChangeStartedTransition = false
            controller.sidebar.isHidden = hidden
            changingSidebar = false
            sidebarChangedWithoutTransition()
        }

        private func saveSidebarChoice(hidden: Bool) {
            prefersSidebarHidden = hidden
            if persistsSidebarChoice { userDefaults[.iPadSidebarHidden] = hidden }
        }

        /// Leaving a game puts back the person's choice. UIKit forgets its
        /// own once the app changes the sidebar.
        private func restoreSidebarChoice() {
            guard let controller, !controller.isTabBarHidden else { return }
            if prefersSidebarHidden {
                setSidebarHidden(true)
            } else if sidebarBesideContentSize == controller.view.bounds.size {
                setSidebarHidden(false)
            }
            scheduleSidebarCopy()
        }

        private func applyTabs(regularWidth: Bool) {
            guard let controller, surroundGroup != nil, ogsGroup != nil, !changingTabs else { return }
            self.regularWidth = regularWidth
            tabs[.browser]?.preferredPlacement = regularWidth ? .sidebarOnly : .fixed
            let root = selectedRoot
            if let selected = controller.selectedTab, effectiveRoot(selected) != root {
                closeSidebarOverGame()
            }
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
            DispatchQueue.main.async { [weak self] in self?.measureLayout() }
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
            selectingTab = true
            DispatchQueue.main.async { [weak self] in self?.selectingTab = false }
            closeSidebarOverGame()
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
            measureLayout()
            // A sidebar that goes or comes with its availability may send no
            // transition: the record follows UIKit a turn later.
            DispatchQueue.main.async { [weak self] in self?.seedSidebarRecord(reason: "sidebar.availability") }
            scheduleSidebarCopy()
            recomputeAccessory(reason: "sidebar.availability")
        }

        func tabBarController(_ controller: UITabBarController, sidebarVisibilityWillChange sidebar: UITabBarController.Sidebar,
                              animator: any UITabBarController.Sidebar.Animating) {
            // Only the person's own toggle beside content is a choice: not the
            // app's, not UIKit's after a selection or a resize, not over a game.
            revealedByPerson = false
            if !changingSidebar, !selectingTab, !controller.isTabBarHidden,
               self.controller?.isTransitioningSize == false {
                if !sidebar.isHidden {
                    revealedByPerson = true
                } else if sidebarBesideContentSize == controller.view.bounds.size {
                    saveSidebarChoice(hidden: true)
                }
            }
            sidebarTransitionID = UUID()
            sidebarTransitionInProgress = true
            sidebarChangeStartedTransition = true
            let transitionID = sidebarTransitionID
            // isHidden already holds where the sidebar is going.
            let showing = !sidebar.isHidden
            #if DEBUG && MAIN_APP
            let started = CACurrentMediaTime()
            logSidebar("willChange", transitionID, [("target", showing ? "shown" : "hidden")])
            #endif
            if showing {
                // The record turns shown as the sidebar starts to show, and
                // the bar goes inside the sidebar's own animator, with no
                // animation of its own: an animated change here stalls the
                // slide, and an unanimated one before it snaps it open. The
                // animator runs before the main queue's next turn; on iPadOS
                // 26.1 an app's own show can run neither its animator nor its
                // completion, and the bar then goes on that turn.
                setSidebarRecord(true, reason: "sidebar.willShow", recomputes: false)
                sidebarClearWaits = transitionID
                animator.addAnimations { [weak self] in
                    #if DEBUG && MAIN_APP
                    self?.logSidebar("animations", transitionID, [])
                    #endif
                    self?.clearBesideSidebar(transitionID, reason: "sidebar.animator")
                }
                DispatchQueue.main.async { [weak self] in
                    self?.clearBesideSidebar(transitionID, reason: "sidebar.nextTurn")
                }
            }
            animator.addAnimations { [weak self] in self?.measureLayout() }
            animator.addCompletion { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.sidebarTransitionID == transitionID else { return }
                    self.controller?.view.layoutIfNeeded()
                    self.measureLayout()
                    self.deliverMetrics()
                    self.sidebarTransitionInProgress = false
                    self.measureLayout()
                    // An opened overlay (portrait) is not a choice.
                    if self.revealedByPerson, let controller = self.controller, !controller.sidebar.isHidden,
                       self.sidebarBesideContentSize == controller.view.bounds.size {
                        self.saveSidebarChoice(hidden: false)
                    }
                    self.revealedByPerson = false
                    #if DEBUG && MAIN_APP
                    self.logSidebar("completion", transitionID, [
                        ("afterMs", String(Int((CACurrentMediaTime() - started) * 1000))),
                    ])
                    #endif
                    // A show whose animator never ran still takes the bar away.
                    self.clearBesideSidebar(transitionID, reason: "sidebar.completed")
                    // The record follows where the sidebar ended, so a hide's
                    // set comes here, at its completion.
                    self.seedSidebarRecord(reason: "sidebar.completed")
                    self.scheduleSidebarCopy()
                }
            }
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

        private func layoutDidChange() {
            measureLayout()
            #if DEBUG && MAIN_APP
            // Only logs.
            accessory.logFrame()
            #endif
        }

        private func measureLayout() {
            guard let controller, controller.isViewLoaded,
                  let host = hosts[selectedRoot], host.isViewLoaded,
                  let window = host.view.window else { return }
            let bounds = host.view.bounds
            let physicalFrame = host.view.convert(window.safeAreaLayoutGuide.layoutFrame, from: window)
            let physicalLeft = max(0, physicalFrame.minX - bounds.minX)
            let physicalRight = max(0, bounds.maxX - physicalFrame.maxX)
            let physicalTop = max(0, physicalFrame.minY - bounds.minY)
            let physicalBottom = max(0, bounds.maxY - physicalFrame.maxY)
            let rightToLeft = host.view.effectiveUserInterfaceLayoutDirection == .rightToLeft
            let hostInsets = host.view.safeAreaInsets
            let available = isSidebarAvailable
            let visible = available && !controller.sidebar.isHidden
            if visible && !controller.isTabBarHidden && !sidebarTransitionInProgress {
                // Beside content, the host's leading inset makes room for it;
                // an overlay leaves only the window's own edge.
                let leading = rightToLeft ? hostInsets.right - physicalRight : hostInsets.left - physicalLeft
                let size = controller.view.bounds.size
                if leading > 0.5 { sidebarBesideContentSize = size }
                else if sidebarBesideContentSize == size { sidebarBesideContentSize = nil }
            }
            let key = IPadHostBaselineKey(root: selectedRoot, width: bounds.width, height: bounds.height,
                physicalLeft: physicalLeft, physicalRight: physicalRight, rightToLeft: rightToLeft)
            func logical(_ insets: UIEdgeInsets) -> EdgeInsets {
                EdgeInsets(top: insets.top, leading: rightToLeft ? insets.right : insets.left,
                           bottom: insets.bottom, trailing: rightToLeft ? insets.left : insets.right)
            }
            let revealing = !visible && controller.isTabBarHidden
                && AppSidebarInsets.revealsHiddenDrawer(
                    current: logical(hostInsets), closed: hiddenHostBaselines[key].map(logical),
                    physicalTop: physicalTop, physicalBottom: physicalBottom)
            let occluded = visible || revealing
            let samplesBaseline = !occluded && !sidebarTransitionInProgress
            if samplesBaseline { hiddenHostBaselines[key] = hostInsets }
            #if DEBUG && MAIN_APP
            logBaseline(hostInsets, recorded: samplesBaseline, revealing: revealing)
            #endif
            // Rotation may introduce a new baseline while the drawer is open.
            // With hidden tabs, this outer host reserves only physical vertical
            // edges when closed; the child navigation stack owns its header.
            // Use those edges until a closed sample exists for the new size.
            // Other screens retain their own native chrome as the fallback.
            let fallbackInsets = controller.isTabBarHidden
                ? UIEdgeInsets(top: physicalTop, left: hostInsets.left,
                               bottom: physicalBottom, right: hostInsets.right)
                : hostInsets
            let closedInsets = hiddenHostBaselines[key] ?? fallbackInsets
            pendingMetrics = IPadTabMetrics(
                sidebarAvailable: available, sidebarVisible: visible,
                insets: AppSidebarInsets(
                    current: logical(hostInsets), closed: logical(closedInsets),
                    physical: AppSidebarInsets.horizontal(left: physicalLeft, right: physicalRight,
                                                          rightToLeft: rightToLeft),
                    sidebarVisible: occluded))
            if !metricsDeliveryScheduled {
                metricsDeliveryScheduled = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.metricsDeliveryScheduled = false
                    self.deliverMetrics()
                }
            }
        }

        private func deliverMetrics() {
            guard let latest = pendingMetrics, latest != deliveredMetrics else { return }
            deliveredMetrics = latest
            for context in contexts.values { context.update(latest) }
        }

        /// A screen's own toggle, the person's choice.
        private func toggleSidebar() {
            guard let controller, regularWidth, controller.mode != .tabBar else { return }
            sidebarChangeStartedTransition = false
            controller.sidebar.isHidden.toggle()
            sidebarChangedWithoutTransition()
        }

        /// Shows or hides the tab bar as the selected tab asks, in
        /// `ActivityAccessoryOrder`'s order: a hide records hidden and clears
        /// the accessory, then drops the closed baselines and calls
        /// setTabBarHidden(true); a show calls setTabBarHidden(false), closes
        /// the sidebar and restores the person's choice, then records shown
        /// and recomputes, which sets the accessory only once the sidebar
        /// record says hidden. The tab bar changes only where UIKit's differs
        /// from the request, and every call recomputes.
        private func applyTabBarVisibility() {
            guard let controller else { return }
            guard !tabBarChangeInProgress else {
                // Asked inside setTabBarHidden's own layout: the record holds
                // until the call returns, and the request is applied then.
                tabBarRequestWaits = true
                recomputeAccessory(reason: "tabs.duringChange")
                return
            }
            let hidden = contexts[selectedRoot]?.prefersTabBarHidden ?? false
            let requested: ActivityTabBarRecord = hidden ? .hidden : .shown
            let from = controller.isTabBarHidden == hidden ? requestedTabBar : (hidden ? .shown : .hidden)
            let reason = from == requested ? "tabs" : hidden ? "tabBar.hide" : "tabBar.show"
            for step in ActivityAccessoryOrder.tabBar(from: from, to: requested) {
                switch step {
                case .record(let record):
                    requestedTabBar = record
                case .recompute:
                    recomputeAccessory(reason: reason)
                case .clearWithoutAnimation:
                    accessory.clearWithoutAnimation(on: controller, reason: reason)
                case .changeTabBar(let hidden):
                    guard controller.isTabBarHidden != hidden else { continue }
                    // Hide the tab bar before closing the sidebar. On iPadOS 27,
                    // closing an open sidebar first leaves the closed host with
                    // the drawer's bottom inset, which shrinks the game's board.
                    // The accessory's clear lays out once with the tab bar still
                    // shown; its baseline goes here.
                    hiddenHostBaselines.removeAll()
                    tabBarChangeInProgress = true
                    controller.setTabBarHidden(hidden, animated: controller.view.window != nil)
                    tabBarChangeInProgress = false
                    // UIKit animates a sidebar change as a morph with the
                    // floating tab bar. In a turn or a resize that bar can
                    // still be outside the window just after the tab bar comes
                    // back, and a morph from a view outside a window stops the
                    // app, so there the sidebar changes without animation.
                    let closeSidebar = {
                        self.setSidebarHidden(true)
                        self.restoreSidebarChoice()
                    }
                    if controller.isTransitioningSize {
                        UIView.performWithoutAnimation(closeSidebar)
                    } else {
                        closeSidebar()
                    }
                }
            }
            if tabBarRequestWaits {
                tabBarRequestWaits = false
                applyTabBarVisibility()
            }
        }

        private func horizontalSizeClassDidChange(_ regular: Bool) {
            hiddenHostBaselines.removeAll()
            applyTabs(regularWidth: regular)
            scheduleSidebarCopy()
            recomputeAccessory(reason: "sizeClass")
            // A popover from the Now section hangs from a sidebar the new
            // width may not have.
            DispatchQueue.main.async { [weak self] in
                self?.parent.closeNowSectionPopover()
                self?.readWindowForNowSection()
            }
        }

        // MARK: The Activity bar

        /// The sidebar as the accessory reads it.
        private var accessorySidebar: ActivityHostPolicy.Sidebar {
            !isSidebarAvailable ? .unavailable : isSidebarRecordShown ? .shown : .hidden
        }

        private var barTraits: ActivityBarTraits {
            ActivityBarTraits(bar: .uiKitAccessory, container: .iPadTabContainer, isCompactWidth: !regularWidth)
        }

        /// Sets UIKit's accessory where `ActivityBarHostState` says it shows,
        /// from the records, the registry's settled place for the selected
        /// tab and the window's bar state, and clears it otherwise. A call
        /// inside a layout reads the same records, so it gives the same
        /// answer. While a showing sidebar's animator is to take the bar
        /// away, nothing else does.
        private func recomputeAccessory(reason: String, animated: Bool? = nil) {
            guard let controller else { return }
            let facts = ActivityHostPolicy.Facts.current(.iPadTabContainer, sidebar: accessorySidebar)
            let overrides = ActivityBarHosting.overrides(afterLaunch: true)
            let placement = ActivityHostPolicy.hosts(for: facts, overrides: overrides).connectionStatus
            let content = ActivityBarHosting.content(parent.activityBar, placement: placement)
            var state = ActivityBarHostState(facts: facts, overrides: overrides)
            state.placeHidesBar = parent.activityPlaces.hidesActivity(in: selectedRoot)
            state.hasContent = content != nil
            state.requestedTabBar = requestedTabBar
            state.isInWindow = isInWindow
            state.isGameAskedFor = contexts[selectedRoot]?.isGameAskedFor ?? false
            state.isKeyboardOverWindow = isKeyboardOverWindow
            state.hasBottomTabBar = !regularWidth
            if sidebarClearWaits != nil, controller.hasActivityAccessory, state.shownBar != .uiKitAccessory {
                #if DEBUG && MAIN_APP
                NoticesHostProbeLog.event("bar.accessory", [
                    ("container", "iPadTabContainer"), ("action", "waits"), ("reason", reason),
                ])
                #endif
                return
            }
            accessory.apply(state, content: content, traits: barTraits,
                            isOffline: ActivityBarHosting.isOffline(parent.activityBar),
                            to: controller, animated: animated ?? (controller.view.window != nil), reason: reason)
        }

        /// The first set comes here, once the view is in a window.
        private func viewIsAppearing() {
            if !isInWindow {
                isInWindow = true
                // UIKit may restore the sidebar after the controller is made.
                seedSidebarRecord(reason: "isAppearing", recomputes: false)
            }
            readWindowForNowSection()
            recomputeAccessory(reason: "isAppearing")
        }

        /// After each turn or resize, a main-queue turn after its completion:
        /// the sidebar has settled, and the window may be shorter or taller.
        private func sizeTransitionCompleted() {
            seedSidebarRecord(reason: "transition", recomputes: false)
            scheduleSidebarCopy()
            readWindowForNowSection()
            recomputeAccessory(reason: "transition")
        }

        /// A tab's stack started or stopped showing a game on top. For the
        /// selected tab the bar clears at once, before the game's first
        /// layout. Nothing sets it again while that tab's top route shows a
        /// game, so a clear that lands inside a layout can't flip back; if
        /// the route goes before the tab bar hides, the bar comes back.
        private func gameAskedForDidChange(_ root: RootView) {
            let asked = contexts[root]?.isGameAskedFor ?? false
            #if DEBUG && MAIN_APP
            NoticesHostProbeLog.event("ipad.gameAskedFor", [
                ("root", root.rawValue), ("asked", NoticesHostProbeLog.flag(asked)),
                ("selected", selectedRoot.rawValue),
                ("accessory", NoticesHostProbeLog.flag(controller?.hasActivityAccessory == true)),
                ("tabBarHidden", NoticesHostProbeLog.flag(controller?.isTabBarHidden == true)),
            ])
            #endif
            guard root == selectedRoot else { return }
            recomputeAccessory(reason: asked ? "gameAskedFor" : "gameAskedFor.ended")
        }

        /// The bar goes beside a showing sidebar: inside its animator, with no
        /// animation of its own, or without one on the main queue's next turn
        /// where the animator hasn't run by then, or at its completion.
        private func clearBesideSidebar(_ transitionID: UUID, reason: String) {
            guard sidebarClearWaits == transitionID else { return }
            sidebarClearWaits = nil
            recomputeAccessory(reason: reason, animated: false)
        }

        private func setSidebarRecord(_ shown: Bool, reason: String, recomputes: Bool = true) {
            guard shown != isSidebarRecordShown else { return }
            isSidebarRecordShown = shown
            #if DEBUG && MAIN_APP
            NoticesHostProbeLog.event("bar.sidebar", [("phase", "record"), ("shown", NoticesHostProbeLog.flag(shown)),
                                                      ("reason", reason)])
            #endif
            scheduleSidebarCopy()
            if recomputes { recomputeAccessory(reason: reason) }
        }

        /// The sidebar as UIKit has it, read only while no sidebar
        /// transition runs: while one does, its own start and completion
        /// keep the record.
        private func seedSidebarRecord(reason: String, recomputes: Bool = true) {
            guard let controller, !sidebarTransitionInProgress else { return }
            setSidebarRecord(isSidebarAvailable && !controller.sidebar.isHidden, reason: reason,
                             recomputes: recomputes)
        }

        /// A change made here that started no transition: the record follows
        /// UIKit at once.
        private func sidebarChangedWithoutTransition() {
            guard let controller, !sidebarChangeStartedTransition else { return }
            setSidebarRecord(isSidebarAvailable && !controller.sidebar.isHidden, reason: "sidebar.set")
        }

        /// SwiftUI's copy of the sidebar, a main-queue turn after it changes,
        /// so nothing publishes inside the layout that changed it. As it
        /// turns from shown, a popover the Now section opened closes: it
        /// would point at nothing.
        private func scheduleSidebarCopy() {
            guard !sidebarCopyScheduled else { return }
            sidebarCopyScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.sidebarCopyScheduled = false
                let copy = self.accessorySidebar
                let wasShown = self.contexts.values.contains { $0.activitySidebar == .shown }
                for context in self.contexts.values { context.setActivitySidebar(copy) }
                #if DEBUG && MAIN_APP
                NoticesHostProbeLog.event("bar.sidebar", [("phase", "copy"), ("sidebar", copy.rawValue)],
                                          key: "bar.sidebar.copy")
                #endif
                if wasShown, copy != .shown { self.parent.closeNowSectionPopover() }
            }
        }

        private func keyboardDidChange(_ notification: Notification) {
            guard let window = controller?.view.window else { return }
            let end = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            let screen = window.windowScene?.screen.coordinateSpace
            let endInWindow = end.flatMap { frame in screen.map { window.convert(frame, from: $0) } } ?? .null
            let over = ActivityBarHostState.keyboardIsOverWindow(
                docked: SystemPlatformServices.shared.isAttachedSoftwareKeyboardVisible(from: notification),
                keyboardEnd: endInWindow, window: window.bounds)
            guard over != isKeyboardOverWindow else { return }
            isKeyboardOverWindow = over
            #if DEBUG && MAIN_APP
            NoticesHostProbeLog.event("bar.keyboard", [
                ("container", "iPadTabContainer"), ("overWindow", NoticesHostProbeLog.flag(over)),
                ("end", NoticesHostProbeLog.rect(endInWindow)), ("window", NoticesHostProbeLog.rect(window.bounds)),
            ])
            #endif
            recomputeAccessory(reason: "keyboard")
        }

        /// How many rows the Now section has room for, from the window
        /// scene's height, the text size and the language the sidebar is
        /// drawn in: as the window comes, after each turn or resize, and as
        /// the text size changes. Never the section's own geometry.
        private func readWindowForNowSection() {
            guard let controller, let scene = controller.view.window?.windowScene else { return }
            let height = scene.coordinateSpace.bounds.height
            let category = controller.traitCollection.preferredContentSizeCategory
            let language = ActivityNowSectionRows.Language.app
            let rows = ActivityNowSectionRows.count(windowHeight: height, sizeCategory: category, language: language)
            #if DEBUG && MAIN_APP
            NoticesHostProbeLog.event("now.rows", [
                ("rows", "\(rows)"), ("windowHeight", NoticesHostProbeLog.number(height)),
                ("textSize", category.rawValue), ("strings", language.strings), ("lines", language.lines),
            ], key: "now.rows")
            #endif
            parent.activityBar.setNowSectionRows(rows)
        }

        #if DEBUG && MAIN_APP
        // MARK: The Debug host log

        private func logSidebar(_ phase: String, _ transitionID: UUID, _ fields: [(String, String)]) {
            guard let controller else { return }
            NoticesHostProbeLog.event("ipad.sidebar", [
                ("phase", phase), ("transition", String(transitionID.uuidString.prefix(8))),
                ("isHidden", NoticesHostProbeLog.flag(controller.sidebar.isHidden)),
                ("record", NoticesHostProbeLog.flag(isSidebarRecordShown)),
                ("tabBarHidden", NoticesHostProbeLog.flag(controller.isTabBarHidden)),
                ("accessory", NoticesHostProbeLog.flag(controller.hasActivityAccessory)),
                ("app", NoticesHostProbeLog.flag(changingSidebar)),
                ("sizeTransition", NoticesHostProbeLog.flag(controller.isTransitioningSize)),
                ("root", selectedRoot.rawValue),
            ] + fields)
        }

        /// Keyboard focus moving into, within or out of the Now section, for a
        /// person's check with a hardware keyboard: the focused item's frame
        /// in the window. Only logs.
        private func observeNowSectionFocus() {
            nowSectionFocusObserver = NotificationCenter.default.addObserver(
                forName: UIFocusSystem.didUpdateNotification, object: nil, queue: .main
            ) { [weak self] notification in
                let context = notification.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext
                MainActor.assumeIsolated { self?.logNowSectionFocus(context) }
            }
        }

        private func logNowSectionFocus(_ context: UIFocusUpdateContext?) {
            guard let window = nowSection.view.window else { return }
            let section = nowSection.view.convert(nowSection.view.bounds, to: window)
            func frame(_ item: UIFocusItem?) -> CGRect? {
                guard let item else { return nil }
                if let view = item as? UIView { return view.convert(view.bounds, to: window) }
                guard let space = item.parentFocusEnvironment?.focusItemContainer?.coordinateSpace else { return nil }
                return space.convert(item.frame, to: window)
            }
            let next = frame(context?.nextFocusedItem), previous = frame(context?.previouslyFocusedItem)
            let inSection = { (rect: CGRect?) in rect.map { section.contains(CGPoint(x: $0.midX, y: $0.midY)) } ?? false }
            guard inSection(next) || inSection(previous) else { return }
            NoticesHostProbeLog.event("now.focus", [
                ("next", NoticesHostProbeLog.rect(next)), ("nextInSection", NoticesHostProbeLog.flag(inSection(next))),
                ("previous", NoticesHostProbeLog.rect(previous)), ("section", NoticesHostProbeLog.rect(section)),
            ])
        }

        /// The closed-baseline sampling, as measureLayout does it.
        private func logBaseline(_ insets: UIEdgeInsets, recorded: Bool, revealing: Bool) {
            guard let controller else { return }
            let number = NoticesHostProbeLog.number
            let flag = NoticesHostProbeLog.flag
            NoticesHostProbeLog.event("ipad.baseline", [
                ("root", selectedRoot.rawValue),
                ("insets", [insets.top, insets.left, insets.bottom, insets.right].map(number).joined(separator: ",")),
                ("recorded", flag(recorded)), ("revealing", flag(revealing)),
                ("tabBarHidden", flag(controller.isTabBarHidden)),
                ("accessory", flag(controller.hasActivityAccessory)),
            ], key: "ipad.baseline.\(selectedRoot.rawValue)")
        }
        #endif

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
    var onLayout: (() -> Void)?
    /// The view is in a window, with its traits, before its first layout.
    var onIsAppearing: (() -> Void)?
    /// A turn or a resize has finished, a main-queue turn after it.
    var onTransitionCompleted: (() -> Void)?
    /// The person's text size changed, inside trait propagation.
    var onTextSizeChange: (() -> Void)?
    /// A rotation or window resize, during which UIKit moves the sidebar
    /// itself.
    private(set) var isTransitioningSize = false

    override func viewDidLoad() {
        super.viewDidLoad()
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (controller: IPadTabBarController, _: UITraitCollection) in
            controller.onHorizontalSizeClassChange?(controller.traitCollection.horizontalSizeClass == .regular)
        }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (controller: IPadTabBarController, _: UITraitCollection) in
            controller.onTextSizeChange?()
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        onIsAppearing?()
    }

    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); onLayout?() }

    /// While a game hides the tab bar, a size transition must not open the
    /// sidebar. UIKit restores its own landscape visibility on rotation (the
    /// size class stays regular, so no trait change fires); close it again if
    /// it was closed before. A sidebar the person opened stays open.
    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        let keepsSidebarClosed = isTabBarHidden && sidebar.isHidden
        isTransitioningSize = true
        super.viewWillTransition(to: size, with: coordinator)
        let queued = coordinator.animate(alongsideTransition: { [weak self] _ in
            if keepsSidebarClosed { self?.closeSidebarIfReopened() }
        }) { [weak self] _ in
            if keepsSidebarClosed { self?.closeSidebarIfReopened() }
            // UIKit can apply its restored visibility after the completion.
            DispatchQueue.main.async { [weak self] in
                if keepsSidebarClosed { self?.closeSidebarIfReopened() }
                self?.isTransitioningSize = false
                self?.onTransitionCompleted?()
            }
        }
        // Not queued, the change happens as this returns: complete after it.
        if !queued { DispatchQueue.main.async { [weak self] in self?.onTransitionCompleted?() } }
    }

    private func closeSidebarIfReopened() {
        guard isTabBarHidden, !sidebar.isHidden else { return }
        sidebar.isHidden = true
    }
}

@available(iOS 18.0, *)
private final class IPadTabHostingController: UIHostingController<AnyView> {
    var onLayout: (() -> Void)?

    override func viewSafeAreaInsetsDidChange() { super.viewSafeAreaInsetsDidChange(); onLayout?() }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); onLayout?() }
}
#endif
