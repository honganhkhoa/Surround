//
//  PublicGamesList.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/1/20.
//

import SwiftUI

struct PublicGamesList: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    @AppStorage(SettingKey<String>.gameTheme.name, store: userDefaults)
    private var gameThemeID = SurroundTheme.standard.rawValue
    @AppStorage(SettingKey<Bool>.themeAppliesToWholeApp.name, store: userDefaults)
    private var themeAppliesToWholeApp = true

    private var theme: SurroundTheme {
        SurroundTheme.current(storedID: gameThemeID, appliesToWholeApp: themeAppliesToWholeApp)
    }

    /// Resolves the window's pending game open while it is Public games',
    /// with the request it resolves.
    @State private var pendingGameOpenTask: (requestID: UUID, task: Task<Void, Never>)?

    @MainActor
    private func resolvePendingGameOpen(_ request: PendingGameOpen) async {
        guard request.rootView == .publicGames,
              nav.pendingGameOpen?.id == request.id else {
            return
        }

        do {
            let resolver = GameOpenResolver<Game>(
                activeGame: { gameID in
                    if let game = ogs.activeGames[gameID],
                       game.gameData != nil {
                        return game
                    }
                    if let game = ogs.sortedPublicGames.first(where: {
                        $0.ogsID == gameID
                    }), game.gameData != nil {
                        return game
                    }
                    return nil
                },
                sharedOverviewGame: { _ in nil },
                restGame: { gameID in
                    for try await game in ogs.getGameDetail(
                        gameID: gameID
                    ).values {
                        return game
                    }
                    throw OGSServiceError.invalidJSON
                }
            )
            let resolution = try await resolver.resolve(
                gameID: request.ogsGameID
            )
            guard !Task.isCancelled,
                  nav.pendingGameOpen?.id == request.id else {
                return
            }
            nav.publicGames.activeGame = resolution.game
            nav.clearPendingGameOpen(id: request.id)
        } catch {
            guard !Task.isCancelled,
                  nav.pendingGameOpen?.id == request.id else {
                return
            }
            nav.clearPendingGameOpen(id: request.id)
        }
    }
    
    var body: some View {
        Group {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))]) {
                    ForEach(ogs.sortedPublicGames) { game in
                        Button(action: { nav.showPublicGame(game) }) {
                            GameCell(game: game)
                                .modifier(HomeCardOnScene(padding: 12))
                        }
                        .accessibilityIdentifier(
                            SurroundUITestContract.AccessibilityID.publicGame(game)
                        )
                        .buttonStyle(.plain)
                        .padding()
                    }
                }
                .background(theme.hasScene ? .clear : Color(colorScheme == .dark ? UIColor.systemGray5 : UIColor.white))
            }
            // On the scroll view itself: on the group, the identifier would
            // also mark the backdrop's empty host, and a first match finds that.
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.screenPublicGames)
            // The scene stays put behind the scrolling games.
            .background { if theme.hasScene { ThemeSceneBackdrop() } }
            .surroundTheme(theme)
        }
        .stackDestination(isPresented: Binding(
            get: { nav.publicGames.activeGame != nil },
            set: { if !$0 { nav.publicGames.activeGame = nil } }
        ), route: .publicGame)
        .onAppear {
//            print("Appeared \(self)")
            ogs.fetchPublicGames()
        }
        // A Task, not a task(id:): a task(id:) doesn't run while a public
        // game covers the list, so a game requested then, such as a link's,
        // would wait for Back. The list's reappearance runs this again, and
        // an open still under way carries on.
        .onChange(of: nav.pendingGameOpen?.id, initial: true) {
            let request = nav.pendingGameOpen?.rootView == .publicGames ? nav.pendingGameOpen : nil
            if let request, request.id == pendingGameOpenTask?.requestID { return }
            pendingGameOpenTask?.task.cancel()
            pendingGameOpenTask = nil
            guard let request else { return }
            let task = Task {
                await resolvePendingGameOpen(request)
                if pendingGameOpenTask?.requestID == request.id { pendingGameOpenTask = nil }
            }
            pendingGameOpenTask = (request.id, task)
        }
        .modifier(ThemeSceneNavigationTitle(title: Text("Public live games"), theme: theme))
    }
}

#if DEBUG
private func publicGamesPreview(games: [Game]) -> some View {
    let nav = NavigationService()
    nav.main.rootView = .publicGames
    return AppNavigationStack {
        PublicGamesList()
            .modifier(RootViewSwitchingMenu())
    }
    .environmentObject(OGSService.previewInstance(publicGames: games))
    .environmentObject(nav)
}

#Preview("Public games — Loaded") {
    publicGamesPreview(
        games: [
            TestData.Ongoing19x19HandicappedWithNoInitialState,
            TestData.Scored15x17,
            TestData.Resigned9x9Japanese,
            TestData.StoneRemoval9x9,
        ]
    )
    .preferredColorScheme(.dark)
}

#Preview("Public games — Empty") {
    publicGamesPreview(games: [])
}
#endif
