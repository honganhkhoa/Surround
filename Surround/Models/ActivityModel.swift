//
//  ActivityModel.swift
//  Surround
//
//  What the Activity surfaces show: the bar on root screens, the in-game
//  control and the Activity list. `ActivityModel.snapshot(_:)` and
//  `ActivityModel.gameControl(_:)` are pure functions of one window's state,
//  so the design's rules can be tested without a socket.
//  `ActivityModel.Input(ogs:place:...)` reads that state from an `OGSService`.
//

import Foundation

enum ActivityModel {

    // MARK: - Input

    /// One of the user's unfinished live games.
    struct LiveGame: Equatable {
        var id: Int
        /// The user's turn, or a stone removal the user has not accepted.
        var isYourMove: Bool
        var isStoneRemoval = false
        var isPaused = false
        /// The user's own clock is running. Connection state never changes
        /// this, so the order and low time stay as last known while offline.
        var isClockRunning = false
        /// Seconds until the user's own clock runs out, counting byo-yomi
        /// periods and the current Canadian block, when that is known.
        var timeUntilTimeout: TimeInterval?
        var usesByoyomi = false
        /// The user's clock is in byo-yomi's last period.
        var isInLastByoyomiPeriod = false
    }

    struct CorrespondenceGame: Equatable {
        var id: Int
        /// False while paused or in stone removal.
        var isClockRunning = true
        var timeUntilTimeout: TimeInterval?
    }

    /// A challenge someone sent the user.
    struct Challenge: Equatable {
        var id: Int
        var isLive: Bool
        /// Custom komi, a handicap, an unusual clock or an unusual board
        /// size. Such a challenge shows its warning and View instead of an
        /// inline Accept.
        var isUnusual = false
    }

    /// Something of the user's own that waits for an opponent.
    struct Waiting: Equatable {
        enum Kind: Int, Comparable {
            case quickMatch, openChallenge, sentChallenge, rengo

            static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
        }

        var id: String
        var kind: Kind
        var isLive: Bool
        /// When it was created or first seen, in seconds since 1970, so
        /// every kind sorts oldest first on one time base.
        var since: TimeInterval
    }

    struct Conversation: Equatable {
        var peerID: Int
        var isUnread: Bool
        var lastMessageTime: TimeInterval
    }

    /// Where the surfaces are drawn.
    enum Place: Equatable {
        case root(isMessagesTab: Bool)
        /// A conversation, pushed or selected in Messages' side pane.
        case conversation
        /// Game Detail. `isOwnGame` means the user plays in it.
        case game(id: Int, isOwnGame: Bool, isLive: Bool, isOver: Bool)
    }

    struct Input: Equatable {
        var liveGames: [LiveGame] = []
        var correspondenceGamesOnYourMove: [CorrespondenceGame] = []
        var challengesReceived: [Challenge] = []
        var waiting: [Waiting] = []
        var conversations: [Conversation] = []
        /// Live games that started without the user opening them, by start
        /// time. The caller drops a game once the user opens it.
        var startedGames: [Int: TimeInterval] = [:]
        /// Read conversations with no message since then don't count as
        /// this session's recent ones.
        var sessionStart: TimeInterval = 0
        var now: TimeInterval = 0
        var place: Place = .root(isMessagesTab: false)
    }

    // MARK: - Output

    enum Item: Equatable, Identifiable {
        case liveGame(LiveGame)
        case challenge(Challenge)
        case waiting(Waiting)
        /// One row for the correspondence games on your move; it opens the
        /// most urgent one other than the game on screen.
        case correspondenceGames(count: Int, mostUrgentID: Int)
        case conversation(Conversation)

        var id: String {
            switch self {
            case .liveGame(let game): "game-\(game.id)"
            case .challenge(let challenge): "challenge-\(challenge.id)"
            case .waiting(let waiting): "waiting-\(waiting.id)"
            case .correspondenceGames: "correspondence-games"
            case .conversation(let conversation): "conversation-\(conversation.peerID)"
            }
        }
    }

    enum Lead: Equatable {
        /// A live game that started elsewhere, before it is ordered as a
        /// live game.
        case gameStarted(LiveGame)
        case item(Item)
        /// Nothing live leads: the inbox glyph and the count, "3 waiting".
        case waiting(count: Int)
    }

    struct Snapshot: Equatable {
        /// Activity's list in order: live games, challenges received,
        /// waiting for opponents, correspondence games and messages.
        var list: [Item]
        /// The bar's lead; nil means there is no bar, as on Game Detail and
        /// in a conversation.
        var lead: Lead?
        /// What else waits for you beyond the lead.
        var plusN: Int
        /// Live games on your move that are low on time.
        var lowTimeGameIDs: Set<Int>
    }

    /// The control in Game Detail's Active games slot.
    enum GameControl: Equatable {
        /// A live game that started elsewhere, for `startedLeadDuration`.
        /// While you play live, challenges and messages are only a dot.
        case gameStarted(LiveGame, plusN: Int, hasDot: Bool)
        /// Another live game on your move: the chip, with +N beyond it.
        /// While you play live, challenges and messages are only a dot.
        case chip(LiveGame, plusN: Int, hasDot: Bool)
        /// Today's Active games button, with +N.
        case base(plusN: Int)
        /// While you play live, challenges and messages wait as a dot.
        case dot
        /// A game the user doesn't play: the inbox glyph and its count.
        case inbox(count: Int)
    }

    // MARK: - Rules

    /// How long a game that started elsewhere leads before it is ordered as
    /// a live game.
    static let startedLeadDuration: TimeInterval = 30
    /// Under this many seconds to timeout is low time, on any clock but
    /// byo-yomi, where only the last period is.
    static let lowTimeThreshold: TimeInterval = 30
    /// How many read conversations follow the unread ones in the list.
    static let recentConversationLimit = 3

    static func isLowOnTime(_ game: LiveGame) -> Bool {
        guard game.isYourMove, game.isClockRunning else { return false }
        if game.usesByoyomi {
            return game.isInLastByoyomiPeriod
        }
        guard let left = game.timeUntilTimeout else { return false }
        return left < lowTimeThreshold
    }

    /// Your move first: running clocks by least time to timeout, then games
    /// with no running clock (stone removal, paused). Their move after, by
    /// id. Ties go by id.
    static func sortedLiveGames(_ games: [LiveGame]) -> [LiveGame] {
        let yours = games.filter(\.isYourMove).sorted { a, b in
            if a.isClockRunning != b.isClockRunning {
                return a.isClockRunning
            }
            if a.isClockRunning {
                let aLeft = a.timeUntilTimeout ?? .infinity
                let bLeft = b.timeUntilTimeout ?? .infinity
                if aLeft != bLeft {
                    return aLeft < bLeft
                }
            }
            return a.id < b.id
        }
        let theirs = games.filter { !$0.isYourMove }.sorted { $0.id < $1.id }
        return yours + theirs
    }

    /// Unread conversations, newest first, then the read ones with a message
    /// since `sessionStart`, newest first and at most
    /// `recentConversationLimit`.
    static func orderedConversations(
        _ conversations: [Conversation],
        sessionStart: TimeInterval = 0
    ) -> [Conversation] {
        let newestFirst: (Conversation, Conversation) -> Bool = { a, b in
            if a.lastMessageTime != b.lastMessageTime {
                return a.lastMessageTime > b.lastMessageTime
            }
            return a.peerID < b.peerID
        }
        let unread = conversations.filter(\.isUnread).sorted(by: newestFirst)
        let recent = conversations
            .filter { !$0.isUnread && $0.lastMessageTime > 0 && $0.lastMessageTime >= sessionStart }
            .sorted(by: newestFirst)
            .prefix(recentConversationLimit)
        return unread + recent
    }

    static func snapshot(_ input: Input) -> Snapshot {
        let onScreenGameID = input.place.gameID
        let live = sortedLiveGames(input.liveGames.filter { $0.id != onScreenGameID })
        let challenges = input.challengesReceived.sorted { $0.id < $1.id }
        let waiting = input.waiting.sorted { ($0.since, $0.kind, $0.id) < ($1.since, $1.kind, $1.id) }
        let correspondence = input.correspondenceGamesOnYourMove.filter { $0.id != onScreenGameID }
        let mostUrgent = correspondence.min { a, b in
            if a.isClockRunning != b.isClockRunning {
                return a.isClockRunning
            }
            let aLeft = a.timeUntilTimeout ?? .infinity
            let bLeft = b.timeUntilTimeout ?? .infinity
            return aLeft != bLeft ? aLeft < bLeft : a.id < b.id
        }
        let conversations = orderedConversations(input.conversations, sessionStart: input.sessionStart)

        var list = live.map { Item.liveGame($0) }
        list += challenges.map { Item.challenge($0) }
        list += waiting.map { Item.waiting($0) }
        if let mostUrgent {
            list.append(.correspondenceGames(count: correspondence.count, mostUrgentID: mostUrgent.id))
        }
        list += conversations.map { Item.conversation($0) }
        let lowTime = Set(live.filter(isLowOnTime).map(\.id))

        // The bar never shows on Game Detail or in a conversation.
        guard case .root(let isMessagesTab) = input.place else {
            return Snapshot(list: list, lead: nil, plusN: 0, lowTimeGameIDs: lowTime)
        }

        // Only these add to +N. Your own searches and sent challenges, live
        // games on their move and correspondence games on your move don't.
        let counted = live.filter(\.isYourMove).map { Item.liveGame($0) }
            + challenges.map { Item.challenge($0) }
            + (isMessagesTab ? [] : conversations.filter(\.isUnread).map { Item.conversation($0) })

        let lead: Lead?
        var leadItemID: String?
        if let started = startedLead(input, allLive: live) {
            lead = .gameStarted(started)
            leadItemID = Item.liveGame(started).id
        } else if let item = leadItem(live: live, challenges: challenges, waiting: waiting) {
            lead = .item(item)
            leadItemID = item.id
        } else if !counted.isEmpty {
            lead = .waiting(count: counted.count)
        } else {
            lead = nil
        }

        let plusN: Int
        switch lead {
        case .waiting, nil:
            plusN = 0
        case .gameStarted, .item:
            plusN = counted.filter { $0.id != leadItemID }.count
        }
        return Snapshot(list: list, lead: lead, plusN: plusN, lowTimeGameIDs: lowTime)
    }

    static func gameControl(_ input: Input) -> GameControl? {
        guard case let .game(id, isOwnGame, isLive, isOver) = input.place else { return nil }
        let others = sortedLiveGames(input.liveGames.filter { $0.id != id })
        let othersOnYourMove = others.filter(\.isYourMove)
        let waitingCount = input.challengesReceived.count + input.conversations.filter(\.isUnread).count
        let playsLive = isOwnGame && isLive && !isOver

        /// Beyond a game the control shows: while you play live only other
        /// live games on your move count, and the rest is a dot.
        func beyond(_ shown: LiveGame) -> (plusN: Int, hasDot: Bool) {
            let games = othersOnYourMove.filter { $0.id != shown.id }.count
            return playsLive ? (games, waitingCount > 0) : (games + waitingCount, false)
        }

        // The game on screen counts for low time, but never as the one that
        // started elsewhere.
        if let started = startedLead(input, allLive: sortedLiveGames(input.liveGames), excluding: id) {
            let extra = beyond(started)
            return .gameStarted(started, plusN: extra.plusN, hasDot: extra.hasDot)
        }
        if let chip = othersOnYourMove.first {
            let extra = beyond(chip)
            return .chip(chip, plusN: extra.plusN, hasDot: extra.hasDot)
        }
        guard isOwnGame else {
            return waitingCount > 0 ? .inbox(count: waitingCount) : nil
        }
        if playsLive {
            return waitingCount > 0 ? .dot : .base(plusN: 0)
        }
        return .base(plusN: waitingCount)
    }

    /// Live once OGS tags it, or from its clock and board size when the tag
    /// is missing; an unknown clock is never live.
    static func isRealtime(_ timeControl: TimeControl, width: Int, height: Int) -> Bool {
        timeControl.resolvedSpeed(boardWidth: width, boardHeight: height)?.isRealtime == true
    }

    /// A live game on your move, a live challenge, a live game on their
    /// move, then your own live searches and challenges. Correspondence
    /// never leads.
    private static func leadItem(live: [LiveGame], challenges: [Challenge], waiting: [Waiting]) -> Item? {
        if let game = live.first(where: \.isYourMove) {
            return .liveGame(game)
        }
        if let challenge = challenges.first(where: \.isLive) {
            return .challenge(challenge)
        }
        if let game = live.first(where: { !$0.isYourMove }) {
            return .liveGame(game)
        }
        if let item = waiting.first(where: \.isLive) {
            return .waiting(item)
        }
        return nil
    }

    /// The newest game that started in the last `startedLeadDuration`,
    /// unless a game on your move is low on time.
    private static func startedLead(_ input: Input, allLive: [LiveGame], excluding gameID: Int? = nil) -> LiveGame? {
        guard !allLive.contains(where: isLowOnTime) else { return nil }
        return allLive
            .filter { $0.id != gameID }
            .compactMap { game in input.startedGames[game.id].map { (game: game, start: $0) } }
            .filter { input.now >= $0.start && input.now - $0.start < startedLeadDuration }
            .max { $0.start < $1.start }?
            .game
    }
}

extension ActivityModel.Place {
    var gameID: Int? {
        if case let .game(id, _, _, _) = self {
            return id
        }
        return nil
    }

    /// Game Detail and conversations hide the bar; root screens don't.
    var hidesBar: Bool {
        if case .root = self { return false }
        return true
    }
}

// MARK: - Reading the app's state

extension Game {
    /// Seconds until `color`'s clock runs out, counting byo-yomi periods and
    /// the current Canadian block. Nil before the clock starts, and for an
    /// untimed or unknown system.
    func timeUntilTimeout(for color: StoneColor) -> TimeInterval? {
        guard let clock, clock.started, let system = gameData?.timeControl.system else { return nil }
        let time = color == .black ? clock.blackTime : clock.whiteTime
        let main = time.thinkingTimeLeft ?? 0
        switch system {
        case .ByoYomi:
            if main > 0 {
                return main + Double(time.periods ?? 0) * (time.periodTime ?? 0)
            }
            let periodsAfter = max(0, (time.periodsLeft ?? 1) - 1)
            return (time.periodTimeLeft ?? 0) + Double(periodsAfter) * (time.periodTime ?? 0)
        case .Canadian(_, let period, _):
            return main > 0 ? main + Double(period) : time.blockTimeLeft
        case .None, .Unknown:
            return nil
        default:
            return time.thinkingTimeLeft
        }
    }
}

extension ActivityModel.LiveGame {
    /// Nil for a finished game, or one the user doesn't play.
    init?(game: Game, userID: Int) {
        let ended = ActivityModel.hasEnded(game)
        guard let id = game.ogsID, !ended, let color = game.userStoneColor else { return nil }
        // Connection state stays out: offline the order, low time and the
        // lead stay as last known, as Home's chips do.
        let clock = GameDetailClockState(game: game, color: color)
        var usesByoyomi = false
        if case .ByoYomi = game.gameData?.timeControl.system {
            usesByoyomi = true
        }
        self.init(
            id: id,
            isYourMove: game.requiresUserAction(forPlayerWithId: userID),
            isStoneRemoval: game.gamePhase == .stoneRemoval,
            isPaused: game.pauseControl?.isPaused() ?? false,
            isClockRunning: clock.running,
            timeUntilTimeout: game.timeUntilTimeout(for: color),
            usesByoyomi: usesByoyomi,
            isInLastByoyomiPeriod: clock.suddenDeath
        )
    }
}

extension ActivityModel {
    /// A game is over once its phase is finished or OGS has sent an
    /// outcome; either can arrive first, as
    /// NavigationService.liveGamesNeedingNotice(among:) notes.
    static func hasEnded(_ game: Game) -> Bool {
        game.gamePhase == .finished
            || !(game.gameData?.outcome?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

extension ActivityModel.Place {
    /// What a Game Detail showing `game` registers, and what its in-game
    /// control will use. Whether the user plays it follows the signed-in
    /// account through `game.ogs`. A game without an OGS id gets 0, which
    /// matches no listed game.
    init(showing game: Game) {
        let isLive = game.gameData.map {
            ActivityModel.isRealtime($0.timeControl, width: game.width, height: game.height)
        } ?? false
        self = .game(id: game.ogsID ?? 0, isOwnGame: game.isUserPlaying,
                     isLive: isLive, isOver: ActivityModel.hasEnded(game))
    }
}

extension ActivityModel.Input {
    /// Reads one window's state.
    /// - Parameters:
    ///   - startedGames: Live games that started without the user opening
    ///     them, by start time.
    ///   - firstSeen: When each waiting item without a creation time was
    ///     first seen, keyed by `ActivityModel.Waiting.id`; unseen ones count
    ///     as seen now.
    ///   - sessionStart: The start of this app session, for recent
    ///     conversations.
    init(
        ogs: OGSService,
        place: ActivityModel.Place,
        startedGames: [Int: TimeInterval] = [:],
        firstSeen: [String: TimeInterval] = [:],
        sessionStart: TimeInterval = 0,
        now: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.init(startedGames: startedGames, sessionStart: sessionStart, now: now, place: place)
        guard let user = ogs.user else { return }

        liveGames = ogs.liveGames.compactMap { ActivityModel.LiveGame(game: $0, userID: user.id) }
        correspondenceGamesOnYourMove = ogs.sortedActiveCorrespondenceGamesOnUserTurn.compactMap { game in
            guard let id = game.ogsID, let color = game.userStoneColor else { return nil }
            return ActivityModel.CorrespondenceGame(
                id: id,
                isClockRunning: GameDetailClockState(game: game, color: color).running,
                timeUntilTimeout: game.timeUntilTimeout(for: color)
            )
        }
        challengesReceived = ogs.challengesReceived.map {
            ActivityModel.Challenge(
                id: $0.id,
                isLive: ActivityModel.isRealtime($0.game.timeControl, width: $0.game.width, height: $0.game.height),
                isUnusual: $0.isUnusual
            )
        }

        func since(_ id: String, created: TimeInterval? = nil) -> TimeInterval {
            created ?? firstSeen[id] ?? now
        }
        var waiting = [ActivityModel.Waiting]()
        for entry in ogs.autoMatchEntryById.values {
            let id = "quick-match-\(entry.uuid)"
            waiting.append(.init(
                id: id,
                kind: .quickMatch,
                isLive: !entry.isCorrespondence,
                since: since(id, created: entry.creationTimestamp)
            ))
        }
        for challenge in ogs.openChallengeSentById.values {
            let id = "open-\(challenge.id)"
            waiting.append(.init(
                id: id,
                kind: .openChallenge,
                isLive: ActivityModel.isRealtime(challenge.game.timeControl, width: challenge.game.width, height: challenge.game.height),
                since: since(id)
            ))
        }
        for challenge in ogs.challengesSent {
            let id = "sent-\(challenge.id)"
            waiting.append(.init(
                id: id,
                kind: .sentChallenge,
                isLive: ActivityModel.isRealtime(challenge.game.timeControl, width: challenge.game.width, height: challenge.game.height),
                since: since(id)
            ))
        }
        let rengo = ogs.participatingRengoChallengeById.merging(ogs.hostingRengoChallengeById) { current, _ in current }
        for challenge in rengo.values {
            let id = "rengo-\(challenge.id)"
            waiting.append(.init(
                id: id,
                kind: .rengo,
                isLive: ActivityModel.isRealtime(challenge.game.timeControl, width: challenge.game.width, height: challenge.game.height),
                since: since(id)
            ))
        }
        self.waiting = waiting

        let unread = ogs.privateMessagesUnreadPeerIds
        conversations = unread.union(ogs.privateMessagesActivePeerIds).map { peerID in
            ActivityModel.Conversation(
                peerID: peerID,
                isUnread: unread.contains(peerID),
                lastMessageTime: ogs.privateMessagesByPeerId[peerID]?.last?.content.timestamp ?? 0
            )
        }
    }
}
