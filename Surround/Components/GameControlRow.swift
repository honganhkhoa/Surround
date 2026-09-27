//
//  GameControlRow.swift
//  Surround
//
//  Created by Anh Khoa Hong on 9/25/20.
//

import SwiftUI

private struct RematchChallengeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let challenge: OGSChallengeTemplate

    var body: some View {
        AppNavigationStack {
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
    @Environment(\.appReviewCoordinator) private var appReviewCoordinator
    @ObservedObject var game: Game
    @ObservedObject var state: GameControlState
    var horizontal = true
    var pendingMove: Binding<Move?> = .constant(nil)
    var pendingPosition: Binding<BoardPosition?> = .constant(nil)
    var goToNextGame: (() -> ())?
    var stoneRemovalOption: Binding<StoneRemovalOption> = .constant(.toggleGroup)

    @Setting(.autoSubmitForLiveGames) var autoSubmitForLiveGames: Bool
    @Setting(.autoSubmitForCorrespondenceGames) var autoSubmitForCorrespondenceGames: Bool

    func submitMove(move: Move) {
        let pendingMove = pendingMove
        let pendingPosition = pendingPosition
        state.submitMove(
            move, game: game, using: ogs,
            reviewCoordinator: appReviewCoordinator
        ) {
            pendingMove.wrappedValue = nil
            pendingPosition.wrappedValue = nil
        }
    }

    func acceptRemovedStones() {
        state.acceptRemovedStones(game: game, using: ogs)
    }

    func estimateTerritory() {
        guard !state.blocksGameActions else { return }
        pendingMove.wrappedValue = nil
        pendingPosition.wrappedValue = nil
        state.estimateTerritory(game: game, using: ogs)
    }

    func clearEstimatedTerritory() {
        game.currentPosition.estimatedScores = nil
        game.objectWillChange.send()
    }

    private var rematchChallenge: OGSChallengeTemplate? {
        guard !state.isBusy,
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
                .disabled(state.blocksGameActions)
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
                if game.gamePhase == .finished,
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
                    }.disabled(state.blocksGameActions || (
                        game.isUserPlaying
                        && (game.gameData?.disableAnalysis ?? false)
                    ))
                }
                if game.isUserPlaying {
                    if game.gamePhase == .play {
                        if !game.rengo && game.undoRequest == nil {
                            Button(action: { ogs.requestUndo(game: game) }) {
                                Label("Request undo", systemImage: "arrow.uturn.left")
                            }.disabled(state.blocksGameActions || !game.undoable || pendingMove.wrappedValue != nil)
                        }
                        if game.pauseControl?.userPauseDetail == nil {
                            Button(action: { ogs.pause(game: game) }) {
                                Label("Pause game", systemImage: "pause")
                            }
                            .disabled(state.blocksGameActions)
                        } else {
                            Button(action: { ogs.resume(game: game) }) {
                                Label("Resume game", systemImage: "play")
                            }
                            .disabled(state.blocksGameActions)
                        }
                    } else if game.gamePhase == .stoneRemoval {
                        Picker(selection: stoneRemovalOption, label: Text("Stone removal option")) {
                            Text("Toggle group").tag(StoneRemovalOption.toggleGroup)
                            Text("Toggle single point").tag(StoneRemovalOption.toggleSinglePoint)
                        }
                        .disabled(state.blocksGameActions)
                        Button(action: { state.confirm(.resume, gameID: game.ID, accountID: ogs.user?.id) }) {
                            Label("Resume game", systemImage: "play")
                                .foregroundColor(.red)
                        }
                        .disabled(state.blocksGameActions)
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
                        Button(action: { state.confirm(.cancel, gameID: game.ID, accountID: ogs.user?.id) }) {
                            Label("Cancel game", systemImage: "xmark").foregroundColor(.red)
                        }
                        .disabled(state.blocksGameActions)
                    } else {
                        Button(role: .destructive, action: { state.confirm(.resign, gameID: game.ID, accountID: ogs.user?.id) }) {
                            Label("Resign", systemImage: "flag")
                        }
                        .accessibilityIdentifier(
                            SurroundUITestContract.AccessibilityID.gameResign
                        )
                        .disabled(state.blocksGameActions)
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
            if state.requiresScoringRefresh && !state.isBusy {
                // The persistent recovery banner owns Refresh; normal scoring
                // actions stay unavailable until a fresh snapshot arrives.
                EmptyView()
            } else if !state.isBusy {
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
                                state.presentRematch(
                                    rematch, gameID: game.ID,
                                    accountID: ogs.user?.id
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
                                Button(action: { state.confirm(.pass, gameID: game.ID, accountID: ogs.user?.id) }) {
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
    
    var actionButtons: some View {
        HStack(spacing: 0) {
            mainActionButton
            actionsMenu
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
    }
}

/// Attach once outside the adaptive game layouts so folding keeps both the
/// presented form's edits and any confirmation attached to the same host.
struct GameControlPresentation: ViewModifier {
    @ObservedObject var state: GameControlState
    @ObservedObject var game: Game
    var pendingMove: Binding<Move?>
    var pendingPosition: Binding<BoardPosition?>
    @EnvironmentObject private var ogs: OGSService
    @Environment(\.appReviewCoordinator) private var appReviewCoordinator

    private var droppingFromCasualRengo: Bool {
        guard game.rengo,
              game.gameData?.rengoCasualMode == true,
              let color = game.userStoneColor,
              let team = game.orderedRengoTeam[color] else { return false }
        return team.count > 1
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let notice = state.scoringNotice {
                    scoringRecoveryBanner(notice)
                }
            }
            .sheet(item: $state.rematchPresentation) { presentation in
                RematchChallengeSheet(challenge: presentation.challenge)
            }
            .alert(item: $state.confirmation, content: confirmationAlert)
            .onChange(of: game.ID, initial: true) { _, _ in
                updateContext()
            }
            .onChange(of: ogs.user?.id) { _, _ in
                updateContext()
            }
    }

    private func updateContext() {
        state.updateContext(gameID: game.ID, accountID: ogs.user?.id)
    }

    private func scoringRecoveryBanner(
        _ notice: GameControlState.ScoringNotice
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch notice {
            case .unconfirmed:
                Text("Scoring update unconfirmed").font(.headline)
                Text("The server may have applied this change. Refresh the game before trying again.")
                    .font(.subheadline)
                Button("Refresh game", action: state.refreshScoringState)
                    .accessibilityIdentifier("game.scoring.refresh")
            case .refreshing:
                ProgressView("Refreshing game…")
            case .refreshed:
                Text("Game refreshed. Check the board before making another change.")
                    .font(.subheadline)
                Button("Dismiss", action: state.dismissScoringNotice)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
    }

    private func confirmationAlert(
        _ confirmation: GameControlConfirmation
    ) -> Alert {
        let title: LocalizedStringKey
        let actionTitle: LocalizedStringKey
        switch confirmation.kind {
        case .pass:
            title = "Are you sure you want to pass?"
            actionTitle = "Pass"
        case .resume:
            title = "Are you sure you want to resume the game?"
            actionTitle = "Resume"
        case .resign:
            title = droppingFromCasualRengo
                ? "Are you sure you want to abandon your team?"
                : "Are you sure you want to resign this game?"
            actionTitle = "Resign"
        case .cancel:
            title = "Are you sure you want to cancel this game?"
            actionTitle = "Cancel game"
        }
        return Alert(
            title: Text(title),
            primaryButton: .destructive(Text(actionTitle)) {
                performConfirmedAction(confirmation)
            },
            secondaryButton: .cancel(Text("Dismiss"))
        )
    }

    private func performConfirmedAction(
        _ confirmation: GameControlConfirmation
    ) {
        guard confirmation.gameID == game.ID,
              confirmation.accountID == ogs.user?.id,
              state.matches(
                gameID: confirmation.gameID,
                accountID: confirmation.accountID
              ), !state.blocksGameActions else { return }
        switch confirmation.kind {
        case .pass:
            let pendingMove = pendingMove
            let pendingPosition = pendingPosition
            state.submitMove(
                .pass, game: game, using: ogs,
                reviewCoordinator: appReviewCoordinator
            ) {
                pendingMove.wrappedValue = nil
                pendingPosition.wrappedValue = nil
            }
        case .resume:
            state.resumeGameFromStoneRemoval(game: game, using: ogs)
        case .resign:
            ogs.resign(game: game)
        case .cancel:
            ogs.cancel(game: game)
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
    @Previewable @StateObject var state = GameControlState()
    let previewData = gameControlRowPreviewData()
    GameControlRow(game: previewData.games[2], state: state)
        .environmentObject(previewData.ogs)
        .environmentObject(NavigationService())
}

#Preview("Vertical controls", traits: .fixedLayout(width: 320, height: 120)) {
    @Previewable @StateObject var state = GameControlState()
    let previewData = gameControlRowPreviewData()
    HStack {
        Spacer()
        GameControlRow(game: previewData.games[2], state: state, horizontal: false)
    }
    .environmentObject(previewData.ogs)
    .environmentObject(NavigationService())
}

#endif
