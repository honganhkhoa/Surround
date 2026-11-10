// Opt-in check of the in-app notices' connection status on a device, from
// the window's real socket and network path, before any screen shows it.
// Off unless the app launches with --surround-connection-status-probe.

#if DEBUG && MAIN_APP
import OSLog
import SwiftUI

struct ConnectionStatusProbe: View {
    private static let log = Logger(subsystem: "com.honganhkhoa.Surround", category: "ConnectionStatusProbe")

    @StateObject private var source: ConnectionStatusSource
    @Environment(\.scenePhase) private var scenePhase

    init(ogs: OGSService) {
        _source = StateObject(wrappedValue: ConnectionStatusSource(
            ogs: ogs,
            path: SystemNetworkPathMonitor.shared
        ))
    }

    private var caption: String {
        switch source.status {
        case .hidden: "connection: hidden"
        case .reconnecting: "connection: reconnecting"
        case .unreachable(.noNetwork): "connection: no network · tap to retry"
        case .unreachable(.timedOut): "connection: timed out · tap to retry"
        case .connected: "connection: connected"
        }
    }

    var body: some View {
        Text(verbatim: caption)
            .font(.caption2.monospaced())
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.yellow.opacity(0.85), in: Capsule())
            .onTapGesture { source.retry() }
            // Taps reach the app underneath except while Retry is offered.
            .allowsHitTesting(source.status.offersRetry)
            .accessibilityIdentifier("test.connectionStatus")
            .onChange(of: scenePhase, initial: true) { _, phase in
                source.setVisible(phase != .background)
            }
            .onReceive(source.$status) { status in
                Self.log.info("status \(String(describing: status), privacy: .public)")
            }
            .onReceive(source.announcements) { announcement in
                Self.log.info("announce \(String(describing: announcement), privacy: .public)")
            }
    }
}
#endif
