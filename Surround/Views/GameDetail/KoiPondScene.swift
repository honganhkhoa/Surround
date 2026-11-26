import SwiftUI

/// Observe the panel layout once, plus the two content-sized corner controls.
/// Their layout slots can be much wider than the chips actually drawn there.
struct KoiPondGameLayout {
    let bounds: Anchor<CGRect>
    let panels: [CGRect]
    let showsBoard: Bool

    /// SwiftUI places slots from the leading edge. Canvas and the measured
    /// board and control anchors use physical coordinates.
    static func panelFrames(_ panels: [CGRect], in game: CGRect, direction: LayoutDirection) -> [CGRect] {
        panels.map { panel in
            let x = direction == .rightToLeft ? game.maxX - panel.maxX : game.minX + panel.minX
            return CGRect(origin: CGPoint(x: x, y: game.minY + panel.minY), size: panel.size)
        }
    }
}

extension View {
    func koiPondControlReservation(_ visible: Bool) -> some View {
        transformAnchorPreference(key: GameDetailForegroundAnchorsKey.self, value: .bounds) { anchors, bounds in
            if visible { anchors.pondControlReservations.append(bounds) }
        }
    }
}

/// The water and shoreline stay fixed to the window. The glass can move to
/// either pane of a Duo or give up space to chat, so the fish beneath it use
/// the board's measured face rather than a device-specific crop.
struct KoiPondScene: View {
    let scheme: ColorScheme
    let boards: [BoardSceneShadowRegion]
    var gameArea: CGRect?
    /// A group of controls can reserve open water between its painted faces.
    /// These bounds guide placement. The SwiftUI foreground supplies the cover.
    var controlReservations: [CGRect] = []
    var windowInScene: CGRect?
    var layout = KoiPondSwimLayout()
    var boardIsHidden = false
    var swimSession: KoiPondSwimSession?
    var gameID: GameID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { scene in
            let viewport = CGRect(origin: .zero, size: scene.size)
            let shore = KoiPondShore(in: viewport)
            let visible = boards.indices.filter { boards[$0].faceBounds.intersects(viewport) }
            let primary = visible.max {
                boards[$0].faceBounds.intersection(viewport).area < boards[$1].faceBounds.intersection(viewport).area
            }
            let visibleBoard = primary.map { boards[$0] }
            let face = visibleBoard?.faceBounds ?? viewport.insetBy(
                dx: viewport.width * 0.16, dy: viewport.height * 0.19)
            let water = gameArea?.intersection(viewport) ?? viewport
            let detailed = visibleBoard?.isDetailed != false
            let reservations = controlReservations + [shore.bank, shore.rocks].filter { !$0.isEmpty }
            ZStack {
                Canvas { context, _ in
                    guard !viewport.isEmpty else { return }
                    let pond = KoiPondArtwork(context: context, scheme: scheme)
                    pond.water(in: viewport)
                    if swimSession == nil {
                        pond.drawBank(shore)
                        if detailed { pond.submergedPair(in: face) }
                        pond.outerPair(around: face, in: water, window: viewport, excluding: reservations)
                    }
                }
                if let swimSession {
                    // Swim in window coordinates. Zen can move the canvas as well as the board.
                    let window = windowInScene ?? viewport
                    let toWindow = CGAffineTransform(translationX: -window.minX, y: -window.minY)
                    let otherBoards = visible.filter { $0 != primary }.map { boards[$0].faceBounds }
                    let measuredFace = visibleBoard?.faceBounds ?? (boardIsHidden ? face : nil)
                    let routes = swimSession.routes(for: gameID, window: CGRect(origin: .zero, size: window.size),
                                                    water: water.applying(toWindow), board: measuredFace?.applying(toWindow),
                                                    detailed: detailed, avoiding: (reservations + otherBoards).map { $0.applying(toWindow) },
                                                    layout: layout, elapsed: swimSession.elapsed,
                                                    reduceMotion: reduceMotion)
                    KoiPondMovingFish(scheme: scheme, session: swimSession, routes: routes,
                                      windowOrigin: window.origin, reduceMotion: reduceMotion)
                    // The irregular edges and gaps between the rocks occlude fish at the shoreline.
                    Canvas { context, _ in
                        KoiPondArtwork(context: context, scheme: scheme).drawBank(shore)
                    }
                }
            }
        }
        .overlay {
            if #unavailable(iOS 26.0, macCatalyst 26.0) {
                // Earlier toolbars draw their title and icons directly over the scene.
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        LinearGradient(colors: [KoiPond.page, KoiPond.page.opacity(0.88), .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: min(90, geometry.size.height * 0.22))
                        Spacer(minLength: 0)
                        LinearGradient(colors: [.clear, KoiPond.page.opacity(0.88), KoiPond.page],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: min(76, geometry.size.height * 0.20))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The selected task and physical display division persist when Zen moves the foreground.
struct KoiPondSwimLayout: Equatable {
    var panel: GameDetailPanel = .playerInfo
    var divided = false
    var hidesChatBoard = false
}

/// The board and controls guide a new course. Once a koi is swimming, the
/// foreground can move over it without changing its position, size, or stroke.
final class KoiPondSwimSession: ObservableObject {
    private struct Habitat: Equatable {
        let gameID: GameID?
        let window: CGRect
        let layout: KoiPondSwimLayout
    }

    private let seed: UInt64
    private lazy var school = KoiPondSwimSchool(seed: seed)
    private var habitat: Habitat?
    private(set) var planned: [KoiPondSwimRoute] = []
    private var clock = KoiPondSwimClock()
    fileprivate var elapsed: TimeInterval { clock.elapsed(at: ProcessInfo.processInfo.systemUptime) }

    init(seed: UInt64 = .random(in: .min ... .max)) {
        self.seed = seed
    }

    func setRunning(_ running: Bool, at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        clock.setRunning(running, at: uptime)
    }

    func routes(for gameID: GameID?, window: CGRect, water: CGRect, board: CGRect?,
                detailed: Bool, avoiding reservations: [CGRect],
                layout: KoiPondSwimLayout = .init(),
                elapsed: TimeInterval, reduceMotion: Bool = false) -> [KoiPondSwimRoute] {
        let next = Habitat(gameID: gameID, window: window, layout: layout)
        planned.removeAll { !$0.isPresent(at: elapsed) }
        guard next != habitat || planned.isEmpty else { return planned }
        let sameGame = habitat.map { $0.gameID == gameID } ?? false
        // Anchors can briefly disappear during layout. Keep the existing fish
        // until the board and window can guide their next pass.
        guard let board, !board.isEmpty, !window.isEmpty, !water.intersection(window).isEmpty else {
            return sameGame ? planned : []
        }
        if !sameGame {
            let gameSeed: UInt64 = if case let .OGS(number)? = gameID { UInt64(truncatingIfNeeded: number) } else { 0 }
            school = KoiPondSwimSchool(seed: seed ^ gameSeed)
        }
        let fitted = school.routes(in: window, gameArea: water, board: board, detailed: detailed,
                                   avoiding: reservations)
        let previous = sameGame ? planned : []
        planned = school.drawingOrder.compactMap { id in
            let prior = previous.first { $0.id == id }
            guard var route = fitted.first(where: { $0.id == id }) else {
                return prior?.departing(in: window, at: elapsed)
            }
            if let prior {
                route.continueFrom(prior, at: elapsed)
            } else if !sameGame && reduceMotion {
                // A visit opened with motion disabled starts with a populated still pond.
                route.startInOpenWater(at: elapsed)
            } else {
                route.enterFromEdge(at: elapsed)
            }
            return route
        }
        habitat = sameGame || !planned.isEmpty ? next : nil
        return planned
    }
}

struct KoiPondSwimClock {
    private var accumulated: TimeInterval = 0
    private var started: TimeInterval?

    func elapsed(at now: TimeInterval) -> TimeInterval {
        accumulated + (started.map { max(0, now - $0) } ?? 0)
    }

    mutating func setRunning(_ running: Bool, at now: TimeInterval) {
        guard running != (started != nil) else { return }
        accumulated = elapsed(at: now)
        started = running ? now : nil
    }
}

private struct KoiPondMovingFish: View {
    let scheme: ColorScheme
    let session: KoiPondSwimSession
    let routes: [KoiPondSwimRoute]
    let windowOrigin: CGPoint
    let reduceMotion: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let swimming = !reduceMotion && scenePhase == .active && !routes.isEmpty
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !swimming)) { _ in
            let elapsed = session.elapsed
            Canvas { context, _ in
                context.translateBy(x: windowOrigin.x, y: windowOrigin.y)
                if scheme == .dark { context.addFilter(.colorMultiply(Color(themeHex: 0x91A7B0))) }
                for route in routes {
                    KoiPondSwimmer.draw(in: context, route: route, at: elapsed)
                }
            }
        }
        .onAppear { session.setRunning(swimming) }
        .onChange(of: swimming) { _, moving in
            session.setRunning(moving)
        }
        .onDisappear { session.setRunning(false) }
    }
}

/// Both the static artwork and the route planner use the actual footprint of
/// each shore. The packaged textures are loaded once, outside the fish timeline.
private struct KoiPondShore {
    let bank, rocks: CGRect
    private static let bankSize = UIImage(named: "KoiPondBank", in: KoiPond.bundle, compatibleWith: nil)?.size ?? .zero
    private static let rockSize = UIImage(named: "KoiPondRocks", in: KoiPond.bundle, compatibleWith: nil)?.size ?? .zero

    init(in rect: CGRect) {
        let side = min(rect.width, rect.height)
        let width = min(340, side * 0.45), lowerWidth = min(230, side * 0.29)
        let height = width * Self.bankSize.height / max(1, Self.bankSize.width)
        let lowerHeight = lowerWidth * Self.rockSize.height / max(1, Self.rockSize.width)
        bank = CGRect(x: rect.minX, y: rect.minY, width: width, height: height)
        rocks = CGRect(x: rect.minX, y: rect.maxY - lowerHeight, width: lowerWidth, height: lowerHeight)
    }
}

/// Board previews outside the shared scene get the same water and submerged
/// pair. The board still draws its own glass, grid and interactive position.
struct KoiPondSubmergedView: View {
    let scheme: ColorScheme

    var body: some View {
        Canvas { context, size in
            let face = CGRect(origin: .zero, size: size)
            guard !face.isEmpty else { return }
            let pond = KoiPondArtwork(context: context, scheme: scheme)
            pond.water(in: face)
            pond.submergedPair(in: face)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct KoiPondArtwork {
    private let context: GraphicsContext

    init(context: GraphicsContext, scheme: ColorScheme) {
        var light = context
        if scheme == .dark { light.addFilter(.colorMultiply(Color(themeHex: 0x91A7B0))) }
        self.context = light
    }

    private func resolve(_ name: String) -> GraphicsContext.ResolvedImage {
        context.resolve(Image(decorative: name, bundle: KoiPond.bundle))
    }

    func water(in rect: CGRect) {
        context.fill(Path(rect), with: .color(Color(themeHex: 0x2F6873)))
        let side = max(rect.width, rect.height)
        context.draw(resolve("KoiPondWater"), in: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2,
                                                         width: side, height: side))
    }

    func drawBank(_ shore: KoiPondShore) {
        if !shore.bank.isEmpty { context.draw(resolve("KoiPondBank"), in: shore.bank) }
        if !shore.rocks.isEmpty { context.draw(resolve("KoiPondRocks"), in: shore.rocks) }
    }

    func submergedPair(in face: CGRect) {
        let side = min(face.width, face.height)
        fish("KoiPondSanke", in: face, x: 0.29, y: 0.44, length: side * 0.31,
             heading: 216, opacity: 0.66)
        fish("KoiPondGold", in: face, x: 0.67, y: 0.72, length: side * 0.29,
             heading: 203, opacity: 0.76)
    }

    func outerPair(around face: CGRect, in viewport: CGRect, window: CGRect, excluding controls: [CGRect]) {
        guard !viewport.isEmpty else { return }
        let length = min(190, min(viewport.width, viewport.height) * 0.25)
        let first = CGPoint(x: face.maxX - face.width * 0.19, y: face.minY - length * 0.32)
        let second = CGPoint(x: face.minX + face.width * 0.19, y: face.maxY + length * 0.55)
        var openings = [viewport.insetBy(dx: 2, dy: 2)]
        for obstruction in [face] + controls {
            openings = openings.flatMap { $0.subtracting(obstruction.insetBy(dx: -2, dy: -2)) }
        }
        for (name, target, upper) in [("KoiPondKohaku", first, true), ("KoiPondSanke", second, false)] {
            let image = resolve(name)
            guard image.size.height > 0 else { continue }
            let aspect = image.size.width / image.size.height
            let placements = openings.compactMap {
                KoiPondFishPlacement(in: $0, toward: target, length: length, aspect: aspect, upper: upper)
            }
            // Scoring on a small phone can leave a hairline above the board
            // and a usable band below both players. Pick a recognizable fish
            // first, then use distance to choose between comparably useful gaps.
            let longest = placements.map(\.length).max() ?? 0
            let minimum = min(length * 0.45, longest * 0.70)
            var placement = placements.filter { $0.length >= minimum }.max(by: { $0.score < $1.score })
            // In Closed Duo Analyze, the tree, toolbar and board consume the
            // gameplay area. The lower part of the side rail still shows water.
            if (placement?.length ?? 0) < length * 0.55,
               let rail = railWater(beside: viewport, in: window, upper: upper),
               let fallback = KoiPondFishPlacement(in: rail, toward: CGPoint(x: rail.midX, y: rail.midY),
                                                   length: length, aspect: aspect, upper: upper),
               fallback.length > (placement?.length ?? 0) {
                placement = fallback
            }
            guard let best = placement else { continue }
            fish(name, in: best.bounds, x: 0.5, y: 0.5, length: best.length,
                 heading: best.heading, opacity: 0.92)
            openings = openings.flatMap { $0.subtracting(best.bounds.insetBy(dx: -8, dy: -8)) }
        }
    }

    private func railWater(beside content: CGRect, in window: CGRect, upper: Bool) -> CGRect? {
        let left = content.minX - window.minX, right = window.maxX - content.maxX
        let width = max(left, right)
        guard window.height > window.width, width >= max(30, window.width * 0.09),
              width < window.width * 0.30 else { return nil }
        // The status tray and tool buttons occupy the upper rail and the
        // active-games button sits at its foot. Split the water between them.
        return CGRect(x: left > right ? window.minX + 3 : content.maxX + 3,
                      y: window.minY + window.height * (upper ? 0.59 : 0.74),
                      width: width - 6, height: window.height * 0.14)
    }

    private func fish(_ name: String, in rect: CGRect, x: CGFloat, y: CGFloat, length: CGFloat,
                      heading: Double, opacity: Double) {
        let image = resolve(name)
        guard image.size.height > 0 else { return }
        let width = length * image.size.width / image.size.height
        var water = context
        water.opacity = opacity
        water.translateBy(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        water.rotate(by: .degrees(heading))
        water.draw(image, in: CGRect(x: -width / 2, y: -length / 2, width: width, height: length))
    }
}

/// Fit the rotated fish entirely within a clear rectangle. Favor a full-size
/// fish near the board's corner over the distant space beside another pane.
private struct KoiPondFishPlacement {
    let length: CGFloat
    let heading: Double
    let bounds: CGRect
    let score: CGFloat

    init?(in gap: CGRect, toward target: CGPoint, length requested: CGFloat, aspect: CGFloat, upper: Bool) {
        guard !gap.isEmpty, requested > 0 else { return nil }
        let wide = gap.width > gap.height
        if wide {
            let narrowRow = gap.height < requested * 0.6
            heading = upper ? (narrowRow ? -85 : -78) : (narrowRow ? 96 : 111)
        } else {
            heading = upper ? -25 : 158
        }
        let angle = heading * .pi / 180
        let width = abs(cos(angle)) * aspect + abs(sin(angle))
        let height = abs(sin(angle)) * aspect + abs(cos(angle))
        length = min(requested, gap.width / width, gap.height / height)
        let halfWidth = length * width / 2, halfHeight = length * height / 2
        let x = min(max(target.x, gap.minX + halfWidth), gap.maxX - halfWidth)
        let y = min(max(target.y, gap.minY + halfHeight), gap.maxY - halfHeight)
        bounds = CGRect(x: x - halfWidth, y: y - halfHeight, width: halfWidth * 2, height: halfHeight * 2)
        score = length - 0.40 * hypot(x - target.x, y - target.y)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }

    /// The panel and board slots are axis-aligned. Keep the four disjoint
    /// strips around an occluder so the number of candidates stays small.
    func subtracting(_ obstacle: CGRect) -> [CGRect] {
        let overlap = intersection(obstacle)
        guard !overlap.isEmpty else { return [self] }
        return [
            CGRect(x: minX, y: minY, width: width, height: overlap.minY - minY),
            CGRect(x: minX, y: overlap.maxY, width: width, height: maxY - overlap.maxY),
            CGRect(x: minX, y: overlap.minY, width: overlap.minX - minX, height: overlap.height),
            CGRect(x: overlap.maxX, y: overlap.minY, width: maxX - overlap.maxX, height: overlap.height)
        ].filter { $0.width >= 4 && $0.height >= 4 }
    }
}

/// Honey bamboo supports the running clock. Smoked bamboo keeps the same
/// grain, nodes, and silhouette beneath the waiting player.
struct KoiPondBambooLedge: View {
    let compact: Bool
    let running: Bool

    static let height: CGFloat = 6
    static let overlap: CGFloat = 0.35

    @Environment(\.colorSchemeContrast) private var contrast

    private func color(_ honey: UInt32, _ opacity: Double = 1) -> Color {
        if running { return Color(themeHex: honey).opacity(opacity) }
        // Remap each honey pigment to the same smoked finish. Transforming
        // the pigments preserves the antialiasing and needs no filtered layer.
        let red = Double((honey >> 16) & 255)
        let green = Double((honey >> 8) & 255)
        let blue = Double(honey & 255)
        let luminance = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
        let tone = contrast == .increased ? 0.73 * luminance : luminance
        return Color(.sRGB, red: (12 + 103 * tone) / 255, green: (17 + 100 * tone) / 255,
                     blue: (16 + 78 * tone) / 255, opacity: opacity)
    }

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = compact ? 6 : 8
            let diameter: CGFloat = compact ? 4.25 : 5.15
            let cap: CGFloat = compact ? 1.95 : 2.45
            let rod = CGRect(x: inset, y: 0, width: size.width - 2 * inset, height: diameter)
            guard rod.width > 2 * cap else { return }
            let body = Path(roundedRect: rod, cornerSize: CGSize(width: cap / 2, height: diameter / 2))
            func at(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
                CGPoint(x: rod.minX + u * rod.width, y: rod.minY + v * diameter)
            }

            // The shadow extends beneath the cane into the existing clock clearance.
            context.drawLayer { shade in
                shade.addFilter(.blur(radius: compact ? 0.46 : 0.52))
                shade.fill(Path(ellipseIn: CGRect(x: rod.minX + 2, y: rod.maxY - diameter * 0.26,
                    width: rod.width - 4, height: diameter * 0.43)), with: .color(color(0x172221, 0.58)))
            }

            var cane = context
            cane.clip(to: body)
            let light = GraphicsContext.Shading.linearGradient(Gradient(stops: [
                .init(color: color(0x6F4E2F), location: 0),
                .init(color: color(0x997B47), location: 0.20),
                .init(color: color(0xE5BC77), location: 0.43),
                .init(color: color(0xF4D8A0), location: 0.55),
                .init(color: color(0xDEB677), location: 0.70),
                .init(color: color(0xAB814D), location: 0.88),
                .init(color: color(0x7A5937), location: 1)
            ]), startPoint: at(0.5, 0), endPoint: at(0.5, 1))
            cane.fill(body, with: light)

            // Long, interrupted bundles follow the length of a culm. Draw them
            // below the joints so each node interrupts the longitudinal grain.
            for i in 0..<(compact ? 9 : 13) {
                let u = CGFloat((i * 31 + 7) % 101) / 107 - 0.04
                let v = CGFloat((i * 43 + 3) % 83) / 100 + 0.11
                let length = CGFloat(15 + (i * 17) % 42) / 100
                let bend = CGFloat(i % 5 - 2) * 0.012
                var fiber = Path()
                fiber.move(to: at(u, v))
                fiber.addQuadCurve(to: at(u + length, v + bend),
                    control: at(u + length * 0.6, v - bend - 0.015))
                let ink = i % 4 == 0 ? color(0xFFF0B8, 0.54) : color(0x77582F, 0.42)
                cane.stroke(fiber, with: .linearGradient(Gradient(colors: [.clear, ink, ink, .clear]),
                    startPoint: at(u, v), endPoint: at(u + length, v)),
                    style: StrokeStyle(lineWidth: compact ? 0.16 : 0.22, lineCap: .round))
            }

            // Each node flares slightly beyond the smooth culm. Its pale lip
            // and narrow shadow stay visible even in the four-point title ledge.
            for fraction: CGFloat in [0.27, 0.77] {
                let x = rod.minX + rod.width * fraction
                let width: CGFloat = compact ? 2.15 : 2.60
                let node = CGRect(x: x - width / 2, y: rod.minY - 0.26,
                                  width: width, height: diameter + (compact ? 0.67 : 0.82))
                let ridge = Path(roundedRect: node, cornerSize: CGSize(width: 0.70, height: 0.70))
                context.fill(ridge, with: .linearGradient(Gradient(colors: [
                    color(0x856540), color(0xE8CB8D), color(0xF8DFA6), color(0xC09A60), color(0x866439)
                ]), startPoint: CGPoint(x: x, y: node.minY), endPoint: CGPoint(x: x, y: node.maxY)))
                var seam = Path()
                seam.move(to: CGPoint(x: node.maxX - 0.35, y: node.minY + 0.15))
                seam.addQuadCurve(to: CGPoint(x: node.maxX - 0.28, y: node.maxY - 0.34),
                                  control: CGPoint(x: x + 0.16, y: node.midY))
                context.stroke(seam, with: .color(color(0x6E502E, 0.79)),
                               style: StrokeStyle(lineWidth: compact ? 0.48 : 0.58, lineCap: .round))
            }

            // Drier end grain is darker than the silky outer surface.
            for right in [false, true] {
                let end = CGRect(x: right ? rod.maxX - cap : rod.minX, y: rod.minY, width: cap, height: diameter)
                let cut = Path(ellipseIn: end.insetBy(dx: 0, dy: diameter * 0.035))
                cane.fill(cut, with: .linearGradient(Gradient(colors: [color(0xDCC397), color(0x987544),
                    color(0x80613B)]), startPoint: CGPoint(x: end.midX, y: end.minY),
                    endPoint: CGPoint(x: end.midX, y: end.maxY)))
                cane.stroke(cut, with: .color(color(0x63482F, 0.55)), lineWidth: compact ? 0.38 : 0.53)
                for v in [0.35, 0.53, 0.73] {
                    cane.fill(Path(ellipseIn: CGRect(x: end.minX + cap * v, y: end.minY + diameter * v,
                        width: cap * 0.15, height: diameter * 0.07)), with: .color(color(0x725737, 0.72)))
                }
            }

            // Contact shadow at the lip where the opaque stone meets the cane.
            cane.fill(body, with: .linearGradient(Gradient(stops: [
                .init(color: color(0x3F3222, 0.51), location: 0),
                .init(color: .clear, location: 0.32)
            ]), startPoint: at(0.5, 0), endPoint: at(0.5, 1)))
        }
        .frame(height: Self.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
