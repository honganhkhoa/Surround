//
//  ConnectionStatusModel.swift
//  Surround
//
//  What a window says about its connection to OGS, from the in-app notices
//  design: nothing while connected or during a short drop, "Reconnecting…"
//  once a drop lasts `revealDelay`, "Can't reach OGS · Retry" after
//  `unreachableDelay` or when the device has no network, and "Connected"
//  briefly after an outage someone saw. `reduce`, `status` and
//  `nextDeadline` are pure, so every rule is tested without a socket;
//  `ConnectionStatusSource` feeds them from a window's `OGSService`.
//

import Foundation

/// Whether the device has a network path, as `NWPathMonitor` reports it.
enum NetworkPathStatus: Equatable {
    /// No report yet. It counts as a network, so nothing is said early.
    case unknown
    /// A path exists, or may come up when a connection starts.
    case satisfied
    /// No usable network: "Can't reach OGS" needs no 30 s wait.
    case unsatisfied
}

enum ConnectionStatusModel {

    // MARK: - Rules

    /// A drop shorter than this shows nothing.
    static let revealDelay: TimeInterval = 2
    /// After this long without a connection, counted from the drop,
    /// "Reconnecting…" becomes "Can't reach OGS". The socket's reconnect
    /// backoff reaches its 30 s cap at about the same time.
    static let unreachableDelay: TimeInterval = 30
    /// How long "Connected" shows after an outage that showed.
    static let confirmationDuration: TimeInterval = 2
    /// After Retry or a network that came back, "Reconnecting…" shows at
    /// least this long, even while the device reports no network.
    static let retryFeedbackDuration: TimeInterval = 2

    // MARK: - Output

    enum Status: Equatable {
        /// Nothing to say: connected, a drop shorter than `revealDelay`, or a
        /// window that isn't on screen.
        case hidden
        /// "Reconnecting…".
        case reconnecting
        /// "Can't reach OGS · Retry".
        case unreachable(UnreachableReason)
        /// "Connected", for `confirmationDuration` after an outage that showed.
        case connected

        /// Retry is offered only when OGS can't be reached.
        var offersRetry: Bool {
            if case .unreachable = self { return true }
            return false
        }
    }

    enum UnreachableReason: Equatable {
        /// The device reports no network path.
        case noNetwork
        /// `unreachableDelay` passed without a connection.
        case timedOut
    }

    /// What VoiceOver hears, once per outage. The source only reports these;
    /// the app posts them once per app, from the frontmost window.
    enum Announcement: Equatable {
        /// "Reconnecting to OGS", when an outage first shows as reconnecting.
        case reconnecting
        /// "Can't reach OGS", when an outage first shows as unreachable.
        case unreachable
        /// "Connected", at low priority, when an outage that showed ends.
        case connected
    }

    // MARK: - Input

    enum Event: Equatable {
        /// The window's socket is open (`OGSWebsocketStatus.connected`) or not.
        case socket(isConnected: Bool)
        case path(NetworkPathStatus)
        /// The window is on screen: its scene is not in the background.
        case visibility(Bool)
        /// The person asked to retry.
        case retry
        /// A deadline from `nextDeadline` passed.
        case tick
    }

    enum Effect: Equatable {
        /// Start a fresh connection attempt now, with the reconnect backoff
        /// reset (`OGSService.retryConnection()`).
        case connect
        case announce(Announcement)
    }

    struct State: Equatable {
        enum Phase: Equatable {
            /// Connected, or not on screen.
            case idle
            /// Down since `since`; nothing shows before `since + revealDelay`.
            case pending(since: TimeInterval)
            /// The outage shows. `since` starts the `unreachableDelay` clock;
            /// `retriedAt` is the latest Retry or network return.
            case shown(since: TimeInterval, retriedAt: TimeInterval?)
            /// "Connected" until `until`.
            case confirming(until: TimeInterval)
        }

        var isSocketConnected = false
        var path = NetworkPathStatus.unknown
        var isVisible = false
        /// The socket has been open at least once since the source started.
        /// Until then, a window with no network says so at once.
        var hasConnected = false
        var phase = Phase.idle
    }

    // MARK: - Rules as functions

    static func reduce(_ state: inout State, _ event: Event, now: TimeInterval) -> [Effect] {
        switch event {
        case .socket(let isConnected):
            guard isConnected != state.isSocketConnected else { return [] }
            state.isSocketConnected = isConnected
            if isConnected {
                state.hasConnected = true
                switch state.phase {
                case .pending:
                    state.phase = .idle
                case .shown:
                    state.phase = .confirming(until: now + confirmationDuration)
                    return [.announce(.connected)]
                case .idle, .confirming:
                    break
                }
                return []
            }
            guard state.isVisible else { return [] }
            if case .confirming = state.phase {
                // A drop while "Connected" shows keeps the outage on screen,
                // with no blank in between and no second announcement.
                state.phase = .shown(since: now, retriedAt: nil)
                return []
            }
            return beginOutage(&state, now: now)

        case .path(let path):
            let networkReturned = state.path == .unsatisfied && path == .satisfied
            state.path = path
            guard state.isVisible, !state.isSocketConnected else { return [] }
            if networkReturned {
                // Reconnect now rather than after the backoff, which may be
                // 30 s by now.
                if case .shown = state.phase {
                    state.phase = .shown(since: now, retriedAt: now)
                }
                return [.connect]
            }
            if path == .unsatisfied, !state.hasConnected, case .pending = state.phase {
                state.phase = .shown(since: now, retriedAt: nil)
                return [.announce(.unreachable)]
            }
            return []

        case .visibility(let isVisible):
            guard isVisible != state.isVisible else { return [] }
            state.isVisible = isVisible
            guard isVisible else {
                // Off screen, nobody sees the outage or its end.
                state.phase = .idle
                return []
            }
            return state.isSocketConnected ? [] : beginOutage(&state, now: now)

        case .retry:
            guard state.isVisible, !state.isSocketConnected else { return [] }
            state.phase = .shown(since: now, retriedAt: now)
            return [.connect]

        case .tick:
            switch state.phase {
            case .pending(let since) where now >= since + revealDelay:
                state.phase = .shown(since: since, retriedAt: nil)
                return [.announce(state.path == .unsatisfied ? .unreachable : .reconnecting)]
            case .confirming(let until) where now >= until:
                state.phase = .idle
            default:
                break
            }
            return []
        }
    }

    static func status(_ state: State, now: TimeInterval) -> Status {
        switch state.phase {
        case .idle, .pending:
            return .hidden
        case .confirming:
            return .connected
        case let .shown(since, retriedAt):
            let givesRetryFeedback = retriedAt.map { now < $0 + retryFeedbackDuration } ?? false
            if state.path == .unsatisfied && !givesRetryFeedback {
                return .unreachable(.noNetwork)
            }
            return now >= since + unreachableDelay ? .unreachable(.timedOut) : .reconnecting
        }
    }

    /// When the status next changes with time alone; nil when it can't.
    static func nextDeadline(_ state: State, now: TimeInterval) -> TimeInterval? {
        switch state.phase {
        case .idle:
            return nil
        case .pending(let since):
            return since + revealDelay
        case .confirming(let until):
            return until
        case let .shown(since, retriedAt):
            var deadlines = [since + unreachableDelay]
            if state.path == .unsatisfied, let retriedAt {
                deadlines.append(retriedAt + retryFeedbackDuration)
            }
            return deadlines.filter { $0 > now }.min()
        }
    }

    /// A window that has never connected and has no network says so at once.
    /// Any other drop waits `revealDelay`, so a short one shows nothing.
    private static func beginOutage(_ state: inout State, now: TimeInterval) -> [Effect] {
        if !state.hasConnected && state.path == .unsatisfied {
            state.phase = .shown(since: now, retriedAt: nil)
            return [.announce(.unreachable)]
        }
        state.phase = .pending(since: now)
        return []
    }
}
