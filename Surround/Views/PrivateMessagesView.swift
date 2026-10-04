import SwiftUI

/// One native stack owns the full route history in compact and column layouts.
struct PrivateMessagesView: View {
    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var nav: NavigationService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.duoTabContext) private var duoTabContext
    @StateObject private var navigation = StackRouter()
    @State private var playerSearchQuery = ""
    @State private var isSearchingPlayers = false
    @FocusState private var searchFocused: Bool
    @State private var selectedPeer: OGSUser?
    @State private var usesColumns: Bool?
    @State private var friendsExpanded = false
    @State private var inboxPosition = ScrollPosition(idType: String.self, edge: .top)
    private var selectedPeerID: Int? { selectedPeer?.id }

    private var privateMessagesByPeerId: [Int: [OGSPrivateMessage]] { ogs.privateMessagesByPeerId }
    private var unreadPeerIds: Set<Int> { ogs.privateMessagesUnreadPeerIds }
    private var activePeerIds: Set<Int> { ogs.privateMessagesActivePeerIds }
    private func user(id: Int) -> OGSUser? {
        if let user = navigation.users[id] ?? ogs.cachedUsersById[id] { return user }
        if let friend = ogs.friends.first(where: { $0.id == id }) { return friend }
        guard let message = privateMessagesByPeerId[id]?.first else { return nil }
        return message.from.id == id ? message.from : message.to
    }
    private var data: [(peer: OGSUser, lastMessage: OGSPrivateMessage)] {
        activePeerIds.compactMap { id in
            guard let peer = user(id: id), let last = privateMessagesByPeerId[id]?.max(by: {
                $0.content.timestamp < $1.content.timestamp
            }) else { return nil }
            return (peer: peer, lastMessage: last)
        }.sorted { $0.lastMessage.content.timestamp > $1.lastMessage.content.timestamp }
    }
    private func openConversation(with peer: OGSUser, inColumns: Bool) {
        searchFocused = false
        selectedPeer = peer
        if !inColumns { navigation.presentMessagesConversation(peer) }
    }
    private func beginPlayerSearch() {
        setPlayerSearchActive(true)
        searchFocused = true
    }
    private func setPlayerSearchActive(_ active: Bool) {
        // Animate only entering/leaving player discovery, never fold geometry
        // or the keyboard-driven size of the navigation container.
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            isSearchingPlayers = active
        }
    }
    private func cancelPlayerSearch() {
        setPlayerSearchActive(false)
        searchFocused = false
        playerSearchQuery = ""
    }

    var body: some View {
        GeometryReader { container in
            // The native host remains measurable while a destination covers the
            // root. Its bounds also exclude sidebar/toolbar layout feedback.
            let size = duoTabContext?.layoutSize ?? container.size
            let mode: Bool? = size.width > 0 && size.height > 0
                ? MessagesColumnLayout(size: size, divisions: container.messagesDivisionFrames).usesColumns : nil
            AppNavigationStack(rootView: .privateMessages, router: navigation) {
                GeometryReader { geometry in
                    let layout = MessagesColumnLayout(size: geometry.size,
                        divisions: geometry.messagesDivisionFrames, usesColumns: usesColumns)
                    HStack(spacing: 0) {
                        inbox(inColumns: layout.usesColumns, availableHeight: geometry.size.height)
                            .frame(width: layout.inboxWidth)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("messages.inboxPane")
                        if layout.usesColumns {
                            Color.clear
                                .frame(width: 1)
                                .background(Color(uiColor: .separator), ignoresSafeAreaEdges: .bottom)
                                .frame(width: layout.gap)
                                .accessibilityHidden(true)
                            Group {
                                if let selectedPeer {
                                    MessagesConversationView(peer: selectedPeer, isPane: true)
                                } else {
                                    ContentUnavailableView("Select a conversation", systemImage: "bubble.left.and.bubble.right",
                                        description: Text("Choose a conversation or a friend to start messaging."))
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("messages.detailPane")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.screenMessages)
                    .onChange(of: data.map { $0.peer.id }, initial: true) { _, _ in
                        selectInitialPeer(inColumns: layout.usesColumns)
                    }
                    #if DEBUG
                    .onChange(of: [CGRect(origin: .zero, size: geometry.size)] + geometry.messagesDivisionFrames, initial: true) { _, _ in
                        if ProcessInfo.processInfo.environment["SURROUND_DUO_SIDEBAR_DIAGNOSTICS"] == "1" {
                            print("MESSAGES-LAYOUT size=\(geometry.size) divisions=\(geometry.messagesDivisionFrames) columns=\(layout.usesColumns) inbox=\(layout.inboxWidth) gap=\(layout.gap)")
                        }
                    }
                    #endif
                }
                .background(MessagesStyle.canvas)
                .navigationTitle("Messages")
                .navigationBarTitleDisplayMode(.large)
            }
            .onChange(of: mode, initial: true) { _, wide in
                guard let wide else { return }
                // One permanent owner reconciles only real layout edges. Back
                // to the compact inbox must not reopen the retained peer.
                if let previous = usesColumns, previous != wide {
                    navigation.showMessagesColumns(wide, peer: selectedPeer)
                }
                usesColumns = wide
                selectInitialPeer(inColumns: wide)
                #if DEBUG
                if ProcessInfo.processInfo.environment["SURROUND_DUO_SIDEBAR_DIAGNOSTICS"] == "1" {
                    print("MESSAGES-MODE size=\(size) columns=\(wide) path=\(navigation.path)")
                }
                #endif
            }
        }
        .onChange(of: navigation.path) { _, _ in searchFocused = false }
        .onChange(of: ogs.user?.id) { _, _ in
            navigation.path = []
            selectedPeer = nil
            searchFocused = false
            isSearchingPlayers = false
            playerSearchQuery = ""
            friendsExpanded = false
            inboxPosition = ScrollPosition(idType: String.self, edge: .top)
        }
    }

    private func selectInitialPeer(inColumns: Bool) {
        if inColumns && selectedPeer == nil { selectedPeer = data.first?.peer }
    }

    private func inbox(inColumns: Bool, availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            searchBar
            ZStack(alignment: .top) {
                if isSearchingPlayers {
                    MessagesPlayerSearchResults(query: $playerSearchQuery) { peer in
                        openConversation(with: peer, inColumns: inColumns)
                    }
                    .transition(.opacity)
                } else {
                    inboxSections(expanded: inColumns, availableHeight: availableHeight)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background {
            MessagesStyle.canvas.ignoresSafeArea(edges: .bottom)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search players", text: $playerSearchQuery)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($searchFocused).submitLabel(.search)
                    .accessibilityIdentifier("messages.playerSearchField")
                if !playerSearchQuery.isEmpty {
                    Button { playerSearchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Clear search")
                }
            }
            .font(.subheadline).padding(.horizontal, 14).frame(minHeight: 42)
            .background(MessagesStyle.searchField, in: Capsule())
            if isSearchingPlayers {
                Button("Cancel", action: cancelPlayerSearch)
                    .font(.subheadline).accessibilityIdentifier("messages.cancelPlayerSearch")
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .onChange(of: searchFocused) { _, focused in
            if focused { setPlayerSearchActive(true) }
        }
    }

    private func inboxSections(expanded: Bool, availableHeight: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !ogs.friendInvitations.isEmpty || ogs.friendInvitationsLoading
                    || ogs.friendInvitationsError != nil {
                    requestsSection.id("messages.requests")
                }

                if !ogs.friends.isEmpty || ogs.friendsLoading || ogs.friendsError != nil {
                    MessagesFriendsSection(isExpanded: $friendsExpanded, selectedPeerID: expanded ? selectedPeerID : nil,
                        recentPeerIDs: data.map { $0.peer.id }) { peer in
                            openConversation(with: peer, inColumns: expanded)
                        }
                        .id("messages.friends")
                }

                if data.isEmpty && ogs.friends.isEmpty && ogs.friendInvitations.isEmpty
                    && !ogs.friendsLoading && !ogs.friendInvitationsLoading {
                    discoveryEmptyState(expanded: expanded)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: max(300, availableHeight - 170))
                } else {
                    conversationsSection(expanded: expanded).id("messages.conversations")
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($inboxPosition)
        .accessibilityIdentifier("messages.inboxScroll")
    }

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Friend requests")
                    .font(.headline)
                if !ogs.friendInvitations.isEmpty {
                    Text(verbatim: "\(ogs.friendInvitations.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MessagesStyle.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(MessagesStyle.paleAccent, in: Capsule())
                }
            }
            if ogs.friendInvitationsLoading && ogs.friendInvitations.isEmpty {
                ProgressView("Loading friend requests…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(MessagesStyle.card, in: RoundedRectangle(cornerRadius: 16))
            }
            if let error = ogs.friendInvitationsError {
                MessagesRetryCard(title: "Couldn’t load friend requests",
                                  message: error, retry: ogs.fetchFriends)
            }
            if !ogs.friendInvitations.isEmpty {
                VStack(spacing: 0) {
                    ForEach(ogs.friendInvitations) { invitation in
                        MessagesRequestRow(invitation: invitation)
                        if invitation.id != ogs.friendInvitations.last?.id {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(MessagesStyle.card, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func conversationsSection(expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Conversations")
                .font(.headline)
            if data.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left")
                        .font(.title2)
                        .foregroundStyle(MessagesStyle.accent)
                        .frame(width: 54, height: 54)
                        .background(MessagesStyle.paleAccent, in: Circle())
                    Text("No conversations yet")
                        .font(.headline)
                    Text("Tap a friend to send a message or a challenge, or search for any player on OGS.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 30)
                .background(MessagesStyle.card, in: RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 0) {
                    ForEach(data, id: \.peer.id) { peer, lastMessage in
                        Button {
                            openConversation(with: peer, inColumns: expanded)
                        } label: {
                            MessagesConversationRow(
                                peer: peer, lastMessage: lastMessage,
                                isUnread: unreadPeerIds.contains(peer.id),
                                isSelected: expanded && selectedPeerID == peer.id
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(expanded && selectedPeerID == peer.id ? .isSelected : [])
                        .accessibilityIdentifier(
                            SurroundUITestContract.AccessibilityID.privateMessageRow(peer.id)
                        )
                        .contextMenu {
                            if peer.id > 0 {
                                Button {
                                    navigation.openProfile(peer)
                                } label: {
                                    Text("View Profile")
                                    Text(verbatim: peer.usernameAndRank)
                                    Image(systemName: "person.crop.circle")
                                }
                                .accessibilityIdentifier(
                                    SurroundUITestContract.AccessibilityID.profileMessageMenuEntry(peer.id)
                                )
                            }
                        }
                        if peer.id != data.last?.peer.id {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .background(MessagesStyle.card, in: RoundedRectangle(cornerRadius: 16))
                Text("Private messages are only stored for a few days, so please make sure to save any important information somewhere else.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
        }
    }

    private func discoveryEmptyState(expanded: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(MessagesStyle.accent)
                .frame(width: 74, height: 74)
                .background(MessagesStyle.paleAccent, in: Circle())
            Text("No conversations yet")
                .font(.title3.bold())
            Text("Search for a player by username to message them, challenge them, or add them as a friend. Friend requests you receive show up here too.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                beginPlayerSearch()
            } label: {
                Label("Find players", systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 44)
                    .background(MessagesStyle.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 300)
        .padding(.vertical, 28)
    }

}

private struct MessagesConversationRow: View {
    let peer: OGSUser
    let lastMessage: OGSPrivateMessage
    let isUnread: Bool
    let isSelected: Bool

    private var timeLabel: String {
        let date = Date(timeIntervalSince1970: lastMessage.content.timestamp)
        if Calendar.current.isDateInToday(date) {
            return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        }
        if Calendar.current.isDateInYesterday(date) {
            return String(localized: "Yesterday")
        }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }

    var body: some View {
        HStack(spacing: 12) {
            MessageAvatar(user: peer, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: peer.username)
                    .font(.subheadline.weight(isUnread ? .bold : .semibold))
                    .foregroundStyle(peer.uiColor)
                    .lineLimit(1)
                Text(verbatim: lastMessage.content.message)
                    .font(.subheadline.weight(isUnread ? .semibold : .regular))
                    .foregroundStyle(isUnread ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 8) {
                Text(verbatim: timeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if isUnread {
                    Circle()
                        .fill(MessagesStyle.accent)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(Text("Unread"))
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 68)
        .background(isSelected ? MessagesStyle.paleAccent : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isUnread ? Text("Unread conversation") : Text(""))
    }
}


/// Wide conversation actions belong to the content header. Compact actions use
/// native navigation chrome; Profile and Challenge retain the stack's Back.
struct MessagesConversationView: View {
    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var navigation: StackRouter
    @Environment(\.owningStackRoute) private var owningStackRoute
    @Environment(\.isVerticalToolbar) private var isVerticalToolbar
    let peer: OGSUser
    var isPane = false

    var body: some View {
        conversationContent
        .modifier(MessagesConversationNavigation(isPane: isPane, title: peer.username))
        .toolbar {
            if isPane && isVerticalToolbar {
                AppVerticalToolbarGroup {
                    challengeButton
                    profileButton
                }
            } else if !isPane {
                ToolbarItem(placement: .principal) { peerHeading }
                if isVerticalToolbar {
                    AppVerticalToolbarGroup {
                        challengeButton
                        profileButton
                    }
                } else {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        challengeButton
                        profileButton
                    }
                }
            }
        }
        .appTabBarHidden(!isPane)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("messages.conversation")
    }

    private var conversationContent: some View {
        VStack(spacing: 0) {
            if isPane {
                HStack(spacing: 10) {
                    MessageAvatar(user: peer, size: 36)
                    peerHeading
                    Spacer(minLength: 0)
                    if !isVerticalToolbar {
                        HStack(spacing: 0) {
                            challengeButton
                            profileButton
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 64)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("messages.conversation.heading")
                Divider()
            }
            PrivateMessageLog(peer: peer,
                marksThreadAsRead: navigation.path.last == owningStackRoute
                    && navigation.isActive,
                draft: navigation.conversationDraft(for: peer.id, accountID: ogs.user?.id),
                scrollBookmark: navigation.conversationScrollBookmark(for: peer.id, accountID: ogs.user?.id),
                showsProfileToolbar: false,
                focusIsSuspended: navigation.path.last != owningStackRoute
                    || !navigation.isActive)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var peerHeading: some View {
        VStack(alignment: isPane ? .leading : .center, spacing: 2) {
            Text(verbatim: peer.username).font(.headline)
                .foregroundStyle(peer.uiColor).lineLimit(1)
            HStack(spacing: 4) {
                Text(verbatim: peer.formattedRank)
                if ogs.friendship(for: peer.id) == .friends { Text("· Friend") }
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    private var challengeButton: some View {
        Button { navigation.openChallenge(for: peer) } label: {
            Image("custom.squareshape.split.3x3.bubble.right")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .tint(MessagesStyle.accent)
        .accessibilityLabel(Text("Challenge \(peer.username)"))
        .accessibilityIdentifier("messages.challenge.\(peer.id)")
    }
    private var profileButton: some View {
        Button { navigation.openProfile(peer) } label: {
            Image(systemName: "person.crop.circle")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("View \(peer.username)’s profile"))
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileMessageToolbarEntry(peer.id))
    }
}

private struct MessagesConversationNavigation: ViewModifier {
    let isPane: Bool
    let title: String

    @ViewBuilder func body(content: Content) -> some View {
        if isPane { content }
        else { content.navigationTitle(title).navigationBarTitleDisplayMode(.inline) }
    }
}
