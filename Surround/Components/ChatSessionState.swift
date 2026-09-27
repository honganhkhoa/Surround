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
    @Published private(set) var isSending = false
    @Published var failure: Failure?
    @Published private(set) var wantsInputFocus = false
    @Published private(set) var composerPresentationID = UUID()
    var scrollAnchor: String?
    var isAtEndOfChat = true
    var shouldScrollToEndAfterKeyboardChange = false

    private var sendCancellable: AnyCancellable?
    private var sendID: UUID?
    private var activeComposerID: UUID?
    private var isGamePresentationActive = true
    private var hasFocusIntent = false
    private var consumedShareFocusRequestID: UUID?
    private(set) var focusRevision = 0

    /// The operation belongs to the game session, never the current TextField.
    func sendMessage(using send: (String) -> AnyPublisher<Void, Error>) {
        guard !isSending, !message.isEmpty else { return }
        let submittedMessage = message
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
                    if self.message == submittedMessage {
                        self.message = ""
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
        focusRevision += 1
        hasFocusIntent = true
        wantsInputFocus = true
    }

    func dismissInput() {
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
        if wantsInputFocus != focused { focusRevision += 1 }
        hasFocusIntent = true
        wantsInputFocus = focused
    }

    /// Explicit game/account changes discard state and invalidate late callbacks.
    func reset() {
        sendID = nil
        sendCancellable?.cancel()
        sendCancellable = nil
        isSending = false
        message = ""
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
        shouldScrollToEndAfterKeyboardChange = false
    }
}
