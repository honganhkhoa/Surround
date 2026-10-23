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

/// Boards and stones show detail only where it can be seen. Below a 14 pt
/// cell they are solid colors: the flat board color, a straight grid, and
/// flat stones with an optional solid outline; no images, textures,
/// gradients, reflections, bevels, shadows or tints. Detailed layers stay
/// mounted and only change color or opacity at the threshold, so a resizing
/// board never fades between two renderings.
func usesDetailedStoneRendering(at size: CGFloat) -> Bool {
    size >= 14
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
        highlightCasing: .white
    )

    func stones(_ color: StoneColor) -> StonePalette {
        color == .black ? black : white
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
