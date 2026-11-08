import SwiftUI
import CoreImage

/// A curated look for Game Detail: its scene, its surfaces and the board.
/// `.standard` is Surround's ordinary appearance.
enum SurroundTheme: String, CaseIterable, Identifiable {
    case standard
    case nebulaPearl
    case rakedGarden
    case surroundStudio
    case frostPine
    case feltMeadow
    case nightGarden
    case christmasKeepsakes
    case flowingInk
    case flowingInkJade
    case flowingInkJadePlain
    case flowingInkPlain

    var id: Self { self }

    /// The themes that ship, in the order pickers show them.
    static let released: [SurroundTheme] = [.standard, .surroundStudio, .rakedGarden, .nebulaPearl]

    /// Whether only Debug builds offer this theme.
    var isDebugOnly: Bool { !Self.released.contains(self) }

    /// The themes this build offers. Debug builds add the unreleased ones,
    /// which the pickers mark as Debug.
    static var available: [SurroundTheme] {
        #if DEBUG
        released + allCases.filter(\.isDebugOnly)
        #else
        released
        #endif
    }

    /// Flowing Ink has one picker tile and four persistent presentation modes.
    /// Keep all modes available for stored IDs and board/marker audits.
    static var pickerThemes: [SurroundTheme] {
        available.filter { !$0.isFlowingInk || $0 == .flowingInk }
    }

    var pickerTheme: SurroundTheme { isFlowingInk ? .flowingInk : self }

    var isFlowingInk: Bool {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain: true
        default: false
        }
    }

    var flowingInkUsesColor: Bool { self == .flowingInkJade || self == .flowingInkJadePlain }

    /// The toolbar enters this family at monochrome with scenery, then
    /// advances through the same cycle across navigation and app launches.
    var nextFlowingInkTheme: SurroundTheme {
        switch self {
        case .flowingInk: .flowingInkJade
        case .flowingInkJade: .flowingInkJadePlain
        case .flowingInkJadePlain: .flowingInkPlain
        default: .flowingInk
        }
    }

    var flowingInkModeDescription: String {
        switch self {
        case .flowingInkJade: String(localized: "Color with background", comment: "Flowing Ink theme presentation mode")
        case .flowingInkJadePlain: String(localized: "Color without background", comment: "Flowing Ink theme presentation mode")
        case .flowingInkPlain: String(localized: "Monochrome without background", comment: "Flowing Ink theme presentation mode")
        default: String(localized: "Monochrome with background", comment: "Flowing Ink theme presentation mode")
        }
    }

    /// The theme games show. A stored theme this build does not offer falls
    /// back to Classic.
    static func current(storedID: String) -> SurroundTheme {
        guard let theme = SurroundTheme(rawValue: storedID), available.contains(theme) else {
            return .standard
        }
        return theme
    }

    /// The theme every screen that supports themes shows (Home, Settings,
    /// Public games, Game history): the games' theme with Whole app,
    /// otherwise Classic.
    static func current(storedID: String, appliesToWholeApp: Bool) -> SurroundTheme {
        appliesToWholeApp ? current(storedID: storedID) : .standard
    }

    /// Localized display names describe each theme's mood and materials.
    /// Surround Studio keeps its branded name; stored IDs stay language-neutral.
    var title: String {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            String(localized: "Flowing Ink", comment: "Theme name: an ink-wash landscape with monochrome and pale jade presentations")
        case .standard: String(localized: "Classic", comment: "Theme name: Surround's ordinary look, with a kaya board and flat stones")
        case .nebulaPearl: String(localized: "Nebula & Pearl", comment: "Theme name: a cosmic nebula, dark glass stones and luminous pearls. Use a short, natural title naming the nebula and pearl.")
        case .rakedGarden: String(localized: "Raked Garden", comment: "Theme name: a Japanese dry landscape garden with raked sand, basalt and jade stones. Use a short, natural garden title; the sand pattern is visible in the preview.")
        case .surroundStudio: "Surround Studio"
        case .frostPine: String(localized: "Frost & Pine", comment: "Theme name: frost crystals and pine branches. Preserve the winter frost and pine imagery in a short title.")
        case .feltMeadow: String(localized: "Felt Meadow", comment: "Theme name: a meadow crafted from soft wool felt. Felt is the textile material, not the past tense of feel. Use a short, natural title.")
        case .nightGarden: String(localized: "Night Garden", comment: "Theme name: a quiet garden at night with lanterns and glass stones. Use a short, natural title.")
        case .christmasKeepsakes: String(localized: "Christmas Keepsakes", comment: "Theme name: cherished Christmas ornaments, enamel pieces and keepsakes. Preserve Christmas and the treasured-object mood in a short, natural title.")
        }
    }

    /// The pickers' thumbnail in the asset catalog, with a Dark variant
    /// unless the theme is always dark. `.github/ci-tools/update-theme-previews.py`
    /// writes it from the app's own rendering.
    var previewImageName: String { "ThemePreview-\(pickerTheme.rawValue)" }

    /// Scene lighting follows the system; Nebula keeps its midnight palette.
    var colorScheme: ColorScheme? {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            nil
        case .standard, .rakedGarden, .surroundStudio, .frostPine, .feltMeadow, .nightGarden, .christmasKeepsakes: nil
        case .nebulaPearl: .dark
        }
    }

    /// Resolve image grading alongside the board palette. The image references
    /// stay cached, so an appearance change does not decode or regenerate art.
    func board(for scheme: ColorScheme) -> BoardAppearance {
        if isFlowingInk, scheme == .dark {
            var night = board
            // Medium graphite/jade separates both solid stone colors. A
            // near-black board would hide the ink stones and their contours.
            let paper = Color(themeHex: flowingInkUsesColor ? 0x748478 : 0x777777)
            let ink = Color(themeHex: flowingInkUsesColor ? 0x183326 : 0x171717)
            night.boardColor = paper
            night.compactBoardColor = paper
            night.boardEdge = Color.black.opacity(0.85)
            night.dameColor = flowingInkUsesColor ? Color(themeHex: 0x3D2A10) : ink
            night.highlightColor = ink
            night.crosshair = .init(valid: ink,
                                   invalid: flowingInkUsesColor ? Color(themeHex: 0x4D161C) : .black,
                                   removal: ink)
            night.removeMark = flowingInkUsesColor ? Color(themeHex: 0x4D161C) : .black
            night.restoreMark = ink
            return night
        }
        if self == .christmasKeepsakes, scheme == .dark {
            var night = board
            night.boardColor = Color(themeHex: 0x667F6C)
            night.compactBoardColor = Color(themeHex: 0x667F6C)
            night.boardEdge = Color(themeHex: 0xBFA981)
            // Keep medium pine under the dark grid as the room dims.
            night.boardTexture?.tint = Color(themeHex: 0xF8F8F8)
            night.stoneImages?.tint = Color(themeHex: 0xE8E5DC)
            night.coordinateColor = Color(themeHex: 0x000703)
            night.emptyPointMarker = Color(themeHex: 0x000703)
            night.black.flat = Color(themeHex: 0x5B0A1B)
            night.black.territory = Color(themeHex: 0x5B0A1B)
            night.white.flat = Color(themeHex: 0xE9E2D5)
            night.white.territory = Color(themeHex: 0xE9E2D5)
            return night
        }
        if self == .nightGarden, scheme == .dark {
            var night = board
            night.boardColor = Color(themeHex: 0x83947E)
            night.compactBoardColor = Color(themeHex: 0x83947E)
            night.boardEdge = Color(themeHex: 0x4D513E).opacity(0.9)
            night.boardTexture?.tint = Color(themeHex: 0xE1E6E2)
            // Subdue the light without changing amethyst/champagne identity.
            night.stoneImages?.tint = Color(themeHex: 0xE8E5E0)
            night.gridColor = Color(themeHex: 0x112018)
            night.coordinateColor = Color(themeHex: 0x112018)
            night.black.flat = Color(themeHex: 0x361336)
            night.white.flat = Color(themeHex: 0xE4D3B8)
            night.white.outline = Color(themeHex: 0x3D3427)
            night.white.territory = Color(themeHex: 0xE4D3B8)
            night.emptyPointMarker = Color(themeHex: 0x112018)
            night.markOutline = Color(themeHex: 0x112018)
            night.dameColor = Color(themeHex: 0x503014)
            night.highlightColor = Color(themeHex: 0x143848)
            night.crosshair = .init(valid: Color(themeHex: 0x1A3B25),
                                   invalid: Color(themeHex: 0x5D2032),
                                   removal: Color(themeHex: 0x143848))
            night.removeMark = Color(themeHex: 0x5D2032)
            night.restoreMark = Color(themeHex: 0x1A3B25)
            night.removedStoneOutline = Color(themeHex: 0x112018)
            return night
        }
        if self == .frostPine, scheme == .light {
            var day = board
            day.stoneImages = FrostPineAssets.dayStones
            return day
        }
        if self == .frostPine, scheme == .dark {
            var night = board
            night.boardColor = Color(themeHex: 0xB0C1CB)
            night.compactBoardColor = Color(themeHex: 0x9BAFB9)
            night.boardEdge = Color(themeHex: 0xBDD6E5).opacity(0.7)
            night.boardTexture?.tint = Color(themeHex: 0xA5B8C5)
            night.boardTexture?.opacity = 0.4
            night.surfaceFrost?.tint = Color(themeHex: 0xA5B8C5)
            night.surfaceFrost?.opacity = 0.56
            night.stoneImages?.tint = Color(themeHex: 0xD5E2EE)
            night.boardDepth = BoardDepth(
                upperFace: Color(themeHex: 0xA6BCC9), lowerFace: Color(themeHex: 0x6C8596),
                highlight: Color(themeHex: 0xE3EFF6).opacity(0.74),
                shade: Color(themeHex: 0x344F63).opacity(0.42),
                shadow: Color(themeHex: 0x07121C).opacity(0.35),
                thicknessRatio: 0.008, maximumThickness: 5, edgeStyle: .frosted)
            night.gridColor = Color(themeHex: 0x253E4C)
            night.coordinateColor = Color(themeHex: 0x172E3C)
            night.black.flat = Color(themeHex: 0x102E43)
            // Bright enough to stand apart from the night board's slate.
            night.white.flat = Color(themeHex: 0xE4EFF6)
            night.white.outline = Color(themeHex: 0x2C4C61)
            night.emptyPointMarker = Color(themeHex: 0x172E3C)
            night.markOutline = Color(themeHex: 0x253E4C)
            night.dameColor = Color(themeHex: 0x513319)
            night.highlightColor = Color(themeHex: 0x173D55)
            night.crosshair = .init(valid: Color(themeHex: 0x244A38),
                                   invalid: Color(themeHex: 0x6D2433),
                                   removal: Color(themeHex: 0x173D55))
            night.removeMark = Color(themeHex: 0x6D2433)
            night.restoreMark = Color(themeHex: 0x244A38)
            night.removedStoneOutline = Color(themeHex: 0x253E4C)
            return night
        }
        if self == .feltMeadow, scheme == .dark {
            var night = board
            night.boardColor = Color(themeHex: 0x737C62)
            night.compactBoardColor = Color(themeHex: 0x737C62)
            night.boardEdge = Color(themeHex: 0xABB494).opacity(0.5)
            night.boardTexture?.tint = Color(themeHex: 0xC0CCB8)
            night.stoneImages?.tint = Color(themeHex: 0xE3E8D9)
            night.gridColor = Color(themeHex: 0x1B2719)
            night.gridStitchColor = Color(themeHex: 0xDAD5B7).opacity(0.42)
            night.coordinateColor = Color(themeHex: 0x020702)
            night.black = StonePalette(
                highlight: Color(themeHex: 0x586151), shade: Color(themeHex: 0x151C15),
                flat: Color(themeHex: 0x202820), outline: Color(themeHex: 0x111A11),
                rim: Color(themeHex: 0x9BA68B).opacity(0.35),
                lastMove: Color(themeHex: 0xFFF8E6), label: Color(themeHex: 0xFFF8E6),
                territory: Color(themeHex: 0x182118),
                detailedMarkerCasing: Color(themeHex: 0x172017))
            night.white = StonePalette(
                highlight: Color(themeHex: 0xECEBDD), shade: Color(themeHex: 0xA1A38B),
                flat: Color(themeHex: 0xDAD8C6), outline: Color(themeHex: 0x1B2719),
                rim: Color(themeHex: 0x4C5942).opacity(0.45),
                lastMove: Color(themeHex: 0x182213), label: Color(themeHex: 0x182213),
                territory: Color(themeHex: 0xF4F0DE))
            night.emptyPointMarker = Color(themeHex: 0x020702)
            night.markOutline = Color(themeHex: 0x1B2719)
            night.dameColor = Color(themeHex: 0x3D2713)
            night.highlightColor = Color(themeHex: 0x102E37)
            night.crosshair = .init(valid: Color(themeHex: 0x14301B),
                                   invalid: Color(themeHex: 0x491C1D),
                                   removal: Color(themeHex: 0x102E37))
            night.removeMark = Color(themeHex: 0x491C1D)
            night.restoreMark = Color(themeHex: 0x14301B)
            night.removedStoneOutline = Color(themeHex: 0x1B2719)
            return night
        }
        if self == .surroundStudio, scheme == .dark {
            var night = board
            night.boardColor = Color(themeHex: 0xA58A5A)
            // Compact boards use this solid pigment, without the detailed
            // texture, tint or bevel. Shared rendering retains the 14 pt cutoff.
            night.compactBoardColor = Color(themeHex: 0xA58A5A)
            night.boardEdge = Color(themeHex: 0xC6BA9C).opacity(0.65)
            night.boardDepth = BoardDepth(
                upperFace: Color(themeHex: 0x756043), lowerFace: Color(themeHex: 0x423623),
                highlight: Color(themeHex: 0xD8C6A3).opacity(0.3),
                shade: Color(themeHex: 0x30271E).opacity(0.7), shadow: .black.opacity(0.4),
                thicknessRatio: 0.012, maximumThickness: 8)
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
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            return flowingInkBoard
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
                boardDepth: BoardDepth(
                    upperFace: Color(themeHex: 0x252D4D), lowerFace: Color(themeHex: 0x090E20),
                    highlight: Color(themeHex: 0xBEC9EF).opacity(0.38),
                    shade: Color(themeHex: 0x080C1C).opacity(0.8), shadow: .black.opacity(0.5),
                    thicknessRatio: 0.009, maximumThickness: 6),
                // Lift the indigo sheen across the whole playing surface so
                // dark amethyst glass keeps its silhouette at phone size,
                // including away from the brighter upper-left reflection.
                boardReflection: BoardReflection(color: Color(themeHex: 0x8E9BD8),
                                                 corner: 0.36, middle: 0.31, edge: 0.20, reach: 1.8,
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
                    // Lighter than the stones, so territory stands out even
                    // on the board's brighter reflected indigo surface.
                    territory: Color(themeHex: 0xA58DFF),
                    detailedMarkerCasing: Color(themeHex: 0x1B122C)
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
        case .feltMeadow:
            return BoardAppearance(
                boardColor: Color(themeHex: 0x8B9166),
                compactBoardColor: Color(themeHex: 0x8B9166),
                boardEdge: Color(themeHex: 0x535D3D).opacity(0.65),
                boardTexture: FeltMeadowAssets.board,
                gridLineScale: 1.4,
                gridStyle: .stitched,
                gridStitchColor: Color(themeHex: 0xE5DDB8).opacity(0.48),
                stoneImages: FeltMeadowAssets.stones,
                gridColor: Color(themeHex: 0x303927),
                coordinateColor: Color(themeHex: 0x182213),
                black: StonePalette(
                    highlight: Color(themeHex: 0x5A6050), shade: Color(themeHex: 0x1C2119),
                    flat: Color(themeHex: 0x2C3028), outline: Color(themeHex: 0x1C2119),
                    rim: Color(themeHex: 0x9EA58D).opacity(0.35),
                    lastMove: Color(themeHex: 0xFFF8E6), label: Color(themeHex: 0xFFF8E6),
                    territory: Color(themeHex: 0x252C20),
                    detailedMarkerCasing: Color(themeHex: 0x1C2119)),
                white: StonePalette(
                    highlight: Color(themeHex: 0xFFF9E8), shade: Color(themeHex: 0xC7B99A),
                    flat: Color(themeHex: 0xF0E6CF), outline: Color(themeHex: 0x303927),
                    rim: Color(themeHex: 0x766E53).opacity(0.4),
                    lastMove: Color(themeHex: 0x25301F), label: Color(themeHex: 0x25301F),
                    territory: Color(themeHex: 0xFFF8E6)),
                emptyPointMarker: Color(themeHex: 0x182213),
                markOutline: Color(themeHex: 0x303927),
                dameColor: Color(themeHex: 0x533719),
                highlightColor: Color(themeHex: 0x102E37),
                highlightCasing: Color(themeHex: 0xFFF8E6),
                crosshair: .init(valid: Color(themeHex: 0x233F28),
                                 invalid: Color(themeHex: 0x622E2A),
                                 removal: Color(themeHex: 0x102E37)),
                crosshairWidth: 1.5,
                removeMark: Color(themeHex: 0x622E2A),
                restoreMark: Color(themeHex: 0x233F28),
                removalMarkCasing: Color(themeHex: 0xFFF8E6),
                removedStoneOutline: Color(themeHex: 0x303927)
            )
        case .surroundStudio:
            return BoardAppearance(
                boardColor: Color(themeHex: 0xD8B27A),
                boardEdge: Color(themeHex: 0x80613E).opacity(0.65),
                boardTexture: SurroundStudioAssets.board,
                boardBevel: true,
                boardDepth: BoardDepth(
                    upperFace: Color(themeHex: 0xB68D59), lowerFace: Color(themeHex: 0x785733),
                    highlight: Color(themeHex: 0xF4DEBA).opacity(0.45),
                    shade: Color(themeHex: 0x634C33).opacity(0.7), shadow: Color(themeHex: 0x342B22).opacity(0.35),
                    thicknessRatio: 0.012, maximumThickness: 8),
                // The kaya grain stays quiet; exact charcoal lines and all
                // game marks are drawn above it by the shared native board.
                gridLineScale: 1.2,
                stoneImages: SurroundStudioAssets.stones,
                stoneLightDirection: .upperLeft,
                imageStoneShadow: .raised,
                imageStoneShading: .clamshellShoulder,
                gridColor: Color(themeHex: 0x3E382E),
                coordinateColor: Color(themeHex: 0x4B3D2C),
                black: StonePalette(
                    highlight: Color(themeHex: 0x6C7070),
                    shade: Color(themeHex: 0x1D2223),
                    flat: Color(themeHex: 0x282D2E),
                    outline: Color(themeHex: 0x1C2021),
                    rim: Color(themeHex: 0x7C8280).opacity(0.4),
                    lastMove: Color(themeHex: 0xFFF9ED),
                    label: Color(themeHex: 0xFFF9ED),
                    territory: Color(themeHex: 0x181D20)
                ),
                white: StonePalette(
                    highlight: Color(themeHex: 0xFFFEFB),
                    shade: Color(themeHex: 0xD8D4CD),
                    flat: Color(themeHex: 0xF5F3EF),
                    outline: Color(themeHex: 0x6B5C45),
                    rim: Color(themeHex: 0x776B58).opacity(0.5),
                    lastMove: Color(themeHex: 0x343B38),
                    label: Color(themeHex: 0x303631),
                    // A shell fill distinguishes ownership from black;
                    // the dark score outline separates it from honey kaya.
                    territory: Color(themeHex: 0xFFF9ED)
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
        case .nightGarden:
            return BoardAppearance(
                boardColor: Color(themeHex: 0x98A78E),
                compactBoardColor: Color(themeHex: 0x98A78E),
                boardEdge: Color(themeHex: 0x645C40).opacity(0.85),
                boardTexture: NightGardenAssets.board,
                // A thin bronze contour holds the quiet glass, without a
                // raised slab or lifted rim. The native grid stays exact.
                gridLineScale: 1.1,
                stoneImages: NightGardenAssets.stones,
                stoneLightDirection: .upperLeft,
                imageStoneShadow: .raised,
                gridColor: Color(themeHex: 0x17251E),
                coordinateColor: Color(themeHex: 0x17251E),
                black: StonePalette(
                    highlight: Color(themeHex: 0xA16998), shade: Color(themeHex: 0x210C2A),
                    flat: Color(themeHex: 0x3E143E), outline: Color(themeHex: 0x210C2A),
                    rim: Color(themeHex: 0xC49BB9).opacity(0.6),
                    lastMove: Color(themeHex: 0xFFF1D7), label: Color(themeHex: 0xFFF1D7),
                    detailedMarkerCasing: Color(themeHex: 0x170D1A)
                ),
                white: StonePalette(
                    highlight: Color(themeHex: 0xFFF5E3), shade: Color(themeHex: 0xB08D62),
                    flat: Color(themeHex: 0xF2DEC1), outline: Color(themeHex: 0x4D3C2A),
                    rim: Color(themeHex: 0xFFF5E3).opacity(0.7),
                    lastMove: Color(themeHex: 0x301A2A), label: Color(themeHex: 0x301A2A),
                    territory: Color(themeHex: 0xF2DEC1),
                    detailedMarkerCasing: Color(themeHex: 0xFFF1D7)
                ),
                emptyPointMarker: Color(themeHex: 0x17251E),
                markOutline: Color(themeHex: 0x17251E),
                dameColor: Color(themeHex: 0x633C15),
                highlightColor: Color(themeHex: 0x18475E),
                highlightCasing: Color(themeHex: 0xFFF1D7),
                crosshair: .init(valid: Color(themeHex: 0x244A32),
                                 invalid: Color(themeHex: 0x6B2639),
                                 removal: Color(themeHex: 0x18475E)),
                crosshairWidth: 1.5,
                removeMark: Color(themeHex: 0x6B2639),
                restoreMark: Color(themeHex: 0x244A32),
                removalMarkCasing: Color(themeHex: 0xFFF1D7),
                removedStoneOutline: Color(themeHex: 0x17251E)
            )
        case .christmasKeepsakes:
            return BoardAppearance(
                boardColor: Color(themeHex: 0x6D8975),
                compactBoardColor: Color(themeHex: 0x6D8975),
                boardEdge: Color(themeHex: 0xD9C29A),
                boardTexture: ChristmasKeepsakesAssets.board,
                // Winter Window keeps the enamel calm: a fine dark-pine
                // grid and a champagne edge, with no raised slab or bevel.
                gridLineScale: 0.85,
                stoneImages: ChristmasKeepsakesAssets.stones,
                stoneLightDirection: .upperLeft,
                imageStoneShadow: .raisedGlass,
                gridColor: Color(themeHex: 0x10291C),
                coordinateColor: Color(themeHex: 0x020D06),
                black: StonePalette(
                    highlight: Color(themeHex: 0xCE5B62), shade: Color(themeHex: 0x370512),
                    flat: Color(themeHex: 0x650D24), outline: Color(themeHex: 0x370512),
                    rim: Color(themeHex: 0xCE5B62).opacity(0.4),
                    lastMove: Color(themeHex: 0xFFF3D8), label: Color(themeHex: 0xFFF3D8),
                    territory: Color(themeHex: 0x650D24),
                    detailedMarkerCasing: Color(themeHex: 0x2B0711)
                ),
                white: StonePalette(
                    highlight: Color(themeHex: 0xFFF9EF), shade: Color(themeHex: 0xB9A993),
                    flat: Color(themeHex: 0xF7EEDF), outline: Color(themeHex: 0x493F32),
                    rim: Color(themeHex: 0xFFF3D8).opacity(0.7),
                    lastMove: Color(themeHex: 0x3B1520), label: Color(themeHex: 0x3B1520),
                    territory: Color(themeHex: 0xF7EEDF),
                    detailedMarkerCasing: Color(themeHex: 0xFFF3D8)
                ),
                emptyPointMarker: Color(themeHex: 0x020D06),
                markOutline: Color(themeHex: 0x10291C),
                dameColor: Color(themeHex: 0x382943),
                highlightColor: Color(themeHex: 0x102F40),
                highlightCasing: Color(themeHex: 0xFFF4E3),
                crosshair: .init(valid: Color(themeHex: 0x102C1B),
                                 invalid: Color(themeHex: 0x501525),
                                 removal: Color(themeHex: 0x102F40)),
                crosshairWidth: 1.5,
                removeMark: Color(themeHex: 0x501525),
                restoreMark: Color(themeHex: 0x102C1B),
                removalMarkCasing: Color(themeHex: 0xFFF4E3),
                removedStoneOutline: Color(themeHex: 0x10291C)
            )
        case .frostPine:
            return BoardAppearance(
                boardColor: Color(themeHex: 0xD2DDE2),
                // Small boards take the frosted board's lower face, so the
                // flat ice stones read brighter than the board, not darker.
                compactBoardColor: Color(themeHex: 0xB3C4CE),
                boardEdge: Color(themeHex: 0xF6FCFF).opacity(0.85),
                boardTexture: FrostPineAssets.board,
                boardBevel: true,
                boardDepth: BoardDepth(
                    upperFace: Color(themeHex: 0xE4ECEF), lowerFace: Color(themeHex: 0xB3C4CE),
                    highlight: Color(themeHex: 0xFCFDFA).opacity(0.92),
                    shade: Color(themeHex: 0x738796).opacity(0.32),
                    shadow: Color(themeHex: 0x253F51).opacity(0.24),
                    thicknessRatio: 0.008, maximumThickness: 5, edgeStyle: .frosted),
                surfaceFrost: FrostPineAssets.surfaceFrost,
                // Polished clear ice leaves the field quiet; recessed engraved
                // cores and recessed hoshi remain native, aligned geometry.
                gridLineScale: 1,
                gridStyle: .engraved,
                stoneImages: FrostPineAssets.stones,
                stoneLightDirection: .upperLeft,
                imageStoneShadow: .ice,
                imageStoneShading: .iceEdge,
                gridColor: Color(themeHex: 0x52616A),
                coordinateColor: Color(themeHex: 0x344F62),
                black: StonePalette(
                    highlight: Color(themeHex: 0x4D799A), shade: Color(themeHex: 0x071C2E),
                    flat: Color(themeHex: 0x123449), outline: Color(themeHex: 0x081F31),
                    rim: Color(themeHex: 0x97C6E6).opacity(0.55),
                    lastMove: Color(themeHex: 0xF5FBFF), label: Color(themeHex: 0xF5FBFF),
                    detailedMarkerCasing: Color(themeHex: 0x0A2438)
                ),
                white: StonePalette(
                    highlight: Color(themeHex: 0xF1FAFF), shade: Color(themeHex: 0x8AB2D0),
                    flat: Color(themeHex: 0xF1FAFF), outline: Color(themeHex: 0x426478),
                    rim: Color(themeHex: 0x426478).opacity(0.7),
                    lastMove: Color(themeHex: 0x193C50), label: Color(themeHex: 0x193C50),
                    // Pale ownership uses the slate outline on empty ice;
                    // it stays distinct from midnight ownership on stones.
                    territory: Color(themeHex: 0xF1FAFF),
                    detailedMarkerCasing: Color(themeHex: 0xF1FAFF)
                ),
                emptyPointMarker: Color(themeHex: 0x193C50),
                markOutline: Color(themeHex: 0x344F62),
                dameColor: Color(themeHex: 0x754C26),
                highlightColor: Color(themeHex: 0x235877),
                highlightCasing: Color(themeHex: 0xF5FBFF),
                crosshair: .init(valid: Color(themeHex: 0x31543E),
                                 invalid: Color(themeHex: 0x8D303E),
                                 removal: Color(themeHex: 0x235877)),
                crosshairWidth: 1.5,
                removeMark: Color(themeHex: 0x8D303E),
                restoreMark: Color(themeHex: 0x31543E),
                removalMarkCasing: Color(themeHex: 0xF5FBFF),
                removedStoneOutline: Color(themeHex: 0x344F62)
            )
        }
    }
}

/// Stained-glass artwork is separate from the native board and its grid.
/// The crystal cutouts have transparent margins and a shared 0.94 footprint.
private enum NightGardenAssets {
    static let stones: StoneImages? = {
        guard let black = UIImage(named: "NightGardenBlackStone"),
              let white = UIImage(named: "NightGardenWhiteStone") else { return nil }
        return StoneImages(black: [black], white: [white])
    }()
    static let board = UIImage(named: "NightGardenBoard").map { BoardTexture(image: $0, mapping: .board) }
}

/// The same garden in daylight and dimmed evening light. Cached providers
/// preserve amethyst/champagne identity while surfaces and inks follow traits.
private enum NightGardenColors {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }

    static let page = adaptive(0xE9E7D8, 0x0D1C1D)
    static let panel = adaptive(0xF5F1E4, 0x1A2B2A)
    static let foreground = adaptive(0x28362D, 0xF3EDDB)
    static let detailSecondary = adaptive(0x53614F, 0xC3CBB6)
    static let panelBorder = adaptive(0x69745A, 0xB9AD7C)
    static let blackGlass = adaptive(0x3E143E, 0x311932)
    static let whiteGlass = adaptive(0xF2DEC1, 0xD9C8AC)
    static let whiteIdentityGlass = adaptive(0xF6E5CD, 0xDFCDB2)
    static let action = adaptive(0x725035, 0x62402D)
    static let chatBubble = adaptive(0xD9DECB, 0x2C4140)
    static let selection = adaptive(0x285566, 0xA8D2DA)
    static let conditional = adaptive(0x78501F, 0xF0CB8D)
    static let cream = adaptive(0xFFF4DF, 0xF1E8DA)
    static let keyline = adaptive(0xFFF4DF, 0x0D1C1D)
    static let treeGuide = adaptive(0x69745A, 0xA7B8A2)
    static let idle = adaptive(0xC9D1BE, 0x344841)
    static let blackSurfaceTop = adaptive(0x5B3455, 0x442440)
    static let blackSurfaceBottom = adaptive(0x331E35, 0x211422)
    static let whiteSurfaceTop = adaptive(0xEAD5B6, 0xCBBBA3)
    static let whiteSurfaceBottom = adaptive(0xFFF2D8, 0xE4D5BA)
    static let blackSolid = adaptive(0x3E143E, 0x311932)
    static let whiteForeground = adaptive(0x2B2028, 0x241D22)
    static let blackAccent = adaptive(0xF3D39B, 0xE8C991)
    static let whiteAccent = adaptive(0x5B3D1E, 0x4F351C)
    static let turnOutline = adaptive(0x8A672A, 0xC5A467)
    static let turnGlow = adaptive(0xB58D40, 0xD8BC7A)
    static let blackBorder = adaptive(0xC3A1B9, 0xB99BB0)
    static let whiteBorder = adaptive(0x6C573B, 0x5C4C35)
    static let blackSecondary = adaptive(0xE2CADD, 0xDBC4D9)
    static let whiteSecondary = adaptive(0x594739, 0x483B30)
    static let darkModerator = adaptive(0xE2C2F6, 0xDEC0F2)
    static let lightModerator = adaptive(0x653376, 0x542B63)
    static let darkProfessional = adaptive(0xBDE5AD, 0xB4DBA7)
    static let lightProfessional = adaptive(0x28502C, 0x214327)
    static let darkSupporter = adaptive(0xF3D39B, 0xE8C991)
    static let lightSupporter = adaptive(0x704216, 0x5A3516)
    static let darkOrdinary = adaptive(0xBDDDF3, 0xB5D3E9)
    static let lightOrdinary = adaptive(0x204962, 0x1B3D53)
}

/// Top-down glass cutouts share the native stone footprint; all decoration
/// belongs to the separate viewport scene, never the playable board image.
private enum ChristmasKeepsakesAssets {
    static let stones: StoneImages? = {
        guard let black = UIImage(named: "ChristmasKeepsakesRubyStone"),
              let white = UIImage(named: "ChristmasKeepsakesIvoryStone") else { return nil }
        return StoneImages(black: [black], white: [white])
    }()
    // The muted enamel has a narrow luminance range so the fine dark-pine
    // grid and coordinates stay legible across the entire playing surface.
    static let board = UIImage(named: "ChristmasKeepsakesBoardSurface")
        .map { BoardTexture(image: $0, mapping: .board) }
    static func room(for composition: ChristmasKeepsakesRoomLayout.Composition) -> UIImage? {
        UIImage(named: composition.assetName)
    }
}

/// Warm walnut, ivory and ruby retain their material identities as the room
/// dims. Opaque pigments also cover Reduce Transparency and Increase Contrast.
private enum ChristmasKeepsakesColors {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }

    static let page = adaptive(0xEAE1D1, 0x201610)
    static let panel = adaptive(0xF7EAD5, 0x33241C)
    static let foreground = adaptive(0x39291F, 0xFAEED7)
    static let detailSecondary = adaptive(0x65513D, 0xD8C6AB)
    static let panelBorder = adaptive(0x846A43, 0xC4A56F)
    static let blackGlass = adaptive(0x700F26, 0x520E20)
    static let whiteGlass = adaptive(0xF2DEC1, 0xD9C8AC)
    static let whiteIdentityGlass = adaptive(0xF6E5CD, 0xDFCDB2)
    static let action = adaptive(0x802337, 0x702437)
    static let chatBubble = adaptive(0xE6D5B8, 0x493629)
    static let selection = adaptive(0x27563F, 0xB6D6BA)
    static let conditional = adaptive(0x79501F, 0xEAC78A)
    static let cream = adaptive(0xFFF4DF, 0xF1E8DA)
    static let keyline = adaptive(0xFFF4DF, 0x201610)
    static let treeGuide = adaptive(0x846A43, 0xBDA77D)
    static let idle = adaptive(0xD5C6AA, 0x534431)
    static let blackSurfaceTop = adaptive(0x6E2939, 0x522031)
    static let blackSurfaceBottom = adaptive(0x480D21, 0x340C1B)
    static let whiteSurfaceTop = adaptive(0xEAD5B6, 0xCBBBA3)
    static let whiteSurfaceBottom = adaptive(0xFFF2D8, 0xE4D5BA)
    static let blackSolid = adaptive(0x700F26, 0x520E20)
    static let whiteForeground = adaptive(0x35251C, 0x2B211A)
    static let blackAccent = adaptive(0xF3D39B, 0xE8C991)
    static let whiteAccent = adaptive(0x5B3D1E, 0x4F351C)
    static let turnOutline = adaptive(0x8A672A, 0xC5A467)
    static let turnGlow = adaptive(0xB58D40, 0xD8BC7A)
    static let blackBorder = adaptive(0xDDAE92, 0xC49B7E)
    static let whiteBorder = adaptive(0x6C573B, 0x5C4C35)
    static let blackSecondary = adaptive(0xEBCDBB, 0xDFC6AE)
    static let whiteSecondary = adaptive(0x594739, 0x483B30)
    static let darkModerator = adaptive(0xE2C2F6, 0xDEC0F2)
    static let lightModerator = adaptive(0x653376, 0x542B63)
    static let darkProfessional = adaptive(0xBDE5AD, 0xB4DBA7)
    static let lightProfessional = adaptive(0x28502C, 0x214327)
    static let darkSupporter = adaptive(0xF3D39B, 0xE8C991)
    static let lightSupporter = adaptive(0x704216, 0x5A3516)
    static let darkOrdinary = adaptive(0xBDDDF3, 0xB5D3E9)
    static let lightOrdinary = adaptive(0x204962, 0x1B3D53)
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

private final class FrostPineAssets {
    private init() {}
    private static let bundle = Bundle(for: FrostPineAssets.self)

    static let stones: StoneImages? = {
        let black = (0..<4).compactMap { UIImage(named: "FrostPineMidnight\($0)", in: bundle, compatibleWith: nil) }
        let white = (0..<4).compactMap { UIImage(named: "FrostPinePale\($0)", in: bundle, compatibleWith: nil) }
        guard black.count == 4, white.count == 4 else { return nil }
        return StoneImages(black: black, white: white, smallStoneInset: 0.35)
    }()

    /// Lift the ice's middle tones against the bright daytime board without
    /// adding a veil over the dark depths or clipping the reflected glints.
    /// Resolve once per process; night keeps the original artwork and tint.
    static let dayStones: StoneImages? = {
        guard let stones else { return nil }
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return stones }
        let context = CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB])
        func grade(_ images: [UIImage], power: Float) -> [UIImage]? {
            var result: [UIImage] = []
            for image in images {
                guard let source = image.cgImage else { return nil }
                let input = CIImage(cgImage: source, options: [.colorSpace: sRGB])
                let graded = input.applyingFilter("CIGammaAdjust", parameters: ["inputPower": power])
                guard let output = context.createCGImage(graded, from: input.extent,
                                                        format: .RGBA8, colorSpace: sRGB) else { return nil }
                result.append(UIImage(cgImage: output, scale: image.scale, orientation: image.imageOrientation))
            }
            return result
        }
        guard let black = grade(stones.black, power: 0.82),
              let white = grade(stones.white, power: 0.60) else { return stones }
        var day = stones
        day.black = black
        day.white = white
        return day
    }()

    // Broad clear-ice depth stays quiet beneath the engraved grid. The
    // crystalline perimeter is a separate, softer surface layer.
    static let board = UIImage(named: "FrostPineBoard").map { BoardTexture(image: $0, mapping: .board, opacity: 0.48) }
    static let surfaceFrost = UIImage(named: "FrostPineBoardFrost").map {
        BoardSurfaceOverlay(image: $0, opacity: 0.76, perimeterFadeFraction: 0.045)
    }
    static let snow = UIImage(named: "FrostPineSnow")
    static let pine = UIImage(named: "FrostPinePine")
    static let pinecone = UIImage(named: "FrostPinePinecone")
    static let twig = UIImage(named: "FrostPineTwig")
}

/// Each wool stone is an opaque, centered silhouette with no baked shadow.
/// Static references keep image identity stable through clocks and resizing.
private enum FeltMeadowAssets {
    static let stones: StoneImages? = {
        guard let black = UIImage(named: "FeltMeadowBlackStone"),
              let white = UIImage(named: "FeltMeadowWhiteStone") else { return nil }
        return StoneImages(black: [black], white: [white],
                           blackFiberContours: FeltFiberContour.stone(image: black).map { [$0] } ?? [],
                           whiteFiberContours: FeltFiberContour.stone(image: white).map { [$0] } ?? [])
    }()

    static let board = UIImage(named: "FeltMeadowBoard").map { BoardTexture(image: $0, mapping: .board) }
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

/// Balanced honey accents, neutral shell and charcoal follow the room's
/// daylight; static trait providers subdue the same materials at night.
private enum SurroundStudioColors {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }

    static let page = adaptive(0xE5DED4, 0x121B24)
    static let panel = adaptive(0xF5F2ED, 0x1C2932)
    static let foreground = adaptive(0x293036, 0xE7E7DD)
    static let panelBorder = adaptive(0x7C7060, 0x9BA7A8)
    static let blackGlass = adaptive(0x34393C, 0x252D35)
    static let whiteGlass = adaptive(0xF1EEE8, 0xCECEC3)
    static let whiteIdentityGlass = adaptive(0xF5F2ED, 0xD5D4C8)
    // A deeper honey pigment keeps the native white action glyph readable.
    static let action = adaptive(0x86613E, 0x775838)
    static let chatBubble = adaptive(0xE1DBD2, 0x2D3B43)
    static let selection = adaptive(0x805B35, 0xDDC39D)
    static let conditional = adaptive(0x8A531D, 0xE4BD82)
    static let cream = adaptive(0xFCFAF7, 0xF0EEE5)
    static let keyline = adaptive(0xFCFAF7, 0x17222B)
    static let treeGuide = adaptive(0x7C7060, 0xA7AAA1)
    static let idle = adaptive(0xD7D0C6, 0x303E47)
    static let blackSurfaceTop = adaptive(0x404548, 0x343F47)
    static let blackSurfaceBottom = adaptive(0x22272A, 0x171F27)
    static let whiteSurfaceTop = adaptive(0xE6E0D8, 0xBDBFB7)
    static let whiteSurfaceBottom = adaptive(0xFCFAF7, 0xD8D8CE)
    static let blackSolid = adaptive(0x2B3033, 0x222D34)
    static let whiteForeground = adaptive(0x293036, 0x222C30)
    static let blackAccent = adaptive(0xE3C89F, 0xE3C89F)
    static let whiteAccent = adaptive(0x795530, 0x604321)
    static let turnOutline = adaptive(0x967247, 0xD0B48A)
    static let turnGlow = adaptive(0xC5A474, 0xC5AB85)
    static let blackBorder = adaptive(0xBBB8B0, 0x9AA7AC)
    static let whiteBorder = adaptive(0x7C7060, 0x566064)
    static let blackSecondary = adaptive(0xD9D7D2, 0xCFD4D0)
    static let whiteSecondary = adaptive(0x5C5B58, 0x3B4444)
    static let darkModerator = adaptive(0xDDC4F4, 0xDDC4F4)
    static let lightModerator = adaptive(0x633889, 0x4E2D67)
    static let darkProfessional = adaptive(0xBCE6B3, 0xBCE6B3)
    static let lightProfessional = adaptive(0x245925, 0x1E472C)
    static let darkSupporter = adaptive(0xF3D69A, 0xF3D69A)
    static let lightSupporter = adaptive(0x854416, 0x633818)
    static let darkOrdinary = adaptive(0xB5D7FF, 0xB5D7FF)
    static let lightOrdinary = adaptive(0x20518B, 0x1C3D62)
}

/// Snow, clear ice and pine retain their material families in moonlight.
private enum FrostPineColors {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }

    static let page = adaptive(0xE8EEF2, 0x101F2B)
    static let panel = adaptive(0xF3F7F9, 0x1B303E)
    static let foreground = adaptive(0x263F50, 0xE3EEF5)
    static let panelBorder = adaptive(0x6B8798, 0xA1BDCE)
    static let blackGlass = adaptive(0x14394F, 0x102D43)
    static let whiteGlass = adaptive(0xC5DFEF, 0xA7C7DE)
    static let whiteIdentityGlass = adaptive(0xD3E7F3, 0xB2CEE1)
    static let action = adaptive(0x43553B, 0x3F614D)
    static let chatBubble = adaptive(0xD6E3E8, 0x293F4B)
    static let selection = adaptive(0x3D5C42, 0xB4D1B1)
    static let conditional = adaptive(0x865423, 0xE9C28A)
    static let cream = adaptive(0xF3FAFF, 0xE9F4FC)
    static let keyline = adaptive(0xF3FAFF, 0x152A39)
    static let treeGuide = adaptive(0x526A7A, 0xAAC1D0)
    static let idle = adaptive(0xCBDCE4, 0x2C4352)
    static let blackSurfaceTop = adaptive(0x214D67, 0x20445D)
    static let blackSurfaceBottom = adaptive(0x0C263B, 0x0C2233)
    static let whiteSurfaceTop = adaptive(0xB5D2E6, 0x9BBBD3)
    static let whiteSurfaceBottom = adaptive(0xE3F1F9, 0xBDD6E8)
    static let blackSolid = adaptive(0x13374F, 0x142F45)
    static let whiteForeground = adaptive(0x173A50, 0x112E43)
    static let blackAccent = adaptive(0xD1E4C6, 0xD7E9CE)
    static let whiteAccent = adaptive(0x3F583A, 0x2C472F)
    static let turnOutline = adaptive(0x526A43, 0xB5D1A1)
    static let turnGlow = adaptive(0xB3CB9E, 0xB7D2AA)
    static let blackBorder = adaptive(0xAECADD, 0x9DBFD5)
    static let whiteBorder = adaptive(0x526E82, 0x36586E)
    static let blackSecondary = adaptive(0xD2E3EC, 0xCBDDE9)
    static let whiteSecondary = adaptive(0x3D596D, 0x2D4A5F)
    static let darkModerator = adaptive(0xE6CBFA, 0xE6CBFA)
    static let lightModerator = adaptive(0x603681, 0x4E2B69)
    static let darkProfessional = adaptive(0xC2EABB, 0xC2EABB)
    static let lightProfessional = adaptive(0x2C592E, 0x21492C)
    static let darkSupporter = adaptive(0xF3DBA9, 0xF3DBA9)
    static let lightSupporter = adaptive(0x76451F, 0x633719)
    static let darkOrdinary = adaptive(0xBDE1FF, 0xBDE1FF)
    static let lightOrdinary = adaptive(0x225080, 0x173D67)
}

/// Felt pigments keep a warm daytime meadow and a muted moss night scene.
/// Dynamic color providers are retained rather than recreated on clock ticks.
private enum FeltMeadowColors {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }

    static let page = adaptive(0xEEE7D5, 0x172119)
    static let panel = adaptive(0xF6F1E4, 0x253027)
    static let foreground = adaptive(0x30382A, 0xEAECDD)
    static let detailSecondary = adaptive(0x555E44, 0xBFCAB5)
    static let panelBorder = adaptive(0x69734D, 0xA6B19A)
    static let blackGlass = adaptive(0x353B2E, 0x28342B)
    static let whiteGlass = adaptive(0xEEE4CE, 0xD3D6C1)
    static let whiteIdentityGlass = adaptive(0xF4EAD5, 0xD9DDCB)
    static let action = adaptive(0x495838, 0x3D563B)
    static let chatBubble = adaptive(0xE0E1CA, 0x344336)
    static let selection = adaptive(0x38552D, 0xBCD6A8)
    static let conditional = adaptive(0x70521D, 0xE3CA8C)
    static let cream = adaptive(0xFFF8E6, 0xF0F1E3)
    static let keyline = adaptive(0xFFF8E6, 0x172119)
    static let treeGuide = adaptive(0x69734D, 0xB0B79B)
    static let idle = adaptive(0xCCD0B5, 0x3C4B3B)
    static let blackSurfaceTop = adaptive(0x48513E, 0x3A483B)
    static let blackSurfaceBottom = adaptive(0x262D22, 0x1A251D)
    static let whiteSurfaceTop = adaptive(0xE3D8BD, 0xC0C8AE)
    static let whiteSurfaceBottom = adaptive(0xFFF8E6, 0xDEE1CD)
    static let blackSolid = adaptive(0x30372A, 0x27352B)
    static let whiteForeground = adaptive(0x30382A, 0x243222)
    static let blackAccent = adaptive(0xE4D397, 0xE8D8A8)
    static let whiteAccent = adaptive(0x495838, 0x364F2E)
    static let turnOutline = adaptive(0x856A27, 0xD0BD80)
    static let turnGlow = adaptive(0xBAA352, 0xD4C38D)
    static let blackBorder = adaptive(0xC0C6AA, 0xABBBA6)
    static let whiteBorder = adaptive(0x69734D, 0x5D6B4E)
    static let blackSecondary = adaptive(0xDEE0CF, 0xD9E1D1)
    static let whiteSecondary = adaptive(0x555E44, 0x3E4C35)
    static let darkModerator = adaptive(0xE0C7F3, 0xE0C7F3)
    static let lightModerator = adaptive(0x633889, 0x4D2D66)
    static let darkProfessional = adaptive(0xBCE6B3, 0xBCE6B3)
    static let lightProfessional = adaptive(0x245925, 0x244A28)
    static let darkSupporter = adaptive(0xF3D69A, 0xF3D69A)
    static let lightSupporter = adaptive(0x704515, 0x5B3B15)
    static let darkOrdinary = adaptive(0xBDD9F9, 0xBDD9F9)
    static let lightOrdinary = adaptive(0x245382, 0x223F5E)
}

// MARK: - Game Detail surfaces

extension SurroundTheme {
    /// The page behind the game when the theme has no scene.
    var pageBackground: Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkUsesColor ? FlowingInkColors.jadePage : FlowingInkColors.monoPage
        case .standard: Color(uiColor: .systemGroupedBackground)
        case .nebulaPearl: Color(themeHex: 0x070A1C)
        case .rakedGarden: RakedGardenColors.page
        case .surroundStudio: SurroundStudioColors.page
        case .frostPine: FrostPineColors.page
        case .feltMeadow: FeltMeadowColors.page
        case .nightGarden: NightGardenColors.page
        case .christmasKeepsakes: ChristmasKeepsakesColors.page
        }
    }

    var panel: Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkUsesColor ? FlowingInkColors.jadePanel : FlowingInkColors.monoPanel
        case .standard: Color(uiColor: .secondarySystemGroupedBackground)
        case .nebulaPearl: Color(themeHex: 0x141938)
        case .rakedGarden: RakedGardenColors.panel
        case .surroundStudio: SurroundStudioColors.panel
        case .frostPine: FrostPineColors.panel
        case .feltMeadow: FeltMeadowColors.panel
        case .nightGarden: NightGardenColors.panel
        case .christmasKeepsakes: ChristmasKeepsakesColors.panel
        }
    }

    var foreground: Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkUsesColor ? FlowingInkColors.jadeForeground : FlowingInkColors.monoForeground
        case .standard, .nebulaPearl: .primary
        case .rakedGarden: RakedGardenColors.foreground
        case .surroundStudio: SurroundStudioColors.foreground
        case .frostPine: FrostPineColors.foreground
        case .feltMeadow: FeltMeadowColors.foreground
        case .nightGarden: NightGardenColors.foreground
        case .christmasKeepsakes: ChristmasKeepsakesColors.foreground
        }
    }

    /// Secondary information in opaque detail panels needs its own pigment;
    /// hierarchical opacity becomes too faint over the meadow's cream.
    var detailSecondaryForeground: Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkUsesColor ? FlowingInkColors.jadeSecondary : FlowingInkColors.monoSecondary
        case .feltMeadow: FeltMeadowColors.detailSecondary
        case .nightGarden: NightGardenColors.detailSecondary
        case .christmasKeepsakes: ChristmasKeepsakesColors.detailSecondary
        default: .secondary
        }
    }

    var panelBorder: Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            foreground.opacity(0.22)
        case .standard:
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 56 / 255, green: 56 / 255, blue: 58 / 255, alpha: 1)
                    : UIColor.black.withAlphaComponent(0.12)
            })
        case .nebulaPearl: Color.white.opacity(0.14)
        case .rakedGarden: RakedGardenColors.panelBorder.opacity(0.28)
        case .surroundStudio: SurroundStudioColors.panelBorder.opacity(0.28)
        case .frostPine: FrostPineColors.panelBorder.opacity(0.28)
        case .feltMeadow: FeltMeadowColors.panelBorder.opacity(0.28)
        case .nightGarden: NightGardenColors.panelBorder.opacity(0.28)
        case .christmasKeepsakes: ChristmasKeepsakesColors.panelBorder.opacity(0.28)
        }
    }

    /// Whether screens use the theme's scene layout and surfaces, including
    /// the paper-only presentations. Hiding artwork must not remove cards,
    /// alter spacing, or fall back to the system page palette.
    var hasScene: Bool { self != .standard }

    /// Whether the scene includes decorative artwork behind its surfaces.
    var showsSceneArt: Bool { hasScene && self != .flowingInkJadePlain && self != .flowingInkPlain }

    /// Clocks, player chips and the main action are tinted Liquid Glass,
    /// letting the scene show through; other themes keep solid surfaces.
    var usesGlassControls: Bool { self != .standard && self != .feltMeadow && !isFlowingInk }

    /// The natural scenes use their own foregrounds, translucent pigment
    /// on older systems, and opaque controls under Increase Contrast.
    var usesLightSceneSurfaces: Bool { isFlowingInk || self == .rakedGarden || self == .surroundStudio || self == .frostPine || self == .feltMeadow || self == .nightGarden || self == .christmasKeepsakes }

    /// Tinted Liquid Glass for a player's clock, in the stone's color.
    /// Light stones use a strong tint to preserve their material color over
    /// the scene; dark ones retain enough pigment for light clock text.
    func clockGlassTint(_ color: StoneColor) -> Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            clockSolidSurface(color).opacity(color == .black ? 0.90 : 0.96)
        case .standard: .clear
        case .nebulaPearl:
            color == .black ? Color(themeHex: 0x3B2585).opacity(0.47) : Color(themeHex: 0xFBF1EC).opacity(0.95)
        case .rakedGarden:
            color == .black ? RakedGardenColors.blackGlass.opacity(0.84) : RakedGardenColors.whiteGlass.opacity(0.72)
        case .surroundStudio:
            color == .black ? SurroundStudioColors.blackGlass.opacity(0.82) : SurroundStudioColors.whiteGlass.opacity(0.84)
        case .frostPine:
            color == .black ? FrostPineColors.blackGlass.opacity(0.82) : FrostPineColors.whiteGlass.opacity(0.84)
        case .feltMeadow:
            color == .black ? FeltMeadowColors.blackGlass.opacity(0.82) : FeltMeadowColors.whiteGlass.opacity(0.84)
        case .nightGarden:
            color == .black ? NightGardenColors.blackGlass.opacity(0.82) : NightGardenColors.whiteGlass.opacity(0.84)
        case .christmasKeepsakes:
            color == .black ? ChristmasKeepsakesColors.blackGlass.opacity(0.82) : ChristmasKeepsakesColors.whiteGlass.opacity(0.84)
        }
    }

    /// Tinted Liquid Glass for a player chip, using the same stone family
    /// as its clock.
    func identityGlassTint(_ color: StoneColor) -> Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            clockSolidSurface(color).opacity(color == .black ? 0.94 : 0.96)
        case .standard: .clear
        case .nebulaPearl:
            color == .black ? Color(themeHex: 0x241858).opacity(0.51) : Color(themeHex: 0xF8EFEB).opacity(0.93)
        case .rakedGarden:
            color == .black ? RakedGardenColors.blackGlass.opacity(0.86) : RakedGardenColors.whiteSurfaceBottom.opacity(0.78)
        case .surroundStudio:
            color == .black ? SurroundStudioColors.blackGlass.opacity(0.86) : SurroundStudioColors.whiteIdentityGlass.opacity(0.90)
        case .frostPine:
            color == .black ? FrostPineColors.blackGlass.opacity(0.86) : FrostPineColors.whiteIdentityGlass.opacity(0.90)
        case .feltMeadow:
            color == .black ? FeltMeadowColors.blackGlass.opacity(0.86) : FeltMeadowColors.whiteIdentityGlass.opacity(0.90)
        case .nightGarden:
            color == .black ? NightGardenColors.blackGlass.opacity(0.86) : NightGardenColors.whiteIdentityGlass.opacity(0.90)
        case .christmasKeepsakes:
            color == .black ? ChristmasKeepsakesColors.blackGlass.opacity(0.86) : ChristmasKeepsakesColors.whiteIdentityGlass.opacity(0.90)
        }
    }

    /// The main action's tint; nil keeps the app's accent.
    var actionTint: Color? {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkAction
        case .standard: nil
        // Deep violet: white text at about 8:1, and close to the violet clock.
        case .nebulaPearl: Color(themeHex: 0x4E36B0)
        case .rakedGarden: RakedGardenColors.maple
        case .surroundStudio: SurroundStudioColors.action
        case .frostPine: FrostPineColors.action
        case .feltMeadow: FeltMeadowColors.action
        case .nightGarden: NightGardenColors.action
        case .christmasKeepsakes: ChristmasKeepsakesColors.action
        }
    }

    /// Glass pigment is independent of the opaque accessibility fill.
    var actionGlassTint: Color? {
        switch self {
        case .surroundStudio: actionTint?.opacity(0.86)
        case .frostPine: actionTint?.opacity(0.86)
        case .feltMeadow: actionTint?.opacity(0.86)
        case .nightGarden: actionTint?.opacity(0.86)
        case .christmasKeepsakes: actionTint?.opacity(0.86)
        case .rakedGarden: actionTint?.opacity(0.88)
        default: actionTint
        }
    }


    /// Scene-specific coordinate inks follow their chat bubble appearance.
    /// Other themes keep the existing system-indigo treatment.
    var chatCoordinateForeground: Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkSelection
        case .nightGarden: NightGardenColors.selection
        case .christmasKeepsakes: ChristmasKeepsakesColors.selection
        default: Color(uiColor: .systemIndigo)
        }
    }

    /// Main-channel chat bubbles.
    var chatBubble: Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkUsesColor ? FlowingInkColors.jadeChat : FlowingInkColors.monoChat
        case .standard: Color(.systemGray4)
        case .nebulaPearl: Color(themeHex: 0x2C2F5E)
        case .rakedGarden: RakedGardenColors.chatBubble
        case .surroundStudio: SurroundStudioColors.chatBubble
        case .frostPine: FrostPineColors.chatBubble
        case .feltMeadow: FeltMeadowColors.chatBubble
        case .nightGarden: NightGardenColors.chatBubble
        case .christmasKeepsakes: ChristmasKeepsakesColors.chatBubble
        }
    }
}

// MARK: - Selection and status marks

extension SurroundTheme {
    /// The selected move in the Analyze tree and its board thumbnails.
    var selectionMark: Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkSelection
        case .standard: Color(uiColor: .systemTeal)
        // The chat highlight's cyan: the one cool accent among the violets.
        case .nebulaPearl: Color(themeHex: 0x6FD6FF)
        case .rakedGarden: RakedGardenColors.selection
        case .surroundStudio: SurroundStudioColors.selection
        case .frostPine: FrostPineColors.selection
        case .feltMeadow: FeltMeadowColors.selection
        case .nightGarden: NightGardenColors.selection
        case .christmasKeepsakes: ChristmasKeepsakesColors.selection
        }
    }

    /// Analyze tree moves that belong to the conditional-move plan; nil
    /// keeps the app's conditional-move color.
    var conditionalMark: Color? {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkUsesColor ? FlowingInkColors.jadeConditional : FlowingInkColors.monoSelection
        case .standard: nil
        case .nebulaPearl: Color(themeHex: 0xE0A86A)
        case .rakedGarden: RakedGardenColors.conditional
        case .surroundStudio: SurroundStudioColors.conditional
        case .frostPine: FrostPineColors.conditional
        case .feltMeadow: FeltMeadowColors.conditional
        case .nightGarden: NightGardenColors.conditional
        case .christmasKeepsakes: ChristmasKeepsakesColors.conditional
        }
    }

    /// A contrasting keyline between a tree mark and its stone; nil lets
    /// the mark touch the stone.
    var treeMarkKeyline: Color? {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            FlowingInkColors.keyline
        case .standard: nil
        case .nebulaPearl: Color(themeHex: 0x0B0E22)
        case .rakedGarden: RakedGardenColors.keyline
        case .surroundStudio: SurroundStudioColors.keyline
        case .frostPine: FrostPineColors.keyline
        case .feltMeadow: FeltMeadowColors.keyline
        case .nightGarden: NightGardenColors.keyline
        case .christmasKeepsakes: ChristmasKeepsakesColors.keyline
        }
    }

    /// The Analyze tree's guide at every fifth move.
    func treeGuide(scheme: ColorScheme) -> Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            foreground.opacity(0.16)
        case .standard: Color(scheme == .dark ? .systemGray6 : .systemGray4)
        case .nebulaPearl: Color(themeHex: 0xC9CFEA).opacity(0.2)
        case .rakedGarden: RakedGardenColors.treeGuide.opacity(0.25)
        case .surroundStudio: SurroundStudioColors.treeGuide.opacity(0.24)
        case .frostPine: FrostPineColors.treeGuide.opacity(0.24)
        case .feltMeadow: FeltMeadowColors.treeGuide.opacity(0.24)
        case .nightGarden: NightGardenColors.treeGuide.opacity(0.24)
        case .christmasKeepsakes: ChristmasKeepsakesColors.treeGuide.opacity(0.24)
        }
    }

    /// Active games where it is the user's turn; the clock's turn color.
    var userTurnMark: Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkSelection
        case .standard: Color(uiColor: .systemTeal)
        case .nebulaPearl: Color(themeHex: 0xC8B8FF)
        case .rakedGarden: RakedGardenColors.selection
        case .surroundStudio: SurroundStudioColors.selection
        case .frostPine: FrostPineColors.selection
        case .feltMeadow: FeltMeadowColors.selection
        case .nightGarden: NightGardenColors.selection
        case .christmasKeepsakes: ChristmasKeepsakesColors.selection
        }
    }

    /// A halo around the user's-turn mark, as around the running clock; nil
    /// draws the mark flat.
    var userTurnGlow: Color? {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            nil
        case .standard: nil
        case .nebulaPearl: Color(themeHex: 0xB7A4FF).opacity(0.85)
        case .rakedGarden, .surroundStudio, .frostPine, .feltMeadow, .nightGarden, .christmasKeepsakes: nil
        }
    }

    /// Active games in stone removal.
    var stoneRemovalMark: Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkUsesColor ? FlowingInkColors.jadeConditional : FlowingInkColors.monoSelection
        case .standard: Color(uiColor: .systemOrange)
        case .nebulaPearl: Color(themeHex: 0xF2B279)
        case .rakedGarden: RakedGardenColors.conditional
        case .surroundStudio: SurroundStudioColors.conditional
        case .frostPine: FrostPineColors.conditional
        case .feltMeadow: FeltMeadowColors.conditional
        case .nightGarden: NightGardenColors.conditional
        case .christmasKeepsakes: ChristmasKeepsakesColors.conditional
        }
    }

    /// Active games waiting on the opponent.
    func idleGameMark(scheme: ColorScheme) -> Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkUsesColor ? FlowingInkColors.jadeIdle : FlowingInkColors.monoIdle
        case .standard: Color(uiColor: scheme == .dark ? .systemGray5 : .systemBackground)
        case .nebulaPearl: Color(themeHex: 0x2A2F55)
        case .rakedGarden: RakedGardenColors.idle
        case .surroundStudio: SurroundStudioColors.idle
        case .frostPine: FrostPineColors.idle
        case .feltMeadow: FeltMeadowColors.idle
        case .nightGarden: NightGardenColors.idle
        case .christmasKeepsakes: ChristmasKeepsakesColors.idle
        }
    }
}

// MARK: - Clock cards and player identities

extension SurroundTheme {
    func clockSurfaceStops(_ color: StoneColor, scheme: ColorScheme) -> [Gradient.Stop] {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            return [.init(color: clockSolidSurface(color), location: 0),
                    .init(color: clockSolidSurface(color), location: 1)]
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
        case .frostPine:
            if color == .black {
                return [.init(color: FrostPineColors.blackSurfaceTop, location: 0),
                        .init(color: FrostPineColors.blackSurfaceBottom, location: 1)]
            }
            return [.init(color: FrostPineColors.whiteSurfaceTop, location: 0),
                    .init(color: FrostPineColors.whiteSurfaceBottom, location: 1)]
        case .feltMeadow:
            if color == .black {
                return [.init(color: FeltMeadowColors.blackSurfaceTop, location: 0),
                        .init(color: FeltMeadowColors.blackSurfaceBottom, location: 1)]
            }
            return [.init(color: FeltMeadowColors.whiteSurfaceTop, location: 0),
                    .init(color: FeltMeadowColors.whiteSurfaceBottom, location: 1)]
        case .nightGarden:
            if color == .black {
                return [.init(color: NightGardenColors.blackSurfaceTop, location: 0),
                        .init(color: NightGardenColors.blackSurfaceBottom, location: 1)]
            }
            return [.init(color: NightGardenColors.whiteSurfaceTop, location: 0),
                    .init(color: NightGardenColors.whiteSurfaceBottom, location: 1)]
        case .christmasKeepsakes:
            if color == .black {
                return [.init(color: ChristmasKeepsakesColors.blackSurfaceTop, location: 0),
                        .init(color: ChristmasKeepsakesColors.blackSurfaceBottom, location: 1)]
            }
            return [.init(color: ChristmasKeepsakesColors.whiteSurfaceTop, location: 0),
                    .init(color: ChristmasKeepsakesColors.whiteSurfaceBottom, location: 1)]
        }
    }

    /// The clock surface under Reduce Transparency or Increase Contrast.
    func clockSolidSurface(_ color: StoneColor) -> Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            color == .black
                ? (flowingInkUsesColor ? FlowingInkColors.jadeBlack : FlowingInkColors.monoBlack)
                : (flowingInkUsesColor ? FlowingInkColors.jadeWhite : FlowingInkColors.monoWhite)
        case .standard: color == .black ? Color(white: 0.06) : Color(white: 0.98)
        case .nebulaPearl: color == .black ? Color(themeHex: 0x1C1240) : Color(themeHex: 0xF6F0EA)
        case .rakedGarden: color == .black ? RakedGardenColors.blackSolid : RakedGardenColors.whiteGlass
        case .surroundStudio: color == .black ? SurroundStudioColors.blackSolid : SurroundStudioColors.whiteGlass
        case .frostPine: color == .black ? FrostPineColors.blackSolid : FrostPineColors.whiteGlass
        case .feltMeadow: color == .black ? FeltMeadowColors.blackSolid : FeltMeadowColors.whiteGlass
        case .nightGarden: color == .black ? NightGardenColors.blackSolid : NightGardenColors.whiteGlass
        case .christmasKeepsakes: color == .black ? ChristmasKeepsakesColors.blackSolid : ChristmasKeepsakesColors.whiteGlass
        }
    }

    func clockForeground(_ color: StoneColor, scheme: ColorScheme) -> Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            color == .black ? .white : .black
        case .standard: color == .black ? .white : Color(white: scheme == .dark ? 19 / 255 : 32 / 255)
        case .nebulaPearl: color == .black ? .white : Color(themeHex: 0x241D33)
        case .rakedGarden: color == .black ? RakedGardenColors.cream : RakedGardenColors.whiteForeground
        case .surroundStudio: color == .black ? SurroundStudioColors.cream : SurroundStudioColors.whiteForeground
        case .frostPine: color == .black ? FrostPineColors.cream : FrostPineColors.whiteForeground
        case .feltMeadow: color == .black ? FeltMeadowColors.cream : FeltMeadowColors.whiteForeground
        case .nightGarden: color == .black ? NightGardenColors.cream : NightGardenColors.whiteForeground
        case .christmasKeepsakes: color == .black ? ChristmasKeepsakesColors.cream : ChristmasKeepsakesColors.whiteForeground
        }
    }

    /// Icons and highlighted text on a clock outside sudden death.
    func clockAccent(_ color: StoneColor) -> Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            // White clocks keep dark text even when filled actions lighten
            // against the charcoal page. Metadata needs text-level contrast.
            color == .black ? .white : (flowingInkUsesColor ? FlowingInkColors.jadeInk : FlowingInkColors.ink)
        case .standard: Color(uiColor: .systemIndigo)
        case .nebulaPearl: color == .black ? Color(themeHex: 0xCDBEFF) : Color(themeHex: 0x5B3FC4)
        case .rakedGarden: color == .black ? RakedGardenColors.blackAccent : RakedGardenColors.whiteAccent
        case .surroundStudio: color == .black ? SurroundStudioColors.blackAccent : SurroundStudioColors.whiteAccent
        case .frostPine: color == .black ? FrostPineColors.blackAccent : FrostPineColors.whiteAccent
        case .feltMeadow: color == .black ? FeltMeadowColors.blackAccent : FeltMeadowColors.whiteAccent
        case .nightGarden: color == .black ? NightGardenColors.blackAccent : NightGardenColors.whiteAccent
        case .christmasKeepsakes: color == .black ? ChristmasKeepsakesColors.blackAccent : ChristmasKeepsakesColors.whiteAccent
        }
    }

    /// Keep the existing warning red on every daytime/other-theme clock.
    /// Pale night clocks need deeper red; dark clocks use brighter coral.
    func clockSuddenDeathAccent(_ color: StoneColor, scheme: ColorScheme) -> Color {
        if isFlowingInk, scheme == .dark, color == .white { return Color(themeHex: 0x7D293B) }
        if self == .nightGarden || self == .christmasKeepsakes { return Color(themeHex: color == .white ? 0x7D293B : 0xFFB5AF) }
        if self == .feltMeadow {
            return Color(themeHex: color == .white ? 0x7D2D2D : 0xFFADA1)
        }
        if self == .rakedGarden, scheme == .dark {
            return Color(themeHex: color == .white ? 0x6B2024 : 0xFF8277)
        }
        if self == .surroundStudio, scheme == .dark {
            return Color(themeHex: color == .white ? 0x7D2D2D : 0xFF9787)
        }
        if self == .frostPine {
            return Color(themeHex: color == .white ? 0x7B2433 : 0xFFACAC)
        }
        return color == .white ? Color(red: 0.75, green: 0.10, blue: 0.07)
            : Color(red: 1, green: 0.34, blue: 0.30)
    }

    /// The warning badge uses a solid pigment beneath its white text.
    func clockSuddenDeathBadge(scheme: ColorScheme) -> Color {
        if isFlowingInk, scheme == .dark { return Color(themeHex: 0x8B3449) }
        if self == .nightGarden || self == .christmasKeepsakes { return Color(themeHex: 0x8B3449) }
        if self == .frostPine { return Color(themeHex: 0x913748) }
        if self == .feltMeadow { return Color(themeHex: 0x8B3434) }
        if self == .surroundStudio, scheme == .dark {
            return Color(themeHex: 0x8B3434)
        }
        return .red
    }

    /// Scoring acceptance remains green, with a deeper pigment on night ivory.
    func clockAgreementAccent(_ color: StoneColor, scheme: ColorScheme) -> Color {
        if isFlowingInk, scheme == .dark, color == .white { return Color(themeHex: 0x284B31) }
        if self == .nightGarden || self == .christmasKeepsakes { return Color(themeHex: color == .white ? 0x284B31 : 0xBDDEA9) }
        if self == .frostPine {
            return Color(themeHex: color == .black ? 0xBCE7B8 : 0x254C30)
        }
        if self == .feltMeadow {
            return Color(themeHex: color == .black ? 0xB8D9A4 : 0x294D2B)
        }
        if self == .surroundStudio, scheme == .dark, color == .white {
            return Color(themeHex: 0x244B2F)
        }
        return color == .black ? Color(red: 125 / 255, green: 210 / 255, blue: 141 / 255)
            : Color(red: 30 / 255, green: 122 / 255, blue: 52 / 255)
    }

    /// The auto-resign countdown and disconnected label share an amber accent.
    func clockDisconnectedAccent(_ color: StoneColor, scheme: ColorScheme) -> Color {
        if isFlowingInk, scheme == .dark, color == .white { return Color(themeHex: 0x633D15) }
        if self == .nightGarden || self == .christmasKeepsakes { return Color(themeHex: color == .white ? 0x633D15 : 0xF3D39B) }
        if self == .frostPine {
            return Color(themeHex: color == .black ? 0xF2D09C : 0x603814)
        }
        if self == .feltMeadow {
            return Color(themeHex: color == .black ? 0xECD293 : 0x664516)
        }
        if self == .surroundStudio, scheme == .dark, color == .white {
            return Color(themeHex: 0x6C3D15)
        }
        return color == .black ? Color(red: 1, green: 159 / 255, blue: 10 / 255)
            : Color(red: 160 / 255, green: 72 / 255, blue: 0)
    }

    /// Inline undo text sits directly on the player's clock, without a badge.
    func clockUndoAccent(_ color: StoneColor, scheme: ColorScheme) -> Color {
        if isFlowingInk, scheme == .dark {
            return Color(themeHex: color == .black ? 0xE8C891 : 0x6B431C)
        }
        if self == .nightGarden || self == .christmasKeepsakes { return Color(themeHex: color == .white ? 0x633D15 : 0xF3D39B) }
        if self == .frostPine {
            return Color(themeHex: color == .black ? 0xF2D09C : 0x603814)
        }
        if self == .feltMeadow {
            return Color(themeHex: color == .black ? 0xECD293 : 0x664516)
        }
        if self == .surroundStudio, scheme == .dark {
            return Color(themeHex: color == .black ? 0xE8C186 : 0x6C3D15)
        }
        return Color(red: 196 / 255, green: 106 / 255, blue: 0)
    }

    /// The full undo badge needs its own darker amber beneath white text.
    func clockUndoBadge(scheme: ColorScheme) -> Color {
        if isFlowingInk, scheme == .dark { return Color(themeHex: 0x795022) }
        if self == .nightGarden || self == .christmasKeepsakes { return Color(themeHex: 0x79501F) }
        if self == .frostPine { return Color(themeHex: 0x795022) }
        if self == .feltMeadow { return Color(themeHex: 0x73511E) }
        if self == .surroundStudio, scheme == .dark {
            return Color(themeHex: 0x835122)
        }
        return Color(red: 196 / 255, green: 106 / 255, blue: 0)
    }

    /// The running clock's outline outside sudden death.
    func turnOutline(scheme: ColorScheme) -> Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkUsesColor ? FlowingInkColors.jadeTurnOutline : FlowingInkColors.monoTurnOutline
        case .standard:
            scheme == .dark
                ? Color(red: 125 / 255, green: 122 / 255, blue: 1)
                : Color(red: 88 / 255, green: 86 / 255, blue: 214 / 255)
        case .nebulaPearl: Color(themeHex: 0xC8B8FF)
        // Daytime uses a deeper amber edge against pale jade; night uses
        // brighter lantern light against the surrounding dark garden.
        case .rakedGarden: RakedGardenColors.turnOutline
        case .surroundStudio: SurroundStudioColors.turnOutline
        case .frostPine: FrostPineColors.turnOutline
        case .feltMeadow: FeltMeadowColors.turnOutline
        case .nightGarden: NightGardenColors.turnOutline
        case .christmasKeepsakes: ChristmasKeepsakesColors.turnOutline
        }
    }

    /// The running clock's halo outside sudden death.
    var turnGlow: Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            .clear
        case .standard: Color(uiColor: .systemIndigo)
        case .nebulaPearl: Color(themeHex: 0xB7A4FF)
        case .rakedGarden: RakedGardenColors.turnGlow
        case .surroundStudio: SurroundStudioColors.turnGlow
        case .frostPine: FrostPineColors.turnGlow
        case .feltMeadow: FeltMeadowColors.turnGlow
        case .nightGarden: NightGardenColors.turnGlow
        case .christmasKeepsakes: ChristmasKeepsakesColors.turnGlow
        }
    }

    /// The status capsule (Your move, reconnecting) behind white text.
    var statusBadge: Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkAction
        case .standard: Color(uiColor: .systemIndigo)
        case .nebulaPearl: Color(themeHex: 0x6A4FD6)
        // Maple carries the badge's white text at over 6:1. Lantern amber
        // remains the turn glow; it is too light for white status text.
        case .rakedGarden: RakedGardenColors.maple
        case .surroundStudio: SurroundStudioColors.action
        case .frostPine: FrostPineColors.action
        case .feltMeadow: FeltMeadowColors.action
        case .nightGarden: NightGardenColors.action
        case .christmasKeepsakes: ChristmasKeepsakesColors.action
        }
    }

    func identityChipColors(_ color: StoneColor) -> [Color] {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            [clockSolidSurface(color), clockSolidSurface(color)]
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
        case .frostPine:
            color == .black
                ? [FrostPineColors.blackSurfaceTop, FrostPineColors.blackSurfaceBottom]
                : [FrostPineColors.whiteSurfaceTop, FrostPineColors.whiteSurfaceBottom]
        case .feltMeadow:
            color == .black
                ? [FeltMeadowColors.blackSurfaceTop, FeltMeadowColors.blackSurfaceBottom]
                : [FeltMeadowColors.whiteSurfaceTop, FeltMeadowColors.whiteSurfaceBottom]
        case .nightGarden:
            color == .black
                ? [NightGardenColors.blackSurfaceTop, NightGardenColors.blackSurfaceBottom]
                : [NightGardenColors.whiteSurfaceTop, NightGardenColors.whiteSurfaceBottom]
        case .christmasKeepsakes:
            color == .black
                ? [ChristmasKeepsakesColors.blackSurfaceTop, ChristmasKeepsakesColors.blackSurfaceBottom]
                : [ChristmasKeepsakesColors.whiteSurfaceTop, ChristmasKeepsakesColors.whiteSurfaceBottom]
        }
    }

    func identityChipBorder(_ color: StoneColor) -> Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            color == .black ? FlowingInkColors.blackBorder : Color.black.opacity(0.55)
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
        case .frostPine:
            color == .black
                ? FrostPineColors.blackBorder.opacity(0.3)
                : FrostPineColors.whiteBorder.opacity(0.35)
        case .feltMeadow:
            color == .black
                ? FeltMeadowColors.blackBorder.opacity(0.3)
                : FeltMeadowColors.whiteBorder.opacity(0.35)
        case .nightGarden:
            color == .black
                ? NightGardenColors.blackBorder.opacity(0.3)
                : NightGardenColors.whiteBorder.opacity(0.35)
        case .christmasKeepsakes:
            color == .black
                ? ChristmasKeepsakesColors.blackBorder.opacity(0.3)
                : ChristmasKeepsakesColors.whiteBorder.opacity(0.35)
        }
    }

    func identityForeground(_ color: StoneColor) -> Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            color == .black ? .white : .black
        case .standard: color == .black ? .white : Color(white: 32 / 255)
        case .nebulaPearl: color == .black ? .white : Color(themeHex: 0x241D33)
        case .rakedGarden: color == .black ? RakedGardenColors.cream : RakedGardenColors.whiteForeground
        case .surroundStudio: color == .black ? SurroundStudioColors.cream : SurroundStudioColors.whiteForeground
        case .frostPine: color == .black ? FrostPineColors.cream : FrostPineColors.whiteForeground
        case .feltMeadow: color == .black ? FeltMeadowColors.cream : FeltMeadowColors.whiteForeground
        case .nightGarden: color == .black ? NightGardenColors.cream : NightGardenColors.whiteForeground
        case .christmasKeepsakes: color == .black ? ChristmasKeepsakesColors.cream : ChristmasKeepsakesColors.whiteForeground
        }
    }

    func identitySecondary(_ color: StoneColor) -> Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            color == .black ? Color(themeHex: 0xDADADA) : Color(themeHex: 0x555555)
        case .standard:
            color == .black ? Color(white: 174 / 255) : Color(red: 108 / 255, green: 108 / 255, blue: 112 / 255)
        case .nebulaPearl:
            color == .black ? Color(themeHex: 0xC9BEEB) : Color(themeHex: 0x5E5670)
        case .rakedGarden:
            color == .black ? RakedGardenColors.blackSecondary : RakedGardenColors.whiteSecondary
        case .surroundStudio:
            color == .black ? SurroundStudioColors.blackSecondary : SurroundStudioColors.whiteSecondary
        case .frostPine:
            color == .black ? FrostPineColors.blackSecondary : FrostPineColors.whiteSecondary
        case .feltMeadow:
            color == .black ? FeltMeadowColors.blackSecondary : FeltMeadowColors.whiteSecondary
        case .nightGarden:
            color == .black ? NightGardenColors.blackSecondary : NightGardenColors.whiteSecondary
        case .christmasKeepsakes:
            color == .black ? ChristmasKeepsakesColors.blackSecondary : ChristmasKeepsakesColors.whiteSecondary
        }
    }

    /// The natural themes keep OGS's role hues while adapting their
    /// lightness to the dark or pale chip.
    func identityRoleColor(for player: OGSUser, on color: StoneColor) -> Color? {
        guard usesLightSceneSurfaces else { return nil }
        let darkSurface = color == .black
        if isFlowingInk, !flowingInkUsesColor { return identityForeground(color) }
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
        if self == .frostPine {
            if player.isOGSModerator || player.isOGSAdmin {
                return darkSurface ? FrostPineColors.darkModerator : FrostPineColors.lightModerator
            }
            if player.isOGSProfessional {
                return darkSurface ? FrostPineColors.darkProfessional : FrostPineColors.lightProfessional
            }
            if player.isOGSSupporter {
                return darkSurface ? FrostPineColors.darkSupporter : FrostPineColors.lightSupporter
            }
            if player.isBot == true || player.uiClass?.contains("bot") == true {
                return identitySecondary(color)
            }
            return darkSurface ? FrostPineColors.darkOrdinary : FrostPineColors.lightOrdinary
        }
        if self == .feltMeadow {
            if player.isOGSModerator || player.isOGSAdmin {
                return darkSurface ? FeltMeadowColors.darkModerator : FeltMeadowColors.lightModerator
            }
            if player.isOGSProfessional {
                return darkSurface ? FeltMeadowColors.darkProfessional : FeltMeadowColors.lightProfessional
            }
            if player.isOGSSupporter {
                return darkSurface ? FeltMeadowColors.darkSupporter : FeltMeadowColors.lightSupporter
            }
            if player.isBot == true || player.uiClass?.contains("bot") == true {
                return identitySecondary(color)
            }
            return darkSurface ? FeltMeadowColors.darkOrdinary : FeltMeadowColors.lightOrdinary
        }
        if self == .nightGarden {
            if player.isOGSModerator || player.isOGSAdmin {
                return darkSurface ? NightGardenColors.darkModerator : NightGardenColors.lightModerator
            }
            if player.isOGSProfessional {
                return darkSurface ? NightGardenColors.darkProfessional : NightGardenColors.lightProfessional
            }
            if player.isOGSSupporter {
                return darkSurface ? NightGardenColors.darkSupporter : NightGardenColors.lightSupporter
            }
            if player.isBot == true || player.uiClass?.contains("bot") == true {
                return identitySecondary(color)
            }
            return darkSurface ? NightGardenColors.darkOrdinary : NightGardenColors.lightOrdinary
        }
        if self == .christmasKeepsakes {
            if player.isOGSModerator || player.isOGSAdmin {
                return darkSurface ? ChristmasKeepsakesColors.darkModerator : ChristmasKeepsakesColors.lightModerator
            }
            if player.isOGSProfessional {
                return darkSurface ? ChristmasKeepsakesColors.darkProfessional : ChristmasKeepsakesColors.lightProfessional
            }
            if player.isOGSSupporter {
                return darkSurface ? ChristmasKeepsakesColors.darkSupporter : ChristmasKeepsakesColors.lightSupporter
            }
            if player.isBot == true || player.uiClass?.contains("bot") == true {
                return identitySecondary(color)
            }
            return darkSurface ? ChristmasKeepsakesColors.darkOrdinary : ChristmasKeepsakesColors.lightOrdinary
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

    /// The running hourglass on a Home clock chip. Standard's indigo is too
    /// dark for its black chip, so Home uses the canvas's lighter indigo there.
    func homeChipAccent(_ color: StoneColor) -> Color {
        guard self == .standard else { return clockAccent(color) }
        return color == .black
            ? Color(red: 165 / 255, green: 163 / 255, blue: 1)
            : Color(red: 88 / 255, green: 86 / 255, blue: 214 / 255)
    }

    /// Text links sit directly on Home's cards. Night Garden's bronze/lantern
    /// ink follows the card, independently of its darker filled-button pigment.
    var homeActionForeground: Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkSelection
        case .nightGarden: NightGardenColors.conditional
        case .christmasKeepsakes: ChristmasKeepsakesColors.conditional
        default: actionTint ?? .accentColor
        }
    }

    /// Home's New game fill. Standard deepens the app's indigo so the white
    /// title stays readable in both appearances.
    var homeActionFill: Color {
        actionTint ?? Color(red: 80 / 255, green: 78 / 255, blue: 206 / 255)
    }

    /// A player's name color on a dark or light surface: the theme's role
    /// hues where it has them, otherwise OGS's, in the surface's variant.
    func roleColor(for player: OGSUser, on surface: StoneColor) -> Color {
        if let roleColor = identityRoleColor(for: player, on: surface) {
            return roleColor
        }
        if surface == .white, !player.isOGSModerator, !player.isOGSAdmin {
            if player.isOGSProfessional { return Color(red: 15 / 255, green: 107 / 255, blue: 51 / 255) }
            if player.isOGSSupporter { return Color(red: 153 / 255, green: 71 / 255, blue: 8 / 255) }
        }
        // The surface decides the role variant even in the opposite system
        // appearance, just as a white stone remains white in Dark Mode.
        let traits = UITraitCollection(userInterfaceStyle: surface == .black ? .dark : .light)
        return Color(uiColor: UIColor(player.uiColor).resolvedColor(with: traits))
    }
}

// MARK: - Flowing Ink

private enum FlowingInkColors {
    private static func adaptive(_ light: UInt, _ dark: UInt) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xff) / 255,
                           green: CGFloat((hex >> 8) & 0xff) / 255,
                           blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        })
    }

    // Board inks stay explicit; page ink and filled-button pigment have
    // different jobs in Dark Mode and must not share the board's colors.
    static let ink = Color(themeHex: 0x171717)
    static let jade = Color(themeHex: 0xDDE7DB)
    static let jadeInk = Color(themeHex: 0x28513F)
    static let ochre = Color(themeHex: 0x6B4C22)
    static let monoPage = adaptive(0xFFFFFF, 0x242424)
    static let jadePage = adaptive(0xFFFFFF, 0x242A27)
    static let monoPanel = adaptive(0xFAFAFA, 0x2D2D2D)
    static let jadePanel = adaptive(0xFAFAFA, 0x2A332E)
    static let monoForeground = adaptive(0x171717, 0xF1F1F1)
    static let jadeForeground = adaptive(0x171717, 0xEAF0EB)
    static let monoSecondary = adaptive(0x555555, 0xC5C5C5)
    static let jadeSecondary = adaptive(0x555555, 0xC2CCC4)
    static let monoChat = adaptive(0xECECEC, 0x393939)
    static let jadeChat = adaptive(0xE1E9E0, 0x39463D)
    static let monoAction = adaptive(0x171717, 0x6E6E6E)
    static let jadeAction = adaptive(0x28513F, 0x4D7B61)
    static let monoSelection = adaptive(0x171717, 0xE0E0E0)
    static let jadeSelection = adaptive(0x28513F, 0xB7D6BF)
    static let jadeConditional = adaptive(0x6B4C22, 0xE1C391)
    static let keyline = adaptive(0xFFFFFF, 0x171717)
    static let monoIdle = adaptive(0xE5E5E5, 0x484848)
    static let jadeIdle = adaptive(0xDFE7DD, 0x414E45)
    static let monoBlack = adaptive(0x000000, 0x0B0B0B)
    static let jadeBlack = adaptive(0x000000, 0x0A0C0B)
    static let monoWhite = adaptive(0xFFFFFF, 0xDADADA)
    static let jadeWhite = adaptive(0xFFFFFF, 0xD9DEDA)
    static let blackBorder = adaptive(0x666666, 0x999999)
    static let monoTurnOutline = adaptive(0x171717, 0x777777)
    static let jadeTurnOutline = adaptive(0x28513F, 0x617F67)
}

extension SurroundTheme {
    private var flowingInkAction: Color {
        flowingInkUsesColor ? FlowingInkColors.jadeAction : FlowingInkColors.monoAction
    }

    private var flowingInkSelection: Color {
        flowingInkUsesColor ? FlowingInkColors.jadeSelection : FlowingInkColors.monoSelection
    }

    private var flowingInkBoard: BoardAppearance {
        let paper = flowingInkUsesColor ? FlowingInkColors.jade : Color.white
        let accent = flowingInkUsesColor ? FlowingInkColors.jadeInk : FlowingInkColors.ink
        return BoardAppearance(
            boardColor: paper,
            compactBoardColor: paper,
            boardEdge: Color.black.opacity(0.7),
            usesShadedStones: false,
            castsBoardShadow: false,
            gridColor: .black,
            coordinateColor: .black,
            black: StonePalette(highlight: .black, shade: .black, flat: .black,
                                lastMove: .white, label: .white),
            white: StonePalette(highlight: .white, shade: .white, flat: .white,
                                outline: .black, lastMove: .black, label: .black),
            emptyPointMarker: .black,
            markOutline: .black,
            dameColor: flowingInkUsesColor ? FlowingInkColors.ochre : FlowingInkColors.ink,
            highlightColor: accent,
            highlightCasing: .white,
            crosshair: .init(valid: accent, invalid: flowingInkUsesColor ? Color(themeHex: 0x842F34) : .black,
                             removal: accent),
            crosshairWidth: 1.5,
            removeMark: flowingInkUsesColor ? Color(themeHex: 0x842F34) : .black,
            restoreMark: accent,
            removalMarkCasing: .white,
            removedStoneOutline: .black
        )
    }
}

private enum FlowingInkAssets {
    static let portrait = UIImage(named: "FlowingInkLandscapePortrait")
    static let landscape = UIImage(named: "FlowingInkLandscapeLandscape")
}

/// The paintings are separated through their mist into four corner plates.
/// Every plate uses the same uniform scale; spare viewport width or height
/// becomes quiet paper between them rather than stretched trees or cliffs.
struct FlowingInkSceneLayout: Equatable {
    enum Composition: CaseIterable {
        case portrait, landscape

        var sourceSize: CGSize {
            self == .portrait ? CGSize(width: 1024, height: 1536) : CGSize(width: 1536, height: 1024)
        }
    }

    enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        var isTrailing: Bool { self == .topRight || self == .bottomRight }
        var isBottom: Bool { self == .bottomLeft || self == .bottomRight }
    }

    let size: CGSize
    let composition: Composition
    let scale: CGFloat
    let imageSize: CGSize

    static let horizontalTransition: ClosedRange<CGFloat> = 0.44...0.56

    init(size: CGSize) {
        let width = size.width.isFinite ? max(0, size.width) : 0
        let height = size.height.isFinite ? max(0, size.height) : 0
        self.size = CGSize(width: width, height: height)
        composition = width > height ? .landscape : .portrait
        let source = composition.sourceSize
        scale = min(width / source.width, height / source.height)
        imageSize = CGSize(width: source.width * scale, height: source.height * scale)
    }

    func frame(for corner: Corner) -> CGRect {
        CGRect(x: corner.isTrailing ? size.width - imageSize.width : 0,
               y: corner.isBottom ? size.height - imageSize.height : 0,
               width: imageSize.width, height: imageSize.height)
    }

    /// The waterfall extends well below the midpoint of the source. Its
    /// left-hand feather starts only after the falling water reaches mist.
    /// The right-hand split sits in empty paper above the foreground pine.
    func verticalTransition(for corner: Corner) -> ClosedRange<CGFloat> {
        if corner.isTrailing { return 0.44...0.56 }
        return composition == .portrait ? 0.70...0.78 : 0.74...0.82
    }

    /// Normalized source regions retained at full opacity, useful when
    /// checking that a composition change preserves its subject landmarks.
    func opaqueSourceBounds(for corner: Corner) -> CGRect {
        let horizontal = Self.horizontalTransition
        let vertical = verticalTransition(for: corner)
        let x = corner.isTrailing ? horizontal.upperBound : 0
        let y = corner.isBottom ? vertical.upperBound : 0
        return CGRect(x: x, y: y,
                      width: corner.isTrailing ? 1 - x : horizontal.lowerBound,
                      height: corner.isBottom ? 1 - y : vertical.lowerBound)
    }
}

/// Corner-anchored scenery keeps the waterfall and pine visible at their
/// natural proportions on phones, tablets, narrow windows and Duo layouts.
/// Switching presentation changes only pigment/opacity; the layers remain
/// mounted beneath chat, analysis and Zen.
private struct FlowingInkScene: View {
    @Environment(\.colorScheme) private var colorScheme
    let usesColor: Bool
    let showsLandscape: Bool

    var body: some View {
        GeometryReader { geometry in
            let layout = FlowingInkSceneLayout(size: geometry.size)
            let paper = usesColor ? FlowingInkColors.jadePage : FlowingInkColors.monoPage
            ZStack {
                paper
                ZStack(alignment: .topLeading) {
                    // White paper lets masked plates overlap as ink washes;
                    // no plate's paper can erase its neighbor's edge art.
                    Color.white
                    if let image = layout.composition == .landscape
                        ? FlowingInkAssets.landscape : FlowingInkAssets.portrait {
                        ForEach(FlowingInkSceneLayout.Corner.allCases, id: \.self) { corner in
                            let frame = layout.frame(for: corner)
                            Image(uiImage: image)
                                .resizable()
                                .frame(width: frame.width, height: frame.height)
                                .mask(fade(FlowingInkSceneLayout.horizontalTransition,
                                           keepsStart: !corner.isTrailing,
                                           start: .leading, end: .trailing))
                                .mask(fade(layout.verticalTransition(for: corner),
                                           keepsStart: !corner.isBottom,
                                           start: .top, end: .bottom))
                                .position(x: frame.midX, y: frame.midY)
                                .blendMode(.multiply)
                        }
                    }
                }
                .frame(width: layout.size.width, height: layout.size.height)
                .compositingGroup()
                .saturation(usesColor ? 1 : 0)
                // Grade the same ink onto charcoal paper rather than
                // inverting it into luminous white silhouettes.
                .colorMultiply(colorScheme == .dark ? paper : .white)
                .opacity(showsLandscape ? 1 : 0)
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func fade(_ transition: ClosedRange<CGFloat>, keepsStart: Bool,
                      start: UnitPoint, end: UnitPoint) -> LinearGradient {
        let first = keepsStart ? Color.white : .clear
        let last = keepsStart ? Color.clear : .white
        return LinearGradient(stops: [
            .init(color: first, location: 0),
            .init(color: first, location: transition.lowerBound),
            .init(color: last, location: transition.upperBound),
            .init(color: last, location: 1)
        ], startPoint: start, endPoint: end)
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
    /// Applies a theme to a screen that wears it (Game Detail, Home, Settings,
    /// Public games, Game history): its
    /// surfaces, board and appearance. `ownsWindow` lets a screen that is
    /// leaving keep its look without holding the window's appearance.
    func surroundTheme(_ theme: SurroundTheme, ownsWindow: Bool = true) -> some View {
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
            .modifier(GameDetailLegacyTint(color: (theme.isFlowingInk || theme == .feltMeadow || theme == .nightGarden || theme == .christmasKeepsakes) ? theme.foreground : .accentColor))
            .toolbarColorScheme(theme.colorScheme, for: .navigationBar, .bottomBar)
            .background(WindowInterfaceStyle(colorScheme: ownsWindow ? theme.colorScheme : nil))
    }
}

extension View {
    /// Holds the window in this appearance while the view is in it, and gives
    /// the window back afterwards; nil asks nothing of it. The window's
    /// appearance also reaches screens, sheets and bars outside this view.
    func surroundWindowAppearance(_ colorScheme: ColorScheme?) -> some View {
        background(WindowInterfaceStyle(colorScheme: colorScheme))
    }
}

/// Earlier SwiftUI toolbar controls use the inherited tint for their unbacked
/// symbols. The tint stays scoped to SwiftUI content and never changes UIKit
/// appearance or the window tint. Modern glass keeps its existing styling.
struct GameDetailLegacyTint: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            content
        } else {
            content.tint(color)
        }
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

/// A flat, stone-contrasting turn cue that also reads when a compact clock
/// omits its status label or shows a score estimate. The stroke stays inside
/// the solid clock face, so landscape colors cannot reduce its contrast.
struct FlowingInkClockOutline: View {
    let color: StoneColor
    let isRunning: Bool
    var cornerRadius: CGFloat = 12
    @Environment(\.surroundTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let increased = contrast == .increased
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(
                theme.clockForeground(color, scheme: colorScheme)
                    .opacity(isRunning ? 1 : (increased ? 0.5 : 0.22)),
                lineWidth: isRunning ? (increased ? 4 : 3) : (increased ? 2 : 1)
            )
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

/// Material themes use a contrast-checked pigment on detail panels.
/// Other themes retain their hierarchical secondary style.
struct GameDetailSecondaryText: ViewModifier {
    @Environment(\.surroundTheme) private var theme

    @ViewBuilder func body(content: Content) -> some View {
        if theme.isFlowingInk || theme == .feltMeadow || theme == .nightGarden || theme == .christmasKeepsakes {
            content.foregroundStyle(theme.detailSecondaryForeground)
        } else {
            content.foregroundStyle(.secondary)
        }
    }
}

extension View {
    func gameDetailSecondaryText() -> some View {
        modifier(GameDetailSecondaryText())
    }
}

// MARK: - Scene

/// The page behind Game Detail: the theme's scene, or its plain color.
struct GameDetailBackdrop: View {
    @Environment(\.surroundTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch theme {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            FlowingInkScene(usesColor: theme.flowingInkUsesColor, showsLandscape: theme.showsSceneArt)
        case .standard:
            theme.pageBackground
        case .nebulaPearl:
            NebulaPearlScene()
        case .rakedGarden:
            RakedGardenScene(scheme: colorScheme)
        case .surroundStudio:
            SurroundStudioScene(scheme: colorScheme)
        case .feltMeadow:
            FeltMeadowScene(scheme: colorScheme)
        case .nightGarden:
            NightGardenScene(scheme: colorScheme)
        case .christmasKeepsakes:
            ChristmasKeepsakesScene(scheme: colorScheme)
        case .frostPine:
            FrostPineScene(scheme: colorScheme)
        }
    }
}

/// The gifts, contact shadows and window belong to one photograph. Its crop
/// follows only the viewport, keeping the room still beneath panels and Zen.
struct ChristmasKeepsakesRoomLayout: Equatable {
    enum Composition: CaseIterable {
        case compactPortrait, compactLandscape, regularPortrait, regularLandscape

        var assetName: String {
            switch self {
            case .compactPortrait: return "ChristmasKeepsakesRoomCompactPortrait"
            case .compactLandscape: return "ChristmasKeepsakesRoomCompactLandscape"
            case .regularPortrait: return "ChristmasKeepsakesRoomRegularPortrait"
            case .regularLandscape: return "ChristmasKeepsakesRoomRegularLandscape"
            }
        }

        var visibleHeightFraction: CGFloat {
            switch self {
            case .compactPortrait: return 956 / 1000
            case .compactLandscape: return 440 / 1000
            case .regularPortrait: return 1210 / 1440
            case .regularLandscape: return 834 / 1440
            }
        }
    }

    let composition: Composition
    let backdrop: CGRect
    /// Material lighting has its own square coordinates. Reframing the room
    /// must not change the daylight sampled by clocks, cards and controls.
    let lightingReference: CGRect
    let lightCenter: CGPoint

    init(size: CGSize) {
        let width = size.width.isFinite ? max(0, size.width) : 0
        let height = size.height.isFinite ? max(0, size.height) : 0
        let shortSide = min(width, height)
        let compact = shortSide <= 560 || width >= height * 1.8
        if width > height {
            composition = compact ? .compactLandscape : .regularLandscape
        } else {
            composition = compact ? .compactPortrait : .regularPortrait
        }
        // The square plates include overscan above and to the right. Larger
        // windows expose that art at the same scale until full coverage needs
        // a larger plate. Small phones scale the whole scene down together.
        let baseSide: CGFloat = compact ? 1000 * min(1, shortSide / 440) : 1440
        // Short portrait windows need more of the photograph, not a deeper
        // crop through its window frame. Scale the entire room down together.
        let preferredSide = min(baseSide, height / composition.visibleHeightFraction)
        let side = max(preferredSide, max(width, height))
        backdrop = CGRect(x: 0, y: height - side, width: side, height: side)

        let compactFraming = min(1, max(0, (600 - shortSide) / 160))
        let backdropBaseSide: CGFloat = 1440 - 480 * compactFraming
        let landscapeFraming = min(1, max(0, (width - height) / 160))
        let compactTopCrop: CGFloat = 40 + 60 * landscapeFraming
        let backdropTopCrop: CGFloat = 160 + (compactTopCrop - 160) * compactFraming
        let backdropSide = max(backdropBaseSide, max(width, height + backdropTopCrop))
        lightingReference = CGRect(x: 0, y: -backdropTopCrop,
                                   width: backdropSide, height: backdropSide)
        lightCenter = CGPoint(x: 72, y: 120)
    }
}

private struct ChristmasKeepsakesScene: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let scheme: ColorScheme

    var body: some View {
        GeometryReader { geometry in
            ChristmasKeepsakesSceneContent(size: geometry.size, scheme: scheme,
                                           showsLight: ChristmasKeepsakesWindowLight.isVisible(
                                               contrast: contrast, reduceTransparency: reduceTransparency)).equatable()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ChristmasKeepsakesSceneContent: View, Equatable {
    let size: CGSize
    let scheme: ColorScheme
    let showsLight: Bool

    private var chrome: Color {
        Color(themeHex: scheme == .dark ? 0x201610 : 0xEAE1D1)
    }

    private var usesLegacyChrome: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }

    private var topFade: Gradient {
        if #available(iOS 26.0, *) {
            return Gradient(colors: [chrome.opacity(0.82), chrome.opacity(0.26), .clear])
        }
        // Match Raked Garden's support for older, unbacked navigation bars.
        return Gradient(stops: [
            .init(color: chrome.opacity(0.92), location: 0),
            .init(color: chrome.opacity(0.92), location: 0.62),
            .init(color: .clear, location: 1)
        ])
    }

    var body: some View {
        let layout = ChristmasKeepsakesRoomLayout(size: size)
        ZStack {
            chrome
            if let backdrop = ChristmasKeepsakesAssets.room(for: layout.composition) {
                Image(uiImage: backdrop)
                    .resizable()
                    .saturation(scheme == .dark ? 0.78 : 1)
                    .colorMultiply(scheme == .dark ? Color(themeHex: 0x8A7767) : .white)
                    .frame(width: layout.backdrop.width, height: layout.backdrop.height)
                    .position(x: layout.backdrop.midX, y: layout.backdrop.midY)
            }
            RadialGradient(colors: [Color(themeHex: 0xF4DFC2).opacity(scheme == .dark ? 0.16 : 0.13), .clear],
                           center: .center, startRadius: 0, endRadius: 210)
                .frame(width: 420, height: 420)
                .position(layout.lightCenter)
            // Match the shipping garden's short fade so the window and pine
            // stay visible beneath the native navigation controls.
            VStack(spacing: 0) {
                LinearGradient(gradient: topFade, startPoint: .top, endPoint: .bottom)
                    .frame(height: min(92, size.height * 0.16))
                Spacer(minLength: 0)
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: chrome.opacity(usesLegacyChrome ? 0.90 : 0.35), location: 0.5),
                    .init(color: chrome.opacity(usesLegacyChrome ? 0.96 : 0.85), location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: min(96, size.height * 0.16))
            }
            // The opaque room includes both gifts and their contact shadows,
            // so the edge fade and appearance treatment affect them together.
            if showsLight {
                // The same field reaches the wood, gifts and material cards.
                // It stays behind game content, so labels and boards stay crisp.
                ChristmasKeepsakesWindowLight(size: size, scheme: scheme)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// One continuous garden, anchored to the viewport rather than the board.
/// Panels and the keyboard never rescale or reposition its lantern and pond.
private struct NightGardenScene: View {
    let scheme: ColorScheme

    var body: some View {
        GeometryReader { geometry in
            NightGardenSceneContent(size: geometry.size, scheme: scheme).equatable()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct NightGardenSceneContent: View, Equatable {
    let size: CGSize
    let scheme: ColorScheme

    private var chrome: Color {
        Color(themeHex: scheme == .dark ? 0x0D1C1D : 0xE9E7D8)
    }

    private var usesLegacyChrome: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }

    var body: some View {
        ZStack {
            chrome
            Image("NightGardenScene")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .saturation(scheme == .dark ? 0.72 : 1)
                .colorMultiply(scheme == .dark ? Color(themeHex: 0x7C8C84) : .white)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipped()
            // Pale ledges support dark Light Mode chrome; pond-dark ledges
            // support the evening chrome. Both leave the central art exposed.
            VStack(spacing: 0) {
                LinearGradient(stops: [
                    .init(color: chrome.opacity(usesLegacyChrome ? 0.98 : 0.97), location: 0),
                    .init(color: chrome.opacity(usesLegacyChrome ? 0.94 : 0.90), location: 0.68),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: min(190, max(140, size.height * 0.22)))
                Spacer(minLength: 0)
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: chrome.opacity(usesLegacyChrome ? 0.90 : 0.3), location: 0.5),
                    .init(color: chrome.opacity(usesLegacyChrome ? 0.96 : 0.82), location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: min(96, size.height * 0.16))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// Fixed viewport anchors: the board and panels naturally occlude this art.
/// Panel selection, clock ticks and the game position never enter this plan.
struct FrostPineDecorationLayout: Equatable {
    let pine: CGRect
    let pinecone: CGRect
    let twig: CGRect

    init(size: CGSize) {
        let width = size.width.isFinite ? max(0, size.width) : 0
        let height = size.height.isFinite ? max(0, size.height) : 0
        let shortSide = min(width, height)
        let pineSide = min(360, min(width * 0.55, height * 0.40))
        let pineTop = min(24, height * 0.035)
        pine = CGRect(x: 0, y: pineTop, width: pineSide, height: pineSide)
        let coneSide = min(106, shortSide * 0.19)
        let bottomMargin = min(82, height * 0.14)
        pinecone = CGRect(x: width * 0.035, y: max(0, height - bottomMargin - coneSide),
                          width: coneSide, height: coneSide)
        let twigSide = min(190, shortSide * 0.32)
        twig = CGRect(x: max(0, width - twigSide), y: min(height * 0.62, height - twigSide),
                      width: twigSide, height: twigSide)
    }
}

private struct FrostPineScene: View {
    let scheme: ColorScheme

    var body: some View {
        GeometryReader { geometry in
            FrostPineSceneContent(size: geometry.size, scheme: scheme).equatable()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Only static artwork carries the restrained winter highlights. Native board
/// marks and controls render above it, with no procedural sparkle or animation.
private struct FrostPineSceneContent: View, Equatable {
    let size: CGSize
    let scheme: ColorScheme

    private var chrome: Color {
        Color(themeHex: scheme == .dark ? 0x101F2B : 0xE8EEF2)
    }

    private var usesLegacyChrome: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }

    private var topFade: Gradient {
        if #available(iOS 26.0, *) {
            return Gradient(colors: [chrome.opacity(0.82), chrome.opacity(0.26), .clear])
        }
        // Match Raked Garden's support for older, unbacked navigation bars.
        return Gradient(stops: [
            .init(color: chrome.opacity(0.92), location: 0),
            .init(color: chrome.opacity(0.92), location: 0.62),
            .init(color: .clear, location: 1)
        ])
    }

    var body: some View {
        let layout = FrostPineDecorationLayout(size: size)
        ZStack {
            chrome
            if let snow = FrostPineAssets.snow {
                Image(uiImage: snow)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .saturation(scheme == .dark ? 0.4 : 1)
                    .colorMultiply(scheme == .dark ? Color(themeHex: 0x4B6A83) : .white)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipped()
            }
            FrostPineDecoration(image: FrostPineAssets.pine, frame: layout.pine, scheme: scheme)
            FrostPineDecoration(image: FrostPineAssets.pinecone, frame: layout.pinecone, scheme: scheme,
                                groundContact: .pinecone)
            FrostPineDecoration(image: FrostPineAssets.twig, frame: layout.twig, scheme: scheme,
                                groundContact: .twig)
            // Clear the native title and toolbar bands without washing out
            // the snow across the whole game. Older bars have no glass.
            VStack(spacing: 0) {
                LinearGradient(gradient: topFade, startPoint: .top, endPoint: .bottom)
                    .frame(height: min(92, size.height * 0.16))
                Spacer(minLength: 0)
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: chrome.opacity(usesLegacyChrome ? 0.90 : 0.45), location: 0.55),
                    .init(color: chrome.opacity(usesLegacyChrome ? 0.96 : 0.85), location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: min(96, size.height * 0.16))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

private struct FrostPineDecoration: View {
    enum GroundContact { case pinecone, twig }

    let image: UIImage?
    let frame: CGRect
    let scheme: ColorScheme
    var groundContact: GroundContact? = nil

    var body: some View {
        if let image {
            ZStack {
                if let groundContact {
                    let cone = groundContact == .pinecone
                    let side = min(frame.width, frame.height)
                    let silhouette = Image(uiImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(Color(themeHex: scheme == .dark ? 0x091522 : 0x253B49))
                        .frame(width: frame.width, height: frame.height)

                    // Keep the short down-right cast attached to the snow.
                    // The twig lies flatter than the rounded cone.
                    silhouette
                        .blur(radius: side * (cone ? 0.03 : 0.008))
                        .opacity(scheme == .dark ? (cone ? 0.32 : 0.28) : (cone ? 0.24 : 0.20))
                        .offset(x: side * (cone ? 0.02 : 0.006), y: side * (cone ? 0.03 : 0.009))
                    // Draw contact separately so its crisp edge never casts
                    // another blurred shadow or lifts the ornament off the snow.
                    silhouette
                        .blur(radius: side * (cone ? 0.008 : 0.003))
                        .opacity(scheme == .dark ? (cone ? 0.48 : 0.40) : (cone ? 0.38 : 0.30))
                        .offset(x: side * (cone ? 0.003 : 0.0015), y: side * (cone ? 0.006 : 0.003))
                }
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .saturation(scheme == .dark ? 0.5 : 1)
                    .colorMultiply(scheme == .dark ? Color(themeHex: 0x68869F) : .white)
                    .frame(width: frame.width, height: frame.height)
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        }
    }
}

/// The meadow stays anchored to the viewport while game panels move above
/// it. Uniform scaling keeps the wool fibers and flowers in proportion.
private struct FeltMeadowScene: View {
    let scheme: ColorScheme

    var body: some View {
        GeometryReader { geometry in
            FeltMeadowSceneContent(size: geometry.size, scheme: scheme).equatable()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FeltMeadowSceneContent: View, Equatable {
    let size: CGSize
    let scheme: ColorScheme

    private var chrome: Color {
        Color(themeHex: scheme == .dark ? 0x172119 : 0xEEE7D5)
    }

    private var usesLegacyChrome: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }

    /// A short landscape viewport crops the sky. Reserve a quiet band for
    /// its native navigation controls without moving the hills or flowers.
    private var shortWideWeight: CGFloat {
        min(1, max(0, (size.width - size.height) / 160))
            * min(1, max(0, (600 - size.height) / 120))
    }

    var body: some View {
        ZStack {
            chrome
            Image("FeltMeadowScene")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .saturation(scheme == .dark ? 0.55 : 1)
                .colorMultiply(scheme == .dark ? Color(themeHex: 0x61765F) : .white)
                .frame(width: size.width, height: size.height, alignment: .bottomLeading)
                .clipped()
            VStack(spacing: 0) {
                LinearGradient(stops: [
                    .init(color: chrome.opacity(usesLegacyChrome ? 0.94 : 0.85), location: 0),
                    .init(color: chrome.opacity(usesLegacyChrome ? 0.92
                        : 0.28 + 0.5 * Double(shortWideWeight)), location: 0.55),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: max(min(110, size.height * 0.18), 100 * shortWideWeight))
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
        Color(themeHex: scheme == .dark ? 0x121B24 : 0xE5DED4)
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
        let tree = SurroundStudioDecorationLayout(size: size).tree
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
            // This lower canopy belongs to the room: boards and panels
            // naturally cover it, while the native preview includes it too.
            Image("SurroundStudioTree")
                .resizable()
                .saturation(scheme == .dark ? 0.42 : 1)
                .colorMultiply(scheme == .dark ? Color(themeHex: 0x6C7D99) : .white)
                .frame(width: tree.width, height: tree.height)
                .shadow(color: Color(themeHex: scheme == .dark ? 0x070D16 : 0x342F21)
                    .opacity(scheme == .dark ? 0.22 : 0.12), radius: 3, x: 3, y: 4)
                .position(x: tree.midX, y: tree.midY)
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

/// Canopies follow the viewport behind the game, so clocks and panels cover
/// the leaves in every layout, including folded displays.
struct GameDetailSceneFoliage: View {
    @Environment(\.surroundTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    var hasTopEdgeClocks = false

    var body: some View {
        Group {
            if theme == .rakedGarden {
                GeometryReader { geometry in
                    RakedGardenFoliageContent(size: geometry.size, scheme: colorScheme,
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

/// Cast shadows retain their projection across the game, above the backdrop.
struct GameDetailSceneForeground: View {
    @Environment(\.surroundTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    var shadowExclusions: [BoardSceneShadowRegion] = []

    var body: some View {
        Group {
            if theme == .rakedGarden {
                GeometryReader { geometry in
                    RakedGardenMapleShadow(size: geometry.size, scheme: colorScheme).equatable()
                }
            } else if theme == .frostPine {
                GeometryReader { geometry in
                    FrostPineShadow(size: geometry.size, scheme: colorScheme,
                                    excludedBoards: shadowExclusions).equatable()
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The content coordinate space excludes safe areas, while the room extends
/// under them. Keep this conversion shared by every illuminated surface.
struct ChristmasKeepsakesLightContext: Equatable {
    static let coordinateSpace = "christmasKeepsakesWindowLight"
    let size: CGSize
    let contentOffset: CGPoint

    init(size: CGSize, safeAreaInsets: EdgeInsets) {
        self.size = CGSize(width: size.width + safeAreaInsets.leading + safeAreaInsets.trailing,
                           height: size.height + safeAreaInsets.top + safeAreaInsets.bottom)
        contentOffset = CGPoint(x: safeAreaInsets.leading, y: safeAreaInsets.top)
    }
}

private struct ChristmasKeepsakesLightContextKey: EnvironmentKey {
    static let defaultValue: ChristmasKeepsakesLightContext? = nil
}

extension EnvironmentValues {
    var christmasKeepsakesLightContext: ChristmasKeepsakesLightContext? {
        get { self[ChristmasKeepsakesLightContextKey.self] }
        set { self[ChristmasKeepsakesLightContextKey.self] = newValue }
    }
}

/// Real illumination of the material, below its text and controls. Each card
/// samples the same window beam instead of restarting a gradient at its edge.
struct ChristmasKeepsakesSurfaceLighting: View {
    enum Profile {
        case room, panel, glassCard, ivoryGlassCard, pigmentCard

        var daylightOpacity: Double {
            switch self {
            case .room: 0.12
            case .pigmentCard: 0.07
            default: 0.14
            }
        }
        var shadeOpacity: Double {
            switch self {
            case .room: 0.42
            case .glassCard: 0.12
            case .ivoryGlassCard: 0.06
            case .panel, .pigmentCard: 0.04
            }
        }
        var distanceShadeFraction: Double { self == .room ? 0.50 : 0.22 }

        var frostOpacity: Double {
            switch self {
            case .room: 0.28
            case .glassCard: 0.12
            case .ivoryGlassCard: 0.10
            case .panel: 0.07
            case .pigmentCard: 0.05
            }
        }
    }

    @Environment(\.surroundTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.christmasKeepsakesLightContext) private var lightContext
    var profile: Profile = .panel

    var body: some View {
        if theme == .christmasKeepsakes, let lightContext,
           ChristmasKeepsakesWindowLight.isVisible(contrast: contrast, reduceTransparency: reduceTransparency) {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .named(ChristmasKeepsakesLightContext.coordinateSpace))
                let origin = CGPoint(x: frame.minX + lightContext.contentOffset.x,
                                     y: frame.minY + lightContext.contentOffset.y)
                ChristmasKeepsakesSurfaceBeam(size: lightContext.size, origin: origin,
                                               scheme: scheme, profile: profile)
                    .equatable()
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// A stationary daylight field shared by the tabletop and every material.
/// Its broad shoulder reaches both clocks; distance adds depth to the far wood.
struct ChristmasKeepsakesSurfaceBeam: View, Equatable {
    let size: CGSize
    let origin: CGPoint
    let scheme: ColorScheme
    let profile: ChristmasKeepsakesSurfaceLighting.Profile

    private struct Crystal {
        let center: CGPoint
        let radius: CGFloat
        let angle: CGFloat
        let strength: Double
    }

    private static let crystals = [
        Crystal(center: CGPoint(x: 0.14, y: 0.21), radius: 0.047, angle: 0.24, strength: 1),
        Crystal(center: CGPoint(x: 0.31, y: 0.22), radius: 0.038, angle: -0.17, strength: 0.85),
        Crystal(center: CGPoint(x: 0.20, y: 0.415), radius: 0.056, angle: 0.46, strength: 0.8),
        Crystal(center: CGPoint(x: 0.40, y: 0.46), radius: 0.05, angle: -0.32, strength: 0.55),
        // Exposed tabletop beside the board on wider layouts; the near pane
        // edge clips part of this projection instead of showing a full motif.
        Crystal(center: CGPoint(x: 0.115, y: 0.52), radius: 0.065, angle: 0.13, strength: 0.9)
    ]

    var body: some View {
        let plate = ChristmasKeepsakesRoomLayout(size: size).lightingReference
        let side = plate.width
        let scale = side / 1440
        let strength = scheme == .dark ? 0.45 : 1.0
        Canvas(rendersAsynchronously: false) { context, _ in
            context.translateBy(x: -origin.x, y: -origin.y)
            let bounds = Path(CGRect(origin: .zero, size: size))
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: plate.minX + side * x, y: plate.minY + side * y)
            }
            let acrossStart = point(0.12, 0.24)
            let acrossEnd = point(0.42, 0.09)
            let distanceStart = point(0.08, 0.12)
            let distanceEnd = point(0.38, 0.94)
            func daylightGradient(_ color: Color) -> GraphicsContext.Shading {
                .linearGradient(Gradient(stops: [
                    .init(color: color, location: 0),
                    .init(color: color.opacity(0.65), location: 0.45),
                    .init(color: .clear, location: 0.75),
                    .init(color: .clear, location: 1)
                ]), startPoint: acrossStart, endPoint: acrossEnd)
            }
            func fadeWithDistance(_ layer: inout GraphicsContext) {
                layer.blendMode = .destinationIn
                // A near pane edge leaves unlit wood beside the broad swath.
                // Its location belongs to the room, never to a card or board.
                layer.fill(bounds, with: .linearGradient(Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: 0.45),
                    .init(color: .white, location: 1)
                ]), startPoint: point(-0.15, -0.10), endPoint: point(-0.03, -0.135)))
                layer.fill(bounds, with: .linearGradient(Gradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: 0.25),
                    .init(color: .white.opacity(0.45), location: 0.65),
                    .init(color: .clear, location: 1)
                ]), startPoint: distanceStart, endPoint: distanceEnd))
            }
            // Stronger room shade preserves the timber's grain and color;
            // card caps are gentler because text contrast governs their range.
            let shade = Color(themeHex: 0x292321)
            context.fill(bounds, with: .linearGradient(Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.45),
                .init(color: shade.opacity(profile.shadeOpacity * strength * (1 - profile.distanceShadeFraction)), location: 0.82),
                .init(color: shade.opacity(profile.shadeOpacity * strength * (1 - profile.distanceShadeFraction)), location: 1)
            ]), startPoint: acrossStart, endPoint: acrossEnd))
            context.fill(bounds, with: .linearGradient(Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.18),
                .init(color: shade.opacity(profile.shadeOpacity * strength * profile.distanceShadeFraction), location: 1)
            ]), startPoint: distanceStart, endPoint: distanceEnd))
            context.drawLayer { light in
                light.fill(bounds, with: daylightGradient(
                    ChristmasKeepsakesWindowLight.daylight.opacity(profile.daylightOpacity * strength)))
                fadeWithDistance(&light)
            }
            context.drawLayer { shadows in
                shadows.drawLayer { softened in
                    softened.addFilter(.blur(radius: (profile == .room ? 2.4 : 3.8) * scale))
                    for crystal in Self.crystals {
                        let center = point(crystal.center.x, crystal.center.y)
                        let transform = CGAffineTransform(translationX: center.x, y: center.y)
                            .rotated(by: .pi / 5)
                            .scaledBy(x: 1.55, y: 0.82)
                            .rotated(by: crystal.angle)
                        let path = Self.crystalPath(radius: side * crystal.radius).applying(transform)
                        softened.stroke(path, with: .color(ChristmasKeepsakesWindowLight.frostShade.opacity(
                            profile.frostOpacity * strength * crystal.strength)),
                            style: StrokeStyle(lineWidth: 8 * scale, lineCap: .round, lineJoin: .round))
                    }
                }
                // Frost only interrupts the illuminated part of the room.
                shadows.blendMode = .destinationIn
                shadows.fill(bounds, with: daylightGradient(.white))
                fadeWithDistance(&shadows)
            }
        }
    }

    private static func crystalPath(radius: CGFloat) -> Path {
        var path = Path()
        let lengths: [CGFloat] = [1, 0.78, 0.92, 0.68, 0.88, 0.79]
        for arm in 0..<6 {
            let angle = CGFloat(arm) * .pi / 3
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            let normal = CGPoint(x: -direction.y, y: direction.x)
            let length = radius * lengths[arm]
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: direction.x * length, y: direction.y * length))
            for fraction: CGFloat in [0.42, 0.7] {
                let base = CGPoint(x: direction.x * length * fraction, y: direction.y * length * fraction)
                let twig = length * (fraction < 0.5 ? 0.23 : 0.16)
                for side: CGFloat in [-1, 1] {
                    path.move(to: base)
                    path.addLine(to: CGPoint(x: base.x + direction.x * twig + normal.x * twig * side,
                                            y: base.y + direction.y * twig + normal.y * twig * side))
                }
            }
        }
        return path
    }
}

/// Room illumination sits behind the boards and controls. Every material card
/// samples the same field beneath its own labels, so no cast washes over ink.
struct ChristmasKeepsakesWindowLight: View, Equatable {
    let size: CGSize
    let scheme: ColorScheme

    static func isVisible(contrast: ColorSchemeContrast, reduceTransparency: Bool) -> Bool {
        contrast != .increased && !reduceTransparency
    }

    static let daylight = Color(themeHex: 0xF8F5E8)
    static let frostShade = Color(themeHex: 0x253C46)

    var body: some View {
        ChristmasKeepsakesSurfaceBeam(size: size, origin: .zero, scheme: scheme, profile: .room)
            .frame(width: size.width, height: size.height)
            .mask {
                // Keep the existing short support fade behind native chrome.
                FrostPineShadowMask(topFadeHeight: min(92, size.height * 0.16))
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Winter light from the upper left projects the pine down and right. Like
/// Garden's canopy, the cast is larger than the ornament and fixed to the scene.
struct FrostPineShadowLayout: Equatable {
    let size: CGSize
    let canopy: CGRect
    let blurRadius: CGFloat
    let topFadeHeight: CGFloat

    init(size: CGSize) {
        let width = size.width.isFinite ? max(0, size.width) : 0
        let height = size.height.isFinite ? max(0, size.height) : 0
        self.size = CGSize(width: width, height: height)
        let shortSide = min(width, height)
        let side = min(840, shortSide * 1.3)
        // Keep the source's cut-off branch roots outside the viewport; the
        // enlarged canopy's center projects down-right from the visible pine.
        canopy = CGRect(x: -side * 0.08, y: -side * 0.04, width: side, height: side)
        blurRadius = min(5, shortSide * 0.008)
        topFadeHeight = min(92, height * 0.16)
    }
}

/// Cut out the union of visible rounded slabs, including miniature chat boards.
/// Apply after the pine blur so no cast spills onto board or stone colors.
struct FrostPineShadowMask: View, Equatable {
    var excludedBoards: [BoardSceneShadowRegion] = []
    var topFadeHeight: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            if topFadeHeight > 0 {
                context.fill(Path(bounds), with: .linearGradient(
                    Gradient(colors: [.clear, .white]), startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: topFadeHeight)))
            } else {
                context.fill(Path(bounds), with: .color(.white))
            }
            context.blendMode = .destinationOut
            for region in excludedBoards {
                let clipped = region.bounds.intersection(bounds)
                if !clipped.isNull && !clipped.isEmpty {
                    // Keep the original corners when a preview or scroller
                    // crops the board; intersecting first would invent corners.
                    let shape = RoundedRectangle(cornerRadius: region.cornerRadius, style: .circular)
                    context.fill(shape.path(in: region.bounds), with: .color(.white))
                }
            }
        }
        .animation(nil, value: excludedBoards)
    }
}

/// Blur the pine's static alpha only, never the board, lettering or controls.
private struct FrostPineShadow: View, Equatable {
    let size: CGSize
    let scheme: ColorScheme
    var excludedBoards: [BoardSceneShadowRegion] = []

    var body: some View {
        let layout = FrostPineShadowLayout(size: size)
        if let pine = FrostPineAssets.pine {
            Image(uiImage: pine)
                .renderingMode(.template)
                .resizable()
                .foregroundStyle(Color(themeHex: scheme == .dark ? 0x091522 : 0x253B49))
                .frame(width: layout.canopy.width, height: layout.canopy.height)
                .blur(radius: layout.blurRadius)
                .opacity(0.18)
                .position(x: layout.canopy.midX, y: layout.canopy.midY)
                .frame(width: layout.size.width, height: layout.size.height)
                .mask {
                    FrostPineShadowMask(excludedBoards: excludedBoards, topFadeHeight: layout.topFadeHeight)
                }
                .clipped()
        }
    }
}

/// Both canopies follow the viewport independently of game panels. The upper
/// foliage reserves chrome; both canopies stay behind the game and its bars.
struct SurroundStudioDecorationLayout: Equatable {
    let foliage: CGRect
    let tree: CGRect

    init(size: CGSize, usesLegacyChrome: Bool = false, hasTopEdgeClocks: Bool = false) {
        let width = size.width.isFinite ? max(0, size.width) : 0
        let height = size.height.isFinite ? max(0, size.height) : 0
        let shortSide = min(width, height)
        let tileSide = min(260, max(176, shortSide * 0.5))
        let roomy = min(1, max(0, (shortSide - 430) / 250))
        let portrait = min(1, max(0, (height / max(1, width) - 1) * 2))
        // Keep a conservative, fixed top reach through panel mode changes.
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
        // Preserve natural leaf scale on phones and tablets, but bound the
        // lower reach in shallow windows and scale down for preview tiles.
        let treeSide = min(400, min(max(280, shortSide * 0.76), min(width * 0.82, height * 0.53)))
        tree = CGRect(x: -treeSide * 0.3, y: height - treeSide * 0.83,
                      width: treeSide, height: treeSide)
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

private struct RakedGardenFoliageContent: View, Equatable {
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
        // Keep the top canopy shallow around legacy chrome and divided layouts.
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
