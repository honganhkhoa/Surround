//
//  SystemNetworkPathMonitor.swift
//  Surround
//
//  The device's network path for every window's connection status, from one
//  NWPathMonitor that starts when the first source subscribes.
//

import Combine
import Foundation
import Network

final class SystemNetworkPathMonitor: NetworkPathMonitoring {
    /// Created, and its monitor started, on first use.
    static let shared = SystemNetworkPathMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.honganhkhoa.Surround.networkPath", qos: .utility)
    private let subject = CurrentValueSubject<NetworkPathStatus, Never>(.unknown)

    private init() {
        let subject = subject
        monitor.pathUpdateHandler = { path in
            let status = NetworkPathStatus(path.status)
            DispatchQueue.main.async { subject.send(status) }
        }
        monitor.start(queue: queue)
    }

    /// Subscribe on the main thread.
    var pathStatus: AnyPublisher<NetworkPathStatus, Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }
}

extension NetworkPathStatus {
    init(_ status: NWPath.Status) {
        switch status {
        case .satisfied, .requiresConnection:
            // `requiresConnection`: a path may come up when a connection
            // starts (an on-demand VPN, asleep cellular), so it isn't "no
            // network".
            self = .satisfied
        case .unsatisfied:
            self = .unsatisfied
        @unknown default:
            self = .satisfied
        }
    }
}
