//
//  ActivityModel.swift
//  Surround
//
//  What the Activity surfaces show: the bar on root screens, the iPad's and
//  the Mac's Now sections, the in-game control, a conversation's control and
//  the Activity list. `ActivityModel.snapshot(_:)`, `nowSection(_:rows:)`,
//  `gameControl(_:context:)` and `conversationControl(_:)` are pure functions
//  of one window's state, so the design's rules can be tested without a
//  socket. `ActivityModel.Input.window(ogs:nav:place:now:)` reads that state
//  from a window's `OGSService` and stores.
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

    /// A waiting item's id names its kind and the object it stands for.
    enum WaitingID {
        static func quickMatch(_ uuid: String) -> String { "quick-match-\(uuid)" }
        static func openChallenge(_ id: Int) -> String { "open-\(id)" }
        static func sentChallenge(_ id: Int) -> String { "sent-\(id)" }
        static func rengo(_ id: Int) -> String { "rengo-\(id)" }
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
        /// this session's recent ones. The app passes 0: every read
        /// conversation counts, as the saved peers Messages lists, so
        /// Nothing waiting shows only to someone without any.
        var sessionStart: TimeInterval = 0
        var now: TimeInterval = 0
        var place: Place = .root(isMessagesTab: false)
        /// The window's selected tab is Messages, whatever the place: with a
        /// conversation selected in Messages' side pane the place reads
        /// `.conversation`. Unread conversations don't count there.
        var isMessagesTabSelected = false
        /// The ids `hiding(_:)` left out: challenges and waiting items OGS
        /// confirmed gone that the service still lists. A hidden id not
        /// among them no longer needs hiding.
        var hiddenListedIDs: Set<String> = []
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

        /// The item that leads; nil for "N waiting".
        var item: Item? {
            switch self {
            case .gameStarted(let game): .liveGame(game)
            case .item(let item): item
            case .waiting: nil
            }
        }

        /// The leading item's id, as the list names it; nil for "N waiting".
        var itemID: String? { item?.id }
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
        /// What +N counted beside the lead, or what "N waiting" counts, in
        /// the list's order (`counts(_:onMessagesTab:)`). The lead never
        /// counts itself. Empty without a lead.
        var counted: [Item] = []
    }

    /// The iPad's and the Mac's Now section (`nowSection(_:rows:)`).
    struct NowSection: Equatable {
        /// In the lead order, the first of them what the bar leads with; or
        /// the one "N waiting" row when nothing that can lead waits. Empty
        /// when nothing waits.
        var rows: [Lead]
        /// All activity's +N: the counted items not in a row. None beside
        /// the "N waiting" row, which stands for them.
        var plusN: Int
        /// What +N counts, or what the "N waiting" row counts.
        var counted: [Item]
    }

    /// The control in Game Detail's Active games slot.
    enum GameControl: Equatable {
        /// A live game that started elsewhere, for `startedLeadDuration`.
        /// While you play live, challenges and messages are only a dot.
        case gameStarted(LiveGame, plusN: Int, hasDot: Bool)
        /// Another live game on your move: the chip, with +N beyond it.
        /// While you play live, challenges and messages are only a dot.
        case chip(LiveGame, plusN: Int, hasDot: Bool)
        /// Your finished game, whose popover leads with the challenge from
        /// its opponent that `GameOverCardRule` chose. +N counts what else
        /// waits.
        case gameOverCard(challengeID: Int, plusN: Int)
        /// Today's Active games button, with +N.
        case base(plusN: Int)
        /// While you play live, challenges and messages wait as a dot.
        case dot
        /// A game the user doesn't play, or one of theirs on a route without
        /// the picker: the inbox glyph and its count.
        case inbox(count: Int)
    }

    /// What the in-game control knows of its Game Detail beyond the
    /// window's state.
    struct GameControlContext: Equatable {
        /// The route has the picker of same-speed games and switches games
        /// in place (`GameControlSwitch`). Without it your own game shows
        /// the inbox, as a game you don't play does.
        var allowsPicker = true
        /// Zen shows only another live game on your move.
        var isZen = false
        /// The challenge the game-over card shows (`GameOverCardRule`).
        var cardChallengeID: Int?

        /// Home's route outside Zen, with no card.
        static let home = GameControlContext()
    }

    // MARK: - Rules

    /// How long a game that started elsewhere leads before it is ordered as
    /// a live game.
    static let startedLeadDuration: TimeInterval = 30
    /// Under this many seconds to timeout is low time, on any clock but
    /// byo-yomi, where only the last period is.
    static let lowTimeThreshold: TimeInterval = 30
    /// One warning haptic when another of your live games, on your move,
    /// falls through this many seconds to timeout (LowTimeHapticWatcher).
    /// In byo-yomi that is the last period's last seconds.
    static let lowTimeHapticThreshold: TimeInterval = 10
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
        let ordered = Ordered(input)
        let mostUrgent = ordered.correspondence.min { a, b in
            if a.isClockRunning != b.isClockRunning {
                return a.isClockRunning
            }
            let aLeft = a.timeUntilTimeout ?? .infinity
            let bLeft = b.timeUntilTimeout ?? .infinity
            return aLeft != bLeft ? aLeft < bLeft : a.id < b.id
        }

        var list = ordered.live.map { Item.liveGame($0) }
        list += ordered.challenges.map { Item.challenge($0) }
        list += ordered.waiting.map { Item.waiting($0) }
        if let mostUrgent {
            list.append(.correspondenceGames(count: ordered.correspondence.count, mostUrgentID: mostUrgent.id))
        }
        list += ordered.conversations.map { Item.conversation($0) }
        let lowTime = Set(ordered.live.filter(isLowOnTime).map(\.id))

        // The bar never shows on Game Detail or in a conversation.
        guard case .root = input.place else {
            return Snapshot(list: list, lead: nil, plusN: 0, lowTimeGameIDs: lowTime)
        }

        let counted = countedItems(ordered, onMessagesTab: input.isOnMessagesTab)
        switch leadOrder(input, ordered).first {
        case let lead?:
            let beyond = counted.filter { $0.id != lead.itemID }
            return Snapshot(list: list, lead: lead, plusN: beyond.count, lowTimeGameIDs: lowTime, counted: beyond)
        case nil where !counted.isEmpty:
            return Snapshot(list: list, lead: .waiting(count: counted.count), plusN: 0, lowTimeGameIDs: lowTime,
                            counted: counted)
        case nil:
            return Snapshot(list: list, lead: nil, plusN: 0, lowTimeGameIDs: lowTime)
        }
    }

    /// Whether `item` adds to +N: a live game on your move, any challenge
    /// sent to you, live or correspondence, and an unread conversation off
    /// the Messages tab. Your own searches and sent challenges, live games
    /// on their move and correspondence games on your move never do.
    static func counts(_ item: Item, onMessagesTab: Bool) -> Bool {
        switch item {
        case .liveGame(let game): game.isYourMove
        case .challenge: true
        case .conversation(let conversation): conversation.isUnread && !onMessagesTab
        case .waiting, .correspondenceGames: false
        }
    }

    /// How many rows the Now section lists at most, before All activity.
    static let nowSectionRows = 2

    /// The iPad's and the Mac's Now section: at most `rows` items in the
    /// order the bar picks its lead, so the first is the bar's lead; the
    /// "N waiting" row when nothing that can lead waits; and All activity's
    /// +N, the counted items not in a row. It answers for every place, a
    /// game and a conversation included, since the iPad's sidebar can show
    /// over a game and the Mac's never hides, and leaves the game on screen
    /// out by its id. On the Messages tab, unread conversations don't count.
    static func nowSection(_ input: Input, rows: Int) -> NowSection {
        let ordered = Ordered(input)
        let counted = countedItems(ordered, onMessagesTab: input.isOnMessagesTab)
        let leads = leadOrder(input, ordered)
        if leads.isEmpty, rows > 0, !counted.isEmpty {
            return NowSection(rows: [.waiting(count: counted.count)], plusN: 0, counted: counted)
        }
        let shown = Array(leads.prefix(max(0, rows)))
        let shownIDs = Set(shown.compactMap(\.itemID))
        let rest = counted.filter { !shownIDs.contains($0.id) }
        return NowSection(rows: shown, plusN: rest.count, counted: rest)
    }

    /// The control in a conversation's top bar, which shows only while a
    /// live game needs you: a live game that started elsewhere, during its
    /// `startedLeadDuration`, unless a game on your move is low on time;
    /// otherwise your live game on your move with the least time. Never +N
    /// or a dot, since the composer owns the screen and Activity is one
    /// Back away. Nil otherwise, and anywhere but a conversation.
    static func conversationControl(_ input: Input) -> GameControl? {
        guard input.place == .conversation else { return nil }
        let live = sortedLiveGames(input.liveGames)
        if let started = startedLead(input, allLive: live) {
            return .gameStarted(started, plusN: 0, hasDot: false)
        }
        return live.first(where: \.isYourMove).map { .chip($0, plusN: 0, hasDot: false) }
    }

    /// The in-game control on Home's route outside Zen, with no card.
    static func gameControl(_ input: Input) -> GameControl? {
        gameControl(input, context: .home)
    }

    /// The in-game control for the game `input.place` shows; nil where the
    /// slot hides. The first rule that applies wins:
    /// 1. In Zen, only the first other live game on your move, as the chip
    ///    with no +N and no dot.
    /// 2. A live game that started elsewhere.
    /// 3. Another live game on your move, in any game: the chip.
    /// 4. Your finished game with the card's challenge.
    /// 5. A game you don't play: the inbox.
    /// 6. Your unfinished live game: the dot when anything waits, otherwise
    ///    the base form where the route has the picker.
    /// 7. Otherwise the base form with +N where the route has the picker,
    ///    and the inbox where it doesn't.
    ///
    /// The inbox hides at 0. While you play live, other live games on your
    /// move still add to +N beside a chip or a started game; challenges and
    /// messages become the dot.
    static func gameControl(_ input: Input, context: GameControlContext) -> GameControl? {
        guard case let .game(id, isOwnGame, isLive, isOver) = input.place else { return nil }
        let others = sortedLiveGames(input.liveGames.filter { $0.id != id })
        let othersOnYourMove = others.filter(\.isYourMove)
        if context.isZen {
            return othersOnYourMove.first.map { GameControl.chip($0, plusN: 0, hasDot: false) }
        }
        let waitingCount = input.challengesReceived.count + input.conversations.filter(\.isUnread).count
        let playsLive = isOwnGame && isLive && !isOver

        /// Beyond a game the control shows: while you play live only other
        /// live games on your move count, and the rest is a dot.
        func beyond(_ shown: LiveGame) -> (plusN: Int, hasDot: Bool) {
            let games = othersOnYourMove.filter { $0.id != shown.id }.count
            return playsLive ? (games, waitingCount > 0) : (games + waitingCount, false)
        }
        let inbox: GameControl? = waitingCount > 0 ? .inbox(count: waitingCount) : nil

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
        // Only while the card's challenge still waits. Game over releases
        // what waited, so everything else counts.
        if isOwnGame, isOver, let card = context.cardChallengeID,
           input.challengesReceived.contains(where: { $0.id == card }) {
            return .gameOverCard(challengeID: card, plusN: waitingCount - 1)
        }
        guard isOwnGame else { return inbox }
        if playsLive {
            if waitingCount > 0 {
                return .dot
            }
            return context.allowsPicker ? .base(plusN: 0) : nil
        }
        return context.allowsPicker ? .base(plusN: waitingCount) : inbox
    }

    /// Live once OGS tags it, or from its clock and board size when the tag
    /// is missing; an unknown clock is never live.
    static func isRealtime(_ timeControl: TimeControl, width: Int, height: Int) -> Bool {
        timeControl.resolvedSpeed(boardWidth: width, boardHeight: height)?.isRealtime == true
    }

    /// The input's items in the list's order, without the game on screen.
    private struct Ordered {
        var live: [LiveGame]
        var challenges: [Challenge]
        var waiting: [Waiting]
        var correspondence: [CorrespondenceGame]
        var conversations: [Conversation]

        init(_ input: Input) {
            let onScreenGameID = input.place.gameID
            live = ActivityModel.sortedLiveGames(input.liveGames.filter { $0.id != onScreenGameID })
            challenges = input.challengesReceived.sorted { $0.id < $1.id }
            waiting = input.waiting.sorted { ($0.since, $0.kind, $0.id) < ($1.since, $1.kind, $1.id) }
            correspondence = input.correspondenceGamesOnYourMove.filter { $0.id != onScreenGameID }
            conversations = ActivityModel.orderedConversations(input.conversations, sessionStart: input.sessionStart)
        }
    }

    /// What adds to +N, in the list's order (`counts(_:onMessagesTab:)`).
    private static func countedItems(_ ordered: Ordered, onMessagesTab: Bool) -> [Item] {
        var items: [Item] = ordered.live.map { Item.liveGame($0) }
        items += ordered.challenges.map { Item.challenge($0) }
        items += ordered.conversations.map { Item.conversation($0) }
        return items.filter { counts($0, onMessagesTab: onMessagesTab) }
    }

    /// What can lead, in the order the bar picks its lead: the games that
    /// started elsewhere, newest first; live games on your move; live
    /// challenges; live games on their move; then your own live searches
    /// and challenges. Each item once; correspondence never leads.
    private static func leadOrder(_ input: Input, _ ordered: Ordered) -> [Lead] {
        // The game on screen counts for low time, but never as one that
        // started elsewhere.
        let started = startedGames(input, allLive: sortedLiveGames(input.liveGames), excluding: input.place.gameID)
        var items: [Item] = ordered.live.filter(\.isYourMove).map { Item.liveGame($0) }
        items += ordered.challenges.filter(\.isLive).map { Item.challenge($0) }
        items += ordered.live.filter { !$0.isYourMove }.map { Item.liveGame($0) }
        items += ordered.waiting.filter(\.isLive).map { Item.waiting($0) }
        var seen = Set(started.map { Item.liveGame($0).id })
        var leads: [Lead] = started.map { Lead.gameStarted($0) }
        leads += items.filter { seen.insert($0.id).inserted }.map { Lead.item($0) }
        return leads
    }

    /// The newest game that started in the last `startedLeadDuration`,
    /// unless a game on your move is low on time.
    private static func startedLead(_ input: Input, allLive: [LiveGame], excluding gameID: Int? = nil) -> LiveGame? {
        startedGames(input, allLive: allLive, excluding: gameID).first
    }

    /// The games that started in the last `startedLeadDuration`, newest
    /// first and in `allLive`'s order among equals; none while a game on
    /// your move is low on time.
    private static func startedGames(_ input: Input, allLive: [LiveGame], excluding gameID: Int?) -> [LiveGame] {
        guard !allLive.contains(where: isLowOnTime) else { return [] }
        struct Started {
            var game: LiveGame
            var start: TimeInterval
            var order: Int
        }
        var started = [Started]()
        for (order, game) in allLive.enumerated() where game.id != gameID {
            guard let start = input.startedGames[game.id],
                  input.now >= start, input.now - start < startedLeadDuration else { continue }
            started.append(Started(game: game, start: start, order: order))
        }
        started.sort { a, b in a.start != b.start ? a.start > b.start : a.order < b.order }
        return started.map(\.game)
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
    /// outcome; either can arrive first: a `phase` event ends a game before
    /// its outcome or the service's list catches up.
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
    ///     conversations. The app passes 0, so every read one counts.
    ///   - openChallenges: The user's own open and Rengo challenges, when
    ///     they come from elsewhere than the service, such as the window's
    ///     last-known copy while the socket is down. Nil reads the service's.
    init(
        ogs: OGSService,
        place: ActivityModel.Place,
        startedGames: [Int: TimeInterval] = [:],
        firstSeen: [String: TimeInterval] = [:],
        sessionStart: TimeInterval = 0,
        now: TimeInterval = Date().timeIntervalSince1970,
        openChallenges: ActivityLastKnown.OpenChallenges? = nil
    ) {
        self.init(startedGames: startedGames, sessionStart: sessionStart, now: now, place: place)
        guard let user = ogs.user else { return }
        let seekGraph = openChallenges ?? ActivityLastKnown.OpenChallenges(
            openChallengeSentById: ogs.openChallengeSentById,
            participatingRengoChallengeById: ogs.participatingRengoChallengeById,
            hostingRengoChallengeById: ogs.hostingRengoChallengeById
        )

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
        typealias WaitingID = ActivityModel.WaitingID
        var waiting = [ActivityModel.Waiting]()
        for entry in ogs.autoMatchEntryById.values {
            let id = WaitingID.quickMatch(entry.uuid)
            waiting.append(.init(
                id: id,
                kind: .quickMatch,
                isLive: !entry.isCorrespondence,
                since: since(id, created: entry.creationTimestamp)
            ))
        }
        for challenge in seekGraph.openChallengeSentById.values {
            let id = WaitingID.openChallenge(challenge.id)
            waiting.append(.init(
                id: id,
                kind: .openChallenge,
                isLive: ActivityModel.isRealtime(challenge.game.timeControl, width: challenge.game.width, height: challenge.game.height),
                since: since(id, created: challenge.createdAt?.timeIntervalSince1970)
            ))
        }
        for challenge in ogs.challengesSent {
            let id = WaitingID.sentChallenge(challenge.id)
            waiting.append(.init(
                id: id,
                kind: .sentChallenge,
                isLive: ActivityModel.isRealtime(challenge.game.timeControl, width: challenge.game.width, height: challenge.game.height),
                since: since(id)
            ))
        }
        let rengo = seekGraph.participatingRengoChallengeById
            .merging(seekGraph.hostingRengoChallengeById) { current, _ in current }
        for challenge in rengo.values {
            let id = WaitingID.rengo(challenge.id)
            waiting.append(.init(
                id: id,
                kind: .rengo,
                isLive: ActivityModel.isRealtime(challenge.game.timeControl, width: challenge.game.width, height: challenge.game.height),
                since: since(id, created: challenge.createdAt?.timeIntervalSince1970)
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

    /// One window's input, which its bar, its Now section, its Activity list
    /// and Game Detail's control all read: the service, with the window's
    /// live games that started elsewhere, the app's first-seen times, the
    /// window's last-known open challenges and its selected tab, less what
    /// OGS confirmed gone (`hiding(_:)`). In Debug runs with an Activity
    /// state, that state's input, less the same.
    /// - Parameter now: Seconds since 1970. A Debug state keeps its own clock.
    static func window(ogs: OGSService, nav: NavigationService, place: ActivityModel.Place,
                       now: TimeInterval = Date().timeIntervalSince1970) -> Self {
        #if DEBUG && MAIN_APP
        let fixture = ActivityFixtures.selectedInput(ogs, place: place)
        #else
        let fixture: Self? = nil
        #endif
        return window(ogs: ogs, nav: nav, place: place, now: now, fixture: fixture)
    }

    /// `window(ogs:nav:place:now:)` with a Debug state's input, if any, in
    /// place of the service's.
    static func window(ogs: OGSService, nav: NavigationService, place: ActivityModel.Place, now: TimeInterval,
                       fixture: Self?) -> Self {
        // Recent read conversations are the saved peers Messages lists, so
        // the session starts at the distant past.
        var input = fixture ?? Self(
            ogs: ogs, place: place, startedGames: nav.startedGamesRecorder.startedGames,
            firstSeen: ActivitySession.firstSeen, sessionStart: 0, now: now,
            openChallenges: nav.activityLastKnown.openChallenges(live: ogs)
        )
        input.isMessagesTabSelected = nav.main.rootView == .privateMessages
        return input.hiding(nav.activityResults.hiddenIDs)
    }

    /// The input without the challenges sent to you and your own waiting
    /// items whose ids (`ActivityModel.Item.id`) `hidden` holds: what OGS
    /// confirmed gone with a 2xx, which the service lists until its next
    /// overview or seek graph update. So none of them leads, counts or
    /// shows as a row. `hiddenListedIDs` gains the ids it left out.
    func hiding(_ hidden: Set<String>) -> Self {
        guard !hidden.isEmpty else { return self }
        var input = self
        var left = Set<String>()
        func keeps(_ item: ActivityModel.Item) -> Bool {
            guard hidden.contains(item.id) else { return true }
            left.insert(item.id)
            return false
        }
        input.challengesReceived = challengesReceived.filter { keeps(.challenge($0)) }
        input.waiting = waiting.filter { keeps(.waiting($0)) }
        input.hiddenListedIDs.formUnion(left)
        return input
    }

    /// The Messages tab is selected: from a root's place, or from the
    /// window's selected tab wherever the place is.
    var isOnMessagesTab: Bool {
        isMessagesTabSelected || place == .root(isMessagesTab: true)
    }
}
