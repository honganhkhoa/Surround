//
//  ConversationDraftStoreTests.swift
//  SurroundTests
//
//  A window's unsent private messages and reading positions, by account and
//  peer: one per person whichever stack shows the conversation, untouched
//  by any stack's navigation, and published only through the store, which
//  only conversation views observe.
//

import Combine
import SwiftUI
import XCTest

final class ConversationDraftStoreTests: XCTestCase {
    private let viewerID = 100
    private var firstPlayer: OGSUser { OGSUser(username: "First player", id: 101) }
    private var secondPlayer: OGSUser { OGSUser(username: "Second player", id: 102) }

    func testDraftsStayWithTheirAccountAndPeer() {
        let store = ConversationDraftStore()
        let first = store.draft(for: firstPlayer.id, accountID: viewerID)
        let second = store.draft(for: secondPlayer.id, accountID: viewerID)
        let otherAccount = store.draft(for: firstPlayer.id, accountID: 200)
        first.wrappedValue = "First account, first peer"
        second.wrappedValue = "First account, second peer"
        otherAccount.wrappedValue = "Other account, first peer"

        XCTAssertEqual(store.draft(for: firstPlayer.id, accountID: viewerID).wrappedValue,
                       "First account, first peer")
        XCTAssertEqual(second.wrappedValue, "First account, second peer")
        XCTAssertEqual(otherAccount.wrappedValue, "Other account, first peer")

        let signedOut = store.draft(for: firstPlayer.id, accountID: nil)
        signedOut.wrappedValue = "Signed-out text"
        XCTAssertEqual(signedOut.wrappedValue, "", "Signed out, the composer keeps nothing.")
        XCTAssertEqual(first.wrappedValue, "First account, first peer")
        first.wrappedValue = ""
        XCTAssertEqual(first.wrappedValue, "")
        XCTAssertEqual(second.wrappedValue, "First account, second peer")
        XCTAssertEqual(otherAccount.wrappedValue, "Other account, first peer")
    }

    /// Messages' own conversation and a profile's Message in another stack
    /// of the same window show one draft; other people and accounts, and
    /// other windows, keep their own.
    func testStacksInOneWindowShareOneDraftPerAccountAndPeer() {
        let nav = NavigationService()
        let messages = StackRouter()
        let home = StackRouter()
        messages.presentMessagesConversation(firstPlayer)
        home.openProfile(firstPlayer)
        home.openConversation(firstPlayer)
        XCTAssertEqual(messages.path, [.messagesConversation(firstPlayer.id)])
        XCTAssertEqual(home.path, [.profile(playerID: firstPlayer.id, selectionID: nil),
                                   .conversation(firstPlayer.id)])

        let inMessages = nav.conversationDrafts.draft(for: firstPlayer.id, accountID: viewerID)
        let inHome = nav.conversationDrafts.draft(for: firstPlayer.id, accountID: viewerID)
        inMessages.wrappedValue = "Started in Messages"
        XCTAssertEqual(inHome.wrappedValue, "Started in Messages")
        inHome.wrappedValue = "Finished from the profile"
        XCTAssertEqual(inMessages.wrappedValue, "Finished from the profile")
        XCTAssertTrue(nav.conversationDrafts.scrollBookmark(for: firstPlayer.id, accountID: viewerID)
                      === nav.conversationDrafts.scrollBookmark(for: firstPlayer.id, accountID: viewerID))

        let secondPeer = nav.conversationDrafts.draft(for: secondPlayer.id, accountID: viewerID)
        let otherAccount = nav.conversationDrafts.draft(for: firstPlayer.id, accountID: viewerID + 1)
        XCTAssertEqual(secondPeer.wrappedValue, "")
        XCTAssertEqual(otherAccount.wrappedValue, "")
        secondPeer.wrappedValue = "To the second peer"
        otherAccount.wrappedValue = "From another account"
        XCTAssertEqual(inMessages.wrappedValue, "Finished from the profile")
        XCTAssertEqual(secondPeer.wrappedValue, "To the second peer")
        XCTAssertEqual(otherAccount.wrappedValue, "From another account")

        let otherWindow = NavigationService()
        XCTAssertEqual(otherWindow.conversationDrafts.draft(for: firstPlayer.id, accountID: viewerID).wrappedValue,
                       "", "Each window keeps its own drafts.")
    }

    /// A keystroke redraws only the views that observe the store, the
    /// conversations: neither the window's service nor any stack publishes.
    func testATypedDraftPublishesOnlyThroughTheStore() {
        let nav = NavigationService()
        let messages = StackRouter()
        let home = StackRouter()
        messages.presentMessagesConversation(firstPlayer)
        home.openProfile(firstPlayer)
        home.openConversation(firstPlayer)
        var published = [String]()
        var subscriptions = Set<AnyCancellable>()
        nav.objectWillChange.sink { published.append("window") }.store(in: &subscriptions)
        messages.objectWillChange.sink { published.append("Messages' stack") }.store(in: &subscriptions)
        home.objectWillChange.sink { published.append("Home's stack") }.store(in: &subscriptions)
        nav.conversationDrafts.objectWillChange.sink { published.append("drafts") }.store(in: &subscriptions)

        let draft = nav.conversationDrafts.draft(for: firstPlayer.id, accountID: viewerID)
        for text in ["H", "Hi", "Hi", ""] { draft.wrappedValue = text }
        XCTAssertEqual(published, ["drafts", "drafts", "drafts"],
                       "Each change publishes once, only through the store; an unchanged value publishes nothing.")

        published = []
        let bookmark = nav.conversationDrafts.scrollBookmark(for: firstPlayer.id, accountID: viewerID)
        bookmark.isAtEndOfChat = false
        bookmark.rememberVisibleMessages(["older"], orderedKeys: ["older", "latest"])
        XCTAssertEqual(bookmark.messageKey, "older")
        XCTAssertEqual(published, [], "Making a bookmark and scrolling publish nothing.")
    }

    func testDiscardingDraftsKeepsOnlyThatAccount() {
        let store = ConversationDraftStore()
        store.draft(for: firstPlayer.id, accountID: viewerID).wrappedValue = "Kept, first peer"
        store.draft(for: secondPlayer.id, accountID: viewerID).wrappedValue = "Kept, second peer"
        store.draft(for: firstPlayer.id, accountID: 200).wrappedValue = "Another account's"
        let kept = store.scrollBookmark(for: firstPlayer.id, accountID: viewerID)
        let dropped = store.scrollBookmark(for: firstPlayer.id, accountID: 200)

        store.discardDrafts(exceptAccount: viewerID)

        XCTAssertEqual(store.draft(for: firstPlayer.id, accountID: viewerID).wrappedValue, "Kept, first peer")
        XCTAssertEqual(store.draft(for: secondPlayer.id, accountID: viewerID).wrappedValue, "Kept, second peer")
        XCTAssertEqual(store.draft(for: firstPlayer.id, accountID: 200).wrappedValue, "")
        XCTAssertTrue(store.scrollBookmark(for: firstPlayer.id, accountID: viewerID) === kept)
        XCTAssertFalse(store.scrollBookmark(for: firstPlayer.id, accountID: 200) === dropped,
                       "Another account's reading position goes with its drafts.")

        var published = 0
        let subscription = store.objectWillChange.sink { published += 1 }
        store.discardDrafts(exceptAccount: viewerID)
        XCTAssertEqual(published, 0, "Nothing to drop redraws nothing.")
        store.discardDrafts(exceptAccount: nil)
        XCTAssertEqual(published, 1)
        subscription.cancel()
        XCTAssertEqual(store.draft(for: firstPlayer.id, accountID: viewerID).wrappedValue, "",
                       "Signed out keeps no account's drafts.")
        XCTAssertEqual(store.draft(for: secondPlayer.id, accountID: viewerID).wrappedValue, "")
    }

    func testBookmarksAreMadeOncePerKeyAndDraftsNeverTouchThem() {
        let store = ConversationDraftStore()
        let bookmark = store.scrollBookmark(for: firstPlayer.id, accountID: viewerID)
        bookmark.isAtEndOfChat = false
        bookmark.messageKey = "older-message"

        let draft = store.draft(for: firstPlayer.id, accountID: viewerID)
        draft.wrappedValue = "Typing"
        draft.wrappedValue = ""

        let again = store.scrollBookmark(for: firstPlayer.id, accountID: viewerID)
        XCTAssertTrue(again === bookmark)
        XCTAssertEqual(again.messageKey, "older-message")
        XCTAssertFalse(again.isAtEndOfChat)

        store.draft(for: secondPlayer.id, accountID: viewerID).wrappedValue = "A draft before any scrolling"
        let fresh = store.scrollBookmark(for: secondPlayer.id, accountID: viewerID)
        XCTAssertFalse(fresh === bookmark)
        XCTAssertNil(fresh.messageKey)
        XCTAssertTrue(fresh.isAtEndOfChat)
        XCTAssertTrue(store.scrollBookmark(for: secondPlayer.id, accountID: viewerID) === fresh)

        XCTAssertFalse(store.scrollBookmark(for: firstPlayer.id, accountID: nil)
                       === store.scrollBookmark(for: firstPlayer.id, accountID: nil),
                       "Signed out, no reading position is kept.")
    }

    /// Drafts live outside every StackRouter, so navigation can no longer
    /// drop one: not a route change, Back, a column change or a reset, nor
    /// a presented stack closing and another opening.
    func testNavigationNeverDropsADraftOrItsReadingPosition() {
        let nav = NavigationService()
        let draft = nav.conversationDrafts.draft(for: firstPlayer.id, accountID: viewerID)
        draft.wrappedValue = "Unsent through every route"
        let bookmark = nav.conversationDrafts.scrollBookmark(for: firstPlayer.id, accountID: viewerID)
        bookmark.isAtEndOfChat = false
        bookmark.messageKey = "older-message"

        let router = StackRouter()
        router.presentMessagesConversation(firstPlayer)
        router.openProfile(firstPlayer)
        router.openAbout(OGSPlayerProfile(user: firstPlayer, about: "Read more"))
        router.openConversation(firstPlayer)
        router.openChallenge(for: firstPlayer)
        for usesColumns in [true, false, true, false] {
            router.showMessagesColumns(usesColumns, peer: firstPlayer)
        }
        router.returnTo(.messagesConversation(firstPlayer.id))
        XCTAssertEqual(router.path, [.messagesConversation(firstPlayer.id)])
        router.path.removeLast()
        router.reset(preserving: nil)
        XCTAssertTrue(router.path.isEmpty)
        XCTAssertTrue(router.users.isEmpty)

        weak var closedStack: StackRouter?
        do {
            let presented = StackRouter()
            presented.openConversation(firstPlayer)
            XCTAssertEqual(presented.path, [.conversation(firstPlayer.id)])
            closedStack = presented
        }
        XCTAssertNil(closedStack, "The presented stack is gone with its routes.")
        let reopened = StackRouter()
        reopened.openConversation(firstPlayer)

        XCTAssertEqual(nav.conversationDrafts.draft(for: firstPlayer.id, accountID: viewerID).wrappedValue,
                       "Unsent through every route")
        XCTAssertEqual(draft.wrappedValue, "Unsent through every route")
        let returned = nav.conversationDrafts.scrollBookmark(for: firstPlayer.id, accountID: viewerID)
        XCTAssertTrue(returned === bookmark)
        XCTAssertEqual(returned.messageKey, "older-message")
        XCTAssertFalse(returned.isAtEndOfChat)
    }

    func testConversationHistoryBookmarkStaysWithAccountAndPeerAcrossRouteRolesAndBack() {
        let store = ConversationDraftStore()
        let router = StackRouter()
        let accountID = 847
        let peer = OGSUser(username: "Selected peer", id: 765826)
        let bookmark = store.scrollBookmark(for: peer.id, accountID: accountID)
        bookmark.messageKey = "older-history-message"
        bookmark.isAtEndOfChat = false

        router.presentMessagesConversation(peer)
        router.openProfile(peer)
        router.openConversation(peer)
        XCTAssertEqual(router.path, [
            .messagesConversation(peer.id), .profile(playerID: peer.id, selectionID: nil),
            .conversation(peer.id),
        ])

        for _ in 0..<3 {
            let current = store.scrollBookmark(for: peer.id, accountID: accountID)
            XCTAssertTrue(current === bookmark)
            XCTAssertEqual(current.messageKey, "older-history-message")
            XCTAssertFalse(current.isAtEndOfChat)
            router.path.removeLast()
        }
        XCTAssertTrue(router.path.isEmpty)
        XCTAssertTrue(router.users.isEmpty)
        let returned = store.scrollBookmark(for: peer.id, accountID: accountID)
        XCTAssertTrue(returned === bookmark)
        XCTAssertEqual(returned.messageKey, "older-history-message")
        XCTAssertFalse(returned.isAtEndOfChat)

        let otherAccount = store.scrollBookmark(for: peer.id, accountID: accountID + 1)
        let otherPeer = store.scrollBookmark(for: peer.id + 1, accountID: accountID)
        for fresh in [otherAccount, otherPeer] {
            XCTAssertFalse(fresh === bookmark)
            XCTAssertNil(fresh.messageKey)
            XCTAssertTrue(fresh.isAtEndOfChat)
        }
    }

    func testConversationHistoryBookmarkUsesMiddleVisibleMessageInTranscriptOrder() {
        let bookmark = PrivateMessageScrollBookmark()
        bookmark.isAtEndOfChat = false
        let orderedKeys = (1...50).map { "history-\($0)" }

        bookmark.rememberVisibleMessages(
            ["history-42", "history-38", "unknown", "history-40", "history-39", "history-41", "history-39"],
            orderedKeys: orderedKeys
        )

        XCTAssertEqual(bookmark.messageKey, "history-40")
        XCTAssertFalse(bookmark.isAtEndOfChat)
    }

    func testConversationHistoryBookmarkIgnoresMissingTargetsAndLatestMode() {
        let bookmark = PrivateMessageScrollBookmark()
        bookmark.isAtEndOfChat = false
        bookmark.messageKey = "retained-history"

        bookmark.rememberVisibleMessages([], orderedKeys: ["another-message"])
        bookmark.rememberVisibleMessages(["removed-message"], orderedKeys: ["another-message"])
        XCTAssertEqual(bookmark.messageKey, "retained-history")

        bookmark.isAtEndOfChat = true
        bookmark.rememberVisibleMessages(["latest-message"], orderedKeys: ["latest-message"])
        XCTAssertEqual(bookmark.messageKey, "retained-history")
        XCTAssertTrue(bookmark.isAtEndOfChat)
    }
}
