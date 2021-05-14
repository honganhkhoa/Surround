//
//  CorrespondenceGamesView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 8/26/20.
//

import SwiftUI
import Combine

struct SingleGameView: View {
    var compact: Bool
    var compactBoardSize: CGFloat = 0
    @ObservedObject var game: Game
    var reducedPlayerInfoVerticalPadding: Bool = false
    var goToNextGame: (() -> ())?
    var horizontal = false
    @Binding var zenMode: Bool
    
    @EnvironmentObject var ogs: OGSService
    @Environment(\.colorScheme) private var colorScheme
    @State var pendingMove: Move? = nil
    @State var pendingPosition: BoardPosition? = nil
    @State var stoneRemovalSelectedPoints = Set<[Int]>()
    @State var stoneRemovalOption = StoneRemovalOption.toggleGroup
    var attachedKeyboardVisible = false
    
    @State var compactDisplayMode = CompactDisplayMode.playerInfo
    var shouldHideActiveGamesCarousel: Binding<Bool> = .constant(false)
    @Setting(.showsBoardCoordinates) var showsBoardCoordinates: Bool

    @State var hoveredPosition: BoardPosition? = nil
    @State var hoveredVariation: Variation? = nil
    @State var hoveredCoordinates: [[Int]] = []
    
    @Namespace var animation
    
    enum CompactDisplayMode {
        case playerInfo
        case chat
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
            if let hoveredPosition = hoveredPosition {
                BoardView(
                    boardPosition: hoveredPosition,
                    variation: hoveredVariation,
                    showsCoordinate: showsBoardCoordinates && !(compact && attachedKeyboardVisible),
                    highlightCoordinates: hoveredCoordinates
                )
            }
        }
    }
    
    var userColor: StoneColor {
        return ogs.user?.id == game.blackId ? .black : .white
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
                Label("Player info", systemImage: "person.crop.square.fill.and.at.rectangle")
                    .labelStyle(IconOnlyLabelStyle())
                    .tag(CompactDisplayMode.playerInfo)
                Label("Chat", systemImage: "message")
                    .labelStyle(IconOnlyLabelStyle())
                    .tag(CompactDisplayMode.chat)
            }
            .pickerStyle(SegmentedPickerStyle())
            .fixedSize()
            .padding(.horizontal, 15)
            .padding(.vertical, 5)
            if game.chatUnreadCount > 0 {
                ZStack {
                    Circle().fill(Color(.systemRed))
                    Text(game.chatUnreadCount > 9 ? "9+" : "\(game.chatUnreadCount)")
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
    
    @ViewBuilder
    var compactPlayerInfoOrChat: some View {
        if compactDisplayMode == .playerInfo {
            ZStack(alignment: .topTrailing) {
                PlayersBannerView(
                    game: game,
                    topLeftPlayerColor: topLeftPlayerColor,
                    reducesVerticalPadding: reducedPlayerInfoVerticalPadding,
                    showsPlayersName: !game.isUserPlaying
                )
                compactDisplayModePicker
            }
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer().frame(width: 10)
                    HStack(spacing: 0) {
                        Stone(color: topLeftPlayerColor, shadowRadius: 2)
                            .frame(width: 20, height: 20)
                        Spacer().frame(width: 5)
                        InlineTimerView(
                            timeControl: game.gameData?.timeControl,
                            clock: game.clock,
                            player: topLeftPlayerColor,
                            pauseControl: game.pauseControl,
                            showsPauseReason: false
                        )
                    }
                    Spacer(minLength: 5)
                    Divider()
                    Spacer(minLength: 5)
                    HStack(spacing: 0) {
                        InlineTimerView(
                            timeControl: game.gameData?.timeControl,
                            clock: game.clock,
                            player: topLeftPlayerColor.opponentColor(),
                            pauseControl: game.pauseControl,
                            showsPauseReason: false
                        )
                        Spacer().frame(width: 5)
                        Stone(color: topLeftPlayerColor.opponentColor(), shadowRadius: 2)
                            .frame(width: 20, height: 20)
                    }
                    Spacer().frame(width: 10)
                    compactDisplayModePicker
                }
                .fixedSize(horizontal: false, vertical: true)
                ChatLog(game: game, hoveredPosition: $hoveredPosition, hoveredVariation: $hoveredVariation, hoveredCoordinates: $hoveredCoordinates)
            }
        }
    }
    
    var compactBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            compactPlayerInfoOrChat
            if !attachedKeyboardVisible {
                Spacer(minLength: 10).frame(maxHeight: 15)
                controlRow
                    .padding(.horizontal)
                Spacer(minLength: 10)
            }
            if attachedKeyboardVisible {
                HStack(alignment: .top) {
                    boardView.frame(width: compactBoardSize / 2, height: compactBoardSize / 2)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack {
                            (Text(game.blackName)
                                .font(.footnote).bold()
                                + Text(" [\(game.blackFormattedRank)]").font(.caption))
                                .minimumScaleFactor(0.5)

                            Stone(color: .black, shadowRadius: 2)
                                .frame(width: 20, height: 20)
                        }
                        Spacer().frame(height: 5)
                        HStack {
                            (Text(game.whiteName)
                                .font(.footnote).bold()
                                + Text(" [\(game.whiteFormattedRank)]").font(.caption))
                                .minimumScaleFactor(0.5)
                            Stone(color: .white, shadowRadius: 2)
                                .frame(width: 20, height: 20)
                        }
                        Spacer().frame(height: 15)
                        verticalControlRow
                    }
                    .padding()
                }
            } else {
                boardView.frame(width: compactBoardSize, height: compactBoardSize)
            }
            Spacer(minLength: 0)
        }
        .onChange(of: compactDisplayMode) { newValue in
            withAnimation {
                shouldHideActiveGamesCarousel.wrappedValue = newValue == .chat
            }
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
                        Spacer(minLength: 15).frame(maxHeight: 15)
                        controlRow
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
                            if horizontalPlayerInfoWidth < 350 {
                                verticalControlRow
                                    .padding(.bottom, -15)
                            } else {
                                controlRow
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
                    Text("\(captures) capture\(captures == 1 ? "" : "s")")
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
                    Text("\(captures) capture\(captures == 1 ? "" : "s")")
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
            Button(action: { withAnimation { zenMode = false } }) {
                Label("Exit Zen mode", systemImage: "arrow.down.forward.and.arrow.up.backward")
                    .labelStyle(IconOnlyLabelStyle())
            }
            .padding()
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
                    if horizontal {
                        regularHorizontalBody
                    } else {
                        regularVerticalBody
                    }
                }
            }
        }
        .onReceive(game.$currentPosition) { _ in
            self.pendingMove = nil
            self.pendingPosition = nil
            self.stoneRemovalSelectedPoints.removeAll()
        }
    }
}

struct GameDetailView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService

    @State var currentGame: Game?
    @State var activeGames: [Game] = []
    @State var activeGameByOGSID: [Int: Game] = [:]
    
    @State var showSettings = false
    @State var attachedKeyboardVisible = false
    @State var needsToHideActiveGameCarousel = false
    @State var zenMode = false
    
    var shouldShowActiveGamesCarousel: Bool {
        guard !zenMode else {
            return false
        }
        if let currentGame = currentGame {
            return currentGame.isUserPlaying && activeGames.count > 1
        } else {
            return false
        }
    }
    
    func updateDetailOfCurrentGameIfNecessary() {
        if let currentGame = currentGame {
            ogs.connect(to: currentGame, withChat: true)
            if currentGame.ogsRawData == nil {
                ogs.updateDetailsOfConnectedGame(game: currentGame)
            }
        }
    }
    
    func updateActiveGameList() {
        if let gameSpeed = currentGame?.gameData?.timeControl.speed {
            if gameSpeed == .correspondence {
                if Set(self.activeGames.map { $0.ogsID }) == Set(ogs.sortedActiveCorrespondenceGames.map { $0.ogsID }) {
                    return
                }
                self.activeGames = []
                for game in ogs.sortedActiveCorrespondenceGames {
                    self.activeGames.append(game)
                    if let ogsID = game.ogsID {
                        self.activeGameByOGSID[ogsID] = game
                    }
                }
            } else if gameSpeed == .live || gameSpeed == .blitz {
                if Set(self.activeGames.map { $0.ogsID }) == Set(ogs.liveGames.map { $0.ogsID }) {
                    return
                }
                self.activeGames = []
                for game in ogs.liveGames {
                    self.activeGames.append(game)
                    if let ogsID = game.ogsID {
                        self.activeGameByOGSID[ogsID] = game
                    }
                }
            }
        }
    }
        
    func goToNextGame() {
        if let currentIndex = activeGames.firstIndex(where: { game in game.ID == currentGame?.ID }) {
            for game in activeGames[currentIndex.advanced(by: 1)..<activeGames.endIndex] + activeGames[activeGames.startIndex..<currentIndex] {
                if game.clock?.currentPlayerId == ogs.user?.id {
                    withAnimation {
                        currentGame = game
                    }
                    break
                }
            }
        }
    }
    
    var compactBody: some View {
        GeometryReader { geometry -> AnyView in
//            print("Geometry \(geometry.size)")
            
            let boardSize: CGFloat = min(geometry.size.width, geometry.size.height)
            let controlRowHeight: CGFloat = NSString(string: "Ilp").boundingRect(with: geometry.size, attributes: [.font: UIFont.preferredFont(forTextStyle: .title2)], context: nil).size.height
            let usableHeight: CGFloat = geometry.size.height
            let playerInfoHeight: CGFloat = 64 + 64 - 10 + 15 * 2
            let spacing: CGFloat = 10.0
            let remainingHeight: CGFloat = usableHeight - boardSize - controlRowHeight - playerInfoHeight - (spacing * 2)
            let enoughRoomForCarousel = remainingHeight >= 140 || (remainingHeight + geometry.safeAreaInsets.bottom * 2 / 3 >= 140)
            let canShowActiveGamesCarousel = !self.needsToHideActiveGameCarousel && shouldShowActiveGamesCarousel && enoughRoomForCarousel
            let reducedPlayerInfoVerticalPadding = (canShowActiveGamesCarousel && remainingHeight <= 150) || remainingHeight < 0

            return AnyView(erasing: VStack(alignment: .leading) {
                if let currentGame = currentGame {
                    SingleGameView(
                        compact: true,
                        compactBoardSize: boardSize,
                        game: currentGame,
                        reducedPlayerInfoVerticalPadding: reducedPlayerInfoVerticalPadding,
                        goToNextGame: goToNextGame,
                        zenMode: $zenMode,
                        attachedKeyboardVisible: self.attachedKeyboardVisible,
                        shouldHideActiveGamesCarousel: self.$needsToHideActiveGameCarousel
                    )
                }
                if canShowActiveGamesCarousel {
                    ActiveGamesCarousel(currentGame: $currentGame, activeGames: activeGames, showsToggleButton: true)
                }
            })
        }
    }
    
    var regularBody: some View {
        GeometryReader { geometry -> AnyView in
            let showsActiveGamesCarousel = !attachedKeyboardVisible && shouldShowActiveGamesCarousel
            let horizontal = geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing + 100 > geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            print("Geometry \(horizontal) \(geometry.size) \(geometry.safeAreaInsets)")
            return AnyView(erasing: VStack(spacing: 0) {
                if showsActiveGamesCarousel {
                    ActiveGamesCarousel(currentGame: $currentGame, activeGames: activeGames)
                }
                if let currentGame = currentGame {
                    SingleGameView(
                        compact: false,
                        game: currentGame,
                        goToNextGame: goToNextGame,
                        horizontal: horizontal,
                        zenMode: $zenMode
                    )
                }
            })
        }
    }
    
    var body: some View {
        guard let currentGame = currentGame else {
            return AnyView(EmptyView())
        }
        
        var compactLayout = true
        #if os(iOS)
        compactLayout = horizontalSizeClass == .compact
        #endif
        let userColor: StoneColor = currentGame.blackId == ogs.user?.id ? .black : .white
        let players = currentGame.gameData!.players
        let opponent = userColor == .black ? players.white : players.black
        let opponentRank = userColor == .black ? currentGame.whiteFormattedRank : currentGame.blackFormattedRank

        let result = Group {
            if compactLayout {
                compactBody
            } else {
                regularBody
            }
        }
        .background(
            colorScheme == .dark ?
                Color(UIColor.systemGray5).edgesIgnoringSafeArea(.bottom) :
                Color.white.edgesIgnoringSafeArea(.bottom)
        )
        .sheet(isPresented: self.$showSettings) {
            NavigationView {
                VStack {
                    GameplaySettings()
                    Spacer()
                }
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: { self.showSettings = false }) {
                            Text("Done").bold()
                        }
                    }
                }
            }
        }
        .navigationBarHidden(attachedKeyboardVisible || zenMode)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(currentGame.isUserPlaying ? "vs \(opponent.username) [\(opponentRank)]" : currentGame.gameName ?? "")
        .onAppear {
            if currentGame.gameData?.timeControl.speed == .live || currentGame.gameData?.timeControl.speed == .blitz {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            updateActiveGameList()
            DispatchQueue.main.async {
                self.updateDetailOfCurrentGameIfNecessary()
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: currentGame) { [currentGame] newGame in
            if newGame.ID != currentGame.ID {
                DispatchQueue.main.async {
                    self.updateDetailOfCurrentGameIfNecessary()
                }
            }
        }
        .onReceive(ogs.$sortedActiveCorrespondenceGames) { _ in
            DispatchQueue.main.async {
                updateActiveGameList()
            }
        }
        .onReceive(ogs.$liveGames) { _ in
            DispatchQueue.main.async {
                updateActiveGameList()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                let screenBounds = UIScreen.main.bounds
                self.attachedKeyboardVisible = !keyboardFrame.isEmpty &&
                    screenBounds.maxX == keyboardFrame.maxX &&
                    screenBounds.maxY == keyboardFrame.maxY &&
                    screenBounds.width == keyboardFrame.width
            }
        }
        
        if compactLayout {
            return AnyView(
                result.toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        HStack {
                            Button(action: { withAnimation { zenMode = true } }) {
                                Label("Zen mode", systemImage: "arrow.up.backward.and.arrow.down.forward")
                            }
                            Button(action: { self.showSettings = true }) {
                                Label("Options", systemImage: "gearshape.2")
                            }
                        }
                    }
                }
            )
        } else {
            return AnyView(
                result.toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            withAnimation {
                                Setting(.showsActiveGamesCarousel).binding.wrappedValue.toggle()
                            }
                        }) {
                            Label("Toggle thumbnails", systemImage: "rectangle.topthird.inset")
                                .labelStyle(IconOnlyLabelStyle())
                        }
                        .disabled(!shouldShowActiveGamesCarousel)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { withAnimation { zenMode = true } }) {
                            Label("Zen mode", systemImage: "arrow.up.backward.and.arrow.down.forward")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { self.showSettings = true }) {
                            Label("Options", systemImage: "gearshape.2")
                        }
                    }
                }
            )
        }
    }
}

struct GameDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let games = [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2, TestData.Ongoing19x19wBot3]
        let ogs = OGSService.previewInstance(
            user: OGSUser(username: "kata-bot", id: 592684),
            activeGames: games
        )
        for game in games {
            game.ogs = ogs
            game.chatUnreadCount = 2
        }

        return Group {
            NavigationView {
                GameDetailView(currentGame: games[0], activeGames: games, zenMode: true)
            }
            .previewDevice("iPhone 12 Pro")
//            .colorScheme(.dark)

            NavigationView {
                GameDetailView(currentGame: games[0], activeGames: games)
            }
            .previewDevice("iPhone 12 Pro")

            GameDetailView(currentGame: games[0], zenMode: true)
                .previewLayout(.fixed(width: 960, height: 754))
                .environment(\.horizontalSizeClass, UserInterfaceSizeClass.regular)

            GameDetailView(currentGame: games[0])
                .previewLayout(.fixed(width: 750, height: 1024))
                .environment(\.horizontalSizeClass, UserInterfaceSizeClass.regular)
        }
        .environmentObject(ogs)
        .environmentObject(NavigationService.shared)
    }
}
