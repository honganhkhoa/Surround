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
//  Debug-only until the moderator superchat cover adopts it. Lifting the
//  outer #if then ships it; the inner DEBUG blocks stay probe-only.
//

#if DEBUG
import OSLog
import SwiftUI
import UIKit

/// What a scene's cover tells the SwiftUI content it hosts.
final class SceneCoverContext: ObservableObject {
    @Published fileprivate(set) var isRaised = false
    /// Counts each rise, so content can move focus every time. A scene's
    /// first rise can land before its content first renders, so observe it
    /// with `onChange(of:initial: true)` and check `isRaised`.
    @Published fileprivate(set) var raiseCount = 0
    #if DEBUG
    /// What the cover last rose over, for probes and logs.
    @Published fileprivate(set) var report: [String] = []
    #endif
}

/// The anchor's latest wish for its scene's cover.
struct SceneCoverRequest {
    var isRaised: Bool
    var options: SceneCoverOptions
    var content: AnyView
}

/// Mounts the scene's cover. Put it, at zero size, in the background of the
/// scene's root view; it never draws anything itself.
struct SceneCoverAnchor<Content: View>: UIViewRepresentable {
    var isRaised: Bool
    var options = SceneCoverOptions()
    @ViewBuilder var content: () -> Content

    func makeUIView(context: Context) -> SceneCoverAnchorView {
        SceneCoverAnchorView(frame: .zero)
    }

    func updateUIView(_ view: SceneCoverAnchorView, context: Context) {
        view.update(SceneCoverRequest(
            isRaised: isRaised, options: options, content: AnyView(content())
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
    private var host: UIHostingController<AnyView>?
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
        self.request = request
        self.contentWindow = contentWindow
        contentChanged = true
        #if DEBUG
        if attaching {
            SceneCoverLog.record("NOTICES-COVER attach scene=\(Self.shortID(contentWindow.windowScene)) raised=\(request.isRaised)")
        }
        #endif
        if attaching, request.options.raisesWhileAttaching, request.isRaised, !isRaised {
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
            raise(in: scene, options: request.options)
        } else if !request.isRaised, isRaised {
            lower(in: scene)
        }
    }

    private func makeWindow(in scene: UIWindowScene) {
        let window = SceneCoverWindow(windowScene: scene)
        window.windowLevel = Self.level
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        host.view.backgroundColor = .systemBackground
        window.rootViewController = host
        self.window = window
        self.host = host
        contentChanged = true
    }

    private func raise(in scene: UIWindowScene, options: SceneCoverOptions) {
        guard let window, let host else { return }
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
        if let contentWindow {
            window.overrideUserInterfaceStyle = contentWindow.overrideUserInterfaceStyle
        }
        matchContentFrame()
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
        UIAccessibility.post(notification: .screenChanged, argument: host.view)
        host.setNeedsFocusUpdate()
        host.updateFocusIfNeeded()
    }

    private func lower(in scene: UIWindowScene) {
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
        UIAccessibility.post(notification: .screenChanged, argument: nil)
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

    /// The view that is first responder in `view`'s subtree. View-only on
    /// purpose: text inputs are views, and this never asks another scene.
    private static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for subview in view.subviews {
            if let responder = firstResponder(in: subview) { return responder }
        }
        return nil
    }
    #endif
}

#if DEBUG
/// The cover's Debug lines, each starting with NOTICES-COVER, under
/// subsystem com.honganhkhoa.Surround, category NoticesCover.
enum SceneCoverLog {
    private static let log = Logger(subsystem: "com.honganhkhoa.Surround", category: "NoticesCover")
    static func record(_ message: String) { log.notice("\(message, privacy: .public)") }
}
#endif
#endif
