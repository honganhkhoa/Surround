//
//  NotificationPopup.swift
//  Surround
//
//  Created by Anh Khoa Hong on 20/02/2021.
//

import SwiftUI

private func friendshipMessage(for action: OGSFriendshipAction) -> String {
    switch action {
    case .send: return String(localized: "Sent friend request")
    case .accept: return String(localized: "Friend request accepted")
    case .reject: return String(localized: "Friend request rejected")
    case .remove: return String(localized: "Removed friend")
    }
}

/// Each navigation stack draws the shared notice above its own content,
/// including stacks presented in sheets. The root popup owns its expiry.
struct FriendshipNoticeBanner: View {
    @EnvironmentObject private var ogs: OGSService

    var body: some View {
        if let notice = ogs.friendshipNotice {
            Text(verbatim: friendshipMessage(for: notice.action))
                .bold()
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.systemIndigo), in: RoundedRectangle(cornerRadius: 10))
                .padding(16)
                .allowsHitTesting(false)
        }
    }
}

/// Message access in the global notice row, on every screen including Game
/// Detail, until the game gets a design of its own for it.
struct PrivateMessageNotificationButton: View {
    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var nav: NavigationService

    static func isVisible(ogs: OGSService, nav: NavigationService) -> Bool {
        guard ogs.socketStatus == .connected else { return false }
        if !ogs.superchatPeerIds.isEmpty || nav.showingPrivateChatView { return true }
        if nav.main.rootView == .privateMessages { return false }
        return ogs.privateMessagesUnreadCount > 0
    }

    private var messageLabel: some View {
        Label("Messages", systemImage: "message.fill")
            .overlay(alignment: .topTrailing) {
                if ogs.privateMessagesUnreadCount > 0 {
                    Text(verbatim: "\(ogs.privateMessagesUnreadCount)")
                        .font(.caption2.bold())
                        .minimumScaleFactor(0.2)
                        .foregroundStyle(.white)
                        .frame(width: 15, height: 15)
                        .background(.red, in: Circle())
                        .offset(x: 6, y: -6)
                }
            }
    }

    var body: some View {
        Button {
            guard !nav.showingPrivateChatView || ogs.superchatPeerIds.isEmpty else { return }
            nav.showingPrivateChatView.toggle()
        } label: {
            messageLabel.labelStyle(.iconOnly)
                .padding()
                .foregroundStyle(.white)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel(Text("Messages"))
        .accessibilityValue(Text(verbatim: String(ogs.privateMessagesUnreadCount)))
        .accessibilityIdentifier("global.privateMessages")
    }
}

struct NotificationPopup: View {
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var friendshipNotice: OGSFriendshipNotice?
    /// When a banner already on screen starts to fade in after the socket
    /// leaves `.connected` (2 s, so a short blip shows nothing). One mounted
    /// while offline is opaque at once and has none.
    @State private var connectionBannerFadeIn: ContinuousClock.Instant?


    var connectionPopup: some View {
        ZStack {
            HStack(spacing: 5) {
                if ogs.socketStatus == .connecting || ogs.socketStatus == .reconnecting {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    EmptyView()
                }
                Text(ogs.socketStatus.localizedString).bold().foregroundColor(.white)
            }
            .animation(.easeInOut, value: ogs.socketStatus.localizedString)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.systemIndigo))
        .cornerRadius(10)
        .opacity(ogs.socketStatus == .connected ? 0 : 1)
        .animation(Animation.easeInOut.delay(2), value: ogs.socketStatus)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.connectionBanner)
        .accessibilityHidden(ogs.socketStatus == .connected)
        .allowsHitTesting(false)
    }

    /// The banner gives way only while a visible game renders its own
    /// Reconnecting… badge on the running clock. Everywhere else, including
    /// stone removal, a finished game and Analyze's glow-only chips, it shows
    /// as on other screens and explains why the game's controls are disabled.
    private var showsConnectionPopup: Bool {
        !nav.visibleGameDetailShowsReconnectingBadge
    }

    private var connectionBannerShown: Bool {
        showsConnectionPopup && ogs.socketStatus != .connected
    }

    /// Tells the game when the banner occupies its title slot: from the
    /// moment it becomes visible until "Connected" has faded (2 s delay,
    /// 0.35 s fade), so the title never blanks while the banner is clear.
    private func publishConnectionBanner() async {
        if connectionBannerShown && !nav.connectionBannerVisible,
           let fadeIn = connectionBannerFadeIn, fadeIn > ContinuousClock.now {
            try? await Task.sleep(until: fadeIn)
            guard !Task.isCancelled else { return }
        }
        if !connectionBannerShown && nav.connectionBannerVisible
            && ogs.socketStatus == .connected && showsConnectionPopup {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
        }
        if nav.connectionBannerVisible != connectionBannerShown {
            nav.connectionBannerVisible = connectionBannerShown
        }
    }
    
    var viewingLiveGames: Bool {
        nav.visibleGameDetailPlaysLiveGame
    }

    var liveGamesElsewhere: [Game] {
        nav.liveGamesNeedingNotice(among: ogs.liveGames)
    }

    var viewingHomeView: Bool {
        return nav.main.rootView == .home && nav.home.activeGame == nil
    }

    func goToLiveGames() {
        if let game = liveGamesElsewhere.first {
            nav.goToActiveGame(game: game)
        }
    }

    var liveGamesPopup: some View {
        Button(action: goToLiveGames) {
            VStack {
                if (liveGamesElsewhere.count == 1) {
                    Text("Live game in progress...", comment: "In Popup. When only 1 game in progress.").bold().foregroundColor(.white)
                    Text("Tap to go to game", comment: "Popup. When a single game is in progress.").font(.subheadline).foregroundColor(.white)
                } else {
                    Text("Live games in progress...", comment: "In Popup. When multiple games are in progress.").bold().foregroundColor(.white)
                    Text("Tap to go to games", comment: "Popup. When multiplpe games are in progress.").font(.subheadline).foregroundColor(.white)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.systemTeal))
            .cornerRadius(10)
        }
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.liveGameBanner)
    }
    
    var waitingGamesPopup: some View {
        Button(action: { nav.main.showWaitingGames = true }) {
            HStack(spacing: 0) {
                VStack {
                    Text("Waiting...").bold().foregroundColor(.white)
                    Text("\(ogs.waitingLiveGames) live games", comment: "NotificationPopup - vary for plural").font(.subheadline).foregroundColor(.white)
                }
                Spacer().frame(width: 10)
                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.systemIndigo))
            .cornerRadius(10)
        }
    }
    
    var shouldShowChallengeReceivedPopup: Bool {
        guard !viewingHomeView && !viewingLiveGames else {
            return false
        }
        return ogs.challengesReceived.count > 0
    }
    
    var challengeReceivedPopup: some View {
        Button(action: { nav.main.showWaitingGames = true }) {
            VStack {
                Text("Challenge received!").bold().foregroundColor(.white)
                Text("Tap to view").font(.subheadline).foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.systemIndigo))
            .cornerRadius(10)
        }
    }
    
    func closeChatWindow() {
        guard ogs.superchatPeerIds.count == 0 else {
            return
        }
        
        nav.showingPrivateChatView = false
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // The panel shows only while connected, and so does the layer
            // that closes it: offline it would swallow taps on an empty window.
            if nav.showingPrivateChatView && ogs.socketStatus == .connected {
                Color.white
                    .opacity(0.01)
                    .contentShape(Rectangle())
                    .onTapGesture { closeChatWindow() }
            }
            if ogs.socketStatus == .connected {
                VStack {
                    HStack {
                        // Game Detail owns connection status, but its active
                        // picker does not replace cross-speed live/challenge notices.
                        if !liveGamesElsewhere.isEmpty {
                            liveGamesPopup
                        } else if ogs.waitingLiveGames > 0 && !viewingHomeView {
                            waitingGamesPopup
                        } else if shouldShowChallengeReceivedPopup {
                            challengeReceivedPopup
                        }
                        if PrivateMessageNotificationButton.isVisible(ogs: ogs, nav: nav) {
                            PrivateMessageNotificationButton()
                        }
                    }
                    if nav.showingPrivateChatView {
                        ZStack {
                            PrivateMessageNotificationView()
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("global.privateMessagesPanel")
                                .frame(maxWidth: 540)
                                .background(
                                    Color(colorScheme == .dark ? .systemGray6 : .systemBackground)
                                        .shadow(radius: 2)
                                )
                                .padding(.horizontal)
                                .padding(.bottom)
                        }
                    }
                }
            }
            if showsConnectionPopup {
                connectionPopup
            }
        }
        .onChange(of: ogs.socketStatus) { oldStatus, newStatus in
            if newStatus == .connected {
                connectionBannerFadeIn = nil
            } else if oldStatus == .connected {
                connectionBannerFadeIn = showsConnectionPopup ? ContinuousClock.now + .seconds(2) : nil
            }
        }
        .onChange(of: showsConnectionPopup) { _, shows in
            if shows { connectionBannerFadeIn = nil }
        }
        .task(id: connectionBannerShown) { await publishConnectionBanner() }
        .onDisappear {
            if nav.connectionBannerVisible { nav.connectionBannerVisible = false }
        }
        .onChange(of: ogs.superchatPeerIds) { _, superchatPeerIds in
            if superchatPeerIds.count > 0 {
                let accountID = ogs.user?.id
                DispatchQueue.main.async {
                    guard let accountID, ogs.user?.id == accountID,
                          !ogs.superchatPeerIds.isEmpty else { return }
                    nav.showingPrivateChatView = true
                }
            }
        }
        .onReceive(ogs.$friendshipNotice) { notice in
            friendshipNotice = notice
            if let notice {
                AccessibilityNotification.Announcement(friendshipMessage(for: notice.action)).post()
            }
        }
        .task(id: friendshipNotice?.id) {
            guard let noticeID = friendshipNotice?.id else { return }
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
            ogs.dismissFriendshipNotice(id: noticeID)
        }
        .onReceive(ogs.$user) { user in
            // The popup previously lost its local state on sign-out. Keep the
            // shared presenter closed when that account lifetime ends.
            if user == nil { nav.showingPrivateChatView = false }
        }
        .appReviewPresentationBlocked(nav.showingPrivateChatView)
    }
}

#if DEBUG
private func notificationPopupPreview(
    ogs: OGSService,
    showingPrivateChatView: Bool = false,
    showsNavigationBackground: Bool = true
) -> some View {
    let nav = NavigationService()
    nav.main.rootView = .publicGames
    nav.showingPrivateChatView = showingPrivateChatView
    return ZStack(alignment: .top) {
        if showsNavigationBackground {
            NavigationView {
                Text("View")
                    .navigationTitle("View")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarItems(leading: Text("Back"))
            }
            .navigationViewStyle(StackNavigationViewStyle())
        } else {
            Color(.systemBackground)
        }
        NotificationPopup()
    }
    .environmentObject(ogs)
    .environmentObject(nav)
}

#Preview("Waiting game and conversations — Dark") {
    notificationPopupPreview(
        ogs: OGSService.previewInstance(
            user: OGSUser(username: "hakhoa", id: 765826),
            openChallengesSent: [OGSChallengeSampleData.sampleOpenChallenge]
        ),
        showingPrivateChatView: true
    )
    .colorScheme(.dark)
}

#Preview("Live games and conversations") {
    notificationPopupPreview(
        ogs: OGSService.previewInstance(
            user: OGSUser(username: "hakhoa", id: 765826),
            activeGames: [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2]
        ),
        showingPrivateChatView: true
    )
}

#Preview("Challenge received") {
    notificationPopupPreview(
        ogs: OGSService.previewInstance(
            user: OGSUser(username: "hakhoa", id: 765826),
            challengesReceived: [OGSChallengeSampleData.sampleChallenge]
        )
    )
}

#Preview("Connecting") {
    notificationPopupPreview(
        ogs: OGSService.previewInstance(socketStatus: .connecting),
        showsNavigationBackground: false
    )
}
#endif
