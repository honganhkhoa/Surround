//
//  PrivateMessageLog.swift
//  Surround
//
//  Created by Anh Khoa Hong on 03/03/2021.
//

import SwiftUI
import Combine

struct PrivateMessageLine: View {
    @EnvironmentObject var ogs: OGSService

    var message: OGSPrivateMessage
    var lastMessage: OGSPrivateMessage?

    private var isOutgoing: Bool {
        ogs.user?.id == message.from.id
    }

    private var showsDateDivider: Bool {
        guard let lastMessage else { return true }
        return !Calendar.current.isDate(
            Date(timeIntervalSince1970: message.content.timestamp),
            inSameDayAs: Date(timeIntervalSince1970: lastMessage.content.timestamp)
        )
    }

    private var dateLabel: Text {
        let date = Date(timeIntervalSince1970: message.content.timestamp)
        if Calendar.current.isDateInToday(date) {
            return Text("Today")
        }
        if Calendar.current.isDateInYesterday(date) {
            return Text("Yesterday")
        }
        return Text(verbatim: message.content.dateString)
    }

    private var showsSenderName: Bool {
        showsDateDivider || lastMessage?.from.id != message.from.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsDateDivider {
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 0.5)
                    dateLabel
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 0.5)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            HStack(alignment: .bottom, spacing: 0) {
                if isOutgoing {
                    Spacer(minLength: 44)
                }
                VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 3) {
                    if showsSenderName {
                        Text(message.from.username)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(message.from.uiColor)
                            .padding(.horizontal, 10)
                    }
                    Text(message.content.message)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 14))
                }
                .fixedSize(horizontal: false, vertical: true)
                if !isOutgoing {
                    Spacer(minLength: 44)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 3)
        }
    }
}

private struct PrivateMessageComposer: View {
    #if os(iOS) && !targetEnvironment(macCatalyst)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    let peer: OGSUser
    let ogs: OGSService
    let allowsRemoteActivity: Bool
    let focusIsSuspended: Bool
    @Binding var draft: String
    @ObservedObject var sendSession: PrivateMessageSendSession
    @FocusState private var isFocused: Bool

    private func sendMessage() {
        guard allowsRemoteActivity else { return }
        sendSession.send(to: peer, draft: $draft, using: ogs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let failure = sendSession.failure {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Group {
                            if failure == .notSent {
                                Text("Message wasn’t sent. Try again.")
                            } else {
                                Text("Couldn’t confirm delivery. Check the conversation before retrying.")
                            }
                        }
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Retry", action: sendMessage)
                        .font(.footnote.weight(.semibold))
                        .disabled(draft.isEmpty || !allowsRemoteActivity)
                }
            }
            HStack(spacing: 10) {
                TextField("Message \(peer.username)", text: $draft, onCommit: sendMessage)
                    .focused($isFocused)
                    .font(.body)
                    .submitLabel(.send)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.privateMessageComposer)
                    .onChange(of: draft) { _, _ in
                        sendSession.dismissFailure()
                    }
                if sendSession.isSending {
                    ProgressView()
                        .frame(width: 44, height: 44)
                } else {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(
                                draft.isEmpty || !allowsRemoteActivity
                                    ? Color(.secondaryLabel) : .white
                            )
                            .frame(width: 44, height: 44)
                            .background(
                                draft.isEmpty || !allowsRemoteActivity
                                    ? Color(.systemGray3) : Color.accentColor,
                                in: Circle()
                            )
                    }
                    .disabled(draft.isEmpty || !allowsRemoteActivity)
                    .accessibilityLabel("Send message")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onDisappear {
            isFocused = false
        }
        .onChange(of: focusIsSuspended, initial: true) { _, suspended in
            if suspended {
                isFocused = false
            }
        }
        #if os(iOS) && !targetEnvironment(macCatalyst)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                isFocused = false
            }
        }
        #endif
    }
}

private struct PrivateMessageTranscript: View {
    @EnvironmentObject private var ogs: OGSService
    @Environment(\.scenePhase) private var scenePhase

    let peerID: Int
    let messages: [OGSPrivateMessage]
    let marksThreadAsRead: Bool
    let isPresented: Bool
    let bookmark: PrivateMessageScrollBookmark

    @State private var isVisible = false
    @State private var atEndOfChat: Bool
    @State private var scrollPosition: ScrollPosition
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var visibleMessageKeys = [String]()

    init(peerID: Int, messages: [OGSPrivateMessage], marksThreadAsRead: Bool,
         isPresented: Bool, bookmark: PrivateMessageScrollBookmark) {
        self.peerID = peerID
        self.messages = messages
        self.marksThreadAsRead = marksThreadAsRead
        self.isPresented = isPresented
        self.bookmark = bookmark
        _atEndOfChat = State(initialValue: bookmark.isAtEndOfChat)
        _scrollPosition = State(initialValue: Self.position(
            for: bookmark, lastMessageKey: messages.last?.messageKey
        ))
    }

    private static func position(
        for bookmark: PrivateMessageScrollBookmark, lastMessageKey: String?
    ) -> ScrollPosition {
        if !bookmark.isAtEndOfChat, let key = bookmark.messageKey {
            return ScrollPosition(id: key, anchor: .center)
        }
        if let lastMessageKey {
            return ScrollPosition(id: lastMessageKey, anchor: .bottom)
        }
        return ScrollPosition(idType: String.self, edge: .bottom)
    }

    private func publishRetainedPosition() {
        guard isVisible, isPresented else { return }
        if bookmark.isAtEndOfChat != atEndOfChat {
            bookmark.isAtEndOfChat = atEndOfChat
        }
        // A covered same-peer destination may have changed the shared bookmark.
        // Returning publishes this transcript's own last user reading context.
        rememberCurrentVisibleMessages()
    }

    private static func isUserScrolling(_ phase: ScrollPhase) -> Bool {
        phase == .interacting || phase == .decelerating
    }

    private func rememberPosition() {
        guard Self.isUserScrolling(scrollPhase) else { return }
        publishRetainedPosition()
    }

    private func rememberCurrentVisibleMessages() {
        guard isVisible, isPresented, !bookmark.isAtEndOfChat, !visibleMessageKeys.isEmpty,
              bookmark.messageKey != visibleMessageKeys[visibleMessageKeys.count / 2] else { return }
        bookmark.rememberVisibleMessages(visibleMessageKeys, orderedKeys: messages.map(\.messageKey))
    }

    private func rememberVisibleMessages(_ keys: [String]) {
        // Only a presented user gesture owns the cache. Restoration and
        // teardown must not replace this transcript's reading context.
        guard isVisible, isPresented, Self.isUserScrolling(scrollPhase) else { return }
        let visible = Set(keys)
        let orderedVisible = messages.map(\.messageKey).filter { visible.contains($0) }
        guard !orderedVisible.isEmpty else { return }
        if visibleMessageKeys != orderedVisible {
            visibleMessageKeys = orderedVisible
        }
        rememberPosition()
    }

    private func rememberUserPosition(in geometry: ScrollGeometry) {
        guard isVisible, isPresented, !messages.isEmpty,
              geometry.containerSize.height > 0, geometry.contentSize.height > 0 else { return }
        // visibleRect includes the area under the composer and keyboard inset.
        let isAtEnd = geometry.visibleRect.maxY - geometry.contentInsets.bottom >= geometry.contentSize.height - 2
        if atEndOfChat != isAtEnd {
            atEndOfChat = isAtEnd
        }
        publishRetainedPosition()
        if isAtEnd { markThreadAsRead() }
    }

    private var followsLatestMessages: Bool {
        atEndOfChat && bookmark.isAtEndOfChat
    }

    private func scrollToLatestMessageIfFollowing() {
        guard isVisible, isPresented, followsLatestMessages,
              !Self.isUserScrolling(scrollPhase), !messages.isEmpty else { return }
        // A fitting transcript is already bottom-aligned. Target its edge to
        // avoid applying that alignment again through a message-ID anchor.
        scrollPosition.scrollTo(edge: .bottom)
    }

    private func markThreadAsRead() {
        guard marksThreadAsRead, isVisible, isPresented, followsLatestMessages,
              scenePhase == .active else { return }
        ogs.markPrivateMessageThreadAsRead(peerId: peerID)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(Array(messages.enumerated()), id: \.1.messageKey) { index, message in
                    PrivateMessageLine(
                        message: message,
                        lastMessage: index == 0 ? nil : messages[index - 1]
                    )
                }
                Color.clear.frame(height: 1)
            }
            .scrollTargetLayout()
            .padding(.vertical, 5)
        }
        .scrollPosition($scrollPosition, anchor: followsLatestMessages ? .bottom : .center)
        .scrollDismissesKeyboard(.interactively)
        .defaultScrollAnchor(followsLatestMessages ? .bottom : nil, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        .defaultScrollAnchor(followsLatestMessages ? .bottom : nil, for: .sizeChanges)
        .onScrollGeometryChange(for: Bool?.self) { geometry in
            guard geometry.containerSize.height > 0, geometry.contentSize.height > 0 else { return nil }
            return geometry.visibleRect.maxY - geometry.contentInsets.bottom >= geometry.contentSize.height - 2
        } action: { _, isAtEnd in
            guard isVisible, isPresented, !messages.isEmpty, let isAtEnd else { return }
            // Initial programmatic layout must agree with the retained mode
            // before it can change local state. User scrolling owns new modes.
            guard Self.isUserScrolling(scrollPhase) || isAtEnd == atEndOfChat else { return }
            if atEndOfChat != isAtEnd {
                atEndOfChat = isAtEnd
            }
            rememberPosition()
            if isAtEnd {
                markThreadAsRead()
            }
        }
        .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.5) { keys in
            rememberVisibleMessages(keys)
        }
        .onScrollPhaseChange { oldPhase, newPhase, context in
            guard isVisible, isPresented else { return }
            if scrollPhase != newPhase {
                scrollPhase = newPhase
            }
            if Self.isUserScrolling(newPhase)
                || (newPhase == .idle && Self.isUserScrolling(oldPhase)) {
                // The settled geometry also handles a geometry callback that
                // arrived before native gesture ownership changed.
                rememberUserPosition(in: context.geometry)
            }
        }
        #if DEBUG && MAIN_APP
        .messagesHistoryReplayUITestHarness()
        #endif
        .onAppear {
            isVisible = true
            publishRetainedPosition()
            scrollToLatestMessageIfFollowing()
            ogs.setUpNewPeerIfNecessary(peerId: peerID)
            markThreadAsRead()
            #if DEBUG && MAIN_APP
            ogs.beginMessagesHistoryUITestReplay(peerID: peerID)
            #endif
        }
        .onDisappear {
            isVisible = false
            if scrollPhase != .idle { scrollPhase = .idle }
        }
        .onChange(of: messages) { _, _ in
            if isVisible && isPresented && followsLatestMessages, !messages.isEmpty {
                scrollPosition.scrollTo(edge: .bottom)
                markThreadAsRead()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                scrollToLatestMessageIfFollowing()
                #if os(iOS) && !targetEnvironment(macCatalyst)
                // Background layouts can clamp an older transcript's offset.
                // Restore its saved message in the active layout.
                if isVisible, isPresented, !atEndOfChat, !bookmark.isAtEndOfChat,
                   !Self.isUserScrolling(scrollPhase), let key = bookmark.messageKey,
                   messages.contains(where: { $0.messageKey == key }) {
                    scrollPosition.scrollTo(id: key, anchor: .center)
                }
                #endif
                markThreadAsRead()
            }
        }
        .onChange(of: marksThreadAsRead) { _, _ in
            markThreadAsRead()
        }
        .onChange(of: isPresented) { _, presented in
            if scrollPhase != .idle { scrollPhase = .idle }
            if presented {
                publishRetainedPosition()
                scrollToLatestMessageIfFollowing()
                markThreadAsRead()
            }
        }
    }
}

private struct PrivateMessageTranscriptIdentity: Hashable {
    let accountID: Int?
    let peerID: Int
}

struct PrivateMessageLog: View {
    @Environment(\.surroundAllowsRemoteActivity) private var allowsRemoteActivity
    @Environment(\.openPlayerProfile) private var openPlayerProfile
    @EnvironmentObject var ogs: OGSService
    var peer: OGSUser

    private let messagesOverride: [OGSPrivateMessage]?
    private let marksThreadAsRead: Bool
    private let draftOverride: Binding<String>?
    private let scrollBookmarkOverride: PrivateMessageScrollBookmark?
    private let showsProfileToolbar: Bool
    private let focusIsSuspended: Bool
    private let composerFocusIsSuspended: Bool

    init(
        peer: OGSUser,
        messages: [OGSPrivateMessage]? = nil,
        marksThreadAsRead: Bool = true,
        draft: Binding<String>? = nil,
        scrollBookmark: PrivateMessageScrollBookmark? = nil,
        showsProfileToolbar: Bool = true,
        focusIsSuspended: Bool = false,
        composerFocusIsSuspended: Bool = false
    ) {
        self.peer = peer
        messagesOverride = messages
        self.marksThreadAsRead = marksThreadAsRead
        draftOverride = draft
        scrollBookmarkOverride = scrollBookmark
        self.showsProfileToolbar = showsProfileToolbar
        self.focusIsSuspended = focusIsSuspended
        self.composerFocusIsSuspended = composerFocusIsSuspended
    }

    var messages: [OGSPrivateMessage] {
        messagesOverride ?? ogs.privateMessagesByPeerId[peer.id] ?? []
    }

    @State private var localDrafts: [PrivateMessageTranscriptIdentity: String] = [:]
    @State private var localScrollBookmarks = LocalScrollBookmarks()

    private final class LocalScrollBookmarks {
        var byTranscript: [PrivateMessageTranscriptIdentity: PrivateMessageScrollBookmark] = [:]
    }

    private var scrollBookmark: PrivateMessageScrollBookmark {
        if let scrollBookmarkOverride { return scrollBookmarkOverride }
        let identity = PrivateMessageTranscriptIdentity(accountID: ogs.user?.id, peerID: peer.id)
        if let existing = localScrollBookmarks.byTranscript[identity] { return existing }
        let bookmark = PrivateMessageScrollBookmark()
        localScrollBookmarks.byTranscript[identity] = bookmark
        return bookmark
    }

    private var draft: Binding<String> {
        if let draftOverride { return draftOverride }
        let identity = PrivateMessageTranscriptIdentity(accountID: ogs.user?.id, peerID: peer.id)
        return Binding(
            get: { localDrafts[identity, default: ""] },
            set: { localDrafts[identity] = $0 }
        )
    }
    
    var body: some View {
        PrivateMessageTranscript(
            peerID: peer.id,
            messages: messages,
            marksThreadAsRead: marksThreadAsRead,
            isPresented: !focusIsSuspended,
            bookmark: scrollBookmark
        )
        .id(PrivateMessageTranscriptIdentity(accountID: ogs.user?.id, peerID: peer.id))
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileConversation)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrivateMessageComposer(
                peer: peer,
                ogs: ogs,
                allowsRemoteActivity: allowsRemoteActivity,
                focusIsSuspended: focusIsSuspended || composerFocusIsSuspended,
                draft: draft,
                sendSession: PrivateMessageSendSessions.session(for: ogs, peerID: peer.id)
            )
            .id(PrivateMessageTranscriptIdentity(accountID: ogs.user?.id, peerID: peer.id))
            .background(Color(uiColor: .systemBackground), ignoresSafeAreaEdges: [])
        }
        .toolbar {
            if showsProfileToolbar, peer.id > 0, let openPlayerProfile {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openPlayerProfile(peer)
                    } label: {
                        AsyncImage(url: allowsRemoteActivity ? peer.iconURL(ofSize: 64) : nil) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.crop.square.fill")
                                .resizable()
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text(
                        "View \(peer.username)’s profile",
                        comment: "Accessibility label for a button that opens a player's profile"
                    ))
                    .accessibilityValue(Text(verbatim: peer.usernameAndRank))
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileMessageToolbarEntry(peer.id))
                }
            }
        }
    }
}

#if DEBUG
#Preview("Private messages — Conversation", traits: .fixedLayout(width: 300, height: 600)) {
    let peer = OGSPrivateMessage.sampleData.first!.from
    let messages = OGSPrivateMessage.sampleData.filter {
        $0.from.id == peer.id || $0.to.id == peer.id
    }
    PrivateMessageLog(
        peer: peer,
        messages: messages,
        marksThreadAsRead: false
    )
        .environmentObject(
            OGSService.previewInstance(
                user: OGSUser(username: "hakhoa", id: 765826),
                privateMessages: []
            )
        )
        .environment(\.surroundAllowsRemoteActivity, false)
}
#endif
