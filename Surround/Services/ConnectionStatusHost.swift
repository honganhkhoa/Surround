//
//  ConnectionStatusHost.swift
//  Surround
//
//  What a window's root hands every view in the window: the window's one
//  connection source, which the moderator superchat cover reads instead of
//  making its own, and the window's width class and shape, which the
//  in-game control's frames follow. MainView forwards both into its
//  UIKit-hosted tabs, and the cover's mount passes the source into the
//  cover's own window. Previews have no root, so both read nil there.
//  Captures get the window's width class and shape but no source, so a
//  capture in a narrow window draws the frames a person sees there.
//

import SwiftUI
import UIKit

private struct ConnectionStatusKey: EnvironmentKey {
    static let defaultValue: ConnectionStatusSource? = nil
}

private struct GameControlWindowClassKey: EnvironmentKey {
    static let defaultValue: GameControlWindowClass? = nil
}

extension EnvironmentValues {
    /// This window's connection status; nil where no root hosts one, so a
    /// view built anywhere else shows none.
    var connectionStatus: ConnectionStatusSource? {
        get { self[ConnectionStatusKey.self] }
        set { self[ConnectionStatusKey.self] = newValue }
    }

    /// This window's width class and shape, from the window's own size. Nil
    /// until the root has measured its window, and where no root measures
    /// one, so the control keeps its widest frames there.
    var gameControlWindowClass: GameControlWindowClass? {
        get { self[GameControlWindowClassKey.self] }
        set { self[GameControlWindowClassKey.self] = newValue }
    }
}

/// A window's root: owns the window's connection source, keeps it on screen
/// while the scene isn't in the background, and reports the window's width
/// class and shape. Apply it around the superchat cover's mount, so the
/// cover shares the source.
struct ConnectionStatusHost: ViewModifier {
    @StateObject private var source: ConnectionStatusSource
    @Environment(\.scenePhase) private var scenePhase

    init(ogs: OGSService, path: NetworkPathMonitoring) {
        _source = StateObject(wrappedValue: {
            let source = ConnectionStatusSource(ogs: ogs, path: path)
            // On screen from the start; the change handler in `body`
            // corrects this for a window made in the background. A window
            // that opens while the device already reports no network says
            // so in its first frame, so the cover of a window that opens
            // covered never focuses a field it disables a moment later.
            source.setVisible(true)
            return source
        }())
    }

    func body(content: Content) -> some View {
        content
            .modifier(GameControlWindowClassHost())
            .environment(\.connectionStatus, source)
            .onChange(of: scenePhase, initial: true) { _, phase in
                source.setVisible(phase != .background)
            }
    }
}

/// Hands the window's width class and shape down, as its reporter last
/// measured them. The state is its own, so a change of connection status
/// never touches it. `ConnectionStatusHost` applies it; captures, which
/// have no connection source, apply it alone.
struct GameControlWindowClassHost: ViewModifier {
    @State private var windowClass: GameControlWindowClass?

    func body(content: Content) -> some View {
        content
            .environment(\.gameControlWindowClass, windowClass)
            .background {
                GameControlWindowClassReporter { windowClass = $0 }
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
    }
}

/// Measures the window it is in. It reads the window's own bounds and
/// horizontal size class, and the device, never its content's layout: when
/// it arrives in the window, when the window's scene changes geometry, when
/// the size class changes, and when it lays out with the root. It reports a
/// main-queue turn later, and only when the class, shape or top-bar room
/// changes, so it publishes only when the window resizes or turns. Nothing
/// drawn inside the window, such as a tab bar that hides, a toolbar item,
/// a keyboard or a hidden status bar, changes the window's bounds or size
/// class, so none of them publishes anything.
private struct GameControlWindowClassReporter: UIViewRepresentable {
    let onChange: (GameControlWindowClass) -> Void

    func makeUIView(context: Context) -> ReporterView {
        let view = ReporterView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: ReporterView, context: Context) {
        view.onChange = onChange
    }

    final class ReporterView: UIView {
        var onChange: ((GameControlWindowClass) -> Void)?
        private var reported: GameControlWindowClass?
        private var geometryObservation: NSKeyValueObservation?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            accessibilityElementsHidden = true
            registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (view: ReporterView, _: UITraitCollection) in
                view.measure()
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Stage Manager and Mac windows resize, and phones turn. The
            // window takes its new bounds after its scene reports them.
            geometryObservation = window?.windowScene?.observe(\.effectiveGeometry, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.measure() }
            }
            measure()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            measure()
        }

        private func measure() {
            guard let window, !window.bounds.isEmpty else { return }
            let measured = GameControlWindowClass(
                windowSize: window.bounds.size,
                isRegularWidth: window.traitCollection.horizontalSizeClass == .regular,
                isPhone: UIDevice.current.userInterfaceIdiom == .phone
            )
            guard measured != reported else { return }
            reported = measured
            // Never inside a SwiftUI update or a UIKit layout pass, such as
            // the one setTabBarHidden runs.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, self.reported == measured else { return }
                self.onChange?(measured)
            }
        }
    }
}
