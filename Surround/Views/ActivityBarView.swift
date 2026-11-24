//
//  ActivityBarView.swift
//  Surround
//
//  The Activity bar as every host draws it: SwiftUI's accessory, UIKit's
//  accessory and the custom bar. One view for each kind of the bar's content
//  (`ActivityBarContent`) in each of its forms: two lines, one line in
//  compact height, inline beside a minimized tab bar, and the Duo's Closed
//  line with the opponent's name. Inside the system's accessories it draws
//  no background, as they draw their own glass; the custom bar draws its
//  capsule. The form comes from the host's traits, never from the bar's
//  width: in a one-line form the width only chooses which parts stay, in the
//  model's drop order, and nothing the bar measures decides whether it
//  exists. Where the host says all of the window's status, the status words
//  and a lead's status badge read whole, the same drop order making room
//  for them. Its text stops growing at XXL, and its buttons show the Large
//  Content Viewer at accessibility sizes, which no host adds. A tap opens
//  the game, or Activity anchored at the bar's frame in its window, which a
//  UIKit view reports; Withdraw and its Retry go through the window's results
//  store in the chrome's session. The bar holds no state that matters: a host
//  may tear it down and build it again at any time. ActivityBarMetrics.swift
//  measures every part it draws.
//

import SwiftUI
import UIKit

private typealias ID = SurroundUITestContract.AccessibilityID

struct ActivityBarView: View {
    /// What the bar shows: `ActivityBarContent(bar.activity, words:
    /// bar.connection.words, placement:)`, the value the host's decision
    /// that the bar exists comes from.
    let content: ActivityBarContent
    /// The host and its traits, which give the form (`ActivityBarForm`).
    let traits: ActivityBarTraits
    /// The window's connection is down or not yet up: Withdraw and a failed
    /// result's Retry dim and say "Reconnecting…"; View and Open game work.
    var isOffline = false

    @EnvironmentObject private var nav: NavigationService
    /// Where the bar is in its window, which a tap anchors a popover at.
    /// Kept by reference, so a new frame redraws nothing.
    @State private var windowFrame = ActivityBarWindowFrame()

    var body: some View {
        let form = ActivityBarForm(traits)
        let isCustomBar = traits.bar == .customBar
        ActivityBarFace(content: content, form: form, bar: traits.bar, container: traits.container,
                        saysAllStatus: traits.saysAllStatus, isOffline: isOffline, windowFrame: windowFrame)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .frame(maxWidth: .infinity, maxHeight: isCustomBar ? nil : .infinity)
            .frame(height: isCustomBar ? ActivityBarMetrics.height(of: .customBar, form: form) : nil)
            .background {
                if isCustomBar {
                    ActivityBarCapsule()
                }
            }
            .background {
                ActivityBarWindowFrameReader(frame: windowFrame) { frame in
                    nav.moveActivityAnchor(to: frame, from: .activityBar)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: ActivityBarAccessibility.barLabel))
            .accessibilityIdentifier(ID.activityBar)
    }
}

// MARK: - The kinds

/// The bar's content in its form, at the capped text size.
private struct ActivityBarFace: View {
    let content: ActivityBarContent
    let form: ActivityBarForm
    let bar: ActivityHostPolicy.Bar
    let container: ActivityHostPolicy.Container
    /// The host says all of the window's status (`ActivityBarTraits.saysAllStatus`).
    let saysAllStatus: Bool
    let isOffline: Bool
    let windowFrame: ActivityBarWindowFrame

    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var nav: NavigationService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let context = ActivityBarContext(
            metrics: ActivityBarMetrics(form: form, sizeCategory: UIContentSizeCategory(dynamicTypeSize)),
            drawing: ActivityBarDrawing(content, form: form, saysAllStatus: saysAllStatus), bar: bar,
            container: container, saysAllStatus: saysAllStatus, isOffline: isOffline,
            more: moreModel, openActivity: openActivity
        )
        switch content {
        case .result(let result):
            ActivityBarResultRow(result: result, context: context)
        case .unreachable:
            ActivityBarUnreachableRow(context: context)
        case .status(let words):
            ActivityBarStatusRow(words: words, context: context)
        case .lead(let lead, _, let status):
            switch lead {
            case .liveGame(let gameID), .gameStarted(let gameID):
                if let game = ogs.liveGames.first(where: { $0.ogsID == gameID }) {
                    ActivityBarGameRow(game: game, isStarted: lead != .liveGame(gameID: gameID), status: status,
                                       context: context)
                }
            case .challenge(let challenge):
                if let received = ogs.challengesReceived.first(where: { $0.id == challenge.id }) {
                    ActivityBarChallengeRow(challenge: received, model: challenge, status: status, context: context)
                }
            case .waiting(let waiting, let withdrawsInPlace):
                ActivityBarWaitingRow(waiting: waiting, withdrawsInPlace: withdrawsInPlace, status: status,
                                      context: context)
            case .nothingLeads(let count):
                ActivityBarNothingLeadsRow(count: count, counted: counted, status: status, context: context)
            }
        }
    }

    private var counted: [ActivityBarCountedItem] {
        switch content {
        case .unreachable(let counted), .lead(_, let counted, _): counted
        case .result, .status: []
        }
    }

    /// +N, where the content shows it.
    private var moreModel: ActivityBarMoreModel? {
        let count = content.plusN
        guard count > 0 else { return nil }
        let breakdown = ActivityBarBreakdown(counted) { id in
            ogs.challengesReceived.first { $0.id == id }?.challenger?.username
        }
        return ActivityBarMoreModel(count: count, accessibility: .plusN(count, breakdown))
    }

    private func openActivity(_ focus: ActivityRequest.Focus) {
        nav.openActivity(source: .activityBar, focus: focus, anchor: windowFrame.value,
                         horizontalSizeClass: horizontalSizeClass)
    }
}

/// What every kind's row needs beside its own content.
private struct ActivityBarContext {
    let metrics: ActivityBarMetrics
    let drawing: ActivityBarDrawing
    /// The host, whose height decides whether line two shows at the cap.
    let bar: ActivityHostPolicy.Bar
    let container: ActivityHostPolicy.Container
    /// The host says all status, so the status words and a lead's status
    /// badge read whole.
    let saysAllStatus: Bool
    let isOffline: Bool
    let more: ActivityBarMoreModel?
    let openActivity: (ActivityRequest.Focus) -> Void

    var form: ActivityBarForm { metrics.form }

    /// Line two shows, where the form draws it: in the host's height at the
    /// text size.
    var showsLineTwo: Bool {
        drawing.parts.contains(.lineTwo) && metrics.showsLineTwo(in: bar, container: container)
    }
}

/// A live game, on your move or theirs, low on time, in stone removal or
/// paused; or one that started elsewhere, with Open game. Observing the
/// game redraws its clock, and the time VoiceOver reads, each second.
private struct ActivityBarGameRow: View {
    @ObservedObject var game: Game
    let isStarted: Bool
    /// What line two says in its place while the window's status shows.
    let status: RootConnectionLine.Words?
    let context: ActivityBarContext

    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var nav: NavigationService
    /// The two settings Home reads, so the clock wears Home's colors.
    @AppStorage(SettingKey<String>.gameTheme.name, store: userDefaults)
    private var gameThemeID = SurroundTheme.standard.rawValue
    @AppStorage(SettingKey<Bool>.themeAppliesToWholeApp.name, store: userDefaults)
    private var themeAppliesToWholeApp = true

    var body: some View {
        ActivityBarRow(model: model, context: context)
            .environment(\.surroundTheme, SurroundTheme.current(storedID: gameThemeID,
                                                                appliesToWholeApp: themeAppliesToWholeApp))
    }

    private var model: ActivityBarRowModel {
        let facts = HomeGameFacts(game: game, user: ogs.user)
        let name = facts.opponent?.username ?? ""
        let nav = nav
        let game = game
        let open = { nav.goToActiveGame(game: game) }
        let lineTwoStatus = status.map { ActivityBarRowModel.LineTwo.badge(ActivityBarWords.status($0)) }
        if isStarted {
            let details = [name, ActivityRowContents.board(width: game.width, height: game.height),
                           game.gameData?.timeControl.system.shortDescription ?? ""].filter { !$0.isEmpty }
            return ActivityBarRowModel(
                tile: .user(facts.opponent), lineOne: ActivityBarWords.gameStarted,
                lineTwo: lineTwoStatus ?? .text(details.joined(separator: " · ")),
                lead: ActivityBarLeadModel(accessibility: .gameStarted(opponent: name), largeContent: name, tap: open),
                action: ActivityBarActionModel(
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
            glows: clockState.running && status == nil
        )
        return ActivityBarRowModel(
            tile: .user(facts.opponent), lineOne: name, rank: rank,
            lineTwo: lineTwoStatus ?? .text(ActivityRowContents.liveGame(facts).detail),
            clock: clock,
            lead: ActivityBarLeadModel(
                accessibility: .liveGame(opponent: name, rank: rank, isYourMove: isYourMove, isSuddenDeath: isSuddenDeath,
                                         timeLeft: clockState.running ? timeLeft : nil, ticks: clockState.running,
                                         isOffline: status != nil),
                largeContent: name, tap: open
            )
        )
    }
}

/// A live challenge sent to you: View opens its full card in Activity, and
/// the rest of the row opens Activity. Never an inline Accept.
private struct ActivityBarChallengeRow: View {
    let challenge: OGSDirectChallenge
    let model: ActivityModel.Challenge
    let status: RootConnectionLine.Words?
    let context: ActivityBarContext

    var body: some View {
        let content = ActivityRowContents.challenge(challenge, isLive: model.isLive)
        let itemID = ActivityModel.Item.challenge(model).id
        let name = content.title
        let row = ActivityBarRowModel(
            tile: .user(challenge.challenger), lineOne: name, rank: content.rank,
            lineTwo: status.map { .badge(ActivityBarWords.status($0)) }
                ?? .text(([ActivityBarWords.challenge] + content.details).joined(separator: " · ")),
            lead: ActivityBarLeadModel(
                accessibility: .challenge(challenger: name, rank: content.rank, details: content.details),
                largeContent: name, tap: { context.openActivity(.top) }
            ),
            action: ActivityBarActionModel(
                action: .view, label: ActivityBarWords.action(.view),
                accessibilityLabel: ActivityBarAccessibility.view(challenger: name),
                tap: { context.openActivity(.item(itemID)) }
            )
        )
        ActivityBarRow(model: row, context: context)
    }
}

/// One of your own searches or challenges: a still hourglass, the time
/// searched, which moves each second unless UI tests stop it
/// (`ActivityElapsed.stopsAt`), and Withdraw where the list's row withdraws
/// in place.
private struct ActivityBarWaitingRow: View {
    let waiting: ActivityModel.Waiting
    let withdrawsInPlace: Bool
    let status: RootConnectionLine.Words?
    let context: ActivityBarContext

    var body: some View {
        if ActivityElapsed.stopsAt == nil {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                ActivityBarWaitingFace(waiting: waiting, withdrawsInPlace: withdrawsInPlace, status: status,
                                       context: context, now: timeline.date.timeIntervalSince1970, ticks: true)
            }
        } else {
            ActivityBarWaitingFace(waiting: waiting, withdrawsInPlace: withdrawsInPlace, status: status,
                                   context: context, now: Date().timeIntervalSince1970, ticks: false)
        }
    }
}

private struct ActivityBarWaitingFace: View {
    let waiting: ActivityModel.Waiting
    let withdrawsInPlace: Bool
    let status: RootConnectionLine.Words?
    let context: ActivityBarContext
    let now: TimeInterval
    let ticks: Bool

    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var nav: NavigationService

    var body: some View {
        let source = ActivityListSource(ogs: ogs, nav: nav, placement: .sheet)
        if let target = source.waitingTarget(ActivityWaitingRef.parse(waiting.id), in: source.openChallenges) {
            ActivityBarRow(model: model(target, content: source.content(of: target, waiting: waiting, now: now)),
                           context: context)
        }
    }

    private func model(_ target: ActivityListSource.WaitingTarget, content: ActivityRowContent) -> ActivityBarRowModel {
        let itemID = ActivityModel.Item.waiting(waiting).id
        let hasElapsedTime = waiting.kind == .quickMatch || waiting.kind == .openChallenge
        let steady = hasElapsedTime ? Array(content.details.dropLast()) : content.details
        let lineOne: String
        let lineTwo: [String]
        let subject: ActivityBarAccessibility.WaitingSubject
        switch target {
        case .search:
            lineOne = ActivityBarWords.searching
            lineTwo = [content.title] + content.details
            subject = .search
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
        let spokenDetails = target.isSearch ? [content.title] + steady : steady
        let waited = hasElapsedTime ? ActivityElapsed.waited(since: waiting.since, now: now) : nil
        let results = nav.activityResults
        let display = content.display
        return ActivityBarRowModel(
            tile: .glyph(content.symbol ?? "hourglass", tint: MessagesStyle.accent, background: MessagesStyle.paleAccent),
            lineOne: lineOne,
            lineTwo: status.map { .badge(ActivityBarWords.status($0)) } ?? .text(lineTwo.joined(separator: " · ")),
            lead: ActivityBarLeadModel(
                accessibility: .waiting(subject, details: spokenDetails, waited: waited, ticks: ticks),
                largeContent: lineOne, tap: { context.openActivity(.top) }
            ),
            action: withdrawsInPlace ? ActivityBarActionModel(
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

private extension ActivityListSource.WaitingTarget {
    var isSearch: Bool {
        if case .search = self { return true }
        return false
    }
}

/// Nothing live leads: the inbox glyph, "3 waiting" and what waits; a tap
/// opens Activity.
private struct ActivityBarNothingLeadsRow: View {
    let count: Int
    let counted: [ActivityBarCountedItem]
    let status: RootConnectionLine.Words?
    let context: ActivityBarContext

    @EnvironmentObject private var ogs: OGSService

    var body: some View {
        let breakdown = ActivityBarBreakdown(counted) { id in
            ogs.challengesReceived.first { $0.id == id }?.challenger?.username
        }
        let lineOne = ActivityBarWords.waiting(count)
        ActivityBarRow(
            model: ActivityBarRowModel(
                tile: .glyph("tray", tint: .primary, background: Color(uiColor: .tertiarySystemFill)),
                lineOne: lineOne,
                lineTwo: status.map { .badge(ActivityBarWords.status($0)) } ?? .text(breakdown.lineTwo),
                lead: ActivityBarLeadModel(accessibility: .nothingLeads(count: count, breakdown),
                                           largeContent: lineOne, tap: { context.openActivity(.top) })
            ),
            context: context
        )
    }
}

/// "Can’t reach OGS", with Retry and +N: the window's source retries.
/// Line one may truncate to nothing, as the title says it too.
private struct ActivityBarUnreachableRow: View {
    let context: ActivityBarContext
    @Environment(\.connectionStatus) private var connection

    var body: some View {
        let words = ActivityBarWords.unreachable
        ActivityBarRow(
            model: ActivityBarRowModel(
                tile: .glyph(ActivityBarStatusGlyph.name(.unreachable), tint: .secondary,
                             background: Color(uiColor: .tertiarySystemFill)),
                lineOne: words, lineOneMinimum: ActivityBarPartText.ellipsis, lineOneIsStatus: true,
                lead: ActivityBarLeadModel(accessibility: .status(.unreachable), largeContent: words,
                                           identifier: ID.rootConnectionStatus, tap: nil),
                action: ActivityBarActionModel(
                    action: .retry, label: ActivityBarWords.action(.retry),
                    accessibilityLabel: ActivityBarAccessibility.retry, identifier: ID.rootConnectionStatusRetry,
                    tap: { connection?.retry() }
                )
            ),
            context: context
        )
    }
}

/// "Connecting…", "Reconnecting…" or "Connected", where the bar carries
/// all status and nothing waits: status, not a button.
private struct ActivityBarStatusRow: View {
    let words: RootConnectionLine.Words
    let context: ActivityBarContext

    var body: some View {
        let text = ActivityBarWords.status(words)
        ActivityBarRow(
            model: ActivityBarRowModel(
                tile: .glyph(ActivityBarStatusGlyph.name(words), tint: ActivityBarStatusGlyph.tint(words),
                             background: Color(uiColor: .tertiarySystemFill)),
                lineOne: text, lineOneIsStatus: true,
                lead: ActivityBarLeadModel(accessibility: .status(words), largeContent: text,
                                           identifier: ID.rootConnectionStatus, tap: nil)
            ),
            context: context
        )
    }
}

/// An action taken in the bar: "Withdrawing…" with a grey hourglass and no
/// action, then "Withdrawn", or "Couldn’t withdraw" with Retry, for 4 s.
private struct ActivityBarResultRow: View {
    let result: ActivityBarResult
    let context: ActivityBarContext
    @EnvironmentObject private var nav: NavigationService

    var body: some View {
        let accessibility = ActivityBarAccessibility.result(result)
        let display = result.display
        let results = nav.activityResults
        let itemID = result.itemID
        ActivityBarRow(
            model: ActivityBarRowModel(
                tile: result.state.isPending
                    ? .glyph(display.kindSymbol ?? "hourglass", tint: .secondary, background: Color(uiColor: .tertiarySystemFill))
                    : .display(display),
                lineOne: accessibility.label,
                lineTwo: .text([display.title, display.detail].filter { !$0.isEmpty }.joined(separator: " · ")),
                lead: ActivityBarLeadModel(accessibility: accessibility, largeContent: accessibility.label, tap: nil),
                action: result.state == .failed ? ActivityBarActionModel(
                    action: .retry, label: ActivityBarWords.action(.retry),
                    accessibilityLabel: ActivityBarWords.action(.retry), isEnabled: !context.isOffline,
                    tap: { results.retry(itemID: itemID, session: results.chromeSession) }
                ) : nil
            ),
            context: context
        )
    }
}

/// The status kinds' glyph: the bar's and the Now section's status row.
enum ActivityBarStatusGlyph {
    static func name(_ words: RootConnectionLine.Words) -> String {
        words == .connected ? "checkmark" : "arrow.triangle.2.circlepath"
    }

    static func tint(_ words: RootConnectionLine.Words) -> Color {
        words == .connected ? Color(uiColor: .systemGreen) : .secondary
    }
}

/// The sudden-death mark in the app's language, measured once: the app's
/// language can't change while it runs. The bar and the Now rows keep the
/// in-game chip's rule.
enum ActivityBarMarks {
    static let suddenDeath = GameControlSuddenDeathMark.drawn(in: .bottomBar)
}

// MARK: - One row

/// What one kind draws, before the form decides which parts fit.
private struct ActivityBarRowModel {
    enum Tile {
        case user(OGSUser?)
        case glyph(String, tint: Color, background: Color)
        /// A resolved item's frozen picture.
        case display(ActivityRowDisplay)
    }

    enum LineTwo {
        case text(String)
        /// The window's status, in a grey badge, on line two's place.
        case badge(String)
    }

    var tile: Tile
    var lineOne: String
    var rank: String?
    /// How far line one may truncate before a part drops.
    var lineOneMinimum = ActivityBarPartText.letterAndEllipsis
    /// Line one says the window's status: where the host says all status,
    /// it reads whole.
    var lineOneIsStatus = false
    var lineTwo: LineTwo = .text("")
    var clock: ActivityBarClockFace?
    var lead: ActivityBarLeadModel
    var action: ActivityBarActionModel?
}

/// The lead: the tile, the lines and a game's clock, one VoiceOver element.
private struct ActivityBarLeadModel {
    var accessibility: ActivityBarAccessibility
    /// What the Large Content Viewer shows for it.
    var largeContent: String
    var identifier = ID.activityBarLead
    /// Nil for the status kinds and results, which aren't buttons.
    var tap: (() -> Void)?
}

private struct ActivityBarActionModel {
    var action: ActivityBarAction
    var label: String
    var accessibilityLabel: String
    var identifier = ID.activityBarAction
    var isEnabled = true
    var tap: () -> Void
}

private struct ActivityBarMoreModel {
    var count: Int
    var accessibility: ActivityBarAccessibility
}

/// A game's clock as the chip draws it: digits only, in its side's stone
/// colors; the running one glows, low time is red with the sudden-death
/// mark, and offline the digits stay while the glow goes. The Now rows draw
/// the same chip at their own size.
struct ActivityBarClockFace {
    /// Nil without a countdown: the hourglass alone.
    var time: GameControlClock?
    var color: StoneColor
    /// In sudden death, in the hourglass's place.
    var mark: GameControlSuddenDeathMark?
    var warns: Bool
    var glows: Bool
}

/// One row of parts in the bar's form. A one-line form drops parts in the
/// model's order until the rest fit the width the host gives it, and so do
/// the other forms where the host says all status, until the status words
/// or a lead's status badge read whole: SwiftUI's `ViewThatFits`, which
/// chooses among the drawings of the same form and never changes the bar's
/// size, so nothing it chooses can feed back into a layout or decide
/// whether the bar exists. Each fixed part is drawn at the width the
/// metrics measure, so the drawing that fits is the one the fit test
/// proves. A +N that drops stays a VoiceOver action on the lead.
private struct ActivityBarRow: View {
    let model: ActivityBarRowModel
    let context: ActivityBarContext

    private var metrics: ActivityBarMetrics { context.metrics }

    private var text: ActivityBarPartText {
        var badge: String?
        if context.saysAllStatus, context.showsLineTwo, case .badge(let words) = model.lineTwo { badge = words }
        return ActivityBarPartText(
            lineOneMinimum: context.saysAllStatus && model.lineOneIsStatus ? model.lineOne : model.lineOneMinimum,
            rank: model.rank, statusBadge: badge, clock: model.clock?.time, suddenDeathMark: model.clock?.mark,
            plusN: context.more?.count ?? 0
        )
    }

    /// The drawing's parts and drop order, as the metrics fit them.
    private var drawn: (parts: [ActivityBarPart], dropOrder: [ActivityBarPart]) {
        let chipDrawsItsSymbol = model.clock?.time == nil || model.clock?.mark != nil
        let left: (ActivityBarPart) -> Bool = { $0 == .hourglass && chipDrawsItsSymbol }
        var parts = context.drawing.parts.filter { !left($0) }
        // A kind whose model has no action draws none, whatever its drawing.
        if model.action == nil { parts.removeAll { if case .action = $0 { return true } else { return false } } }
        if context.more == nil { parts.removeAll { $0 == .plusN } }
        return (parts, context.drawing.dropOrder.filter { !left($0) && parts.contains($0) })
    }

    var body: some View {
        let shown = self.drawn
        Group {
            if !shown.dropOrder.isEmpty {
                ViewThatFits(in: .horizontal) {
                    ForEach(Array(Self.variants(shown.parts, dropOrder: shown.dropOrder).enumerated()),
                            id: \.offset) { _, kept in
                        parts(kept)
                    }
                }
            } else {
                parts(shown.parts)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Every part, then one fewer at a time in the drop order.
    private static func variants(_ parts: [ActivityBarPart], dropOrder: [ActivityBarPart]) -> [[ActivityBarPart]] {
        var variants = [parts]
        var kept = parts
        for part in dropOrder {
            kept.removeAll { $0 == part }
            variants.append(kept)
        }
        return variants
    }

    private func parts(_ kept: [ActivityBarPart]) -> some View {
        HStack(spacing: metrics.spacing.between) {
            ActivityBarLeadView(model: model, metrics: metrics, text: text, kept: kept,
                                showsLineTwo: kept.contains(.lineTwo) && context.showsLineTwo,
                                lineOneLines: context.drawing.lineOneLines,
                                droppedMore: kept.contains(.plusN) ? nil : context.more,
                                openActivity: { context.openActivity(.top) })
            if let action = model.action, kept.contains(.action(action.action)) {
                ActivityBarActionButton(model: action, metrics: metrics)
            }
            if let more = context.more, kept.contains(.plusN) {
                ActivityBarMoreButton(model: more, metrics: metrics) { context.openActivity(.top) }
            }
        }
        .padding(.leading, metrics.spacing.leading)
        .padding(.trailing, metrics.spacing.trailing)
    }
}

/// The lead: a button where a tap opens the game or Activity, else an
/// element that says the status or the result.
private struct ActivityBarLeadView: View {
    let model: ActivityBarRowModel
    let metrics: ActivityBarMetrics
    let text: ActivityBarPartText
    let kept: [ActivityBarPart]
    let showsLineTwo: Bool
    /// The lines line one may take.
    let lineOneLines: Int
    /// +N, where it dropped from view: VoiceOver keeps its count and its
    /// way to Activity as an action of the lead's.
    let droppedMore: ActivityBarMoreModel?
    let openActivity: () -> Void

    var body: some View {
        let accessibility = model.lead.accessibility
        Group {
            if let tap = model.lead.tap {
                Button(action: tap) { face }
                    .buttonStyle(ActivityBarPressStyle())
                    .accessibilityHint(Text(verbatim: accessibility.hint))
                    .accessibilityShowsLargeContentViewer {
                        Text(verbatim: model.lead.largeContent)
                    }
            } else {
                face
                    .accessibilityElement(children: .ignore)
            }
        }
        .accessibilityLabel(Text(verbatim: accessibility.label))
        .accessibilityValue(Text(verbatim: accessibility.value))
        .accessibilityAddTraits(accessibility.updatesFrequently ? .updatesFrequently : [])
        .accessibilityIdentifier(model.lead.identifier)
        .modifier(ActivityBarDroppedMoreAction(more: droppedMore, open: openActivity))
    }

    private var face: some View {
        HStack(spacing: metrics.spacing.between) {
            if kept.contains(.tile) {
                ActivityBarTile(tile: model.tile, size: metrics.tileSize)
            }
            let lines = metrics.width(of: .lineOne, text, lineOneLines: lineOneLines)
            ActivityBarLines(model: model, metrics: metrics, showsLineTwo: showsLineTwo, lineOneLines: lineOneLines)
                .frame(minWidth: lines, idealWidth: lines, maxWidth: .infinity, alignment: .leading)
            if let clock = model.clock, kept.contains(.clock) {
                let showsHourglass = kept.contains(.hourglass)
                ActivityBarClockChip(clock: clock, sizes: metrics.clockChip, showsHourglass: showsHourglass)
                    .frame(width: (showsHourglass ? metrics.width(of: .hourglass, text) + metrics.spacing.between : 0)
                           + metrics.width(of: .clock, text))
            }
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

/// A dropped +N's count, and its way to Activity, as a VoiceOver action.
private struct ActivityBarDroppedMoreAction: ViewModifier {
    let more: ActivityBarMoreModel?
    let open: () -> Void

    func body(content: Content) -> some View {
        if let more {
            content.accessibilityAction(named: Text(verbatim: more.accessibility.label), open)
        } else {
            content
        }
    }
}

private struct ActivityBarTile: View {
    let tile: ActivityBarRowModel.Tile
    let size: CGFloat

    var body: some View {
        Group {
            switch tile {
            case .user(let user):
                ActivityRowTile(user: user, symbol: user == nil ? "person.fill" : nil, size: size)
            case .glyph(let name, let tint, let background):
                Image(systemName: name)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
                    .background(background, in: Circle())
            case .display(let display):
                ActivityRowTile(user: nil, symbol: display.kindSymbol, display: display, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Line one, with the rank beside the name, then line two or the grey
/// status badge. Each truncates at its tail; the status words take line
/// two's place where the drawing gives them two lines.
private struct ActivityBarLines: View {
    let model: ActivityBarRowModel
    let metrics: ActivityBarMetrics
    let showsLineTwo: Bool
    let lineOneLines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: ActivityBarMetrics.lineGap) {
            HStack(alignment: .firstTextBaseline, spacing: ActivityBarMetrics.rankGap) {
                Text(verbatim: model.lineOne)
                    .font(Font(metrics.lineOneFont as CTFont))
                    .foregroundStyle(.primary)
                    .lineLimit(lineOneLines)
                    .truncationMode(.tail)
                if let rank = model.rank, !rank.isEmpty, !metrics.form.isOneLine {
                    Text(verbatim: rank)
                        .font(Font(metrics.detailFont as CTFont))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            if showsLineTwo {
                switch model.lineTwo {
                case .text(let text):
                    Text(verbatim: text)
                        .font(Font(metrics.detailFont as CTFont).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                case .badge(let text):
                    Text(verbatim: text)
                        .font(Font(metrics.badgeFont as CTFont))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: metrics.badgeHeight)
                        .background(ActivityBarStyle.statusBadge, in: Capsule())
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A clock chip's sizes: the bar's in its form, or a Now row's.
struct ActivityClockChipSizes {
    var height: CGFloat
    var padding: CGFloat
    /// Between the hourglass or the mark and the digits.
    var innerGap: CGFloat
    var cornerRadius: CGFloat
    var font: UIFont
    var symbolPointSize: CGFloat
}

extension ActivityBarMetrics {
    var clockChip: ActivityClockChipSizes {
        ActivityClockChipSizes(height: clockHeight, padding: clockPadding, innerGap: clockInnerGap,
                               cornerRadius: form.isOneLine ? 8 : 9, font: clockFont, symbolPointSize: symbolPointSize)
    }
}

/// The clock in its side's stone colors, as Home's chips wear them: the
/// hourglass, or the sudden-death mark in its place, beside the digits.
struct ActivityBarClockChip: View {
    let clock: ActivityBarClockFace
    let sizes: ActivityClockChipSizes
    let showsHourglass: Bool

    @Environment(\.surroundTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var warningColor: Color { theme.clockSuddenDeathAccent(clock.color, scheme: colorScheme) }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: sizes.cornerRadius, style: .continuous)
    }
    private var symbolFont: Font { .system(size: sizes.symbolPointSize, weight: .semibold) }

    var body: some View {
        HStack(spacing: sizes.innerGap) {
            if let mark = clock.mark {
                switch mark {
                case .text(let text):
                    Text(verbatim: text)
                        .font(Font(sizes.font as CTFont))
                        .foregroundStyle(warningColor)
                        .fixedSize()
                case .glyph:
                    Image(systemName: GameControlSuddenDeathMark.glyphSystemName)
                        .font(symbolFont)
                        .foregroundStyle(warningColor)
                }
            } else if showsHourglass || clock.time == nil {
                Image(systemName: "hourglass")
                    .font(symbolFont)
                    .foregroundStyle(clock.warns ? warningColor
                                     : (clock.glows ? theme.homeChipAccent(clock.color) : Color.secondary))
            }
            if let time = clock.time {
                Text(verbatim: time.text)
                    .font(Font(sizes.font as CTFont))
                    .foregroundStyle(clock.warns ? warningColor : theme.identityForeground(clock.color))
                    .fixedSize()
            }
        }
        .padding(.horizontal, sizes.padding)
        .frame(maxWidth: .infinity)
        .frame(height: sizes.height)
        .background { surface }
        .overlay { ring }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var surface: some View {
        if theme == .feltMeadow {
            FeltControlSurface(color: clock.color, shape: shape)
        } else if theme == .christmasKeepsakes {
            ChristmasOrnamentSurface(color: clock.color, role: .clock, compact: true)
        } else if theme == .nightGarden {
            NightGardenPaneSurface(color: clock.color, role: .clock, compact: true)
        } else {
            shape.fill(LinearGradient(colors: theme.identityChipColors(clock.color), startPoint: .top, endPoint: .bottom))
        }
    }

    /// Strokes, not blurred shadows, as Home's chips draw them.
    @ViewBuilder private var ring: some View {
        if clock.warns {
            shape.strokeBorder(warningColor, lineWidth: 1.5)
                .background {
                    shape.inset(by: -2.5).stroke(warningColor.opacity(colorScheme == .dark ? 0.5 : 0.4), lineWidth: 3)
                }
        } else if clock.glows {
            shape.strokeBorder(theme.turnOutline(scheme: colorScheme), lineWidth: contrast == .increased ? 2 : 1)
                .background {
                    if contrast != .increased {
                        shape.inset(by: -2.5).stroke(theme.turnGlow.opacity(colorScheme == .dark ? 0.5 : 0.4),
                                                     lineWidth: 3)
                    }
                }
        } else if theme != .christmasKeepsakes {
            shape.strokeBorder(theme.identityChipBorder(clock.color), lineWidth: 1)
        }
    }
}

/// View, Open game and Retry as indigo-tinted pills; Withdraw as accent
/// text, in the bar's own tint (`ActivityBarStyle`). Each sits in a 44 pt
/// target, at the width the metrics measure.
private struct ActivityBarActionButton: View {
    let model: ActivityBarActionModel
    let metrics: ActivityBarMetrics

    var body: some View {
        let width = metrics.actionWidth(model.action, label: model.label)
        let isPill = model.action != .withdraw
        Button(action: model.tap) {
            Text(verbatim: model.label)
                .font(Font(metrics.actionFont as CTFont))
                .foregroundStyle(ActivityBarStyle.accent)
                .lineLimit(1)
                .fixedSize()
                .frame(width: width, height: isPill ? metrics.capsuleHeight : ActivityBarMetrics.targetSize)
                .background {
                    if isPill {
                        Capsule().fill(MessagesStyle.paleAccent)
                    }
                }
                .frame(height: ActivityBarMetrics.targetSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(ActivityBarPressStyle())
        .frame(width: width)
        .disabled(!model.isEnabled)
        .accessibilityLabel(Text(verbatim: model.accessibilityLabel))
        .accessibilityValue(Text(verbatim: model.isEnabled ? "" : ActivityBarWords.reconnecting))
        .accessibilityShowsLargeContentViewer {
            Text(verbatim: model.label)
        }
        .accessibilityIdentifier(model.identifier)
    }
}

/// +N: a neutral capsule that opens Activity, drawn 36 pt tall, 30 pt in a
/// one-line form, in a 44 pt target.
private struct ActivityBarMoreButton: View {
    let model: ActivityBarMoreModel
    let metrics: ActivityBarMetrics
    let open: () -> Void

    var body: some View {
        let text = ActivityBarMetrics.countText(model.count)
        Button(action: open) {
            Text(verbatim: text)
                .font(Font(metrics.countFont as CTFont))
                .foregroundStyle(.primary)
                .fixedSize()
                .frame(width: metrics.countWidth(model.count), height: metrics.capsuleHeight)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                .frame(width: max(ActivityBarMetrics.targetSize, metrics.countWidth(model.count)),
                       height: ActivityBarMetrics.targetSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(ActivityBarPressStyle())
        .accessibilityLabel(Text(verbatim: model.accessibility.label))
        .accessibilityHint(Text(verbatim: model.accessibility.hint))
        .accessibilityShowsLargeContentViewer {
            Text(verbatim: text)
        }
        .accessibilityIdentifier(ID.activityBarMore)
    }
}

/// The bar's and the Now section's own colours (`ActivityBarColors`): the
/// actions' words and All activity in a deeper indigo in light and a lighter
/// one in dark, and the status badge's darker grey, so each reads at 4.5:1
/// where Messages' indigo and the system's grey didn't. The pills keep
/// Messages' pale tint.
enum ActivityBarStyle {
    static let accent = Color(uiColor: ActivityBarColors.accent)
    static let statusBadge = Color(uiColor: ActivityBarColors.statusBadge)
}

/// Dims a part while it is pressed, as the in-game control's do.
struct ActivityBarPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// The custom bar's capsule: a material fill, a hairline edge and a soft
/// shadow, in light and dark.
private struct ActivityBarCapsule: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Capsule(style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
                                  lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.12), radius: 12, y: 8)
            .accessibilityHidden(true)
    }
}

// MARK: - The bar's frame in its window

/// The bar's latest frame in its window's coordinates, held by reference so
/// a new frame redraws nothing.
final class ActivityBarWindowFrame {
    fileprivate(set) var value = CGRect.zero
}

/// Reports the bar's frame in its window from UIKit, which converts its
/// bounds to the window. SwiftUI's global space stops at the hosting view of
/// an accessory or a sidebar's bottom bar. It reports a main-queue turn
/// after its window's geometry changes, as on a turn or a resize, so the
/// open popover follows the bar; it only records, and nothing it reports
/// decides whether the bar exists.
private struct ActivityBarWindowFrameReader: UIViewRepresentable {
    let frame: ActivityBarWindowFrame
    let moved: (CGRect) -> Void

    func makeUIView(context: Context) -> ReaderView {
        ReaderView(holder: frame, moved: moved)
    }

    func updateUIView(_ view: ReaderView, context: Context) {
        view.holder = frame
        view.moved = moved
    }

    final class ReaderView: UIView {
        var holder: ActivityBarWindowFrame
        var moved: (CGRect) -> Void
        private var reportIsScheduled = false

        init(holder: ActivityBarWindowFrame, moved: @escaping (CGRect) -> Void) {
            self.holder = holder
            self.moved = moved
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            accessibilityElementsHidden = true
            registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self]) {
                (view: ReaderView, _: UITraitCollection) in
                view.scheduleReport()
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scheduleReport()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleReport()
        }

        /// A main-queue turn later, outside the layout pass.
        private func scheduleReport() {
            guard !reportIsScheduled else { return }
            reportIsScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                reportIsScheduled = false
                guard let window else { return }
                let value = convert(bounds, to: window)
                guard value != holder.value else { return }
                holder.value = value
                moved(value)
            }
        }
    }
}

#if DEBUG && MAIN_APP
// MARK: - The Debug state element

/// Hidden, for UI tests: what the window's host applied
/// (`ActivityBarAppliedState`), such as "live game-26268404 uiKitAccessory
/// expanded", or "none". A host puts it where it applies the bar; UIKit's
/// accessory gives it what the coordinator set, never what MainView asked.
struct ActivityBarStateElement: View {
    let text: String

    var body: some View {
        if SurroundUITestContract.isEnabled {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: "Activity bar state"))
                .accessibilityValue(Text(verbatim: text))
                .accessibilityIdentifier(ID.activityBarState)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Previews

private func activityBarPreview(_ content: ActivityBarContent, bar: ActivityHostPolicy.Bar = .customBar,
                                placement: ActivityHostPolicy.AccessoryPlacement = .unavailable,
                                container: ActivityHostPolicy.Container = .swiftUITabView,
                                isCompactHeight: Bool = false, hasVerticalBarEdge: Bool = false,
                                ogs: OGSService = OGSService.previewInstance(
                                    user: OGSUser(username: "HongAnhKhoa", id: 314459),
                                    challengesReceived: [OGSChallengeSampleData.sampleChallenge],
                                    automatchEntries: [OGSAutomatchEntry.sampleEntry])) -> some View {
    let traits = ActivityBarTraits(bar: bar, container: container, placement: placement,
                                   isCompactHeight: isCompactHeight, hasVerticalBarEdge: hasVerticalBarEdge)
    return ActivityBarView(content: content, traits: traits)
        .padding(.horizontal, bar == .customBar ? 16 : 21)
        .frame(width: bar == .uiKitAccessory && hasVerticalBarEdge ? 290 : 402, height: 80)
        .environmentObject(ogs)
        .environmentObject(NavigationService())
        .environment(\.surroundAllowsRemoteActivity, false)
}

private let previewChallenge = ActivityModel.Challenge(id: OGSChallengeSampleData.sampleChallenge.id, isLive: true)

#Preview("Bar — Challenge, expanded") {
    activityBarPreview(.lead(.challenge(previewChallenge), counted: [.conversation(peerID: 1), .conversation(peerID: 2)],
                             status: nil))
}

#Preview("Bar — Search, compact height") {
    activityBarPreview(.lead(.waiting(ActivityModel.Waiting(id: ActivityModel.WaitingID.quickMatch(OGSAutomatchEntry.sampleEntry.uuid),
                                                            kind: .quickMatch, isLive: true, since: Date().timeIntervalSince1970 - 72),
                                      withdrawsInPlace: true), counted: [], status: nil),
                       isCompactHeight: true)
}

#Preview("Bar — Nothing leads, accessory") {
    activityBarPreview(.lead(.nothingLeads(count: 3),
                             counted: [.challenge(ActivityModel.Challenge(id: 1, isLive: false)),
                                       .conversation(peerID: 1), .conversation(peerID: 2)], status: nil),
                       bar: .swiftUIAccessory)
}

#Preview("Bar — Can’t reach OGS, inline") {
    activityBarPreview(.unreachable(counted: [.conversation(peerID: 1)]), bar: .uiKitAccessory, placement: .inline,
                       container: .duoTabContainer)
}

#Preview("Bar — Can’t reach OGS, Closed") {
    activityBarPreview(.unreachable(counted: [.conversation(peerID: 1), .conversation(peerID: 2)]), bar: .uiKitAccessory,
                       container: .duoTabContainer, hasVerticalBarEdge: true)
}

#Preview("Bar — Reconnecting, custom bar") {
    activityBarPreview(.status(.reconnecting))
}

#Preview("Bar — Withdrawn") {
    activityBarPreview(.result(ActivityBarResult(itemID: "waiting-quick-match-1", action: .withdraw,
                                                 state: .succeeded(.withdrawn),
                                                 display: ActivityRowDisplay(title: "Quick match", detail: "Live · 19×19",
                                                                             kindSymbol: "hourglass"))))
}
#endif
