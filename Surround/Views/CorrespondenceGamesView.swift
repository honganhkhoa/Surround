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
    @State var activeGames: [Game] = []
    @Namespace var selectingGame

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(self.activeGames) { game in
                    VStack(alignment: .trailing) {
                        ZStack(alignment: .center) {
                            if game.clock?.currentPlayerId == ogs.user?.id {
                                Color(UIColor.systemTeal).cornerRadius(3)
                            }
                            BoardView(boardPosition: game.currentPosition)
                                .frame(width: 120, height: 120)
                                .padding(.horizontal, 5)
                                .onTapGesture {
                                    withAnimation {
                                        currentGame = game
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
                        InlineTimerView(
                            timeControl: game.gameData?.timeControl,
                            clock: game.clock,
                            player: game.blackId == ogs.user?.id ? .black : .white,
                            mainFont: Font.caption.monospacedDigit(),
                            subFont: Font.caption2.monospacedDigit()
                        )
                        .padding(0)
                        .offset(x: -5)
                    }.padding(.horizontal, 2.5)
                }
            }
            .padding(.horizontal, 5)
        }
        .frame(height: 160)
        .onAppear {
            self.activeGames = ogs.sortedActiveGamesOnUserTurn + ogs.sortedActiveGamesNotOnUserTurn
        }
    }
}

struct CorrespondenceGamesPlayerInfo: View {
    @EnvironmentObject var ogs: OGSService
    var currentGame: Game
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
        .padding(.vertical, geometry.size.width <= 320 ? 10 : nil)
        .padding(.horizontal)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color(UIColor.darkGray), Color.white]),
                startPoint: userColor == .black ? .topLeading : .bottomTrailing,
                endPoint: userColor == .black ? .bottomTrailing : .topLeading)
        )
    }
}

struct CorrespondenceGamesView: View {
    @EnvironmentObject var ogs: OGSService
    @StateObject var currentGame: Game
    @State var pendingMove: Move? = nil
    @State var pendingPosition: BoardPosition? = nil
    @State var submitMoveCancellable: AnyCancellable?
    @State var showingPassAlert = false
    
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
    
    var body: some View {
        let userColor: StoneColor = currentGame.blackId == ogs.user?.id ? .black : .white
        let players = currentGame.gameData!.players
        let opponent = userColor == .black ? players.white : players.black
        
        return GeometryReader { geometry -> AnyView in
            let boardSize = min(geometry.size.width, geometry.size.height)
            return AnyView(VStack(alignment: .leading) {
//                ActiveGamesCarousel(currentGame: $currentGame)
//                    .padding(.top)
                CorrespondenceGamesPlayerInfo(currentGame: currentGame, geometry: geometry)
                Spacer()
                HStack {
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
                        } else if isUserTurn {
                            Button(action: { self.showingPassAlert = true }) {
                                Text("Pass")
                            }
                        }
                    } else {
                        ProgressView()
                    }
                    Menu {
                        if undoable {
                            Button(action: { ogs.requestUndo(game: currentGame) }) {
                                Label("Request undo", systemImage: "arrow.uturn.left")
                            }
                        }
                        Button(action: {}) {
                            Label("Resign", systemImage: "flag").accentColor(.red)
                        }
                    }
                    label: {
                        Label("More actions", systemImage: "ellipsis.circle.fill").labelStyle(IconOnlyLabelStyle())
                    }
                    .frame(minHeight: 44)
                    .padding(.leading)
                }
                .padding(.horizontal)
                Spacer()
                BoardView(
                    boardPosition: currentGame.currentPosition,
                    editable: isUserTurn,
                    newMove: $pendingMove,
                    newPosition: $pendingPosition
                ).frame(width: boardSize, height: boardSize)
            })
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {}) {
                    Label("Active games carousel", systemImage: "squares.below.rectangle")
                }
            }
        }
        .frame(maxHeight: .infinity)
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
    }
}

struct CorrespondenceGamesView_Previews: PreviewProvider {
    static var previews: some View {
        let games = [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2, TestData.Ongoing19x19wBot3]
        return NavigationView {
            CorrespondenceGamesView(currentGame: games[1])
                .environmentObject(
                    OGSService.previewInstance(
                        user: OGSUser(username: "kata-bot", id: 592684),
                        activeGames: games
                    )
                )
        }
    }
}
