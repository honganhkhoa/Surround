import SwiftUI

final class KoiPondBoard {
    private init() {}

    private static let pebbles: StoneImages? = {
        let bundle = Bundle(for: KoiPondBoard.self)
        guard let charcoal = UIImage(named: "KoiPondBlackStone", in: bundle, compatibleWith: nil),
              let cream = UIImage(named: "KoiPondWhiteStone", in: bundle, compatibleWith: nil) else { return nil }
        return StoneImages(black: [charcoal], white: [cream])
    }()

    fileprivate static let charcoalGrain = Image(decorative: "KoiPondBlackGrain", bundle: KoiPond.bundle)
    fileprivate static let creamGrain = Image(decorative: "KoiPondWhiteGrain", bundle: KoiPond.bundle)

    static func appearance(for scheme: ColorScheme) -> BoardAppearance {
        let night = scheme == .dark
        let pond = Color(themeHex: night ? 0x769295 : 0x77A2A0)
        let ink = Color(themeHex: 0x071D20)
        let lettering = Color(themeHex: 0x00080A)
        let cream = Color(themeHex: 0xFFF7E8)
        let leaves = Color(themeHex: 0x133A29)
        let vermilion = Color(themeHex: 0x612222)
        let deepWater = Color(themeHex: 0x102F40)
        var stones = pebbles
        if night { stones?.tint = Color(themeHex: 0xD9E3E5) }
        return BoardAppearance(
            boardColor: pond,
            waterGlass: Color(themeHex: night ? 0x93B6B7 : 0xA8CFCA).opacity(night ? 0.63 : 0.49),
            castsBoardShadow: false, gridLineScale: 1.2, stoneImages: stones,
            gridColor: ink, coordinateColor: lettering,
            black: StonePalette(
                highlight: Color(themeHex: 0x68675E), shade: Color(themeHex: 0x161F22),
                flat: Color(themeHex: 0x262E2F), lastMove: cream, label: cream, detailedMarkerCasing: ink),
            white: StonePalette(
                highlight: cream, shade: Color(themeHex: 0xAE9980),
                flat: Color(themeHex: 0xF0E3CA), outline: Color(themeHex: 0x344542),
                lastMove: ink, label: ink, detailedMarkerCasing: cream),
            emptyPointMarker: lettering, markOutline: ink, dameColor: Color(themeHex: 0x35283C),
            highlightColor: deepWater, highlightCasing: cream,
            crosshair: .init(valid: leaves, invalid: vermilion, removal: deepWater),
            crosshairWidth: 1.5, removeMark: vermilion, restoreMark: leaves,
            removalMarkCasing: cream, removedStoneOutline: ink)
    }
}

/// The chip's fine mineral inclusions come from the corresponding board stone.
/// Their scale stays fixed as the identity becomes a header, row or column.
struct KoiPondPebbleChip: View {
    let color: StoneColor
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let dark = color == .black
        let night = scheme == .dark
        let face = dark ? Color(themeHex: night ? 0x282F30 : 0x303636)
                        : Color(themeHex: night ? 0xDCD8CA : 0xF3E5CD)
        let light = dark ? Color(themeHex: night ? 0x88918B : 0x96958A)
                         : Color(themeHex: night ? 0xF8FAF0 : 0xFFFCED)
        let shade = dark ? Color(themeHex: 0x080F13)
                         : Color(themeHex: night ? 0x959991 : 0xAD9981)
        let highContrast = contrast == .increased
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let shoulder = min(6, side * 0.10)
            let shape = RoundedRectangle(cornerRadius: max(cornerRadius, min(17, side * 0.26)),
                                         style: .continuous)
            ZStack {
                // A broad soft shoulder rolls away from the upper-left light.
                // Both shadows are inside the stone, beneath its mineral grain.
                shape.fill(face
                    .shadow(.inner(color: light.opacity(0.48), radius: shoulder * 0.55,
                                   x: shoulder * 0.30, y: shoulder * 0.68))
                    .shadow(.inner(color: shade.opacity(0.50), radius: shoulder * 0.68,
                                   x: -shoulder * 0.25, y: -shoulder * 0.72)))
                if !highContrast {
                    shape.fill(ImagePaint(image: dark ? KoiPondBoard.charcoalGrain : KoiPondBoard.creamGrain,
                                          scale: 0.48))
                        .mask {
                            RadialGradient(stops: [.init(color: .white.opacity(0.38), location: 0),
                                                   .init(color: .white.opacity(0.46), location: 0.65),
                                                   .init(color: .white.opacity(0.82), location: 1)],
                                           center: .center, startRadius: 0,
                                           endRadius: max(1, max(geometry.size.width, geometry.size.height) / 2))
                        }
                }
                shape.strokeBorder(LinearGradient(colors: [light, shade],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing),
                                   lineWidth: highContrast ? 1.5 : max(0.65, 1 / displayScale))
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The pond runs continuously below the glass in Game Detail. An isolated
/// board supplies the water and submerged koi behind its own pane.
struct KoiPondGlassFace: View {
    let tint: Color
    let opaqueColor: Color
    let surfaceIsInScene: Bool
    let cellSize: CGFloat
    let cornerRadius: CGFloat
    let reduceTransparency: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let rim = min(1.25, cellSize * 0.048)
        let shape = RoundedRectangle(cornerRadius: max(cornerRadius, min(4, cellSize * 0.14)),
                                     style: .continuous)
        ZStack {
            if !surfaceIsInScene && !reduceTransparency {
                KoiPondSubmergedView(scheme: scheme)
            }
            shape.fill(reduceTransparency ? opaqueColor : tint)
            // Light catches the cut top and opposite lower lip while the
            // exposed side edges take on the green of the glass.
            shape.strokeBorder(LinearGradient(colors: [
                Color.white.opacity(0.92), Color.white.opacity(0.38),
                Color(themeHex: 0x214F55).opacity(0.75), Color(themeHex: 0xD4FFF8)
            ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: rim)
            shape.inset(by: rim).strokeBorder(LinearGradient(colors: [
                Color(themeHex: 0x163F43).opacity(0.55), .clear, Color.white.opacity(0.48)
            ], startPoint: .top, endPoint: .bottom), lineWidth: rim)
        }
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
