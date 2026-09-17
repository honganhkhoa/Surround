//
//  GameHistoryView.swift
//  Surround
//
//  Paginated finished games, from Home or a player profile. An optional
//  opponent restricts the list to games between those two players.
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
    @EnvironmentObject private var navigation: StackRouter

    private static let pageSize = 10

    let player: OGSUser?
    let opponentID: Int?
    let perspectivePlayerID: Int?

    private struct QueryIdentity: Equatable {
        let playerID: Int?
        let opponentID: Int?
        let viewerID: Int?
        let botGames: Bool
    }

    @State private var pagination = GameHistoryPaginationState()
    @State private var fetchCancellable: AnyCancellable?
    @State private var activeIdentity: QueryIdentity?

    init(
        player: OGSUser? = nil,
        opponentID: Int? = nil,
        perspectivePlayerID: Int? = nil,
        pagination: GameHistoryPaginationState = GameHistoryPaginationState()
    ) {
        self.player = player
        self.opponentID = opponentID
        self.perspectivePlayerID = perspectivePlayerID
        _pagination = State(initialValue: pagination)
    }

    private var queryIdentity: QueryIdentity {
        QueryIdentity(
            playerID: player?.id ?? ogs.user?.id,
            opponentID: opponentID,
            viewerID: ogs.user?.id,
            botGames: player?.isBot == true
        )
    }

    @ViewBuilder
    var body: some View {
        if player == nil {
            historyContent
                .stackDestination(isPresented: Binding(
                    get: { nav.gameHistory.activeGame != nil },
                    set: { if !$0 { nav.gameHistory.activeGame = nil } }
                ), route: .historyGame)
        } else {
            historyContent
        }
    }

    private var historyContent: some View {
        ScrollView {
            if let player {
                Text(verbatim: player.username)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))]) {
                ForEach(pagination.games) { game in
                    HistoryGameCell(game: game, perspectivePlayerID: perspectivePlayerID ?? player?.id) {
                        if player != nil {
                            navigation.openGame(game, using: nav)
                        } else {
                            nav.gameHistory.activeGame = game
                        }
                    }
                    .accessibilityIdentifier(
                        player == nil
                            ? SurroundUITestContract.AccessibilityID.homeHistoryGame(game)
                            : game.ogsID.map(SurroundUITestContract.AccessibilityID.profileHistoryGame)
                                ?? SurroundUITestContract.AccessibilityID.homeHistoryGame(game)
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
            player == nil
                ? SurroundUITestContract.AccessibilityID.screenGameHistory
                : SurroundUITestContract.AccessibilityID.screenProfileGameHistory
        )
        .onAppear {
            if let activeIdentity, activeIdentity != queryIdentity {
                resetPages(for: queryIdentity)
                return
            }
            activeIdentity = queryIdentity
            if !pagination.loadedOnce {
                loadNextPage()
            }
        }
        .onChange(of: queryIdentity) { _, identity in
            resetPages(for: identity)
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
        let identity = queryIdentity
        if activeIdentity == nil { activeIdentity = identity }
        guard activeIdentity == identity,
              let request = pagination.beginRequest(playerID: identity.playerID) else {
            return
        }
        fetchCancellable = ogs.fetchHydratedFinishedGames(
            playerId: request.playerID,
            page: request.page,
            pageSize: Self.pageSize,
            opponentId: identity.opponentID,
            botGames: identity.botGames,
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
                guard activeIdentity == identity, ogs.user?.id == identity.viewerID else { return }
                let action = pagination.finish(
                    result,
                    for: request,
                    currentPlayerID: queryIdentity.playerID
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
                        guard activeIdentity == identity else { return }
                        loadNextPage()
                    }
                }
            }
    }

    /// Invalidate both pagination tokens and the broader query when its player,
    /// opponent, or viewing account changes.
    private func resetPages(for identity: QueryIdentity) {
        fetchCancellable?.cancel()
        fetchCancellable = nil
        activeIdentity = identity
        pagination.reset(playerID: identity.playerID)
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

    return AppNavigationStack {
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
