//
//  CorrespondenceGamesView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 8/26/20.
//

import SwiftUI
import Combine
#if DEBUG && MAIN_APP
import os
#endif

extension GeometryProxy {
    func boardShadowRegions(_ anchors: [BoardSceneShadowAnchor]) -> [BoardSceneShadowRegion] {
        anchors.map {
            BoardSceneShadowRegion(bounds: self[$0.bounds], cornerRadius: $0.cornerRadius,
                                   isDetailed: $0.isDetailed, cellSize: $0.cellSize, frontDepth: $0.frontDepth)
        }
    }
}

struct GameDetailView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isVerticalToolbar) private var isVerticalToolbar
    @Environment(\.owningStackRoute) private var owningStackRoute
    @Environment(\.duoTabContext) private var duoTabContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.openPlayerProfile) private var openPlayerProfile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    /// The game content's clock scale, for the Zen layout it draws.
    @ScaledMetric(relativeTo: .body) private var clockScale: CGFloat = 1
    /// How the game's content draws its board, for the same Zen layout.
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Setting(.showsBoardCoordinates) private var showsBoardCoordinates: Bool
    /// The window's width class and shape, measured at its root long before
    /// a game opens.
    @Environment(\.gameControlWindowClass) private var gameControlWindowClass
    /// The window's connection status, which the control's popover shares.
    @Environment(\.connectionStatus) private var connectionStatus
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    @AppStorage(SettingKey<String>.gameTheme.name, store: userDefaults)
    private var gameThemeID = SurroundTheme.standard.rawValue
    @State private var flowingInkCycleRevision = 0
    @StateObject private var koiPondVisit = KoiPondSwimSession()

    @Binding var currentGame: Game?
    /// Back clears the game as the slide-out begins. The screen keeps drawing
    /// it until it is gone, instead of turning blank while still visible.
    @State private var departingGame: Game?
    @State var activeGames: [Game] = []
    @State var activeGameByOGSID: [Int: Game] = [:]
    @State private var detailConnection = GameDetailConnectionCoordinator()

    /// Finished-game history routes do not offer the active-game picker.
    var allowsActiveGamesCarousel = true
    
    @State var showSettings = false
    /// The in-game control's popover: where it is open, and the window's
    /// Activity request it made.
    @State private var gameControlPopover = GameControlPopover()
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
    @State private var hasRestoredChatPanel = false
    @AppStorage(SettingKey<Bool>.regularGameChatVisible.name, store: userDefaults)
    private var regularGameChatVisible = false
    @State private var showsCompactChatBoard = true
    @State private var variationShareDraft: VariationShareDraft?
    @State private var selectedChatChannel = OGSChatSendChannel.main
    @EnvironmentObject private var chatSessions: GameChatSessionStore
    private var chatSession: ChatSessionState {
        chatSessions.session(for: (currentGame ?? departingGame)?.ID,
                             accountID: ogs.user?.id)
    }
    @StateObject private var gameControlState = GameControlState()
    @State private var selectedConditionalVariation: ConditionalMoveBranch?
    @Setting(.hidesRank) private var hidesRank: Bool
    @EnvironmentObject private var stackRouter: StackRouter
    #if DEBUG && MAIN_APP
    @State private var animationObservationID = UUID()
    /// This screen, for the in-game control's state cycle, which counts
    /// screens that open and leave, not their content drawn again.
    @State private var gameControlCycleScreen = UUID()
    #endif

    private func cycleFlowingInkTheme() {
        let selectedTheme = SurroundTheme.current(storedID: gameThemeID)
        guard selectedTheme.isFlowingInk else { return }
        gameThemeID = selectedTheme.nextFlowingInkTheme.rawValue
        // A local state change carries the animation through this screen even
        // when AppStorage publishes to its other observers independently.
        flowingInkCycleRevision += 1
    }

    // MARK: The in-game control

    /// How this Game Detail switches games, and whether its route has the
    /// picker: in place only on Home's route with the picker allowed.
    private var gameControlSwitch: GameControlSwitch {
        GameControlSwitch(route: owningStackRoute, allowsActiveGamesCarousel: allowsActiveGamesCarousel)
    }

    /// Where this layout puts the control. It follows the arrangement and
    /// the pose alone, never the control.
    private var gameControlPlacement: GameActiveGamesPlacement {
        toolbarArrangement.activeGamesPlacement(compact: compactLayout,
                                                navigationBarHidden: hidesNavigationBarInDuoWide)
    }

    /// Shows `game` as this route switches games: in place on Home's route,
    /// through Home elsewhere. The chip, the picker, the popover's live rows
    /// and Next all come here.
    private func showGame(_ game: Game) {
        gameControlSwitch.perform(game, navigation: nav) { next in
            withAnimation { currentGame = next }
        }
    }

    private func showGame(id gameID: Int) {
        guard let game = ogs.liveGames.first(where: { $0.ogsID == gameID }) else { return }
        showGame(game)
    }

    /// A hold, a tap or VoiceOver's Open Activity. It opens the popover from
    /// the item at this layout's placement, unless it is open there already,
    /// so a popover left open at an item a turn removed can never keep the
    /// new item from opening it.
    private func openGameControlPopover() {
        let placement = gameControlPlacement
        guard let game = currentGame, !gameControlPopover.isPresented(at: placement) else { return }
        gameControlPopover.open(at: placement, place: ActivityModel.Place(showing: game), navigation: nav)
    }

    private func closeGameControlPopover() {
        gameControlPopover.close(navigation: nav)
    }

    /// The popover binding of the item at `placement`. It reads true only at
    /// the placement the popover opened from, so the item a rotation leaves
    /// can't hold it open and the one that replaces it starts closed.
    private func gameControlPresentation(at placement: GameActiveGamesPlacement) -> Binding<Bool> {
        Binding(
            get: { gameControlPopover.isPresented(at: placement) },
            set: { presented in
                if !presented {
                    gameControlPopover.itemClosed(at: placement, navigation: nav)
                }
            }
        )
    }

    /// The control's popover: at game over the game-over card, then the
    /// picker, above Activity's sections, at this game's place and with the
    /// window's connection status. Each opening's list is new content, so a
    /// popover opened again while the last one closes never shows the last
    /// list's results or records its actions against the last session.
    /// - Parameter cardChallengeID: The challenge of the card the control
    ///   shows, if any.
    private func gameControlPopoverContent(for game: Game, cardChallengeID: Int?) -> some View {
        AppNavigationStack {
            ActivityListView(
                session: gameControlPopover.listSessionID, placement: .gamePopover,
                place: ActivityModel.Place(showing: game), cardChallengeID: cardChallengeID,
                header: gameControlPicker, switchGame: showGame, connection: connectionStatus
            )
        }
        .id(gameControlPopover.listSessionID)
        .environmentObject(ogs)
        .environmentObject(nav)
        .frame(idealWidth: 400, idealHeight: 620)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameActiveGamesPopover)
    }

    /// The user's games at this game's speed, where the route has the picker
    /// and it lists another game; nil elsewhere, so the list knows whether
    /// anything draws below its game-over card. Picking one switches in
    /// place.
    private var gameControlPicker: AnyView? {
        guard gameControlSwitch.allowsPicker, activeGames.contains(where: { $0.ID != currentGame?.ID }) else {
            return nil
        }
        return AnyView(
            ActiveGamesCarousel(
                currentGame: $currentGame,
                activeGames: activeGames,
                onSelectGame: closeGameControlPopover,
                switchGame: showGame
            )
            .padding(.vertical, 8)
        )
    }

    /// What the toolbar needs from this screen to fill the control's slot.
    private func gameControlHost(for game: Game) -> GameControlHost {
        GameControlHost(
            switchRule: gameControlSwitch,
            windowClass: gameControlWindowClass,
            zenForm: zenControlForm,
            zenCorner: barZenCorner?.form,
            isPopoverOpen: gameControlPopover.isOpen,
            presentation: gameControlPresentation(at:),
            popover: { AnyView(gameControlPopoverContent(for: game, cardChallengeID: $0)) },
            openPopover: openGameControlPopover,
            show: showGame(id:),
            isOnScreen: nav.gameDetailNotificationContexts[notificationContextID] != nil
        )
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

    /// Until Game Detail's own geometry arrives, a main-queue turn after its
    /// first layout, the window root's shape decides, so a game opened in
    /// landscape draws its first pass with the top bar's items, the in-game
    /// control among them, in the bar they stay in.
    private var compactLandscape: Bool {
        guard compactLayout else { return false }
        if let size = windowGeometry?.windowSize {
            return size.width > size.height
        }
        return gameControlWindowClass?.shape == .landscape
    }

    private var openLandscape: Bool {
        guard hasDisplayDivision, !hasActiveVerticalDisplayDivision,
              let size = windowGeometry?.windowSize else { return false }
        return size.width > size.height
    }

    private var prefersHorizontalZenToolbar: Bool {
        zenMode && (compactLandscape || regularPhoneLandscape
                    || hasActiveVerticalDisplayDivision || openLandscape)
    }

    private var regularPhoneLandscape: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard UIDevice.current.userInterfaceIdiom == .phone,
              horizontalSizeClass == .regular,
              let size = windowGeometry?.windowSize else { return false }
        return size.width > size.height
        #else
        return false
        #endif
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

    /// Sidebar navigation also appears on regular-width phones, including
    /// Duo Open tall and ordinary iPhone landscape. Hiding Back and our own
    /// items leaves the system sidebar toggle and its full navigation band.
    /// Hide that bar in Zen and keep Exit in the game content instead,
    /// including Book wide's split layout.
    private var hidesZenChrome: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        return zenMode && (UIDevice.current.userInterfaceIdiom == .pad
                           || horizontalSizeClass == .regular
                           || openLandscape)
        #else
        return false
        #endif
    }

    /// Before iPadOS 26, the multitasking control stays at the top centre with
    /// the status bar hidden, and the app's banners would move under it.
    private var hidesStatusBarInZen: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    /// Where Duo's wide poses draw our own chrome (the sidebar button, Exit
    /// Zen): in the band the navigation bar's items used, 24 pt from the
    /// window's top, in the game content's coordinates.
    private var chromeBandTop: CGFloat? {
        guard hidesNavigationBarInDuoWide
                || (hidesZenChrome && (openLandscape || hasActiveVerticalDisplayDivision)),
              let windowGeometry else { return nil }
        let contentTop = windowGeometry.contentFrame.minY - windowGeometry.windowFrame.minY
        return max(0, max(24, windowGeometry.windowSafeAreaTop) - contentTop)
    }

    /// Exit, and before it the circle for another live game on your move,
    /// which the toolbar reads for the game on screen. Where the circle there
    /// would reach over the clocks or the board, as in an iPad's compact
    /// window or a narrow one at regular width, it sits under Exit in the
    /// board's trailing column instead, or beside Exit without its
    /// countdown, or not at all. In compact landscape, where Exit is a bar
    /// item, the circle alone, under Exit in that column, where the chip and
    /// Exit would reach over the board.
    @ViewBuilder private func zenExitOverlay(in geometry: GeometryProxy) -> some View {
        if hidesZenChrome {
            let corner = contentZenCorner(in: geometry)
            // Each in the corner on its own: the overlay's implicit stack
            // would centre them on each other.
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .top, spacing: 0) {
                    switch corner?.form {
                    case nil: GameControlZenCircle(placement: zenCountdownPlacement)
                    case .besideExitAlone?: GameControlZenCircle(placement: .omitted)
                    default: EmptyView()
                    }
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
                }
                .padding(.top, zenExitTop)
                .padding(.trailing, zenExitTrailing)
                if let corner {
                    zenColumnCircle(corner)
                }
            }
        } else if let corner = barZenCorner {
            zenColumnCircle(corner)
        }
    }

    /// The circle in the board's trailing column, centred in it, where the
    /// column holds it.
    @ViewBuilder private func zenColumnCircle(_ corner: ZenCornerPlacement) -> some View {
        if case .circle(let showsCountdown) = corner.form {
            GameControlZenColumnCircle(showsCountdown: showsCountdown)
                .padding(.top, corner.top)
                .padding(.trailing, max(0, (corner.column - GameControlZenCorner.width(showsCountdown: showsCountdown)) / 2))
        }
    }

    /// Where the game's content draws Exit, its distance from the content's
    /// top: in Duo's chrome band, else 16 pt.
    private var zenExitTop: CGFloat { chromeBandTop ?? 16 }
    /// Its distance from the content's trailing edge: 16 pt in regular
    /// landscape and in Duo's chrome band, else 24.
    private var zenExitTrailing: CGFloat { regularLandscape || chromeBandTop != nil ? 16 : 24 }

    /// Where compact landscape's bar items end, from the top of the game's
    /// content, which reaches the window's top in Zen and reports no inset
    /// for the bar there: 44 pt items 24 pt down from iOS 26; before, a
    /// 32 pt bar whose items keep their 44 pt touch target from the top.
    private static var compactLandscapeBarBottom: CGFloat {
        if #available(iOS 26.0, macCatalyst 26.0, *) { return 68 }
        return 44
    }

    /// The Zen circle's countdown hangs below the circle where the window is
    /// wider than tall, as the board's column leaves its corners clear there
    /// (a compact window barely wider than tall puts its clocks above the
    /// board, and the circle moves into the column). Book wide is the
    /// exception: its board fills a portrait-shaped pane right below Exit,
    /// so there, as in portrait windows, the countdown sits beside the
    /// circle, inside Exit's band.
    private var zenCountdownPlacement: GameControlZenCountdownPlacement {
        let windowIsLandscape = windowGeometry.map { $0.windowSize.width > $0.windowSize.height }
            ?? (gameControlWindowClass?.shape == .landscape)
        return windowIsLandscape && !hasActiveVerticalDisplayDivision ? .below : .leading
    }

    /// The form of Zen's control where Exit is a bar item: the Mac's native
    /// icon; the rail's in Duo Closed portrait, whose Zen keeps the vertical
    /// toolbar; and the top-bar chip elsewhere, as on compact iPhones and in
    /// Duo Closed landscape, whose Zen turns the toolbar horizontal. From the
    /// window root's shape, not the toolbar's own state, so the first pass
    /// already has it.
    private var zenControlForm: GameControlForm {
        #if targetEnvironment(macCatalyst)
        return .mac
        #else
        return isVerticalToolbar && gameControlWindowClass?.shape != .landscape ? .rail : .topBar
        #endif
    }

    /// Where Zen's control sits in the board's trailing column: its form, the
    /// column's width, and how far down the content the control starts.
    private struct ZenCornerPlacement {
        var form: GameControlZenCorner
        var column: CGFloat
        var top: CGFloat
    }

    /// Zen's control in compact landscape, where Exit is a bar item and the
    /// board reaches the window's top: the chip before Exit where they clear
    /// the board, else the circle in the board's trailing column, 8 pt below
    /// the bar. From the Zen layout the game's content draws, at the
    /// content's width and the window's height, which entering Zen leaves as
    /// they are, so the bar's first Zen pass has it and it keeps for the
    /// pose. Nil everywhere else.
    private var barZenCorner: ZenCornerPlacement? {
        guard zenMode, !hidesZenChrome, compactLandscape, zenControlForm == .topBar,
              let windowGeometry, let game = currentGame ?? departingGame else { return nil }
        let size = CGSize(width: windowGeometry.contentFrame.width, height: windowGeometry.windowSize.height)
        let column = max(0, size.width - zenLayoutPlan(size: size, game: game)[.board].maxX)
        let content = windowGeometry.contentFrame, window = windowGeometry.windowFrame
        let trailingInset = layoutDirection == .rightToLeft ? content.minX - window.minX : window.maxX - content.maxX
        return ZenCornerPlacement(form: GameControlZenCorner(column: column, trailingInset: max(0, trailingInset)),
                                  column: column, top: Self.compactLandscapeBarBottom + GameControlZenCorner.gapUnderExit)
    }

    /// Zen's control wherever the game's content draws Exit (an iPad, a
    /// regular-width phone, Duo Open), except on Book's active fold, whose
    /// board keeps clear of Exit's band and whose clocks sit in the other
    /// pane: nil where the circle beside Exit clears the Zen layout's clocks,
    /// board and actions, else the circle under Exit in the board's trailing
    /// column, the circle alone beside Exit, or no control. From the Zen
    /// layout the game's content draws in `geometry`, the content's own, in
    /// the same pass.
    private func contentZenCorner(in geometry: GeometryProxy) -> ZenCornerPlacement? {
        guard zenMode, hidesZenChrome, !hasActiveVerticalDisplayDivision,
              let game = currentGame ?? departingGame else { return nil }
        let size = geometry.size
        let plan = zenLayoutPlan(size: size, game: game, division: SingleGameView.activeDivision(in: geometry),
                                 panelDivision: SingleGameView.availablePanelDivision(in: geometry))
        let column = max(0, size.width - plan[.board].maxX)
        let exit = CGRect(x: size.width - zenExitTrailing - 44, y: zenExitTop, width: 44, height: 44)
        guard let form = GameControlZenCorner(contentExit: exit, countdownBelow: zenCountdownPlacement == .below,
                                              width: size.width, column: column,
                                              occupied: [plan[.clocks], plan[.board], plan[.actions]])
        else { return nil }
        return ZenCornerPlacement(form: form, column: column, top: exit.maxY + GameControlZenCorner.gapUnderExit)
    }

    /// The Zen layout the game's content draws at `size`, from the inputs
    /// SingleGameView gives its plan that reach a Zen layout: the content's
    /// width class, the display's fold (`division` where it divides the
    /// scene, `panelDivision` divided or not), the clocks' and the actions'
    /// measures with the action's offline label, and the board as the theme
    /// draws it. The rest (identities, panels, the keyboard) Zen leaves out.
    private func zenLayoutPlan(size: CGSize, game: Game, division: CGRect? = nil,
                               panelDivision: CGRect? = nil) -> GameDetailLayoutPlan {
        // Zen has no title slot, so with no clock in play the action reads
        // Reconnecting… and its row reserves the label. The Mac's Zen keeps
        // its bar and never draws this layout.
        let relabels = GameConnectionPlacement(GameConnectionPlacement.Input(
            game: game, blocksActions: gameControlState.blocksGameActions, panel: interaction.panel,
            restoresChatPanel: restoresChatPanel, isVerticalToolbar: isVerticalToolbar, isZen: zenMode,
            isCatalyst: false
        )).action == .relabelled
        let actions = GameControlRowMetrics(dynamicTypeSize: dynamicTypeSize, locale: locale, phase: game.gamePhase,
                                            relabelsOffline: relabels)
        let theme = SurroundTheme.current(storedID: gameThemeID)
        let scale = min(clockScale, 1.65)
        let lineWidth = GameDetailClockPair.compactLineWidth(game: game, scale: scale, theme: theme)
        let chipWidth = GameDetailClockPair.narrowChipWidth(game: game, scale: scale, theme: theme)
        let spaciousChipWidth = GameDetailClockPair.narrowChipWidth(game: game, scale: scale, spacious: true,
                                                                    theme: theme)
        let board = BoardDepthPlacement(boardWidth: game.currentPosition.width,
                                        boardHeight: game.currentPosition.height,
                                        showsCoordinates: showsBoardCoordinates, displayScale: displayScale,
                                        depth: theme.board(for: theme.colorScheme ?? colorScheme).boardDepth)
        let centerY = windowGeometry.map { $0.windowFrame.midY - $0.contentFrame.minY }
        return GameDetailLayoutPlan(
            size: size, compact: compactLayout, zen: true, analyze: false, chat: false, hidesBoard: false,
            keyboard: false, accessibility: dynamicTypeSize.isAccessibilitySize,
            foldsClock: dynamicTypeSize >= .xxxLarge, clockScale: scale, actionSize: actions.horizontalSize,
            actionMetrics: actions, division: division, panelDivision: panelDivision,
            usesVerticalToolbar: isVerticalToolbar || (compactLandscape && verticalToolbarOutsideZen),
            zenBoardCenterY: centerY, compactClockLineWidth: lineWidth,
            compactClockBorderAllowance: theme.compactClockBorderAllowance, narrowChipWidth: chipWidth,
            spaciousNarrowChipWidth: spaciousChipWidth, chromeBandTop: chromeBandTop, boardDepth: board
        )
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
        if zenMode && (compactLandscape || regularPhoneLandscape || regularLandscape) && !openLandscape
            && !isVerticalToolbar && !hasActiveVerticalDisplayDivision
            && !effectiveAttachedKeyboardVisible {
            edges.insert(.top)
        }
        // Without their tray, both wide Duo Zen layouts use the window's top.
        if hidesZenChrome && (openLandscape || hasActiveVerticalDisplayDivision) {
            edges.insert(.top)
        }
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

    private func usesPhoneLandscapeRoomFraming(in geometry: GeometryProxy) -> Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        return UIDevice.current.userInterfaceIdiom == .phone && !hasDisplayDivision(in: geometry)
        #else
        return false
        #endif
    }

    /// Which of Game Detail's four toolbar arrangements this layout uses.
    private var toolbarArrangement: GameToolbarArrangement {
        #if DEBUG && MAIN_APP
        // Version 2.4's bottom bar held one item. With the freeze control
        // its item is alone in the bar, and everything else goes to the top
        // bar, as in compact landscape.
        if ownGameFreezeControlBar != nil { return .compactLandscape }
        #endif
        return layoutToolbarArrangement
    }

    private var layoutToolbarArrangement: GameToolbarArrangement {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let isCatalyst = false
        #else
        let isCatalyst = true
        #endif
        return GameToolbarArrangement(isVerticalToolbar: isVerticalToolbar, compact: compactLayout,
                                      compactLandscape: compactLandscape, isCatalyst: isCatalyst)
    }

    #if DEBUG && MAIN_APP
    /// The freeze control's bar, in the bottom bar's arrangement: compact
    /// portrait.
    private var ownGameFreezeControlBar: SurroundUITestContract.OwnGameFreezeControl? {
        guard layoutToolbarArrangement == .bottomBar else { return nil }
        return SurroundUITestContract.gameControlDrivers.freezeControl
    }
    #endif

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
        if let gameSpeed = currentGame?.resolvedSpeed {
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
        
    /// Next (N): the next game at this speed on the user's move, shown as
    /// the control switches, so off Home's route it opens on Home's.
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
            showGame(nextGame)
        }
    }
    
    func enterZenMode() {
        closeGameControlPopover()
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
        let connection = windowConnection

        return VStack(alignment: .leading, spacing: compact ? nil : 0) {
            // Keep this view in one structural slot as the size class changes,
            // so folding preserves analysis and pending board moves.
            if let currentGame = currentGame ?? departingGame {
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
                    connection: connection,
                    restoresChatPanel: restoresChatPanel,
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
        usesCompactLayout(at: contentWidth)
    }

    private func usesCompactLayout(at width: CGFloat) -> Bool {
        var compactLayout = true
        #if os(iOS)
        compactLayout = horizontalSizeClass == .compact
        #endif
        #if DEBUG && MAIN_APP
        if SurroundUITestContract.forcesCompactGameLayout {
            compactLayout = true
        }
        #endif
        if width > 0 && width < 600 {
            compactLayout = true
        }
        return compactLayout
    }

    private func restoreChatPanelIfNeeded(contentWidth: CGFloat) {
        guard !hasRestoredChatPanel, contentWidth > 0, currentGame != nil else { return }
        // Restore once for this route, after measuring the actual layout.
        // Resizing and returning from Profile keep the current task intact.
        let restore = GameDetailChatRestore(hasRestored: false, remembersChat: regularGameChatVisible,
                                            isCompact: usesCompactLayout(at: contentWidth))
        hasRestoredChatPanel = true
        if restore.opensChat(from: interaction.panel) {
            interaction.setChatVisible(true)
        }
    }

    /// The window's connection source, or one that is never offline where
    /// no root hosts one (previews, most captures), so nothing shows there.
    private var windowConnection: ConnectionStatusSource {
        connectionStatus ?? ConnectionStatusSource.neverOffline
    }

    /// A remembered Chat panel that opens once Game Detail has measured its
    /// width, from the size class and the saved setting until then. Where a
    /// game says its connection status counts it as Chat from the first
    /// pass, so the title slot never shows the status for the pass before
    /// Chat opens.
    private var restoresChatPanel: Bool {
        GameDetailChatRestore(hasRestored: hasRestoredChatPanel, remembersChat: regularGameChatVisible,
                              isCompact: compactLayout)
            .opensChat(from: interaction.panel)
    }

    private var measuredContent: some View {
        GeometryReader { geometry in
            content(geometry: geometry)
                #if DEBUG && MAIN_APP
                .modifier(OwnGameFreezeControlItem(
                    control: SurroundUITestContract.gameControlDrivers.freezeControl,
                    isActive: ownGameFreezeControlBar != nil && !zenMode,
                    spare: geometry.size.height - min(geometry.size.width, geometry.size.height)
                ))
                #endif
                .background {
                    GameDetailWindowGeometryReader(
                        layoutFrame: geometry.frame(in: .global),
                        beginSizeTransition: {
                            let session = chatSession
                            guard let token = session.beginWindowSizeTransition() else { return nil }
                            #if DEBUG && MAIN_APP
                            SurroundAnimationDiagnostics.record(
                                "composer.windowTransitionBegan", ownerID: animationObservationID,
                                fields: ["focusRevision": String(session.focusRevision)]
                            )
                            #endif
                            return { allowsRestoration in
                                session.completeWindowSizeTransition(token, allowsRestoration: allowsRestoration)
                                #if DEBUG && MAIN_APP
                                SurroundAnimationDiagnostics.record(
                                    "composer.windowTransitionCompleted", ownerID: animationObservationID,
                                    fields: ["wantsFocus": String(session.wantsInputFocus),
                                             "restorationRevision": String(session.focusRestorationRevision)]
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
        #if DEBUG && MAIN_APP
        .modifier(GameControlCycleScreen(id: gameControlCycleScreen))
        #endif
    }

    var body: some View {
        measuredContent
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            contentWidth = width
            restoreChatPanelIfNeeded(contentWidth: width)
        }
        .onChange(of: interaction) { oldValue, newValue in
            guard hasRestoredChatPanel, !compactLayout,
                  oldValue.analysisResetRevision == newValue.analysisResetRevision,
                  oldValue.isChatVisible != newValue.isChatVisible else { return }
            regularGameChatVisible = newValue.isChatVisible
        }
        .onChange(of: currentGame) { oldGame, newGame in
            departingGame = newGame == nil ? oldGame : nil
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
        .statusBarHidden(hidesZenChrome && hidesStatusBarInZen)
        // Typing never changes the scene's geometry. The conversation places
        // its composer above the keyboard using the owning window's overlap.
        // The navigation host tracks no keyboard region either: see
        // GameDetailWindowGeometryReader.GeometryController.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func content(geometry: GeometryProxy) -> some View {
        guard let currentGame = self.currentGame ?? departingGame else {
            return AnyView(EmptyView())
        }

        let toolbarArrangement = self.toolbarArrangement
        let connection = windowConnection
        #if targetEnvironment(macCatalyst)
        // Keep the document identity in the Mac window title. The game
        // surface itself has no navigation heading; clocks open its details.
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
        let navigationTitle = title.isEmpty
            ? String(
                localized: "Game",
                comment: "Fallback game window title"
            )
            : title
        #else
        let navigationTitle = ""
        #endif
        
        let theme = SurroundTheme.current(storedID: gameThemeID)
        let result = gameBody(compact: compactLayout, geometry: geometry)
        .environment(\.christmasKeepsakesLightContext,
                     ChristmasKeepsakesLightContext(size: geometry.size, safeAreaInsets: geometry.safeAreaInsets))
        .environment(\.excludesBoardsFromSceneShadows, theme == .frostPine || theme == .sakuraStream)
        .environment(\.keepsCompactBoardsUnlit, theme == .reefLight)
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        .coordinateSpace(name: ChristmasKeepsakesLightContext.coordinateSpace)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.gameDetail(currentGame)
        )
        .backgroundPreferenceValue(BoardSceneShadowExclusionKey.self) { anchors in
            Color.clear.preference(key: GameDetailForegroundAnchorsKey.self,
                                   value: GameDetailForegroundAnchors(boards: anchors))
        }
        .backgroundPreferenceValue(GameDetailForegroundAnchorsKey.self) { anchors in
            Group {
                if theme == .koiPond {
                    GeometryReader { scene in
                        let layout = anchors.pondLayout
                        let game = layout.map { scene[$0.bounds] }
                        let panels = layout.map {
                            KoiPondGameLayout.panelFrames($0.panels, in: scene[$0.bounds], direction: layoutDirection)
                        } ?? []
                        let corners = anchors.pondControlReservations.map { scene[$0] }
                        KoiPondScene(scheme: colorScheme, boards: scene.boardShadowRegions(anchors.boards),
                                     gameArea: game, controlReservations: panels + corners,
                                     windowInScene: windowGeometry?.bounds(relativeTo: scene.frame(in: .global)) ?? .zero,
                                     layout: KoiPondSwimLayout(panel: interaction.panel,
                                                               divided: SingleGameView.activeDivision(in: geometry) != nil,
                                                               hidesChatBoard: interaction.isChatVisible && !showsCompactChatBoard),
                                     boardIsHidden: layout?.showsBoard == false,
                                     swimSession: SurroundUITestContract.freezesKoiPond ? nil : koiPondVisit,
                                     gameID: currentGame.ID)
                    }
                } else if theme.usesBoardAlignedBackdrop {
                    GeometryReader { scene in
                        GameDetailBackdrop(sceneBoards: scene.boardShadowRegions(anchors.boards))
                    }
                } else {
                    GameDetailBackdrop(usesPhoneLandscapeFraming: usesPhoneLandscapeRoomFraming(in: geometry))
                }
            }
            .overlay {
                GameDetailSceneFoliage(hasTopEdgeClocks: hasActiveVerticalDisplayDivision(in: geometry))
            }
            .overlay {
                ThemeStatusBarContrast(hidden: hidesZenChrome && hidesStatusBarInZen)
            }
            .ignoresSafeArea(.container)
        }
        .overlayPreferenceValue(GameDetailForegroundAnchorsKey.self) { anchors in
            GeometryReader { scene in
                GameDetailSceneForeground(shadowExclusions: scene.boardShadowRegions(anchors.boards),
                                          shellFaces: anchors.shells.map {
                                              RoundedRectangle(cornerRadius: $0.cornerRadius).path(in: scene[$0.bounds])
                                          })
            }
            .ignoresSafeArea(.container)
        }
        .overlay(alignment: .topTrailing) { zenExitOverlay(in: geometry) }
        .overlay(alignment: .topLeading) { duoSidebarButton }
        .overlay(alignment: .topTrailing) { duoBackButton(in: geometry) }
        .sheet(isPresented: self.$showSettings) {
            AppNavigationStack {
                ScrollView {
                    VStack {
                        GameThemeSettings()
                        GameplaySettings()
                    }
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
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
            // Settings retain the app's accent even when legacy game bars
            // use the meadow foreground for their unbacked controls.
            .modifier(GameDetailLegacyTint(color: .accentColor))
        }
        // Catalyst keeps this useful as the Mac window title in Zen mode.
        .navigationTitle(navigationTitle)
        .navigationBarHidden(hidesZenChrome || hidesNavigationBarInDuoWide)
        .navigationBarBackButtonHidden(zenMode)
        .navigationBarTitleDisplayMode(.inline)
        .modifier(GameDetailNotificationRegistration(game: currentGame, contextID: notificationContextID))
        .onAppear {
            restoreChatPanelIfNeeded(contentWidth: geometry.size.width)
            updateActiveGameList()
            updateDetailOfCurrentGameIfNecessary()
        }
        .onDisappear {
            clearKeyboardVisibility()
        }
        .modifier(GameControlPopoverLifecycle(
            placement: gameControlPlacement, gameID: currentGame.ogsID,
            close: closeGameControlPopover, open: openGameControlPopover,
            windowRequestChanged: { gameControlPopover.windowRequestChanged(to: $0) }
        ))
        .onChange(of: currentGame) { oldGame, newGame in
            if newGame.ID != oldGame.ID {
                chatSessions.deactivate(gameID: oldGame.ID, accountID: ogs.user?.id)
                selectedConditionalVariation = nil
                showSettings = false
                closeGameControlPopover()
                if GameDetailDisplayReset.restoresDisplayDefaults(from: oldGame, to: newGame) {
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
        .onChange(of: ogs.user?.id) { _, newAccountID in
            chatSessions.discardOtherAccounts(keeping: newAccountID)
            clearKeyboardVisibility()
            selectedConditionalVariation = nil
            zenMode = false
            interaction.resetPanels()
            showsCompactChatBoard = true
            closeGameControlPopover()
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
            value: "attachedKeyboard=\(effectiveAttachedKeyboardVisible);navigationHidden=\(hidesZenChrome || hidesNavigationBarInDuoWide);compact=\(compactLayout)",
            ownerID: animationObservationID,
            focusRequestID: variationShareDraft?.focusRequestID
        )
        #endif
        
        return AnyView(
            result.modifier(GameToolbarLayout(
                game: currentGame,
                gameControlState: gameControlState,
                connection: connection,
                activityResults: nav.activityResults,
                selectedConditionalVariation: $selectedConditionalVariation,
                interaction: $interaction,
                showsCompactChatBoard: $showsCompactChatBoard,
                showSettings: $showSettings,
                compact: compactLayout,
                arrangement: toolbarArrangement,
                zenMode: zenMode,
                exitsZenFromContent: hidesZenChrome,
                navigationBarHidden: hidesNavigationBarInDuoWide,
                drawsBackInContent: hidesNavigationBarInDuoWide && trailingVerticalBarWidth(in: geometry) != nil,
                showsOpponentInHeader: showsOpponentInHeader,
                showsClocksInHeader: showsClocksInHeader,
                showsCurrentPlayerClockInHeader: showsCurrentPlayerClockInHeader,
                keyboardVisible: effectiveAttachedKeyboardVisible || chatSession.wantsInputFocus,
                softwareKeyboardVisible: effectiveAttachedKeyboardVisible,
                gameControl: gameControlHost(for: currentGame),
                cycleFlowingInk: cycleFlowingInkTheme,
                dismissChatInput: chatSession.dismissInput,
                enterZenMode: enterZenMode,
                exitZenMode: exitZenMode,
                restoresChatPanel: restoresChatPanel
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
            // A departing screen gives the window back at once, so the
            // screen sliding in already has its own appearance.
            .surroundTheme(theme,
                             ownsWindow: self.currentGame != nil)
            // Only this toolbar action animates the theme. Picking a theme in
            // Settings, game updates and layout changes keep their own policy.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.38),
                       value: flowingInkCycleRevision)
        )
    }
}

/// Registers what a visible Game Detail shows with its window. It observes the
/// game itself, so a result reaches the app's notices and display sleep at
/// once, even when nothing else redraws the screen. It also tells the
/// window's Activity hosts that a Game Detail is on top of its tab.
private struct GameDetailNotificationRegistration: ViewModifier {
    @ObservedObject var game: Game
    let contextID: UUID
    @EnvironmentObject private var nav: NavigationService
    // Whether the user plays this game follows the signed-in account.
    @EnvironmentObject private var ogs: OGSService
    @StateObject private var lifetime = ViewLifetime()

    private var context: GameDetailNotificationContext {
        GameDetailNotificationContext(showing: game)
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                nav.gameDetailNotificationContexts[contextID] = context
                // A finished game must not keep a restored window awake
                // because this registration outlived its views.
                let nav = nav, contextID = contextID
                lifetime.release = { nav.removeGameDetailNotificationContext(contextID) }
            }
            .onChange(of: context) { _, newContext in
                // A retained navigation destination can receive game updates
                // after disappearing. Only its visible registration owns notices.
                guard nav.gameDetailNotificationContexts[contextID] != nil else { return }
                nav.gameDetailNotificationContexts[contextID] = newContext
            }
            .onDisappear {
                nav.gameDetailNotificationContexts.removeValue(forKey: contextID)
            }
            // Activity's bar never shows over Game Detail. Unlike the notice
            // context above, this follows the stack's path, not appearance:
            // see ActivityPlaceRegistration.
            .activityPlace(ActivityModel.Place(showing: game))
    }
}

private struct GameDetailWindowGeometry: Equatable {
    weak var owningWindow: UIWindow?
    let contentFrame: CGRect
    let windowFrame: CGRect
    let screenBounds: CGRect
    let windowSize: CGSize
    let windowSafeAreaTop: CGFloat
    /// The UIKit window expressed in SwiftUI's global space, including when
    /// Game Detail occupies only part of a window.
    let globalWindowOrigin: CGPoint

    func bounds(relativeTo scene: CGRect) -> CGRect {
        CGRect(x: globalWindowOrigin.x - scene.minX, y: globalWindowOrigin.y - scene.minY,
               width: windowSize.width, height: windowSize.height)
    }
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
        controller.geometryView.layoutFrame = layoutFrame
        controller.geometryView.reportGeometry()
    }

    final class GeometryController: UIViewController {
        let geometryView = GeometryView()
        var beginSizeTransition: (() -> ((Bool) -> Void)?)?

        override func loadView() {
            geometryView.isUserInteractionEnabled = false
            view = geometryView
        }

        #if !targetEnvironment(macCatalyst)
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            removeHostKeyboardRegion()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            // In case SwiftUI added this controller before it put the host
            // in its navigation stack.
            removeHostKeyboardRegion()
        }

        /// Game Detail never takes SwiftUI's keyboard region: its body ignores
        /// it, and the conversation places its composer with the overlap this
        /// bridge measures. So the host of the navigation stack level that
        /// shows it tracks no keyboard region either. During a push or pop,
        /// SwiftUI can give that host a stale region taller than its view
        /// (iPadOS 26.5 and 27.0, after a turn from landscape, a docked keyboard
        /// shown and dismissed in another tab and a window resize). Other screens
        /// collapse until the transition ends; Game Detail, which ignores the
        /// region, grew past the bottom of its window and stayed there. The
        /// host is SwiftUI's own and is reached through public API, whatever
        /// view it hosts. Its other regions are kept, and Game Detail hosted
        /// any other way is left alone.
        private func removeHostKeyboardRegion() {
            var ancestor = parent
            while let controller = ancestor, !(controller is any SafeAreaRegionsHost) {
                ancestor = controller.parent
            }
            guard let host = ancestor as? any SafeAreaRegionsHost,
                  host.parent is UINavigationController,
                  host.safeAreaRegions.contains(.keyboard) else { return }
            host.safeAreaRegions.remove(.keyboard)
        }
        #endif

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
        var layoutFrame: CGRect?
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
            guard let window, let layoutFrame, !bounds.isEmpty else { return }
            let screenSpace = window.screen.coordinateSpace
            let inWindow = convert(bounds, to: window)
            let geometry = GameDetailWindowGeometry(
                owningWindow: window,
                contentFrame: window.convert(inWindow, to: screenSpace),
                windowFrame: window.convert(window.bounds, to: screenSpace),
                screenBounds: screenSpace.bounds,
                windowSize: window.bounds.size,
                windowSafeAreaTop: window.safeAreaInsets.top,
                globalWindowOrigin: CGPoint(x: layoutFrame.minX - inWindow.minX, y: layoutFrame.minY - inWindow.minY)
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

#if !targetEnvironment(macCatalyst)
/// A UIHostingController, whatever view it hosts: SwiftUI hosts each level of
/// a navigation stack in a private subclass.
@MainActor
private protocol SafeAreaRegionsHost: UIViewController {
    var safeAreaRegions: SafeAreaRegions { get set }
}

extension UIHostingController: SafeAreaRegionsHost {}
#endif

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
    @Environment(\.surroundTheme) private var theme
    @AppStorage(SettingKey<String>.gameTheme.name, store: userDefaults)
    private var gameThemeID = SurroundTheme.standard.rawValue
    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var nav: NavigationService
    @Environment(\.iPadTabContext) private var iPadTabContext
    @Environment(\.isVerticalToolbar) private var isVerticalToolbar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var game: Game
    @ObservedObject var gameControlState: GameControlState
    /// The window's connection status, for the title slot's capsule and
    /// the header clocks' mark.
    @ObservedObject var connection: ConnectionStatusSource
    /// The window's Activity results, so the in-game control drops what OGS
    /// confirmed gone as soon as the store hides it.
    @ObservedObject var activityResults: ActivityResults
    /// Redraws the in-game control where time alone changes its state.
    @StateObject private var gameControlDeadlines = GameControlDeadlines()
    /// The control's last state, which it keeps while its popover is open
    /// and nothing waits any more, so the popover keeps its anchor.
    @State private var lastShownGameControl: GameControlSlot?
    /// The challengers of the game-over cards the control has shown, by
    /// challenge.
    @State private var cardChallengers: [Int: OGSUser] = [:]
    /// The rail's and the Mac's native item is made again when its badge
    /// changes, as iOS 27 can keep a stale badge, but never while its
    /// popover is open or still on screen, which would leave the popover
    /// there.
    @State private var nativeGameControlIdentity = GameControlNativeIdentity()
    #if DEBUG && MAIN_APP
    @State private var gameControlFirstState: GameControlFirstState?
    #endif
    @Binding var selectedConditionalVariation: ConditionalMoveBranch?
    @Binding var interaction: GameDetailInteraction
    @Binding var showsCompactChatBoard: Bool
    @Binding var showSettings: Bool
    let compact: Bool
    let arrangement: GameToolbarArrangement
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
    /// What the in-game control needs from its Game Detail. Every
    /// arrangement emits the control's slot at its own place.
    let gameControl: GameControlHost
    let cycleFlowingInk: () -> Void
    let dismissChatInput: () -> Void
    let enterZenMode: () -> Void
    let exitZenMode: () -> Void
    /// A remembered Chat panel opens once Game Detail has measured its width.
    let restoresChatPanel: Bool

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
        arrangement == .bottomBar
    }

    /// Before iOS 26 the custom button carries the unread badge, but a top
    /// bar that runs out of room cannot move a custom view into its More menu
    /// and drops Chat. A narrow, landscape-shaped iPad window keeps the top
    /// bar, so it uses the native Toggle, which overflows.
    private var usesCustomChatButton: Bool {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            return usesBottomChatToolbar
        }
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if compact && !usesBottomChatToolbar && UIDevice.current.userInterfaceIdiom == .pad {
            return false
        }
        #endif
        return true
    }

    /// Before iOS 26 a native toolbar Toggle shows no badge, so its symbol
    /// carries the unread dot instead.
    private var nativeChatSymbol: String {
        if #available(iOS 26.0, macCatalyst 26.0, *) { return "message" }
        return !chatIsPresented && game.chatUnreadCount > 0 ? "message.badge" : "message"
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

    /// Conditional moves shows beside Analyze and Chat while the user waits
    /// for the opponent with branches saved.
    private var showsConditionalMoves: Bool {
        game.gamePhase == .play && game.isUserPlaying && !game.isUserTurn
            && !game.conditionalMoveBranches.isEmpty
    }

    @ViewBuilder private var modeButtons: some View {
        if showsConditionalMoves {
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
        .modifier(GameDetailLegacyTint(color: theme.usesCustomDetailTint && !analyzingIsPresented
            ? theme.foreground : .accentColor))
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
                Label("Chat", systemImage: nativeChatSymbol)
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
            // Zen from Analyze shows the live game; leaving restores the analysis.
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

    private var flowingInkButton: some View {
        let selectedTheme = SurroundTheme.current(storedID: gameThemeID)
        // Preserve the button's live accessibility value: synthesizing a
        // native bar item from its Label drops that value on recent iOS.
        return ZStack {
            Button(action: cycleFlowingInk) {
                Label("Flowing Ink", systemImage: "paintbrush.pointed")
                    .labelStyle(.iconOnly)
                    .modifier(GameToolbarMinimumTouchTarget())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(selectedTheme.isFlowingInk ? selectedTheme.flowingInkModeDescription : "")
            .accessibilityHint(Text("Cycles the color and landscape background.",
                                    comment: "Accessibility hint for the Flowing Ink toolbar button, which cycles monochrome/color and landscape/no landscape"))
            .help(Text("Cycles the color and landscape background."))
            .accessibilityIdentifier("game.flowingInkCycle")
        }
        .accessibilityElement(children: .contain)
    }

    /// A separate native group precedes the existing trailing controls. It
    /// follows those controls onto Duo's side bar when the toolbar is vertical.
    @ToolbarContentBuilder private func flowingInkItems(placement: ToolbarItemPlacement) -> some ToolbarContent {
        if SurroundTheme.current(storedID: gameThemeID).isFlowingInk {
            GameVerticalToolbarGroup(placement: placement) {
                flowingInkButton
            }
            #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: placement)
            }
            #endif
        }
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
                                   showsStatus: !analyzingIsPresented,
                                   connection: headerClockConnection)
            .frame(maxWidth: maximumWidth)
    }

    // MARK: Connection status

    /// Where this game says the window's connection is down. Read from
    /// what this screen has before it draws, never from a rendered badge or
    /// the layout plan, so a game opened during an outage has its status in
    /// its place from the first frame. The game's content reads the same,
    /// and its chat preview, which the bar doesn't see: the preview moves
    /// the mark only where the clocks are in the game's body, never the
    /// bar's.
    private var connectionPlacement: GameConnectionPlacement {
        GameConnectionPlacement(GameConnectionPlacement.Input(
            game: game, blocksActions: gameControlState.blocksGameActions, panel: interaction.panel,
            restoresChatPanel: restoresChatPanel, isVerticalToolbar: isVerticalToolbar, isZen: zenMode,
            isCatalyst: Self.isCatalyst
        ))
    }

    private var headerClockConnection: GameDetailClockConnection {
        GameDetailClockConnection(
            hasConnected: connection.hasConnected,
            marksOneClock: connectionPlacement.clocks == .oneClock && connection.status.showsInGame
        )
    }

    /// The capsule in the title slot: no clock in play, neither Chat nor
    /// Analyze open, a title slot, and the window's status showing.
    private var showsConnectionCapsule: Bool {
        connectionPlacement.showsTitleCapsule && connection.status.showsInGame
    }

    private var headerIdentity: some View {
        GameDetailPlayerIdentity(game: game, color: topLeftPlayerColor,
                                 navigationHeader: true,
                                 compactHeader: dynamicTypeSize < .xxxLarge)
    }

    /// The principal slot holds useful clocks, the connection status or
    /// opponent identity only. Split from `body` so Xcode 26.2 can
    /// type-check the toolbar.
    private enum PrincipalItem { case clocks, status, identity, none }

    private var principalItem: PrincipalItem {
        if showsClocksInHeader && !isVerticalToolbar {
            // A principal title can receive less width than its
            // intrinsic clock. The pair fits its chips to the
            // proposal instead of painting beneath native items.
            // The status never replaces header clocks: they carry its
            // mark, and it takes the slot once they have left.
            return .clocks
        } else if showsConnectionCapsule {
            return .status
        } else if compact && showsOpponentInHeader && !isVerticalToolbar {
            return .identity
        }
        return .none
    }

    /// The game hides iPad's tab bar, which holds the sidebar toggle before
    /// iPadOS 27; iPadOS 27 adds its own to the navigation bar instead.
    private var showsIPadSidebarButton: Bool {
        guard !zenMode, iPadTabContext?.sidebarAvailable == true else { return false }
        if #available(iOS 27.0, *) { return false }
        return true
    }

    @ToolbarContentBuilder private var iPadSidebarItems: some ToolbarContent {
        if showsIPadSidebarButton, let iPadTabContext {
            ToolbarItem(placement: .topBarLeading) {
                Button { iPadTabContext.toggleSidebar() } label: {
                    Label("Toggle sidebar", systemImage: "sidebar.left")
                        .modifier(GameToolbarMinimumTouchTarget())
                }
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameSidebarToggle)
            }
        }
    }

    @ToolbarContentBuilder private var principalItems: some ToolbarContent {
        // Independent conditions (one is true at most): Xcode 26.2 cannot
        // type-check nested conditions inside an else-if chain here.
        if principalItem == .clocks {
            ToolbarItem(placement: .principal) { headerClocks }
        }
        if principalItem == .status {
            ToolbarItem(placement: .principal) {
                GameConnectionStatusCapsule(connection: connection, socket: ogs.socketStatus)
            }
        }
        if principalItem == .identity {
            ToolbarItem(placement: .principal) { headerIdentity }
        }
    }

    /// Modes, utilities and the in-game control's slot. Each arrangement's
    /// builder keeps its bar items in order, the slot composed in place,
    /// never through a separate `.toolbar` (whose items coalesce before a
    /// spacer). Split by arrangement so Xcode 26.2 can type-check each.
    @ToolbarContentBuilder private func controlItems(_ slot: GameActiveGamesSlot) -> some ToolbarContent {
        if arrangement != .vertical {
            flowingInkItems(placement: .topBarTrailing)
        }
        if arrangement == .vertical {
            verticalControlItems(slot)
        } else if arrangement == .bottomBar {
            bottomBarControlItems(slot)
        } else if arrangement == .compactLandscape {
            compactLandscapeControlItems(slot)
        } else {
            wideControlItems(slot)
        }
    }

    /// Duo's vertical toolbar, with the control in its own group at the bottom.
    @ToolbarContentBuilder private func verticalControlItems(_ slot: GameActiveGamesSlot) -> some ToolbarContent {
        if compact {
            flowingInkItems(placement: .topBarTrailing)
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
            flowingInkItems(placement: .bottomBar)
            GameVerticalToolbarGroup(placement: .bottomBar) {
                if !drawsBackInContent { backButton }
                modeButtons
                utilityButtons
            }
            // The slot's own spacer keeps the control in its circle.
        } else {
            flowingInkItems(placement: .topBarTrailing)
            GameVerticalToolbarGroup(placement: .topBarTrailing) {
                modeButtons
                utilityButtons
            }
        }
        GameActiveGamesSlotItems(slot: slot)
    }

    /// Compact portrait: utilities at the top; the control, a spacer and the
    /// modes in the bottom bar, all in this one builder.
    @ToolbarContentBuilder private func bottomBarControlItems(_ slot: GameActiveGamesSlot) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) { utilityButtons }
        GameActiveGamesSlotItems(slot: slot)
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
    }

    // MARK: The in-game control

    private static var isCatalyst: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    /// One read of the window's state for the game on screen, the input the
    /// window's bar and Activity read (`ActivityModel.Input.window`): less
    /// what OGS confirmed gone, so a challenge rejected in the popover leaves
    /// the control at once, and in Debug runs with an Activity state, the
    /// state's own on its clock.
    private func gameControlInput() -> ActivityModel.Input {
        ActivityModel.Input.window(ogs: ogs, nav: nav, place: ActivityModel.Place(showing: game))
    }

    private func opponentName(in game: Game?) -> String? {
        guard let game, let color = game.userStoneColor else { return nil }
        return game.currentPlayer(with: color.opponentColor())?.username
    }

    /// What the control knows of this Game Detail: whether its route has the
    /// picker, Zen, and the game-over card's challenge, which
    /// `GameOverCardRule` picks for the game on screen among those the user
    /// received. The rule decides what the control and its popover lead
    /// with, never an action.
    private func gameControlContext(allowsPicker: Bool) -> ActivityModel.GameControlContext {
        ActivityModel.GameControlContext(
            allowsPicker: allowsPicker, isZen: zenMode,
            cardChallengeID: GameOverCardRule.challengeID(for: game, among: ogs.challengesReceived)
        )
    }

    /// The game-over card's challenger, whose tile the control draws and
    /// VoiceOver names. The card keeps its state while its popover is open
    /// after its challenge has gone, as after Reject, so the challenger the
    /// state last had stays.
    private func cardChallenger(for slot: GameControlSlot?) -> OGSUser? {
        guard let challengeID = slot?.cardChallengeID else { return nil }
        return ogs.challengesReceived.first { $0.id == challengeID }?.challenger ?? cardChallengers[challengeID]
    }

    /// The control's state and its slot. The state comes from the model in
    /// this pass, from `ogs` and the game this layout observes, so the bar's
    /// first frame already has it, an in-place switch has the new game's at
    /// once, and so does the game's end. No geometry takes part: the form
    /// follows the placement and the window's class, and the frame follows
    /// the form, the state and the class.
    private func gameControlBarState() -> GameControlBarState {
        let placement = arrangement.activeGamesPlacement(compact: compact, navigationBarHidden: navigationBarHidden)
        let input = gameControlInput()
        let allowsPicker = gameControl.switchRule.allowsPicker
        let value = GameControlSlot(input, context: gameControlContext(allowsPicker: allowsPicker))
        let isOpen = gameControl.isPopoverOpen
        // While its popover is open the control stays, in its last state,
        // even when nothing waits any more.
        let drawn = value ?? (isOpen ? lastShownGameControl : nil)
        let form = GameControlForm(placement, isCatalyst: Self.isCatalyst, windowClass: gameControl.windowClass)
        let otherGame = drawn?.gameID.flatMap { id in ogs.liveGames.first { $0.ogsID == id } }
        let challenger = cardChallenger(for: drawn)
        let name = opponentName(in: otherGame) ?? challenger?.username ?? ""
        let isPresented = gameControl.presentation(placement)
        let popover = gameControl.popover(drawn?.cardChallengeID)
        let view: AnyView
        let isShown: Bool
        var nativeBadge: GameControlNativeItem.Badge?
        if form.isNative {
            let keepsPlace = GameControlNativeItem.keepsPlace(at: placement, isSignedIn: ogs.isLoggedIn)
            let item = GameControlNativeItem(drawn, allowsPicker: allowsPicker, keepsPlace: keepsPlace)
            nativeBadge = item?.badge
            isShown = (item != nil && !zenMode) || isOpen
            let spoken = GameControlAccessibility(drawn ?? .inbox(count: 0), form: form, allowsPicker: allowsPicker,
                                                  name: name)
            view = AnyView(GameControlNativeButton(
                item: item ?? GameControlNativeItem(icon: .inbox, badge: .none), label: spoken.label,
                hint: spoken.hint, isPresented: isPresented, popover: popover, openPopover: gameControl.openPopover,
                popoverAppeared: { nativeGameControlIdentity.popoverAppeared() },
                popoverDisappeared: { nativeGameControlIdentity.popoverDisappeared() }
            ).id(nativeGameControlIdentity.id(showing: item?.badge, isPopoverOpen: isOpen)))
        } else {
            isShown = (drawn != nil && !zenMode) || isOpen
            let model = GameControlItemModel(
                slot: drawn ?? .base(plusN: 0), windowClass: gameControl.windowClass,
                modeCount: showsConditionalMoves ? 3 : 2, sizeCategory: UIContentSizeCategory(dynamicTypeSize),
                allowsPicker: allowsPicker, game: otherGame, challenger: challenger, show: gameControl.show,
                openPopover: gameControl.openPopover
            )
            view = form == .bottomBar
                ? AnyView(GameControlBottomBarItem(model: model, isPresented: isPresented, popover: popover))
                : AnyView(GameControlTopBarItem(model: model, isPresented: isPresented, popover: popover))
        }
        let zen = gameControlZen(value, game: otherGame, name: name, allowsPicker: allowsPicker)
        return GameControlBarState(
            value: value, slot: GameActiveGamesSlot(placement: placement, isShown: isShown, view: view),
            zen: zen.item, zenCircle: zen.circle,
            nativeBadge: nativeBadge, deadlines: gameControlDeadlinePlan(input, value: value), now: input.now
        )
    }

    /// Zen's control: in Zen the model gives only another live game on your
    /// move, which a tap shows. Before a native Exit it is a bar item, the
    /// top-bar chip or the Mac's or the rail's native icon with a badge of 1;
    /// where Exit is drawn in the content, the content draws it as the circle.
    private func gameControlZen(_ value: GameControlSlot?, game other: Game?, name: String,
                                allowsPicker: Bool) -> (item: GameControlZenItem, circle: GameControlItemModel?) {
        guard zenMode, let value, let gameID = value.gameID, let other else { return (.hidden, nil) }
        let model = GameControlItemModel(
            slot: value, windowClass: gameControl.windowClass, modeCount: 2,
            sizeCategory: UIContentSizeCategory(dynamicTypeSize), allowsPicker: allowsPicker,
            game: other, challenger: nil, show: gameControl.show, openPopover: {}, role: .zen
        )
        if exitsZenFromContent { return (.hidden, model) }
        // Where the chip and Exit would reach over the board, the content
        // draws the circle in the board's column instead; with no room even
        // for the circle, Zen shows no control.
        switch gameControl.zenCorner {
        case .circle?, .besideExitAlone?: return (.hidden, model)
        case .noRoom?: return (.hidden, nil)
        case .barChip?, nil: break
        }
        let form = gameControl.zenForm
        guard form.isNative, let item = GameControlNativeItem(value, allowsPicker: allowsPicker) else {
            return (GameControlZenItem(isShown: true, view: AnyView(GameControlZenTopBarItem(model: model))), nil)
        }
        let spoken = GameControlAccessibility(value, form: form, isZen: true, allowsPicker: allowsPicker, name: name)
        let show = gameControl.show
        let button = GameControlZenNativeButton(item: item, label: spoken.label, hint: spoken.hint) { show(gameID) }
        return (GameControlZenItem(isShown: true, view: AnyView(button)), nil)
    }

    /// When time alone can change the control's state: at the latest
    /// started game's end, and each second while two or more other live
    /// games are on the user's move or a started game leads.
    private func gameControlDeadlinePlan(_ input: ActivityModel.Input,
                                         value: GameControlSlot?) -> GameControlDeadlines.Plan {
        let shownID = ActivityModel.Place(showing: game).gameID
        let othersOnYourMove = input.liveGames.filter { $0.id != shownID && $0.isYourMove }.count
        var startedLeads = false
        if case .gameStarted? = value { startedLeads = true }
        let leadEnds = input.startedGames.values.max().map { $0 + ActivityModel.startedLeadDuration }
        let ticks = !ActivityListSource.isClockFrozen && (othersOnYourMove >= 2 || startedLeads)
        return GameControlDeadlines.Plan(leadEnds: leadEnds, ticksEachSecond: ticks)
    }

    private func gameControlChanged(_ value: GameControlSlot?) {
        if let value { lastShownGameControl = value }
        if let challengeID = value?.cardChallengeID,
           let challenger = ogs.challengesReceived.first(where: { $0.id == challengeID })?.challenger {
            cardChallengers[challengeID] = challenger
        }
    }

    /// "Game started with CedarWave", once per game in this window, when a
    /// control on screen first shows a live game that started elsewhere.
    private func announceStartedGame(_ gameID: Int) {
        guard let name = opponentName(in: ogs.liveGames.first(where: { $0.ogsID == gameID })),
              nav.startedGamesRecorder.claimAnnouncement(for: gameID) else { return }
        nav.announce(AppAnnouncement(.gameStarted(gameID), audience: .frontmostWindow,
                                     speech: GameControlAccessibility.gameStarted(with: name)))
    }

    /// Compact landscape: the control, then the modes and the utilities, at the top.
    @ToolbarContentBuilder private func compactLandscapeControlItems(_ slot: GameActiveGamesSlot) -> some ToolbarContent {
        GameActiveGamesSlotItems(slot: slot)
        ToolbarItemGroup(placement: .topBarTrailing) { modeButtons }
        ToolbarItemGroup(placement: .topBarTrailing) { utilityButtons }
    }

    /// Zen's bar where Exit is a bar item: another live game on your move,
    /// then Exit. Independent conditions, as in principalItems.
    @ToolbarContentBuilder private func zenItems(_ zen: GameControlZenItem) -> some ToolbarContent {
        if zen.isShown {
            ToolbarItem(placement: .topBarTrailing) { zen.view }
        }
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
    }

    /// Wide windows and the Mac: modes, the control and utilities at the top.
    @ToolbarContentBuilder private func wideControlItems(_ slot: GameActiveGamesSlot) -> some ToolbarContent {
        // Wide windows keep the modes and the control at the top.
        GameVerticalToolbarGroup(placement: .topBarTrailing) {
            modeButtons
        }
        GameActiveGamesSlotItems(slot: slot)
        ToolbarItemGroup(placement: .topBarTrailing) {
            utilityButtons
        }
    }

    func body(content: Content) -> some View {
        // One read of the window's state for the control, in the pass that
        // draws the bar, so the control is there from the bar's first frame.
        let control = gameControlBarState()
        return content
            // SwiftUI also places custom principal content in its title
            // slot. Remove only an unused slot, preserving clocks, the
            // connection status and player identity when they occupy it.
            .toolbar(removing: isVerticalToolbar || principalItem == .none ? .title : nil)
            .environment(\.compactGameModesInToolbar, !zenMode)
            // Where Exit is drawn in the content, Zen's circle beside it.
            .environment(\.gameControlZen, control.zenCircle)
            .toolbar {
                if zenMode {
                    zenItems(control.zen)
                } else {
                    principalItems
                    controlItems(control.slot)
                }
            }
            .toolbar { iPadSidebarItems }
            .modifier(GameToolbarCompression())
            .modifier(GameControlUpdates(
                value: control.value, nativeBadge: control.nativeBadge, deadlines: control.deadlines,
                now: control.now, isOnScreen: gameControl.isOnScreen,
                holdsNativeIdentity: nativeGameControlIdentity.holds(isPopoverOpen: gameControl.isPopoverOpen),
                onValue: gameControlChanged, onStartedGame: announceStartedGame, onNativeBadge: { badge in
                    nativeGameControlIdentity.follow(badge, isPopoverOpen: gameControl.isPopoverOpen)
                },
                onDeadlines: { gameControlDeadlines.follow($0, now: $1) }
            ))
            #if DEBUG && MAIN_APP
            .modifier(GameControlFirstStateRecorder(
                gameID: game.ogsID, shown: control.slot.isShown ? control.value : nil,
                recorded: $gameControlFirstState
            ))
            .modifier(GameControlCycleHook())
            #endif
    }
}

/// Our own chrome where a hidden navigation bar leaves its corner: Exit Zen,
/// the Zen circle and its countdown, and the Duo sidebar button.
struct GameChromeButtonSurface<SurfaceShape: Shape>: ViewModifier {
    var shape: SurfaceShape

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

extension GameChromeButtonSurface where SurfaceShape == Circle {
    init() {
        self.init(shape: Circle())
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
    @Environment(\.surroundTheme) private var theme

    // Selected matches the native selected toggles beside it (Analyze): a
    // solid accent capsule with a white glyph, or a black one in dark mode.
    private var iconColor: Color {
        if isSelected { return colorScheme == .dark ? .black : .white }
        if #available(iOS 26.0, macCatalyst 26.0, *) { return .primary }
        return theme.usesCustomDetailTint ? theme.foreground : .accentColor
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

/// The window's connection status in the title slot, where no clock is in
/// play and neither Chat nor Analyze is open: a filled indigo capsule.
/// Reconnecting… (Connecting… before the window's first connection), then
/// Can’t reach OGS once the window's source gives up waiting (at once with
/// no network), with Retry where both fit and the words alone where they
/// don't. VoiceOver reads the words as one element, and Retry as its own
/// button. It never says Connected: the slot goes back to what it held
/// once the outage ends.
private struct GameConnectionStatusCapsule: View {
    @ObservedObject var connection: ConnectionStatusSource
    /// The window's socket, which tells a first attempt from a reconnect.
    let socket: OGSWebsocketStatus

    private var words: Text {
        let words = connection.status.gameCapsuleWords(hasConnected: connection.hasConnected, socket: socket)
        return Text(verbatim: ActivityBarWords.status(words ?? .reconnecting))
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if connection.status.offersRetry {
                capsule(offersRetry: true)
            }
            capsule(offersRetry: false)
        }
    }

    private func capsule(offersRetry: Bool) -> some View {
        HStack(spacing: 8) {
            words
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(offersRetry ? 1 : 0.7)
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameConnectionStatus)
            if offersRetry {
                Button { connection.retry() } label: {
                    Text("Retry")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(.systemIndigo))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(.white, in: Capsule())
                        // The bar's height, beyond the capsule's 32 pt.
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameConnectionStatusRetry)
            }
        }
        .fixedSize(horizontal: offersRetry, vertical: false)
        .foregroundStyle(.white)
        .padding(.horizontal, offersRetry ? 4 : 14)
        .padding(.leading, offersRetry ? 10 : 0)
        .frame(height: 32)
        .background(Color(.systemIndigo), in: Capsule())
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

/// When the in-game control's popover closes with its screen: when the
/// slot moves to another bar, since the old item goes with its popover and
/// SwiftUI may never report that popover closed, so the item that replaces
/// it starts closed and opens again; when the window's request goes or
/// another replaces it; and when the screen goes with the popover open, so
/// no request waits on a list no one can see. Apart from Game Detail's
/// body so Xcode 26.2 can type-check it.
private struct GameControlPopoverLifecycle: ViewModifier {
    let placement: GameActiveGamesPlacement
    let gameID: Int?
    let close: () -> Void
    let open: () -> Void
    let windowRequestChanged: (UUID?) -> Void
    @EnvironmentObject private var nav: NavigationService

    func body(content: Content) -> some View {
        content
            .onChange(of: placement) { _, _ in close() }
            .onChange(of: nav.main.activity?.sessionID) { _, sessionID in windowRequestChanged(sessionID) }
            .onDisappear(perform: close)
            #if DEBUG && MAIN_APP
            .onReceive(nav.debugGameControlPopoverRequests) { requested in
                if requested == gameID { open() }
            }
            .background { debugActivityRequest }
            #endif
    }

    #if DEBUG && MAIN_APP
    /// Hidden, for UI tests: the window's Activity request's source.
    @ViewBuilder private var debugActivityRequest: some View {
        if SurroundUITestContract.isEnabled {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: "Activity request"))
                .accessibilityValue(Text(verbatim: nav.main.activity.map { "\($0.source)" } ?? "none"))
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.debugActivityRequest)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
    #endif
}

/// What the in-game control needs from its Game Detail: how a switch happens
/// on its route, its popover and the popover's content, and what a tap or a
/// hold does. The toolbar reads the control's state itself.
private struct GameControlHost {
    var switchRule: GameControlSwitch
    var windowClass: GameControlWindowClass?
    /// Zen's control where Exit is a bar item.
    var zenForm: GameControlForm
    /// In compact landscape, whether Zen's control is the chip before Exit
    /// or the circle the content draws in the board's column; nil elsewhere.
    var zenCorner: GameControlZenCorner?
    var isPopoverOpen: Bool
    /// The popover binding of the item at a placement.
    var presentation: (GameActiveGamesPlacement) -> Binding<Bool>
    /// The popover's content, which leads with the game-over card of the
    /// challenge passed in.
    var popover: (_ cardChallengeID: Int?) -> AnyView
    var openPopover: () -> Void
    /// Shows one of the user's live games by its id.
    var show: (Int) -> Void
    /// This Game Detail's visible registration exists: it is on screen, not
    /// kept by a stack under another screen or in another tab.
    var isOnScreen: Bool
}

/// The control's state in one pass of the toolbar.
private struct GameControlBarState {
    /// The model's state for the game on screen; nil where the slot hides.
    var value: GameControlSlot?
    var slot: GameActiveGamesSlot
    /// Zen's control before a native Exit.
    var zen: GameControlZenItem
    /// Zen's control where the content draws Exit, for the circle beside it.
    var zenCircle: GameControlItemModel?
    /// The native item's badge, on the rail and the Mac.
    var nativeBadge: GameControlNativeItem.Badge?
    var deadlines: GameControlDeadlines.Plan
    /// When the state was read, in seconds since 1970.
    var now: TimeInterval
}

/// What happens when the control's state changes, apart from the toolbar's
/// body so Xcode 26.2 can type-check both.
private struct GameControlUpdates: ViewModifier {
    let value: GameControlSlot?
    let nativeBadge: GameControlNativeItem.Badge?
    let deadlines: GameControlDeadlines.Plan
    let now: TimeInterval
    /// Game Detail is on screen. Only then is a started game announced
    /// (`GameControlOnScreen`) and are the deadlines followed.
    let isOnScreen: Bool
    /// The native item's popover is open or still on screen.
    let holdsNativeIdentity: Bool
    let onValue: (GameControlSlot?) -> Void
    let onStartedGame: (Int) -> Void
    let onNativeBadge: (GameControlNativeItem.Badge?) -> Void
    let onDeadlines: (GameControlDeadlines.Plan, TimeInterval) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: value, initial: true) { _, value in onValue(value) }
            // Keyed on the state and on being on screen, so a Game Detail
            // that comes back on screen announces a start the window has
            // not announced yet.
            .onChange(of: GameControlOnScreen.startedGameToAnnounce(value, isOnScreen: isOnScreen),
                      initial: true) { _, gameID in
                if let gameID { onStartedGame(gameID) }
            }
            .onChange(of: nativeBadge, initial: true) { _, badge in onNativeBadge(badge) }
            // A badge that changed while the popover was open or on screen
            // takes effect once the popover has gone.
            .onChange(of: holdsNativeIdentity) { _, holds in
                if !holds { onNativeBadge(nativeBadge) }
            }
            // Off screen no deadline, which stops the control's timer; back
            // on screen the deadlines again.
            .onChange(of: isOnScreen ? deadlines : GameControlDeadlines.Plan(), initial: true) { _, plan in
                onDeadlines(plan, now)
            }
    }
}

#if DEBUG && MAIN_APP
/// The control's state as it first drew for one game.
private struct GameControlFirstState: Equatable {
    var gameID: Int?
    var text: String
}

/// Hidden, for UI tests: the control's state as it first drew for the game
/// on screen, from the pass that first drew the bar for it, or "none".
private struct GameControlFirstStateRecorder: ViewModifier {
    private struct Shown: Equatable {
        var gameID: Int?
        var value: GameControlSlot?
    }

    let gameID: Int?
    let shown: GameControlSlot?
    @Binding var recorded: GameControlFirstState?

    func body(content: Content) -> some View {
        content
            .onChange(of: Shown(gameID: gameID, value: shown), initial: true) { _, current in
                guard recorded?.gameID != current.gameID else { return }
                recorded = GameControlFirstState(gameID: current.gameID,
                                                 text: GameControlSlot.testDescription(current.value))
            }
            .background {
                if SurroundUITestContract.isEnabled {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(Text(verbatim: "Game control first state"))
                        .accessibilityValue(Text(verbatim: recorded?.text ?? ""))
                        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameControlFirstState)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// The in-game control's state cycle (`GameControlCycleDriver`) steps when
/// this Game Detail's screen opens: here, outside the first state's record,
/// whose first value is the state the screen opened in, and inside the tab
/// bar's hide, so the step lands in the hide. Its content can leave and come
/// back while the screen stays, as when Back clears the game on iOS 18, so
/// the driver counts the screen, from `GameControlCycleScreen`.
private struct GameControlCycleHook: ViewModifier {
    @Environment(\.gameControlCycleScreen) private var screen

    @ViewBuilder func body(content: Content) -> some View {
        if SurroundUITestContract.gameControlDrivers.cycle != nil {
            content.onAppear {
                if let screen { GameControlCycleDriver.screenAppeared(screen) }
            }
        } else {
            content
        }
    }
}

/// Game Detail's screen for the state cycle: it names the screen for the
/// content's hook and steps the cycle when the screen leaves, outside the
/// content, which can leave and come back while the screen stays.
private struct GameControlCycleScreen: ViewModifier {
    let id: UUID

    @ViewBuilder func body(content: Content) -> some View {
        if SurroundUITestContract.gameControlDrivers.cycle != nil {
            content
                .environment(\.gameControlCycleScreen, id)
                .onDisappear { GameControlCycleDriver.screenLeft(id) }
        } else {
            content
        }
    }
}

private struct GameControlCycleScreenKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    fileprivate var gameControlCycleScreen: UUID? {
        get { self[GameControlCycleScreenKey.self] }
        set { self[GameControlCycleScreenKey.self] = newValue }
    }
}

/// The freeze control (`SurroundUITestContract.OwnGameFreezeControl`):
/// version 2.4's compact bottom bar, alone in the bar, whose item shows by
/// the height Game Detail has spare, as its reader measures it, with its
/// last decision kept by `onChange`. Only its flag brings it.
private struct OwnGameFreezeControlItem: ViewModifier {
    let control: SurroundUITestContract.OwnGameFreezeControl?
    /// Compact portrait outside Zen, where 2.4 had the bar.
    let isActive: Bool
    let spare: CGFloat
    @State private var wasShown = false

    @ViewBuilder func body(content: Content) -> some View {
        if let control {
            let shows = isActive && control.shows(spare: Double(spare), wasShown: wasShown)
            let _ = OwnGameFreezeControlLog.read(spare: spare, wasShown: wasShown, shows: shows,
                                                 isActive: isActive, control: control)
            content
                .toolbar {
                    if shows {
                        ToolbarItem(placement: .bottomBar) {
                            Text(verbatim: "2.4 bar")
                                .font(.footnote)
                        }
                    }
                }
                .onChange(of: shows, initial: true) { _, value in wasShown = value }
        } else {
            content
        }
    }
}

/// Logs what the freeze control reads, a pass at a time: every new reading
/// in the first 200 passes, then every thousandth pass, so a layout that
/// never ends still logs.
private enum OwnGameFreezeControlLog {
    private static let log = Logger(subsystem: "com.honganhkhoa.Surround", category: "FreezeControl")
    private static var passes = 0
    private static var lastReading: String?

    static func read(spare: CGFloat, wasShown: Bool, shows: Bool, isActive: Bool,
                     control: SurroundUITestContract.OwnGameFreezeControl) {
        passes += 1
        let band = control.loops(withSpareWithoutItem: Double(spare)) ? ", between low and high" : ""
        let reading = "spare \(String(format: "%.1f", Double(spare))) pt\(band), was shown \(wasShown), shows \(shows)"
        guard isActive, passes <= 200 ? reading != lastReading : passes.isMultiple(of: 1_000) else { return }
        lastReading = reading
        log.notice("FREEZE-CONTROL pass \(passes, privacy: .public): \(reading, privacy: .public); low \(control.low, privacy: .public), high \(control.high, privacy: .public)")
    }
}
#endif

/// What fills Game Detail's control slot: the in-game control's item for
/// its placement, and whether it shows.
private struct GameActiveGamesSlot {
    var placement: GameActiveGamesPlacement
    /// A state outside Zen, or the popover is open.
    var isShown: Bool
    var view: AnyView
}

/// Zen's control in the bar, before a native Exit, and whether it shows:
/// only for another live game on your move. One item in one place, so the
/// game's clock ticks inside it and nothing else in the bar moves.
private struct GameControlZenItem {
    var isShown: Bool
    var view: AnyView

    static var hidden: GameControlZenItem { GameControlZenItem(isShown: false, view: AnyView(EmptyView())) }
}

/// The control's slot at the place its arrangement gives it. Every
/// arrangement emits this one unit, so the slot changes here and in
/// `GameToolbarLayout.gameControlBarState()`, never in the arrangements.
private struct GameActiveGamesSlotItems: ToolbarContent {
    let slot: GameActiveGamesSlot

    var body: some ToolbarContent {
        // Duo's wide poses keep Active games in its own circle at the bottom
        // of the rail. The spacer stays without the slot, as it did before.
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
        if slot.placement == .railSeparated {
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.flexible, placement: .bottomBar)
            }
        }
        #endif
        // Independent conditions (one is true at most), as in principalItems.
        if slot.isShown && slot.placement.form == .rail {
            GameVerticalToolbarGroup(placement: .bottomBar) { slot.view }
        }
        if slot.isShown && slot.placement == .bottomBar {
            ToolbarItem(placement: .bottomBar) { slot.view }
        }
        if slot.isShown && slot.placement == .topBarBeforeModes {
            ToolbarItem(placement: .topBarTrailing) { slot.view }
        }
        if slot.isShown && slot.placement == .topBarAfterModes {
            GameVerticalToolbarGroup(placement: .topBarTrailing) { slot.view }
        }
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
    .environmentObject(GameChatSessionStore())
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
    .environmentObject(GameChatSessionStore())
}

#Preview("Regular landscape — Zen mode", traits: .fixedLayout(width: 960, height: 754)) {
    let fixture = gameDetailPreviewFixture()

    AppNavigationStack {
        GameDetailView(currentGame: .constant(fixture.games[0]), zenMode: true)
    }
    .environment(\.horizontalSizeClass, UserInterfaceSizeClass.regular)
    .environmentObject(fixture.ogs)
    .environmentObject(fixture.navigation)
    .environmentObject(GameChatSessionStore())
}

#Preview("Regular portrait — Active game", traits: .fixedLayout(width: 750, height: 1024)) {
    let fixture = gameDetailPreviewFixture()

    AppNavigationStack {
        GameDetailView(currentGame: .constant(fixture.games[0]))
    }
    .environment(\.horizontalSizeClass, UserInterfaceSizeClass.regular)
    .environmentObject(fixture.ogs)
    .environmentObject(fixture.navigation)
    .environmentObject(GameChatSessionStore())
}
#endif
