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

struct Goban: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.boardAppearance) private var appearance
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
            : (isHoveredPointValid ?? false) ? appearance.crosshair.valid : appearance.crosshair.invalid
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
                if appearance.gridStyle.usesRaggedEdges(at: size) {
                    RaggedGobanGrid(
                        geometry: RaggedGridGeometry(width: width, height: height,
                                                     cellSize: size, lineScale: appearance.gridLineScale),
                        color: appearance.gridColor
                    ).equatable()
                } else {
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
                    .stroke(appearance.gridColor, lineWidth: size < 10 ? 1 / displayScale : 0.5 * appearance.gridLineScale)
                    Path { path in
                        path.move(to: CGPoint(x: size / 2, y: size / 2))
                        path.addLine(to: CGPoint(x: (CGFloat(width) - 0.5) * size, y: size / 2))
                        path.addLine(to: CGPoint(x: (CGFloat(width) - 0.5) * size, y: (CGFloat(height) - 0.5) * size))
                        path.addLine(to: CGPoint(x: size / 2, y: (CGFloat(height) - 0.5) * size))
                        path.closeSubpath()
                    }.stroke(appearance.gridColor, lineWidth: size < 10 ? 0.5 : appearance.gridLineScale)
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
                if highlightedColumn >= 0 && highlightedColumn < width && highlightedRow >= 0 && highlightedRow < height {
                    Path { path in
                        path.move(to: CGPoint(x: size / 2, y: (CGFloat(highlightedRow) + 0.5) * size))
                        path.addLine(to: CGPoint(x: (CGFloat(width) - 0.5) * size, y:(CGFloat(highlightedRow) + 0.5) * size))

                        path.move(to: CGPoint(x: (CGFloat(highlightedColumn) + 0.5) * size, y: size / 2))
                        path.addLine(to: CGPoint(x: (CGFloat(highlightedColumn) + 0.5) * size, y: (CGFloat(height) - 0.5) * size))
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
    
    var body: some View {
        let labels = Array(variation.nonDuplicatingMoveCoordinatesByLabel.keys)
        
        return ZStack {
            ForEach(labels, id: \.self) { label -> AnyView in
                if let coordinate = variation.nonDuplicatingMoveCoordinatesByLabel[label] {
                    let stoneColor: StoneColor = variation.position[coordinate] == .hasStone(.black) ? .black : .white
                    let labelSize = cellSize >= 14 ? cellSize / 1.5 : cellSize
                    return AnyView(
                        Text(verbatim: "\(label)")
                            .font(.system(size: labelSize))
                            .bold()
                            .foregroundColor(appearance.stones(stoneColor).label)
                            .minimumScaleFactor(0.2)
                            .frame(width: labelSize, height: labelSize)
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

/// A border inside the board drawn as four edge strips, its colors running
/// from the top-left corner through the middle to the bottom-right one like
/// a diagonal gradient across the square board. A stroked outline, above all
/// a gradient one, is redrawn across the whole board on every frame of a
/// resize; strips cost only their own area.
private struct BoardBorder: View {
    let start: Color
    let middle: Color
    let end: Color
    let width: CGFloat

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [start, middle], startPoint: .leading, endPoint: .trailing)
                    .frame(height: width)
                Spacer(minLength: 0)
                LinearGradient(colors: [middle, end], startPoint: .leading, endPoint: .trailing)
                    .frame(height: width)
            }
            // The sides stop at the top and bottom strips, so the corners are
            // not covered twice.
            HStack(spacing: 0) {
                LinearGradient(colors: [start, middle], startPoint: .top, endPoint: .bottom)
                    .frame(width: width)
                Spacer(minLength: 0)
                LinearGradient(colors: [middle, end], startPoint: .top, endPoint: .bottom)
                    .frame(width: width)
            }
            .padding(.vertical, width)
        }
        .allowsHitTesting(false)
    }
}

private struct ImageStone {
    var rect: CGRect
    var color: StoneColor
    var isRemoved: Bool
    var variant: Int
}

/// Rendered stones in one Canvas, so a full board is a few dozen image draws
/// rather than a view per stone. One blurred layer holds every contact
/// shadow, under all stones, following the images' key-light direction.
private struct ImageStoneCanvas: View {
    var stones: [ImageStone]
    var images: StoneImages?
    var cellSize: CGFloat
    var lightDirection: StoneLightDirection
    private let overhang: CGFloat = 6

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, _ in
            guard let images, !stones.isEmpty else { return }
            context.translateBy(x: overhang, y: overhang)
            let black = images.black.map { context.resolve(Image(uiImage: $0).interpolation(.high)) }
            let white = images.white.map { context.resolve(Image(uiImage: $0).interpolation(.high)) }

            let offset = CGSize(width: lightDirection.shadowXSign * cellSize * 0.03, height: cellSize * 0.06)
            context.drawLayer { shadows in
                shadows.addFilter(.blur(radius: max(1, cellSize * 0.06)))
                var path = Path()
                for stone in stones where !stone.isRemoved {
                    path.addEllipse(in: stone.rect.offsetBy(dx: offset.width, dy: offset.height).insetBy(dx: 0.5, dy: 0.5))
                }
                shadows.fill(path, with: .color(.black.opacity(0.5)))
            }

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
}

struct Stones: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.boardAppearance) private var appearance
    @ObservedObject var boardPosition: BoardPosition
    var variation: Variation?
    var geometry: GeometryProxy
    var isLastMovePending = false
    var undoRequestCoordinates: [[Int]] = []

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

        let drawsShadow = usesDetailedStoneRendering(at: size)
        let shadowXSign = appearance.stoneLightDirection.shadowXSign
        let shadowOffset: CGFloat = size > 30 ? 2 : 1
        let stoneImages = drawsShadow ? appearance.stoneImages : nil
        var imageStones = [ImageStone]()
        
        let whitePaths = [CGMutablePath(), CGMutablePath(), CGMutablePath(), CGMutablePath()]
        let blackPaths = [CGMutablePath(), CGMutablePath(), CGMutablePath(), CGMutablePath()]

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
                                                              count: stoneImages.variants(stoneColor).count)
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
            }
        }
        
        let lastMoveIndicatorWidth: CGFloat = size >= 20 ? 2 : (size > 10 ? 1 : 0.5)
        let undoMarkerCoordinates = undoRequestCoordinates.filter { coordinate in
            guard coordinate.count == 2 else {
                return false
            }
            let row = coordinate[0]
            let column = coordinate[1]
            guard row >= 0, row < height, column >= 0, column < width else {
                return false
            }
            if case .hasStone = boardPosition[row, column] {
                return true
            }
            return false
        }
        
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
                .shadow(color: dropShadow, radius: 2, x: shadowXSign * shadowOffset, y: shadowOffset)
            }
            Path(whiteLivingPath).stroke(edge(white), lineWidth: 0.5)
            ForEach(blackPaths.indices, id: \.self) { index in
                Path(blackPaths[index]).fill(fill(black))
                .shadow(color: dropShadow, radius: 2, x: shadowXSign * shadowOffset, y: shadowOffset)
            }
            Path(blackLivingPath).stroke(edge(black), lineWidth: drawsShadow ? 0.75 : 0.5)
            ImageStoneCanvas(stones: imageStones, images: stoneImages, cellSize: size,
                             lightDirection: appearance.stoneLightDirection)
            
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
                VariationNumberings(variation: variation, cellSize: size)
            } else if case .placeStone(let lastRow, let lastColumn) = boardPosition.lastMove {
                if case .hasStone(let lastColor) = boardPosition[lastRow, lastColumn] {
                    if boardPosition.estimatedScores == nil
                        && !undoMarkerCoordinates.contains([lastRow, lastColumn]) {
                        if isLastMovePending {
                            Path { path in
                                let centerX = CGFloat(lastColumn) * size + size / 2
                                let centerY = CGFloat(lastRow) * size + size / 2
                                path.move(to: CGPoint(x: centerX - size / 4, y: centerY))
                                path.addLine(to: CGPoint(x: centerX + size / 4, y: centerY))
                                path.move(to: CGPoint(x: centerX, y: centerY - size / 4))
                                path.addLine(to: CGPoint(x: centerX, y: centerY + size / 4))
                            }
                            .stroke(appearance.stones(lastColor).lastMove, lineWidth: lastMoveIndicatorWidth)
                        } else {
                            Path { path in
                                path.addEllipse(in: CGRect(
                                                    x: CGFloat(lastColumn) * size + size / 4,
                                                    y: CGFloat(lastRow) * size + size / 4,
                                                    width: size / 2,
                                                    height: size / 2))
                            }
                            .stroke(appearance.stones(lastColor).lastMove, lineWidth: lastMoveIndicatorWidth)
                        }
                    }
                }
            }

            if indicatorMode == .positionIndicators {
                ForEach(Array(undoMarkerCoordinates.enumerated()), id: \.offset) { _, coordinate in
                    let row = coordinate[0]
                    let column = coordinate[1]
                    if case .hasStone(let stoneColor) = boardPosition[row, column] {
                        Text(verbatim: "↶")
                            .font(.system(size: size * 0.65, weight: .bold))
                            .foregroundColor(appearance.stones(stoneColor).label)
                            .minimumScaleFactor(0.2)
                            .frame(width: size, height: size)
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
                Path(dameIndicator).stroke(appearance.dameColor, lineWidth: lastMoveIndicatorWidth)
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
        }
        .frame(width: size * CGFloat(width), height: size * CGFloat(height))
    }
}

struct StoneRemovalOverlay: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.boardAppearance) private var appearance
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

        let toBeRemovedPath = CGMutablePath()
        let toBeAddedPath = CGMutablePath()
        
        for point in hoveredGroup {
            let row = point[0]
            let column = point[1]
            
            let indicatorRectSize = max(size / 2, 3)
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
        let indicatorWidth: CGFloat = size >= 20 ? 2.5 : (size > 10 ? 2 : 1)
        
        let casing = appearance.removalMarkCasing ?? .clear
        let casingStyle = StrokeStyle(lineWidth: indicatorWidth + 2, lineCap: .round)
        return ZStack {
            Color.clear
            Path(toBeRemovedPath).stroke(casing, style: casingStyle)
            Path(toBeAddedPath).stroke(casing, style: casingStyle)
            Path(toBeRemovedPath).stroke(appearance.removeMark, lineWidth: indicatorWidth)
            Path(toBeAddedPath).stroke(appearance.restoreMark, lineWidth: indicatorWidth)
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
        let highlightWidth: CGFloat = size >= 20 ? 3 : (size > 10 ? 2 : 1)

        for coordinate in highlightCoordinates {
            let row = boardPosition.height - coordinate[0] - 1
            let column = coordinate[1]

            let highlightRectSize = size / 1.5
            let highlightRectPadding = (size - highlightRectSize) / 2
            let highlightRect = CGRect(
                x: CGFloat(column) * size + highlightRectPadding,
                y: CGFloat(row) * size + highlightRectPadding,
                width: highlightRectSize,
                height: highlightRectSize)
            
            highlightedCoordinatesPath.move(to: CGPoint(x: highlightRect.midX, y: highlightRect.minY))
            highlightedCoordinatesPath.addLine(to: CGPoint(x: highlightRect.midX - highlightRect.width * 0.433, y: highlightRect.maxY - highlightRect.height / 4))
            highlightedCoordinatesPath.addLine(to: CGPoint(x: highlightRect.midX + highlightRect.width * 0.433, y: highlightRect.maxY - highlightRect.height / 4))
            highlightedCoordinatesPath.addLine(to: CGPoint(x: highlightRect.midX, y: highlightRect.minY))
        }
        
        return ZStack {
            if let casing = appearance.highlightCasing {
                Path(highlightedCoordinatesPath)
                    .stroke(casing, lineWidth: highlightWidth + 2)
            }
            Path(highlightedCoordinatesPath)
                .stroke(appearance.highlightColor, lineWidth: highlightWidth)
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

        ZStack {
            ForEach(markups.keys.sorted(), id: \.self) { point in
                if point.row >= 0,
                   point.row < boardPosition.height,
                   point.column >= 0,
                   point.column < boardPosition.width,
                   let markup = markups[point] {
                    let foreground = markerColor(at: point)
                    ZStack {
                        if boardPosition[point.row, point.column] == .empty {
                            Circle()
                                .fill(emptyPointBackground)
                                .frame(width: size * 0.62, height: size * 0.62)
                        }
                        ForEach(BoardMarkShape.allCases, id: \.self) { shape in
                            if markup.shapes.contains(shape) {
                                BoardMarkShapeView(shape: shape)
                                    .stroke(
                                        foreground,
                                        style: StrokeStyle(
                                            lineWidth: max(1 / displayScale, size * 0.09),
                                            lineCap: .round,
                                            lineJoin: .round
                                        )
                                    )
                                    .frame(width: size * 0.58, height: size * 0.58)
                            }
                        }
                        if let label = markup.label {
                            Text(verbatim: label)
                                .font(.system(size: size * 0.55, weight: .bold))
                                .minimumScaleFactor(0.35)
                                .foregroundStyle(foreground)
                                .frame(width: size * 0.75, height: size * 0.75)
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

    private var emptyPointBackground: Color {
        widgetRenderingMode == .fullColor
            ? appearance.boardColor
            : Color.white.opacity(0.8)
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
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
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

struct BoardView: View {
    @Environment(\.boardAppearance) private var appearance
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
        return GeometryReader { boardGeometry in
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
                    isLastMovePending: newMove.wrappedValue != nil,
                    undoRequestCoordinates: undoRequestCoordinates
                )
                BoardMarkupOverlay(
                    boardPosition: boardPosition,
                    markups: markups.wrappedValue,
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
        }
    }
    
    var body: some View {
        let width: CGFloat = CGFloat(boardPosition.width)
        let height: CGFloat = CGFloat(boardPosition.height)
        return GeometryReader { geometry in
            ZStack(alignment: .center) {
                if widgetRenderingMode == .fullColor {
                    appearance.boardColor
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
                            }
                        }
                        .overlay {
                            if let reflection = appearance.boardReflection {
                                BoardReflectionView(reflection: reflection)
                            }
                        }
                        .cornerRadius(cornerRadius)
                        .overlay {
                            ZStack {
                                if let edge = appearance.boardEdge {
                                    BoardBorder(start: edge, middle: edge, end: edge, width: 1)
                                }
                                if appearance.boardBevel {
                                    BoardBorder(start: .white.opacity(0.18), middle: .clear,
                                                end: .black.opacity(0.45), width: 3)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                        }
                        // The board's shape casts the shadow, so the layers above
                        // are not drawn offscreen to find their outline.
                        .background {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(appearance.boardColor)
                                .shadow(color: .black.opacity(appearance.boardBevel ? 0.55 : 0.33),
                                        radius: appearance.boardBevel ? 10 : 2,
                                        y: appearance.boardBevel ? 6 : 0)
                        }
                } else {
                    Color.white.cornerRadius(cornerRadius).opacity(0.5)
                }
                gobanAndStones
                    .frame(
                        width: showsCoordinate ? geometry.size.width * width / (width + 1) : geometry.size.width,
                        height: showsCoordinate ? geometry.size.width * height / (height + 1) : geometry.size.height
                    )
                    .offset(
                        x: showsCoordinate ? geometry.size.width / (width + 1) / 2 : 0,
                        y: showsCoordinate ? geometry.size.height / (height + 1) / 2 : 0
                    )
            }
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
