//
//  GameControlProbe.swift
//  Surround
//
//  The Debug-only toolbar-item probe: a placeholder in Game Detail's Active
//  games slot, in every toolbar form, that logs its frames and what it
//  receives, and anchors a popover with a composer in it (TESTING.md). Only
//  gameControlProbeFrame(_:) exists in other builds, where it does nothing.
//

import Combine
import os
import SwiftUI
import UIKit

extension View {
    /// Logs this view's frame while the probe runs; otherwise it is the view itself.
    @ViewBuilder func gameControlProbeFrame(_ name: String) -> some View {
        #if DEBUG && MAIN_APP
        if GameControlProbeConfiguration.current != nil {
            onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                GameControlProbeLog.record("frame \(name) global=\(frame)")
            }
        } else { self }
        #else
        self
        #endif
    }
}

#if DEBUG && MAIN_APP
/// Lines under subsystem com.honganhkhoa.Surround, category GameControlProbe.
enum GameControlProbeLog {
    private static let log = Logger(subsystem: "com.honganhkhoa.Surround", category: "GameControlProbe")
    static func record(_ message: String) { log.notice("\(message, privacy: .public)") }
}

/// Stands in for the slot's view in every arrangement, with the Active games
/// identifiers and popover, so the slot's journeys run against it.
struct GameControlProbeItem: View {
    let placement: GameActiveGamesPlacement
    let configuration: GameControlProbeConfiguration
    @Binding var isPresented: Bool        // GameDetailView.showsActiveGames
    let onTurnCount: Int                  // today's accessibility value
    let popoverContent: AnyView           // GameDetailView.activeGamesPopoverContent
    @State private var events = GameControlProbeEvents()
    @State private var heldDuringPress = false
    private var size: CGSize { configuration.size(for: placement.form) }

    var body: some View {
        if configuration.variants.contains(.nativeBadge) {
            // The fallback design: a plain native icon item, which must not be wrapped.
            Button { handle(.tap) } label: {
                Label { Text("Active games") } icon: { Image(systemName: "square.grid.2x2") }
                    .frame(minWidth: 44, minHeight: 44)
            }
            .badge(3)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in handle(.hold) })
            .modifier(ProbeAccessibility(onTurnCount: onTurnCount) { handle(.accessibilityAction) })
            .popover(isPresented: $isPresented) { popover }
        } else {
            // The container keeps the toolbar from synthesizing a native item
            // out of the label, as GameToolbarChatButton's does.
            ZStack { interactiveLabel }
                .frame(width: size.width, height: size.height)
                .accessibilityElement(children: .contain)
                .popover(isPresented: $isPresented) { popover }
                .onAppear { GameControlProbeLog.record("appear \(placement) size=\(size)") }
                .onDisappear { GameControlProbeLog.record("disappear \(placement)") }
        }
    }

    @ViewBuilder private var interactiveLabel: some View {
        if configuration.variants.contains(.gestureView) {
            label
                .onTapGesture { handle(.tap) }
                .onLongPressGesture(minimumDuration: 0.5) { handle(.hold) }
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { handle(.tap) }
                .modifier(ProbeAccessibility(onTurnCount: onTurnCount) { handle(.accessibilityAction) })
        } else {
            Button {
                if !heldDuringPress { handle(.tap) }   // the release ending a hold is no tap
            } label: { label }
            .buttonStyle(PressStyle { heldDuringPress = false })
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                heldDuringPress = true
                handle(.hold)
            })
            .modifier(ProbeAccessibility(onTurnCount: onTurnCount) { handle(.accessibilityAction) })
        }
    }

    private var label: some View {
        formLabel
            .padding(.horizontal, 6)
            .frame(width: size.width, height: size.height)
            .overlay { RoundedRectangle(cornerRadius: min(size.width, size.height) / 2).strokeBorder(.orange) }
            .contentShape(Rectangle())
            .gesture(GameControlProbeSecondaryClick { handle(.secondaryClick) })
            .background { GameControlProbeMarker(label: "item \(placement)") }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                GameControlProbeLog.record("frame item \(placement) global=\(frame)")
            }
    }

    /// Each form's drawn content (canvas AGameForms), with stand-in values.
    @ViewBuilder private var formLabel: some View {
        switch placement.form {
        case .bottomBar:
            HStack(spacing: 8) {
                board
                Text(verbatim: "Probe").lineLimit(1)
                Text(verbatim: "00:42").monospacedDigit().fixedSize()
                Text(verbatim: "+3")
            }
            .font(.subheadline.weight(.semibold))
        case .topBar:
            HStack(spacing: 4) {
                Image(systemName: "square.grid.2x2")
                Text(verbatim: "00:42")
            }
        case .rail:
            VStack(spacing: 2) {
                board
                Text(verbatim: "00:42").font(.caption2)
            }
        }
    }

    /// The flat 28 pt square that stands in for the game's board.
    private var board: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color(red: 0.86, green: 0.69, blue: 0.42))
            .frame(width: 28, height: 28)
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 0) {
            popoverContent
            Divider()
            Text(verbatim: events.summary).font(.footnote.monospacedDigit()).padding([.horizontal, .top])
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameControlProbeEvents)
            GameControlProbeComposer()
        }
        .presentationCompactAdaptation(.popover)
        .onAppear { GameControlProbeLog.record("popover appear \(placement)") }
        .onDisappear { GameControlProbeLog.record("popover disappear \(placement)") }
    }

    private func handle(_ kind: GameControlProbeEvents.Kind) {
        events.record(kind)
        GameControlProbeLog.record("event \(kind.rawValue) \(placement) \(events.summary)")
        if kind == .tap && configuration.variants.contains(.chip) { return }   // the chip's tap switches games
        isPresented = true
    }

    /// Calls `onPress` as each press starts, so the release that ends a hold
    /// never counts as a tap.
    private struct PressStyle: ButtonStyle {
        let onPress: () -> Void

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.6 : 1)
                .onChange(of: configuration.isPressed) { wasPressed, isPressed in
                    if isPressed && !wasPressed { onPress() }
                }
        }
    }

    /// Today's label, value and identifier, so label- and identifier-based
    /// queries still match, plus a VoiceOver action that opens the popover.
    private struct ProbeAccessibility: ViewModifier {
        let onTurnCount: Int
        let openActivity: () -> Void

        func body(content: Content) -> some View {
            content
                .accessibilityLabel(Text("Active games"))
                .accessibilityValue(Text(verbatim: String(onTurnCount)))
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameActiveGamesButton)
                .accessibilityAction(named: Text(verbatim: "Open Activity"), openActivity)
        }
    }
}

/// A secondary click from a pointer: the Mac, or an iPad with a trackpad or
/// mouse. Fingers never match.
private struct GameControlProbeSecondaryClick: UIGestureRecognizerRepresentable {
    let action: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let recognizer = UITapGestureRecognizer()
        recognizer.buttonMaskRequired = .secondary
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        if recognizer.state == .ended { action() }
    }
}

/// Logs where the item's view really is, one line whenever the text changes:
/// `marker <label> window=<Bool> frame=<frame in its window, or nil> bar=<bar class, or none>`.
/// A native bar item's view stays in an offscreen host and never enters a
/// window; a custom view the bar drops leaves its window. It only logs.
private struct GameControlProbeMarker: UIViewRepresentable {
    let label: String

    func makeUIView(context: Context) -> MarkerView { MarkerView(label: label) }

    func updateUIView(_ view: MarkerView, context: Context) { view.label = label }

    final class MarkerView: UIView {
        var label: String { didSet { log() } }
        private var lastLine: String?

        init(label: String) {
            self.label = label
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            log()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            log()
        }

        private func log() {
            let windowFrame = window.map { "\(convert(bounds, to: $0))" } ?? "nil"
            let line = "marker \(label) window=\(window != nil) frame=\(windowFrame) bar=\(barName)"
            guard line != lastLine else { return }
            lastLine = line
            GameControlProbeLog.record(line)
        }

        /// The first enclosing view whose type name says it is a bar.
        private var barName: String {
            var ancestor = superview
            while let view = ancestor {
                let name = String(describing: type(of: view))
                if name.contains("Toolbar") || name.contains("NavigationBar") { return name }
                ancestor = view.superview
            }
            return "none"
        }
    }
}

/// Stands in for a conversation's composer, to see where the popover puts
/// it with the keyboard up.
private struct GameControlProbeComposer: View {
    @State private var draft = ""

    var body: some View {
        HStack {
            TextField(text: $draft, prompt: Text(verbatim: "Reply")) { Text(verbatim: "Reply") }
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameControlProbeComposer)
            Button {
                GameControlProbeLog.record("composer send length=\(draft.count)")
            } label: {
                Label { Text(verbatim: "Send") } icon: { Image(systemName: "arrow.up.circle.fill") }
                    .labelStyle(.iconOnly)
            }
        }
        .padding()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            GameControlProbeLog.record("composer global=\(frame)")
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardDidChangeFrameNotification
        )) { notification in
            let end = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            GameControlProbeLog.record("keyboard end=\(end.map { "\($0)" } ?? "nil")")
        }
    }
}
#endif
