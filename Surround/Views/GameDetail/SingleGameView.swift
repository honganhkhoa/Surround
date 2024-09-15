//
//  SingleGameView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 30/05/2021.
//

import SwiftUI
import AVFAudio

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
    
    @State var compactDisplayMode = DisplayMode.playerInfo
    @State var showCompactModeSwitcher = true
    var analyzeMode: Binding<Bool> = .constant(false)
    var shouldHideActiveGamesCarousel: Binding<Bool> = .constant(false)
    @Setting(.showsBoardCoordinates) var showsBoardCoordinates: Bool
    @Setting(.soundOnStonePlacement) var soundOnStonePlacement: Bool

    @State var hoveredPosition: BoardPosition? = nil
    @State var hoveredVariation: Variation? = nil
    @State var hoveredCoordinates: [[Int]] = []
    
    @State var analyticsPosition: BoardPosition?
    
    @State var analyticsPendingMove: Move? = nil
    @State var analyticsPendingPosition: BoardPosition? = nil
    
    @State var stonePlacingPlayer: AVAudioPlayer? = nil
    
    @Namespace var animation
    
    enum DisplayMode {
        case playerInfo
        case chat
        case analyze
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
        ZStack {
            if let hoveredPosition = hoveredPosition {
                BoardView(
                    boardPosition: hoveredPosition,
                    variation: hoveredVariation,
                    showsCoordinate: showsBoardCoordinates && !(compact && attachedKeyboardVisible),
                    highlightCoordinates: hoveredCoordinates
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
                .onChange(of: analyticsPendingMove) { newMove in
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
                    highlightCoordinates: hoveredCoordinates
                )
            }
        }
    }
    
    var userColor: StoneColor {
        return game.userStoneColor ?? .white
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
            ChatLog(game: game, hoveredPosition: $hoveredPosition, hoveredVariation: $hoveredVariation, hoveredCoordinates: $hoveredCoordinates).zIndex(-1)
        }
    }

    var analyzeTree: some View {
        VStack(spacing: 0) {
            compactClockHeader
            AnalyzeTreeView(game: game, selectedPosition: $analyticsPosition)
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
            if !attachedKeyboardVisible && compactDisplayMode != .analyze {
                Spacer(minLength: 10).frame(maxHeight: 15)
                controlRow
                    .padding(.horizontal)
                Spacer(minLength: 10)
            }
            if attachedKeyboardVisible && UIScreen.main.bounds.size.height < 600 {
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
            Spacer(minLength: 0)
        }
        .onChange(of: compactDisplayMode) { newValue in
            withAnimation {
                shouldHideActiveGamesCarousel.wrappedValue = newValue != .playerInfo
                if newValue == .analyze {
                    analyticsPosition = game.currentPosition
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
                    ChatLog(game: game, hoveredPosition: $hoveredPosition, hoveredVariation: $hoveredVariation, hoveredCoordinates: $hoveredCoordinates)
                        .frame(height: chatHeight)
                    Spacer(minLength: 15)
                    VStack {
                        PlayersBannerView(
                            game: game,
                            topLeftPlayerColor: topLeftPlayerColor,
                            playerIconSize: 80,
                            playerIconsOffset: 25,
                            showsPlayersName: true
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
                            showsPlayersName: true
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
                                    showsPlayersName: true
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
                            ChatLog(game: game, hoveredPosition: $hoveredPosition, hoveredVariation: $hoveredVariation, hoveredCoordinates: $hoveredCoordinates)
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
                            AnalyzeTreeView(game: game, selectedPosition: $analyticsPosition)
                                .frame(maxHeight: UIScreen.main.bounds.size.height / 3.7)
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
        }
        .onDisappear {
            self.stonePlacingPlayer = nil
        }
        .onChange(of: analyzeMode.wrappedValue) { newValue in
            if newValue {
                analyticsPosition = game.currentPosition
            }
        }
    }
}

struct SingleGameView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationView {
                SingleGameView(
                    compact: true,
                    compactBoardSize: 390,
                    game: TestData.Ongoing19x19wBot3,
                    zenMode: .constant(false),
                    compactDisplayMode: .analyze
                )
                .navigationBarTitleDisplayMode(.inline)
            }
            .previewDevice("iPhone 12 Pro")
//            NavigationView {
//                SingleGameView(
//                    compact: true,
//                    compactBoardSize: 390,
//                    game: TestData.Ongoing19x19wBot3,
//                    zenMode: .constant(false)
//                )
//                .navigationBarTitleDisplayMode(.inline)
//            }
//            .previewDevice("iPhone 12 Pro")
            NavigationView {
                SingleGameView(
                    compact: true,
                    compactBoardSize: 390,
                    game: TestData.EuropeanChampionshipWithChat,
                    zenMode: .constant(false),
                    compactDisplayMode: .chat
                )
                .navigationBarTitleDisplayMode(.inline)
            }
            .previewDevice("iPhone 12 Pro")
        }
        .environmentObject(OGSService.previewInstance())
    }
}
