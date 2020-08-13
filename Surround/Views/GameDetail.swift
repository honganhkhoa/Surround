//
//  GameDetail.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/13/20.
//

import SwiftUI
import URLImage
import Combine

struct PlayerInfo: View {
    @ObservedObject var game: Game
    var player: StoneColor
    
    var body: some View {
        let icon: String? = game.playerIcon(for: player, size: 64)
        return VStack(alignment: .leading) {
            HStack(alignment: .top) {
                ZStack(alignment: .topLeading) {
                    if icon != nil {
                        URLImage(URL(string: icon!)!)
                            .frame(width: 64, height: 64)
                    }
                    Stone(color: player, shadowRadius: 1)
                        .frame(width: 20, height: 20)
                        .position(x: 62, y: 62)
                }
                .background(Color.gray)
                .frame(width: 64, height: 64)
                Spacer()
                TimerView(timeControl: game.gameData?.timeControl, clock: game.clock, player: player)
            }
            Text(player == .black ? game.blackName : game.whiteName)
                .font(Font.caption.bold())
            +
            Text(" (\(player == .black ? game.blackFormattedRank : game.whiteFormattedRank))")
                .font(.caption)
        }
    }
}

struct GameDetail: View {
    @EnvironmentObject var ogs: OGSService
    @ObservedObject var game: Game
    @State var gameDetailCancellable: AnyCancellable?
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
                self.pendingMove = nil
                self.pendingPosition = nil
                self.submitMoveCancellable = nil
            })
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

        guard game.gameData?.phase == "play" else {
            return false
        }
        
        return (game.clock?.currentPlayer == .black && ogs.user?.id == game.gameData?.blackPlayerId)
            || (game.clock?.currentPlayer == .white && ogs.user?.id == game.gameData?.whitePlayerId)
    }
    
    var undoable: Bool {
        guard isUserPlaying else {
            return false
        }
        
        guard game.gameData?.phase == "play" && game.gameData?.outcome == nil else {
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
                        return "Your move - opponent passed"
                    } else {
                        return "Your move"
                    }
                } else {
                    return defaultStatus
                }
            } else {
                return defaultStatus
            }
        }
    }
    
    var body: some View {
        return VStack(alignment: .center) {
            HStack {
                PlayerInfo(game: game, player: .black)
                Spacer()
                Divider()
                PlayerInfo(game: game, player: .white)
                Spacer()
            }.padding()
            HStack {
                Text(status)
                    .font(.headline).bold()
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
            }
            BoardView(
                boardPosition: game.currentPosition,
                editable: isUserTurn,
                newMove: $pendingMove,
                newPosition: $pendingPosition
            ).layoutPriority(1)
            if undoable {
                Button(action: { ogs.requestUndo(game: game) }) {
                    Text("Request undo")
                }
            }
            if undoacceptable {
                Button(action: { ogs.acceptUndo(game: game, moveNumber: game.undoRequested!) }) {
                    Text("Accept undo")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
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

struct GameDetail_Previews: PreviewProvider {
    static var previews: some View {
        let game = TestData.Resigned19x19HandicappedWithInitialState
        let ongoingGame = TestData.Ongoing19x19HandicappedWithNoInitialState
        let pendingMove = Move.placeStone(8, 14)
        let pendingPosition = try! ongoingGame.currentPosition.makeMove(move: pendingMove)
        return Group {
            GameDetail(game: game)
            GameDetail(game: ongoingGame, pendingMove: pendingMove, pendingPosition: pendingPosition)
        }.environmentObject(OGSService.previewInstance(user: OGSUser(username: ongoingGame.blackName, id: ongoingGame.blackId!)))
    }    
}
