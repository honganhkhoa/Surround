//
//  NoticesHostProbe.swift
//  Surround
//
//  Debug-only placeholders for the in-app notices host probes. Each one is
//  dashed magenta, says PLACEHOLDER and logs what its host does with it, so a
//  device run can answer where Activity's bar, its Now section and connection
//  status can live before the real views exist. Every placeholder stays off
//  unless its --surround-notices-* launch flag is present (TESTING.md).
//

#if DEBUG && MAIN_APP
import Combine
import OSLog
import SwiftUI
import UIKit

private typealias NoticesProbeID = SurroundUITestContract.NoticesHostProbe.AccessibilityID

// MARK: - Log

/// Lines like `[NoticesHostProbe] seq=12 event=bar.frame key=… window=0,739,402,48 …`,
/// under subsystem com.honganhkhoa.Surround, category NoticesHostProbe.
enum NoticesHostProbeLog {
    private final class Output: @unchecked Sendable {
        let lock = NSLock()
        let logger = Logger(subsystem: "com.honganhkhoa.Surround", category: "NoticesHostProbe")
        var sequence = 0
        var lastPayloads = [String: String]()
    }

    private static let output = Output()

    /// Logs one event. A keyed line equal to the last one for its key is
    /// dropped, so layout passes don't flood the log.
    static func event(_ name: String, _ fields: [(String, String)] = [], key: String? = nil) {
        let payload = ([("event", name)] + fields).map { "\($0.0)=\($0.1)" }.joined(separator: " ")
        output.lock.lock()
        defer { output.lock.unlock() }
        if let key {
            guard output.lastPayloads[key] != payload else { return }
            output.lastPayloads[key] = payload
        }
        output.sequence += 1
        let line = "[NoticesHostProbe] seq=\(output.sequence) \(payload)"
        output.logger.notice("\(line, privacy: .public)")
    }

    /// `x,y,w,h` in points, or `none`.
    static func rect(_ rect: CGRect?) -> String {
        guard let rect, !rect.isNull else { return "none" }
        return [rect.minX, rect.minY, rect.width, rect.height].map { number($0) }.joined(separator: ",")
    }

    static func number(_ value: CGFloat) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", Double(value))
    }

    static func flag(_ value: Bool) -> String { value ? "1" : "0" }

    static func fields(_ facts: ActivityHostPolicy.Facts,
                       _ hosts: ActivityHostPolicy.Hosts) -> [(String, String)] {
        [("container", facts.container.rawValue), ("platform", facts.platform.rawValue),
         ("release", "\(facts.release)"), ("sdk", flag(facts.sdkHasHostAPIs)),
         ("sidebar", facts.sidebar.rawValue), ("bar", hosts.bar?.rawValue ?? "none"),
         ("now", hosts.nowSection?.rawValue ?? "none"), ("connection", hosts.connectionStatus.rawValue),
         ("minimize", hosts.minimize?.rawValue ?? "untouched")]
    }
}

private extension ActivityHostPolicy.ConnectionStatus {
    /// Status under a title: root screens' subtitle, or the Mac's window subtitle.
    var isSubtitle: Bool { self == .rootSubtitle || self == .windowSubtitle }
}

// MARK: - Marker

/// Goes in `.background` behind every placeholder and logs `<event>.frame`
/// in window coordinates, which SwiftUI's `.global` space doesn't reach from
/// accessories and sidebar bars. It only logs, so it is safe in any layout pass.
struct NoticesProbeMarker: UIViewRepresentable {
    let event: String
    let key: String

    func makeUIView(context: Context) -> MarkerView { MarkerView(event: event, key: key) }

    func updateUIView(_ view: MarkerView, context: Context) {
        view.update(event: event, key: key)
    }

    final class MarkerView: UIView {
        private var event: String
        private var key: String

        init(event: String, key: String) {
            self.event = event
            self.key = key
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            registerForActivityAccessoryEnvironmentChanges { $0.setNeedsLayout() }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func update(event: String, key: String) {
            guard event != self.event || key != self.key else { return }
            self.event = event
            self.key = key
            // SwiftUI applies the new frame after this update, so the next
            // layout pass logs; logging here would put the old frame under the new key.
            setNeedsLayout()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            log()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            log()
        }

        private func log() {
            let divisions = activityDivisionFrames
            let windowDivisions = window.map { window in divisions.map { convert($0, to: window) } } ?? []
            NoticesHostProbeLog.event("\(event).frame", [
                ("key", key),
                ("window", NoticesHostProbeLog.rect(window.map { convert(bounds, to: $0) })),
                ("uikit", activityAccessoryEnvironment.rawValue),
                ("divisions", windowDivisions.map { NoticesHostProbeLog.rect($0) }.joined(separator: ";")),
                ("crossesDivision", NoticesHostProbeLog.flag(divisions.contains { $0.intersects(bounds) })),
                ("textSize", traitCollection.preferredContentSizeCategory.rawValue),
            ], key: key)
        }
    }
}

private struct NoticesPlaceholderOutline: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(red: 1, green: 0, blue: 1), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Bar

/// Activity's bar, in whichever host shows it: SwiftUI's accessory, UIKit's
/// accessory or the custom bar.
struct NoticesPlaceholderBar: View {
    private enum Presentation: String { case sheet, popover }

    let host: ActivityHostPolicy.Bar
    let root: RootView?
    var connection: ActivityHostPolicy.ConnectionStatus? = nil

    @State private var placement = ActivityHostPolicy.AccessoryPlacement.unavailable
    @State private var showsSheet = false
    @State private var showsPopover = false

    private var rootName: String { root?.rawValue ?? "window" }

    private var secondLine: String {
        (connection == .customBar ? "Reconnecting… · " : "") + "placement \(placement.rawValue)"
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "PLACEHOLDER · \(host.rawValue)")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .accessibilityIdentifier(NoticesProbeID.barLine1)
                Text(verbatim: secondLine)
                    .font(.caption2)
                    .lineLimit(1)
                    .accessibilityIdentifier(NoticesProbeID.barLine2)
            }
            Spacer(minLength: 4)
            Button { open(.sheet) } label: { Text(verbatim: "Sheet") }
                .accessibilityIdentifier(NoticesProbeID.barSheet)
            Button { open(.popover) } label: { Text(verbatim: "Popover") }
                .accessibilityIdentifier(NoticesProbeID.barPopover)
                .popover(isPresented: $showsPopover) { presented(.popover) }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 44)
        .modifier(NoticesPlaceholderOutline())
        .background(NoticesProbeMarker(event: "bar", key: "bar.\(host.rawValue).\(rootName)"))
        .sheet(isPresented: $showsSheet) { presented(.sheet) }
        .onActivityAccessoryPlacementChange { placement = $0 }
        .onChange(of: placement, initial: true) { _, placement in
            NoticesHostProbeLog.event("bar.placement", [
                ("host", host.rawValue), ("root", rootName), ("swiftui", placement.rawValue),
            ], key: "bar.placement.\(host.rawValue).\(rootName)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(NoticesProbeID.bar)
        .accessibilityValue(Text(verbatim: "host=\(host.rawValue);root=\(rootName);swiftui=\(placement.rawValue)"))
    }

    private func open(_ presentation: Presentation) {
        NoticesHostProbeLog.event("bar.tap", [
            ("host", host.rawValue), ("root", rootName), ("kind", presentation.rawValue),
        ])
        switch presentation {
        case .sheet: showsSheet = true
        case .popover: showsPopover = true
        }
    }

    private func presented(_ presentation: Presentation) -> some View {
        Text(verbatim: "PLACEHOLDER · \(presentation.rawValue) from \(host.rawValue)")
            .padding(24)
            .accessibilityIdentifier(NoticesProbeID.barPresented)
            .onAppear {
                NoticesHostProbeLog.event("bar.presented", [
                    ("host", host.rawValue), ("kind", presentation.rawValue),
                ])
            }
    }
}

// MARK: - Now

/// The iPad or Mac sidebar's Now section: a status row with Retry, rows that
/// grow and shrink, and an All activity popover.
struct NoticesPlaceholderNow: View {
    let host: ActivityHostPolicy.NowSection
    var onReassign: (() -> Void)? = nil

    @State private var rows = 2
    @State private var showsAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(verbatim: "PLACEHOLDER · Can’t reach OGS")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button { tap("retry") } label: { Text(verbatim: "Retry") }
                    .accessibilityIdentifier(NoticesProbeID.nowRetry)
            }
            ForEach(Array(stride(from: 1, through: rows, by: 1)), id: \.self) { row in
                Button { tap("row.\(row)") } label: {
                    Text(verbatim: "Now row \(row)").frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier(NoticesProbeID.nowRow(row))
            }
            HStack(spacing: 12) {
                Button {
                    rows += 1
                    tap("add")
                } label: { Text(verbatim: "Add") }
                    .accessibilityIdentifier(NoticesProbeID.nowAdd)
                Button {
                    rows = max(0, rows - 1)
                    tap("remove")
                } label: { Text(verbatim: "Remove") }
                    .accessibilityIdentifier(NoticesProbeID.nowRemove)
                if let onReassign {
                    Button {
                        tap("reassign")
                        onReassign()
                    } label: { Text(verbatim: "Reassign") }
                        .accessibilityIdentifier(NoticesProbeID.nowReassign)
                }
            }
            Button {
                tap("all")
                showsAll = true
            } label: { Text(verbatim: "All activity") }
                .accessibilityIdentifier(NoticesProbeID.nowAll)
                .popover(isPresented: $showsAll) {
                    Text(verbatim: "PLACEHOLDER · All activity from \(host.rawValue)")
                        .padding(24)
                        .accessibilityIdentifier(NoticesProbeID.nowAllContent)
                        .onAppear { NoticesHostProbeLog.event("now.presented", [("host", host.rawValue)]) }
                }
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(10)
        .modifier(NoticesPlaceholderOutline())
        .background(NoticesProbeMarker(event: "now", key: "now.\(host.rawValue).\(rows)"))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(NoticesProbeID.now)
    }

    private func tap(_ target: String) {
        NoticesHostProbeLog.event("now.tap", [("host", host.rawValue), ("target", target), ("rows", "\(rows)")])
    }
}

// MARK: - SwiftUI TabView

/// MainView.swiftUITabs: SwiftUI's bottom accessory, the tab bar's minimize
/// behavior and the Mac sidebar's Now section.
struct NoticesHostProbeTabs: ViewModifier {
    let places: ActivityPlaceRegistry
    let root: RootView

    func body(content: Content) -> some View {
        if let probe = SurroundUITestContract.noticesHostProbe {
            content.modifier(Probed(probe: probe, places: places, root: root))
        } else {
            content
        }
    }

    private struct Probed: ViewModifier {
        let probe: SurroundUITestContract.NoticesHostProbe
        @ObservedObject var places: ActivityPlaceRegistry
        let root: RootView
        @State private var afterLaunch = false

        func body(content: Content) -> some View {
            let facts = ActivityHostPolicy.Facts.current(.swiftUITabView)
            let hosts = ActivityHostPolicy.hosts(for: facts, overrides: .init(probe, afterLaunch: afterLaunch))
            let isEnabled = probe.showsBar && hosts.bar == .swiftUIAccessory && !places.hidesActivity(in: root)
            content
                .activityBottomAccessory(isEnabled: isEnabled) {
                    NoticesPlaceholderBar(host: .swiftUIAccessory, root: nil)
                }
                .activityTabBarMinimizeBehavior(hosts.minimize)
                .modifier(MacNow(shows: probe.showsNow))
                .onChange(of: isEnabled, initial: true) { _, isEnabled in
                    NoticesHostProbeLog.event("bar.accessory", [
                        ("container", ActivityHostPolicy.Container.swiftUITabView.rawValue),
                        ("action", isEnabled ? "set" : "cleared"), ("reason", "state"), ("root", root.rawValue),
                    ])
                }
                .onChange(of: hosts, initial: true) { _, hosts in
                    NoticesHostProbeLog.event("host.decision", NoticesHostProbeLog.fields(facts, hosts),
                                              key: "decision.swiftUITabView")
                }
                .onAppear { DispatchQueue.main.async { afterLaunch = true } }
        }
    }

    /// Branches on a launch constant, so the TabView keeps its identity.
    private struct MacNow: ViewModifier {
        let shows: Bool

        func body(content: Content) -> some View {
            if shows {
                content.activityMacSidebarBottomBar { NoticesPlaceholderNow(host: .macSidebar) }
            } else {
                content
            }
        }
    }
}

// MARK: - Root screens

/// AppNavigationStack's root content: the custom bar and the root subtitle.
/// Plain content without a probe, in presented stacks and in roots without
/// tabs.
struct NoticesHostProbeRoot: ViewModifier {
    let rootView: RootView?

    func body(content: Content) -> some View {
        if let probe = SurroundUITestContract.noticesHostProbe, let rootView {
            content.modifier(Probed(probe: probe, root: rootView))
        } else {
            content
        }
    }

    private struct Probed: ViewModifier {
        let probe: SurroundUITestContract.NoticesHostProbe
        let root: RootView
        @EnvironmentObject private var nav: NavigationService
        @Environment(\.iPadTabContext) private var iPadTabContext
        @Environment(\.duoTabContext) private var duoTabContext

        func body(content: Content) -> some View {
            content.modifier(Hosted(probe: probe, root: root, places: nav.activityPlaces, facts: facts))
        }

        /// The container's state, which it delivers after layout; never geometry.
        private var facts: ActivityHostPolicy.Facts {
            if let iPadTabContext {
                let sidebar: ActivityHostPolicy.Sidebar = !iPadTabContext.sidebarAvailable ? .unavailable
                    : iPadTabContext.sidebarVisible ? .shown : .hidden
                return .current(.iPadTabContainer, sidebar: sidebar)
            }
            return .current(duoTabContext == nil ? .swiftUITabView : .duoTabContainer)
        }
    }

    private struct Hosted: ViewModifier {
        let probe: SurroundUITestContract.NoticesHostProbe
        let root: RootView
        @ObservedObject var places: ActivityPlaceRegistry
        let facts: ActivityHostPolicy.Facts
        @State private var keyboardShows = false

        private static let keyboardChanges = SystemPlatformServices.shared.keyboardWillChangeFramePublisher

        func body(content: Content) -> some View {
            let hosts = ActivityHostPolicy.hosts(for: facts, overrides: .init(probe, afterLaunch: true))
            let shows = probe.showsBar && hosts.bar == .customBar && !places.hidesActivity(in: root)
                && !(probe.barKeyboard == .hide && keyboardShows)
            let subtitled = probe.subtitle != nil && hosts.connectionStatus.isSubtitle
            content
                .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { insets in
                    NoticesHostProbeLog.event("root.layout", [
                        ("root", root.rawValue), ("top", NoticesHostProbeLog.number(insets.top)),
                        ("bottom", NoticesHostProbeLog.number(insets.bottom)),
                    ], key: "root.layout.\(root.rawValue)")
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if shows {
                        NoticesPlaceholderBar(host: .customBar, root: root, connection: hosts.connectionStatus)
                    }
                }
                .modifier(NoticesProbeSubtitle(variant: subtitled ? probe.subtitle : nil, root: root.rawValue,
                                               neverMinimizes: probe.navigationBarMinimize == .never))
                .modifier(IgnoresKeyboard(ignores: probe.showsBar && probe.barKeyboard == .ignore))
                .onReceive(Self.keyboardChanges) { notification in
                    guard probe.showsBar else { return }
                    let visible = SystemPlatformServices.shared.isAttachedSoftwareKeyboardVisible(from: notification)
                    guard visible != keyboardShows else { return }
                    keyboardShows = visible
                    NoticesHostProbeLog.event("bar.keyboard", [
                        ("root", root.rawValue), ("visible", NoticesHostProbeLog.flag(visible)),
                        ("variant", probe.barKeyboard.rawValue),
                    ])
                }
                .onChange(of: shows, initial: true) { _, shows in
                    NoticesHostProbeLog.event("bar.custom", [
                        ("root", root.rawValue), ("shown", NoticesHostProbeLog.flag(shows)),
                    ])
                }
                .onChange(of: hosts, initial: true) { _, hosts in
                    NoticesHostProbeLog.event("host.decision",
                                              NoticesHostProbeLog.fields(facts, hosts) + [("root", root.rawValue)],
                                              key: "decision.root.\(root.rawValue)")
                }
        }
    }

    /// A launch constant, so the root keeps its identity.
    private struct IgnoresKeyboard: ViewModifier {
        let ignores: Bool

        func body(content: Content) -> some View {
            if ignores {
                content.ignoresSafeArea(.keyboard, edges: .bottom)
            } else {
                content
            }
        }
    }
}

/// The Mac's pushed screens: the window subtitle follows the top screen, so
/// they carry the same placeholder subtitle and Retry item as the roots.
struct NoticesHostProbeDestination: ViewModifier {
    @Environment(\.owningTabRoot) private var owningTabRoot

    func body(content: Content) -> some View {
        if let probe = SurroundUITestContract.noticesHostProbe, let variant = probe.subtitle,
           ActivityHostPolicy.hosts(for: .current(.swiftUITabView)).connectionStatus.isSubtitle {
            content.modifier(NoticesProbeSubtitle(variant: variant,
                                                  root: "\(owningTabRoot?.rawValue ?? "window").destination",
                                                  neverMinimizes: probe.navigationBarMinimize == .never))
        } else {
            content
        }
    }
}

/// The placeholder connection status under a title: "Reconnecting…" as the
/// subtitle, "Can’t reach OGS" with Retry as subtitle toolbar items, or the
/// status coming and going every 4 s. Plain content without a variant.
private struct NoticesProbeSubtitle: ViewModifier {
    let variant: SurroundUITestContract.NoticesHostProbe.Subtitle?
    let root: String
    let neverMinimizes: Bool

    func body(content: Content) -> some View {
        if let variant {
            content.modifier(Shown(variant: variant, root: root, neverMinimizes: neverMinimizes))
        } else {
            content
        }
    }

    private struct Shown: ViewModifier {
        let variant: SurroundUITestContract.NoticesHostProbe.Subtitle
        let root: String
        let neverMinimizes: Bool
        @State private var cycleOn = true

        func body(content: Content) -> some View {
            let statusShown = variant == .status || (variant == .cycle && cycleOn)
            content
                .activityNavigationSubtitle(statusShown ? Text(verbatim: "PLACEHOLDER · Reconnecting…") : nil)
                .activitySubtitleItem(isPresent: variant == .retry) { retryItem(largeTitle: false) }
                .activitySubtitleItem(largeTitle: true, isPresent: variant == .retry) { retryItem(largeTitle: true) }
                .activityNavigationBarNeverMinimizes(neverMinimizes)
                .task {
                    guard variant == .cycle else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(4))
                        guard !Task.isCancelled else { return }
                        cycleOn.toggle()
                        NoticesHostProbeLog.event("subtitle.state", [
                            ("root", root), ("text", cycleOn ? "status" : "empty"),
                        ])
                    }
                }
        }

        private func retryItem(largeTitle: Bool) -> some View {
            let placement = largeTitle ? "largeSubtitle" : "subtitle"
            return HStack(spacing: 6) {
                Text(verbatim: "PLACEHOLDER · Can’t reach OGS").lineLimit(1)
                Button {
                    NoticesHostProbeLog.event("subtitle.retry", [("root", root), ("placement", placement)])
                } label: { Text(verbatim: "Retry") }
                    .accessibilityIdentifier(largeTitle ? NoticesProbeID.subtitleLargeRetry
                                                        : NoticesProbeID.subtitleRetry)
            }
            .font(.caption)
            .background(NoticesProbeMarker(event: "subtitle", key: "subtitle.\(placement).\(root)"))
        }
    }
}

// MARK: - UIKit containers

#if !targetEnvironment(macCatalyst)
/// UIKit's bottom accessory content: a hosted placeholder bar. Deliberately
/// not a child controller, so a device run shows whether content hosted this
/// way still presents and still receives its placement.
final class NoticesPlaceholderAccessoryView: UIView {
    private let host = UIHostingController(rootView: NoticesPlaceholderBar(host: .uiKitAccessory, root: nil))

    init() {
        super.init(frame: .zero)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Owned by DuoTabContainer's and IPadTabContainer's coordinators: sets and
/// clears the UIKit accessory, applies the Duo's minimize behavior and puts
/// the Now section in the iPad sidebar's bottom bar. It decides from state
/// (the tab bar request, the registry's settled state, a settled sidebar
/// transition), never from geometry.
@MainActor
final class NoticesHostProbeUIKit {
    struct State {
        var root: RootView
        var tabBarHidden: Bool
        var sidebar: ActivityHostPolicy.Sidebar
    }

    /// Nil unless a notices host flag is present.
    static func make(container: ActivityHostPolicy.Container,
                     places: ActivityPlaceRegistry?) -> NoticesHostProbeUIKit? {
        guard let probe = SurroundUITestContract.noticesHostProbe else { return nil }
        return NoticesHostProbeUIKit(probe: probe, container: container, places: places)
    }

    /// A deferred accessory change waits for the next main turn. Until then
    /// IPadTabContainer samples no closed baselines.
    private(set) var changePending = false

    private let probe: SurroundUITestContract.NoticesHostProbe
    private let container: ActivityHostPolicy.Container
    private let places: ActivityPlaceRegistry?
    private weak var controller: UITabBarController?
    private var state: (() -> State?)?
    private var subscription: AnyCancellable?
    private var nowHost: UIHostingController<NoticesPlaceholderNow>?
    private lazy var accessory = NoticesPlaceholderAccessoryView()
    private var afterLaunch = false
    private var afterLaunchScheduled = false

    private init(probe: SurroundUITestContract.NoticesHostProbe, container: ActivityHostPolicy.Container,
                 places: ActivityPlaceRegistry?) {
        self.probe = probe
        self.container = container
        self.places = places
    }

    func install(on controller: UITabBarController, state: @escaping () -> State?) {
        self.controller = controller
        self.state = state
        if container == .duoTabContainer { applyMinimize(phase: "install") }
        if container == .iPadTabContainer, probe.showsNow {
            let host = UIHostingController(rootView: NoticesPlaceholderNow(host: .iPadSidebar) { [weak self] in
                self?.reassignNow()
            })
            host.sizingOptions = .intrinsicContentSize
            host.view.backgroundColor = .clear
            controller.sidebar.bottomBarView = host.view
            nowHost = host
        }
        subscription = places?.stateDidChange.sink { [weak self] _ in self?.refresh(reason: "registry") }
        refresh(reason: "install")
    }

    /// Right before setTabBarHidden: the `before` order changes the accessory here.
    func tabBarWillChange(hidden: Bool) {
        guard probe.barOrder == .before else { return }
        apply(tabBarHidden: hidden, reason: "tabBarWillChange")
    }

    /// Right after setTabBarHidden: `after` changes the accessory here;
    /// `deferred` waits for the next main turn.
    func tabBarDidChange(hidden: Bool) {
        switch probe.barOrder {
        case .before:
            break
        case .after:
            apply(tabBarHidden: hidden, reason: "tabBarDidChange")
        case .deferred:
            changePending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.changePending = false
                self.refresh(reason: "deferred")
            }
        }
    }

    func refresh(reason: String) {
        guard !changePending, let state = state?() else { return }
        apply(tabBarHidden: state.tabBarHidden, reason: reason)
    }

    /// The Duo with on-scroll-down-after-launch: once the controller is in a
    /// window, switch to .onScrollDown a main turn later.
    func controllerDidLayout() {
        guard container == .duoTabContainer, probe.tabBarMinimize == .onScrollDownAfterLaunch,
              !afterLaunchScheduled, controller?.view.window != nil else { return }
        afterLaunchScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.afterLaunch = true
            self.applyMinimize(phase: "afterLaunch")
        }
    }

    /// IPadTabContainer's closed-baseline sampling, logged from measureLayout.
    /// It only logs.
    func baselineSample(root: RootView, insets: UIEdgeInsets, recorded: Bool, revealing: Bool,
                        tabBarHidden: Bool) {
        let number = NoticesHostProbeLog.number
        let flag = NoticesHostProbeLog.flag
        NoticesHostProbeLog.event("ipad.baseline", [
            ("root", root.rawValue),
            ("insets", [insets.top, insets.left, insets.bottom, insets.right].map(number).joined(separator: ",")),
            ("recorded", flag(recorded)), ("revealing", flag(revealing)), ("tabBarHidden", flag(tabBarHidden)),
            ("accessory", flag(controller?.hasActivityAccessory == true)), ("pending", flag(changePending)),
        ], key: "ipad.baseline.\(root.rawValue)")
    }

    private func applyMinimize(phase: String) {
        guard let controller else { return }
        let minimize = ActivityHostPolicy.hosts(for: .current(container),
                                                overrides: .init(probe, afterLaunch: afterLaunch)).minimize
        controller.setActivityMinimizeBehavior(minimize)
        NoticesHostProbeLog.event("minimize.applied", [
            ("container", container.rawValue), ("minimize", minimize?.rawValue ?? "untouched"), ("phase", phase),
        ])
    }

    private func apply(tabBarHidden: Bool, reason: String) {
        guard let controller, let state = state?() else { return }
        let facts = ActivityHostPolicy.Facts.current(container, sidebar: state.sidebar)
        let hosts = ActivityHostPolicy.hosts(for: facts, overrides: .init(probe, afterLaunch: afterLaunch))
        let hides = places?.hidesActivity(in: state.root) ?? false
        let wanted = probe.showsBar && hosts.bar == .uiKitAccessory && !tabBarHidden && !hides
        let had = controller.hasActivityAccessory
        controller.setActivityAccessory(wanted ? accessory : nil, animated: controller.view.window != nil)
        let action = wanted == had ? "kept" : wanted ? "set" : "cleared"
        let flag = NoticesHostProbeLog.flag
        NoticesHostProbeLog.event("bar.accessory", [
            ("container", container.rawValue), ("action", action), ("reason", reason),
            ("order", probe.barOrder.rawValue), ("tabBarHidden", flag(tabBarHidden)), ("hides", flag(hides)),
            ("root", state.root.rawValue), ("sidebar", state.sidebar.rawValue),
        ], key: action == "kept" ? "bar.accessory.kept.\(container.rawValue)" : nil)
        NoticesHostProbeLog.event("host.decision", NoticesHostProbeLog.fields(facts, hosts),
                                  key: "decision.\(container.rawValue)")
    }

    /// Reassigns the sidebar's bottom bar, for its resizing check.
    private func reassignNow() {
        guard let controller, let view = nowHost?.view else { return }
        controller.sidebar.bottomBarView = nil
        controller.sidebar.bottomBarView = view
    }
}
#endif
#endif
