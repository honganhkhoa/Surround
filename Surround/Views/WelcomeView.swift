//
//  WelcomeView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 25/03/2021.
//

import SwiftUI
import Combine

struct WelcomeView: View {
    @Environment(\.surroundAllowsRemoteActivity) private var allowsRemoteActivity
    @EnvironmentObject var ogs: OGSService
    @State var publicGames = [Game]()
    private let animatesPublicGameChanges: Bool

    init(
        publicGames: [Game] = [],
        animatesPublicGameChanges: Bool = true
    ) {
        _publicGames = State(initialValue: publicGames)
        self.animatesPublicGameChanges = animatesPublicGameChanges
    }
    
    private func accountLink<Label: View>(path: String, @ViewBuilder label: () -> Label) -> some View {
        AppNavigationLink(
            destination: OGSBrowserView(
                initialURL: URL(string: "\(OGSService.ogsRoot)/\(path)")!,
                showsURLBar: true
            )
            .navigationBarTitleDisplayMode(.inline)
        ) {
            label()
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 50)
                .padding(.horizontal)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Signed out, Home says what Surround is, offers both ways in, and
    /// shows games being played now as Large tiles (canvas "Home Redesign").
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Surround is a client to play Go online with other players on the website Online-Go.com, also known as Online Go Server (OGS).")
                    .font(.callout)
                    .padding(.horizontal, 4)
                VStack(spacing: 10) {
                    accountLink(path: "sign-in") {
                        Text("Sign in to your OGS account")
                    }
                    .modifier(HomeActionSurface())
                    accountLink(path: "register") {
                        Text("Register an OGS account")
                            .modifier(HomeActionText())
                    }
                    .modifier(HomeCard(cornerRadius: 25))
                }
                .frame(maxWidth: 420)
                .padding(.top, 18)
                if let liveGames = ogs.sitewiseLiveGamesCount, let correspondenceGames = ogs.sitewiseCorrespondenceGamesCount {
                    Text(.init(localized: "**\(correspondenceGames) correspondence games** and **\(liveGames) live games** are being played right now."))
                        .font(.subheadline)
                        .modifier(HomeSecondaryText())
                        .padding(.horizontal, 4)
                        .padding(.top, 18)
                }
            }
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 12)
            if publicGames.count > 0 {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(publicGames) { game in
                            HomeGameTile(game: game)
                                .frame(width: HomeGameTile.minimumWidth + 4)
                                .modifier(HomeCard(cornerRadius: 20))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
                .accessibilityLabel(Text("Games being played now", comment: "Welcome - VoiceOver: the public games shown when signed out"))
            }
        }
        .background { GameDetailBackdrop().ignoresSafeArea(.container) }
        .onAppear {
            #if DEBUG && MAIN_APP
            if SurroundUITestContract.isEnabled {
                publicGames = Array(ogs.sortedPublicGames.prefix(4))
                return
            }
            #endif
            guard allowsRemoteActivity else { return }
            ogs.ensureConnect {
                ogs.subscribeToGameCount()
                ogs.cyclePublicGames()
            }
        }
        .onDisappear {
            guard allowsRemoteActivity else { return }
            ogs.unsubscribeFromGameCount()
            ogs.cancelPublicGamesCycling()
        }
        .onChange(of: ogs.sortedPublicGames) { _, games in
            guard animatesPublicGameChanges else {
                publicGames = Array(games.prefix(4))
                return
            }
            if self.publicGames.count > 0 {
                withAnimation(.easeInOut(duration: 2)) {
                    self.publicGames = []
                }
            }
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .milliseconds(2500))) {
                withAnimation(.easeInOut(duration: 2)) {
                    self.publicGames = games.shuffled()
                }
            }
        }
    }
}

#if DEBUG
private func welcomePreview() -> some View {
    let games = [
        TestData.Ongoing19x19HandicappedWithNoInitialState,
        TestData.Ongoing19x19wBot1,
    ]
    return NavigationStack {
        WelcomeView(
            publicGames: games,
            animatesPublicGameChanges: false
        )
            .navigationTitle("Welcome")
    }
    .environmentObject(
        OGSService.previewInstance(
            publicGames: games
        )
    )
    .environment(\.surroundAllowsRemoteActivity, false)
}

#Preview("Welcome — Default device") {
    welcomePreview()
}

#Preview("Welcome — Compact layout", traits: .fixedLayout(width: 320, height: 568)) {
    welcomePreview()
}
#endif
