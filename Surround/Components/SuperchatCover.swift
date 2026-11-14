//
//  SuperchatCover.swift
//  Surround
//
//  The moderator superchat cover (in-app notices): the one interruption
//  that covers the whole app. One overlay window per scene,
//  from SceneCover, is raised while this window's account has a cover in
//  SuperchatStore. Only the moderator's conversation works under it; the
//  user's live games are listed because their clocks keep running.
//

import SwiftUI

extension NavigationService {
    /// Navigation in this window waits while its account is covered.
    /// Idempotent; set where the root makes its services, before any URL arrives.
    func holdNavigationWhileCovered(by ogs: OGSService, store: SuperchatStore) {
        guard navigationHold == nil else { return }
        navigationHold = NavigationHold(store: store) { [weak ogs] in ogs?.superchatCover != nil }
    }
}

/// Mounts the cover in a window's root, around MainView.
struct SuperchatCoverMount: ViewModifier {
    let ogs: OGSService
    let nav: NavigationService
    let store: SuperchatStore
    // Only what the cover's own hosting window needs, each read on its own:
    // every mount update replaces the cover's root view (SceneCover.apply).
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.surroundAllowsLocalPersistence) private var allowsLocalPersistence
    @Environment(\.surroundAllowsRemoteActivity) private var allowsRemoteActivity
    /// Only the cover state. Observing `ogs` itself would replace the
    /// cover's root view on every socket event.
    @State private var cover: SuperchatCover?
    /// Drops this window's held navigation once its views go. A scene the
    /// system disconnects never lowers its cover, and its NavigationService
    /// is reused when it returns.
    @StateObject private var lifetime: ViewLifetime

    init(ogs: OGSService, nav: NavigationService, store: SuperchatStore) {
        self.ogs = ogs
        self.nav = nav
        self.store = store
        // Covered at the first render, so a window that opens covered raises at attach.
        _cover = State(initialValue: ogs.superchatCover)
        // Made once per view state, so it needs no onAppear.
        _lifetime = StateObject(wrappedValue: {
            let lifetime = ViewLifetime()
            lifetime.release = { [weak nav] in nav?.dropHeldNavigation() }
            return lifetime
        }())
    }

    func body(content: Content) -> some View {
        content
            #if targetEnvironment(macCatalyst)
            // AppKit draws the title bar, toolbar and menus outside the cover window.
            .disabled(cover != nil)
            #endif
            .background {
                SceneCoverAnchor(
                    isRaised: cover != nil,
                    voiceOver: voiceOver(for:),
                    didLower: { DispatchQueue.main.async { nav.replayHeldNavigation() } }
                ) {
                    if let cover, let accountID = ogs.superchatCoverAccountID {
                        SuperchatCoverView(cover: cover, accountID: accountID, store: store, ogs: ogs,
                                           path: allowsRemoteActivity
                                               ? SystemNetworkPathMonitor.shared : ConstantNetworkPath.satisfied,
                                           isFrontmost: isFrontmost)
                            .environmentObject(ogs)
                            .environmentObject(nav)
                            // Its own hosting window gets no SwiftUI environment:
                            // forward what MainView's hosted tabs get, except the
                            // color scheme, which the cover sets itself.
                            .environment(\.openURL, openURL)
                            .environment(\.locale, locale)
                            .environment(\.layoutDirection, layoutDirection)
                            .environment(\.dynamicTypeSize, dynamicTypeSize)
                            .environment(\.scenePhase, scenePhase)
                            .environment(\.surroundAllowsLocalPersistence, allowsLocalPersistence)
                            .environment(\.surroundAllowsRemoteActivity, allowsRemoteActivity)
                    }
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
            .onReceive(ogs.$superchatCover.removeDuplicates()) { cover = $0 }
            .onReceive(store.coverLiftedWithoutDone) { accountID in
                guard accountID == ogs.superchatCoverAccountID else { return }
                // High priority: the lower's screen change comes a main turn
                // later and would cut a normal announcement short.
                nav.announce(.init(.superchatLifted(accountID), audience: .frontmostWindow,
                                   speech: String(localized: "The moderator ended this chat."),
                                   priority: .high))
            }
    }

    /// Read by SceneCover at each rise and lower, with the cover window's traits.
    private func voiceOver(for traits: UITraitCollection) -> SceneCoverVoiceOver {
        guard isFrontmost() else { return .none }
        let isStale = ogs.user?.id != ogs.superchatCoverAccountID
        return SuperchatCoverPresentation.focusesReply(
            isCompactHeight: traits.verticalSizeClass == .compact, isStale: isStale) ? .content : .coverRoot
    }

    /// Only the window the user is in moves VoiceOver.
    private func isFrontmost() -> Bool {
        AppAnnouncer.windows.frontmostWindow.map { $0 == nav.announcerWindow } ?? true
    }
}

/// The cover's content in the scene's cover window: the header with the
/// user's live games, then the moderator's conversation with its end card
/// and reply box.
struct SuperchatCoverView: View {
    private typealias ID = SurroundUITestContract.AccessibilityID

    let cover: SuperchatCover
    let accountID: Int
    let store: SuperchatStore
    @ObservedObject var ogs: OGSService
    let isFrontmost: () -> Bool

    @EnvironmentObject private var context: SceneCoverContext
    @StateObject private var connection: ConnectionStatusSource
    @State private var selectedModeratorID: Int?
    /// The rise whose reply focus was asked for, or skipped (compact height,
    /// a stale window). Each rise asks once, so a chip switch or a rotation
    /// within it never takes focus and VoiceOver back to the field.
    @State private var handledRise: Int?
    @AccessibilityFocusState private var endCardFocused: Bool
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// The two settings Home reads, so the live games' clocks match Home's.
    @AppStorage(SettingKey<String>.gameTheme.name, store: userDefaults)
    private var gameThemeID = SurroundTheme.standard.rawValue
    @AppStorage(SettingKey<Bool>.themeAppliesToWholeApp.name, store: userDefaults)
    private var themeAppliesToWholeApp = true

    init(cover: SuperchatCover, accountID: Int, store: SuperchatStore, ogs: OGSService,
         path: NetworkPathMonitoring, isFrontmost: @escaping () -> Bool) {
        self.cover = cover
        self.accountID = accountID
        self.store = store
        _ogs = ObservedObject(wrappedValue: ogs)
        self.isFrontmost = isFrontmost
        _connection = StateObject(wrappedValue: {
            let source = ConnectionStatusSource(ogs: ogs, path: path)
            // The content exists only while its window is covered, so it is
            // on screen from its first frame (the change handler in `body`
            // corrects this in the background). Knowing the status before
            // that frame keeps a window that opens with no network from
            // focusing a field it disables a moment later.
            source.setVisible(true)
            return source
        }())
    }

    private var presentation: SuperchatCoverPresentation? {
        SuperchatCoverPresentation(cover: cover, selectedModeratorID: selectedModeratorID,
                                   windowUserID: ogs.user?.id, accountID: accountID)
    }

    /// Reconnecting… and Can't reach OGS both read Reconnecting… here.
    private var isOffline: Bool {
        switch connection.status {
        case .reconnecting, .unreachable: true
        default: false
        }
    }

    private var homeTheme: SurroundTheme {
        SurroundTheme.current(storedID: gameThemeID, appliesToWholeApp: themeAppliesToWholeApp)
    }

    /// The user's unfinished live games, your move first, then least time.
    private func liveGames(_ presentation: SuperchatCoverPresentation) -> [Game] {
        guard presentation.showsLiveGames else { return [] }
        let games = ogs.liveGames
        let order = ActivityModel.sortedLiveGames(
            games.compactMap { ActivityModel.LiveGame(game: $0, userID: accountID) })
        return order.compactMap { live in games.first { $0.ogsID == live.id } }
    }

    private func focusRequest(_ presentation: SuperchatCoverPresentation) -> Int? {
        guard context.isRaised, handledRise != context.raiseCount,
              SuperchatCoverPresentation.focusesReply(
                isCompactHeight: verticalSizeClass == .compact, isStale: presentation.isStale)
        else { return nil }
        return context.raiseCount
    }

    var body: some View {
        Group {
            if let presentation {
                layout(presentation)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MessagesStyle.canvas.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ID.superchatCover)
        .modifier(WholeAppThemeAppearance())
        .modifier(FixtureColorScheme(colorScheme: SurroundApp.fixtureColorScheme))
        .onChange(of: context.isRaised && scenePhase != .background, initial: true) { _, visible in
            connection.setVisible(visible)
        }
        .onChange(of: context.raiseCount, initial: true) { _, count in
            // The composer gets this rise's request in the update that runs
            // this; from the next update on it is nil for the rest of the rise.
            if context.isRaised { handledRise = count }
        }
        .onChange(of: presentation?.endCard == .done, initial: true) { _, done in
            if done, context.isRaised, isFrontmost() { endCardFocused = true }
        }
        .onChange(of: cover.moderators.first?.id) {
            // A new start shows the newest moderator.
            selectedModeratorID = nil
        }
    }

    /// One column on a phone; at 660 pt or wider, or across a Duo's
    /// division, the header in the leading pane and the conversation in the
    /// trailing one, so nothing crosses the hinge.
    private func layout(_ presentation: SuperchatCoverPresentation) -> some View {
        GeometryReader { geometry in
            let columns = MessagesColumnLayout(size: geometry.size, divisions: geometry.messagesDivisionFrames)
            // One layout whose children keep their places: turning the device
            // or resizing the window never rebuilds the conversation, so its
            // draft and scroll position stay.
            let stack = columns.usesColumns
                ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            stack {
                headerPane(presentation, columns: columns, height: geometry.size.height)
                separator(columns: columns)
                conversation(presentation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func headerPane(_ presentation: SuperchatCoverPresentation, columns: MessagesColumnLayout,
                            height: CGFloat) -> some View {
        if columns.usesColumns {
            ScrollView {
                header(presentation)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: columns.inboxWidth)
        } else {
            // At most 40% of the height: at large text sizes in landscape
            // the header scrolls and the conversation keeps its room.
            CappedHeight(maxHeight: height * 0.4) {
                ViewThatFits(in: .vertical) {
                    header(presentation)
                    ScrollView { header(presentation) }
                }
            }
        }
    }

    @ViewBuilder
    private func separator(columns: MessagesColumnLayout) -> some View {
        if columns.usesColumns {
            Color.clear
                .frame(width: 1)
                .background {
                    Color(uiColor: .separator)
                        .ignoresSafeArea(.all, edges: .vertical)
                }
                .frame(width: columns.gap)
                .accessibilityHidden(true)
        } else {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(maxWidth: .infinity)
                .frame(height: 1 / displayScale)
                .accessibilityHidden(true)
        }
    }

    // MARK: Header

    private func header(_ presentation: SuperchatCoverPresentation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 22))
                    .foregroundStyle(MessagesStyle.accent)
                    .frame(width: 40, height: 40)
                    .background(MessagesStyle.accent.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    titleRow
                    Text("Surround is locked until the moderator ends this chat. You can read and reply.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(ID.superchatCoverSubtitle)
                }
            }
            if presentation.showsChips {
                chips(selected: presentation.moderator.id)
            }
            ForEach(liveGames(presentation), id: \.ogsID) { game in
                SuperchatCoverLiveGameRow(game: game, user: ogs.user, theme: homeTheme)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        // Clears a windowed iPad's window controls. A plain padding works in
        // both layouts, where a corner offset reached neither into the
        // two-column scroll view nor into a cover window made after its
        // scene's first layout.
        .padding(.leading, context.windowControlsLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The title, and offline Reconnecting… beside it, or under it where the
    /// two don't fit on one line: squeezed side by side, both break inside a word.
    @ViewBuilder private var titleRow: some View {
        let title = Text("Moderator chat")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(ID.superchatCoverTitle)
        if isOffline {
            let status = HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
                Text("Reconnecting…")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(ID.superchatCoverStatus)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    title
                    status
                }
                VStack(alignment: .leading, spacing: 2) {
                    title
                    status
                }
            }
        } else {
            title
        }
    }

    /// One chip per moderator, newest first. The selected one is filled.
    private func chips(selected: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(cover.moderators) { moderator in
                    let isSelected = moderator.id == selected
                    Button {
                        selectedModeratorID = moderator.id
                    } label: {
                        HStack(spacing: 4) {
                            if !moderator.isOn {
                                Image(systemName: "checkmark.circle")
                                    .accessibilityHidden(true)
                            }
                            Text(verbatim: Self.displayName(moderator))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : MessagesStyle.accent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(isSelected ? MessagesStyle.accent : MessagesStyle.paleAccent, in: Capsule())
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityValue(Text("The moderator ended this chat."), isEnabled: !moderator.isOn)
                    .accessibilityIdentifier(ID.superchatCoverModerator(moderator.id))
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// The name OGS sent, or "Moderator" when it sent none.
    private static func displayName(_ moderator: SuperchatModerator) -> String {
        moderator.username.isEmpty ? String(localized: "Moderator", comment: "pause reason") : moderator.username
    }

    // MARK: Conversation

    /// The cached profile, else the conversation's own copy, else one built
    /// from the event.
    private func conversationPeer(for moderator: SuperchatModerator) -> OGSUser {
        if let cached = ogs.cachedUsersById[moderator.id] { return cached }
        if let first = ogs.privateMessagesByPeerId[moderator.id]?.first {
            return first.from.id == moderator.id ? first.from : first.to
        }
        return OGSUser(username: Self.displayName(moderator), id: moderator.id,
                       uiClass: "moderator", isModerator: true)
    }

    private func conversation(_ presentation: SuperchatCoverPresentation) -> some View {
        let peer = conversationPeer(for: presentation.moderator)
        let isEmpty = (ogs.privateMessagesByPeerId[peer.id] ?? []).isEmpty
        return PrivateMessageLog(
            peer: peer, marksThreadAsRead: context.isRaised, showsProfileToolbar: false,
            focusIsSuspended: !context.isRaised,
            composer: PrivateMessageComposerOptions(
                prompt: Text("Reply"), label: Text("Reply to the moderator"),
                fieldIdentifier: ID.superchatCoverReply, sendIdentifier: ID.superchatCoverSend,
                isOffline: isOffline, hidesField: !presentation.showsReplyField,
                focusRequest: focusRequest(presentation),
                didRequestFocus: { if isFrontmost() { context.moveVoiceOverToFocusedElement() } },
                header: endCard(presentation)))
        .overlay {
            // Before the history arrives, and after a relaunch offline.
            if isEmpty, !presentation.isStale {
                Text(verbatim: peer.username)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: End card

    /// Above the reply field, in the composer's header slot, which shows in
    /// a stale window too.
    private func endCard(_ presentation: SuperchatCoverPresentation) -> AnyView? {
        switch presentation.endCard {
        case .none:
            return nil
        case .endedLine:
            // Another moderator is still on: no Done yet.
            return AnyView(
                Text("The moderator ended this chat.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(ID.superchatCoverEnded))
        case .done:
            return AnyView(doneCard)
        }
    }

    private var doneCard: some View {
        // At accessibility sizes Done goes under the line: side by side, the
        // line squeezes Done until its label breaks inside the word.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text("The moderator ended this chat.")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(ID.superchatCoverEnded)
                .accessibilityFocused($endCardFocused)
            Button("Done") {
                store.done(accountID: accountID)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(MessagesStyle.accent)
            .controlSize(.large)
            .accessibilityIdentifier(ID.superchatCoverDone)
        }
        .padding(.vertical, 12)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .background(MessagesStyle.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .systemGray5), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 8)
    }
}

/// One of the user's live games on the cover, with its clock as Home draws
/// it: information only, one element for VoiceOver.
private struct SuperchatCoverLiveGameRow: View {
    @ObservedObject var game: Game
    let user: OGSUser?
    /// The theme Home wears, which the cover's own window doesn't have.
    let theme: SurroundTheme

    var body: some View {
        let facts = HomeGameFacts(game: game, user: user)
        HStack(spacing: 10) {
            if let opponent = facts.opponent {
                MessageAvatar(user: opponent, size: 28)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Your live game with \(Text(verbatim: facts.opponent?.username ?? "").fontWeight(.semibold)) keeps running")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if !facts.turnText.isEmpty {
                    Text(verbatim: facts.turnText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(facts.awaitsUser ? Color.white : MessagesStyle.accent)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 20)
                        .background(facts.awaitsUser ? MessagesStyle.accent : MessagesStyle.paleAccent,
                                    in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HomeClockChip(game: game, facts: facts, color: facts.bottomColor) { EmptyView() }
                .environment(\.surroundTheme, theme)
                .fixedSize()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(MessagesStyle.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(uiColor: .systemGray5), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.superchatCoverLiveGame(game.ogsID ?? 0))
    }
}

/// Its one subview at the height it asks for, at most `maxHeight`. A
/// `.frame(maxHeight:)` would instead grow the header to the full cap.
private struct CappedHeight: Layout {
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let wanted = subview.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? wanted.width, height: min(wanted.height, max(maxHeight, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
