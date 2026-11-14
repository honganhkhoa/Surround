//
//  NoticesPlaceholderCoverContract.swift
//  Surround
//
//  Launch flags, commands and app-wide state of the Debug-only placeholder
//  moderator cover, which probes one overlay window per scene. Nothing
//  exists without --surround-notices-placeholder-cover.
//

#if DEBUG
import Combine
import Foundation

enum NoticesPlaceholderCoverContract {
    static let launchArgument = "--surround-notices-placeholder-cover"
    /// Seconds after launch before the cover rises; 0 starts covered.
    static let raiseAfterArgument = "--surround-notices-placeholder-cover-raise-after"
    /// Seconds that "Lower, raise in" and the menu's timed raise wait.
    static let reraiseAfterArgument = "--surround-notices-placeholder-cover-reraise-after"
    /// A comma-separated list of `NoticesPlaceholderCoverConfiguration.Variant`s.
    static let variantArgument = "--surround-notices-placeholder-cover-variant"
    static let defaultReraiseDelay: TimeInterval = 5
    static let maximumDelay: TimeInterval = 600

    /// Darwin notifications that raise, lower or toggle the cover in every
    /// window: `xcrun simctl spawn <device> notifyutil -p <name>` on a
    /// simulator, `notifyutil -p <name>` on the Mac, or CFNotificationCenter
    /// from a UI test running on the same device.
    enum Command: String, CaseIterable {
        case raise = "com.honganhkhoa.Surround.debug.notices-cover.raise"
        case lower = "com.honganhkhoa.Surround.debug.notices-cover.lower"
        case toggle = "com.honganhkhoa.Surround.debug.notices-cover.toggle"
    }

    enum AccessibilityID {
        static let cover = "notices.placeholderCover"
        static let lower = "notices.placeholderCover.lower"
        static let reraise = "notices.placeholderCover.reraise"
        static let reply = "notices.placeholderCover.reply"
        static let send = "notices.placeholderCover.send"
        static let report = "notices.placeholderCover.report"
    }
}

struct NoticesPlaceholderCoverConfiguration: Equatable {
    enum Variant: String, CaseIterable {
        /// Take key without ending editing underneath.
        case keepResponder = "keep-responder"
        /// `accessibilityViewIsModal` on the cover's root view, not its window.
        case modalRoot = "modal-root"
        /// Also hide the windows below from accessibility and disable them.
        case lockUnderneath = "lock-underneath"
        /// Focus the cover's reply field each time it rises.
        case focusReply = "focus-reply"
        /// Mac: leave the window's content and toolbar enabled under the cover.
        case keepContentEnabled = "keep-content-enabled"
        /// A window that opens covered raises while its anchor attaches.
        case raiseWhileAttaching = "raise-while-attaching"
    }

    enum ParseError: Error, Equatable {
        case missingValue(argument: String)
        case invalidDelay(argument: String, value: String)
        case unknownVariant(String)
    }

    /// Seconds after launch before the cover rises; nil waits for a command.
    var raiseAfterLaunch: TimeInterval?
    var reraiseDelay = NoticesPlaceholderCoverContract.defaultReraiseDelay
    var variants = Set<Variant>()

    /// Nil unless the cover's own flag is present: its other flags alone do
    /// nothing. Malformed values throw, so a probe never runs half-configured.
    static func parse(_ arguments: [String]) throws -> NoticesPlaceholderCoverConfiguration? {
        typealias Contract = NoticesPlaceholderCoverContract
        guard arguments.contains(Contract.launchArgument) else { return nil }
        var configuration = NoticesPlaceholderCoverConfiguration()
        configuration.raiseAfterLaunch = try delay(after: Contract.raiseAfterArgument, in: arguments)
        if let reraise = try delay(after: Contract.reraiseAfterArgument, in: arguments) {
            configuration.reraiseDelay = reraise
        }
        if let list = try value(after: Contract.variantArgument, in: arguments) {
            for name in list.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) })
            where !name.isEmpty {
                guard let variant = Variant(rawValue: name) else { throw ParseError.unknownVariant(name) }
                configuration.variants.insert(variant)
            }
        }
        return configuration
    }

    /// The window behaviour the variants select. `focus-reply` and
    /// `keep-content-enabled` act in the probe's views instead.
    var coverOptions: SceneCoverOptions {
        var options = SceneCoverOptions()
        options.endsEditingUnderneath = !variants.contains(.keepResponder)
        options.modalTarget = variants.contains(.modalRoot) ? .rootView : .window
        options.locksWindowsBelow = variants.contains(.lockUnderneath)
        options.raisesWhileAttaching = variants.contains(.raiseWhileAttaching)
        return options
    }

    private static func value(after argument: String, in arguments: [String]) throws -> String? {
        guard let index = arguments.firstIndex(of: argument) else { return nil }
        guard arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("--") else {
            throw ParseError.missingValue(argument: argument)
        }
        return arguments[index + 1]
    }

    private static func delay(after argument: String, in arguments: [String]) throws -> TimeInterval? {
        guard let text = try value(after: argument, in: arguments) else { return nil }
        guard let seconds = TimeInterval(text), seconds.isFinite,
              (0...NoticesPlaceholderCoverContract.maximumDelay).contains(seconds) else {
            throw ParseError.invalidDelay(argument: argument, value: text)
        }
        return seconds
    }
}

/// The placeholder cover's app-wide state: raised in every window or in none,
/// as the real cover will be. Main thread only, like the app's services.
final class NoticesPlaceholderCoverState: ObservableObject {
    typealias Schedule = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> AnyCancellable

    static let mainQueueSchedule: Schedule = { delay, work in
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return AnyCancellable { item.cancel() }
    }

    let configuration: NoticesPlaceholderCoverConfiguration
    @Published private(set) var isRaised = false
    private let schedule: Schedule
    private var pendingRaise: AnyCancellable?

    var hasPendingRaise: Bool { pendingRaise != nil }

    init(
        configuration: NoticesPlaceholderCoverConfiguration,
        schedule: @escaping Schedule = NoticesPlaceholderCoverState.mainQueueSchedule
    ) {
        self.configuration = configuration
        self.schedule = schedule
        if let delay = configuration.raiseAfterLaunch {
            if delay == 0 { isRaised = true } else { raise(after: delay) }
        }
    }

    func raise() {
        pendingRaise = nil
        if !isRaised { isRaised = true }
    }

    func lower() {
        pendingRaise = nil
        if isRaised { isRaised = false }
    }

    /// Raises after `delay`, replacing any timed raise already waiting.
    func raise(after delay: TimeInterval) {
        pendingRaise = schedule(delay) { [weak self] in
            guard let self else { return }
            self.pendingRaise = nil
            if !self.isRaised { self.isRaised = true }
        }
    }

    /// Lowers now and rises again after the configured delay, so a tester can
    /// first open a sheet, alert or menu underneath.
    func lowerThenRaiseAgain() {
        lower()
        raise(after: configuration.reraiseDelay)
    }

    func perform(_ command: NoticesPlaceholderCoverContract.Command) {
        switch command {
        case .raise: raise()
        case .lower: lower()
        case .toggle: isRaised ? lower() : raise()
        }
    }
}
#endif
