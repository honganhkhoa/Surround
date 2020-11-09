//
//  CorrespondenceGamesView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 8/26/20.
//

import SwiftUI
import Combine

struct GameView: View {
    var compact: Bool
    var compactBoardSize: CGFloat = 0
    @ObservedObject var game: Game
    var reducedPlayerInfoVerticalPadding: Bool = false
    var goToNextGame: (() -> ())?
    
    @EnvironmentObject var ogs: OGSService
    @State var pendingMove: Move? = nil
    @State var pendingPosition: BoardPosition? = nil
    @State var stoneRemovalSelectedPoints = Set<[Int]>()
    @State var stoneRemovalOption = StoneRemovalOption.toggleGroup

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
        BoardView(
            boardPosition: game.currentPosition,
            playable: game.isUserTurn,
            stoneRemovable: game.isUserPlaying && game.gamePhase == .stoneRemoval,
            stoneRemovalOption: stoneRemovalOption,
            newMove: $pendingMove,
            newPosition: $pendingPosition,
            allowsSelfCapture: game.gameData?.allowSelfCapture ?? false,
            stoneRemovalSelectedPoints: $stoneRemovalSelectedPoints
        )
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

    var compactBody: some View {
        VStack(alignment: .leading) {
            PlayersBannerView(
                game: game,
                topLeftPlayerColor: topLeftPlayerColor,
                reducesVerticalPadding: reducedPlayerInfoVerticalPadding,
                showsPlayersName: !game.isUserPlaying
            )
            Spacer(minLength: 10).frame(maxHeight: 15)
            controlRow
                .padding(.horizontal)
            Spacer(minLength: 10)
            boardView.frame(width: compactBoardSize, height: compactBoardSize)
            Spacer(minLength: 0)
        }
    }
    
    var regularBody: some View {
        GeometryReader { geometry -> AnyView in
//            print("Geometry \(geometry.size)")
            let width = geometry.size.width
            let height = geometry.size.height - 15 * 2
            let boardSizeHorizontal = min(height, width - 300 - 15 * 3)
            let boardSizeVertical = min(width - 15 * 2, height - 80 - 15 * 2 - 15 * 4)
            var horizontal = true
            var boardSizeLimit = boardSizeHorizontal
            let playerInfoWidth = width - boardSizeHorizontal - 15 * 3
            var playerIconsOffset: CGFloat = 25
            if playerInfoWidth > 400 {
                playerIconsOffset = -10
            }
            if boardSizeVertical > boardSizeHorizontal {
                horizontal = false
                boardSizeLimit = boardSizeVertical
            }
            if boardSizeLimit < 0 {
                return AnyView(EmptyView())
            }
            return AnyView(erasing: ZStack {
                if horizontal {
                    HStack(alignment: .top, spacing: 15) {
                        VStack(alignment: .trailing) {
                            PlayersBannerView(
                                game: game,
                                topLeftPlayerColor: topLeftPlayerColor,
                                playerIconSize: 80,
                                playerIconsOffset: playerIconsOffset,
                                showsPlayersName: true
                            ).frame(minWidth: 300)
                            Spacer().frame(maxHeight: 15)
                            verticalControlRow
                            Spacer()
                        }
                        boardView.frame(width: boardSizeLimit, height: boardSizeLimit)
                    }
                    .padding()
                    .frame(height: boardSizeLimit + 15 * 2)
                } else {
                    VStack(alignment: .center, spacing: 0) {
                        PlayersBannerView(
                            game: game,
                            topLeftPlayerColor: topLeftPlayerColor,
                            playerIconSize: 80,
                            playerIconsOffset: -80,
                            showsPlayersName: true
                        )
                        Spacer(minLength: 15).frame(maxHeight: 15)
                        controlRow
                        Spacer(minLength: 15)
                        boardView.frame(width: boardSizeLimit, height: boardSizeLimit)
                        Spacer(minLength: 0)
                    }
                    .padding()
                    .frame(maxWidth: boardSizeLimit + 15 * 2)
                }
            }.frame(width: width, height: height + 15 * 2))
        }
    }
    
    var body: some View {
        Group {
            if compact {
                compactBody
            } else {
                regularBody
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

    @State var currentGame: Game
    @State var activeGames: [Game] = []
    @State var activeGameByOGSID: [Int: Game] = [:]
    
    @State var showSettings = false

    var shouldShowActiveGamesCarousel: Bool {
//        return true
        return currentGame.isUserPlaying && activeGames.count > 1 && currentGame.gameData?.timeControl.speed == .correspondence
    }
    
    func updateDetailOfCurrentGameIfNecessary() {
        if currentGame.ogsRawData == nil {
            ogs.updateDetailsOfConnectedGame(game: currentGame)
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
        if let currentIndex = activeGames.firstIndex(where: { game in game.ID == currentGame.ID }) {
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
            let showsActiveGamesCarousel = shouldShowActiveGamesCarousel && enoughRoomForCarousel
            let reducedPlayerInfoVerticalPadding = (showsActiveGamesCarousel && remainingHeight <= 150) || remainingHeight < 0

            return AnyView(erasing: VStack(alignment: .leading) {
//                Text("\(usableHeight) \(controlRowHeight) \(remainingHeight)")
                GameView(
                    compact: true,
                    compactBoardSize: boardSize,
                    game: currentGame,
                    reducedPlayerInfoVerticalPadding: reducedPlayerInfoVerticalPadding,
                    goToNextGame: goToNextGame
                )
                if showsActiveGamesCarousel {
                    ActiveCorrespondenceGamesCarousel(currentGame: $currentGame, activeGames: activeGames)
                }
            })
        }
    }
    
    var regularBody: some View {
        VStack(spacing: 0) {
            if shouldShowActiveGamesCarousel {
                ActiveCorrespondenceGamesCarousel(currentGame: $currentGame, activeGames: activeGames)
            }
            GameView(
                compact: false,
                game: currentGame,
                goToNextGame: goToNextGame
            )
        }
    }
    
    var body: some View {
        var compactLayout = true
        #if os(iOS)
        compactLayout = horizontalSizeClass == .compact
        #endif
        let userColor: StoneColor = currentGame.blackId == ogs.user?.id ? .black : .white
        let players = currentGame.gameData!.players
        let opponent = userColor == .black ? players.white : players.black
        let opponentRank = userColor == .black ? currentGame.whiteFormattedRank : currentGame.blackFormattedRank

        return Group {
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
            self.updateDetailOfCurrentGameIfNecessary()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: currentGame) { newGame in
            DispatchQueue.main.async {
                self.updateDetailOfCurrentGameIfNecessary()
            }
        }
        .onReceive(ogs.$sortedActiveCorrespondenceGames) { sortedActiveGames in
            
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
        }
        return NavigationView {
            GameDetailView(currentGame: games[0], activeGames: games)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .environmentObject(ogs)
//        .previewLayout(.fixed(width: 750, height: 704))
//        .previewLayout(.fixed(width: 1024, height: 768))
//        .previewLayout(.fixed(width: 768, height: 1024))
//        .previewLayout(.fixed(width: 375, height: 812))
//        .previewLayout(.fixed(width: 568, height: 320))
        .colorScheme(.dark)
    }
}
