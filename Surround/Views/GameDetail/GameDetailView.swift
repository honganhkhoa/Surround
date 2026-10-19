//
//  CorrespondenceGamesView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 8/26/20.
//

import SwiftUI
import Combine

struct GameDetailView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isVerticalToolbar) private var isVerticalToolbar
    @Environment(\.owningStackRoute) private var owningStackRoute
    @Environment(\.duoTabContext) private var duoTabContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.openPlayerProfile) private var openPlayerProfile
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService

    @Binding var currentGame: Game?
    @State var activeGames: [Game] = []
    @State var activeGameByOGSID: [Int: Game] = [:]
    @State private var detailConnection = GameDetailConnectionCoordinator()

    /// Finished-game history routes do not offer the active-game picker.
    var allowsActiveGamesCarousel = true
    
    @State var showSettings = false
    @State private var showsActiveGames = false
    @State private var contentWidth: CGFloat = 0
    @State private var notificationContextID = UUID()
    @State private var showsClocksInHeader = false
    @State private var showsCurrentPlayerClockInHeader = false
    @State private var showsOpponentInHeader = false
    @State var attachedKeyboardVisible = false
    @State private var keyboardScreenFrame: CGRect?
    @State private var windowGeometry: GameDetailWindowGeometry?
    @State private var hasDisplayDivision = false
    /// Zen turns the vertical toolbar off in compact landscape (iPhone and Duo
    /// Closed alike), so remember whether this pose uses it outside Zen: Duo
    /// Closed landscape's Zen keeps the single column (canvas v146).
    @State private var verticalToolbarOutsideZen = false
    @State private var hasActiveVerticalDisplayDivision = false
    @State var zenMode = false
    @State var interaction = GameDetailInteraction()
    @State private var showsCompactChatBoard = true
    @State private var variationShareDraft: VariationShareDraft?
    @State private var selectedChatChannel = OGSChatSendChannel.main
    @StateObject private var chatSession = ChatSessionState()
    @StateObject private var gameControlState = GameControlState()
    @State private var selectedConditionalVariation: ConditionalMoveBranch?
    @Setting(.hidesRank) private var hidesRank: Bool
    @EnvironmentObject private var stackRouter: StackRouter
    #if DEBUG && MAIN_APP
    @State private var animationObservationID = UUID()
    #endif

    private var onTurnActiveGameCount: Int {
        activeGames.filter(ogs.isOnUserTurn).count
    }

    private var activeGamesButton: some View {
        Button {
            showsActiveGames = true
        } label: {
            Label("Active games", systemImage: "square.grid.2x2")
                .modifier(GameToolbarMinimumTouchTarget())
        }
        .accessibilityValue(Text(verbatim: String(onTurnActiveGameCount)))
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.gameActiveGamesButton
        )
        .popover(isPresented: $showsActiveGames) {
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    if currentGame?.gameData?.timeControl.speed?.isRealtime == true {
                        Text("Live games")
                    } else {
                        Text("Correspondence games")
                    }
                }
                .font(.headline)
                .padding(.horizontal)
                ActiveGamesCarousel(
                    currentGame: $currentGame,
                    activeGames: activeGames,
                    onSelectGame: { showsActiveGames = false }
                )
            }
            .padding(.vertical)
            .frame(idealWidth: 420)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(
                SurroundUITestContract.AccessibilityID.gameActiveGamesPopover
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var effectiveAttachedKeyboardVisible: Bool {
        let measuredVisibility = keyboardScreenFrame.flatMap { keyboard in
            windowGeometry.map { geometry in
                geometry.hasAttachedKeyboard(keyboard)
            }
        } ?? attachedKeyboardVisible
        #if DEBUG && MAIN_APP
        return measuredVisibility
            || SurroundUITestContract
                .simulatesAttachedSoftwareKeyboardVisible
        #else
        return measuredVisibility
        #endif
    }

    private var keyboardVisibilityNotifications: AnyPublisher<Notification, Never> {
        #if targetEnvironment(macCatalyst)
        return Empty(completeImmediately: false).eraseToAnyPublisher()
        #else
        return Publishers.MergeMany([
            UIResponder.keyboardWillChangeFrameNotification,
            UIResponder.keyboardDidChangeFrameNotification,
            UIResponder.keyboardWillHideNotification,
            UIResponder.keyboardDidHideNotification,
        ].map { NotificationCenter.default.publisher(for: $0) })
            .eraseToAnyPublisher()
        #endif
    }

    private func clearKeyboardVisibility() {
        keyboardScreenFrame = nil
        attachedKeyboardVisible = false
    }

    private func updateKeyboardVisibility(from notification: Notification) {
        // Retained destinations and other app windows must not acquire this
        // screen's keyboard layout from a process-wide notification.
        guard nav.gameDetailNotificationContexts[notificationContextID] != nil,
              notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool != false,
              let window = windowGeometry?.owningWindow else { return }
        if let screen = notification.object as? UIScreen, screen !== window.screen { return }

        if notification.name == UIResponder.keyboardWillHideNotification
            || notification.name == UIResponder.keyboardDidHideNotification {
            // Losing key-window status can precede the hide notification.
            // Clear the previous owner's layout even during that handoff.
            clearKeyboardVisibility()
        } else {
            guard window.isKeyWindow else { return }
            keyboardScreenFrame = notification.userInfo?[
                UIResponder.keyboardFrameEndUserInfoKey
            ] as? CGRect
            attachedKeyboardVisible = keyboardScreenFrame.map {
                windowGeometry?.hasAttachedKeyboard($0) == true
            } ?? false
        }
        #if DEBUG && MAIN_APP
        SurroundAnimationDiagnostics.record(
            "keyboard.attachedClassification", ownerID: animationObservationID,
            focusRequestID: variationShareDraft?.focusRequestID,
            fields: ["attached": String(attachedKeyboardVisible),
                     "notification": notification.name.rawValue],
            deduplicated: true
        )
        #endif
    }

    private func keyboardOverlap() -> CGFloat {
        // Every layout keeps its unoccluded frame. Only the conversation
        // avoids an attached keyboard; the board remains behind it.
        guard effectiveAttachedKeyboardVisible,
              let keyboardScreenFrame, let windowGeometry else { return 0 }
        return windowGeometry.keyboardOverlap(keyboardScreenFrame)
    }

    var canShowActiveGames: Bool {
        guard allowsActiveGamesCarousel else {
            return false
        }
        guard !zenMode else {
            return false
        }
        if let currentGame = currentGame {
            return currentGame.isUserPlaying && !activeGames.isEmpty
        } else {
            return false
        }
    }

    private var compactLandscape: Bool {
        guard compactLayout, let size = windowGeometry?.windowSize else { return false }
        return size.width > size.height
    }

    private var openLandscape: Bool {
        guard hasDisplayDivision, !hasActiveVerticalDisplayDivision,
              let size = windowGeometry?.windowSize else { return false }
        return size.width > size.height
    }

    private var prefersHorizontalZenToolbar: Bool {
        zenMode && (compactLandscape || hasActiveVerticalDisplayDivision || openLandscape)
    }

    /// Duo wide poses (Book and Open). The navigation bar would hold only the
    /// system sidebar toggle, and claim every touch across its full-width
    /// band; Back and the game controls live in the separate vertical toolbar.
    /// The game hides the bar and draws its own sidebar button instead.
    /// Decided from the pose alone, never from the toolbar it changes.
    private var hidesNavigationBarInDuoWide: Bool {
        guard !zenMode, hasDisplayDivision,
              let size = windowGeometry?.windowSize else { return false }
        return size.width > size.height
    }

    /// Zen keeps only Exit: on iPad, whose navigation bar carries the sidebar
    /// toggle iPadOS adds once the tab bar hides (no API removes it alone),
    /// and on Duo Open wide, whose tray would otherwise sit over the board.
    /// Duo Book wide keeps its tray.
    private var hidesZenChrome: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        return zenMode && (UIDevice.current.userInterfaceIdiom == .pad || openLandscape)
        #else
        return false
        #endif
    }

    /// Where Duo's wide poses draw our own chrome (the sidebar button, Exit
    /// Zen): in the band the navigation bar's items used, 24 pt from the
    /// window's top, in the game content's coordinates.
    private var chromeBandTop: CGFloat? {
        guard hidesNavigationBarInDuoWide || (hidesZenChrome && openLandscape),
              let windowGeometry else { return nil }
        let contentTop = windowGeometry.contentFrame.minY - windowGeometry.windowFrame.minY
        return max(0, max(24, windowGeometry.windowSafeAreaTop) - contentTop)
    }

    @ViewBuilder private var zenExitOverlay: some View {
        if hidesZenChrome {
            Button(action: exitZenMode) {
                Label("Exit Zen mode", systemImage: "arrow.down.forward.and.arrow.up.backward")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modifier(GameChromeButtonSurface())
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameZenExit)
            .surroundUITestZenShortcut()
            .padding(.top, chromeBandTop ?? 16)
            .padding(.trailing, regularLandscape || chromeBandTop != nil ? 16 : 24)
        }
    }

    /// The system toggle leaves with the hidden navigation bar; this one
    /// takes its place and drives the same native sidebar.
    @ViewBuilder private var duoSidebarButton: some View {
        if hidesNavigationBarInDuoWide, let duoTabContext, duoTabContext.sidebarAvailable,
           let chromeBandTop {
            Button { duoTabContext.toggleSidebar() } label: {
                Label("Toggle sidebar", systemImage: "sidebar.left")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modifier(GameChromeButtonSurface())
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameSidebarToggle)
            .padding(.leading, 16)
            .padding(.top, chromeBandTop + 8)
        }
    }

    /// Width of Duo's vertical bar when it sits at the trailing edge: the
    /// trailing safe-area inset it adds.
    private func trailingVerticalBarWidth(in geometry: GeometryProxy) -> CGFloat? {
        let width = geometry.safeAreaInsets.trailing
        return width >= 60 ? width : nil
    }

    /// Hiding the navigation bar also removes the system Back from the top of
    /// the vertical bar; toolbar items can only take its lower group. The game
    /// draws Back where the system put it: on the bar's centre line, 48 pt in
    /// from the window edge, centred at y 144 below the vertical status bar.
    /// The overlay is trailing-aligned, but an offset is physical: it moves
    /// toward the trailing edge, which is on the left in right-to-left layouts.
    @ViewBuilder private func duoBackButton(in geometry: GeometryProxy) -> some View {
        if hidesNavigationBarInDuoWide, let barWidth = trailingVerticalBarWidth(in: geometry) {
            Button { dismiss() } label: {
                Label("Back", systemImage: "chevron.backward")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modifier(GameChromeButtonSurface())
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameBack)
            .padding(.top, max(0, 144 - 22 - geometry.frame(in: .global).minY))
            // Out of the content into the bar's inset (negative padding wider
            // than the button would collapse its frame instead).
            .offset(x: (barWidth - 48 + 22) * (layoutDirection == .rightToLeft ? -1 : 1))
        }
    }

    private var extendsContentToBottomEdge: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        return GameDetailBottomEdgePolicy.extendsContent(
            isPhone: UIDevice.current.userInterfaceIdiom == .phone,
            compact: compactLayout,
            windowSize: windowGeometry?.windowSize,
            hasDisplayDivision: hasDisplayDivision,
            keyboardVisible: false
        )
        #else
        return false
        #endif
    }

    private var hidesHomeIndicator: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        return GameDetailBottomEdgePolicy.extendsContent(
            isPhone: UIDevice.current.userInterfaceIdiom == .phone,
            compact: compactLayout,
            windowSize: windowGeometry?.windowSize,
            hasDisplayDivision: hasDisplayDivision,
            keyboardVisible: false
        )
        #else
        return false
        #endif
    }

    private var extendedContentEdges: Edge.Set {
        var edges: Edge.Set = extendsContentToBottomEdge ? .bottom : []
        // Landscape Zen's board occupies the center column, clear of the
        // native exit control. The sidebar overlays that same geometry.
        // Toolbars retain their own safe-area placement; regular layouts keep
        // the bottom home-indicator inset.
        // Open Duo's horizontal system status tray places Exit over the
        // board's upper-right edge when the top safe area is reclaimed.
        // Keep that native reservation while still returning the side rail.
        if zenMode && (compactLandscape || regularLandscape) && !openLandscape
            && !isVerticalToolbar && !hasActiveVerticalDisplayDivision
            && !effectiveAttachedKeyboardVisible {
            edges.insert(.top)
        }
        // Without its tray, Open wide Zen measures from the window's top.
        if hidesZenChrome && openLandscape { edges.insert(.top) }
        return edges
    }

    private var regularLandscape: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard UIDevice.current.userInterfaceIdiom == .pad, !compactLayout,
              let size = windowGeometry?.contentFrame.size else { return false }
        return size.width > size.height
        #else
        return false
        #endif
    }

    private func hasDisplayDivision(in geometry: GeometryProxy) -> Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            // Test visibility against the owning window rather than the safe
            // content height, so extending the bottom cannot change the pose.
            let bounds: CGRect
            if let windowGeometry {
                bounds = CGRect(
                    x: windowGeometry.windowFrame.minX - windowGeometry.contentFrame.minX,
                    y: windowGeometry.windowFrame.minY - windowGeometry.contentFrame.minY,
                    width: windowGeometry.windowSize.width,
                    height: windowGeometry.windowSize.height
                )
            } else {
                bounds = CGRect(origin: .zero, size: geometry.size)
            }
            return geometry.reservedRegions(kind: .division, options: .includeInactive)
                .contains { $0.frame.intersects(bounds) }
        }
        #endif
        return false
    }

    private func hasActiveVerticalDisplayDivision(in geometry: GeometryProxy) -> Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            return geometry.reservedRegions(kind: .division)
                .contains { $0.isActive && $0.frame.height > $0.frame.width }
        }
        #endif
        return false
    }

    private var placesActiveGamesAtTop: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        !isVerticalToolbar && (UIDevice.current.userInterfaceIdiom == .pad
            || !compactLayout || compactLandscape)
        #else
        true
        #endif
    }
    
    func updateDetailOfCurrentGameIfNecessary() {
        guard let requestedGame = currentGame, requestedGame.ogsID != nil else {
            detailConnection.release()
            return
        }

        let gameBinding = $currentGame
        detailConnection.observeLifetime(in: stackRouter, route: owningStackRoute) { [weak service = ogs] canonicalGame in
            guard gameBinding.wrappedValue?.ID == canonicalGame.ID else { return }
            if gameBinding.wrappedValue !== canonicalGame {
                gameBinding.wrappedValue = canonicalGame
            }
            if canonicalGame.ogsRawData == nil {
                service?.updateDetailsOfConnectedGame(game: canonicalGame)
            }
        }
        let canonicalGame = detailConnection.connect(to: requestedGame, using: ogs)
        if canonicalGame !== requestedGame {
            currentGame = canonicalGame
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
            } else if gameSpeed.isRealtime {
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
        let candidates: [Game]
        if let currentIndex = activeGames.firstIndex(where: {
            $0.ID == currentGame?.ID
        }) {
            candidates = Array(activeGames.dropFirst(currentIndex + 1))
                + Array(activeGames.prefix(currentIndex))
        } else {
            candidates = activeGames
        }

        if let nextGame = candidates.first(where: ogs.isOnUserTurn) {
            withAnimation {
                currentGame = nextGame
            }
        }
    }
    
    func enterZenMode() {
        showsActiveGames = false
        withAnimation {
            zenMode = true
        }
    }
    
    func exitZenMode() {
        withAnimation {
            zenMode = false
        }
    }
    
    private func gameBody(compact: Bool, geometry: GeometryProxy) -> some View {
        let availableWidth = geometry.size.width
            + geometry.safeAreaInsets.leading
            + geometry.safeAreaInsets.trailing
        // Window pose is independent of keyboard visibility and its overlay.
        let unoccludedHeight = windowGeometry?.windowSize.height
            ?? geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
        let horizontal = windowGeometry.map { $0.windowSize.width > $0.windowSize.height }
            ?? (availableWidth > unoccludedHeight)

        return VStack(alignment: .leading, spacing: compact ? nil : 0) {
            // Keep this view in one structural slot as the size class changes,
            // so folding preserves analysis and pending board moves.
            if let currentGame {
                SingleGameView(
                    compact: compact,
                    game: currentGame,
                    goToNextGame: goToNextGame,
                    horizontal: horizontal,
                    zenMode: $zenMode,
                    zenBoardCenterY: windowGeometry.map { $0.windowFrame.midY - $0.contentFrame.minY },
                    chromeBandTop: chromeBandTop,
                    // Only compact landscape (Duo Closed landscape) keeps the
                    // remembered toolbar pose in Zen. Book and Open wide also
                    // use the vertical toolbar outside Zen, but their Zen has
                    // its own layouts (ZenDuoBookWide, ZenDuoOpenWide).
                    verticalToolbarPose: isVerticalToolbar
                        || (zenMode && compactLandscape && verticalToolbarOutsideZen),
                    attachedKeyboardVisible: effectiveAttachedKeyboardVisible,
                    keyboardOverlap: keyboardOverlap(),
                    interaction: $interaction,
                    chatSession: chatSession,
                    gameControlState: gameControlState,
                    selectedConditionalVariation: $selectedConditionalVariation,
                    showsCompactChatBoard: $showsCompactChatBoard,
                    variationShareDraft: $variationShareDraft,
                    selectedChatChannel: $selectedChatChannel
                )
            }
        }
    }

    private var compactLayout: Bool {
        var compactLayout = true
        #if os(iOS)
        compactLayout = horizontalSizeClass == .compact
        #endif
        #if DEBUG && MAIN_APP
        if SurroundUITestContract.forcesCompactGameLayout {
            compactLayout = true
        }
        #endif
        if contentWidth > 0 && contentWidth < 600 {
            compactLayout = true
        }
        return compactLayout
    }

    private var navigationBarHidden: Bool {
        zenMode
    }

    var body: some View {
        GeometryReader { geometry in
            content(geometry: geometry)
                .background {
                    GameDetailWindowGeometryReader(
                        layoutFrame: geometry.frame(in: .global),
                        beginSizeTransition: {
                            guard let token = chatSession.beginWindowSizeTransition() else { return nil }
                            #if DEBUG && MAIN_APP
                            SurroundAnimationDiagnostics.record(
                                "composer.windowTransitionBegan", ownerID: animationObservationID,
                                fields: ["focusRevision": String(chatSession.focusRevision)]
                            )
                            #endif
                            return { allowsRestoration in
                                chatSession.completeWindowSizeTransition(token, allowsRestoration: allowsRestoration)
                                #if DEBUG && MAIN_APP
                                SurroundAnimationDiagnostics.record(
                                    "composer.windowTransitionCompleted", ownerID: animationObservationID,
                                    fields: ["wantsFocus": String(chatSession.wantsInputFocus),
                                             "restorationRevision": String(chatSession.focusRestorationRevision)]
                                )
                                #endif
                            }
                        }
                    ) { newGeometry in
                        if windowGeometry != newGeometry {
                            windowGeometry = newGeometry
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            contentWidth = width
        }
        .onChange(of: isVerticalToolbar, initial: true) { _, vertical in
            if !zenMode { verticalToolbarOutsideZen = vertical }
        }
        .onGeometryChange(for: Bool.self) { hasDisplayDivision(in: $0) } action: { hasDivision in
            hasDisplayDivision = hasDivision
        }
        .onGeometryChange(for: Bool.self) { hasActiveVerticalDisplayDivision(in: $0) } action: { hasDivision in
            hasActiveVerticalDisplayDivision = hasDivision
        }
        .onPreferenceChange(GameDetailOpponentHeaderPreferenceKey.self) { showsOpponentInHeader = $0 }
        .onPreferenceChange(GameDetailClocksInHeaderPreferenceKey.self) { showsClocksInHeader = $0 }
        .onPreferenceChange(GameDetailCurrentPlayerClockInHeaderPreferenceKey.self) {
            showsCurrentPlayerClockInHeader = $0
        }
        // Deferral changes gesture priority, while container expansion gives
        // the board and panels the bottom inset. Under a keyboard that inset
        // is reported as keyboard space, so it is ignored too: typing keeps
        // the scene's height. Camera, side-toolbar and fold regions stay intact.
        .ignoresSafeArea(extendsContentToBottomEdge ? [.container, .keyboard] : .container,
                         edges: extendedContentEdges)
        #if os(iOS) && !targetEnvironment(macCatalyst)
        .defersSystemGestures(on: extendsContentToBottomEdge && !effectiveAttachedKeyboardVisible ? .bottom : [])
        .persistentSystemOverlays(hidesHomeIndicator ? .hidden : .automatic)
        #endif
        .modifier(GameToolbarOrientation(prefersHorizontal: prefersHorizontalZenToolbar))
        .statusBarHidden(hidesZenChrome)
        // Typing never changes the scene's geometry. The conversation places
        // its composer above the keyboard using the owning window's overlap.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func content(geometry: GeometryProxy) -> some View {
        guard let currentGame = self.currentGame else {
            return AnyView(EmptyView())
        }
        let viewingOwnLiveGame = allowsActiveGamesCarousel
            && currentGame.gamePhase != .finished
            && currentGame.isUserPlaying
            && currentGame.gameData?.timeControl.speed?.isRealtime == true

        let showsActiveGamesButton = canShowActiveGames
        var title = currentGame.gameName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        if currentGame.isUserPlaying,
           let userColor = currentGame.userStoneColor,
           let opponent = currentGame.currentPlayer(with: userColor.opponentColor()) {
            title = "vs \(opponent.usernameAndRank(hidesRank: hidesRank))"
            if currentGame.rengo {
                if let opponentTeam = currentGame.gameData?.rengoTeams?[userColor.opponentColor()] {
                    if opponentTeam.count > 1 {
                        title += " +\(opponentTeam.count - 1)"
                    }
                }
            }
        }
        if currentGame.gamePhase == .stoneRemoval {
            title = String(localized: "Stone removal")
        } else if currentGame.gamePhase == .finished {
            title = String(localized: "Game over")
        }
        #if targetEnvironment(macCatalyst)
        let navigationTitle = title.isEmpty
            ? String(
                localized: "Game",
                comment: "Fallback game window title"
            )
            : title
        #else
        // The app's connection banner sits in the title slot; the title gives
        // way while it shows (canvas "Reconnecting in stone removal · iPhone").
        let showsTitle = !zenMode && !isVerticalToolbar && !showsOpponentInHeader
            && !showsClocksInHeader && !nav.connectionBannerVisible
            && (compactLayout || UIDevice.current.userInterfaceIdiom == .phone)
        let navigationTitle = showsTitle ? title : ""
        #endif
        
        let result = gameBody(compact: compactLayout, geometry: geometry)
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        .onChange(of: showsActiveGamesButton) { _, isVisible in
            if !isVisible { showsActiveGames = false }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.gameDetail(currentGame)
        )
        .background(GameDetailAppearance.background.ignoresSafeArea(.container))
        .overlay(alignment: .topTrailing) { zenExitOverlay }
        .overlay(alignment: .topLeading) { duoSidebarButton }
        .overlay(alignment: .topTrailing) { duoBackButton(in: geometry) }
        .sheet(isPresented: self.$showSettings) {
            AppNavigationStack {
                VStack {
                    GameplaySettings()
                    Spacer()
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(
                    SurroundUITestContract.compatibilityScene == .gameOptions
                        ? SurroundUITestContract.AccessibilityID
                            .compatibilityScreen(.gameOptions)
                        : SurroundUITestContract.AccessibilityID
                            .screenGameOptions
                )
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: { self.showSettings = false }) {
                            Text("Done", comment: "close button for in-game settings").bold()
                        }
                    }
                }
            }
        }
        // Catalyst keeps this useful as the Mac window title in Zen mode.
        .navigationTitle(navigationTitle)
        .navigationBarHidden(hidesZenChrome || hidesNavigationBarInDuoWide)
        .navigationBarBackButtonHidden(navigationBarHidden)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            nav.gameDetailNotificationContexts[notificationContextID] = viewingOwnLiveGame
            updateActiveGameList()
            updateDetailOfCurrentGameIfNecessary()
        }
        .onChange(of: viewingOwnLiveGame) { _, isViewingOwnLiveGame in
            // A retained navigation destination can receive game updates
            // after disappearing. Only its visible registration owns notices.
            guard nav.gameDetailNotificationContexts[notificationContextID] != nil else { return }
            nav.gameDetailNotificationContexts[notificationContextID] = isViewingOwnLiveGame
        }
        .onDisappear {
            nav.gameDetailNotificationContexts.removeValue(forKey: notificationContextID)
            clearKeyboardVisibility()
        }
        .onChange(of: currentGame) { oldGame, newGame in
            if newGame.ID != oldGame.ID {
                selectedConditionalVariation = nil
                showSettings = false
                showsActiveGames = false
                if GameDetailDisplayReset.restoresDisplayDefaults(
                    from: oldGame.gameData?.timeControl.speed,
                    to: newGame.gameData?.timeControl.speed
                ) {
                    zenMode = false
                    interaction.resetPanels()
                    showsCompactChatBoard = true
                }
                variationShareDraft = nil
                selectedChatChannel = .main
                updateActiveGameList()
                updateDetailOfCurrentGameIfNecessary()
            }
        }
        .onChange(of: ogs.user?.id) { _, _ in
            clearKeyboardVisibility()
            selectedConditionalVariation = nil
            zenMode = false
            interaction.resetPanels()
            showsCompactChatBoard = true
            showsActiveGames = false
            variationShareDraft = nil
            selectedChatChannel = .main
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
        .onReceive(keyboardVisibilityNotifications, perform: updateKeyboardVisibility)
        #if DEBUG && MAIN_APP
        .surroundAnimationObservation(
            "game.detail", ownerID: animationObservationID,
            focusRequestID: variationShareDraft?.focusRequestID
        )
        .surroundAnimationKeyboardObservations(ownerID: animationObservationID)
        .surroundAnimationState(
            "detail.visibilityState",
            value: "attachedKeyboard=\(effectiveAttachedKeyboardVisible);navigationHidden=\(navigationBarHidden);compact=\(compactLayout)",
            ownerID: animationObservationID,
            focusRequestID: variationShareDraft?.focusRequestID
        )
        #endif
        
        return AnyView(
            result.modifier(GameToolbarLayout(
                game: currentGame,
                gameControlState: gameControlState,
                selectedConditionalVariation: $selectedConditionalVariation,
                interaction: $interaction,
                showsCompactChatBoard: $showsCompactChatBoard,
                showSettings: $showSettings,
                compact: compactLayout,
                compactLandscape: compactLandscape,
                zenMode: zenMode,
                exitsZenFromContent: hidesZenChrome,
                navigationBarHidden: hidesNavigationBarInDuoWide,
                drawsBackInContent: hidesNavigationBarInDuoWide && trailingVerticalBarWidth(in: geometry) != nil,
                showsOpponentInHeader: showsOpponentInHeader,
                showsClocksInHeader: showsClocksInHeader,
                showsCurrentPlayerClockInHeader: showsCurrentPlayerClockInHeader,
                keyboardVisible: effectiveAttachedKeyboardVisible || chatSession.wantsInputFocus,
                softwareKeyboardVisible: effectiveAttachedKeyboardVisible,
                showsActiveGamesButton: showsActiveGamesButton,
                placesActiveGamesAtTop: placesActiveGamesAtTop,
                activeGamesButton: AnyView(activeGamesButton),
                dismissChatInput: chatSession.dismissInput,
                enterZenMode: enterZenMode,
                exitZenMode: exitZenMode,
                notificationContextID: notificationContextID
            ))
            // Games use the whole window; the native sidebar overlays it.
            .appTabBarHidden(true)
            // Content and toolbar items (header chips and their details, the
            // header identity) share one profile action: the chat hand-off
            // ends composer focus before the push, so UIKit cannot restore it.
            .environment(\.openPlayerProfile, openPlayerProfile.map { openProfile in
                { [chatSession] player in
                    chatSession.gamePresentationDisappeared()
                    openProfile(player)
                }
            })
            .environment(\.gameDetailNotificationContextID, notificationContextID)
        )
    }
}

private struct GameDetailWindowGeometry: Equatable {
    weak var owningWindow: UIWindow?
    let contentFrame: CGRect
    let windowFrame: CGRect
    let screenBounds: CGRect
    let windowSize: CGSize
    let windowSafeAreaTop: CGFloat
    func hasAttachedKeyboard(_ keyboard: CGRect) -> Bool {
        !keyboard.isEmpty && keyboard.height > 100
            && keyboard.minX <= screenBounds.minX + 1
            && keyboard.maxX >= screenBounds.maxX - 1
            && keyboard.maxY >= screenBounds.maxY - 1
            && !keyboard.intersection(windowFrame).isEmpty
            && !keyboard.intersection(windowFrame).isNull
    }

    func keyboardOverlap(_ keyboard: CGRect) -> CGFloat {
        let intersection = contentFrame.intersection(keyboard)
        guard !intersection.isNull, !intersection.isEmpty,
              keyboard.maxY >= contentFrame.maxY - 1 else { return 0 }
        return min(contentFrame.height, intersection.height)
    }
}

/// A narrow UIKit bridge supplies the owning window's coordinate conversion.
/// Keyboard notifications are in screen coordinates; SwiftUI's global frame
/// alone cannot account for an offset Stage Manager or secondary app window.
private struct GameDetailWindowGeometryReader: UIViewControllerRepresentable {
    let layoutFrame: CGRect
    let beginSizeTransition: () -> ((Bool) -> Void)?
    let onChange: (GameDetailWindowGeometry) -> Void

    func makeUIViewController(context: Context) -> GeometryController {
        let controller = GeometryController()
        controller.geometryView.onChange = onChange
        controller.beginSizeTransition = beginSizeTransition
        return controller
    }

    func updateUIViewController(_ controller: GeometryController, context: Context) {
        controller.geometryView.onChange = onChange
        controller.beginSizeTransition = beginSizeTransition
        controller.geometryView.reportGeometry()
    }

    final class GeometryController: UIViewController {
        let geometryView = GeometryView()
        var beginSizeTransition: (() -> ((Bool) -> Void)?)?

        override func loadView() {
            geometryView.isUserInteractionEnabled = false
            view = geometryView
        }

        override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
            let completion = view.window?.isKeyWindow == true ? beginSizeTransition?() : nil
            super.viewWillTransition(to: size, with: coordinator)
            let finish = { [weak self] in
                // Let SwiftUI consume the final layout before restoring only
                // the still-valid focus intent captured by this window.
                DispatchQueue.main.async {
                    completion?(self?.view.window?.isKeyWindow == true)
                }
            }
            if !coordinator.animate(alongsideTransition: nil, completion: { _ in finish() }) {
                finish()
            }
        }
    }

    final class GeometryView: UIView {
        var onChange: ((GameDetailWindowGeometry) -> Void)?
        private var lastGeometry: GameDetailWindowGeometry?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reportGeometry()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            reportGeometry()
        }

        func reportGeometry() {
            guard let window, !bounds.isEmpty else { return }
            let screenSpace = window.screen.coordinateSpace
            let geometry = GameDetailWindowGeometry(
                owningWindow: window,
                contentFrame: window.convert(convert(bounds, to: window), to: screenSpace),
                windowFrame: window.convert(window.bounds, to: screenSpace),
                screenBounds: screenSpace.bounds,
                windowSize: window.bounds.size,
                windowSafeAreaTop: window.safeAreaInsets.top
            )
            guard geometry != lastGeometry else { return }
            lastGeometry = geometry
            // Avoid publishing SwiftUI state while its representable updates.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil,
                      self.lastGeometry == geometry else { return }
                self.onChange?(geometry)
            }
        }
    }
}

private struct CompactGameModesInToolbarKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var compactGameModesInToolbar: Bool {
        get { self[CompactGameModesInToolbarKey.self] }
        set { self[CompactGameModesInToolbarKey.self] = newValue }
    }
}

/// Navigation owns these items, including their Liquid Glass, safe-area insets,
/// native vertical placement, and overflow. Game content never imitates a bar.
private struct GameToolbarLayout: ViewModifier {
    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var nav: NavigationService
    @Environment(\.isVerticalToolbar) private var isVerticalToolbar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @Setting(.hidesRank) private var hidesRank: Bool
    @ObservedObject var game: Game
    @ObservedObject var gameControlState: GameControlState
    @Binding var selectedConditionalVariation: ConditionalMoveBranch?
    @Binding var interaction: GameDetailInteraction
    @Binding var showsCompactChatBoard: Bool
    @Binding var showSettings: Bool
    let compact: Bool
    let compactLandscape: Bool
    let zenMode: Bool
    let exitsZenFromContent: Bool
    let navigationBarHidden: Bool
    let drawsBackInContent: Bool
    let showsOpponentInHeader: Bool
    let showsClocksInHeader: Bool
    let showsCurrentPlayerClockInHeader: Bool
    let keyboardVisible: Bool
    /// An on-screen keyboard; a hardware keyboard leaves nothing to dismiss.
    let softwareKeyboardVisible: Bool
    let showsActiveGamesButton: Bool
    let placesActiveGamesAtTop: Bool
    let activeGamesButton: AnyView
    let dismissChatInput: () -> Void
    let enterZenMode: () -> Void
    let exitZenMode: () -> Void
    /// Header chips report a rendered Reconnecting… badge for this game.
    let notificationContextID: UUID

    private var topLeftPlayerColor: StoneColor {
        game.isUserPlaying ? (game.userStoneColor?.opponentColor() ?? .black) : .black
    }

    private var analyzingIsPresented: Bool {
        interaction.isAnalyzing
    }

    private var chatIsPresented: Bool {
        interaction.isChatVisible
    }

    private var usesBottomChatToolbar: Bool {
        compact && !compactLandscape && !placesActiveGamesAtTop && !isVerticalToolbar
    }

    private var usesCustomChatButton: Bool {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            return usesBottomChatToolbar
        }
        return true
    }

    private var usesCompactNavigationTitle: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return compact && !isVerticalToolbar
        #endif
    }

    /// The app's connection banner sits in the title slot (canvas
    /// "Reconnecting in stone removal · iPhone"). The title, or the opponent
    /// standing in for it, gives way; header clock chips stay.
    private var titleGivesWayToConnectionBanner: Bool {
        nav.connectionBannerVisible
    }

    @ViewBuilder private var compactNavigationTitle: some View {
        if game.gamePhase == .stoneRemoval {
            Text("Stone removal").font(.headline)
        } else if game.gamePhase == .finished {
            Text("Game over").font(.headline)
        } else if game.isUserPlaying,
           let color = game.userStoneColor,
           let opponent = game.currentPlayer(with: color.opponentColor()) {
            let teammates = game.gameData?.rengoTeams?[color.opponentColor()].count ?? 0
            HStack(spacing: 4) {
                Text(verbatim: String(localized: "vs.", defaultValue: "vs")).fixedSize()
                Text(verbatim: opponent.username)
                    .lineLimit(1).truncationMode(.tail)
                if !hidesRank {
                    Text(verbatim: "[\(opponent.formattedRank)]").fixedSize()
                }
                if game.rengo && teammates > 1 {
                    Text(verbatim: "+\(teammates - 1)").fixedSize()
                }
            }
            .font(.headline)
            .accessibilityElement(children: .combine)
        } else {
            Text(verbatim: game.gameName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                .font(.headline).lineLimit(1).truncationMode(.tail)
        }
    }

    /// The toggle wins over the composer's focus. Leaving chat first ends the
    /// input, keeping the draft, and resigns the keyboard, so the field
    /// regaining focus (as after the toolbar's overflow menu closes) cannot
    /// present chat again.
    private func setChatVisible(_ visible: Bool) {
        if !visible && chatIsPresented { endChatInput() }
        withAnimation { interaction.setChatVisible(visible) }
    }

    private func endChatInput() {
        dismissChatInput()
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    @ViewBuilder private var modeButtons: some View {
        if game.gamePhase == .play && game.isUserPlaying && !game.isUserTurn
            && !game.conditionalMoveBranches.isEmpty {
            ConditionalMovesButton(game: game, context: .gameDetail, usesToolbarStyle: true) {
                selectedConditionalVariation = $0
            }
            .modifier(GameToolbarMinimumTouchTarget())
        }
        Toggle(isOn: Binding(
            get: { analyzingIsPresented },
            set: { selected in
                if selected && chatIsPresented { endChatInput() }
                withAnimation { interaction.setAnalyzing(selected) }
            }
        )) {
            Label(game.analysisAvailable ? "Analyze mode" : "Playback mode",
                  systemImage: game.analysisAvailable ? "arrow.triangle.branch" : "arrow.left.and.right")
                .modifier(GameToolbarMinimumTouchTarget())
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .accessibilityIdentifier(
            compact
                ? SurroundUITestContract.AccessibilityID.gameDisplayModePicker + ".analyze"
                : SurroundUITestContract.AccessibilityID.gameAnalyzeToggle
        )
        if usesCustomChatButton {
            GameToolbarChatButton(isSelected: chatIsPresented,
                                  unreadCount: chatIsPresented ? 0 : game.chatUnreadCount) {
                setChatVisible(!chatIsPresented)
            }
        } else {
            Toggle(isOn: Binding(
                get: { chatIsPresented },
                set: { selected in setChatVisible(selected) }
            )) {
                Label("Chat", systemImage: "message")
                    .modifier(GameToolbarMinimumTouchTarget())
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .badge(chatIsPresented ? 0 : game.chatUnreadCount)
            // iOS 27's native toolbar can retain a rendered badge after its
            // accessibility value clears. Recreate the item when it changes.
            .id(chatIsPresented ? 0 : game.chatUnreadCount)
            .accessibilityIdentifier(
                SurroundUITestContract.AccessibilityID.gameDisplayModePicker + ".chat"
            )
        }
    }

    private var pinnedUtilityPlacement: ToolbarItemPlacement {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) { return .topBarPinnedTrailing }
        #endif
        return .topBarTrailing
    }

    @ViewBuilder private var utilityModeButton: some View {
        if compact && interaction.panel == .chat {
            Button {
                withAnimation { showsCompactChatBoard.toggle() }
            } label: {
                if showsCompactChatBoard {
                    Label("Hide main board", image: "custom.squareshape.split.3x3.slash")
                        .modifier(GameToolbarMinimumTouchTarget())
                } else {
                    Label("Show main board", image: "custom.squareshape.split.3x3.badge.eye")
                        .modifier(GameToolbarMinimumTouchTarget())
                }
            }
            .accessibilityIdentifier(showsCompactChatBoard
                ? SurroundUITestContract.AccessibilityID.gameChatBoardHide
                : SurroundUITestContract.AccessibilityID.gameChatBoardShow)
        } else if !analyzingIsPresented || !compact {
            Button(action: enterZenMode) {
                Label("Zen mode", systemImage: "arrow.up.backward.and.arrow.down.forward")
                    .modifier(GameToolbarMinimumTouchTarget())
            }
            .disabled(analyzingIsPresented)
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameZenEnter)
            .surroundUITestZenShortcut()
        }
    }

    private var optionsButton: some View {
        Button { showSettings = true } label: {
            Label("Options", systemImage: "gearshape.2")
                .modifier(GameToolbarMinimumTouchTarget())
        }
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameOptions)
    }

    @ViewBuilder private var utilityButtons: some View {
        utilityModeButton
        optionsButton
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Label("Back", systemImage: "chevron.backward")
                .modifier(GameToolbarMinimumTouchTarget())
        }
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameBack)
    }

    /// A header clock can consume the first tap to dismiss an attached keyboard.
    private var headerClockTapBeforeDetails: (() -> Bool)? {
        guard keyboardVisible else { return nil }
        return {
            // Clear retained focus intent before the
            // keyboard's disappearance expands layout.
            // Otherwise a restored composer can refocus.
            dismissChatInput()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
            // Only an on-screen keyboard takes the first
            // tap; with a hardware keyboard it also opens
            // the details.
            return softwareKeyboardVisible
        }
    }

    private var headerClocks: some View {
        let maximumWidth: CGFloat = showsCurrentPlayerClockInHeader ? 230 : 320
        return GameDetailClockPair(game: game, topLeftPlayerColor: topLeftPlayerColor,
                                   style: .inline,
                                   isInToolbar: true,
                                   showsCurrentPlayerOnly: showsCurrentPlayerClockInHeader,
                                   onTapBeforeDetails: headerClockTapBeforeDetails,
                                   blocksGameActions: gameControlState.blocksGameActions,
                                   showsStatus: !analyzingIsPresented)
            .frame(maxWidth: maximumWidth)
            // Set on the item itself: toolbar content is
            // hosted apart from the game's content.
            .environment(\.gameDetailNotificationContextID, notificationContextID)
    }

    private var headerIdentity: some View {
        GameDetailPlayerIdentity(game: game, color: topLeftPlayerColor,
                                 navigationHeader: true,
                                 compactHeader: dynamicTypeSize < .xxxLarge)
    }

    /// The title slot: header clocks, the opponent, or the compact title.
    /// Split from `body` so Xcode 26.2 can type-check the toolbar.
    private enum PrincipalItem { case clocks, identity, title, none }

    private var principalItem: PrincipalItem {
        if showsClocksInHeader && !isVerticalToolbar {
            // A principal title can receive less width than its
            // intrinsic clock. The pair fits its chips to the
            // proposal instead of painting beneath native items.
            return .clocks
        } else if compact && showsOpponentInHeader && !isVerticalToolbar {
            return titleGivesWayToConnectionBanner ? .none : .identity
        } else if usesCompactNavigationTitle {
            return titleGivesWayToConnectionBanner ? .none : .title
        }
        return .none
    }

    @ToolbarContentBuilder private var principalItems: some ToolbarContent {
        // Independent conditions (one is true at most): Xcode 26.2 cannot
        // type-check nested conditions inside an else-if chain here.
        if principalItem == .clocks {
            ToolbarItem(placement: .principal) { headerClocks }
        }
        if principalItem == .identity {
            ToolbarItem(placement: .principal) { headerIdentity }
        }
        if principalItem == .title {
            ToolbarItem(placement: .principal) { compactNavigationTitle }
        }
    }

    /// Modes, utilities and Active Games for each toolbar arrangement. The
    /// bottom-bar items stay in this one builder (see the spacer note).
    @ToolbarContentBuilder private var controlItems: some ToolbarContent {
        if isVerticalToolbar {
            if compact {
                // Closed keeps utilities beside upper navigation
                // and modes in their own lower native group.
                if interaction.panel == .chat || !analyzingIsPresented {
                    ToolbarItem(placement: pinnedUtilityPlacement) {
                        utilityModeButton
                    }
                }
                GameVerticalToolbarGroup(placement: .topBarTrailing) {
                    optionsButton
                }
                GameVerticalToolbarGroup(placement: .topBarTrailing) {
                    modeButtons
                }
            } else if navigationBarHidden {
                // Duo wide hides the navigation bar, whose band held
                // only the system sidebar toggle. The controls move
                // to the vertical bar's lower group, which stays;
                // the game draws Back at the top of the bar itself.
                GameVerticalToolbarGroup(placement: .bottomBar) {
                    if !drawsBackInContent { backButton }
                    modeButtons
                    utilityButtons
                }
                // Active Games keeps its own circle at the bottom.
                #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                }
                #endif
            } else {
                GameVerticalToolbarGroup(placement: .topBarTrailing) {
                    modeButtons
                    utilityButtons
                }
            }
            if showsActiveGamesButton {
                GameVerticalToolbarGroup(placement: .bottomBar) {
                    activeGamesButton
                }
            }
        } else if compact && !compactLandscape && !placesActiveGamesAtTop {
            ToolbarItemGroup(placement: .topBarTrailing) { utilityButtons }
            if showsActiveGamesButton {
                ToolbarItem(placement: .bottomBar) { activeGamesButton }
            }
            // All bottom content belongs to this toolbar builder;
            // separate builders coalesce items before their spacer.
            #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.flexible, placement: .bottomBar)
            } else {
                ToolbarItem(placement: .bottomBar) { Spacer() }
            }
            #else
            ToolbarItem(placement: .bottomBar) { Spacer() }
            #endif
            ToolbarItemGroup(placement: .bottomBar) { modeButtons }
        } else if compactLandscape {
            if showsActiveGamesButton {
                ToolbarItem(placement: .topBarTrailing) { activeGamesButton }
            }
            ToolbarItemGroup(placement: .topBarTrailing) { modeButtons }
            ToolbarItemGroup(placement: .topBarTrailing) { utilityButtons }
        } else {
            // All iPad windows keep modes and Active Games at the
            // top, even when a narrow window uses compact content.
            GameVerticalToolbarGroup(placement: .topBarTrailing) {
                modeButtons
            }
            if placesActiveGamesAtTop && showsActiveGamesButton {
                GameVerticalToolbarGroup(placement: .topBarTrailing) {
                    activeGamesButton
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                utilityButtons
            }
        }
    }

    func body(content: Content) -> some View {
        content
            // Duo's vertical toolbar carries navigation on the side. Remove
            // its unused title item so it cannot reserve a horizontal title row.
            .toolbar(removing: isVerticalToolbar ? .title : nil)
            .environment(\.compactGameModesInToolbar, !zenMode)
            .toolbar {
                if !nav.gameDetailNotificationContexts.isEmpty,
                   PrivateMessageNotificationButton.isVisible(ogs: ogs, nav: nav) {
                    ToolbarItem(placement: .topBarTrailing) {
                        PrivateMessageNotificationButton(isInToolbar: true)
                            .tint(.orange)
                            .modifier(GameToolbarMinimumTouchTarget())
                    }
                }
                if zenMode {
                    if !exitsZenFromContent {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: exitZenMode) {
                                Label("Exit Zen mode", systemImage: "arrow.down.forward.and.arrow.up.backward")
                                    .modifier(GameToolbarMinimumTouchTarget())
                            }
                            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameZenExit)
                            .surroundUITestZenShortcut()
                        }
                    }
                } else {
                    principalItems
                    controlItems
                }
            }
            .modifier(GameToolbarCompression())
    }
}

/// Our own chrome where a hidden navigation bar leaves its corner: Exit Zen,
/// and the Duo sidebar button.
private struct GameChromeButtonSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(.regularMaterial, in: Circle())
        }
    }
}

/// Game controls retain a full touch target; native toolbars own their insets.
private struct GameToolbarMinimumTouchTarget: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        content.frame(minWidth: 44, minHeight: 44)
        #else
        content
        #endif
    }
}

/// Keep the badge and action inside one custom toolbar view. Native toolbar
/// Toggle extraction drops bottom-bar badge preferences and label overlays.
private struct GameToolbarChatButton: View {
    let isSelected: Bool
    let unreadCount: Int
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    // Selected matches the native selected toggles beside it (Analyze): a
    // solid accent capsule with a white glyph, or a black one in dark mode.
    private var iconColor: Color {
        if isSelected { return colorScheme == .dark ? .black : .white }
        if #available(iOS 26.0, macCatalyst 26.0, *) { return .primary }
        return .accentColor
    }

    var body: some View {
        // The container prevents the toolbar from synthesizing a bar item out
        // of the label's text and image separately from its button action.
        ZStack {
            Button(action: action) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "message")
                        .font(.system(size: 20))
                        .imageScale(.medium)
                        .foregroundStyle(iconColor)
                        .frame(width: 44, height: 44)
                        .background {
                            if isSelected {
                                Capsule().fill(Color.accentColor)
                                    .frame(width: 42, height: 38)
                            }
                        }
                    if unreadCount > 0 {
                        Text(unreadCount, format: .number)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Color.red, in: Capsule())
                            .fixedSize()
                            .accessibilityIdentifier("game.chat.unreadBadge")
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(unreadCount > 0 ? Text("Chat, unread messages") : Text("Chat"))
            .accessibilityValue(Text(verbatim: unreadCount > 0 ? String(unreadCount) : ""))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameDisplayModePicker + ".chat")
        }
        .frame(width: 44, height: 44)
        .accessibilityElement(children: .contain)
    }
}

/// Native Duo groups opt their custom Toggle representation into the vertical
/// axis. No content overlay or hard-coded toolbar width participates.
private struct GameVerticalToolbarGroup<Content: View>: ToolbarContent {
    let placement: ToolbarItemPlacement
    @ViewBuilder var content: () -> Content

    var body: some ToolbarContent {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            ToolbarItemGroup(placement: placement, content: content)
                .axisBehavior(.verticalPreferred)
                .visibilityPriority(.high)
        } else {
            ToolbarItemGroup(placement: placement, content: content)
        }
        #else
        ToolbarItemGroup(placement: placement, content: content)
        #endif
    }
}

private struct GameToolbarCompression: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            content.toolbarVerticalCompressionBehavior(.prefersToolbarItems)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Landscape Zen only needs Exit, so a horizontal bar returns the side rail's
/// width to the board. Book still reserves the hinge and interaction margins.
private struct GameToolbarOrientation: ViewModifier {
    let prefersHorizontal: Bool

    func body(content: Content) -> some View {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            content.toolbarVerticalBehavior(prefersHorizontal ? .disabled : .automatic)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

struct GameDetailClocksInHeaderPreferenceKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct GameDetailCurrentPlayerClockInHeaderPreferenceKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    @ViewBuilder
    func surroundUITestZenShortcut() -> some View {
        #if DEBUG
        if SurroundUITestContract.isEnabled {
            // Catalyst 26 exposes the toolbar control to XCTest but does not
            // dispatch its action through synthesized pointer events.
            keyboardShortcut("z", modifiers: [.control, .option])
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if DEBUG
private func gameDetailPreviewFixture() -> (
    games: [Game],
    ogs: OGSService,
    navigation: NavigationService
) {
    let games = [
        TestData.Ongoing19x19wBot1,
        TestData.Ongoing19x19wBot2,
        TestData.Ongoing19x19wBot3,
    ]
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "kata-bot", id: 592684),
        activeGames: games
    )
    for game in games {
        game.chatUnreadCount = 2
    }
    return (games, ogs, NavigationService())
}

#Preview("Phone — Zen mode", traits: .fixedLayout(width: 390, height: 844)) {
    let fixture = gameDetailPreviewFixture()

    AppNavigationStack {
        GameDetailView(
            currentGame: .constant(fixture.games[0]),
            activeGames: fixture.games,
            zenMode: true
        )
    }
    .environmentObject(fixture.ogs)
    .environmentObject(fixture.navigation)
}

#Preview("Phone — Active games", traits: .fixedLayout(width: 390, height: 844)) {
    let fixture = gameDetailPreviewFixture()

    AppNavigationStack {
        GameDetailView(
            currentGame: .constant(fixture.games[0]),
            activeGames: fixture.games
        )
    }
    .environmentObject(fixture.ogs)
    .environmentObject(fixture.navigation)
}

#Preview("Regular landscape — Zen mode", traits: .fixedLayout(width: 960, height: 754)) {
    let fixture = gameDetailPreviewFixture()

    AppNavigationStack {
        GameDetailView(currentGame: .constant(fixture.games[0]), zenMode: true)
    }
    .environment(\.horizontalSizeClass, UserInterfaceSizeClass.regular)
    .environmentObject(fixture.ogs)
    .environmentObject(fixture.navigation)
}

#Preview("Regular portrait — Active game", traits: .fixedLayout(width: 750, height: 1024)) {
    let fixture = gameDetailPreviewFixture()

    AppNavigationStack {
        GameDetailView(currentGame: .constant(fixture.games[0]))
    }
    .environment(\.horizontalSizeClass, UserInterfaceSizeClass.regular)
    .environmentObject(fixture.ogs)
    .environmentObject(fixture.navigation)
}
#endif
