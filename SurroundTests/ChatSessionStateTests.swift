import Combine
import XCTest

final class ChatSessionStateTests: XCTestCase {
    private enum SendError: Error { case unavailable }

    func testChannelDraftsRemainIndependentAcrossSwitches() {
        let session = ChatSessionState()
        session.message = "Public draft"
        session.selectChannel(.personal)
        XCTAssertEqual(session.message, "")
        session.message = "Private note"
        session.selectChannel(.main)
        XCTAssertEqual(session.message, "Public draft")
        session.selectChannel(.personal)
        XCTAssertEqual(session.message, "Private note")
        session.reset()
        session.selectChannel(.personal)
        XCTAssertEqual(session.message, "")
    }

    func testSendCompletionClearsOnlyTheSubmittedChannelDraft() {
        let session = ChatSessionState()
        let response = PassthroughSubject<Void, Error>()
        session.message = "Public message"
        session.sendMessage { _ in response.eraseToAnyPublisher() }
        session.selectChannel(.personal)
        session.message = "Private note"
        response.send(())
        drainMainQueue()
        XCTAssertEqual(session.message, "Private note")
        session.selectChannel(.main)
        XCTAssertEqual(session.message, "")
    }

    func testPendingSendSurvivesComposerReplacementAndPreventsDuplicate() {
        let session = ChatSessionState()
        let response = PassthroughSubject<Void, Error>()
        let firstComposer = UUID()
        session.composerAppeared(id: firstComposer, shareFocusRequestID: nil)
        session.message = "Retain this draft"
        var submissions = [String]()
        let send: (String) -> AnyPublisher<Void, Error> = { message in
            submissions.append(message)
            return response.eraseToAnyPublisher()
        }

        session.sendMessage(using: send)
        session.composerDisappeared(id: firstComposer)
        session.composerAppeared(id: UUID(), shareFocusRequestID: nil)
        session.sendMessage(using: send)

        XCTAssertTrue(session.isSending)
        XCTAssertEqual(session.message, "Retain this draft")
        XCTAssertEqual(submissions, ["Retain this draft"])

        response.send(())
        drainMainQueue()
        XCTAssertFalse(session.isSending)
        XCTAssertEqual(session.message, "")
        XCTAssertNil(session.failure)
    }

    func testFailedSendRetainsMessageAndErrorForReplacementComposer() {
        let session = ChatSessionState()
        let response = PassthroughSubject<Void, Error>()
        session.message = "Retry after folding"
        session.sendMessage { _ in response.eraseToAnyPublisher() }
        response.send(completion: .failure(SendError.unavailable))
        drainMainQueue()

        session.composerAppeared(id: UUID(), shareFocusRequestID: nil)
        XCTAssertFalse(session.isSending)
        XCTAssertEqual(session.message, "Retry after folding")
        XCTAssertEqual(session.failure, .messageSend)

        let retry = PassthroughSubject<Void, Error>()
        session.sendMessage { message in
            XCTAssertEqual(message, "Retry after folding")
            return retry.eraseToAnyPublisher()
        }
        XCTAssertTrue(session.isSending)
        XCTAssertNil(session.failure)
        retry.send(())
        drainMainQueue()
        XCTAssertEqual(session.message, "")
    }

    func testSuccessfulSendDoesNotEraseNewerDraft() {
        let session = ChatSessionState()
        let response = PassthroughSubject<Void, Error>()
        session.message = "First message"
        session.sendMessage { _ in response.eraseToAnyPublisher() }
        session.message = "Second message still being edited"
        response.send(())
        drainMainQueue()

        XCTAssertFalse(session.isSending)
        XCTAssertEqual(session.message, "Second message still being edited")
    }

    func testResetRejectsQueuedCompletionFromPreviousGame() {
        let session = ChatSessionState()
        let oldResponse = PassthroughSubject<Void, Error>()
        session.message = "Old game"
        session.sendMessage { _ in oldResponse.eraseToAnyPublisher() }
        oldResponse.send(())

        session.reset()
        let newResponse = PassthroughSubject<Void, Error>()
        session.message = "New game"
        session.sendMessage { _ in newResponse.eraseToAnyPublisher() }
        drainMainQueue()

        XCTAssertTrue(session.isSending)
        XCTAssertEqual(session.message, "New game")
        XCTAssertNil(session.failure)

        newResponse.send(completion: .failure(SendError.unavailable))
        drainMainQueue()
        XCTAssertFalse(session.isSending)
        XCTAssertEqual(session.message, "New game")
        XCTAssertEqual(session.failure, .messageSend)
    }

    func testDismissedShareDoesNotRefocusUntilAnotherShareIsRequested() {
        let session = ChatSessionState()
        let request = UUID()
        let firstComposer = UUID()
        session.composerAppeared(id: firstComposer, shareFocusRequestID: request)
        XCTAssertTrue(session.wantsInputFocus)
        session.dismissInput()
        session.composerDisappeared(id: firstComposer)
        session.composerAppeared(id: UUID(), shareFocusRequestID: request)
        XCTAssertFalse(session.wantsInputFocus)

        session.requestShareFocus(UUID())
        XCTAssertTrue(session.wantsInputFocus)
    }

    func testFocusedComposerRestoresWithoutOldPresenterDismissal() {
        let session = ChatSessionState()
        let presentationID = session.composerPresentationID
        let oldComposer = UUID()
        session.composerAppeared(id: oldComposer, shareFocusRequestID: nil)
        session.recordInputFocus(true, composerID: oldComposer)
        session.composerDisappeared(id: oldComposer)
        let replacement = UUID()
        session.composerAppeared(id: replacement, shareFocusRequestID: nil)
        session.recordInputFocus(false, composerID: oldComposer)
        session.composerDisappeared(id: oldComposer)

        XCTAssertTrue(session.wantsInputFocus)
        XCTAssertTrue(session.isActiveComposer(replacement))
        XCTAssertEqual(session.composerPresentationID, presentationID)
    }

    func testNavigationSuspendsFocusWithoutDiscardingDraftOrPendingSend() {
        let session = ChatSessionState()
        let composer = UUID()
        session.composerAppeared(id: composer, shareFocusRequestID: nil)
        session.recordInputFocus(true, composerID: composer)
        session.message = "Finish this thought after viewing a profile"
        session.scrollAnchor = "earlier-message"
        let response = PassthroughSubject<Void, Error>()
        session.sendMessage { _ in response.eraseToAnyPublisher() }
        let oldRevision = session.focusRevision

        session.gamePresentationDisappeared()
        // Lifecycle and focus callbacks can arrive in either order.
        session.recordInputFocus(true, composerID: composer)
        session.recordInputFocus(false, composerID: composer)
        session.composerDisappeared(id: composer)
        session.setGamePresentationActive(true)
        session.composerAppeared(id: composer, shareFocusRequestID: nil)
        session.recordInputFocus(
            false, composerID: composer, expectedRevision: oldRevision
        )

        XCTAssertFalse(session.wantsInputFocus)
        XCTAssertEqual(session.message, "Finish this thought after viewing a profile")
        XCTAssertEqual(session.scrollAnchor, "earlier-message")
        XCTAssertTrue(session.isSending)

        response.send(completion: .failure(SendError.unavailable))
        drainMainQueue()
        XCTAssertFalse(session.isSending)
        XCTAssertEqual(session.failure, .messageSend)
        XCTAssertEqual(session.message, "Finish this thought after viewing a profile")
    }

    func testNavigationDoesNotRepeatShareFocusButANewShareStillFocuses() {
        let session = ChatSessionState()
        let shareRequest = UUID()
        session.composerAppeared(id: UUID(), shareFocusRequestID: shareRequest)
        XCTAssertTrue(session.wantsInputFocus)
        session.gamePresentationDisappeared()
        session.setGamePresentationActive(true)
        session.composerAppeared(id: UUID(), shareFocusRequestID: shareRequest)
        XCTAssertFalse(session.wantsInputFocus)

        session.requestShareFocus(UUID())
        XCTAssertTrue(session.wantsInputFocus)
    }

    func testExplicitResumeRefocusesDismissedShareWithoutChangingReplacementPolicy() {
        let session = ChatSessionState()
        let shareRequest = UUID()
        let originalComposer = UUID()
        session.composerAppeared(id: originalComposer, shareFocusRequestID: shareRequest)
        session.dismissInput()
        session.composerDisappeared(id: originalComposer)

        // A fold alone retains the user's keyboard dismissal.
        let replacement = UUID()
        session.composerAppeared(id: replacement, shareFocusRequestID: shareRequest)
        XCTAssertFalse(session.wantsInputFocus)
        session.gamePresentationDisappeared()

        // Explicitly returning from Zen can resume the pending share task.
        session.setGamePresentationActive(true)
        session.requestInputFocus()
        session.composerAppeared(id: UUID(), shareFocusRequestID: shareRequest)
        XCTAssertTrue(session.wantsInputFocus)

        session.dismissInput()
        session.composerAppeared(id: UUID(), shareFocusRequestID: shareRequest)
        XCTAssertFalse(session.wantsInputFocus)
    }

    func testNavigationReplacesNativeComposerOnceAndRejectsHiddenFocusEvents() {
        let session = ChatSessionState()
        let oldComposer = UUID()
        let oldPresentation = session.composerPresentationID
        session.composerAppeared(id: oldComposer, shareFocusRequestID: nil)
        session.recordInputFocus(true, composerID: oldComposer)
        session.message = "Draft retained through profile navigation"

        // The profile action invalidates first; route and disappearance follow.
        session.gamePresentationDisappeared()
        let returningPresentation = session.composerPresentationID
        XCTAssertNotEqual(returningPresentation, oldPresentation)
        session.setGamePresentationActive(false)
        session.gamePresentationDisappeared()
        XCTAssertEqual(session.composerPresentationID, returningPresentation)

        let returningComposer = UUID()
        session.composerAppeared(id: returningComposer, shareFocusRequestID: nil)
        session.recordInputFocus(true, composerID: oldComposer)
        session.recordInputFocus(true, composerID: returningComposer)
        session.requestInputFocus()
        XCTAssertFalse(session.wantsInputFocus)

        // The replacement may mount before the route becomes active again.
        session.setGamePresentationActive(true)
        XCTAssertFalse(session.wantsInputFocus)
        XCTAssertEqual(session.message, "Draft retained through profile navigation")
        session.recordInputFocus(true, composerID: returningComposer)
        XCTAssertTrue(session.wantsInputFocus)
    }

    func testQueuedFocusRestoreRequiresCurrentComposerAndRevision() {
        let session = ChatSessionState()
        let composer = UUID()
        session.composerAppeared(id: composer, shareFocusRequestID: nil)
        session.recordInputFocus(true, composerID: composer)
        let queuedRevision = session.focusRevision
        XCTAssertTrue(session.shouldRestoreInputFocus(
            composerID: composer, revision: queuedRevision
        ))

        session.dismissInput()
        session.requestInputFocus()
        XCTAssertFalse(session.shouldRestoreInputFocus(
            composerID: composer, revision: queuedRevision
        ))
        XCTAssertTrue(session.shouldRestoreInputFocus(
            composerID: composer, revision: session.focusRevision
        ))

        session.gamePresentationDisappeared()
        session.setGamePresentationActive(true)
        let replacement = UUID()
        session.composerAppeared(id: replacement, shareFocusRequestID: nil)
        session.requestInputFocus()
        XCTAssertFalse(session.shouldRestoreInputFocus(
            composerID: composer, revision: session.focusRevision
        ))
        XCTAssertTrue(session.shouldRestoreInputFocus(
            composerID: replacement, revision: session.focusRevision
        ))
    }

    func testDelayedFocusLossCannotOverrideNewShareRequest() {
        let session = ChatSessionState()
        let composer = UUID()
        session.composerAppeared(id: composer, shareFocusRequestID: nil)
        session.recordInputFocus(true, composerID: composer)
        let oldRevision = session.focusRevision
        session.requestShareFocus(UUID())
        session.recordInputFocus(
            false, composerID: composer, expectedRevision: oldRevision
        )
        XCTAssertTrue(session.wantsInputFocus)

        session.recordInputFocus(
            false, composerID: composer, expectedRevision: session.focusRevision
        )
        XCTAssertFalse(session.wantsInputFocus)
    }

    func testWindowTransitionPreservesFocusedComposerThroughTransientLoss() throws {
        let session = ChatSessionState()
        let composer = UUID()
        session.composerAppeared(id: composer, shareFocusRequestID: nil)
        session.recordInputFocus(true, composerID: composer)
        session.message = "Unsent through rotation"
        let transition = try XCTUnwrap(session.beginWindowSizeTransition())

        // UIKit can resign, restore, then resign the same field during rotation.
        session.recordInputFocus(false, composerID: composer)
        session.recordInputFocus(true, composerID: composer)
        session.recordInputFocus(false, composerID: composer)
        XCTAssertTrue(session.wantsInputFocus)
        XCTAssertEqual(session.focusRestorationRevision, 0)

        session.completeWindowSizeTransition(transition)
        XCTAssertEqual(session.focusRestorationRevision, 1)
        XCTAssertEqual(session.message, "Unsent through rotation")
        session.completeWindowSizeTransition(transition)
        XCTAssertEqual(session.focusRestorationRevision, 1, "Completion only restores once")
        session.recordInputFocus(false, composerID: composer)
        XCTAssertFalse(session.wantsInputFocus, "Ordinary focus loss after rotation still dismisses")
    }

    func testWindowTransitionRestorationIsCancelledByDismissalNavigationOrReset() throws {
        let interruptions: [(String, (ChatSessionState) -> Void)] = [
            ("explicit dismissal", { $0.dismissInput() }),
            ("navigation", { $0.gamePresentationDisappeared() }),
            ("game or account reset", { $0.reset() }),
        ]
        for (name, interrupt) in interruptions {
            let session = ChatSessionState()
            let composer = UUID()
            session.composerAppeared(id: composer, shareFocusRequestID: nil)
            session.recordInputFocus(true, composerID: composer)
            let transition = try XCTUnwrap(session.beginWindowSizeTransition())
            interrupt(session)
            session.completeWindowSizeTransition(transition)
            XCTAssertFalse(session.wantsInputFocus, name)
            XCTAssertEqual(session.focusRestorationRevision, 0, name)
        }
    }

    func testWindowTransitionDoesNotFocusAnUnfocusedComposer() {
        let session = ChatSessionState()
        session.composerAppeared(id: UUID(), shareFocusRequestID: nil)
        XCTAssertNil(session.beginWindowSizeTransition())
        XCTAssertFalse(session.wantsInputFocus)
        XCTAssertEqual(session.focusRestorationRevision, 0)
    }

    func testNewShareFocusRequestSupersedesWindowTransitionRestoration() throws {
        let session = ChatSessionState()
        let composer = UUID()
        session.composerAppeared(id: composer, shareFocusRequestID: nil)
        session.recordInputFocus(true, composerID: composer)
        let transition = try XCTUnwrap(session.beginWindowSizeTransition())
        session.requestShareFocus(UUID())
        session.completeWindowSizeTransition(transition)
        XCTAssertTrue(session.wantsInputFocus)
        XCTAssertEqual(session.focusRestorationRevision, 0)
    }

    func testWindowLosingKeyStatusEndsGuardWithoutRestoringFocus() throws {
        let session = ChatSessionState()
        let composer = UUID()
        session.composerAppeared(id: composer, shareFocusRequestID: nil)
        session.recordInputFocus(true, composerID: composer)
        let transition = try XCTUnwrap(session.beginWindowSizeTransition())
        session.completeWindowSizeTransition(transition, allowsRestoration: false)
        XCTAssertEqual(session.focusRestorationRevision, 0)
        session.recordInputFocus(false, composerID: composer)
        XCTAssertFalse(session.wantsInputFocus)
    }

    func testKeyboardAndViewportResizeCannotStopFollowingLatestMessages() {
        let session = ChatSessionState()
        // Opening a keyboard can hide the end marker several times while the
        // viewport and lazy content settle, without a user scrolling history.
        for _ in 0..<3 {
            session.recordScrollPosition(
                atEnd: false, anchor: "earlier-message", userInitiated: false
            )
        }
        XCTAssertTrue(session.isAtEndOfChat)
        XCTAssertNil(session.scrollAnchor)
    }

    func testOlderReadingPositionSurvivesKeyboardDismissalAndNewMessages() {
        let session = ChatSessionState()
        session.recordScrollPosition(
            atEnd: false, anchor: "move-42", userInitiated: true
        )
        // A larger viewport can temporarily expose the bottom, and an append
        // can hide it again. Neither event should replace the user's bookmark.
        session.recordScrollPosition(
            atEnd: true, anchor: "latest-message", userInitiated: false
        )
        session.recordScrollPosition(
            atEnd: false, anchor: "move-57", userInitiated: false
        )
        XCTAssertFalse(session.isAtEndOfChat)
        XCTAssertEqual(session.scrollAnchor, "move-42")
    }

    func testScrollingBackToLatestMessageResumesFollowingAcrossReplacement() {
        let session = ChatSessionState()
        session.recordScrollPosition(
            atEnd: false, anchor: "move-42", userInitiated: true
        )
        session.recordScrollPosition(
            atEnd: true, anchor: "latest-message", userInitiated: true
        )
        session.recordScrollPosition(
            atEnd: false, anchor: nil, userInitiated: false
        )
        XCTAssertTrue(session.isAtEndOfChat)
        XCTAssertNil(session.scrollAnchor)
    }

    func testTransientMissingVisibleRowsRetainOlderBookmark() {
        let session = ChatSessionState()
        session.recordScrollPosition(
            atEnd: false, anchor: "move-42", userInitiated: true
        )
        session.recordScrollPosition(
            atEnd: false, anchor: nil, userInitiated: true
        )
        XCTAssertFalse(session.isAtEndOfChat)
        XCTAssertEqual(session.scrollAnchor, "move-42")
        session.reset()
        XCTAssertTrue(session.isAtEndOfChat)
        XCTAssertNil(session.scrollAnchor)
    }

    private func drainMainQueue() {
        let drained = expectation(description: "Deliver scheduled send completion")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }
}
