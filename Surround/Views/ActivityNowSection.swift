//
//  ActivityNowSection.swift
//  Surround
//
//  The sidebar's Now section: what needs the user now, below the sidebar's
//  tab rows. "Now", the rows the window's bar state lists, two or one in a
//  short window, and All activity with what else waits, at the third row
//  density (`ActivityNowRowMetrics`). During an outage the window's status
//  takes its first row, with Retry once OGS can't be reached, on every
//  screen but a game, which says its status itself; signed out, or with
//  nothing waiting, the section is that row alone. It draws nothing when
//  nothing waits and nothing is to be said, and over a game it leaves that
//  game out. A row opens its game, or Activity anchored at it; View opens
//  Activity with a challenge's card pushed; Withdraw acts in place, and its
//  result keeps the row's place for 4 s, as in the bar. Its text stops
//  growing at XXL, so it keeps its height, and its rows, their
//  actions and All activity take keyboard focus. A row keeps at least the
//  first ten characters of its line one, the hourglass, the tile and the
//  rank giving way first and its action drawn as its symbol last, and the
//  status row's words read whole (`ActivityNowRowMetrics`). The iPad's
//  container and, on the Mac, MainView host it in UIKit's sidebar bottom
//  bar, which follows its size; it holds no state that matters. The Mac's
//  View menu also opens Activity as All activity does
//  (`ActivityMenuCommands`).
//

import SwiftUI
import UIKit

private typealias ID = SurroundUITestContract.AccessibilityID

struct ActivityNowSection: View {
    @ObservedObject var bar: ActivityBarState
    /// Where its openers are: on the Mac, the window's, which its Activity
    /// command reads; nil for the section's own.
    var openers: ActivityNowOpeners?
    @EnvironmentObject private var nav: NavigationService

    var body: some View {
        ActivityNowSectionBody(bar: bar, results: nav.activityResults, sharedOpeners: openers)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// The rows and All activity, from the bar state's section and the chrome's
/// results.
private struct ActivityNowSectionBody: View {
    @ObservedObject var bar: ActivityBarState
    @ObservedObject var results: ActivityResults
    let sharedOpeners: ActivityNowOpeners?
    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var nav: NavigationService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    /// Where each opener is in its window, and which one opened the list,
    /// where no host shares its own. Held by reference, so a new frame
    /// redraws nothing.
    @State private var ownOpeners = ActivityNowOpeners()
    /// The rows last drawn, so a withdrawn row's result keeps its place.
    @State private var lastDrawn = ActivityNowLastDrawn()

    private var openers: ActivityNowOpeners { sharedOpeners ?? ownOpeners }

    var body: some View {
        let section = bar.nowSection
        // The window's status takes no row here while the bar state lists
        // none (`ActivityBarState.nowSectionSaysStatus`).
        let room = NowStatusRow.activityRows(beside: section.statusRow, of: bar.nowSectionRows)
        let entries = lastDrawn.keep(ActivityNowEntry.entries(rows: section.rows, results: results.chromeResults,
                                                              room: room, previous: lastDrawn.ids))
        if !entries.isEmpty || section.statusRow != nil {
            let context = ActivityNowContext(
                metrics: ActivityNowRowMetrics(sizeCategory: UIContentSizeCategory(dynamicTypeSize)),
                isOffline: ActivityBarHosting.isOffline(bar), counted: section.counted, openers: openers,
                open: open
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: ActivityBarAccessibility.nowHeader)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .accessibilityAddTraits(.isHeader)
                if let statusRow = section.statusRow {
                    ActivityNowStatusRow(row: statusRow, context: context)
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    ActivityNowRow(entry: entry, isLead: index == 0, context: context)
                }
                if !entries.isEmpty || section.hasActivity {
                    allActivity(section)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(height: 1 / max(1, displayScale))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(ID.activityNow)
        }
    }

    private func allActivity(_ section: ActivityBarNowSection) -> some View {
        let breakdown = ActivityBarBreakdown(section.counted) { id in
            ogs.challengesReceived.first { $0.id == id }?.challenger?.username
        }
        let accessibility = ActivityBarAccessibility.allActivity(plusN: section.plusN, breakdown)
        let opener = ActivityNowOpeners.allActivity
        return Button { open(.top, from: opener) } label: {
            HStack(spacing: 6) {
                Text(verbatim: ActivityBarAccessibility.allActivityTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ActivityBarStyle.accent)
                    .lineLimit(1)
                if section.plusN > 0 {
                    Text(verbatim: ActivityBarMetrics.countText(section.plusN))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: ActivityBarMetrics.targetSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(ActivityBarPressStyle())
        .focusable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibility.label))
        .accessibilityValue(Text(verbatim: accessibility.value))
        .accessibilityHint(Text(verbatim: accessibility.hint))
        .accessibilityAddTraits(.isButton)
        .accessibilityShowsLargeContentViewer {
            Text(verbatim: ActivityBarAccessibility.allActivityTitle)
        }
        .accessibilityIdentifier(ID.activityNowAll)
        .modifier(ActivityNowOpenerFrame(openers: openers, opener: opener))
    }

    /// Opens Activity from an opener: a popover anchored at it in regular
    /// width, over a game the game's own.
    private func open(_ focus: ActivityRequest.Focus, from opener: String) {
        openers.opened = opener
        openers.openedSource = .nowSection
        nav.openActivity(source: .nowSection, focus: focus, anchor: openers.frames[opener] ?? .zero,
                         horizontalSizeClass: horizontalSizeClass)
    }
}

/// The openers' frames in their window, while each is drawn. Inside the
/// sidebar's bottom bar SwiftUI's global space is the window's, once laid
/// out.
final class ActivityNowOpeners {
    static let allActivity = "all"
    var frames: [String: CGRect] = [:]
    /// The opener the window's list last opened from, and what opened it
    /// there: the section, or the Mac's Activity command at All activity.
    var opened: String?
    var openedSource = ActivityRequest.Source.nowSection
}

/// What the section last drew, by its rows' ids in order.
final class ActivityNowLastDrawn {
    private(set) var ids: [String] = []

    func keep(_ entries: [ActivityNowEntry]) -> [ActivityNowEntry] {
        ids = entries.map(\.id)
        return entries
    }
}

/// Records an opener's frame while it is drawn, and moves the popover it
/// opened as it moves, a main-queue turn later: only while that popover is
/// open (`moveActivityAnchor`). Nothing it reads decides what the section
/// shows.
private struct ActivityNowOpenerFrame: ViewModifier {
    let openers: ActivityNowOpeners
    let opener: String
    @EnvironmentObject private var nav: NavigationService

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                openers.frames[opener] = frame
                guard openers.opened == opener else { return }
                let nav = nav, source = openers.openedSource
                DispatchQueue.main.async { nav.moveActivityAnchor(to: frame, from: source) }
            }
            // A gone opener anchors nothing: with no All activity, the Mac's
            // Activity command opens a sheet.
            .onDisappear { openers.frames[opener] = nil }
    }
}

/// What every row needs beside its own content.
private struct ActivityNowContext {
    let metrics: ActivityNowRowMetrics
    /// The window's connection is down or not yet up: Withdraw and a failed
    /// result's Retry dim and say "Reconnecting…"; View and Open game work.
    let isOffline: Bool
    /// What the "N waiting" row counts.
    let counted: [ActivityBarCountedItem]
    let openers: ActivityNowOpeners
    let open: (ActivityRequest.Focus, String) -> Void
}

// MARK: - The rows

/// One row: a lead's kind, or the chrome's result on its item.
private struct ActivityNowRow: View {
    let entry: ActivityNowEntry
    /// The first row, which is tinted.
    let isLead: Bool
    let context: ActivityNowContext

    @EnvironmentObject private var ogs: OGSService

    var body: some View {
        switch entry {
        case .result(let result):
            ActivityNowResultRow(result: result, isLead: isLead, context: context)
        case .lead(let lead):
            switch lead {
            case .liveGame(let gameID), .gameStarted(let gameID):
                if let game = ogs.liveGames.first(where: { $0.ogsID == gameID }) {
                    ActivityNowGameRow(game: game, itemID: entry.id, isStarted: lead != .liveGame(gameID: gameID),
                                       isLead: isLead, context: context)
                }
            case .challenge(let challenge):
                if let received = ogs.challengesReceived.first(where: { $0.id == challenge.id }) {
                    ActivityNowChallengeRow(challenge: received, model: challenge, isLead: isLead, context: context)
                }
            case .waiting(let waiting, let withdrawsInPlace):
                ActivityNowWaitingRow(waiting: waiting, withdrawsInPlace: withdrawsInPlace, isLead: isLead,
                                      context: context)
            case .nothingLeads(let count):
                ActivityNowNothingLeadsRow(count: count, isLead: isLead, context: context)
            }
        }
    }
}

/// A live game, on your move or theirs, or one that started elsewhere, with
/// Open game. Observing the game redraws its clock each second.
private struct ActivityNowGameRow: View {
    @ObservedObject var game: Game
    /// The game's item (`ActivityModel.Item.id`).
    let itemID: String
    let isStarted: Bool
    let isLead: Bool
    let context: ActivityNowContext

    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var nav: NavigationService
    /// The two settings Home reads, so the clock wears Home's colors.
    @AppStorage(SettingKey<String>.gameTheme.name, store: userDefaults)
    private var gameThemeID = SurroundTheme.standard.rawValue
    @AppStorage(SettingKey<Bool>.themeAppliesToWholeApp.name, store: userDefaults)
    private var themeAppliesToWholeApp = true

    var body: some View {
        ActivityNowRowFace(model: model, isLead: isLead, context: context)
            .environment(\.surroundTheme, SurroundTheme.current(storedID: gameThemeID,
                                                                appliesToWholeApp: themeAppliesToWholeApp))
    }

    private var model: ActivityNowRowModel {
        let facts = HomeGameFacts(game: game, user: ogs.user)
        let name = facts.opponent?.username ?? ""
        let nav = nav
        let game = game
        let open = { nav.goToActiveGame(game: game) }
        if isStarted {
            let details = [name, ActivityRowContents.board(width: game.width, height: game.height),
                           game.gameData?.timeControl.system.shortDescription ?? ""].filter { !$0.isEmpty }
            return ActivityNowRowModel(
                itemID: itemID, tile: .user(facts.opponent), lineOne: ActivityBarWords.gameStarted,
                lineTwo: details.joined(separator: " · "),
                accessibility: .gameStarted(opponent: name), largeContent: name, tap: open,
                action: ActivityNowActionModel(
                    action: .openGame, label: ActivityBarWords.action(.openGame),
                    accessibilityLabel: ActivityBarAccessibility.openGame(opponent: name), tap: open
                )
            )
        }
        let live = ogs.user.flatMap { ActivityModel.LiveGame(game: game, userID: $0.id) }
        let isYourMove = live?.isYourMove ?? false
        // Your clock on your move; theirs, in their stone's color, on theirs.
        let color = isYourMove ? facts.bottomColor : facts.topColor
        let clockState = facts.clock(color)
        let timeLeft = facts.chipTimeLeft(color)
        let isSuddenDeath = isYourMove && clockState.running && clockState.suddenDeath
        let rank = ActivityRowContents.rank(facts.opponent)
        let clock = ActivityBarClockFace(
            time: timeLeft.map(GameControlClock.init(timeLeft:)), color: color,
            mark: isSuddenDeath ? ActivityBarMarks.suddenDeath : nil,
            warns: (live.map(ActivityModel.isLowOnTime) ?? false) || isSuddenDeath,
            glows: clockState.running
        )
        return ActivityNowRowModel(
            itemID: itemID, tile: .user(facts.opponent), lineOne: name, rank: rank,
            lineTwo: ActivityRowContents.liveGame(facts).detail, clock: clock,
            accessibility: .liveGame(opponent: name, rank: rank, isYourMove: isYourMove, isSuddenDeath: isSuddenDeath,
                                     state: ActivityRowContents.pauseState(of: game), timeLeft: timeLeft,
                                     ticks: clockState.running),
            largeContent: name, tap: open
        )
    }
}

/// A live challenge sent to you: View opens its full card in Activity, and
/// the rest of the row opens Activity.
private struct ActivityNowChallengeRow: View {
    let challenge: OGSDirectChallenge
    let model: ActivityModel.Challenge
    let isLead: Bool
    let context: ActivityNowContext

    var body: some View {
        let content = ActivityRowContents.challenge(challenge, isLive: model.isLive)
        let itemID = ActivityModel.Item.challenge(model).id
        let name = content.title
        let context = context
        ActivityNowRowFace(
            model: ActivityNowRowModel(
                itemID: itemID, tile: .user(challenge.challenger), lineOne: name, rank: content.rank,
                lineTwo: ([ActivityBarWords.challenge] + content.details).joined(separator: " · "),
                accessibility: .challenge(challenger: name, rank: content.rank, details: content.details),
                largeContent: name, tap: { context.open(.top, itemID) },
                action: ActivityNowActionModel(
                    action: .view, label: ActivityBarWords.action(.view),
                    accessibilityLabel: ActivityBarAccessibility.view(challenger: name),
                    tap: { context.open(.item(itemID), ActivityNowRowFace.actionOpener(itemID)) }
                )
            ),
            isLead: isLead, context: context
        )
    }
}

/// One of your own searches or challenges: a still hourglass, the time
/// searched, which moves each second unless UI tests stop it
/// (`ActivityElapsed.stopsAt`), and Withdraw where the list's row withdraws
/// in place.
private struct ActivityNowWaitingRow: View {
    let waiting: ActivityModel.Waiting
    let withdrawsInPlace: Bool
    let isLead: Bool
    let context: ActivityNowContext

    var body: some View {
        if ActivityElapsed.stopsAt == nil {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                ActivityNowWaitingFace(waiting: waiting, withdrawsInPlace: withdrawsInPlace, isLead: isLead,
                                       context: context, now: timeline.date.timeIntervalSince1970, ticks: true)
            }
        } else {
            ActivityNowWaitingFace(waiting: waiting, withdrawsInPlace: withdrawsInPlace, isLead: isLead,
                                   context: context, now: Date().timeIntervalSince1970, ticks: false)
        }
    }
}

private struct ActivityNowWaitingFace: View {
    let waiting: ActivityModel.Waiting
    let withdrawsInPlace: Bool
    let isLead: Bool
    let context: ActivityNowContext
    let now: TimeInterval
    let ticks: Bool

    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var nav: NavigationService

    var body: some View {
        let source = ActivityListSource(ogs: ogs, nav: nav, placement: .sheet)
        if let target = source.waitingTarget(ActivityWaitingRef.parse(waiting.id), in: source.openChallenges) {
            ActivityNowRowFace(model: model(target, content: source.content(of: target, waiting: waiting, now: now)),
                               isLead: isLead, context: context)
        }
    }

    private func model(_ target: ActivityListSource.WaitingTarget, content: ActivityRowContent) -> ActivityNowRowModel {
        let itemID = ActivityModel.Item.waiting(waiting).id
        let hasElapsedTime = waiting.kind == .quickMatch || waiting.kind == .openChallenge
        let steady = hasElapsedTime ? Array(content.details.dropLast()) : content.details
        let lineOne: String
        let lineTwo: [String]
        let subject: ActivityBarAccessibility.WaitingSubject
        var isSearch = false
        switch target {
        case .search:
            lineOne = ActivityBarWords.searching
            lineTwo = [content.title] + content.details
            subject = .search
            isSearch = true
        case .openChallenge:
            lineOne = content.title
            lineTwo = content.details
            subject = .openChallenge
        case .sentChallenge(let challenge):
            lineOne = content.title
            lineTwo = content.details
            subject = .sentChallenge(to: challenge.challenged?.username ?? "")
        case .rengo(let challenge):
            lineOne = content.title
            lineTwo = content.details
            let gameName = challenge.game.name.trimmingCharacters(in: .whitespacesAndNewlines)
            subject = .rengo(gameName.isEmpty ? (challenge.challenger?.username ?? "") : gameName)
        }
        let spokenDetails = isSearch ? [content.title] + steady : steady
        let waited = hasElapsedTime ? ActivityElapsed.waited(since: waiting.since, now: now) : nil
        let results = nav.activityResults
        let display = content.display
        let context = context
        return ActivityNowRowModel(
            itemID: itemID,
            tile: .glyph(content.symbol ?? "hourglass", tint: MessagesStyle.accent, background: MessagesStyle.paleAccent),
            lineOne: lineOne, lineTwo: lineTwo.joined(separator: " · "),
            accessibility: .waiting(subject, details: spokenDetails, waited: waited, ticks: ticks),
            largeContent: lineOne, tap: { context.open(.top, itemID) },
            action: withdrawsInPlace ? ActivityNowActionModel(
                action: .withdraw, label: ActivityBarWords.action(.withdraw),
                accessibilityLabel: ActivityBarAccessibility.withdraw(title: content.title, details: steady),
                isEnabled: !context.isOffline,
                tap: {
                    switch target {
                    case .search(let entry):
                        results.withdraw(automatch: entry, session: results.chromeSession, itemID: itemID,
                                         display: display, section: .waiting, after: nil)
                    default:
                        guard let challenge = target.challenge else { return }
                        results.withdraw(challenge: challenge, session: results.chromeSession, itemID: itemID,
                                         display: display, section: .waiting, after: nil)
                    }
                }
            ) : nil
        )
    }
}

/// Nothing live leads: the inbox glyph, "3 waiting" and what waits; a tap
/// opens Activity.
private struct ActivityNowNothingLeadsRow: View {
    let count: Int
    let isLead: Bool
    let context: ActivityNowContext

    @EnvironmentObject private var ogs: OGSService

    var body: some View {
        let breakdown = ActivityBarBreakdown(context.counted) { id in
            ogs.challengesReceived.first { $0.id == id }?.challenger?.username
        }
        let lineOne = ActivityBarWords.waiting(count)
        let context = context
        ActivityNowRowFace(
            model: ActivityNowRowModel(
                itemID: ActivityNowEntry.waitingID,
                tile: .glyph("tray", tint: .primary, background: Color(uiColor: .tertiarySystemFill)),
                lineOne: lineOne, lineTwo: breakdown.lineTwo,
                accessibility: .nothingLeads(count: count, breakdown), largeContent: lineOne,
                tap: { context.open(.top, ActivityNowEntry.waitingID) }
            ),
            isLead: isLead, context: context
        )
    }
}

/// The window's status in the section's first row: "Reconnecting…",
/// "Connecting…" before the window's first connection, "Can’t reach OGS"
/// with Retry, or "Connected" for 2 s after an outage someone saw. Status,
/// not a button; Retry has the window's source retry.
private struct ActivityNowStatusRow: View {
    let row: NowStatusRow
    let context: ActivityNowContext
    @Environment(\.connectionStatus) private var connection

    var body: some View {
        let words = row.words
        let text = ActivityBarWords.status(words)
        let connection = connection
        ActivityNowRowFace(
            model: ActivityNowRowModel(
                itemID: Self.opener,
                tile: .glyph(ActivityBarStatusGlyph.name(words), tint: ActivityBarStatusGlyph.tint(words),
                             background: Color(uiColor: .tertiarySystemFill)),
                lineOne: text, lineTwo: "",
                accessibility: .status(words), largeContent: text, tap: nil,
                action: row.offersRetry ? ActivityNowActionModel(
                    action: .retry, label: ActivityBarWords.action(.retry),
                    accessibilityLabel: ActivityBarAccessibility.retry,
                    identifier: ID.rootConnectionStatusRetry,
                    tap: { connection?.retry() }
                ) : nil,
                identifier: ID.rootConnectionStatus, isStatus: true
            ),
            isLead: false, context: context
        )
    }

    /// Its opener name among the rows', which no item has.
    static let opener = "status"
}

/// An action taken from the bar or the section: "Withdrawing…" with a grey
/// hourglass and no action, then "Withdrawn", or "Couldn’t withdraw" with
/// Retry, for 4 s after it settles.
private struct ActivityNowResultRow: View {
    let result: ActivityBarResult
    let isLead: Bool
    let context: ActivityNowContext
    @EnvironmentObject private var nav: NavigationService

    var body: some View {
        let accessibility = ActivityBarAccessibility.result(result)
        let display = result.display
        let results = nav.activityResults
        let itemID = result.itemID
        ActivityNowRowFace(
            model: ActivityNowRowModel(
                itemID: itemID,
                tile: result.state.isPending
                    ? .glyph(display.kindSymbol ?? "hourglass", tint: .secondary,
                             background: Color(uiColor: .tertiarySystemFill))
                    : .display(display),
                lineOne: accessibility.label,
                lineTwo: [display.title, display.detail].filter { !$0.isEmpty }.joined(separator: " · "),
                accessibility: accessibility, largeContent: accessibility.label, tap: nil,
                action: result.state == .failed ? ActivityNowActionModel(
                    action: .retry, label: ActivityBarWords.action(.retry),
                    accessibilityLabel: ActivityBarWords.action(.retry), isEnabled: !context.isOffline,
                    tap: { results.retry(itemID: itemID, session: results.chromeSession) }
                ) : nil
            ),
            isLead: isLead, context: context
        )
    }
}

// MARK: - One row's face

private struct ActivityNowRowModel {
    enum Tile {
        case user(OGSUser?)
        case glyph(String, tint: Color, background: Color)
        /// A resolved item's frozen picture.
        case display(ActivityRowDisplay)
    }

    /// The row's item (`ActivityModel.Item.id`), which names its identifiers.
    var itemID: String
    var tile: Tile
    var lineOne: String
    var rank: String?
    var lineTwo: String
    var clock: ActivityBarClockFace?
    var accessibility: ActivityBarAccessibility
    /// What the Large Content Viewer shows for the row.
    var largeContent: String
    /// Nil for a result and the status row, which aren't buttons.
    var tap: (() -> Void)?
    var action: ActivityNowActionModel?
    /// The row's identifier, where it isn't its item's: the status row's.
    var identifier: String?
    /// The status row, whose words read whole.
    var isStatus = false
}

private struct ActivityNowActionModel {
    var action: ActivityBarAction
    var label: String
    var accessibilityLabel: String
    var isEnabled = true
    /// The action's identifier, where it isn't its row's: the status row's
    /// Retry.
    var identifier: String?
    var tap: () -> Void
}

/// A 60 pt row: the tile, the name with its rank and line two, then one
/// trailing part, a live game's clock or the row's action. Line one keeps
/// its floor (`ActivityNowRowMetrics.floor(of:)`): where it wouldn't, the
/// hourglass drops, then the tile, then the rank, and last the action is
/// drawn as its symbol; the clock and the action never drop. The status
/// row's words read whole, on as many lines as `statusLayout` gives them.
/// The lead's row is tinted.
private struct ActivityNowRowFace: View {
    let model: ActivityNowRowModel
    let isLead: Bool
    let context: ActivityNowContext

    private var metrics: ActivityNowRowMetrics { context.metrics }

    /// The opener name of a row's action, apart from the row's own.
    static func actionOpener(_ itemID: String) -> String { "\(itemID).action" }

    var body: some View {
        let text = self.text
        let status = model.isStatus ? metrics.statusLayout(parts, text: text) : nil
        let face = Face(drawsSymbol: status?.actionAsSymbol ?? metrics.actionDrawsSymbol(parts, text: text),
                        lines: status?.lines ?? 1, text: text)
        ViewThatFits(in: .horizontal) {
            row(face, showsHourglass: true, showsTile: true, showsRank: true)
            row(face, showsHourglass: false, showsTile: true, showsRank: true)
            row(face, showsHourglass: false, showsTile: false, showsRank: true)
            if model.rank?.isEmpty == false {
                row(face, showsHourglass: false, showsTile: false, showsRank: false)
            }
        }
        .frame(height: status?.height ?? ActivityNowRowMetrics.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isLead {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MessagesStyle.accent.opacity(0.08))
                    .accessibilityHidden(true)
            }
        }
    }

    /// What every variant of the row draws alike: the action as words or
    /// its symbol, the lines line one may take, and the measured text.
    private struct Face {
        var drawsSymbol: Bool
        var lines: Int
        var text: ActivityBarPartText
    }

    /// The row's measured text: line one at its floor, the status words
    /// whole, and the action's words.
    private var text: ActivityBarPartText {
        var text = ActivityBarPartText(
            lineOneMinimum: model.isStatus ? model.lineOne : ActivityNowRowMetrics.floor(of: model.lineOne),
            rank: model.rank, clock: model.clock?.time, suddenDeathMark: model.clock?.mark
        )
        if let label = model.action?.label { text.actionLabel = { _ in label } }
        return text
    }

    /// The row's parts as it draws them, from the leading edge.
    private var parts: [ActivityBarPart] {
        var parts: [ActivityBarPart] = [.tile, .lineOne]
        if model.clock != nil { parts += [.hourglass, .clock] }
        if let action = model.action { parts.append(.action(action.action)) }
        return parts
    }

    private func row(_ face: Face, showsHourglass: Bool, showsTile: Bool, showsRank: Bool) -> some View {
        HStack(spacing: 0) {
            lead(face, showsHourglass: showsHourglass, showsTile: showsTile, showsRank: showsRank)
            if let action = model.action {
                actionButton(action, face: face)
                    .padding(.leading, metrics.spacing.between)
            }
        }
        .padding(.leading, metrics.spacing.leading)
        .padding(.trailing, metrics.spacing.trailing)
    }

    @ViewBuilder
    private func lead(_ face: Face, showsHourglass: Bool, showsTile: Bool, showsRank: Bool) -> some View {
        let accessibility = model.accessibility
        let floor = lineOneFloor(face, showsRank: showsRank)
        let row = HStack(spacing: metrics.spacing.between) {
            if showsTile {
                tile
            }
            // Ideal at its floor, so the variant that fits is the one the
            // fit test proves; the lines then take the rest.
            lines(showsRank: showsRank, lineOneLines: face.lines)
                .frame(minWidth: floor, idealWidth: floor, maxWidth: .infinity, alignment: .leading)
            if let clock = model.clock {
                ActivityBarClockChip(clock: clock, sizes: metrics.clockChip, showsHourglass: showsHourglass)
                    .fixedSize()
            }
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        Group {
            if let tap = model.tap {
                Button {
                    tap()
                } label: {
                    row
                }
                .buttonStyle(ActivityBarPressStyle())
                .focusable()
                .accessibilityHint(Text(verbatim: accessibility.hint))
                .accessibilityShowsLargeContentViewer {
                    Text(verbatim: model.largeContent)
                }
            } else {
                row
                    .accessibilityElement(children: .ignore)
            }
        }
        .accessibilityLabel(Text(verbatim: accessibility.label))
        .accessibilityValue(Text(verbatim: accessibility.value))
        .accessibilityAddTraits(accessibility.updatesFrequently ? .updatesFrequently : [])
        .accessibilityIdentifier(model.identifier ?? ID.activityNowRow(model.itemID))
        .modifier(ActivityNowOpenerFrame(openers: context.openers, opener: model.itemID))
    }

    /// Line one's column at its floor, with the rank where the variant
    /// keeps it.
    private func lineOneFloor(_ face: Face, showsRank: Bool) -> CGFloat {
        var measured = face.text
        if !showsRank { measured.rank = nil }
        return metrics.width(of: .lineOne, measured, lineOneLines: face.lines)
    }

    private var tile: some View {
        Group {
            switch model.tile {
            case .user(let user):
                ActivityRowTile(user: user, symbol: user == nil ? "person.fill" : nil,
                                size: ActivityNowRowMetrics.tileSize)
            case .glyph(let name, let tint, let background):
                Image(systemName: name)
                    .font(.system(size: ActivityNowRowMetrics.tileSize * 0.45, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: ActivityNowRowMetrics.tileSize, height: ActivityNowRowMetrics.tileSize)
                    .background(background, in: Circle())
            case .display(let display):
                ActivityRowTile(user: nil, symbol: display.kindSymbol, display: display,
                                size: ActivityNowRowMetrics.tileSize)
            }
        }
        .frame(width: ActivityNowRowMetrics.tileSize, height: ActivityNowRowMetrics.tileSize)
        .accessibilityHidden(true)
    }

    private func lines(showsRank: Bool, lineOneLines: Int) -> some View {
        VStack(alignment: .leading, spacing: ActivityBarMetrics.lineGap) {
            HStack(alignment: .firstTextBaseline, spacing: ActivityBarMetrics.rankGap) {
                Text(verbatim: model.lineOne)
                    .font(Font(metrics.lineOneFont as CTFont))
                    .foregroundStyle(.primary)
                    .lineLimit(lineOneLines)
                    .truncationMode(.tail)
                if showsRank, let rank = model.rank, !rank.isEmpty {
                    Text(verbatim: rank)
                        .font(Font(metrics.detailFont as CTFont))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            if !model.lineTwo.isEmpty {
                Text(verbatim: model.lineTwo)
                    .font(Font(metrics.detailFont as CTFont).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .accessibilityHidden(true)
    }

    /// View, Open game and Retry as indigo-tinted pills; Withdraw as accent
    /// text; each in a 44 pt target, in the bar's own tint. Where the words
    /// would leave line one short of its floor, the action's symbol in a pill
    /// instead, with the words as its tooltip on the Mac and its Large
    /// Content Viewer; VoiceOver reads the same label either way.
    private func actionButton(_ action: ActivityNowActionModel, face: Face) -> some View {
        let drawsSymbol = face.drawsSymbol
        let isPill = drawsSymbol || action.action != .withdraw
        let width = drawsSymbol ? metrics.symbolActionWidth(action.action)
            : metrics.width(of: .action(action.action), face.text)
        let opener = Self.actionOpener(model.itemID)
        return Button(action: action.tap) {
            Group {
                if drawsSymbol {
                    Image(systemName: ActivityNowRowMetrics.symbolName(action.action))
                        .font(.system(size: metrics.actionFont.pointSize, weight: .semibold))
                } else {
                    Text(verbatim: action.label)
                        .font(Font(metrics.actionFont as CTFont))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(ActivityBarStyle.accent)
            .frame(width: width, height: isPill ? ActivityNowRowMetrics.pillHeight : ActivityBarMetrics.targetSize)
            .background {
                if isPill {
                    Capsule().fill(MessagesStyle.accent.opacity(0.12))
                }
            }
            .frame(height: ActivityBarMetrics.targetSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(ActivityBarPressStyle())
        .frame(width: width)
        .disabled(!action.isEnabled)
        .focusable()
        .modifier(ActivityNowSymbolTooltip(words: drawsSymbol ? action.label : nil))
        .accessibilityLabel(Text(verbatim: action.accessibilityLabel))
        .accessibilityValue(Text(verbatim: action.isEnabled ? "" : ActivityBarWords.reconnecting))
        .accessibilityShowsLargeContentViewer {
            Text(verbatim: action.label)
        }
        .accessibilityIdentifier(action.identifier ?? ID.activityNowRowAction(model.itemID))
        .modifier(ActivityNowOpenerFrame(openers: context.openers, opener: opener))
    }
}

/// The words of an action drawn as its symbol, as its tooltip: on the Mac,
/// where a pointer rests on it. Nothing for an action drawn in words.
private struct ActivityNowSymbolTooltip: ViewModifier {
    let words: String?

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        if let words {
            content.help(Text(verbatim: words))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension ActivityNowRowMetrics {
    /// The 28 pt clock chip.
    var clockChip: ActivityClockChipSizes {
        ActivityClockChipSizes(height: Self.clockHeight, padding: clockPadding, innerGap: clockInnerGap,
                               cornerRadius: 8, font: clockFont,
                               symbolPointSize: (clockFont.pointSize * 0.75).rounded())
    }
}

// MARK: - The Mac

#if targetEnvironment(macCatalyst)
/// The Mac's Now section, in UIKit's sidebar bottom bar on the TabView's own
/// UITabBarController, as the iPad's container hosts its own: SwiftUI's
/// bottom bar never changes its height after its first layout, so rows that
/// come or go would never show. A hosting controller sized to its content,
/// down to nothing, made once, whose root view is replaced in place with the
/// window's environment; the section observes the window's bar state
/// itself. It is set once the TabView is in a window, as the window first
/// appears, and checked again a main-queue turn after each sign-in change,
/// since signing in or out changes the TabView's tabs and may rebuild its
/// controller; never from layout or a timer. MainView places it behind its
/// TabView, and it connects the window's Activity command to the section.
struct ActivityMacNowSectionHost: UIViewControllerRepresentable {
    let nav: NavigationService
    let isLoggedIn: Bool
    let menuTarget: ActivityMenuTarget
    /// The section with the window's environment, given the openers it
    /// shares with the Activity command.
    let content: (ActivityNowOpeners) -> AnyView

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AnchorController {
        let anchor = AnchorController()
        let coordinator = context.coordinator
        anchor.onAppear = { [weak coordinator] in coordinator?.windowDidAppear() }
        anchor.onBecameKey = { [weak coordinator] in coordinator?.windowBecameKey() }
        coordinator.anchor = anchor
        coordinator.update(self)
        return anchor
    }

    func updateUIViewController(_ anchor: AnchorController, context: Context) {
        context.coordinator.update(self)
    }

    @MainActor
    final class Coordinator {
        private let host = UIHostingController(rootView: AnyView(EmptyView()))
        private let openers = ActivityNowOpeners()
        weak var anchor: AnchorController?
        private var isLoggedIn: Bool?
        private var isInstalled = false

        init() {
            host.sizingOptions = .intrinsicContentSize
            host.view.backgroundColor = .clear
        }

        func update(_ parent: ActivityMacNowSectionHost) {
            host.rootView = parent.content(openers)
            parent.menuTarget.connect(nav: parent.nav, openers: openers) { [weak self] in self?.anchor?.view.window }
            let signInChanged = isLoggedIn.map { $0 != parent.isLoggedIn } ?? false
            isLoggedIn = parent.isLoggedIn
            if signInChanged {
                // The TabView's new tabs, and any controller SwiftUI builds
                // for them, are in place a turn later.
                DispatchQueue.main.async { [weak self] in self?.install(reason: "signIn") }
            }
        }

        /// The window has first appeared: the TabView is in it. Should its
        /// controller join the window after this one, the turn after
        /// finds it, or the window's first turn as the key window does.
        func windowDidAppear() {
            install(reason: "appeared")
            guard !isInstalled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isInstalled else { return }
                self.install(reason: "appeared.turn")
            }
        }

        func windowBecameKey() {
            guard !isInstalled else { return }
            install(reason: "key")
        }

        /// Sets the section as the sidebar's bottom bar of the window's
        /// TabView, unless it already is.
        private func install(reason: String) {
            guard let window = anchor?.view.window,
                  let tabs = Self.tabBarController(under: window.rootViewController, in: window) else {
                log("notFound", reason: reason)
                return
            }
            isInstalled = true
            guard tabs.sidebar.bottomBarView !== host.view else {
                log("kept", reason: reason)
                return
            }
            let replaced = tabs.sidebar.bottomBarView.map { "\(type(of: $0))" } ?? "none"
            tabs.sidebar.bottomBarView = host.view
            log("installed", reason: reason, replaced: replaced)
        }

        private static func tabBarController(under controller: UIViewController?,
                                             in window: UIWindow) -> UITabBarController? {
            guard let controller else { return nil }
            if let tabs = controller as? UITabBarController, tabs.viewIfLoaded?.window === window { return tabs }
            for child in controller.children {
                if let found = tabBarController(under: child, in: window) { return found }
            }
            return nil
        }

        private func log(_ action: String, reason: String, replaced: String? = nil) {
            #if DEBUG && MAIN_APP
            NoticesHostProbeLog.event("mac.now", [("action", action), ("reason", reason)]
                                      + (replaced.map { [("replaced", $0)] } ?? []))
            #endif
        }
    }

    /// A controller with no content, whose appearance says that the window
    /// has first appeared; then, for a window not yet key, its first turn as
    /// the key window.
    final class AnchorController: UIViewController {
        var onAppear: (() -> Void)?
        var onBecameKey: (() -> Void)?
        private var hasAppeared = false
        private var keyObserver: NSObjectProtocol?

        override func loadView() {
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.accessibilityElementsHidden = true
            self.view = view
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !hasAppeared else { return }
            hasAppeared = true
            onAppear?()
            guard let window = view.window, !window.isKeyWindow else { return }
            keyObserver = NotificationCenter.default.addObserver(
                forName: UIWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowBecameKey() }
            }
        }

        private func windowBecameKey() {
            if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
            keyObserver = nil
            onBecameKey?()
        }

        deinit {
            if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        }
    }
}

/// The Mac's Activity command for one window, which MainView publishes to
/// the menu bar as its scene's focused value: Activity as the Now section's
/// All activity opens it, anchored there while the section shows it, and
/// otherwise as `openActivityFromMenuCommand(allActivity:top:)` says, from
/// the window's top edge where a popover needs an anchor.
@MainActor
final class ActivityMenuTarget {
    private weak var nav: NavigationService?
    private weak var openers: ActivityNowOpeners?
    private var window: () -> UIWindow? = { nil }

    func connect(nav: NavigationService, openers: ActivityNowOpeners, window: @escaping () -> UIWindow?) {
        self.nav = nav
        self.openers = openers
        self.window = window
    }

    func open() {
        guard let nav else { return }
        let allActivity = openers?.frames[ActivityNowOpeners.allActivity]
        if allActivity != nil {
            openers?.opened = ActivityNowOpeners.allActivity
            openers?.openedSource = .menuCommand
        }
        #if DEBUG && MAIN_APP
        NoticesHostProbeLog.event("mac.activityCommand", [
            ("allActivity", NoticesHostProbeLog.rect(allActivity)),
        ])
        #endif
        nav.openActivityFromMenuCommand(allActivity: allActivity, top: top)
    }

    /// The middle of the window's top edge, below its toolbar.
    private var top: CGRect {
        guard let window = window() else { return .zero }
        return CGRect(x: window.bounds.midX, y: window.safeAreaInsets.top, width: 0, height: 0)
    }
}

private struct ActivityMenuTargetKey: FocusedValueKey {
    typealias Value = ActivityMenuTarget
}

extension FocusedValues {
    /// The Activity command of the window in front, on the Mac.
    var activityMenuTarget: ActivityMenuTarget? {
        get { self[ActivityMenuTargetKey.self] }
        set { self[ActivityMenuTargetKey.self] = newValue }
    }
}

/// View > Activity, ⇧⌘A, on the Mac: Activity in the window in front
/// (`ActivityMenuTarget`), the keyboard's way to it, since Tab never reaches
/// the sidebar's Now section. Off while no main window is in front, while
/// the moderator's cover is up, and while the window in front is signed
/// out, which has no Activity.
struct ActivityMenuCommands: Commands {
    @FocusedValue(\.activityMenuTarget) private var target

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button {
                target?.open()
            } label: {
                Text(verbatim: ActivityBarAccessibility.listTitle)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(target == nil)
        }
    }
}
#endif
