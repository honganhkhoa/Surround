//
//  LiveGameView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 9/11/20.
//

import SwiftUI
import Combine

struct LiveGameView: View {
    @EnvironmentObject var ogs: OGSService
    @ObservedObject var game: Game
    @State var pendingMove: Move? = nil
    @State var pendingPosition: BoardPosition? = nil
    @State var submitMoveCancellable: AnyCancellable?
    @State var showingPassAlert = false

    func submitMove(move: Move) {
        self.submitMoveCancellable = ogs.submitMove(move: move, forGame: game)
            .zip(game.$currentPosition.setFailureType(to: Error.self))
            .sink(receiveCompletion: { _ in
                self.submitMoveCancellable = nil
            }, receiveValue: { _ in
                DispatchQueue.main.async {
                    self.pendingMove = nil
                    self.pendingPosition = nil
                    self.submitMoveCancellable = nil
                }
            })
    }

    var userColor: StoneColor {
        ogs.user?.id == game.blackId ? .black : .white
    }
    
    var isUserPlaying: Bool {
        guard let user = ogs.user else {
            return false
        }
        return user.id == game.gameData?.blackPlayerId || user.id == game.gameData?.whitePlayerId
    }
    
    var isUserTurn: Bool {
        guard isUserPlaying else {
            return false
        }

        guard game.gamePhase == .play else {
            return false
        }
        
        return (game.clock?.currentPlayer == .black && ogs.user?.id == game.gameData?.blackPlayerId)
            || (game.clock?.currentPlayer == .white && ogs.user?.id == game.gameData?.whitePlayerId)
    }
    
    var undoable: Bool {
        guard isUserPlaying else {
            return false
        }
        
        guard game.gamePhase == .play && game.gameData?.outcome == nil else {
            return false
        }
        
        return !isUserTurn && game.undoRequested == nil && game.currentPosition.lastMoveNumber > 0
    }
    
    var undoacceptable: Bool {
        guard let undoRequested = game.undoRequested else {
            return false
        }
        return isUserTurn && undoRequested == game.currentPosition.lastMoveNumber
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
            if game.undoRequested != nil {
                return "Undo requested"
            }
            if isUserPlaying {
                if isUserTurn {
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
            }
        }
    }
    
    var actionButtons: some View {
        HStack(alignment: .firstTextBaseline) {
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
                    }
                }
            } else {
                ProgressView().alignmentGuide(.firstTextBaseline, computeValue: { viewDimension in
                    viewDimension.height
                })
            }
            Menu {
                Button(action: { ogs.requestUndo(game: game) }) {
                    Label("Request undo", systemImage: "arrow.uturn.left")
                }.disabled(!undoable)
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
        }
    }
    
    var controlRow: some View {
        HStack(alignment: .firstTextBaseline) {
            statusText
            Spacer()
            actionButtons
        }
    }
    
    var boardView: some View {
        BoardView(
            boardPosition: game.currentPosition,
            playable: isUserTurn,
            newMove: $pendingMove,
            newPosition: $pendingPosition
        )
    }
    
    var body: some View {
        return VStack {
            PlayersBannerView(game: game, topLeftPlayerColor: userColor)
            controlRow
                .padding(.horizontal)
            boardView
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ogs.updateDetailsOfConnectedGame(game: game)
        }
    }
}

struct LiveGameView_Previews: PreviewProvider {
    static var previews: some View {
        let games = [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2, TestData.Ongoing19x19wBot3]
        return Group {
            NavigationView {
                LiveGameView(game: games[0])
            }
        }
        .environmentObject(
            OGSService.previewInstance(
                user: OGSUser(username: "kata-bot", id: 592684),
                activeGames: games
            )
        )
    }
}
