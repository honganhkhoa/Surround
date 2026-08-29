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
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService

    @Binding var currentGame: Game?
    @State var activeGames: [Game] = []
    @State var activeGameByOGSID: [Int: Game] = [:]
    @State private var detailConnection = GameDetailConnectionCoordinator()

    /// When false (e.g. opening a finished game from Game History), the
    /// active-games carousel is never shown regardless of the active game list.
    var allowsActiveGamesCarousel = true
    
    @State var showSettings = false
    @State var attachedKeyboardVisible = false
    @State var needsToHideActiveGameCarousel = false
    @State var zenMode = false
    @State var analyzeMode = false
    @State private var compactDisplayMode =
        SingleGameView.DisplayMode.playerInfo
    @State private var showsCompactChatBoard = true
    @State private var variationShareDraft: VariationShareDraft?
    @State private var selectedChatChannel = OGSChatSendChannel.main

    @ObservedObject var settings = userDefaults
    
    var showsActiveGamesCarouselSetting = Setting(.showsActiveGamesCarousel).binding

    private var effectiveAttachedKeyboardVisible: Bool {
        #if DEBUG && MAIN_APP
        attachedKeyboardVisible
            || SurroundUITestContract
                .simulatesAttachedSoftwareKeyboardVisible
        #else
        attachedKeyboardVisible
        #endif
    }

    var shouldShowActiveGamesCarousel: Bool {
        guard allowsActiveGamesCarousel else {
            return false
        }
        guard !zenMode else {
            return false
        }
        if let currentGame = currentGame {
            return currentGame.isUserPlaying && activeGames.count > 1
        } else {
            return false
        }
    }
    
    func updateDetailOfCurrentGameIfNecessary() {
        guard let requestedGame = currentGame, requestedGame.ogsID != nil else {
            detailConnection.release(using: ogs)
            return
        }

        let canonicalGame = detailConnection.connect(to: requestedGame, using: ogs)
        if canonicalGame !== requestedGame {
            currentGame = canonicalGame
        }
        if canonicalGame.ogsRawData == nil {
            ogs.updateDetailsOfConnectedGame(game: canonicalGame)
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
            } else if gameSpeed == .live || gameSpeed == .blitz {
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
        withAnimation {
            zenMode = true
        }
    }
    
    func exitZenMode() {
        withAnimation {
            zenMode = false
        }
    }
    
    var compactBody: some View {
        GeometryReader { geometry -> AnyView in
//            print("Geometry \(geometry.size)")
            
            let boardSize: CGFloat = min(geometry.size.width, geometry.size.height)
            let controlRowHeight: CGFloat = NSString(string: "Ilp").boundingRect(with: geometry.size, attributes: [.font: UIFont.preferredFont(forTextStyle: .title2)], context: nil).size.height
            let usableHeight: CGFloat = geometry.size.height
            let playerInfoHeight: CGFloat = 64 + 64 - 10 + 15 * 2
            let spacing: CGFloat = 10.0
            let remainingHeight: CGFloat = usableHeight - boardSize - controlRowHeight - playerInfoHeight - (spacing * 2)
            let enoughRoomForCarousel = remainingHeight >= 140 || (remainingHeight + geometry.safeAreaInsets.bottom * 2 / 3 >= 134)
            let canShowActiveGamesCarousel = !self.needsToHideActiveGameCarousel && shouldShowActiveGamesCarousel && enoughRoomForCarousel
            let reducedPlayerInfoVerticalPadding = (canShowActiveGamesCarousel && remainingHeight <= 150) || remainingHeight < 0

            return AnyView(erasing: VStack(alignment: .leading) {
                if let currentGame = currentGame {
                    SingleGameView(
                        compact: true,
                        compactBoardSize: boardSize,
                        game: currentGame,
                        reducedPlayerInfoVerticalPadding: reducedPlayerInfoVerticalPadding,
                        goToNextGame: goToNextGame,
                        zenMode: $zenMode,
                        exitZenMode: self.exitZenMode,
                        attachedKeyboardVisible:
                            self.effectiveAttachedKeyboardVisible,
                        compactDisplayMode: $compactDisplayMode,
                        showsCompactChatBoard: $showsCompactChatBoard,
                        variationShareDraft: $variationShareDraft,
                        selectedChatChannel: $selectedChatChannel,
                        analyzeMode: self.$analyzeMode,
                        shouldHideActiveGamesCarousel: self.$needsToHideActiveGameCarousel
                    )
                }
                if canShowActiveGamesCarousel {
                    ActiveGamesCarousel(currentGame: $currentGame, activeGames: activeGames, showsToggleButton: true)
                }
            })
        }
    }
    
    var regularBody: some View {
        GeometryReader { geometry -> AnyView in
            let showsActiveGamesCarousel =
                !effectiveAttachedKeyboardVisible
                    && shouldShowActiveGamesCarousel
            let horizontal = geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing + 100 > geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            print("Geometry \(horizontal) \(geometry.size) \(geometry.safeAreaInsets)")
            return AnyView(erasing: VStack(spacing: 0) {
                if showsActiveGamesCarousel && !analyzeMode {
                    ActiveGamesCarousel(currentGame: $currentGame, activeGames: activeGames)
                }
                if let currentGame = currentGame {
                    SingleGameView(
                        compact: false,
                        game: currentGame,
                        goToNextGame: goToNextGame,
                        horizontal: horizontal,
                        zenMode: $zenMode,
                        exitZenMode: self.exitZenMode,
                        attachedKeyboardVisible:
                            self.effectiveAttachedKeyboardVisible,
                        compactDisplayMode: $compactDisplayMode,
                        showsCompactChatBoard: $showsCompactChatBoard,
                        variationShareDraft: $variationShareDraft,
                        selectedChatChannel: $selectedChatChannel,
                        analyzeMode: self.$analyzeMode
                    )
                }
            })
        }
    }
    
    var body: some View {
        guard let currentGame = self.currentGame else {
            return AnyView(EmptyView())
        }

        var compactLayout = true
        #if os(iOS)
        compactLayout = horizontalSizeClass == .compact
        #endif
        #if DEBUG && MAIN_APP
        if SurroundUITestContract.forcesCompactGameLayout {
            compactLayout = true
        }
        #endif
        let navigationBarHidden =
            (effectiveAttachedKeyboardVisible && !compactLayout) || zenMode
        var title = currentGame.gameName
        if currentGame.isUserPlaying, let userColor = currentGame.userStoneColor, let opponent = currentGame.currentPlayer(with: userColor.opponentColor()) {
            title = "vs \(opponent.usernameAndRank)"
            if currentGame.rengo {
                if let opponentTeam = currentGame.gameData?.rengoTeams?[userColor.opponentColor()] {
                    if opponentTeam.count > 1 {
                        title = title! + " +\(opponentTeam.count - 1)"
                    }
                }
            }
        }
        #if targetEnvironment(macCatalyst)
        let trimmedTitle = title?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        let navigationTitle = trimmedTitle.isEmpty
            ? String(
                localized: "Game",
                comment: "Fallback game window title"
            )
            : trimmedTitle
        #else
        let navigationTitle = navigationBarHidden ? "" : (title ?? "")
        #endif
        
        let result = Group {
            if compactLayout {
                compactBody
            } else {
                regularBody
            }
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
            NavigationStack {
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
                variationShareDraft = nil
                selectedChatChannel = .main
                updateDetailOfCurrentGameIfNecessary()
            }
        }
        .onChange(of: ogs.user?.id) { _, _ in
            variationShareDraft = nil
            selectedChatChannel = .main
        }
        .onDisappear {
            detailConnection.release(using: ogs)
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
        }
        
        if compactLayout {
            return AnyView(
                result.toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if !navigationBarHidden {
                            HStack {
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
                            }
                        } else if zenMode {
                            Button(action: exitZenMode) {
                                Label("Exit Zen mode", systemImage: "arrow.down.forward.and.arrow.up.backward")
                            }
                            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameZenExit)
                            .surroundUITestZenShortcut()
                        }
                    }
                }
                .toolbar(.hidden, for: .tabBar)
                .ignoresSafeArea(edges: navigationBarHidden ? [.top] : [])
            )
        } else {
            return AnyView(
                result.toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Toggle(isOn: $analyzeMode.animation()) {
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
                        Toggle(isOn: Binding<Bool>(
                            get: { showsActiveGamesCarouselSetting.wrappedValue },
                            set: { newValue in
                                withAnimation {
                                    if newValue && analyzeMode {
                                        analyzeMode.toggle()
                                    }
                                    showsActiveGamesCarouselSetting.wrappedValue = newValue
                                }
                            })) {
                            Label("Toggle thumbnails", systemImage: "rectangle.topthird.inset")
                                .labelStyle(IconOnlyLabelStyle())
                        }
                        .disabled(!shouldShowActiveGamesCarousel)
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
                .toolbar(zenMode ? .hidden : .automatic, for: .tabBar)
            )
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

    NavigationView {
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

    NavigationView {
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

    GameDetailView(currentGame: .constant(fixture.games[0]), zenMode: true)
        .environment(\.horizontalSizeClass, UserInterfaceSizeClass.regular)
        .environmentObject(fixture.ogs)
        .environmentObject(fixture.navigation)
}

#Preview("Regular portrait — Active game", traits: .fixedLayout(width: 750, height: 1024)) {
    let fixture = gameDetailPreviewFixture()

    GameDetailView(currentGame: .constant(fixture.games[0]))
        .environment(\.horizontalSizeClass, UserInterfaceSizeClass.regular)
        .environmentObject(fixture.ogs)
        .environmentObject(fixture.navigation)
}
#endif
