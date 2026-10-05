import Combine
import Foundation

/// A history view owns its optional replay requests and can cancel them independently.
final class FinishedGamePreviewLoader: ObservableObject {
    private struct Context: Equatable {
        let serviceID: ObjectIdentifier
        let authenticationGeneration: UInt
        let viewerID: Int?

        init(service: OGSService) {
            serviceID = ObjectIdentifier(service)
            authenticationGeneration = service.finishedGamePreviewAuthenticationGeneration
            viewerID = service.user?.id
        }
    }

    private struct Request {
        let id: UUID
        let game: Game
        var cancellable: AnyCancellable?
    }

    private let maximumConcurrentRequests: Int
    private let loadPreview: (Game, OGSService) -> AnyPublisher<Void, Error>
    private var queue: [Game] = []
    private var queuedIDs: Set<Int> = []
    private var demandedIDs: Set<Int> = []
    private var requests: [Int: Request] = [:]
    private var cooldownChanges: AnyCancellable?
    private var resumeTimer: Timer?
    private var resumeDeadline: Date?
    private weak var service: OGSService?
    private var context: Context?
    private var generation: UInt = 0

    init(
        maximumConcurrentRequests: Int = 4,
        loadPreview: @escaping (Game, OGSService) -> AnyPublisher<Void, Error> = {
            $1.loadFinishedGamePreview(for: $0)
        }
    ) {
        self.maximumConcurrentRequests = min(4, max(1, maximumConcurrentRequests))
        self.loadPreview = loadPreview
    }

    deinit { cancel() }

    func load(games: [Game], using service: OGSService) {
        let nextContext = Context(service: service)
        if context != nextContext { cancel() }
        self.service = service
        context = nextContext
        if cooldownChanges == nil {
            cooldownChanges = service.finishedGamePreviewCooldown.changes
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.startQueuedRequests() }
        }
        for game in games {
            guard let gameID = game.ogsID, gameID > 0 else { continue }
            demandedIDs.insert(gameID)
            if game.hasCompleteFinishedGameDetail {
                game.historyDetailState = .ready
                continue
            }
            guard game.historyDetailState != .unavailable,
                  requests[gameID] == nil, queuedIDs.insert(gameID).inserted else { continue }
            queue.append(game)
        }
        startQueuedRequests()
    }

    /// Disappearing rows lose queued demand. A started request may still finish
    /// and populate its reusable cache unless the whole view cancels its loader.
    func removeDemand(for game: Game) {
        guard let gameID = game.ogsID else { return }
        demandedIDs.remove(gameID)
        queuedIDs.remove(gameID)
        queue.removeAll { $0.ogsID == gameID }
        if queue.isEmpty { clearResumeTimer() }
    }

    func retry(game: Game, using service: OGSService) {
        guard game.historyDetailState == .unavailable,
              let gameID = game.ogsID, service.finishedGamePreviewCanStart(gameID: gameID) else { return }
        game.historyDetailState = .notRequested
        load(games: [game], using: service)
    }

    func cancel() {
        generation &+= 1
        let cancelledRequests = Array(requests.values)
        requests.removeAll()
        queue.removeAll()
        queuedIDs.removeAll()
        demandedIDs.removeAll()
        cooldownChanges?.cancel()
        cooldownChanges = nil
        clearResumeTimer()
        context = nil
        service = nil
        for request in cancelledRequests {
            request.cancellable?.cancel()
            if request.game.historyDetailRequestID == request.id {
                request.game.historyDetailRequestID = nil
                if request.game.historyDetailState == .loading {
                    request.game.historyDetailState = .notRequested
                }
            }
        }
    }

    private func startQueuedRequests() {
        guard let service, let context, context == Context(service: service) else {
            cancel()
            return
        }
        queue.removeAll { game in
            guard let gameID = game.ogsID, demandedIDs.contains(gameID),
                  game.historyDetailState != .unavailable else {
                if let gameID = game.ogsID { queuedIDs.remove(gameID) }
                return true
            }
            if game.hasCompleteFinishedGameDetail {
                game.historyDetailState = .ready
                queuedIDs.remove(gameID)
                return true
            }
            return false
        }
        while requests.count < maximumConcurrentRequests, !queue.isEmpty {
            guard let index = queue.firstIndex(where: { game in
                game.ogsID.map { service.finishedGamePreviewCanStart(gameID: $0) } == true
            }) else { break }
            let game = queue.remove(at: index)
            guard let gameID = game.ogsID else { continue }
            queuedIDs.remove(gameID)
            if game.hasCompleteFinishedGameDetail {
                game.historyDetailState = .ready
                continue
            }
            guard game.historyDetailState != .unavailable else { continue }
            let requestID = UUID()
            let requestGeneration = generation
            game.historyDetailRequestID = requestID
            game.historyDetailState = .loading
            requests[gameID] = Request(id: requestID, game: game)
            let cancellable = loadPreview(game, service)
                .receive(on: RunLoop.main)
                .sink(
                    receiveCompletion: { [weak self] completion in
                        self?.complete(
                            gameID: gameID, requestID: requestID,
                            generation: requestGeneration, completion: completion
                        )
                    },
                    receiveValue: { _ in }
                )
            if requests[gameID]?.id == requestID {
                requests[gameID]?.cancellable = cancellable
            } else {
                cancellable.cancel()
            }
        }
        scheduleResumeIfNeeded(using: service)
    }

    private func clearResumeTimer() {
        resumeTimer?.invalidate()
        resumeTimer = nil
        resumeDeadline = nil
    }

    private func scheduleResumeIfNeeded(using service: OGSService) {
        guard !queue.isEmpty,
              let deadline = service.finishedGamePreviewCooldown.retryNotBefore,
              let interval = service.finishedGamePreviewCooldown.remainingInterval, interval > 0 else {
            clearResumeTimer()
            return
        }
        if resumeDeadline == deadline, resumeTimer != nil { return }
        clearResumeTimer()
        resumeDeadline = deadline
        let requestGeneration = generation
        // Chunk exceptionally distant deadlines so Timer never overflows, while
        // checking the same shared deadline before any queued request can start.
        let timer = Timer(timeInterval: min(interval, 3600), repeats: false) { [weak self] firedTimer in
            guard let self, self.generation == requestGeneration, self.resumeTimer === firedTimer else { return }
            self.clearResumeTimer()
            self.service?.finishedGamePreviewCooldown.refresh()
            self.startQueuedRequests()
        }
        resumeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func complete(
        gameID: Int, requestID: UUID, generation requestGeneration: UInt,
        completion: Subscribers.Completion<Error>
    ) {
        guard generation == requestGeneration,
              let request = requests[gameID], request.id == requestID else { return }
        guard let service, context == Context(service: service) else {
            cancel()
            return
        }
        if case .failure(let error) = completion,
           let error = error as? OGSServiceError, case .staleAuthenticationContext = error {
            cancel()
            return
        }
        if case .failure(let error) = completion,
           let rateLimit = error as? FinishedGamePreviewRateLimitError {
            service.finishedGamePreviewCooldown.record(retryNotBefore: rateLimit.retryNotBefore)
        }
        requests.removeValue(forKey: gameID)
        if request.game.historyDetailRequestID == requestID {
            request.game.historyDetailRequestID = nil
            switch completion {
            case .finished:
                request.game.historyDetailState = request.game.hasCompleteFinishedGameDetail
                    ? .ready : .unavailable
            case .failure:
                request.game.historyDetailState = .unavailable
            }
        }
        startQueuedRequests()
    }
}
