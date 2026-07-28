//
//  GameHistoryPaginationState.swift
//  Surround
//
//  Pure pagination state for GameHistoryView. Network effects remain in the
//  view, while request/result transitions stay deterministic and testable.
//

struct GameHistoryPaginationState {
    private static let maximumConsecutiveNoProgressPages = 3

    struct Request: Equatable {
        let playerID: Int
        let page: Int
        fileprivate let generation: UInt
    }

    enum PageResult {
        case success(games: [Game], hasNextPage: Bool)
        case failure
    }

    enum CompletionAction: Equatable {
        /// The request was invalidated by an account reset or superseded.
        case ignored
        case finished
        case loadNextPage
    }

    private(set) var games: [Game] = []
    private(set) var nextPage = 1
    private(set) var hasMore = true
    private(set) var loadedOnce = false
    private(set) var lastRequestFailed = false

    private var playerID: Int?
    private var generation: UInt = 0
    private var activeRequest: Request?
    private var consecutiveNoProgressPages = 0

    var isLoading: Bool {
        activeRequest != nil
    }

    var reusableGames: [Int: Game] {
        Dictionary(
            games.compactMap { game in game.ogsID.map { ($0, game) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Starts the next page only when it belongs to the selected account.
    ///
    /// The first request establishes the account. Later account changes must
    /// call `reset(playerID:)`, which also invalidates any in-flight token.
    mutating func beginRequest(playerID requestedPlayerID: Int?) -> Request? {
        guard activeRequest == nil,
              hasMore,
              let requestedPlayerID else {
            return nil
        }

        if playerID == nil {
            playerID = requestedPlayerID
        }
        guard playerID == requestedPlayerID else {
            return nil
        }

        let request = Request(
            playerID: requestedPlayerID,
            page: nextPage,
            generation: generation
        )
        lastRequestFailed = false
        activeRequest = request
        return request
    }

    /// Applies exactly one terminal result for a request.
    ///
    /// Duplicate-only pages request another page when the server reports one,
    /// up to a small consecutive limit that prevents a malformed response from
    /// creating an unbounded request chain.
    mutating func finish(
        _ result: PageResult,
        for request: Request,
        currentPlayerID: Int?
    ) -> CompletionAction {
        guard activeRequest == request,
              currentPlayerID == request.playerID else {
            return .ignored
        }

        activeRequest = nil
        loadedOnce = true

        switch result {
        case .failure:
            lastRequestFailed = true
            consecutiveNoProgressPages = 0
            return .finished

        case .success(let incomingGames, let hasNextPage):
            lastRequestFailed = false
            let previousCount = games.count
            games = OGSService.mergingFinishedGames(games, with: incomingGames)
            hasMore = hasNextPage
            nextPage += 1

            guard games.count == previousCount, hasMore else {
                consecutiveNoProgressPages = 0
                return .finished
            }

            consecutiveNoProgressPages += 1
            guard consecutiveNoProgressPages < Self.maximumConsecutiveNoProgressPages else {
                hasMore = false
                return .finished
            }
            return .loadNextPage
        }
    }

    /// Clears all pages and invalidates results from the previous account or
    /// an earlier request generation, even when the numeric player id matches.
    mutating func reset(playerID: Int?) {
        generation &+= 1
        self.playerID = playerID
        activeRequest = nil
        games = []
        nextPage = 1
        hasMore = true
        loadedOnce = false
        lastRequestFailed = false
        consecutiveNoProgressPages = 0
    }
}
