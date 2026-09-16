//
//  PlayerProfileView.swift
//  Surround
//

import SwiftUI
import Combine

private struct OpenPlayerProfileKey: EnvironmentKey {
    static let defaultValue: ((OGSUser) -> Void)? = nil
}

private struct OpenPlayerConversationKey: EnvironmentKey {
    static let defaultValue: ((OGSUser) -> Void)? = nil
}

extension EnvironmentValues {
    /// Actions belong to the nearest app navigation stack. Standalone content
    /// has no action, so it does not expose buttons that cannot navigate.
    var openPlayerProfile: ((OGSUser) -> Void)? {
        get { self[OpenPlayerProfileKey.self] }
        set { self[OpenPlayerProfileKey.self] = newValue }
    }

    var openPlayerConversation: ((OGSUser) -> Void)? {
        get { self[OpenPlayerConversationKey.self] }
        set { self[OpenPlayerConversationKey.self] = newValue }
    }
}

struct PlayerProfileView: View {
    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var navigation: StackRouter
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    let user: OGSUser
    var selectionID: UUID? = nil

    private enum LoadState {
        case loading
        case loaded(OGSPlayerProfile)
        case failed
    }

    private struct LoadIdentity: Equatable {
        let playerID: Int
        let viewerID: Int?
        let attempt: Int
    }

    @State private var state: LoadState = .loading
    @State private var attempt = 0
    @State private var loadedFor: LoadIdentity?
    @State private var refreshAfterEditing = false

    private var loadIdentity: LoadIdentity {
        LoadIdentity(playerID: user.id, viewerID: ogs.user?.id, attempt: attempt)
    }

    private var profileURL: URL {
        URL(string: OGSService.ogsRoot)!
            .appendingPathComponent("player")
            .appendingPathComponent(String(user.id))
    }

    private var loadedProfile: OGSPlayerProfile? {
        guard case .loaded(let profile) = state else { return nil }
        return profile
    }

    private var identityHeader: some View {
        let profile = loadedProfile
        let displayedUser = profile?.user ?? user
        return PlayerProfileIdentity(
            user: displayedUser,
            isOwnProfile: displayedUser.id == ogs.user?.id,
            registrationDate: profile?.registrationDate
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(profile == nil ? SurroundUITestContract.AccessibilityID.profileIdentity : SurroundUITestContract.AccessibilityID.profileLoaded)
        #if DEBUG && MAIN_APP
        .accessibilityValue(Text(verbatim: SurroundUITestContract.isEnabled
            ? (colorScheme == .dark ? "dark" : "light") : ""))
        #endif
    }

    private func loadProfile(for identity: LoadIdentity) async {
        guard loadedFor != identity else { return }
        state = .loading
        do {
            for try await profile in ogs.fetchPlayerProfile(playerId: identity.playerID).values {
                try Task.checkCancellation()
                guard identity == loadIdentity else { return }
                state = .loaded(profile)
                loadedFor = identity
                return
            }
            if !Task.isCancelled { state = .failed }
        } catch {
            if !Task.isCancelled { state = .failed }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                identityHeader
                switch state {
                case .loading:
                    ProgressView("Loading profile…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileLoading)
                case .loaded(let profile):
                    actions(for: profile.user)
                case .failed:
                    ContentUnavailableView {
                        Label("Unable to load profile", systemImage: "person.crop.circle.badge.exclamationmark")
                            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileError)
                    } description: {
                        Text("Check your connection and try again. The player may no longer be available.")
                    } actions: {
                        Button("Try again") { attempt += 1 }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileRetry)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.screenPlayerProfile)
        .task(id: loadIdentity) {
            await loadProfile(for: loadIdentity)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, refreshAfterEditing {
                refreshAfterEditing = false
                attempt += 1
            }
        }
    }

    @ViewBuilder
    private func actions(for player: OGSUser) -> some View {
        if player.id == ogs.user?.id {
            VStack(spacing: 12) {
                Button {
                    refreshAfterEditing = true
                    openURL(profileURL)
                } label: {
                    Label("Edit on OGS", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileEdit)
                ShareLink(item: profileURL) {
                    Label("Share profile", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileShare)
            }
        } else if ogs.isLoggedIn {
            VStack(spacing: 12) {
                if let selectionID, let selection = navigation.selections[selectionID] {
                    Button {
                        navigation.selectOpponent(player, selectionID: selectionID, viewerID: ogs.user?.id)
                    } label: {
                        switch selection.action {
                        case .selectOpponent:
                            Label("Select opponent", systemImage: "person.crop.circle.badge.checkmark")
                                .frame(maxWidth: .infinity, minHeight: 32)
                        case .challengeWithSettings:
                            Label("Challenge with these settings", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(selection.action == .selectOpponent
                                             ? SurroundUITestContract.AccessibilityID.profileSelectOpponent : SurroundUITestContract.AccessibilityID.profileChallengeWithSettings)
                } else if selectionID == nil {
                    Button {
                        navigation.openChallenge(for: player)
                    } label: {
                        Label("Challenge", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileChallenge)
                }
                Button {
                    navigation.openConversation(player)
                } label: {
                    Label("Message", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileMessage)
            }
        }
    }
}

private struct PlayerProfileIdentity: View {
    @Environment(\.surroundAllowsRemoteActivity) private var allowsRemoteActivity
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var availableWidth: CGFloat = 0
    private static let countryCodes = Set(Locale.Region.isoRegions.map(\.identifier))

    let user: OGSUser
    let isOwnProfile: Bool
    var registrationDate: Date?

    private var countryName: String? {
        guard let country = user.country?.uppercased(),
              country != "UN",
              Self.countryCodes.contains(country) else {
            return nil
        }
        return Locale.current.localizedString(forRegionCode: country)
    }

    private var nameColor: Color {
        // The standard orange/green role colors are too light on white.
        if colorScheme == .light, !user.isOGSModerator {
            if user.uiClass?.contains("professional") == true {
                return Color(red: 0.06, green: 0.42, blue: 0.20)
            }
            if user.isOGSSupporter {
                return Color(red: 0.60, green: 0.28, blue: 0.03)
            }
        }
        return user.uiColor
    }

    var body: some View {
        identityLayout {
            avatar
            details
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            availableWidth = width
        }
    }

    private var identityLayout: AnyLayout {
        // Retain one avatar while changing layout. Narrow headers leave too
        // little room beside the 96-point image for readable identity details.
        if dynamicTypeSize.isAccessibilitySize || (availableWidth > 0 && availableWidth < 320) {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
        }
        return AnyLayout(HStackLayout(alignment: .top, spacing: 20))
    }

    private var avatar: some View {
        AsyncImage(url: allowsRemoteActivity ? user.iconURL(ofSize: 128) : nil) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.square.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
        .frame(width: 96, height: 96)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: user.usernameAndRank)
                .font(.title2.bold())
                .foregroundStyle(nameColor)
                .fixedSize(horizontal: false, vertical: true)
            if isOwnProfile {
                Text("You")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.tint.opacity(0.12), in: Capsule())
            }
            if user.isOGSSupporter || user.supporter == true {
                Label("OGS Supporter", systemImage: "heart.fill")
                    .font(.caption)
            }
            if let countryName {
                Label(countryName, systemImage: "globe")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let registrationDate {
                Label {
                    Text("Member since \(registrationDate, format: .dateTime.month(.wide).year())")
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
private func profilePreview(isOwnProfile: Bool) -> some View {
    let viewer = OGSUser(username: "JuniperStone", id: 314459)
    let player = isOwnProfile ? viewer : OGSUser(username: "CopperKoi", id: 429553, country: "tw")
    let profile = OGSPlayerProfile(
        user: player,
        registrationDate: Date(timeIntervalSince1970: 1_443_657_600)
    )
    return AppNavigationStack {
        PlayerProfileView(user: player)
    }
    .environmentObject(OGSService(previewState: .init(
        user: viewer,
        isLoggedIn: true,
        playerProfilesById: [profile.id: profile]
    )))
    .environmentObject(NavigationService())
    .environment(\.surroundAllowsRemoteActivity, false)
}

#Preview("Profile — Other player") {
    profilePreview(isOwnProfile: false)
}

#Preview("Profile — Own, dark") {
    profilePreview(isOwnProfile: true)
        .preferredColorScheme(.dark)
}
#endif
