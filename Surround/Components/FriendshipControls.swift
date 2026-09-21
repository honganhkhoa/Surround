import SwiftUI

/// Both Home and profiles use these controls and the service's per-player busy
/// state, so navigating during a request cannot submit it a second time.
struct FriendshipControls: View {
    enum Presentation {
        case profile, requestBanner, requestCard
    }

    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var navigation: StackRouter
    @Environment(\.owningStackRoute) private var owningStackRoute
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let user: OGSUser
    var presentation: Presentation = .profile

    private var isInvitation: Bool { presentation != .profile }

    @State private var confirmingRejection = false
    @State private var confirmingRemoval = false
    @State private var failedAction: OGSFriendshipAction?
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var refreshing = false
    @State private var isVisible = false
    @State private var failureID: UUID?
    @State private var awaitsActionResult = false

    private var isBusy: Bool { ogs.friendshipActionPlayerIDs.contains(user.id) }
    private var relationship: OGSProfileFriendship? { ogs.friendship(for: user.id) }
    private var canPresentFailure: Bool {
        isVisible && navigation.isActive && navigation.path.last == owningStackRoute
    }

    private var errorTitle: String {
        switch failedAction {
        case .send: return String(localized: "Couldn’t send friend request")
        case .accept: return String(localized: "Couldn’t accept friend request")
        case .reject: return String(localized: "Couldn’t reject friend request")
        case .remove: return String(localized: "Couldn’t remove friend")
        case nil: return String(localized: "Couldn’t load friendship status")
        }
    }

    private func perform(_ action: OGSFriendshipAction) {
        guard !isBusy, !awaitsActionResult else { return }
        awaitsActionResult = true
        Task { @MainActor in
            defer { awaitsActionResult = false }
            do {
                for try await _ in ogs.performFriendshipAction(action, user: user).values {}
            } catch {
                // The service retains failures even if this control disappeared.
                // Its shared failure stream presents them here or on reentry.
            }
        }
    }

    private func presentFailure(_ failure: OGSFriendshipFailure?) {
        guard canPresentFailure, let failure, failure.id != failureID else { return }
        failureID = failure.id
        failedAction = failure.action
        errorMessage = failure.message
        showingError = true
    }

    private func dismissFailure() {
        if let failureID {
            ogs.dismissFriendshipFailure(playerID: user.id, failureID: failureID)
        }
        failureID = nil
    }

    private func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            for try await _ in ogs.refreshFriendship(playerID: user.id, force: true).values {}
        } catch {
            // An unknown state remains retryable without hiding profile actions.
        }
    }

    var body: some View {
        Group {
            if isInvitation {
                if presentation == .requestBanner {
                    invitationActions.buttonStyle(.bordered)
                } else {
                    invitationActions.buttonStyle(.borderless)
                }
            } else {
                profileAction
            }
        }
        .confirmationDialog(
            Text("Reject \(user.username)’s friend request?"),
            isPresented: $confirmingRejection,
            titleVisibility: .visible
        ) {
            Button("Reject and Let Them Know", role: .destructive) {
                perform(.reject(notifyRequestor: true))
            }
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.friendshipRejectNotify)
            Button("Reject Quietly", role: .destructive) {
                perform(.reject(notifyRequestor: false))
            }
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.friendshipRejectQuietly)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("OGS can let them know you rejected it.")
        }
        .confirmationDialog(
            Text("Remove \(user.username) from your friends?"),
            isPresented: $confirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove friend", role: .destructive) { perform(.remove) }
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.friendshipRemoveConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("To be friends again, you’d have to send a new request.")
        }
        .alert(errorTitle, isPresented: $showingError) {
            Button("Retry") {
                if let failedAction { perform(failedAction) }
            }
            .accessibilityIdentifier(isInvitation
                ? SurroundUITestContract.AccessibilityID.friendRequestRetry(user.id)
                : SurroundUITestContract.AccessibilityID.profileFriendshipRetry)
            Button("Cancel", role: .cancel, action: dismissFailure)
        } message: {
            Text(verbatim: errorMessage)
                .accessibilityIdentifier(isInvitation
                    ? SurroundUITestContract.AccessibilityID.friendRequestError(user.id)
                    : SurroundUITestContract.AccessibilityID.profileFriendshipError)
        }
        .onChange(of: ogs.user?.id) { _, _ in
            showingError = false
            confirmingRejection = false
            confirmingRemoval = false
            failedAction = nil
            failureID = nil
        }
        .onReceive(ogs.$friendshipFailuresByPlayerID) { failures in
            if failures[user.id] == nil, failureID != nil {
                showingError = false
                failureID = nil
            }
            // The visible destination takes over a request started elsewhere;
            // covered Home cards and profiles cannot compete for the alert.
            presentFailure(failures[user.id])
        }
        .onChange(of: canPresentFailure) { _, canPresent in
            if canPresent {
                presentFailure(ogs.friendshipFailuresByPlayerID[user.id])
            } else {
                showingError = false
                failureID = nil
            }
        }
        .onAppear {
            isVisible = true
            presentFailure(ogs.friendshipFailuresByPlayerID[user.id])
        }
        .onDisappear {
            isVisible = false
            showingError = false
            failureID = nil
        }
        .appReviewPresentationBlocked(showingError || confirmingRemoval || confirmingRejection || isBusy)
    }

    private var invitationActions: some View {
        let stacksActions = dynamicTypeSize.isAccessibilitySize
        let layout = stacksActions
            ? AnyLayout(VStackLayout(alignment: presentation == .requestCard ? .trailing : .center, spacing: 8))
            : AnyLayout(HStackLayout(spacing: presentation == .requestCard ? 20 : 8))
        return layout {
            if isBusy {
                ProgressView()
                    .accessibilityLabel(Text("Updating friendship…"))
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.friendRequestBusy(user.id))
            } else {
                Button(role: .destructive) { confirmingRejection = true } label: {
                    Text("Reject")
                        .frame(maxWidth: presentation == .requestBanner ? .infinity : nil,
                               minHeight: presentation == .requestCard ? 44 : 32)
                }
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.friendRequestReject(user.id))
                Button { perform(.accept) } label: {
                    Text("Accept")
                        .frame(maxWidth: presentation == .requestBanner ? .infinity : nil,
                               minHeight: presentation == .requestCard ? 44 : 32)
                }
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.friendRequestAccept(user.id))
            }
        }
        .font(.body.bold())
        .frame(maxWidth: .infinity, minHeight: 44,
               alignment: presentation == .requestCard ? .trailing : .leading)
    }

    @ViewBuilder
    private var profileAction: some View {
        if isBusy {
            ProgressView()
                .accessibilityLabel(Text("Updating friendship…"))
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileFriendshipLoading)
        } else {
            switch relationship {
            case .none?:
                Button { perform(.send) } label: {
                    Label("Add friend", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileFriendshipAction)
            case .requestSent?:
                Button {} label: {
                    Label("Request sent", systemImage: "clock")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .disabled(true)
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileFriendshipAction)
            case .friends?:
                Menu {
                    Button("Remove friend", systemImage: "person.badge.minus", role: .destructive) {
                        confirmingRemoval = true
                    }
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileRemoveFriend)
                } label: {
                    Label("Friends", systemImage: "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileFriendshipAction)
            case .requestReceived?:
                EmptyView()
            case nil:
                VStack(alignment: .leading, spacing: 8) {
                    if refreshing {
                        ProgressView("Loading friendship status…")
                    } else {
                        Text("Couldn’t load friendship status")
                            .foregroundStyle(.secondary)
                        Button("Try Again") { Task { await refresh() } }
                            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileFriendshipRetry)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileFriendshipError)
            }
        }
    }
}

struct FriendRequestCard: View {
    @Environment(\.openPlayerProfile) private var openPlayerProfile
    @Environment(\.surroundAllowsRemoteActivity) private var allowsRemoteActivity
    let invitation: OGSFriendInvitation

    private var user: OGSUser { invitation.fromUser }

    private var identity: some View {
        HStack(spacing: 10) {
            AsyncImage(url: allowsRemoteActivity ? user.iconURL(ofSize: 40) : nil) {
                $0.resizable()
            } placeholder: {
                Image(systemName: "person.crop.square.fill")
                    .resizable().foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: user.usernameAndRank).bold().foregroundStyle(user.uiColor)
                if let created = invitation.created {
                    Text(created, format: .relative(presentation: .named))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let openPlayerProfile {
                Button { openPlayerProfile(user) } label: { identity }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("View \(user.username)’s profile"))
                    .accessibilityValue(Text(verbatim: user.usernameAndRank))
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.friendRequestProfile(user.id))
            } else {
                identity
            }
            Divider()
            FriendshipControls(user: user, presentation: .requestCard)
        }
    }
}
