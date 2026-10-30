import Combine
import XCTest

final class ChatSessionStateTests: XCTestCase {
    private enum SendError: Error { case unavailable }

    func testChannelDraftsRemainIndependentAcrossSwitches() {
        let session = ChatSessionState()
        session.setMessage("Public draft", in: .main)
        XCTAssertEqual(session.message(in: .personal), "")
        session.setMessage("Private note", in: .personal)
        XCTAssertEqual(session.message(in: .main), "Public draft")
        XCTAssertEqual(session.message(in: .personal), "Private note")
        session.reset()
        XCTAssertEqual(session.message(in: .personal), "")
    }

    func testSendCompletionClearsOnlyTheSubmittedChannelDraft() {
        let session = ChatSessionState()
        let response = PassthroughSubject<Void, Error>()
        session.setMessage("Public message", in: .main)
        session.sendMessage(in: .main) { _, _ in response.eraseToAnyPublisher() }
        session.setMessage("Private note", in: .personal)
        response.send(())
        drainMainQueue()
        XCTAssertEqual(session.message(in: .personal), "Private note")
        XCTAssertEqual(session.message(in: .main), "")
    }

    func testPendingSendSurvivesComposerReplacementAndPreventsDuplicate() {
        let session = ChatSessionState()
        let response = PassthroughSubject<Void, Error>()
        let firstComposer = UUID()
        session.composerAppeared(id: firstComposer, shareFocusRequestID: nil)
        session.setMessage("Retain this draft", in: .main)
        var submissions = [String]()
        let send: (OGSChatSendChannel, String) -> AnyPublisher<Void, Error> = { _, message in
            submissions.append(message)
            return response.eraseToAnyPublisher()
        }

        session.sendMessage(in: .main, using: send)
        session.composerDisappeared(id: firstComposer)
        session.composerAppeared(id: UUID(), shareFocusRequestID: nil)
        session.sendMessage(in: .main, using: send)

        XCTAssertTrue(session.isSending)
        XCTAssertEqual(session.message(in: .main), "Retain this draft")
        XCTAssertEqual(submissions, ["Retain this draft"])

        response.send(())
        drainMainQueue()
        XCTAssertFalse(session.isSending)
        XCTAssertEqual(session.message(in: .main), "")
        XCTAssertNil(session.failure)
    }

    func testFailedSendRetainsMessageAndErrorForReplacementComposer() {
        let session = ChatSessionState()
        let response = PassthroughSubject<Void, Error>()
        session.setMessage("Retry after folding", in: .main)
        session.sendMessage(in: .main) { _, _ in response.eraseToAnyPublisher() }
        response.send(completion: .failure(SendError.unavailable))
        drainMainQueue()

        session.composerAppeared(id: UUID(), shareFocusRequestID: nil)
        XCTAssertFalse(session.isSending)
        XCTAssertEqual(session.message(in: .main), "Retry after folding")
        XCTAssertEqual(session.failure, .messageSend)

        let retry = PassthroughSubject<Void, Error>()
        session.sendMessage(in: .main) { _, message in
            XCTAssertEqual(message, "Retry after folding")
            return retry.eraseToAnyPublisher()
        }
        XCTAssertTrue(session.isSending)
        XCTAssertNil(session.failure)
        retry.send(())
        drainMainQueue()
        XCTAssertEqual(session.message(in: .main), "")
    }

    func testSuccessfulSendDoesNotEraseNewerDraft() {
        let session = ChatSessionState()
        let response = PassthroughSubject<Void, Error>()
        session.setMessage("First message", in: .main)
        session.sendMessage(in: .main) { _, _ in response.eraseToAnyPublisher() }
        session.setMessage("Second message still being edited", in: .main)
        response.send(())
        drainMainQueue()

        XCTAssertFalse(session.isSending)
        XCTAssertEqual(session.message(in: .main), "Second message still being edited")
    }

    func testResetRejectsQueuedCompletionFromPreviousGame() {
        let session = ChatSessionState()
        let oldResponse = PassthroughSubject<Void, Error>()
        session.setMessage("Old game", in: .main)
        session.sendMessage(in: .main) { _, _ in oldResponse.eraseToAnyPublisher() }
        oldResponse.send(())

        session.reset()
        let newResponse = PassthroughSubject<Void, Error>()
        session.setMessage("New game", in: .main)
        session.sendMessage(in: .main) { _, _ in newResponse.eraseToAnyPublisher() }
        drainMainQueue()

        XCTAssertTrue(session.isSending)
        XCTAssertEqual(session.message(in: .main), "New game")
        XCTAssertNil(session.failure)

        newResponse.send(completion: .failure(SendError.unavailable))
        drainMainQueue()
        XCTAssertFalse(session.isSending)
        XCTAssertEqual(session.message(in: .main), "New game")
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
        session.setMessage("Finish this thought after viewing a profile", in: .main)
        session.scrollAnchor = "earlier-message"
        let response = PassthroughSubject<Void, Error>()
        session.sendMessage(in: .main) { _, _ in response.eraseToAnyPublisher() }
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
        XCTAssertEqual(session.message(in: .main), "Finish this thought after viewing a profile")
        XCTAssertEqual(session.scrollAnchor, "earlier-message")
        XCTAssertTrue(session.isSending)

        response.send(completion: .failure(SendError.unavailable))
        drainMainQueue()
        XCTAssertFalse(session.isSending)
        XCTAssertEqual(session.failure, .messageSend)
        XCTAssertEqual(session.message(in: .main), "Finish this thought after viewing a profile")
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
        session.setMessage("Draft retained through profile navigation", in: .main)

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
        XCTAssertEqual(session.message(in: .main), "Draft retained through profile navigation")
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
        session.setMessage("Unsent through rotation", in: .main)
        let transition = try XCTUnwrap(session.beginWindowSizeTransition())

        // UIKit can resign, restore, then resign the same field during rotation.
        session.recordInputFocus(false, composerID: composer)
        session.recordInputFocus(true, composerID: composer)
        session.recordInputFocus(false, composerID: composer)
        XCTAssertTrue(session.wantsInputFocus)
        XCTAssertEqual(session.focusRestorationRevision, 0)

        session.completeWindowSizeTransition(transition)
        XCTAssertEqual(session.focusRestorationRevision, 1)
        XCTAssertEqual(session.message(in: .main), "Unsent through rotation")
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
        first.setMessage("First game chat", in: .main)
        first.setMessage("First game personal note", in: .personal)
        store.deactivate(gameID: .OGS(101), accountID: 7)

        let second = store.session(for: .OGS(102), accountID: 7)
        XCTAssertFalse(first === second)
        XCTAssertEqual(second.message(in: .main), "")
        second.setMessage("Second game chat", in: .main)
        XCTAssertEqual(second.message(in: .personal), "")
        second.setMessage("Second game personal note", in: .personal)

        let returned = store.session(for: .OGS(101), accountID: 7)
        XCTAssertTrue(first === returned)
        // Game Detail opens the main channel when switching games.
        XCTAssertEqual(returned.message(in: .main), "First game chat")
        XCTAssertEqual(returned.message(in: .personal), "First game personal note")
        XCTAssertEqual(second.message(in: .main), "Second game chat")
        XCTAssertEqual(second.message(in: .personal), "Second game personal note")
    }

    func testRetainedRoutesForSameGameReadAndEditIndependentChannelDrafts() {
        let store = GameChatSessionStore()
        let home = store.session(for: .OGS(101), accountID: 7)
        let homeChannel = OGSChatSendChannel.main
        let homeComposer = UUID()
        home.composerAppeared(id: homeComposer, shareFocusRequestID: nil)
        home.setMessage("Home public draft", in: homeChannel, from: homeComposer)
        home.gamePresentationDisappeared()

        let profile = store.session(for: .OGS(101), accountID: 7)
        let profileChannel = OGSChatSendChannel.personal
        XCTAssertTrue(home === profile)
        XCTAssertEqual(profile.message(in: profileChannel), "",
                       "The other route must not display Home's draft before appearing.")
        profile.setGamePresentationActive(true)
        let profileComposer = UUID()
        profile.composerAppeared(id: profileComposer, shareFocusRequestID: nil)
        profile.setMessage("Profile private note", in: profileChannel, from: profileComposer)
        profile.setMessage("Hidden-from-opponent note", in: .malkovich, from: profileComposer)

        // Both routes retain their own selection. Reading a covered route must
        // already be safe, without waiting for its next lifecycle callback.
        XCTAssertEqual(home.message(in: homeChannel), "Home public draft")
        XCTAssertEqual(profile.message(in: profileChannel), "Profile private note")
        profile.gamePresentationDisappeared()
        XCTAssertEqual(home.message(in: homeChannel), "Home public draft")
        home.setGamePresentationActive(true)
        let returningComposer = UUID()
        home.composerAppeared(id: returningComposer, shareFocusRequestID: nil)
        home.setMessage("Edited public draft", in: homeChannel, from: returningComposer)

        XCTAssertEqual(profile.message(in: profileChannel), "Profile private note")
        XCTAssertEqual(home.message(in: homeChannel), "Edited public draft")
        XCTAssertEqual(home.message(in: .malkovich), "Hidden-from-opponent note")
    }

    func testReturningToRetainedMainRouteSubmitsOnlyItsPublicDraft() {
        let store = GameChatSessionStore()
        let home = store.session(for: .OGS(101), accountID: 7)
        home.setMessage("Public message", in: .main)
        home.gamePresentationDisappeared()
        let profile = store.session(for: .OGS(101), accountID: 7)
        profile.setGamePresentationActive(true)
        let profileComposer = UUID()
        profile.composerAppeared(id: profileComposer, shareFocusRequestID: nil)
        profile.setMessage("Personal message", in: .personal, from: profileComposer)
        profile.gamePresentationDisappeared()

        home.setGamePresentationActive(true)
        let homeComposer = UUID()
        home.composerAppeared(id: homeComposer, shareFocusRequestID: nil)
        let publicResponse = PassthroughSubject<Void, Error>()
        var sentChannels = [OGSChatSendChannel]()
        var sentMessages = [String]()
        home.sendMessage(in: .main, from: homeComposer) { channel, message in
            sentChannels.append(channel)
            sentMessages.append(message)
            return publicResponse.eraseToAnyPublisher()
        }
        XCTAssertEqual(sentChannels, [.main])
        XCTAssertEqual(sentMessages, ["Public message"])
        publicResponse.send(())
        drainMainQueue()
        XCTAssertEqual(home.message(in: .main), "")
        XCTAssertEqual(profile.message(in: .personal), "Personal message")

        home.gamePresentationDisappeared()
        profile.setGamePresentationActive(true)
        let returningComposer = UUID()
        profile.composerAppeared(id: returningComposer, shareFocusRequestID: nil)
        let personalResponse = PassthroughSubject<Void, Error>()
        profile.sendMessage(in: .personal, from: returningComposer) { channel, message in
            sentChannels.append(channel)
            sentMessages.append(message)
            return personalResponse.eraseToAnyPublisher()
        }
        XCTAssertEqual(sentChannels, [.main, .personal])
        XCTAssertEqual(sentMessages, ["Public message", "Personal message"])
        personalResponse.send(())
        drainMainQueue()
        XCTAssertEqual(profile.message(in: .personal), "")
    }

    func testEmptyMainDraftCannotSubmitAnotherRoutesPersonalDraft() {
        let store = GameChatSessionStore()
        let profile = store.session(for: .OGS(101), accountID: 7)
        let profileComposer = UUID()
        profile.composerAppeared(id: profileComposer, shareFocusRequestID: nil)
        profile.setMessage("Keep this private", in: .personal, from: profileComposer)
        profile.gamePresentationDisappeared()

        let home = store.session(for: .OGS(101), accountID: 7)
        XCTAssertEqual(home.message(in: .main), "")
        home.setGamePresentationActive(true)
        let homeComposer = UUID()
        home.composerAppeared(id: homeComposer, shareFocusRequestID: nil)
        home.sendMessage(in: .main, from: homeComposer) { _, _ in
            XCTFail("An empty public composer must never submit a private draft.")
            return Empty().eraseToAnyPublisher()
        }
        XCTAssertFalse(home.isSending)
        XCTAssertEqual(profile.message(in: .personal), "Keep this private")
    }

    func testPendingPrivateSendKeepsNewerDraftAndAnotherRoutesPublicDraft() {
        let store = GameChatSessionStore()
        let profile = store.session(for: .OGS(101), accountID: 7)
        let profileComposer = UUID()
        profile.composerAppeared(id: profileComposer, shareFocusRequestID: nil)
        profile.setMessage("Submitted private note", in: .personal, from: profileComposer)
        let response = PassthroughSubject<Void, Error>()
        profile.sendMessage(in: .personal, from: profileComposer) { channel, message in
            XCTAssertEqual(channel, .personal)
            XCTAssertEqual(message, "Submitted private note")
            return response.eraseToAnyPublisher()
        }
        profile.gamePresentationDisappeared()

        let home = store.session(for: .OGS(101), accountID: 7)
        home.setGamePresentationActive(true)
        let homeComposer = UUID()
        home.composerAppeared(id: homeComposer, shareFocusRequestID: nil)
        home.setMessage("Unsent public draft", in: .main, from: homeComposer)
        home.sendMessage(in: .main, from: homeComposer) { _, _ in
            XCTFail("The same game must still reject a second send while one is pending.")
            return Empty().eraseToAnyPublisher()
        }
        home.gamePresentationDisappeared()

        profile.setGamePresentationActive(true)
        let returningComposer = UUID()
        profile.composerAppeared(id: returningComposer, shareFocusRequestID: nil)
        profile.setMessage("Newer private note", in: .personal, from: returningComposer)
        response.send(())
        drainMainQueue()

        XCTAssertFalse(profile.isSending)
        XCTAssertEqual(profile.message(in: .personal), "Newer private note")
        XCTAssertEqual(home.message(in: .main), "Unsent public draft")
    }

    func testStaleComposerCannotOverwriteAnyChannelAfterRouteReplacement() {
        let store = GameChatSessionStore()
        let profile = store.session(for: .OGS(101), accountID: 7)
        let oldComposer = UUID()
        profile.composerAppeared(id: oldComposer, shareFocusRequestID: nil)
        profile.setMessage("Personal draft", in: .personal, from: oldComposer)
        profile.gamePresentationDisappeared()
        profile.setMessage("Queued private edit", in: .personal, from: oldComposer)
        XCTAssertEqual(profile.message(in: .personal), "Personal draft")

        let home = store.session(for: .OGS(101), accountID: 7)
        home.setGamePresentationActive(true)
        let currentComposer = UUID()
        home.composerAppeared(id: currentComposer, shareFocusRequestID: nil)
        home.setMessage("Public draft", in: .main, from: currentComposer)
        profile.setMessage("Stale private edit", in: .personal, from: oldComposer)
        profile.setMessage("Misrouted stale edit", in: .main, from: oldComposer)
        XCTAssertEqual(home.message(in: .main), "Public draft")
        XCTAssertEqual(profile.message(in: .personal), "Personal draft")

        // A replacement field can continue the private draft normally.
        home.gamePresentationDisappeared()
        profile.setGamePresentationActive(true)
        let returningComposer = UUID()
        profile.composerAppeared(id: returningComposer, shareFocusRequestID: nil)
        profile.setMessage("Edited personal draft", in: .personal, from: returningComposer)
        profile.setMessage("Old field returning late", in: .personal, from: oldComposer)
        XCTAssertEqual(profile.message(in: .personal), "Edited personal draft")
        XCTAssertEqual(home.message(in: .main), "Public draft")
    }

    func testSwitchingGamesDeactivatesOldComposerWithoutRestoringFocus() {
        let store = GameChatSessionStore()
        let first = store.session(for: .OGS(101), accountID: 7)
        let oldComposer = UUID()
        first.composerAppeared(id: oldComposer, shareFocusRequestID: nil)
        first.requestInputFocus()
        first.setMessage("Unsent first game draft", in: .main)
        let oldRevision = first.focusRevision
        store.deactivate(gameID: .OGS(101), accountID: 7)
        first.recordInputFocus(true, composerID: oldComposer,
                               expectedRevision: oldRevision)

        let second = store.session(for: .OGS(102), accountID: 7)
        XCTAssertFalse(first.isActiveComposer(oldComposer))
        XCTAssertFalse(first.wantsInputFocus)
        XCTAssertFalse(second.wantsInputFocus)
        XCTAssertEqual(second.message(in: .main), "")

        let returned = store.session(for: .OGS(101), accountID: 7)
        returned.setGamePresentationActive(true)
        returned.composerAppeared(id: UUID(), shareFocusRequestID: nil)
        XCTAssertEqual(returned.message(in: .main), "Unsent first game draft")
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
        first.setMessage("First game message", in: .main)
        let send: (OGSChatSendChannel, String) -> AnyPublisher<Void, Error> = { _, message in
            submissions.append(message)
            return response.eraseToAnyPublisher()
        }
        first.sendMessage(in: .main, from: originalComposer, using: send)
        store.deactivate(gameID: .OGS(101), accountID: 7)
        let second = store.session(for: .OGS(102), accountID: 7)
        second.setMessage("Second game unsent draft", in: .main)

        let returned = store.session(for: .OGS(101), accountID: 7)
        returned.setGamePresentationActive(true)
        let replacementComposer = UUID()
        returned.composerAppeared(id: replacementComposer, shareFocusRequestID: nil)
        returned.sendMessage(in: .main, from: replacementComposer, using: send)
        XCTAssertEqual(submissions, ["First game message"])
        XCTAssertTrue(returned.isSending)
        response.send(())
        drainMainQueue()

        XCTAssertFalse(returned.isSending)
        XCTAssertEqual(returned.message(in: .main), "")
        XCTAssertEqual(second.message(in: .main), "Second game unsent draft")
        XCTAssertNil(second.failure)
    }

    func testSendFailureWhileAnotherGameIsVisibleRetainsOriginalDraftAndRetry() {
        let store = GameChatSessionStore()
        let first = store.session(for: .OGS(101), accountID: 7)
        let response = PassthroughSubject<Void, Error>()
        first.setMessage("Retry only in first game", in: .main)
        first.sendMessage(in: .main) { _, _ in response.eraseToAnyPublisher() }
        store.deactivate(gameID: .OGS(101), accountID: 7)
        let second = store.session(for: .OGS(102), accountID: 7)
        second.setMessage("Leave second game alone", in: .main)
        response.send(completion: .failure(SendError.unavailable))
        drainMainQueue()

        let returned = store.session(for: .OGS(101), accountID: 7)
        XCTAssertEqual(returned.message(in: .main), "Retry only in first game")
        XCTAssertEqual(returned.failure, .messageSend)
        XCTAssertFalse(returned.isSending)
        XCTAssertEqual(second.message(in: .main), "Leave second game alone")
        XCTAssertNil(second.failure)
        let retry = PassthroughSubject<Void, Error>()
        returned.sendMessage(in: .main) { _, message in
            XCTAssertEqual(message, "Retry only in first game")
            return retry.eraseToAnyPublisher()
        }
        retry.send(())
        drainMainQueue()
        XCTAssertEqual(returned.message(in: .main), "")
    }

    func testAccountChangeDiscardsEveryOldGameAndRejectsQueuedCompletion() {
        let store = GameChatSessionStore()
        let first = store.session(for: .OGS(101), accountID: 7)
        let second = store.session(for: .OGS(102), accountID: 7)
        let response = PassthroughSubject<Void, Error>()
        let composer = UUID()
        first.composerAppeared(id: composer, shareFocusRequestID: nil)
        first.requestInputFocus()
        first.setMessage("Old account pending message", in: .main)
        first.sendMessage(in: .main) { _, _ in response.eraseToAnyPublisher() }
        second.setMessage("Old account second game", in: .main)
        response.send(())

        // A new render may acquire its session before the account observer runs.
        let newAccount = store.session(for: .OGS(101), accountID: 8)
        XCTAssertFalse(newAccount === first)
        XCTAssertEqual(newAccount.message(in: .main), "")
        newAccount.setMessage("New account draft", in: .main)
        store.discardOtherAccounts(keeping: 8)
        first.recordInputFocus(true, composerID: composer)
        drainMainQueue()

        XCTAssertEqual(first.message(in: .main), "")
        XCTAssertEqual(second.message(in: .main), "")
        XCTAssertFalse(first.isSending)
        XCTAssertFalse(first.wantsInputFocus)
        XCTAssertEqual(newAccount.message(in: .main), "New account draft")
        XCTAssertNil(newAccount.failure)
        let oldAccountAgain = store.session(for: .OGS(101), accountID: 7)
        XCTAssertFalse(oldAccountAgain === first)
        XCTAssertEqual(oldAccountAgain.message(in: .main), "")
    }

    func testLogoutDiscardsSignedInGameDrafts() {
        let store = GameChatSessionStore()
        let signedIn = store.session(for: .OGS(101), accountID: 7)
        signedIn.setMessage("Signed-in draft", in: .main)
        signedIn.setMessage("Private note", in: .personal)
        store.discardOtherAccounts(keeping: nil)

        XCTAssertEqual(signedIn.message(in: .personal), "")
        XCTAssertEqual(signedIn.message(in: .main), "")
        XCTAssertEqual(store.session(for: .OGS(101), accountID: nil).message(in: .main), "")
        XCTAssertEqual(store.session(for: .OGS(101), accountID: 7).message(in: .main), "")
    }

    func testStaleComposerCannotSubmitRetainedPersonalDraftAfterSwitchOrReturn() {
        let store = GameChatSessionStore()
        let first = store.session(for: .OGS(101), accountID: 7)
        let oldComposer = UUID()
        first.composerAppeared(id: oldComposer, shareFocusRequestID: nil)
        first.setMessage("Personal draft must never become public", in: .personal)
        var submitted = [String]()
        let send: (OGSChatSendChannel, String) -> AnyPublisher<Void, Error> = { _, message in
            submitted.append(message)
            return Empty().eraseToAnyPublisher()
        }

        store.deactivate(gameID: .OGS(101), accountID: 7)
        let second = store.session(for: .OGS(102), accountID: 7)
        second.composerAppeared(id: UUID(), shareFocusRequestID: nil)
        second.setMessage("Second game draft", in: .main)
        first.sendMessage(in: .personal, from: oldComposer, using: send)
        XCTAssertTrue(submitted.isEmpty)
        XCTAssertEqual(first.message(in: .personal), "Personal draft must never become public")
        XCTAssertEqual(second.message(in: .main), "Second game draft")

        first.setGamePresentationActive(true)
        first.composerAppeared(id: UUID(), shareFocusRequestID: nil)
        first.setMessage("Newer first-game main draft", in: .main)
        first.sendMessage(in: .main, from: oldComposer, using: send)
        XCTAssertTrue(submitted.isEmpty)
        XCTAssertEqual(first.message(in: .main), "Newer first-game main draft")
        XCTAssertEqual(first.message(in: .personal), "Personal draft must never become public")
    }

    func testDiscardedAccountComposerCannotSubmitAfterItsGameIsReused() {
        let store = GameChatSessionStore()
        let old = store.session(for: .OGS(101), accountID: 7)
        let oldComposer = UUID()
        old.composerAppeared(id: oldComposer, shareFocusRequestID: nil)
        old.setMessage("Old account draft", in: .main)
        store.discardOtherAccounts(keeping: 8)
        let current = store.session(for: .OGS(101), accountID: 8)
        let currentComposer = UUID()
        current.composerAppeared(id: currentComposer, shareFocusRequestID: nil)
        current.setMessage("Current account draft", in: .main)
        var submitted = [String]()
        old.sendMessage(in: .main, from: oldComposer) { _, message in
            submitted.append(message)
            return Empty().eraseToAnyPublisher()
        }
        current.sendMessage(in: .main, from: oldComposer) { _, message in
            submitted.append(message)
            return Empty().eraseToAnyPublisher()
        }
        XCTAssertTrue(submitted.isEmpty)
        XCTAssertEqual(current.message(in: .main), "Current account draft")
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
        first.setMessage("First game message", in: .main)
        let response = PassthroughSubject<Void, Error>()
        first.sendMessage(in: .main) { _, _ in response.eraseToAnyPublisher() }
        first.recordScrollPosition(atEnd: false, anchor: "older-first-game-message",
                                   userInitiated: true)
        store.deactivate(gameID: .OGS(101), accountID: 7)
        let second = store.session(for: .OGS(102), accountID: 7)
        second.setMessage("Second game draft", in: .main)

        let returned = store.session(for: .OGS(101), accountID: 7)
        returned.resetReadingPosition()
        XCTAssertTrue(returned.isAtEndOfChat)
        XCTAssertNil(returned.scrollAnchor)
        XCTAssertEqual(returned.message(in: .main), "First game message")
        XCTAssertTrue(returned.isSending)
        XCTAssertEqual(second.message(in: .main), "Second game draft")

        response.send(())
        drainMainQueue()
        XCTAssertFalse(returned.isSending)
        XCTAssertEqual(returned.message(in: .main), "")
        XCTAssertEqual(second.message(in: .main), "Second game draft")
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
        discarded.setMessage("Obsolete field update", in: .main)
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
        survivingSession?.setMessage("A field can briefly outlive its route", in: .main)
        XCTAssertEqual(survivingSession?.message(in: .main), "A field can briefly outlive its route")
    }

    func testInactiveSessionAndPendingSendOutliveAllPresentationReferences() {
        let store = GameChatSessionStore()
        let response = PassthroughSubject<Void, Error>()
        weak var retainedSession: ChatSessionState?
        var submissions = [String]()
        let send: (OGSChatSendChannel, String) -> AnyPublisher<Void, Error> = { _, text in
            submissions.append(text)
            return response.eraseToAnyPublisher()
        }
        do {
            let presented = store.session(for: .OGS(101), accountID: 7)
            retainedSession = presented
            let composer = UUID()
            presented.composerAppeared(id: composer, shareFocusRequestID: nil)
            presented.setMessage("Pending main message", in: .main)
            presented.sendMessage(in: .main, from: composer, using: send)
            presented.setMessage("Unsent Personal draft", in: .personal)
            store.deactivate(gameID: .OGS(101), accountID: 7)
        }

        XCTAssertNotNil(retainedSession)
        let reopened = store.session(for: .OGS(101), accountID: 7)
        XCTAssertTrue(reopened === retainedSession)
        XCTAssertEqual(reopened.message(in: .personal), "Unsent Personal draft")
        XCTAssertTrue(reopened.isSending)
        XCTAssertFalse(reopened.wantsInputFocus)
        reopened.setGamePresentationActive(true)
        let replacementComposer = UUID()
        reopened.composerAppeared(id: replacementComposer, shareFocusRequestID: nil)
        XCTAssertEqual(reopened.message(in: .main), "Pending main message")
        reopened.sendMessage(in: .main, from: replacementComposer, using: send)
        XCTAssertEqual(submissions, ["Pending main message"])

        response.send(())
        drainMainQueue()
        XCTAssertFalse(reopened.isSending)
        XCTAssertEqual(reopened.message(in: .personal), "Unsent Personal draft")
        XCTAssertEqual(reopened.message(in: .main), "")
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
            first.setMessage("Old account pending draft", in: .main)
            first.sendMessage(in: .main) { _, _ in
                response.handleEvents(receiveCancel: { cancellations += 1 })
                    .eraseToAnyPublisher()
            }
            second.setMessage("Old account Personal draft", in: .personal)
            store.deactivate(gameID: .OGS(101), accountID: 7)
            store.deactivate(gameID: .OGS(102), accountID: 7)
        }
        XCTAssertNotNil(oldFirst)
        XCTAssertNotNil(oldSecond)
        let current = store.session(for: .OGS(101), accountID: 8)
        current.setMessage("Current account draft", in: .main)

        // The stable owner performs this while Home has no game presented.
        store.discardOtherAccounts(keeping: 8)
        XCTAssertEqual(cancellations, 1)
        XCTAssertNil(oldFirst)
        XCTAssertNil(oldSecond)
        response.send(())
        drainMainQueue()
        XCTAssertEqual(current.message(in: .main), "Current account draft")
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
            presented.setMessage("Pending while leaving the window", in: .main)
            presented.sendMessage(in: .main) { _, _ in
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
