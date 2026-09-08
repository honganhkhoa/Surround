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
#endif
