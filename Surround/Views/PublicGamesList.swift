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
                        Button(action: { nav.publicGames.activeGame = game }) {
                            GameCell(game: game)
                        }
                        .accessibilityIdentifier(
                            SurroundUITestContract.AccessibilityID.publicGame(game)
                        )
                        .buttonStyle(.plain)
                        .padding()
                    }
                }
                .background(Color(colorScheme == .dark ? UIColor.systemGray5 : UIColor.white))
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { nav.publicGames.activeGame != nil },
            set: { if !$0 { nav.publicGames.activeGame = nil } }
        ), destination: {
            GameDetailView(currentGame: $nav.publicGames.activeGame)
        })
        .onAppear {
//            print("Appeared \(self)")
            ogs.fetchPublicGames()
        }
        .task(id: nav.pendingGameOpen?.id) {
            guard let request = nav.pendingGameOpen,
                  request.rootView == .publicGames else {
                return
            }
            await resolvePendingGameOpen(request)
        }
        .navigationBarTitle(Text("Public live games"))
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.screenPublicGames)
    }
}

#if DEBUG
private func publicGamesPreview(games: [Game]) -> some View {
    let nav = NavigationService()
    nav.main.rootView = .publicGames
    return NavigationStack {
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
