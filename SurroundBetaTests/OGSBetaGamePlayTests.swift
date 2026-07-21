import Combine
import XCTest
@testable import Surround

@MainActor
final class OGSBetaGamePlayTests: XCTestCase {
    private static let requiredHost = "beta.online-go.com"
    private static let artifactPrefix = "surround-e2e-"
    private static let expectedAccounts = ["hakhoa", "hakhoa2", "hakhoa3", "hakhoa4"]
    private var diagnosticEvents = [String]()

    private struct Player {
        let username: String
        let preferencesSuite: String
        let socket: OGSWebsocket
        let service: OGSService

        func dispose() {
            socket.close()
            UserDefaults.standard.removePersistentDomain(forName: preferencesSuite)
        }
    }

    private final class CancellableBox {
        var cancellable: AnyCancellable?
    }

    private enum BetaTestError: LocalizedError {
        case invalidConfiguration(String)
        case timeout(String)
        case publisherFinishedWithoutValue
        case cleanupFailed([String])

        var errorDescription: String? {
            switch self {
            case .invalidConfiguration(let message): return message
            case .timeout(let description): return "Timed out waiting for \(description)"
            case .publisherFinishedWithoutValue: return "A request completed without returning a value"
            case .cleanupFailed(let artifacts): return "Tagged beta artifacts remain: \(artifacts.joined(separator: ", "))"
            }
        }
    }

    func testCompleteLiveGameBetweenTwoPlayers() async throws {
        diagnosticEvents = ["beta play-through started"]
        defer { attachSanitizedDiagnostics() }
        let process = ProcessInfo.processInfo.environment
        let hostString = process["OGS_BETA_HOST"] ?? "https://beta.online-go.com"
        guard hostString == "https://beta.online-go.com",
              let rootURL = URL(string: hostString),
              rootURL.scheme == "https",
              rootURL.host == Self.requiredHost,
              rootURL.user == nil,
              rootURL.password == nil,
              rootURL.port == nil,
              rootURL.query == nil,
              rootURL.fragment == nil else {
            throw BetaTestError.invalidConfiguration("OGS_BETA_HOST must be exactly https://beta.online-go.com")
        }
        guard let password = process["OGS_BETA_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("OGS_BETA_PASSWORD is not configured")
        }

        let configuredAccounts = (process["OGS_BETA_USERNAMES"] ?? Self.expectedAccounts.joined(separator: ","))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard configuredAccounts == Self.expectedAccounts else {
            throw BetaTestError.invalidConfiguration("OGS_BETA_USERNAMES must contain the four dedicated Surround beta accounts in their documented order")
        }

        let environment = OGSEnvironment(rootURL: rootURL)
        let players = configuredAccounts.map { makePlayer(username: $0, environment: environment) }
        defer { players.forEach { $0.dispose() } }
        diagnosticEvents.append("configuration validated")

        for player in players {
            let config = try await value(
                from: player.service.login(username: player.username, password: password),
                timeout: 30,
                description: "login for \(player.username)"
            )
            guard player.service.isLoggedIn,
                  config.user.username == player.username,
                  player.service.user?.username == player.username else {
                throw BetaTestError.invalidConfiguration("A beta login returned the wrong account or no authenticated session")
            }
            diagnosticEvents.append("login completed for \(player.username)")
        }

        for player in players {
            try await eventually(description: "authenticated socket for \(player.username)") {
                player.service.socketStatus == .connected && player.service.isWebsocketAuthenticated
            }
        }
        diagnosticEvents.append("all websocket sessions authenticated")

        // A previous process can die before XCTest teardown. Recover only
        // artifacts carrying the automation prefix; never touch manual games.
        try await cleanupTaggedArtifacts(players: players, tag: Self.artifactPrefix)
        diagnosticEvents.append("stale tagged-artifact cleanup completed")

        let runTag = Self.artifactPrefix + UUID().uuidString.lowercased()
        var scenarioError: Error?
        do {
            try await playGame(runTag: runTag, black: players[0], white: players[1])
            diagnosticEvents.append("play-through completed")
        } catch {
            scenarioError = error
            diagnosticEvents.append("play-through failed")
        }

        var cleanupError: Error?
        do {
            try await cleanupTaggedArtifacts(players: players, tag: runTag)
            diagnosticEvents.append("current-run cleanup completed")
        } catch {
            cleanupError = error
            diagnosticEvents.append("current-run cleanup failed")
        }

        if let scenarioError {
            if let cleanupError {
                XCTContext.runActivity(named: "Cleanup failure") { activity in
                    activity.add(XCTAttachment(string: cleanupError.localizedDescription))
                }
            }
            throw scenarioError
        }
        if let cleanupError {
            throw cleanupError
        }
    }

    private func makePlayer(username: String, environment: OGSEnvironment) -> Player {
        let suite = "com.honganhkhoa.Surround.BetaTests.\(username).\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        let socket = OGSWebsocket(rootURL: environment.rootURL, websocketURL: environment.websocketURL)
        let service = OGSService(
            environment: environment,
            httpClient: AlamofireOGSHTTPClient.isolated(),
            preferences: preferences,
            ogsWebsocket: socket,
            connectsAutomatically: true,
            usesSurroundOverviewService: false,
            enablesAppSideEffects: false,
            startsTimers: false
        )
        return Player(username: username, preferencesSuite: suite, socket: socket, service: service)
    }

    private func playGame(runTag: String, black: Player, white: Player) async throws {
        guard let whiteUser = white.service.user else {
            throw BetaTestError.invalidConfiguration("The second beta account did not expose a logged-in user")
        }

        var challenge = OGSChallengeTemplate(game: .init(
            width: 5,
            height: 5,
            ranked: false,
            isPrivate: true,
            handicap: 0,
            disableAnalysis: false,
            name: runTag,
            rules: .japanese,
            timeControl: TimeControl(codingData: .init(
                timeControl: "fischer",
                initialTime: 120,
                timeIncrement: 30,
                maxTime: 300,
                speed: .live,
                pauseOnWeekends: false
            ))
        ))
        challenge.challengerColor = .black

        _ = try await value(
            from: black.service.sendChallenge(opponent: whiteUser, challenge: challenge),
            timeout: 30,
            description: "challenge creation"
        )
        diagnosticEvents.append("direct challenge created")

        let receivedChallenge = try await eventuallyValue(
            description: "the direct challenge to appear",
            refresh: { try await self.refreshOverview(white.service) }
        ) {
            white.service.challengesReceived.first { $0.game.name == runTag }
        }

        let gameID = try await value(
            from: white.service.acceptChallenge(challenge: receivedChallenge),
            timeout: 30,
            description: "challenge acceptance"
        )
        diagnosticEvents.append("challenge accepted; game id \(gameID)")

        let blackGame = try await value(
            from: black.service.getGameDetailAndConnect(gameID: gameID),
            timeout: 30,
            description: "black game connection"
        )
        let whiteGame = try await value(
            from: white.service.getGameDetailAndConnect(gameID: gameID),
            timeout: 30,
            description: "white game connection"
        )

        try await eventually(description: "opposite player colors") {
            blackGame.userStoneColor == .black && whiteGame.userStoneColor == .white
        }

        let moves: [Move] = [
            .placeStone(0, 0),
            .placeStone(4, 4),
            .placeStone(0, 1),
            .placeStone(4, 3),
            .pass,
            .pass
        ]

        for (index, move) in moves.enumerated() {
            let previousBlackClockTime = blackGame.clock?.lastMoveTime
            let previousWhiteClockTime = whiteGame.clock?.lastMoveTime
            let mover = blackGame.currentPosition.nextToMove == .black ? (black.service, blackGame) : (white.service, whiteGame)
            _ = try await value(
                from: mover.0.submitMove(move: move, forGame: mover.1),
                timeout: 20,
                description: "move \(index + 1) acknowledgement"
            )
            try await eventually(description: "move \(index + 1) on both clients") {
                blackGame.currentPosition.lastMoveNumber == index + 1 &&
                    whiteGame.currentPosition.lastMoveNumber == index + 1
            }
            XCTAssertTrue(blackGame.currentPosition.hasTheSamePosition(with: whiteGame.currentPosition))
            if index < 4 {
                try await eventually(description: "clock update after move \(index + 1)") {
                    guard let blackClock = blackGame.clock, let whiteClock = whiteGame.clock else { return false }
                    return blackClock.currentPlayerColor == blackGame.currentPosition.nextToMove &&
                        whiteClock.currentPlayerColor == whiteGame.currentPosition.nextToMove &&
                        blackClock.lastMoveTime != previousBlackClockTime &&
                        whiteClock.lastMoveTime != previousWhiteClockTime
                }
                XCTAssertEqual(blackGame.clock?.currentPlayerId, whiteGame.clock?.currentPlayerId)
            }
            diagnosticEvents.append("move \(index + 1) observed by both clients")
        }

        try await eventually(description: "stone-removal phase", timeout: 45) {
            blackGame.gamePhase == .stoneRemoval && whiteGame.gamePhase == .stoneRemoval
        }
        diagnosticEvents.append("stone-removal phase observed")

        black.service.acceptRemovedStone(game: blackGame)
        white.service.acceptRemovedStone(game: whiteGame)

        try await eventually(description: "finished game", timeout: 60) {
            blackGame.gamePhase == .finished && whiteGame.gamePhase == .finished
        }
        diagnosticEvents.append("finished phase observed")
        XCTAssertTrue(blackGame.currentPosition.hasTheSamePosition(with: whiteGame.currentPosition))
    }

    private func cleanupTaggedArtifacts(players: [Player], tag: String) async throws {
        diagnosticEvents.append("cleanup started for tag scope")
        let deadline = Date().addingTimeInterval(45)
        let cancellationFallbackAt = Date().addingTimeInterval(3)

        while true {
            for player in players {
                try await refreshOverview(player.service)
            }

            let remaining = taggedArtifactDescriptions(players: players, tag: tag)
            if remaining.isEmpty {
                diagnosticEvents.append("cleanup verification passed")
                return
            }

            var handledChallenges = Set<Int>()
            for player in players {
                let challenges = player.service.challengesSent + player.service.challengesReceived
                for challenge in challenges
                where challenge.game.name.hasPrefix(tag) && handledChallenges.insert(challenge.id).inserted {
                    _ = try? await value(
                        from: player.service.withdrawOrDeclineChallenge(challenge: challenge),
                        timeout: 15,
                        description: "challenge cleanup"
                    )
                }
            }

            var handledGames = Set<Int>()
            for player in players {
                for game in player.service.activeGames.values {
                    guard let gameID = game.ogsID,
                          game.gameData?.gameName.hasPrefix(tag) == true,
                          handledGames.insert(gameID).inserted else { continue }

                    // Prefer cancellation so aborted setup does not create a
                    // result. If cancellation has not cleared the game after a
                    // short grace period, resignation is the reliable fallback.
                    if game.canBeCancelled && Date() < cancellationFallbackAt {
                        player.service.cancel(game: game)
                    } else {
                        player.service.resign(game: game)
                    }
                }
            }

            guard Date() < deadline else {
                throw BetaTestError.cleanupFailed(remaining.sorted())
            }
            try await Task.sleep(for: .seconds(1))
        }
    }

    private func taggedArtifactDescriptions(players: [Player], tag: String) -> Set<String> {
        var remaining = Set<String>()
        for player in players {
            for challenge in player.service.challengesSent + player.service.challengesReceived
            where challenge.game.name.hasPrefix(tag) {
                remaining.insert("challenge:\(challenge.id)")
            }
            for game in player.service.activeGames.values
            where game.gameData?.gameName.hasPrefix(tag) == true {
                remaining.insert("game:\(game.ogsID ?? -1)")
            }
        }
        return remaining
    }

    private func attachSanitizedDiagnostics() {
        let attachment = XCTAttachment(string: diagnosticEvents.joined(separator: "\n"))
        attachment.name = "Sanitized OGS beta stage transcript"
        attachment.lifetime = .deleteOnSuccess
        add(attachment)
    }

    private func refreshOverview(_ service: OGSService) async throws {
        _ = try await value(
            from: service.refreshOverviewFromOGS(),
            timeout: 45,
            description: "beta overview refresh"
        )
    }

    private func eventually(
        description: String,
        timeout: TimeInterval = 30,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw BetaTestError.timeout(description)
    }

    private func eventuallyValue<T>(
        description: String,
        timeout: TimeInterval = 30,
        refresh: @escaping @MainActor () async throws -> Void,
        value: @escaping @MainActor () -> T?
    ) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try await refresh()
            if let result = value() { return result }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw BetaTestError.timeout(description)
    }

    private func value<T>(
        from publisher: AnyPublisher<T, Error>,
        timeout: TimeInterval,
        description: String
    ) async throws -> T {
        let box = CancellableBox()
        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            box.cancellable = publisher
                .timeout(.seconds(timeout), scheduler: DispatchQueue.main, customError: { BetaTestError.timeout(description) })
                .first()
                .sink(
                    receiveCompletion: { completion in
                        guard !resumed else { return }
                        resumed = true
                        switch completion {
                        case .finished: continuation.resume(throwing: BetaTestError.publisherFinishedWithoutValue)
                        case .failure(let error): continuation.resume(throwing: error)
                        }
                        box.cancellable = nil
                    },
                    receiveValue: { result in
                        guard !resumed else { return }
                        resumed = true
                        continuation.resume(returning: result)
                        box.cancellable = nil
                    }
                )
        }
    }
}
