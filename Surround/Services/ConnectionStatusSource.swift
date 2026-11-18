//
//  ConnectionStatusSource.swift
//  Surround
//
//  One window's connection status, for the screens that show it: the
//  moderator superchat cover (SuperchatCover.swift), and later the in-app
//  notices of phases 4 and 5. It feeds `ConnectionStatusModel` from the
//  window's `OGSService` socket status, the device's network path and
//  whether the window is on screen, and wakes itself at the model's next
//  deadline.
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
    /// The window's socket has been open at least once since the source
    /// started, on screen or not. Until then the window is still making its
    /// first connection; only after it can a connection be lost.
    @Published private(set) var hasConnected = false

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
        if state.hasConnected != hasConnected {
            hasConnected = state.hasConnected
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

extension ConnectionStatusModel.Announcement {
    /// What the app posts for it: once per app, from the window the user is
    /// in, with "Connected" at low priority.
    var appAnnouncement: AppAnnouncement {
        switch self {
        case .reconnecting:
            AppAnnouncement(.connection(self), audience: .frontmostWindow, speech: String(
                localized: "Reconnecting to OGS",
                comment: "VoiceOver: spoken once when the app loses its connection to OGS and starts reconnecting"
            ))
        case .unreachable:
            AppAnnouncement(.connection(self), audience: .frontmostWindow, speech: String(
                localized: "Can’t reach OGS",
                comment: "Activity: under the title while the app can't connect to OGS; shown with Retry"
            ))
        case .connected:
            AppAnnouncement(.connection(self), audience: .frontmostWindow,
                            speech: String(localized: "Connected", comment: "Connection status"),
                            priority: .low)
        }
    }
}
