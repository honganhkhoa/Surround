import SwiftUI

/// The native grid is cut directly into the sandy channel. The sand and shell
/// textures sit beneath the live positions and gameplay marks.
final class ReefLight {
    private init() {}

    static let bundle = Bundle(for: ReefLight.self)
    static let sand = UIImage(named: "ReefLightBoard", in: bundle, compatibleWith: nil)
        .map { BoardTexture(image: $0, mapping: .board) }
    private static let shellStones: StoneImages? = {
        guard let black = UIImage(named: "ReefLightBlackStone", in: bundle, compatibleWith: nil),
              let white = UIImage(named: "ReefLightWhiteStone", in: bundle, compatibleWith: nil) else { return nil }
        return StoneImages(black: [black], white: [white])
    }()

    static let abaloneFace = faceSwatch(from: shellStones?.black.first)
    static let nacreFace = faceSwatch(from: shellStones?.white.first)

    /// Cut inside the stone silhouettes. The upper-right abalone folds and
    /// the nacre growth seam then run continuously across a rectangular plate.
    private static func faceSwatch(from stone: UIImage?) -> Image? {
        guard let image = stone?.cgImage else { return nil }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let interior = CGRect(x: 0.153 * width, y: 0.194 * height, width: 0.675 * width, height: 0.49 * height)
        return image.cropping(to: interior.integral).map { Image(decorative: $0, scale: 1) }
    }

    // Moonlight grades the scene and the sand together. The grid, stones and
    // gameplay marks keep their own contrast independently of the artwork.
    static let nightLight = Color(themeHex: 0x879FAC)

    static func board(for scheme: ColorScheme) -> BoardAppearance {
        let night = scheme == .dark
        let seabed = Color(themeHex: night ? 0x778078 : 0xEDD4B4)
        let ink = Color(themeHex: night ? 0x031316 : 0x332E27)
        let cut = Color(themeHex: night ? 0x192726 : 0x6A5341)
        let pearl = Color(themeHex: 0xF2FFFB)
        let lagoon = Color(themeHex: 0x0C303D)
        let algae = Color(themeHex: 0x0D321D)
        let coral = Color(themeHex: 0x4E1629)
        var texture = sand
        var stones = shellStones
        if night {
            texture?.tint = nightLight
            stones?.tint = Color(themeHex: 0xE5EBF0)
        }
        return BoardAppearance(
            boardColor: seabed, compactBoardColor: seabed, castsBoardShadow: false,
            boardTexture: texture, gridLineScale: 1.6, gridStyle: .ragged, stoneImages: stones,
            stoneLightDirection: .upperRight, imageStoneShadow: .raisedIvoryGlass,
            gridColor: cut, coordinateColor: ink,
            black: StonePalette(
                highlight: Color(themeHex: 0x395C68), shade: Color(themeHex: 0x090F14),
                flat: Color(themeHex: night ? 0x131B20 : 0x1A2128), outline: Color(themeHex: 0x0B1014),
                lastMove: pearl, label: pearl, detailedMarkerCasing: lagoon),
            white: StonePalette(
                highlight: Color(themeHex: 0xFFFAF3), shade: Color(themeHex: 0xA39890),
                flat: Color(themeHex: night ? 0xC6C2BE : 0xD6CDC2), outline: Color(themeHex: 0x2F3135),
                lastMove: lagoon, label: lagoon, detailedMarkerCasing: pearl),
            emptyPointMarker: ink, markOutline: ink, dameColor: Color(themeHex: 0x382710),
            highlightColor: lagoon, highlightCasing: pearl,
            crosshair: .init(valid: algae, invalid: coral, removal: lagoon), crosshairWidth: 1.5,
            removeMark: coral, restoreMark: algae, removalMarkCasing: pearl, removedStoneOutline: ink)
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(Color(themeHex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }

    static let page = adaptive(0xEADCC6, 0x11262F)
    static let panel = adaptive(0xF5F4E9, 0x19313A)
    static let foreground = adaptive(0x15343A, 0xE6F4EF)
    static let detailSecondary = adaptive(0x425959, 0xBBD5D3)
    static let panelBorder = adaptive(0x567576, 0x95B8B8)
    static let deepGlass = adaptive(0x134654, 0x133844)
    static let paleGlass = adaptive(0xD6F0E9, 0xBBDDD7)
    static let blackSurfaceTop = adaptive(0x23525D, 0x1D4350)
    static let blackSurfaceBottom = adaptive(0x0E3443, 0x0D2A38)
    static let whiteSurfaceTop = adaptive(0xC4E4DD, 0xA8CDC9)
    static let whiteSurfaceBottom = adaptive(0xE6F6EF, 0xD0E7E0)
    static let blackForeground = adaptive(0xF4FFFA, 0xECF9F7)
    static let whiteForeground = adaptive(0x17373D, 0x102F34)
    static let blackAccent = adaptive(0xB9F3E7, 0xC4F7ED)
    static let whiteAccent = adaptive(0x23575B, 0x18484E)
    static let blackSecondary = adaptive(0xD0EAE5, 0xC9E3E3)
    static let whiteSecondary = adaptive(0x385758, 0x2B4A4C)
    static let action = adaptive(0x59416F, 0x654C7B)
    static let selection = adaptive(0x315768, 0xA4E2E1)
    static let conditional = adaptive(0x684175, 0xE4BEEB)
    static let chatBubble = adaptive(0xD8E6DD, 0x29434C)
    static let keyline = adaptive(0xFFFFF3, 0x102832)
    static let idle = adaptive(0xBBCCC5, 0x46636A)
    static let turnOutline = adaptive(0x704D8A, 0xDDABEA)
    static let turnGlow = adaptive(0xB484CA, 0xCB93DE)

    /// The white hourglass and turn label sit on a dark cut of the player's shell.
    static func turnBadge(on color: StoneColor) -> Color {
        Color(themeHex: color == .black ? 0x275157 : 0x695562)
    }
}

/// Each plate shares the grain of its playing stone. Its cut-shell inlay
/// follows the player layout, while the light on the face stays upper right.
struct ReefLightShellSurface: View {
    enum Role { case clock, player }

    let color: StoneColor
    let cornerRadius: CGFloat
    let role: Role
    let compact: Bool
    var shellOnLeading = false
    var hairlineOnly = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.layoutDirection) private var direction
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicType

    private var darkShell: Bool { color == .black }
    private var night: Bool { scheme == .dark }
    private var fineDetail: Bool { compact || dynamicType.isAccessibilitySize }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius) }
    private var face: Color {
        darkShell ? Color(themeHex: night ? 0x101923 : 0x16202B)
                  : Color(themeHex: night ? 0xDDDAD9 : 0xEEE9E2)
    }

    private var materialFace: some View {
        let light = darkShell ? Color(themeHex: 0x344957) : Color(themeHex: night ? 0xECE8E5 : 0xFFF8EE)
        let shade = darkShell ? Color(themeHex: 0x0C121B) : Color(themeHex: night ? 0xC9C6CB : 0xD6D0D4)
        return ZStack {
            shape.fill(LinearGradient(colors: [light, face, shade], startPoint: .topTrailing,
                                      endPoint: .bottomLeading))
            if let swatch = darkShell ? ReefLight.abaloneFace : ReefLight.nacreFace {
                swatch.resizable().interpolation(.high)
                    .colorMultiply(night ? Color(themeHex: 0xE5EBF0) : .white)
                    .opacity(darkShell ? 0.76 : 0.55)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private var polishedRim: LinearGradient {
        let colors: [Color] = darkShell
            ? [Color(themeHex: 0xA5D7E1), Color(themeHex: 0x59899B),
               Color(themeHex: 0x5B5975), Color(themeHex: 0x29323C)]
            : [Color(themeHex: 0xFFFCF6), Color(themeHex: 0xEBDBDF),
               Color(themeHex: 0xBBB4C0), Color(themeHex: 0x918D98)]
        return LinearGradient(colors: colors, startPoint: .topTrailing, endPoint: .bottomLeading)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let plain = reduceTransparency || contrast == .increased
            let hairline = hairlineOnly || size.height < 32 || size.width < 65
            let pixel = 1 / max(displayScale, 1)
            ZStack {
                if plain {
                    shape.fill(face)
                    shape.strokeBorder(darkShell ? Color(themeHex: 0xAECACC) : Color(themeHex: 0x576767),
                                       lineWidth: contrast == .increased ? 1.5 : 1)
                } else {
                    materialFace
                    if !hairline {
                        if role == .clock || !darkShell {
                            inlay(foot: false, leading: role == .clock || shellOnLeading, size: size)
                        }
                        if role == .clock || darkShell {
                            inlay(foot: true, leading: role == .player && shellOnLeading, size: size)
                        }
                    }
                    shape.strokeBorder(polishedRim, lineWidth: hairline ? max(pixel, 0.6) : (fineDetail ? 1 : 1.4))
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .clipShape(shape)
        }
        .anchorPreference(key: GameDetailForegroundAnchorsKey.self, value: .bounds) {
            GameDetailForegroundAnchors(shells: [.init(bounds: $0, cornerRadius: cornerRadius)])
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func inlay(foot: Bool, leading: Bool, size: CGSize) -> some View {
        let clock = role == .clock
        // The abalone foot is broad; the pearl foot is a smaller sliver.
        // Limit both axes to keep the centers open on wide clocks and tall chips.
        let fraction: CGSize
        if !clock {
            let playerScale: CGFloat = fineDetail ? 1 : 1.22
            fraction = CGSize(width: (darkShell ? 0.24 : 0.21) * playerScale, height: 0.47 * playerScale)
        } else if foot {
            fraction = darkShell ? CGSize(width: 0.46, height: 0.55) : CGSize(width: 0.29, height: 0.39)
        } else {
            fraction = darkShell ? CGSize(width: 0.42, height: 0.52) : CGSize(width: 0.45, height: 0.57)
        }
        let width = min(fineDetail ? 38 : (clock ? 100 : 58.5), size.width * fraction.width)
        let height = size.height * (fineDetail ? 0.28 : fraction.height)
        let top = !foot
        let left = leading == (direction == .leftToRight)
        let alignment: Alignment = top ? (leading ? .topLeading : .topTrailing)
                                       : (leading ? .bottomLeading : .bottomTrailing)
        let shell = darkShell ? "ReefLightAbalone" : "ReefLightPearl"
        return Image(decorative: shell + (foot ? "Foot" : "Corner"), bundle: ReefLight.bundle)
            .resizable()
            .scaledToFit()
            .scaleEffect(x: left ? -1 : 1, y: top ? 1 : -1)
            .frame(width: width, height: height, alignment: alignment)
            .opacity(night ? 0.66 : 0.78)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

/// The running clock catches a stronger reflection along its upper-right shoulder.
struct ReefLightClockHighlight: View {
    let color: StoneColor
    let cornerRadius: CGFloat
    let isRunning: Bool
    let isWarning: Bool
    var plain = false

    private var shoulder: Color {
        if isWarning { return Color(themeHex: color == .black ? 0xFA9D70 : 0x984424) }
        return Color(themeHex: color == .black ? 0xA899CC : 0x856875)
    }

    private var glint: Color {
        if isWarning { return Color(themeHex: color == .black ? 0xFFDEC0 : 0xFFDFAC) }
        return Color(themeHex: color == .black ? 0xA2EFE9 : 0xFFF9EB)
    }

    var body: some View {
        if isRunning {
            let shape = RoundedRectangle(cornerRadius: cornerRadius)
            Group {
                if plain {
                    shape.strokeBorder(shoulder, lineWidth: 3)
                } else {
                    Canvas { context, size in
                        guard size.width > 0, size.height > 0 else { return }
                        let bounds = CGRect(origin: .zero, size: size)
                        let radius = min(cornerRadius, min(size.width, size.height) / 2)
                        let light = CGPoint(x: bounds.maxX - radius * 0.62, y: radius * 0.30)
                        let reach = min(size.width * 0.66, size.height * 1.08)
                        let width = size.height < 45 ? 3.2 : 4.1
                        // The darker shoulder tapers farther around the bend than the
                        // bright crest. Both stay within the plate, clear of the labels.
                        let shoulderPath = shape.inset(by: width / 2).path(in: bounds)
                        context.stroke(shoulderPath, with: .radialGradient(
                            Gradient(stops: [.init(color: shoulder, location: 0),
                                             .init(color: shoulder, location: 0.28),
                                             .init(color: shoulder.opacity(0.65), location: 0.63),
                                             .init(color: shoulder.opacity(0), location: 1)]),
                            center: light, startRadius: 0, endRadius: reach), lineWidth: width)
                        let lip = shape.inset(by: 1.15).path(in: bounds)
                        context.stroke(lip, with: .radialGradient(
                            Gradient(stops: [.init(color: glint, location: 0),
                                             .init(color: glint, location: 0.23),
                                             .init(color: glint.opacity(0), location: 1)]),
                            center: light, startRadius: 0, endRadius: reach * 0.76), lineWidth: 1.4)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// A single overhead reef spans the window, including split and folded layouts.
/// Bias the crop toward the sea fan when the window is taller or wider than the art.
struct ReefLightScene: View {
    let scheme: ColorScheme
    let boards: [BoardSceneShadowRegion]
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let landscape = size.width > size.height
            let ratio: CGFloat = landscape ? 1.5 : 2 / 3
            let width = max(size.width, size.height * ratio)
            let height = width / ratio
            ZStack {
                ReefLight.page
                Image(decorative: landscape ? "ReefLightSceneLandscape" : "ReefLightScenePortrait",
                      bundle: ReefLight.bundle)
                    .resizable()
                    .frame(width: width, height: height)
                    .colorMultiply(scheme == .dark ? ReefLight.nightLight : .white)
                    .position(x: width / 2 - (width - size.width) * 0.26,
                              y: height / 2 - (height - size.height) * 0.30)
                // Game Detail clips each interactive board to its layout slot. Paint
                // the sandy clearing here so it continues past the outer intersections.
                ForEach(Array(boards.enumerated()), id: \.offset) { _, board in
                    if board.isDetailed && !board.bounds.isEmpty {
                        sandField(around: board)
                    }
                }
                // Accessible opaque panels keep their original contrast. Project
                // the still water onto the exposed seabed behind them instead.
                if reduceTransparency || contrast == .increased {
                    ReefLightWaterSurface(scheme: scheme, phase: 0)
                }
                if #unavailable(iOS 26.0, macCatalyst 26.0) {
                    // Older toolbar symbols sit directly over the reef.
                    VStack(spacing: 0) {
                        LinearGradient(colors: [ReefLight.page, ReefLight.page.opacity(0.9), .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: min(96, size.height * 0.23))
                        Spacer(minLength: 0)
                        LinearGradient(colors: [.clear, ReefLight.page.opacity(0.9), ReefLight.page],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: min(84, size.height * 0.2))
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func sandField(around board: BoardSceneShadowRegion) -> some View {
        let face = board.faceBounds
        let shore = min(100, max(26, board.cellSize * 2.2))
        let field = face.insetBy(dx: -shore, dy: -shore)
        return Color(themeHex: 0xEDD4B4)
            .overlay {
                if let sand = ReefLight.sand {
                    Image(uiImage: sand.image).resizable().scaledToFill()
                }
            }
            .colorMultiply(scheme == .dark ? ReefLight.nightLight : .white)
            .frame(width: field.width, height: field.height)
            .clipped()
            .mask {
                // Blur the static silhouette only. The inner grid is quiet sand,
                // with the reef and caustics showing through its outer banks.
                RoundedRectangle(cornerRadius: shore * 1.2)
                    .inset(by: shore * 0.6)
                    .fill(.white)
                    .blur(radius: shore * 0.37)
            }
            .opacity(0.96)
            .position(x: face.midX, y: face.midY)
    }
}

/// Only the light field ticks. Game layout, clocks and board state are outside this timeline.
struct ReefLightWater: View {
    let scheme: ColorScheme
    let boards: [BoardSceneShadowRegion]
    let animates: Bool
    var shells: [Path] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if !reduceTransparency && contrast != .increased {
            if shells.isEmpty {
                surface
            } else {
                // The mask follows layout, outside the 12 Hz timeline. A trace
                // of the common water light remains on each matte shell face.
                surface.mask {
                    Canvas { context, size in
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                        var plates = Path()
                        for shell in shells { plates.addPath(shell) }
                        context.blendMode = .destinationOut
                        context.fill(plates, with: .color(.white.opacity(0.85)))
                    }
                }
            }
        }
    }

    @ViewBuilder private var surface: some View {
        if animates && !reduceMotion && scenePhase == .active {
            TimelineView(.animation(minimumInterval: 1.0 / 12)) { tick in
                let seconds = tick.date.timeIntervalSinceReferenceDate
                ReefLightWaterSurface(scheme: scheme, phase: seconds.truncatingRemainder(dividingBy: 12) / 12,
                                      boards: boards)
            }
        } else {
            ReefLightWaterSurface(scheme: scheme, phase: 0, boards: boards)
        }
    }
}

/// A single projection crosses sand, glass and panels. Cropping the atlas once
/// gives the sampler separate tile edges for each frame of the wave cycle.
struct ReefLightWaterSurface: View {
    let scheme: ColorScheme
    let phase: Double
    var boards: [BoardSceneShadowRegion] = []

    private static let caustics: [Image] = {
        guard let atlas = UIImage(named: "ReefLightCaustics", in: ReefLight.bundle, compatibleWith: nil)?.cgImage
        else { return [] }
        let side = atlas.width / 4
        return (0..<16).compactMap { i in
            let rect = CGRect(x: i % 4 * side, y: i / 4 * side, width: side, height: side)
            return atlas.cropping(to: rect).map { Image(decorative: $0, scale: 1) }
        }
    }()

    var body: some View {
        Canvas { context, size in
            let field = Path(CGRect(origin: .zero, size: size))
            for board in boards where !board.isDetailed {
                let slab = RoundedRectangle(cornerRadius: board.cornerRadius).path(in: board.bounds)
                context.clip(to: slab, options: .inverse)
            }
            let night = scheme == .dark
            let deep = Color(themeHex: night ? 0x00566F : 0x167D92)
            let shallow = Color(themeHex: 0x5CD7D0)
            // Water absorbs the sandy warmth with depth. Oblique shafts enter
            // from the same upper-right light as the glass stone highlights.
            context.fill(field, with: .linearGradient(Gradient(colors: [shallow.opacity(0.04), deep.opacity(0.09)]),
                startPoint: CGPoint(x: size.width * 0.9, y: 0), endPoint: CGPoint(x: size.width * 0.12, y: size.height)))
            let light = Color(themeHex: night ? 0x9DE5F2 : 0xCEFFF5)
            let shafts = Gradient(stops: [
                .init(color: .clear, location: 0.12), .init(color: light.opacity(0.04), location: 0.21),
                .init(color: .clear, location: 0.27), .init(color: .clear, location: 0.48),
                .init(color: light.opacity(0.05), location: 0.55), .init(color: .clear, location: 0.64),
                .init(color: light.opacity(0.03), location: 0.78), .init(color: .clear, location: 0.84)
            ])
            let span = min(size.width, size.height * 1.3)
            context.fill(field, with: .linearGradient(shafts, startPoint: .zero,
                         endPoint: CGPoint(x: span, y: span * 0.48)))

            let frames = Self.caustics
            guard !frames.isEmpty else { return }
            let cycle = phase - floor(phase)
            let index = cycle * Double(frames.count)
            let first = Int(index)
            let mix = index - Double(first)
            // A passing swell carries the light a few points across the seabed.
            // Both blended frames share the offset, which returns to zero at the seam.
            let angle = 2 * Double.pi * cycle
            let drift = CGPoint(x: 4 * sin(angle), y: 1.5 * (1 - cos(angle)))
            // Keep wavelets at a physical scale across rotations and split views.
            // Each frame is 320 pixels wide and covers 272 points of seabed.
            context.addFilter(.colorMultiply(light))
            for (frame, weight) in [(first, 1 - mix), ((first + 1) % frames.count, mix)] where weight > 0 {
                context.opacity = (night ? 0.13 : 0.21) * weight
                context.fill(field, with: .tiledImage(frames[frame], origin: drift, scale: 0.85))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
