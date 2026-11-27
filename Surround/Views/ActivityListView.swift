//
//  ActivityListView.swift
//  Surround
//
//  One window's Activity list: the user's live games, challenges received,
//  their own searches and challenges, one row for the correspondence games
//  on their move, and conversations. Rows act in place through the window's
//  results store (ActivityResults), and a row the user resolved shows its
//  result until the list closes. View, Quick Match and Rengo rows push
//  their full cards, and conversations push inside the list's own stack.
//  The list rebuilds its rows each second; offline it reads the user's open
//  challenges from the window's last-known copy and dims the actions that
//  need OGS. Each window shows its list from one presenter, a sheet or a
//  popover by the request, and the controls that open it record where they
//  are so a popover is anchored there. Game Detail's in-game control
//  presents its own popover instead: at game over the opponent's challenge
//  leads it as the game-over card, then the picker, above the sections,
//  with its game's place and the window's connection status.
//

import Combine
import SwiftUI

private typealias ID = SurroundUITestContract.AccessibilityID

struct ActivityListView: View {
    /// Where the list is shown.
    enum Placement: Equatable {
        case sheet
        /// On a root screen at regular width.
        case popover
        /// Over a game: denser rows, and View instead of inline Accept.
        case gamePopover
        /// Inside New game's stack, or the capture scene.
        case route

        var density: ActivityRowDensity { self == .gamePopover ? .dense : .regular }
    }

    let session: UUID
    let placement: Placement
    let focus: ActivityRequest.Focus
    /// The list's place, which a game's popover takes from its Game Detail:
    /// the window's registry leaves out a game in a presented stack, such
    /// as the iPad Profile sheet. Nil reads the registry.
    var place: ActivityModel.Place?
    /// The challenge of the game-over card, which the in-game control shows
    /// at game over. The card leads the list, under the status line, and
    /// its challenge stays out of Challenges received.
    var cardChallengeID: Int?
    /// Above the sections, under the status line and the card, inside the
    /// list's scroll: the in-game control's picker of same-speed games. Nil
    /// where nothing draws there, so the card knows what follows it.
    var header: AnyView?
    /// How a live row shows its game. A game's popover switches as its Game
    /// Detail does, in place on Home's route; nil opens the game on Home's
    /// route and resets the window's stacks.
    var switchGame: ((Game) -> Void)?
    /// The window's connection status, which root lists and a game's
    /// popover share with the window's other carriers. Nil makes the list's
    /// own, as in captures, which have no window source.
    var connection: ConnectionStatusSource?

    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var nav: NavigationService
    @Environment(\.surroundAllowsRemoteActivity) private var allowsRemoteActivity

    init(session: UUID, placement: Placement, focus: ActivityRequest.Focus = .top,
         place: ActivityModel.Place? = nil, cardChallengeID: Int? = nil, header: AnyView? = nil,
         switchGame: ((Game) -> Void)? = nil, connection: ConnectionStatusSource? = nil) {
        self.session = session
        self.placement = placement
        self.focus = focus
        self.place = place
        self.cardChallengeID = cardChallengeID
        self.header = header
        self.switchGame = switchGame
        self.connection = connection
    }

    var body: some View {
        ActivityListContent(
            session: session, placement: placement, focus: focus, place: place, cardChallengeID: cardChallengeID,
            header: header, switchGame: switchGame, connection: connection, ogs: ogs, nav: nav,
            path: allowsRemoteActivity ? SystemNetworkPathMonitor.shared : ConstantNetworkPath.satisfied
        )
    }
}

// MARK: - What the list shows

/// What one window's Activity list shows now, from the window's input
/// (`ActivityModel.Input.window`), which the window's bar and Game Detail's
/// control read too, its last-known seek graph rows and its results; in
/// Debug runs with an Activity state, from the fixture and its clock. The
/// pushed cards read the same, so their actions keep the row's place.
@MainActor
struct ActivityListSource {
    let ogs: OGSService
    let nav: NavigationService
    let placement: ActivityListView.Placement
    /// A game's popover's own place, from its Game Detail.
    var placeOverride: ActivityModel.Place? = nil

    struct Snapshot {
        var input: ActivityModel.Input
        var model: ActivityModel.Snapshot
        /// The game-over card's row, which leads the list.
        var card: ActivityListSections.Row?
        /// Every section but the card's row.
        var sections: [ActivityListSections.Section]
        /// The user's open and Rengo challenges, as the rows read them.
        var openChallenges: ActivityLastKnown.OpenChallenges
        /// Ids the store hides that the service no longer lists
        /// (`ActivityModel.Input.hiddenListedIDs`), so they need no hiding.
        var settledHiddenIDs: Set<String>

        /// No card and no section: the list reads "Nothing waiting".
        var isEmpty: Bool { card == nil && sections.isEmpty }
    }

    /// One of the user's own waiting items, from its id.
    enum WaitingTarget {
        case search(OGSAutomatchEntry)
        case openChallenge(OGSSeekgraphChallenge)
        case sentChallenge(OGSDirectChallenge)
        case rengo(OGSSeekgraphChallenge)

        var challenge: (any OGSSubmittedChallenge)? {
            switch self {
            case .search: nil
            case .openChallenge(let challenge), .rengo(let challenge): challenge
            case .sentChallenge(let challenge): challenge
            }
        }
    }

    /// A Debug Activity state's fixture clock stands still, and the list
    /// never ticks.
    static var isClockFrozen: Bool {
        #if DEBUG && MAIN_APP
        return ActivityFixtures.selected?.clock.isFrozen ?? false
        #else
        return false
        #endif
    }

    /// Inside New game's stack the place is the root's; a game's popover
    /// can bring its own.
    var place: ActivityModel.Place {
        if let placeOverride { return placeOverride }
        return placement == .route
            ? .root(isMessagesTab: nav.main.rootView == .privateMessages)
            : nav.activityPlaces.place(in: nav.main.rootView)
    }

    var openChallenges: ActivityLastKnown.OpenChallenges {
        #if DEBUG && MAIN_APP
        if ActivityFixtures.selected != nil {
            // The fixture's input reads the service's own rows.
            return ActivityLastKnown.OpenChallenges(
                openChallengeSentById: ogs.openChallengeSentById,
                participatingRengoChallengeById: ogs.participatingRengoChallengeById,
                hostingRengoChallengeById: ogs.hostingRengoChallengeById
            )
        }
        #endif
        return nav.activityLastKnown.openChallenges(live: ogs)
    }

    /// - Parameters:
    ///   - card: The game-over cards the list has shown.
    ///   - cardChallengeID: The control's card now.
    func snapshot(now: TimeInterval, card: ActivityGameOverCard = ActivityGameOverCard(),
                  showing cardChallengeID: Int? = nil) -> Snapshot {
        let openChallenges = openChallenges
        let input = ActivityModel.Input.window(ogs: ogs, nav: nav, place: place, now: now)
        let model = ActivityModel.snapshot(input)
        let results = nav.activityResults
        let hidden = results.hiddenIDs
        // The input already leaves out what OGS confirmed gone; the list
        // keeps its own filter for the resolved rows it shows.
        let listed = model.list.filter { !hidden.contains($0.id) }
        let resolved = results.resolvedRows
        let cardRow = card.row(showing: cardChallengeID, listed: listed, resolved: resolved)
        return Snapshot(
            input: input, model: model, card: cardRow,
            sections: ActivityListSections.sections(list: listed, resolved: resolved,
                                                    excluding: Set(cardRow.map { [$0.id] } ?? [])),
            openChallenges: openChallenges,
            settledHiddenIDs: hidden.subtracting(input.hiddenListedIDs)
        )
    }

    func waitingTarget(_ ref: ActivityWaitingRef?, in openChallenges: ActivityLastKnown.OpenChallenges) -> WaitingTarget? {
        switch ref {
        case .quickMatch(let uuid):
            ogs.autoMatchEntryById[uuid].map(WaitingTarget.search)
        case .openChallenge(let id):
            openChallenges.openChallengeSentById[id].map(WaitingTarget.openChallenge)
        case .sentChallenge(let id):
            ogs.challengesSent.first { $0.id == id }.map(WaitingTarget.sentChallenge)
        case .rengo(let id):
            (openChallenges.participatingRengoChallengeById[id] ?? openChallenges.hostingRengoChallengeById[id])
                .map(WaitingTarget.rengo)
        case nil:
            nil
        }
    }

    /// A waiting row's content, its time searched at `now`, or where UI
    /// tests stop it (`ActivityElapsed.stopsAt`).
    func content(of target: WaitingTarget, waiting: ActivityModel.Waiting, now: TimeInterval) -> ActivityRowContent {
        let waited = ActivityElapsed.waited(since: waiting.since, now: now)
        return switch target {
        case .search(let entry):
            ActivityRowContents.quickMatch(entry, waited: waited)
        case .openChallenge(let challenge):
            ActivityRowContents.openChallenge(challenge, isLive: waiting.isLive, waited: waited)
        case .sentChallenge(let challenge):
            ActivityRowContents.sentChallenge(challenge, isLive: waiting.isLive)
        case .rengo(let challenge):
            ActivityRowContents.rengo(challenge, isLive: waiting.isLive)
        }
    }

    /// An item's row as it is now, its section and the id before it there:
    /// what an action freezes.
    func frozen(_ itemID: String) -> (display: ActivityRowDisplay, section: ActivitySection, after: String?) {
        let snapshot = snapshot(now: Date().timeIntervalSince1970)
        let position = ActivityListSections.position(of: itemID, in: snapshot.sections)
        var content: ActivityRowContent?
        switch snapshot.model.list.first(where: { $0.id == itemID }) {
        case .challenge(let item):
            content = ogs.challengesReceived.first { $0.id == item.id }
                .map { ActivityRowContents.challenge($0, isLive: item.isLive) }
        case .waiting(let waiting):
            content = waitingTarget(ActivityWaitingRef.parse(waiting.id), in: snapshot.openChallenges)
                .map { self.content(of: $0, waiting: waiting, now: snapshot.input.now) }
        default:
            content = nil
        }
        let section = position?.section ?? (itemID.hasPrefix("challenge-") ? .challengesReceived : .waiting)
        return (content?.display ?? ActivityRowDisplay(title: "", detail: ""), section, position?.after)
    }
}

// MARK: - The list

private struct ActivityListContent: View {
    let session: UUID
    let placement: ActivityListView.Placement
    let focus: ActivityRequest.Focus
    let place: ActivityModel.Place?
    let cardChallengeID: Int?
    let header: AnyView?
    let switchGame: ((Game) -> Void)?
    @ObservedObject var ogs: OGSService
    let nav: NavigationService
    @ObservedObject var results: ActivityResults
    @ObservedObject var lastKnown: ActivityLastKnown
    @ObservedObject var places: ActivityPlaceRegistry

    @EnvironmentObject private var navigation: StackRouter
    @Environment(\.owningStackRoute) private var owningStackRoute
    @Environment(\.scenePhase) private var scenePhase
    /// The window's, in a game's popover; otherwise the list's own.
    @StateObject private var connection: ConnectionStatusSource
    /// The list made its own source, so it says when it is on screen. The
    /// window's host says that for the window's source.
    private let ownsConnection: Bool
    /// Ends the session if the list goes while something covers it, such as
    /// a sheet closed with a card pushed.
    @StateObject private var lifetime = ViewLifetime()
    /// The list is shown, or covered only by what it pushed.
    @State private var isPresented = true
    @State private var hasFocused = false
    /// The game-over cards this list has shown, so the card keeps its place
    /// and its result while the list is open.
    @State private var card = ActivityGameOverCard()
    /// Where VoiceOver is among the rows' controls and results.
    @AccessibilityFocusState private var voiceOverFocus: ActivityFocus?
    /// The two settings Home reads, so the live games' clocks match Home's.
    @AppStorage(SettingKey<String>.gameTheme.name, store: userDefaults)
    private var gameThemeID = SurroundTheme.standard.rawValue
    @AppStorage(SettingKey<Bool>.themeAppliesToWholeApp.name, store: userDefaults)
    private var themeAppliesToWholeApp = true

    init(session: UUID, placement: ActivityListView.Placement, focus: ActivityRequest.Focus,
         place: ActivityModel.Place?, cardChallengeID: Int?, header: AnyView?, switchGame: ((Game) -> Void)?,
         connection windowConnection: ConnectionStatusSource?,
         ogs: OGSService, nav: NavigationService, path: NetworkPathMonitoring) {
        self.session = session
        self.placement = placement
        self.focus = focus
        self.place = place
        self.cardChallengeID = cardChallengeID
        self.header = header
        self.switchGame = switchGame
        _ogs = ObservedObject(wrappedValue: ogs)
        self.nav = nav
        _results = ObservedObject(wrappedValue: nav.activityResults)
        _lastKnown = ObservedObject(wrappedValue: nav.activityLastKnown)
        _places = ObservedObject(wrappedValue: nav.activityPlaces)
        ownsConnection = windowConnection == nil
        _connection = StateObject(wrappedValue: windowConnection ?? {
            let source = ConnectionStatusSource(ogs: ogs, path: path)
            // On screen from its first frame, so the rows know at once.
            source.setVisible(true)
            return source
        }())
    }

    private var density: ActivityRowDensity { placement.density }
    private var source: ActivityListSource {
        ActivityListSource(ogs: ogs, nav: nav, placement: placement, placeOverride: place)
    }

    private var isOffline: Bool { connection.dimsActivityActions }

    private var homeTheme: SurroundTheme {
        SurroundTheme.current(storedID: gameThemeID, appliesToWholeApp: themeAppliesToWholeApp)
    }

    /// Something the list pushed is on top of its stack.
    private var isCoveredInItsStack: Bool {
        guard let route = owningStackRoute else { return !navigation.path.isEmpty }
        return navigation.path.contains(route) && navigation.path.last != route
    }

    var body: some View {
        Group {
            if ActivityListSource.isClockFrozen {
                list(source.snapshot(now: Date().timeIntervalSince1970, card: card, showing: cardChallengeID))
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    list(source.snapshot(now: context.date.timeIntervalSince1970, card: card, showing: cardChallengeID))
                }
            }
        }
        .navigationTitle(Text("Activity", comment: "Title of the list of the user's games, challenges, searches and messages. Also the Activity bar's VoiceOver name and the Mac's View menu command that opens the list"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: cardChallengeID, initial: true) { _, challengeID in card.remember(challengeID) }
        .onAppear {
            results.begin(session: session)
            isPresented = true
            // The cards this list pushes dim by its status: the window's,
            // in a game's popover. Pushed at a route, it lends it while its
            // route is in the stack.
            navigation.setActivityList(connection, at: owningStackRoute)
            if lifetime.release == nil {
                let results = results
                let session = session
                lifetime.release = { [weak results] in results?.end(session: session) }
            }
            if placement != .route, navigation.gameOpenOverride == nil {
                // A game opened from a profile pushed here opens in the
                // window, never inside the list.
                let nav = nav
                navigation.gameOpenOverride = { [weak nav] gameID in
                    nav?.closeActivity()
                    nav?.openGame(gameID, closesNewGame: true)
                }
            }
        }
        .onDisappear {
            // A card or conversation pushed above the list keeps its
            // session, so Back shows what came of it.
            guard !isCoveredInItsStack else { return }
            isPresented = false
            results.end(session: session)
        }
        .onChange(of: isPresented && scenePhase != .background, initial: true) { _, visible in
            if ownsConnection {
                connection.setVisible(visible)
            }
        }
        .onReceive(results.$entries) { claimResults($0) }
    }

    /// Sends a row's request. VoiceOver on the control that sent it moves to
    /// the spinner standing in for it, where the result can take it over.
    private func send(_ control: ActivityFocusControl, of itemID: String, _ request: () -> Void) {
        if let next = ActivityFocus.sending(control, of: itemID, from: voiceOverFocus) {
            voiceOverFocus = next
        }
        request()
    }

    /// As a result publishes, a row whose control or spinner has VoiceOver
    /// focus moves it to the result and claims it, in this same callback,
    /// before the store decides a turn later. Waiting for the redraw could
    /// be too late. `results.entries` still holds the value before `next`.
    private func claimResults(_ next: [String: ActivityResults.Entry]) {
        let before = results.entries
        for (itemID, entry) in next where !entry.state.isPending && before[itemID]?.state != entry.state {
            guard ActivityFocus.resultTakesFocus(from: voiceOverFocus, row: itemID) else { continue }
            voiceOverFocus = .result(itemID)
            results.claim(itemID: itemID)
        }
    }

    private func list(_ snapshot: ActivityListSource.Snapshot) -> some View {
        Group {
            if snapshot.isEmpty {
                VStack(spacing: 0) {
                    statusLine
                    header
                    ContentUnavailableView(
                        String(localized: "Nothing waiting", comment: "Activity: the list has no games, challenges, searches or messages"),
                        systemImage: "tray"
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(ID.activityEmpty)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        scrolledContent(snapshot)
                    }
                    .padding(.horizontal, density == .regular ? 16 : 0)
                    .padding(.bottom, 20)
                }
                .onAppear { applyFocus(snapshot) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((density == .regular ? MessagesStyle.canvas : MessagesStyle.card).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ID.activityList)
        .onChange(of: snapshot.settledHiddenIDs, initial: true) { _, ids in
            ids.forEach { results.forget(hidden: $0) }
        }
    }

    /// What the list's scroll holds: the status line, the game-over card,
    /// the header, then the sections.
    @ViewBuilder private func scrolledContent(_ snapshot: ActivityListSource.Snapshot) -> some View {
        statusLine
        if let card = snapshot.card {
            cardView(card, isFollowed: header != nil || !snapshot.sections.isEmpty)
        }
        header
        ForEach(snapshot.sections) { section in
            sectionView(section, snapshot)
        }
    }

    /// Opened at an item, as View in the bar or a Now row opens it, the list
    /// pushes that item's card on its first appearance, so Back shows the
    /// list.
    private func applyFocus(_ snapshot: ActivityListSource.Snapshot) {
        guard focus != .top, !hasFocused else { return }
        hasFocused = true
        let opening = focus.opening(in: snapshot.model.list)
        // After the first layout, so the stack has appeared.
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            switch opening {
            case .none:
                break
            case .card(let itemID):
                withTransaction(transaction) {
                    push(itemID)
                }
            }
        }
    }

    /// Under the title: "Reconnecting…", "Connecting…" before the window's
    /// first connection, or "Can’t reach OGS" with Retry.
    @ViewBuilder private var statusLine: some View {
        if isOffline {
            ActivityStatusLine(connection: connection, socket: ogs.socketStatus)
                .padding(.top, 4)
        }
    }

    // MARK: Sections

    private func sectionView(_ section: ActivityListSections.Section, _ snapshot: ActivityListSource.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: density == .regular ? 6 : 0) {
            if density == .dense, section.kind != snapshot.sections.first?.kind {
                Divider().padding(.horizontal, 16)
            }
            Text(verbatim: title(of: section.kind))
                .font(density == .regular ? .subheadline.weight(.semibold) : .footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, density == .regular ? 4 : 16)
                .padding(.top, density == .regular ? 16 : 8)
                .padding(.bottom, density == .regular ? 0 : 2)
                .accessibilityAddTraits(.isHeader)
            rows(section, snapshot)
                .background {
                    if density == .regular {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MessagesStyle.card)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: density == .regular ? 14 : 0, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ID.activitySection(name(of: section.kind)))
    }

    private func rows(_ section: ActivityListSections.Section, _ snapshot: ActivityListSource.Snapshot) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider().padding(.leading, density.separatorInset)
                }
                rowView(row, after: index > 0 ? section.rows[index - 1].id : nil, snapshot)
            }
            if section.kind == .messages {
                Divider().padding(.leading, density.horizontalPadding)
                ActivityLinkRow(
                    content: ActivityRowContent(title: String(
                        localized: "All messages", comment: "Activity: the last row of Messages; opens the Messages tab")),
                    density: density, identifier: ID.activityAllMessages, showsTile: false, open: openAllMessages
                )
            }
        }
    }

    private func title(of section: ActivitySection) -> String {
        switch section {
        case .liveGames: String(localized: "Live games")
        case .challengesReceived: String(localized: "Challenges received")
        case .waiting:
            String(localized: "Waiting for opponents", comment: "Activity: the section of the user's own searches and challenges")
        case .correspondence:
            String(localized: "Your correspondence games", comment: "Activity: the section with one row for the correspondence games on the user's move")
        case .messages: String(localized: "Messages")
        }
    }

    private func name(of section: ActivitySection) -> String {
        switch section {
        case .liveGames: "liveGames"
        case .challengesReceived: "challengesReceived"
        case .waiting: "waiting"
        case .correspondence: "correspondence"
        case .messages: "messages"
        }
    }

    // MARK: Rows

    private func actionState(for itemID: String, isUnusual: Bool = false,
                             isGameOverCard: Bool = false) -> ActivityRowActionState {
        ActivityRowActionState(isUnusual: isUnusual, isInGamePopover: placement == .gamePopover,
                               isGameOverCard: isGameOverCard, isOffline: isOffline,
                               state: results.entries[itemID]?.state)
    }

    @ViewBuilder
    private func rowView(_ row: ActivityListSections.Row, after: String?,
                         _ snapshot: ActivityListSource.Snapshot) -> some View {
        switch row {
        case .item(let item):
            itemRow(item, after: after, snapshot)
        case .resolved(let resolved):
            resolvedRow(resolved)
        }
    }

    private func resolvedRow(_ resolved: ActivityResolvedRow) -> some View {
        ActivityResolvedRowView(
            row: resolved, entry: results.entries[resolved.id], density: density,
            actionState: actionState(for: resolved.id), focus: $voiceOverFocus,
            retry: { send(.retry, of: resolved.id) { results.retry(itemID: resolved.id) } },
            openGame: openGame
        )
    }

    /// The game-over card: the opponent's challenge with Reject and Accept,
    /// or its warning and View when it is unusual, then its result in its
    /// place until the list closes. Its requests are the list's, in the
    /// list's session. A divider parts it from what follows: the header, or
    /// the sections.
    private func cardView(_ row: ActivityListSections.Row, isFollowed: Bool) -> some View {
        VStack(spacing: 0) {
            switch row {
            case .item(.challenge(let model)):
                if let challenge = ogs.challengesReceived.first(where: { $0.id == model.id }) {
                    challengeRow(challenge, model: model, itemID: row.id, after: nil, isGameOverCard: true)
                }
            case .item:
                EmptyView()
            case .resolved(let resolved):
                resolvedRow(resolved)
            }
            if isFollowed, density == .dense {
                Divider().padding(.horizontal, 16)
            }
        }
        .background {
            if density == .regular {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MessagesStyle.card)
            }
        }
        .padding(.top, density == .regular ? 16 : 0)
    }

    @ViewBuilder
    private func itemRow(_ item: ActivityModel.Item, after: String?,
                         _ snapshot: ActivityListSource.Snapshot) -> some View {
        switch item {
        case .liveGame(let live):
            if let game = ogs.liveGames.first(where: { $0.ogsID == live.id }) {
                ActivityLiveGameRow(
                    game: game, itemID: item.id, user: ogs.user, theme: homeTheme,
                    isLowOnTime: snapshot.model.lowTimeGameIDs.contains(live.id), density: density,
                    open: { openLiveGame(game) }
                )
            }
        case .challenge(let model):
            if let challenge = ogs.challengesReceived.first(where: { $0.id == model.id }) {
                challengeRow(challenge, model: model, itemID: item.id, after: after)
            }
        case .waiting(let waiting):
            if let target = source.waitingTarget(ActivityWaitingRef.parse(waiting.id), in: snapshot.openChallenges) {
                waitingRow(target, waiting: waiting, itemID: item.id, after: after, now: snapshot.input.now)
            }
        case .correspondenceGames(let count, let mostUrgentID):
            ActivityLinkRow(content: ActivityRowContents.correspondence(count: count), density: density,
                            identifier: ID.activityRow(item.id), open: { openGame(mostUrgentID) })
        case .conversation(let conversation):
            if let peer = peer(conversation.peerID) {
                ActivityConversationRow(
                    itemID: item.id, peer: peer, lastMessage: lastMessage(with: conversation.peerID),
                    isUnread: conversation.isUnread, density: density,
                    open: { navigation.openConversation(peer) }
                )
            }
        }
    }

    /// A challenge's row. The game-over card's offers Reject and Accept in a
    /// game's popover, unless the challenge is unusual, which on the card
    /// includes an automatic handicap.
    private func challengeRow(_ challenge: OGSDirectChallenge, model: ActivityModel.Challenge,
                              itemID: String, after: String?, isGameOverCard: Bool = false) -> some View {
        let content = ActivityRowContents.challenge(challenge, isLive: model.isLive)
        let results = results
        let session = session
        let isUnusual = isGameOverCard ? challenge.isUnusualOnGameOverCard : model.isUnusual
        return ActivityChallengeRow(
            itemID: itemID, challenge: challenge, content: content, density: density,
            actionState: actionState(for: itemID, isUnusual: isUnusual, isGameOverCard: isGameOverCard),
            entry: results.entries[itemID],
            focus: $voiceOverFocus,
            accept: {
                send(.action(.accept), of: itemID) {
                    results.accept(challenge: challenge, isLive: model.isLive, session: session, itemID: itemID,
                                   display: content.display, section: .challengesReceived, after: after)
                }
            },
            reject: {
                send(.action(.reject), of: itemID) {
                    results.reject(challenge: challenge, session: session, itemID: itemID,
                                   display: content.display, section: .challengesReceived, after: after)
                }
            },
            view: { push(itemID) },
            retry: { send(.retry, of: itemID) { results.retry(itemID: itemID) } },
            openGame: openGame,
            isGameOverCard: isGameOverCard
        )
    }

    private func waitingRow(_ target: ActivityListSource.WaitingTarget, waiting: ActivityModel.Waiting,
                            itemID: String, after: String?, now: TimeInterval) -> some View {
        let content = source.content(of: target, waiting: waiting, now: now)
        let results = results
        let session = session
        let withdrawsInPlace: Bool
        let opensCard: Bool
        switch target {
        case .search(let entry):
            withdrawsInPlace = ActivityQuickMatchRow.withdrawsInPlace(entry)
            opensCard = true
        case .openChallenge, .sentChallenge:
            withdrawsInPlace = true
            opensCard = false
        case .rengo:
            withdrawsInPlace = false
            opensCard = true
        }
        let hasElapsedTime: Bool = switch target {
        case .search, .openChallenge: true
        case .sentChallenge, .rengo: false
        }
        return ActivityWaitingRow(
            itemID: itemID, content: content, density: density, withdrawsInPlace: withdrawsInPlace,
            withdrawLabel: ActivityRowContents.withdrawLabel(content, hasElapsedTime: hasElapsedTime),
            hasElapsedTime: hasElapsedTime,
            open: opensCard ? { push(itemID) } : nil,
            actionState: actionState(for: itemID), entry: results.entries[itemID],
            focus: $voiceOverFocus,
            withdraw: {
                send(.action(.withdraw), of: itemID) {
                    switch target {
                    case .search(let entry):
                        results.withdraw(automatch: entry, session: session, itemID: itemID,
                                         display: content.display, section: .waiting, after: after)
                    default:
                        guard let challenge = target.challenge else { return }
                        results.withdraw(challenge: challenge, session: session, itemID: itemID,
                                         display: content.display, section: .waiting, after: after)
                    }
                }
            },
            retry: { send(.retry, of: itemID) { results.retry(itemID: itemID) } },
            openGame: openGame
        )
    }

    /// The cached player, else a friend, else the conversation's own copy,
    /// as Messages' inbox finds them.
    private func peer(_ id: Int) -> OGSUser? {
        if let user = ogs.cachedUsersById[id] ?? ogs.friends.first(where: { $0.id == id }) { return user }
        guard let message = ogs.privateMessagesByPeerId[id]?.first else { return nil }
        return message.from.id == id ? message.from : message.to
    }

    private func lastMessage(with peerID: Int) -> String {
        ogs.privateMessagesByPeerId[peerID]?
            .max { $0.content.timestamp < $1.content.timestamp }?
            .content.message ?? ""
    }

    // MARK: Navigation

    private func push(_ itemID: String) {
        navigation.present(.activityItem(itemID))
    }

    /// Opening a game closes the list first. In New game's stack, closing
    /// New game closes the list.
    private func closeList() {
        if placement != .route {
            nav.closeActivity()
        }
    }

    private func openLiveGame(_ game: Game) {
        closeList()
        if let switchGame {
            switchGame(game)
        } else {
            nav.goToActiveGame(game: game)
        }
    }

    private func openGame(_ gameID: Int) {
        closeList()
        nav.openGame(gameID, closesNewGame: true)
    }

    /// The inbox's route closes the list, and New game in its stack.
    private func openAllMessages() {
        nav.openMessagesInbox()
    }
}

// MARK: - A pushed card

/// A challenge or search from the list as its full card, pushed inside the
/// list's stack. Its actions go through the window's results store, so Back
/// shows their result and a request outlives the card. While the list is
/// offline the card's actions dim, as its rows do. After a success, or once
/// the item has gone, the card pops itself.
struct ActivityItemCard: View {
    let itemID: String
    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var nav: NavigationService
    @EnvironmentObject private var navigation: StackRouter

    var body: some View {
        ActivityItemCardContent(itemID: itemID, ogs: ogs, nav: nav, results: nav.activityResults,
                                lastKnown: nav.activityLastKnown,
                                connection: navigation.activityConnection ?? .neverOffline)
    }
}

private struct ActivityItemCardContent: View {
    let itemID: String
    @ObservedObject var ogs: OGSService
    let nav: NavigationService
    @ObservedObject var results: ActivityResults
    @ObservedObject var lastKnown: ActivityLastKnown
    /// The list's own, which pushed the card.
    @ObservedObject var connection: ConnectionStatusSource
    @EnvironmentObject private var navigation: StackRouter
    /// Where VoiceOver is among the card's controls and its failure line.
    @AccessibilityFocusState private var voiceOverFocus: ActivityFocus?

    private enum Target {
        case challenge(any OGSSubmittedChallenge)
        case search(OGSAutomatchEntry)
    }

    private var source: ActivityListSource { ActivityListSource(ogs: ogs, nav: nav, placement: .sheet) }

    /// Nil once the item has gone, or OGS has confirmed it gone.
    private var target: Target? {
        guard !results.hiddenIDs.contains(itemID) else { return nil }
        switch ActivityItemRef.parse(itemID) {
        case .challenge(let id):
            return ogs.challengesReceived.first { $0.id == id }.map { .challenge($0) }
        case .waiting(let ref):
            switch source.waitingTarget(ref, in: source.openChallenges) {
            case .search(let entry): return .search(entry)
            case let waiting?: return waiting.challenge.map { .challenge($0) }
            case nil: return nil
            }
        case nil:
            return nil
        }
    }

    var body: some View {
        let target = target
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let entry = results.entries[itemID], entry.state == .failed {
                    ActivityEntryLine(
                        itemID: itemID, entry: entry,
                        actionState: ActivityRowActionState(isUnusual: false, isInGamePopover: false,
                                                            isOffline: connection.dimsActivityActions,
                                                            state: entry.state),
                        focus: $voiceOverFocus,
                        retry: { send(.retry) { results.retry(itemID: itemID) } }, openGame: { _ in }
                    )
                    .padding(.horizontal, 4)
                }
                switch target {
                case .challenge(let challenge):
                    ChallengeCell(challenge: challenge)
                        .padding()
                        .background(MessagesStyle.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                case .search(let entry):
                    AutomatchEntryCell(entry: entry)
                        .padding()
                        .background(MessagesStyle.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                case nil:
                    EmptyView()
                }
            }
            .padding()
        }
        .background(MessagesStyle.canvas.ignoresSafeArea())
        .environment(\.activityCellActions, target == nil ? nil : actions)
        .navigationTitle(title(target))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: target == nil, initial: true) { _, gone in
            if gone { pop() }
        }
        .onChange(of: results.entries[itemID]?.state) { _, state in
            if case .succeeded = state { pop() }
        }
        .onReceive(results.$entries) { claimFailure($0) }
    }

    /// Sends one of the card's requests. VoiceOver on the control that sent
    /// it moves to the spinner standing in for it.
    private func send(_ control: ActivityFocusControl, _ request: () -> Void) {
        if let next = ActivityFocus.sending(control, of: itemID, from: voiceOverFocus) {
            voiceOverFocus = next
        }
        request()
    }

    /// A failure shows above the card. When VoiceOver is on the card's
    /// control or spinner as it publishes, the failure takes focus and
    /// claims it, as the list's rows do. A success pops the card, so the
    /// store speaks it.
    private func claimFailure(_ next: [String: ActivityResults.Entry]) {
        guard next[itemID]?.state == .failed, results.entries[itemID]?.state != .failed,
              ActivityFocus.resultTakesFocus(from: voiceOverFocus, row: itemID) else { return }
        voiceOverFocus = .result(itemID)
        results.claim(itemID: itemID)
    }

    private func title(_ target: Target?) -> Text {
        switch target {
        case .search: Text("Quick match")
        case .challenge(let challenge) where challenge.rengo: Text("Rengo")
        default: Text("Challenge")
        }
    }

    private func pop() {
        // A turn later: the push may still be settling.
        DispatchQueue.main.async {
            navigation.remove(.activityItem(itemID))
        }
    }

    /// The card's buttons send through the store for the list on screen,
    /// with the row as it is when the button is tapped.
    private var actions: ActivityCellActions {
        let results = results
        let itemID = itemID
        let source = source
        let session = results.liveSession ?? UUID()
        let current = results.entries[itemID]
        return ActivityCellActions(
            isPending: current?.state.isPending ?? false,
            isOffline: connection.dimsActivityActions,
            focus: $voiceOverFocus,
            itemID: itemID,
            pendingAction: current?.state.isPending == true ? current?.action : nil,
            accept: { challenge in
                send(.action(.accept)) {
                    let row = source.frozen(itemID)
                    results.accept(challenge: challenge, isLive: Self.isLive(challenge), session: session,
                                   itemID: itemID, display: row.display, section: row.section, after: row.after)
                }
            },
            reject: { challenge in
                send(.action(.reject)) {
                    let row = source.frozen(itemID)
                    results.reject(challenge: challenge, session: session, itemID: itemID,
                                   display: row.display, section: row.section, after: row.after)
                }
            },
            withdraw: { challenge in
                send(.action(.withdraw)) {
                    let row = source.frozen(itemID)
                    results.withdraw(challenge: challenge, session: session, itemID: itemID,
                                     display: row.display, section: row.section, after: row.after)
                }
            },
            withdrawSearch: { entry in
                send(.action(.withdraw)) {
                    let row = source.frozen(itemID)
                    results.withdraw(automatch: entry, session: session, itemID: itemID,
                                     display: row.display, section: row.section, after: row.after)
                }
            },
            leave: { challenge in
                send(.action(.leave)) {
                    let row = source.frozen(itemID)
                    results.leave(rengo: challenge, session: session, itemID: itemID,
                                  display: row.display, section: row.section, after: row.after)
                }
            },
            start: { challenge in
                send(.action(.start)) {
                    let row = source.frozen(itemID)
                    results.start(rengo: challenge, isLive: Self.isLive(challenge), session: session,
                                  itemID: itemID, display: row.display, section: row.section, after: row.after)
                }
            }
        )
    }

    /// As the model decides a challenge is live.
    private static func isLive(_ challenge: any OGSChallenge) -> Bool {
        ActivityModel.isRealtime(challenge.game.timeControl, width: challenge.game.width, height: challenge.game.height)
    }
}

/// The list's offline line: "Reconnecting…", "Connecting…" before the
/// window's first connection, or "Can’t reach OGS" with Retry, in the words
/// every carrier of the window's status says (`RootConnectionLine`). It
/// shows under the list's title, and above the composer of a conversation,
/// where the list's own line is out of sight or none shows. At
/// accessibility sizes Retry goes under the words, so neither breaks inside
/// a word.
struct ActivityStatusLine: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var connection: ConnectionStatusSource
    /// The window's socket, which tells a first attempt from a reconnect.
    let socket: OGSWebsocketStatus
    var statusIdentifier = ID.activityStatus
    var retryIdentifier = ID.activityStatusRetry

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize && connection.status.offersRetry
            ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 6))
        layout {
            if connection.status.offersRetry {
                Text("Can’t reach OGS", comment: "Activity: under the title while the app can't connect to OGS; shown with Retry")
                    .accessibilityIdentifier(statusIdentifier)
                // Its own style, as a tint loses to the line's secondary one.
                Button("Retry") { connection.retry() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MessagesStyle.accent)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(retryIdentifier)
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
                Text(verbatim: waitingWords)
                    .accessibilityIdentifier(statusIdentifier)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 32)
    }

    /// "Connecting…" before the window's first connection, while its socket
    /// is on its first attempt; "Reconnecting…" otherwise.
    private var waitingWords: String {
        let words = RootConnectionLine.words(status: connection.status, hasConnected: connection.hasConnected,
                                             socket: socket)
        return words == .connecting ? ActivityBarWords.connecting : ActivityBarWords.reconnecting
    }
}

extension ConnectionStatusSource {
    /// Reconnecting… and Can’t reach OGS both dim the actions that need OGS.
    var dimsActivityActions: Bool {
        switch status {
        case .reconnecting, .unreachable: true
        default: false
        }
    }

    /// For a card without its list, and a conversation outside Activity's
    /// stack: never offline, since it is never shown.
    static let neverOffline = ConnectionStatusSource(
        socketIsConnected: Just(true).eraseToAnyPublisher(),
        path: ConstantNetworkPath.satisfied,
        reconnect: {}
    )
}

// MARK: - New game's list

/// The Activity list inside New game's stack, from its Searching and Rengo
/// links, or as the root of the `waiting-games` capture scene. Each time it
/// is shown it has a session of its own.
struct ActivityRouteList: View {
    @State private var session = UUID()
    /// The window's source; none in the capture scene, which makes its own.
    @Environment(\.connectionStatus) private var connection

    var body: some View {
        ActivityListView(session: session, placement: .route, focus: .top, connection: connection)
    }
}

// MARK: - The window's presenter

/// The window's Activity list as a sheet, for a sheet request: the compact
/// root screens. Done or a swipe closes the request.
struct ActivitySheetPresenter: ViewModifier {
    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var nav: NavigationService
    /// The window's source, which the list says, as every root carrier does.
    @Environment(\.connectionStatus) private var connection

    private var request: Binding<ActivityRequest?> {
        Binding(
            get: { nav.main.activity?.style == .sheet ? nav.main.activity : nil },
            set: { request in
                if request == nil, nav.main.activity?.style == .sheet {
                    nav.main.activity = nil
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: request) { request in
                AppNavigationStack {
                    ActivityListView(session: request.sessionID, placement: .sheet, focus: request.focus,
                                     connection: connection)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { nav.main.activity = nil }
                                    .accessibilityIdentifier(ID.activityDone)
                            }
                        }
                }
                .environmentObject(ogs)
                .environmentObject(nav)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
    }
}

/// The window's Activity list as a popover, for a popover request: regular
/// widths, and over a game, as the Now section and the Mac's Activity
/// command open it there. It hangs off this always-mounted, invisible
/// anchor, placed at the opener's frame as it was tapped, so the popover
/// never depends on its opener staying on screen. An outside tap or Escape
/// closes the request. The in-game control's requests are its own
/// popover's, so this presenter never shows them.
struct ActivityPopoverPresenter: View {
    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var nav: NavigationService
    /// The window's source, which the list says, as every root carrier does.
    @Environment(\.connectionStatus) private var connection
    /// The latest popover request, whose content stays while it closes.
    @State private var latest: ActivityRequest?

    private var current: ActivityRequest? {
        guard let request = nav.main.activity, request.style == .popover,
              request.source != .gameControl else { return nil }
        return request
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { current != nil },
            set: { presented in
                if !presented, current != nil {
                    nav.main.activity = nil
                }
            }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let shown = current ?? latest
            // The anchor is in the window's global space, which this
            // overlay's own frame need not start at. One whose opener went
            // stays where it was, so it is kept inside the overlay.
            let origin = proxy.frame(in: .global).origin
            let anchor = ActivityRequest.anchor(
                (shown?.anchor ?? .zero).offsetBy(dx: -origin.x, dy: -origin.y), inside: proxy.size)
            Color.clear
                .frame(width: anchor.width, height: anchor.height)
                .allowsHitTesting(false)
                .popover(isPresented: isPresented, attachmentAnchor: .rect(.bounds)) {
                    if let shown {
                        popover(shown)
                    }
                }
                .position(x: anchor.midX, y: anchor.midY)
        }
        .onChange(of: current, initial: true) { _, request in
            if let request { latest = request }
        }
    }

    private func popover(_ request: ActivityRequest) -> some View {
        AppNavigationStack {
            ActivityListView(
                session: request.sessionID,
                placement: request.place.gameID == nil ? .popover : .gamePopover,
                focus: request.focus,
                connection: connection
            )
        }
        .environmentObject(ogs)
        .environmentObject(nav)
        .frame(idealWidth: 400, idealHeight: 620)
        .presentationCompactAdaptation(.popover)
        .id(request.sessionID)
    }
}

/// A control that opens the window's Activity list. It keeps its frame in
/// the window's global space as it changes, without redrawing anything, so
/// a tap anchors the list where the control is, and a popover it opened
/// follows it while it stays on screen.
struct ActivityOpenerButton<Label: View>: View {
    let source: ActivityRequest.Source
    var focus: ActivityRequest.Focus = .top
    @ViewBuilder var label: () -> Label

    @EnvironmentObject private var nav: NavigationService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var frame = ActivityOpenerFrame()

    var body: some View {
        Button {
            nav.openActivity(source: source, focus: focus, anchor: frame.value,
                             horizontalSizeClass: horizontalSizeClass)
        } label: {
            label()
        }
        .activityOpenerFrame(frame, source: source)
    }
}

/// An opener's latest frame in the window's global space, held by
/// reference so a new frame redraws nothing. `ActivityOpenerButton` keeps
/// one in `@State` and records it with `activityOpenerFrame(_:source:)`.
final class ActivityOpenerFrame {
    fileprivate(set) var value = CGRect.zero
}

extension View {
    /// Keeps `frame` at this control's frame in the window's global space,
    /// and moves the popover `source` opened, while it is shown, with it.
    func activityOpenerFrame(_ frame: ActivityOpenerFrame, source: ActivityRequest.Source) -> some View {
        modifier(ActivityOpenerFrameRecorder(frame: frame, source: source))
    }
}

private struct ActivityOpenerFrameRecorder: ViewModifier {
    let frame: ActivityOpenerFrame
    let source: ActivityRequest.Source
    @EnvironmentObject private var nav: NavigationService

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { value in
                frame.value = value
                nav.moveActivityAnchor(to: value, from: source)
            }
    }
}

// MARK: - Debug opener

#if DEBUG && MAIN_APP
/// `--surround-activity-open sheet|game-popover`: opens the list once at
/// launch, for UI tests and captures. `sheet` opens a sheet over the
/// offline root, through the window's presenter. `game-popover` opens game
/// 26268404, then, once Game Detail's place has settled and its push has
/// ended, asks that Game Detail to open its control's popover
/// (`NavigationService.debugGameControlPopoverRequests`).
struct ActivityDebugOpener: ViewModifier {
    @EnvironmentObject private var nav: NavigationService
    @State private var awaitsGame = false
    private static var hasOpened = false
    /// Long enough for the push of the game to end, so its bar's items are
    /// in the window when the popover presents from one of them.
    private static let gamePopoverDelay: TimeInterval = 0.8

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Read first, so a malformed flag stops the launch, also in
                // a run whose service isn't an Activity state's.
                _ = SurroundUITestContract.activityActions
                guard let open = SurroundUITestContract.activityOpen, !Self.hasOpened else { return }
                Self.hasOpened = true
                switch open {
                case .sheet:
                    nav.main.activity = ActivityRequest(
                        source: .debug, style: .sheet, place: nav.activityPlaces.place(in: nav.main.rootView))
                case .gamePopover:
                    guard let route = AppRoute(rootView: .home, ogsGameID: SurroundUITestContract.fixtureGameID)
                    else { return }
                    awaitsGame = true
                    nav.requestGameOpen(route)
                }
            }
            .onReceive(nav.activityPlaces.stateDidChange) { state in
                let gameID = SurroundUITestContract.fixtureGameID
                guard awaitsGame, state.places[.home]?.gameID == gameID else { return }
                awaitsGame = false
                let nav = nav
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.gamePopoverDelay) { [weak nav] in
                    nav?.debugGameControlPopoverRequests.send(gameID)
                }
            }
    }
}

// MARK: - Previews

private func activityPreview(_ ogs: OGSService) -> some View {
    AppNavigationStack {
        ActivityListView(session: UUID(), placement: .sheet)
    }
    .environmentObject(ogs)
    .environmentObject(NavigationService())
    .environment(\.surroundAllowsRemoteActivity, false)
    .environment(\.surroundAllowsLocalPersistence, false)
}

#Preview("Activity — Several") {
    activityPreview(OGSService.previewInstance(
        user: OGSUser(username: "HongAnhKhoa", id: 314459),
        openChallengesSent: [OGSChallengeSampleData.sampleOpenChallenge],
        challengesReceived: [OGSChallengeSampleData.sampleChallenge],
        automatchEntries: [OGSAutomatchEntry.sampleEntry]
    ))
}

#Preview("Activity — Nothing waiting") {
    activityPreview(OGSService.previewInstance(
        user: OGSUser(username: "HongAnhKhoa", id: 314459), privateMessages: []
    ))
}
#endif
