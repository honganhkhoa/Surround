//
//  ActivityRows.swift
//  Surround
//
//  The Activity list's rows, one view per kind: live games, challenges
//  received, the user's own searches and challenges, the correspondence
//  row, conversations, All messages, and a row whose item went after the
//  user acted on it. Each row is one VoiceOver element whose label reads it
//  as a sentence; its buttons stay separate elements with full labels. At
//  accessibility sizes a row drops its second line before any action label
//  shortens. Also the hook through which the challenge and Quick Match cards
//  act inside Activity.
//

import SwiftUI

private typealias ID = SurroundUITestContract.AccessibilityID

// MARK: - The cards' hook

/// How the challenge and Quick Match cards act inside Activity: through the
/// window's results store, which owns each request. Unset elsewhere, where
/// the cards send their own requests and navigate as they always have.
struct ActivityCellActions {
    /// The item's request is in flight: the card shows its spinner and sends
    /// nothing more.
    var isPending = false
    var accept: (any OGSSubmittedChallenge) -> Void
    var reject: (any OGSSubmittedChallenge) -> Void
    /// The user's own open or sent challenge, or a Rengo challenge the user
    /// hosts.
    var withdraw: (any OGSSubmittedChallenge) -> Void
    var withdrawSearch: (OGSAutomatchEntry) -> Void
    var leave: (OGSSeekgraphChallenge) -> Void
    var start: (OGSSeekgraphChallenge) -> Void
}

private struct ActivityCellActionsKey: EnvironmentKey {
    static let defaultValue: ActivityCellActions? = nil
}

extension EnvironmentValues {
    var activityCellActions: ActivityCellActions? {
        get { self[ActivityCellActionsKey.self] }
        set { self[ActivityCellActionsKey.self] = newValue }
    }
}

// MARK: - Density

/// The rows of the sheet and of a popover on a root screen, or the denser
/// rows of a game's popover.
enum ActivityRowDensity {
    case regular, dense

    var tile: CGFloat { self == .regular ? 40 : 36 }
    var rowHeight: CGFloat { self == .regular ? 60 : 56 }
    var liveGameHeight: CGFloat { self == .regular ? 72 : 56 }
    var horizontalPadding: CGFloat { self == .regular ? 12 : 16 }
    var titleFont: Font { self == .regular ? .callout.weight(.semibold) : .subheadline.weight(.semibold) }
    var rankFont: Font { self == .regular ? .subheadline : .footnote }
    /// Separators start past the tile.
    var separatorInset: CGFloat { horizontalPadding + tile + 12 }
}

// MARK: - Words

/// A row's words, from the service's objects. They also become the frozen
/// `ActivityRowDisplay` an action keeps.
struct ActivityRowContent {
    var title: String
    var rank: String?
    /// Line two, joined with middle dots.
    var details: [String] = []
    /// A challenge's time control and komi: line three in the sheet.
    var moreDetails: [String] = []
    var user: OGSUser?
    /// The glyph circle of the user's own searches and challenges.
    var symbol: String?

    var detail: String { details.joined(separator: " · ") }

    var display: ActivityRowDisplay {
        ActivityRowDisplay(
            title: title,
            detail: (details + moreDetails).joined(separator: " · "),
            avatarURL: user?.iconURL(ofSize: 80),
            initial: user.map { String($0.username.prefix(1)).uppercased() },
            kindSymbol: symbol
        )
    }

    /// The row as VoiceOver reads it.
    var spoken: String {
        let name = [title, rank].compactMap { $0 }.joined(separator: " ")
        return ([name] + details + moreDetails).joined(separator: ", ")
    }
}

@MainActor
enum ActivityRowContents {
    static func speed(isLive: Bool) -> String {
        isLive ? String(localized: "Live") : String(localized: "Correspondence")
    }

    static func board(width: Int, height: Int) -> String { "\(width)×\(height)" }

    /// Nil while the user hides ranks.
    static func rank(_ user: OGSUser?) -> String? {
        guard let user, !(userDefaults[.hidesRank] ?? false) else { return nil }
        return user.formattedRank
    }

    static func liveGame(_ facts: HomeGameFacts) -> ActivityRowContent {
        let game = facts.game
        let state: String
        if game.gamePhase == .stoneRemoval {
            state = String(localized: "Stone removal", comment: "pause reason")
        } else if game.pauseControl?.isPaused() ?? false {
            state = String(localized: "Paused", comment: "pause reason")
        } else {
            state = facts.turnText
        }
        let clock = game.gameData?.timeControl.system.shortDescription ?? ""
        return ActivityRowContent(
            title: facts.opponent?.username ?? "",
            rank: rank(facts.opponent),
            details: [state, board(width: game.width, height: game.height), clock].filter { !$0.isEmpty },
            user: facts.opponent
        )
    }

    static func challenge(_ challenge: OGSDirectChallenge, isLive: Bool) -> ActivityRowContent {
        let game = challenge.game
        let ranked = game.ranked
            ? String(localized: "Ranked", comment: "ChallengeCell rank status")
            : String(localized: "Unranked", comment: "ChallengeCell rank status")
        let komi = game.komi ?? game.rules.defaultKomi
        let more = [game.timeControl.shortDescription, String(localized: "\(komi, specifier: "%.1f") komi")]
        return ActivityRowContent(
            title: challenge.challenger?.username ?? "",
            rank: rank(challenge.challenger),
            details: [board(width: game.width, height: game.height), ranked, speed(isLive: isLive)],
            moreDetails: more.filter { !$0.isEmpty },
            user: challenge.challenger
        )
    }

    /// - Parameter waited: How long the search has run, from its `since`.
    static func quickMatch(_ entry: OGSAutomatchEntry, waited: TimeInterval) -> ActivityRowContent {
        let sizes = Set(entry.sizeSpeedOptions.map(\.size)).sorted(by: >).map { board(width: $0, height: $0) }
        var details = [speed(isLive: !entry.isCorrespondence)]
        if !sizes.isEmpty {
            details.append(sizes.formatted(.list(type: .and)))
        }
        details.append(ActivityElapsed.text(waited))
        return ActivityRowContent(title: String(localized: "Quick match"), details: details, symbol: "hourglass")
    }

    static func openChallenge(_ challenge: OGSSeekgraphChallenge, isLive: Bool,
                              waited: TimeInterval) -> ActivityRowContent {
        ActivityRowContent(
            title: String(
                localized: "Open challenge",
                comment: "Activity: a row for an open challenge the user posted, which anyone can accept"
            ),
            details: [speed(isLive: isLive), board(width: challenge.game.width, height: challenge.game.height),
                      ActivityElapsed.text(waited)],
            symbol: "hourglass"
        )
    }

    static func sentChallenge(_ challenge: OGSDirectChallenge, isLive: Bool) -> ActivityRowContent {
        let name = challenge.challenged?.username ?? ""
        return ActivityRowContent(
            title: String(
                localized: "Challenge to \(name)",
                comment: "Activity: a row for a challenge the user sent to this player"
            ),
            details: [speed(isLive: isLive), board(width: challenge.game.width, height: challenge.game.height)],
            symbol: "paperplane"
        )
    }

    static func rengo(_ challenge: OGSSeekgraphChallenge, isLive: Bool) -> ActivityRowContent {
        let gameName = challenge.game.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = gameName.isEmpty ? (challenge.challenger?.username ?? "") : gameName
        let players = challenge.game.rengoParticipants?.count ?? 0
        return ActivityRowContent(
            title: String(
                localized: "Rengo · \(name)",
                comment: "Activity: a row for a Rengo challenge the user hosts or joined, with its name"
            ),
            details: [
                speed(isLive: isLive), board(width: challenge.game.width, height: challenge.game.height),
                String(localized: "\(players) players", comment: "Activity: how many players a Rengo challenge has"),
            ],
            symbol: "person.2.fill"
        )
    }

    static func correspondence(count: Int) -> ActivityRowContent {
        ActivityRowContent(
            title: String(
                localized: "Your move in \(count) games",
                comment: "Activity: one row for the correspondence games on the user's move; opens the most urgent"
            ),
            symbol: "squareshape.split.3x3"
        )
    }

    /// What a waiting row's Withdraw names: the row without its elapsed
    /// time, which would change the label each second.
    static func withdrawLabel(_ content: ActivityRowContent, hasElapsedTime: Bool) -> String {
        let details = hasElapsedTime ? Array(content.details.dropLast()) : content.details
        let subject = ([content.title] + details).joined(separator: ", ")
        return String(
            localized: "Withdraw \(subject)",
            comment: "Activity: VoiceOver, the Withdraw button of the user's own search or challenge, with its row"
        )
    }
}

// MARK: - Pieces

/// A row's leading tile: the player's avatar, or a glyph circle for the
/// user's own searches and challenges. A resolved row draws its frozen
/// picture.
struct ActivityRowTile: View {
    @Environment(\.surroundAllowsRemoteActivity) private var allowsRemoteActivity
    let user: OGSUser?
    let symbol: String?
    var display: ActivityRowDisplay? = nil
    let size: CGFloat

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(MessagesStyle.accent)
                    .frame(width: size - 4, height: size - 4)
                    .background(MessagesStyle.paleAccent, in: Circle())
            } else if let user {
                MessageAvatar(user: user, size: size)
            } else {
                AsyncImage(url: allowsRemoteActivity ? display?.avatarURL : nil) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Text(verbatim: display?.initial ?? "")
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(MessagesStyle.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(MessagesStyle.paleAccent)
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: max(9, size * 0.23)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Line one, then line two (and a challenge's line three), which drop at
/// accessibility sizes so no action label shortens.
struct ActivityRowLines<Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let content: ActivityRowContent
    let density: ActivityRowDensity
    var showsMoreDetails = false
    /// Beside line one, such as a live game's clock.
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: content.title)
                        .font(density.titleFont)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    if let rank = content.rank {
                        Text(verbatim: rank)
                            .font(density.rankFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing()
            }
            if !dynamicTypeSize.isAccessibilitySize {
                if !content.details.isEmpty {
                    Text(verbatim: content.detail)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if showsMoreDetails, !content.moreDetails.isEmpty {
                    Text(verbatim: content.moreDetails.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

extension ActivityRowLines where Trailing == EmptyView {
    init(content: ActivityRowContent, density: ActivityRowDensity, showsMoreDetails: Bool = false) {
        self.init(content: content, density: density, showsMoreDetails: showsMoreDetails) { EmptyView() }
    }
}

/// A trailing text button, such as Withdraw or View: accent text in the
/// sheet, a small capsule in a game's popover.
private struct ActivityTrailingButtonStyle: ViewModifier {
    let density: ActivityRowDensity
    /// View is tinted; Withdraw is neutral in a game's popover.
    var isAccent = true

    func body(content: Content) -> some View {
        switch density {
        case .regular:
            content
                .buttonStyle(.borderless)
                .font(.callout.weight(.semibold))
                .tint(MessagesStyle.accent)
                .frame(minHeight: 44)
        case .dense:
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .font(.subheadline.weight(.semibold))
                .tint(isAccent ? MessagesStyle.accent : Color.primary)
                .frame(minHeight: 44)
        }
    }
}

/// The spinner that stands in for an action's button while it is sent, with
/// the button's identifier.
private struct ActivityPendingControl: View {
    let action: ActivityAction
    let identifier: String

    var body: some View {
        ProgressView()
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: action.pendingText))
            .accessibilityIdentifier(identifier)
    }
}

/// What replaces a row's actions once it acted: its result (with Open game
/// for a correspondence game that started), its failure with Retry, or, for
/// a row whose item went while it was sent, a spinner.
struct ActivityEntryLine: View {
    let itemID: String
    let entry: ActivityResults.Entry
    let actionState: ActivityRowActionState
    let retry: () -> Void
    let openGame: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            switch entry.state {
            case .pending:
                ProgressView()
                    .accessibilityHidden(true)
                Text(verbatim: entry.action.pendingText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(ID.activityRowResult(itemID))
                Spacer(minLength: 0)
            case .succeeded(let outcome):
                Text(verbatim: outcome.text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(ID.activityRowResult(itemID))
                if case .gameStarted(let gameID) = outcome {
                    Button {
                        openGame(gameID)
                    } label: {
                        Text("Open game", comment: "Activity: opens the correspondence game an accepted challenge started")
                    }
                    .modifier(ActivityTrailingButtonStyle(density: .regular))
                    .disabled(!actionState.isEnabled(.openGame))
                    .accessibilityIdentifier(ID.activityRow(itemID, .openGame))
                }
            case .failed:
                Text(verbatim: entry.action.failureText)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(ID.activityRowResult(itemID))
                Button("Retry", action: retry)
                    .modifier(ActivityTrailingButtonStyle(density: .regular))
                    .disabled(!actionState.isEnabled(.retry))
                    .accessibilityValue(Text(verbatim: actionState.accessibilityValue(.retry) ?? ""))
                    .accessibilityIdentifier(ID.activityRow(itemID, .retry))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension ActivityResults.Entry {
    /// A result or a failure, which replaces the row's actions.
    var replacesActions: Bool { !state.isPending }
}

// MARK: - Live game

/// One of the user's live games: the opponent, their move or the user's,
/// and the user's clock as Home draws it. The row opens the game.
struct ActivityLiveGameRow: View {
    @ObservedObject var game: Game
    let itemID: String
    let user: OGSUser?
    /// The theme Home wears, for the clock chip.
    let theme: SurroundTheme
    let isLowOnTime: Bool
    let density: ActivityRowDensity
    let open: () -> Void

    var body: some View {
        let facts = HomeGameFacts(game: game, user: user)
        let content = ActivityRowContents.liveGame(facts)
        Button(action: open) {
            HStack(spacing: 12) {
                ActivityRowTile(user: facts.opponent, symbol: nil, size: density.tile)
                ActivityRowLines(content: content, density: density) {
                    HomeClockChip(game: game, facts: facts, color: facts.bottomColor,
                                  marksLowTime: isLowOnTime) { EmptyView() }
                        .environment(\.surroundTheme, theme)
                        .fixedSize()
                }
            }
            .padding(.horizontal, density.horizontalPadding)
            .padding(.vertical, 6)
            .frame(minHeight: density.liveGameHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: spoken(content, facts: facts)))
        .accessibilityIdentifier(ID.activityRow(itemID))
    }

    /// The row, then the user's clock, as Home's row reads it.
    private func spoken(_ content: ActivityRowContent, facts: HomeGameFacts) -> String {
        var sentence = content.spoken
        if facts.userColor != nil {
            sentence += ". \(String(localized: "You")): \(facts.chipTime(facts.bottomColor))"
        }
        if isLowOnTime {
            sentence += ". " + String(
                localized: "Low on time",
                comment: "Homeview - VoiceOver: under 12 hours left on the user's running clock"
            )
        }
        return sentence
    }
}

// MARK: - Challenge received

/// A challenge someone sent the user. A usual one, outside a game's
/// popover, takes Reject and Accept on their own line; an unusual one, or
/// any in a game's popover, shows its warnings and View, which opens the
/// full card.
struct ActivityChallengeRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let itemID: String
    let challenge: OGSDirectChallenge
    let content: ActivityRowContent
    let density: ActivityRowDensity
    let actionState: ActivityRowActionState
    let entry: ActivityResults.Entry?
    let accept: () -> Void
    let reject: () -> Void
    let view: () -> Void
    let retry: () -> Void
    let openGame: (Int) -> Void

    private var name: String { challenge.challenger?.username ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                summary
                if !actionState.showsInlineAcceptAndReject, !dynamicTypeSize.isAccessibilitySize {
                    viewButton
                }
            }
            if !actionState.showsInlineAcceptAndReject {
                if challenge.isUnusual {
                    VStack(alignment: .leading, spacing: 2) {
                        ChallengeWarningLines(challenge: challenge)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.systemOrange))
                    .accessibilityElement(children: .combine)
                }
                if dynamicTypeSize.isAccessibilitySize {
                    viewButton
                }
            }
            if let entry, entry.replacesActions || !actionState.showsInlineAcceptAndReject {
                ActivityEntryLine(itemID: itemID, entry: entry, actionState: actionState,
                                  retry: retry, openGame: openGame)
            } else if actionState.showsInlineAcceptAndReject {
                inlineActions
            }
        }
        .padding(.horizontal, density.horizontalPadding)
        .padding(.vertical, 12)
        .frame(minHeight: density.rowHeight)
        .accessibilityElement(children: .contain)
    }

    private var summary: some View {
        HStack(spacing: 12) {
            ActivityRowTile(user: challenge.challenger, symbol: nil, size: density.tile)
            ActivityRowLines(content: content, density: density, showsMoreDetails: density == .regular)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: content.spoken))
        .accessibilityIdentifier(ID.activityRow(itemID))
    }

    private var viewButton: some View {
        Button(action: view) {
            Text("View", comment: "Activity: opens a challenge's full card, for a challenge that needs a closer look")
                .fixedSize()
        }
        .modifier(ActivityTrailingButtonStyle(density: density))
        .disabled(!actionState.isEnabled(.view))
        .accessibilityLabel(Text(
            "View the challenge from \(name)",
            comment: "Activity: VoiceOver, the View button of a challenge someone sent the user"
        ))
        .accessibilityIdentifier(ID.activityRow(itemID, .view))
    }

    /// Reject and Accept, side by side; at accessibility sizes, one above
    /// the other.
    private var inlineActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            if entry?.action == .reject {
                ActivityPendingControl(action: .reject, identifier: ID.activityRow(itemID, .reject))
                    .frame(maxWidth: .infinity)
            } else {
                Button(action: reject) {
                    Text("Reject").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.primary)
                .modifier(InlineActionShape(isEnabled: actionState.isEnabled(.reject)))
                .accessibilityLabel(Text(
                    "Reject \(name)’s challenge",
                    comment: "Activity: VoiceOver, rejecting a challenge someone sent the user"
                ))
                .accessibilityValue(Text(verbatim: actionState.accessibilityValue(.reject) ?? ""))
                .accessibilityIdentifier(ID.activityRow(itemID, .reject))
            }
            if entry?.action == .accept {
                ActivityPendingControl(action: .accept, identifier: ID.activityRow(itemID, .accept))
                    .frame(maxWidth: .infinity)
            } else {
                Button(action: accept) {
                    Text("Accept").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(MessagesStyle.accent)
                .modifier(InlineActionShape(isEnabled: actionState.isEnabled(.accept)))
                .accessibilityLabel(Text(
                    "Accept \(name)’s challenge",
                    comment: "Activity: VoiceOver, accepting a challenge someone sent the user"
                ))
                .accessibilityValue(Text(verbatim: actionState.accessibilityValue(.accept) ?? ""))
                .accessibilityIdentifier(ID.activityRow(itemID, .accept))
            }
        }
    }

    private struct InlineActionShape: ViewModifier {
        let isEnabled: Bool

        func body(content: Content) -> some View {
            content
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .font(.callout.weight(.semibold))
                .disabled(!isEnabled)
        }
    }
}

// MARK: - Waiting for opponents

/// One of the user's own searches or challenges. Withdraw sits trailing; a
/// row whose card holds its actions shows a chevron instead. A Quick Match
/// or Rengo row opens its card.
struct ActivityWaitingRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let itemID: String
    let content: ActivityRowContent
    let density: ActivityRowDensity
    let withdrawsInPlace: Bool
    /// The VoiceOver label of Withdraw.
    let withdrawLabel: String
    /// Pushes the row's card; nil for a row without one.
    let open: (() -> Void)?
    let actionState: ActivityRowActionState
    let entry: ActivityResults.Entry?
    let withdraw: () -> Void
    let retry: () -> Void
    /// A Rengo game the user started from the card, when it is correspondence.
    let openGame: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                summary
                trailing
            }
            if let entry, entry.replacesActions || !withdrawsInPlace {
                ActivityEntryLine(itemID: itemID, entry: entry, actionState: actionState,
                                  retry: retry, openGame: openGame)
            }
        }
        .padding(.leading, density.horizontalPadding)
        .padding(.trailing, density == .regular ? 4 : density.horizontalPadding)
        .padding(.vertical, entry == nil ? 0 : 8)
        .frame(minHeight: density.rowHeight)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var summary: some View {
        let lines = HStack(spacing: 12) {
            ActivityRowTile(user: content.user, symbol: content.symbol, size: density.tile)
            ActivityRowLines(content: content, density: density)
            if open != nil, !withdrawsInPlace || dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, density == .regular ? 8 : 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        if let open {
            Button(action: open) { lines }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: content.spoken))
                .accessibilityIdentifier(ID.activityRow(itemID))
        } else {
            lines
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: content.spoken))
                .accessibilityIdentifier(ID.activityRow(itemID))
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if withdrawsInPlace, entry?.replacesActions != true {
            if entry?.state.isPending == true {
                ActivityPendingControl(action: .withdraw, identifier: ID.activityRow(itemID, .withdraw))
            } else {
                Button(action: withdraw) {
                    // In the sheet the row leaves 4 pt, so the label sits 12 pt in.
                    Text("Withdraw")
                        .fixedSize()
                        .padding(.horizontal, density == .regular ? 8 : 0)
                        .contentShape(Rectangle())
                }
                .modifier(ActivityTrailingButtonStyle(density: density, isAccent: false))
                .disabled(!actionState.isEnabled(.withdraw))
                .accessibilityLabel(Text(verbatim: withdrawLabel))
                .accessibilityValue(Text(verbatim: actionState.accessibilityValue(.withdraw) ?? ""))
                .accessibilityIdentifier(ID.activityRow(itemID, .withdraw))
            }
        }
    }
}

// MARK: - Correspondence, conversations, All messages

/// A plain row that opens something: the correspondence row, All messages.
struct ActivityLinkRow: View {
    let content: ActivityRowContent
    let density: ActivityRowDensity
    let identifier: String
    var showsTile = true
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                if showsTile {
                    ActivityRowTile(user: nil, symbol: content.symbol, size: density.tile)
                }
                ActivityRowLines(content: content, density: density)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, density.horizontalPadding)
            .frame(minHeight: showsTile ? density.rowHeight : 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: content.spoken))
        .accessibilityIdentifier(identifier)
    }
}

/// A conversation: the peer, the last message on one line, and an unread
/// dot. It opens the conversation inside the list's stack.
struct ActivityConversationRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let itemID: String
    let peer: OGSUser
    let lastMessage: String
    let isUnread: Bool
    let density: ActivityRowDensity
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                MessageAvatar(user: peer, size: density.tile)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: peer.username)
                        .font(density.titleFont)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(verbatim: lastMessage)
                            .font(density == .regular ? .subheadline : .footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isUnread {
                    Circle()
                        .fill(MessagesStyle.accent)
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.leading, density.horizontalPadding)
            .padding(.trailing, density == .regular ? 14 : density.horizontalPadding)
            .frame(minHeight: density.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(peer.username): \(lastMessage)"))
        .accessibilityValue(isUnread ? Text("Unread conversation") : Text(verbatim: ""))
        .accessibilityIdentifier(ID.activityRow(itemID))
    }
}

// MARK: - A resolved row

/// A row whose item went after the user acted on it, drawn as it was then,
/// with its result, or its failure and Retry.
struct ActivityResolvedRowView: View {
    let row: ActivityResolvedRow
    let entry: ActivityResults.Entry?
    let density: ActivityRowDensity
    let actionState: ActivityRowActionState
    let retry: () -> Void
    let openGame: (Int) -> Void

    var body: some View {
        let content = ActivityRowContent(
            title: row.display.title,
            details: row.display.detail.isEmpty ? [] : [row.display.detail],
            symbol: row.display.kindSymbol
        )
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ActivityRowTile(user: nil, symbol: row.display.kindSymbol, display: row.display, size: density.tile)
                ActivityRowLines(content: content, density: density)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: content.spoken))
            .accessibilityIdentifier(ID.activityRow(row.id))
            if let entry {
                ActivityEntryLine(itemID: row.id, entry: entry, actionState: actionState,
                                  retry: retry, openGame: openGame)
            }
        }
        .padding(.horizontal, density.horizontalPadding)
        .padding(.vertical, 10)
        .frame(minHeight: density.rowHeight)
        .accessibilityElement(children: .contain)
    }
}
