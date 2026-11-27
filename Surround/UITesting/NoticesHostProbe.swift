//
//  NoticesHostProbe.swift
//  Surround
//
//  The Activity hosts' Debug log (TESTING.md): the UIKit containers' accessory
//  sets and clears with their reasons, the iPad's sidebar, baselines and Now
//  rows, and the Mac's Now section log here, and with
//  --surround-activity-hidden-log so does each Game Detail board's frame.
//

#if DEBUG && MAIN_APP
import OSLog
import SwiftUI
import UIKit

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
}

// MARK: - The board's marker

/// Game Detail's board, one key per screen instance, so each open logs the
/// board's first size and every later change: how a game opened beside the
/// Activity bar lays out. Only with `--surround-activity-hidden-log`. It
/// logs `board.frame` in window coordinates, which SwiftUI's `.global` space
/// doesn't reach from accessories and sidebar bars, and it only logs, so it
/// is safe in any layout pass.
struct NoticesProbeBoardMarker: UIViewRepresentable {
    static let logs = ProcessInfo.processInfo.arguments.contains(ActivityPlaceRegistry.logLaunchArgument)
    private static var instances = 0

    func makeUIView(context: Context) -> MarkerView {
        Self.instances += 1
        return MarkerView(key: "board.\(Self.instances)")
    }

    func updateUIView(_ view: MarkerView, context: Context) {}

    final class MarkerView: UIView {
        private let key: String

        init(key: String) {
            self.key = key
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            registerForActivityAccessoryEnvironmentChanges { $0.setNeedsLayout() }
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
            let divisions = activityDivisionFrames
            let windowDivisions = window.map { window in divisions.map { convert($0, to: window) } } ?? []
            NoticesHostProbeLog.event("board.frame", [
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

#endif
