//
//  PrivateMessageComposerStateTests.swift
//  SurroundTests
//
//  A conversation composer's enablement rule. Offline turns the field and
//  Send off and reads "Reconnecting…", even where remote activity is
//  allowed, which offline UI tests never allow. Online, Send follows the
//  draft and remote activity as it always has, with the field on.
//

import XCTest

final class PrivateMessageComposerStateTests: XCTestCase {
    func testOfflineDisablesTheFieldAndSendEvenWithRemoteActivity() {
        let state = PrivateMessageComposerState(
            draftIsEmpty: false, allowsRemoteActivity: true, isOffline: true)

        XCTAssertFalse(state.fieldIsEnabled)
        XCTAssertFalse(state.sendIsEnabled)
        XCTAssertTrue(state.readsReconnecting)

        // Offline wins over every draft and remote-activity combination.
        for draftIsEmpty in [false, true] {
            for allowsRemoteActivity in [false, true] {
                let offline = PrivateMessageComposerState(
                    draftIsEmpty: draftIsEmpty, allowsRemoteActivity: allowsRemoteActivity, isOffline: true)
                let context = "draftIsEmpty: \(draftIsEmpty), allowsRemoteActivity: \(allowsRemoteActivity)"

                XCTAssertFalse(offline.fieldIsEnabled, context)
                XCTAssertFalse(offline.sendIsEnabled, context)
                XCTAssertTrue(offline.readsReconnecting, context)
            }
        }
    }

    func testOnlineSendFollowsTheDraftAndRemoteActivity() {
        for draftIsEmpty in [false, true] {
            for allowsRemoteActivity in [false, true] {
                let state = PrivateMessageComposerState(
                    draftIsEmpty: draftIsEmpty, allowsRemoteActivity: allowsRemoteActivity, isOffline: false)
                let context = "draftIsEmpty: \(draftIsEmpty), allowsRemoteActivity: \(allowsRemoteActivity)"

                XCTAssertTrue(state.fieldIsEnabled, context)
                // The composer's rule before the state existed: Send was off
                // when `draft.isEmpty || !allowsRemoteActivity`.
                XCTAssertEqual(state.sendIsEnabled, !(draftIsEmpty || !allowsRemoteActivity), context)
                XCTAssertFalse(state.readsReconnecting, context)
            }
        }

        XCTAssertTrue(PrivateMessageComposerState(
            draftIsEmpty: false, allowsRemoteActivity: true, isOffline: false).sendIsEnabled)
    }
}
