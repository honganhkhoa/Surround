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

enum GameHistoryLoadStatus {
    case loading
    case failed
    case empty
}

struct GameHistoryLoadStatusView: View {
    struct AccessibilityIdentifiers {
        let loading: String
        let error: String
        let retry: String
        let empty: String
    }

    let status: GameHistoryLoadStatus
    let accessibilityIdentifiers: AccessibilityIdentifiers
    let emptyVerticalPadding: CGFloat
    let retry: () -> Void

    init(
        status: GameHistoryLoadStatus,
        accessibilityIdentifiers: AccessibilityIdentifiers,
        emptyVerticalPadding: CGFloat = 40,
        retry: @escaping () -> Void
    ) {
        self.status = status
        self.accessibilityIdentifiers = accessibilityIdentifiers
        self.emptyVerticalPadding = emptyVerticalPadding
        self.retry = retry
    }

    @ViewBuilder
    var body: some View {
        switch status {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
                .accessibilityIdentifier(accessibilityIdentifiers.loading)
        case .failed:
            VStack(spacing: 10) {
                Text(
                    "Couldn’t load game history",
                    comment: "GameHistoryView loading error"
                )
                .foregroundColor(.secondary)
                .accessibilityIdentifier(accessibilityIdentifiers.error)
                Button(action: retry) {
                    Text(
                        "Try Again",
                        comment: "GameHistoryView retry loading"
                    )
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(accessibilityIdentifiers.retry)
            }
            .frame(maxWidth: .infinity)
            .padding()
        case .empty:
            Text("No finished games yet")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, emptyVerticalPadding)
                .accessibilityIdentifier(accessibilityIdentifiers.empty)
        }
    }
}

struct GameHistoryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService

    private static let pageSize = 10

    @State private var pagination = GameHistoryPaginationState()
    @State private var fetchCancellable: AnyCancellable?

    init(pagination: GameHistoryPaginationState = GameHistoryPaginationState()) {
        _pagination = State(initialValue: pagination)
    }

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
                if let loadStatus {
                    GameHistoryLoadStatusView(
                        status: loadStatus,
                        accessibilityIdentifiers: .init(
                            loading: SurroundUITestContract.AccessibilityID
                                .gameHistoryLoading,
                            error: SurroundUITestContract.AccessibilityID
                                .gameHistoryError,
                            retry: SurroundUITestContract.AccessibilityID
                                .gameHistoryRetry,
                            empty: SurroundUITestContract.AccessibilityID
                                .gameHistoryEmpty
                        ),
                        retry: loadNextPage
                    )
                }
            }
            .background(Color(colorScheme == .dark ? UIColor.systemGray5 : UIColor.white))
        }
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.screenGameHistory
        )
        .navigationDestination(isPresented: Binding(
            get: { nav.gameHistory.activeGame != nil },
            set: { if !$0 { nav.gameHistory.activeGame = nil } }
        ), destination: {
            GameDetailView(
                currentGame: $nav.gameHistory.activeGame,
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

    private var loadStatus: GameHistoryLoadStatus? {
        if pagination.isLoading {
            return .loading
        }
        if pagination.lastRequestFailed {
            return .failed
        }
        if pagination.loadedOnce && pagination.games.isEmpty {
            return .empty
        }
        return nil
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

#if DEBUG
private func gameHistoryPreviewPagination(
    playerID: Int,
    result: GameHistoryPaginationState.PageResult
) -> GameHistoryPaginationState {
    var pagination = GameHistoryPaginationState()
    guard let request = pagination.beginRequest(playerID: playerID) else {
        preconditionFailure("A fresh preview pagination state must accept its first request.")
    }
    _ = pagination.finish(
        result,
        for: request,
        currentPlayerID: playerID
    )
    return pagination
}

private func gameHistoryPreview(
    result: GameHistoryPaginationState.PageResult
) -> some View {
    let user = OGSUser(username: "HongAnhKhoa", id: 314459)
    let pagination = gameHistoryPreviewPagination(
        playerID: user.id,
        result: result
    )

    return NavigationStack {
        GameHistoryView(pagination: pagination)
    }
    .environmentObject(OGSService.previewInstance(user: user))
    .environmentObject(NavigationService())
}

#Preview("Game history — Loaded") {
    gameHistoryPreview(
        result: .success(
            games: [TestData.Scored19x19Korean],
            hasNextPage: false
        )
    )
}

#Preview("Game history — Empty") {
    gameHistoryPreview(
        result: .success(games: [], hasNextPage: false)
    )
}

#Preview("Game history — Load error") {
    gameHistoryPreview(result: .failure)
}
#endif
