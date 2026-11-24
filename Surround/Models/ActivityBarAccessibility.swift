//
//  ActivityBarAccessibility.swift
//  Surround
//
//  What VoiceOver hears from the Activity bar and from the Now section's
//  rows: each element's label, value and hint, and the breakdown of what +N
//  and "N waiting" count. A time that changes each second is an element's
//  value, so its label holds still. The visible words that only this
//  breakdown and the Now section say are here too, beside the sentences that
//  say them. Pure, so SurroundTests checks every sentence without a view.
//

import Foundation

/// One element of the bar or a Now row, as VoiceOver reads it.
struct ActivityBarAccessibility: Equatable {
    var label: String
    var value = ""
    var hint = ""
    /// The value is a time that changes each second.
    var updatesFrequently = false
}

extension ActivityBarAccessibility {
    /// What one of the user's own searches or challenges is, for its label.
    enum WaitingSubject: Equatable {
        case search
        case openChallenge
        /// A challenge sent to this player.
        case sentChallenge(to: String)
        /// A Rengo challenge, by its name.
        case rengo(String)
    }

    /// The bar, a container: "Activity".
    static var barLabel: String { Words.activity }

    /// The list's title, "Activity", which also names the Mac's command
    /// that opens it.
    static var listTitle: String { Words.activity }

    /// A live game's lead, or its Now row: "Live game with HarborMist, 1d.
    /// Your move", and "42 seconds left" as the value, which changes each
    /// second while the user's clock runs. Sudden death comes before the
    /// time; their move has no time; "Reconnecting to OGS" follows while the
    /// window's connection is down.
    /// - Parameters:
    ///   - rank: As the row shows it (`ActivityRowContents.rank`); nil while
    ///     the user hides ranks.
    ///   - timeLeft: The user's time left on that game's clock, said on the
    ///     user's move; nil without a countdown.
    ///   - ticks: The user's clock runs, so the time changes each second.
    static func liveGame(opponent: String, rank: String?, isYourMove: Bool, isSuddenDeath: Bool = false,
                         timeLeft: TimeInterval? = nil, ticks: Bool = false, isOffline: Bool = false,
                         locale: Locale = GameControlAccessibility.appLocale) -> Self {
        let who = player(opponent, rank: rank)
        let label = switch (isYourMove, isSuddenDeath) {
        case (true, false): Words.liveYourMove(who)
        case (true, true): Words.liveYourMoveInSuddenDeath(who)
        case (false, _): Words.liveTheirMove(who)
        }
        var value = [String]()
        let time = isYourMove ? timeLeft : nil
        if let time {
            value.append(Words.left(GameControlAccessibility.spokenDuration(time, locale: locale)))
        }
        if isOffline {
            value.append(Words.reconnectingToOGS)
        }
        return Self(label: label, value: joined(value), hint: Words.opensThatGame,
                    updatesFrequently: time != nil && ticks)
    }

    /// A live game that started elsewhere: "Game started with CedarWave".
    static func gameStarted(opponent: String) -> Self {
        Self(label: GameControlAccessibility.gameStarted(with: opponent), hint: Words.opensThatGame)
    }

    /// A live challenge sent to the user: "Challenge from CedarWave, 5k:
    /// 19×19, Ranked, Live".
    /// - Parameter details: The row's line two (`ActivityRowContents.challenge`).
    static func challenge(challenger: String, rank: String?, details: [String]) -> Self {
        Self(label: Words.challenge(from: player(challenger, rank: rank), details: list(details)),
             hint: Words.opensActivity)
    }

    /// One of the user's own searches or challenges: "Searching for a game:
    /// Quick match, Live, 19×19", with the time searched as its value.
    /// - Parameters:
    ///   - details: Line two without the time searched.
    ///   - waited: The time searched, for a search or an open challenge.
    ///   - ticks: The time searched moves (`ActivityElapsed.stopsAt` is nil).
    static func waiting(_ subject: WaitingSubject, details: [String], waited: TimeInterval? = nil,
                        ticks: Bool = false, locale: Locale = GameControlAccessibility.appLocale) -> Self {
        let what = list(details)
        let label = switch subject {
        case .search: Words.searching(what)
        case .openChallenge: Words.openChallenge(what)
        case .sentChallenge(let name): Words.sentChallenge(to: name, details: what)
        case .rengo(let name): Words.rengo(name, details: what)
        }
        return Self(label: label, value: waited.map { GameControlAccessibility.spokenDuration($0, locale: locale) } ?? "",
                    hint: Words.opensActivity, updatesFrequently: waited != nil && ticks)
    }

    /// Nothing live leads: "3 waiting for you: a correspondence challenge
    /// from CedarWave and 2 unread conversations".
    static func nothingLeads(count: Int, _ breakdown: ActivityBarBreakdown,
                             locale: Locale = GameControlAccessibility.appLocale) -> Self {
        Self(label: Words.waitingForYou(count, breakdown.spoken(locale: locale)), hint: Words.opensActivity)
    }

    /// +N: "3 more waiting for you: a challenge from CedarWave and 2 unread
    /// conversations".
    static func plusN(_ count: Int, _ breakdown: ActivityBarBreakdown,
                      locale: Locale = GameControlAccessibility.appLocale) -> Self {
        Self(label: Words.moreWaitingForYou(count, breakdown.spoken(locale: locale)), hint: Words.opensActivity)
    }

    /// The Now section's All activity, with what its +N counts as the value.
    static func allActivity(plusN: Int, _ breakdown: ActivityBarBreakdown,
                            locale: Locale = GameControlAccessibility.appLocale) -> Self {
        Self(label: allActivityTitle,
             value: plusN > 0 ? Words.moreWaitingForYou(plusN, breakdown.spoken(locale: locale)) : "",
             hint: Words.opensActivity)
    }

    /// A started game's Open game: "Open the game with CedarWave".
    static func openGame(opponent: String) -> String {
        String(localized: "Open the game with \(opponent)",
               comment: "Activity bar, VoiceOver: the Open game button of a live game that started elsewhere. The value is the opponent's name")
    }

    /// A challenge's View, as the list's row names it.
    static func view(challenger: String) -> String {
        String(localized: "View the challenge from \(challenger)",
               comment: "Activity: VoiceOver, the View button of a challenge someone sent the user")
    }

    /// Withdraw, as the list's row names it: what it withdraws, without the
    /// time searched (`ActivityRowContents.withdrawLabel`).
    static func withdraw(title: String, details: [String]) -> String {
        let subject = ([title] + details).joined(separator: ", ")
        return String(localized: "Withdraw \(subject)",
                      comment: "Activity: VoiceOver, the Withdraw button of the user's own search or challenge, with its row")
    }

    /// Retry beside "Can’t reach OGS".
    static var retry: String {
        String(localized: "Retry connecting to OGS",
               comment: "Activity bar and Now section, VoiceOver: the Retry button beside Can’t reach OGS")
    }

    /// A status kind, which isn't a button.
    static func status(_ words: RootConnectionLine.Words) -> Self {
        let label = switch words {
        case .connecting: ActivityBarWords.connecting
        case .reconnecting: Words.reconnectingToOGS
        case .unreachable: ActivityBarWords.unreachable
        case .connected: ActivityBarWords.connected
        }
        return Self(label: label)
    }

    /// An action taken in the bar: "Withdrawing…", "Withdrawn" or "Couldn’t
    /// withdraw", with what it acted on as the value.
    static func result(_ result: ActivityBarResult) -> Self {
        let label = switch result.state {
        case .pending: result.action.pendingText
        case .succeeded(let outcome): outcome.text
        case .failed: result.action.failureText
        }
        return Self(label: label, value: result.display.title)
    }

    /// The Now section's header.
    static var nowHeader: String {
        String(localized: "Now", comment: "iPad and Mac sidebar: the header of the section that lists what needs the user now, above All activity")
    }

    /// The Now section's last row, which opens Activity.
    static var allActivityTitle: String {
        String(localized: "All activity", comment: "iPad and Mac sidebar: the Now section's last row; opens the whole Activity list")
    }

    // MARK: Helpers

    /// "HarborMist, 1d", or the name alone while ranks are hidden.
    private static func player(_ name: String, rank: String?) -> String {
        guard let rank, !rank.isEmpty else { return name }
        return Words.joined(name, rank)
    }

    /// Details as one comma-separated phrase.
    private static func list(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Value parts, each after a comma.
    private static func joined(_ parts: [String]) -> String {
        guard var result = parts.first else { return "" }
        for part in parts.dropFirst() {
            result = Words.joined(result, part)
        }
        return result
    }

    fileprivate enum Words {
        static func liveYourMove(_ who: String) -> String {
            String(localized: "Live game with \(who). Your move",
                   comment: "Activity bar and Now section, VoiceOver: a live game on the user's move. The value is the opponent's name and rank; the time left follows as the element's value")
        }

        static func liveYourMoveInSuddenDeath(_ who: String) -> String {
            String(localized: "Live game with \(who). Your move, sudden death",
                   comment: "Activity bar and Now section, VoiceOver: a live game on the user's move, in its last byo-yomi period. The value is the opponent's name and rank; the time left follows as the element's value")
        }

        static func liveTheirMove(_ who: String) -> String {
            String(localized: "Live game with \(who). Their move",
                   comment: "Activity bar and Now section, VoiceOver: a live game on the opponent's move. The value is the opponent's name and rank")
        }

        static func left(_ time: String) -> String {
            String(localized: "\(time) left",
                   comment: "Activity bar and Now section, VoiceOver: the time left on the user's clock in a live game, such as 42 seconds; said after the game")
        }

        static func challenge(from who: String, details: String) -> String {
            String(localized: "Challenge from \(who): \(details)",
                   comment: "Activity bar and Now section, VoiceOver: a live challenge sent to the user. The first value is the challenger's name and rank, the second the board size, rankedness and speed")
        }

        static func searching(_ details: String) -> String {
            String(localized: "Searching for a game: \(details)",
                   comment: "Activity bar and Now section, VoiceOver: the user's Quick Match search. The value is its kind, speed and board sizes; the time searched follows as the element's value")
        }

        static func openChallenge(_ details: String) -> String {
            String(localized: "Open challenge: \(details)",
                   comment: "Activity bar and Now section, VoiceOver: an open challenge the user posted, which anyone can accept. The value is its speed and board size; the time it has waited follows as the element's value")
        }

        static func sentChallenge(to name: String, details: String) -> String {
            String(localized: "Challenge to \(name): \(details)",
                   comment: "Activity bar and Now section, VoiceOver: a challenge the user sent to this player. The first value is the player's name, the second the speed and board size")
        }

        static func rengo(_ name: String, details: String) -> String {
            String(localized: "Rengo · \(name): \(details)",
                   comment: "Activity bar and Now section, VoiceOver: a Rengo challenge the user hosts or joined. The first value is its name, the second its speed, board size and players")
        }

        static func waitingForYou(_ count: Int, _ breakdown: String) -> String {
            String(localized: "\(count) waiting for you: \(breakdown)",
                   comment: "Activity bar, VoiceOver: nothing live leads, and this many challenges and messages wait. The second value lists them, such as a correspondence challenge from CedarWave and 2 unread conversations")
        }

        static func moreWaitingForYou(_ count: Int, _ breakdown: String) -> String {
            String(localized: "\(count) more waiting for you: \(breakdown)",
                   comment: "Activity bar and Now section, VoiceOver: how many more games, challenges and messages wait beyond what is shown. The second value lists them, such as a challenge from CedarWave and 2 unread conversations")
        }

        static var activity: String {
            String(localized: "Activity", comment: "Title of the list of the user's games, challenges, searches and messages. Also the Activity bar's VoiceOver name and the Mac's View menu command that opens the list")
        }

        static var reconnectingToOGS: String {
            String(localized: "Reconnecting to OGS",
                   comment: "VoiceOver: spoken once when the app loses its connection to OGS and starts reconnecting")
        }

        static var opensThatGame: String {
            String(localized: "Opens that game.",
                   comment: "In-game control, VoiceOver hint: a tap opens the live game that just started")
        }

        static var opensActivity: String {
            String(localized: "Opens Activity.",
                   comment: "In-game control, VoiceOver hint: a tap opens the popover of the user's other games and Activity")
        }

        static func joined(_ first: String, _ second: String) -> String {
            String(localized: "\(first), \(second)",
                   comment: "Two parts of an accessibility description separated by a comma, such as a speaker and message or a game speed and search status.")
        }
    }
}

// MARK: - What +N and "N waiting" count

/// What +N, "N waiting" and All activity count, by kind, in the list's
/// order: live games on your move, challenges, then unread conversations.
struct ActivityBarBreakdown: Equatable {
    struct Challenge: Equatable {
        /// Nil once the service no longer has the challenge.
        var challenger: String?
        var isLive: Bool
    }

    var liveGamesOnYourMove = 0
    var challenges: [Challenge] = []
    var unreadConversations = 0

    init(liveGamesOnYourMove: Int = 0, challenges: [Challenge] = [], unreadConversations: Int = 0) {
        self.liveGamesOnYourMove = liveGamesOnYourMove
        self.challenges = challenges
        self.unreadConversations = unreadConversations
    }

    /// - Parameter challenger: A challenge's challenger, by the challenge's id.
    init(_ counted: [ActivityBarCountedItem], challenger: (Int) -> String?) {
        for item in counted {
            switch item {
            case .liveGame: liveGamesOnYourMove += 1
            case .challenge(let challenge):
                challenges.append(Challenge(challenger: challenger(challenge.id), isLive: challenge.isLive))
            case .conversation: unreadConversations += 1
            }
        }
    }

    /// What VoiceOver says of them: "a challenge from CedarWave and 2 unread
    /// conversations". One challenge names its challenger.
    func spoken(locale: Locale = GameControlAccessibility.appLocale) -> String {
        var phrases = [String]()
        if liveGamesOnYourMove > 0 {
            phrases.append(String(localized: "\(liveGamesOnYourMove) live games on your move",
                                  comment: "Activity bar, VoiceOver: one part of what waits for the user, such as 2 live games on your move"))
        }
        if challenges.count == 1, let name = challenges[0].challenger {
            phrases.append(challenges[0].isLive
                ? String(localized: "a challenge from \(name)",
                         comment: "Activity bar, VoiceOver: one part of what waits for the user, a live challenge from this player")
                : String(localized: "a correspondence challenge from \(name)",
                         comment: "Activity bar, VoiceOver: one part of what waits for the user, a correspondence challenge from this player"))
        } else if !challenges.isEmpty {
            phrases.append(String(localized: "\(challenges.count) challenges",
                                  comment: "Activity bar, VoiceOver: one part of what waits for the user, how many challenges were sent to them"))
        }
        if unreadConversations > 0 {
            phrases.append(String(localized: "\(unreadConversations) unread conversations",
                                  comment: "Activity bar, VoiceOver: one part of what waits for the user, how many conversations are unread"))
        }
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: phrases) ?? phrases.joined(separator: ", ")
    }

    /// Line two of "N waiting", where nothing live leads, so only
    /// correspondence challenges and unread conversations can wait: "A
    /// correspondence challenge · 2 conversations".
    var lineTwo: String {
        var parts = [String]()
        let correspondence = challenges.filter { !$0.isLive }.count
        if correspondence > 0 {
            parts.append(String(localized: "\(correspondence) correspondence challenges",
                                comment: "Activity bar: under N waiting, how many correspondence challenges were sent to the user"))
        }
        if unreadConversations > 0 {
            parts.append(String(localized: "\(unreadConversations) conversations",
                                comment: "Activity bar: under N waiting, how many conversations are unread"))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Words the bar shows

/// The words the bar's status kinds and actions show, from the catalog's
/// existing keys, so the bar and the fit test read the same text.
enum ActivityBarWords {
    static var unreachable: String {
        String(localized: "Can’t reach OGS", comment: "Activity: under the title while the app can't connect to OGS; shown with Retry")
    }

    static var reconnecting: String { String(localized: "Reconnecting…") }

    static var connecting: String {
        String(localized: "Connecting…", comment: "While the app first connects to OGS: a game's clock badge and title capsule, and the connection status in the Activity bar, the Now section, under root titles, in the Activity list and on the moderator cover")
    }

    static var connected: String { String(localized: "Connected", comment: "Connection status") }

    static func status(_ words: RootConnectionLine.Words) -> String {
        switch words {
        case .connecting: connecting
        case .reconnecting: reconnecting
        case .unreachable: unreachable
        case .connected: connected
        }
    }

    static func action(_ action: ActivityBarAction) -> String {
        switch action {
        case .openGame:
            String(localized: "Open game", comment: "Activity: opens the correspondence game an accepted challenge started")
        case .view:
            String(localized: "View", comment: "Activity: opens a challenge's full card, for a challenge that needs a closer look")
        case .withdraw:
            String(localized: "Withdraw")
        case .retry:
            String(localized: "Retry")
        }
    }

    static var gameStarted: String { String(localized: "Game started") }

    static var challenge: String {
        String(localized: "activity.lead.challenge", defaultValue: "Challenge",
               comment: "The first word of a challenge's line two in the Activity bar and the Now section, before its details. A noun, the challenge itself, not the profile's button that sends one")
    }

    static var searching: String {
        String(localized: "Searching for a game", comment: "Status indicating that one Quick Match request is active.")
    }

    static func waiting(_ count: Int) -> String {
        String(localized: "\(count) waiting",
               comment: "In-game control, VoiceOver: how many games, challenges and messages wait in Activity. The Activity bar also shows it, as its first line when nothing live leads")
    }
}

#if DEBUG
// MARK: - The Debug state element

/// What the hidden Debug element `activity.bar.state` says a host applied:
/// the kind, the lead's item id, the host and the form, such as "live
/// game-26268404 uiKitAccessory expanded", or "none" where no bar shows.
enum ActivityBarAppliedState {
    static func text(_ content: ActivityBarContent?, host: ActivityHostPolicy.Bar?, form: ActivityBarForm) -> String {
        guard let content, let host else { return "none" }
        return [kind(content), itemID(content) ?? "none", host.rawValue, "\(form)"].joined(separator: " ")
    }

    static func kind(_ content: ActivityBarContent) -> String {
        switch content {
        case .result(let result):
            switch result.state {
            case .pending: "pending"
            case .succeeded: "succeeded"
            case .failed: "failed"
            }
        case .unreachable: "unreachable"
        case .status(let words): "\(words)"
        case .lead(let lead, _, _):
            switch lead {
            case .liveGame: "live"
            case .gameStarted: "started"
            case .challenge: "challenge"
            case .waiting(let waiting, _):
                switch waiting.kind {
                case .quickMatch: "search"
                case .openChallenge: "openChallenge"
                case .sentChallenge: "sentChallenge"
                case .rengo: "rengo"
                }
            case .nothingLeads: "nothingLeads"
            }
        }
    }

    private static func itemID(_ content: ActivityBarContent) -> String? {
        switch content {
        case .result(let result): result.itemID
        case .lead(let lead, _, _): lead.itemID
        case .unreachable, .status: nil
        }
    }
}
#endif
