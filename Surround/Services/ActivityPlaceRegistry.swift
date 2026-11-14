//
//  ActivityPlaceRegistry.swift
//  Surround
//
//  The window-level "Activity hidden" signal. Game Detail and conversations,
//  pushed or selected in Messages' side pane, register here, and Activity's
//  root hosts (the accessory, the custom bar, the iPad and Mac Now sections)
//  read the settled state. Nothing reads it yet.
//

import Foundation
import Combine
import OSLog

/// One window's screens that hide Activity's bar, by tab. Each
/// NavigationService owns one, so there is one per window. Main thread by
/// convention, like its owner.
final class ActivityPlaceRegistry: ObservableObject {
    /// What one screen reports.
    struct Registration: Equatable {
        /// `.game` or `.conversation`. A `.root` place hides nothing.
        var place: ActivityModel.Place
        /// The tab whose stack shows the screen. Nil in a presented stack (a
        /// sheet or popover) and in roots without tabs, which never hide a
        /// tab's bar.
        var root: RootView?
        /// Nothing is pushed above the screen and it has not been popped.
        var isOnTop: Bool
    }

    /// What hosts read.
    struct State: Equatable {
        /// For each tab whose top screen hides Activity, that screen's place.
        var places: [RootView: ActivityModel.Place] = [:]
    }

    /// Settles one main-queue turn after the screens change, so it never
    /// changes during a view update or a layout pass, including
    /// setTabBarHidden's synchronous layout (forum-224).
    private(set) var state = State()

    /// Sends each new `state` after it is stored. A `@Published` publisher
    /// fires before the store, so UIKit hosts subscribe here instead.
    let stateDidChange = PassthroughSubject<State, Never>()

    private struct Entry {
        var registration: Registration
        /// Registration order; the latest screen on top of a tab wins.
        let order: Int
    }

    private var entries: [UUID: Entry] = [:]
    private var nextOrder = 0
    private var settleScheduled = false
    private let schedule: (@escaping () -> Void) -> Void

    /// - Parameter schedule: Runs work on a later main-queue turn. Tests pass
    ///   a queue they run by hand.
    init(schedule: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) {
        self.schedule = schedule
    }

    // MARK: Reading

    /// Whether `root`'s top screen hides Activity's bar.
    func hidesActivity(in root: RootView) -> Bool {
        state.places[root] != nil
    }

    /// The place for `ActivityModel.Input` on a window-level surface while
    /// `root` is selected.
    func place(in root: RootView) -> ActivityModel.Place {
        state.places[root] ?? .root(isMessagesTab: root == .privateMessages)
    }

    // MARK: Writing (ActivityPlaceRegistration, StackRouter.swift)

    /// Adds or updates `owner`'s screen. An update keeps its order; a `.root`
    /// place removes it.
    func set(_ registration: Registration, for owner: UUID) {
        guard registration.place.hidesBar else {
            remove(owner)
            return
        }
        if var entry = entries[owner] {
            guard entry.registration != registration else { return }
            entry.registration = registration
            entries[owner] = entry
        } else {
            entries[owner] = Entry(registration: registration, order: nextOrder)
            nextOrder += 1
        }
        scheduleSettle()
    }

    func remove(_ owner: UUID) {
        guard entries.removeValue(forKey: owner) != nil else { return }
        scheduleSettle()
    }

    // MARK: Settling

    private func scheduleSettle() {
        guard !settleScheduled else { return }
        settleScheduled = true
        schedule { [weak self] in self?.settle() }
    }

    private func settle() {
        // Cleared first, so an observer that changes a screen schedules a new
        // turn instead of re-entering.
        settleScheduled = false
        var frontmost: [RootView: Entry] = [:]
        for entry in entries.values {
            guard let root = entry.registration.root, entry.registration.isOnTop else { continue }
            if let current = frontmost[root], current.order > entry.order { continue }
            frontmost[root] = entry
        }
        let next = State(places: frontmost.mapValues { $0.registration.place })
        guard next != state else { return }
        objectWillChange.send()
        state = next
        stateDidChange.send(next)
        #if DEBUG
        logIfRequested(next)
        #endif
    }

    #if DEBUG
    /// Logs every settled change, for the accessory and freeze checks.
    static let logLaunchArgument = "--surround-activity-hidden-log"
    private static let logsChanges = ProcessInfo.processInfo.arguments.contains(logLaunchArgument)
    private static let log = Logger(subsystem: "com.honganhkhoa.Surround", category: "ActivityHidden")
    private var settledChanges = 0

    private func logIfRequested(_ state: State) {
        guard Self.logsChanges else { return }
        settledChanges += 1
        let places = state.places.map { "\($0.key.rawValue)=\($0.value)" }.sorted()
        let summary = places.isEmpty ? "none" : places.joined(separator: " ")
        Self.log.notice("ACTIVITY-HIDDEN #\(self.settledChanges, privacy: .public) \(summary, privacy: .public)")
    }
    #endif
}
