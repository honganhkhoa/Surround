//
//  NotificationPopup.swift
//  Surround
//
//  Created by Anh Khoa Hong on 20/02/2021.
//

import SwiftUI

/// Message access in the global notice row, on every screen but a game's,
/// whose in-game control reaches Messages in its popover. It opens the
/// window's Activity list at Messages.
struct PrivateMessageNotificationButton: View {
    @EnvironmentObject private var ogs: OGSService

    /// While connected, off the Messages tab, with unread conversations.
    /// The list it opened hangs off the window's presenter, so it stays open
    /// when the button goes.
    static func isVisible(ogs: OGSService, nav: NavigationService) -> Bool {
        ogs.socketStatus == .connected
            && nav.main.rootView != .privateMessages
            && ogs.privateMessagesUnreadCount > 0
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
        ActivityOpenerButton(source: .messagesButton, focus: .messages) {
            messageLabel.labelStyle(.iconOnly)
                .padding()
                .foregroundStyle(.white)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel(Text("Messages"))
        .accessibilityValue(Text(verbatim: String(ogs.privateMessagesUnreadCount)))
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.messagesButton)
    }
}

private struct GlobalNotificationOverlayKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Main tab stacks share the root popup; presented stacks do not.
    var hasGlobalNotificationOverlay: Bool {
        get { self[GlobalNotificationOverlayKey.self] }
        set { self[GlobalNotificationOverlayKey.self] = newValue }
    }
}

/// Which of the popup's pills and its Messages button show.
@MainActor
struct NotificationPopupVisibility {
    let showsLiveGames: Bool
    let showsWaitingGames: Bool
    let showsChallenge: Bool
    let showsPrivateMessages: Bool

    init(ogs: OGSService, nav: NavigationService) {
        let connected = ogs.socketStatus == .connected
        let viewingHome = nav.main.rootView == .home && nav.home.activeGame == nil
        showsLiveGames = connected && !nav.liveGamesNeedingNotice(among: ogs.liveGames).isEmpty
        showsWaitingGames = connected && !showsLiveGames && ogs.waitingLiveGames > 0 && !viewingHome
        showsChallenge = connected && !showsLiveGames && !showsWaitingGames
            && !viewingHome && !nav.visibleGameDetailPlaysLiveGame && !ogs.challengesReceived.isEmpty
        showsPrivateMessages = PrivateMessageNotificationButton.isVisible(ogs: ogs, nav: nav)
    }
}

/// The live, waiting and challenge pills and the Messages button, while
/// connected. The window's connection status is said by each platform's own
/// carriers instead: the line under root titles, the Activity bar, the Now
/// section, a game's own status and a conversation's line.
struct NotificationPopup: View {
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Where the live pill is, for the Activity list it opens when several
    /// live games wait.
    @State private var livePillFrame = ActivityOpenerFrame()

    var liveGamesElsewhere: [Game] {
        nav.liveGamesNeedingNotice(among: ogs.liveGames)
    }

    /// One live game elsewhere opens at once. Several open Activity, whose
    /// Live games section lists them most urgent first.
    func goToLiveGames() {
        let games = liveGamesElsewhere
        if games.count > 1 {
            nav.openActivity(source: .livePill, focus: .top, anchor: livePillFrame.value,
                             horizontalSizeClass: horizontalSizeClass)
        } else if let game = games.first {
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
        .activityOpenerFrame(livePillFrame, source: .livePill)
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.liveGameBanner)
    }
    
    var waitingGamesPopup: some View {
        ActivityOpenerButton(source: .waitingPill) {
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
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.waitingBanner)
    }

    var challengeReceivedPopup: some View {
        ActivityOpenerButton(source: .challengePill) {
            VStack {
                Text("Challenge received!").bold().foregroundColor(.white)
                Text("Tap to view").font(.subheadline).foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.systemIndigo))
            .cornerRadius(10)
        }
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.challengeBanner)
    }

    var body: some View {
        let visibility = NotificationPopupVisibility(ogs: ogs, nav: nav)
        ZStack(alignment: .top) {
            if ogs.socketStatus == .connected {
                HStack {
                    if visibility.showsLiveGames {
                        liveGamesPopup
                    } else if visibility.showsWaitingGames {
                        waitingGamesPopup
                    } else if visibility.showsChallenge {
                        challengeReceivedPopup
                    }
                    if visibility.showsPrivateMessages {
                        PrivateMessageNotificationButton()
                    }
                }
            }
        }
    }
}

#if DEBUG
private func notificationPopupPreview(
    ogs: OGSService,
    showsNavigationBackground: Bool = true
) -> some View {
    let nav = NavigationService()
    nav.main.rootView = .publicGames
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

#Preview("Waiting game and Messages — Dark") {
    notificationPopupPreview(
        ogs: OGSService.previewInstance(
            user: OGSUser(username: "hakhoa", id: 765826),
            openChallengesSent: [OGSChallengeSampleData.sampleOpenChallenge]
        )
    )
    .colorScheme(.dark)
}

#Preview("Live games and Messages") {
    notificationPopupPreview(
        ogs: OGSService.previewInstance(
            user: OGSUser(username: "hakhoa", id: 765826),
            activeGames: [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2]
        )
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
#endif
