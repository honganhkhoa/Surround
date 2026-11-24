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
    @State private var playerSearchPhase: MessagesPlayerSearchPhase = .idle
    @FocusState private var searchFocused: Bool
    @State private var selectedPeer: OGSUser?
    @State private var usesColumns: Bool?
    @State private var friendsExpanded = false
    @State private var inboxPosition = ScrollPosition(idType: String.self, edge: .top)
    /// Friend requests accepted or rejected here, by player id. Each keeps
    /// its row, showing the result, until the inbox goes off screen or the
    /// player sends a new request.
    @State private var requestResults: [Int: MessagesRequestResult] = [:]
    /// Requests acted on here whose confirmation hasn't come yet.
    @State private var actingRequests: [Int: RequestPlace] = [:]
    @AccessibilityFocusState private var requestFocus: MessagesRequestFocus?
    private var selectedPeerID: Int? { selectedPeer?.id }

    /// Where a request was when the user acted on it.
    private struct RequestPlace {
        /// The request shown before it, if any.
        let after: Int?
    }

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
        playerSearchPhase = .idle
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
                                .background {
                                    Color(uiColor: .separator)
                                        .ignoresSafeArea(.all, edges: .vertical)
                                }
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
                    .background(alignment: .leading) {
                        // Paint up to the separator at the center of the native
                        // division clearance; keep pane controls out of it.
                        // Extend only the paint through keyboard clearance so
                        // a tabletop fold does not expose the white backing.
                        MessagesStyle.canvas
                            .frame(width: layout.inboxWidth + layout.gap / 2)
                            .clipped()
                            .ignoresSafeArea(.all, edges: .vertical)
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
                .background(usesColumns == true ? Color(uiColor: .systemBackground) : MessagesStyle.canvas)
                .navigationTitle("Messages")
                .navigationBarTitleDisplayMode(usesColumns == true ? .inline : .large)
                .toolbar {
                    if #available(iOS 26.0, *) {
                        ToolbarItem(placement: .topBarTrailing) {
                            loadingIndicator
                        }
                        .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .topBarTrailing) {
                            loadingIndicator
                        }
                    }
                }
                // Request results go once the inbox is off screen, covered by
                // what it pushed or left for another tab. Going as a push
                // starts would collapse the rows while the inbox slides away.
                .onDisappear { clearRequestResults() }
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
            playerSearchPhase = .idle
            playerSearchQuery = ""
            friendsExpanded = false
            inboxPosition = ScrollPosition(idType: String.self, edge: .top)
            clearRequestResults()
        }
        .onReceive(ogs.$friendshipNotice.compactMap { $0 }) { keepRequestResult($0) }
        .onChange(of: ogs.friendInvitations.map(\.id)) { _, ids in dropSupersededResults(listing: ids) }
    }

    /// A request accepted or rejected here keeps its row, showing what came
    /// of it. When VoiceOver was on the row's controls, the result takes
    /// focus and the row claims the notice as it arrives, so the window,
    /// which decides a turn later, doesn't speak it too.
    private func keepRequestResult(_ notice: OGSFriendshipNotice) {
        switch notice.action {
        case .accept, .reject: break
        case .send, .remove: return
        }
        let id = notice.user.id
        guard let place = actingRequests.removeValue(forKey: id) else { return }
        let order = (requestResults.values.map(\.order).max() ?? 0) + 1
        requestResults[id] = MessagesRequestResult(user: notice.user, action: notice.action,
                                                   after: place.after, order: order)
        if MessagesRequestFocus.resultTakesFocus(from: requestFocus, row: id) {
            requestFocus = .result(id)
            nav.friendshipConfirmations.claim(notice.id)
        }
    }

    private func clearRequestResults() {
        if !requestResults.isEmpty { requestResults = [:] }
        if !actingRequests.isEmpty { actingRequests = [:] }
    }

    /// Accepting or rejecting takes a request out of the service's list
    /// before its result is kept, so a listed request whose player has a
    /// result here is a new one. Its old result goes, and the request shows
    /// with its Accept and Reject.
    private func dropSupersededResults(listing ids: [Int]) {
        let standing = ResolvedRowOrder.standing(requestResults, live: ids)
        if standing.count != requestResults.count { requestResults = standing }
    }

    /// The live requests in the service's order, with each resolved one back
    /// in its place.
    private var requestRowIDs: [Int] {
        ResolvedRowOrder.merge(
            live: ogs.friendInvitations.map(\.id),
            resolved: requestResults.values.sorted { $0.order < $1.order }.map { (id: $0.user.id, after: $0.after) }
        )
    }

    /// What a request row tells the inbox: where it was when the user acted.
    private func requestHooks(for id: Int, in ids: [Int]) -> MessagesRequestHooks {
        MessagesRequestHooks(focus: $requestFocus) { _ in
            let index = ids.firstIndex(of: id) ?? 0
            actingRequests[id] = RequestPlace(after: index > 0 ? ids[index - 1] : nil)
        }
    }

    private func selectInitialPeer(inColumns: Bool) {
        #if DEBUG && MAIN_APP
        if SurroundUITestContract.isEnabled,
           ProcessInfo.processInfo.arguments.contains(SurroundUITestContract.messagesInitialOpeningLaunchArgument) {
            // Wait for the permanent host's layout before any initial selection.
            guard let wide = usesColumns, navigation.path.isEmpty, selectedPeer == nil,
                  let peer = user(id: 765826) else { return }
            openConversation(with: peer, inColumns: wide)
            return
        }
        #endif
        if inColumns && selectedPeer == nil { selectedPeer = data.first?.peer }
    }

    private func inbox(inColumns: Bool, availableHeight: CGFloat) -> some View {
        ZStack(alignment: .top) {
            if isSearchingPlayers {
                MessagesPlayerSearchResults(query: $playerSearchQuery, phase: $playerSearchPhase) { peer in
                    openConversation(with: peer, inColumns: inColumns)
                }
                .transition(.opacity)
            } else {
                inboxSections(expanded: inColumns, availableHeight: availableHeight)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .top, spacing: 0) {
            // Keep the scroll view at the navigation edge so it owns native
            // large-title collapse, while search stays pinned above its content.
            searchBar.background(MessagesStyle.canvas, ignoresSafeAreaEdges: [])
        }
    }

    private var loadingIndicator: some View {
        let searching = isSearchingPlayers && playerSearchPhase == .loading
        let loading = searching || ogs.friendsLoading || ogs.friendInvitationsLoading
        let label: Text = if searching {
            Text("Searching…")
        } else if ogs.friendsLoading && ogs.friendInvitationsLoading {
            Text("\(Text("Loading friends…")), \(Text("Loading friend requests…"))")
        } else if ogs.friendInvitationsLoading {
            Text("Loading friend requests…")
        } else {
            Text("Loading friends…")
        }
        return ZStack {
            Color.clear.accessibilityHidden(true)
            if loading {
                ProgressView()
                    .accessibilityLabel(label)
                    .accessibilityIdentifier("messages.loadingStatus")
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: ""))
        .accessibilityIdentifier("messages.loadingSlot")
        .accessibilityHidden(!loading)
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
                if !ogs.friendInvitations.isEmpty || ogs.friendInvitationsError != nil || !requestResults.isEmpty {
                    requestsSection.id("messages.requests")
                }

                if !ogs.friends.isEmpty || ogs.friendsError != nil {
                    MessagesFriendsSection(isExpanded: $friendsExpanded, selectedPeerID: expanded ? selectedPeerID : nil,
                        recentPeerIDs: data.map { $0.peer.id }) { peer in
                            openConversation(with: peer, inColumns: expanded)
                        }
                        .id("messages.friends")
                }

                if data.isEmpty && ogs.friends.isEmpty && ogs.friendInvitations.isEmpty && requestResults.isEmpty {
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
            if let error = ogs.friendInvitationsError {
                MessagesRetryCard(title: "Couldn’t load friend requests",
                                  message: error, retry: ogs.fetchFriends)
            }
            let ids = requestRowIDs
            if !ids.isEmpty {
                let invitations = Dictionary(ogs.friendInvitations.map { ($0.id, $0) },
                                             uniquingKeysWith: { first, _ in first })
                VStack(spacing: 0) {
                    ForEach(ids, id: \.self) { id in
                        // A listed request is newer than any result for its
                        // player, which goes once the inbox sees it.
                        if let invitation = invitations[id] {
                            MessagesRequestRow(invitation: invitation, hooks: requestHooks(for: id, in: ids))
                        } else if let result = requestResults[id] {
                            MessagesResolvedRequestRow(result: result, focus: $requestFocus)
                        }
                        if id != ids.last {
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
/// While a live game needs you, a control before Challenge and Profile shows
/// it (`ConversationGameControlPlacement`); a tap opens it through Home, and
/// the draft stays.
struct MessagesConversationView: View {
    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var nav: NavigationService
    @EnvironmentObject private var navigation: StackRouter
    @Environment(\.owningStackRoute) private var owningStackRoute
    @Environment(\.isVerticalToolbar) private var isVerticalToolbar
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.gameControlWindowClass) private var gameControlWindowClass
    /// Set only in a stack with an Activity list, whose status turns the
    /// composer off while offline.
    @Environment(\.activityConnection) private var activityConnection
    /// The window's, which turns the composer off elsewhere.
    @Environment(\.connectionStatus) private var windowConnection
    @Environment(\.iPadTabContext) private var iPadTabContext
    @Environment(\.duoTabContext) private var duoTabContext
    /// Redraws the control where time alone changes it: as a started game's
    /// lead ends.
    @StateObject private var gameControlDeadlines = GameControlDeadlines()
    let peer: OGSUser
    var isPane = false

    var body: some View {
        // One read of the window's state for the control, in the pass that
        // builds the bar. A pushed conversation's is the pass that hides the
        // tab bar, so the item is there or not from the first frame, and a
        // pass inside that call gives the same answer.
        let control = gameControl()
        conversationContent(headingControl: control.item(at: .headingChip))
        .modifier(MessagesConversationNavigation(isPane: isPane, title: peer.username))
        .toolbar {
            if isPane && isVerticalToolbar {
                if let rail = control.item(at: .railIcon) {
                    AppVerticalToolbarGroup { rail }
                }
                AppVerticalToolbarGroup {
                    challengeButton
                    profileButton
                }
            } else if !isPane {
                ToolbarItem(placement: .principal) { peerHeading }
                if isVerticalToolbar {
                    if let rail = control.item(at: .railIcon) {
                        AppVerticalToolbarGroup { rail }
                    }
                    AppVerticalToolbarGroup {
                        challengeButton
                        profileButton
                    }
                } else {
                    // Independent conditions (one is true at most), so the
                    // icon and the chip are each an item of their own.
                    if let icon = control.item(at: .barIcon) ?? control.item(at: .macToolbarIcon) {
                        ToolbarItem(placement: .topBarTrailing) { icon }
                    }
                    if let chip = control.item(at: .barChip) {
                        ToolbarItem(placement: .topBarTrailing) { chip }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        challengeButton
                        profileButton
                    }
                }
            }
        }
        .appTabBarHidden(!isPane)
        // Pushed or in the side pane, a conversation hides Activity's bar.
        // The pane keeps the tab bar.
        .activityPlace(.conversation)
        // Off screen no deadline, which stops the control's timer.
        .onChange(of: isOnScreen ? control.deadlines : GameControlDeadlines.Plan(), initial: true) { _, plan in
            gameControlDeadlines.follow(plan, now: control.now)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("messages.conversation")
    }

    private static var isCatalyst: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    /// On top of its stack, in the window's selected tab, as the thread is
    /// marked read.
    private var isOnScreen: Bool {
        navigation.path.last == owningStackRoute && navigation.isActive
    }

    /// The control from one read of the window's state
    /// (`ActivityModel.conversationControl`), where its placement shows one.
    /// The window's traits choose the placement, never a measured width.
    private func gameControl() -> ConversationGameControl {
        let placement = ConversationGameControlPlacement(.init(
            isPane: isPane, isInActivityStack: activityConnection != nil, isVerticalToolbar: isVerticalToolbar,
            isCompactWidth: horizontalSizeClass == .compact, isCompactHeight: verticalSizeClass == .compact,
            isCatalyst: Self.isCatalyst))
        guard let form = placement.form else {
            return ConversationGameControl(placement: placement, item: nil, deadlines: .init(), now: 0)
        }
        let input = ActivityModel.Input.window(ogs: ogs, nav: nav, place: .conversation)
        let slot = GameControlSlot(conversation: input)
        var control = ConversationGameControl(placement: placement, item: nil,
                                              deadlines: .init(conversation: input, slot: slot), now: input.now)
        guard let slot, let gameID = slot.gameID,
              let game = ogs.liveGames.first(where: { $0.ogsID == gameID }) else { return control }
        // Through Home, as every route but Home's own shows another game:
        // the stacks pop, and the draft stays in the window's store.
        let show: (Int) -> Void = { [ogs, nav] id in
            guard let game = ogs.liveGames.first(where: { $0.ogsID == id }) else { return }
            GameControlSwitch.throughHome.perform(game, navigation: nav) { _ in }
        }
        if form.isNative, let native = GameControlNativeItem(slot, allowsPicker: false) {
            // Spoken as Zen's: no time in the label, and a tap shows the game.
            let spoken = GameControlAccessibility(slot, form: form, isZen: true, allowsPicker: false,
                                                  name: Self.opponentName(in: game))
            if #available(iOS 26.0, *) {
                control.item = AnyView(GameControlZenNativeButton(item: native, label: spoken.label,
                                                                  hint: spoken.hint, role: .conversation) {
                    show(gameID)
                })
            } else {
                control.item = AnyView(GameControlBadgedIconButton(item: native, label: spoken.label,
                                                                   hint: spoken.hint, role: .conversation) {
                    show(gameID)
                })
            }
        } else {
            control.item = AnyView(GameControlZenTopBarItem(model: GameControlItemModel(
                slot: slot, windowClass: gameControlWindowClass, modeCount: 0,
                sizeCategory: UIContentSizeCategory(dynamicTypeSize), allowsPicker: false, game: game,
                challenger: nil, show: show, openPopover: {}, role: .conversation)))
        }
        return control
    }

    private static func opponentName(in game: Game) -> String {
        guard let color = game.userStoneColor else { return "" }
        return game.currentPlayer(with: color.opponentColor())?.username ?? ""
    }

    private func conversationContent(headingControl: AnyView?) -> some View {
        VStack(spacing: 0) {
            if isPane {
                HStack(spacing: 10) {
                    MessageAvatar(user: peer, size: 36)
                    peerHeading
                    Spacer(minLength: 0)
                    if !isVerticalToolbar {
                        HStack(spacing: 0) {
                            if let headingControl { headingControl }
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
            MessagesConversationLog(drafts: nav.conversationDrafts,
                connection: activityConnection ?? windowConnection ?? .neverOffline,
                socket: ogs.socketStatus, statusLine: statusLinePlace, peer: peer,
                accountID: ogs.user?.id,
                marksThreadAsRead: navigation.path.last == owningStackRoute
                    && navigation.isActive,
                focusIsSuspended: navigation.path.last != owningStackRoute
                    || !navigation.isActive,
                composerFocusIsSuspended: nav.main.accountSheet != nil,
                header: endedLine)
        }
        .background(Color(uiColor: .systemBackground))
    }

    /// What the composer's status line shows beside. Inside Activity's
    /// stack nothing of the root's shows beside it, so its line always does.
    private var statusLinePlace: MessagesConversationLog.StatusLinePlace {
        guard activityConnection == nil else { return .alone }
        return .besideRoot(isPane: isPane, placement: connectionPlacement, nowRowSaysStatus: nowRowSaysStatus)
    }

    /// Where the window says its status, from its container's facts.
    private var connectionPlacement: ActivityHostPolicy.ConnectionStatus {
        let container: ActivityHostPolicy.Container = iPadTabContext != nil ? .iPadTabContainer
            : duoTabContext != nil ? .duoTabContainer : .swiftUITabView
        return ActivityHostPolicy.hosts(for: .current(container), overrides: ActivityBarHosting.overrides(afterLaunch: true))
            .connectionStatus
    }

    /// The window's Now section says the status beside the conversation: on
    /// the Mac, whose sidebar always shows, or on iPad while the sidebar's
    /// copy says it shows and the window has room for a row.
    private var nowRowSaysStatus: Bool {
        let bar = nav.activityBar
        guard bar.nowSectionSaysStatus, bar.nowSectionRows > 0 else { return false }
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return iPadTabContext?.activitySidebar == .shown
        #endif
    }

    /// Above the composer while this session's superchat ending for the
    /// peer, live or missed, is newer than every message in the conversation.
    private var endedLine: AnyView? {
        guard ogs.showsSuperchatEndedLine(peerID: peer.id) else { return nil }
        return AnyView(
            Text("The moderator ended this chat.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.messagesSuperchatEnded))
    }

    private var peerHeading: some View {
        Button { navigation.openProfile(peer) } label: {
            VStack(alignment: isPane ? .leading : .center, spacing: 2) {
                Text(verbatim: peer.username).font(.headline)
                    .foregroundStyle(peer.uiColor).lineLimit(1)
                HStack(spacing: 4) {
                    Text(verbatim: peer.formattedRank)
                    if ogs.friendship(for: peer.id) == .friends { Text("· Friend") }
                }.font(.caption).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("View \(peer.username)’s profile"))
        .accessibilityValue(ogs.friendship(for: peer.id) == .friends
            ? Text("\(Text(verbatim: peer.formattedRank)) \(Text("· Friend"))")
            : Text(verbatim: peer.formattedRank))
        .accessibilityIdentifier("messages.conversation.profile.\(peer.id)")
    }

    private var challengeButton: some View {
        Button { navigation.openChallenge(for: peer) } label: {
            Image("custom.squareshape.split.3x3.bubble.right")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
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

/// A conversation's control in one pass: where it goes and the item it
/// draws there.
private struct ConversationGameControl {
    var placement: ConversationGameControlPlacement
    /// Nil while no live game needs you, or where no control goes.
    var item: AnyView?
    /// When time alone changes the control.
    var deadlines: GameControlDeadlines.Plan
    /// When the state was read, in seconds since 1970.
    var now: TimeInterval

    /// The item, where the control goes at `placement`.
    func item(at placement: ConversationGameControlPlacement) -> AnyView? {
        self.placement == placement ? item : nil
    }
}

/// The transcript and composer, with the draft and reading position from
/// the window's store. Only this view observes the store, so a keystroke
/// redraws the window's conversations, including a second composer for the
/// same peer, and never the stacks or games around them. The composer is
/// off while the window's connection is down or not yet up (inside
/// Activity's stack, the list's), as the moderator cover's is, and Activity's
/// offline line above it says why, unless a root carrier beside it says so
/// (`ConversationStatusLine`).
private struct MessagesConversationLog: View {
    /// What the composer's status line shows beside.
    enum StatusLinePlace {
        /// Nothing of the root's: inside Activity's stack.
        case alone
        /// The window's root carriers, as `ConversationStatusLine` reads them.
        case besideRoot(isPane: Bool, placement: ActivityHostPolicy.ConnectionStatus, nowRowSaysStatus: Bool)
    }

    @ObservedObject var drafts: ConversationDraftStore
    @ObservedObject var connection: ConnectionStatusSource
    /// The window's socket, which tells a first attempt from a reconnect.
    let socket: OGSWebsocketStatus
    let statusLine: StatusLinePlace
    let peer: OGSUser
    let accountID: Int?
    let marksThreadAsRead: Bool
    let focusIsSuspended: Bool
    let composerFocusIsSuspended: Bool
    let header: AnyView?

    var body: some View {
        PrivateMessageLog(peer: peer,
            marksThreadAsRead: marksThreadAsRead,
            draft: drafts.draft(for: peer.id, accountID: accountID),
            scrollBookmark: drafts.scrollBookmark(for: peer.id, accountID: accountID),
            showsProfileToolbar: false,
            focusIsSuspended: focusIsSuspended,
            composerFocusIsSuspended: composerFocusIsSuspended,
            composer: .init(isOffline: connection.dimsActivityActions, header: composerHeader))
    }

    /// Offline, Activity's line where no root carrier beside says the
    /// status, then Messages' ended line if any.
    private var composerHeader: AnyView? {
        guard connection.dimsActivityActions, showsStatusLine else { return header }
        return AnyView(VStack(spacing: 6) {
            ActivityStatusLine(
                connection: connection, socket: socket,
                statusIdentifier: SurroundUITestContract.AccessibilityID.activityConversationStatus,
                retryIdentifier: SurroundUITestContract.AccessibilityID.activityConversationStatusRetry)
            if let header { header }
        })
    }

    private var showsStatusLine: Bool {
        switch statusLine {
        case .alone:
            return true
        case .besideRoot(let isPane, let placement, let nowRowSaysStatus):
            let words = RootConnectionLine.words(status: connection.status, hasConnected: connection.hasConnected,
                                                 socket: socket)
            return ConversationStatusLine.shows(words, isPane: isPane, placement: placement,
                                                nowRowSaysStatus: nowRowSaysStatus)
        }
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
