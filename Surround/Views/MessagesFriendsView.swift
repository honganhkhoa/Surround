import SwiftUI

enum MessagesStyle {
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let searchField = Color(uiColor: .systemGray5)
    static let accent = Color.indigo
    static let paleAccent = Color.indigo.opacity(0.1)
}

struct MessageAvatar: View {
    @Environment(\.surroundAllowsRemoteActivity) private var allowsRemoteActivity
    let user: OGSUser
    var size: CGFloat = 44

    private var fallbackColor: Color {
        switch user.id.magnitude % 5 {
        case 0: Color(red: 0.87, green: 0.93, blue: 0.86)
        case 1: Color(red: 0.88, green: 0.89, blue: 0.98)
        case 2: Color(red: 0.85, green: 0.93, blue: 0.92)
        case 3: Color(red: 0.98, green: 0.91, blue: 0.79)
        default: Color(red: 0.96, green: 0.87, blue: 0.90)
        }
    }

    var body: some View {
        AsyncImage(url: allowsRemoteActivity ? user.iconURL(ofSize: Int(size * 2)) : nil) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Text(verbatim: String(user.username.prefix(1)).uppercased())
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(user.uiColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(fallbackColor)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(9, size * 0.23)))
        .accessibilityHidden(true)
    }
}

struct MessagesRequestRow: View {
    @Environment(\.openPlayerProfile) private var openPlayerProfile
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let invitation: OGSFriendInvitation

    private var profileAccessibilityValue: Text {
        let rank = Text(verbatim: invitation.fromUser.formattedRank)
        guard let created = invitation.created else { return rank }
        return rank + Text(verbatim: ", ")
            + Text(created, format: .relative(presentation: .named))
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 9))
        return layout {
            Button {
                openPlayerProfile?(invitation.fromUser)
            } label: {
                HStack(spacing: 9) {
                    MessageAvatar(user: invitation.fromUser, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: invitation.fromUser.username)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(invitation.fromUser.uiColor)
                            .lineLimit(1)
                        HStack(spacing: 3) {
                            Text(verbatim: invitation.fromUser.formattedRank)
                            if let created = invitation.created {
                                Text("·")
                                Text(created, format: .relative(presentation: .named))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text("View \(invitation.fromUser.username)’s profile"))
            .accessibilityValue(profileAccessibilityValue)
            .accessibilityIdentifier(
                SurroundUITestContract.AccessibilityID.friendRequestProfile(invitation.fromUser.id)
            )
            FriendshipControls(user: invitation.fromUser, presentation: .inboxRow)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 140)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 60)
        .accessibilityElement(children: .contain)
    }
}

struct MessagesRetryCard: View {
    let title: LocalizedStringKey
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(verbatim: message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Try Again", action: retry)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(MessagesStyle.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct MessagesFriendsSection: View {
    @EnvironmentObject private var ogs: OGSService
    @Binding var isExpanded: Bool
    let selectedPeerID: Int?
    let recentPeerIDs: [Int]
    let onMessage: (OGSUser) -> Void

    @ScaledMetric(relativeTo: .caption2) private var cellWidth: CGFloat = 58
    @State private var rowContentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    private var orderedFriends: [OGSUser] {
        let friends = Dictionary(ogs.friends.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values.sorted {
                let comparison = $0.username.localizedStandardCompare($1.username)
                return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
            }
        let friendsByID = Dictionary(uniqueKeysWithValues: friends.map { ($0.id, $0) })
        var seen = Set<Int>()
        let recent = recentPeerIDs.compactMap { id -> OGSUser? in
            guard let friend = friendsByID[id], seen.insert(id).inserted else { return nil }
            return friend
        }
        return recent + friends.filter { !seen.contains($0.id) }
    }

    private var hasOverflow: Bool {
        viewportWidth > 0 && rowContentWidth > viewportWidth + 0.5
    }

    private var showsGrid: Bool { isExpanded && hasOverflow }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasOverflow {
                Button { isExpanded.toggle() } label: {
                    header
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Friends"))
                .accessibilityValue(showsGrid ? Text("Expanded") : Text("Collapsed"))
                .accessibilityIdentifier("messages.friends.toggle")
            } else {
                header
            }
            if let error = ogs.friendsError {
                MessagesRetryCard(title: "Couldn’t load friends", message: error, retry: ogs.fetchFriends)
            }
            if ogs.friendsLoading && ogs.friends.isEmpty {
                ProgressView("Loading friends…")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if ogs.friends.isEmpty {
                Text("No friends yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ZStack(alignment: .topLeading) {
                    // Retain the actual strip measurement while the grid is
                    // shown, so resizing and Dynamic Type still detect overflow.
                    friendsStrip
                        .opacity(showsGrid ? 0 : 1)
                        .accessibilityHidden(showsGrid)
                        .allowsHitTesting(!showsGrid)
                    if showsGrid {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: cellWidth), spacing: 8)],
                                  alignment: .leading, spacing: 10) {
                            ForEach(orderedFriends, id: \.id) { friend in
                                friendButton(friend)
                            }
                        }
                        .padding(12)
                        .background(MessagesStyle.card, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("messages.friends.grid")
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Friends").font(.headline)
            Text(verbatim: "\(orderedFriends.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if hasOverflow {
                Image(systemName: showsGrid ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MessagesStyle.accent)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var friendsStrip: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(orderedFriends, id: \.id) { friend in
                    friendButton(friend)
                }
            }
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowContentWidth = $0 }
        }
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
        .background(MessagesStyle.card, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("messages.friends.strip")
    }

    private func friendButton(_ friend: OGSUser) -> some View {
        Button { onMessage(friend) } label: {
            VStack(spacing: 5) {
                MessageAvatar(user: friend, size: 44)
                    .padding(3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(friend.id == selectedPeerID ? MessagesStyle.accent : .clear, lineWidth: 2)
                    }
                Text(verbatim: friend.username)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: cellWidth)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Message \(friend.username)"))
        .accessibilityAddTraits(friend.id == selectedPeerID ? .isSelected : [])
        .accessibilityIdentifier("messages.friend.message.\(friend.id)")
    }
}

struct MessagesPlayerSearchResults: View {
    @EnvironmentObject private var ogs: OGSService

    @Binding var query: String
    let onMessage: (OGSUser) -> Void

    private struct SearchIdentity: Hashable {
        let accountID: Int?
        let query: String
        let attempt: Int
    }

    private enum SearchPhase {
        case idle, loading, loaded, failed
    }

    @State private var attempt = 0
    @State private var results = [OGSUser]()
    @State private var phase: SearchPhase = .idle
    @State private var searchError = ""
    @State private var loadedIdentity: SearchIdentity?

    private var searchIdentity: SearchIdentity {
        SearchIdentity(accountID: ogs.user?.id, query: query, attempt: attempt)
    }

    private var friendResults: [OGSUser] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }
        let friendIDs = Set(ogs.friends.map(\.id))
        let matches = ogs.friends.filter { $0.username.localizedStandardContains(keyword) }
            + results.filter { friendIDs.contains($0.id) }
        return Dictionary(matches.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values.sorted { $0.username.localizedStandardCompare($1.username) == .orderedAscending }
    }

    private var otherResults: [OGSUser] {
        let friendIDs = Set(ogs.friends.map(\.id))
        return results.filter { !friendIDs.contains($0.id) }
    }

    private func search(identity: SearchIdentity) async {
        guard !Task.isCancelled, identity == searchIdentity else { return }
        // Native Back may restart the task while its successful results remain.
        if loadedIdentity == identity, case .loaded = phase { return }
        let keyword = identity.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            loadedIdentity = nil
            results = []
            phase = .idle
            return
        }
        loadedIdentity = nil
        results = []
        phase = .loading
        do {
            try await Task.sleep(for: .milliseconds(250))
            try Task.checkCancellation()
            for try await players in ogs.searchByUsername(keyword: keyword).values {
                try Task.checkCancellation()
                guard identity == searchIdentity else { return }
                results = players.filter { $0.id != ogs.user?.id && $0.id > 0 }
                phase = .loaded
                loadedIdentity = identity
                return
            }
            guard !Task.isCancelled, identity == searchIdentity else { return }
            phase = .loaded
            loadedIdentity = identity
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, identity == searchIdentity else { return }
            loadedIdentity = nil
            results = []
            searchError = error.localizedDescription
            phase = .failed
        }
    }

    var body: some View {
        let identity = searchIdentity
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch phase {
                case .idle:
                    ContentUnavailableView {
                        Label("Find players on OGS", systemImage: "person.crop.circle.badge.magnifyingglass")
                    } description: {
                        Text("Search by username to view a profile or start a conversation.")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                case .loading:
                    ProgressView("Searching…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                case .failed:
                    MessagesRetryCard(title: "Couldn’t search players",
                                      message: searchError, retry: { attempt += 1 })
                case .loaded:
                    if friendResults.isEmpty && otherResults.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        if !friendResults.isEmpty {
                            searchSection("Your friends", users: friendResults)
                        }
                        if !otherResults.isEmpty {
                            searchSection("Players on OGS", users: otherResults)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(MessagesStyle.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.screenMessages)
        .task(id: identity) {
            await search(identity: identity)
        }
    }

    private func searchSection(_ title: LocalizedStringKey, users: [OGSUser]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)
            LazyVStack(spacing: 0) {
                ForEach(users, id: \.id) { user in
                    MessagesSearchPlayerRow(user: user, onMessage: onMessage)
                    if user.id != users.last?.id {
                        Divider().padding(.leading, 62)
                    }
                }
            }
            .background(MessagesStyle.card, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct MessagesSearchPlayerRow: View {
    @EnvironmentObject private var ogs: OGSService
    @Environment(\.openPlayerProfile) private var openPlayerProfile
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let user: OGSUser
    let onMessage: (OGSUser) -> Void

    private struct RelationshipIdentity: Hashable {
        let accountID: Int?
        let playerID: Int
    }

    private var relationshipIdentity: RelationshipIdentity {
        RelationshipIdentity(accountID: ogs.user?.id, playerID: user.id)
    }

    private var relationship: OGSProfileFriendship? {
        ogs.friendship(for: user.id)
    }

    private var relationshipText: Text? {
        switch relationship {
        case .friends?: Text("· Friend")
        case .requestSent?: Text("· Request sent")
        case .requestReceived?: Text("· Wants to be friends")
        default: nil
        }
    }

    private var profileAccessibilityValue: Text {
        let rank = Text(verbatim: user.formattedRank)
        guard let relationshipText else { return rank }
        return rank + Text(verbatim: " ") + relationshipText
    }

    private func refreshRelationship() async {
        guard !Task.isCancelled, relationship == nil else { return }
        let identity = relationshipIdentity
        do {
            for try await _ in ogs.refreshFriendship(playerID: user.id, force: false).values {
                guard !Task.isCancelled, identity == relationshipIdentity else { return }
            }
        } catch {
            // Relationship details are informational; Profile owns its actions
            // and any friendship refresh errors.
        }
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Button {
                openPlayerProfile?(user)
            } label: {
                HStack(spacing: 10) {
                    MessageAvatar(user: user, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: user.username)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(user.uiColor)
                            .lineLimit(1)
                        HStack(spacing: 3) {
                            Text(verbatim: user.formattedRank)
                            if let relationshipText { relationshipText }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text("View \(user.username)’s profile"))
            .accessibilityValue(profileAccessibilityValue)
            .accessibilityIdentifier("messages.search.profile.\(user.id)")

            Button {
                onMessage(user)
            } label: {
                Image(systemName: "bubble.left")
                    .frame(width: 36, height: 36)
                    .background(MessagesStyle.paleAccent, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(MessagesStyle.accent)
            .accessibilityLabel(Text("Message \(user.username)"))
            .accessibilityIdentifier("messages.search.message.\(user.id)")
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 60)
        .task(id: relationshipIdentity) {
            await refreshRelationship()
        }
    }
}
