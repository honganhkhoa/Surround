//
//  CorrespondenceGamesView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 8/26/20.
//

import SwiftUI
import Combine

struct GameDetailView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    
    @Setting(.hideOpponentRank) var hideOpponentRank: Bool

    @State var currentGame: Game?
    @State var activeGames: [Game] = []
    @State var activeGameByOGSID: [Int: Game] = [:]
    
    @State var showSettings = false
    @State var attachedKeyboardVisible = false
    @State var needsToHideActiveGameCarousel = false
    @State var zenMode = false
    @State var analyzeMode = false
    
    @State var columnVisibilityBeforeZenMode = NavigationSplitViewVisibilityProxy.automatic

    @ObservedObject var settings = userDefaults
    
    var showsActiveGamesCarouselSetting = Setting(.showsActiveGamesCarousel).binding

    var shouldShowActiveGamesCarousel: Bool {
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
        if let currentGame = currentGame {
            ogs.connect(to: currentGame, withChat: true)
            if currentGame.ogsRawData == nil {
                ogs.updateDetailsOfConnectedGame(game: currentGame)
            }
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
            columnVisibilityBeforeZenMode = nav.columnVisibility
            zenMode = true
            nav.columnVisibility = .detailOnly
        }
    }
    
    func exitZenMode() {
        withAnimation {
            zenMode = false
            nav.columnVisibility = columnVisibilityBeforeZenMode
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
            title = "vs \(opponent.username) [\(opponent.formattedRank)]"
            if hideOpponentRank {
                title = "vs \(opponent.username)"
            }
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
        .background(
            colorScheme == .dark ?
                Color(UIColor.systemGray5).edgesIgnoringSafeArea(.bottom) :
                Color.white.edgesIgnoringSafeArea(.bottom)
        )
        .sheet(isPresented: self.$showSettings) {
            NavigationView {
                VStack {
                    GameplaySettings()
                    Spacer()
                }
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
            DispatchQueue.main.async {
                self.updateDetailOfCurrentGameIfNecessary()
            }
        }
        .onChange(of: currentGame) { [currentGame] newGame in
            if newGame.ID != currentGame.ID {
                DispatchQueue.main.async {
                    self.updateDetailOfCurrentGameIfNecessary()
                }
            }
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                let screenBounds = UIScreen.main.bounds
                self.attachedKeyboardVisible = !keyboardFrame.isEmpty && keyboardFrame.height > 100 &&
                    screenBounds.maxX == keyboardFrame.maxX &&
                    screenBounds.maxY == keyboardFrame.maxY &&
                    screenBounds.width == keyboardFrame.width
            }
        }
        
        if compactLayout {
            return AnyView(
                result.toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        if !navigationBarHidden {
                            HStack {
                                if !analyzeMode {
                                    Button(action: enterZenMode) {
                                        Label("Zen mode", systemImage: "arrow.up.backward.and.arrow.down.forward")
                                    }
                                }
                                Button(action: { self.showSettings = true }) {
                                    Label("Options", systemImage: "gearshape.2")
                                }
                            }
                        } else if zenMode {
                            Button(action: exitZenMode) {
                                Label("Exit Zen mode", systemImage: "arrow.down.forward.and.arrow.up.backward")
                            }
                        }
                    }
                }.ignoresSafeArea(edges: navigationBarHidden ? [.top] : [])
            )
        } else {
            return AnyView(
                result.toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Toggle(isOn: $analyzeMode.animation()) {
                            if currentGame.analysisAvailable {
                                Label("Toggle analyze mode", systemImage: "arrow.triangle.branch")
                                    .labelStyle(IconOnlyLabelStyle())
                            } else {
                                Label("Toggle playback mode", systemImage: "arrow.left.and.right")
                                    .labelStyle(IconOnlyLabelStyle())
                            }
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
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
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: enterZenMode) {
                            Label("Zen mode", systemImage: "arrow.up.backward.and.arrow.down.forward")
                        }
                        .disabled(analyzeMode)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { self.showSettings = true }) {
                            Label("Options", systemImage: "gearshape.2")
                        }
                    }
                }
            )
        }
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
