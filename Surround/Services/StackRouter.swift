import SwiftUI
import Combine

/// Lightweight routes. Editable forms and selection callbacks live outside the path.
enum StackRoute: Hashable {
    case homeGame
    case gameHistory
    case historyGame
    case publicGame
    case waitingGames
    case game(Int)
    case playerHistory(playerID: Int, opponentID: Int?)
    case playerActiveGames(Int)
    case playerAbout(Int)
    case profile(playerID: Int, selectionID: UUID?)
    case challenge(UUID)
    case opponentPicker(UUID)
    case messagesConversation(Int)
    case conversation(Int)
}

enum OpponentSelectionAction: Equatable {
    case selectOpponent
    case challengeWithSettings
}

struct OpponentSelection: Identifiable {
    let id: UUID
    let action: OpponentSelectionAction
    let draftID: UUID?
    let selectedUser: () -> OGSUser?
    let onSelect: (OGSUser) -> Void
    var isRoot = false
}

/// The root picker retains this registration while covered by a destination.
/// Destroying that picker releases its callbacks even if the stack survives.
final class RootOpponentSelection {
    let selection: OpponentSelection
    private weak var router: StackRouter?

    init(selection: OpponentSelection, router: StackRouter) {
        self.selection = selection
        self.router = router
    }

    deinit {
        router?.unregisterRootPicker(id: selection.id)
    }
}

/// Retained by the conversation's account/peer owner, without publishing scroll
/// updates through the navigation or inbox hierarchy.
final class PrivateMessageScrollBookmark {
    var messageKey: String?
    var isAtEndOfChat = true

    /// Visibility callbacks do not promise transcript order. Retain the middle
    /// visible message in chronological order, rather than a lazy layout's
    /// estimated leading target or a content offset tied to one width.
    func rememberVisibleMessages(_ visibleKeys: [String], orderedKeys: [String]) {
        guard !isAtEndOfChat else { return }
        let visible = Set(visibleKeys)
        let orderedVisible = orderedKeys.filter { visible.contains($0) }
        guard !orderedVisible.isEmpty else { return }
        messageKey = orderedVisible[orderedVisible.count / 2]
    }
}

/// One instance belongs to one navigation stack, including each presented sheet.
final class StackRouter: ObservableObject {
    private struct ConversationDraftKey: Hashable {
        let accountID: Int
        let peerID: Int
    }
    @Published private var conversationDrafts: [ConversationDraftKey: String] = [:]
    private var conversationScrollBookmarks: [ConversationDraftKey: PrivateMessageScrollBookmark] = [:]

    /// Draft lifetime is independent of the compact or detail navigation path.
    func conversationDraft(for peerID: Int, accountID: Int?) -> Binding<String> {
        guard let accountID else { return .constant("") }
        let key = ConversationDraftKey(accountID: accountID, peerID: peerID)
        return Binding(
            get: { self.conversationDrafts[key, default: ""] },
            set: { self.conversationDrafts[key] = $0 }
        )
    }

    /// Scroll bookmarks share the draft's account/peer lifetime, but scrolling
    /// never publishes a navigation or inbox update.
    func conversationScrollBookmark(for peerID: Int, accountID: Int?) -> PrivateMessageScrollBookmark {
        guard let accountID else { return PrivateMessageScrollBookmark() }
        let key = ConversationDraftKey(accountID: accountID, peerID: peerID)
        if let bookmark = conversationScrollBookmarks[key] { return bookmark }
        let bookmark = PrivateMessageScrollBookmark()
        conversationScrollBookmarks[key] = bookmark
        return bookmark
    }

    /// Compact presentation of Messages' selected root peer. Generic Profile
    /// conversations keep their own route, including when they share this peer.
    func presentMessagesConversation(_ user: OGSUser) {
        guard user.id > 0 else { return }
        users[user.id] = user
        present(.messagesConversation(user.id))
    }

    /// Move only the root conversation's compact presentation across a layout
    /// edge. Covering destinations remain full-width with unchanged history.
    func showMessagesColumns(_ usesColumns: Bool, peer: OGSUser?) {
        if usesColumns {
            if case .messagesConversation = path.first { path.removeFirst() }
        } else if let peer, peer.id > 0 {
            users[peer.id] = peer
            if case .messagesConversation = path.first { return }
            path.insert(.messagesConversation(peer.id), at: 0)
        }
    }

    @Published var path: [StackRoute] = [] {
        didSet { discardInactiveState() }
    }
    private(set) var users: [Int: OGSUser] = [:]
    @Published private(set) var games: [Int: Game] = [:]
    private(set) var activeGamesByPlayer: [Int: ProfileActiveGames] = [:]
    private(set) var aboutProfilesByPlayer: [Int: OGSPlayerProfile] = [:]
    private(set) var drafts: [UUID: ChallengeDraft] = [:]
    private(set) var selections: [UUID: OpponentSelection] = [:]
    @Published private(set) var isActive = false

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
    }

    func present(_ route: StackRoute) {
        guard !path.contains(route) else { return }
        switch route {
        case .homeGame, .gameHistory:
            // Home's game and history are sibling branches. A banner can open
            // the game before the history binding finishes clearing; appending
            // would let that later cleanup remove the new game with its parent.
            path = [route]
        default:
            path.append(route)
        }
    }

    func remove(_ route: StackRoute) {
        guard let index = path.firstIndex(of: route) else { return }
        path.removeSubrange(index...)
    }

    func returnTo(_ route: StackRoute) {
        guard let index = path.firstIndex(of: route) else { return }
        path = Array(path.prefix(through: index))
    }

    func reset(preserving route: StackRoute?) {
        if let route, path.contains(route) { returnTo(route) }
        else { path = [] }
    }

    func openProfile(_ user: OGSUser, selectionID: UUID? = nil) {
        guard user.id > 0 else { return }
        if let selectionID, selections[selectionID] == nil { return }
        users[user.id] = user
        let route = StackRoute.profile(playerID: user.id, selectionID: selectionID)
        if path.contains(route) { returnTo(route) }
        else { present(route) }
    }

    /// Biography links can identify a player before their name is cached.
    /// The destination loads the full profile and supplies its real identity.
    func openProfile(playerID: Int) {
        guard playerID > 0 else { return }
        let route = StackRoute.profile(playerID: playerID, selectionID: nil)
        if path.contains(route) { returnTo(route) }
        else { present(route) }
    }

    func openAbout(_ profile: OGSPlayerProfile) {
        guard profile.id > 0 else { return }
        users[profile.id] = profile.user
        aboutProfilesByPlayer[profile.id] = profile
        let route = StackRoute.playerAbout(profile.id)
        if path.contains(route) { returnTo(route) }
        else { present(route) }
    }

    func openConversation(_ user: OGSUser) {
        guard user.id > 0 else { return }
        users[user.id] = user
        let route = StackRoute.conversation(user.id)
        if path.contains(route) { returnTo(route) }
        else { present(route) }
    }

    /// Opening a game already below the profile returns to that same screen,
    /// retaining its analysis, chat draft and connection owner.
    func openGame(_ game: Game, using navigation: NavigationService) {
        guard let gameID = game.ogsID, gameID > 0 else { return }
        if returnToExistingGame(gameID: gameID, using: navigation) { return }
        games[gameID] = game
        present(.game(gameID))
    }

    /// A biography's game link stays in its originating stack. Cached models
    /// retain their connection owner; an uncached destination loads REST detail.
    func openGame(gameID: Int, using navigation: NavigationService, service: OGSService) {
        guard gameID > 0 else { return }
        if returnToExistingGame(gameID: gameID, using: navigation) { return }
        if let game = service.knownProfileGame(gameID: gameID)
            ?? service.cachedOverviewGame(gameID: gameID) {
            games[gameID] = game
        }
        present(.game(gameID))
    }

    private func returnToExistingGame(gameID: Int, using navigation: NavigationService) -> Bool {
        let existingGames: [(StackRoute, Game?)] = [
            (.homeGame, navigation.home.activeGame),
            (.historyGame, navigation.gameHistory.activeGame),
            (.publicGame, navigation.publicGames.activeGame),
        ]
        if let route = existingGames.first(where: { path.contains($0.0) && $0.1?.ogsID == gameID })?.0 {
            returnTo(route)
            return true
        }
        let route = StackRoute.game(gameID)
        if path.contains(route) {
            returnTo(route)
            return true
        }
        return false
    }

    func updateGame(_ game: Game?, for gameID: Int) {
        guard path.contains(.game(gameID)), let game, game.ogsID == gameID else { return }
        guard games[gameID] !== game else { return }
        games[gameID] = game
    }

    func openHistory(for user: OGSUser, opponentID: Int? = nil) {
        guard user.id > 0, opponentID.map({ $0 > 0 && $0 != user.id }) ?? true else { return }
        users[user.id] = user
        let route = StackRoute.playerHistory(playerID: user.id, opponentID: opponentID)
        if path.contains(route) { returnTo(route) }
        else { present(route) }
    }

    func openActiveGames(_ games: ProfileActiveGames, for user: OGSUser) {
        guard user.id > 0 else { return }
        users[user.id] = user
        activeGamesByPlayer[user.id] = games
        let route = StackRoute.playerActiveGames(user.id)
        if path.contains(route) { returnTo(route) }
        else { present(route) }
    }

    func openChallenge(for user: OGSUser) {
        guard user.id > 0 else { return }
        if let draft = activeDraft {
            draft.opponent = user
            draft.isOpen = false
            returnToDraft(draft)
            return
        }
        var template = ChallengeDraft.defaultChallengeTemplate
        template.challenged = user
        let draft = ChallengeDraft(initialChallenge: template)
        drafts[draft.id] = draft
        path.append(.challenge(draft.id))
    }

    func openOpponentPicker(for proposedDraft: ChallengeDraft) {
        // Every stack edits at most one draft, including a form at its root.
        let draft = activeDraft ?? proposedDraft
        if let route = path.first(where: { route in
            if case .opponentPicker(let id) = route {
                return selections[id]?.draftID == draft.id
            }
            return false
        }) {
            returnTo(route)
            return
        }
        drafts[draft.id] = draft
        let selection = OpponentSelection(
            id: UUID(), action: .selectOpponent, draftID: draft.id,
            selectedUser: { draft.opponent },
            onSelect: { draft.opponent = $0; draft.isOpen = false }
        )
        selections[selection.id] = selection
        path.append(.opponentPicker(selection.id))
    }

    private var activeDraft: ChallengeDraft? { drafts.values.first }

    private func returnToDraft(_ draft: ChallengeDraft) {
        if path.contains(.challenge(draft.id)) {
            returnTo(.challenge(draft.id))
        } else if let selection = selections.values.first(where: { $0.draftID == draft.id }) {
            remove(.opponentPicker(selection.id))
        }
    }

    func openSavedSettingsOpponentPicker(onSelect: @escaping (OGSUser) -> Void) {
        if let route = path.first(where: { route in
            if case .opponentPicker(let id) = route {
                return selections[id]?.action == .challengeWithSettings
            }
            return false
        }) {
            returnTo(route)
            return
        }
        let selection = OpponentSelection(
            id: UUID(), action: .challengeWithSettings, draftID: nil,
            selectedUser: { nil }, onSelect: onSelect
        )
        selections[selection.id] = selection
        path.append(.opponentPicker(selection.id))
    }

    /// Supports a picker that is itself a stack's root (previews and fixture scenes).
    func registerRootPicker(user: Binding<OGSUser?>) -> RootOpponentSelection {
        let selection = OpponentSelection(
            id: UUID(), action: .selectOpponent, draftID: nil,
            selectedUser: { user.wrappedValue }, onSelect: { user.wrappedValue = $0 },
            isRoot: true
        )
        selections[selection.id] = selection
        return RootOpponentSelection(selection: selection, router: self)
    }

    fileprivate func unregisterRootPicker(id: UUID) {
        guard selections[id]?.isRoot == true else { return }
        selections.removeValue(forKey: id)
    }

    func selectOpponent(_ user: OGSUser, selectionID: UUID, viewerID: Int?) {
        guard user.id > 0, user.id != viewerID,
              let selection = selections[selectionID] else { return }
        if let index = path.firstIndex(of: .opponentPicker(selectionID)) {
            // Consume before calling out: saved settings may immediately send a challenge.
            selections.removeValue(forKey: selectionID)
            path = Array(path.prefix(index))
        } else if selection.isRoot {
            // Root pickers only update a binding and stay visible. Keep their
            // selection available for another row or profile inspection.
            path = []
        } else {
            return
        }
        selection.onSelect(user)
    }

    private func discardInactiveState() {
        let playerIDs = Set(path.compactMap { route -> Int? in
            switch route {
            case .profile(let id, _), .conversation(let id), .messagesConversation(let id),
                 .playerHistory(let id, _), .playerActiveGames(let id), .playerAbout(let id): return id
            default: return nil
            }
        })
        users = users.filter { playerIDs.contains($0.key) }
        let gameIDs = Set(path.compactMap { route -> Int? in
            if case .game(let id) = route { return id }; return nil
        })
        games = games.filter { gameIDs.contains($0.key) }
        let activeListIDs = Set(path.compactMap { route -> Int? in
            if case .playerActiveGames(let id) = route { return id }; return nil
        })
        activeGamesByPlayer = activeGamesByPlayer.filter { activeListIDs.contains($0.key) }
        let aboutIDs = Set(path.compactMap { route -> Int? in
            if case .playerAbout(let id) = route { return id }; return nil
        })
        aboutProfilesByPlayer = aboutProfilesByPlayer.filter { aboutIDs.contains($0.key) }
        let pickerIDs = Set(path.compactMap { route -> UUID? in
            if case .opponentPicker(let id) = route { return id }; return nil
        })
        selections = selections.filter { $0.value.isRoot || pickerIDs.contains($0.key) }
        let draftIDs = Set(path.compactMap { route -> UUID? in
            if case .challenge(let id) = route { return id }; return nil
        }).union(selections.values.compactMap(\.draftID))
        drafts = drafts.filter { draftIDs.contains($0.key) }
    }
}

#if MAIN_APP
/// Central switch for reclaiming Duo's empty navigation inset in compact layouts.
enum AppNavigationLayout {
    // The top band still handles system scroll-to-top taps. Compact game modes
    // live in the toolbar; the remaining avatar/team-icon edge overlap is accepted.
    // Intentional kill switch: keep reclamation independently reversible.
    static let reclaimsEmptyVerticalBarTopInset = true
    static let maximumEmptyVerticalBarTopInset: CGFloat = 24
}

private struct IsVerticalToolbarKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Synchronous toolbar orientation supplied by the navigation content host.
    var isVerticalToolbar: Bool {
        get { self[IsVerticalToolbarKey.self] }
        set { self[IsVerticalToolbarKey.self] = newValue }
    }
}

/// Apply inside NavigationStack: its UIKit content host supplies its own safe
/// area, so ignoring the safe area on the outside of the stack has no effect.
/// Keep this private so navigation entry points own the policy, not screens.
struct AppNavigationContentLayout: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            content.modifier(VerticalNavigationContentLayout())
                .modifier(SidebarNavigationContentLayout())
        } else if #available(iOS 27.0, *) {
            content.environment(\.isVerticalToolbar, false)
                .modifier(SidebarNavigationContentLayout())
        } else {
            content.environment(\.isVerticalToolbar, false)
        }
        #else
        content.environment(\.isVerticalToolbar, false)
        #endif
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0)
/// Reclaim only sidebar occlusion inside the navigation content host. UIKit
/// retains its safe area for the title and toolbars outside this body.
@available(iOS 27.0, *)
private struct SidebarNavigationContentLayout: ViewModifier {
    @Environment(\.duoTabContext) private var tabs

    private var preservedInsets: EdgeInsets {
        guard let tabs, tabs.sidebarAvailable else { return EdgeInsets() }
        // Measure outside this content: feeding its own safe-area geometry back
        // into padding can oscillate at pixel boundaries during native layout.
        return tabs.physicalHorizontalInsets
    }

    func body(content: Content) -> some View {
        let usesOverlap = tabs?.sidebarAvailable == true
        content
            .frame(maxWidth: usesOverlap ? .infinity : nil)
            .padding(.leading, usesOverlap ? preservedInsets.leading : 0)
            .padding(.trailing, usesOverlap ? preservedInsets.trailing : 0)
            .ignoresSafeArea(.container, edges: usesOverlap ? .horizontal : [])
    }
}

private struct AppTabBarVisibility: ViewModifier {
    @Environment(\.duoTabContext) private var tabs
    @State private var owner = UUID()
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .toolbar(hidden ? .hidden : .automatic, for: .tabBar)
            .onAppear {
                if #available(iOS 27.0, *) {
                    tabs?.setTabBarHidden(hidden, owner: owner)
                }
            }
            .onChange(of: hidden) { _, value in
                if #available(iOS 27.0, *) {
                    tabs?.setTabBarHidden(value, owner: owner)
                }
            }
            .onDisappear {
                if #available(iOS 27.0, *) {
                    tabs?.removeTabBarHiddenRequest(owner: owner)
                }
            }
    }
}
#endif

extension View {
    /// SwiftUI shells keep their native preference; the owned Duo container
    /// receives the same request without inspecting generated controllers.
    func appTabBarHidden(_ hidden: Bool) -> some View {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0)
        modifier(AppTabBarVisibility(hidden: hidden))
        #else
        toolbar(hidden ? .hidden : .automatic, for: .tabBar)
        #endif
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
@available(iOS 27.1, *)
private struct VerticalNavigationContentLayout: ViewModifier {
    @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var hasEmptyTopBand = false

    func body(content: Content) -> some View {
        let reclaimsTop = AppNavigationLayout.reclaimsEmptyVerticalBarTopInset
            // Regular game layouts can put the playable board at the top.
            // Preserve their inset so top-row touches remain available.
            && horizontalSizeClass == .compact
            && toolbarVerticalEdge != nil && hasEmptyTopBand

        content
            .environment(\.isVerticalToolbar, toolbarVerticalEdge != nil)
            .ignoresSafeArea(.container, edges: reclaimsTop ? .top : [])
            // Observe outside ignoresSafeArea to retain the original inset,
            // without a GeometryReader changing the content's ideal size.
            .onGeometryChange(for: Bool.self) { geometry in
                // iOS 27.1 leaves an empty navigation bar at y=24 even when
                // its height and the window's top inset are zero. Keep larger
                // insets for titles/search. The bound is observed behavior,
                // not an Apple contract or a fixed offset to subtract.
                let topInset = geometry.safeAreaInsets.top
                guard topInset > 0,
                      topInset <= AppNavigationLayout.maximumEmptyVerticalBarTopInset
                else { return false }
                let topBand = CGRect(x: 0, y: -topInset,
                                     width: geometry.size.width, height: topInset)
                return !geometry.reservedRegions(kind: .occlusion).contains { region in
                    let frame = region.frame
                    let margins = region.margins
                    let reservedFrame = CGRect(
                        x: frame.minX - margins.leading,
                        y: frame.minY - margins.top,
                        width: frame.width + margins.leading + margins.trailing,
                        height: frame.height + margins.top + margins.bottom
                    )
                    return reservedFrame.intersects(topBand)
                }
            } action: { hasEmptyTopBand = $0 }
    }
}
#endif

/// Keep SDK-specific toolbar presentation alongside the navigation policy.
/// Callers use `isVerticalToolbar` and need no availability branches.
struct AppVerticalToolbarGroup<Content: View>: ToolbarContent {
    var separatesNextGroup: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some ToolbarContent {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            ToolbarItemGroup(placement: .bottomBar, content: content)
                .axisBehavior(.verticalPreferred)
                .visibilityPriority(.high)
            if separatesNextGroup {
                ToolbarSpacer(.fixed, placement: .bottomBar)
            }
        }
        #else
        ToolbarItem(placement: .bottomBar) { EmptyView() }
        #endif
    }
}

/// Direct-view pushes need the same content layout as the stack's routed pushes.
/// Use a value-based NavigationLink for StackRoute, or this wrapper for views.
struct AppNavigationLink<Label: View, Destination: View>: View {
    private let destination: () -> Destination
    private let label: Label

    init(destination: Destination, @ViewBuilder label: () -> Label) {
        self.destination = { destination }
        self.label = label()
    }

    init(@ViewBuilder destination: @escaping () -> Destination,
         @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }

    var body: some View {
        NavigationLink {
            destination()
                .modifier(AppNavigationContentLayout())
        } label: {
            label
        }
    }
}

extension View {
    /// Boolean destinations have their own navigation content host, independent
    /// of the root and StackRoute destination builder in AppNavigationStack.
    func appNavigationDestination<Destination: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        navigationDestination(isPresented: isPresented) {
            destination()
                .modifier(AppNavigationContentLayout())
        }
    }
}

private struct OwningStackRouteKey: EnvironmentKey {
    static let defaultValue: StackRoute? = nil
}

extension EnvironmentValues {
    var owningStackRoute: StackRoute? {
        get { self[OwningStackRouteKey.self] }
        set { self[OwningStackRouteKey.self] = newValue }
    }
}

/// Owns the root and StackRoute destination layout. Direct-view and Boolean
/// pushes use AppNavigationLink/appNavigationDestination for the same policy.
struct AppNavigationStack<Content: View>: View {
    @EnvironmentObject private var nav: NavigationService
    #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0)
    @Environment(\.duoTabContext) private var duoTabContext
    #endif
    @StateObject private var navigation = StackRouter()
    @State private var isVisible = false
    var rootView: RootView? = nil
    init(rootView: RootView? = nil, router: StackRouter? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.rootView = rootView
        _navigation = StateObject(wrappedValue: router ?? StackRouter())
        self.content = content
    }

    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack(path: $navigation.path) {
            content()
                .modifier(AppNavigationContentLayout())
                .environment(\.owningStackRoute, nil)
                .navigationDestination(for: StackRoute.self) { route in
                    destination(for: route)
                        .modifier(AppNavigationContentLayout())
                        .environment(\.owningStackRoute, route)
                }
        }
        .overlay(alignment: .bottom) {
            if navigation.isActive { FriendshipNoticeBanner() }
        }
        .environmentObject(navigation)
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0)
        // Presented stacks have their own safe area and chrome ownership.
        .environment(\.duoTabContext, rootView == nil ? nil : duoTabContext)
        #endif
        .environment(\.openPlayerProfile) { navigation.openProfile($0) }
        .environment(\.openPlayerConversation) { navigation.openConversation($0) }
        .onAppear {
            isVisible = true
            updateActivity()
        }
        .onDisappear {
            isVisible = false
            updateActivity()
        }
        .onChange(of: nav.main.rootView) { _, _ in updateActivity() }
        .onChange(of: nav.navigationResetID) { _, _ in
            let route: StackRoute? = switch nav.preservingActiveGameOnReset {
            case .home: .homeGame
            case .publicGames: .publicGame
            default: nil
            }
            navigation.reset(preserving: route)
        }
        .onChange(of: nav.pendingGameOpen?.id) { _, _ in
            switch nav.pendingGameOpen?.rootView {
            case .home: navigation.returnTo(.homeGame)
            case .publicGames: navigation.returnTo(.publicGame)
            default: break
            }
        }
    }

    private func updateActivity() {
        navigation.setActive(isVisible && (rootView == nil || rootView == nav.main.rootView))
    }

    @ViewBuilder
    private func destination(for route: StackRoute) -> some View {
        switch route {
        case .homeGame:
            GameDetailView(currentGame: $nav.home.activeGame,
                           allowsActiveGamesCarousel: nav.home.activeGameShowsCarousel)
        case .gameHistory:
            GameHistoryView()
        case .historyGame:
            GameDetailView(currentGame: $nav.gameHistory.activeGame,
                           allowsActiveGamesCarousel: false)
        case .publicGame:
            GameDetailView(currentGame: $nav.publicGames.activeGame)
        case .waitingGames:
            WaitingGamesView()
        case .game(let gameID):
            StackGameDestination(gameID: gameID)
        case .playerHistory(let playerID, let opponentID):
            if let player = navigation.users[playerID] {
                GameHistoryView(player: player, opponentID: opponentID,
                                perspectivePlayerID: opponentID ?? playerID)
            }
        case .playerActiveGames(let playerID):
            if let player = navigation.users[playerID],
               let games = navigation.activeGamesByPlayer[playerID] {
                PlayerActiveGamesView(player: player, games: games)
            }
        case .profile(let playerID, let selectionID):
            PlayerProfileView(playerID: playerID, seedUser: navigation.users[playerID],
                              selectionID: selectionID)
        case .playerAbout(let playerID):
            if let profile = navigation.aboutProfilesByPlayer[playerID] {
                PlayerAboutView(profile: profile)
            }
        case .messagesConversation(let playerID), .conversation(let playerID):
            if let user = navigation.users[playerID] {
                MessagesConversationView(peer: user)
            }
        case .challenge(let id):
            if let draft = navigation.drafts[id] {
                CustomGameForm(onChallengeCreated: { navigation.remove(.challenge(id)) },
                               draft: draft,
                               onChooseOpponent: { navigation.openOpponentPicker(for: draft) })
                    .navigationTitle("Challenge")
                    .navigationBarTitleDisplayMode(.inline)
            }
        case .opponentPicker(let id):
            if let selection = navigation.selections[id] {
                UserSelectionView(selection: selection)
                    .navigationTitle("Select your opponent ")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

/// Keeps a linked game's fetch and retry local to the game destination. The
/// router owns the loaded model so covering it with Profile retains its state.
private struct StackGameDestination: View {
    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var navigation: StackRouter
    let gameID: Int
    @State private var attempt = 0
    @State private var failed = false

    private struct LoadIdentity: Equatable {
        let gameID: Int
        let accountID: Int?
        let attempt: Int
    }

    private var loadIdentity: LoadIdentity {
        LoadIdentity(gameID: gameID, accountID: ogs.user?.id, attempt: attempt)
    }

    var body: some View {
        Group {
            if navigation.games[gameID] != nil {
                GameDetailView(currentGame: Binding(
                    get: { navigation.games[gameID] },
                    set: { navigation.updateGame($0, for: gameID) }
                ), allowsActiveGamesCarousel: false)
            } else if failed {
                ContentUnavailableView {
                    Label("Unable to load game", systemImage: "squareshape.split.3x3")
                        .accessibilityIdentifier("profile.linkedGame.error")
                } description: {
                    Text("Check your connection and try again. The game may no longer be available.")
                } actions: {
                    Button("Try again") { attempt += 1 }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("profile.linkedGame.retry")
                }
                .navigationTitle("Game")
            } else {
                ProgressView("Loading game…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle("Game")
                    .accessibilityIdentifier("profile.linkedGame.loading")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadIdentity) { await loadGame(for: loadIdentity) }
    }

    private func loadGame(for identity: LoadIdentity) async {
        guard navigation.games[gameID] == nil else { return }
        failed = false
        do {
            for try await game in ogs.getGameDetail(gameID: gameID).values {
                try Task.checkCancellation()
                guard identity == loadIdentity else { return }
                navigation.updateGame(game, for: gameID)
                return
            }
            if !Task.isCancelled { failed = true }
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

/// Bridges existing external game requests to the stack's explicit routes.
/// Profile/Challenge use the same path, so adding them cannot discard a game ancestor.
private struct StackDestinationBinding: ViewModifier {
    @EnvironmentObject private var navigation: StackRouter
    @Binding var isPresented: Bool
    let route: StackRoute

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented, initial: true) { _, presented in
                if presented { navigation.present(route) }
                else { navigation.remove(route) }
            }
            .onChange(of: navigation.path) { oldPath, newPath in
                if oldPath.contains(route), !newPath.contains(route) {
                    isPresented = false
                }
            }
    }
}

extension View {
    func stackDestination(isPresented: Binding<Bool>, route: StackRoute) -> some View {
        modifier(StackDestinationBinding(isPresented: isPresented, route: route))
    }
}
#endif
