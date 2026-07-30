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

    @State var currentGame: Game?
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

    @ObservedObject var settings = userDefaults
    
    var showsActiveGamesCarouselSetting = Setting(.showsActiveGamesCarousel).binding

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
        if let currentIndex = activeGames.firstIndex(where: { game in game.ID == currentGame?.ID }) {
            for game in activeGames[currentIndex.advanced(by: 1)..<activeGames.endIndex] + activeGames[activeGames.startIndex..<currentIndex] {
                if game.clock?.currentPlayerId == ogs.user?.id {
                    withAnimation {
                        currentGame = game
                    }
                    break
                }
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
                        attachedKeyboardVisible: self.attachedKeyboardVisible,
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
            let showsActiveGamesCarousel = !attachedKeyboardVisible && shouldShowActiveGamesCarousel
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
                        attachedKeyboardVisible: self.attachedKeyboardVisible,
                        analyzeMode: self.$analyzeMode
                    )
                }
            })
        }
    }
    
    var body: some View {
        guard let currentGame = self.currentGame else {
            // Work-around for pre-iOS 16.4 bug related navigation destination with data dependencies captured from ancestor views.
            if let currentGameFromNav = nav.home.activeGame {
                DispatchQueue.main.async {
                    self.currentGame = currentGameFromNav
                }
            }
            return AnyView(EmptyView())
        }

        var compactLayout = true
        #if os(iOS)
        compactLayout = horizontalSizeClass == .compact
        #endif
        let navigationBarHidden = (attachedKeyboardVisible && !compactLayout) || zenMode
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
                    SurroundUITestContract.AccessibilityID.screenGameOptions
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
        .navigationTitle(
            navigationBarHidden
            ? "" :
                (title ?? "")
        )
        .navigationBarHidden(navigationBarHidden && !compactLayout)
        .navigationBarBackButtonHidden(navigationBarHidden)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            updateActiveGameList()
            updateDetailOfCurrentGameIfNecessary()
        }
        .onChange(of: currentGame) { oldGame, newGame in
            if newGame.ID != oldGame.ID {
                updateDetailOfCurrentGameIfNecessary()
            }
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
                                if !analyzeMode {
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

struct GameDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let games = [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2, TestData.Ongoing19x19wBot3]
        let ogs = OGSService.previewInstance(
            user: OGSUser(username: "kata-bot", id: 592684),
            activeGames: games
        )
        for game in games {
            game.ogs = ogs
            game.chatUnreadCount = 2
        }

        return Group {
            NavigationView {
                GameDetailView(currentGame: games[0], activeGames: games, zenMode: true)
            }
            .previewDevice("iPhone 12 Pro")
//            .colorScheme(.dark)

            NavigationView {
                GameDetailView(currentGame: games[0], activeGames: games)
            }
            .previewDevice("iPhone 12 Pro")

            GameDetailView(currentGame: games[0], zenMode: true)
                .previewLayout(.fixed(width: 960, height: 754))
                .environment(\.horizontalSizeClass, UserInterfaceSizeClass.regular)

            GameDetailView(currentGame: games[0])
                .previewLayout(.fixed(width: 750, height: 1024))
                .environment(\.horizontalSizeClass, UserInterfaceSizeClass.regular)
        }
        .environmentObject(ogs)
        .environmentObject(NavigationService.shared)
    }
}
