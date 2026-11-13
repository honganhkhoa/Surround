//
//  ConversationDraftStore.swift
//  Surround
//
//  Unsent private messages and reading positions, by account and peer, for
//  one window. Every navigation stack in the window shows the same draft
//  for the same person: Messages, a profile's Message and any presented
//  stack. NavigationService holds it as a constant, so a keystroke never
//  publishes through the window or its stacks: only conversation views
//  observe it. Main thread by convention, like its owner.
//

import Combine
import SwiftUI

/// Retained by the conversation's account/peer owner, without publishing scroll
/// updates through the navigation or inbox hierarchy.
final class PrivateMessageScrollBookmark {
    var messageKey: String?
    var isAtEndOfChat = true

    /// Visibility callbacks do not promise transcript order. Retain the middle
    /// visible message in chronological order, rather than a lazy layout's
    /// estimated leading target or a content offset tied to one width.
    func rememberVisibleMessages(_ visibleKeys: [String], orderedKeys: [String]) {
        guard !isAtEndOfChat else { return }
        let visible = Set(visibleKeys)
        let orderedVisible = orderedKeys.filter { visible.contains($0) }
        guard !orderedVisible.isEmpty else { return }
        messageKey = orderedVisible[orderedVisible.count / 2]
    }
}

final class ConversationDraftStore: ObservableObject {
    private struct Key: Hashable {
        let accountID: Int
        let peerID: Int
    }

    @Published private var drafts: [Key: String] = [:]
    /// Scrolling never publishes, so it redraws nothing.
    private var bookmarks: [Key: PrivateMessageScrollBookmark] = [:]

    /// One draft per account and peer, whichever stack shows it. Signed
    /// out, the composer keeps nothing.
    func draft(for peerID: Int, accountID: Int?) -> Binding<String> {
        guard let accountID else { return .constant("") }
        let key = Key(accountID: accountID, peerID: peerID)
        return Binding(
            get: { self.drafts[key, default: ""] },
            set: { text in
                // An unchanged value redraws no conversation.
                guard self.drafts[key, default: ""] != text else { return }
                self.drafts[key] = text.isEmpty ? nil : text
            }
        )
    }

    /// Made on first use and kept with the draft's account and peer.
    func scrollBookmark(for peerID: Int, accountID: Int?) -> PrivateMessageScrollBookmark {
        guard let accountID else { return PrivateMessageScrollBookmark() }
        let key = Key(accountID: accountID, peerID: peerID)
        if let bookmark = bookmarks[key] { return bookmark }
        let bookmark = PrivateMessageScrollBookmark()
        bookmarks[key] = bookmark
        return bookmark
    }

    /// After an account change: drops every other account's drafts and
    /// reading positions. Nil, signed out, drops them all.
    func discardDrafts(exceptAccount accountID: Int?) {
        let kept = drafts.filter { $0.key.accountID == accountID }
        if kept.count != drafts.count { drafts = kept }
        bookmarks = bookmarks.filter { $0.key.accountID == accountID }
    }
}
