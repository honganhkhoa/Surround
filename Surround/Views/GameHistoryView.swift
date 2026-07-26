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

    private static let pageSize = 50

    @State private var games: [Game] = []
    @State private var nextPage = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var fetchCancellable: AnyCancellable?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))]) {
                ForEach(games) { game in
                    HistoryGameCell(game: game) {
                        nav.gameHistory.activeGame = game
                    }
                    .padding()
                    .onAppear {
                        if game.ogsID == games.last?.ogsID {
                            loadNextPage()
                        }
                    }
                }
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                if loadedOnce && games.isEmpty && !isLoading {
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
            let openedGame = nav.gameHistory.activeGame
            GameDetailView(currentGame: openedGame, allowsActiveGamesCarousel: false)
                .onDisappear {
                    // Finished games are never dropped from connectedGames by
                    // the overview, so release what this screen opened.
                    if let openedGame {
                        ogs.releaseConnectionIfNotActive(for: openedGame)
                    }
                }
        })
        .onAppear {
            if !loadedOnce {
                loadNextPage()
            }
        }
        .onChange(of: ogs.user?.id) { _, _ in
            resetPages()
        }
        .navigationTitle(Text("Game history"))
    }

    private func loadNextPage() {
        guard !isLoading, hasMore, let playerId = ogs.user?.id else {
            return
        }
        isLoading = true
        let reusableGames = Dictionary(
            games.compactMap { game in game.ogsID.map { ($0, game) } },
            uniquingKeysWith: { first, _ in first }
        )
        fetchCancellable = ogs.fetchFinishedGames(playerId: playerId, page: nextPage, pageSize: Self.pageSize, reusing: reusableGames)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    guard ogs.user?.id == playerId else {
                        return
                    }
                    isLoading = false
                    loadedOnce = true
                    if case .failure = completion {
                        hasMore = false
                    }
                    fetchCancellable = nil
                },
                receiveValue: { result in
                    // Ignore a page that belongs to the previously signed-in
                    // account; `resetPages()` has already cleared its state.
                    guard ogs.user?.id == playerId else {
                        return
                    }
                    games.append(contentsOf: result.games)
                    hasMore = result.hasNextPage
                    nextPage += 1
                }
            )
    }

    /// Discards pages belonging to the previous account and starts over.
    private func resetPages() {
        fetchCancellable?.cancel()
        fetchCancellable = nil
        games = []
        nextPage = 1
        hasMore = true
        isLoading = false
        loadedOnce = false
        loadNextPage()
    }
}
