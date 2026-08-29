//
//  GameControlRow.swift
//  Surround
//
//  Created by Anh Khoa Hong on 9/25/20.
//

import SwiftUI
import Combine

private struct RematchPresentation: Identifiable {
    let gameID: GameID
    let challenge: OGSChallengeTemplate

    var id: GameID { gameID }
}

private struct RematchChallengeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let challenge: OGSChallengeTemplate

    var body: some View {
        NavigationStack {
            CustomGameForm(
                initialChallenge: challenge,
                mode: .rematch
            )
            .navigationTitle("Rematch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

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
    @State private var rematchPresentation: RematchPresentation?
    
    @Setting(.autoSubmitForLiveGames) var autoSubmitForLiveGames: Bool
    @Setting(.autoSubmitForCorrespondenceGames) var autoSubmitForCorrespondenceGames: Bool

    func submitMove(move: Move) {
        self.ogsRequestCancellable = ogs.submitMove(move: move, forGame: game)
            .zip(game.$currentPosition.filter({ $0.lastMoveNumber != game.currentPosition.lastMoveNumber }).setFailureType(to: Error.self))
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

    private var rematchChallenge: OGSChallengeTemplate? {
        guard ogsRequestCancellable == nil,
              game.currentPosition.estimatedScores == nil,
              game.userStoneColor != nil else {
            return nil
        }
        return OGSChallengeTemplate.rematch(for: game)
    }

    private var nextGameCount: Int? {
        guard game.isUserPlaying,
              let gameSpeed = game.gameData?.timeControl.speed else {
            return nil
        }

        let gamesWaiting = gameSpeed == .correspondence
            ? ogs.sortedActiveCorrespondenceGamesOnUserTurn.count
            : ogs.liveGames.filter { ogs.isOnUserTurn(game: $0) }.count
        return gamesWaiting > 0 ? gamesWaiting : nil
    }

    var statusText: some View {
        Group {
            if game.canAcceptUndo || game.canCancelUndo {
                Menu {
                    if game.canAcceptUndo {
                        Button(action: { ogs.acceptUndo(game: game) }) {
                            Label("Accept undo", systemImage: "arrow.uturn.left")
                        }
                        Button(action: { ogs.cancelUndo(game: game) }) {
                            Label(
                                String(
                                    localized: "Reject undo",
                                    comment: "Button to reject the opponent's pending undo request"
                                ),
                                systemImage: "xmark"
                            )
                        }
                    } else if game.canCancelUndo {
                        Button(action: { ogs.cancelUndo(game: game) }) {
                            Label(
                                String(
                                    localized: "Cancel undo",
                                    comment: "Button to withdraw the user's own pending undo request"
                                ),
                                systemImage: "xmark"
                            )
                        }
                    }
                }
                label: {
                    Text(verbatim: "\(game.status) ▾")
                        .font(Font.title2.bold())
                        .lineLimit(1)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.7)
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
                if rematchChallenge != nil,
                   let goToNextGame,
                   let gamesWaiting = nextGameCount {
                    Button(action: goToNextGame) {
                        Label {
                            Text("Next") + Text(verbatim: " (\(gamesWaiting))")
                        } icon: {
                            Image(systemName: "arrow.right")
                        }
                    }
                    .accessibilityIdentifier(
                        SurroundUITestContract.AccessibilityID.gameNext
                    )
                }
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
                        if !game.rengo && game.undoRequest == nil {
                            Button(action: { ogs.requestUndo(game: game) }) {
                                Label("Request undo", systemImage: "arrow.uturn.left")
                            }.disabled(!game.undoable || pendingMove.wrappedValue != nil)
                        }
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
                Button(action: { SystemPlatformServices.shared.open(game.ogsURL!) }) {
                    Label("Open in browser", systemImage: "safari")
                }
            }
            if game.isUserPlaying && game.gamePhase != .finished {
                Section {
                    if game.canBeCancelled {
                        Button(action: { self.showingCancelAlert = true }) {
                            Label("Cancel game", systemImage: "xmark").foregroundColor(.red)
                        }
                    } else {
                        Button(role: .destructive, action: { self.showingResignAlert = true }) {
                            Label("Resign", systemImage: "flag")
                        }
                        .accessibilityIdentifier(
                            SurroundUITestContract.AccessibilityID.gameResign
                        )
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
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.gameActionsMenu
        )
    }
    
    var mainActionButton: some View {
        Group {
            if ogsRequestCancellable == nil {
                if let userColor = game.userStoneColor {
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
                        } else if let rematch = rematchChallenge {
                            Button("Rematch") {
                                rematchPresentation = RematchPresentation(
                                    gameID: game.ID,
                                    challenge: rematch
                                )
                            }
                            .accessibilityIdentifier(
                                SurroundUITestContract.AccessibilityID.gameRematch
                            )
                        } else if isUserTurnToPlay {
                            if let pendingMove = pendingMove.wrappedValue {
                                if !game.hasCurrentUndoRequest {
                                    Button(action: { submitMove(move: pendingMove)}) {
                                        Text("Submit move")
                                    }
                                }
                            } else if !isHandicapPlacement {
                                Button(action: { self.showingPassAlert = true }) {
                                    Text("Pass")
                                }
                            }
                        } else if userNeedsToAcceptStoneRemoval {
                            Button(action: { acceptRemovedStones() }) {
                                Text("Accept removed stones", comment: "Displayed next to Stone Removal Phase - keep short. eg: 'Accept'")
                            }
                        } else if game.isUserPlaying {
                            if let goToNextGame, let gamesWaiting = nextGameCount {
                                Button(action: goToNextGame) {
                                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                                        Text("Next")
                                        Text(verbatim: "(\(gamesWaiting))")
                                            .font(Font.caption2.bold())
                                    }
                                }
                                .accessibilityIdentifier(
                                    SurroundUITestContract.AccessibilityID.gameNext
                                )
                            }
                        }
                    }
                    .padding(10)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .hoverEffect(.highlight)
                } else {
                    EmptyView()
                }
            } else {
                ProgressView().alignmentGuide(.firstTextBaseline, computeValue: { viewDimension in
                    viewDimension.height
                })
            }
        }
    }
    
    var droppingFromCasualRengo: Bool {
        guard game.rengo, let casual = game.gameData?.rengoCasualMode, casual else {
            return false
        }
        
        guard let userStoneColor = game.userStoneColor, let userTeam = game.orderedRengoTeam[userStoneColor] else {
            return false
        }
        
        return userTeam.count > 1
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
                        title: Text(droppingFromCasualRengo ? "Are you sure you want to abandon your team?" : "Are you sure you want to resign this game?"),
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
        .onChange(of: stoneRemovalSelectedPoints.wrappedValue) { _, selectedPoints in
            self.toggleRemovedStones(stones: selectedPoints)
        }
        .onChange(of: pendingMove.wrappedValue) { _, newPendingMove in
            if let newPendingMove = newPendingMove {
                if let timeControl = game.gameData?.timeControl {
                    var shouldAutoSubmitMove = timeControl.speed == .correspondence && autoSubmitForCorrespondenceGames
                    shouldAutoSubmitMove = shouldAutoSubmitMove
                        || (timeControl.speed?.isRealtime == true && autoSubmitForLiveGames)
                    if shouldAutoSubmitMove {
                        self.submitMove(move: newPendingMove)
                    }
                }
            }
        }
        .sheet(item: $rematchPresentation) { presentation in
            RematchChallengeSheet(challenge: presentation.challenge)
        }
    }
}

#if DEBUG
private func gameControlRowPreviewData() -> (games: [Game], ogs: OGSService) {
    let games = [
        TestData.Ongoing19x19wBot1,
        TestData.Ongoing19x19wBot2,
        TestData.Ongoing19x19wBot3
    ]
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "kata-bot", id: 592684),
        activeGames: games
    )
    for game in games {
        game.ogs = ogs
    }
    return (games, ogs)
}

#Preview("Horizontal controls", traits: .fixedLayout(width: 320, height: 60)) {
    let previewData = gameControlRowPreviewData()
    GameControlRow(game: previewData.games[2])
        .environmentObject(previewData.ogs)
}

#Preview("Vertical controls", traits: .fixedLayout(width: 320, height: 120)) {
    let previewData = gameControlRowPreviewData()
    HStack {
        Spacer()
        GameControlRow(game: previewData.games[2], horizontal: false)
    }
    .environmentObject(previewData.ogs)
}

#endif
