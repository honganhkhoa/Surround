//
//  AppAnnouncer.swift
//  Surround
//
//  VoiceOver announcements and haptics, once per app instead of once per
//  window. Every window has its own OGSService, socket and views, and the
//  services of closed windows stay in OGSService.instances, so each window
//  would otherwise speak the same event. AppAnnouncer decides from which
//  window the user is in and what it said in the last few seconds. Its
//  system output, the shared instance and each window's anchor live in
//  AppAnnouncer+System.swift, outside the unit-test target.
//

import Foundation

/// Something to say or feel, on behalf of one window.
struct AppAnnouncement: Equatable {
    /// The event it is about. Equal keys from any window are one event,
    /// so only one of them is spoken or felt.
    struct Key: Hashable {
        let rawValue: String

        init(_ rawValue: String) {
            self.rawValue = rawValue
        }
    }

    enum Audience: Equatable {
        /// Every window learns of it through its own socket, or it is about
        /// a window's own state, such as its connection or a game's clock.
        /// Only the frontmost window's copy counts, so nothing is posted
        /// while every window is in the background.
        case frontmostWindow
        /// Only the window where it happened learns of it, such as the
        /// result of the user's own action there. Any open window's copy
        /// counts, so moving to another window doesn't silence it. It posts
        /// even while every window is in the background, as the app's
        /// announcements did before AppAnnouncer.
        case anyWindow
    }

    /// VoiceOver's announcement priority.
    enum Priority: Equatable {
        case low, normal, high
    }

    enum Haptic: Equatable {
        case success, warning, error
    }

    var key: Key
    var audience: Audience
    var speech: String?
    var priority: Priority
    var haptic: Haptic?

    init(
        _ key: Key,
        audience: Audience,
        speech: String? = nil,
        priority: Priority = .normal,
        haptic: Haptic? = nil
    ) {
        self.key = key
        self.audience = audience
        self.speech = speech
        self.priority = priority
        self.haptic = haptic
    }
}

extension AppAnnouncement.Key {
    /// A friendship action OGS confirmed. Each notice is its own event.
    static func friendshipResult(_ notice: UUID) -> Self {
        Self("friendship.\(notice.uuidString)")
    }

    /// Quick Match searches the user just started, in any order.
    static func quickMatchStarted(_ entryIDs: [String]) -> Self {
        Self("quick-match.started.\(entryIDs.sorted().joined(separator: ","))")
    }

    /// OGS cancelled this search. Every window's socket hears it.
    static func quickMatchCancelled(_ entryID: String) -> Self {
        Self("quick-match.cancelled.\(entryID)")
    }

    /// OGS ended every search at once. Its event names none, so two of
    /// them within AppAnnouncer.duplicateInterval count as one.
    static let quickMatchSearchesEnded = Self("quick-match.searches-ended")

    /// Searches OGS didn't confirm after a reconnect, in any order.
    static func quickMatchNotConfirmed(_ entryIDs: Set<String>) -> Self {
        Self("quick-match.not-confirmed.\(entryIDs.sorted().joined(separator: ","))")
    }

    /// A live game started. "Game found" uses it now, and Activity's
    /// "Game started" will, so the two are never both spoken.
    static func gameStarted(_ gameID: Int) -> Self {
        Self("game.started.\(gameID)")
    }
}

/// The app's windows and which one the user is in. Each window's anchor
/// reports its own state, and the app-wide answer combines every window's,
/// as DisplaySleepRequests does for display sleep.
struct AppAnnouncerWindows {
    enum Activation: Equatable {
        /// UIScene's foregroundActive: on screen and taking input.
        case active
        /// foregroundInactive: on screen behind Control Center, the app
        /// switcher or a system alert, or still launching.
        case inactive
        /// background, or unattached.
        case background
    }

    private struct Entry {
        var owner: UUID
        var activation: Activation
        /// When the user last came to this window, as a sequence number;
        /// 0 means never.
        var focus = 0
        /// It went to the background after the user last came to it.
        var wasInBackground = false
    }

    private var entries = [UUID: Entry]()
    private var focusCount = 0

    /// Records what a window's anchor, `owner`, sees. The window counts as
    /// the one the user came to when it first becomes active, when it is
    /// active again after the background, or when `focused` says so (a Mac
    /// window becoming key). Activating again after Control Center or an
    /// alert keeps the order the windows had.
    mutating func update(
        _ window: UUID,
        owner: UUID,
        activation: Activation,
        focused: Bool = false
    ) {
        var entry = entries[window] ?? Entry(owner: owner, activation: activation)
        entry.owner = owner
        if activation == .background {
            entry.wasInBackground = true
        }
        entry.activation = activation
        if activation == .active, focused || entry.focus == 0 || entry.wasInBackground {
            focusCount += 1
            entry.focus = focusCount
            entry.wasInBackground = false
        }
        entries[window] = entry
    }

    /// Withdraws a window, unless a newer anchor has taken it over.
    mutating func remove(_ window: UUID, owner: UUID) {
        guard entries[window]?.owner == owner else { return }
        entries.removeValue(forKey: window)
    }

    func contains(_ window: UUID) -> Bool {
        entries[window] != nil
    }

    /// The window the user is in: the active window they came to last;
    /// while none is active, the on-screen window they came to last; nil
    /// while every window is in the background.
    var frontmost: UUID? {
        latestFocused(.active) ?? latestFocused(.inactive)
    }

    private func latestFocused(_ activation: Activation) -> UUID? {
        entries
            .filter { $0.value.activation == activation }
            .max { ($0.value.focus, $0.key.uuidString) < ($1.value.focus, $1.key.uuidString) }?
            .key
    }
}

/// What AppAnnouncer asks before every post.
protocol AppAnnouncerSceneStates: AnyObject {
    /// The window the user is in, or nil while every window is in the
    /// background.
    var frontmostWindow: UUID? { get }
    /// The window's scene is still connected. A closed window's services
    /// stay in OGSService.instances, but it never posts.
    func isOpen(_ window: UUID) -> Bool
}

/// The app's windows, as their anchors report them.
final class AppAnnouncerWindowRegistry: AppAnnouncerSceneStates {
    private(set) var windows = AppAnnouncerWindows()

    func update(
        _ window: UUID,
        owner: UUID,
        activation: AppAnnouncerWindows.Activation,
        focused: Bool = false
    ) {
        windows.update(window, owner: owner, activation: activation, focused: focused)
    }

    func remove(_ window: UUID, owner: UUID) {
        windows.remove(window, owner: owner)
    }

    var frontmostWindow: UUID? { windows.frontmost }

    func isOpen(_ window: UUID) -> Bool { windows.contains(window) }
}

/// Where posts go: VoiceOver and the Taptic Engine in the app, a recorder
/// in tests.
protocol AppAnnouncerOutput {
    func speak(_ text: String, priority: AppAnnouncement.Priority)
    func play(_ haptic: AppAnnouncement.Haptic)
}

/// Posts VoiceOver announcements and haptics once per app instead of once
/// per window: a window's own events only from the window the user is in,
/// and copies of one event from several windows once. Main thread only,
/// like OGSService and NavigationService. It publishes nothing, so a post
/// during a layout pass can't invalidate SwiftUI views.
final class AppAnnouncer {
    enum Outcome: Equatable {
        case posted
        /// The reporting window's scene is gone.
        case windowClosed
        /// A .frontmostWindow copy while every window is in the background.
        case noWindowInFront
        /// A .frontmostWindow copy from a window the user isn't in.
        case notFrontmost
        /// The same key was posted less than duplicateInterval ago.
        case duplicate
    }

    /// Long enough for every window's socket to deliver one event; short
    /// enough that a later event with the same key is spoken again.
    static let duplicateInterval: TimeInterval = 5

    private let now: () -> TimeInterval
    private let scenes: AppAnnouncerSceneStates
    private let output: AppAnnouncerOutput
    private let duplicateInterval: TimeInterval
    /// When each key was last posted. Dropped copies aren't remembered, so
    /// the frontmost window's copy still posts after another window's.
    private var postedAt = [AppAnnouncement.Key: TimeInterval]()

    /// - Parameter now: Monotonic seconds, replaceable for tests.
    init(
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        scenes: AppAnnouncerSceneStates,
        output: AppAnnouncerOutput,
        duplicateInterval: TimeInterval = AppAnnouncer.duplicateInterval
    ) {
        self.now = now
        self.scenes = scenes
        self.output = output
        self.duplicateInterval = duplicateInterval
    }

    /// For focus moves and other window-local accessibility, which must
    /// never come from a window the user isn't in.
    func isFrontmost(_ window: UUID) -> Bool {
        scenes.frontmostWindow == window
    }

    /// Keys still remembered for the duplicate check, for tests.
    var rememberedKeyCount: Int { postedAt.count }

    @discardableResult
    func post(_ announcement: AppAnnouncement, from window: UUID) -> Outcome {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(.main))
        #endif
        let time = now()
        postedAt = postedAt.filter { time - $0.value < duplicateInterval }
        guard scenes.isOpen(window) else { return .windowClosed }
        // Only a window's own events wait for a window in front; an
        // .anyWindow copy posts from the background, as before.
        if announcement.audience == .frontmostWindow {
            guard let frontmost = scenes.frontmostWindow else { return .noWindowInFront }
            guard frontmost == window else { return .notFrontmost }
        }
        guard postedAt[announcement.key] == nil else { return .duplicate }
        postedAt[announcement.key] = time
        if let speech = announcement.speech {
            output.speak(speech, priority: announcement.priority)
        }
        if let haptic = announcement.haptic {
            output.play(haptic)
        }
        return .posted
    }
}
