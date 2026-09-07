import Foundation
import Observation

/// Installation-wide history; all windows reserve attempts through this store.
@MainActor
final class AppReviewHistoryStore {
    private static let storageKey = "appReview.history.v1"
    private static let day: TimeInterval = 24 * 60 * 60

    private struct History: Codable, Equatable {
        var firstUse: Date?
        var activeDays: Set<String> = []
        var lastAttempt: Date?
        var lastAttemptVersion: String?
    }

    private let preferences: UserDefaults
    private let calendar: Calendar
    private let marketingVersion: String

    init(
        preferences: UserDefaults,
        calendar: Calendar = .current,
        marketingVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? ""
    ) {
        self.preferences = preferences
        self.calendar = calendar
        self.marketingVersion = marketingVersion
    }

    func recordForegroundUse(at date: Date, signedIn: Bool) {
        var history = readHistory()
        let previousHistory = history
        if history.firstUse == nil {
            history.firstUse = date
        }
        if signedIn && history.activeDays.count < 5 {
            let components = calendar.dateComponents(
                [.era, .year, .month, .day], from: date
            )
            let dayID = "\(components.era ?? 0)-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
            history.activeDays.insert(dayID)
        }
        if history != previousHistory { writeHistory(history) }
    }

    func isEligible(at date: Date) -> Bool {
        isEligible(readHistory(), at: date)
    }

    /// Recording and checking occur synchronously on the main actor. Read fresh
    /// preferences so even independently constructed stores cannot double prompt.
    func reserveAttempt(at date: Date) -> Bool {
        var history = readHistory()
        guard isEligible(history, at: date) else { return false }
        history.lastAttempt = date
        history.lastAttemptVersion = marketingVersion
        writeHistory(history)
        return true
    }

    private func isEligible(_ history: History, at date: Date) -> Bool {
        guard !marketingVersion.isEmpty,
              let firstUse = history.firstUse,
              date.timeIntervalSince(firstUse) >= 7 * Self.day,
              history.activeDays.count >= 5,
              history.lastAttemptVersion != marketingVersion else {
            return false
        }
        if let lastAttempt = history.lastAttempt,
           date.timeIntervalSince(lastAttempt) < 120 * Self.day {
            return false
        }
        return true
    }

    private func readHistory() -> History {
        guard let data = preferences.data(forKey: Self.storageKey),
              let history = try? JSONDecoder().decode(History.self, from: data)
        else { return History() }
        return history
    }

    private func writeHistory(_ history: History) {
        if let data = try? JSONEncoder().encode(history) {
            preferences.set(data, forKey: Self.storageKey)
        }
    }
}

struct AppReviewContext: Equatable {
    var isActive: Bool
    var isBackground: Bool
    var userID: Int?
    var isHome: Bool
    var hasCorrespondenceTurns: Bool
    var isBlocked: Bool
}

enum AppReviewGamePhase {
    case playing, scoring, finished, cancelled
}

struct AppReviewSubmission: Hashable {
    fileprivate let id: UUID
    fileprivate let sessionID: UUID
    fileprivate let userID: Int
    fileprivate let gameID: Int
    fileprivate let correspondence: Bool
}

/// Transient opportunities belong to one scene and one foreground account
/// session. Merely opening Home, replaying history, or receiving server events
/// cannot create an opportunity.
@MainActor
@Observable
final class AppReviewCoordinator {
    private(set) var requestID: UUID?
    /// A displayed view retries its baseline when the parent scene becomes
    /// ready, independently of SwiftUI's parent/child callback ordering.
    private(set) var gameObservationContextID = UUID()

    private struct LiveGameObservationKey: Hashable {
        let ownerID: UUID
        let gameID: Int
    }

    @ObservationIgnored private let history: AppReviewHistoryStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let delay: () async throws -> Void
    @ObservationIgnored private var context = AppReviewContext(
        isActive: false, isBackground: false, userID: nil,
        isHome: true, hasCorrespondenceTurns: true, isBlocked: true
    )
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var pendingMoves = Set<AppReviewSubmission>()
    @ObservationIgnored private var observedLiveGames = [LiveGameObservationKey: AppReviewGamePhase]()
    @ObservationIgnored private var correspondenceActivity = false
    @ObservationIgnored private var liveCompletion = false
    @ObservationIgnored private var returnedHomeAfterActivity = false
    @ObservationIgnored private var sessionHadFailure = false

    init(
        history: AppReviewHistoryStore,
        now: @escaping () -> Date = Date.init,
        delay: @escaping () async throws -> Void = {
            try await Task.sleep(for: .seconds(2))
        }
    ) {
        self.history = history
        self.now = now
        self.delay = delay
    }

    func updateContext(_ newContext: AppReviewContext) {
        let previous = context
        if previous.userID != newContext.userID || newContext.isBackground {
            resetSession()
        }
        context = newContext
        if !newContext.isActive || newContext.isHome {
            observedLiveGames.removeAll()
        }
        if previous.userID != newContext.userID
            || previous.isActive != newContext.isActive
            || previous.isBackground != newContext.isBackground
            || previous.isHome != newContext.isHome {
            gameObservationContextID = UUID()
        }
        if newContext.isActive && !newContext.isBackground {
            history.recordForegroundUse(
                at: now(), signedIn: newContext.userID != nil
            )
        }
        if !newContext.isHome {
            returnedHomeAfterActivity = false
        } else if !previous.isHome && previous.userID == newContext.userID {
            // A server confirmation can arrive after the user leaves the board.
            // Preserve this return only when a local interaction already exists.
            returnedHomeAfterActivity = correspondenceActivity || liveCompletion
                || pendingMoves.contains(where: \.correspondence)
        }
        refreshRequest()
    }

    func beginMove(gameID: Int, correspondence: Bool) -> AppReviewSubmission? {
        guard context.isActive, !context.isBackground, !context.isHome,
              let userID = context.userID, gameID > 0 else { return nil }
        let submission = AppReviewSubmission(
            id: UUID(), sessionID: sessionID, userID: userID,
            gameID: gameID, correspondence: correspondence
        )
        pendingMoves.insert(submission)
        refreshRequest()
        return submission
    }

    func finishMove(_ submission: AppReviewSubmission, succeeded: Bool) {
        guard submission.sessionID == sessionID,
              submission.userID == context.userID,
              pendingMoves.remove(submission) != nil else { return }
        if succeeded {
            correspondenceActivity = correspondenceActivity
                || submission.correspondence
        } else {
            // An error suppresses this foreground session, including earlier
            // successful activity, instead of prompting beside a failed move.
            sessionHadFailure = true
        }
        refreshRequest()
    }

    /// Called only for the scene's displayed realtime game. Initial finished
    /// history and spectator updates have no preceding participant phase. Each
    /// view owns its baseline so an outgoing layout cannot clear its replacement.
    func observeLiveGame(
        ownerID: UUID, gameID: Int, isParticipant: Bool, phase: AppReviewGamePhase
    ) {
        let key = LiveGameObservationKey(ownerID: ownerID, gameID: gameID)
        guard context.isActive, !context.isBackground, !context.isHome,
              context.userID != nil, isParticipant, gameID > 0 else {
            observedLiveGames.removeValue(forKey: key)
            return
        }
        switch phase {
        case .playing, .scoring:
            observedLiveGames[key] = phase
        case .finished:
            if let previous = observedLiveGames.removeValue(forKey: key),
               previous == .playing || previous == .scoring {
                liveCompletion = true
            }
        case .cancelled:
            observedLiveGames.removeValue(forKey: key)
        }
        refreshRequest()
    }

    func stopObservingLiveGame(ownerID: UUID, gameID: Int) {
        observedLiveGames.removeValue(
            forKey: LiveGameObservationKey(ownerID: ownerID, gameID: gameID)
        )
    }

    /// Drive from `.task(id: requestID)`. Both task cancellation and the request
    /// identity invalidate stale delays; the UI supplies a final scene check.
    func requestIfEligible(
        present: @MainActor () -> Void,
        finalCheck: @MainActor () -> Bool
    ) async {
        guard let requestedID = requestID else { return }
        do {
            try await delay()
        } catch {
            if requestID == requestedID { requestID = nil }
            return
        }
        guard requestID == requestedID else { return }
        guard !Task.isCancelled else {
            requestID = nil
            return
        }
        guard canPresent, finalCheck(), history.reserveAttempt(at: now()) else {
            requestID = nil
            return
        }
        correspondenceActivity = false
        liveCompletion = false
        returnedHomeAfterActivity = false
        requestID = nil
        present()
    }

    private var canPresent: Bool {
        context.isActive && !context.isBackground && context.userID != nil
            && context.isHome && !context.isBlocked && pendingMoves.isEmpty
            && !sessionHadFailure && returnedHomeAfterActivity
            && (liveCompletion
                || (correspondenceActivity && !context.hasCorrespondenceTurns))
    }

    private func refreshRequest() {
        guard canPresent, history.isEligible(at: now()) else {
            requestID = nil
            return
        }
        if requestID == nil { requestID = UUID() }
    }

    private func resetSession() {
        sessionID = UUID()
        pendingMoves.removeAll()
        observedLiveGames.removeAll()
        correspondenceActivity = false
        liveCompletion = false
        returnedHomeAfterActivity = false
        sessionHadFailure = false
        requestID = nil
    }
}
