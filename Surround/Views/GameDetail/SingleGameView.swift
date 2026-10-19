//
//  SingleGameView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 30/05/2021.
//

import SwiftUI
import AVFAudio
import Combine

struct SingleGameView: View {
    var compact: Bool
    @ObservedObject var game: Game
    var goToNextGame: (() -> ())?
    var horizontal = false
    @Binding var zenMode: Bool
    var zenBoardCenterY: CGFloat? = nil
    /// Duo wide poses: the top of the band that holds our own chrome.
    var chromeBandTop: CGFloat? = nil
    /// The pose uses the vertical toolbar, also in Zen where it is turned off.
    var verticalToolbarPose = false
    
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject private var stackRouter: StackRouter
    @EnvironmentObject private var navigation: NavigationService
    @Environment(\.owningStackRoute) private var owningStackRoute
    @State private var owningRootView: RootView?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.isVerticalToolbar) private var isVerticalToolbar
    @ScaledMetric(relativeTo: .body) private var clockScale: CGFloat = 1
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appReviewCoordinator) private var appReviewCoordinator
    @State private var isVisibleForAppReview = false
    @State private var reviewObservationOwnerID = UUID()
    @State private var observedReviewGameID: Int?
    #if DEBUG && MAIN_APP
    @State private var animationObservationID = UUID()
    @State private var hasAppliedUITestScene = false
    #endif
    @State var pendingMove: Move? = nil
    @State var pendingPosition: BoardPosition? = nil
    @State var stoneRemovalSelectedPoints = Set<[Int]>()
    @State var stoneRemovalOption = StoneRemovalOption.toggleGroup
    var attachedKeyboardVisible = false
    var keyboardOverlap: CGFloat = 0
    @State private var messageComposerHeight: CGFloat = 50
    @State private var variationComposerHeight: CGFloat = 188
    #if DEBUG && MAIN_APP
    /// Every size the conversation laid out at since it appeared, for UI tests.
    @State private var chatPanelLayoutSizes: [String] = []
    #endif
    
    @Binding var interaction: GameDetailInteraction
    private var displayedPanel: GameDetailPanel {
        get { interaction.panel }
        nonmutating set { interaction.selectPanel(newValue) }
    }
    @ObservedObject var chatSession: ChatSessionState
    @ObservedObject var gameControlState = GameControlState()
    var selectedConditionalVariation: Binding<ConditionalMoveBranch?> = .constant(nil)
    @State private var preferredNextPositionByPosition =
        [ObjectIdentifier: BoardPosition]()
    var showsCompactChatBoard: Binding<Bool> = .constant(true)
    var variationShareDraft: Binding<VariationShareDraft?> = .constant(nil)
    var selectedChatChannel: Binding<OGSChatSendChannel> = .constant(.main)
    @Setting(.showsBoardCoordinates) var showsBoardCoordinates: Bool
    @Setting(.soundOnStonePlacement) var soundOnStonePlacement: Bool
    @Setting(.hidesRank) private var hidesRank: Bool

    @State private var selectedChatItem: ChatLogSelection?
    
    @State var analyticsPosition: BoardPosition?
    
    @State var analyticsPendingMove: Move? = nil
    @State var analyticsPendingPosition: BoardPosition? = nil
    @State private var analyzeBoardTool = AnalyzeBoardTool.moves
    @State private var analyzeMarkupsByPosition =
        [ObjectIdentifier: BoardMarkups]()
    
    @State var stonePlacingPlayer: AVAudioPlayer? = nil
    @StateObject private var conditionalMoveRequest = GameControlState()
    @State private var showingConditionalMoveSubmissionError = false
    @State private var hasUsedAddToConditionalMoves =
        userDefaults[.hasUsedAddToConditionalMoves] ?? false
    
    
    typealias DisplayMode = GameDetailPanel

    private struct AnalyzeControlBarConditionalState {
        var canAdd = false
        var addReplacesVariations = false
        var canRemove = false
        var canDeleteBranch = false
        var deletesVariations = false
    }

    private struct ReviewGameObservationIdentity: Equatable {
        let gameID: GameID
        let accountID: Int?
        let scenePhase: ScenePhase
        let isVisible: Bool
        let sceneContextID: UUID?
    }

    private var reviewGameObservationIdentity: ReviewGameObservationIdentity {
        ReviewGameObservationIdentity(
            gameID: game.ID,
            accountID: ogs.user?.id,
            scenePhase: scenePhase,
            isVisible: isVisibleForAppReview,
            sceneContextID: appReviewCoordinator?.gameObservationContextID
        )
    }

    private var isChatRouteActive: Bool {
        (owningRootView == nil || navigation.main.rootView == owningRootView)
            && stackRouter.path.last == owningStackRoute
    }

    private var chatSelection: Binding<ChatLogSelection?> {
        Binding(
            get: { selectedChatItem },
            set: { newSelection in
                selectedChatItem = newSelection
                if newSelection != nil {
                    interaction.beginChatPreview()
                    if newSelection?.preview.position != nil {
                        showsCompactChatBoard.wrappedValue = true
                    }
                }
            }
        )
    }

    private var stoneRemovalSelection: Binding<Set<[Int]>> {
        Binding(
            get: { stoneRemovalSelectedPoints },
            set: { points in
                guard !gameControlState.blocksGameActions else { return }
                stoneRemovalSelectedPoints = points
                // A board commit is an action even when the same group remains
                // selected after an unconfirmed request and explicit refresh.
                gameControlState.toggleRemovedStones(points, game: game, using: ogs) {
                    stoneRemovalSelectedPoints.removeAll()
                }
            }
        )
    }

    private var currentGameVariationShareDraft: Binding<VariationShareDraft?> {
        Binding(
            get: {
                guard let draft = variationShareDraft.wrappedValue,
                      draft.gameID == game.ID else {
                    return nil
                }
                return draft
            },
            set: { draft in
                guard draft == nil || draft?.gameID == game.ID else {
                    return
                }
                variationShareDraft.wrappedValue = draft
            }
        )
    }

    private var analysisPositionSelection: Binding<BoardPosition?> {
        Binding(get: { analyticsPosition }, set: { position in
            interaction.setAnalyzing(true)
            selectedChatItem = nil
            analyticsPosition = position
        })
    }

    private var analysisToolSelection: Binding<AnalyzeBoardTool> {
        Binding(get: { analyzeBoardTool }, set: { tool in
            interaction.setAnalyzing(true)
            analyzeBoardTool = tool
        })
    }

    private func analyzeMarkups(for position: BoardPosition) -> BoardMarkups {
        analyzeMarkupsByPosition[ObjectIdentifier(position)] ?? [:]
    }

    private func analyzeMarkupsBinding(
        for position: BoardPosition
    ) -> Binding<BoardMarkups> {
        let identifier = ObjectIdentifier(position)
        return Binding(
            get: { analyzeMarkupsByPosition[identifier] ?? [:] },
            set: { markups in
                interaction.setAnalyzing(true)
                if markups.isEmpty {
                    analyzeMarkupsByPosition[identifier] = nil
                } else {
                    analyzeMarkupsByPosition[identifier] = markups
                }
            }
        )
    }

    private func pruneAnalyzeMarkups() {
        let registeredPositions = Set(game.moveTree.indexByBoardPosition.keys)
        let retainedMarkups = analyzeMarkupsByPosition.filter {
            registeredPositions.contains($0.key)
        }
        if retainedMarkups.count != analyzeMarkupsByPosition.count {
            analyzeMarkupsByPosition = retainedMarkups
        }
    }

    private var reviewGamePhase: AppReviewGamePhase? {
        AppReviewGameActivity.phase(
            game.gamePhase,
            authoritativePhase: game.gameData?.phase,
            outcome: game.gameData?.outcome
        )
    }

    private func updateReviewGameObservation() {
        guard isVisibleForAppReview,
              scenePhase == .active,
              let gameID = game.ogsID,
              gameID > 0,
              ogs.user != nil,
              game.gameData?.timeControl.speed?.isRealtime == true else {
            stopReviewGameObservation()
            return
        }
        if observedReviewGameID != gameID {
            stopReviewGameObservation()
            observedReviewGameID = gameID
        }
        guard let phase = reviewGamePhase else {
            return
        }
        appReviewCoordinator?.observeLiveGame(
            ownerID: reviewObservationOwnerID,
            gameID: gameID,
            isParticipant: game.isUserPlaying,
            phase: phase
        )
    }

    private func stopReviewGameObservation() {
        if let observedReviewGameID {
            appReviewCoordinator?.stopObservingLiveGame(
                ownerID: reviewObservationOwnerID, gameID: observedReviewGameID
            )
        }
        observedReviewGameID = nil
    }
    
    private var showsAnalysisPanel: Bool {
        !zenMode && interaction.isAnalyzing
    }

    private var showsChatPreview: Bool {
        !zenMode && selectedChatItem?.preview.position != nil
    }

    private var chatPreviewTitle: Text {
        if case let .move(number) = selectedChatItem?.target {
            Text("Move \(number)")
        } else {
            Text("Chat variation")
        }
    }

    private var chatPreviewBar: some View {
        HStack(spacing: 12) {
            chatPreviewTitle
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                selectedChatItem = nil
            } label: {
                Label("Return to game", systemImage: "arrow.uturn.backward")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.purple)
            .accessibilityIdentifier("game.chat.preview.return")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    var boardView: some View {
        let selectedChatPreview = zenMode ? nil : selectedChatItem?.preview
        return ZStack {
            if let selectedChatPosition = selectedChatPreview?.position {
                BoardView(
                    boardPosition: selectedChatPosition,
                    variation: selectedChatPreview?.variation,
                    showsCoordinate: showsBoardCoordinates,
                    highlightCoordinates: selectedChatPreview?.coordinates ?? [],
                    markups: .constant(
                        selectedChatPreview?.variation?.markups ?? [:]
                    )
                )
            } else if let analyticsPosition = analyticsPosition, showsAnalysisPanel {
                BoardView(
                    boardPosition: analyticsPosition,
                    variation: game.moveTree.variation(to: analyticsPosition),
                    showsCoordinate: showsBoardCoordinates,
                    playable: game.analysisAvailable,
                    newMove: $analyticsPendingMove,
                    newPosition: $analyticsPendingPosition,
                    allowsSelfCapture: game.gameData?.allowSelfCapture ?? false,
                    boardTool: analysisToolSelection,
                    markups: analyzeMarkupsBinding(for: analyticsPosition)
                )
                .onChange(of: analyticsPendingMove) { _, newMove in
                    if let newMove = newMove {
                        interaction.setAnalyzing(true)
                        if let newPosition = try? game.makeMove(move: newMove, fromAnalyticsPosition: analyticsPosition) {
                            self.analyticsPosition = newPosition
                            analyticsPendingMove = nil
                            analyticsPendingPosition = nil
                        }
                    }
                }
            } else {
                BoardView(
                    boardPosition: game.currentPosition,
                    showsCoordinate: showsBoardCoordinates,
                    playable: game.isUserTurn && !gameControlState.blocksGameActions && ogs.socketStatus == .connected,
                    stoneRemovable: game.isUserPlaying && game.gamePhase == .stoneRemoval && !gameControlState.blocksGameActions && ogs.socketStatus == .connected,
                    stoneRemovalOption: stoneRemovalOption,
                    newMove: $pendingMove,
                    newPosition: $pendingPosition,
                    allowsSelfCapture: game.gameData?.allowSelfCapture ?? false,
                    stoneRemovalSelectedPoints: stoneRemovalSelection,
                    highlightCoordinates: selectedChatPreview?.coordinates ?? [],
                    undoRequestCoordinates: game.undoRequestCoordinates
                )
            }
            if game.gameData == nil {
                Color(UIColor.systemBackground).opacity(0.65)
                ProgressView("Loading game…")
            }
            #if DEBUG && MAIN_APP
            if SurroundUITestContract.isEnabled {
                // Canvas does not otherwise expose a stable element to XCTest.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "Go board"))
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameBoard)
                    .accessibilityValue(
                        Text(verbatim: boardUITestAccessibilityValue)
                    )
            }
            #endif
        }
    }

    #if DEBUG && MAIN_APP
    private var boardUITestAccessibilityValue: String {
        if !zenMode, let preview = selectedChatItem?.preview,
           let position = preview.position {
            return boardUITestAccessibilityValue(
                position: position,
                variation: preview.variation,
                markups: preview.variation?.markups ?? [:]
            )
        }
        if let analyticsPosition,
           showsAnalysisPanel {
            return boardUITestAccessibilityValue(
                position: analyticsPosition,
                variation: game.moveTree.variation(to: analyticsPosition),
                markups: analyzeMarkups(for: analyticsPosition)
            )
        }
        return boardUITestAccessibilityValue(
            position: game.currentPosition,
            variation: nil,
            markups: [:]
        )
    }

    private func boardUITestAccessibilityValue(
        position: BoardPosition,
        variation: Variation?,
        markups: BoardMarkups
    ) -> String {
        let markerSuffix = boardUITestMarkerSuffix(markups)
        if let variation {
            return "variation:\(variation.basePosition.lastMoveNumber):"
                + variation.moves.map { $0.toOGSString() }
                    .joined(separator: "-")
                + markerSuffix
        }
        return "position:\(position.lastMoveNumber):"
            + (position.lastMove?.toOGSString() ?? "none")
            + markerSuffix
    }

    private func boardUITestMarkerSuffix(_ markups: BoardMarkups) -> String {
        let encoded = markups.ogsMarks(
            boardWidth: game.width,
            boardHeight: game.height
        )
        guard !encoded.isEmpty else {
            return ""
        }
        return "|marks:"
            + encoded.keys.sorted().map { key in
                "\(key)=\(encoded[key]!)"
            }.joined(separator: ",")
    }
    #endif
    
    var userColor: StoneColor {
        return game.userStoneColor ?? .white
    }

    private func showConditionalVariation(
        _ branch: ConditionalMoveBranch
    ) {
        selectedChatItem = nil
        analyticsPosition = branch.position
        withAnimation {
            zenMode = false
            displayedPanel = .analyze
        }
    }

    private var canShareSelectedVariation: Bool {
        guard game.analysisAvailable,
              ogs.user != nil,
              let analyticsPosition else {
            return false
        }
        return shareableVariation(at: analyticsPosition) != nil
    }

    private func shareableVariation(
        at position: BoardPosition
    ) -> Variation? {
        let markups = analyzeMarkups(for: position)
        if var variation = game.moveTree.variation(to: position) {
            variation.markups = markups
            return variation
        }

        guard !markups.isEmpty,
              game.moveTree.indexByBoardPosition[ObjectIdentifier(position)]
                == 0 else {
            return nil
        }
        return Variation(
            position: position,
            basePosition: position,
            moves: [],
            markups: markups
        )
    }

    private func beginSharingSelectedVariation() {
        guard canShareSelectedVariation,
              let analyticsPosition,
              let variation = shareableVariation(at: analyticsPosition) else {
            return
        }

        #if DEBUG && MAIN_APP
        SurroundAnimationDiagnostics.record(
            "share.begin", ownerID: animationObservationID,
            focusRequestID: variationShareDraft.wrappedValue?.focusRequestID,
            fields: ["compact": String(compact)]
        )
        #endif

        analyticsPendingMove = nil
        analyticsPendingPosition = nil
        selectedChatItem = nil
        variationShareDraft.wrappedValue = VariationShareDraft(
            gameID: game.ID,
            variation: variation
        )
        #if DEBUG && MAIN_APP
        SurroundAnimationDiagnostics.record(
            "share.draftAssigned", ownerID: animationObservationID,
            focusRequestID: variationShareDraft.wrappedValue?.focusRequestID
        )
        #endif
        withAnimation {
            showsCompactChatBoard.wrappedValue = false
            interaction.beginChatInteraction()
        }
    }

    private func cancelVariationSharing() {
        #if DEBUG && MAIN_APP
        SurroundAnimationDiagnostics.record(
            "share.cancel", ownerID: animationObservationID,
            focusRequestID: variationShareDraft.wrappedValue?.focusRequestID
        )
        #endif
        variationShareDraft.wrappedValue = nil
    }

    private func finishVariationSharing() {
        #if DEBUG && MAIN_APP
        SurroundAnimationDiagnostics.record(
            "share.finished", ownerID: animationObservationID,
            focusRequestID: variationShareDraft.wrappedValue?.focusRequestID
        )
        #endif
        variationShareDraft.wrappedValue = nil
    }
    
    var topLeftPlayerColor: StoneColor {
        if game.isUserPlaying {
            return userColor.opponentColor()
        } else {
            return .black
        }
    }

    func analyzeControlBar(verticalTree: Bool) -> some View {
        let state = analyzeControlBarConditionalState
        return AnalyzeControlBar(
            moveTree: game.moveTree,
            selectedPosition: analysisPositionSelection,
            preferredNextPositionByPosition: $preferredNextPositionByPosition,
            boardTool: analysisToolSelection,
            markups: analyticsPosition.map {
                analyzeMarkups(for: $0)
            } ?? [:],
            analysisAvailable: game.analysisAvailable,
            canShareVariation: canShareSelectedVariation,
            canAddConditionalMoves: state.canAdd,
            addReplacesConditionalVariations:
                state.addReplacesVariations,
            canRemoveConditionalMoves: state.canRemove,
            showsConditionalMoveQuickAction:
                hasUsedAddToConditionalMoves,
            canDeleteSelectedBranch: state.canDeleteBranch,
            deletesConditionalVariations:
                state.deletesVariations,
            shareVariation: beginSharingSelectedVariation,
            addToConditionalMoves: addSelectedVariationToConditionalMoves,
            removeFromConditionalMoves:
                removeSelectedVariationFromConditionalMoves,
            deleteBranch: deleteAnalysisBranch,
            verticalTree: verticalTree,
            currentPosition: game.currentPosition
        )
    }

    private var conditionalMoveSubmissionPending: Bool {
        ogs.isConditionalMoveSubmissionPending(gameID: game.ogsID)
    }

    private func resetAnalyzeBoardTool() {
        analyzeBoardTool = .moves
        analyticsPendingMove = nil
        analyticsPendingPosition = nil
    }

    private var analyzeControlBarConditionalState:
        AnalyzeControlBarConditionalState {
        var state = AnalyzeControlBarConditionalState()
        guard game.analysisAvailable, let analyticsPosition else {
            return state
        }

        guard !conditionalMoveSubmissionPending else {
            return state
        }

        let canStructurallyDelete =
            game.moveTree.canStructurallyRemoveBranch(
                startingAt: analyticsPosition
            )
        var selectedVariationIDs = Set<ConditionalVariationID>()
        if canStructurallyDelete {
            selectedVariationIDs =
                game.moveTree.conditionalVariationIDs(
                    inSubtreeStartingAt: analyticsPosition
                )
            state.deletesVariations = !selectedVariationIDs.isEmpty
            if selectedVariationIDs.isEmpty {
                state.canDeleteBranch = true
            }
        }

        guard let ownerID = ogs.user?.id else {
            return state
        }

        let additionEffect = game.conditionalMoveAdditionEffect(
            endingAt: analyticsPosition,
            ownerID: ownerID
        )
        state.canAdd = additionEffect == .addsVariation
            || additionEffect == .replacesExistingVariations
        state.addReplacesVariations =
            additionEffect == .replacesExistingVariations
        state.canRemove = game.canRemoveConditionalMoveVariation(
            endingAt: analyticsPosition,
            ownerID: ownerID
        )
        if canStructurallyDelete && !selectedVariationIDs.isEmpty {
            state.canDeleteBranch =
                game.canRemoveConditionalMoveVariations(
                    selectedVariationIDs,
                    ownerID: ownerID
                )
        }
        return state
    }

    private func addSelectedVariationToConditionalMoves() {
        guard !conditionalMoveSubmissionPending,
              let analyticsPosition,
              let ownerID = ogs.user?.id,
              let plan = game.conditionalMovePlanByAddingVariation(
                endingAt: analyticsPosition,
                ownerID: ownerID
              ) else {
            return
        }
        hasUsedAddToConditionalMoves = true
        userDefaults[.hasUsedAddToConditionalMoves] = true
        submitConditionalMovePlan(plan)
    }

    private func removeSelectedVariationFromConditionalMoves() {
        guard !conditionalMoveSubmissionPending,
              let analyticsPosition,
              let ownerID = ogs.user?.id,
              let plan = game.conditionalMovePlanByRemovingVariation(
                endingAt: analyticsPosition,
                ownerID: ownerID
              ) else {
            return
        }
        submitConditionalMovePlan(plan)
    }

    private func deleteAnalysisBranch(startingAt position: BoardPosition) {
        guard let parentPosition = position.previousPosition,
              game.moveTree.canStructurallyRemoveBranch(
                startingAt: position
              ) else {
            return
        }

        let variationIDs = game.moveTree.conditionalVariationIDs(
            inSubtreeStartingAt: position
        )
        guard !variationIDs.isEmpty else {
            completeAnalysisBranchDeletion(
                startingAt: position,
                parentPosition: parentPosition
            )
            return
        }
        guard let ownerID = ogs.user?.id,
              let plan = game.conditionalMovePlanByRemovingVariations(
                variationIDs,
                ownerID: ownerID
              ) else {
            showingConditionalMoveSubmissionError = true
            return
        }
        submitConditionalMovePlan(plan) {
            completeAnalysisBranchDeletion(
                startingAt: position,
                parentPosition: parentPosition,
                reportsConditionalMoveFailure: true
            )
        }
    }

    private func completeAnalysisBranchDeletion(
        startingAt position: BoardPosition,
        parentPosition: BoardPosition,
        reportsConditionalMoveFailure: Bool = false
    ) {
        if game.moveTree.contains(position) {
            guard let destination = game.moveTree.removeBranch(
                startingAt: position
            ) else {
                if reportsConditionalMoveFailure {
                    showingConditionalMoveSubmissionError = true
                }
                return
            }
            pruneAnalyzeMarkups()
            analyticsPosition = destination
        } else if game.moveTree.contains(parentPosition) {
            analyticsPosition = parentPosition
        }
    }

    private func submitConditionalMovePlan(
        _ plan: ConditionalMovePlan,
        onSuccess: (() -> Void)? = nil
    ) {
        conditionalMoveRequest.performRequest(
            gameID: game.ID,
            accountID: ogs.user?.id,
            publisher: { ogs.submitConditionalMovePlan(plan, for: game) },
            receiveValue: { onSuccess?() },
            receiveFailure: { _ in showingConditionalMoveSubmissionError = true }
        )
    }
    
    private var showsChatPanel: Bool {
        !zenMode && interaction.isChatVisible
    }


    private var gameActions: GameControlRow {
        GameControlRow(game: game, state: gameControlState,
                       pendingMove: $pendingMove, pendingPosition: $pendingPosition,
                       goToNextGame: goToNextGame, stoneRemovalOption: $stoneRemovalOption)
    }

    private var recoveryHeight: CGFloat {
        gameControlState.scoringNotice == nil ? 0 : max(72, 72 * min(clockScale, 1.65))
    }

    private var recoveryBanner: some View {
        Group {
            if gameControlState.scoringNotice != nil {
                gameActions.recoveryStatus
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// v149: both column chips keep their second line (rank, Rengo's Next)
    /// unless it is empty for both or the column's cards wrap.
    private func columnChipSecondLine(_ plan: GameDetailLayoutPlan) -> Bool {
        GameDetailPlayerIdentity.columnChipsHaveSecondLine(game: game, hidesRank: hidesRank)
            && !plan.compactColumnIdentityDropsSecondLine
    }

    private func actionCorner(plan: GameDetailLayoutPlan, columnStyle: ColumnIdentityStyle) -> some View {
        let compactIdentity = compact && !plan.verticalActions && dynamicTypeSize < .xxxLarge
            && plan.hidesOpponentIdentity
        let stacksCorner = plan.verticalActions || plan.columnActionRow
        let layout = stacksCorner
            ? AnyLayout(VStackLayout(alignment: plan.horizontalActionsInColumn ? .leading : .trailing, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        return layout {
            if !stacksCorner { Spacer(minLength: 0) }
            if !showsAnalysisPanel && !showsChatPreview {
                GameControlRow(game: game, state: gameControlState,
                               horizontal: !plan.verticalActions || plan.horizontalActionsInColumn,
                               columnRow: plan.columnActionRow,
                               wrapsMainAction: plan.wrapsMainAction,
                               alignsControlsToBottom: zenMode,
                               alignsControlsToLeading: plan.horizontalActionsInColumn,
                               alignsMoreToTrailing: plan.trailsMoreInColumn,
                               pendingMove: $pendingMove, pendingPosition: $pendingPosition,
                               goToNextGame: goToNextGame, stoneRemovalOption: $stoneRemovalOption)
                    .layoutPriority(stacksCorner ? 1 : 0)
            }
            if !plan.hidesActionIdentity {
                GameDetailPlayerIdentity(game: game, color: topLeftPlayerColor.opponentColor(),
                                         vertical: stacksCorner && plan.verticalOpponentIdentity,
                                         facesBoard: stacksCorner,
                                         compactHeader: compactIdentity,
                                         columnAvatarSize: plan.compactColumnIdentity ? 32 : columnStyle.avatarSize,
                                         columnPadding: columnStyle.padding,
                                         compactColumn: plan.compactColumnIdentity,
                                         columnSecondLine: columnChipSecondLine(plan))
                    .frame(maxWidth: stacksCorner ? .infinity : nil,
                           alignment: stacksCorner && !plan.compactColumnIdentity ? .leading : .trailing)
                    .layoutPriority(stacksCorner ? 0 : 1)
            }
        }
        .frame(maxHeight: stacksCorner ? .infinity : nil, alignment: .bottom)
    }

    /// Using the conversation keeps chat the open panel. A chat that is closing
    /// (its views fade out briefly) never re-presents itself, for example when
    /// its field regains focus after the toolbar's overflow menu closes.
    private func chatInteractionOccurred() {
        guard showsChatPanel else { return }
        interaction.beginChatInteraction()
    }

    // Opening chat never focuses the field; the keyboard appears only when
    // the field is tapped. Sharing a variation still requests focus itself.
    private var conversationPanel: some View {
        ChatLog(game: game, session: chatSession, selection: chatSelection,
                selectedChannel: selectedChatChannel,
                variationShareDraft: currentGameVariationShareDraft,
                showsComposer: false,
                onInteraction: chatInteractionOccurred,
                onVariationShared: finishVariationSharing,
                onCancelVariationSharing: cancelVariationSharing)
            .background(GameDetailAppearance.panel)
            #if DEBUG && MAIN_APP
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                guard SurroundUITestContract.isEnabled else { return }
                let entry = "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
                if chatPanelLayoutSizes.last != entry && chatPanelLayoutSizes.count < 64 {
                    chatPanelLayoutSizes.append(entry)
                }
            }
            .onDisappear { chatPanelLayoutSizes = [] }
            #endif
    }

    /// Chat arrives at its final size, fading in with a short slide from the
    /// edge it opens from: the leading side for a side column or the other
    /// screen, the top above a portrait board. Its frame never interpolates
    /// from an empty slot, so lines never rewrap while it animates.
    private func chatPanelTransition(panel: CGRect, board: CGRect) -> AnyTransition {
        let fromLeading = !board.isEmpty && panel.maxX <= board.minX + 1
        return .opacity.combined(with: .offset(x: fromLeading ? -16 : 0, y: fromLeading ? 0 : -16))
    }

    private var chatComposerHeight: CGFloat {
        guard ogs.user != nil else { return 0 }
        return currentGameVariationShareDraft.wrappedValue == nil
            ? messageComposerHeight : variationComposerHeight
    }

    private var chatComposer: some View {
        NewChatInput(game: game, session: chatSession,
                     selectedChannel: selectedChatChannel,
                     variationShareDraft: currentGameVariationShareDraft,
                     onInteraction: chatInteractionOccurred,
                     onVariationShared: finishVariationSharing,
                     onCancelVariationSharing: cancelVariationSharing)
            .id(chatSession.composerPresentationID)
            .frame(minHeight: 50)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { height in
                let height = max(50, height)
                if currentGameVariationShareDraft.wrappedValue == nil {
                    if messageComposerHeight != height { messageComposerHeight = height }
                } else if variationComposerHeight != height {
                    variationComposerHeight = height
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .background(GameDetailAppearance.panel)
            .overlay(alignment: .top) { Divider().allowsHitTesting(false) }
    }

    private func analysisPanel(plan: GameDetailLayoutPlan) -> some View {
        AnalyzeTreeView(game: game, selectedPosition: analysisPositionSelection,
                        vertical: plan.verticalAnalysisTree)
            .background(GameDetailAppearance.panel, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func availablePanelDivision(in geometry: GeometryProxy) -> CGRect? {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            return geometry.reservedRegions(kind: .division, options: .includeInactive)
                .first.map(\.frame)
        }
        #endif
        return nil
    }

    private func activeDivision(in geometry: GeometryProxy) -> CGRect? {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            // ReservedRegion.frame already includes its interaction margins.
            // Expanding it again needlessly takes space from both screen panes.
            return geometry.reservedRegions(kind: .division)
                .first(where: \.isActive).map(\.frame)
        }
        #endif
        return nil
    }

    private struct ColumnIdentityStyle {
        let avatarSize: CGFloat
        let padding: CGFloat
    }

    private func columnIdentityStyle(in geometry: GeometryProxy) -> ColumnIdentityStyle {
        if compact { return .init(avatarSize: 40, padding: 5) }
        if let division = activeDivision(in: geometry), division.width > division.height {
            return .init(avatarSize: 56, padding: 8)
        }
        return .init(avatarSize: 52, padding: 8)
    }

    private func layoutPlan(in geometry: GeometryProxy, columnStyle: ColumnIdentityStyle,
                            analyze: Bool? = nil, chat: Bool? = nil) -> GameDetailLayoutPlan {
        let actionMetrics = GameControlRowMetrics(dynamicTypeSize: dynamicTypeSize, locale: locale,
                                                 phase: game.gamePhase)
        // v149: the Duo Closed landscape column's detail lines, measured for
        // the values the cards show (the disconnect snapshot while offline).
        let connected = ogs.socketStatus == .connected
        let frozenClock = connected ? nil : game.disconnectedClock
        func columnDetail(fullCards: Bool) -> GameDetailColumnDetailLayouts {
            GameDetailColumnDetailLayouts(game: game, fullCards: fullCards, cardWidth: 126,
                                          scale: min(clockScale, 1.65),
                                          clockOverride: frozenClock, isConnected: connected)
        }
        return GameDetailLayoutPlan(
            size: geometry.size, compact: compact, zen: zenMode,
            analyze: analyze ?? showsAnalysisPanel, chat: chat ?? showsChatPanel,
            hidesBoard: !showsCompactChatBoard.wrappedValue,
            keyboard: attachedKeyboardVisible, keyboardLandscape: horizontal,
            accessibility: dynamicTypeSize.isAccessibilitySize,
            foldsClock: dynamicTypeSize >= .xxxLarge, clockScale: min(clockScale, 1.65),
            actionSize: actionMetrics.horizontalSize, actionMetrics: actionMetrics,
            composerHeight: chatComposerHeight, keyboardOverlap: keyboardOverlap,
            division: activeDivision(in: geometry), panelDivision: availablePanelDivision(in: geometry),
            usesVerticalToolbar: isVerticalToolbar || verticalToolbarPose, preview: showsChatPreview,
            zenBoardCenterY: zenBoardCenterY,
            identityRowHeight: GameDetailPlayerIdentity.rowHeight(dynamicTypeSize: dynamicTypeSize),
            identityColumnHeight: GameDetailPlayerIdentity.columnHeight(
                dynamicTypeSize: dynamicTypeSize, avatarSize: columnStyle.avatarSize,
                padding: columnStyle.padding),
            opponentSharesStatusWhenFolded: compact && UIDevice.current.userInterfaceIdiom == .pad
                && availablePanelDivision(in: geometry) == nil,
            recoveryHeight: recoveryHeight,
            fullClockFooterWidth: GameDetailClockPair.fullFooterWidth(game: game, scale: min(clockScale, 1.65)),
            compactClockLineWidth: GameDetailClockPair.compactLineWidth(game: game, scale: min(clockScale, 1.65)),
            compactColumnIdentityHeight: GameDetailPlayerIdentity.compactColumnHeight(
                dynamicTypeSize: dynamicTypeSize,
                secondLine: GameDetailPlayerIdentity.columnChipsHaveSecondLine(game: game, hidesRank: hidesRank)),
            compactColumnIdentityShortHeight: GameDetailPlayerIdentity.compactColumnHeight(
                dynamicTypeSize: dynamicTypeSize, secondLine: false),
            columnDetail: columnDetail(fullCards: true), compactColumnDetail: columnDetail(fullCards: false),
            chromeBandTop: chromeBandTop)
    }

    #if DEBUG && MAIN_APP
    private var clockModelDiagnostic: String {
        let black = game.clock?.blackTime.timeLeft.map { timeString(timeLeft: $0) } ?? "-"
        let white = game.clock?.whiteTime.timeLeft.map { timeString(timeLeft: $0) } ?? "-"
        return "black=\(black);white=\(white);frozen=\(game.disconnectedClock != nil)"
    }

    private func layoutDiagnostic(in geometry: GeometryProxy, plan: GameDetailLayoutPlan) -> String {
        var value = "content=\(geometry.size);global=\(geometry.frame(in: .global));safeArea=\(geometry.safeAreaInsets);board=\(plan[.board])"
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            let regions = geometry.reservedRegions(kind: .division, options: .includeInactive)
            for region in regions {
                value += ";division(active=\(region.isActive),frame=\(region.frame),margins=\(region.margins))"
            }
        }
        #endif
        return value
    }
    #endif

    private func clockStyle(_ style: GameDetailLayoutPlan.ClockStyle) -> GameDetailClockStyle {
        switch style {
        case .full: return .full
        case .compact: return .compact
        case .inline: return .inline
        }
    }

    private var gameContent: some View {
        GeometryReader { geometry in
            let columnStyle = columnIdentityStyle(in: geometry)
            let plan = layoutPlan(in: geometry, columnStyle: columnStyle)
            // Chat's slots always hold the frames chat has when open, so it
            // appears and leaves at its final size instead of growing out of
            // an empty slot.
            let chatPlan = showsChatPanel ? plan
                : layoutPlan(in: geometry, columnStyle: columnStyle, analyze: false, chat: true)
            let chatTransition = chatPanelTransition(panel: chatPlan[.chat], board: chatPlan[.board])
            let opponentFacesBoard = plan.verticalActions
                || (plan[.opponent].width > 0 && plan[.opponent].maxX < plan[.board].minX)
            GameDetailLayout(plan: plan, chatPlan: chatPlan) {
                // Keep this board in a single structural slot across every pose,
                // panel and Zen transition. Selection lives in this screen. The
                // layout animates its frame, so it redraws at every size.
                boardView
                    .gameDetailSlot(.board, plan: plan)
                GameDetailClockPair(game: game, topLeftPlayerColor: topLeftPlayerColor,
                                    stacked: plan.stackedClocks, style: clockStyle(plan.clockStyle),
                                    narrowFullCards: plan.narrowFullClocks,
                                    narrowCompactCards: plan.narrowCompactClocks,
                                    spaciousCompact: plan.spaciousCompactClocks,
                                    columnCards: plan.columnClockCards,
                                    columnDetailLayouts: plan.columnDetailLayouts,
                                    columnCardsGrow: plan.columnCardsGrow,
                                    showsCurrentPlayerOnly: plan.showsCurrentPlayerClockOnly,
                                    fullCardScale: plan.fullClockScale,
                                    showsRoleNames: plan.hidesIdentity && !zenMode && dynamicTypeSize.isAccessibilitySize,
                                    blocksGameActions: gameControlState.blocksGameActions,
                                    showsStatus: true)
                    .gameDetailSlot(.clocks, plan: plan)
                recoveryBanner.gameDetailSlot(.status, plan: plan).zIndex(2)
                GameDetailPlayerIdentity(game: game, color: topLeftPlayerColor,
                                         vertical: plan.verticalOpponentIdentity,
                                         facesBoard: opponentFacesBoard,
                                         columnAvatarSize: plan.compactColumnIdentity ? 32 : columnStyle.avatarSize,
                                         columnPadding: columnStyle.padding,
                                         compactColumn: plan.compactColumnIdentity,
                                         columnSecondLine: columnChipSecondLine(plan))
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: opponentFacesBoard ? .topTrailing : .leading)
                    .gameDetailSlot(.opponent, plan: plan)
                actionCorner(plan: plan, columnStyle: columnStyle).gameDetailSlot(.actions, plan: plan)
                Group { if showsAnalysisPanel { analysisPanel(plan: plan) } }
                    .gameDetailSlot(.analysis, plan: plan)
                Group {
                    if showsAnalysisPanel {
                        analyzeControlBar(verticalTree: plan.verticalAnalysisTree)
                    }
                }
                    .gameDetailSlot(.analysisControls, plan: plan)
                GameDetailInformationCard(game: game)
                    .gameDetailSlot(.information, plan: plan)
                Group { if showsChatPanel {
                    conversationPanel.clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
                        .transition(chatTransition)
                } }
                    .gameDetailSlot(.chat, plan: chatPlan)
                Group { if showsChatPanel && ogs.user != nil {
                    chatComposer.clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
                        .transition(chatTransition)
                } }
                    .gameDetailSlot(.composer, plan: chatPlan)
                Group { if showsChatPreview { chatPreviewBar } }
                    .gameDetailSlot(.preview, plan: plan)
            }
            .preference(key: GameDetailClocksInHeaderPreferenceKey.self, value: plan.clocksInHeader)
            .preference(key: GameDetailCurrentPlayerClockInHeaderPreferenceKey.self,
                        value: plan.clocksInHeader && plan.showsCurrentPlayerClockOnly)
            .preference(key: GameDetailOpponentHeaderPreferenceKey.self,
                        value: plan.hidesOpponentIdentity)
            #if DEBUG && MAIN_APP
            .overlay(alignment: .topLeading) {
                if SurroundUITestContract.isEnabled {
                    ZStack {
                        Color.clear.frame(width: 1, height: 1)
                            .allowsHitTesting(false)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Game layout geometry")
                            .accessibilityIdentifier("game.layout.geometry")
                            .accessibilityValue(Text(verbatim: layoutDiagnostic(in: geometry, plan: plan)))
                        Color.clear.frame(width: 1, height: 1)
                            .allowsHitTesting(false)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Chat panel layout sizes")
                            .accessibilityIdentifier("game.chat.layoutSizes")
                            .accessibilityValue(Text(verbatim: chatPanelLayoutSizes.joined(separator: ";")))
                        // The shared model clock, which keeps ticking locally
                        // while the displayed clocks hold the disconnect value.
                        Color.clear.frame(width: 1, height: 1)
                            .allowsHitTesting(false)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Clock model")
                            .accessibilityIdentifier("game.clock.model")
                            .accessibilityValue(Text(verbatim: clockModelDiagnostic))
                    }
                }
            }
            #endif
            .overlay {
                if chatSession.wantsInputFocus && showsChatPanel && attachedKeyboardVisible {
                    // A first tap outside the composer dismisses the on-screen
                    // keyboard without triggering the board, a clock popover, or
                    // an action. With a hardware keyboard nothing covers the
                    // board, so the tap plays and ends editing (below).
                    let outsideChat = Path { path in
                        path.addRect(CGRect(origin: .zero, size: geometry.size))
                        path.addRect(plan[.chat])
                        path.addRect(plan[.composer])
                    }
                    outsideChat.fill(.clear, style: FillStyle(eoFill: true))
                        .contentShape(outsideChat, eoFill: true)
                        .onTapGesture {
                            chatSession.dismissInput()
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                        .accessibilityHidden(true)
                }
            }
            .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                // Hardware keyboard: a tap outside chat ends editing while the
                // board, clock or action under it still receives the tap.
                guard chatSession.wantsInputFocus, showsChatPanel, !attachedKeyboardVisible,
                      !plan[.chat].contains(tap.location), !plan[.composer].contains(tap.location)
                else { return }
                chatSession.dismissInput()
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            })
        }
        .modifier(GameDetailVoiceCountdown(game: game))
    }

    private var presentedGameContent: some View {
        gameContent
        .modifier(GameControlPresentation(
            state: gameControlState,
            game: game,
            pendingMove: $pendingMove,
            pendingPosition: $pendingPosition
        ))
        .onChange(of: isChatRouteActive) { _, active in
            chatSession.setGamePresentationActive(active && !zenMode)
        }
        #if DEBUG && MAIN_APP
        .surroundAnimationObservation(
            "game.content", ownerID: animationObservationID,
            focusRequestID: variationShareDraft.wrappedValue?.focusRequestID
        )
        .surroundAnimationState(
            "game.layoutState",
            value: "compact=\(compact);horizontal=\(horizontal);analyze=\(interaction.isAnalyzing);attachedKeyboard=\(attachedKeyboardVisible);zen=\(zenMode)",
            ownerID: animationObservationID,
            focusRequestID: variationShareDraft.wrappedValue?.focusRequestID
        )
        #endif
    }

    private var observedGameContent: some View {
        presentedGameContent
        .onReceive(game.$currentPosition) { [game] newPosition in
            self.pendingMove = nil
            self.pendingPosition = nil
            if !gameControlState.requiresScoringRefresh {
                self.stoneRemovalSelectedPoints.removeAll()
            }
            
            if game.currentPosition === analyticsPosition {
                analyticsPosition = newPosition
            }
            
            if soundOnStonePlacement {
                if self.stonePlacingPlayer == nil {
                    if let audioData = NSDataAsset(name: "stonePlacing")?.data {
                        self.stonePlacingPlayer = try? AVAudioPlayer(data: audioData)
                    }
                }
                if let stonePlacingPlayer = stonePlacingPlayer {
                    if newPosition.previousPosition?.hasTheSamePosition(with: game.currentPosition) ?? false {
                        stonePlacingPlayer.play()
                    }
                }
            }
        }
        .onAppear {
            if owningRootView == nil { owningRootView = navigation.main.rootView }
            chatSession.setGamePresentationActive(isChatRouteActive && !zenMode)
            isVisibleForAppReview = true
            if self.soundOnStonePlacement {
                if let audioData = NSDataAsset(name: "stonePlacing")?.data {
                    self.stonePlacingPlayer = try? AVAudioPlayer(data: audioData)
                }
            }
            #if DEBUG && MAIN_APP
            if !hasAppliedUITestScene {
                hasAppliedUITestScene = true
                let designArtboard = SurroundUITestContract.gameDetailDesignArtboard
                let designAnalysis = designArtboard.map { (22...31).contains($0) || [72, 82].contains($0) } ?? false
                let scene = SurroundUITestContract.compatibilityScene
                if designAnalysis || scene == .gameAnalysis || scene == .finishedGamePlayback {
                    displayedPanel = .analyze
                    DispatchQueue.main.async {
                        if designAnalysis {
                            analyticsPosition = game.moveTree.positionsByLastMoveNumber[
                                SurroundUITestContract.gameDetailDesignAnalysisSelectedMoveNumber
                            ]?.compactMap { $0 }.first {
                                $0.lastMove == .placeStone(
                                    SurroundUITestContract.gameDetailDesignAnalysisSelectedRow,
                                    SurroundUITestContract.gameDetailDesignAnalysisSelectedColumn
                                )
                            } ?? game.currentPosition
                        } else {
                            analyticsPosition = game.positionByLastMoveNumber[
                                SurroundUITestContract.screenshotAnalysisSelectedMoveNumber
                            ] ?? game.currentPosition
                        }
                    }
                } else if scene == .gameChat {
                    displayedPanel = .chat
                }
            }
            #endif
        }
        .task(id: reviewGameObservationIdentity) {
            // Visibility and parent context readiness both restart observation,
            // including when this task starts before the view's onAppear.
            guard !Task.isCancelled else {
                return
            }
            updateReviewGameObservation()
        }
        .onDisappear {
            isVisibleForAppReview = false
            stopReviewGameObservation()
            self.stonePlacingPlayer = nil
            // This owner survives adaptive layout changes. Leaving its route
            // suspends keyboard focus without discarding the chat draft.
            chatSession.gamePresentationDisappeared()
            // Preserve analysis, markups, and chat selection across both pushed
            // destinations and tab switches. Game/mode changes below reset
            // them; removing this game route destroys the retained view state.
        }
        .onReceive(game.moveTree.objectWillChange) {
            DispatchQueue.main.async {
                pruneAnalyzeMarkups()
            }
        }
    }

    private var interactiveGameContent: some View {
        observedGameContent
        .onChange(of: selectedConditionalVariation.wrappedValue) { _, branch in
            guard let branch else { return }
            selectedConditionalVariation.wrappedValue = nil
            guard game.conditionalMoveBranches.contains(where: { $0.id == branch.id }) else { return }
            showConditionalVariation(branch)
        }
        .onChange(of: displayedPanel) { oldValue, newValue in
            if oldValue == .chat && newValue != .chat {
                selectedChatItem = nil
                // A task switch dismisses input; replacing its adaptive host
                // during rotation still preserves focus through the session.
                chatSession.dismissInput()
            }
        }
        .onChange(of: interaction.isAnalyzing, initial: true) { _, analyzing in
            guard analyzing else { return }
            selectedChatItem = nil
            if analyticsPosition == nil {
                analyticsPosition = game.currentPosition
            }
        }
        .onChange(of: showsChatPanel, initial: true) { _, visible in
            if visible { game.markAllChatAsRead() }
        }
        .onChange(of: interaction.analysisResetRevision) { _, _ in
            // Account and game-speed changes reset the session. Panel switches,
            // folding and chat previews retain its position and tools.
            analyticsPosition = interaction.isAnalyzing ? game.currentPosition : nil
            analyticsPendingMove = nil
            analyticsPendingPosition = nil
            preferredNextPositionByPosition.removeAll()
            resetAnalyzeBoardTool()
        }
        .onChange(of: analyzeBoardTool) { _, newValue in
            if newValue != .moves {
                analyticsPendingMove = nil
                analyticsPendingPosition = nil
            }
        }
        .onChange(of: zenMode) { _, newValue in
            chatSession.setGamePresentationActive(!newValue && isChatRouteActive)
            if !newValue && currentGameVariationShareDraft.wrappedValue != nil {
                // Leaving Zen explicitly resumes the suspended sharing flow.
                // A size-class change alone keeps any keyboard dismissal.
                chatSession.requestInputFocus()
            }
        }
    }

    var body: some View {
        interactiveGameContent
        .onChange(of: selectedChatChannel.wrappedValue, initial: true) { _, channel in
            chatSession.selectChannel(channel)
        }
        .onChange(of: game.ID) { _, _ in
            updateReviewGameObservation()
            chatSession.reset()
            conditionalMoveRequest.updateContext(gameID: game.ID, accountID: ogs.user?.id)
            showingConditionalMoveSubmissionError = false
            preferredNextPositionByPosition.removeAll()
            pendingMove = nil
            pendingPosition = nil
            stoneRemovalSelectedPoints.removeAll()
            selectedChatItem = nil
            analyzeMarkupsByPosition.removeAll()
            resetAnalyzeBoardTool()
            if analyticsPosition != nil {
                // The previous game's position is not in this game's move
                // tree. Keep Analyze on the game that is actually on screen.
                analyticsPosition = game.currentPosition
            }
        }
        .onChange(of: reviewGamePhase) { _, _ in
            updateReviewGameObservation()
        }
        .onChange(of: game.gameData?.timeControl.speed) { _, _ in
            updateReviewGameObservation()
        }
        .onChange(of: game.isUserPlaying) { _, _ in
            updateReviewGameObservation()
        }
        .onChange(of: ogs.user?.id) { _, _ in
            chatSession.reset()
            conditionalMoveRequest.updateContext(gameID: game.ID, accountID: ogs.user?.id)
            showingConditionalMoveSubmissionError = false
            selectedChatItem = nil
            pendingMove = nil
            pendingPosition = nil
            stopReviewGameObservation()
            updateReviewGameObservation()
        }
        .onChange(of: scenePhase) { _, _ in
            updateReviewGameObservation()
        }
        .onChange(of: game.analysisAvailable) { _, newValue in
            if !newValue {
                resetAnalyzeBoardTool()
            }
        }
        .onChange(of: game.conditionalMoveBranches.map(\.id)) {
            pruneAnalyzeMarkups()
            if let analyticsPosition,
               !game.moveTree.contains(analyticsPosition) {
                self.analyticsPosition = game.currentPosition
            }
        }
        .alert(
            "Couldn’t update conditional moves",
            isPresented: $showingConditionalMoveSubmissionError
        ) {} message: {
            Text("Please try again.")
        }
    }
}

#if DEBUG
#Preview("Play — Player info", traits: .fixedLayout(width: 390, height: 844)) {
    @Previewable @State var zenMode = false
    @Previewable @StateObject var chatSession = ChatSessionState()
    @Previewable @State var interaction = GameDetailInteraction(panel: .playerInfo)
    let game = TestData.Ongoing19x19wBot3
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "kata-bot", id: 592684),
        activeGames: [game]
    )

    NavigationView {
        SingleGameView(
            compact: true,
            game: game,
            zenMode: $zenMode,
            interaction: $interaction,
            chatSession: chatSession
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(ogs)
    .environmentObject(StackRouter())
    .environmentObject(NavigationService())
}

#Preview("Play — Analysis", traits: .fixedLayout(width: 390, height: 844)) {
    @Previewable @State var zenMode = false
    @Previewable @StateObject var chatSession = ChatSessionState()
    @Previewable @State var interaction = GameDetailInteraction(panel: .analyze)
    let game = TestData.Ongoing19x19wBot3
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "kata-bot", id: 592684),
        activeGames: [game]
    )

    NavigationView {
        SingleGameView(
            compact: true,
            game: game,
            zenMode: $zenMode,
            interaction: $interaction,
            chatSession: chatSession
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(ogs)
    .environmentObject(StackRouter())
    .environmentObject(NavigationService())
}

#Preview("Finished game — Chat", traits: .fixedLayout(width: 390, height: 844)) {
    @Previewable @State var zenMode = false
    @Previewable @StateObject var chatSession = ChatSessionState()
    @Previewable @State var interaction = GameDetailInteraction(panel: .chat)
    let game = TestData.EuropeanChampionshipWithChat
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950),
        activeGames: [game]
    )

    NavigationView {
        SingleGameView(
            compact: true,
            game: game,
            zenMode: $zenMode,
            interaction: $interaction,
            chatSession: chatSession
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(ogs)
    .environmentObject(StackRouter())
    .environmentObject(NavigationService())
}

#Preview("Stone removal", traits: .fixedLayout(width: 390, height: 844)) {
    @Previewable @State var zenMode = false
    @Previewable @StateObject var chatSession = ChatSessionState()
    @Previewable @State var interaction = GameDetailInteraction(panel: .playerInfo)
    let game = TestData.StoneRemoval9x9
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "HongAnhKhoa", id: 314459),
        activeGames: [game]
    )

    NavigationView {
        SingleGameView(
            compact: true,
            game: game,
            zenMode: $zenMode,
            interaction: $interaction,
            chatSession: chatSession
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(ogs)
    .environmentObject(StackRouter())
    .environmentObject(NavigationService())
}

#Preview("Finished game — Score and playback", traits: .fixedLayout(width: 390, height: 844)) {
    @Previewable @State var zenMode = false
    @Previewable @StateObject var chatSession = ChatSessionState()
    @Previewable @State var interaction = GameDetailInteraction(panel: .playerInfo)
    let game = TestData.Scored19x19Korean
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "HongAnhKhoa", id: 314459),
        activeGames: [game]
    )

    NavigationView {
        SingleGameView(
            compact: true,
            game: game,
            zenMode: $zenMode,
            interaction: $interaction,
            chatSession: chatSession
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(ogs)
    .environmentObject(StackRouter())
    .environmentObject(NavigationService())
}
#endif
