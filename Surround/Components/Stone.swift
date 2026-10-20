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
/// view lit from the upper left, centered, filling `footprint` of the square,
/// opaque inside and transparent outside, with no shadow or board baked in.
struct StoneImages: Equatable {
    var black: [UIImage]
    var white: [UIImage]
    var footprint: CGFloat = 0.94

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

/// A seamless surface tile repeated at a fixed size, whatever the board size.
struct BoardTexture: Equatable {
    var image: UIImage
    /// The tile's width in points.
    var tileSize: CGFloat
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

/// Image stones replace drawn ones only where their detail can be seen.
func usesDetailedStoneRendering(at size: CGFloat) -> Bool {
    size >= 14
}

/// The board and stone colors shared by full boards and standalone stones.
/// A theme supplies its own; everything else keeps `.standard`.
struct BoardAppearance: Equatable {
    var boardColor: Color
    /// A thin edge around the board surface.
    var boardEdge: Color? = nil
    var boardTexture: BoardTexture? = nil
    /// A raised slab: light on the top-left edge, shade on the bottom-right.
    var boardBevel = false
    var boardReflection: BoardReflection? = nil
    /// Scales the grid's line widths on detailed boards.
    var gridLineScale: CGFloat = 1
    /// Rendered stones for detailed sizes; the palettes still draw small
    /// boards, widgets and markers.
    var stoneImages: StoneImages? = nil
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
            lastMove: .gray,
            label: .black
        ),
        emptyPointMarker: .black,
        markOutline: .gray,
        dameColor: Color(UIColor.systemIndigo),
        highlightColor: Color(.systemBlue)
    )

    func stones(_ color: StoneColor) -> StonePalette {
        color == .black ? black : white
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
                            .frame(width: size / images.footprint, height: size / images.footprint)
                            .frame(width: size, height: size)
                            .shadow(color: .black.opacity(0.35), radius: shadowRadius,
                                    x: shadowRadius / 2, y: shadowRadius)
                    } else {
                        ZStack {
                            if shadowRadius > 0 {
                                Path(path).fill(
                                    palette.highlight
                                        .shadow(.inner(color: palette.shade, radius: size / 4, x: -size / 2.5, y: -size / 2.5))
                                ).shadow(radius: shadowRadius, x: shadowRadius, y: shadowRadius)
                            } else {
                                Circle().fill(palette.flat)
                            }
                            if let edge = palette.outline ?? palette.rim {
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
                            ).shadow(radius: shadowRadius, x: shadowRadius, y: shadowRadius)
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
