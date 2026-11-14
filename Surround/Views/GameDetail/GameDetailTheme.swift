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
    case paperBlossoms
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
        case .paperBlossoms: String(localized: "Paper Blossoms", comment: "Theme name: delicate layered paper blossoms, lanterns and a miniature village for Lunar New Year. Use a short, natural title preserving the paper-and-blossom imagery.")
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
        case .standard, .rakedGarden, .surroundStudio, .frostPine, .feltMeadow, .nightGarden, .christmasKeepsakes, .paperBlossoms: nil
        case .nebulaPearl: .dark
        }
    }

    /// Resolve image grading alongside the board palette. The image references
    /// stay cached, so an appearance change does not decode or regenerate art.
    func board(for scheme: ColorScheme) -> BoardAppearance {
        if self == .paperBlossoms, scheme == .dark {
            var night = board
            // Keep rice paper light enough to separate the ink stones. Only
            // its illumination changes; the native grid and marks stay crisp.
            night.boardColor = Color(themeHex: 0xD6C0A0)
            night.compactBoardColor = Color(themeHex: 0xD6C0A0)
            night.boardTexture?.tint = Color(themeHex: 0xE1D5C1)
            night.stoneImages?.tint = Color(themeHex: 0xE8DFD0)
            night.boardEdge = Color(themeHex: 0x75513F)
            return night
        }
        if isFlowingInk, scheme == .dark {
            var night = board
            // Medium graphite, jade or wood separates both solid stone colors. A
            // near-black board would hide the ink stones and their contours.
            let paper = flowingInkColors.nightBoard
            let ink = flowingInkColors.nightInk
            night.boardColor = paper
            night.compactBoardColor = paper
            night.boardEdge = Color.black.opacity(0.85)
            night.dameColor = flowingInkColors.nightDame
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
            night.boardDepth = BoardDepth(
                upperFace: Color(themeHex: 0x566B5C), lowerFace: Color(themeHex: 0x203B2E),
                highlight: Color(themeHex: 0xD8CBAE).opacity(0.9),
                shade: Color(themeHex: 0x344638), shadow: Color(themeHex: 0x130F0A).opacity(0.44),
                thicknessRatio: 0.012, maximumThickness: 7, edgeStyle: .rolledTin)
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
            night.boardColor = Color(themeHex: 0xADB2B1)
            night.compactBoardColor = Color(themeHex: 0x9FA9A5)
            night.boardEdge = Color(themeHex: 0xBDD6E5).opacity(0.7)
            night.boardTexture?.tint = Color(themeHex: 0xE2DCD0)
            night.boardTexture?.opacity = 0.22
            night.surfaceFrost?.tint = Color(themeHex: 0xA5B8C5)
            night.surfaceFrost?.opacity = 0.52
            night.stoneImages?.tint = Color(themeHex: 0xD5E2EE)
            night.boardDepth = BoardDepth(
                upperFace: Color(themeHex: 0xA6BCC9), lowerFace: Color(themeHex: 0x6C8596),
                highlight: Color(themeHex: 0xE3EFF6).opacity(0.74),
                shade: Color(themeHex: 0x344F63).opacity(0.42),
                shadow: Color(themeHex: 0x07121C).opacity(0.35),
                thicknessRatio: 0.008, maximumThickness: 5, edgeStyle: .frosted)
            night.gridColor = Color(themeHex: 0x3A4947)
            night.coordinateColor = Color(themeHex: 0x263A3D)
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
        case .paperBlossoms:
            return BoardAppearance(
                boardColor: Color(themeHex: 0xF3DEC1),
                compactBoardColor: Color(themeHex: 0xF3DEC1),
                boardEdge: Color(themeHex: 0xA5785D),
                boardTexture: PaperBlossomsAssets.board,
                gridLineScale: 0.82,
                stoneImages: PaperBlossomsAssets.stones,
                stoneLightDirection: .upperLeft,
                // The firmer two-layer profile lifts ivory folds off rice
                // paper; it adds only cast/contact shadows, never gloss.
                imageStoneShadow: .raisedGlass,
                imageStoneShading: .clamshellShoulder,
                gridColor: Color(themeHex: 0x9E2F25),
                coordinateColor: Color(themeHex: 0x5B201A),
                black: StonePalette(
                    highlight: Color(themeHex: 0x42423D), shade: Color(themeHex: 0x171816),
                    flat: Color(themeHex: 0x242321), outline: Color(themeHex: 0x111210),
                    lastMove: Color(themeHex: 0xFFF5DF), label: Color(themeHex: 0xFFF5DF),
                    detailedMarkerCasing: Color(themeHex: 0x171816)
                ),
                white: StonePalette(
                    highlight: Color(themeHex: 0xFFF5DF), shade: Color(themeHex: 0xCAB294),
                    flat: Color(themeHex: 0xF6ECD9), outline: Color(themeHex: 0x65503E),
                    lastMove: Color(themeHex: 0x55221C), label: Color(themeHex: 0x55221C),
                    detailedMarkerCasing: Color(themeHex: 0xFFF5DF)
                ),
                emptyPointMarker: Color(themeHex: 0x55221C),
                markOutline: Color(themeHex: 0x65503E),
                dameColor: Color(themeHex: 0x67421F),
                highlightColor: Color(themeHex: 0x2F4955),
                highlightCasing: Color(themeHex: 0xFFF5DF),
                crosshair: .init(valid: Color(themeHex: 0x345241),
                                 invalid: Color(themeHex: 0x8C231D),
                                 removal: Color(themeHex: 0x2F4955)),
                crosshairWidth: 1.5,
                removeMark: Color(themeHex: 0x8C231D),
                restoreMark: Color(themeHex: 0x345241),
                removalMarkCasing: Color(themeHex: 0xFFF5DF),
                removedStoneOutline: Color(themeHex: 0x65503E)
            )
        case .christmasKeepsakes:
            return BoardAppearance(
                boardColor: Color(themeHex: 0x6D8975),
                compactBoardColor: Color(themeHex: 0x6D8975),
                boardEdge: Color(themeHex: 0xD9C29A),
                boardTexture: ChristmasKeepsakesAssets.board,
                boardBevel: true,
                boardDepth: BoardDepth(
                    upperFace: Color(themeHex: 0x738573), lowerFace: Color(themeHex: 0x354B3D),
                    highlight: Color(themeHex: 0xF1E5CC), shade: Color(themeHex: 0x53604E),
                    shadow: Color(themeHex: 0x2B190D).opacity(0.36),
                    thicknessRatio: 0.012, maximumThickness: 7, edgeStyle: .rolledTin),
                // A rolled biscuit-tin lip and shallow sidewall frame the
                // calm pine enamel; the dark-pine grid keeps its fine weight.
                gridLineScale: 0.85,
                stoneImages: ChristmasKeepsakesAssets.stones,
                stoneLightDirection: .upperLeft,
                imageStoneShadow: .raisedIvoryGlass,
                // The cabochon artwork contains its broad window reflection
                // and transmitted red light; an extra contour would double it.
                imageStoneShading: .artwork,
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
                // A quiet silver face separates the blue stones by hue as
                // well as value; the rim retains the colder ice reflections.
                boardColor: Color(themeHex: 0xCBCBC1),
                compactBoardColor: Color(themeHex: 0xBBC0B9),
                boardEdge: Color(themeHex: 0xF6FCFF).opacity(0.85),
                boardTexture: FrostPineAssets.board,
                boardBevel: true,
                boardDepth: BoardDepth(
                    upperFace: Color(themeHex: 0xDDE5E5), lowerFace: Color(themeHex: 0xB5C4CA),
                    highlight: Color(themeHex: 0xFCFDFA).opacity(0.92),
                    shade: Color(themeHex: 0x738796).opacity(0.32),
                    shadow: Color(themeHex: 0x253F51).opacity(0.24),
                    thicknessRatio: 0.008, maximumThickness: 5, edgeStyle: .frosted),
                surfaceFrost: FrostPineAssets.surfaceFrost,
                // Keep the existing chipped cuts and recessed hoshi; graphite
                // cores ground the engraving in the more neutral playing face.
                gridLineScale: 1,
                gridStyle: .engraved,
                stoneImages: FrostPineAssets.stones,
                stoneLightDirection: .upperLeft,
                imageStoneShadow: .ice,
                imageStoneShading: .iceEdge,
                gridColor: Color(themeHex: 0x58615C),
                coordinateColor: Color(themeHex: 0x344742),
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
private final class ChristmasKeepsakesAssets {
    private init() {}
    private static let bundle = Bundle(for: ChristmasKeepsakesAssets.self)

    static let stones: StoneImages? = {
        guard let black = UIImage(named: "ChristmasKeepsakesRubyStone", in: bundle, compatibleWith: nil),
              let white = UIImage(named: "ChristmasKeepsakesIvoryStone", in: bundle, compatibleWith: nil) else { return nil }
        // The selected cabochon is authored at its final brightness. Reuse
        // the source in both appearances; Night applies only its scene tint.
        return StoneImages(black: [black], white: [white], smallStoneInset: 0.45)
    }()

    // The muted enamel has a narrow luminance range so the fine dark-pine
    // grid and coordinates stay legible across the entire playing surface.
    static let board = UIImage(named: "ChristmasKeepsakesBoardSurface", in: bundle, compatibleWith: nil)
        .map { BoardTexture(image: $0, mapping: .board) }
    static func room(for composition: ChristmasKeepsakesRoomLayout.Composition) -> UIImage? {
        UIImage(named: composition.assetName, in: bundle, compatibleWith: nil)
    }
}

/// The upright tree is separate from the table photograph so only its outer
/// boughs peek through the right edge across the room's different crops.
final class ChristmasKeepsakesTreeAssets {
    private init() {}
    static let image = UIImage(named: "ChristmasKeepsakesTree",
                               in: Bundle(for: ChristmasKeepsakesTreeAssets.self), compatibleWith: nil)
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
    // Cranberry and ivory painted wood. The generated brush/grain relief
    // stays inside these readable pigment bounds; exposed wood frames it.
    static let blackSurfaceTop = adaptive(0x85273B, 0x702536)
    static let blackSurfaceBottom = adaptive(0x66182D, 0x4B1729)
    static let whiteSurfaceTop = adaptive(0xFFF3DD, 0xE6DACA)
    static let whiteSurfaceBottom = adaptive(0xE0C9AB, 0xCCBAA0)
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

    // Reuse the ice artwork at a quieter blend with a warm-neutral tint.
    // The colder crystalline perimeter remains a separate layer.
    static let board = UIImage(named: "FrostPineBoard").map {
        BoardTexture(image: $0, mapping: .board, tint: Color(themeHex: 0xFFF5E7), opacity: 0.22)
    }
    static let surfaceFrost = UIImage(named: "FrostPineBoardFrost").map {
        BoardSurfaceOverlay(image: $0, opacity: 0.68, perimeterFadeFraction: 0.045)
    }
    // Give the generated fibers a useful tonal range without letting a bright
    // splinter or dark check compromise text anywhere on a resized control.
    // Both grades are cached once; no image processing runs on clock ticks.
    private static let controlWoodGrades: (black: UIImage, white: UIImage)? = {
        guard let image = UIImage(named: "FrostPineControlWood", in: bundle, compatibleWith: nil),
              let source = image.cgImage,
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let context = CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB])
        let input = CIImage(cgImage: source, options: [.colorSpace: sRGB])
        let fibers = input.applyingFilter("CIColorControls", parameters: [
            "inputSaturation": 0, "inputContrast": 4.2
        ]).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
        ])
        func grade(low: UInt32, high: UInt32) -> UIImage? {
            func channel(_ value: UInt32, shift: UInt32) -> CGFloat {
                CGFloat((value >> shift) & 255) / 255
            }
            func vector(_ shift: UInt32) -> CIVector {
                let span = channel(high, shift: shift) - channel(low, shift: shift)
                return CIVector(x: span * 0.2126, y: span * 0.7152, z: span * 0.0722, w: 0)
            }
            let tinted = fibers.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": vector(16), "inputGVector": vector(8), "inputBVector": vector(0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: channel(low, shift: 16), y: channel(low, shift: 8),
                                            z: channel(low, shift: 0), w: 0)
            ])
            guard let output = context.createCGImage(tinted, from: input.extent,
                                                     format: .RGBA8, colorSpace: sRGB) else { return nil }
            return UIImage(cgImage: output, scale: image.scale, orientation: image.imageOrientation)
        }
        guard let black = grade(low: 0x202722, high: 0x4A4F45),
              let white = grade(low: 0xD0D1C5, high: 0xF0EDE3) else { return nil }
        return (black, white)
    }()

    static func controlWood(_ color: StoneColor) -> UIImage? {
        color == .black ? controlWoodGrades?.black : controlWoodGrades?.white
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
    static let whiteGlass = adaptive(0xE1DED4, 0xD5D7CF)
    static let whiteIdentityGlass = adaptive(0xD3E7F3, 0xB2CEE1)
    static let action = adaptive(0x43553B, 0x3F614D)
    static let chatBubble = adaptive(0xD6E3E8, 0x293F4B)
    static let selection = adaptive(0x3D5C42, 0xB4D1B1)
    static let conditional = adaptive(0x865423, 0xE9C28A)
    static let cream = adaptive(0xF3FAFF, 0xE9F4FC)
    static let keyline = adaptive(0xF3FAFF, 0x152A39)
    static let treeGuide = adaptive(0x526A7A, 0xAAC1D0)
    static let idle = adaptive(0xCBDCE4, 0x2C4352)
    // Weathered pine controls retain warm cut wood beneath the winter wash.
    static let blackSurfaceTop = adaptive(0x3D403B, 0x333B37)
    static let blackSurfaceBottom = adaptive(0x292E2C, 0x242A28)
    static let whiteSurfaceTop = adaptive(0xDAD8CE, 0xD0D1C8)
    static let whiteSurfaceBottom = adaptive(0xE8E5DB, 0xDCDDD4)
    static let blackSolid = adaptive(0x313631, 0x29302C)
    static let whiteForeground = adaptive(0x173A50, 0x112E43)
    static let blackAccent = adaptive(0xD1E4C6, 0xD7E9CE)
    static let whiteAccent = adaptive(0x3F583A, 0x2C472F)
    static let turnOutline = adaptive(0x526A43, 0xB5D1A1)
    static let turnGlow = adaptive(0xB3CB9E, 0xB7D2AA)
    static let blackBorder = adaptive(0xBCB7A8, 0xA5A99C)
    static let whiteBorder = adaptive(0x736C5F, 0x62695F)
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
            flowingInkColors.page
        case .standard: Color(uiColor: .systemGroupedBackground)
        case .nebulaPearl: Color(themeHex: 0x070A1C)
        case .rakedGarden: RakedGardenColors.page
        case .surroundStudio: SurroundStudioColors.page
        case .frostPine: FrostPineColors.page
        case .feltMeadow: FeltMeadowColors.page
        case .nightGarden: NightGardenColors.page
        case .christmasKeepsakes: ChristmasKeepsakesColors.page
        case .paperBlossoms: PaperBlossomsColors.page
        }
    }

    var panel: Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkColors.panel
        case .standard: Color(uiColor: .secondarySystemGroupedBackground)
        case .nebulaPearl: Color(themeHex: 0x141938)
        case .rakedGarden: RakedGardenColors.panel
        case .surroundStudio: SurroundStudioColors.panel
        case .frostPine: FrostPineColors.panel
        case .feltMeadow: FeltMeadowColors.panel
        case .nightGarden: NightGardenColors.panel
        case .christmasKeepsakes: ChristmasKeepsakesColors.panel
        case .paperBlossoms: PaperBlossomsColors.panel
        }
    }

    var foreground: Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkColors.foreground
        case .standard, .nebulaPearl: .primary
        case .rakedGarden: RakedGardenColors.foreground
        case .surroundStudio: SurroundStudioColors.foreground
        case .frostPine: FrostPineColors.foreground
        case .feltMeadow: FeltMeadowColors.foreground
        case .nightGarden: NightGardenColors.foreground
        case .christmasKeepsakes: ChristmasKeepsakesColors.foreground
        case .paperBlossoms: PaperBlossomsColors.foreground
        }
    }

    /// Secondary information in opaque detail panels needs its own pigment;
    /// hierarchical opacity becomes too faint over the meadow's cream.
    var detailSecondaryForeground: Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkColors.secondary
        case .feltMeadow: FeltMeadowColors.detailSecondary
        case .nightGarden: NightGardenColors.detailSecondary
        case .christmasKeepsakes: ChristmasKeepsakesColors.detailSecondary
        case .paperBlossoms: PaperBlossomsColors.detailSecondary
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
        case .paperBlossoms: PaperBlossomsColors.panelBorder.opacity(0.28)
        }
    }

    /// Whether screens use the theme's scene layout and surfaces, including
    /// the paper-only presentations. Hiding artwork must not remove cards,
    /// alter spacing, or fall back to the system page palette.
    var hasScene: Bool { self != .standard }

    /// Whether the scene includes decorative artwork behind its surfaces.
    var showsSceneArt: Bool { hasScene && self != .flowingInkJadePlain && self != .flowingInkPlain }

    /// Native glass is available to the scene's controls. Frost clocks/chips
    /// use pine plates and Christmas uses painted ornaments; their main actions
    /// keep glass.
    var usesGlassControls: Bool { self != .standard && self != .feltMeadow && self != .paperBlossoms && !isFlowingInk }

    /// The natural scenes use their own foregrounds, translucent pigment
    /// on older systems, and opaque controls under Increase Contrast.
    var usesLightSceneSurfaces: Bool { isFlowingInk || self == .rakedGarden || self == .surroundStudio || self == .frostPine || self == .feltMeadow || self == .nightGarden || self == .christmasKeepsakes || self == .paperBlossoms }

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
        case .paperBlossoms:
            color == .black ? PaperBlossomsColors.blackGlass.opacity(0.82) : PaperBlossomsColors.whiteGlass.opacity(0.84)
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
        case .paperBlossoms:
            color == .black ? PaperBlossomsColors.blackGlass.opacity(0.86) : PaperBlossomsColors.whiteIdentityGlass.opacity(0.90)
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
        case .paperBlossoms: PaperBlossomsColors.action
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
        case .paperBlossoms: actionTint?.opacity(0.86)
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
        case .paperBlossoms: PaperBlossomsColors.selection
        default: Color(uiColor: .systemIndigo)
        }
    }

    /// Main-channel chat bubbles.
    var chatBubble: Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkColors.chat
        case .standard: Color(.systemGray4)
        case .nebulaPearl: Color(themeHex: 0x2C2F5E)
        case .rakedGarden: RakedGardenColors.chatBubble
        case .surroundStudio: SurroundStudioColors.chatBubble
        case .frostPine: FrostPineColors.chatBubble
        case .feltMeadow: FeltMeadowColors.chatBubble
        case .nightGarden: NightGardenColors.chatBubble
        case .christmasKeepsakes: ChristmasKeepsakesColors.chatBubble
        case .paperBlossoms: PaperBlossomsColors.chatBubble
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
        case .paperBlossoms: PaperBlossomsColors.selection
        }
    }

    /// Analyze tree moves that belong to the conditional-move plan; nil
    /// keeps the app's conditional-move color.
    var conditionalMark: Color? {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkColors.conditional
        case .standard: nil
        case .nebulaPearl: Color(themeHex: 0xE0A86A)
        case .rakedGarden: RakedGardenColors.conditional
        case .surroundStudio: SurroundStudioColors.conditional
        case .frostPine: FrostPineColors.conditional
        case .feltMeadow: FeltMeadowColors.conditional
        case .nightGarden: NightGardenColors.conditional
        case .christmasKeepsakes: ChristmasKeepsakesColors.conditional
        case .paperBlossoms: PaperBlossomsColors.conditional
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
        case .paperBlossoms: PaperBlossomsColors.keyline
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
        case .paperBlossoms: PaperBlossomsColors.treeGuide.opacity(0.24)
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
        case .paperBlossoms: PaperBlossomsColors.selection
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
        case .rakedGarden, .surroundStudio, .frostPine, .feltMeadow, .nightGarden, .christmasKeepsakes, .paperBlossoms: nil
        }
    }

    /// Active games in stone removal.
    var stoneRemovalMark: Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkColors.conditional
        case .standard: Color(uiColor: .systemOrange)
        case .nebulaPearl: Color(themeHex: 0xF2B279)
        case .rakedGarden: RakedGardenColors.conditional
        case .surroundStudio: SurroundStudioColors.conditional
        case .frostPine: FrostPineColors.conditional
        case .feltMeadow: FeltMeadowColors.conditional
        case .nightGarden: NightGardenColors.conditional
        case .christmasKeepsakes: ChristmasKeepsakesColors.conditional
        case .paperBlossoms: PaperBlossomsColors.conditional
        }
    }

    /// Active games waiting on the opponent.
    func idleGameMark(scheme: ColorScheme) -> Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            flowingInkColors.idle
        case .standard: Color(uiColor: scheme == .dark ? .systemGray5 : .systemBackground)
        case .nebulaPearl: Color(themeHex: 0x2A2F55)
        case .rakedGarden: RakedGardenColors.idle
        case .surroundStudio: SurroundStudioColors.idle
        case .frostPine: FrostPineColors.idle
        case .feltMeadow: FeltMeadowColors.idle
        case .nightGarden: NightGardenColors.idle
        case .christmasKeepsakes: ChristmasKeepsakesColors.idle
        case .paperBlossoms: PaperBlossomsColors.idle
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
        case .paperBlossoms:
            if color == .black {
                return [.init(color: PaperBlossomsColors.blackSurfaceTop, location: 0),
                        .init(color: PaperBlossomsColors.blackSurfaceBottom, location: 1)]
            }
            return [.init(color: PaperBlossomsColors.whiteSurfaceTop, location: 0),
                    .init(color: PaperBlossomsColors.whiteSurfaceBottom, location: 1)]
        }
    }

    /// The clock surface under Reduce Transparency or Increase Contrast.
    func clockSolidSurface(_ color: StoneColor) -> Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            color == .black ? flowingInkColors.black : flowingInkColors.white
        case .standard: color == .black ? Color(white: 0.06) : Color(white: 0.98)
        case .nebulaPearl: color == .black ? Color(themeHex: 0x1C1240) : Color(themeHex: 0xF6F0EA)
        case .rakedGarden: color == .black ? RakedGardenColors.blackSolid : RakedGardenColors.whiteGlass
        case .surroundStudio: color == .black ? SurroundStudioColors.blackSolid : SurroundStudioColors.whiteGlass
        case .frostPine: color == .black ? FrostPineColors.blackSolid : FrostPineColors.whiteGlass
        case .feltMeadow: color == .black ? FeltMeadowColors.blackSolid : FeltMeadowColors.whiteGlass
        case .nightGarden: color == .black ? NightGardenColors.blackSolid : NightGardenColors.whiteGlass
        case .christmasKeepsakes: color == .black ? ChristmasKeepsakesColors.blackSolid : ChristmasKeepsakesColors.whiteGlass
        case .paperBlossoms: color == .black ? PaperBlossomsColors.blackSolid : PaperBlossomsColors.whiteGlass
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
        case .paperBlossoms: color == .black ? PaperBlossomsColors.cream : PaperBlossomsColors.whiteForeground
        }
    }

    /// Icons and highlighted text on a clock outside sudden death.
    func clockAccent(_ color: StoneColor) -> Color {
        switch self {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            // White clocks keep dark text even when filled actions lighten
            // against the charcoal page. Metadata needs text-level contrast.
            color == .black ? .white : flowingInkColors.ink
        case .standard: Color(uiColor: .systemIndigo)
        case .nebulaPearl: color == .black ? Color(themeHex: 0xCDBEFF) : Color(themeHex: 0x5B3FC4)
        case .rakedGarden: color == .black ? RakedGardenColors.blackAccent : RakedGardenColors.whiteAccent
        case .surroundStudio: color == .black ? SurroundStudioColors.blackAccent : SurroundStudioColors.whiteAccent
        case .frostPine: color == .black ? FrostPineColors.blackAccent : FrostPineColors.whiteAccent
        case .feltMeadow: color == .black ? FeltMeadowColors.blackAccent : FeltMeadowColors.whiteAccent
        case .nightGarden: color == .black ? NightGardenColors.blackAccent : NightGardenColors.whiteAccent
        case .christmasKeepsakes: color == .black ? ChristmasKeepsakesColors.blackAccent : ChristmasKeepsakesColors.whiteAccent
        case .paperBlossoms: color == .black ? PaperBlossomsColors.blackAccent : PaperBlossomsColors.whiteAccent
        }
    }

    /// Keep the existing warning red on every daytime/other-theme clock.
    /// Pale night clocks need deeper red; dark clocks use brighter coral.
    func clockSuddenDeathAccent(_ color: StoneColor, scheme: ColorScheme) -> Color {
        if isFlowingInk, scheme == .dark, color == .white { return Color(themeHex: 0x7D293B) }
        if self == .nightGarden || self == .christmasKeepsakes || self == .paperBlossoms { return Color(themeHex: color == .white ? 0x7D293B : 0xFFB5AF) }
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
        if self == .nightGarden || self == .christmasKeepsakes || self == .paperBlossoms { return Color(themeHex: 0x8B3449) }
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
        if self == .nightGarden || self == .christmasKeepsakes || self == .paperBlossoms { return Color(themeHex: color == .white ? 0x284B31 : 0xBDDEA9) }
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
        if self == .nightGarden || self == .christmasKeepsakes || self == .paperBlossoms { return Color(themeHex: color == .white ? 0x633D15 : 0xF3D39B) }
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
        if self == .nightGarden || self == .christmasKeepsakes || self == .paperBlossoms { return Color(themeHex: color == .white ? 0x633D15 : 0xF3D39B) }
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
        if self == .nightGarden || self == .christmasKeepsakes || self == .paperBlossoms { return Color(themeHex: 0x79501F) }
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
            flowingInkColors.turnOutline
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
        case .paperBlossoms: PaperBlossomsColors.turnOutline
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
        case .paperBlossoms: PaperBlossomsColors.turnGlow
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
        case .paperBlossoms: PaperBlossomsColors.action
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
        case .paperBlossoms:
            color == .black
                ? [PaperBlossomsColors.blackSurfaceTop, PaperBlossomsColors.blackSurfaceBottom]
                : [PaperBlossomsColors.whiteSurfaceTop, PaperBlossomsColors.whiteSurfaceBottom]
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
        case .paperBlossoms:
            color == .black
                ? PaperBlossomsColors.blackBorder.opacity(0.3)
                : PaperBlossomsColors.whiteBorder.opacity(0.35)
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
        case .paperBlossoms: color == .black ? PaperBlossomsColors.cream : PaperBlossomsColors.whiteForeground
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
        case .paperBlossoms:
            color == .black ? PaperBlossomsColors.blackSecondary : PaperBlossomsColors.whiteSecondary
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
        if self == .paperBlossoms {
            if player.isOGSModerator || player.isOGSAdmin {
                return darkSurface ? PaperBlossomsColors.darkModerator : PaperBlossomsColors.lightModerator
            }
            if player.isOGSProfessional {
                return darkSurface ? PaperBlossomsColors.darkProfessional : PaperBlossomsColors.lightProfessional
            }
            if player.isOGSSupporter {
                return darkSurface ? PaperBlossomsColors.darkSupporter : PaperBlossomsColors.lightSupporter
            }
            if player.isBot == true || player.uiClass?.contains("bot") == true {
                return identitySecondary(color)
            }
            return darkSurface ? PaperBlossomsColors.darkOrdinary : PaperBlossomsColors.lightOrdinary
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
        case .paperBlossoms: PaperBlossomsColors.selection
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

// MARK: - Paper Blossoms

/// Paper artwork never includes grid geometry or game marks. Static images
/// keep their identity through clock ticks, panel transitions and resizing.
private enum PaperBlossomsAssets {
    static let board = UIImage(named: "PaperBlossomsBoard")
        .map { BoardTexture(image: $0, mapping: .board) }
    static let stones: StoneImages? = {
        guard let black = UIImage(named: "PaperBlossomsBlackStone"),
              let white = UIImage(named: "PaperBlossomsWhiteStone") else { return nil }
        return StoneImages(black: [black], white: [white], blackFaceGain: 1.3)
    }()
    private final class ResourceBundle {}
    static let turnedCorner = UIImage(named: "PaperBlossomsTurnedCorner",
                                      in: Bundle(for: ResourceBundle.self), compatibleWith: nil)
    static let portrait = UIImage(named: "PaperBlossomsScenePortrait")
    static let landscape = UIImage(named: "PaperBlossomsSceneLandscape")
}

/// Warm matte pigments keep labels independent of the red garden. The
/// black/ivory player identities remain the same in both system appearances.
private enum PaperBlossomsColors {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }

    static let page = adaptive(0xF3E5CF, 0x291614)
    static let panel = adaptive(0xFFF0D9, 0x3B211D)
    static let foreground = adaptive(0x54271E, 0xF8E8CC)
    static let detailSecondary = adaptive(0x75513C, 0xDCC1A4)
    static let panelBorder = adaptive(0x9E664E, 0xD7A985)
    static let blackGlass = adaptive(0x2D2B26, 0x292521)
    static let whiteGlass = adaptive(0xF6E8D0, 0xDECEB3)
    static let whiteIdentityGlass = adaptive(0xFFF0D9, 0xE8D7BC)
    static let action = adaptive(0x9F3025, 0x93372C)
    static let chatBubble = adaptive(0xF0D9BB, 0x53332B)
    static let selection = adaptive(0x8A2D24, 0xF1C298)
    static let conditional = adaptive(0x714416, 0xEAD09B)
    static let cream = adaptive(0xFFF3DD, 0xF4E5CC)
    static let keyline = adaptive(0xFFF3DD, 0x291614)
    static let treeGuide = adaptive(0x96664F, 0xCFAC8C)
    static let idle = adaptive(0xDBC3A6, 0x68473A)
    static let blackSurfaceTop = adaptive(0x35332D, 0x302923)
    static let blackSurfaceBottom = adaptive(0x25241F, 0x211C18)
    static let whiteSurfaceTop = adaptive(0xF2DFC0, 0xD8C4A5)
    static let whiteSurfaceBottom = adaptive(0xFFF1DA, 0xE9D8BA)
    static let blackSolid = adaptive(0x2D2B26, 0x292521)
    static let whiteForeground = adaptive(0x54271E, 0x44231B)
    static let blackAccent = adaptive(0xF2C5A0, 0xEFC6A2)
    static let whiteAccent = adaptive(0x8D3026, 0x752B22)
    static let turnOutline = adaptive(0xAD392B, 0xEAB98D)
    static let turnGlow = adaptive(0xC75A3D, 0xDAA174)
    static let blackBorder = adaptive(0xCBB99B, 0xBFA78A)
    static let whiteBorder = adaptive(0x9F6249, 0x865B43)
    static let blackSecondary = adaptive(0xDED1BB, 0xD8C8B1)
    static let whiteSecondary = adaptive(0x79503A, 0x674530)
    static let darkModerator = adaptive(0xE5C5ED, 0xE2C1EB)
    static let lightModerator = adaptive(0x6E3376, 0x56265F)
    static let darkProfessional = adaptive(0xC3DEA9, 0xBCD6A4)
    static let lightProfessional = adaptive(0x35502B, 0x2C4426)
    static let darkSupporter = adaptive(0xF1D29D, 0xEACB99)
    static let lightSupporter = adaptive(0x754416, 0x603916)
    static let darkOrdinary = adaptive(0xBBD9E5, 0xBCD5DF)
    static let lightOrdinary = adaptive(0x28505D, 0x244650)
}

/// One turned corner, shared by full cards and compact headers. The face-only
/// path follows the crease so the turn ring stays on readable ink/ivory paper.
struct PaperBlossomsControlShape: InsettableShape {
    var cornerRadius: CGFloat = 12
    var compact = false
    var faceOnly = false
    var folded = true
    private var insetAmount: CGFloat = 0

    init(cornerRadius: CGFloat = 12, compact: Bool = false, faceOnly: Bool = false, folded: Bool = true) {
        self.cornerRadius = cornerRadius
        self.compact = compact
        self.faceOnly = faceOnly
        self.folded = folded
    }

    static func foldLength(in size: CGSize, compact: Bool) -> CGFloat {
        max(0, min(compact ? 12 : 20, min(size.width, size.height) / 2))
    }

    static func contentClearance(compact: Bool) -> CGFloat { compact ? 14 : 22 }

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard bounds.width > 0, bounds.height > 0 else { return Path() }
        let radius = max(0, min(cornerRadius - insetAmount, min(bounds.width, bounds.height) / 2))
        guard folded else {
            return RoundedRectangle(cornerRadius: radius).path(in: bounds)
        }
        let fold = min(Self.foldLength(in: rect.size, compact: compact),
                       min(bounds.width, bounds.height) / 2)
        let left = bounds.minX, right = bounds.maxX
        let top = bounds.minY, bottom = bounds.maxY
        return Path { path in
            path.move(to: CGPoint(x: left + radius, y: top))
            path.addLine(to: CGPoint(x: right - radius, y: top))
            path.addQuadCurve(to: CGPoint(x: right, y: top + radius),
                              control: CGPoint(x: right, y: top))
            path.addLine(to: CGPoint(x: right, y: bottom - fold))
            if faceOnly {
                path.addCurve(to: CGPoint(x: right - fold, y: bottom),
                              control1: CGPoint(x: right - fold * 0.9, y: bottom - fold),
                              control2: CGPoint(x: right - fold, y: bottom - fold * 0.9))
            } else {
                path.addLine(to: CGPoint(x: right - fold, y: bottom))
            }
            path.addLine(to: CGPoint(x: left + radius, y: bottom))
            path.addQuadCurve(to: CGPoint(x: left, y: bottom - radius),
                              control: CGPoint(x: left, y: bottom))
            path.addLine(to: CGPoint(x: left, y: top + radius))
            path.addQuadCurve(to: CGPoint(x: left + radius, y: top),
                              control: CGPoint(x: left, y: top))
            path.closeSubpath()
        }
    }

    func inset(by amount: CGFloat) -> Self {
        var result = self
        result.insetAmount += amount
        return result
    }
}

/// Flat ink/ivory paper with an actual clipped tip and a vermilion reverse.
/// The artwork is confined to its reserved corner; the broad face stays solid.
struct PaperBlossomsControlSurface: View {
    let color: StoneColor
    var cornerRadius: CGFloat = 12
    var compact = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var showsFold: Bool { contrast != .increased && !reduceTransparency }

    var body: some View {
        let shape = PaperBlossomsControlShape(cornerRadius: cornerRadius, compact: compact,
                                              folded: showsFold)
        shape.fill(SurroundTheme.paperBlossoms.clockSolidSurface(color))
            .overlay {
                GeometryReader { geometry in
                    let length = PaperBlossomsControlShape.foldLength(in: geometry.size, compact: compact)
                    Group {
                        if let image = PaperBlossomsAssets.turnedCorner {
                            Image(uiImage: image).resizable()
                        } else {
                            // A solid reverse also keeps the silhouette intact
                            // in resource-light hosts such as isolated previews.
                            PaperBlossomsColors.action
                        }
                    }
                    .frame(width: length, height: length)
                    .background(PaperBlossomsColors.action)
                    .clipShape(PaperBlossomsCornerFold())
                    .shadow(color: .black.opacity(0.22), radius: 0.8, x: -0.4, y: -0.4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                .opacity(showsFold ? 1 : 0)
            }
            .clipShape(shape)
            .compositingGroup()
            .shadow(color: .black.opacity(showsFold ? 0.2 : 0), radius: 1, x: 0, y: 0.8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The same crease as the face path, in the corner artwork's own coordinates.
private struct PaperBlossomsCornerFold: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.1),
                          control2: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.minY))
            path.closeSubpath()
        }
    }
}

/// The four edges share a uniform scale. Extra width or height opens quiet
/// red paper between them, preserving lanterns and village on narrow windows
/// and divided displays without stretching or cropping their silhouettes.
struct PaperBlossomsSceneLayout: Equatable {
    enum Composition: CaseIterable {
        case portrait, landscape

        var sourceSize: CGSize {
            self == .portrait ? CGSize(width: 1024, height: 1536) : CGSize(width: 1536, height: 1024)
        }

        var assetName: String {
            self == .portrait ? "PaperBlossomsScenePortrait" : "PaperBlossomsSceneLandscape"
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
}

private struct PaperBlossomsScene: View {
    let scheme: ColorScheme

    var body: some View {
        GeometryReader { geometry in
            PaperBlossomsSceneContent(size: geometry.size, scheme: scheme).equatable()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PaperBlossomsSceneContent: View, Equatable {
    let size: CGSize
    let scheme: ColorScheme

    private var legacyChrome: Bool {
        if #available(iOS 26, *) { return false }
        return true
    }

    var body: some View {
        let layout = PaperBlossomsSceneLayout(size: size)
        let paper = Color(themeHex: 0xC21B08)
        let chrome = Color(themeHex: scheme == .dark ? 0x291614 : 0xF3E5CF)
        ZStack {
            ZStack(alignment: .topLeading) {
                paper
                if let image = layout.composition == .portrait
                    ? PaperBlossomsAssets.portrait : PaperBlossomsAssets.landscape {
                    ForEach(PaperBlossomsSceneLayout.Corner.allCases, id: \.self) { corner in
                        let frame = layout.frame(for: corner)
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: frame.width, height: frame.height)
                            .mask(fade(keepsStart: !corner.isTrailing, start: .leading, end: .trailing))
                            .mask(fade(keepsStart: !corner.isBottom, start: .top, end: .bottom))
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .compositingGroup()
            .saturation(scheme == .dark ? 0.72 : 1)
            .colorMultiply(scheme == .dark ? Color(themeHex: 0x87665F) : .white)
            // Keep support close to bare status/navigation ink. The matte
            // game controls carry their own text, so the garden can stay
            // visible beneath them instead of a broad cream wash.
            if legacyChrome {
                VStack(spacing: 0) {
                    LinearGradient(stops: [
                        .init(color: chrome.opacity(0.88), location: 0),
                        .init(color: chrome.opacity(0.68), location: 0.48),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: min(96, layout.size.height * 0.25))
                    Spacer(minLength: 0)
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: chrome.opacity(0.48), location: 0.6),
                        .init(color: chrome.opacity(0.82), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: min(56, layout.size.height * 0.2))
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .clipped()
    }

    private func fade(keepsStart: Bool, start: UnitPoint, end: UnitPoint) -> LinearGradient {
        let first = keepsStart ? Color.white : .clear
        let last = keepsStart ? Color.clear : .white
        return LinearGradient(stops: [
            .init(color: first, location: 0),
            .init(color: first, location: 0.42),
            .init(color: last, location: 0.58),
            .init(color: last, location: 1)
        ], startPoint: start, endPoint: end)
    }
}

// MARK: - Flowing Ink

private struct FlowingInkColors {
    let board: Color
    let nightBoard: Color
    let ink: Color
    let nightInk: Color
    let dame: Color
    let nightDame: Color
    let page: Color
    let panel: Color
    let foreground: Color
    let secondary: Color
    let chat: Color
    let action: Color
    let selection: Color
    let conditional: Color
    let idle: Color
    let black: Color
    let white: Color
    let turnOutline: Color

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
    static let monochrome = Self(
        board: .white, nightBoard: Color(themeHex: 0x777777),
        ink: Color(themeHex: 0x171717), nightInk: Color(themeHex: 0x171717),
        dame: Color(themeHex: 0x171717), nightDame: Color(themeHex: 0x171717),
        page: adaptive(0xFFFFFF, 0x242424), panel: adaptive(0xFAFAFA, 0x2D2D2D),
        foreground: adaptive(0x171717, 0xF1F1F1), secondary: adaptive(0x555555, 0xC5C5C5),
        chat: adaptive(0xECECEC, 0x393939), action: adaptive(0x171717, 0x6E6E6E),
        selection: adaptive(0x171717, 0xE0E0E0), conditional: adaptive(0x171717, 0xE0E0E0),
        idle: adaptive(0xE5E5E5, 0x484848),
        black: adaptive(0x000000, 0x0B0B0B), white: adaptive(0xFFFFFF, 0xDADADA),
        turnOutline: adaptive(0x171717, 0x777777)
    )
    static let jade = Self(
        board: Color(themeHex: 0xDDE7DB), nightBoard: Color(themeHex: 0x748478),
        ink: Color(themeHex: 0x28513F), nightInk: Color(themeHex: 0x183326),
        dame: Color(themeHex: 0x6B4C22), nightDame: Color(themeHex: 0x3D2A10),
        page: adaptive(0xFFFFFF, 0x242A27), panel: adaptive(0xFAFAFA, 0x2A332E),
        foreground: adaptive(0x171717, 0xEAF0EB), secondary: adaptive(0x555555, 0xC2CCC4),
        chat: adaptive(0xE1E9E0, 0x39463D), action: adaptive(0x28513F, 0x4D7B61),
        selection: adaptive(0x28513F, 0xB7D6BF), conditional: adaptive(0x6B4C22, 0xE1C391),
        idle: adaptive(0xDFE7DD, 0x414E45),
        black: adaptive(0x000000, 0x0A0C0B), white: adaptive(0xFFFFFF, 0xD9DEDA),
        turnOutline: adaptive(0x28513F, 0x617F67)
    )
    static let wood = Self(
        board: Color(themeHex: 0xE6BD76), nightBoard: Color(themeHex: 0x99825D),
        ink: Color(themeHex: 0x62421F), nightInk: Color(themeHex: 0x35240F),
        dame: Color(themeHex: 0x4C4830), nightDame: Color(themeHex: 0x2B2C17),
        page: adaptive(0xFAF5EA, 0x29251F), panel: adaptive(0xFFFBF2, 0x342E25),
        foreground: adaptive(0x2C2418, 0xF4EBDD), secondary: adaptive(0x655744, 0xCFC2AD),
        chat: adaptive(0xEEE1C9, 0x453A2B), action: adaptive(0x62421F, 0x886638),
        selection: adaptive(0x62421F, 0xE5C78E), conditional: adaptive(0x4C4830, 0xCEC99F),
        idle: adaptive(0xE9DDC5, 0x514532),
        black: adaptive(0x000000, 0x0D0B08), white: adaptive(0xFFFFFF, 0xE2D9C9),
        turnOutline: adaptive(0x62421F, 0x987A4E)
    )
    static let keyline = adaptive(0xFFFFFF, 0x171717)
    static let blackBorder = adaptive(0x666666, 0x999999)
}

extension SurroundTheme {
    private var flowingInkColors: FlowingInkColors {
        switch self {
        case .flowingInkJade: .jade
        // Retain the stored mode ID while giving the paper-only color mode
        // its own wooden board and coordinated warm surfaces.
        case .flowingInkJadePlain: .wood
        default: .monochrome
        }
    }

    private var flowingInkAction: Color {
        flowingInkColors.action
    }

    private var flowingInkSelection: Color {
        flowingInkColors.selection
    }

    private var flowingInkBoard: BoardAppearance {
        let paper = flowingInkColors.board
        let accent = flowingInkColors.ink
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
                                outline: .black, outlineWidth: 0.75, outlineReferenceDiameter: 18,
                                lastMove: .black, label: .black),
            emptyPointMarker: .black,
            markOutline: .black,
            dameColor: flowingInkColors.dame,
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
    let paper: Color

    var body: some View {
        GeometryReader { geometry in
            let layout = FlowingInkSceneLayout(size: geometry.size)
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
            .modifier(GameDetailLegacyTint(color: (theme.isFlowingInk || theme == .feltMeadow || theme == .nightGarden || theme == .christmasKeepsakes || theme == .paperBlossoms) ? theme.foreground : .accentColor))
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

/// Weathered pine with frayed edges, worn fibers and accumulated upper snow. The
/// material owns no layout or interaction; clock and identity content sit above it.
struct FrostPineWoodPlateSurface: View {
    enum Role: Equatable { case clock, player }

    let color: StoneColor
    let cornerRadius: CGFloat
    let role: Role
    var compact = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        FrostPineWoodPlateMaterial(color: color, cornerRadius: cornerRadius, role: role,
                                  compact: compact, scheme: colorScheme,
                                  reduceTransparency: reduceTransparency, contrast: contrast)
    }
}

/// Explicit appearance inputs keep the drawing independent of clock updates.
struct FrostPineWoodPlateMaterial: View {
    let color: StoneColor
    let cornerRadius: CGFloat
    let role: FrostPineWoodPlateSurface.Role
    var compact = false
    let scheme: ColorScheme
    let reduceTransparency: Bool
    let contrast: ColorSchemeContrast

    var body: some View {
        Group {
            if reduceTransparency || contrast == .increased {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(SurroundTheme.frostPine.clockSolidSurface(color))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(SurroundTheme.frostPine.identityChipBorder(color),
                                          lineWidth: contrast == .increased ? 2 : 1)
                    }
            } else {
                FrostPineWoodPlateDrawing(color: color, cornerRadius: cornerRadius,
                                          role: role, compact: compact, scheme: scheme)
                    .equatable()
                    .shadow(color: Color(themeHex: 0x242A27).opacity(scheme == .dark ? 0.23 : 0.17),
                            radius: compact ? 0.65 : 1.25, x: compact ? 0.2 : 0.4, y: compact ? 0.5 : 0.8)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FrostPineWoodPlateDrawing: View, Equatable {
    let color: StoneColor
    let cornerRadius: CGFloat
    let role: FrostPineWoodPlateSurface.Role
    let compact: Bool
    let scheme: ColorScheme

    private var darkStone: Bool { color == .black }
    private var seed: UInt32 {
        role == .clock ? (darkStone ? 17 : 83) : (darkStone ? 139 : 211)
    }
    private var frostOverflow: CGFloat { compact ? 3 : 6 }

    var body: some View {
        Canvas { context, size in
            guard size.width > 8, size.height > 8 else { return }
            // Extra drawing room lets the frost stand above the plate without
            // moving its original face, content, or interaction bounds.
            let outer = CGRect(origin: CGPoint(x: frostOverflow + 0.5, y: frostOverflow + 0.5),
                               size: CGSize(width: size.width - frostOverflow * 2 - 1,
                                            height: size.height - frostOverflow * 2 - 1))
            guard outer.width > 8, outer.height > 8 else { return }
            let depth = compact ? 0.6 : min(1.35, outer.height * 0.022)
            let face = CGRect(x: outer.minX, y: outer.minY,
                              width: outer.width, height: outer.height - depth)
            let radius = min(cornerRadius, face.height / 2, face.width / 2)
            let facePath = woodPath(face, radius: radius)

            // A shallow raw-pine cut warms the lower edge. The face and all
            // decoration stay inside the existing layout and text reservation.
            context.fill(woodPath(outer, radius: radius), with: .linearGradient(
                Gradient(colors: [Color(themeHex: 0xD5C3A4), Color(themeHex: 0x827761),
                                  Color(themeHex: 0xB7A17D)]),
                startPoint: CGPoint(x: outer.minX, y: outer.minY),
                endPoint: CGPoint(x: outer.maxX, y: outer.maxY)))
            context.fill(facePath, with: .linearGradient(
                Gradient(stops: SurroundTheme.frostPine.clockSurfaceStops(color, scheme: scheme)),
                startPoint: CGPoint(x: face.minX, y: face.minY),
                endPoint: CGPoint(x: face.minX + face.width * 0.35, y: face.maxY)))

            var faceContext = context
            faceContext.clip(to: facePath)
            if let wood = FrostPineAssets.controlWood(color) {
                // Tile in points, never stretch the grain to the control's
                // aspect ratio. Each player and role gets a stable cut of wood.
                var grainContext = faceContext
                grainContext.opacity = 0.90
                grainContext.fill(facePath, with: .tiledImage(Image(uiImage: wood),
                    origin: CGPoint(x: face.minX - CGFloat(seed % 97),
                                    y: face.minY - CGFloat(seed % 173)), scale: 0.625))
            }

            drawSurfaceWear(context: &faceContext, rect: face)
            let rimWidth: CGFloat = compact ? 1.8 : 3
            var rim = woodPath(outer, radius: radius)
            rim.addPath(path(outer.insetBy(dx: rimWidth, dy: rimWidth),
                             radius: max(0, radius - rimWidth)))
            var rimContext = faceContext
            rimContext.clip(to: rim, style: FillStyle(eoFill: true))
            // Keep the edge broken and fibrous rather than outlining the wood
            // with a smooth polished bevel. The warm cut remains below it.
            rimContext.stroke(facePath, with: .color(Color(themeHex: 0x383A31).opacity(0.40)),
                              lineWidth: 0.45)
            drawWeatheredEdges(context: &rimContext, rect: face, radius: radius)

            // The inner rounded reserve excludes bright powder even at the
            // curved corners; the outer context preserves its raised silhouette.
            var frostContext = context
            var frostRegion = Path(CGRect(origin: .zero, size: size))
            frostRegion.addPath(path(outer.insetBy(dx: rimWidth, dy: rimWidth),
                                     radius: max(0, radius - rimWidth)))
            frostContext.clip(to: frostRegion, style: FillStyle(eoFill: true))
            drawTopFrost(context: &frostContext, rect: face, radius: radius)
        }
        .padding(-frostOverflow)
    }

    private func path(_ rect: CGRect, radius: CGFloat) -> Path {
        RoundedRectangle(cornerRadius: radius, style: .circular).path(in: rect)
    }

    /// Erosion stays inside the existing control bounds. Sampling in points
    /// keeps small bites visible on both compact chips and wide clock plates.
    private func woodPath(_ rect: CGRect, radius: CGFloat) -> Path {
        var points: [CGPoint] = []
        let reach: CGFloat = compact ? 0.55 : 1.15
        func append(_ point: CGPoint, inward: CGVector) {
            let phase = (point.x - rect.minX) * 0.23 + (point.y - rect.minY) * 0.47 + CGFloat(seed)
            let chips = 0.12 + 0.20 * (0.5 + 0.5 * sin(phase * 2.7))
                + 0.68 * pow(max(0, sin(phase * 0.61)), 5)
            points.append(CGPoint(x: point.x + inward.dx * reach * chips,
                                  y: point.y + inward.dy * reach * chips))
        }
        func line(_ first: CGPoint, _ last: CGPoint, inward: CGVector) {
            let count = max(1, Int(hypot(last.x - first.x, last.y - first.y) / 1.25))
            for index in 0..<count {
                let t = CGFloat(index) / CGFloat(count)
                append(CGPoint(x: first.x + (last.x - first.x) * t,
                               y: first.y + (last.y - first.y) * t), inward: inward)
            }
        }
        func corner(_ center: CGPoint, start: CGFloat) {
            let count = max(3, Int(radius * .pi / 2 / 1.25))
            for index in 0..<count {
                let angle = start + CGFloat(index) / CGFloat(count) * .pi / 2
                append(CGPoint(x: center.x + cos(angle) * radius,
                               y: center.y + sin(angle) * radius),
                       inward: CGVector(dx: -cos(angle), dy: -sin(angle)))
            }
        }
        line(CGPoint(x: rect.minX + radius, y: rect.minY),
             CGPoint(x: rect.maxX - radius, y: rect.minY), inward: CGVector(dx: 0, dy: 1))
        corner(CGPoint(x: rect.maxX - radius, y: rect.minY + radius), start: -.pi / 2)
        line(CGPoint(x: rect.maxX, y: rect.minY + radius),
             CGPoint(x: rect.maxX, y: rect.maxY - radius), inward: CGVector(dx: -1, dy: 0))
        corner(CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), start: 0)
        line(CGPoint(x: rect.maxX - radius, y: rect.maxY),
             CGPoint(x: rect.minX + radius, y: rect.maxY), inward: CGVector(dx: 0, dy: -1))
        corner(CGPoint(x: rect.minX + radius, y: rect.maxY - radius), start: .pi / 2)
        line(CGPoint(x: rect.minX, y: rect.maxY - radius),
             CGPoint(x: rect.minX, y: rect.minY + radius), inward: CGVector(dx: 1, dy: 0))
        corner(CGPoint(x: rect.minX + radius, y: rect.minY + radius), start: .pi)
        return polygon(points)
    }

    private func drawSurfaceWear(context: inout GraphicsContext, rect: CGRect) {
        var random = Grain(seed: seed ^ 0x325D)
        // These pigments share the cached grain's bounded range, so a shallow
        // check or a small pit can cross the face without weakening its labels.
        let groove = Color(themeHex: darkStone ? 0x202722 : 0xD0D1C5)
        let fiber = Color(themeHex: darkStone ? 0x4A4F45 : 0xF0EDE3)
        for index in 0..<(compact ? 3 : 7) {
            let fraction = (CGFloat(index) + 0.3 + random.next() * 0.5) / CGFloat(compact ? 3 : 7)
            let y = rect.minY + rect.height * fraction
            let length = min(rect.width * 0.48, compact ? 34 : 92) * (0.55 + random.next() * 0.45)
            let x = rect.minX + random.next() * max(0, rect.width - length)
            let depth: CGFloat = compact ? 0.55 : 1.1
            let check = polygon([
                CGPoint(x: x, y: y),
                CGPoint(x: x + length * 0.28, y: y - depth * 0.45),
                CGPoint(x: x + length * 0.68, y: y + depth * 0.15),
                CGPoint(x: x + length, y: y - depth * 0.3),
                CGPoint(x: x + length * 0.74, y: y + depth * 0.5),
                CGPoint(x: x + length * 0.34, y: y + depth)
            ])
            context.fill(check, with: .color(groove.opacity(0.65 + Double(random.next()) * 0.30)))
            var lip = Path()
            lip.move(to: CGPoint(x: x + length * 0.20, y: y + depth))
            lip.addLine(to: CGPoint(x: x + length * 0.75, y: y + depth * 0.6))
            context.stroke(lip, with: .color(fiber.opacity(0.70)), lineWidth: compact ? 0.35 : 0.5)
        }
        let count = min(90, max(12, Int(rect.width * rect.height / 240)))
        for _ in 0..<count {
            let x = rect.minX + random.next() * rect.width
            let y = rect.minY + random.next() * rect.height
            let width = 0.7 + random.next() * 2.4
            let depth = 0.25 + random.next() * (compact ? 0.25 : 0.45)
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: width, height: depth)),
                         with: .color(groove.opacity(0.35 + Double(random.next()) * 0.5)))
        }
    }

    private func drawWeatheredEdges(context: inout GraphicsContext, rect: CGRect, radius: CGFloat) {
        var random = Grain(seed: seed ^ 0x74B1)
        let reach: CGFloat = compact ? 1.5 : 3.5
        for index in 0..<(compact ? 3 : 6) {
            let fromLeft = (index + Int(seed)) % 2 == 0
            let upper = index < (compact ? 1 : 3)
            let length = min(rect.width * 0.38, compact ? 30 : 72) * (0.65 + random.next() * 0.35)
            let x = fromLeft ? rect.minX + radius * 0.25 : rect.maxX - radius * 0.25
            let direction: CGFloat = fromLeft ? 1 : -1
            let y = upper ? rect.minY + reach * (0.25 + random.next() * 0.5)
                          : rect.maxY - reach * (0.25 + random.next() * 0.5)
            let split = polygon([
                CGPoint(x: x, y: y - 0.35),
                CGPoint(x: x + direction * length * 0.35, y: y + reach * 0.15),
                CGPoint(x: x + direction * length, y: y - reach * 0.18),
                CGPoint(x: x + direction * length * 0.55, y: y + reach * 0.25),
                CGPoint(x: x, y: y + (compact ? 0.6 : 1.2))
            ])
            context.fill(split, with: .color(Color(themeHex: 0x292B25).opacity(0.85)))
            var splinter = Path()
            splinter.move(to: CGPoint(x: x, y: y + reach * 0.5))
            splinter.addLine(to: CGPoint(x: x + direction * length * 0.36, y: y + reach * 0.35))
            splinter.addLine(to: CGPoint(x: x + direction * length * 0.76, y: y + reach * 0.15))
            context.stroke(splinter, with: .color(Color(themeHex: 0xDCC8A3).opacity(0.80)),
                           style: StrokeStyle(lineWidth: compact ? 0.65 : 1, lineCap: .butt))
        }
        // Raw fibers appear in broken runs along upper, lower and side edges.
        for index in 0..<(compact ? 18 : 44) {
            let fraction = random.next()
            let upper = index % 3 == 0
            let x = rect.minX + fraction * rect.width
            let top = topEdge(at: x, rect: rect, radius: radius)
            let y = upper ? top + random.next() * reach
                          : rect.maxY - (top - rect.minY) - random.next() * reach
            var fiber = Path()
            fiber.move(to: CGPoint(x: x, y: y))
            fiber.addLine(to: CGPoint(x: x + 1 + random.next() * (compact ? 5 : 11), y: y - 0.4))
            context.stroke(fiber, with: .color(Color(themeHex: 0xDED9C7).opacity(0.40 + Double(random.next()) * 0.40)),
                           lineWidth: compact ? 0.45 : 0.7)
        }
    }

    private func drawTopFrost(context: inout GraphicsContext, rect: CGRect, radius: CGFloat) {
        let deposits: [(center: CGFloat, fraction: CGFloat, limit: CGFloat)]
        switch (role, color) {
        case (.clock, .black): deposits = [(0.22, 0.48, 200), (0.73, 0.43, 180)]
        case (.clock, .white): deposits = [(0.16, 0.32, 132), (0.64, 0.57, 220), (0.96, 0.10, 34)]
        case (.player, .black): deposits = [(0.27, 0.58, 110), (0.82, 0.28, 58)]
        case (.player, .white): deposits = [(0.14, 0.28, 40), (0.66, 0.62, 100)]
        }
        let height: CGFloat = compact ? 2 : 4.8
        let inward: CGFloat = compact ? 1.1 : 2.3
        for (index, deposit) in deposits.enumerated() {
            var random = Grain(seed: (seed ^ 0xA591) &+ UInt32(index) &* 709)
            let width = min(deposit.limit, rect.width * deposit.fraction)
            let start = max(rect.minX + 1, min(rect.maxX - width - 1,
                rect.minX + rect.width * deposit.center - width / 2))
            let phase = random.next() * .pi * 2
            func envelope(_ t: CGFloat) -> CGFloat {
                pow(max(0, sin(t * .pi)), 0.32)
                    * (0.76 + 0.13 * sin(t * .pi * 5 + phase) + 0.11 * sin(t * .pi * 9 - phase))
            }
            var crown: [CGPoint] = [], underside: [CGPoint] = []
            let samples = max(8, Int(width / 0.75))
            for sample in 0...samples {
                let t = CGFloat(sample) / CGFloat(samples)
                let x = start + width * t
                let edge = topEdge(at: x, rect: rect, radius: radius)
                let body = envelope(t)
                crown.append(CGPoint(x: x, y: edge - height * body * (0.55 + random.next() * 0.45)))
                underside.append(CGPoint(x: x, y: edge + inward * body * (0.45 + random.next() * 0.55)))
            }
            let depositPath = polygon(crown + Array(underside.reversed()))
            var contact = context
            contact.translateBy(x: 0.25, y: compact ? 0.6 : 0.9)
            contact.fill(depositPath, with: .color(Color(themeHex: 0x536F7C).opacity(0.58)))
            context.fill(depositPath, with: .linearGradient(
                Gradient(colors: [Color(themeHex: 0xFFFEF8), Color(themeHex: 0xCBE5F3)]),
                startPoint: CGPoint(x: start, y: rect.minY - height),
                endPoint: CGPoint(x: start, y: rect.minY + inward)))
            for _ in 0..<max(8, Int(width * 1.5)) {
                let t = random.next()
                let x = start + t * width
                let body = envelope(t)
                let y = topEdge(at: x, rect: rect, radius: radius) - body * height * random.next()
                let grain = (compact ? 0.35 : 0.65) + random.next() * (compact ? 0.40 : 0.75)
                context.fill(polygon([CGPoint(x: x - grain, y: y),
                                      CGPoint(x: x, y: y - grain * 0.8),
                                      CGPoint(x: x + grain, y: y + grain * 0.2),
                                      CGPoint(x: x, y: y + grain * 0.6)]),
                             with: .color(.white.opacity(0.62 + Double(random.next()) * 0.35)))
            }
        }
    }

    private func topEdge(at x: CGFloat, rect: CGRect, radius: CGFloat) -> CGFloat {
        let dx = max(rect.minX + radius - x, x - (rect.maxX - radius), 0)
        return rect.minY + radius - sqrt(max(0, radius * radius - dx * dx))
    }

    private func polygon(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
    }

    private struct Grain {
        var seed: UInt32
        mutating func next() -> CGFloat {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return CGFloat(seed >> 8) / CGFloat(0x00FF_FFFF)
        }
    }
}

/// A flat, stone-contrasting turn cue that also reads when a compact clock
/// omits its status label or shows a score estimate. The stroke stays inside
/// the solid clock face, so landscape colors cannot reduce its contrast.
struct GameDetailMatteClockOutline: View {
    let color: StoneColor
    let isRunning: Bool
    var isWarning = false
    var cornerRadius: CGFloat = 12
    var paperCompact = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.surroundTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let increased = contrast == .increased
        let foreground = theme.clockForeground(color, scheme: colorScheme)
        let runningInk = theme == .paperBlossoms
            ? (isWarning ? theme.clockSuddenDeathAccent(color, scheme: colorScheme) : theme.clockAccent(color))
            : foreground
        let ink = isRunning ? runningInk : foreground.opacity(increased ? 0.5 : 0.22)
        let width: CGFloat = isRunning ? (increased ? 4 : 3) : (increased ? 2 : 1)
        if theme == .paperBlossoms {
            PaperBlossomsControlShape(cornerRadius: cornerRadius, compact: paperCompact,
                                      faceOnly: true, folded: !increased && !reduceTransparency)
                .strokeBorder(ink, lineWidth: width)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(ink, lineWidth: width)
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

/// Material themes use a contrast-checked pigment on detail panels.
/// Other themes retain their hierarchical secondary style.
struct GameDetailSecondaryText: ViewModifier {
    @Environment(\.surroundTheme) private var theme

    @ViewBuilder func body(content: Content) -> some View {
        if theme.isFlowingInk || theme == .feltMeadow || theme == .nightGarden || theme == .christmasKeepsakes || theme == .paperBlossoms {
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

/// Scene art behind bare system status text sometimes needs a narrow
/// contrast margin. Read the owning window's actual status frame: there is no
/// band behind Duo's self-backed status tray, hidden-status Zen, Mac windows
/// or picker art.
struct ThemeStatusBarContrast: View {
    @Environment(\.surroundTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    var hidden = false

    private var opacity: CGFloat {
        // Older scenes already back their unglazed navigation controls.
        if #unavailable(iOS 26.0), !theme.isFlowingInk { return 0 }
        // Nebula's bright planet sits behind the white battery glyphs.
        if colorScheme == .dark { return theme == .nebulaPearl ? 0.55 : 0 }
        return switch theme {
        case .nightGarden: 0.8
        case .flowingInk, .flowingInkJade: 0.85
        case .rakedGarden, .frostPine, .surroundStudio, .paperBlossoms: 0.55
        default: 0
        }
    }

    var body: some View {
        #if targetEnvironment(macCatalyst)
        EmptyView()
        #else
        if !hidden, theme.showsSceneArt, opacity > 0 {
            StatusBarContrastSurface(color: UIColor(theme.pageBackground),
                                     opacity: opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        #endif
    }
}

private struct StatusBarContrastSurface: UIViewRepresentable {
    let color: UIColor
    let opacity: CGFloat

    func makeUIView(context: Context) -> StatusBarContrastView {
        StatusBarContrastView()
    }

    func updateUIView(_ view: StatusBarContrastView, context: Context) {
        view.color = color.withAlphaComponent(opacity)
        view.setNeedsLayout()
    }

    final class StatusBarContrastView: UIView {
        var color: UIColor = .clear
        private let gradient = CAGradientLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            layer.addSublayer(gradient)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            setNeedsLayout()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            gradient.isHidden = true
            guard let window, let scene = window.windowScene, let status = scene.statusBarManager,
                  !status.isStatusBarHidden, status.statusBarFrame.height > 0 else {
                return
            }
            #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
            if #available(iOS 27.1, *) {
                // Side bars and divided displays use the system's own status
                // tray, including the horizontal tray after unfolding.
                if window.traitCollection.verticalBarEdge != .unspecified
                    || window.reservedRegions(kind: .division, options: .includeInactive)
                        .contains(where: { $0.frame.intersects(window.bounds) }) {
                    return
                }
            }
            #endif
            let coordinateSpace: any UICoordinateSpace
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                coordinateSpace = scene.effectiveGeometry.coordinateSpace
            } else {
                coordinateSpace = scene.coordinateSpace
            }
            let windowFrame = window.convert(status.statusBarFrame, from: coordinateSpace)
            // A narrow tray or vertical rail must never become a full-width
            // wash. Support only a conventional status band at the window top.
            guard windowFrame.width > windowFrame.height,
                  abs(windowFrame.minX - window.bounds.minX) < 1,
                  abs(windowFrame.maxX - window.bounds.maxX) < 1,
                  abs(windowFrame.minY - window.bounds.minY) < 1 else { return }
            let frame = convert(windowFrame, from: window)
            gradient.isHidden = false
            gradient.frame = CGRect(x: 0, y: frame.minY, width: bounds.width,
                                    height: frame.height + 18)
            gradient.colors = [color.cgColor, color.cgColor, color.withAlphaComponent(0).cgColor]
            // Keep even the shorter iPad status glyphs on stable pigment,
            // then feather only the lower edge of their margin.
            gradient.locations = [0, NSNumber(value: Double(max(0, frame.height - 3) / (frame.height + 18))), 1]
        }
    }
}

/// The page behind Game Detail: the theme's scene, or its plain color.
struct GameDetailBackdrop: View {
    @Environment(\.surroundTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    var usesPhoneLandscapeFraming = false

    var body: some View {
        switch theme {
        case .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain:
            FlowingInkScene(usesColor: theme.flowingInkUsesColor, showsLandscape: theme.showsSceneArt,
                            paper: theme.pageBackground)
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
            ChristmasKeepsakesScene(scheme: colorScheme, usesPhoneLandscapeFraming: usesPhoneLandscapeFraming)
        case .paperBlossoms:
            PaperBlossomsScene(scheme: colorScheme)
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

    init(size: CGSize, usesPhoneLandscapeFraming: Bool = false) {
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
        // Wide ordinary phone landscape needs more of the frosted pane above
        // the sill. Move the whole photograph without enlarging its gifts;
        // their bases may crop slightly below the viewport. Other contexts
        // keep their original bottom anchor. A closed divided phone can have
        // no visible division; its narrower landscape shape needs no reveal.
        let wideLandscapeWeight = height > 0 ? min(1, max(0, (width / height - 1.5) / 0.25)) : 0
        let bottomCrop = usesPhoneLandscapeFraming && composition == .compactLandscape
            ? min(height * 0.12 * wideLandscapeWeight, max(0, side - height)) : 0
        backdrop = CGRect(x: 0, y: height - side + bottomCrop, width: side, height: side)

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

/// A standing tree continues beyond the right and bottom edges. Its scale
/// depends only on the shorter viewport edge, so panels and Zen cannot move it
/// and rotation reveals different boughs without enlarging the decorations.
struct ChristmasKeepsakesTreeLayout: Equatable {
    let frame: CGRect

    init(size: CGSize, artworkSize: CGSize) {
        let width = size.width.isFinite ? max(0, size.width) : 0
        let height = size.height.isFinite ? max(0, size.height) : 0
        guard width > 0, height > 0,
              artworkSize.width.isFinite, artworkSize.height.isFinite,
              artworkSize.width > 0, artworkSize.height > 0 else {
            frame = .zero
            return
        }
        let scale = min(1, min(width, height) / 440)
        let treeHeight = 560 * scale
        let treeWidth = treeHeight * artworkSize.width / artworkSize.height
        guard treeWidth.isFinite, treeWidth > 0 else {
            frame = .zero
            return
        }
        // The portrait source includes clear space before its outer needles;
        // this frame reach leaves only a smaller strip of actual foliage.
        let visibleWidth = min(80 * scale, treeWidth * 0.32)
        frame = CGRect(x: width - visibleWidth, y: height - treeHeight * 0.9,
                       width: treeWidth, height: treeHeight)
    }
}

private struct ChristmasKeepsakesScene: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let scheme: ColorScheme
    let usesPhoneLandscapeFraming: Bool

    var body: some View {
        GeometryReader { geometry in
            ChristmasKeepsakesSceneContent(size: geometry.size, scheme: scheme,
                                           usesPhoneLandscapeFraming: usesPhoneLandscapeFraming,
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
    let usesPhoneLandscapeFraming: Bool
    let showsLight: Bool

    private var chrome: Color {
        Color(themeHex: scheme == .dark ? 0x201610 : 0xEAE1D1)
    }

    private var usesLegacyChrome: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }

    private var legacyTopFade: Gradient {
        Gradient(stops: [
            .init(color: chrome.opacity(0.92), location: 0),
            .init(color: chrome.opacity(0.92), location: 0.62),
            .init(color: .clear, location: 1)
        ])
    }

    var body: some View {
        let layout = ChristmasKeepsakesRoomLayout(size: size, usesPhoneLandscapeFraming: usesPhoneLandscapeFraming)
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
            if let tree = ChristmasKeepsakesTreeAssets.image {
                let frame = ChristmasKeepsakesTreeLayout(size: size, artworkSize: tree.size).frame
                Image(uiImage: tree)
                    .resizable()
                    .saturation(scheme == .dark ? 0.78 : 1)
                    .colorMultiply(scheme == .dark ? Color(themeHex: 0x8A7767) : .white)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
            RadialGradient(colors: [Color(themeHex: 0xF4DFC2).opacity(scheme == .dark ? 0.16 : 0.13), .clear],
                           center: .center, startRadius: 0, endRadius: 210)
                .frame(width: 420, height: 420)
                .position(layout.lightCenter)
            // Only older unbacked buttons need fades behind their bars.
            // Modern chrome leaves the winter window and pine exposed.
            if usesLegacyChrome {
                VStack(spacing: 0) {
                    LinearGradient(gradient: legacyTopFade, startPoint: .top, endPoint: .bottom)
                        .frame(height: min(92, size.height * 0.16))
                    Spacer(minLength: 0)
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: chrome.opacity(0.90), location: 0.5),
                        .init(color: chrome.opacity(0.96), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: min(96, size.height * 0.16))
                }
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
            // Status support belongs to the screen, not the artwork.
            // Only legacy buttons need fades behind their bars here.
            if usesLegacyChrome {
                VStack(spacing: 0) {
                    LinearGradient(stops: [
                        .init(color: chrome.opacity(0.98), location: 0),
                        .init(color: chrome.opacity(0.94), location: 0.68),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: min(110, size.height * 0.22))
                    Spacer(minLength: 0)
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: chrome.opacity(0.90), location: 0.5),
                        .init(color: chrome.opacity(0.96), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: min(96, size.height * 0.16))
                }
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

    private var legacyTopFade: Gradient {
        Gradient(stops: [
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
            // Only older toolbar buttons need scene support; modern
            // controls have their own glass and status support is separate.
            if usesLegacyChrome {
                VStack(spacing: 0) {
                    LinearGradient(gradient: legacyTopFade, startPoint: .top, endPoint: .bottom)
                        .frame(height: min(92, size.height * 0.16))
                    Spacer(minLength: 0)
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: chrome.opacity(0.90), location: 0.55),
                        .init(color: chrome.opacity(0.96), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: min(96, size.height * 0.16))
                }
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
            if usesLegacyChrome {
                VStack(spacing: 0) {
                    LinearGradient(stops: [
                        .init(color: chrome.opacity(0.94), location: 0),
                        .init(color: chrome.opacity(0.92), location: 0.55),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: min(110, size.height * 0.18))
                    Spacer(minLength: 0)
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: chrome.opacity(0.90), location: 0.55),
                        .init(color: chrome.opacity(0.94), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: min(96, size.height * 0.16))
                }
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
            if usesLegacyChrome {
                VStack(spacing: 0) {
                    LinearGradient(stops: [
                        .init(color: chrome.opacity(0.94), location: 0),
                        .init(color: chrome.opacity(0.92), location: 0.55),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: min(110, size.height * 0.18))
                    Spacer(minLength: 0)
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: chrome.opacity(0.90), location: 0.55),
                        .init(color: chrome.opacity(0.94), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: min(96, size.height * 0.16))
                }
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
                if usesLegacyChrome {
                    VStack(spacing: 0) {
                        LinearGradient(stops: [
                            .init(color: .white.opacity(0.08), location: 0),
                            .init(color: .white.opacity(0.12), location: 0.55),
                            .init(color: .white, location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                        .frame(height: 80)
                        Color.white
                    }
                } else {
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
            // Earlier toolbar icons need quiet foliage behind them.
            // Modern controls carry their own glass.
            .mask {
                if usesLegacyChrome {
                    VStack(spacing: 0) {
                        LinearGradient(stops: [
                            .init(color: .white.opacity(0.08), location: 0),
                            .init(color: .white.opacity(0.08), location: 0.62),
                            .init(color: .white, location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                        .frame(height: layout.topFadeHeight)
                        Color.white
                    }
                } else {
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

    private var usesLegacyChrome: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }

    private var legacyTopFade: Gradient {
        // Earlier toolbars have no glass backing. Keep their icons on quiet
        // sand while preserving the foliage below the navigation controls.
        Gradient(stops: [
            .init(color: sand.opacity(0.92), location: 0),
            .init(color: sand.opacity(0.92), location: 0.62),
            .init(color: .clear, location: 1)
        ])
    }

    private var legacyBottomFade: Gradient {
        Gradient(stops: [
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
            // Only older unbacked controls need support from the scene.
            if usesLegacyChrome {
                VStack(spacing: 0) {
                    LinearGradient(gradient: legacyTopFade,
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: layout.topFadeHeight)
                    Spacer(minLength: 0)
                    LinearGradient(gradient: legacyBottomFade,
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: layout.bottomFadeHeight)
                }
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
    private var usesLegacyChrome: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }

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
                // Modern controls have their own glass. Only older bars
                // need the scene to fade behind their unbacked icons.
                if usesLegacyChrome {
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
