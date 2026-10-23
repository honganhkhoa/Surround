//
//  Stone.swift
//  Surround
//
//  Created by Anh Khoa Hong on 29/12/2020.
//

import SwiftUI

/// The colors of one player's stones and of the marks drawn on them.
struct StonePalette: Equatable {
    /// The lit side of a shaded stone.
    var highlight: Color
    /// The inner shadow that shapes a shaded stone.
    var shade: Color
    /// A stone below the detail threshold.
    var flat: Color
    /// A thin edge on flat stones.
    var outline: Color? = nil
    /// A thin edge on shaded stones.
    var rim: Color? = nil
    /// The last-move ring and pending-move cross.
    var lastMove: Color
    /// Move numbers, undo markers and markup on the stone.
    var label: Color
    /// Territory and estimate squares, when `flat` is too close to the board.
    var territory: Color? = nil
    /// A narrow, centered edge keeps marks separate from image reflections.
    /// Small solid stones use the palette alone.
    var detailedMarkerCasing: Color? = nil

    var territoryMark: Color { territory ?? flat }
}

/// Rendered stones: a few variants per player, so a full board does not
/// repeat one image. Every image follows the same contract: a straight-down
/// view with lighting matching `BoardAppearance.stoneLightDirection`, centered,
/// filling `footprint` of the square, opaque inside and transparent outside,
/// with no shadow or board baked in.
struct StoneImages: Equatable {
    var black: [UIImage]
    var white: [UIImage]
    var footprint: CGFloat = 0.94
    /// Scene lighting applied to the artwork, independently of game marks.
    var tint: Color = .white

    func variants(_ color: StoneColor) -> [UIImage] {
        color == .black ? black : white
    }

    /// A stable variant for a point, so stones keep their look as the game
    /// moves on and when the board redraws.
    static func variantIndex(row: Int, column: Int, count: Int) -> Int {
        guard count > 1 else { return 0 }
        var hash = UInt32(truncatingIfNeeded: row &* 92_821 &+ column &* 68_917)
        hash ^= hash >> 16
        hash &*= 0x7FEB_352D
        hash ^= hash >> 15
        return Int(hash % UInt32(count))
    }
}

/// Native shading and contact shadows follow the rendered stones' key light.
enum StoneLightDirection: Equatable {
    case upperLeft, upperRight

    var shadowXSign: CGFloat { self == .upperLeft ? 1 : -1 }
}

/// Detailed image stones can use a broader cast shadow over textured boards.
/// This does not affect standalone stones or the solid small-board rendering.
enum ImageStoneShadowStyle: Equatable {
    case contact
    case raised
}

/// A board surface, either a seamless fixed-size tile or one composition
/// scaled to cover the entire board without repeating within its bounds.
struct BoardTexture: Equatable {
    enum Mapping: Equatable {
        case tiled, board
    }

    var image: UIImage
    /// The tile's width in points; unused for a board-wide composition.
    var tileSize: CGFloat = 320
    var mapping: Mapping = .tiled
    /// Applied after image preparation, so changing appearance reuses the
    /// original texture and its cached margin without baking in old traits.
    var tint: Color = .white

    func paintScale(in size: CGSize) -> CGFloat {
        switch mapping {
        case .tiled:
            return tileSize / max(1, image.size.width)
        case .board:
            // Cover either aspect ratio with one image. A temporarily empty
            // layout slot still needs a positive, finite ImagePaint scale.
            return max(max(1, size.width) / max(1, image.size.width),
                       max(1, size.height) / max(1, image.size.height))
        }
    }
}

/// Light the polished board reflects: a broad sheen from the upper left,
/// where the stones are lit from, and faint starry specks within it.
struct BoardReflection: Equatable {
    var color: Color
    /// The sheen's opacity at the upper-left corner, partway across, and at
    /// its reach, which is a multiple of the board's longer side measured
    /// from just beyond the upper-left corner.
    var corner: Double
    var middle: Double
    var edge: Double
    var reach: CGFloat
    /// Fine specks per 10,000 square points, and soft glints per 10,000.
    var dustDensity: Double
    var glintDensity: Double
}

/// The material visible on a board's lower face, below the playing surface.
struct BoardDepth: Equatable {
    enum EdgeStyle: Equatable {
        case cut, frosted
    }

    var upperFace: Color
    var lowerFace: Color
    var highlight: Color
    var shade: Color
    var shadow: Color
    var thicknessRatio: CGFloat
    var maximumThickness: CGFloat
    var edgeStyle: EdgeStyle = .cut
}

/// Match the board's existing coordinate gutters, including rectangular boards.
/// Layout, detail eligibility and depth must all measure this same grid frame.
func boardGridSize(containerSize: CGSize, boardWidth: Int, boardHeight: Int, showsCoordinates: Bool) -> CGSize {
    guard showsCoordinates else { return containerSize }
    let width = CGFloat(max(1, boardWidth))
    let height = CGFloat(max(1, boardHeight))
    return CGSize(width: containerSize.width * width / (width + 1),
                  height: containerSize.width * height / (height + 1))
}

/// Fit a square-on board and its shallow sidewall into the same layout slot.
/// All drawing and hit testing use `faceRect`; only decoration uses the depth.
struct BoardDepthGeometry: Equatable {
    let faceRect: CGRect
    let thickness: CGFloat
    let cellSize: CGFloat
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let shadowOffset: CGFloat

    init(containerSize: CGSize, boardWidth: Int, boardHeight: Int, showsCoordinates: Bool,
         displayScale: CGFloat, depth: BoardDepth?) {
        let grid = boardGridSize(containerSize: containerSize, boardWidth: boardWidth,
                                 boardHeight: boardHeight, showsCoordinates: showsCoordinates)
        self.init(containerSize: containerSize,
                  proposedCellSize: min(grid.width, grid.height) / CGFloat(max(1, max(boardWidth, boardHeight))),
                  displayScale: displayScale, depth: depth)
    }

    private init(containerSize: CGSize, proposedCellSize: CGFloat, displayScale: CGFloat, depth: BoardDepth?) {
        let side = min(containerSize.width, containerSize.height)
        let scale = max(1, displayScale)
        let proposedCell = max(0, proposedCellSize)
        // Grow out of the flat footprint continuously. At the cutoff there
        // is no inset, so fitting depth cannot push a detailed cell below it.
        let growth = min(1, max(0, (proposedCell - 14) / 4))
        let thickness = depth.map { min($0.maximumThickness, max(0, side) * $0.thicknessRatio) * growth } ?? 0
        // Reserve three blur radii around the slab. Moving the face upward
        // by the shadow offset leaves the full fade below its lower edge.
        let shadowRadius = thickness * 0.3
        let shadowOffset = thickness * 0.2
        let reserve = thickness + 6 * shadowRadius
        let factor = side > 0 ? max(0, 1 - reserve / side) : 1
        let faceSize = CGSize(width: containerSize.width * factor, height: containerSize.height * factor)
        self.faceRect = CGRect(x: (containerSize.width - faceSize.width) / 2,
                               y: (containerSize.height - faceSize.height - thickness) / 2 - shadowOffset,
                               width: faceSize.width, height: faceSize.height)
        self.thickness = thickness
        self.cellSize = floor(proposedCell * factor * scale) / scale
        // Soft ice rounds within the half-cell margin; this changes only
        // the slab silhouette, never the grid frame or interaction geometry.
        self.cornerRadius = depth?.edgeStyle == .frosted
            ? min(thickness * 2.8, self.cellSize * 0.45)
            : min(thickness * 0.65, self.cellSize / 4)
        self.shadowRadius = shadowRadius
        self.shadowOffset = shadowOffset
    }
}

/// Boards and stones show detail only where it can be seen. Below a 14 pt
/// cell they are solid colors: the flat board color, a straight grid, and
/// flat stones with an optional solid outline; no images, textures,
/// gradients, reflections, bevels, shadows or tints. Detailed layers stay
/// mounted and only change color or opacity at the threshold, so a resizing
/// board never fades between two renderings.
func usesDetailedStoneRendering(at size: CGFloat) -> Bool {
    size >= 14
}

/// Marks fit the stone face, leaving its material and rim visible on phones.
/// Their center remains the grid intersection, independent of cast shadows.
struct StoneMarkerGeometry {
    var cellSize: CGFloat

    var stoneDiameter: CGFloat { cellSize - (cellSize < 10 ? 0 : 2) }
    var ringDiameter: CGFloat { stoneDiameter * 0.4 }
    var pendingDiameter: CGFloat { stoneDiameter * 0.48 }
    var shapeDiameter: CGFloat { stoneDiameter * 0.52 }
    /// Rings, pending crosses, annotation shapes and dame share one weight.
    var lineWidth: CGFloat { min(1.75, max(0.5, cellSize * 0.055)) }
    var actionDiameter: CGFloat { stoneDiameter * 0.5 }
    var actionLineWidth: CGFloat { min(2, max(0.6, cellSize * 0.065)) }
    var casingWidth: CGFloat { min(0.6, max(0.25, cellSize * 0.02)) }
    var scoreLineWidth: CGFloat { min(1.25, max(0.5, cellSize * 0.035)) }

    // Axis-aligned plus signs straddle pixel boundaries. Keep a solid core
    // and a distinct casing even on the smallest 2× thumbnails.
    func restoreLineWidth(displayScale: CGFloat) -> CGFloat {
        max(actionLineWidth, 2 / displayScale)
    }

    func restoreCasingWidth(displayScale: CGFloat) -> CGFloat {
        max(casingWidth, 1 / displayScale)
    }
}

/// Fit a single line to its point and outline the glyphs symmetrically.
/// Reusing one resolved glyph run avoids eight separate text layouts and
/// keeps the casing sharp, with no blur or directional shadow. Equatable, so
/// with `.equatable()` an unchanged label is not redrawn on board updates;
/// the casing pass runs only when a casing is given.
struct StoneMarkerText: View, Equatable {
    var text: String
    var systemImage: String? = nil
    var fontSize: CGFloat
    var foreground: Color
    var casing: Color? = nil
    var casingWidth: CGFloat = 0.4

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let line = text.components(separatedBy: .newlines).joined(separator: " ")
            let content = systemImage.map { Text(Image(systemName: $0)) } ?? Text(verbatim: line)
            var glyphs = context.resolve(content.font(.system(size: fontSize, weight: .bold)))
            let measured = glyphs.measure(in: CGSize(width: max(1, fontSize * CGFloat(line.count + 1)),
                                                    height: max(1, fontSize * 2)))
            let inset = casing == nil ? CGFloat.zero : casingWidth
            let scale = min(1, max(0.01, min((size.width - inset * 2) / max(1, measured.width),
                                            (size.height - inset * 2) / max(1, measured.height))))
            context.scaleBy(x: scale, y: scale)
            let center = CGPoint(x: size.width / (2 * scale), y: size.height / (2 * scale))
            if let casing {
                glyphs.shading = .color(casing)
                let distance = casingWidth / scale
                for step in 0..<8 {
                    let angle = Double(step) * .pi / 4
                    context.draw(glyphs, at: CGPoint(x: center.x + cos(angle) * distance,
                                                    y: center.y + sin(angle) * distance))
                }
            }
            glyphs.shading = .color(foreground)
            context.draw(glyphs, at: center)
        }
        .accessibilityLabel(Text(verbatim: text))
        .allowsHitTesting(false)
    }
}

enum BoardGridStyle: Equatable {
    case straight, ragged

    func usesRaggedEdges(at cellSize: CGFloat) -> Bool {
        self == .ragged && usesDetailedStoneRendering(at: cellSize)
    }
}

/// A straight grid with scratched edges. The sample pattern belongs to the
/// row/column and fractional cell, so resizing never reseeds the texture.
struct RaggedGridGeometry: Equatable {
    var width: Int
    var height: Int
    var cellSize: CGFloat
    var lineScale: CGFloat

    static let samplesPerCell = 20
    // Keep edge variation visible after native 2x/3x antialiasing; smaller
    // offsets make the scratched outline look straight at ordinary sizes.
    static let edgeVariation: CGFloat = 0.38

    var path: Path {
        guard width >= 2, height >= 2, cellSize >= 10,
              cellSize.isFinite, lineScale.isFinite, lineScale > 0 else { return Path() }
        var result = Path()
        for row in 0..<height {
            addLine(to: &result, line: row, cells: width - 1, vertical: false,
                    outer: row == 0 || row == height - 1)
        }
        for column in 0..<width {
            addLine(to: &result, line: column, cells: height - 1, vertical: true,
                    outer: column == 0 || column == width - 1)
        }
        return result
    }

    private func coreWidth(outer: Bool) -> CGFloat {
        max(0.5, (outer ? 1 : 0.5) * lineScale - 2 * Self.edgeVariation)
    }

    private func sampleHash(line: Int, sample: Int, vertical: Bool) -> UInt32 {
        var hash = UInt32(truncatingIfNeeded: line &* 92_821 &+ sample &* 68_917)
        hash ^= vertical ? 0xA341_316C : 0xC801_3EA4
        hash ^= hash >> 16
        hash &*= 0x7FEB_352D
        hash ^= hash >> 15
        return hash
    }

    private func addLine(to path: inout Path, line: Int, cells: Int, vertical: Bool, outer: Bool) {
        let sampleCount = cells * Self.samplesPerCell
        let center = (CGFloat(line) + 0.5) * cellSize
        let coreHalfWidth = coreWidth(outer: outer) / 2
        func point(along: CGFloat, offset: CGFloat) -> CGPoint {
            // Both axes wind the same way, so overlapping filled strips
            // cannot cancel each other at an intersection.
            vertical ? CGPoint(x: center - offset, y: along) : CGPoint(x: along, y: center + offset)
        }
        // A continuous spine guarantees intact intersections. Extending
        // the outer spines by half their width also closes all four corners.
        let start = cellSize / 2 - (outer ? coreHalfWidth : 0)
        let end = (CGFloat(cells) + 0.5) * cellSize + (outer ? coreHalfWidth : 0)
        path.move(to: point(along: start, offset: -coreHalfWidth))
        path.addLine(to: point(along: end, offset: -coreHalfWidth))
        path.addLine(to: point(along: end, offset: coreHalfWidth))
        path.addLine(to: point(along: start, offset: coreHalfWidth))
        path.closeSubpath()
        func edgePoint(_ sample: Int, side: CGFloat) -> CGPoint {
            let hash = sampleHash(line: line, sample: sample, vertical: vertical)
            let irregularity = (CGFloat(hash & 0xFFFF) / 65_535 * 2 - 1) * Self.edgeVariation
            let halfWidth = max(coreHalfWidth, (outer ? 0.5 : 0.25) * lineScale + irregularity)
            // Unequal short runs avoid regular teeth along the edge. The
            // endpoints remain exact and the sample order stays monotonic.
            let jitter = sample == 0 || sample == sampleCount ? 0 : (CGFloat(hash >> 16) / 65_535 - 0.5) * 0.6
            let along = (0.5 + (CGFloat(sample) + jitter) / CGFloat(Self.samplesPerCell)) * cellSize
            return point(along: along, offset: side * halfWidth)
        }
        path.move(to: edgePoint(0, side: -1))
        for sample in 1...sampleCount {
            path.addLine(to: edgePoint(sample, side: -1))
        }
        for sample in stride(from: sampleCount, through: 0, by: -1) {
            path.addLine(to: edgePoint(sample, side: 1))
        }
        path.closeSubpath()
    }
}

/// The board and stone colors shared by full boards and standalone stones.
/// A theme supplies its own; everything else keeps `.standard`.
struct BoardAppearance: Equatable {
    var boardColor: Color
    /// The solid board below the detail threshold, matching the detailed
    /// surface's overall tone; nil uses `boardColor`.
    var compactBoardColor: Color? = nil
    /// A thin edge around the board surface.
    var boardEdge: Color? = nil
    var boardTexture: BoardTexture? = nil
    /// A raised slab: light on the top-left edge, shade on the bottom-right.
    var boardBevel = false
    var boardDepth: BoardDepth? = nil
    var boardReflection: BoardReflection? = nil
    /// Scales the grid's line widths on detailed boards.
    var gridLineScale: CGFloat = 1
    /// Roughens only the line edges; intersections stay on the same grid.
    var gridStyle: BoardGridStyle = .straight
    /// Rendered stones for detailed sizes; the palettes still draw small
    /// boards, widgets and markers.
    var stoneImages: StoneImages? = nil
    var stoneLightDirection: StoneLightDirection = .upperLeft
    var imageStoneShadow: ImageStoneShadowStyle = .contact
    var gridColor: Color
    var coordinateColor: Color
    var black: StonePalette
    var white: StonePalette
    /// Markup on an empty point.
    var emptyPointMarker: Color
    /// The outline of territory squares and captured white stones.
    var markOutline: Color
    var dameColor: Color
    /// Coordinates highlighted from chat.
    var highlightColor: Color
    /// Contrasting edge for coordinate highlights over dark stones.
    var highlightCasing: Color? = nil
    /// The crosshair under a finger: a legal point, an illegal one, or
    /// stone removal. It runs beneath the stones.
    var crosshair = CrosshairColors()
    var crosshairWidth: CGFloat = 1
    /// Stone removal's marks over a group: remove (✕) and restore (+).
    var removeMark = Color(UIColor.systemRed)
    var restoreMark = Color(UIColor.systemGreen)
    /// A dark casing under the removal marks, so they read over light and
    /// dark stones alike; nil draws them bare.
    var removalMarkCasing: Color? = nil
    /// A dashed outline for dead stones, which otherwise fade into a dark
    /// board; nil leaves them translucent only.
    var removedStoneOutline: Color? = nil

    struct CrosshairColors: Equatable {
        var valid = Color(UIColor.systemGreen)
        var invalid = Color(UIColor.systemRed)
        var removal = Color(UIColor.systemTeal)
    }

    static let standard = BoardAppearance(
        boardColor: Color(red: 0.86, green: 0.69, blue: 0.42),
        gridColor: .black,
        coordinateColor: .black,
        black: StonePalette(
            highlight: Color(red: 0.6, green: 0.6, blue: 0.6),
            shade: .black,
            flat: .black,
            lastMove: .white,
            label: .white
        ),
        white: StonePalette(
            highlight: .white,
            shade: Color(red: 0.8, green: 0.8, blue: 0.8),
            flat: .white,
            outline: .gray,
            // Dark enough to read on white stones at thumbnail sizes too.
            lastMove: Color(white: 0.3),
            label: .black
        ),
        emptyPointMarker: .black,
        markOutline: Color(white: 0.3),
        // Fixed, deeper versions of indigo and blue that read on the wood;
        // a white casing carries the highlight over black stones.
        dameColor: Color(red: 0.27, green: 0.22, blue: 0.66),
        highlightColor: Color(red: 0, green: 0.3, blue: 0.85),
        highlightCasing: .white,
        crosshair: .init(valid: Color(red: 0.157, green: 0.408, blue: 0.302),
                         invalid: Color(red: 0.608, green: 0.204, blue: 0.216),
                         removal: Color(red: 0.157, green: 0.369, blue: 0.431)),
        crosshairWidth: 1.5,
        removeMark: Color(red: 0.608, green: 0.204, blue: 0.216),
        restoreMark: Color(red: 0.157, green: 0.408, blue: 0.302),
        removalMarkCasing: .white
    )

    func stones(_ color: StoneColor) -> StonePalette {
        color == .black ? black : white
    }

    /// Territory can cover a stone of the same color. Its contour must
    /// contrast with that stone instead of using the board's outline.
    func scoreMarkOutline(on stone: StoneColor?) -> Color {
        stone.map { stones($0).label } ?? markOutline
    }

    func textCasing(on stone: StoneColor?) -> Color? {
        guard let stone else { return nil }
        let palette = stones(stone)
        return palette.detailedMarkerCasing ?? (stone == .black ? palette.shade : palette.highlight)
    }

    /// The board's color under its detail, or alone below the threshold.
    func surfaceColor(detailed: Bool) -> Color {
        detailed ? boardColor : compactBoardColor ?? boardColor
    }
}

private struct BoardAppearanceKey: EnvironmentKey {
    static let defaultValue = BoardAppearance.standard
}

extension EnvironmentValues {
    var boardAppearance: BoardAppearance {
        get { self[BoardAppearanceKey.self] }
        set { self[BoardAppearanceKey.self] = newValue }
    }
}

struct Stone: View {
    @Environment(\.boardAppearance) private var appearance
    var color: StoneColor?
    var shadowRadius: CGFloat = 0.0

    var body: some View {
        GeometryReader { geometry -> AnyView in
            let size = geometry.size.width
            let shadowXSign = appearance.stoneLightDirection.shadowXSign
            let path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: size, height: size), transform: nil)
            return AnyView(erasing: Group {
                switch color {
                case .black, .white:
                    let palette = appearance.stones(color!)
                    if shadowRadius > 0, usesDetailedStoneRendering(at: size),
                       let images = appearance.stoneImages,
                       let image = images.variants(color!).first {
                        Image(uiImage: image)
                            .resizable()
                            .colorMultiply(images.tint)
                            .frame(width: size / images.footprint, height: size / images.footprint)
                            .frame(width: size, height: size)
                            .shadow(color: .black.opacity(0.35), radius: shadowRadius,
                                    x: shadowXSign * shadowRadius / 2, y: shadowRadius)
                    } else {
                        // Small stones stay flat, as on small boards.
                        let detailed = shadowRadius > 0 && usesDetailedStoneRendering(at: size)
                        ZStack {
                            if detailed {
                                Path(path).fill(
                                    palette.highlight
                                        .shadow(.inner(color: palette.shade, radius: size / 4,
                                                       x: -shadowXSign * size / 2.5, y: -size / 2.5))
                                ).shadow(radius: shadowRadius, x: shadowXSign * shadowRadius, y: shadowRadius)
                            } else {
                                Circle().fill(palette.flat)
                            }
                            if let edge = detailed ? palette.outline ?? palette.rim : palette.outline {
                                Circle().stroke(edge, lineWidth: 0.5)
                            }
                        }
                    }
                case .none:
                    ZStack {
                        if shadowRadius > 0 {
                            Path(path).fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [appearance.black.flat, appearance.white.flat]
                                    ),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            ).shadow(radius: shadowRadius, x: shadowXSign * shadowRadius, y: shadowRadius)
                        }
                        Text(verbatim: "?").font(Font.system(size: size / 1.5).bold()).foregroundColor(Color.white)
                        Circle().stroke(Color.gray, lineWidth: 0.5)
                    }
                }
            }.aspectRatio(1, contentMode: .fit)
            )
        }
    }
}

#if DEBUG
#Preview("Black with shadow", traits: .fixedLayout(width: 100, height: 50)) {
    Stone(color: .black, shadowRadius: 2)
        .frame(width: 25, height: 25)
}

#Preview("White with shadow", traits: .fixedLayout(width: 100, height: 50)) {
    Stone(color: .white, shadowRadius: 2)
        .frame(width: 25, height: 25)
}

#Preview("Empty intersection", traits: .fixedLayout(width: 100, height: 50)) {
    Stone(color: nil, shadowRadius: 2)
        .frame(width: 25, height: 25)
}

#Preview("Black with shadow — Dark", traits: .fixedLayout(width: 100, height: 50)) {
    ZStack {
        Rectangle().fill(Color(UIColor.systemGray5))
        Stone(color: .black, shadowRadius: 2)
            .frame(width: 25, height: 25)
    }
    .colorScheme(.dark)
}

#Preview("White with shadow — Dark", traits: .fixedLayout(width: 100, height: 50)) {
    ZStack {
        Rectangle().fill(Color(UIColor.systemGray5))
        Stone(color: .white, shadowRadius: 2)
            .frame(width: 25, height: 25)
    }
    .colorScheme(.dark)
}

#Preview("Black without shadow", traits: .fixedLayout(width: 100, height: 50)) {
    Stone(color: .black)
        .frame(width: 25, height: 25)
}

#Preview("White without shadow", traits: .fixedLayout(width: 100, height: 50)) {
    Stone(color: .white)
        .frame(width: 25, height: 25)
}
#endif
