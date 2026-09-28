//
//  CorrespondenceGamesView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 8/26/20.
//

import SwiftUI
import Combine

struct GameDetailView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isVerticalToolbar) private var isVerticalToolbar
    @Environment(\.owningStackRoute) private var owningStackRoute
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService

    @Binding var currentGame: Game?
    @State var activeGames: [Game] = []
    @State var activeGameByOGSID: [Int: Game] = [:]
    @State private var detailConnection = GameDetailConnectionCoordinator()

    /// Finished-game history routes do not offer the active-game picker.
    var allowsActiveGamesCarousel = true
    
    @State var showSettings = false
    @State private var showsActiveGames = false
    @State private var compactBottomBarWasVisible = false
    @State var attachedKeyboardVisible = false
    @State var zenMode = false
    @State var interaction = GameDetailInteraction()
    @State private var showsCompactChatBoard = true
    @State private var variationShareDraft: VariationShareDraft?
    @State private var selectedChatChannel = OGSChatSendChannel.main
    @EnvironmentObject private var stackRouter: StackRouter
    #if DEBUG && MAIN_APP
    @State private var animationObservationID = UUID()
    #endif

    @ObservedObject var settings = userDefaults
    
    private var compactDisplayMode: GameDetailPanel {
        get { interaction.panel }
        nonmutating set { interaction.selectPanel(newValue) }
    }

    private var analyzeMode: Bool { interaction.isAnalyzing }

    private var onTurnActiveGameCount: Int {
        activeGames.filter(ogs.isOnUserTurn).count
    }

    private var activeGamesButton: some View {
        Button {
            showsActiveGames = true
        } label: {
            Label("Active games", systemImage: "square.grid.2x2")
        }
        .accessibilityValue(Text(verbatim: String(onTurnActiveGameCount)))
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.gameActiveGamesButton
        )
        .popover(isPresented: $showsActiveGames) {
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    if currentGame?.gameData?.timeControl.speed?.isRealtime == true {
                        Text("Live games")
                    } else {
                        Text("Correspondence games")
                    }
                }
                .font(.headline)
                .padding(.horizontal)
                ActiveGamesCarousel(
                    currentGame: $currentGame,
                    activeGames: activeGames,
                    onSelectGame: { showsActiveGames = false }
                )
            }
            .padding(.vertical)
            .frame(idealWidth: 420)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(
                SurroundUITestContract.AccessibilityID.gameActiveGamesPopover
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var analyzeModeBinding: Binding<Bool> {
        Binding(get: { interaction.isAnalyzing },
                set: { interaction.setAnalyzing($0) })
    }

    private var effectiveAttachedKeyboardVisible: Bool {
        #if DEBUG && MAIN_APP
        attachedKeyboardVisible
            || SurroundUITestContract
                .simulatesAttachedSoftwareKeyboardVisible
        #else
        attachedKeyboardVisible
        #endif
    }

    var canShowActiveGames: Bool {
        guard allowsActiveGamesCarousel else {
            return false
        }
        guard !zenMode else {
            return false
        }
        if let currentGame = currentGame {
            return currentGame.isUserPlaying && !activeGames.isEmpty
        } else {
            return false
        }
    }
    
    func updateDetailOfCurrentGameIfNecessary() {
        guard let requestedGame = currentGame, requestedGame.ogsID != nil else {
            detailConnection.release()
            return
        }

        let gameBinding = $currentGame
        detailConnection.observeLifetime(in: stackRouter, route: owningStackRoute) { [weak service = ogs] canonicalGame in
            guard gameBinding.wrappedValue?.ID == canonicalGame.ID else { return }
            if gameBinding.wrappedValue !== canonicalGame {
                gameBinding.wrappedValue = canonicalGame
            }
            if canonicalGame.ogsRawData == nil {
                service?.updateDetailsOfConnectedGame(game: canonicalGame)
            }
        }
        let canonicalGame = detailConnection.connect(to: requestedGame, using: ogs)
        if canonicalGame !== requestedGame {
            currentGame = canonicalGame
        }
    }
    
    func updateActiveGameList() {
        if let gameSpeed = currentGame?.gameData?.timeControl.speed {
            if gameSpeed == .correspondence {
                if Set(self.activeGames.map { $0.ogsID }) == Set(ogs.sortedActiveCorrespondenceGames.map { $0.ogsID }) {
                    return
                }
                self.activeGames = []
                for game in ogs.sortedActiveCorrespondenceGames {
                    self.activeGames.append(game)
                    if let ogsID = game.ogsID {
                        self.activeGameByOGSID[ogsID] = game
                    }
                }
            } else if gameSpeed.isRealtime {
                if Set(self.activeGames.map { $0.ogsID }) == Set(ogs.liveGames.map { $0.ogsID }) {
                    return
                }
                self.activeGames = []
                for game in ogs.liveGames {
                    self.activeGames.append(game)
                    if let ogsID = game.ogsID {
                        self.activeGameByOGSID[ogsID] = game
                    }
                }
            }
        }
    }
        
    func goToNextGame() {
        let candidates: [Game]
        if let currentIndex = activeGames.firstIndex(where: {
            $0.ID == currentGame?.ID
        }) {
            candidates = Array(activeGames.dropFirst(currentIndex + 1))
                + Array(activeGames.prefix(currentIndex))
        } else {
            candidates = activeGames
        }

        if let nextGame = candidates.first(where: ogs.isOnUserTurn) {
            withAnimation {
                currentGame = nextGame
            }
        }
    }
    
    func enterZenMode() {
        showsActiveGames = false
        withAnimation {
            zenMode = true
        }
    }
    
    func exitZenMode() {
        withAnimation {
            zenMode = false
        }
    }
    
    private func gameBody(
        compact: Bool, geometry: GeometryProxy, remainingHeight: CGFloat
    ) -> some View {
        let horizontal = geometry.size.width
            + geometry.safeAreaInsets.leading
            + geometry.safeAreaInsets.trailing + 100
            > geometry.size.height + geometry.safeAreaInsets.top
                + geometry.safeAreaInsets.bottom

        return VStack(alignment: .leading, spacing: compact ? nil : 0) {
            // Keep this view in one structural slot as the size class changes,
            // so folding preserves analysis and pending board moves.
            if let currentGame {
                SingleGameView(
                    compact: compact,
                    compactBoardSize: min(geometry.size.width, geometry.size.height),
                    game: currentGame,
                    reducedPlayerInfoVerticalPadding: remainingHeight < 0,
                    goToNextGame: goToNextGame,
                    horizontal: horizontal,
                    zenMode: $zenMode,
                    exitZenMode: exitZenMode,
                    attachedKeyboardVisible: effectiveAttachedKeyboardVisible,
                    interaction: $interaction,
                    showsCompactChatBoard: $showsCompactChatBoard,
                    variationShareDraft: $variationShareDraft,
                    selectedChatChannel: $selectedChatChannel
                )
            }
        }
    }

    private var compactLayout: Bool {
        var compactLayout = true
        #if os(iOS)
        compactLayout = horizontalSizeClass == .compact
        #endif
        #if DEBUG && MAIN_APP
        if SurroundUITestContract.forcesCompactGameLayout {
            compactLayout = true
        }
        #endif
        return compactLayout
    }

    private var navigationBarHidden: Bool {
        (effectiveAttachedKeyboardVisible && !compactLayout) || zenMode
    }

    var body: some View {
        GeometryReader { geometry in
            content(geometry: geometry)
        }
        .ignoresSafeArea(edges: compactLayout && navigationBarHidden ? [.top] : [])
    }

    private func content(geometry: GeometryProxy) -> some View {
        guard let currentGame = self.currentGame else {
            return AnyView(EmptyView())
        }

        let controlRowHeight = NSString(string: "Ilp").boundingRect(
            with: geometry.size,
            attributes: [.font: UIFont.preferredFont(forTextStyle: .title2)],
            context: nil
        ).size.height
        let playerInfoHeight: CGFloat = 64 + 64 - 10 + 15 * 2
            + PlayersBannerView.additionalPhoneVerticalPadding * 2
        let remainingHeight = geometry.size.height
            - min(geometry.size.width, geometry.size.height)
            - controlRowHeight - playerInfoHeight - 20
        // Decide during layout, including the first pass. Remember only whether
        // the previous pass already reserved the horizontal bar's height;
        // this hysteresis avoids toggling as the bar consumes/releases space.
        let hasRoomForActiveGamesButton = remainingHeight
            >= (compactBottomBarWasVisible ? 0 : 70)
        let showsActiveGamesButton = canShowActiveGames
            && (!compactLayout || isVerticalToolbar || hasRoomForActiveGamesButton)
        let showsCompactBottomBar = compactLayout && !isVerticalToolbar
            && showsActiveGamesButton
        var title = currentGame.gameName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        if title.isEmpty, currentGame.isUserPlaying,
           let userColor = currentGame.userStoneColor,
           let opponent = currentGame.currentPlayer(with: userColor.opponentColor()) {
            title = "vs \(opponent.usernameAndRank)"
            if currentGame.rengo {
                if let opponentTeam = currentGame.gameData?.rengoTeams?[userColor.opponentColor()] {
                    if opponentTeam.count > 1 {
                        title += " +\(opponentTeam.count - 1)"
                    }
                }
            }
        }
        #if targetEnvironment(macCatalyst)
        let navigationTitle = title.isEmpty
            ? String(
                localized: "Game",
                comment: "Fallback game window title"
            )
            : title
        #else
        let navigationTitle = navigationBarHidden ? "" : title
        #endif
        
        let result = gameBody(
            compact: compactLayout, geometry: geometry,
            remainingHeight: remainingHeight
        )
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        .onChange(of: showsCompactBottomBar, initial: true) { _, isVisible in
            compactBottomBarWasVisible = isVisible
        }
        .onChange(of: showsActiveGamesButton) { _, isVisible in
            if !isVisible { showsActiveGames = false }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.gameDetail(currentGame)
        )
        .background(
            colorScheme == .dark ?
                Color(UIColor.systemGray5).edgesIgnoringSafeArea(.bottom) :
                Color.white.edgesIgnoringSafeArea(.bottom)
        )
        .sheet(isPresented: self.$showSettings) {
            AppNavigationStack {
                VStack {
                    GameplaySettings()
                    Spacer()
                }
                .accessibilityIdentifier(
                    SurroundUITestContract.compatibilityScene == .gameOptions
                        ? SurroundUITestContract.AccessibilityID
                            .compatibilityScreen(.gameOptions)
                        : SurroundUITestContract.AccessibilityID
                            .screenGameOptions
                )
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: { self.showSettings = false }) {
                            Text("Done", comment: "close button for in-game settings").bold()
                        }
                    }
                }
            }
        }
        // Catalyst keeps this useful as the Mac window title even when Zen
        // mode hides the in-window navigation chrome.
        .navigationTitle(navigationTitle)
        .navigationBarHidden(navigationBarHidden && !compactLayout)
        .navigationBarBackButtonHidden(navigationBarHidden)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            updateActiveGameList()
            updateDetailOfCurrentGameIfNecessary()
        }
        .onChange(of: currentGame) { oldGame, newGame in
            if newGame.ID != oldGame.ID {
                showSettings = false
                showsActiveGames = false
                if GameDetailDisplayReset.restoresDisplayDefaults(
                    from: oldGame.gameData?.timeControl.speed,
                    to: newGame.gameData?.timeControl.speed
                ) {
                    zenMode = false
                    compactDisplayMode = .playerInfo
                    showsCompactChatBoard = true
                }
                variationShareDraft = nil
                selectedChatChannel = .main
                updateActiveGameList()
                updateDetailOfCurrentGameIfNecessary()
            }
        }
        .onChange(of: ogs.user?.id) { _, _ in
            showsActiveGames = false
            variationShareDraft = nil
            selectedChatChannel = .main
        }
        .onReceive(ogs.$sortedActiveCorrespondenceGames) { _ in
            DispatchQueue.main.async {
                updateActiveGameList()
            }
        }
        .onReceive(ogs.$liveGames) { _ in
            DispatchQueue.main.async {
                updateActiveGameList()
            }
        }
        .onReceive(SystemPlatformServices.shared.keyboardWillChangeFramePublisher) { notification in
            self.attachedKeyboardVisible = SystemPlatformServices.shared
                .isAttachedSoftwareKeyboardVisible(from: notification)
            #if DEBUG && MAIN_APP
            SurroundAnimationDiagnostics.record(
                "keyboard.attachedClassification", ownerID: animationObservationID,
                focusRequestID: variationShareDraft?.focusRequestID,
                fields: ["attached": String(attachedKeyboardVisible)],
                deduplicated: true
            )
            #endif
        }
        #if DEBUG && MAIN_APP
        .surroundAnimationObservation(
            "game.detail", ownerID: animationObservationID,
            focusRequestID: variationShareDraft?.focusRequestID
        )
        .surroundAnimationKeyboardObservations(ownerID: animationObservationID)
        .surroundAnimationState(
            "detail.visibilityState",
            value: "attachedKeyboard=\(effectiveAttachedKeyboardVisible);navigationHidden=\(navigationBarHidden);compact=\(compactLayout)",
            ownerID: animationObservationID,
            focusRequestID: variationShareDraft?.focusRequestID
        )
        #endif
        
        return AnyView(
            result.toolbar {
                if compactLayout {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if !navigationBarHidden {
                            if compactDisplayMode == .chat {
                                Button {
                                    withAnimation {
                                        showsCompactChatBoard.toggle()
                                    }
                                } label: {
                                    if showsCompactChatBoard {
                                        Label(
                                            "Hide main board",
                                            image: "custom.squareshape.split.3x3.slash"
                                        )
                                    } else {
                                        Label(
                                            "Show main board",
                                            image: "custom.squareshape.split.3x3.badge.eye"
                                        )
                                    }
                                }
                                .accessibilityIdentifier(
                                    showsCompactChatBoard
                                        ? SurroundUITestContract
                                            .AccessibilityID
                                            .gameChatBoardHide
                                        : SurroundUITestContract
                                            .AccessibilityID
                                            .gameChatBoardShow
                                )
                            } else if !analyzeMode {
                                Button(action: enterZenMode) {
                                    Label("Zen mode", systemImage: "arrow.up.backward.and.arrow.down.forward")
                                }
                                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameZenEnter)
                                .surroundUITestZenShortcut()
                            }
                            Button(action: { self.showSettings = true }) {
                                Label("Options", systemImage: "gearshape.2")
                            }
                            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameOptions)
                        } else if zenMode {
                            Button(action: exitZenMode) {
                                Label("Exit Zen mode", systemImage: "arrow.down.forward.and.arrow.up.backward")
                            }
                            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameZenExit)
                            .surroundUITestZenShortcut()
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Toggle(isOn: analyzeModeBinding.animation()) {
                            if currentGame.analysisAvailable {
                                Label("Toggle analyze mode", systemImage: "arrow.triangle.branch")
                                    .labelStyle(IconOnlyLabelStyle())
                            } else {
                                Label("Toggle playback mode", systemImage: "arrow.left.and.right")
                                    .labelStyle(IconOnlyLabelStyle())
                            }
                        }
                        .accessibilityIdentifier(
                            SurroundUITestContract.AccessibilityID.gameAnalyzeToggle
                        )
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: enterZenMode) {
                            Label("Zen mode", systemImage: "arrow.up.backward.and.arrow.down.forward")
                        }
                        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameZenEnter)
                        .surroundUITestZenShortcut()
                        .disabled(analyzeMode)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { self.showSettings = true }) {
                            Label("Options", systemImage: "gearshape.2")
                        }
                        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameOptions)
                    }
                }
                if showsActiveGamesButton {
                    ToolbarItem(placement: .bottomBar) { activeGamesButton }
                    #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
                    if #available(iOS 26.0, *) {
                        ToolbarSpacer(.flexible, placement: .bottomBar)
                    } else {
                        ToolbarItem(placement: .bottomBar) { Spacer() }
                    }
                    #else
                    ToolbarItem(placement: .bottomBar) { Spacer() }
                    #endif
                }
            }
            // Keep the bottom mode group above the Active Games item.
            .modifier(GameToolbarLayout(
                game: currentGame,
                interaction: $interaction,
                compact: compactLayout,
                navigationBarHidden: navigationBarHidden,
                showsActiveGamesButton: showsActiveGamesButton
            ))
            .toolbar(compactLayout || zenMode ? .hidden : .automatic, for: .tabBar)
        )
    }
}

private struct CompactGameModesInToolbarKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var compactGameModesInToolbar: Bool {
        get { self[CompactGameModesInToolbarKey.self] }
        set { self[CompactGameModesInToolbarKey.self] = newValue }
    }
}

/// Keep title metadata and native navigation/actions. Vertical bars also host
/// the compact mode controls, leaving the content header for the game clock.
private struct GameToolbarLayout: ViewModifier {
    @Environment(\.isVerticalToolbar) private var isVerticalToolbar
    @ObservedObject var game: Game
    @Binding var interaction: GameDetailInteraction
    let compact: Bool
    let navigationBarHidden: Bool
    let showsActiveGamesButton: Bool

    private func panelSelection(_ panel: GameDetailPanel) -> Binding<Bool> {
        Binding(
            get: { interaction.panel == panel },
            set: { selected in
                guard selected, interaction.panel != panel else { return }
                withAnimation { interaction.selectPanel(panel) }
            }
        )
    }

    private func panelButton(
        _ panel: GameDetailPanel,
        title: LocalizedStringKey,
        symbol: String,
        identifier: String
    ) -> some View {
        Toggle(isOn: panelSelection(panel)) {
            Label(title, systemImage: symbol)
        }
        .toggleStyle(.button)
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.gameDisplayModePicker
                + "." + identifier
        )
    }

    func body(content: Content) -> some View {
        let showsModeButtons = compact && !navigationBarHidden
            && isVerticalToolbar

        content
            .toolbar(removing: isVerticalToolbar ? .title : nil)
            .environment(\.compactGameModesInToolbar, showsModeButtons)
            .toolbar {
                if showsModeButtons {
                    AppVerticalToolbarGroup(separatesNextGroup: showsActiveGamesButton) {
                        panelButton(
                            .analyze,
                            title: game.analysisAvailable
                                ? "Analyze mode" : "Playback mode",
                            symbol: game.analysisAvailable
                                ? "arrow.triangle.branch" : "arrow.left.and.right",
                            identifier: "analyze"
                        )
                        panelButton(
                            .playerInfo,
                            title: "Player info",
                            symbol: "person.crop.square.fill.and.at.rectangle",
                            identifier: "playerInfo"
                        )
                        panelButton(
                            .chat,
                            title: "Chat",
                            symbol: "message",
                            identifier: "chat"
                        )
                        .badge(game.chatUnreadCount)
                    }
                }
            }
    }
}

extension View {
    @ViewBuilder
    func surroundUITestZenShortcut() -> some View {
        #if DEBUG
        if SurroundUITestContract.isEnabled {
            // Catalyst 26 exposes the toolbar control to XCTest but does not
            // dispatch its action through synthesized pointer events.
            keyboardShortcut("z", modifiers: [.control, .option])
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if DEBUG
private func gameDetailPreviewFixture() -> (
    games: [Game],
    ogs: OGSService,
    navigation: NavigationService
) {
    let games = [
        TestData.Ongoing19x19wBot1,
        TestData.Ongoing19x19wBot2,
        TestData.Ongoing19x19wBot3,
    ]
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "kata-bot", id: 592684),
        activeGames: games
    )
    for game in games {
        game.chatUnreadCount = 2
    }
    return (games, ogs, NavigationService())
}

#Preview("Phone — Zen mode", traits: .fixedLayout(width: 390, height: 844)) {
    let fixture = gameDetailPreviewFixture()

    AppNavigationStack {
        GameDetailView(
            currentGame: .constant(fixture.games[0]),
            activeGames: fixture.games,
            zenMode: true
        )
    }
    .environmentObject(fixture.ogs)
    .environmentObject(fixture.navigation)
}

#Preview("Phone — Active games", traits: .fixedLayout(width: 390, height: 844)) {
    let fixture = gameDetailPreviewFixture()

    AppNavigationStack {
        GameDetailView(
            currentGame: .constant(fixture.games[0]),
            activeGames: fixture.games
        )
    }
    .environmentObject(fixture.ogs)
    .environmentObject(fixture.navigation)
}

#Preview("Regular landscape — Zen mode", traits: .fixedLayout(width: 960, height: 754)) {
    let fixture = gameDetailPreviewFixture()

    AppNavigationStack {
        GameDetailView(currentGame: .constant(fixture.games[0]), zenMode: true)
    }
    .environment(\.horizontalSizeClass, UserInterfaceSizeClass.regular)
    .environmentObject(fixture.ogs)
    .environmentObject(fixture.navigation)
}

#Preview("Regular portrait — Active game", traits: .fixedLayout(width: 750, height: 1024)) {
    let fixture = gameDetailPreviewFixture()

    AppNavigationStack {
        GameDetailView(currentGame: .constant(fixture.games[0]))
    }
    .environment(\.horizontalSizeClass, UserInterfaceSizeClass.regular)
    .environmentObject(fixture.ogs)
    .environmentObject(fixture.navigation)
}
#endif
