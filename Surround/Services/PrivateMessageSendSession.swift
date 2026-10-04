import SwiftUI
import Combine

private enum PrivateMessageSendError: Error {
    case acknowledgementTimedOut
}

/// A send belongs to its account and peer, rather than to a particular composer.
/// The registry below retains it while navigation or an adaptive layout replaces
/// the view that submitted the message.
final class PrivateMessageSendSession: ObservableObject {
    @Published private(set) var isSending = false
    @Published private(set) var failure: PrivateMessageSendFailure?

    private var sendCancellable: AnyCancellable?
    private var activeSendID: UUID?
    private var acknowledgedSendID: UUID?
    private let acknowledgementTimeout: TimeInterval
    var onFinished: (() -> Void)?

    init(acknowledgementTimeout: TimeInterval = OGSWebsocket.defaultCallbackTimeout + 5) {
        self.acknowledgementTimeout = acknowledgementTimeout
    }

    func send(to peer: OGSUser, draft: Binding<String>, using ogs: OGSService) {
        // The socket owns its acknowledgment deadline. This is only a fallback
        // for a publisher that fails to finish after that deadline.
        send(
            draft: draft,
            acknowledgementTimeout: max(acknowledgementTimeout, ogs.privateMessageAcknowledgementTimeout + 5)
        ) { message in
            ogs.sendPrivateMessage(to: peer, message: message)
        }
    }

    func send(
        draft: Binding<String>,
        using sendMessage: (String) -> AnyPublisher<OGSPrivateMessage, Error>
    ) {
        send(draft: draft, acknowledgementTimeout: acknowledgementTimeout, using: sendMessage)
    }

    private func send(
        draft: Binding<String>,
        acknowledgementTimeout: TimeInterval,
        using sendMessage: (String) -> AnyPublisher<OGSPrivateMessage, Error>
    ) {
        let submittedMessage = draft.wrappedValue
        guard !isSending, !submittedMessage.isEmpty else { return }

        let sendID = UUID()
        activeSendID = sendID
        acknowledgedSendID = nil
        isSending = true
        failure = nil

        sendCancellable = sendMessage(submittedMessage)
            .timeout(
                .seconds(acknowledgementTimeout),
                scheduler: DispatchQueue.main,
                customError: { PrivateMessageSendError.acknowledgementTimedOut }
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self, self.activeSendID == sendID else { return }
                self.activeSendID = nil
                self.sendCancellable = nil
                self.isSending = false
                if case .failure(let error) = completion {
                    self.failure = PrivateMessageSendFailure.classify(error)
                } else if self.acknowledgedSendID != sendID {
                    self.failure = .deliveryUnconfirmed
                }
                self.acknowledgedSendID = nil
                self.onFinished?()
            } receiveValue: { [weak self] _ in
                guard let self, self.activeSendID == sendID else { return }
                self.acknowledgedSendID = sendID
                if draft.wrappedValue == submittedMessage {
                    draft.wrappedValue = ""
                }
            }
    }

    func dismissFailure() {
        failure = nil
    }
}

enum PrivateMessageSendSessions {
    private final class ServiceSessions {
        weak var service: OGSService?
        let accountID: Int?
        private var sessionsByPeerID = [Int: PrivateMessageSendSession]()
        private var recentPeerIDs = [Int]()

        init(service: OGSService) {
            self.service = service
            accountID = service.user?.id
        }

        private func trimIdleSessions(keepingAtMost limit: Int = 32) {
            while recentPeerIDs.count > limit {
                guard let evictionIndex = recentPeerIDs.firstIndex(where: {
                    sessionsByPeerID[$0]?.isSending == false
                }) else { break }
                let evictedPeerID = recentPeerIDs.remove(at: evictionIndex)
                sessionsByPeerID.removeValue(forKey: evictedPeerID)
            }
        }

        func session(for peerID: Int) -> PrivateMessageSendSession {
            if let existing = sessionsByPeerID[peerID] {
                recentPeerIDs.removeAll { $0 == peerID }
                recentPeerIDs.append(peerID)
                return existing
            }

            trimIdleSessions(keepingAtMost: 31)
            let session = PrivateMessageSendSession()
            session.onFinished = { [weak self] in self?.trimIdleSessions() }
            sessionsByPeerID[peerID] = session
            recentPeerIDs.append(peerID)
            return session
        }
    }

    private static var services = [ObjectIdentifier: ServiceSessions]()

    static func session(for ogs: OGSService, peerID: Int) -> PrivateMessageSendSession {
        services = services.filter { $0.value.service != nil }
        let serviceID = ObjectIdentifier(ogs)
        if let sessions = services[serviceID],
           sessions.service === ogs,
           sessions.accountID == ogs.user?.id {
            return sessions.session(for: peerID)
        }
        let sessions = ServiceSessions(service: ogs)
        services[serviceID] = sessions
        return sessions.session(for: peerID)
    }
}
