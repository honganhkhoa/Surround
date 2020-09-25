//
//  CorrespondenceGamesView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 8/26/20.
//

import SwiftUI
import Combine

struct CorrespondenceGamesView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var ogs: OGSService
    @State var currentGame: Game
    @State var pendingMove: Move? = nil
    @State var pendingPosition: BoardPosition? = nil
    @State var ogsRequestCancellable: AnyCancellable?
    @State var activeGames: [Game] = []
    @State var activeGameByOGSID: [Int: Game] = [:]
    @State var stoneRemovalSelectedPoints = Set<[Int]>()
    @State var stoneRemovalOption = StoneRemovalOption.toggleGroup

    func updateActiveGameList() {
        self.activeGames = []
        for game in ogs.sortedActiveCorrespondenceGames {
            self.activeGames.append(game)
            if let ogsID = game.ogsID {
                self.activeGameByOGSID[ogsID] = game
            }
        }
    }

    func toggleRemovedStones(stones: Set<[Int]>) {
        self.ogsRequestCancellable = ogs.toggleRemovedStones(stones: stones, forGame: currentGame)
            .zip(currentGame.currentPosition.$removedStones.setFailureType(to: Error.self))
            .sink(receiveCompletion: { _ in
                DispatchQueue.main.async {
                    self.ogsRequestCancellable = nil
                }
            }, receiveValue: { _ in
                DispatchQueue.main.async {
                    self.stoneRemovalSelectedPoints.removeAll()
                    self.ogsRequestCancellable = nil
                }
            })
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
    
    var controlRow: some View {
        GameControlRow(
            game: currentGame,
            pendingMove: $pendingMove,
            pendingPosition: $pendingPosition,
            goToNextGame: goToNextGame
        )
    }
    
    var verticalControlRow: some View {
        GameControlRow(
            game: currentGame,
            horizontal: false,
            pendingMove: $pendingMove,
            pendingPosition: $pendingPosition,
            goToNextGame: goToNextGame,
            stoneRemovalOption: $stoneRemovalOption
        )
    }
    
    var boardView: some View {
        BoardView(
            boardPosition: currentGame.currentPosition,
            playable: currentGame.isUserTurn,
            stoneRemovable: currentGame.isUserPlaying && currentGame.gamePhase == .stoneRemoval,
            stoneRemovalOption: stoneRemovalOption,
            newMove: $pendingMove,
            newPosition: $pendingPosition,
            stoneRemovalSelectedPoints: $stoneRemovalSelectedPoints
        )
    }
    
    func userColor(in game: Game) -> StoneColor {
        return ogs.user?.id == game.blackId ? .black : .white
    }
    
    var compactBody: some View {
        GeometryReader { geometry -> AnyView in
            print("Geometry \(geometry.size)")
            
            let boardSize: CGFloat = min(geometry.size.width, geometry.size.height)
            let controlRowHeight: CGFloat = NSString(string: "Waiting for Opponent").boundingRect(with: geometry.size, attributes: [.font: UIFont.preferredFont(forTextStyle: .title2)], context: nil).size.height
            let usableHeight: CGFloat = geometry.size.height
            let playerInfoHeight: CGFloat = 64 + 64 - 10 + 15 * 2
            let spacing: CGFloat = 10.0
            let remainingHeight: CGFloat = usableHeight - boardSize - controlRowHeight - playerInfoHeight - (spacing * 2)
            let showsActiveGamesCarousel = remainingHeight >= 140 || (remainingHeight + geometry.safeAreaInsets.bottom * 2 / 3 >= 140)
            let reducedPlayerInfoVerticalPadding = (showsActiveGamesCarousel && remainingHeight <= 150) || remainingHeight < 0

            return AnyView(erasing: VStack(alignment: .leading) {
//                Text("\(usableHeight) \(controlRowHeight) \(remainingHeight)")
                PlayersBannerView(game: currentGame, topLeftPlayerColor: self.userColor(in: currentGame).opponentColor(), reduceVerticalPadding: reducedPlayerInfoVerticalPadding)
                Spacer(minLength: spacing)
                controlRow
                    .padding(.horizontal)
                Spacer(minLength: spacing)
                boardView.frame(width: boardSize, height: boardSize)
                if showsActiveGamesCarousel {
                    ActiveCorrespondenceGamesCarousel(currentGame: $currentGame, activeGames: activeGames)
                }
            })
        }
    }
    
    var regularBody: some View {
        GeometryReader { geometry -> AnyView in
            let width = geometry.size.width
            let height = geometry.size.height - 140 - 15 * 2
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
            return AnyView(erasing: VStack(spacing: 0) {
                ActiveCorrespondenceGamesCarousel(currentGame: $currentGame, activeGames: activeGames)
                Spacer(minLength: 0)
                if horizontal {
                    HStack(alignment: .top, spacing: 15) {
                        VStack(alignment: .trailing) {
                            PlayersBannerView(game: currentGame, topLeftPlayerColor: self.userColor(in: currentGame).opponentColor(), playerIconSize: 80, playerIconsOffset: playerIconsOffset, showsPlayersName: true)
                                .frame(minWidth: 300)
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
                        PlayersBannerView(game: currentGame, topLeftPlayerColor: self.userColor(in: currentGame).opponentColor(), playerIconSize: 80, playerIconsOffset: -80, showsPlayersName: true)
                        Spacer(minLength: 15)
                        controlRow
                        Spacer(minLength: 15)
                        boardView.frame(width: boardSizeLimit, height: boardSizeLimit)
                    }
                    .padding()
                    .frame(maxWidth: boardSizeLimit + 15 * 2)
                }
                Spacer(minLength: 0)
            })
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
                Button(action: {}) {
                    Label("Active games carousel", systemImage: "gearshape.2")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("vs \(opponent.username) [\(opponentRank)]")
        .onAppear {
            updateActiveGameList()
            for game in activeGames {
                ogs.updateDetailsOfConnectedGame(game: game)
            }
        }
        .onChange(of: currentGame) { _ in
            self.pendingMove = nil
            self.pendingPosition = nil
        }
        .onChange(of: stoneRemovalSelectedPoints) { selectedPoints in
            self.toggleRemovedStones(stones: selectedPoints)
        }
        .onReceive(ogs.$sortedActiveCorrespondenceGames) { sortedActiveGames in
            
        }
    }
}

struct CorrespondenceGamesView_Previews: PreviewProvider {
    static var previews: some View {
        let games = [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2, TestData.Ongoing19x19wBot3]
        return NavigationView {
            CorrespondenceGamesView(currentGame: games[0], activeGames: games)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .environmentObject(
            OGSService.previewInstance(
                user: OGSUser(username: "kata-bot", id: 592684),
                activeGames: games
            )
        )
//        .previewLayout(.fixed(width: 750, height: 704))
//        .previewLayout(.fixed(width: 1024, height: 768))
//        .previewLayout(.fixed(width: 768, height: 1024))
//        .previewLayout(.fixed(width: 375, height: 812))
//        .previewLayout(.fixed(width: 568, height: 320))
        .colorScheme(.dark)
    }
}
