//
//  BoardView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/18/20.
//

import SwiftUI
import WidgetKit

func stoneSize(geometry: GeometryProxy, boardSize: Int, displayScale: CGFloat) -> CGFloat {
    let size = min(geometry.size.width, geometry.size.height)
    return CGFloat(
        floor(size / CGFloat(boardSize) * displayScale) / displayScale
    )
}

enum StoneRemovalOption: Int {
    case toggleGroup
    case toggleSinglePoint
}

#if DEBUG
/// Draw the production interaction layers deterministically in the audit.
/// Gestures and game state continue to use their normal bindings.
struct BoardMarkerAuditState {
    var highlightedRow = -1
    var highlightedColumn = -1
    var hoverValid: Bool? = nil
    var removalPoints = Set<[Int]>()
}

private struct BoardMarkerAuditStateKey: EnvironmentKey {
    static let defaultValue: BoardMarkerAuditState? = nil
}

extension EnvironmentValues {
    var boardMarkerAuditState: BoardMarkerAuditState? {
        get { self[BoardMarkerAuditStateKey.self] }
        set { self[BoardMarkerAuditStateKey.self] = newValue }
    }
}
#endif

/// Rebuild the batched geometry only when the grid itself changes, rather
/// than on every move, clock tick or crosshair update in the parent board.
/// The Canvas rasterizes it in the app: as a filled shape, its thousands of
/// edge points made the render server redraw it on every frame of a resize.
private struct RaggedGobanGrid: View, Equatable {
    var geometry: RaggedGridGeometry
    var color: Color

    var body: some View {
        Canvas { context, _ in
            context.fill(geometry.path, with: .color(color))
        }
    }
}

private struct StitchedGobanGrid: View, Equatable {
    var geometry: StitchedGridGeometry
    var color: Color

    var body: some View {
        Canvas { context, _ in
            context.stroke(geometry.path, with: .color(color),
                           style: StrokeStyle(lineWidth: min(1.15, geometry.cellSize * 0.028),
                                              lineCap: .round))
        }
    }
}

/// Transparent relief over the wool image: one Canvas, without a separate
/// view, blur or offscreen shadow for every square. Geometry is independent
/// of the game state, so clocks and moves do not rebuild the felt surface.
private struct PaddedFeltGrid: View, Equatable {
    var geometry: FeltGridGeometry
    var shade: Color

    var body: some View {
        Canvas { context, _ in
            let cells = geometry.cellRects
            let radius = geometry.cellCornerRadius
            var edges = Path()
            for (index, rect) in cells.enumerated() {
                let cell = Path(roundedRect: rect, cornerRadius: radius)
                edges.addPath(cell)
                let loft = cellLoft(at: index)
                context.fill(cell, with: .linearGradient(Gradient(stops: [
                    .init(color: .white.opacity(0.19 * loft), location: 0),
                    .init(color: .white.opacity(0.045 * loft), location: 0.22),
                    .init(color: .clear, location: 0.48),
                    .init(color: shade.opacity(0.08 * loft), location: 0.74),
                    .init(color: shade.opacity(0.34 * loft), location: 1)
                ]), startPoint: CGPoint(x: rect.midX, y: rect.minY),
                   endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                context.fill(cell, with: .linearGradient(Gradient(stops: [
                    .init(color: .white.opacity(0.11), location: 0),
                    .init(color: .clear, location: 0.28),
                    .init(color: .clear, location: 0.65),
                    .init(color: shade.opacity(0.22), location: 1)
                ]), startPoint: CGPoint(x: rect.minX, y: rect.midY),
                   endPoint: CGPoint(x: rect.maxX, y: rect.midY)))
            }
            // Batched, translucent edges sink into the seam; the rounded
            // corners leave a small dark recess at each playing intersection.
            context.stroke(edges, with: .color(shade.opacity(0.16)),
                           lineWidth: geometry.cellSize * 0.035)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A small, stable difference in loft keeps the wool handmade. Typed
    /// steps outside the Canvas closure keep Xcode 26.6 able to type-check it.
    private func cellLoft(at index: Int) -> Double {
        let row: Int = index / max(1, geometry.width - 1)
        let variation: Int = (index * 13 + row * 7) % 5
        return 0.92 + Double(variation) * 0.04
    }
}

/// Soft textile binding sits inside the existing board slot, including its
/// coordinate gutter. It never changes the playable surface's dimensions.
private struct FeltBoardRim: View, Equatable {
    var cellSize: CGFloat
    var cornerRadius: CGFloat
    var shade: Color

    var body: some View {
        Canvas { context, size in
            let width = min(7, cellSize * 0.16)
            let bounds = CGRect(origin: .zero, size: size)
            let outer = Path(roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2),
                             cornerRadius: max(0, cornerRadius - width / 2))
            context.stroke(outer, with: .linearGradient(Gradient(colors: [
                .white.opacity(0.25), .white.opacity(0.04), shade.opacity(0.42)
            ]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)), lineWidth: width)
            let inner = Path(roundedRect: bounds.insetBy(dx: width, dy: width),
                             cornerRadius: max(0, cornerRadius - width))
            context.stroke(inner, with: .color(shade.opacity(0.12)), lineWidth: width * 0.45)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct Goban: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.boardAppearance) private var appearance
    #if DEBUG
    @Environment(\.boardMarkerAuditState) private var markerAuditState
    #endif
    var geometry: GeometryProxy
    var width: Int
    var height: Int
    var showsCoordinates = false
    var playable = false
    var stoneRemovable = false
    @Binding var highlightedRow: Int
    @Binding var highlightedColumn: Int
    var hoveredPoint: Binding<[Int]?> = .constant(nil)
    var isHoveredPointValid: Bool? = nil
    var selectPoint: ([Int]?) -> Bool = { _ in false }
    #if MAIN_APP
    @State var selectionFeedbackGenerator: UISelectionFeedbackGenerator? = nil
    #endif

    @Setting(.hapticsFeedback) var hapticsFeedbback: Bool
    
    var body: some View {
        let size = stoneSize(geometry: geometry, boardSize: max(width, height), displayScale: displayScale)
        let padded = appearance.gridStyle.usesPaddedCells(at: size)
        let lineColor = appearance.gridColor.opacity(padded ? 0.6 : 1)
        #if DEBUG
        let drawnRow = markerAuditState?.highlightedRow ?? highlightedRow
        let drawnColumn = markerAuditState?.highlightedColumn ?? highlightedColumn
        let drawnHoverValid = markerAuditState.map { $0.hoverValid } ?? isHoveredPointValid
        #else
        let drawnRow = highlightedRow
        let drawnColumn = highlightedColumn
        let drawnHoverValid = isHoveredPointValid
        #endif
        var starPoints = [[CGFloat]]()
        if size > 10 {
            if height == 19 && width == 19 {
                starPoints = [3, 9, 15].flatMap({ x in [3, 9, 15].map({ y in [x, y] })})
            } else if height == 13 && width == 13 {
                starPoints = [[3, 3], [3, 9], [6, 6], [9, 3], [9, 9]]
            } else if height == 9 && width == 9 {
                starPoints = [[2, 2], [2, 6], [4, 4], [6, 2], [6, 6]]
            }
        }
        let highlightColor = stoneRemovable
            ? appearance.crosshair.removal
            : (drawnHoverValid ?? false) ? appearance.crosshair.valid : appearance.crosshair.invalid
        let coordinates = "ABCDEFGHJKLMNOPQRSTUVWXYZ".map { String($0) }
        return Group {
            ZStack {
                if showsCoordinates {
                    ForEach(0..<width, id: \.self) { col in
                        Text(verbatim: "\(coordinates[col])").font(.system(size: size > 30 ? size / 1.5 : size))
                            .minimumScaleFactor(0.2)
                            .foregroundColor(appearance.coordinateColor)
                            .frame(width: size, height: size)
                            .position(x: (CGFloat(col) + 0.5) * size, y: -0.5 * size)
                    }
                    ForEach(0..<height, id: \.self) { row in
                        Text(verbatim: "\(height - row)").font(.system(size: size > 30 ? size / 1.5 : size))
                            .minimumScaleFactor(0.2)
                            .foregroundColor(appearance.coordinateColor)
                            .frame(width: size, height: size)
                            .position(x: -0.5 * size, y: (CGFloat(row) + 0.5) * size)
                    }
                }
                // Keep detail layers mounted across the threshold. A board
                // resizing through 14 pt switches pigment without a cross-fade.
                if appearance.gridStyle == .stitched {
                    PaddedFeltGrid(geometry: FeltGridGeometry(width: width, height: height, cellSize: size),
                                   shade: appearance.gridColor)
                        .equatable()
                        .opacity(padded ? 1 : 0)
                        .animation(nil, value: padded)
                }
                if appearance.gridStyle == .ragged {
                    RaggedGobanGrid(
                        geometry: RaggedGridGeometry(width: width, height: height,
                                                     cellSize: size, lineScale: appearance.gridLineScale),
                        color: appearance.gridColor
                    ).equatable()
                        .opacity(appearance.gridStyle.usesRaggedEdges(at: size) ? 1 : 0)
                        .animation(nil, value: appearance.gridStyle.usesRaggedEdges(at: size))
                }
                Group {
                    Path { path in
                        for i in 1..<height-1 {
                            path.move(to: CGPoint(x: size / 2, y: (CGFloat(i) + 0.5) * size))
                            path.addLine(to: CGPoint(x: (CGFloat(width) - 0.5) * size, y:(CGFloat(i) + 0.5) * size))
                        }
                        for i in 1..<width-1 {
                            path.move(to: CGPoint(x: (CGFloat(i) + 0.5) * size, y: size / 2))
                            path.addLine(to: CGPoint(x: (CGFloat(i) + 0.5) * size, y: (CGFloat(height) - 0.5) * size))
                        }
                    }
                    .stroke(lineColor, lineWidth: size < 10 ? 1 / displayScale : 0.5 * appearance.gridLineScale)
                    Path { path in
                        path.move(to: CGPoint(x: size / 2, y: size / 2))
                        path.addLine(to: CGPoint(x: (CGFloat(width) - 0.5) * size, y: size / 2))
                        path.addLine(to: CGPoint(x: (CGFloat(width) - 0.5) * size, y: (CGFloat(height) - 0.5) * size))
                        path.addLine(to: CGPoint(x: size / 2, y: (CGFloat(height) - 0.5) * size))
                        path.closeSubpath()
                    }.stroke(lineColor, lineWidth: size < 10 ? 0.5 : appearance.gridLineScale)
                }
                .opacity(appearance.gridStyle.usesRaggedEdges(at: size) ? 0 : 1)
                .animation(nil, value: appearance.gridStyle.usesRaggedEdges(at: size))
                .animation(nil, value: padded)
                if appearance.gridStyle == .stitched {
                    StitchedGobanGrid(
                        geometry: StitchedGridGeometry(width: width, height: height, cellSize: size),
                        color: appearance.gridStitchColor
                    ).equatable()
                        .opacity(appearance.gridStyle.usesStitches(at: size) ? 1 : 0)
                        .animation(nil, value: appearance.gridStyle.usesStitches(at: size))
                        .allowsHitTesting(false)
                }
                if starPoints.count > 0 {
                    Path { path in
                        for starPoint in starPoints {
                            let starPointSize: CGFloat = size > 20 ? 6.0 : 4.0
                            let starPointRect = CGRect(x: (starPoint[0] + 0.5) * size - starPointSize / 2, y: (starPoint[1] + 0.5) * size - starPointSize / 2, width: starPointSize, height: starPointSize)
                            path.addEllipse(in: starPointRect)
                        }
                    }.fill(appearance.gridColor)
                }
                if drawnColumn >= 0 && drawnColumn < width && drawnRow >= 0 && drawnRow < height {
                    Path { path in
                        path.move(to: CGPoint(x: size / 2, y: (CGFloat(drawnRow) + 0.5) * size))
                        path.addLine(to: CGPoint(x: (CGFloat(width) - 0.5) * size, y:(CGFloat(drawnRow) + 0.5) * size))

                        path.move(to: CGPoint(x: (CGFloat(drawnColumn) + 0.5) * size, y: size / 2))
                        path.addLine(to: CGPoint(x: (CGFloat(drawnColumn) + 0.5) * size, y: (CGFloat(height) - 0.5) * size))
                    }
                    .stroke(highlightColor, lineWidth: appearance.crosshairWidth)
                }
            }
        }
        .frame(width: size * CGFloat(width), height: size * CGFloat(height))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged({ value in
                    #if MAIN_APP
                    if self.selectionFeedbackGenerator == nil && self.hapticsFeedbback {
                        self.selectionFeedbackGenerator = SystemPlatformServices.shared
                            .makeSelectionFeedbackGenerator()
                    }
                    #endif
                    _ = selectPoint(nil)
                    highlightedRow = Int((value.location.y / size - 0.5).rounded())
                    highlightedColumn = Int((value.location.x / size - 0.5).rounded())
                    if highlightedColumn >= 0 && highlightedColumn < width && highlightedRow >= 0 && highlightedRow < height {
                        if hoveredPoint.wrappedValue != [highlightedRow, highlightedColumn] {
                            hoveredPoint.wrappedValue = [highlightedRow, highlightedColumn]
                            #if MAIN_APP
                            self.selectionFeedbackGenerator?.selectionChanged()
                            #endif
                        }
                    } else {
                        hoveredPoint.wrappedValue = nil
                    }
                })
                .onEnded { value in
                    let row = Int((value.location.y / size - 0.5).rounded())
                    let column = Int((value.location.x / size - 0.5).rounded())
                    let point = row >= 0 && row < height && column >= 0 && column < width
                        ? [row, column] : nil
                    // A quick tap can end before hover validation is rendered.
                    // Commit the release point directly instead of consulting that state.
                    let didSelectPoint = selectPoint(point)
                    highlightedRow = -1
                    highlightedColumn = -1
                    hoveredPoint.wrappedValue = nil
                    #if MAIN_APP
                    if didSelectPoint && self.hapticsFeedbback {
                        SystemPlatformServices.shared.playNotificationFeedback(.success)
                    }
                    self.selectionFeedbackGenerator = nil
                    #endif
                }
        )
    }
}

struct VariationNumberings: View {
    @Environment(\.boardAppearance) private var appearance
    var variation: Variation
    var cellSize: CGFloat
    var policy = BoardPointIndicatorPolicy(markups: [:])
    
    var body: some View {
        let labels = variation.nonDuplicatingMoveCoordinatesByLabel.keys.sorted()
        let marker = StoneMarkerGeometry(cellSize: cellSize)
        
        return ZStack {
            ForEach(labels, id: \.self) { label -> AnyView in
                if let coordinate = variation.nonDuplicatingMoveCoordinatesByLabel[label],
                   policy.showsVariationNumber(at: BoardPoint(row: coordinate[0], column: coordinate[1])) {
                    let stoneColor: StoneColor? = {
                        if case .hasStone(let color) = variation.position[coordinate] { return color }
                        return nil
                    }()
                    let detailed = usesDetailedStoneRendering(at: cellSize)
                    return AnyView(
                        StoneMarkerText(text: "\(label)", fontSize: cellSize * 0.62,
                                        foreground: stoneColor.map { appearance.stones($0).label } ?? appearance.emptyPointMarker,
                                        casing: detailed ? appearance.textCasing(on: stoneColor) : nil,
                                        casingWidth: marker.casingWidth)
                            .equatable()
                            .frame(width: marker.stoneDiameter * 0.78, height: marker.stoneDiameter * 0.78)
                            .background {
                                if stoneColor == nil {
                                    Circle().fill(appearance.surfaceColor(detailed: detailed))
                                        .frame(width: marker.stoneDiameter * 0.88, height: marker.stoneDiameter * 0.88)
                                }
                            }
                            .position(
                                x: (CGFloat(coordinate[1]) + 0.5) * cellSize,
                                y: (CGFloat(coordinate[0]) + 0.5) * cellSize
                            )
                    )
                } else {
                    return AnyView(EmptyView())
                }
            }
        }
    }
}

/// The board's reflected light, beneath the grid and stones: a gradient sheen
/// and a tiled image of dust and glints, drawn once, that fades away from the
/// light. Views rather than a Canvas, so a resize redraws nothing; the specks
/// keep their density per area and stay put like the texture.
private struct BoardReflectionView: View {
    let reflection: BoardReflection
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let tile = BoardReflectionTile.image(dustDensity: reflection.dustDensity,
                                             glintDensity: reflection.glintDensity, scale: displayScale)
        let light = UnitPoint(x: -0.12, y: -0.12)
        GeometryReader { geometry in
            let reach = reflection.reach * max(geometry.size.width, geometry.size.height)
            ZStack {
                Rectangle().fill(RadialGradient(stops: [
                    .init(color: reflection.color.opacity(reflection.corner), location: 0),
                    .init(color: reflection.color.opacity(reflection.middle), location: 0.45),
                    .init(color: reflection.color.opacity(reflection.edge), location: 1)
                ], center: light, startRadius: 0, endRadius: reach))
                // Specks are brighter where the sheen is: full near the
                // light, fading to 35% two thirds of the way out.
                Image(uiImage: tile)
                    .resizable(resizingMode: .tile)
                    .mask(RadialGradient(stops: [.init(color: .white, location: 0),
                                                 .init(color: .white.opacity(0.35), location: 0.65)],
                                         center: light, startRadius: 0, endRadius: reach))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The reflection's dust and glints on one seamless tile, rendered once per
/// density and display scale. Its side is not a multiple of the texture's,
/// so the two repeats do not line up.
@MainActor
private enum BoardReflectionTile {
    static let side: CGFloat = 384

    private struct Key: Hashable {
        let dust: CGFloat
        let glints: CGFloat
        let scale: CGFloat
    }

    private static var cache: [Key: UIImage] = [:]

    static func image(dustDensity: CGFloat, glintDensity: CGFloat, scale: CGFloat) -> UIImage {
        let key = Key(dust: dustDensity, glints: glintDensity, scale: scale)
        if let image = cache[key] { return image }
        let image = render(dustDensity: dustDensity, glintDensity: glintDensity, scale: scale)
        cache[key] = image
        return image
    }

    private static func render(dustDensity: CGFloat, glintDensity: CGFloat, scale: CGFloat) -> UIImage {
        var state: UInt64 = 0x57A2_2026
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(state >> 33) / CGFloat(1 << 31)
        }
        let area = side * side / 10_000
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { renderer in
            let context = renderer.cgContext
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            // Each speck is drawn again across any edge it overlaps, so the
            // tile repeats without seams.
            func wrapped(_ center: CGPoint, reach: CGFloat, draw: (CGPoint) -> Void) {
                for dx in [-side, 0, side] where center.x + dx + reach > 0 && center.x + dx - reach < side {
                    for dy in [-side, 0, side] where center.y + dy + reach > 0 && center.y + dy - reach < side {
                        draw(CGPoint(x: center.x + dx, y: center.y + dy))
                    }
                }
            }
            for _ in 0..<Int(area * dustDensity) {
                let center = CGPoint(x: next() * side, y: next() * side)
                let radius = 0.25 + 0.35 * pow(next(), 3)
                let opacity = 0.12 + 0.3 * next()
                context.setFillColor(CGColor(srgbRed: 0.86, green: 0.89, blue: 1, alpha: opacity))
                wrapped(center, reach: radius) { point in
                    context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                                   width: radius * 2, height: radius * 2))
                }
            }
            for _ in 0..<Int(area * glintDensity) {
                let center = CGPoint(x: next() * side, y: next() * side)
                let radius = 0.5 + 0.5 * pow(next(), 3)
                let strength = 0.55 + 0.35 * next()
                let halo = radius * 5
                let gradient = CGGradient(colorsSpace: colorSpace, colors: [
                    CGColor(srgbRed: 0.91, green: 0.93, blue: 1, alpha: 0.3 * strength),
                    CGColor(srgbRed: 0.91, green: 0.93, blue: 1, alpha: 0)] as CFArray, locations: [0, 1])!
                wrapped(center, reach: halo) { point in
                    context.drawRadialGradient(gradient, startCenter: point, startRadius: 0,
                                               endCenter: point, endRadius: halo, options: [])
                    context.setFillColor(CGColor(srgbRed: 0.96, green: 0.96, blue: 1, alpha: strength))
                    context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                                   width: radius * 2, height: radius * 2))
                }
            }
        }
    }
}

/// The board texture as images rather than an ImagePaint fill, so an
/// animated resize does not redraw the layer on every frame: a tile repeated
/// at its tile size, or one composition covering the board from its top-left
/// corner at `paintScale(in:)`, as the paint placed it.
private struct BoardTextureImage: View {
    let texture: BoardTexture
    /// The margin's lift: `brightness(0.1)` then `contrast(1.25)`.
    let lifted: Bool
    let boardSize: CGSize

    var body: some View {
        let image = BoardTextureImages.image(for: texture, lifted: lifted)
        Group {
            switch texture.mapping {
            case .tiled:
                Image(uiImage: image).resizable(resizingMode: .tile)
            case .board:
                let scale = texture.paintScale(in: boardSize)
                Color.clear
                    .overlay(alignment: .topLeading) {
                        Image(uiImage: image).resizable()
                            .frame(width: texture.image.size.width * scale,
                                   height: texture.image.size.height * scale)
                    }
                    .clipped()
            }
        }
        .colorMultiply(texture.tint)
    }
}

/// Texture images prepared once: a tile given its point size, and copies
/// with the margin's lift applied, which is 1.25× each channel, rather than
/// filters computed on every frame.
@MainActor
private enum BoardTextureImages {
    private struct Key: Hashable {
        let source: ObjectIdentifier
        let lifted: Bool
        let tileSize: CGFloat?
    }

    private static var cache: [Key: (source: UIImage, image: UIImage)] = [:]

    static func image(for texture: BoardTexture, lifted: Bool) -> UIImage {
        let tileSize = texture.mapping == .tiled ? texture.tileSize : nil
        let key = Key(source: ObjectIdentifier(texture.image), lifted: lifted, tileSize: tileSize)
        if let entry = cache[key], entry.source === texture.image { return entry.image }
        guard let source = texture.image.cgImage else { return texture.image }
        let pixels = lifted ? liftedCopy(of: source) ?? source : source
        let scale = tileSize.map { CGFloat(source.width) / max(1, $0) } ?? texture.image.scale
        let image = UIImage(cgImage: pixels, scale: scale, orientation: .up)
        cache[key] = (texture.image, image)
        return image
    }

    private static func liftedCopy(of source: CGImage) -> CGImage? {
        let width = source.width, height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            for index in stride(from: 0, to: buffer.count, by: 4) {
                let alpha = buffer[index + 3]
                for channel in 0..<3 {
                    buffer[index + channel] = UInt8(min(Int(alpha), Int(buffer[index + channel]) * 5 / 4))
                }
            }
            return context.makeImage()
        }
    }
}

/// The top-left quarter of a rounded bevel, rotated for the other corners.
private struct BoardBorderCorner: Shape {
    let width: CGFloat
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        guard radius > 0, width > 0 else { return Path() }
        let center = CGPoint(x: radius, y: radius)
        var path = Path()
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: side, y: 0))
        path.addLine(to: CGPoint(x: side, y: width))
        path.addLine(to: CGPoint(x: radius, y: width))
        path.addArc(center: center, radius: max(0, radius - width),
                    startAngle: .degrees(270), endAngle: .degrees(180), clockwise: true)
        path.addLine(to: CGPoint(x: width, y: side))
        path.addLine(to: CGPoint(x: 0, y: side))
        path.closeSubpath()
        return path
    }
}

/// Narrow strips and corner patches keep the bevel's rendering work near
/// the edges, instead of redrawing a board-sized gradient stroke on resize.
private struct BoardBorder: View {
    let start: Color
    let middle: Color
    let end: Color
    let width: CGFloat
    var cornerRadius: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // Give each patch a whole-pixel frame, with short straight arms from
        // its true radius to the strips. Fractional frames can round their
        // joins differently; overlapping them would double translucent colors.
        let patchSide = ceil(cornerRadius * displayScale) / displayScale
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [start, middle], startPoint: .leading, endPoint: .trailing)
                    .frame(height: width)
                Spacer(minLength: 0)
                LinearGradient(colors: [middle, end], startPoint: .leading, endPoint: .trailing)
                    .frame(height: width)
            }
            .padding(.horizontal, patchSide)
            // Square bevels still stop at the top and bottom strips.
            HStack(spacing: 0) {
                LinearGradient(colors: [start, middle], startPoint: .top, endPoint: .bottom)
                    .frame(width: width)
                Spacer(minLength: 0)
                LinearGradient(colors: [middle, end], startPoint: .top, endPoint: .bottom)
                    .frame(width: width)
            }
            .padding(.vertical, max(width, patchSide))
            // Small quarter rings join the strips without rasterizing a
            // board-sized gradient stroke each time the board resizes.
            BoardBorderCorner(width: width, radius: cornerRadius).fill(start)
                .frame(width: patchSide, height: patchSide)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            BoardBorderCorner(width: width, radius: cornerRadius).fill(middle)
                .frame(width: patchSide, height: patchSide).rotationEffect(.degrees(90))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            BoardBorderCorner(width: width, radius: cornerRadius).fill(middle)
                .frame(width: patchSide, height: patchSide).rotationEffect(.degrees(-90))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            BoardBorderCorner(width: width, radius: cornerRadius).fill(end)
                .frame(width: patchSide, height: patchSide).rotationEffect(.degrees(180))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .allowsHitTesting(false)
    }
}

/// A shallow material face below the board, contained in its layout slot.
/// Only this simple silhouette casts a shadow; the stones are never flattened
/// into an offscreen image to obtain a board-shaped shadow.
private struct BoardDepthView: View {
    let material: BoardDepth
    let thickness: CGFloat
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let shadowOffset: CGFloat
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
            ZStack(alignment: .bottom) {
                shape.fill(material.upperFace)
                LinearGradient(colors: [material.upperFace, material.lowerFace],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: thickness + 1 / displayScale)
            }
            .overlay {
                BoardBorder(start: .clear, middle: material.shade.opacity(0.15),
                            end: material.shade.opacity(0.6),
                            width: min(1 / displayScale, thickness * 0.2), cornerRadius: cornerRadius)
            }
            .clipShape(shape)
            .background {
                shape.fill(material.lowerFace)
                    .shadow(color: material.shadow, radius: shadowRadius, y: shadowOffset)
            }
            .frame(width: geometry.size.width, height: geometry.size.height + thickness)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Rime scatters light across a soft lip instead of forming a hard metallic
/// bevel. Thin nested edge strips stay beneath the grid and do not require a
/// board-sized blur or offscreen rendering when the board resizes.
private struct FrostedBoardEdge: View {
    let material: BoardDepth
    let cellSize: CGFloat
    let thickness: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            BoardBorder(start: material.highlight.opacity(0.20),
                        middle: material.highlight.opacity(0.10), end: material.highlight.opacity(0.17),
                        width: min(6, min(cellSize * 0.26, thickness * 1.6)), cornerRadius: cornerRadius)
            BoardBorder(start: material.highlight.opacity(0.36),
                        middle: material.highlight.opacity(0.18), end: material.highlight.opacity(0.28),
                        width: min(3, min(cellSize * 0.13, thickness * 0.8)), cornerRadius: cornerRadius)
            BoardBorder(start: material.highlight,
                        middle: material.highlight.opacity(0.50), end: material.highlight.opacity(0.72),
                        width: min(1, min(cellSize * 0.045, thickness * 0.3)), cornerRadius: cornerRadius)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ImageStone: Equatable {
    var rect: CGRect
    var color: StoneColor
    var isRemoved: Bool
    var variant: Int
    var fiberSeed: UInt32
}

/// Rendered stones in one Canvas, so a full board is a few dozen image draws
/// rather than a view per stone. Shadows are batched below all stones,
/// following the images' key-light direction. Equatable: a Canvas redraws
/// whenever its view updates, so an unchanged board (a clock tick on a row
/// or in Game Detail) must not repaint its stones and their blurred shadows.
private struct ImageStoneCanvas: View, Equatable {
    var stones: [ImageStone]
    var images: StoneImages?
    var cellSize: CGFloat
    var lightDirection: StoneLightDirection
    var shadowStyle: ImageStoneShadowStyle
    var blackPalette: StonePalette
    var whitePalette: StonePalette
    // The raised profile is capped at a 3 pt blur and 3 pt offset; allow
    // three blur radii beyond that offset, including edge intersections.
    private var overhang: CGFloat { shadowStyle == .raised ? 12 : 6 }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, _ in
            guard let images, !stones.isEmpty else { return }
            context.translateBy(x: overhang, y: overhang)
            let black = images.black.map { context.resolve(Image(uiImage: $0).interpolation(.high)) }
            let white = images.white.map { context.resolve(Image(uiImage: $0).interpolation(.high)) }

            // Long casts shift the apparent center of a tiny stone. Keep
            // phone-size shadows close to its footprint; larger boards
            // retain the theme's full raised profile and light direction.
            let shadowScale = min(1, max(0.35, (cellSize - 10) / 30))

            if shadowStyle == .raised {
                // A full-footprint cast stays visible against wood grain at
                // phone size. Cap its spread so larger boards do not float.
                drawShadow(in: context, radius: min(3, max(1.8, cellSize * 0.07)) * shadowScale,
                           x: min(2, max(0.8, cellSize * 0.035)) * shadowScale,
                           y: min(3, max(1.6, cellSize * 0.065)) * shadowScale,
                           inset: 0, opacity: 0.34)
                // The tighter edge keeps the curved stone grounded; the
                // cast above is softer than the default contact-only shadow.
                drawShadow(in: context, radius: min(1, max(0.45, cellSize * 0.02)),
                           x: min(0.5, cellSize * 0.01), y: min(0.8, cellSize * 0.02),
                           inset: 0.2, opacity: 0.32)
            } else {
                drawShadow(in: context, radius: max(0.6, cellSize * 0.06 * shadowScale),
                           x: cellSize * 0.03 * shadowScale, y: cellSize * 0.06 * shadowScale,
                           inset: 0.5, opacity: 0.5)
            }

            // Batch the loose fibers by player and captured state. Their
            // roots follow the actual artwork rather than a perfect circle.
            var fiberBodies = [Path](repeating: Path(), count: 4)
            var fiberWisps = [Path](repeating: Path(), count: 4)
            var fiberTemplates = [Int: FeltEdgeFibers]()
            for stone in stones {
                let variants = stone.color == .black ? black : white
                guard !variants.isEmpty else { continue }
                var stoneContext = context
                // Scoring fades the whole stone, as removed flat stones do.
                if stone.isRemoved { stoneContext.opacity = 0.5 }
                let side = stone.rect.width / images.footprint
                stoneContext.draw(variants[stone.variant % variants.count],
                                  in: CGRect(x: stone.rect.midX - side / 2, y: stone.rect.midY - side / 2,
                                             width: side, height: side))
                if let contour = images.fiberContour(stone.color, variant: stone.variant) {
                    // Eight stable tuft patterns per artwork keep a dense
                    // board from constructing every strand for every stone.
                    let key = (stone.variant * 8 + Int(stone.fiberSeed)) * 2 + (stone.color == .black ? 0 : 1)
                    let fibers: FeltEdgeFibers
                    if let cached = fiberTemplates[key] {
                        fibers = cached
                    } else {
                        fibers = FeltEdgeFibers.stone(contour: contour,
                            in: CGRect(origin: .zero, size: stone.rect.size),
                            seed: stone.fiberSeed, footprint: images.footprint)
                        fiberTemplates[key] = fibers
                    }
                    let index = (stone.color == .black ? 0 : 2) + (stone.isRemoved ? 1 : 0)
                    let offset = CGAffineTransform(translationX: stone.rect.minX, y: stone.rect.minY)
                    fiberBodies[index].addPath(fibers.body, transform: offset)
                    fiberWisps[index].addPath(fibers.wisps, transform: offset)
                }
            }
            for index in 0..<4 where !fiberBodies[index].isEmpty || !fiberWisps[index].isEmpty {
                let palette = index < 2 ? blackPalette : whitePalette
                var fibers = context
                fibers.opacity = index.isMultiple(of: 2) ? 1 : 0.5
                fibers.stroke(fiberBodies[index], with: .color(palette.shade.opacity(0.7)),
                              style: StrokeStyle(lineWidth: 0.3, lineCap: .round))
                fibers.stroke(fiberWisps[index], with: .color(palette.highlight.opacity(0.75)),
                              style: StrokeStyle(lineWidth: 0.22, lineCap: .round))
            }
        }
        // Tint only the rendered stones and their black contact shadows;
        // move numbers, territory and interaction marks remain independent.
        .colorMultiply(images?.tint ?? .white)
        // Room for the edge stones' shadows.
        .padding(-overhang)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawShadow(in context: GraphicsContext, radius: CGFloat,
                            x: CGFloat, y: CGFloat, inset: CGFloat, opacity: Double) {
        context.drawLayer { shadows in
            shadows.addFilter(.blur(radius: radius))
            var path = Path()
            for stone in stones where !stone.isRemoved {
                path.addEllipse(in: stone.rect
                    .offsetBy(dx: lightDirection.shadowXSign * x, dy: y)
                    .insetBy(dx: inset, dy: inset))
            }
            shadows.fill(path, with: .color(.black.opacity(opacity)))
        }
    }
}

struct Stones: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.boardAppearance) private var appearance
    @ObservedObject var boardPosition: BoardPosition
    var variation: Variation?
    var geometry: GeometryProxy
    /// Which status indicators to draw, shared with the annotation overlay.
    var indicators: BoardIndicatorPlan

    var body: some View {
        let width = boardPosition.width
        let height = boardPosition.height
        let indicatorMode = BoardStoneIndicatorMode(variation: variation)
                
        let size = stoneSize(geometry: geometry, boardSize: max(width, height), displayScale: displayScale)
        let whiteLivingPath = CGMutablePath()
        let blackLivingPath = CGMutablePath()
        let whiteCapturedPath = CGMutablePath()
        let blackCapturedPath = CGMutablePath()
        let whiteScoreIndicator = CGMutablePath()
        let blackScoreIndicator = CGMutablePath()
        let dameIndicator = CGMutablePath()
        let whiteEstimatedScore = CGMutablePath()
        let blackEstimatedScore = CGMutablePath()
        let scoresOnBlackStones = CGMutablePath()
        let scoresOnWhiteStones = CGMutablePath()

        let drawsShadow = usesDetailedStoneRendering(at: size)
        let shadowXSign = appearance.stoneLightDirection.shadowXSign
        let shadowScale = min(1, max(0.35, (size - 10) / 30))
        let shadowOffset = min(2, max(1, size / 30)) * shadowScale
        let stoneImages = drawsShadow ? appearance.stoneImages : nil
        var imageStones = [ImageStone]()
        
        let whitePaths = [CGMutablePath(), CGMutablePath(), CGMutablePath(), CGMutablePath()]
        let blackPaths = [CGMutablePath(), CGMutablePath(), CGMutablePath(), CGMutablePath()]

        let scoreHiddenPoints = Set(indicators.undoPoints.map { [$0.row, $0.column] })

        for row in 0..<height {
            for column in 0..<width {
                if case .hasStone(let stoneColor) = boardPosition[row, column] {
                    let padding = size < 10 ? CGFloat(0.0) : CGFloat(1.0)
                    let stoneRect = CGRect(x: CGFloat(column) * size + padding, y: CGFloat(row) * size + padding, width: size - padding * 2, height: size - padding * 2)
                    let isRemoved = boardPosition.removedStones?.contains([row, column]) ?? false
                    if let stoneImages {
                        imageStones.append(ImageStone(
                            rect: stoneRect, color: stoneColor, isRemoved: isRemoved,
                            variant: StoneImages.variantIndex(row: row, column: column,
                                                              count: stoneImages.variants(stoneColor).count),
                            fiberSeed: UInt32(StoneImages.variantIndex(row: row, column: column, count: 8))
                        ))
                    }
                    if isRemoved {
                        if stoneColor == .white {
                            whiteCapturedPath.addEllipse(in: stoneRect)
                        } else {
                            blackCapturedPath.addEllipse(in: stoneRect)
                        }
                    } else {
                        if stoneColor == .white {
                            whiteLivingPath.addEllipse(in: stoneRect)
                            
                            // Needs 4 paths to avoid drawing adjacent (orthogonally and diagonally)
                            // stones in the same path.
                            whitePaths[(row % 2) * 2 + (column % 2)].addEllipse(in: stoneRect)
                        } else {
                            blackLivingPath.addEllipse(in: stoneRect)
                            blackPaths[(row % 2) * 2 + (column % 2)].addEllipse(in: stoneRect)
                        }
                    }
                    
                }
                // An active undo request must stay readable over a score estimate.
                // The estimate data remains intact and returns when the request ends.
                if scoreHiddenPoints.contains([row, column]) { continue }
                let scoringRectSize = max(size / 3, 2)
                let scoringRectPadding = (size - scoringRectSize) / 2
                let scoringRect = CGRect(
                    x: CGFloat(column) * size + scoringRectPadding,
                    y: CGFloat(row) * size + scoringRectPadding,
                    width: scoringRectSize,
                    height: scoringRectSize)
                if let scores = boardPosition.gameScores {
                    let isRemoved = boardPosition.removedStones?.contains([row, column]) ?? false
                    if boardPosition[row, column] == .empty && isRemoved {
                        dameIndicator.addRect(scoringRect)
                    } else {
                        if scores.black.scoringPositions.contains([row, column]) {
                            blackScoreIndicator.addRect(scoringRect)
                        } else if scores.white.scoringPositions.contains([row, column]) {
                            whiteScoreIndicator.addRect(scoringRect)
                        }
                    }
                }
                if let estimatedScores = boardPosition.estimatedScores {
                    if case .hasStone(let color) = estimatedScores[row][column] {
                        if color == .black {
                            blackEstimatedScore.addRect(scoringRect)
                        } else {
                            whiteEstimatedScore.addRect(scoringRect)
                        }
                    }
                }
                if boardPosition.hasOwnershipMark(atRow: row, column: column),
                   case .hasStone(let color) = boardPosition[row, column] {
                    (color == .black ? scoresOnBlackStones : scoresOnWhiteStones).addRect(scoringRect)
                }
            }
        }
        
        let marker = StoneMarkerGeometry(cellSize: size)
        
        // One structure at every size: shaded stones and the small flat ones
        // differ only in style. Switching views at the 14 pt threshold (or
        // identifying the paths by their contents) made a resizing board, as
        // when chat opens, fade between two boards of different sizes.
        // Image stones take over at detailed sizes; the drawn layers stay in
        // place, transparent, for the same reason.
        let drawsPaths = stoneImages == nil
        let dropShadow = drawsShadow && drawsPaths ? Color(.sRGBLinear, white: 0, opacity: 0.33) : .clear
        let black = appearance.black
        let white = appearance.white
        let fill = { (palette: StonePalette) -> AnyShapeStyle in
            if !drawsPaths { return AnyShapeStyle(Color.clear) }
            return drawsShadow
                ? AnyShapeStyle(palette.highlight
                    .shadow(.inner(color: palette.shade, radius: size / 4,
                                   x: -shadowXSign * size / 2.5, y: -size / 2.5)))
                : AnyShapeStyle(palette.flat)
        }
        // Edges are always present and only change color, for the same reason.
        let edge = { (palette: StonePalette) in
            drawsPaths ? (drawsShadow ? palette.rim : palette.outline) ?? .clear : .clear
        }
        return ZStack {
            ForEach(whitePaths.indices, id: \.self) { index in
                Path(whitePaths[index]).fill(fill(white))
                .shadow(color: dropShadow, radius: 2 * shadowScale, x: shadowXSign * shadowOffset, y: shadowOffset)
            }
            Path(whiteLivingPath).stroke(edge(white), lineWidth: 0.5)
            ForEach(blackPaths.indices, id: \.self) { index in
                Path(blackPaths[index]).fill(fill(black))
                .shadow(color: dropShadow, radius: 2 * shadowScale, x: shadowXSign * shadowOffset, y: shadowOffset)
            }
            Path(blackLivingPath).stroke(edge(black), lineWidth: drawsShadow ? 0.75 : 0.5)
            // The Canvas overhangs the board for edge shadows, and that
            // overhang widens the board's accessibility frame. Mount it only
            // for themes with image stones; the choice follows the theme, not
            // the cell size, so a resizing board never mounts or removes it.
            if appearance.stoneImages != nil {
                ImageStoneCanvas(stones: imageStones, images: stoneImages, cellSize: size,
                                 lightDirection: appearance.stoneLightDirection,
                                 shadowStyle: appearance.imageStoneShadow,
                                 blackPalette: black, whitePalette: white)
                .equatable()
            }
            
            if boardPosition.removedStones != nil {
                Path(whiteCapturedPath).fill(drawsPaths ? white.flat : .clear).opacity(0.5)
                Path(whiteCapturedPath).stroke(drawsPaths ? appearance.markOutline : .clear)
                Path(blackCapturedPath).fill(drawsPaths ? black.flat : .clear).opacity(0.5)
                let removedOutline = appearance.removedStoneOutline ?? .clear
                let removedOutlineStyle = StrokeStyle(lineWidth: size >= 20 ? 1 : 0.75,
                                                      dash: [max(1.5, size * 0.12), max(1.5, size * 0.1)])
                Path(whiteCapturedPath).stroke(removedOutline, style: removedOutlineStyle)
                Path(blackCapturedPath).stroke(removedOutline, style: removedOutlineStyle)
            }

            if indicatorMode == .variationNumberings, let variation {
                VariationNumberings(variation: variation, cellSize: size, policy: indicators.policy)
            } else if let lastMove = indicators.lastMove {
                let lastRow = lastMove.point.row
                let lastColumn = lastMove.point.column
                if case .hasStone(let lastColor) = boardPosition[lastRow, lastColumn] {
                    let palette = appearance.stones(lastColor)
                    let mark = Path { path in
                        let center = CGPoint(x: (CGFloat(lastColumn) + 0.5) * size,
                                             y: (CGFloat(lastRow) + 0.5) * size)
                        if lastMove.pending {
                            let radius = marker.pendingDiameter / 2
                            path.move(to: CGPoint(x: center.x - radius, y: center.y))
                            path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
                            path.move(to: CGPoint(x: center.x, y: center.y - radius))
                            path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                        } else {
                            let radius = marker.ringDiameter / 2
                            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                                       width: radius * 2, height: radius * 2))
                        }
                    }
                    // A solid, symmetric keyline, never an offset glow. Only
                    // themes with a casing draw it; it stays in place, clear,
                    // below the detail threshold.
                    if let casing = palette.detailedMarkerCasing {
                        mark.stroke(drawsShadow ? casing : .clear,
                                    style: StrokeStyle(lineWidth: marker.lineWidth + 2 * marker.casingWidth,
                                                       lineCap: .round, lineJoin: .round))
                    }
                    mark.stroke(palette.lastMove,
                                style: StrokeStyle(lineWidth: marker.lineWidth,
                                                   lineCap: .round, lineJoin: .round))
                }
            }

            if indicatorMode == .positionIndicators {
                ForEach(Array(indicators.undoPoints.enumerated()), id: \.offset) { _, point in
                    let row = point.row
                    let column = point.column
                    if case .hasStone(let stoneColor) = boardPosition[row, column] {
                        StoneMarkerText(text: "", systemImage: "arrow.uturn.backward", fontSize: size * 0.55,
                                        foreground: appearance.stones(stoneColor).label,
                                        casing: drawsShadow ? appearance.textCasing(on: stoneColor) : nil,
                                        casingWidth: marker.casingWidth)
                            .equatable()
                            .frame(width: marker.stoneDiameter * 0.8, height: marker.stoneDiameter * 0.8)
                            .position(
                                x: (CGFloat(column) + 0.5) * size,
                                y: (CGFloat(row) + 0.5) * size
                            )
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
            
            if boardPosition.gameScores != nil {
                Path(dameIndicator).stroke(appearance.dameColor, lineWidth: marker.lineWidth)
                Path(whiteScoreIndicator).fill(white.territoryMark)
                Path(whiteScoreIndicator).stroke(appearance.markOutline, lineWidth: 0.5)
                Path(blackScoreIndicator).fill(black.territoryMark)
                Path(blackScoreIndicator).stroke(appearance.markOutline, lineWidth: 0.5)
            }

            if boardPosition.estimatedScores != nil {
                Path(whiteEstimatedScore).fill(white.territoryMark)
                Path(whiteEstimatedScore).stroke(appearance.markOutline, lineWidth: 0.5)
                Path(blackEstimatedScore).fill(black.territoryMark)
                Path(blackEstimatedScore).stroke(appearance.markOutline, lineWidth: 0.5)
            }
            Path(scoresOnBlackStones).stroke(appearance.scoreMarkOutline(on: .black), lineWidth: marker.scoreLineWidth)
            Path(scoresOnWhiteStones).stroke(appearance.scoreMarkOutline(on: .white), lineWidth: marker.scoreLineWidth)
        }
        .frame(width: size * CGFloat(width), height: size * CGFloat(height))
    }
}

struct StoneRemovalOverlay: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.boardAppearance) private var appearance
    #if DEBUG
    @Environment(\.boardMarkerAuditState) private var markerAuditState
    #endif
    @ObservedObject var boardPosition: BoardPosition
    var stoneRemovalOption = StoneRemovalOption.toggleGroup
    var geometry: GeometryProxy
    @Binding var highlightedRow: Int
    @Binding var highlightedColumn: Int
    @State var hoveredGroup = Set<[Int]>()
    var stoneRemovalSelectedPoints: Binding<Set<[Int]>> = .constant(Set<[Int]>())

    var body: some View {
        let width = boardPosition.width
        let height = boardPosition.height
        let size = stoneSize(geometry: geometry, boardSize: max(width, height), displayScale: displayScale)
        let marker = StoneMarkerGeometry(cellSize: size)

        let toBeRemovedPath = CGMutablePath()
        let toBeAddedPath = CGMutablePath()
        
        #if DEBUG
        let drawnGroup = markerAuditState?.removalPoints ?? hoveredGroup
        #else
        let drawnGroup = hoveredGroup
        #endif
        for point in drawnGroup {
            let row = point[0]
            let column = point[1]
            
            let indicatorRectSize = marker.actionDiameter
            let indicatorRectPadding = (size - indicatorRectSize) / 2
            let indicatorRect = CGRect(
                x: CGFloat(column) * size + indicatorRectPadding,
                y: CGFloat(row) * size + indicatorRectPadding,
                width: indicatorRectSize,
                height: indicatorRectSize)
            
            if boardPosition.removedStones?.contains([row, column]) ?? false {
                toBeAddedPath.move(to: CGPoint(x: indicatorRect.midX, y: indicatorRect.minY))
                toBeAddedPath.addLine(to: CGPoint(x: indicatorRect.midX, y: indicatorRect.maxY))
                toBeAddedPath.move(to: CGPoint(x: indicatorRect.minX, y: indicatorRect.midY))
                toBeAddedPath.addLine(to: CGPoint(x: indicatorRect.maxX, y: indicatorRect.midY))
            } else {
                toBeRemovedPath.move(to: CGPoint(x: indicatorRect.minX, y: indicatorRect.maxY))
                toBeRemovedPath.addLine(to: CGPoint(x: indicatorRect.maxX, y: indicatorRect.minY))
                toBeRemovedPath.move(to: CGPoint(x: indicatorRect.minX, y: indicatorRect.minY))
                toBeRemovedPath.addLine(to: CGPoint(x: indicatorRect.maxX, y: indicatorRect.maxY))
            }
        }
        let indicatorWidth = marker.actionLineWidth
        
        let casing = appearance.removalMarkCasing ?? .clear
        let casingStyle = StrokeStyle(lineWidth: indicatorWidth + 2 * marker.casingWidth, lineCap: .round)
        let markStyle = StrokeStyle(lineWidth: indicatorWidth, lineCap: .round)
        let restoreWidth = marker.restoreLineWidth(displayScale: displayScale)
        let restoreCasing = marker.restoreCasingWidth(displayScale: displayScale)
        return ZStack {
            Color.clear
            Path(toBeRemovedPath).stroke(casing, style: casingStyle)
            Path(toBeAddedPath).stroke(casing, style: StrokeStyle(lineWidth: restoreWidth + 2 * restoreCasing, lineCap: .round))
            Path(toBeRemovedPath).stroke(appearance.removeMark, style: markStyle)
            Path(toBeAddedPath).stroke(appearance.restoreMark, style: StrokeStyle(lineWidth: restoreWidth, lineCap: .round))
        }
        .frame(width: size * CGFloat(width), height: size * CGFloat(height))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged({ value in
                    let newRow = Int((value.location.y / size - 0.5).rounded())
                    let newColumn = Int((value.location.x / size - 0.5).rounded())
                    
                    if newColumn >= 0 && newColumn < width && newRow >= 0 && newRow < height {
                        if newRow != highlightedRow || newColumn != highlightedColumn {
                            highlightedRow = newRow
                            highlightedColumn = newColumn
                            if !hoveredGroup.contains([newRow, newColumn]) {
                                if stoneRemovalOption == .toggleGroup {
                                    hoveredGroup = self.boardPosition.groupForStoneRemoval(atRow: newRow, column: newColumn)
                                } else {
                                    hoveredGroup = Set<[Int]>([[newRow, newColumn]])
                                }
                            }
                        }
                    } else {
                        highlightedRow = -1
                        highlightedColumn = -1
                        hoveredGroup.removeAll()
                    }
                })
                .onEnded { _ in
                    stoneRemovalSelectedPoints.wrappedValue = hoveredGroup
                    highlightedRow = -1
                    highlightedColumn = -1
                }
        )
        .onChange(of: stoneRemovalSelectedPoints.wrappedValue) { _, newSelectedPoints in
            if newSelectedPoints.count == 0 {
                hoveredGroup.removeAll()
            }
        }
    }
}

struct CoordinateHighlightOverlay: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.boardAppearance) private var appearance
    @ObservedObject var boardPosition: BoardPosition
    var geometry: GeometryProxy
    var highlightCoordinates: [[Int]]

    var body: some View {
        let width = boardPosition.width
        let height = boardPosition.height
                
        let size = stoneSize(geometry: geometry, boardSize: max(width, height), displayScale: displayScale)
        let highlightedCoordinatesPath = CGMutablePath()
        let marker = StoneMarkerGeometry(cellSize: size)
        let highlightWidth = marker.actionLineWidth

        for coordinate in highlightCoordinates {
            let row = boardPosition.height - coordinate[0] - 1
            let column = coordinate[1]

            // Corner brackets identify the point while keeping its center
            // clear for move numbers, annotations and an undo request.
            let highlightRectSize = max(1, size - highlightWidth - 2 * marker.casingWidth - 1 / displayScale)
            let highlightRectPadding = (size - highlightRectSize) / 2
            let highlightRect = CGRect(
                x: CGFloat(column) * size + highlightRectPadding,
                y: CGFloat(row) * size + highlightRectPadding,
                width: highlightRectSize,
                height: highlightRectSize)
            
            let arm = highlightRectSize * 0.23
            for (x, y, dx, dy) in [(highlightRect.minX, highlightRect.minY, CGFloat(1), CGFloat(1)),
                                   (highlightRect.maxX, highlightRect.minY, -1, 1),
                                   (highlightRect.minX, highlightRect.maxY, 1, -1),
                                   (highlightRect.maxX, highlightRect.maxY, -1, -1)] {
                highlightedCoordinatesPath.move(to: CGPoint(x: x, y: y + dy * arm))
                highlightedCoordinatesPath.addLine(to: CGPoint(x: x, y: y))
                highlightedCoordinatesPath.addLine(to: CGPoint(x: x + dx * arm, y: y))
            }
        }
        
        return ZStack {
            if let casing = appearance.highlightCasing {
                Path(highlightedCoordinatesPath)
                    .stroke(casing, style: StrokeStyle(lineWidth: highlightWidth + 2 * marker.casingWidth,
                                                       lineCap: .round, lineJoin: .round))
            }
            Path(highlightedCoordinatesPath)
                .stroke(appearance.highlightColor, style: StrokeStyle(lineWidth: highlightWidth,
                                                                      lineCap: .round, lineJoin: .round))
        }.frame(width: size * CGFloat(width), height: size * CGFloat(height))
    }
}

struct BoardMarkupOverlay: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.boardAppearance) private var appearance
    @ObservedObject var boardPosition: BoardPosition
    var markups: BoardMarkups
    var geometry: GeometryProxy
    var widgetRenderingMode: WidgetRenderingMode

    var body: some View {
        let size = stoneSize(
            geometry: geometry,
            boardSize: max(boardPosition.width, boardPosition.height),
            displayScale: displayScale
        )
        let marker = StoneMarkerGeometry(cellSize: size)

        ZStack {
            ForEach(markups.keys.sorted(), id: \.self) { point in
                if point.row >= 0,
                   point.row < boardPosition.height,
                   point.column >= 0,
                   point.column < boardPosition.width,
                   let markup = markups[point], markup.isVisible {
                    let foreground = markerColor(at: point)
                    ZStack {
                        if boardPosition[point.row, point.column] == .empty {
                            Circle()
                                .fill(emptyPointBackground(cellSize: size))
                                .frame(width: markup.label?.isEmpty == false ? marker.stoneDiameter * 0.88 : size * 0.62,
                                       height: markup.label?.isEmpty == false ? marker.stoneDiameter * 0.88 : size * 0.62)
                        }
                        let casing = markerCasing(at: point, cellSize: size)
                        ForEach(BoardMarkShape.allCases, id: \.self) { shape in
                            if markup.shapes.contains(shape) {
                                if let casing {
                                    BoardMarkShapeView(shape: shape)
                                        .stroke(casing,
                                                style: StrokeStyle(
                                                    lineWidth: max(1 / displayScale, marker.lineWidth) + 2 * marker.casingWidth,
                                                    lineCap: .round, lineJoin: .round))
                                        .frame(width: marker.shapeDiameter, height: marker.shapeDiameter)
                                }
                                BoardMarkShapeView(shape: shape)
                                    .stroke(
                                        foreground,
                                        style: StrokeStyle(
                                            lineWidth: max(1 / displayScale, marker.lineWidth),
                                            lineCap: .round,
                                            lineJoin: .round
                                        )
                                    )
                                    .frame(width: marker.shapeDiameter, height: marker.shapeDiameter)
                            }
                        }
                        if let label = markup.label {
                            StoneMarkerText(text: label, fontSize: size * 0.55, foreground: foreground,
                                            casing: textCasing(at: point, cellSize: size),
                                            casingWidth: marker.casingWidth)
                                .equatable()
                                .frame(width: marker.stoneDiameter * 0.78, height: marker.stoneDiameter * 0.78)
                        }
                    }
                    .position(
                        x: (CGFloat(point.column) + 0.5) * size,
                        y: (CGFloat(point.row) + 0.5) * size
                    )
                }
            }
        }
        .frame(
            width: size * CGFloat(boardPosition.width),
            height: size * CGFloat(boardPosition.height)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func emptyPointBackground(cellSize: CGFloat) -> Color {
        widgetRenderingMode == .fullColor
            ? appearance.surfaceColor(detailed: usesDetailedStoneRendering(at: cellSize))
            : Color.white.opacity(0.8)
    }

    /// A shape's casing, only on stones whose theme defines one. It stays in
    /// place, clear, below the detail threshold, so resizing never swaps views.
    private func markerCasing(at point: BoardPoint, cellSize: CGFloat) -> Color? {
        guard case .hasStone(let color) = boardPosition[point.row, point.column],
              let casing = appearance.stones(color).detailedMarkerCasing else { return nil }
        return usesDetailedStoneRendering(at: cellSize) ? casing : .clear
    }

    private func textCasing(at point: BoardPoint, cellSize: CGFloat) -> Color? {
        guard usesDetailedStoneRendering(at: cellSize),
              case .hasStone(let color) = boardPosition[point.row, point.column] else { return nil }
        return appearance.textCasing(on: color)
    }

    private func markerColor(at point: BoardPoint) -> Color {
        if case .hasStone(let color) = boardPosition[point.row, point.column] {
            return appearance.stones(color).label
        }
        return widgetRenderingMode == .fullColor ? appearance.emptyPointMarker : .black
    }
}

private struct BoardMarkShapeView: Shape {
    let shape: BoardMarkShape

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch shape {
        case .triangle:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            // Equilateral and centered by its centroid, like the other marks.
            path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.433, y: rect.midY + rect.height / 4))
            path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.433, y: rect.midY + rect.height / 4))
            path.closeSubpath()
        case .square:
            path.addRect(rect)
        case .circle:
            path.addEllipse(in: rect)
        case .cross:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        return path
    }
}

private struct BoardMarkupEditingOverlay: View {
    private enum GestureMode {
        case paint
        case clear
    }

    @Environment(\.displayScale) private var displayScale
    @ObservedObject var boardPosition: BoardPosition
    @Binding var markups: BoardMarkups
    @Binding var tool: AnalyzeBoardTool
    var geometry: GeometryProxy
    @State private var visitedPoints = Set<BoardPoint>()
    @State private var gestureMode: GestureMode?
    #if MAIN_APP
    @State private var selectionFeedbackGenerator: UISelectionFeedbackGenerator?
    #endif
    @Setting(.hapticsFeedback) private var hapticsFeedback: Bool

    var body: some View {
        let size = stoneSize(
            geometry: geometry,
            boardSize: max(boardPosition.width, boardPosition.height),
            displayScale: displayScale
        )

        Color.clear
            .frame(
                width: size * CGFloat(boardPosition.width),
                height: size * CGFloat(boardPosition.height)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        editPoint(at: value.location, cellSize: size)
                    }
                    .onEnded { _ in
                        #if MAIN_APP
                        if !visitedPoints.isEmpty && hapticsFeedback {
                            SystemPlatformServices.shared
                                .playNotificationFeedback(.success)
                        }
                        selectionFeedbackGenerator = nil
                        #endif
                        visitedPoints.removeAll()
                        gestureMode = nil
                    }
            )
    }

    private func editPoint(at location: CGPoint, cellSize: CGFloat) {
        let row = Int((location.y / cellSize - 0.5).rounded())
        let column = Int((location.x / cellSize - 0.5).rounded())
        guard row >= 0,
              row < boardPosition.height,
              column >= 0,
              column < boardPosition.width else {
            return
        }

        let point = BoardPoint(row: row, column: column)
        guard visitedPoints.insert(point).inserted else {
            return
        }
        if gestureMode == nil {
            gestureMode = tool == .eraser || tool.matches(markups[point])
                ? .clear
                : .paint
        }

        var updatedMarkups = markups
        switch gestureMode {
        case .clear:
            updatedMarkups[point] = nil
        case .paint:
            updatedMarkups.paint(tool, at: point)
        case nil:
            break
        }
        markups = updatedMarkups

        #if MAIN_APP
        if selectionFeedbackGenerator == nil && hapticsFeedback {
            selectionFeedbackGenerator = SystemPlatformServices.shared
                .makeSelectionFeedbackGenerator()
        }
        selectionFeedbackGenerator?.selectionChanged()
        #endif
    }
}

/// A board that shows a position and nothing else, as in list rows and
/// cards. A live game's row re-renders on every clock tick; compared by the
/// position it shows, the board is skipped then instead of redrawing its
/// stones. It still follows the position's own changes and the theme. Its
/// own compositing group keeps the render server from redrawing its stones'
/// shadows when the row's clock text changes beside it. (A geometry group
/// would too, but it moves the grid by a pixel on fractional positions.)
struct PositionBoardView: View, Equatable {
    let boardPosition: BoardPosition

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.boardPosition === rhs.boardPosition
    }

    var body: some View {
        BoardView(boardPosition: boardPosition)
            .compositingGroup()
    }
}

struct BoardView: View {
    @Environment(\.boardAppearance) private var appearance
    @Environment(\.displayScale) private var displayScale
    var widgetRenderingMode: WidgetRenderingMode = .fullColor
    @ObservedObject var boardPosition: BoardPosition
    var variation: Variation?
    var showsCoordinate = false
    var playable = false
    var stoneRemovable = false
    var stoneRemovalOption = StoneRemovalOption.toggleGroup
    var newMove: Binding<Move?> = .constant(nil)
    var newPosition: Binding<BoardPosition?> = .constant(nil)
    var allowsSelfCapture: Bool = false
    @State var hoveredPoint: [Int]? = nil
    @State var isHoveredPointValid: Bool? = nil
    @State var highlightedRow = -1
    @State var highlightedColumn = -1
    var stoneRemovalSelectedPoints: Binding<Set<[Int]>> = .constant(Set<[Int]>())
    var cornerRadius: CGFloat = 0.0
    var highlightCoordinates: [[Int]] = []
    var undoRequestCoordinates: [[Int]] = []
    var boardTool: Binding<AnalyzeBoardTool> = .constant(.moves)
    var markups: Binding<BoardMarkups> = .constant([:])
    #if DEBUG
    var markerAuditState: BoardMarkerAuditState? = nil
    #endif

    @ViewBuilder
    private func withMarkerAudit<Content: View>(_ content: Content) -> some View {
        #if DEBUG
        content.environment(\.boardMarkerAuditState, markerAuditState)
        #else
        content
        #endif
    }
    
    private func selectPoint(_ point: [Int]?) -> Bool {
        guard let point,
              let position = try? boardPosition.makeMove(
                move: .placeStone(point[0], point[1]),
                allowsSelfCapture: allowsSelfCapture
              ) else {
            newMove.wrappedValue = nil
            newPosition.wrappedValue = nil
            return false
        }
        // Consumers observe newMove, so publish its matching position first.
        newPosition.wrappedValue = position
        newMove.wrappedValue = .placeStone(point[0], point[1])
        return true
    }

    var gobanAndStones: some View {
        let displayedPosition = (newMove.wrappedValue != nil && newPosition.wrappedValue != nil) ?
            newPosition.wrappedValue! : boardPosition
        // One plan for the stones and the overlay: a status indicator and an
        // annotation never both claim, or both leave empty, the same point.
        let indicators = BoardIndicatorPlan(
            position: displayedPosition, variation: variation, markups: markups.wrappedValue,
            undoRequestCoordinates: undoRequestCoordinates,
            isLastMovePending: newMove.wrappedValue != nil, showsLastMove: !stoneRemovable)
        return withMarkerAudit(GeometryReader { boardGeometry in
            ZStack(alignment: .center) {
                Goban(
                    geometry: boardGeometry,
                    width: boardPosition.width,
                    height: boardPosition.height,
                    showsCoordinates: showsCoordinate,
                    playable: playable,
                    stoneRemovable: stoneRemovable,
                    highlightedRow: $highlightedRow,
                    highlightedColumn: $highlightedColumn,
                    hoveredPoint: $hoveredPoint,
                    isHoveredPointValid: isHoveredPointValid,
                    selectPoint: selectPoint
                )
                .allowsHitTesting(
                    playable
                        && boardTool.wrappedValue == .moves
                        && displayedPosition.estimatedScores == nil
                )
                .onChange(of: hoveredPoint) { _, value in
                    isHoveredPointValid = nil
                    if let hoveredPoint = hoveredPoint {
                        do {
                            newPosition.wrappedValue = try boardPosition.makeMove(move: .placeStone(hoveredPoint[0], hoveredPoint[1]), allowsSelfCapture: allowsSelfCapture)
                            isHoveredPointValid = true
                        } catch {
                            isHoveredPointValid = false
                        }
                    }
                }
                Stones(
                    boardPosition: displayedPosition,
                    variation: variation,
                    geometry: boardGeometry,
                    indicators: indicators
                )
                BoardMarkupOverlay(
                    boardPosition: displayedPosition,
                    markups: indicators.visibleMarkups,
                    geometry: boardGeometry,
                    widgetRenderingMode: widgetRenderingMode
                )
                CoordinateHighlightOverlay(
                    boardPosition: boardPosition,
                    geometry: boardGeometry,
                    highlightCoordinates: highlightCoordinates
                )
                if playable && boardTool.wrappedValue != .moves {
                    BoardMarkupEditingOverlay(
                        boardPosition: boardPosition,
                        markups: markups,
                        tool: boardTool,
                        geometry: boardGeometry
                    )
                }
                if stoneRemovable {
                    StoneRemovalOverlay(
                        boardPosition: boardPosition,
                        stoneRemovalOption: stoneRemovalOption,
                        geometry: boardGeometry,
                        highlightedRow: $highlightedRow,
                        highlightedColumn: $highlightedColumn,
                        stoneRemovalSelectedPoints: stoneRemovalSelectedPoints
                    )
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).aspectRatio(1, contentMode: .fit)
        })
    }
    
    private func boardFace(in geometry: GeometryProxy, depthGeometry: BoardDepthGeometry) -> some View {
        let width: CGFloat = CGFloat(boardPosition.width)
        let height: CGFloat = CGFloat(boardPosition.height)
        return Group {
            // The grid's cell, as Goban and Stones size it. Below the detail
            // threshold the surface is its solid color alone; its layers stay
            // in place, hidden, so a resizing board does not fade between two.
            let gridSize = boardGridSize(containerSize: geometry.size, boardWidth: boardPosition.width,
                                         boardHeight: boardPosition.height, showsCoordinates: showsCoordinate)
            let cellSize = floor(min(gridSize.width, gridSize.height) / max(width, height) * displayScale) / displayScale
            let detailed = usesDetailedStoneRendering(at: cellSize)
            let padded = appearance.gridStyle.usesPaddedCells(at: cellSize)
            let feltRadius = padded ? min(12, cellSize * 0.24) : 0
            let faceRadius = max(cornerRadius, detailed ? max(depthGeometry.cornerRadius, feltRadius) : 0)
            ZStack(alignment: .center) {
                if widgetRenderingMode == .fullColor {
                    appearance.surfaceColor(detailed: detailed)
                        .overlay {
                            if let texture = appearance.boardTexture {
                                BoardTextureImage(texture: texture, lifted: false, boardSize: geometry.size)
                                    .overlay {
                                        if appearance.boardBevel {
                                            // Lift the existing mineral detail only in the margin,
                                            // fading before the outer grid line half a cell in.
                                            let fade = 0.45 / (max(width, height) + (showsCoordinate ? 1 : 0))
                                            let stops: [Gradient.Stop] = [
                                                .init(color: .white.opacity(0.75), location: 0),
                                                .init(color: .clear, location: fade),
                                                .init(color: .clear, location: 1 - fade),
                                                .init(color: .white.opacity(0.75), location: 1)
                                            ]
                                            BoardTextureImage(texture: texture, lifted: true, boardSize: geometry.size)
                                                .mask {
                                                    LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
                                                        .overlay {
                                                            LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
                                                        }
                                                }
                                        }
                                    }
                                    .opacity(detailed ? 1 : 0)
                            }
                        }
                        .overlay {
                            if let reflection = appearance.boardReflection {
                                BoardReflectionView(reflection: reflection)
                                    .opacity(detailed ? 1 : 0)
                            }
                        }
                        .overlay {
                            if let frost = appearance.surfaceFrost {
                                BoardSurfaceOverlayView(surface: frost, cellSize: cellSize)
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: faceRadius, style: .circular))
                        .overlay {
                            ZStack {
                                if let edge = appearance.boardEdge {
                                    BoardBorder(start: edge, middle: edge, end: edge, width: 1)
                                        .opacity(detailed && (appearance.boardDepth != nil || padded) ? 0 : 1)
                                }
                                if appearance.gridStyle == .stitched {
                                    FeltBoardRim(cellSize: cellSize, cornerRadius: faceRadius, shade: appearance.gridColor)
                                        .equatable()
                                        .opacity(padded ? 1 : 0)
                                        .animation(nil, value: padded)
                                }
                                if appearance.boardBevel {
                                    Group {
                                        if let depth = appearance.boardDepth, depth.edgeStyle == .frosted {
                                            FrostedBoardEdge(material: depth, cellSize: depthGeometry.cellSize,
                                                             thickness: depthGeometry.thickness,
                                                             cornerRadius: faceRadius)
                                        } else {
                                            BoardBorder(start: appearance.boardDepth?.highlight ?? .white.opacity(0.18), middle: .clear,
                                                        end: appearance.boardDepth?.shade ?? .black.opacity(0.45),
                                                        width: appearance.boardDepth == nil ? 3 : min(2, depthGeometry.thickness * 0.35),
                                                        cornerRadius: appearance.boardDepth == nil ? 0 : faceRadius)
                                        }
                                    }
                                    .opacity(detailed ? 1 : 0)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: faceRadius, style: .circular))
                        }
                        // The board's shape casts the shadow, so the layers above
                        // are not drawn offscreen to find their outline.
                        .background {
                            if let depth = appearance.boardDepth {
                                ZStack {
                                    // Retain the solid backing at fractional-pixel
                                    // compact edges, where the face is antialiased.
                                    RoundedRectangle(cornerRadius: cornerRadius)
                                        .fill(appearance.surfaceColor(detailed: detailed))
                                        .opacity(detailed ? 0 : 1)
                                    BoardDepthView(material: depth, thickness: depthGeometry.thickness,
                                                   cornerRadius: faceRadius, shadowRadius: depthGeometry.shadowRadius,
                                                   shadowOffset: depthGeometry.shadowOffset)
                                        .opacity(detailed ? 1 : 0)
                                }
                            } else {
                                RoundedRectangle(cornerRadius: faceRadius)
                                    .fill(appearance.surfaceColor(detailed: detailed))
                                    .shadow(color: .black.opacity(detailed ? (appearance.boardBevel ? 0.55 : 0.33) : 0),
                                            radius: appearance.boardBevel ? 10 : 2,
                                            y: appearance.boardBevel ? 6 : 0)
                            }
                        }
                        .animation(nil, value: padded)
                } else {
                    Color.white.cornerRadius(cornerRadius).opacity(0.5)
                }
                gobanAndStones
                    .frame(width: gridSize.width, height: gridSize.height)
                    .offset(
                        x: showsCoordinate ? geometry.size.width / (width + 1) / 2 : 0,
                        y: showsCoordinate ? geometry.size.height / (height + 1) / 2 : 0
                    )
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = BoardDepthGeometry(
                containerSize: geometry.size,
                boardWidth: boardPosition.width, boardHeight: boardPosition.height, showsCoordinates: showsCoordinate,
                displayScale: displayScale,
                depth: widgetRenderingMode == .fullColor ? appearance.boardDepth : nil)
            GeometryReader { faceGeometry in
                boardFace(in: faceGeometry, depthGeometry: layout)
            }
            .frame(width: layout.faceRect.width, height: layout.faceRect.height)
            .position(x: layout.faceRect.midX, y: layout.faceRect.midY)
        }
        .onChange(of: boardTool.wrappedValue) { _, _ in
            hoveredPoint = nil
            isHoveredPointValid = nil
            newMove.wrappedValue = nil
            newPosition.wrappedValue = nil
        }
    }
}

#if DEBUG
#Preview("Analysis variation", traits: .fixedLayout(width: 375, height: 375)) {
    let game = TestData.EuropeanChampionshipWithChat
    let chatLine = game.chatLog[36]
    BoardView(
        boardPosition: chatLine.variation!.position,
        variation: chatLine.variation,
        showsCoordinate: true,
        highlightCoordinates: [[2, 2]]
    )
}

#Preview("Board markers", traits: .fixedLayout(width: 375, height: 375)) {
    let position = TestData.Resigned9x9Japanese.currentPosition
    BoardView(
        boardPosition: position,
        showsCoordinate: true,
        markups: .constant([
            BoardPoint(row: 2, column: 2): BoardMarkup(label: "A"),
            BoardPoint(row: 3, column: 3): BoardMarkup(shapes: [.triangle]),
            BoardPoint(row: 4, column: 4): BoardMarkup(shapes: [.square]),
            BoardPoint(row: 5, column: 5): BoardMarkup(shapes: [.circle]),
            BoardPoint(row: 6, column: 6): BoardMarkup(shapes: [.cross])
        ])
    )
}

#Preview("9×9 Undo request with coordinates", traits: .fixedLayout(width: 200, height: 200)) {
    let game = {
        let game = TestData.Resigned9x9Japanese
        game.undoRequest = OGSUndoRequest(
            moveNumber: game.currentPosition.lastMoveNumber,
            moveCount: 2
        )
        return game
    }()
    BoardView(
        boardPosition: game.currentPosition,
        showsCoordinate: true,
        undoRequestCoordinates: game.undoRequestCoordinates
    )
}

#Preview("Scored 19×19", traits: .fixedLayout(width: 500, height: 500)) {
    BoardView(boardPosition: TestData.Scored19x19Korean.currentPosition)
}

#Preview("Game card thumbnail", traits: .fixedLayout(width: 120, height: 120)) {
    BoardView(boardPosition: TestData.Scored19x19Korean.currentPosition)
}

#Preview("Compact handicap thumbnail", traits: .fixedLayout(width: 44, height: 44)) {
    BoardView(
        boardPosition: TestData.Resigned19x19HandicappedWithInitialState.currentPosition
    )
}
#endif
