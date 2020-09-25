//
//  GameControlRow.swift
//  Surround
//
//  Created by Anh Khoa Hong on 9/25/20.
//

import SwiftUI
import Combine

struct GameControlRow: View {
    @EnvironmentObject var ogs: OGSService
    var game: Game
    var horizontal = true
    var pendingMove: Binding<Move?> = .constant(nil)
    var pendingPosition: Binding<BoardPosition?> = .constant(nil)
    var goToNextGame: (() -> ())?
    @State var ogsRequestCancellable: AnyCancellable?
    var stoneRemovalOption: Binding<StoneRemovalOption> = .constant(.toggleGroup)

    @State var showingPassAlert = false
    @State var showingResumeFromStoneRemovalAlert = false

    var userColor: StoneColor {
        return ogs.user?.id == game.blackId ? .black : .white
    }
    
    func submitMove(move: Move) {
        self.ogsRequestCancellable = ogs.submitMove(move: move, forGame: game)
            .zip(game.$currentPosition.setFailureType(to: Error.self))
            .sink(receiveCompletion: { _ in
                DispatchQueue.main.async {
                    self.ogsRequestCancellable = nil
                }
            }, receiveValue: { _ in
                DispatchQueue.main.async {
                    self.pendingMove.wrappedValue = nil
                    self.pendingPosition.wrappedValue = nil
                    self.ogsRequestCancellable = nil
                }
            })
    }
    
    func acceptRemovedStones() {
        ogs.acceptRemovedStone(game: game)
        self.ogsRequestCancellable = game.$removedStonesAccepted.sink(receiveValue: { _ in
            self.ogsRequestCancellable = nil
        })
    }
    
    func resumeGameFromStoneRemoval() {
        ogs.resumeGameFromStoneRemoval(game: game)
        self.ogsRequestCancellable = game.$gamePhase.sink(receiveValue: { _ in
            self.ogsRequestCancellable = nil
        })
    }
    
    var undoable: Bool {
        guard game.isUserPlaying else {
            return false
        }
        
        guard game.gamePhase == .play && game.gameData?.outcome == nil else {
            return false
        }
        
        return !game.isUserTurn && game.undoRequested == nil && game.currentPosition.lastMoveNumber > 0
    }
    
    var undoacceptable: Bool {
        guard let undoRequested = game.undoRequested else {
            return false
        }
        return game.isUserTurn && undoRequested == game.currentPosition.lastMoveNumber
    }
    
    var defaultStatus: String {
        if let currentPlayer = game.clock?.currentPlayer {
            return "\(currentPlayer == .black ? "Black" : "White") to move"
        } else {
            return ""
        }
    }
    
    var status: String {
        if let outcome = game.gameData?.outcome {
            if game.gameData?.winner == game.gameData?.blackPlayerId {
                return "Black wins by \(outcome)"
            } else {
                return "White wins by \(outcome)"
            }
        } else {
            if game.gamePhase == .stoneRemoval {
                return "Stone Removal Phase"
            }
            if game.undoRequested != nil {
                return "Undo requested"
            }
            if game.isUserPlaying {
                if game.isUserTurn {
                    if case .pass = game.currentPosition.lastMove {
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
    
    var statusText: some View {
        Group {
            if undoacceptable {
                Menu {
                    Button(action: { ogs.acceptUndo(game: game, moveNumber: game.undoRequested!) }) {
                        Label("Accept undo", systemImage: "arrow.uturn.left")
                    }
                }
                label: {
                    Text("\(status) ▾").font(Font.title2.bold())
                }
            } else {
                Text(status).font(Font.title2.bold())
                    .allowsTightening(true)
                    .minimumScaleFactor(0.7)
            }
        }
    }
    
    var actionButtons: some View {
        HStack(alignment: .firstTextBaseline) {
            if ogsRequestCancellable == nil {
                let isUserTurnToPlay = game.gamePhase == .play && game.isUserTurn
                let userNeedsToAcceptStoneRemoval = game.gamePhase == .stoneRemoval
                    && game.removedStonesAccepted[userColor] != game.currentPosition.removedStones
                if isUserTurnToPlay {
                    if let pendingMove = pendingMove.wrappedValue {
                        Button(action: { submitMove(move: pendingMove)}) {
                            Text("Submit move")
                        }
                    } else {
                        Button(action: { self.showingPassAlert = true }) {
                            Text("Pass")
                        }
                    }
                } else if userNeedsToAcceptStoneRemoval {
                    Button(action: { acceptRemovedStones() }) {
                        Text("Accept")
                    }
                } else {
                    if let goToNextGame = goToNextGame {
                        if ogs.sortedActiveCorrespondenceGamesOnUserTurn.count > 0 {
                            Button(action: goToNextGame) {
                                HStack(alignment: .firstTextBaseline, spacing: 2) {
                                    Text("Next")
                                    Text("(\(ogs.sortedActiveCorrespondenceGamesOnUserTurn.count))")
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
                if game.gamePhase == .play {
                    Button(action: { ogs.requestUndo(game: game) }) {
                        Label("Request undo", systemImage: "arrow.uturn.left")
                    }.disabled(!undoable)
                } else if game.gamePhase == .stoneRemoval {
                    Picker(selection: stoneRemovalOption, label: Text("Stone removal option")) {
                        Text("Toggle group").tag(StoneRemovalOption.toggleGroup)
                        Text("Toggle single point").tag(StoneRemovalOption.toggleSinglePoint)
                    }
                    Button(action: { self.showingResumeFromStoneRemovalAlert = true }) {
                        Label("Resume game", systemImage: "play")
                    }
                }
                Button(action: { UIApplication.shared.open(game.ogsURL!) }) {
                    Label("Open in browser", systemImage: "safari")
                }
                Button(action: {}) {
                    Label("Resign", systemImage: "flag").accentColor(.red)
                }
            }
            label: {
                Label("More actions", systemImage: "ellipsis.circle.fill").labelStyle(IconOnlyLabelStyle())
            }
            .padding(.leading)
            
            // Putting these inside conditional views above does not seem to work well
            Rectangle().frame(width: 0, height: 0)
                .alert(isPresented: $showingResumeFromStoneRemovalAlert) {
                    Alert(
                        title: Text("Are you sure you want to resume the game?"),
                        message: nil,
                        primaryButton: .destructive(Text("Resume")) {
                            self.resumeGameFromStoneRemoval()
                        },
                        secondaryButton: .cancel(Text("Cancel"))
                    )
                }
            Rectangle().frame(width: 0, height: 0)
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

        }
    }
    
    var body: some View {
        if horizontal {
            HStack(alignment: .firstTextBaseline) {
                statusText
                Spacer()
                actionButtons
            }
        } else {
            VStack(alignment: .trailing) {
                statusText
                actionButtons
            }
        }
    }
}

struct GameControlRow_Previews: PreviewProvider {
    static var previews: some View {
        let games = [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2, TestData.Ongoing19x19wBot3]
        return Group {
            GameControlRow(game: games[0])
                .previewLayout(.fixed(width: 320, height: 80))
        }
        .environmentObject(
            OGSService.previewInstance(
                user: OGSUser(username: "kata-bot", id: 592684),
                activeGames: games
            )
        )
    }
}
