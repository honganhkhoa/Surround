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

    @State var currentGame: Game?
    @State var activeGames: [Game] = []
    @State var activeGameByOGSID: [Int: Game] = [:]
    
    @State var showSettings = false
    @State var attachedKeyboardVisible = false
    @State var needsToHideActiveGameCarousel = false
    @State var zenMode = false
    
    @ObservedObject var settings = userDefaults

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
    
    var compactBody: some View {
        GeometryReader { geometry -> AnyView in
//            print("Geometry \(geometry.size)")
            
            let boardSize: CGFloat = min(geometry.size.width, geometry.size.height)
            let controlRowHeight: CGFloat = NSString(string: "Ilp").boundingRect(with: geometry.size, attributes: [.font: UIFont.preferredFont(forTextStyle: .title2)], context: nil).size.height
            let usableHeight: CGFloat = geometry.size.height
            let playerInfoHeight: CGFloat = 64 + 64 - 10 + 15 * 2
            let spacing: CGFloat = 10.0
            let remainingHeight: CGFloat = usableHeight - boardSize - controlRowHeight - playerInfoHeight - (spacing * 2)
            let enoughRoomForCarousel = remainingHeight >= 140 || (remainingHeight + geometry.safeAreaInsets.bottom * 2 / 3 >= 140)
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
                        attachedKeyboardVisible: self.attachedKeyboardVisible,
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
                if showsActiveGamesCarousel {
                    ActiveGamesCarousel(currentGame: $currentGame, activeGames: activeGames)
                }
                if let currentGame = currentGame {
                    SingleGameView(
                        compact: false,
                        game: currentGame,
                        goToNextGame: goToNextGame,
                        horizontal: horizontal,
                        zenMode: $zenMode
                    )
                }
            })
        }
    }
    
    var body: some View {
        guard let currentGame = currentGame else {
            return AnyView(EmptyView())
        }
        
        var compactLayout = true
        #if os(iOS)
        compactLayout = horizontalSizeClass == .compact
        #endif
        let userColor: StoneColor = currentGame.blackId == ogs.user?.id ? .black : .white
        let players = currentGame.gameData!.players
        let opponent = userColor == .black ? players.white : players.black
        let opponentRank = userColor == .black ? currentGame.whiteFormattedRank : currentGame.blackFormattedRank
        let navigationBarHidden = /*attachedKeyboardVisible ||*/ zenMode
        
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
                            Text("Done").bold()
                        }
                    }
                }
            }
        }
        .navigationTitle(
            navigationBarHidden
            ? "" :
                (currentGame.isUserPlaying ? "vs \(opponent.username) [\(opponentRank)]" : currentGame.gameName ?? "")
        )
        .navigationBarHidden(navigationBarHidden)
        .navigationBarBackButtonHidden(navigationBarHidden)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if currentGame.gameData?.timeControl.speed == .live || currentGame.gameData?.timeControl.speed == .blitz {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            updateActiveGameList()
            DispatchQueue.main.async {
                self.updateDetailOfCurrentGameIfNecessary()
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
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
                self.attachedKeyboardVisible = !keyboardFrame.isEmpty &&
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
                                Button(action: { withAnimation { zenMode = true } }) {
                                    Label("Zen mode", systemImage: "arrow.up.backward.and.arrow.down.forward")
                                }
                                Button(action: { self.showSettings = true }) {
                                    Label("Options", systemImage: "gearshape.2")
                                }
                            }
                        }
                    }
                }
            )
        } else {
            return AnyView(
                result.toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            withAnimation {
                                Setting(.showsActiveGamesCarousel).binding.wrappedValue.toggle()
                            }
                        }) {
                            Label("Toggle thumbnails", systemImage: "rectangle.topthird.inset")
                                .labelStyle(IconOnlyLabelStyle())
                        }
                        .disabled(!shouldShowActiveGamesCarousel)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { withAnimation { zenMode = true } }) {
                            Label("Zen mode", systemImage: "arrow.up.backward.and.arrow.down.forward")
                        }
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
