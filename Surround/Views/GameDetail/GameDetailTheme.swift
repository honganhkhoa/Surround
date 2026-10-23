import SwiftUI

/// A curated look for Game Detail: its scene, its surfaces and the board.
/// `.standard` is Surround's ordinary appearance.
enum SurroundTheme: String, CaseIterable, Identifiable {
    case standard
    case nebulaPearl
    case rakedGarden
    case surroundStudio

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
        case .surroundStudio: "Surround Studio"
        }
    }

    /// Natural scenes and standard follow the system; Nebula stays dark.
    var colorScheme: ColorScheme? {
        switch self {
        case .standard, .rakedGarden, .surroundStudio: nil
        case .nebulaPearl: .dark
        }
    }

    /// Resolve image grading alongside the board palette. The image references
    /// stay cached, so an appearance change does not decode or regenerate art.
    func board(for scheme: ColorScheme) -> BoardAppearance {
        if self == .surroundStudio, scheme == .dark {
            var night = board
            night.boardColor = Color(themeHex: 0xA58A5A)
            // Compact boards use this solid pigment, without the detailed
            // texture, tint or bevel. Shared rendering retains the 14 pt cutoff.
            night.compactBoardColor = Color(themeHex: 0xA58A5A)
            night.boardEdge = Color(themeHex: 0xC6BA9C).opacity(0.65)
            night.boardTexture?.tint = Color(themeHex: 0xB2B6C1)
            // Keep slate neutral and shell ivory: the warm kaya and the
            // moonlit room must not give the stones a green-blue cast.
            night.stoneImages?.tint = Color(themeHex: 0xE4E5E6)
            night.gridColor = Color(themeHex: 0x30383C)
            night.coordinateColor = Color(themeHex: 0x171E22)
            night.black = StonePalette(
                highlight: Color(themeHex: 0x5C6265), shade: Color(themeHex: 0x151B1F),
                flat: Color(themeHex: 0x22282B), outline: Color(themeHex: 0x12171A),
                rim: Color(themeHex: 0x85929A).opacity(0.4),
                lastMove: Color(themeHex: 0xF4F0E6), label: Color(themeHex: 0xF4F0E6),
                territory: Color(themeHex: 0x181D20)
            )
            night.white = StonePalette(
                highlight: Color(themeHex: 0xEAE9E1), shade: Color(themeHex: 0xA9A596),
                flat: Color(themeHex: 0xDCDACF), outline: Color(themeHex: 0x30383C),
                rim: Color(themeHex: 0x566068).opacity(0.5),
                lastMove: Color(themeHex: 0x222C30), label: Color(themeHex: 0x222C30),
                territory: Color(themeHex: 0xFFF9ED)
            )
            night.emptyPointMarker = Color(themeHex: 0x171E22)
            night.markOutline = Color(themeHex: 0x30383C)
            night.dameColor = Color(themeHex: 0x50351D)
            night.highlightColor = Color(themeHex: 0x193D4A)
            night.highlightCasing = Color(themeHex: 0xF4F0E6)
            night.crosshair = .init(valid: Color(themeHex: 0x253D31),
                                   invalid: Color(themeHex: 0x5E2828),
                                   removal: Color(themeHex: 0x193D4A))
            night.removeMark = Color(themeHex: 0x5E2828)
            night.restoreMark = Color(themeHex: 0x253D31)
            night.removalMarkCasing = Color(themeHex: 0xF4F0E6)
            night.removedStoneOutline = Color(themeHex: 0x30383C)
            return night
        }
        guard self == .rakedGarden, scheme == .dark else { return board }
        var night = board
        night.boardColor = Color(themeHex: 0x7F8586)
        night.boardEdge = Color(themeHex: 0xA2B2AD).opacity(0.45)
        night.boardTexture?.tint = Color(themeHex: 0x909FB0)
        night.stoneImages?.tint = Color(themeHex: 0xDEE7F2)
        night.gridColor = Color(themeHex: 0x26322F)
        night.coordinateColor = Color(themeHex: 0x111B21)
        night.black = StonePalette(
            highlight: Color(themeHex: 0x5C4256), shade: Color(themeHex: 0x171620),
            flat: Color(themeHex: 0x30232F), outline: Color(themeHex: 0x171620),
            rim: Color(themeHex: 0xA991A5).opacity(0.5),
            lastMove: Color(themeHex: 0xF3EFDF), label: Color(themeHex: 0xF3EFDF),
            territory: Color(themeHex: 0x211B24)
        )
        night.white = StonePalette(
            highlight: Color(themeHex: 0xDCE7AD), shade: Color(themeHex: 0x6C863E),
            flat: Color(themeHex: 0xAEC46B), outline: Color(themeHex: 0x23311E),
            rim: Color(themeHex: 0x23311E).opacity(0.7),
            lastMove: Color(themeHex: 0x182612), label: Color(themeHex: 0x182612),
            territory: Color(themeHex: 0xF0F3B4)
        )
        night.emptyPointMarker = Color(themeHex: 0x111B21)
        night.markOutline = Color(themeHex: 0x152328)
        night.dameColor = Color(themeHex: 0x3C2710)
        night.highlightColor = Color(themeHex: 0x102A3A)
        night.highlightCasing = Color(themeHex: 0xF2F0DF)
        night.crosshair = .init(valid: Color(themeHex: 0x102F23),
                               invalid: Color(themeHex: 0x4C1119),
                               removal: Color(themeHex: 0x102A3A))
        night.removeMark = Color(themeHex: 0x4C1119)
        night.restoreMark = Color(themeHex: 0x102F23)
        night.removalMarkCasing = Color(themeHex: 0xF2F0DF)
        night.removedStoneOutline = Color(themeHex: 0x152328)
        return night
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
                // Small boards are solid: a midnight close to the lit surface,
                // dark enough for violet stones to stand out by their fill.
                compactBoardColor: Color(themeHex: 0x1E2240),
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
                    // Small stones are a lighter violet with a dark keyline, so
                    // a white last-move ring is not mistaken for a light rim.
                    flat: Color(themeHex: 0x7C5EC4),
                    outline: Color(themeHex: 0x141731),
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
                    outline: Color(themeHex: 0x141731),
                    lastMove: Color(themeHex: 0x3A2785),
                    label: Color(themeHex: 0x241D33)
                ),
                emptyPointMarker: Color(themeHex: 0xE6E9F7),
                markOutline: .gray,
                dameColor: Color(themeHex: 0xF3C7A4),
                highlightColor: Color(themeHex: 0x6FD6FF),
                // The cyan disappears on pearl without a dark edge.
                highlightCasing: Color(themeHex: 0x141731),
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
                // Dark teal needs a light edge over basalt stones.
                highlightCasing: Color(themeHex: 0xFFF9E8),
                crosshair: .init(valid: Color(themeHex: 0x28684D),
                                 invalid: Color(themeHex: 0x9B3437),
                                 removal: Color(themeHex: 0x285E6E)),
                crosshairWidth: 1.5,
                removeMark: Color(themeHex: 0x9B3437),
                restoreMark: Color(themeHex: 0x28684D),
                removalMarkCasing: Color(themeHex: 0xFFF9E8),
                removedStoneOutline: Color(themeHex: 0x62533F)
            )
        case .surroundStudio:
            return BoardAppearance(
                boardColor: Color(themeHex: 0xE3AF69),
                boardEdge: Color(themeHex: 0x79522F).opacity(0.65),
                boardTexture: SurroundStudioAssets.board,
                boardBevel: true,
                // The kaya grain stays quiet; exact charcoal lines and all
                // game marks are drawn above it by the shared native board.
                gridLineScale: 1.2,
                stoneImages: SurroundStudioAssets.stones,
                stoneLightDirection: .upperLeft,
                gridColor: Color(themeHex: 0x3E382E),
                coordinateColor: Color(themeHex: 0x4B3D2C),
                black: StonePalette(
                    highlight: Color(themeHex: 0x6C7070),
                    shade: Color(themeHex: 0x1D2223),
                    flat: Color(themeHex: 0x282D2E),
                    outline: Color(themeHex: 0x1C2021),
                    rim: Color(themeHex: 0x7C8280).opacity(0.4),
                    lastMove: Color(themeHex: 0xFFF9ED),
                    label: Color(themeHex: 0xFFF9ED)
                ),
                white: StonePalette(
                    highlight: Color(themeHex: 0xFFFDF5),
                    shade: Color(themeHex: 0xD7CDBA),
                    flat: Color(themeHex: 0xF4EDDE),
                    outline: Color(themeHex: 0x6B5C45),
                    rim: Color(themeHex: 0x776B58).opacity(0.5),
                    lastMove: Color(themeHex: 0x343B38),
                    label: Color(themeHex: 0x303631),
                    // A darker warm mark remains distinct from kaya where
                    // a clamshell-colored territory square would disappear.
                    territory: Color(themeHex: 0x736044)
                ),
                emptyPointMarker: Color(themeHex: 0x282D2E),
                markOutline: Color(themeHex: 0x64543B),
                dameColor: Color(themeHex: 0x80511F),
                highlightColor: Color(themeHex: 0x2A5C68),
                // Dark teal needs a light edge over slate stones.
                highlightCasing: Color(themeHex: 0xFFF9ED),
                crosshair: .init(valid: Color(themeHex: 0x3D634B),
                                 invalid: Color(themeHex: 0x963C32),
                                 removal: Color(themeHex: 0x2A5C68)),
                crosshairWidth: 1.5,
                removeMark: Color(themeHex: 0x963C32),
                restoreMark: Color(themeHex: 0x3D634B),
                removalMarkCasing: Color(themeHex: 0xFFF9ED),
                removedStoneOutline: Color(themeHex: 0x64543B)
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

private enum SurroundStudioAssets {
    static let stones: StoneImages? = {
        let black = (0..<4).compactMap { UIImage(named: "SurroundStudioSlate\($0)") }
        let white = (0..<4).compactMap { UIImage(named: "SurroundStudioClamshell\($0)") }
        guard black.count == 4, white.count == 4 else { return nil }
        return StoneImages(black: black, white: white)
    }()

    /// One continuous kaya surface; the grain follows the board at every size.
    static let board = UIImage(named: "SurroundStudioBoard").map { BoardTexture(image: $0, mapping: .board) }
}

/// Static providers retain value identity through clock ticks and resizing.
/// Light values are the accepted daytime design; only Dark Mode resolves
/// the cooler night pigment. UIKit supplies the traits at render time.
private enum RakedGardenColors {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }

    static let page = adaptive(0xEFEAE1, 0x0E191F)
    static let panel = adaptive(0xF7F4EE, 0x17272D)
    static let foreground = adaptive(0x2B2621, 0xE7E9DE)
    static let panelBorder = adaptive(0x89785D, 0x8EAAA0)
    static let blackGlass = adaptive(0x4B263D, 0x2B2534)
    static let whiteGlass = adaptive(0xD6E9A3, 0xA4B68E)
    static let maple = adaptive(0xA2402A, 0x8F4436)
    static let chatBubble = adaptive(0xDEDCC1, 0x273A3F)
    static let selection = adaptive(0x28684D, 0xA7D3B7)
    static let conditional = adaptive(0x9B532B, 0xE5BB76)
    static let cream = adaptive(0xFFF9E8, 0xE9E8E0)
    static let keyline = adaptive(0xFFF9E8, 0x14232A)
    static let treeGuide = adaptive(0x736550, 0x9DADAC)
    static let idle = adaptive(0xD7CEBA, 0x2A3B40)
    static let blackSurfaceTop = adaptive(0x6A3F5C, 0x3D3044)
    static let blackSurfaceBottom = adaptive(0x22101C, 0x171621)
    static let whiteSurfaceTop = adaptive(0xBFDD7A, 0x96AA82)
    static let whiteSurfaceBottom = adaptive(0xE6F2C4, 0xB2C498)
    static let blackSolid = adaptive(0x3A1E31, 0x24202D)
    static let whiteForeground = adaptive(0x2B2621, 0x14241C)
    static let blackAccent = adaptive(0xF3CE7A, 0xEACB8B)
    static let whiteAccent = adaptive(0x8A3421, 0x4C2C1A)
    static let turnOutline = adaptive(0x9B6423, 0xD6A03C)
    static let turnGlow = adaptive(0xD6A03C, 0xE3BE70)
    static let blackBorder = adaptive(0xD6B8BD, 0xAF9DB8)
    static let whiteBorder = adaptive(0x52632D, 0x3B5137)
    static let blackSecondary = adaptive(0xE0D1D5, 0xD4CBD7)
    static let whiteSecondary = adaptive(0x505A39, 0x273923)
    static let darkModerator = adaptive(0xDDC4F4, 0xDDC4F4)
    static let lightModerator = adaptive(0x633889, 0x442557)
    static let darkProfessional = adaptive(0xBCE6B3, 0xBCE6B3)
    static let lightProfessional = adaptive(0x245925, 0x163B23)
    static let darkSupporter = adaptive(0xF3D69A, 0xF3D69A)
    static let lightSupporter = adaptive(0x854416, 0x593012)
    static let darkOrdinary = adaptive(0xB5D7FF, 0xB5D7FF)
    static let lightOrdinary = adaptive(0x20518B, 0x123752)
}

/// Day pigments remain exact; static trait providers resolve the studio's
/// cool charcoal and subdued ivory surfaces without recreating image assets.
private enum SurroundStudioColors {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }

    static let page = adaptive(0xE8DDC7, 0x121B24)
    static let panel = adaptive(0xF7F2E8, 0x1C2932)
    static let foreground = adaptive(0x303631, 0xE7E7DD)
    static let panelBorder = adaptive(0x78684F, 0x9BA7A8)
    static let blackGlass = adaptive(0x303735, 0x252D35)
    static let whiteGlass = adaptive(0xF3EBDD, 0xCECEC3)
    static let whiteIdentityGlass = adaptive(0xF7F0E2, 0xD5D4C8)
    static let action = adaptive(0x3D634B, 0x3E6659)
    static let chatBubble = adaptive(0xDDDCCB, 0x2D3B43)
    static let selection = adaptive(0x3D634B, 0xB4CFBC)
    static let conditional = adaptive(0x8A531D, 0xE4BD82)
    static let cream = adaptive(0xFFF9ED, 0xF0EEE5)
    static let keyline = adaptive(0xFFF9ED, 0x17222B)
    static let treeGuide = adaptive(0x78684F, 0xA7AAA1)
    static let idle = adaptive(0xD8CEBB, 0x303E47)
    static let blackSurfaceTop = adaptive(0x3E4745, 0x343F47)
    static let blackSurfaceBottom = adaptive(0x202624, 0x171F27)
    static let whiteSurfaceTop = adaptive(0xE5DCCA, 0xBDBFB7)
    static let whiteSurfaceBottom = adaptive(0xFFF9ED, 0xD8D8CE)
    static let blackSolid = adaptive(0x282F2C, 0x222D34)
    static let whiteForeground = adaptive(0x303631, 0x222C30)
    static let blackAccent = adaptive(0xC6D5BD, 0xD1DABB)
    static let whiteAccent = adaptive(0x3D634B, 0x294839)
    static let turnOutline = adaptive(0x688360, 0xA9C7AC)
    static let turnGlow = adaptive(0xA0B78F, 0xA7C3B1)
    static let blackBorder = adaptive(0xB7BDAF, 0x9AA7AC)
    static let whiteBorder = adaptive(0x78684F, 0x566064)
    static let blackSecondary = adaptive(0xD8D8CB, 0xCFD4D0)
    static let whiteSecondary = adaptive(0x5B6155, 0x3B4444)
    static let darkModerator = adaptive(0xDDC4F4, 0xDDC4F4)
    static let lightModerator = adaptive(0x633889, 0x4E2D67)
    static let darkProfessional = adaptive(0xBCE6B3, 0xBCE6B3)
    static let lightProfessional = adaptive(0x245925, 0x1E472C)
    static let darkSupporter = adaptive(0xF3D69A, 0xF3D69A)
    static let lightSupporter = adaptive(0x854416, 0x633818)
    static let darkOrdinary = adaptive(0xB5D7FF, 0xB5D7FF)
    static let lightOrdinary = adaptive(0x20518B, 0x1C3D62)
}

// MARK: - Game Detail surfaces

extension SurroundTheme {
    /// The page behind the game when the theme has no scene.
    var pageBackground: Color {
        switch self {
        case .standard: Color(uiColor: .systemGroupedBackground)
        case .nebulaPearl: Color(themeHex: 0x070A1C)
        case .rakedGarden: RakedGardenColors.page
        case .surroundStudio: SurroundStudioColors.page
        }
    }

    var panel: Color {
        switch self {
        case .standard: Color(uiColor: .secondarySystemGroupedBackground)
        case .nebulaPearl: Color(themeHex: 0x141938)
        case .rakedGarden: RakedGardenColors.panel
        case .surroundStudio: SurroundStudioColors.panel
        }
    }

    var foreground: Color {
        switch self {
        case .standard, .nebulaPearl: .primary
        case .rakedGarden: RakedGardenColors.foreground
        case .surroundStudio: SurroundStudioColors.foreground
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
        case .rakedGarden: RakedGardenColors.panelBorder.opacity(0.28)
        case .surroundStudio: SurroundStudioColors.panelBorder.opacity(0.28)
        }
    }

    /// Whether Game Detail draws a scene instead of a plain page.
    var hasScene: Bool { self != .standard }

    /// Clocks, player chips and the main action are tinted Liquid Glass,
    /// letting the scene show through; other themes keep solid surfaces.
    var usesGlassControls: Bool { self != .standard }

    /// The natural scenes use their own foregrounds, translucent pigment
    /// on older systems, and opaque controls under Increase Contrast.
    var usesLightSceneSurfaces: Bool { self == .rakedGarden || self == .surroundStudio }

    /// Tinted Liquid Glass for a player's clock, in the stone's color.
    /// Light stones use a strong tint to preserve their material color over
    /// the scene; dark ones retain enough pigment for light clock text.
    func clockGlassTint(_ color: StoneColor) -> Color {
        switch self {
        case .standard: .clear
        case .nebulaPearl:
            color == .black ? Color(themeHex: 0x3B2585).opacity(0.47) : Color(themeHex: 0xFBF1EC).opacity(0.95)
        case .rakedGarden:
            color == .black ? RakedGardenColors.blackGlass.opacity(0.84) : RakedGardenColors.whiteGlass.opacity(0.72)
        case .surroundStudio:
            color == .black ? SurroundStudioColors.blackGlass.opacity(0.82) : SurroundStudioColors.whiteGlass.opacity(0.84)
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
            color == .black ? RakedGardenColors.blackGlass.opacity(0.86) : RakedGardenColors.whiteSurfaceBottom.opacity(0.78)
        case .surroundStudio:
            color == .black ? SurroundStudioColors.blackGlass.opacity(0.86) : SurroundStudioColors.whiteIdentityGlass.opacity(0.90)
        }
    }

    /// The main action's tint; nil keeps the app's accent.
    var actionTint: Color? {
        switch self {
        case .standard: nil
        // Deep violet: white text at about 8:1, and close to the violet clock.
        case .nebulaPearl: Color(themeHex: 0x4E36B0)
        case .rakedGarden: RakedGardenColors.maple
        case .surroundStudio: SurroundStudioColors.action
        }
    }

    /// Glass pigment is independent of the opaque accessibility fill.
    var actionGlassTint: Color? {
        switch self {
        case .surroundStudio: actionTint?.opacity(0.86)
        case .rakedGarden: actionTint?.opacity(0.88)
        default: actionTint
        }
    }


    /// Main-channel chat bubbles.
    var chatBubble: Color {
        switch self {
        case .standard: Color(.systemGray4)
        case .nebulaPearl: Color(themeHex: 0x2C2F5E)
        case .rakedGarden: RakedGardenColors.chatBubble
        case .surroundStudio: SurroundStudioColors.chatBubble
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
        case .rakedGarden: RakedGardenColors.selection
        case .surroundStudio: SurroundStudioColors.selection
        }
    }

    /// Analyze tree moves that belong to the conditional-move plan; nil
    /// keeps the app's conditional-move color.
    var conditionalMark: Color? {
        switch self {
        case .standard: nil
        case .nebulaPearl: Color(themeHex: 0xE0A86A)
        case .rakedGarden: RakedGardenColors.conditional
        case .surroundStudio: SurroundStudioColors.conditional
        }
    }

    /// A contrasting keyline between a tree mark and its stone; nil lets
    /// the mark touch the stone.
    var treeMarkKeyline: Color? {
        switch self {
        case .standard: nil
        case .nebulaPearl: Color(themeHex: 0x0B0E22)
        case .rakedGarden: RakedGardenColors.keyline
        case .surroundStudio: SurroundStudioColors.keyline
        }
    }

    /// The Analyze tree's guide at every fifth move.
    func treeGuide(scheme: ColorScheme) -> Color {
        switch self {
        case .standard: Color(scheme == .dark ? .systemGray6 : .systemGray4)
        case .nebulaPearl: Color(themeHex: 0xC9CFEA).opacity(0.2)
        case .rakedGarden: RakedGardenColors.treeGuide.opacity(0.25)
        case .surroundStudio: SurroundStudioColors.treeGuide.opacity(0.24)
        }
    }

    /// Active games where it is the user's turn; the clock's turn color.
    var userTurnMark: Color {
        switch self {
        case .standard: Color(uiColor: .systemTeal)
        case .nebulaPearl: Color(themeHex: 0xC8B8FF)
        case .rakedGarden: RakedGardenColors.selection
        case .surroundStudio: SurroundStudioColors.selection
        }
    }

    /// A halo around the user's-turn mark, as around the running clock; nil
    /// draws the mark flat.
    var userTurnGlow: Color? {
        switch self {
        case .standard: nil
        case .nebulaPearl: Color(themeHex: 0xB7A4FF).opacity(0.85)
        case .rakedGarden, .surroundStudio: nil
        }
    }

    /// Active games in stone removal.
    var stoneRemovalMark: Color {
        switch self {
        case .standard: Color(uiColor: .systemOrange)
        case .nebulaPearl: Color(themeHex: 0xF2B279)
        case .rakedGarden: RakedGardenColors.conditional
        case .surroundStudio: SurroundStudioColors.conditional
        }
    }

    /// Active games waiting on the opponent.
    func idleGameMark(scheme: ColorScheme) -> Color {
        switch self {
        case .standard: Color(uiColor: scheme == .dark ? .systemGray5 : .systemBackground)
        case .nebulaPearl: Color(themeHex: 0x2A2F55)
        case .rakedGarden: RakedGardenColors.idle
        case .surroundStudio: SurroundStudioColors.idle
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
                return [.init(color: RakedGardenColors.blackSurfaceTop, location: 0),
                        .init(color: RakedGardenColors.blackSurfaceBottom, location: 1)]
            }
            return [.init(color: RakedGardenColors.whiteSurfaceTop, location: 0),
                    .init(color: RakedGardenColors.whiteSurfaceBottom, location: 1)]
        case .surroundStudio:
            if color == .black {
                return [.init(color: SurroundStudioColors.blackSurfaceTop, location: 0),
                        .init(color: SurroundStudioColors.blackSurfaceBottom, location: 1)]
            }
            return [.init(color: SurroundStudioColors.whiteSurfaceTop, location: 0),
                    .init(color: SurroundStudioColors.whiteSurfaceBottom, location: 1)]
        }
    }

    /// The clock surface under Reduce Transparency or Increase Contrast.
    func clockSolidSurface(_ color: StoneColor) -> Color {
        switch self {
        case .standard: color == .black ? Color(white: 0.06) : Color(white: 0.98)
        case .nebulaPearl: color == .black ? Color(themeHex: 0x1C1240) : Color(themeHex: 0xF6F0EA)
        case .rakedGarden: color == .black ? RakedGardenColors.blackSolid : RakedGardenColors.whiteGlass
        case .surroundStudio: color == .black ? SurroundStudioColors.blackSolid : SurroundStudioColors.whiteGlass
        }
    }

    func clockForeground(_ color: StoneColor, scheme: ColorScheme) -> Color {
        switch self {
        case .standard: color == .black ? .white : Color(white: scheme == .dark ? 19 / 255 : 32 / 255)
        case .nebulaPearl: color == .black ? .white : Color(themeHex: 0x241D33)
        case .rakedGarden: color == .black ? RakedGardenColors.cream : RakedGardenColors.whiteForeground
        case .surroundStudio: color == .black ? SurroundStudioColors.cream : SurroundStudioColors.whiteForeground
        }
    }

    /// Icons and highlighted text on a clock outside sudden death.
    func clockAccent(_ color: StoneColor) -> Color {
        switch self {
        case .standard: Color(uiColor: .systemIndigo)
        case .nebulaPearl: color == .black ? Color(themeHex: 0xCDBEFF) : Color(themeHex: 0x5B3FC4)
        case .rakedGarden: color == .black ? RakedGardenColors.blackAccent : RakedGardenColors.whiteAccent
        case .surroundStudio: color == .black ? SurroundStudioColors.blackAccent : SurroundStudioColors.whiteAccent
        }
    }

    /// Keep the existing warning red on every daytime/other-theme clock.
    /// Pale night clocks need deeper red; dark clocks use brighter coral.
    func clockSuddenDeathAccent(_ color: StoneColor, scheme: ColorScheme) -> Color {
        if self == .rakedGarden, scheme == .dark {
            return Color(themeHex: color == .white ? 0x6B2024 : 0xFF8277)
        }
        if self == .surroundStudio, scheme == .dark {
            return Color(themeHex: color == .white ? 0x7D2D2D : 0xFF9787)
        }
        return color == .white ? Color(red: 0.75, green: 0.10, blue: 0.07)
            : Color(red: 1, green: 0.34, blue: 0.30)
    }

    /// The warning badge uses a solid pigment beneath its white text.
    func clockSuddenDeathBadge(scheme: ColorScheme) -> Color {
        if self == .surroundStudio, scheme == .dark {
            return Color(themeHex: 0x8B3434)
        }
        return .red
    }

    /// Scoring acceptance remains green, with a deeper pigment on night ivory.
    func clockAgreementAccent(_ color: StoneColor, scheme: ColorScheme) -> Color {
        if self == .surroundStudio, scheme == .dark, color == .white {
            return Color(themeHex: 0x244B2F)
        }
        return color == .black ? Color(red: 125 / 255, green: 210 / 255, blue: 141 / 255)
            : Color(red: 30 / 255, green: 122 / 255, blue: 52 / 255)
    }

    /// The auto-resign countdown and disconnected label share an amber accent.
    func clockDisconnectedAccent(_ color: StoneColor, scheme: ColorScheme) -> Color {
        if self == .surroundStudio, scheme == .dark, color == .white {
            return Color(themeHex: 0x6C3D15)
        }
        return color == .black ? Color(red: 1, green: 159 / 255, blue: 10 / 255)
            : Color(red: 160 / 255, green: 72 / 255, blue: 0)
    }

    /// Inline undo text sits directly on the player's clock, without a badge.
    func clockUndoAccent(_ color: StoneColor, scheme: ColorScheme) -> Color {
        if self == .surroundStudio, scheme == .dark {
            return Color(themeHex: color == .black ? 0xE8C186 : 0x6C3D15)
        }
        return Color(red: 196 / 255, green: 106 / 255, blue: 0)
    }

    /// The full undo badge needs its own darker amber beneath white text.
    func clockUndoBadge(scheme: ColorScheme) -> Color {
        if self == .surroundStudio, scheme == .dark {
            return Color(themeHex: 0x835122)
        }
        return Color(red: 196 / 255, green: 106 / 255, blue: 0)
    }

    /// The running clock's outline outside sudden death.
    func turnOutline(scheme: ColorScheme) -> Color {
        switch self {
        case .standard:
            scheme == .dark
                ? Color(red: 125 / 255, green: 122 / 255, blue: 1)
                : Color(red: 88 / 255, green: 86 / 255, blue: 214 / 255)
        case .nebulaPearl: Color(themeHex: 0xC8B8FF)
        // Daytime uses a deeper amber edge against pale jade; night uses
        // brighter lantern light against the surrounding dark garden.
        case .rakedGarden: RakedGardenColors.turnOutline
        case .surroundStudio: SurroundStudioColors.turnOutline
        }
    }

    /// The running clock's halo outside sudden death.
    var turnGlow: Color {
        switch self {
        case .standard: Color(uiColor: .systemIndigo)
        case .nebulaPearl: Color(themeHex: 0xB7A4FF)
        case .rakedGarden: RakedGardenColors.turnGlow
        case .surroundStudio: SurroundStudioColors.turnGlow
        }
    }

    /// The status capsule (Your move, reconnecting) behind white text.
    var statusBadge: Color {
        switch self {
        case .standard: Color(uiColor: .systemIndigo)
        case .nebulaPearl: Color(themeHex: 0x6A4FD6)
        // Maple carries the badge's white text at over 6:1. Lantern amber
        // remains the turn glow; it is too light for white status text.
        case .rakedGarden: RakedGardenColors.maple
        case .surroundStudio: SurroundStudioColors.action
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
                ? [RakedGardenColors.blackSurfaceTop, RakedGardenColors.blackSurfaceBottom]
                : [RakedGardenColors.whiteSurfaceTop, RakedGardenColors.whiteSurfaceBottom]
        case .surroundStudio:
            color == .black
                ? [SurroundStudioColors.blackSurfaceTop, SurroundStudioColors.blackSurfaceBottom]
                : [SurroundStudioColors.whiteSurfaceTop, SurroundStudioColors.whiteSurfaceBottom]
        }
    }

    func identityChipBorder(_ color: StoneColor) -> Color {
        switch self {
        case .standard: color == .black ? Color.white.opacity(0.15) : Color.black.opacity(0.12)
        case .nebulaPearl: color == .black ? Color.white.opacity(0.18) : Color.white.opacity(0.5)
        case .rakedGarden:
            color == .black
                ? RakedGardenColors.blackBorder.opacity(0.3)
                : RakedGardenColors.whiteBorder.opacity(0.4)
        case .surroundStudio:
            color == .black
                ? SurroundStudioColors.blackBorder.opacity(0.3)
                : SurroundStudioColors.whiteBorder.opacity(0.35)
        }
    }

    func identityForeground(_ color: StoneColor) -> Color {
        switch self {
        case .standard: color == .black ? .white : Color(white: 32 / 255)
        case .nebulaPearl: color == .black ? .white : Color(themeHex: 0x241D33)
        case .rakedGarden: color == .black ? RakedGardenColors.cream : RakedGardenColors.whiteForeground
        case .surroundStudio: color == .black ? SurroundStudioColors.cream : SurroundStudioColors.whiteForeground
        }
    }

    func identitySecondary(_ color: StoneColor) -> Color {
        switch self {
        case .standard:
            color == .black ? Color(white: 174 / 255) : Color(red: 108 / 255, green: 108 / 255, blue: 112 / 255)
        case .nebulaPearl:
            color == .black ? Color(themeHex: 0xC9BEEB) : Color(themeHex: 0x5E5670)
        case .rakedGarden:
            color == .black ? RakedGardenColors.blackSecondary : RakedGardenColors.whiteSecondary
        case .surroundStudio:
            color == .black ? SurroundStudioColors.blackSecondary : SurroundStudioColors.whiteSecondary
        }
    }

    /// The natural themes keep OGS's role hues while adapting their
    /// lightness to the dark or pale chip.
    func identityRoleColor(for player: OGSUser, on color: StoneColor) -> Color? {
        guard usesLightSceneSurfaces else { return nil }
        let darkSurface = color == .black
        if self == .rakedGarden {
            if player.isOGSModerator || player.isOGSAdmin {
                return darkSurface ? RakedGardenColors.darkModerator : RakedGardenColors.lightModerator
            }
            if player.isOGSProfessional {
                return darkSurface ? RakedGardenColors.darkProfessional : RakedGardenColors.lightProfessional
            }
            if player.isOGSSupporter {
                return darkSurface ? RakedGardenColors.darkSupporter : RakedGardenColors.lightSupporter
            }
            if player.isBot == true || player.uiClass?.contains("bot") == true {
                return identitySecondary(color)
            }
            return darkSurface ? RakedGardenColors.darkOrdinary : RakedGardenColors.lightOrdinary
        }
        // Match OGSUser.uiColor's priority, including lightweight ui_class
        // payloads: moderator/admin, professional, supporter, then bot.
        if player.isOGSModerator || player.isOGSAdmin {
            return darkSurface ? SurroundStudioColors.darkModerator : SurroundStudioColors.lightModerator
        }
        if player.isOGSProfessional {
            return darkSurface ? SurroundStudioColors.darkProfessional : SurroundStudioColors.lightProfessional
        }
        if player.isOGSSupporter {
            return darkSurface ? SurroundStudioColors.darkSupporter : SurroundStudioColors.lightSupporter
        }
        if player.isBot == true || player.uiClass?.contains("bot") == true {
            return identitySecondary(color)
        }
        return darkSurface ? SurroundStudioColors.darkOrdinary : SurroundStudioColors.lightOrdinary
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
            .environment(\.boardAppearance, theme.board(for: theme.colorScheme ?? systemColorScheme))
            .environment(\.colorScheme, theme.colorScheme ?? systemColorScheme)
            .foregroundColor(theme.usesLightSceneSurfaces ? theme.foreground : nil)
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch theme {
        case .standard:
            theme.pageBackground
        case .nebulaPearl:
            NebulaPearlScene()
        case .rakedGarden:
            RakedGardenScene(scheme: colorScheme)
        case .surroundStudio:
            SurroundStudioScene(scheme: colorScheme)
        }
    }
}

/// A single overhead room across Game Detail, including divided displays.
/// Architecture and the six-mat floor share one uniform image scale.
/// The board keeps its own square geometry and independent kaya surface.
private struct SurroundStudioScene: View {
    let scheme: ColorScheme

    var body: some View {
        GeometryReader { geometry in
            SurroundStudioSceneContent(size: geometry.size, scheme: scheme).equatable()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The room and its decorations depend only on the viewport. Opening a
/// panel never rearranges the room. Top-leading alignment retains timber.
private struct SurroundStudioSceneContent: View, Equatable {
    let size: CGSize
    let scheme: ColorScheme

    private var chrome: Color {
        Color(themeHex: scheme == .dark ? 0x121B24 : 0xE8DDC7)
    }

    private var usesLegacyChrome: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }

    /// Short landscape windows place the unbacked navigation title over
    /// the shoji rail. Keep a quiet plateau behind that band, blending the
    /// adjustment continuously away as the window becomes taller or square.
    private var shortWideChromeWeight: CGFloat {
        min(1, max(0, (size.width - size.height) / 160))
            * min(1, max(0, (600 - size.height) / 120))
    }

    private var topFadeHeight: CGFloat {
        let ordinaryHeight = min(110, size.height * 0.18)
        return ordinaryHeight + (max(100, ordinaryHeight) - ordinaryHeight) * shortWideChromeWeight
    }

    var body: some View {
        ZStack {
            chrome
            Image("SurroundStudioScene")
                .resizable()
                .aspectRatio(contentMode: .fill)
                // The same shoji light and mat seams become moonlit. Grade
                // the artwork only, keeping the kaya and native UI independent.
                .saturation(scheme == .dark ? 0.28 : 1)
                .colorMultiply(scheme == .dark ? Color(themeHex: 0x495C7C) : .white)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipped()
            // Support native bars locally, leaving the room and board free
            // of a global scrim. Older toolbars have no glass of their own.
            VStack(spacing: 0) {
                LinearGradient(stops: [
                    .init(color: chrome.opacity(usesLegacyChrome ? 0.94 : 0.82), location: 0),
                    .init(color: chrome.opacity(usesLegacyChrome ? 0.92
                        : 0.24 + 0.58 * Double(shortWideChromeWeight)), location: 0.55),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: topFadeHeight)
                Spacer(minLength: 0)
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: chrome.opacity(usesLegacyChrome ? 0.90 : 0.24), location: 0.55),
                    .init(color: chrome.opacity(usesLegacyChrome ? 0.94 : 0.78), location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: min(96, size.height * 0.16))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// Foliage sits above its cast shadow and the game, independently of panels.
/// System chrome and presented sheets remain above this scene layer.
struct GameDetailSceneForeground: View {
    @Environment(\.surroundTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    var hasTopEdgeClocks = false

    var body: some View {
        Group {
            if theme == .rakedGarden {
                GeometryReader { geometry in
                    RakedGardenForegroundContent(size: geometry.size, scheme: colorScheme,
                                                 hasTopEdgeClocks: hasTopEdgeClocks).equatable()
                }
            } else if theme == .surroundStudio {
                GeometryReader { geometry in
                    SurroundStudioFoliageContent(size: geometry.size, scheme: colorScheme,
                                                 hasTopEdgeClocks: hasTopEdgeClocks).equatable()
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Like Raked Garden, the canopy follows the viewport independently of game
/// panels, keeping its natural leaf scale through mode and orientation changes.
struct SurroundStudioDecorationLayout: Equatable {
    let foliage: CGRect

    init(size: CGSize, usesLegacyChrome: Bool = false, hasTopEdgeClocks: Bool = false) {
        let width = size.width.isFinite ? max(0, size.width) : 0
        let height = size.height.isFinite ? max(0, size.height) : 0
        let shortSide = min(width, height)
        let tileSide = min(260, max(176, shortSide * 0.5))
        let roomy = min(1, max(0, (shortSide - 430) / 250))
        let portrait = min(1, max(0, (height / max(1, width) - 1) * 2))
        // A conservative, fixed top reach keeps
        // the foreground clear of clocks and panel text through mode changes.
        let foliageSide = tileSide * 1.5
        let heightLimit: CGFloat = usesLegacyChrome ? 80 : hasTopEdgeClocks ? 88 : 128 - 18 * roomy
        // Phone landscape can place a board under this corner. Reserve that
        // clearance in every mode so opening Chat cannot move the canopy.
        let shallowLandscape = min(1, max(0, width / max(1, height) - 1)) * (1 - roomy)
        // A small floating portrait window also puts its clock cards close
        // to the title bar, even though it has a portrait aspect ratio.
        let shortPortrait = portrait * min(1, max(0, (700 - height) / 152))
        let visibleHeight = min(heightLimit, 128 - 44 * shallowLandscape - 58 * shortPortrait)
        foliage = CGRect(x: width - foliageSide * 0.66 + 12 * roomy, y: visibleHeight - foliageSide,
                         width: foliageSide, height: foliageSide)
    }
}

private struct SurroundStudioFoliageContent: View, Equatable {
    let size: CGSize
    let scheme: ColorScheme
    let hasTopEdgeClocks: Bool

    private var usesLegacyChrome: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }

    var body: some View {
        let layout = SurroundStudioDecorationLayout(size: size,
                                                    usesLegacyChrome: usesLegacyChrome,
                                                    hasTopEdgeClocks: hasTopEdgeClocks)
        Image("SurroundStudioFoliage")
            .resizable()
            .saturation(scheme == .dark ? 0.42 : 1)
            .colorMultiply(scheme == .dark ? Color(themeHex: 0x6C7D99) : .white)
            .frame(width: layout.foliage.width, height: layout.foliage.height)
            .shadow(color: Color(themeHex: scheme == .dark ? 0x070D16 : 0x342F21)
                .opacity(scheme == .dark ? 0.3 : 0.16), radius: 3, x: 3, y: 5)
            .position(x: layout.foliage.midX, y: layout.foliage.midY)
            .frame(width: size.width, height: size.height)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(stops: [
                        .init(color: .white.opacity(usesLegacyChrome ? 0.08 : 0.18), location: 0),
                        .init(color: .white.opacity(usesLegacyChrome ? 0.12 : 0.65), location: 0.55),
                        .init(color: .white, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: usesLegacyChrome ? 80 : 100)
                    Color.white
                }
            }
            .clipped()
    }
}

private struct RakedGardenForegroundContent: View, Equatable {
    let size: CGSize
    let scheme: ColorScheme
    let hasTopEdgeClocks: Bool

    private var usesLegacyChrome: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }

    var body: some View {
        let layout = RakedGardenSceneLayout(size: size, usesLegacyChrome: usesLegacyChrome,
                                           hasTopEdgeClocks: hasTopEdgeClocks)
        ZStack {
            RakedGardenMapleShadow(size: size, scheme: scheme).equatable()
            Image("RakedGardenMaple")
                .resizable()
                .colorMultiply(scheme == .dark ? Color(themeHex: 0x8292AC) : .white)
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
/// Only size or appearance updates this leaf, not moves, scrolling or ticks.
private struct RakedGardenMapleShadow: View, Equatable {
    let size: CGSize
    let scheme: ColorScheme

    var body: some View {
        let layout = RakedGardenShadowLayout(size: size)
        Image("RakedGardenMaple")
            .renderingMode(.template)
            .resizable()
            .foregroundStyle(Color(themeHex: scheme == .dark ? 0x09131A : 0x342F29))
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
    let scheme: ColorScheme

    var body: some View {
        GeometryReader { geometry in
            RakedGardenSceneContent(size: geometry.size, scheme: scheme).equatable()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Only container size or appearance updates the composition; moves and
/// clock ticks do not reconstruct its fixed image layers.
private struct RakedGardenSceneContent: View, Equatable {
    let size: CGSize
    let scheme: ColorScheme
    private var sand: Color { Color(themeHex: scheme == .dark ? 0x0E191F : 0xEFEAE1) }

    private var topFade: Gradient {
        if #available(iOS 26.0, *) {
            return Gradient(colors: [sand.opacity(0.82), sand.opacity(0.26), .clear])
        }
        // Earlier toolbars have no glass backing. Keep their icons on quiet
        // sand while preserving the foliage below the navigation controls.
        return Gradient(stops: [
            .init(color: sand.opacity(0.92), location: 0),
            .init(color: sand.opacity(0.92), location: 0.62),
            .init(color: .clear, location: 1)
        ])
    }

    private var bottomFade: Gradient {
        if #available(iOS 26.0, *) {
            return Gradient(colors: [.clear, sand.opacity(0.24), sand.opacity(0.78)])
        }
        return Gradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: sand.opacity(0.90), location: 0.55),
            .init(color: sand.opacity(0.94), location: 1)
        ])
    }

    var body: some View {
        let layout = RakedGardenSceneLayout(size: size)
        ZStack {
            sand
            Image("RakedGardenSand")
                .resizable()
                .colorMultiply(scheme == .dark ? Color(themeHex: 0x364B60) : .white)
                .aspectRatio(contentMode: .fill)
                .frame(width: layout.size.width, height: layout.size.height)
                .clipped()
            // Moonlight belongs to the garden artwork behind the game,
            // never to text, stones, marks or the whole app compositing group.
            RadialGradient(colors: [Color(themeHex: 0xB8D9E8).opacity(0.16),
                                    Color(themeHex: 0x769AAD).opacity(0.05), .clear],
                           center: .topTrailing, startRadius: 0,
                           endRadius: max(1, max(layout.size.width, layout.size.height) * 0.8))
                .opacity(scheme == .dark ? 1 : 0)
            Image("RakedGardenRocks")
                .resizable()
                .colorMultiply(scheme == .dark ? Color(themeHex: 0x566C83) : .white)
                .frame(width: layout.rocks.width, height: layout.rocks.height)
                .position(x: layout.rocks.midX, y: layout.rocks.midY)
            Image("RakedGardenRocks")
                .resizable()
                .colorMultiply(scheme == .dark ? Color(themeHex: 0x566C83) : .white)
                .frame(width: layout.upperRocks.width, height: layout.upperRocks.height)
                .position(x: layout.upperRocks.midX, y: layout.upperRocks.midY)
            // Appearance-matched support stays local to the chrome, leaving
            // the rock and foliage silhouettes visible in either light.
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
