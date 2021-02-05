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
    @State var showingResignAlert = false
    @State var showingCancelAlert = false
    
    @Setting(.autoSubmitForLiveGames) var autoSubmitForLiveGames: Bool
    @Setting(.autoSubmitForCorrespondenceGames) var autoSubmitForCorrespondenceGames: Bool

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
    
    func estimateTerritory() {
        pendingMove.wrappedValue = nil
        pendingPosition.wrappedValue = nil
        self.ogsRequestCancellable = game.currentPosition.estimateTerritory(on: game.computeQueue)
            .receive(on: DispatchQueue.main)
            .sink { estimatedTerritory in
                game.currentPosition.estimatedScores = estimatedTerritory
                self.ogsRequestCancellable = nil
            }
    }
    
    func clearEstimatedTerritory() {
        game.currentPosition.estimatedScores = nil
        game.objectWillChange.send()
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
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.7)
            }
        }
    }
    
    var actionsMenu: some View {
        Menu {
            Section {
                if game.gamePhase == .play {
                    Button(action: { self.estimateTerritory() }) {
                        Label("Estimate score", systemImage: "dot.squareshape.split.2x2")
                    }.disabled(
                        game.isUserPlaying
                        && (game.gameData?.disableAnalysis ?? false)
                    )
                }
                if game.isUserPlaying {
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
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            Section {
                Button(action: { UIApplication.shared.open(game.ogsURL!) }) {
                    Label("Open in browser", systemImage: "safari")
                }
            }
            if game.isUserPlaying {
                Section {
                    if game.canBeCancelled {
                        Button(action: { self.showingCancelAlert = true }) {
                            Label("Cancel game", systemImage: "xmark").foregroundColor(.red)
                        }
                    } else {
                        Button(action: { self.showingResignAlert = true }) {
                            Label("Resign", systemImage: "flag").foregroundColor(.red)
                        }
                    }
                }
            }
        }
        label: {
            Label("More actions", systemImage: "ellipsis.circle.fill").labelStyle(IconOnlyLabelStyle())
                .padding(15)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .hoverEffect(.highlight)
    }
    
    var mainActionButton: some View {
        Group {
            if ogsRequestCancellable == nil {
                let isUserTurnToPlay = game.gamePhase == .play && game.isUserTurn
                let userNeedsToAcceptStoneRemoval =
                    game.isUserPlaying
                    && game.gamePhase == .stoneRemoval
                    && game.removedStonesAccepted[userColor] != game.currentPosition.removedStones
                let isHandicapPlacement = (game.gameData?.freeHandicapPlacement ?? false) && (game.currentPosition.lastMoveNumber < (game.gameData?.handicap ?? 0))
                Group {
                    if game.currentPosition.estimatedScores != nil {
                        Button(action: { clearEstimatedTerritory() }) {
                            Text("Clear estimates")
                                .minimumScaleFactor(0.7)
                        }
                    } else if isUserTurnToPlay {
                        if let pendingMove = pendingMove.wrappedValue {
                            Button(action: { submitMove(move: pendingMove)}) {
                                Text("Submit move")
                            }
                        } else if !isHandicapPlacement {
                            Button(action: { self.showingPassAlert = true }) {
                                Text("Pass")
                            }
                        }
                    } else if userNeedsToAcceptStoneRemoval {
                        Button(action: { acceptRemovedStones() }) {
                            Text("Accept")
                        }
                    } else if game.isUserPlaying && game.gameData?.timeControl.speed == .correspondence {
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
        }
    }
    
    var actionButtons: some View {
        HStack(spacing: 0) {
            mainActionButton
            
            actionsMenu
            
            // Putting these inside conditional views above does not seem to work well
            Rectangle().frame(width: 0, height: 0)
                .alert(isPresented: $showingResumeFromStoneRemovalAlert) {
                    Alert(
                        title: Text("Are you sure you want to resume the game?"),
                        message: nil,
                        primaryButton: .destructive(Text("Resume")) {
                            self.resumeGameFromStoneRemoval()
                        },
                        secondaryButton: .cancel(Text("Dismiss"))
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
                        secondaryButton: .cancel(Text("Dismiss"))
                    )
                }
            Rectangle().frame(width: 0, height: 0)
                .alert(isPresented: $showingResignAlert) {
                    Alert(
                        title: Text("Are you sure you want to resign this game?"),
                        message: nil,
                        primaryButton: .destructive(Text("Resign")) {
                            ogs.resign(game: game)
                        },
                        secondaryButton: .cancel(Text("Dismiss"))
                    )
                }
            Rectangle().frame(width: 0, height: 0)
                .alert(isPresented: $showingCancelAlert) {
                    Alert(
                        title: Text("Are you sure you want to cancel this game?"),
                        message: nil,
                        primaryButton: .destructive(Text("Cancel game")) {
                            ogs.cancel(game: game)
                        },
                        secondaryButton: .cancel(Text("Dismiss"))
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
        .onChange(of: pendingMove.wrappedValue) { newPendingMove in
            if let newPendingMove = newPendingMove {
                if let timeControl = game.gameData?.timeControl {
                    var shouldAutoSubmitMove = timeControl.speed == .correspondence && autoSubmitForCorrespondenceGames
                    shouldAutoSubmitMove = shouldAutoSubmitMove || ((timeControl.speed == .live || timeControl.speed == .blitz) && autoSubmitForLiveGames)
                    if shouldAutoSubmitMove {
                        self.submitMove(move: newPendingMove)
                    }
                }
            }
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
