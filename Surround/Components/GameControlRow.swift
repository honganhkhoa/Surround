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
    @ObservedObject var game: Game
    var horizontal = true
    var pendingMove: Binding<Move?> = .constant(nil)
    var pendingPosition: Binding<BoardPosition?> = .constant(nil)
    var goToNextGame: (() -> ())?
    @State var ogsRequestCancellable: AnyCancellable?
    var stoneRemovalOption: Binding<StoneRemovalOption> = .constant(.toggleGroup)
    var stoneRemovalSelectedPoints: Binding<Set<[Int]>> = .constant(Set<[Int]>())

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
    
    func toggleRemovedStones(stones: Set<[Int]>) {
        self.ogsRequestCancellable = ogs.toggleRemovedStones(stones: stones, forGame: game)
            .zip(game.currentPosition.$removedStones.setFailureType(to: Error.self))
            .sink(receiveCompletion: { _ in
                DispatchQueue.main.async {
                    self.ogsRequestCancellable = nil
                }
            }, receiveValue: { _ in
                DispatchQueue.main.async {
                    self.stoneRemovalSelectedPoints.wrappedValue.removeAll()
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
    
    var statusText: some View {
        Group {
            if game.undoacceptable {
                Menu {
                    Button(action: { ogs.acceptUndo(game: game, moveNumber: game.undoRequested!) }) {
                        Label("Accept undo", systemImage: "arrow.uturn.left")
                    }
                }
                label: {
                    Text("\(game.status) ▾").font(Font.title2.bold())
                }
            } else {
                Text(game.status).font(Font.title2.bold())
                    .allowsTightening(true)
                    .minimumScaleFactor(0.7)
            }
        }
    }
    
    var actionButtons: some View {
        HStack(spacing: 0) {
            if ogsRequestCancellable == nil {
                let isUserTurnToPlay = game.gamePhase == .play && game.isUserTurn
                let userNeedsToAcceptStoneRemoval = game.gamePhase == .stoneRemoval
                    && game.removedStonesAccepted[userColor] != game.currentPosition.removedStones
                Group {
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
                }
                .padding(10)
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .hoverEffect(.highlight)
            } else {
                ProgressView().alignmentGuide(.firstTextBaseline, computeValue: { viewDimension in
                    viewDimension.height
                })
            }
            Menu {
                if game.gamePhase == .play {
                    Button(action: { ogs.requestUndo(game: game) }) {
                        Label("Request undo", systemImage: "arrow.uturn.left")
                    }.disabled(!game.undoable)
                    if game.pauseControl?.userPauseDetail == nil {
                        Button(action: { ogs.pause(game: game) }) {
                            Label("Pause game", systemImage: "pause")
                        }
                    } else {
                        Button(action: { ogs.resume(game: game) }) {
                            Label("Resume game", systemImage: "play")
                        }
                    }
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
                    .padding(15)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .hoverEffect(.highlight)
            
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
    
    var rowHeight: CGFloat = NSString(string: "Ilp").boundingRect(with: CGSize(width: 1024, height: 768), attributes: [.font: UIFont.preferredFont(forTextStyle: .title2)], context: nil).size.height

    var body: some View {
        Group {
            if horizontal {
                HStack {
                    statusText
                    Spacer(minLength: 0)
                    actionButtons
                }
                .padding([.trailing], -15)
                .frame(height: rowHeight)
            } else {
                VStack(alignment: .trailing, spacing: 0) {
                    statusText
                        .frame(height: rowHeight)
                    actionButtons
                        .padding([.trailing], -15)
                }
            }
        }
        .onChange(of: stoneRemovalSelectedPoints.wrappedValue) { selectedPoints in
            self.toggleRemovedStones(stones: selectedPoints)
        }
    }
}

struct GameControlRow_Previews: PreviewProvider {
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
            GameControlRow(game: games[2])
                .previewLayout(.fixed(width: 320, height: 60))
        }
        .environmentObject(ogs)
    }
}
