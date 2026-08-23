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
    var goToNextGame: (() -> ())?
    var horizontal = false
    @Binding var zenMode: Bool
    var exitZenMode: (() -> ())?
    
    @EnvironmentObject var ogs: OGSService
    @Environment(\.colorScheme) private var colorScheme
    @State var pendingMove: Move? = nil
    @State var pendingPosition: BoardPosition? = nil
    @State var stoneRemovalSelectedPoints = Set<[Int]>()
    @State var stoneRemovalOption = StoneRemovalOption.toggleGroup
    var attachedKeyboardVisible = false
    
    @Binding var compactDisplayMode: DisplayMode
    var showsCompactChatBoard: Binding<Bool> = .constant(true)
    var variationShareDraft: Binding<VariationShareDraft?> = .constant(nil)
    var selectedChatChannel: Binding<OGSChatSendChannel> = .constant(.main)
    @State var showCompactModeSwitcher = true
    var analyzeMode: Binding<Bool> = .constant(false)
    var shouldHideActiveGamesCarousel: Binding<Bool> = .constant(false)
    @Setting(.showsBoardCoordinates) var showsBoardCoordinates: Bool
    @Setting(.soundOnStonePlacement) var soundOnStonePlacement: Bool

    @State private var selectedChatItem: ChatLogSelection?
    
    @State var analyticsPosition: BoardPosition?
    
    @State var analyticsPendingMove: Move? = nil
    @State var analyticsPendingPosition: BoardPosition? = nil
    
    @State var stonePlacingPlayer: AVAudioPlayer? = nil
    @State private var conditionalMoveSubmissionCancellable: AnyCancellable?
    @State private var showingConditionalMoveSubmissionError = false
    
    @Namespace var animation
    
    enum DisplayMode {
        case playerInfo
        case chat
        case analyze
    }

    private struct AnalyzeControlBarConditionalState {
        var canAdd = false
        var addReplacesVariations = false
        var canRemove = false
        var canDeleteBranch = false
        var deletesVariations = false
    }

    private var chatSelection: Binding<ChatLogSelection?> {
        Binding(
            get: { selectedChatItem },
            set: { newSelection in
                selectedChatItem = newSelection
                if newSelection != nil {
                    analyzeMode.wrappedValue = false
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

    private var showsCompactHorizontalControlRow: Bool {
        compactDisplayMode != .analyze
            && (
                !attachedKeyboardVisible
                    || (compactDisplayMode == .chat
                        && !showsCompactChatBoard.wrappedValue)
            )
    }
    
    var controlRow: some View {
        GameControlRow(
            game: game,
            pendingMove: $pendingMove,
            pendingPosition: $pendingPosition,
            goToNextGame: goToNextGame,
            stoneRemovalOption: $stoneRemovalOption,
            stoneRemovalSelectedPoints: $stoneRemovalSelectedPoints
        )
    }
    
    var verticalControlRow: some View {
        GameControlRow(
            game: game,
            horizontal: false,
            pendingMove: $pendingMove,
            pendingPosition: $pendingPosition,
            goToNextGame: goToNextGame,
            stoneRemovalOption: $stoneRemovalOption,
            stoneRemovalSelectedPoints: $stoneRemovalSelectedPoints
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
                    highlightCoordinates: selectedChatPreview?.coordinates ?? []
                )
            } else if let analyticsPosition = analyticsPosition, (compactDisplayMode == .analyze || analyzeMode.wrappedValue) {
                BoardView(
                    boardPosition: analyticsPosition,
                    variation: game.moveTree.variation(to: analyticsPosition),
                    showsCoordinate: showsBoardCoordinates,
                    playable: game.analysisAvailable,
                    newMove: $analyticsPendingMove,
                    newPosition: $analyticsPendingPosition,
                    allowsSelfCapture: game.gameData?.allowSelfCapture ?? false
                )
                .onChange(of: analyticsPendingMove) { _, newMove in
                    if let newMove = newMove {
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
                    playable: game.isUserTurn,
                    stoneRemovable: game.isUserPlaying && game.gamePhase == .stoneRemoval,
                    stoneRemovalOption: stoneRemovalOption,
                    newMove: $pendingMove,
                    newPosition: $pendingPosition,
                    allowsSelfCapture: game.gameData?.allowSelfCapture ?? false,
                    stoneRemovalSelectedPoints: $stoneRemovalSelectedPoints,
                    highlightCoordinates: selectedChatPreview?.coordinates ?? [],
                    undoRequestCoordinates: game.undoRequestCoordinates
                )
            }
            #if DEBUG && MAIN_APP
            if SurroundUITestContract.isEnabled {
                // Canvas does not otherwise expose a stable element to XCTest.
                Text(verbatim: "Go board")
                    .foregroundStyle(.clear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
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
                variation: preview.variation
            )
        }
        if let analyticsPosition,
           compactDisplayMode == .analyze || analyzeMode.wrappedValue {
            return boardUITestAccessibilityValue(
                position: analyticsPosition,
                variation: game.moveTree.variation(to: analyticsPosition)
            )
        }
        return boardUITestAccessibilityValue(
            position: game.currentPosition,
            variation: nil
        )
    }

    private func boardUITestAccessibilityValue(
        position: BoardPosition,
        variation: Variation?
    ) -> String {
        if let variation {
            return "variation:\(variation.basePosition.lastMoveNumber):"
                + variation.moves.map { $0.toOGSString() }
                    .joined(separator: "-")
        }
        return "position:\(position.lastMoveNumber):"
            + (position.lastMove?.toOGSString() ?? "none")
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
        return game.moveTree.variation(to: analyticsPosition) != nil
    }

    private func beginSharingSelectedVariation() {
        guard canShareSelectedVariation,
              let analyticsPosition,
              let variation = game.moveTree.variation(to: analyticsPosition) else {
            return
        }

        analyticsPendingMove = nil
        analyticsPendingPosition = nil
        selectedChatItem = nil
        variationShareDraft.wrappedValue = VariationShareDraft(
            gameID: game.ID,
            variation: variation
        )
        withAnimation {
            if compact {
                showsCompactChatBoard.wrappedValue = false
                compactDisplayMode = .chat
                analyzeMode.wrappedValue = false
            }
        }
    }

    private func cancelVariationSharing() {
        variationShareDraft.wrappedValue = nil
    }

    private func finishVariationSharing() {
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
            Picker(selection: $compactDisplayMode.animation(), label: Text("Display mode")) {
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
                showsPlayersName: !game.isUserPlaying,
                onSelectConditionalVariation: showConditionalVariation,
                showCompactModeSwitcher: $showCompactModeSwitcher
            )
            if showCompactModeSwitcher {
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
            compactDisplayModePicker
        }
    }
    
    var chatLog: some View {
        VStack(spacing: 0) {
            compactClockHeader
            ChatLog(
                game: game,
                selection: chatSelection,
                selectedChannel: selectedChatChannel,
                variationShareDraft: currentGameVariationShareDraft,
                focusInputOnAppear: true,
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
            AnalyzeTreeView(game: game, selectedPosition: $analyticsPosition)
        }
    }

    var analyzeControlBar: some View {
        let state = analyzeControlBarConditionalState
        return AnalyzeControlBar(
            moveTree: game.moveTree,
            selectedPosition: $analyticsPosition,
            analysisAvailable: game.analysisAvailable,
            canShareVariation: canShareSelectedVariation,
            canAddConditionalMoves: state.canAdd,
            addReplacesConditionalVariations:
                state.addReplacesVariations,
            canRemoveConditionalMoves: state.canRemove,
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
            analyticsPosition = destination
        } else if game.moveTree.contains(parentPosition) {
            analyticsPosition = parentPosition
        }
    }

    private func submitConditionalMovePlan(
        _ plan: ConditionalMovePlan,
        onSuccess: (() -> Void)? = nil
    ) {
        conditionalMoveSubmissionCancellable = ogs
            .submitConditionalMovePlan(plan, for: game)
            .sink { completion in
                if case .failure = completion {
                    showingConditionalMoveSubmissionError = true
                }
                conditionalMoveSubmissionCancellable = nil
            } receiveValue: {
                onSuccess?()
            }
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
            if showsCompactHorizontalControlRow {
                Spacer(minLength: 10).frame(maxHeight: 15)
                controlRow
                    .padding(.horizontal)
                Spacer(minLength: 10)
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
                                verticalControlRow
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
        .onChange(of: compactDisplayMode) { oldValue, newValue in
            if oldValue == .chat && newValue != .chat {
                selectedChatItem = nil
            }
            withAnimation {
                shouldHideActiveGamesCarousel.wrappedValue = newValue != .playerInfo
                if newValue == .analyze, analyticsPosition == nil {
                    analyticsPosition = game.currentPosition
                } else if newValue != .analyze {
                    analyticsPosition = nil
                }
            }
            analyzeMode.wrappedValue = newValue == .analyze
        }
    }
    
    var regularVerticalBody: some View {
        GeometryReader { geometry -> AnyView in
            let width = geometry.size.width
            let height = geometry.size.height
            let chatHeight: CGFloat = 270
            let boardSize = min(width - 15 * 2, height - chatHeight - 15 * 3)
            return AnyView(erasing: VStack(alignment: .center, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    ChatLog(
                        game: game,
                        selection: chatSelection,
                        selectedChannel: selectedChatChannel,
                        variationShareDraft: currentGameVariationShareDraft,
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
                                showConditionalVariation
                        )
                        if !analyzeMode.wrappedValue {
                            Spacer(minLength: 15).frame(maxHeight: 15)
                            controlRow
                        }
                    }.frame(width: 350)
                }
                Spacer(minLength: 15)
                boardView.frame(width: boardSize, height: boardSize)
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
                                showConditionalVariation
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
                                        showConditionalVariation
                                ).frame(minWidth: minimumPlayerInfoWidth)
                            }
                            if !analyzeMode.wrappedValue {
                                if horizontalPlayerInfoWidth < 350 {
                                    verticalControlRow
                                        .padding(.bottom, -15)
                                } else {
                                    controlRow
                                }
                            }
                            ChatLog(
                                game: game,
                                selection: chatSelection,
                                selectedChannel: selectedChatChannel,
                                variationShareDraft:
                                    currentGameVariationShareDraft,
                                onVariationShared: finishVariationSharing,
                                onCancelVariationSharing:
                                    cancelVariationSharing
                            )
                        }
                        boardView.frame(width: boardSize, height: boardSize)
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
    
    var body: some View {
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
                        if analyzeMode.wrappedValue && !attachedKeyboardVisible {
                            analyzeControlBar
                            AnalyzeTreeView(game: game, selectedPosition: $analyticsPosition)
                                .frame(maxHeight: 240)
                        }
                    }
                }
            }
        }
        .onReceive(game.$currentPosition) { [game] newPosition in
            self.pendingMove = nil
            self.pendingPosition = nil
            self.stoneRemovalSelectedPoints.removeAll()
            
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
            if self.soundOnStonePlacement {
                if let audioData = NSDataAsset(name: "stonePlacing")?.data {
                    self.stonePlacingPlayer = try? AVAudioPlayer(data: audioData)
                }
            }
            #if DEBUG && MAIN_APP
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
            #endif
        }
        .onDisappear {
            self.stonePlacingPlayer = nil
            selectedChatItem = nil
        }
        .onChange(of: analyzeMode.wrappedValue) { _, newValue in
            if newValue {
                selectedChatItem = nil
                if analyticsPosition == nil {
                    analyticsPosition = game.currentPosition
                }
            } else if !newValue {
                analyticsPosition = nil
            }
        }
        .onChange(of: zenMode) { _, newValue in
            if newValue {
                selectedChatItem = nil
            }
        }
        .onChange(of: game.ID) { _, _ in
            selectedChatItem = nil
        }
        .onChange(of: game.conditionalMoveBranches.map(\.id)) {
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
    @Previewable @State var compactDisplayMode =
        SingleGameView.DisplayMode.playerInfo
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
            compactDisplayMode: $compactDisplayMode
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(ogs)
}

#Preview("Play — Analysis", traits: .fixedLayout(width: 390, height: 844)) {
    @Previewable @State var zenMode = false
    @Previewable @State var compactDisplayMode =
        SingleGameView.DisplayMode.analyze
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
            compactDisplayMode: $compactDisplayMode
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(ogs)
}

#Preview("Finished game — Chat", traits: .fixedLayout(width: 390, height: 844)) {
    @Previewable @State var zenMode = false
    @Previewable @State var compactDisplayMode =
        SingleGameView.DisplayMode.chat
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
            compactDisplayMode: $compactDisplayMode
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(ogs)
}

#Preview("Stone removal", traits: .fixedLayout(width: 390, height: 844)) {
    @Previewable @State var zenMode = false
    @Previewable @State var compactDisplayMode =
        SingleGameView.DisplayMode.playerInfo
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
            compactDisplayMode: $compactDisplayMode
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(ogs)
}

#Preview("Finished game — Score and playback", traits: .fixedLayout(width: 390, height: 844)) {
    @Previewable @State var zenMode = false
    @Previewable @State var compactDisplayMode =
        SingleGameView.DisplayMode.playerInfo
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
            compactDisplayMode: $compactDisplayMode
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(ogs)
}
#endif
