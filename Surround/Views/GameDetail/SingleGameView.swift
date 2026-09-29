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
    var compactBoardSize: CGFloat = 0
    @ObservedObject var game: Game
    var reducedPlayerInfoVerticalPadding: Bool = false
    var reserveCompactBottomBarClearance = false
    var goToNextGame: (() -> ())?
    var horizontal = false
    @Binding var zenMode: Bool
    var exitZenMode: (() -> ())?
    
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject private var stackRouter: StackRouter
    @EnvironmentObject private var navigation: NavigationService
    @Environment(\.owningStackRoute) private var owningStackRoute
    @Environment(\.compactGameModesInToolbar) private var compactGameModesInToolbar
    @Environment(\.openPlayerProfile) private var openPlayerProfile
    @State private var owningRootView: RootView?
    @Environment(\.colorScheme) private var colorScheme
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
    
    @Binding var interaction: GameDetailInteraction
    private var compactDisplayMode: GameDetailPanel {
        get { interaction.panel }
        nonmutating set { interaction.selectPanel(newValue) }
    }
    private var panelSelection: Binding<GameDetailPanel> {
        Binding(get: { interaction.panel },
                set: { interaction.selectPanel($0) })
    }
    @StateObject private var chatSession = ChatSessionState()
    @StateObject private var gameControlState = GameControlState()
    @State private var showsRengoTeamDetail = false
    @State private var preferredNextPositionByPosition =
        [ObjectIdentifier: BoardPosition]()
    var showsCompactChatBoard: Binding<Bool> = .constant(true)
    var variationShareDraft: Binding<VariationShareDraft?> = .constant(nil)
    var selectedChatChannel: Binding<OGSChatSendChannel> = .constant(.main)
    private var analyzeMode: Binding<Bool> {
        Binding(get: { interaction.isAnalyzing },
                set: { interaction.setAnalyzing($0) })
    }
    @Setting(.showsBoardCoordinates) var showsBoardCoordinates: Bool
    @Setting(.soundOnStonePlacement) var soundOnStonePlacement: Bool

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
    
    @Namespace var animation
    
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

    private var showsCompactHorizontalControlRow: Bool {
        compactDisplayMode != .analyze
            && (
                !attachedKeyboardVisible
                    || (compactDisplayMode == .chat
                        && !showsCompactChatBoard.wrappedValue)
            )
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
    
    private var showsAnalysisBoard: Bool {
        interaction.isAnalyzing && (!compact || compactDisplayMode == .analyze)
    }

    private var showsChatPreview: Bool {
        selectedChatItem?.preview.position != nil
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

    var controlRow: some View {
        GameControlRow(
            game: game,
            state: gameControlState,
            pendingMove: $pendingMove,
            pendingPosition: $pendingPosition,
            goToNextGame: goToNextGame,
            stoneRemovalOption: $stoneRemovalOption
        )
    }
    
    var verticalControlRow: some View {
        GameControlRow(
            game: game,
            state: gameControlState,
            horizontal: false,
            pendingMove: $pendingMove,
            pendingPosition: $pendingPosition,
            goToNextGame: goToNextGame,
            stoneRemovalOption: $stoneRemovalOption
        )
    }
    
    var boardView: some View {
        let selectedChatPreview = selectedChatItem?.preview
        return ZStack {
            if let selectedChatPosition = selectedChatPreview?.position {
                BoardView(
                    boardPosition: selectedChatPosition,
                    variation: selectedChatPreview?.variation,
                    showsCoordinate: showsBoardCoordinates && !(compact && attachedKeyboardVisible),
                    highlightCoordinates: selectedChatPreview?.coordinates ?? [],
                    markups: .constant(
                        selectedChatPreview?.variation?.markups ?? [:]
                    )
                )
            } else if let analyticsPosition = analyticsPosition, showsAnalysisBoard {
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
                    showsCoordinate: showsBoardCoordinates && !(compact && attachedKeyboardVisible),
                    playable: game.isUserTurn && !gameControlState.blocksGameActions,
                    stoneRemovable: game.isUserPlaying && game.gamePhase == .stoneRemoval && !gameControlState.blocksGameActions,
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
        if let preview = selectedChatItem?.preview,
           let position = preview.position {
            return boardUITestAccessibilityValue(
                position: position,
                variation: preview.variation,
                markups: preview.variation?.markups ?? [:]
            )
        }
        if let analyticsPosition,
           showsAnalysisBoard {
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
            if compact {
                compactDisplayMode = .analyze
            }
            analyzeMode.wrappedValue = true
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

    var compactDisplayModePicker: some View {
        ZStack(alignment: .topTrailing) {
            Picker(selection: panelSelection.animation(), label: Text("Display mode")) {
                if game.analysisAvailable {
                    Label("Analyze mode", systemImage: "arrow.triangle.branch")
                        .labelStyle(IconOnlyLabelStyle())
                        .tag(DisplayMode.analyze)
                } else {
                    Label("Playback mode", systemImage: "arrow.left.and.right")
                        .labelStyle(IconOnlyLabelStyle())
                        .tag(DisplayMode.analyze)
                }
                Label("Player info", systemImage: "person.crop.square.fill.and.at.rectangle")
                    .labelStyle(IconOnlyLabelStyle())
                    .tag(DisplayMode.playerInfo)
                Label("Chat", systemImage: "message")
                    .labelStyle(IconOnlyLabelStyle())
                    .tag(DisplayMode.chat)
            }
            .pickerStyle(SegmentedPickerStyle())
            .accessibilityIdentifier(
                SurroundUITestContract.AccessibilityID.gameDisplayModePicker
            )
            .fixedSize()
            .padding(.horizontal, 15)
            .padding(.vertical, 5)
            if game.chatUnreadCount > 0 {
                ZStack {
                    Circle().fill(Color(.systemRed))
                    Text(verbatim: game.chatUnreadCount > 9 ? "9+" : "\(game.chatUnreadCount)")
                        .font(.caption2).bold()
                        .minimumScaleFactor(0.2)
                        .foregroundColor(.white)
                        .frame(width: 15, height: 15)
                }
                .frame(width: 15, height: 15)
                .offset(x: -18, y: 5)
            }
        }
        .matchedGeometryEffect(id: "compactDisplayModePicker", in: animation)
    }
    
    var playerInfo: some View {
        ZStack(alignment: .topTrailing) {
            PlayersBannerView(
                game: game,
                topLeftPlayerColor: topLeftPlayerColor,
                reducesVerticalPadding: reducedPlayerInfoVerticalPadding,
                showsPlayersName: true,
                extendsBackgroundIntoTopSafeArea: compact,
                onSelectConditionalVariation: showConditionalVariation,
                rengoTeamDetail: $showsRengoTeamDetail
            )
            if !showsRengoTeamDetail && !compactGameModesInToolbar {
                compactDisplayModePicker
            }
        }
    }
    
    @ViewBuilder
    var compactClockHeader: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 10)
            if let currentPlayerColor = game.clock?.currentPlayerColor {
                HStack(spacing: 5) {
                    Stone(color: currentPlayerColor, shadowRadius: 2)
                        .frame(width: 20, height: 20)
                    InlineTimerView(
                        timeControl: game.gameData?.timeControl,
                        clock: game.clock,
                        player: currentPlayerColor,
                        pauseControl: game.pauseControl,
                        showsPauseReason: true
                    )
                }
            }
            Spacer(minLength: 10)
            if !compactGameModesInToolbar {
                compactDisplayModePicker
            }
        }
        .frame(minHeight: compactGameModesInToolbar ? 30 : nil)
    }
    
    var chatLog: some View {
        VStack(spacing: 0) {
            compactClockHeader
            ChatLog(
                game: game,
                session: chatSession,
                selection: chatSelection,
                selectedChannel: selectedChatChannel,
                variationShareDraft: currentGameVariationShareDraft,
                focusInputOnAppear: true,
                // This panel is already Chat. An outgoing composer's late
                // callback must not undo an explicit switch to another mode.
                onVariationShared: finishVariationSharing,
                onCancelVariationSharing:
                    cancelVariationSharing
            )
            .zIndex(-1)
        }
    }

    var analyzeTree: some View {
        VStack(spacing: 0) {
            compactClockHeader
            AnalyzeTreeView(game: game, selectedPosition: analysisPositionSelection)
        }
    }

    var analyzeControlBar: some View {
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
            deleteBranch: deleteAnalysisBranch
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
    
    var compactBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch compactDisplayMode {
            case .playerInfo:
                playerInfo
            case .chat:
                chatLog
            case .analyze:
                analyzeTree
            }
            if compactDisplayMode == .analyze && !attachedKeyboardVisible {
                analyzeControlBar
            }
            if showsCompactHorizontalControlRow && !showsChatPreview {
                Spacer(minLength: 10).frame(maxHeight: 15)
                controlRow
                    .padding(.horizontal)
                if reserveCompactBottomBarClearance {
                    Spacer(minLength: 10).frame(maxHeight: 15)
                } else {
                    Spacer(minLength: 10)
                }
            }
            if showsChatPreview {
                chatPreviewBar.padding(.horizontal, 10).padding(.vertical, 5)
            }
            if compactDisplayMode != .chat
                || showsCompactChatBoard.wrappedValue {
                if attachedKeyboardVisible && compactBoardSize < 320 {
                    EmptyView()
                } else {
                    if attachedKeyboardVisible, let blackPlayer = game.currentPlayer(with: .black), let whitePlayer = game.currentPlayer(with: .white) {
                        HStack(alignment: .top) {
                            boardView.frame(width: compactBoardSize / 2, height: compactBoardSize / 2)
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 0) {
                                HStack {
                                    Text(verbatim: blackPlayer.usernameAndRank)
                                        .font(.footnote).bold()
                                        .minimumScaleFactor(0.5)

                                    Stone(color: .black, shadowRadius: 2)
                                        .frame(width: 20, height: 20)
                                }
                                Spacer().frame(height: 5)
                                HStack {
                                    Text(verbatim: whitePlayer.usernameAndRank)
                                        .font(.footnote).bold()
                                        .minimumScaleFactor(0.5)
                                    Stone(color: .white, shadowRadius: 2)
                                        .frame(width: 20, height: 20)
                                }
                                Spacer().frame(height: 15)
                                if !showsChatPreview {
                                    verticalControlRow
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding([.leading, .trailing])
                            .padding(.top, 5)
                        }
                    } else {
                        boardView.frame(width: compactBoardSize, height: compactBoardSize)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
    /// SwiftUI measures the scalable preview first. The board then fits the
    /// remaining space instead of assuming the preview is one fixed-height row.
    private var regularBoardWithPreview: some View {
        VStack(spacing: showsChatPreview ? 5 : 0) {
            if showsChatPreview {
                chatPreviewBar
                    .fixedSize(horizontal: false, vertical: true)
            }
            GeometryReader { geometry in
                let size = max(0, min(geometry.size.width, geometry.size.height))
                boardView
                    .frame(width: size, height: size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    var regularVerticalBody: some View {
        GeometryReader { geometry -> AnyView in
            let width = geometry.size.width
            let height = geometry.size.height
            let chatHeight: CGFloat = 270
            let boardSize = max(0, min(width - 15 * 2, height - chatHeight - 15 * 3))
            return AnyView(erasing: VStack(alignment: .center, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    ChatLog(
                        game: game,
                        session: chatSession,
                        selection: chatSelection,
                        selectedChannel: selectedChatChannel,
                        variationShareDraft: currentGameVariationShareDraft,
                        onInteraction: { interaction.beginChatInteraction() },
                        onVariationShared: finishVariationSharing,
                        onCancelVariationSharing:
                            cancelVariationSharing
                    )
                        .frame(height: chatHeight)
                    Spacer(minLength: 15)
                    VStack {
                        PlayersBannerView(
                            game: game,
                            topLeftPlayerColor: topLeftPlayerColor,
                            playerIconSize: 80,
                            playerIconsOffset: 25,
                            showsPlayersName: true,
                            onSelectConditionalVariation:
                                showConditionalVariation,
                            rengoTeamDetail: $showsRengoTeamDetail
                        )
                        if !analyzeMode.wrappedValue && !showsChatPreview {
                            Spacer(minLength: 15).frame(maxHeight: 15)
                            controlRow
                        }
                    }.frame(width: 350)
                }
                Spacer(minLength: 15)
                if showsChatPreview {
                    regularBoardWithPreview.frame(width: boardSize, height: boardSize)
                } else {
                    boardView.frame(width: boardSize, height: boardSize)
                }
                Spacer(minLength: 0)
            }
            .padding())
        }
    }
    
    var regularHorizontalBody: some View {
        GeometryReader { geometry -> AnyView in
//            print("Geometry \(geometry.safeAreaInsets)")
            let width = geometry.size.width
            let height = geometry.size.height
            let minimumPlayerInfoWidth: CGFloat = 350
            let minimumChatWidth: CGFloat = 250
            let minimumPlayerInfoHeight: CGFloat = 80 + 15 * 2
            let boardSizeInfoLeft = min(height - 15 * 2, width - minimumPlayerInfoWidth - 15 * 3)
            let boardSizeInfoTop = min(height - 15 * 3 - minimumPlayerInfoHeight, width - 15 * 3 - minimumChatWidth)
            let infoLeft = boardSizeInfoLeft > boardSizeInfoTop
            let boardSize = infoLeft ? boardSizeInfoLeft : boardSizeInfoTop
            var playerIconsOffset: CGFloat = 25
            let horizontalPlayerInfoWidth = width - boardSize - 15 * 3
            if infoLeft {
                if horizontalPlayerInfoWidth > 600 {
                    playerIconsOffset = -80
                } else if horizontalPlayerInfoWidth > 400 {
                    playerIconsOffset = -10
                }
            } else {
                playerIconsOffset = -80
            }
            if boardSize <= 0 {
                return AnyView(EmptyView())
            }
            return AnyView(erasing: ZStack {
                VStack(spacing: 15) {
                    if !infoLeft {
                        PlayersBannerView(
                            game: game,
                            topLeftPlayerColor: topLeftPlayerColor,
                            playerIconSize: 80,
                            playerIconsOffset: playerIconsOffset,
                            showsPlayersName: true,
                            onSelectConditionalVariation:
                                showConditionalVariation,
                            rengoTeamDetail: $showsRengoTeamDetail
                        )
                    }
                    HStack(alignment: .top, spacing: 15) {
                        VStack(alignment: .trailing, spacing: 15) {
                            if infoLeft {
                                PlayersBannerView(
                                    game: game,
                                    topLeftPlayerColor: topLeftPlayerColor,
                                    playerIconSize: 80,
                                    playerIconsOffset: playerIconsOffset,
                                    showsPlayersName: true,
                                    onSelectConditionalVariation:
                                        showConditionalVariation,
                                    rengoTeamDetail: $showsRengoTeamDetail
                                ).frame(minWidth: minimumPlayerInfoWidth)
                            }
                            if !analyzeMode.wrappedValue && !showsChatPreview {
                                if horizontalPlayerInfoWidth < 350 {
                                    verticalControlRow
                                        .padding(.bottom, -15)
                                } else {
                                    controlRow
                                }
                            }
                            ChatLog(
                                game: game,
                                session: chatSession,
                                selection: chatSelection,
                                selectedChannel: selectedChatChannel,
                                variationShareDraft:
                                    currentGameVariationShareDraft,
                                onInteraction: { interaction.beginChatInteraction() },
                                onVariationShared: finishVariationSharing,
                                onCancelVariationSharing:
                                    cancelVariationSharing
                            )
                        }
                        if showsChatPreview {
                            regularBoardWithPreview.frame(width: boardSize)
                        } else {
                            boardView.frame(width: boardSize, height: boardSize)
                        }
                    }.frame(height: boardSize)
                }.padding(15)
            }.frame(width: width, height: height))
        }
    }
    
    func zenModeTimerBackground(playerColor: StoneColor) -> Color {
        if colorScheme == .dark {
            return playerColor == .black ? Color(.systemGray6) : Color(.systemGray4)
        } else {
            return playerColor == .black ? Color(.systemGray2) : Color(.systemGray5)
        }
    }
    
    func zenModeTimer(playerColor: StoneColor, horizontal: Bool = true) -> some View {
        let captures = game.currentPosition.captures[playerColor] ?? 0
        let topLeft = playerColor == topLeftPlayerColor
        let hasTimeControl = game.gameData?.timeControl.system != .None
        let timer = TimerView(
            timeControl: game.gameData?.timeControl,
            clock: game.clock,
            player: playerColor,
            mainFont: compact ? Font.body : Font.title3,
            subFont: compact ? Font.subheadline : Font.body)
        return ZStack(alignment: topLeft ? .topLeading : .bottomTrailing) {
            if horizontal {
                HStack {
                    if hasTimeControl && topLeft {
                        timer
                        Divider()
                    }
                    Text("\(captures) captures", comment: "SingleGameView - vary for plural")
                    if hasTimeControl && !topLeft {
                        Divider()
                        timer
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 25)
                .padding(.vertical, 10)
            } else {
                VStack(alignment: .trailing) {
                    if hasTimeControl {
                        timer
                        Divider()
                    }
                    Text("\(captures) captures", comment: "SingleGameView - vary for plural")
                }
                .fixedSize(horizontal: /*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/, vertical: false)
                .padding(.horizontal, 25)
                .padding(.vertical, 10)
            }
            Stone(color: playerColor, shadowRadius: 2)
                .frame(width: 20, height: 20)
                .offset(x: topLeft ? -10 : 10, y: topLeft ? -10 : 10)
        }
        .background(zenModeTimerBackground(playerColor: playerColor).shadow(radius: 2))
    }
    
    var zenModeBody: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geometry in
                if geometry.size.height > geometry.size.width - 200 {
                    VStack(spacing: 0) {
                        Spacer()
                        HStack {
                            zenModeTimer(playerColor: topLeftPlayerColor)
                                .padding(.leading, 15)
                            Spacer()
                        }
                        Spacer()
                        boardView
                            .padding(compact ? 0 : 15)
                            .aspectRatio(1, contentMode: .fit)
                        if compact {
                            controlRow.padding()
                        }
                        Spacer()
                        HStack {
                            Spacer()
                            if !compact {
                                verticalControlRow.padding()
                            }
                            zenModeTimer(playerColor: topLeftPlayerColor.opponentColor())
                                .padding(.trailing, 15)
                        }
                        Spacer()
                    }
                } else {
                    HStack(spacing: 0) {
                        Spacer()
                        VStack {
                            zenModeTimer(playerColor: topLeftPlayerColor, horizontal: false)
                                .padding(.top, 15)
                            Spacer()
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            boardView.padding(15).aspectRatio(1, contentMode: .fit)
                            verticalControlRow.padding(.horizontal)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Spacer()
                            zenModeTimer(playerColor: topLeftPlayerColor.opponentColor(), horizontal: false)
                                .padding(.bottom, 15)
                        }
                        Spacer()
                    }
                }
            }
            if !compact {
                Button(action: { if let exitZenMode { exitZenMode() } }) {
                    Label("Exit Zen mode", systemImage: "arrow.down.forward.and.arrow.up.backward")
                        .labelStyle(IconOnlyLabelStyle())
                }
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameZenExit)
                .surroundUITestZenShortcut()
                .padding()
            }
        }
    }
    
    // Bound each type-checking expression while retaining one state owner and
    // the same unconditional modifier chain across adaptive layouts.
    private var gameContent: some View {
        Group {
            if zenMode {
                zenModeBody
            } else {
                if compact {
                    compactBody
                } else {
                    VStack(spacing: 0) {
                        if horizontal {
                            regularHorizontalBody
                        } else {
                            regularVerticalBody
                        }
                        if analyzeMode.wrappedValue {
                            // Keep the menu presenter alive while the keyboard
                            // opens and the Share menu finishes dismissing.
                            analyzeControlBar
                                .frame(height: attachedKeyboardVisible ? 0 : nil)
                                .clipped()
                                .allowsHitTesting(!attachedKeyboardVisible)
                                .accessibilityHidden(attachedKeyboardVisible)
                                #if DEBUG && MAIN_APP
                                .surroundAnimationObservation(
                                    "analyze.collapsibleRegion",
                                    ownerID: animationObservationID,
                                    focusRequestID: variationShareDraft.wrappedValue?.focusRequestID
                                )
                                #endif
                            if !attachedKeyboardVisible {
                                AnalyzeTreeView(game: game, selectedPosition: analysisPositionSelection)
                                    .frame(maxHeight: 240)
                            }
                        }
                    }
                }
            }
        }
    }

    private var presentedGameContent: some View {
        gameContent
        .modifier(GameControlPresentation(
            state: gameControlState,
            game: game,
            pendingMove: $pendingMove,
            pendingPosition: $pendingPosition
        ))
        .environment(\.openPlayerProfile, openPlayerProfile.map { openProfile in
            { player in
                chatSession.gamePresentationDisappeared()
                openProfile(player)
            }
        })
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
            value: "compact=\(compact);horizontal=\(horizontal);analyze=\(analyzeMode.wrappedValue);attachedKeyboard=\(attachedKeyboardVisible);zen=\(zenMode)",
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
                switch SurroundUITestContract.compatibilityScene {
                case .gameAnalysis, .finishedGamePlayback:
                    compactDisplayMode = .analyze
                    analyzeMode.wrappedValue = true
                    DispatchQueue.main.async {
                        analyticsPosition = game.positionByLastMoveNumber[
                            SurroundUITestContract
                                .screenshotAnalysisSelectedMoveNumber
                        ] ?? game.currentPosition
                    }
                case .gameChat:
                    compactDisplayMode = .chat
                default:
                    break
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
        .onChange(of: compactDisplayMode) { oldValue, newValue in
            if oldValue == .chat && newValue != .chat {
                selectedChatItem = nil
            }
        }
        .onChange(of: interaction.isAnalyzing, initial: true) { _, analyzing in
            analyticsPendingMove = nil
            analyticsPendingPosition = nil
            if analyzing {
                selectedChatItem = nil
                if analyticsPosition == nil {
                    analyticsPosition = game.currentPosition
                }
            }
        }
        .onChange(of: interaction.analysisResetRevision) { _, _ in
            // Only explicit mode exits reset the session. Folding, sharing,
            // and selecting a read-only chat preview can resume its position.
            analyticsPosition = interaction.isAnalyzing ? game.currentPosition : nil
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
            if newValue {
                selectedChatItem = nil
                resetAnalyzeBoardTool()
            } else if currentGameVariationShareDraft.wrappedValue != nil {
                // Leaving Zen explicitly resumes the suspended sharing flow.
                // A size-class change alone keeps any keyboard dismissal.
                chatSession.requestInputFocus()
            }
        }
    }

    var body: some View {
        interactiveGameContent
        .onChange(of: game.ID) { _, _ in
            updateReviewGameObservation()
            chatSession.reset()
            conditionalMoveRequest.updateContext(gameID: game.ID, accountID: ogs.user?.id)
            showingConditionalMoveSubmissionError = false
            preferredNextPositionByPosition.removeAll()
            showsRengoTeamDetail = false
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
    @Previewable @State var interaction = GameDetailInteraction(panel: .playerInfo)
    let game = TestData.Ongoing19x19wBot3
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "kata-bot", id: 592684),
        activeGames: [game]
    )

    NavigationView {
        SingleGameView(
            compact: true,
            compactBoardSize: 390,
            game: game,
            zenMode: $zenMode,
            interaction: $interaction
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(ogs)
    .environmentObject(StackRouter())
    .environmentObject(NavigationService())
}

#Preview("Play — Analysis", traits: .fixedLayout(width: 390, height: 844)) {
    @Previewable @State var zenMode = false
    @Previewable @State var interaction = GameDetailInteraction(panel: .analyze)
    let game = TestData.Ongoing19x19wBot3
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "kata-bot", id: 592684),
        activeGames: [game]
    )

    NavigationView {
        SingleGameView(
            compact: true,
            compactBoardSize: 390,
            game: game,
            zenMode: $zenMode,
            interaction: $interaction
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(ogs)
    .environmentObject(StackRouter())
    .environmentObject(NavigationService())
}

#Preview("Finished game — Chat", traits: .fixedLayout(width: 390, height: 844)) {
    @Previewable @State var zenMode = false
    @Previewable @State var interaction = GameDetailInteraction(panel: .chat)
    let game = TestData.EuropeanChampionshipWithChat
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950),
        activeGames: [game]
    )

    NavigationView {
        SingleGameView(
            compact: true,
            compactBoardSize: 390,
            game: game,
            zenMode: $zenMode,
            interaction: $interaction
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(ogs)
    .environmentObject(StackRouter())
    .environmentObject(NavigationService())
}

#Preview("Stone removal", traits: .fixedLayout(width: 390, height: 844)) {
    @Previewable @State var zenMode = false
    @Previewable @State var interaction = GameDetailInteraction(panel: .playerInfo)
    let game = TestData.StoneRemoval9x9
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "HongAnhKhoa", id: 314459),
        activeGames: [game]
    )

    NavigationView {
        SingleGameView(
            compact: true,
            compactBoardSize: 390,
            game: game,
            zenMode: $zenMode,
            interaction: $interaction
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(ogs)
    .environmentObject(StackRouter())
    .environmentObject(NavigationService())
}

#Preview("Finished game — Score and playback", traits: .fixedLayout(width: 390, height: 844)) {
    @Previewable @State var zenMode = false
    @Previewable @State var interaction = GameDetailInteraction(panel: .playerInfo)
    let game = TestData.Scored19x19Korean
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "HongAnhKhoa", id: 314459),
        activeGames: [game]
    )

    NavigationView {
        SingleGameView(
            compact: true,
            compactBoardSize: 390,
            game: game,
            zenMode: $zenMode,
            interaction: $interaction
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(ogs)
    .environmentObject(StackRouter())
    .environmentObject(NavigationService())
}
#endif
