//
//  CorrespondenceGamesView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 8/26/20.
//

import SwiftUI
import Combine

struct SingleGameView: View {
    var compact: Bool
    var compactBoardSize: CGFloat = 0
    @ObservedObject var game: Game
    var reducedPlayerInfoVerticalPadding: Bool = false
    var goToNextGame: (() -> ())?
    var horizontal = false
    
    @EnvironmentObject var ogs: OGSService
    @Environment(\.colorScheme) private var colorScheme
    @State var pendingMove: Move? = nil
    @State var pendingPosition: BoardPosition? = nil
    @State var stoneRemovalSelectedPoints = Set<[Int]>()
    @State var stoneRemovalOption = StoneRemovalOption.toggleGroup
    var attachedKeyboardVisible = false
    
    @State var compactDisplayMode = CompactDisplayMode.playerInfo
    var shouldHideActiveGamesCarousel: Binding<Bool> = .constant(false)
    @Setting(.showsBoardCoordinates) var showsBoardCoordinates: Bool

    @State var hoveredPosition: BoardPosition? = nil
    @State var hoveredVariation: Variation? = nil
    
    @Namespace var animation
    
    enum CompactDisplayMode {
        case playerInfo
        case chat
    }
    
    var controlRow: some View {
        GameControlRow(
            game: game,
            pendingMove: $pendingMove,
            pendingPosition: $pendingPosition,
            goToNextGame: goToNextGame,
            stoneRemovalOption: $stoneRemovalOption,
            stoneRemovalSelectedPoints: $stoneRemovalSelectedPoints
        )
    }
    
    var verticalControlRow: some View {
        GameControlRow(
            game: game,
            horizontal: false,
            pendingMove: $pendingMove,
            pendingPosition: $pendingPosition,
            goToNextGame: goToNextGame,
            stoneRemovalOption: $stoneRemovalOption,
            stoneRemovalSelectedPoints: $stoneRemovalSelectedPoints
        )
    }
    
    var boardView: some View {
        ZStack {
            BoardView(
                boardPosition: game.currentPosition,
                showsCoordinate: showsBoardCoordinates && !(compact && attachedKeyboardVisible),
                playable: game.isUserTurn,
                stoneRemovable: game.isUserPlaying && game.gamePhase == .stoneRemoval,
                stoneRemovalOption: stoneRemovalOption,
                newMove: $pendingMove,
                newPosition: $pendingPosition,
                allowsSelfCapture: game.gameData?.allowSelfCapture ?? false,
                stoneRemovalSelectedPoints: $stoneRemovalSelectedPoints
            )
            if let hoveredPosition = hoveredPosition {
                BoardView(
                    boardPosition: hoveredPosition,
                    variation: hoveredVariation,
                    showsCoordinate: showsBoardCoordinates && !(compact && attachedKeyboardVisible)
                )
            }
        }
    }
    
    var userColor: StoneColor {
        return ogs.user?.id == game.blackId ? .black : .white
    }
    
    var topLeftPlayerColor: StoneColor {
        if game.isUserPlaying {
            return userColor.opponentColor()
        } else {
            return .black
        }
    }

    var compactDisplayModePicker: some View {
        Picker(selection: $compactDisplayMode.animation(), label: Text("Display mode")) {
            Label("Player info", systemImage: "person.crop.square.fill.and.at.rectangle")
                .labelStyle(IconOnlyLabelStyle())
                .tag(CompactDisplayMode.playerInfo)
            Label("Chat", systemImage: "message")
                .labelStyle(IconOnlyLabelStyle())
                .tag(CompactDisplayMode.chat)
        }
        .pickerStyle(SegmentedPickerStyle())
        .fixedSize()
        .padding(.horizontal, 15)
        .padding(.vertical, 5)
        .matchedGeometryEffect(id: "compactDisplayModePicker", in: animation)
    }
    
    var compactBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if compactDisplayMode == .playerInfo {
                ZStack(alignment: .topTrailing) {
                    PlayersBannerView(
                        game: game,
                        topLeftPlayerColor: topLeftPlayerColor,
                        reducesVerticalPadding: reducedPlayerInfoVerticalPadding,
                        showsPlayersName: !game.isUserPlaying
                    )
                    compactDisplayModePicker
                }
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Spacer().frame(width: 10)
                        HStack(spacing: 0) {
                            Stone(color: topLeftPlayerColor, shadowRadius: 2)
                                .frame(width: 20, height: 20)
                            Spacer().frame(width: 5)
                            InlineTimerView(
                                timeControl: game.gameData?.timeControl,
                                clock: game.clock,
                                player: topLeftPlayerColor,
                                pauseControl: game.pauseControl,
                                showsPauseReason: false
                            )
                        }
                        Spacer(minLength: 5)
                        Divider()
                        Spacer(minLength: 5)
                        HStack(spacing: 0) {
                            InlineTimerView(
                                timeControl: game.gameData?.timeControl,
                                clock: game.clock,
                                player: topLeftPlayerColor.opponentColor(),
                                pauseControl: game.pauseControl,
                                showsPauseReason: false
                            )
                            Spacer().frame(width: 5)
                            Stone(color: topLeftPlayerColor.opponentColor(), shadowRadius: 2)
                                .frame(width: 20, height: 20)
                        }
                        Spacer().frame(width: 10)
                        compactDisplayModePicker
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    ChatLog(game: game, hoveredPosition: $hoveredPosition, hoveredVariation: $hoveredVariation)
                }
            }
            if compactDisplayMode == .playerInfo {
                Spacer(minLength: 10).frame(maxHeight: 15)
                controlRow
                    .padding(.horizontal)
                Spacer(minLength: 10)
            }
            if attachedKeyboardVisible {
                HStack(alignment: .top) {
                    boardView.frame(width: compactBoardSize / 2, height: compactBoardSize / 2)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack {
                            (Text(game.blackName)
                                .font(.footnote).bold()
                                + Text(" [\(game.blackFormattedRank)]").font(.caption))
                                .minimumScaleFactor(0.5)

                            Stone(color: .black, shadowRadius: 2)
                                .frame(width: 20, height: 20)
                        }
                        Spacer().frame(height: 5)
                        HStack {
                            (Text(game.whiteName)
                                .font(.footnote).bold()
                                + Text(" [\(game.whiteFormattedRank)]").font(.caption))
                                .minimumScaleFactor(0.5)
                            Stone(color: .white, shadowRadius: 2)
                                .frame(width: 20, height: 20)
                        }
                        Spacer().frame(height: 15)
                        verticalControlRow
                    }
                    .padding()
                }
            } else {
                boardView.frame(width: compactBoardSize, height: compactBoardSize)
            }
            Spacer(minLength: 0)
        }
        .onChange(of: compactDisplayMode) { newValue in
            withAnimation {
                shouldHideActiveGamesCarousel.wrappedValue = newValue == .chat
            }
        }
}
    
    var regularVerticalBody: some View {
        GeometryReader { geometry -> AnyView in
            let width = geometry.size.width
            let height = geometry.size.height
            let chatHeight: CGFloat = 270
            let boardSize = min(width - 15 * 2, height - chatHeight - 15 * 3)
            return AnyView(erasing: VStack(alignment: .center, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    ChatLog(game: game, hoveredPosition: $hoveredPosition, hoveredVariation: $hoveredVariation)
                        .frame(height: chatHeight)
                    Spacer(minLength: 15)
                    VStack {
                        PlayersBannerView(
                            game: game,
                            topLeftPlayerColor: topLeftPlayerColor,
                            playerIconSize: 80,
                            playerIconsOffset: 25,
                            showsPlayersName: true
                        )
                        Spacer(minLength: 15).frame(maxHeight: 15)
                        controlRow
                    }.frame(width: 350)
                }
                Spacer(minLength: 15)
                boardView.frame(width: boardSize, height: boardSize)
                Spacer(minLength: 0)
            }
            .padding())
        }
    }
    
    var regularHorizontalBody: some View {
        GeometryReader { geometry -> AnyView in
//            print("Geometry \(geometry.safeAreaInsets)")
            let width = geometry.size.width
            let height = geometry.size.height
            let minimumPlayerInfoWidth: CGFloat = 350
            let minimumChatWidth: CGFloat = 250
            let minimumPlayerInfoHeight: CGFloat = 80 + 15 * 2
            let boardSizeInfoLeft = min(height - 15 * 2, width - minimumPlayerInfoWidth - 15 * 3)
            let boardSizeInfoTop = min(height - 15 * 3 - minimumPlayerInfoHeight, width - 15 * 3 - minimumChatWidth)
            let infoLeft = boardSizeInfoLeft > boardSizeInfoTop
            let boardSize = infoLeft ? boardSizeInfoLeft : boardSizeInfoTop
            var playerIconsOffset: CGFloat = 25
            if infoLeft {
            let horizontalPlayerInfoWidth = width - boardSize - 15 * 3
                if horizontalPlayerInfoWidth > 600 {
                    playerIconsOffset = -80
                } else if horizontalPlayerInfoWidth > 400 {
                    playerIconsOffset = -10
                }
            } else {
                playerIconsOffset = -80
            }
            return AnyView(erasing: ZStack {
                VStack(spacing: 15) {
                    if !infoLeft {
                        PlayersBannerView(
                            game: game,
                            topLeftPlayerColor: topLeftPlayerColor,
                            playerIconSize: 80,
                            playerIconsOffset: playerIconsOffset,
                            showsPlayersName: true
                        )
                    }
                    HStack(alignment: .top, spacing: 15) {
                        VStack(alignment: .trailing, spacing: 15) {
                            if infoLeft {
                                PlayersBannerView(
                                    game: game,
                                    topLeftPlayerColor: topLeftPlayerColor,
                                    playerIconSize: 80,
                                    playerIconsOffset: playerIconsOffset,
                                    showsPlayersName: true
                                ).frame(minWidth: minimumPlayerInfoWidth)
                            }
                            controlRow
                            ChatLog(game: game, hoveredPosition: $hoveredPosition, hoveredVariation: $hoveredVariation)
                        }
                        boardView.frame(width: boardSize, height: boardSize)
                    }.frame(height: boardSize)
                }.padding(15)
            }.frame(width: width, height: height))
        }
    }
    
    var body: some View {
        Group {
            if compact {
                compactBody
            } else {
                if horizontal {
                    regularHorizontalBody
                } else {
                    regularVerticalBody
                }
            }
        }
        .onReceive(game.$currentPosition) { _ in
            self.pendingMove = nil
            self.pendingPosition = nil
            self.stoneRemovalSelectedPoints.removeAll()
        }
    }
}

struct GameDetailView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var ogs: OGSService

    @State var currentGame: Game?
    @State var activeGames: [Game] = []
    @State var activeGameByOGSID: [Int: Game] = [:]
    
    @State var showSettings = false
    @State var attachedKeyboardVisible = false
    @State var shouldHideActiveGameCarousel = false

    var shouldShowActiveGamesCarousel: Bool {
//        return true
        if let currentGame = currentGame {
            return currentGame.isUserPlaying && activeGames.count > 1 && currentGame.gameData?.timeControl.speed == .correspondence
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
        self.activeGames = []
        for game in ogs.sortedActiveCorrespondenceGames {
            self.activeGames.append(game)
            if let ogsID = game.ogsID {
                self.activeGameByOGSID[ogsID] = game
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
            let showsActiveGamesCarousel = !self.shouldHideActiveGameCarousel && shouldShowActiveGamesCarousel && enoughRoomForCarousel
            let reducedPlayerInfoVerticalPadding = (showsActiveGamesCarousel && remainingHeight <= 150) || remainingHeight < 0

            return AnyView(erasing: VStack(alignment: .leading) {
                if let currentGame = currentGame {
                    SingleGameView(
                        compact: true,
                        compactBoardSize: boardSize,
                        game: currentGame,
                        reducedPlayerInfoVerticalPadding: reducedPlayerInfoVerticalPadding,
                        goToNextGame: goToNextGame,
                        attachedKeyboardVisible: self.attachedKeyboardVisible,
                        shouldHideActiveGamesCarousel: self.$shouldHideActiveGameCarousel
                    )
                }
                if showsActiveGamesCarousel {
                    ActiveCorrespondenceGamesCarousel(currentGame: $currentGame, activeGames: activeGames)
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
                    ActiveCorrespondenceGamesCarousel(currentGame: $currentGame, activeGames: activeGames)
                }
                if let currentGame = currentGame {
                    SingleGameView(
                        compact: false,
                        game: currentGame,
                        goToNextGame: goToNextGame,
                        horizontal: horizontal
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

        return AnyView(Group {
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { self.showSettings = true }) {
                    Label("Options", systemImage: "gearshape.2")
                }
            }
        }
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
        .navigationBarHidden(attachedKeyboardVisible)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(currentGame.isUserPlaying ? "vs \(opponent.username) [\(opponentRank)]" : currentGame.gameName ?? "")
        .onAppear {
            if currentGame.gameData?.timeControl.speed == .live {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            if let ogsId = currentGame.ogsID {
                if ogs.activeGames[ogsId] != nil {
                    updateActiveGameList()
                }
            }
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
        .onReceive(ogs.$sortedActiveCorrespondenceGames) { sortedActiveGames in

        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                let screenBounds = UIScreen.main.bounds
                self.attachedKeyboardVisible = !keyboardFrame.isEmpty &&
                    screenBounds.maxX == keyboardFrame.maxX &&
                    screenBounds.maxY == keyboardFrame.maxY &&
                    screenBounds.width == keyboardFrame.width
            }
        })
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
        }

        return Group {
            NavigationView {
                GameDetailView(currentGame: games[0], activeGames: games)
            }
            .previewDevice("iPhone 12 Pro")

            GameDetailView(currentGame: games[0])
                .previewLayout(.fixed(width: 750, height: 754))
                .environment(\.horizontalSizeClass, UserInterfaceSizeClass.regular)

            GameDetailView(currentGame: games[0])
                .previewLayout(.fixed(width: 750, height: 1024))
                .environment(\.horizontalSizeClass, UserInterfaceSizeClass.regular)
        }
        .environmentObject(ogs)
    }
}
