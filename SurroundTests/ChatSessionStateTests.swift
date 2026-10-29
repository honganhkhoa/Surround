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

    func testGameSwitchingRetainsIndependentGameAndChannelDrafts() {
        let store = GameChatSessionStore()
        let first = store.session(for: .OGS(101), accountID: 7)
        first.message = "First game chat"
        first.selectChannel(.personal)
        first.message = "First game personal note"
        store.deactivate(gameID: .OGS(101), accountID: 7)

        let second = store.session(for: .OGS(102), accountID: 7)
        XCTAssertFalse(first === second)
        XCTAssertEqual(second.message, "")
        second.message = "Second game chat"
        second.selectChannel(.personal)
        XCTAssertEqual(second.message, "")
        second.message = "Second game personal note"

        let returned = store.session(for: .OGS(101), accountID: 7)
        XCTAssertTrue(first === returned)
        // Game Detail opens the main channel when switching games.
        returned.selectChannel(.main)
        XCTAssertEqual(returned.message, "First game chat")
        returned.selectChannel(.personal)
        XCTAssertEqual(returned.message, "First game personal note")
        second.selectChannel(.main)
        XCTAssertEqual(second.message, "Second game chat")
        second.selectChannel(.personal)
        XCTAssertEqual(second.message, "Second game personal note")
    }

    func testSwitchingGamesDeactivatesOldComposerWithoutRestoringFocus() {
        let store = GameChatSessionStore()
        let first = store.session(for: .OGS(101), accountID: 7)
        let oldComposer = UUID()
        first.composerAppeared(id: oldComposer, shareFocusRequestID: nil)
        first.requestInputFocus()
        first.message = "Unsent first game draft"
        let oldRevision = first.focusRevision
        store.deactivate(gameID: .OGS(101), accountID: 7)
        first.recordInputFocus(true, composerID: oldComposer,
                               expectedRevision: oldRevision)

        let second = store.session(for: .OGS(102), accountID: 7)
        XCTAssertFalse(first.isActiveComposer(oldComposer))
        XCTAssertFalse(first.wantsInputFocus)
        XCTAssertFalse(second.wantsInputFocus)
        XCTAssertEqual(second.message, "")

        let returned = store.session(for: .OGS(101), accountID: 7)
        returned.setGamePresentationActive(true)
        returned.composerAppeared(id: UUID(), shareFocusRequestID: nil)
        XCTAssertEqual(returned.message, "Unsent first game draft")
        XCTAssertFalse(returned.wantsInputFocus)
        XCTAssertFalse(returned.shouldRestoreInputFocus(
            composerID: oldComposer, revision: oldRevision
        ))
    }

    func testPendingSendStaysWithItsGameAndStillPreventsDuplicateSubmission() {
        let store = GameChatSessionStore()
        let first = store.session(for: .OGS(101), accountID: 7)
        let originalComposer = UUID()
        first.composerAppeared(id: originalComposer, shareFocusRequestID: nil)
        let response = PassthroughSubject<Void, Error>()
        var submissions = [String]()
        first.message = "First game message"
        let send: (String) -> AnyPublisher<Void, Error> = { message in
            submissions.append(message)
            return response.eraseToAnyPublisher()
        }
        first.sendMessage(from: originalComposer, using: send)
        store.deactivate(gameID: .OGS(101), accountID: 7)
        let second = store.session(for: .OGS(102), accountID: 7)
        second.message = "Second game unsent draft"

        let returned = store.session(for: .OGS(101), accountID: 7)
        returned.setGamePresentationActive(true)
        let replacementComposer = UUID()
        returned.composerAppeared(id: replacementComposer, shareFocusRequestID: nil)
        returned.sendMessage(from: replacementComposer, using: send)
        XCTAssertEqual(submissions, ["First game message"])
        XCTAssertTrue(returned.isSending)
        response.send(())
        drainMainQueue()

        XCTAssertFalse(returned.isSending)
        XCTAssertEqual(returned.message, "")
        XCTAssertEqual(second.message, "Second game unsent draft")
        XCTAssertNil(second.failure)
    }

    func testSendFailureWhileAnotherGameIsVisibleRetainsOriginalDraftAndRetry() {
        let store = GameChatSessionStore()
        let first = store.session(for: .OGS(101), accountID: 7)
        let response = PassthroughSubject<Void, Error>()
        first.message = "Retry only in first game"
        first.sendMessage { _ in response.eraseToAnyPublisher() }
        store.deactivate(gameID: .OGS(101), accountID: 7)
        let second = store.session(for: .OGS(102), accountID: 7)
        second.message = "Leave second game alone"
        response.send(completion: .failure(SendError.unavailable))
        drainMainQueue()

        let returned = store.session(for: .OGS(101), accountID: 7)
        XCTAssertEqual(returned.message, "Retry only in first game")
        XCTAssertEqual(returned.failure, .messageSend)
        XCTAssertFalse(returned.isSending)
        XCTAssertEqual(second.message, "Leave second game alone")
        XCTAssertNil(second.failure)
        let retry = PassthroughSubject<Void, Error>()
        returned.sendMessage { message in
            XCTAssertEqual(message, "Retry only in first game")
            return retry.eraseToAnyPublisher()
        }
        retry.send(())
        drainMainQueue()
        XCTAssertEqual(returned.message, "")
    }

    func testAccountChangeDiscardsEveryOldGameAndRejectsQueuedCompletion() {
        let store = GameChatSessionStore()
        let first = store.session(for: .OGS(101), accountID: 7)
        let second = store.session(for: .OGS(102), accountID: 7)
        let response = PassthroughSubject<Void, Error>()
        let composer = UUID()
        first.composerAppeared(id: composer, shareFocusRequestID: nil)
        first.requestInputFocus()
        first.message = "Old account pending message"
        first.sendMessage { _ in response.eraseToAnyPublisher() }
        second.message = "Old account second game"
        response.send(())

        // A new render may acquire its session before the account observer runs.
        let newAccount = store.session(for: .OGS(101), accountID: 8)
        XCTAssertFalse(newAccount === first)
        XCTAssertEqual(newAccount.message, "")
        newAccount.message = "New account draft"
        store.discardOtherAccounts(keeping: 8)
        first.recordInputFocus(true, composerID: composer)
        drainMainQueue()

        XCTAssertEqual(first.message, "")
        XCTAssertEqual(second.message, "")
        XCTAssertFalse(first.isSending)
        XCTAssertFalse(first.wantsInputFocus)
        XCTAssertEqual(newAccount.message, "New account draft")
        XCTAssertNil(newAccount.failure)
        let oldAccountAgain = store.session(for: .OGS(101), accountID: 7)
        XCTAssertFalse(oldAccountAgain === first)
        XCTAssertEqual(oldAccountAgain.message, "")
    }

    func testLogoutDiscardsSignedInGameDrafts() {
        let store = GameChatSessionStore()
        let signedIn = store.session(for: .OGS(101), accountID: 7)
        signedIn.message = "Signed-in draft"
        signedIn.selectChannel(.personal)
        signedIn.message = "Private note"
        store.discardOtherAccounts(keeping: nil)

        XCTAssertEqual(signedIn.message, "")
        signedIn.selectChannel(.main)
        XCTAssertEqual(signedIn.message, "")
        XCTAssertEqual(store.session(for: .OGS(101), accountID: nil).message, "")
        XCTAssertEqual(store.session(for: .OGS(101), accountID: 7).message, "")
    }

    func testStaleComposerCannotSubmitRetainedPersonalDraftAfterSwitchOrReturn() {
        let store = GameChatSessionStore()
        let first = store.session(for: .OGS(101), accountID: 7)
        let oldComposer = UUID()
        first.composerAppeared(id: oldComposer, shareFocusRequestID: nil)
        first.selectChannel(.personal)
        first.message = "Personal draft must never become public"
        var submitted = [String]()
        let send: (String) -> AnyPublisher<Void, Error> = { message in
            submitted.append(message)
            return Empty().eraseToAnyPublisher()
        }

        store.deactivate(gameID: .OGS(101), accountID: 7)
        let second = store.session(for: .OGS(102), accountID: 7)
        second.composerAppeared(id: UUID(), shareFocusRequestID: nil)
        second.message = "Second game draft"
        first.sendMessage(from: oldComposer, using: send)
        XCTAssertTrue(submitted.isEmpty)
        XCTAssertEqual(first.message, "Personal draft must never become public")
        XCTAssertEqual(second.message, "Second game draft")

        first.setGamePresentationActive(true)
        first.selectChannel(.main)
        first.composerAppeared(id: UUID(), shareFocusRequestID: nil)
        first.message = "Newer first-game main draft"
        first.sendMessage(from: oldComposer, using: send)
        XCTAssertTrue(submitted.isEmpty)
        XCTAssertEqual(first.message, "Newer first-game main draft")
        first.selectChannel(.personal)
        XCTAssertEqual(first.message, "Personal draft must never become public")
    }

    func testDiscardedAccountComposerCannotSubmitAfterItsGameIsReused() {
        let store = GameChatSessionStore()
        let old = store.session(for: .OGS(101), accountID: 7)
        let oldComposer = UUID()
        old.composerAppeared(id: oldComposer, shareFocusRequestID: nil)
        old.message = "Old account draft"
        store.discardOtherAccounts(keeping: 8)
        let current = store.session(for: .OGS(101), accountID: 8)
        let currentComposer = UUID()
        current.composerAppeared(id: currentComposer, shareFocusRequestID: nil)
        current.message = "Current account draft"
        var submitted = [String]()
        old.sendMessage(from: oldComposer) { message in
            submitted.append(message)
            return Empty().eraseToAnyPublisher()
        }
        current.sendMessage(from: oldComposer) { message in
            submitted.append(message)
            return Empty().eraseToAnyPublisher()
        }
        XCTAssertTrue(submitted.isEmpty)
        XCTAssertEqual(current.message, "Current account draft")
        XCTAssertTrue(current.isActiveComposer(currentComposer))
    }

    func testOldWindowTransitionCompletionCannotRestoreAnotherGamesFocus() throws {
        let store = GameChatSessionStore()
        let first = store.session(for: .OGS(101), accountID: 7)
        first.composerAppeared(id: UUID(), shareFocusRequestID: nil)
        first.requestInputFocus()
        let oldTransition = try XCTUnwrap(first.beginWindowSizeTransition())
        store.deactivate(gameID: .OGS(101), accountID: 7)

        let second = store.session(for: .OGS(102), accountID: 7)
        second.composerAppeared(id: UUID(), shareFocusRequestID: nil)
        second.requestInputFocus()
        let currentTransition = try XCTUnwrap(second.beginWindowSizeTransition())
        first.completeWindowSizeTransition(oldTransition)
        XCTAssertFalse(first.wantsInputFocus)
        XCTAssertEqual(first.focusRestorationRevision, 0)
        XCTAssertEqual(second.focusRestorationRevision, 0)

        second.completeWindowSizeTransition(currentTransition)
        XCTAssertTrue(second.wantsInputFocus)
        XCTAssertEqual(second.focusRestorationRevision, 1)
    }

    func testReturningToLatestChatKeepsGameDraftAndPendingSend() {
        let store = GameChatSessionStore()
        let first = store.session(for: .OGS(101), accountID: 7)
        first.message = "First game message"
        let response = PassthroughSubject<Void, Error>()
        first.sendMessage { _ in response.eraseToAnyPublisher() }
        first.recordScrollPosition(atEnd: false, anchor: "older-first-game-message",
                                   userInitiated: true)
        store.deactivate(gameID: .OGS(101), accountID: 7)
        let second = store.session(for: .OGS(102), accountID: 7)
        second.message = "Second game draft"

        let returned = store.session(for: .OGS(101), accountID: 7)
        returned.resetReadingPosition()
        XCTAssertTrue(returned.isAtEndOfChat)
        XCTAssertNil(returned.scrollAnchor)
        XCTAssertEqual(returned.message, "First game message")
        XCTAssertTrue(returned.isSending)
        XCTAssertEqual(second.message, "Second game draft")

        response.send(())
        drainMainQueue()
        XCTAssertFalse(returned.isSending)
        XCTAssertEqual(returned.message, "")
        XCTAssertEqual(second.message, "Second game draft")
    }

    func testRouteOwnerReceivesFocusChangesWithoutWindowGeometryChanges() {
        let store = GameChatSessionStore()
        let session = store.session(for: .OGS(101), accountID: 7)
        session.composerAppeared(id: UUID(), shareFocusRequestID: nil)
        var ownerInvalidations = 0
        let observation = store.objectWillChange.sink { ownerInvalidations += 1 }
        defer { observation.cancel() }

        session.requestInputFocus()
        XCTAssertTrue(session.wantsInputFocus)
        XCTAssertGreaterThan(ownerInvalidations, 0,
                             "The toolbar owner must update even without keyboard geometry events.")
        let afterFocus = ownerInvalidations
        session.dismissInput()
        XCTAssertFalse(session.wantsInputFocus)
        XCTAssertGreaterThan(ownerInvalidations, afterFocus)
    }

    func testDiscardedAccountSessionsNoLongerInvalidateRouteOwner() {
        let store = GameChatSessionStore()
        let discarded = store.session(for: .OGS(101), accountID: 7)
        let kept = store.session(for: .OGS(101), accountID: 8)
        var ownerInvalidations = 0
        let observation = store.objectWillChange.sink { ownerInvalidations += 1 }
        defer { observation.cancel() }
        store.discardOtherAccounts(keeping: 8)
        let afterDiscard = ownerInvalidations

        // An obsolete field can still retain its old session after logout.
        discarded.message = "Obsolete field update"
        discarded.failure = .messageSend
        XCTAssertEqual(ownerInvalidations, afterDiscard)
        kept.composerAppeared(id: UUID(), shareFocusRequestID: nil)
        kept.requestInputFocus()
        XCTAssertGreaterThan(ownerInvalidations, afterDiscard)
    }

    func testRetainedSessionObservationDoesNotRetainItsRouteStore() {
        weak var releasedStore: GameChatSessionStore?
        var survivingSession: ChatSessionState?
        do {
            let store = GameChatSessionStore()
            releasedStore = store
            survivingSession = store.session(for: .OGS(101), accountID: 7)
        }
        XCTAssertNil(releasedStore)
        survivingSession?.message = "A field can briefly outlive its route"
        XCTAssertEqual(survivingSession?.message, "A field can briefly outlive its route")
    }

    func testInactiveSessionAndPendingSendOutliveAllPresentationReferences() {
        let store = GameChatSessionStore()
        let response = PassthroughSubject<Void, Error>()
        weak var retainedSession: ChatSessionState?
        var submissions = [String]()
        let send: (String) -> AnyPublisher<Void, Error> = { text in
            submissions.append(text)
            return response.eraseToAnyPublisher()
        }
        do {
            let presented = store.session(for: .OGS(101), accountID: 7)
            retainedSession = presented
            let composer = UUID()
            presented.composerAppeared(id: composer, shareFocusRequestID: nil)
            presented.message = "Pending main message"
            presented.sendMessage(from: composer, using: send)
            presented.selectChannel(.personal)
            presented.message = "Unsent Personal draft"
            store.deactivate(gameID: .OGS(101), accountID: 7)
        }

        XCTAssertNotNil(retainedSession)
        let reopened = store.session(for: .OGS(101), accountID: 7)
        XCTAssertTrue(reopened === retainedSession)
        XCTAssertEqual(reopened.message, "Unsent Personal draft")
        XCTAssertTrue(reopened.isSending)
        XCTAssertFalse(reopened.wantsInputFocus)
        reopened.setGamePresentationActive(true)
        let replacementComposer = UUID()
        reopened.composerAppeared(id: replacementComposer, shareFocusRequestID: nil)
        reopened.selectChannel(.main)
        XCTAssertEqual(reopened.message, "Pending main message")
        reopened.sendMessage(from: replacementComposer, using: send)
        XCTAssertEqual(submissions, ["Pending main message"])
        reopened.selectChannel(.personal)

        response.send(())
        drainMainQueue()
        XCTAssertFalse(reopened.isSending)
        XCTAssertEqual(reopened.message, "Unsent Personal draft")
        reopened.selectChannel(.main)
        XCTAssertEqual(reopened.message, "")
    }

    func testAccountCleanupWithoutPresentedGameCancelsAndReleasesOldSessions() {
        let store = GameChatSessionStore()
        let response = PassthroughSubject<Void, Error>()
        var cancellations = 0
        weak var oldFirst: ChatSessionState?
        weak var oldSecond: ChatSessionState?
        do {
            let first = store.session(for: .OGS(101), accountID: 7)
            let second = store.session(for: .OGS(102), accountID: 7)
            oldFirst = first
            oldSecond = second
            first.message = "Old account pending draft"
            first.sendMessage { _ in
                response.handleEvents(receiveCancel: { cancellations += 1 })
                    .eraseToAnyPublisher()
            }
            second.selectChannel(.personal)
            second.message = "Old account Personal draft"
            store.deactivate(gameID: .OGS(101), accountID: 7)
            store.deactivate(gameID: .OGS(102), accountID: 7)
        }
        XCTAssertNotNil(oldFirst)
        XCTAssertNotNil(oldSecond)
        let current = store.session(for: .OGS(101), accountID: 8)
        current.message = "Current account draft"

        // The stable owner performs this while Home has no game presented.
        store.discardOtherAccounts(keeping: 8)
        XCTAssertEqual(cancellations, 1)
        XCTAssertNil(oldFirst)
        XCTAssertNil(oldSecond)
        response.send(())
        drainMainQueue()
        XCTAssertEqual(current.message, "Current account draft")
        XCTAssertNil(current.failure)
    }

    func testWindowStoreReleaseCancelsAndReleasesInactivePendingSession() {
        let response = PassthroughSubject<Void, Error>()
        var cancellations = 0
        weak var releasedStore: GameChatSessionStore?
        weak var releasedSession: ChatSessionState?
        do {
            let windowStore = GameChatSessionStore()
            releasedStore = windowStore
            let presented = windowStore.session(for: .OGS(101), accountID: 7)
            releasedSession = presented
            presented.message = "Pending while leaving the window"
            presented.sendMessage { _ in
                response.handleEvents(receiveCancel: { cancellations += 1 })
                    .eraseToAnyPublisher()
            }
            windowStore.deactivate(gameID: .OGS(101), accountID: 7)
        }
        XCTAssertNil(releasedStore)
        XCTAssertNil(releasedSession)
        XCTAssertEqual(cancellations, 1)
    }

    private func drainMainQueue() {
        let drained = expectation(description: "Deliver scheduled send completion")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }
}
