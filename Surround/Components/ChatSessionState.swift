import Combine
import Foundation

/// One game detail owns this state; adaptive chat views only present it.
final class ChatSessionState: ObservableObject {
    enum Failure: Hashable, Identifiable {
        case messageSend
        case invalidVariation
        case variationUnavailable
        case variationRetryable

        var id: Self { self }

        var title: LocalizedStringResource {
            switch self {
            case .messageSend:
                return LocalizedStringResource("Couldn’t send message")
            case .invalidVariation, .variationUnavailable, .variationRetryable:
                return LocalizedStringResource(
                    "Couldn’t share variation",
                    comment: "Alert title shown when sending an analyzed variation to game chat fails."
                )
            }
        }

        var message: LocalizedStringResource {
            switch self {
            case .invalidVariation:
                return LocalizedStringResource(
                    "This variation is no longer available.",
                    comment: "Message shown when an analyzed variation can no longer be shared because its branch has changed or been removed."
                )
            case .variationUnavailable:
                return LocalizedStringResource(
                    "This variation cannot be shared right now.",
                    comment: "Message shown after a temporary connection or account-state problem prevents an analyzed variation from being shared."
                )
            case .messageSend, .variationRetryable:
                return LocalizedStringResource("Please try again.")
            }
        }
    }

    @Published var message = ""
    private var draftsByChannel: [String: String] = [:]
    private var draftChannel = OGSChatSendChannel.main

    func selectChannel(_ channel: OGSChatSendChannel) {
        guard channel != draftChannel else { return }
        draftsByChannel[draftChannel.rawValue] = message
        draftChannel = channel
        message = draftsByChannel[channel.rawValue] ?? ""
    }
    @Published private(set) var isSending = false
    @Published var failure: Failure?
    @Published private(set) var wantsInputFocus = false
    @Published private(set) var focusRestorationRevision = 0
    @Published private(set) var composerPresentationID = UUID()
    var scrollAnchor: String?
    private(set) var isAtEndOfChat = true

    /// Layout changes can move the visible end without changing reading intent.
    /// Only a user scroll may enter history mode or resume following messages.
    func recordScrollPosition(atEnd: Bool, anchor: String?, userInitiated: Bool) {
        guard userInitiated else { return }
        isAtEndOfChat = atEnd
        if atEnd {
            scrollAnchor = nil
        } else if let anchor {
            scrollAnchor = anchor
        }
    }

    private var sendCancellable: AnyCancellable?
    private var sendID: UUID?
    private var activeComposerID: UUID?
    private var isGamePresentationActive = true
    private var hasFocusIntent = false
    private var consumedShareFocusRequestID: UUID?
    private(set) var focusRevision = 0
    private var sizeTransitionFocus: (id: UUID, revision: Int)?

    /// UIKit may temporarily resign an unchanged field while its window rotates.
    /// Only the focus intent present at the start of that transition survives it.
    func beginWindowSizeTransition() -> UUID? {
        guard isGamePresentationActive, activeComposerID != nil,
              wantsInputFocus else { return nil }
        let id = UUID()
        sizeTransitionFocus = (id, focusRevision)
        return id
    }

    func completeWindowSizeTransition(_ id: UUID, allowsRestoration: Bool = true) {
        guard let transition = sizeTransitionFocus, transition.id == id else { return }
        sizeTransitionFocus = nil
        guard allowsRestoration, isGamePresentationActive, activeComposerID != nil,
              wantsInputFocus, transition.revision == focusRevision else { return }
        focusRestorationRevision += 1
    }

    func preservesInputFocusDuringWindowTransition(composerID: UUID) -> Bool {
        isActiveComposer(composerID) && wantsInputFocus
            && sizeTransitionFocus?.revision == focusRevision
    }

    /// The operation belongs to the game session, never the current TextField.
    func sendMessage(using send: (String) -> AnyPublisher<Void, Error>) {
        guard !isSending, !message.isEmpty else { return }
        let submittedMessage = message
        let submittedChannel = draftChannel
        let requestID = UUID()
        sendID = requestID
        isSending = true
        failure = nil
        sendCancellable = send(submittedMessage)
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self, self.sendID == requestID else { return }
                self.sendID = nil
                self.sendCancellable = nil
                self.isSending = false
                switch completion {
                case .finished:
                    // The user may have started a different draft while sending.
                    if self.draftChannel == submittedChannel {
                        if self.message == submittedMessage { self.message = "" }
                    } else if self.draftsByChannel[submittedChannel.rawValue] == submittedMessage {
                        self.draftsByChannel[submittedChannel.rawValue] = nil
                    }
                case .failure:
                    self.failure = .messageSend
                }
            } receiveValue: { _ in }
    }

    func composerAppeared(
        id: UUID,
        automaticallyFocus: Bool,
        shareFocusRequestID: UUID?
    ) {
        activeComposerID = id
        guard isGamePresentationActive else { return }
        requestShareFocus(shareFocusRequestID)
        if !hasFocusIntent && automaticallyFocus {
            requestInputFocus()
        }
    }

    func composerDisappeared(id: UUID) {
        guard activeComposerID == id else { return }
        activeComposerID = nil
    }

    /// The game screen was left or replaced by Zen, rather than resized.
    /// Keep drafts and requests, but reject focus events from its old composer.
    func gamePresentationDisappeared() {
        guard isGamePresentationActive else { return }
        sizeTransitionFocus = nil
        isGamePresentationActive = false
        activeComposerID = nil
        if hasFocusIntent {
            dismissInput()
        }
        // Navigation can restore UIKit's retained first responder independently
        // of FocusState. Retain the draft, but give the next field a fresh host.
        composerPresentationID = UUID()
    }

    func setGamePresentationActive(_ active: Bool) {
        if active {
            isGamePresentationActive = true
        } else {
            gamePresentationDisappeared()
        }
    }

    func isActiveComposer(_ id: UUID) -> Bool {
        isGamePresentationActive && activeComposerID == id
    }

    func shouldRestoreInputFocus(composerID: UUID, revision: Int) -> Bool {
        isActiveComposer(composerID) && wantsInputFocus
            && focusRevision == revision
    }

    func requestShareFocus(_ requestID: UUID?) {
        guard let requestID,
              requestID != consumedShareFocusRequestID else { return }
        consumedShareFocusRequestID = requestID
        requestInputFocus()
    }

    func requestInputFocus() {
        guard isGamePresentationActive else { return }
        sizeTransitionFocus = nil
        focusRevision += 1
        hasFocusIntent = true
        wantsInputFocus = true
    }

    func dismissInput() {
        sizeTransitionFocus = nil
        focusRevision += 1
        hasFocusIntent = true
        wantsInputFocus = false
    }

    func recordInputFocus(
        _ focused: Bool,
        composerID: UUID,
        expectedRevision: Int? = nil
    ) {
        guard isActiveComposer(composerID),
              expectedRevision == nil || expectedRevision == focusRevision else {
            return
        }
        if !focused && preservesInputFocusDuringWindowTransition(composerID: composerID) {
            return
        }
        if wantsInputFocus != focused { focusRevision += 1 }
        hasFocusIntent = true
        wantsInputFocus = focused
    }

    /// Explicit game/account changes discard state and invalidate late callbacks.
    func reset() {
        sizeTransitionFocus = nil
        sendID = nil
        sendCancellable?.cancel()
        sendCancellable = nil
        isSending = false
        message = ""
        draftsByChannel.removeAll()
        draftChannel = .main
        failure = nil
        // Account changes can leave this route mounted, but its old field and
        // queued focus callbacks must not carry over to the new session.
        focusRevision += 1
        hasFocusIntent = false
        consumedShareFocusRequestID = nil
        wantsInputFocus = false
        activeComposerID = nil
        composerPresentationID = UUID()
        scrollAnchor = nil
        isAtEndOfChat = true
    }
}
