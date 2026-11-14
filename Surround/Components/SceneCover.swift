//
//  SceneCover.swift
//  Surround
//
//  One overlay window per window scene, above alerts, that hides and blocks
//  everything else the scene shows while it is raised: sheets, popovers,
//  alerts, menus and system view controllers presented in the scene's own
//  windows. A SwiftUI view mounts it with `SceneCoverAnchor`; the caller
//  decides when it is raised and what it shows.
//
//  Ships with the moderator superchat cover; the inner DEBUG blocks stay
//  probe-only.
//

import SwiftUI
import UIKit

/// What a scene's cover tells the SwiftUI content it hosts.
final class SceneCoverContext: ObservableObject {
    @Published fileprivate(set) var isRaised = false
    /// Counts each rise, so content can move focus every time. A scene's
    /// first rise can land before its content first renders, so observe it
    /// with `onChange(of:initial: true)` and check `isRaised`.
    @Published fileprivate(set) var raiseCount = 0
    /// How far content keeps off its leading edge to clear a windowed iPad's
    /// window controls (iPadOS 26 and later); 0 elsewhere. It comes from the
    /// content window, which has had its corner insets since its scene's
    /// first layout. A cover window made later gets none until its window
    /// moves, and a corner offset doesn't reach into a scroll view.
    @Published fileprivate(set) var windowControlsLeading: CGFloat = 0
    #if DEBUG
    /// What the cover last rose over, for probes and logs.
    @Published fileprivate(set) var report: [String] = []
    #endif
    /// Set by the cover that owns this context, in its `init`.
    fileprivate var moveVoiceOver: @MainActor () -> Void = {}

    /// Points VoiceOver at the cover's focused element, such as the reply
    /// field the content just focused, or at its root view when nothing has
    /// focus. Content calls it after a rise its request answered `.content` for.
    @MainActor func moveVoiceOverToFocusedElement() {
        moveVoiceOver()
    }
}

/// Who moves VoiceOver when the cover rises.
enum SceneCoverVoiceOver {
    /// Another window is the one the user is in: post nothing.
    case none
    /// Post `.screenChanged` with the cover's root view: VoiceOver starts at the header.
    case coverRoot
    /// Post nothing at the rise: the content focuses a field and calls
    /// `SceneCoverContext.moveVoiceOverToFocusedElement()`.
    case content
}

/// The anchor's latest wish for its scene's cover.
struct SceneCoverRequest {
    var isRaised: Bool
    var options: SceneCoverOptions
    /// Read at each rise and lower, with the cover window's traits.
    var voiceOver: (UITraitCollection) -> SceneCoverVoiceOver
    /// Called last when the cover lowers: its window is hidden and the next
    /// key window is chosen.
    var didLower: () -> Void
    var content: AnyView
}

/// Mounts the scene's cover. Put it, at zero size, in the background of the
/// scene's root view; it never draws anything itself.
struct SceneCoverAnchor<Content: View>: UIViewRepresentable {
    var isRaised: Bool
    var options = SceneCoverOptions()
    /// By default VoiceOver starts at the cover's root view, and nothing
    /// runs after a lower.
    var voiceOver: (UITraitCollection) -> SceneCoverVoiceOver = { _ in .coverRoot }
    var didLower: () -> Void = {}
    @ViewBuilder var content: () -> Content

    func makeUIView(context: Context) -> SceneCoverAnchorView {
        SceneCoverAnchorView(frame: .zero)
    }

    func updateUIView(_ view: SceneCoverAnchorView, context: Context) {
        view.update(SceneCoverRequest(
            isRaised: isRaised, options: options, voiceOver: voiceOver, didLower: didLower,
            content: AnyView(content())
        ))
    }
}

final class SceneCoverAnchorView: UIView {
    private var request: SceneCoverRequest?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ request: SceneCoverRequest) {
        self.request = request
        deliver(attaching: false)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        deliver(attaching: true)
    }

    private func deliver(attaching: Bool) {
        // An anchor inside a cover's own content must not cover itself.
        guard let request, let window, !(window is SceneCoverWindow),
              let scene = window.windowScene else { return }
        SceneCover.cover(for: scene).receive(request, from: window, attaching: attaching)
    }
}

/// The cover's window. A lowered cover can never take key.
final class SceneCoverWindow: UIWindow {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
}

/// The cover window's root: reports each layout pass, so the window
/// controls' inset follows resizes and the scene's first layout.
private final class SceneCoverHostingController: UIHostingController<AnyView> {
    var didLayout: () -> Void = {}

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        didLayout()
    }
}

/// One per window scene. Owns the scene's cover window and applies the
/// latest request one run-loop turn after it arrives, so a window change
/// never runs inside a SwiftUI update or a UIKit layout pass such as
/// setTabBarHidden's (the forum-224 freeze).
@MainActor
final class SceneCover: NSObject {
    /// Above `.alert`. The software keyboard's windows sit higher still, so
    /// raising also ends editing underneath.
    static let level = UIWindow.Level.alert + 1

    private static var covers = [ObjectIdentifier: SceneCover]()

    /// The scene's cover, created on first use and dropped when the scene
    /// disconnects.
    static func cover(for scene: UIWindowScene) -> SceneCover {
        let key = ObjectIdentifier(scene)
        if let cover = covers[key], cover.scene === scene { return cover }
        let cover = SceneCover(scene: scene)
        covers[key] = cover
        return cover
    }

    let context = SceneCoverContext()
    private(set) var isRaised = false
    private weak var scene: UIWindowScene?
    private weak var contentWindow: UIWindow?
    private weak var keyWindowBeforeRaise: UIWindow?
    private var window: SceneCoverWindow?
    private var host: SceneCoverHostingController?
    private var request: SceneCoverRequest?
    private var contentChanged = false
    private var applyScheduled = false
    private var locked = [LockedWindow]()
    private var geometryObservation: NSKeyValueObservation?

    private struct LockedWindow {
        weak var window: UIWindow?
        let accessibilityHidden: Bool
        let interactionEnabled: Bool
    }

    private init(scene: UIWindowScene) {
        self.scene = scene
        super.init()
        context.moveVoiceOver = { [weak self] in self?.moveVoiceOverToFocusedElement() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(sceneDidDisconnect(_:)),
            name: UIScene.didDisconnectNotification, object: scene
        )
        // Stage Manager and Mac windows resize; keep the cover the content's size.
        geometryObservation = scene.observe(\.effectiveGeometry, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.matchContentFrame() }
        }
    }

    func receive(_ request: SceneCoverRequest, from contentWindow: UIWindow, attaching: Bool) {
        // The anchor delivers nothing before it has a window, so a scene's
        // first request is its attach.
        let isFirstRequest = self.request == nil
        self.request = request
        self.contentWindow = contentWindow
        contentChanged = true
        #if DEBUG
        if attaching {
            SceneCoverLog.record("NOTICES-COVER attach scene=\(Self.shortID(contentWindow.windowScene)) raised=\(request.isRaised)")
        }
        #endif
        if SceneCoverPolicy.raisesWhileAttaching(
            attaching: attaching, isFirstRequest: isFirstRequest, options: request.options,
            wantsRaised: request.isRaised, isRaised: isRaised
        ) {
            apply()
        } else {
            scheduleApply()
        }
    }

    private func scheduleApply() {
        guard !applyScheduled else { return }
        applyScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyScheduled = false
            self.apply()
        }
    }

    private func apply() {
        guard let scene, let request else { return }
        if request.isRaised, window == nil { makeWindow(in: scene) }
        if contentChanged, let host {
            host.rootView = AnyView(request.content.environmentObject(context))
            contentChanged = false
        }
        if request.isRaised, !isRaised {
            raise(in: scene, request: request)
        } else if !request.isRaised, isRaised {
            lower(in: scene, request: request)
        }
    }

    private func makeWindow(in scene: UIWindowScene) {
        let window = SceneCoverWindow(windowScene: scene)
        window.windowLevel = Self.level
        let host = SceneCoverHostingController(rootView: AnyView(EmptyView()))
        host.view.backgroundColor = .systemBackground
        // A layout pass follows each resize and the scene's first layout; the
        // inset is read a main turn later, outside the pass.
        host.didLayout = { [weak self] in
            DispatchQueue.main.async { self?.updateWindowControlsLeading() }
        }
        window.rootViewController = host
        self.window = window
        self.host = host
        contentChanged = true
    }

    private func raise(in scene: UIWindowScene, request: SceneCoverRequest) {
        guard let window, let host else { return }
        let options = request.options
        let below = Set(SceneCoverPolicy.windowsBelow(
            ObjectIdentifier(window), in: scene.windows.map { Self.policyWindow($0) },
            coverLevel: Self.level.rawValue
        ))
        keyWindowBeforeRaise = scene.keyWindow.flatMap { $0 === window ? nil : $0 }
        #if DEBUG
        var report = describe(scene, cover: window)
        #endif
        if options.endsEditingUnderneath {
            for other in scene.windows where below.contains(ObjectIdentifier(other)) {
                other.endEditing(true)
            }
        }
        if options.locksWindowsBelow {
            for other in scene.windows where below.contains(ObjectIdentifier(other)) {
                locked.append(LockedWindow(
                    window: other,
                    accessibilityHidden: other.accessibilityElementsHidden,
                    interactionEnabled: other.isUserInteractionEnabled
                ))
                other.accessibilityElementsHidden = true
                other.isUserInteractionEnabled = false
            }
        }
        window.accessibilityViewIsModal = options.modalTarget == .window
        host.view.accessibilityViewIsModal = options.modalTarget == .rootView
        // The content sets its own appearance; the window underneath may wear
        // a screen's own style, such as a dark game.
        matchContentFrame()
        // Before the window shows, so its first frame already clears the controls.
        updateWindowControlsLeading(atRise: true)
        isRaised = true
        window.allowsKey = true
        window.isHidden = false
        window.makeKey()
        context.isRaised = true
        context.raiseCount += 1
        #if DEBUG
        let editing = contentWindow.flatMap { Self.firstResponder(in: $0) }
        report.append("Editing after: " + (editing.map { String(describing: type(of: $0)) } ?? "none"))
        report.append("Cover is key: \(window.isKeyWindow)")
        context.report = report
        SceneCoverLog.record("NOTICES-COVER raise " + report.joined(separator: " | "))
        #endif
        // `.content` moves VoiceOver itself once it has focused a field, and
        // `.none` leaves it in the window the user is in.
        if request.voiceOver(window.traitCollection) == .coverRoot {
            UIAccessibility.post(notification: .screenChanged, argument: host.view)
        }
        host.setNeedsFocusUpdate()
        host.updateFocusIfNeeded()
    }

    private func lower(in scene: UIWindowScene, request: SceneCoverRequest) {
        guard let window else { return }
        let next = SceneCoverPolicy.keyWindowAfterLowering(
            scene.windows.map { Self.policyWindow($0) },
            cover: ObjectIdentifier(window),
            coverLevel: Self.level.rawValue,
            previousKey: keyWindowBeforeRaise.map { ObjectIdentifier($0) },
            content: contentWindow.map { ObjectIdentifier($0) }
        )
        isRaised = false
        window.allowsKey = false
        // A hidden cover never keeps its own first responder, such as the reply field.
        window.endEditing(true)
        window.isHidden = true
        for entry in locked {
            entry.window?.accessibilityElementsHidden = entry.accessibilityHidden
            entry.window?.isUserInteractionEnabled = entry.interactionEnabled
        }
        locked.removeAll()
        if scene.keyWindow == nil || scene.keyWindow === window,
           let next, let target = scene.windows.first(where: { ObjectIdentifier($0) == next }) {
            target.makeKey()
        }
        keyWindowBeforeRaise = nil
        context.isRaised = false
        #if DEBUG
        let key = scene.keyWindow.map { String(describing: type(of: $0)) } ?? "none"
        SceneCoverLog.record("NOTICES-COVER lower scene=\(Self.shortID(scene)) key=\(key)")
        #endif
        if request.voiceOver(window.traitCollection) != .none {
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
        // Last, so what it starts, such as held navigation, runs uncovered.
        request.didLower()
    }

    /// Points VoiceOver at the cover's first responder, such as the reply
    /// field it just focused (probe 5, device run 5); at the cover's root
    /// view when nothing in it has focus.
    func moveVoiceOverToFocusedElement() {
        guard isRaised, let window, let host else { return }
        let target: UIView = Self.firstResponder(in: window) ?? host.view
        UIAccessibility.post(notification: .screenChanged, argument: target)
        #if DEBUG
        SceneCoverLog.record("NOTICES-COVER voiceover target=\(type(of: target))")
        #endif
    }

    private func matchContentFrame() {
        guard let window, let contentWindow,
              contentWindow.windowScene === window.windowScene,
              window.frame != contentWindow.frame else { return }
        #if DEBUG
        SceneCoverLog.record("NOTICES-COVER frame cover=\(window.frame) content=\(contentWindow.frame)")
        #endif
        window.frame = contentWindow.frame
    }

    /// Reads the window controls' inset from the content window's
    /// corner-adapted safe area, and publishes it when it changes.
    private func updateWindowControlsLeading(atRise: Bool = false) {
        let insets = contentLeadingInsets()
        let leading = insets.map {
            SceneCoverPolicy.windowControlsLeading(
                isFullScreen: $0.isFullScreen, cornerAdapted: $0.cornerAdapted, plain: $0.plain)
        } ?? 0
        #if DEBUG
        if atRise || context.windowControlsLeading != leading {
            let raw = insets.map { "corner \($0.cornerAdapted) plain \($0.plain) fullScreen \($0.isFullScreen)" } ?? "none"
            SceneCoverLog.record("NOTICES-COVER window controls leading=\(leading) (\(raw)) scene=\(Self.shortID(scene))")
        }
        #endif
        guard context.windowControlsLeading != leading else { return }
        context.windowControlsLeading = leading
    }

    /// The content window's leading safe area, plain and corner-adapted. The
    /// Mac draws its window controls in the title bar, outside the content.
    private func contentLeadingInsets() -> (isFullScreen: Bool, cornerAdapted: CGFloat, plain: CGFloat)? {
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *), let contentWindow, let windowScene = contentWindow.windowScene,
           let view = contentWindow.rootViewController?.view {
            return (windowScene.isFullScreen,
                    view.directionalEdgeInsets(for: .safeArea(cornerAdaptation: .horizontal)).leading,
                    view.directionalEdgeInsets(for: .safeArea()).leading)
        }
        #endif
        return nil
    }

    @objc private func sceneDidDisconnect(_ notification: Notification) {
        if let scene = notification.object as? UIScene,
           Self.covers[ObjectIdentifier(scene)] === self {
            Self.covers[ObjectIdentifier(scene)] = nil
        }
        geometryObservation?.invalidate()
        geometryObservation = nil
        window?.allowsKey = false
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        host = nil
        isRaised = false
        #if DEBUG
        SceneCoverLog.record("NOTICES-COVER disconnect")
        #endif
    }

    private static func policyWindow(_ window: UIWindow) -> SceneCoverPolicy.Window<ObjectIdentifier> {
        SceneCoverPolicy.Window(
            id: ObjectIdentifier(window), level: window.windowLevel.rawValue, isHidden: window.isHidden
        )
    }

    /// The view that is first responder in `view`'s subtree. View-only on
    /// purpose: text inputs are views, and this never asks another scene.
    private static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for subview in view.subviews {
            if let responder = firstResponder(in: subview) { return responder }
        }
        return nil
    }

    #if DEBUG
    private func describe(_ scene: UIWindowScene, cover: UIWindow) -> [String] {
        let windows = scene.windows.map { window -> String in
            var text = "\(type(of: window)) \(window.windowLevel.rawValue)"
            if window === cover { text += " (cover)" }
            if window.isKeyWindow { text += " key" }
            if window.isHidden { text += " hidden" }
            return text
        }
        let presented = contentWindow?.rootViewController.map { Self.presentedControllers(from: $0) } ?? []
        let editing = contentWindow.flatMap { Self.firstResponder(in: $0) }
        return [
            "Scene \(Self.shortID(scene)) · rise \(context.raiseCount + 1)",
            "Windows: " + windows.joined(separator: ", "),
            "Presented: " + (presented.isEmpty ? "none"
                : presented.map { String(describing: type(of: $0)) }.joined(separator: " → ")),
            "Editing before: " + (editing.map { String(describing: type(of: $0)) } ?? "none"),
        ]
    }

    private static func shortID(_ scene: UIScene?) -> String {
        scene.map { String($0.session.persistentIdentifier.prefix(8)) } ?? "none"
    }

    /// Every view controller presented from `root` or its children, in order.
    private static func presentedControllers(from root: UIViewController) -> [UIViewController] {
        var result = [UIViewController]()
        var pending = [root]
        while let controller = pending.popLast() {
            if let presented = controller.presentedViewController,
               presented.presentingViewController === controller {
                result.append(presented)
                pending.append(presented)
            }
            pending.append(contentsOf: controller.children)
        }
        return result
    }
    #endif
}

#if DEBUG
import OSLog

/// The cover's Debug lines, each starting with NOTICES-COVER, under
/// subsystem com.honganhkhoa.Surround, category NoticesCover.
enum SceneCoverLog {
    private static let log = Logger(subsystem: "com.honganhkhoa.Surround", category: "NoticesCover")
    static func record(_ message: String) { log.notice("\(message, privacy: .public)") }
}
#endif
