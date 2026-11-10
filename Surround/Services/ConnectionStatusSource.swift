//
//  ConnectionStatusSource.swift
//  Surround
//
//  One window's connection status, for the screens that will show it (in-app
//  notices, phases 4 and 5). It feeds `ConnectionStatusModel` from the
//  window's `OGSService` socket status, the device's network path and
//  whether the window is on screen, and wakes itself at the model's next
//  deadline. Nothing creates one in Release builds yet.
//

import Combine
import Foundation

/// The device's network path, for `ConnectionStatusSource`.
protocol NetworkPathMonitoring: AnyObject {
    /// The current status at once, then each change, on the main queue.
    var pathStatus: AnyPublisher<NetworkPathStatus, Never> { get }
}

/// A path that never changes, for the offline UI-test roots, previews and tests.
final class ConstantNetworkPath: NetworkPathMonitoring {
    static let satisfied = ConstantNetworkPath(.satisfied)

    let pathStatus: AnyPublisher<NetworkPathStatus, Never>

    init(_ status: NetworkPathStatus) {
        pathStatus = Just(status).eraseToAnyPublisher()
    }
}

/// Main thread only, like `OGSService`. A source starts off screen and says
/// nothing until its host calls `setVisible(true)`.
final class ConnectionStatusSource: ObservableObject {
    @Published private(set) var status = ConnectionStatusModel.Status.hidden

    /// What VoiceOver should hear. The app posts these once per app, from
    /// the frontmost window; a window never posts its own.
    var announcements: AnyPublisher<ConnectionStatusModel.Announcement, Never> {
        announcementSubject.eraseToAnyPublisher()
    }

    private var state = ConnectionStatusModel.State()
    private let announcementSubject = PassthroughSubject<ConnectionStatusModel.Announcement, Never>()
    private let reconnect: () -> Void
    private let scheduler: OGSWebsocketScheduling
    private let now: () -> TimeInterval
    private var wakeUp: Cancellable?
    private var subscriptions = Set<AnyCancellable>()

    /// - Parameters:
    ///   - socketIsConnected: Whether the window's socket is open, current
    ///     value first.
    ///   - path: The device's network path, shared by every window.
    ///   - reconnect: A fresh connection attempt with the backoff reset.
    ///   - scheduler: Wakes the source at the model's deadlines.
    ///   - now: Seconds on the scheduler's clock. The default stops while the
    ///     device sleeps, as `DispatchTime` does.
    init(
        socketIsConnected: AnyPublisher<Bool, Never>,
        path: NetworkPathMonitoring,
        reconnect: @escaping () -> Void,
        scheduler: OGSWebsocketScheduling = OGSMainQueueWebsocketScheduler.shared,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.reconnect = reconnect
        self.scheduler = scheduler
        self.now = now
        socketIsConnected
            .removeDuplicates()
            .sink { [weak self] in self?.send(.socket(isConnected: $0)) }
            .store(in: &subscriptions)
        path.pathStatus
            .removeDuplicates()
            .sink { [weak self] in self?.send(.path($0)) }
            .store(in: &subscriptions)
    }

    /// A window's source. Signed-out windows count too: public games use the
    /// socket.
    convenience init(
        ogs: OGSService,
        path: NetworkPathMonitoring,
        scheduler: OGSWebsocketScheduling = OGSMainQueueWebsocketScheduler.shared,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.init(
            // `socketStatus` republishes `.reconnecting` on every failed
            // attempt; the designated initializer drops the repeats.
            socketIsConnected: ogs.$socketStatus.map { $0 == .connected }.eraseToAnyPublisher(),
            path: path,
            reconnect: { [weak ogs] in ogs?.retryConnection() },
            scheduler: scheduler,
            now: now
        )
    }

    deinit {
        wakeUp?.cancel()
    }

    /// Whether the window is on screen: its scene is not in the background.
    func setVisible(_ isVisible: Bool) {
        send(.visibility(isVisible))
    }

    /// Retry, from "Can't reach OGS · Retry".
    func retry() {
        send(.retry)
    }

    private func send(_ event: ConnectionStatusModel.Event) {
        let time = now()
        let effects = ConnectionStatusModel.reduce(&state, event, now: time)
        let newStatus = ConnectionStatusModel.status(state, now: time)
        if newStatus != status {
            status = newStatus
        }
        scheduleWakeUp(at: ConnectionStatusModel.nextDeadline(state, now: time), from: time)
        for effect in effects {
            switch effect {
            case .connect:
                reconnect()
            case .announce(let announcement):
                announcementSubject.send(announcement)
            }
        }
    }

    private func scheduleWakeUp(at deadline: TimeInterval?, from time: TimeInterval) {
        wakeUp?.cancel()
        wakeUp = nil
        guard let deadline else { return }
        wakeUp = scheduler.schedule(after: max(0, deadline - time)) { [weak self] in
            self?.send(.tick)
        }
    }
}
