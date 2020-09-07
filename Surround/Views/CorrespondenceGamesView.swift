//
//  CorrespondenceGamesView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 8/26/20.
//

import SwiftUI
import URLImage
import Combine

struct ActiveGamesCarousel: View {
    @EnvironmentObject var ogs: OGSService
    @Binding var currentGame: Game
    @Namespace var selectingGame
    var activeGames: [Game]
    @State var scrollTarget: GameID?
    @State var discardNextScrollTarget = false
    @State var renderedCurrentGame: PassthroughSubject<Bool, Never> = PassthroughSubject<Bool, Never>()
    @State var renderedCurrentGameCollected: AnyPublisher<[Bool], Never> = PassthroughSubject<[Bool], Never>().eraseToAnyPublisher()

    var body: some View {
        ScrollView(.horizontal) {
            ScrollViewReader { scrollView in
                LazyHStack(spacing: 0) {
                    ForEach(activeGames) { game in
                        VStack(alignment: .trailing) {
                            ZStack(alignment: .center) {
                                if game.clock?.currentPlayerId == ogs.user?.id {
                                    Color(UIColor.systemTeal).cornerRadius(3)
                                } else {
                                    Color(.white)
                                }
                                BoardView(boardPosition: game.currentPosition)
                                    .frame(width: 120, height: 120)
                                    .padding(.horizontal, 5)
                                    .onTapGesture {
                                        withAnimation {
                                            discardNextScrollTarget = true
                                            currentGame = game
                                            scrollTarget = currentGame.ID
                                        }
                                    }
                                if game.ID == currentGame.ID {
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                                        .padding(1)
                                        .foregroundColor(.black)
                                        .matchedGeometryEffect(id: "selectionIndicator", in: selectingGame)
                                }
                            }
                            .frame(width: 130, height: 130)
                        }
                        .padding(.horizontal, 2.5)
                        .id(game.ID)
                        .onChange(of: currentGame) { _ in
                            self.renderedCurrentGame.send(game == currentGame)
                        }
                    }
                }
                .padding(.horizontal, 5)
                .onChange(of: scrollTarget) { target in
                    if let target = target {
                        if discardNextScrollTarget {
                            discardNextScrollTarget = false
                        } else {
                            DispatchQueue.main.async {
                                withAnimation {
                                    scrollView.scrollTo(target, anchor: .leading)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 140)
        .coordinateSpace(name: "ActiveGames")
        .onReceive(renderedCurrentGameCollected) { rendered in
            if rendered.allSatisfy({ !$0 }) {
                if scrollTarget != currentGame.ID {
                    scrollTarget = currentGame.ID
                }
            }
        }
        .onAppear {
            scrollTarget = currentGame.ID
            self.renderedCurrentGameCollected = self.renderedCurrentGame.collect(.byTime(DispatchQueue.main, 1.0)).eraseToAnyPublisher()
        }
    }
}

struct CorrespondenceGamesPlayerInfo: View {
    @EnvironmentObject var ogs: OGSService
    @ObservedObject var currentGame: Game
    var geometry: GeometryProxy

    func playerIcon(color: StoneColor) -> some View {
        let icon = currentGame.playerIcon(for: color, size: 64)
        return VStack {
            ZStack(alignment: .topLeading) {
                if icon != nil {
                    URLImage(URL(string: icon!)!)
                        .frame(width: 64, height: 64)
                        .shadow(radius: 2)
                }
                Stone(color: color, shadowRadius: 1)
                    .frame(width: 20, height: 20)
                    .position(x: 62, y: 62)
            }
            .background(Color.gray)
            .frame(width: 64, height: 64)
        }
    }

    var body: some View {
        let userColor: StoneColor = currentGame.blackId == ogs.user?.id ? .black : .white
        let userCaptures = currentGame.currentPosition.captures[userColor] ?? 0
        let opponentCaptures = currentGame.currentPosition.captures[userColor.opponentColor()] ?? 0

        return VStack {
            HStack {
                playerIcon(color: userColor)
                VStack(alignment: .trailing) {
                    TimerView(timeControl: currentGame.gameData?.timeControl, clock: currentGame.clock, player: userColor)
                    if userCaptures > 0 {
                        Text("\(userCaptures) capture\(userCaptures > 1 ? "s" : "")")
                            .font(Font.caption.monospacedDigit())
                    }
                    if let komi = currentGame.gameData?.komi {
                        if userColor == .white && komi != 0 {
                            Text("\(String(format: "%.1f", komi)) komi")
                                .font(Font.caption.monospacedDigit())
                        }
                    }
                }
                if currentGame.clock?.currentPlayer == userColor {
                    Image(systemName: "hourglass")
                }
                Spacer()
            }
            HStack {
                Spacer()
                if currentGame.clock?.currentPlayer != userColor {
                    Image(systemName: "hourglass")
                }
                VStack(alignment: .trailing) {
                    TimerView(timeControl: currentGame.gameData?.timeControl, clock: currentGame.clock, player: userColor.opponentColor())
                    if opponentCaptures > 0 {
                        Text("\(opponentCaptures) capture\(opponentCaptures > 1 ? "s" : "")")
                            .font(.caption)
                    }
                    if let komi = currentGame.gameData?.komi {
                        if userColor.opponentColor() == .white && komi != 0 {
                            Text("\(String(format: "%.1f", komi)) komi")
                                .font(Font.caption.monospacedDigit())
                        }
                    }
                }
                playerIcon(color: userColor.opponentColor())
            }
            .offset(y: -20)
            .padding(.bottom, -20)
        }
        .padding(.vertical, geometry.size.width <= 375 ? 10 : nil)
        .padding(.horizontal)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color(UIColor.darkGray), Color.white]),
                startPoint: userColor == .black ? .topLeading : .bottomTrailing,
                endPoint: userColor == .black ? .bottomTrailing : .topLeading)
                .shadow(radius: 2)
        )
    }
}

struct CorrespondenceGamesView: View {
    @EnvironmentObject var ogs: OGSService
    @State var currentGame: Game
    @State var pendingMove: Move? = nil
    @State var pendingPosition: BoardPosition? = nil
    @State var submitMoveCancellable: AnyCancellable?
    @State var showingPassAlert = false
    @State var activeGames: [Game] = []
    @State var activeGameByOGSID: [Int: Game] = [:]

    func updateActiveGameList() {
        self.activeGames = []
        for game in ogs.sortedActiveGames {
            self.activeGames.append(game)
            if let ogsID = game.ogsID {
                self.activeGameByOGSID[ogsID] = game
            }
        }
    }

    func submitMove(move: Move) {
        self.submitMoveCancellable = ogs.submitMove(move: move, forGame: currentGame)
            .zip(currentGame.$currentPosition.setFailureType(to: Error.self))
            .sink(receiveCompletion: { _ in
                self.submitMoveCancellable = nil
            }, receiveValue: { _ in
                self.pendingMove = nil
                self.pendingPosition = nil
                self.submitMoveCancellable = nil
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

    var isUserPlaying: Bool {
        guard let user = ogs.user else {
            return false
        }
        return user.id == currentGame.gameData?.blackPlayerId || user.id == currentGame.gameData?.whitePlayerId
    }
    
    var isUserTurn: Bool {
        guard isUserPlaying else {
            return false
        }

        guard currentGame.gameData?.phase == "play" else {
            return false
        }
        
        return (currentGame.clock?.currentPlayer == .black && ogs.user?.id == currentGame.gameData?.blackPlayerId)
            || (currentGame.clock?.currentPlayer == .white && ogs.user?.id == currentGame.gameData?.whitePlayerId)
    }
    
    var undoable: Bool {
        guard isUserPlaying else {
            return false
        }
        
        guard currentGame.gameData?.phase == "play" && currentGame.gameData?.outcome == nil else {
            return false
        }
        
        return !isUserTurn && currentGame.undoRequested == nil && currentGame.currentPosition.lastMoveNumber > 0
    }
    
    var undoacceptable: Bool {
        guard let undoRequested = currentGame.undoRequested else {
            return false
        }
        return isUserTurn && undoRequested == currentGame.currentPosition.lastMoveNumber
    }
    
    var defaultStatus: String {
        if let currentPlayer = currentGame.clock?.currentPlayer {
            return "\(currentPlayer == .black ? "Black" : "White") to move"
        } else {
            return ""
        }
    }
    
    var status: String {
        if let outcome = currentGame.gameData?.outcome {
            if currentGame.gameData?.winner == currentGame.gameData?.blackPlayerId {
                return "Black wins by \(outcome)"
            } else {
                return "White wins by \(outcome)"
            }
        } else {
            if currentGame.undoRequested != nil {
                return "Undo requested"
            }
            if isUserPlaying {
                if isUserTurn {
                    if case .pass = currentGame.currentPosition.lastMove {
                        return "Opponent passed"
                    } else {
                        return "Your move"
                    }
                } else {
                    return "Waiting for opponent"
                }
            } else {
                return defaultStatus
            }
        }
    }
    
    var controlRow: some View {
        HStack(alignment: .firstTextBaseline) {
            if undoacceptable {
                Menu {
                    Button(action: { ogs.acceptUndo(game: currentGame, moveNumber: currentGame.undoRequested!) }) {
                        Label("Accept undo", systemImage: "arrow.uturn.left")
                    }
                }
                label: {
                    Text("\(status) ▾").font(Font.title2.bold())
                }
            } else {
                Text(status).font(Font.title2.bold())
            }
            Spacer()
            if submitMoveCancellable == nil {
                if let pendingMove = pendingMove {
                    Button(action: {
                        submitMove(move: pendingMove)
                    }) {
                        Text("Submit move")
                    }
                } else {
                    if isUserTurn {
                        Button(action: { self.showingPassAlert = true }) {
                            Text("Pass")
                        }
                    } else {
                        if ogs.sortedActiveGamesOnUserTurn.count > 0 {
                            Button(action: goToNextGame) {
                                HStack(alignment: .firstTextBaseline, spacing: 2) {
                                    Text("Next")
                                    Text("(\(ogs.sortedActiveGamesOnUserTurn.count))")
                                        .font(Font.caption2.bold())
                                }
                            }
                        }
                    }
                }
            } else {
                ProgressView().alignmentGuide(.firstTextBaseline, computeValue: { viewDimension in
                    viewDimension.height
                })
            }
            Menu {
                Button(action: { ogs.requestUndo(game: currentGame) }) {
                    Label("Request undo", systemImage: "arrow.uturn.left")
                }.disabled(!undoable)
                Button(action: { UIApplication.shared.open(currentGame.ogsURL!) }) {
                    Label("Open in browser", systemImage: "safari")
                }
                Button(action: {}) {
                    Label("Resign", systemImage: "flag").accentColor(.red)
                }
            }
            label: {
                Label("More actions", systemImage: "ellipsis.circle.fill").labelStyle(IconOnlyLabelStyle())
            }
//            .frame(minHeight: 44)
            .padding(.leading)
        }
        .padding(.horizontal)
    }
    
    var body: some View {
        let userColor: StoneColor = currentGame.blackId == ogs.user?.id ? .black : .white
        let players = currentGame.gameData!.players
        let opponent = userColor == .black ? players.white : players.black
        
        return GeometryReader { geometry -> AnyView in
            let boardSize = min(geometry.size.width, geometry.size.height)
            return AnyView(VStack(alignment: .leading) {
                CorrespondenceGamesPlayerInfo(currentGame: currentGame, geometry: geometry)
                Spacer()
                controlRow
                Spacer()
                BoardView(
                    boardPosition: currentGame.currentPosition,
                    editable: isUserTurn,
                    newMove: $pendingMove,
                    newPosition: $pendingPosition
                )
                .frame(width: boardSize, height: boardSize)
                if geometry.size.height / geometry.size.width > 1.8 {
                    ActiveGamesCarousel(currentGame: $currentGame, activeGames: activeGames)
                }
            })
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {}) {
                    Label("Active games carousel", systemImage: "squares.below.rectangle")
                }
            }
        }
//        .frame(maxHeight: .infinity)
        .alert(isPresented: $showingPassAlert) {
            Alert(
                title: Text("Are you sure you want to pass?"),
                message: nil,
                primaryButton: .destructive(Text("Pass")) {
                    self.submitMove(move: .pass)
                },
                secondaryButton: .cancel(Text("Cancel"))
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("vs \(opponent.username)")
        .onAppear {
            updateActiveGameList()
            for game in activeGames {
                ogs.updateDetailsOfConnectedGame(game: game)
            }
        }
        .onReceive(ogs.$sortedActiveGames) { sortedActiveGames in
            
        }
    }
}

struct CorrespondenceGamesView_Previews: PreviewProvider {
    static var previews: some View {
        let games = [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2, TestData.Ongoing19x19wBot3]
        return NavigationView {
            CorrespondenceGamesView(currentGame: games[0], activeGames: games)
                .environmentObject(
                    OGSService.previewInstance(
                        user: OGSUser(username: "kata-bot", id: 592684),
                        activeGames: games
                    )
                )
        }
    }
}
