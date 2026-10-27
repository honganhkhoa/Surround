//
//  GameControlRow.swift
//  Surround
//
//  Created by Anh Khoa Hong on 9/25/20.
//

import SwiftUI

private struct GameActionControlsLayout: Layout {
    var horizontal: Bool
    var columnRow = false
    var wrapsMainAction: Bool
    var alignsToBottom: Bool
    var alignsToLeading: Bool
    var alignsMoreToTrailing: Bool
    var metrics: GameControlRowMetrics

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                     cache: inout ()) -> CGSize {
        if columnRow {
            let width = max(metrics.moreButtonDiameter * 2, proposal.width ?? 126)
            return CGSize(width: width, height: metrics.columnRowHeight(width: width))
        }
        if horizontal {
            let mainWidth = subviews.first?.sizeThatFits(.unspecified).width ?? 0
            return metrics.rowSize(proposedWidth: proposal.width,
                                   mainActionWidth: mainWidth,
                                   wrapsMainAction: wrapsMainAction)
        }
        let width = max(44, proposal.width ?? 104)
        return CGSize(width: width, height: metrics.columnHeight(at: width))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let diameter = metrics.moreButtonDiameter
        let spacing = GameControlRowMetrics.spacing
        if horizontal {
            let reservedMainWidth = max(0, bounds.width - diameter - spacing)
            // A leading-aligned row keeps the pill at the phase's reserved
            // width, not the visible label's, so it never grows (rule 19).
            let phaseMainWidth = metrics.horizontalSize.width - spacing - diameter
            let mainWidth = alignsToLeading && !columnRow
                ? min(reservedMainWidth, max(0, phaseMainWidth)) : reservedMainWidth
            subviews[0].place(at: bounds.origin, anchor: .topLeading,
                             proposal: ProposedViewSize(width: mainWidth,
                                                        height: bounds.height))
            let moreY = alignsToBottom ? bounds.maxY - diameter : bounds.midY - diameter / 2
            let moreX = alignsToLeading ? bounds.minX + mainWidth + (mainWidth > 0 ? spacing : 0)
                : bounds.maxX - diameter
            subviews[1].place(at: CGPoint(x: moreX, y: moreY),
                             anchor: .topLeading,
                             proposal: ProposedViewSize(width: diameter, height: diameter))
        } else {
            subviews[0].place(at: bounds.origin, anchor: .topLeading,
                             proposal: ProposedViewSize(width: bounds.width,
                                                        height: bounds.height - diameter - spacing))
            let moreX = alignsMoreToTrailing ? bounds.maxX - diameter : bounds.midX - diameter / 2
            subviews[1].place(at: CGPoint(x: moreX, y: bounds.maxY - diameter),
                             anchor: .topLeading,
                             proposal: ProposedViewSize(width: diameter, height: diameter))
        }
    }
}

private struct GameControlGlass<Surface: Shape>: ViewModifier {
    var shape: Surface
    var interactive = true
    var prominent = false
    /// A disabled main action: a grey pill with no accent glow, on every iOS
    /// version (iOS 18 resolved the accent to grey by itself; iOS 26+ glass
    /// kept its tint, so a disabled Accept looked active).
    var disabled = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.surroundTheme) private var theme

    private var prominentFill: Color {
        disabled ? Color(uiColor: .systemGray) : (theme.actionTint ?? Color.accentColor)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || (theme.usesLightSceneSurfaces && contrast == .increased) {
            content.background(prominent ? prominentFill : Color(uiColor: .secondarySystemGroupedBackground), in: shape)
        } else if #available(iOS 26, *) {
            if prominent {
                content.glassEffect(.regular.tint(disabled ? prominentFill : (theme.actionGlassTint ?? prominentFill))
                    .interactive(interactive && !disabled), in: shape)
            } else {
                // The garden's petals can pass beneath More. Give its ink
                // a stable surface that follows the current appearance.
                content.glassEffect((theme == .nightGarden
                    ? Glass.regular.tint(theme.panel.opacity(0.9)) : .clear)
                    .interactive(interactive), in: shape)
            }
        } else if prominent {
            if theme.usesLightSceneSurfaces && !disabled {
                content.background {
                    shape.fill(.regularMaterial)
                        .overlay { shape.fill(prominentFill.opacity(0.92)) }
                }
            } else {
                content.background(prominentFill, in: shape)
            }
        } else {
            content.background(.thinMaterial, in: shape)
        }
    }
}

private struct GameMainActionStyle: ButtonStyle {
    var font: UIFont
    var lineLimit: Int?
    var horizontal: Bool
    var alignsToBottom: Bool
    var columnRow = false
    // The button's own state: Pass, Submit move and Accept while actions are
    // blocked or the socket is down. The sending spinner is not a button.
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        // One view structure for the row and the column: a branch here gave
        // the pill a new identity whenever the actions moved between a row
        // and a column (opening chat), so it faded out at its old place and in
        // at the new one. Only the modifiers' values change, and it moves.
        // In a row the pill fills the slot reserved for the phase's labels
        // (rule 19), so Pass becoming Submit move never grows it.
        configuration.label
            .font(.system(size: font.pointSize, weight: .semibold))
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .padding(.horizontal, columnRow ? 6 : (horizontal ? 14 : 12))
            .padding(.vertical, columnRow ? 4 : 6)
            .fixedSize(horizontal: false, vertical: horizontal)
            .frame(maxWidth: .infinity, maxHeight: horizontal ? nil : .infinity)
            .frame(minHeight: horizontal ? GameControlRowMetrics.moreDiameter : nil)
            .foregroundStyle(.white)
            .contentShape(Capsule())
            .modifier(GameControlGlass(shape: Capsule(), prominent: true, disabled: !isEnabled))
            .opacity(configuration.isPressed ? 0.7 : 1)
            // The reserved layout slot keeps More stationary. Only the painted
            // pill hugs its actual label, even when a longer possible action
            // needs a taller slot. Zen keeps their bottom edge beside the board;
            // ordinary rows keep controls centered with the adjacent identity.
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: horizontal ? (alignsToBottom ? .bottomTrailing : .trailing) : .center)
    }
}

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.surroundTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var game: Game
    @ObservedObject var state: GameControlState
    var horizontal = true
    /// Duo Closed landscape: the pill and More share the 126 pt column's line.
    var columnRow = false
    var wrapsMainAction = false
    var alignsControlsToBottom = false
    var alignsControlsToLeading = false
    var alignsMoreToTrailing = false
    var pendingMove: Binding<Move?> = .constant(nil)
    var pendingPosition: Binding<BoardPosition?> = .constant(nil)
    var goToNextGame: (() -> ())?
    var stoneRemovalOption: Binding<StoneRemovalOption> = .constant(.toggleGroup)

    @Setting(.autoSubmitForLiveGames) var autoSubmitForLiveGames: Bool
    @Setting(.autoSubmitForCorrespondenceGames) var autoSubmitForCorrespondenceGames: Bool

    private var blocksGameActions: Bool {
        state.blocksGameActions || ogs.socketStatus != .connected
    }

    private var moreForeground: Color {
        guard theme == .nightGarden else {
            return theme == .feltMeadow ? theme.foreground : .accentColor
        }
        // Glass can choose its own content appearance over the garden. Keep
        // the dots paired with the panel's palette through moves and rotation.
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        return Color(uiColor: UIColor(theme.foreground).resolvedColor(with: traits))
    }

    private func performGameAction(_ action: () -> Void) {
        guard !blocksGameActions else { return }
        action()
    }

    private func confirm(_ kind: GameControlConfirmation.Kind) {
        performGameAction { state.confirm(kind, gameID: game.ID, accountID: ogs.user?.id) }
    }

    func submitMove(move: Move) {
        guard !blocksGameActions else { return }
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
        guard !blocksGameActions else { return }
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
                            Button(action: { performGameAction { ogs.requestUndo(game: game) } }) {
                                Label("Request undo", systemImage: "arrow.uturn.left")
                            }.disabled(blocksGameActions || !game.undoable || pendingMove.wrappedValue != nil)
                        }
                        if game.pauseControl?.userPauseDetail == nil {
                            Button(action: { performGameAction { ogs.pause(game: game) } }) {
                                Label("Pause game", systemImage: "pause")
                            }
                            .disabled(blocksGameActions)
                        } else {
                            Button(action: { performGameAction { ogs.resume(game: game) } }) {
                                Label("Resume game", systemImage: "play")
                            }
                            .disabled(blocksGameActions)
                        }
                    } else if game.gamePhase == .stoneRemoval {
                        Picker(selection: stoneRemovalOption, label: Text("Stone removal option")) {
                            Text("Toggle group").tag(StoneRemovalOption.toggleGroup)
                            Text("Toggle single point").tag(StoneRemovalOption.toggleSinglePoint)
                        }
                        .disabled(blocksGameActions)
                        Button(action: { confirm(.resume) }) {
                            Label("Resume game", systemImage: "play")
                                .foregroundColor(.red)
                        }
                        .disabled(blocksGameActions)
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
                        Button(action: { confirm(.cancel) }) {
                            Label("Cancel game", systemImage: "xmark").foregroundColor(.red)
                        }
                        .disabled(blocksGameActions)
                    } else {
                        Button(role: .destructive, action: { confirm(.resign) }) {
                            Label("Resign", systemImage: "flag")
                        }
                        .accessibilityIdentifier(
                            SurroundUITestContract.AccessibilityID.gameResign
                        )
                        .disabled(blocksGameActions)
                    }
                }
            }
        }
        label: {
            Label("More actions", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .font(.system(size: 18 * metrics.moreButtonDiameter / GameControlRowMetrics.moreDiameter,
                              weight: .semibold))
                .foregroundStyle(moreForeground)
                .frame(width: metrics.moreButtonDiameter, height: metrics.moreButtonDiameter)
                .contentShape(Circle())
                .modifier(GameControlGlass(shape: Circle()))
                .accessibilityShowsLargeContentViewer()
        }
        .buttonStyle(.plain)
        .frame(width: metrics.moreButtonDiameter, height: metrics.moreButtonDiameter)
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.gameActionsMenu
        )
    }
    
    var mainActionButton: some View {
        Group {
            if state.requiresScoringRefresh {
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
                                    .disabled(blocksGameActions)
                                }
                            } else if !isHandicapPlacement {
                                Button(action: { confirm(.pass) }) {
                                    Text("Pass")
                                }
                                .disabled(blocksGameActions)
                            }
                        } else if userNeedsToAcceptStoneRemoval {
                            Button(action: { acceptRemovedStones() }) {
                                Text("Accept removed stones", comment: "Displayed next to Stone Removal Phase - keep short. eg: 'Accept'")
                            }
                            .disabled(blocksGameActions)
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
                } else {
                    EmptyView()
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tint(.white)
                    .modifier(GameControlGlass(shape: Capsule(), interactive: false, prominent: true))
                    .accessibilityLabel("Sending")
            }
        }
    }
    
    private var metrics: GameControlRowMetrics {
        GameControlRowMetrics(dynamicTypeSize: dynamicTypeSize, locale: locale,
                              phase: game.gamePhase)
    }

    /// The adaptive layout owns this banner's slot, so recovery cannot resize
    /// the board by adding a new safe-area inset below the screen.
    @ViewBuilder var recoveryStatus: some View {
        if let notice = state.scoringNotice {
            GameScoringRecoveryStatus(state: state, notice: notice)
        }
    }

    var actionButtons: some View {
        GameActionControlsLayout(horizontal: horizontal || columnRow,
                                 columnRow: columnRow,
                                 wrapsMainAction: wrapsMainAction,
                                 alignsToBottom: alignsControlsToBottom,
                                 alignsToLeading: alignsControlsToLeading,
                                 alignsMoreToTrailing: alignsMoreToTrailing,
                                 metrics: metrics) {
            // Preserve the pill slot even when only More is available.
            ZStack { mainActionButton }
                .buttonStyle(GameMainActionStyle(
                    font: horizontal && !columnRow ? metrics.font : metrics.columnFont,
                    lineLimit: columnRow ? 2 : (horizontal ? (wrapsMainAction ? nil : 1) : 2),
                    horizontal: horizontal || columnRow,
                    alignsToBottom: alignsControlsToBottom,
                    columnRow: columnRow
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Keep Menu's semantic host separate from the adjacent action.
            // A Menu placed directly in a custom Layout can otherwise inherit
            // the whole row's accessibility frame when it is the last control.
            ZStack { actionsMenu }
                .frame(width: metrics.moreButtonDiameter, height: metrics.moreButtonDiameter)
                .accessibilityElement(children: .contain)
        }
    }

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 4) { actionButtons }
            } else {
                actionButtons
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
            .sheet(item: $state.rematchPresentation) { presentation in
                RematchChallengeSheet(challenge: presentation.challenge)
            }
            .alert(item: $state.confirmation, content: confirmationAlert)
            .onChange(of: confirmationStillApplies) { _, applies in
                if !applies { state.confirmation = nil }
            }
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

    /// A confirmation answers for the game as it stood when it was asked.
    /// Once a move, a phase change or the result rules its action out, it
    /// closes, and an answer already on its way is dropped.
    private func stillApplies(_ kind: GameControlConfirmation.Kind) -> Bool {
        switch kind {
        case .pass: return game.gamePhase == .play && game.isUserTurn
        case .resume: return game.isUserPlaying && game.gamePhase == .stoneRemoval
        case .resign: return game.isUserPlaying && game.gamePhase != .finished
        case .cancel: return game.isUserPlaying && game.canBeCancelled
        }
    }

    private var confirmationStillApplies: Bool {
        state.confirmation.map { stillApplies($0.kind) } ?? true
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
              ), !state.blocksGameActions, ogs.socketStatus == .connected,
              stillApplies(confirmation.kind) else { return }
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

private struct GameScoringRecoveryStatus: View {
    @ObservedObject var state: GameControlState
    let notice: GameControlState.ScoringNotice
    // Read here, not by the row: SingleGameView builds the row only to take
    // this banner from it, so the row's environment is never installed.
    @EnvironmentObject private var ogs: OGSService
    @State private var showsExplanation = false

    private var explanation: LocalizedStringKey {
        switch notice {
        case .unconfirmed: return "The server may have applied this change. Refresh the game before trying again."
        case .refreshing: return "Refreshing game…"
        case .refreshed: return "Game refreshed. Check the board before making another change."
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            switch notice {
            case .unconfirmed:
                explanationButton("Scoring unconfirmed")
                Button(action: state.refreshScoringState) {
                    Label("Refresh game", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly).frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                    // Offline, Refresh could only fail again at once; the
                    // recovery settles by itself on the gamedata after reconnecting.
                    .disabled(ogs.socketStatus != .connected)
                    .accessibilityIdentifier("game.scoring.refresh")
            case .refreshing:
                Text("Refreshing game…").frame(maxWidth: .infinity, alignment: .leading)
                ProgressView().frame(width: 44, height: 44)
            case .refreshed:
                explanationButton("Check refreshed board")
                Button(action: state.dismissScoringNotice) {
                    Label("Dismiss", systemImage: "xmark")
                        .labelStyle(.iconOnly).frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .font(.footnote)
        .lineLimit(2).minimumScaleFactor(0.7)
        .buttonStyle(.borderless)
        .padding(.leading, 8)
        .frame(height: 44)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("game.scoring.recovery")
        .popover(isPresented: $showsExplanation) {
            Text(explanation).padding().frame(idealWidth: 300)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func explanationButton(_ title: LocalizedStringKey) -> some View {
        Button { showsExplanation = true } label: {
            Text(title).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(explanation))
        .accessibilityHint("Shows details")
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
