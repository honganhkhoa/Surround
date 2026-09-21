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
    case profile(playerID: Int, selectionID: UUID?)
    case challenge(UUID)
    case opponentPicker(UUID)
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

/// One instance belongs to one navigation stack, including each presented sheet.
final class StackRouter: ObservableObject {
    @Published var path: [StackRoute] = [] {
        didSet { discardInactiveState() }
    }
    private(set) var users: [Int: OGSUser] = [:]
    @Published private(set) var games: [Int: Game] = [:]
    private(set) var activeGamesByPlayer: [Int: ProfileActiveGames] = [:]
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
        let existingGames: [(StackRoute, Game?)] = [
            (.homeGame, navigation.home.activeGame),
            (.historyGame, navigation.gameHistory.activeGame),
            (.publicGame, navigation.publicGames.activeGame),
        ]
        if let route = existingGames.first(where: { path.contains($0.0) && $0.1?.ogsID == gameID })?.0 {
            returnTo(route)
            return
        }
        let route = StackRoute.game(gameID)
        if path.contains(route) {
            returnTo(route)
        } else {
            games[gameID] = game
            present(route)
        }
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
            case .profile(let id, _), .conversation(let id),
                 .playerHistory(let id, _), .playerActiveGames(let id): return id
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
private struct OwningStackRouteKey: EnvironmentKey {
    static let defaultValue: StackRoute? = nil
}

extension EnvironmentValues {
    var owningStackRoute: StackRoute? {
        get { self[OwningStackRouteKey.self] }
        set { self[OwningStackRouteKey.self] = newValue }
    }
}

struct AppNavigationStack<Content: View>: View {
    @EnvironmentObject private var nav: NavigationService
    @StateObject private var navigation = StackRouter()
    @State private var isVisible = false
    var rootView: RootView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack(path: $navigation.path) {
            content()
                .environment(\.owningStackRoute, nil)
                .navigationDestination(for: StackRoute.self) { route in
                    destination(for: route)
                        .environment(\.owningStackRoute, route)
                }
        }
        .overlay(alignment: .bottom) {
            if navigation.isActive { FriendshipNoticeBanner() }
        }
        .environmentObject(navigation)
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
            GameDetailView(currentGame: Binding(
                get: { navigation.games[gameID] },
                set: { navigation.updateGame($0, for: gameID) }
            ), allowsActiveGamesCarousel: false)
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
            if let user = navigation.users[playerID] {
                PlayerProfileView(user: user, selectionID: selectionID)
            }
        case .conversation(let playerID):
            if let user = navigation.users[playerID] {
                PrivateMessageLog(peer: user)
                    .navigationTitle(user.username)
                    .navigationBarTitleDisplayMode(.inline)
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
