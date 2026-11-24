//
//  NoticesHostProbe.swift
//  Surround
//
//  Debug-only placeholders for the in-app notices host probes, and the hosts'
//  log. The one placeholder left, connection status under root titles, says
//  PLACEHOLDER and logs what its host does with it, so a device run can
//  answer where connection status can live before the real line exists; it
//  stays off unless its --surround-notices-* launch flag is present
//  (TESTING.md). Activity's bar and the Now section, on iPad and the Mac,
//  are the real ones in every container, and log here.
//

#if DEBUG && MAIN_APP
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

private extension ActivityHostPolicy.Facts {
    /// Where the placeholders put status under a title: root screens from
    /// iOS 26, and every title on the Mac.
    var showsPlaceholderSubtitle: Bool {
        platform == .mac || container == .duoTabContainer || (sdkHasHostAPIs && release >= .iOS26_0)
    }
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

/// Game Detail's board, one key per screen instance, so each open logs the
/// board's first size and every later change: how a game opened beside the
/// Activity bar lays out. Only with `--surround-activity-hidden-log`.
struct NoticesProbeBoardMarker: UIViewRepresentable {
    static let logs = ProcessInfo.processInfo.arguments.contains(ActivityPlaceRegistry.logLaunchArgument)
    private static var instances = 0

    func makeUIView(context: Context) -> NoticesProbeMarker.MarkerView {
        Self.instances += 1
        return NoticesProbeMarker.MarkerView(event: "board", key: "board.\(Self.instances)")
    }

    func updateUIView(_ view: NoticesProbeMarker.MarkerView, context: Context) {}
}

// MARK: - Root screens

/// AppNavigationStack's root content: the root subtitle, and what the policy
/// decides for the root. Every container has its real bar
/// (ActivityBarHosts.swift, ActivityAccessoryHost.swift), which the force
/// flag reaches too. Plain content without a probe, in presented stacks and
/// in roots without tabs.
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
        @Environment(\.iPadTabContext) private var iPadTabContext
        @Environment(\.duoTabContext) private var duoTabContext

        func body(content: Content) -> some View {
            content.modifier(Hosted(probe: probe, root: root, facts: facts))
        }

        /// The container's state: on iPad the sidebar's observable copy, as
        /// the real chrome reads it; never geometry.
        private var facts: ActivityHostPolicy.Facts {
            if let iPadTabContext {
                return .current(.iPadTabContainer, sidebar: iPadTabContext.activitySidebar)
            }
            return .current(duoTabContext == nil ? .swiftUITabView : .duoTabContainer)
        }
    }

    private struct Hosted: ViewModifier {
        let probe: SurroundUITestContract.NoticesHostProbe
        let root: RootView
        let facts: ActivityHostPolicy.Facts

        func body(content: Content) -> some View {
            let hosts = ActivityHostPolicy.hosts(for: facts, overrides: .init(probe, afterLaunch: true))
            let subtitled = probe.subtitle != nil && facts.showsPlaceholderSubtitle
            content
                .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { insets in
                    NoticesHostProbeLog.event("root.layout", [
                        ("root", root.rawValue), ("top", NoticesHostProbeLog.number(insets.top)),
                        ("bottom", NoticesHostProbeLog.number(insets.bottom)),
                    ], key: "root.layout.\(root.rawValue)")
                }
                .modifier(NoticesProbeSubtitle(variant: subtitled ? probe.subtitle : nil, root: root.rawValue,
                                               neverMinimizes: probe.navigationBarMinimize == .never))
                .onChange(of: hosts, initial: true) { _, hosts in
                    NoticesHostProbeLog.event("host.decision",
                                              NoticesHostProbeLog.fields(facts, hosts) + [("root", root.rawValue)],
                                              key: "decision.root.\(root.rawValue)")
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
           ActivityHostPolicy.Facts.current(.swiftUITabView).showsPlaceholderSubtitle {
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
                .placeholderNavigationSubtitle(statusShown ? Text(verbatim: "PLACEHOLDER · Reconnecting…") : nil)
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

private extension View {
    /// The placeholder's navigation subtitle: from iOS 26, and on the Mac,
    /// where SwiftUI draws none. Nil sets an empty subtitle instead of
    /// removing it, so one that comes and goes keeps its identity.
    @ViewBuilder
    func placeholderNavigationSubtitle(_ subtitle: Text?) -> some View {
        #if targetEnvironment(macCatalyst)
        navigationSubtitle(subtitle ?? Text(verbatim: ""))
        #elseif os(iOS) && canImport(SwiftUI, _version: 7.2.5)
        if #available(iOS 26.0, *) { navigationSubtitle(subtitle ?? Text(verbatim: "")) } else { self }
        #else
        self
        #endif
    }
}

#endif
