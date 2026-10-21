import SwiftUI

/// A curated look for Game Detail: its scene, its surfaces and the board.
/// `.standard` is Surround's ordinary appearance.
enum SurroundTheme: String, CaseIterable, Identifiable {
    case standard
    case nebulaPearl
    case rakedGarden

    var id: Self { self }

    /// The theme Game Detail shows. Themes are a Debug-only preview until
    /// they have a proper home, so other builds ignore a stored choice.
    static func current(storedID: String) -> SurroundTheme {
        #if DEBUG
        SurroundTheme(rawValue: storedID) ?? .standard
        #else
        .standard
        #endif
    }

    /// The temporary chooser's label; not localized until themes ship.
    var debugTitle: String {
        switch self {
        case .standard: "Surround"
        case .nebulaPearl: "Nebula & Pearl"
        case .rakedGarden: "Raked Garden"
        }
    }

    /// A scene theme fixes Game Detail's appearance; nil follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .standard: nil
        case .nebulaPearl: .dark
        case .rakedGarden: .light
        }
    }

    var board: BoardAppearance {
        switch self {
        case .standard:
            return .standard
        case .nebulaPearl:
            // Bright silver, as in the concept, readable over the lit board.
            let silver = Color(themeHex: 0xC9CFEA)
            return BoardAppearance(
                boardColor: Color(themeHex: 0x191C34),
                boardEdge: Color(themeHex: 0x8E97C8).opacity(0.3),
                boardTexture: NebulaPearlAssets.board,
                boardBevel: true,
                // The concept's board catches the scene's light from the upper
                // left. It lightens most of the surface, brightest in that
                // corner, which also sets the dark glass off as a shape.
                boardReflection: BoardReflection(color: Color(themeHex: 0x8E9BD8),
                                                 corner: 0.36, middle: 0.19, edge: 0.07, reach: 1.8,
                                                 dustDensity: 97, glintDensity: 1.9),
                gridLineScale: 1.2,
                stoneImages: NebulaPearlAssets.stones,
                gridColor: silver.opacity(0.92),
                coordinateColor: silver,
                // Compact drawn stones keep a dark amethyst face and a pale
                // violet boundary, so adjacent stones stay distinct. Image
                // stones carry their own reflected edge.
                black: StonePalette(
                    highlight: Color(themeHex: 0x9A78D2),
                    shade: Color(themeHex: 0x2A1650),
                    flat: Color(themeHex: 0x5F3F94),
                    outline: Color(themeHex: 0xC4B3E0).opacity(0.85),
                    rim: Color(themeHex: 0xB8A2E6).opacity(0.5),
                    lastMove: .white,
                    label: .white,
                    // Lighter than the stones, so territory stands out on indigo.
                    territory: Color(themeHex: 0x9C80FF)
                ),
                // Moon pearl: ivory with a lilac shade.
                white: StonePalette(
                    highlight: Color(themeHex: 0xFFFCF7),
                    shade: Color(themeHex: 0xC9B6D9),
                    flat: Color(themeHex: 0xEEE4DC),
                    lastMove: Color(themeHex: 0x3A2785),
                    label: Color(themeHex: 0x241D33)
                ),
                emptyPointMarker: Color(themeHex: 0xE6E9F7),
                markOutline: .gray,
                dameColor: Color(themeHex: 0xF3C7A4),
                highlightColor: Color(themeHex: 0x6FD6FF),
                // Mint, coral and cyan stay clear of the violet stones and,
                // a little heavier, of the bright silver grid.
                crosshair: .init(valid: Color(themeHex: 0x7FE3A8),
                                 invalid: Color(themeHex: 0xFF7B72),
                                 removal: Color(themeHex: 0x6FD6FF)),
                crosshairWidth: 1.5,
                removeMark: Color(themeHex: 0xFF7B72),
                restoreMark: Color(themeHex: 0x7FE3A8),
                removalMarkCasing: Color(themeHex: 0x0B0E22).opacity(0.8),
                // Dead glass is nearly the board's own color at half opacity.
                removedStoneOutline: silver.opacity(0.75)
            )
        case .rakedGarden:
            return BoardAppearance(
                boardColor: Color(themeHex: 0xE5DCCA),
                boardEdge: Color(themeHex: 0x8D8069).opacity(0.45),
                boardTexture: RakedGardenAssets.board,
                // A scratched grid on quiet sand; curved rake grooves and
                // deeper relief belong to the surrounding garden scene.
                gridLineScale: 1.6,
                gridStyle: .ragged,
                stoneImages: RakedGardenAssets.stones,
                // Match the canopy's down-left cast and the stones' key light.
                stoneLightDirection: .upperRight,
                gridColor: Color(themeHex: 0x736550),
                coordinateColor: Color(themeHex: 0x62533F),
                black: StonePalette(
                    highlight: Color(themeHex: 0x6A485A),
                    shade: Color(themeHex: 0x241C27),
                    flat: Color(themeHex: 0x382736),
                    outline: Color(themeHex: 0x241C27),
                    rim: Color(themeHex: 0x8D6976).opacity(0.5),
                    lastMove: Color(themeHex: 0xFFF9E8),
                    label: Color(themeHex: 0xFFF9E8)
                ),
                white: StonePalette(
                    highlight: Color(themeHex: 0xE8F2B6),
                    shade: Color(themeHex: 0x7C9842),
                    flat: Color(themeHex: 0xBCD273),
                    // Jade stays pale: its contour, not stronger saturation,
                    // separates it from sand at thumbnail sizes.
                    outline: Color(themeHex: 0x52632D),
                    rim: Color(themeHex: 0x52632D).opacity(0.7),
                    lastMove: Color(themeHex: 0x293419),
                    label: Color(themeHex: 0x293419),
                    territory: Color(themeHex: 0x6C7D35)
                ),
                emptyPointMarker: Color(themeHex: 0x382736),
                markOutline: Color(themeHex: 0x62533F),
                dameColor: Color(themeHex: 0x8D4E2C),
                highlightColor: Color(themeHex: 0x285E6E),
                crosshair: .init(valid: Color(themeHex: 0x28684D),
                                 invalid: Color(themeHex: 0x9B3437),
                                 removal: Color(themeHex: 0x285E6E)),
                crosshairWidth: 1.5,
                removeMark: Color(themeHex: 0x9B3437),
                restoreMark: Color(themeHex: 0x28684D),
                removalMarkCasing: Color(themeHex: 0xFFF9E8),
                removedStoneOutline: Color(themeHex: 0x62533F)
            )
        }
    }
}

/// Rendered with Blender; the scene scripts and asset notes are kept with the
/// workspace's design sources, outside this repository.
private enum NebulaPearlAssets {
    static let stones: StoneImages? = {
        let black = (0..<4).compactMap { UIImage(named: "NebulaPearlGlass\($0)") }
        let white = (0..<4).compactMap { UIImage(named: "NebulaPearlPearl\($0)") }
        guard !black.isEmpty, !white.isEmpty else { return nil }
        return StoneImages(black: black, white: white)
    }()

    /// Fine midnight-indigo slate, repeated every 320 pt: large enough not
    /// to show a pattern on an iPad board.
    static let board = UIImage(named: "NebulaPearlBoard").map { BoardTexture(image: $0, tileSize: 320) }
}

private enum RakedGardenAssets {
    static let stones: StoneImages? = {
        let black = (0..<4).compactMap { UIImage(named: "RakedGardenBasalt\($0)") }
        let white = (0..<4).compactMap { UIImage(named: "RakedGardenJade\($0)") }
        guard black.count == 4, white.count == 4 else { return nil }
        return StoneImages(black: black, white: white)
    }()

    /// One quiet sand field scales with the board; fine grain naturally
    /// softens in thumbnails while the native grid retains its contrast.
    static let board = UIImage(named: "RakedGardenBoard").map { BoardTexture(image: $0, mapping: .board) }
}

// MARK: - Game Detail surfaces

extension SurroundTheme {
    /// The page behind the game when the theme has no scene.
    var pageBackground: Color {
        switch self {
        case .standard: Color(uiColor: .systemGroupedBackground)
        case .nebulaPearl: Color(themeHex: 0x070A1C)
        case .rakedGarden: Color(themeHex: 0xEFEAE1)
        }
    }

    var panel: Color {
        switch self {
        case .standard: Color(uiColor: .secondarySystemGroupedBackground)
        case .nebulaPearl: Color(themeHex: 0x141938)
        case .rakedGarden: Color(themeHex: 0xF7F4EE)
        }
    }

    var foreground: Color {
        switch self {
        case .standard, .nebulaPearl: .primary
        case .rakedGarden: Color(themeHex: 0x2B2621)
        }
    }

    var panelBorder: Color {
        switch self {
        case .standard:
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 56 / 255, green: 56 / 255, blue: 58 / 255, alpha: 1)
                    : UIColor.black.withAlphaComponent(0.12)
            })
        case .nebulaPearl: Color.white.opacity(0.14)
        case .rakedGarden: Color(themeHex: 0x89785D).opacity(0.28)
        }
    }

    /// Whether Game Detail draws a scene instead of a plain page.
    var hasScene: Bool { self != .standard }

    /// Clocks, player chips and the main action are tinted Liquid Glass,
    /// letting the scene show through; other themes keep solid surfaces.
    var usesGlassControls: Bool { self != .standard }

    /// Tinted Liquid Glass for a player's clock, in the stone's color.
    /// Light stones use a strong tint to preserve their material color over
    /// the scene; dark ones retain enough pigment for light clock text.
    func clockGlassTint(_ color: StoneColor) -> Color {
        switch self {
        case .standard: .clear
        case .nebulaPearl:
            color == .black ? Color(themeHex: 0x3B2585).opacity(0.47) : Color(themeHex: 0xFBF1EC).opacity(0.95)
        case .rakedGarden:
            color == .black ? Color(themeHex: 0x4B263D).opacity(0.84) : Color(themeHex: 0xD6E9A3).opacity(0.72)
        }
    }

    /// Tinted Liquid Glass for a player chip, using the same stone family
    /// as its clock.
    func identityGlassTint(_ color: StoneColor) -> Color {
        switch self {
        case .standard: .clear
        case .nebulaPearl:
            color == .black ? Color(themeHex: 0x241858).opacity(0.51) : Color(themeHex: 0xF8EFEB).opacity(0.93)
        case .rakedGarden:
            color == .black ? Color(themeHex: 0x4B263D).opacity(0.86) : Color(themeHex: 0xE6F2C4).opacity(0.78)
        }
    }

    /// The main action's tint; nil keeps the app's accent.
    var actionTint: Color? {
        switch self {
        case .standard: nil
        // Deep violet: white text at about 8:1, and close to the violet clock.
        case .nebulaPearl: Color(themeHex: 0x4E36B0)
        case .rakedGarden: Color(themeHex: 0xA2402A)
        }
    }

    /// Glass pigment is independent of the opaque accessibility fill.
    var actionGlassTint: Color? {
        self == .rakedGarden ? actionTint?.opacity(0.88) : actionTint
    }


    /// Main-channel chat bubbles.
    var chatBubble: Color {
        switch self {
        case .standard: Color(.systemGray4)
        case .nebulaPearl: Color(themeHex: 0x2C2F5E)
        case .rakedGarden: Color(themeHex: 0xDEDCC1)
        }
    }
}

// MARK: - Selection and status marks

extension SurroundTheme {
    /// The selected move in the Analyze tree and its board thumbnails.
    var selectionMark: Color {
        switch self {
        case .standard: Color(uiColor: .systemTeal)
        // The chat highlight's cyan: the one cool accent among the violets.
        case .nebulaPearl: Color(themeHex: 0x6FD6FF)
        case .rakedGarden: Color(themeHex: 0x28684D)
        }
    }

    /// Analyze tree moves that belong to the conditional-move plan; nil
    /// keeps the app's conditional-move color.
    var conditionalMark: Color? {
        switch self {
        case .standard: nil
        case .nebulaPearl: Color(themeHex: 0xE0A86A)
        case .rakedGarden: Color(themeHex: 0x9B532B)
        }
    }

    /// A contrasting keyline between a tree mark and its stone; nil lets
    /// the mark touch the stone.
    var treeMarkKeyline: Color? {
        switch self {
        case .standard: nil
        case .nebulaPearl: Color(themeHex: 0x0B0E22)
        case .rakedGarden: Color(themeHex: 0xFFF9E8)
        }
    }

    /// The Analyze tree's guide at every fifth move.
    func treeGuide(scheme: ColorScheme) -> Color {
        switch self {
        case .standard: Color(scheme == .dark ? .systemGray6 : .systemGray4)
        case .nebulaPearl: Color(themeHex: 0xC9CFEA).opacity(0.2)
        case .rakedGarden: Color(themeHex: 0x736550).opacity(0.25)
        }
    }

    /// Active games where it is the user's turn; the clock's turn color.
    var userTurnMark: Color {
        switch self {
        case .standard: Color(uiColor: .systemTeal)
        case .nebulaPearl: Color(themeHex: 0xC8B8FF)
        case .rakedGarden: Color(themeHex: 0x28684D)
        }
    }

    /// A halo around the user's-turn mark, as around the running clock; nil
    /// draws the mark flat.
    var userTurnGlow: Color? {
        switch self {
        case .standard: nil
        case .nebulaPearl: Color(themeHex: 0xB7A4FF).opacity(0.85)
        case .rakedGarden: nil
        }
    }

    /// Active games in stone removal.
    var stoneRemovalMark: Color {
        switch self {
        case .standard: Color(uiColor: .systemOrange)
        case .nebulaPearl: Color(themeHex: 0xF2B279)
        case .rakedGarden: Color(themeHex: 0x9B532B)
        }
    }

    /// Active games waiting on the opponent.
    func idleGameMark(scheme: ColorScheme) -> Color {
        switch self {
        case .standard: Color(uiColor: scheme == .dark ? .systemGray5 : .systemBackground)
        case .nebulaPearl: Color(themeHex: 0x2A2F55)
        case .rakedGarden: Color(themeHex: 0xD7CEBA)
        }
    }
}

// MARK: - Clock cards and player identities

extension SurroundTheme {
    func clockSurfaceStops(_ color: StoneColor, scheme: ColorScheme) -> [Gradient.Stop] {
        switch self {
        case .standard:
            if color == .black {
                if scheme == .dark {
                    return [.init(color: Color(white: 125 / 255), location: 0),
                            .init(color: Color(white: 51 / 255), location: 0.5),
                            .init(color: Color(white: 12 / 255), location: 1)]
                }
                return [.init(color: Color(red: 125 / 255, green: 126 / 255, blue: 125 / 255), location: 0),
                        .init(color: Color(white: 14 / 255), location: 1)]
            }
            if scheme == .dark {
                return [.init(color: Color(white: 136 / 255), location: 0),
                        .init(color: Color(white: 239 / 255), location: 0.5),
                        .init(color: Color(white: 239 / 255), location: 1)]
            }
            return [.init(color: Color(white: 204 / 255), location: 0),
                    .init(color: Color(white: 238 / 255), location: 0.3),
                    .init(color: .white, location: 1)]
        case .nebulaPearl:
            if color == .black {
                return [.init(color: Color(themeHex: 0x6447BE), location: 0),
                        .init(color: Color(themeHex: 0x2E1C68), location: 0.55),
                        .init(color: Color(themeHex: 0x160D36), location: 1)]
            }
            return [.init(color: Color(themeHex: 0xD9CCE6), location: 0),
                    .init(color: Color(themeHex: 0xF1EAEE), location: 0.35),
                    .init(color: Color(themeHex: 0xF8F1E8), location: 1)]
        case .rakedGarden:
            if color == .black {
                return [.init(color: Color(themeHex: 0x6A3F5C), location: 0),
                        .init(color: Color(themeHex: 0x22101C), location: 1)]
            }
            return [.init(color: Color(themeHex: 0xBFDD7A), location: 0),
                    .init(color: Color(themeHex: 0xE6F2C4), location: 1)]
        }
    }

    /// The clock surface under Reduce Transparency or Increase Contrast.
    func clockSolidSurface(_ color: StoneColor) -> Color {
        switch self {
        case .standard: color == .black ? Color(white: 0.06) : Color(white: 0.98)
        case .nebulaPearl: color == .black ? Color(themeHex: 0x1C1240) : Color(themeHex: 0xF6F0EA)
        case .rakedGarden: color == .black ? Color(themeHex: 0x3A1E31) : Color(themeHex: 0xD6E9A3)
        }
    }

    func clockForeground(_ color: StoneColor, scheme: ColorScheme) -> Color {
        switch self {
        case .standard: color == .black ? .white : Color(white: scheme == .dark ? 19 / 255 : 32 / 255)
        case .nebulaPearl: color == .black ? .white : Color(themeHex: 0x241D33)
        case .rakedGarden: color == .black ? Color(themeHex: 0xFFF9E8) : Color(themeHex: 0x2B2621)
        }
    }

    /// Icons and highlighted text on a clock outside sudden death.
    func clockAccent(_ color: StoneColor) -> Color {
        switch self {
        case .standard: Color(uiColor: .systemIndigo)
        case .nebulaPearl: color == .black ? Color(themeHex: 0xCDBEFF) : Color(themeHex: 0x5B3FC4)
        case .rakedGarden: color == .black ? Color(themeHex: 0xF3CE7A) : Color(themeHex: 0x8A3421)
        }
    }

    /// The running clock's outline outside sudden death.
    func turnOutline(scheme: ColorScheme) -> Color {
        switch self {
        case .standard:
            scheme == .dark
                ? Color(red: 125 / 255, green: 122 / 255, blue: 1)
                : Color(red: 88 / 255, green: 86 / 255, blue: 214 / 255)
        case .nebulaPearl: Color(themeHex: 0xC8B8FF)
        // The lantern glow stays bright; the sharper outline needs a deeper
        // amber to remain visible against the pale jade clock.
        case .rakedGarden: Color(themeHex: 0x9B6423)
        }
    }

    /// The running clock's halo outside sudden death.
    var turnGlow: Color {
        switch self {
        case .standard: Color(uiColor: .systemIndigo)
        case .nebulaPearl: Color(themeHex: 0xB7A4FF)
        case .rakedGarden: Color(themeHex: 0xD6A03C)
        }
    }

    /// The status capsule (Your move, reconnecting) behind white text.
    var statusBadge: Color {
        switch self {
        case .standard: Color(uiColor: .systemIndigo)
        case .nebulaPearl: Color(themeHex: 0x6A4FD6)
        // Maple carries the badge's white text at over 6:1. Lantern amber
        // remains the turn glow; it is too light for white status text.
        case .rakedGarden: Color(themeHex: 0xA2402A)
        }
    }

    func identityChipColors(_ color: StoneColor) -> [Color] {
        switch self {
        case .standard:
            color == .black
                ? [Color(red: 61 / 255, green: 62 / 255, blue: 61 / 255), Color(white: 18 / 255)]
                : [Color(white: 236 / 255), .white]
        case .nebulaPearl:
            color == .black
                ? [Color(themeHex: 0x3E2B78), Color(themeHex: 0x160F33)]
                : [Color(themeHex: 0xE6DCEB), Color(themeHex: 0xF8F3EC)]
        case .rakedGarden:
            color == .black
                ? [Color(themeHex: 0x6A3F5C), Color(themeHex: 0x22101C)]
                : [Color(themeHex: 0xBFDD7A), Color(themeHex: 0xE6F2C4)]
        }
    }

    func identityChipBorder(_ color: StoneColor) -> Color {
        switch self {
        case .standard: color == .black ? Color.white.opacity(0.15) : Color.black.opacity(0.12)
        case .nebulaPearl: color == .black ? Color.white.opacity(0.18) : Color.white.opacity(0.5)
        case .rakedGarden:
            color == .black
                ? Color(themeHex: 0xD6B8BD).opacity(0.3)
                : Color(themeHex: 0x52632D).opacity(0.4)
        }
    }

    func identityForeground(_ color: StoneColor) -> Color {
        switch self {
        case .standard: color == .black ? .white : Color(white: 32 / 255)
        case .nebulaPearl: color == .black ? .white : Color(themeHex: 0x241D33)
        case .rakedGarden: color == .black ? Color(themeHex: 0xFFF9E8) : Color(themeHex: 0x2B2621)
        }
    }

    func identitySecondary(_ color: StoneColor) -> Color {
        switch self {
        case .standard:
            color == .black ? Color(white: 174 / 255) : Color(red: 108 / 255, green: 108 / 255, blue: 112 / 255)
        case .nebulaPearl:
            color == .black ? Color(themeHex: 0xC9BEEB) : Color(themeHex: 0x5E5670)
        case .rakedGarden:
            color == .black ? Color(themeHex: 0xE0D1D5) : Color(themeHex: 0x505A39)
        }
    }

    /// Garden keeps OGS's role hues while adapting their lightness to the
    /// basalt or jade chip. Other themes retain their existing role colors.
    func identityRoleColor(for player: OGSUser, on color: StoneColor) -> Color? {
        guard self == .rakedGarden else { return nil }
        let darkSurface = color == .black
        // Match OGSUser.uiColor's priority, including lightweight ui_class
        // payloads: moderator/admin, professional, supporter, then bot.
        if player.isOGSModerator || player.isOGSAdmin {
            return Color(themeHex: darkSurface ? 0xDDC4F4 : 0x633889)
        }
        if player.isOGSProfessional {
            return Color(themeHex: darkSurface ? 0xBCE6B3 : 0x245925)
        }
        if player.isOGSSupporter {
            return Color(themeHex: darkSurface ? 0xF3D69A : 0x854416)
        }
        if player.isBot == true || player.uiClass?.contains("bot") == true {
            return identitySecondary(color)
        }
        return Color(themeHex: darkSurface ? 0xB5D7FF : 0x20518B)
    }
}

// MARK: - Environment

private struct SurroundThemeKey: EnvironmentKey {
    static let defaultValue = SurroundTheme.standard
}

extension EnvironmentValues {
    var surroundTheme: SurroundTheme {
        get { self[SurroundThemeKey.self] }
        set { self[SurroundThemeKey.self] = newValue }
    }
}

extension View {
    /// Applies a theme to Game Detail: its surfaces, board and appearance.
    /// `ownsWindow` lets a screen that is leaving keep its look without
    /// holding the window's appearance.
    func gameDetailTheme(_ theme: SurroundTheme, ownsWindow: Bool = true) -> some View {
        modifier(GameDetailThemeModifier(theme: theme, ownsWindow: ownsWindow))
    }
}

private struct GameDetailThemeModifier: ViewModifier {
    let theme: SurroundTheme
    let ownsWindow: Bool
    @Environment(\.colorScheme) private var systemColorScheme

    func body(content: Content) -> some View {
        // The window's override also reaches the status bar and the bars,
        // which belong to controllers outside this view; the environment
        // covers the first frame, before it applies. Neither changes the
        // view's identity between themes.
        content
            .environment(\.surroundTheme, theme)
            .environment(\.boardAppearance, theme.board)
            .environment(\.colorScheme, theme.colorScheme ?? systemColorScheme)
            .foregroundColor(theme == .rakedGarden ? theme.foreground : nil)
            .toolbarColorScheme(theme.colorScheme, for: .navigationBar, .bottomBar)
            .background(WindowInterfaceStyle(colorScheme: ownsWindow ? theme.colorScheme : nil))
    }
}

/// Fixes the window's light or dark appearance while this view is in it, and
/// restores the window's own setting afterwards. A preferred color scheme
/// cannot do this from a screen hosted in a tab's own controller.
private struct WindowInterfaceStyle: UIViewRepresentable {
    let colorScheme: ColorScheme?

    func makeUIView(context: Context) -> StyleView {
        let view = StyleView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: StyleView, context: Context) {
        view.style = switch colorScheme {
        case .dark: .dark
        case .light: .light
        default: .unspecified
        }
    }

    static func dismantleUIView(_ view: StyleView, coordinator: ()) {
        view.restore()
    }

    final class StyleView: UIView {
        var style = UIUserInterfaceStyle.unspecified {
            didSet { if style != oldValue { apply() } }
        }
        private weak var styledWindow: UIWindow?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        private func apply() {
            if let styledWindow, styledWindow !== window || style == .unspecified {
                WindowStyleRequests.remove(self, from: styledWindow)
                self.styledWindow = nil
            }
            guard style != .unspecified, let window else { return }
            WindowStyleRequests.set(style, for: self, in: window)
            styledWindow = window
        }

        func restore() {
            if let styledWindow { WindowStyleRequests.remove(self, from: styledWindow) }
            styledWindow = nil
        }
    }
}

/// Every themed screen in a window holds a request, so one leaving (a game
/// pushed over another) cannot restore the window under the other.
@MainActor
private enum WindowStyleRequests {
    private struct Entry {
        let original: UIUserInterfaceStyle
        var requests: [ObjectIdentifier: UIUserInterfaceStyle] = [:]
    }

    private static var entries = [ObjectIdentifier: Entry]()

    static func set(_ style: UIUserInterfaceStyle, for requester: AnyObject, in window: UIWindow) {
        let key = ObjectIdentifier(window)
        var entry = entries[key] ?? Entry(original: window.overrideUserInterfaceStyle)
        entry.requests[ObjectIdentifier(requester)] = style
        entries[key] = entry
        window.overrideUserInterfaceStyle = style
    }

    static func remove(_ requester: AnyObject, from window: UIWindow) {
        let key = ObjectIdentifier(window)
        guard var entry = entries[key] else { return }
        entry.requests[ObjectIdentifier(requester)] = nil
        if let remaining = entry.requests.values.first {
            entries[key] = entry
            window.overrideUserInterfaceStyle = remaining
        } else {
            entries[key] = nil
            window.overrideUserInterfaceStyle = entry.original
        }
    }
}

/// A Game Detail surface that follows the current theme wherever a
/// `ShapeStyle` is accepted.
struct GameDetailSurfaceStyle: ShapeStyle {
    enum Role {
        case page, panel, panelBorder
    }

    let role: Role

    func resolve(in environment: EnvironmentValues) -> Color {
        let theme = environment.surroundTheme
        return switch role {
        case .page: theme.pageBackground
        case .panel: theme.panel
        case .panelBorder: theme.panelBorder
        }
    }
}

// MARK: - Scene

/// The page behind Game Detail: the theme's scene, or its plain color.
struct GameDetailBackdrop: View {
    @Environment(\.surroundTheme) private var theme

    var body: some View {
        switch theme {
        case .standard:
            theme.pageBackground
        case .nebulaPearl:
            NebulaPearlScene()
        case .rakedGarden:
            RakedGardenScene()
        }
    }
}

/// Foliage sits above its cast shadow and the game, independently of panels.
/// System chrome and presented sheets remain above this scene layer.
struct GameDetailSceneForeground: View {
    @Environment(\.surroundTheme) private var theme
    var hasTopEdgeClocks = false

    var body: some View {
        Group {
            if theme == .rakedGarden {
                GeometryReader { geometry in
                    RakedGardenForegroundContent(size: geometry.size,
                                                 hasTopEdgeClocks: hasTopEdgeClocks).equatable()
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct RakedGardenForegroundContent: View, Equatable {
    let size: CGSize
    let hasTopEdgeClocks: Bool

    private var usesLegacyChrome: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }

    var body: some View {
        let layout = RakedGardenSceneLayout(size: size, usesLegacyChrome: usesLegacyChrome,
                                           hasTopEdgeClocks: hasTopEdgeClocks)
        ZStack {
            RakedGardenMapleShadow(size: size).equatable()
            Image("RakedGardenMaple")
                .resizable()
                .frame(width: layout.maple.width, height: layout.maple.height)
                .position(x: layout.maple.midX, y: layout.maple.midY)
                // Fade the foliage beneath system chrome without putting
                // a pale scrim over the game content below it.
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(stops: [
                            .init(color: .white.opacity(usesLegacyChrome ? 0.08 : 0.18), location: 0),
                            .init(color: .white.opacity(usesLegacyChrome ? 0.08 : 0.74),
                                  location: usesLegacyChrome ? 0.62 : 0.5),
                            .init(color: .white, location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                        .frame(height: layout.topFadeHeight)
                        Color.white
                    }
                }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .clipped()
    }
}

/// The upper-right canopy casts farther down and left than its visible
/// foliage. Its bounded projection reaches the upper board on a phone.
struct RakedGardenShadowLayout: Equatable {
    let size: CGSize
    let canopy: CGRect
    let blurRadius: CGFloat

    init(size: CGSize) {
        let width = size.width.isFinite ? max(0, size.width) : 0
        let height = size.height.isFinite ? max(0, size.height) : 0
        self.size = CGSize(width: width, height: height)
        let shortSide = min(width, height)
        let side = min(840, shortSide * 1.3)
        canopy = CGRect(x: width - side * 0.86, y: shortSide * 0.08,
                        width: side, height: side)
        blurRadius = min(5, shortSide * 0.008)
    }
}

/// Blur only this static alpha silhouette, never the game beneath it.
/// The size-only leaf stays unchanged during moves, scrolling and ticks.
private struct RakedGardenMapleShadow: View, Equatable {
    let size: CGSize

    var body: some View {
        let layout = RakedGardenShadowLayout(size: size)
        Image("RakedGardenMaple")
            .renderingMode(.template)
            .resizable()
            .foregroundStyle(Color(themeHex: 0x342F29))
            .frame(width: layout.canopy.width, height: layout.canopy.height)
            .blur(radius: layout.blurRadius)
            .opacity(0.18)
            .position(x: layout.canopy.midX, y: layout.canopy.midY)
            .frame(width: layout.size.width, height: layout.size.height)
            .clipped()
    }
}

/// The scene's accents follow its outer edges, independently of the sand
/// crop. Continuous sizing avoids an artwork swap during window resizing.
struct RakedGardenSceneLayout: Equatable {
    let size: CGSize
    let rocks: CGRect
    let upperRocks: CGRect
    let maple: CGRect
    let topFadeHeight: CGFloat
    let bottomFadeHeight: CGFloat

    init(size: CGSize, usesLegacyChrome: Bool = false, hasTopEdgeClocks: Bool = false) {
        let width = size.width.isFinite ? max(0, size.width) : 0
        let height = size.height.isFinite ? max(0, size.height) : 0
        self.size = CGSize(width: width, height: height)
        let shortSide = min(width, height)
        // Shallow phone windows need less vertical decoration. This changes
        // smoothly with the aspect ratio, with no portrait/landscape branch.
        let wide = min(1, max(0, width / max(1, height) - 1))
        let rockSide = min(440, shortSide * 0.62 * (1 - 0.2 * wide))
        let upperRockSide = min(240, shortSide * 0.46 * (1 - 0.2 * wide))
        let mapleSide = min(300, shortSide * 0.50 * (1 - 0.2 * wide))
        rocks = CGRect(x: -rockSide * 0.30, y: height - rockSide * 0.75,
                       width: rockSide, height: rockSide)
        upperRocks = CGRect(x: -upperRockSide * 0.30, y: -upperRockSide * 0.56,
                            width: upperRockSide, height: upperRockSide)
        // Real leaves may overlap a panel edge, but stop above clock digits.
        // Legacy phone clocks sit higher, below their shorter navigation bar.
        let mapleHeightLimit: CGFloat = usesLegacyChrome || hasTopEdgeClocks ? 100 : 160
        let mapleVisibleHeight = min(mapleSide * 0.84, mapleHeightLimit)
        maple = CGRect(x: width - mapleSide * 0.68, y: mapleVisibleHeight - mapleSide,
                       width: mapleSide, height: mapleSide)
        topFadeHeight = min(92, height * 0.16)
        bottomFadeHeight = min(96, height * 0.16)
    }
}

/// One garden across the whole Game Detail surface, including divided
/// layouts. The playable board keeps its separate quiet sand texture.
private struct RakedGardenScene: View {
    var body: some View {
        GeometryReader { geometry in
            RakedGardenSceneContent(size: geometry.size).equatable()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Only container resizing updates the composition; moves and clock ticks
/// do not reconstruct its fixed image layers.
private struct RakedGardenSceneContent: View, Equatable {
    let size: CGSize
    private static let sand = Color(themeHex: 0xEFEAE1)

    private var topFade: Gradient {
        if #available(iOS 26.0, *) {
            return Gradient(colors: [Self.sand.opacity(0.82), Self.sand.opacity(0.26), .clear])
        }
        // Earlier toolbars have no glass backing. Keep their icons on quiet
        // sand while preserving the foliage below the navigation controls.
        return Gradient(stops: [
            .init(color: Self.sand.opacity(0.92), location: 0),
            .init(color: Self.sand.opacity(0.92), location: 0.62),
            .init(color: .clear, location: 1)
        ])
    }

    private var bottomFade: Gradient {
        if #available(iOS 26.0, *) {
            return Gradient(colors: [.clear, Self.sand.opacity(0.24), Self.sand.opacity(0.78)])
        }
        return Gradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: Self.sand.opacity(0.90), location: 0.55),
            .init(color: Self.sand.opacity(0.94), location: 1)
        ])
    }

    var body: some View {
        let layout = RakedGardenSceneLayout(size: size)
        ZStack {
            Self.sand
            Image("RakedGardenSand")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: layout.size.width, height: layout.size.height)
                .clipped()
            Image("RakedGardenRocks")
                .resizable()
                .frame(width: layout.rocks.width, height: layout.rocks.height)
                .position(x: layout.rocks.midX, y: layout.rocks.midY)
            Image("RakedGardenRocks")
                .resizable()
                .frame(width: layout.upperRocks.width, height: layout.upperRocks.height)
                .position(x: layout.upperRocks.midX, y: layout.upperRocks.midY)
            // Pale support stays local to the chrome instead of washing
            // out the rock and foliage silhouettes across the whole scene.
            VStack(spacing: 0) {
                LinearGradient(gradient: topFade,
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: layout.topFadeHeight)
                Spacer(minLength: 0)
                LinearGradient(gradient: bottomFade,
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: layout.bottomFadeHeight)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .clipped()
    }
}

/// Nebula & Pearl's scene, composed from parts so the calm center stays
/// behind the board at any window shape: a square sky cropped to fill,
/// native stars, and a planet and rocks pinned to the corners.
private struct NebulaPearlScene: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let shortSide = min(size.width, size.height)
            let planetDiameter = min(max(shortSide * 0.28, 100), 280)
            ZStack {
                Color(themeHex: 0x070A1C)
                Image("NebulaPearlSky")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                ThemeStarField()
                planet(diameter: planetDiameter)
                    .position(x: size.width - planetDiameter * 0.22, y: planetDiameter * 0.24)
                ForEach(Self.fragments.indices, id: \.self) { index in
                    let fragment = Self.fragments[index]
                    let side = min(shortSide * fragment.size, 360 * fragment.size / 0.3)
                    Image("NebulaPearlFragment\(fragment.image)")
                        .resizable()
                        .frame(width: side, height: side)
                        .opacity(fragment.opacity)
                        .position(x: size.width * fragment.x, y: size.height * fragment.y)
                }
                // No text sits directly on the scene: the title and the
                // bottom controls get the ground fading out behind them.
                VStack(spacing: 0) {
                    LinearGradient(colors: [Color(themeHex: 0x070A1C).opacity(0.85), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 120)
                    Spacer(minLength: 0)
                    LinearGradient(colors: [.clear, Color(themeHex: 0x070A1C).opacity(0.7)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 110)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Fragments drifting around the edges, never one continuous ground:
    /// larger ones in the lower corners, small far ones fainter. Positions
    /// are fractions of the scene; sizes of its short side. Each image is
    /// used once and never rotated, which would turn its baked light.
    private struct Fragment {
        let image: Int
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: Double
    }

    private static let fragments: [Fragment] = [
        Fragment(image: 0, x: -0.02, y: 0.95, size: 0.3, opacity: 1),
        Fragment(image: 3, x: 0.2, y: 0.985, size: 0.12, opacity: 1),
        Fragment(image: 5, x: 0.07, y: 0.81, size: 0.065, opacity: 0.85),
        Fragment(image: 1, x: 1.03, y: 0.92, size: 0.25, opacity: 1),
        Fragment(image: 4, x: 0.84, y: 0.99, size: 0.1, opacity: 1),
        Fragment(image: 2, x: 0.03, y: 0.17, size: 0.085, opacity: 0.8),
        Fragment(image: 6, x: 0.15, y: 0.075, size: 0.04, opacity: 0.6),
        Fragment(image: 7, x: 0.975, y: 0.4, size: 0.06, opacity: 0.75),
        Fragment(image: 8, x: 0.02, y: 0.56, size: 0.045, opacity: 0.65),
    ]

    /// The disc, lit from the upper left like the stones, with a soft glow
    /// on that side only.
    private func planet(diameter: CGFloat) -> some View {
        Image("NebulaPearlPlanet")
            .resizable()
            .frame(width: diameter, height: diameter)
            .background {
                Circle()
                    .fill(RadialGradient(colors: [Color(themeHex: 0x9FB2FF).opacity(0.3), .clear],
                                         center: .center, startRadius: diameter * 0.45,
                                         endRadius: diameter * 0.62))
                    .frame(width: diameter * 1.3, height: diameter * 1.3)
                    .mask {
                        LinearGradient(colors: [.white, .clear], startPoint: .topLeading,
                                       endPoint: UnitPoint(x: 0.7, y: 0.7))
                    }
            }
    }
}

/// Fine stars on a fixed tile, so they stay put while the window resizes:
/// many faint points and a few brighter ones with a soft halo.
private struct ThemeStarField: View {
    private struct Star {
        let point: CGPoint
        let radius: CGFloat
        let opacity: Double
        let color: Color
        let halo: Bool
    }

    private static let tileSize: CGFloat = 512
    private static let stars: [Star] = {
        var state: UInt64 = 0x5EED_2026
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(state >> 33) / CGFloat(1 << 31)
        }
        let tints = [Color(themeHex: 0xF4F1FF), Color(themeHex: 0xDCE4FF), Color(themeHex: 0xEADCFF)]
        let faint = (0..<240).map { _ in
            Star(point: CGPoint(x: next() * tileSize, y: next() * tileSize),
                 radius: 0.25 + pow(next(), 4) * 0.6,
                 opacity: 0.2 + Double(next()) * 0.55,
                 color: tints[Int(next() * 2.999)], halo: false)
        }
        let bright = (0..<5).map { _ in
            Star(point: CGPoint(x: next() * tileSize, y: next() * tileSize),
                 radius: 0.7 + next() * 0.4,
                 opacity: 0.95,
                 color: tints[Int(next() * 2.999)], halo: true)
        }
        return faint + bright
    }()

    var body: some View {
        Canvas { context, size in
            let tile = Self.tileSize
            for column in 0..<Int((size.width / tile).rounded(.up)) {
                for row in 0..<Int((size.height / tile).rounded(.up)) {
                    let origin = CGPoint(x: CGFloat(column) * tile, y: CGFloat(row) * tile)
                    for star in Self.stars {
                        let center = CGPoint(x: origin.x + star.point.x, y: origin.y + star.point.y)
                        if star.halo {
                            let halo = star.radius * 5
                            context.fill(Path(ellipseIn: CGRect(x: center.x - halo, y: center.y - halo,
                                                                width: halo * 2, height: halo * 2)),
                                         with: .radialGradient(Gradient(colors: [star.color.opacity(0.35), .clear]),
                                                               center: center, startRadius: 0, endRadius: halo))
                        }
                        var starContext = context
                        starContext.opacity = star.opacity
                        starContext.fill(Path(ellipseIn: CGRect(x: center.x - star.radius, y: center.y - star.radius,
                                                                width: star.radius * 2, height: star.radius * 2)),
                                         with: .color(star.color))
                    }
                }
            }
        }
    }
}

extension Color {
    /// An sRGB color from a 0xRRGGBB literal, as the theme designs specify.
    init(themeHex value: UInt32) {
        self.init(.sRGB,
                  red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255,
                  opacity: 1)
    }
}
