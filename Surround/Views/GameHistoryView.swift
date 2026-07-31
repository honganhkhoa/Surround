//
//  GameHistoryView.swift
//  Surround
//
//  Paginated list of the logged-in user's finished games. Reached from the
//  "Recent finished games" section on the home screen. Tapping a game opens
//  GameDetailView without the active-games carousel.
//

import SwiftUI
import Combine

struct GameHistoryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService

    private static let pageSize = 10

    @State private var pagination = GameHistoryPaginationState()
    @State private var fetchCancellable: AnyCancellable?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))]) {
                ForEach(pagination.games) { game in
                    HistoryGameCell(game: game) {
                        nav.gameHistory.activeGame = game
                    }
                    .accessibilityIdentifier(
                        SurroundUITestContract.AccessibilityID
                            .homeHistoryGame(game)
                    )
                    .padding(.horizontal)
                    .onAppear {
                        if game.ogsID == pagination.games.last?.ogsID {
                            loadNextPage()
                        }
                    }
                }
                if pagination.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                if pagination.lastRequestFailed && !pagination.isLoading {
                    VStack(spacing: 10) {
                        Text("Couldn’t load game history", comment: "GameHistoryView loading error")
                            .foregroundColor(.secondary)
                        Button {
                            loadNextPage()
                        } label: {
                            Text("Try Again", comment: "GameHistoryView retry loading")
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                if pagination.loadedOnce
                    && pagination.games.isEmpty
                    && !pagination.isLoading
                    && !pagination.lastRequestFailed {
                    Text("No finished games yet")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
            }
            .background(Color(colorScheme == .dark ? UIColor.systemGray5 : UIColor.white))
        }
        .navigationDestination(isPresented: Binding(
            get: { nav.gameHistory.activeGame != nil },
            set: { if !$0 { nav.gameHistory.activeGame = nil } }
        ), destination: {
            GameDetailView(
                currentGame: nav.gameHistory.activeGame,
                allowsActiveGamesCarousel: false
            )
        })
        .onAppear {
            if !pagination.loadedOnce {
                loadNextPage()
            }
        }
        .onChange(of: ogs.user?.id) { _, newPlayerID in
            resetPages(playerID: newPlayerID)
        }
        .navigationTitle(Text("Game history"))
    }

    private func loadNextPage() {
        guard let request = pagination.beginRequest(playerID: ogs.user?.id) else {
            return
        }
        fetchCancellable = ogs.fetchHydratedFinishedGames(
            playerId: request.playerID,
            page: request.page,
            pageSize: Self.pageSize,
            reusing: pagination.reusableGames
        )
            .map { page in
                GameHistoryPaginationState.PageResult.success(
                    games: page.games,
                    hasNextPage: page.hasNextPage
                )
            }
            .catch { _ in
                Just(GameHistoryPaginationState.PageResult.failure)
            }
            .receive(on: RunLoop.main)
            .sink { result in
                let action = pagination.finish(
                    result,
                    for: request,
                    currentPlayerID: ogs.user?.id
                )
                guard action != .ignored else {
                    return
                }

                fetchCancellable = nil
                if action == .loadNextPage {
                    // A shifted page can contain only ids already present.
                    // Advance again rather than waiting for a new last row
                    // whose `onAppear` can never fire.
                    DispatchQueue.main.async {
                        loadNextPage()
                    }
                }
            }
    }

    /// Discards pages belonging to the previous account and starts over.
    private func resetPages(playerID: Int?) {
        fetchCancellable?.cancel()
        fetchCancellable = nil
        pagination.reset(playerID: playerID)
        loadNextPage()
    }
}
