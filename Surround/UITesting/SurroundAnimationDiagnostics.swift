// Opt-in observations for deterministic UI-test animation investigations.
// Observation IDs identify SwiftUI state storage, not UIKit presenter objects.

#if DEBUG && MAIN_APP
import SwiftUI
import OSLog

enum SurroundAnimationDiagnostics {
    static let isEnabled = SurroundUITestContract.isEnabled
        && ProcessInfo.processInfo.arguments.contains(
            SurroundUITestContract.animationDiagnosticsLaunchArgument
        )

    private final class Output: @unchecked Sendable {
        let lock = NSLock()
        let logger = Logger(
            subsystem: "com.honganhkhoa.Surround",
            category: "UIAnimationDiagnostics"
        )
        var sequence = 0
        var lastValues = [String: String]()
        var reportedLimit = false
    }

    private static let output = Output()
    private static let eventLimit = 2_000

    static func record(
        _ event: StaticString,
        observationID: UUID? = nil,
        ownerID: UUID? = nil,
        focusRequestID: UUID? = nil,
        fields: @autoclosure () -> [String: String] = [:],
        deduplicated: Bool = false
    ) {
        guard isEnabled else { return }
        let eventName = String(describing: event)
        let values = fields().sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        let identity = "observation=\(observationID?.uuidString ?? "none") "
            + "owner=\(ownerID?.uuidString ?? "none") "
            + "focusRequest=\(focusRequestID?.uuidString ?? "none")"
        let key = "\(eventName)|\(observationID?.uuidString ?? "none")|\(ownerID?.uuidString ?? "none")"
        let payload = "\(identity) \(values)"

        output.lock.lock()
        defer { output.lock.unlock() }
        guard output.sequence < eventLimit else {
            if !output.reportedLimit {
                output.reportedLimit = true
                emit("trace.limitReached limit=\(eventLimit)")
            }
            return
        }
        if deduplicated, output.lastValues[key] == payload { return }
        if deduplicated { output.lastValues[key] = payload }
        emit("event=\(eventName) \(payload)")
    }

    // Called only with output.lock held. Store no views, notifications, or text.
    private static func emit(_ message: String) {
        output.sequence += 1
        let uptime = String(
            format: "%.6f", ProcessInfo.processInfo.systemUptime
        )
        let line = "[SurroundAnimation] seq=\(output.sequence) "
            + "uptime=\(uptime) pid=\(ProcessInfo.processInfo.processIdentifier) "
            + message
        output.logger.notice("\(line, privacy: .public)")
    }

    static func roundedFrame(_ frame: CGRect) -> CGRect {
        CGRect(
            x: frame.origin.x.rounded(), y: frame.origin.y.rounded(),
            width: frame.width.rounded(), height: frame.height.rounded()
        )
    }

    static func frameDescription(_ frame: CGRect) -> String {
        let frame = roundedFrame(frame)
        return "\(frame.origin.x),\(frame.origin.y),\(frame.width),\(frame.height)"
    }

    static func keyboard(
        _ event: StaticString,
        notification: Notification,
        ownerID: UUID
    ) {
        guard isEnabled else { return }
        let info = notification.userInfo ?? [:]
        var fields = [String: String]()
        if let frame = info[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect {
            fields["beginFrame"] = frameDescription(frame)
        }
        if let frame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            fields["endFrame"] = frameDescription(frame)
        }
        if let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber {
            fields["duration"] = duration.stringValue
        }
        if let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber {
            fields["curve"] = curve.stringValue
        }
        record(event, ownerID: ownerID, fields: fields)
    }
}

private struct SurroundAnimationObservation: ViewModifier {
    let name: String
    let ownerID: UUID
    let focusRequestID: UUID?
    let context: String
    @State private var observationID = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { record("view.appearCallback") }
            .onDisappear { record("view.disappearCallback") }
            .onGeometryChange(for: CGRect.self) { proxy in
                SurroundAnimationDiagnostics.roundedFrame(
                    proxy.frame(in: .global)
                )
            } action: { frame in
                record("view.frame", frame: frame)
            }
    }

    private func record(_ event: StaticString, frame: CGRect? = nil) {
        var fields = ["name": name, "context": context]
        if let frame {
            fields["frame"] = SurroundAnimationDiagnostics.frameDescription(frame)
        }
        SurroundAnimationDiagnostics.record(
            event,
            observationID: observationID,
            ownerID: ownerID,
            focusRequestID: focusRequestID,
            fields: fields,
            deduplicated: frame != nil
        )
    }
}

extension View {
    @ViewBuilder
    func surroundAnimationObservation(
        _ name: String,
        ownerID: UUID,
        focusRequestID: UUID? = nil,
        context: String = ""
    ) -> some View {
        if SurroundAnimationDiagnostics.isEnabled {
            modifier(SurroundAnimationObservation(
                name: name, ownerID: ownerID,
                focusRequestID: focusRequestID, context: context
            ))
        } else {
            self
        }
    }

    @ViewBuilder
    func surroundAnimationState(
        _ event: StaticString,
        value: String,
        ownerID: UUID,
        focusRequestID: UUID? = nil
    ) -> some View {
        if SurroundAnimationDiagnostics.isEnabled {
            onAppear {
                SurroundAnimationDiagnostics.record(
                    event, ownerID: ownerID, focusRequestID: focusRequestID,
                    fields: ["value": value], deduplicated: true
                )
            }
            .onChange(of: value) { _, newValue in
                SurroundAnimationDiagnostics.record(
                    event, ownerID: ownerID, focusRequestID: focusRequestID,
                    fields: ["value": newValue], deduplicated: true
                )
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func surroundAnimationKeyboardObservations(ownerID: UUID) -> some View {
        if SurroundAnimationDiagnostics.isEnabled {
            onReceive(SystemPlatformServices.shared.keyboardWillChangeFramePublisher) {
                SurroundAnimationDiagnostics.keyboard(
                    "keyboard.willChangeFrameCallback", notification: $0,
                    ownerID: ownerID
                )
            }
            .onReceive(SystemPlatformServices.shared.keyboardDidChangeFramePublisher) {
                SurroundAnimationDiagnostics.keyboard(
                    "keyboard.didChangeFrameCallback", notification: $0,
                    ownerID: ownerID
                )
            }
        } else {
            self
        }
    }
}
// DIAGNOSTIC (iPadOS 18 Home long-press on CI): logs touch delivery,
// gesture-recognizer state changes and main-thread stalls, so a long press
// that ends as a tap shows which recognizer won and whether touches arrived
// late. Enabled with the animation-diagnostics launch argument.
enum SurroundTouchTrace {
    private static let logger = Logger(subsystem: "com.honganhkhoa.Surround", category: "TouchTrace")
    private static var sequence = 0
    private static let limit = 20_000
    private static var lastTouchUptime: TimeInterval = -.infinity
    private static var lastTick = ProcessInfo.processInfo.systemUptime
    private static var installed = false

    static func installIfEnabled() {
        guard SurroundAnimationDiagnostics.isEnabled, !installed else { return }
        installed = true
        swizzle(UIApplication.self, #selector(UIApplication.sendEvent(_:)),
                #selector(UIApplication.surroundTrace_sendEvent(_:)))
        swizzle(UIGestureRecognizer.self, NSSelectorFromString("setState:"),
                #selector(UIGestureRecognizer.surroundTrace_setState(_:)))
        swizzle(UIGestureRecognizer.self, NSSelectorFromString("setEnabled:"),
                #selector(UIGestureRecognizer.surroundTrace_setEnabled(_:)))
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            let gap = now - lastTick
            lastTick = now
            if gap > 0.25 { emit("stall gap=\(String(format: "%.3f", gap))") }
        }
        RunLoop.main.add(timer, forMode: .common)
        emit("installed")
    }

    private static func swizzle(_ cls: AnyClass, _ original: Selector, _ replacement: Selector) {
        guard let a = class_getInstanceMethod(cls, original),
              let b = class_getInstanceMethod(cls, replacement) else {
            emit("swizzleFailed \(NSStringFromSelector(original))")
            return
        }
        method_exchangeImplementations(a, b)
    }

    static var isNearTouch: Bool {
        ProcessInfo.processInfo.systemUptime - lastTouchUptime < 6
    }

    static func touches(_ event: UIEvent) {
        guard event.type == .touches, let touches = event.allTouches else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lastTouchUptime = now
        for touch in touches {
            let point = touch.window.map { touch.location(in: $0) } ?? .zero
            var chain = [String]()
            var view = touch.view
            while let current = view, chain.count < 8 {
                let recognizers = current.gestureRecognizers?.map { String(describing: type(of: $0)) } ?? []
                chain.append(String(describing: type(of: current))
                             + (recognizers.isEmpty ? "" : "{\(recognizers.joined(separator: ","))}"))
                view = current.superview
            }
            let lag = now - touch.timestamp
            emit("touch phase=\(touch.phase.rawValue) at=\(Int(point.x)),\(Int(point.y)) "
                 + "lag=\(String(format: "%.3f", lag)) taps=\(touch.tapCount) "
                 + "recognizers=\(touch.gestureRecognizers?.count ?? 0) view=\(chain.joined(separator: " < "))")
        }
    }

    static func state(_ recognizer: UIGestureRecognizer, _ newState: UIGestureRecognizer.State) {
        guard isNearTouch, newState != .possible || recognizer.state != .possible else { return }
        let view = recognizer.view.map { String(describing: type(of: $0)) } ?? "nil"
        emit("gesture \(type(of: recognizer)) \(recognizer.state.rawValue)->\(newState.rawValue) "
             + "view=\(view) enabled=\(recognizer.isEnabled) "
             + "delegate=\(recognizer.delegate.map { String(describing: type(of: $0)) } ?? "nil")")
    }

    static func enabled(_ recognizer: UIGestureRecognizer, _ enabled: Bool) {
        guard isNearTouch, enabled != recognizer.isEnabled else { return }
        let name = String(describing: type(of: recognizer))
        guard name.contains("TouchDuration") || name.contains("Relationship") || name.contains("LongPress") else { return }
        let view = recognizer.view.map { String(describing: type(of: $0)) } ?? "nil"
        emit("setEnabled \(name) \(recognizer.isEnabled)->\(enabled) state=\(recognizer.state.rawValue) view=\(view)")
        for (index, frame) in Thread.callStackSymbols.prefix(45).enumerated() {
            emit("  stack[\(index)] \(frame)")
        }
    }

    static func emit(_ message: String) {
        guard sequence < limit else { return }
        sequence += 1
        let uptime = String(format: "%.4f", ProcessInfo.processInfo.systemUptime)
        logger.notice("[SurroundTouch] seq=\(sequence) uptime=\(uptime, privacy: .public) \(message, privacy: .public)")
    }
}

extension UIApplication {
    @objc func surroundTrace_sendEvent(_ event: UIEvent) {
        SurroundTouchTrace.touches(event)
        surroundTrace_sendEvent(event)
    }
}

extension UIGestureRecognizer {
    @objc func surroundTrace_setEnabled(_ enabled: Bool) {
        SurroundTouchTrace.enabled(self, enabled)
        surroundTrace_setEnabled(enabled)
    }

    @objc func surroundTrace_setState(_ newState: UIGestureRecognizer.State) {
        SurroundTouchTrace.state(self, newState)
        surroundTrace_setState(newState)
    }
}
#endif
