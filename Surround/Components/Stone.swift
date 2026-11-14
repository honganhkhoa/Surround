//
//  Stone.swift
//  Surround
//
//  Created by Anh Khoa Hong on 29/12/2020.
//

import SwiftUI

/// Opted-in scenes keep their cast shadows off every board and its stones.
/// Bounds are resolved by the scene without feeding geometry back into layout.
struct BoardSceneShadowRegion: Equatable {
    var bounds: CGRect
    var cornerRadius: CGFloat = 0
}

struct BoardSceneShadowAnchor {
    let bounds: Anchor<CGRect>
    let cornerRadius: CGFloat
}

struct BoardSceneShadowExclusionKey: PreferenceKey {
    static let defaultValue: [BoardSceneShadowAnchor] = []

    static func reduce(value: inout [BoardSceneShadowAnchor], nextValue: () -> [BoardSceneShadowAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

private struct ExcludesBoardsFromSceneShadowsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var excludesBoardsFromSceneShadows: Bool {
        get { self[ExcludesBoardsFromSceneShadowsKey.self] }
        set { self[ExcludesBoardsFromSceneShadowsKey.self] = newValue }
    }
}

struct BoardSceneShadowExclusion: ViewModifier {
    @Environment(\.excludesBoardsFromSceneShadows) private var enabled
    var cornerRadius: CGFloat = 0

    func body(content: Content) -> some View {
        content.anchorPreference(key: BoardSceneShadowExclusionKey.self, value: .bounds) {
            enabled ? [BoardSceneShadowAnchor(bounds: $0, cornerRadius: cornerRadius)] : []
        }
    }
}

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
    /// Flat-stone contour width in points, shared by boards and standalone stones.
    var outlineWidth: CGFloat = 0.5
    /// Optional diameter where the contour starts growing, up to twice its base width.
    var outlineReferenceDiameter: CGFloat? = nil
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

    func flatOutlineWidth(forStoneDiameter diameter: CGFloat) -> CGFloat {
        guard let reference = outlineReferenceDiameter, reference > 0 else { return outlineWidth }
        return outlineWidth * min(2, max(1, diameter / reference))
    }
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
    /// Extra breathing room for detailed phone stones, independent of the
    /// source image's transparent margin. Large and solid stones keep their size.
    var smallStoneInset: CGFloat = 0
    /// Scene lighting applied to the artwork, independently of game marks.
    var tint: Color = .white
    /// Lift dark material facets without changing their black point, alpha,
    /// contact shadows or marks. One preserves the source artwork.
    var blackFaceGain: Double = 1
    /// Optional wool silhouettes, sampled once from the source alpha. Other
    /// materials keep their clean edges. Points follow each image variant.
    var blackFiberContours: [FeltFiberContour] = []
    var whiteFiberContours: [FeltFiberContour] = []

    func variants(_ color: StoneColor) -> [UIImage] {
        color == .black ? black : white
    }

    func displayRect(in rect: CGRect, cellSize: CGFloat) -> CGRect {
        guard cellSize.isFinite, usesDetailedStoneRendering(at: cellSize), smallStoneInset.isFinite,
              smallStoneInset > 0, rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0 else { return rect }
        // A normal board's stone is two points narrower than its cell.
        // Key the taper to the visible diameter so standalone previews agree.
        let growth = min(1, max(0, (cellSize - 14) / 2))
        let fade = min(1, max(0, (30 - rect.width) / 10))
        let inset = min(smallStoneInset * growth * fade, min(rect.width, rect.height) / 4)
        return rect.insetBy(dx: inset, dy: inset)
    }

    func fiberContour(_ color: StoneColor, variant: Int = 0) -> FeltFiberContour? {
        let contours = color == .black ? blackFiberContours : whiteFiberContours
        return contours.isEmpty ? nil : contours[variant % contours.count]
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
    /// Clear ice rests close to the polished surface with a gentle contact.
    case ice
    /// A firmer contact edge gives polished glass depth on dark enamel.
    case raisedGlass
    /// Cream glass needs a stronger white contact without a broader cast.
    case raisedIvoryGlass

    var usesRaisedGlassProfile: Bool { self == .raisedGlass || self == .raisedIvoryGlass }

    func contactOpacity(for color: StoneColor, cellSize: CGFloat) -> Double {
        guard cellSize.isFinite, usesDetailedStoneRendering(at: cellSize) else { return 0 }
        switch self {
        case .contact: return 0.5
        case .raised: return 0.32
        case .ice: return 0.26
        case .raisedGlass, .raisedIvoryGlass:
            let ivory = self == .raisedIvoryGlass && color == .white
            let large: CGFloat = ivory ? 0.6 : 0.5
            let phone: CGFloat = ivory ? 0.48 : 0.34
            let phoneWeight = min(1, max(0, (32 - cellSize) / 10))
            return Double(large + (phone - large) * phoneWeight)
        }
    }
}

/// A surface accent for artwork whose shallow shoulder is hard to separate
/// from its neighbors. Each material controls its own size response.
enum ImageStoneShading: Equatable {
    case artwork
    case clamshellShoulder
    case iceEdge
    case cranberryGlassEdge

    /// Reflected edge light stays on the surface and casts no extra shadow.
    var keepsAccentOutOfShadow: Bool { self == .iceEdge || self == .cranberryGlassEdge }

    func opacity(for color: StoneColor, cellSize: CGFloat, diameter: CGFloat) -> Double {
        guard cellSize.isFinite, diameter.isFinite,
              usesDetailedStoneRendering(at: cellSize), diameter > 0 else { return 0 }
        switch self {
        case .artwork:
            return 0
        case .clamshellShoulder:
            return color == .white ? 0.18 * Double(min(1, max(0, (32 - diameter) / 12))) : 0
        case .iceEdge:
            return 0.38 * Double(min(1, max(0, (32 - diameter) / 10)))
        case .cranberryGlassEdge:
            guard color == .black else { return 0 }
            // Dark glass still needs a readable shoulder in large groups;
            // retain a gentler reflection as the original art gains detail.
            return 0.48 - 0.14 * Double(min(1, max(0, (diameter - 22) / 22)))
        }
    }

    func draw(in context: GraphicsContext, rect: CGRect, color: StoneColor,
              cellSize: CGFloat, lightDirection: StoneLightDirection) {
        let strength = opacity(for: color, cellSize: cellSize, diameter: rect.width)
        guard strength > 0 else { return }
        if self == .cranberryGlassEdge {
            let width = min(1.2, max(0.65, rect.width * 0.035))
            // The glass artwork's shoulder sits slightly inside its nominal
            // circular footprint. Scale this clearance with the image so the
            // reflection never fills its transparent fringe on larger stones.
            let inset = width / 2 + max(0.3, rect.width * 0.024)
            let edge = Path(ellipseIn: rect.insetBy(dx: inset, dy: inset))
            let lit = CGPoint(x: lightDirection == .upperLeft ? rect.minX : rect.maxX, y: rect.minY)
            let shaded = CGPoint(x: lightDirection == .upperLeft ? rect.maxX : rect.minX, y: rect.maxY)
            let reflection = Color(red: 0.96, green: 0.57, blue: 0.59)
            // An asymmetric cranberry reflection follows the glass shoulder,
            // fading before the existing bright lower refraction. It stays
            // inside the silhouette and leaves the face beneath marks clear.
            context.stroke(edge, with: .linearGradient(Gradient(stops: [
                .init(color: reflection.opacity(strength), location: 0),
                .init(color: reflection.opacity(strength * 0.8), location: 0.35),
                .init(color: reflection.opacity(strength * 0.25), location: 0.65),
                .init(color: .clear, location: 0.9)
            ]), startPoint: lit, endPoint: shaded), lineWidth: width)
            return
        }
        if self == .iceEdge {
            // A narrow shoulder separates adjacent ice stones without
            // darkening their faces or broadening their contact shadows.
            // Pale ice keeps a shaded lower edge; midnight catches the key
            // light along its upper edge. Both stay inside the artwork.
            let edge = Path(ellipseIn: rect.insetBy(dx: 0.45, dy: 0.45))
            let lit = CGPoint(x: lightDirection == .upperLeft ? rect.minX : rect.maxX, y: rect.minY)
            let shaded = CGPoint(x: lightDirection == .upperLeft ? rect.maxX : rect.minX, y: rect.maxY)
            let colors: [Color] = color == .white
                ? [Color(red: 0.18, green: 0.34, blue: 0.47).opacity(strength * 0.55),
                   Color(red: 0.18, green: 0.34, blue: 0.47).opacity(strength)]
                : [Color(red: 0.48, green: 0.74, blue: 0.95).opacity(strength),
                   Color(red: 0.48, green: 0.74, blue: 0.95).opacity(strength * 0.45)]
            context.stroke(edge, with: .linearGradient(Gradient(colors: colors),
                                                       startPoint: lit, endPoint: shaded),
                           lineWidth: color == .white ? 0.5 : 0.65)
            return
        }
        let center = CGPoint(x: rect.minX + rect.width * (lightDirection == .upperLeft ? 0.34 : 0.66),
                             y: rect.minY + rect.height * 0.3)
        // The clear center keeps the ivory face and shell lines untouched.
        // Shade stays inside the silhouette and follows the artwork's light.
        context.fill(Path(ellipseIn: rect.insetBy(dx: 0.1, dy: 0.1)), with: .radialGradient(
            Gradient(stops: [.init(color: .clear, location: 0.5),
                             .init(color: .black.opacity(strength * 0.2), location: 0.72),
                             .init(color: .black.opacity(strength), location: 1)]),
            center: center, startRadius: 0, endRadius: rect.width * 0.76))
    }
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
    /// Blend busy material grain with the board's base pigment while keeping
    /// the original artwork and its separate surface deposits intact.
    var opacity: Double = 1

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

/// Hide the complete texture group below the detail threshold without
/// unmounting it or cross-fading when the board resizes.
struct BoardTextureVisibility: ViewModifier {
    var opacity: Double
    var cellSize: CGFloat

    func body(content: Content) -> some View {
        let detailed = usesDetailedStoneRendering(at: cellSize)
        content.opacity(detailed ? opacity : 0)
            .animation(nil, value: detailed)
    }
}

/// Transparent material resting on the whole board face. Stretching this
/// composition to the face retains every edge on rectangular boards.
struct BoardSurfaceOverlay: Equatable {
    var image: UIImage
    var opacity: Double = 1
    var tint: Color = .white
    /// Fade inward across this fraction of the shorter face dimension.
    /// Nil retains the complete artwork; a bounded rim keeps the field calm.
    var perimeterFadeFraction: CGFloat? = nil
}

/// The surface layer stays mounted across the detail threshold, without
/// changing the board's layout, interactions or accessibility tree.
struct BoardSurfaceOverlayView: View {
    var surface: BoardSurfaceOverlay
    var cellSize: CGFloat

    var body: some View {
        let detailed = usesDetailedStoneRendering(at: cellSize)
        Image(uiImage: surface.image)
            .resizable()
            .interpolation(.high)
            .colorMultiply(surface.tint)
            .mask {
                if let fraction = surface.perimeterFadeFraction {
                    Canvas { context, size in
                        let reach = min(size.width, size.height) * min(0.5, max(0, fraction))
                        guard fraction.isFinite, reach > 0, detailed else { return }
                        let fade = Gradient(colors: [.white, .clear])
                        func edge(_ rect: CGRect, from start: CGPoint, to end: CGPoint) {
                            context.fill(Path(rect), with: .linearGradient(fade, startPoint: start, endPoint: end))
                        }
                        edge(CGRect(x: 0, y: 0, width: size.width, height: reach),
                             from: .zero, to: CGPoint(x: 0, y: reach))
                        edge(CGRect(x: 0, y: size.height - reach, width: size.width, height: reach),
                             from: CGPoint(x: 0, y: size.height), to: CGPoint(x: 0, y: size.height - reach))
                        edge(CGRect(x: 0, y: 0, width: reach, height: size.height),
                             from: .zero, to: CGPoint(x: reach, y: 0))
                        edge(CGRect(x: size.width - reach, y: 0, width: reach, height: size.height),
                             from: CGPoint(x: size.width, y: 0), to: CGPoint(x: size.width - reach, y: 0))
                    }
                } else {
                    Color.white
                }
            }
            .opacity(detailed ? surface.opacity : 0)
            .animation(nil, value: detailed)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
        case cut, frosted, rolledTin
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

    /// The board as it is seen: its face and the sidewall below it, without
    /// the shadow's fade. Views that line up with the board follow this.
    var visibleRect: CGRect {
        CGRect(x: faceRect.minX, y: faceRect.minY, width: faceRect.width, height: faceRect.height + thickness)
    }
}

/// What BoardView gives BoardDepthGeometry, for a container that lines its
/// own views up with the board BoardView draws in a frame it is given.
struct BoardDepthPlacement: Equatable {
    var boardWidth: Int
    var boardHeight: Int
    var showsCoordinates: Bool
    var displayScale: CGFloat
    var depth: BoardDepth?

    /// The visible board inside `frame`, in the same coordinates; without
    /// depth that is the whole frame.
    func visibleBoard(in frame: CGRect) -> CGRect {
        guard depth != nil, frame.width > 0, frame.height > 0 else { return frame }
        return BoardDepthGeometry(containerSize: frame.size, boardWidth: boardWidth, boardHeight: boardHeight,
                                  showsCoordinates: showsCoordinates, displayScale: displayScale, depth: depth)
            .visibleRect.offsetBy(dx: frame.minX, dy: frame.minY)
    }
}

/// A row, the board and a row, top to bottom, as a VStack lays them out.
/// Where the board spans the column, the rows run edge to edge with the board
/// as drawn: a theme with depth draws it inset within its square.
struct BoardColumnLayout: Layout {
    /// Nil keeps the spacing a VStack would use between these views.
    var spacing: CGFloat?
    var board: BoardDepthPlacement

    /// The board's side and the rows' width in a column `width` wide, where
    /// the rows and spacing take `rows` points of an optional `height`.
    struct Column: Equatable {
        var side: CGFloat
        var rowWidth: CGFloat

        init(width: CGFloat, height: CGFloat?, rows: CGFloat, board: BoardDepthPlacement) {
            side = height.map { min(width, max(0, $0 - rows)) } ?? width
            // The rows meet the board's sides only where it spans the column.
            rowWidth = side < width ? width
                : board.visibleBoard(in: CGRect(x: 0, y: 0, width: side, height: side)).width
        }
    }

    private struct Arrangement {
        var column: Column
        var top: CGSize
        var bottom: CGSize
        var spacing: (CGFloat, CGFloat)
        /// A row that cannot shrink to the board widens the column, as in a VStack.
        var width: CGFloat
    }

    private func arrangement(_ proposal: ProposedViewSize, subviews: Subviews) -> Arrangement {
        let width = proposal.width ?? subviews[1].sizeThatFits(.unspecified).width
        let spacing = (self.spacing ?? subviews[0].spacing.distance(to: subviews[1].spacing, along: .vertical),
                       self.spacing ?? subviews[1].spacing.distance(to: subviews[2].spacing, along: .vertical))
        let full = ProposedViewSize(width: width, height: nil)
        var top = subviews[0].sizeThatFits(full)
        var bottom = subviews[2].sizeThatFits(full)
        let rows = top.height + bottom.height + spacing.0 + spacing.1
        let column = Column(width: width, height: proposal.height, rows: rows, board: board)
        if column.rowWidth != width {
            let drawn = ProposedViewSize(width: column.rowWidth, height: nil)
            top = subviews[0].sizeThatFits(drawn)
            bottom = subviews[2].sizeThatFits(drawn)
        }
        return Arrangement(column: column, top: top, bottom: bottom, spacing: spacing,
                           width: max(width, top.width, bottom.width))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let column = arrangement(proposal, subviews: subviews)
        let height = column.top.height + column.column.side + column.bottom.height + column.spacing.0 + column.spacing.1
        return CGSize(width: column.width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        // Measured as in sizeThatFits: a wide row makes the bounds wider than the board.
        let column = arrangement(proposal, subviews: subviews)
        let side = column.column.side
        let midX = bounds.midX
        let boardY = bounds.minY + column.top.height + column.spacing.0
        let rowWidth = column.column.rowWidth
        subviews[0].place(at: CGPoint(x: midX - column.top.width / 2, y: bounds.minY),
                          proposal: ProposedViewSize(width: rowWidth, height: column.top.height))
        subviews[1].place(at: CGPoint(x: midX - side / 2, y: boardY),
                          proposal: ProposedViewSize(width: side, height: side))
        subviews[2].place(at: CGPoint(x: midX - column.bottom.width / 2, y: boardY + side + column.spacing.1),
                          proposal: ProposedViewSize(width: rowWidth, height: column.bottom.height))
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
    case straight, ragged, stitched, engraved

    func usesEngraving(at cellSize: CGFloat) -> Bool {
        self == .engraved && usesDetailedStoneRendering(at: cellSize)
    }

    func usesRaggedEdges(at cellSize: CGFloat) -> Bool {
        self == .ragged && usesDetailedStoneRendering(at: cellSize)
    }

    func usesStitches(at cellSize: CGFloat) -> Bool {
        self == .stitched && usesDetailedStoneRendering(at: cellSize)
    }

    func usesPaddedCells(at cellSize: CGFloat) -> Bool {
        self == .stitched && usesDetailedStoneRendering(at: cellSize)
    }
}

/// The engraved core uses the same half-cell intersections as the plain
/// grid. Relief never changes the playing area, including rectangular boards.
struct EngravedGridGeometry: Equatable {
    var width: Int
    var height: Int
    var cellSize: CGFloat
    var lineScale: CGFloat = 1

    private var isValid: Bool {
        width >= 2 && height >= 2 && cellSize.isFinite && cellSize > 0
            && lineScale.isFinite && lineScale > 0
    }

    var gridRect: CGRect {
        guard isValid else { return .zero }
        return CGRect(x: cellSize / 2, y: cellSize / 2,
                      width: CGFloat(width - 1) * cellSize, height: CGFloat(height - 1) * cellSize)
    }

    var innerPath: Path {
        guard isValid else { return Path() }
        var path = Path()
        for row in 1..<(height - 1) {
            let y = (CGFloat(row) + 0.5) * cellSize
            path.move(to: CGPoint(x: gridRect.minX, y: y))
            path.addLine(to: CGPoint(x: gridRect.maxX, y: y))
        }
        for column in 1..<(width - 1) {
            let x = (CGFloat(column) + 0.5) * cellSize
            path.move(to: CGPoint(x: x, y: gridRect.minY))
            path.addLine(to: CGPoint(x: x, y: gridRect.maxY))
        }
        return path
    }

    var outlinePath: Path { isValid ? Path(gridRect) : Path() }

    /// Chipped lips share a straight, continuous spine. Their seeded edge
    /// variation stays attached to each row/cell as the board resizes.
    var chippedPath: Path {
        guard isValid else { return Path() }
        // Preserve the phone's facets and give larger ice cuts enough width
        // to read at tablet viewing distance. Seeded positions stay fixed.
        let largeBoardStrength = min(1, max(0, (cellSize - 22) / 18))
        return RaggedGridGeometry(width: width, height: height,
                                  cellSize: cellSize, lineScale: lineScale,
                                  edgeAmplitude: 0.7 + 0.4 * largeBoardStrength,
                                  edgeSamplesPerCell: 8, independentEdges: true).path
    }

    var starCenters: [CGPoint] {
        guard isValid, width == height else { return [] }
        let points: [(Int, Int)]
        switch width {
        case 19: points = [3, 9, 15].flatMap { row in [3, 9, 15].map { (row, $0) } }
        case 13: points = [(3, 3), (3, 9), (6, 6), (9, 3), (9, 9)]
        case 9: points = [(2, 2), (2, 6), (4, 4), (6, 2), (6, 6)]
        default: points = []
        }
        return points.map { CGPoint(x: (CGFloat($0.1) + 0.5) * cellSize,
                                    y: (CGFloat($0.0) + 0.5) * cellSize) }
    }

    var dimpleDiameter: CGFloat { min(5.5, max(4.5, cellSize * 0.26)) }
    /// A substantial opaque center stays distinct from a chipped crossing.
    var dimpleCoreDiameter: CGFloat { dimpleDiameter - 0.8 }
}

/// Rough ice-cut lips around a continuous pigment core. Relief stays in a
/// narrow strip along each cut, leaving the playing field and intersections clear.
struct EngravedGobanGrid: View, Equatable {
    var geometry: EngravedGridGeometry
    var color: Color

    var body: some View {
        Canvas { context, _ in
            guard usesDetailedStoneRendering(at: geometry.cellSize) else { return }
            let chips = geometry.chippedPath
            var upperWall = context
            upperWall.translateBy(x: -0.3, y: -0.3)
            upperWall.fill(chips, with: .color(color.opacity(0.3)))
            var lowerWall = context
            lowerWall.translateBy(x: 0.5, y: 0.5)
            lowerWall.fill(chips, with: .color(.white.opacity(0.52)))
            context.fill(chips, with: .color(color.opacity(0.64)))
            // The pigment is drawn last, so neither relief wall interrupts it.
            context.stroke(geometry.innerPath, with: .color(color), lineWidth: 0.45 * geometry.lineScale)
            context.stroke(geometry.outlinePath, with: .color(color), lineWidth: 0.7 * geometry.lineScale)
            for center in geometry.starCenters {
                let diameter = geometry.dimpleDiameter
                let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                                  width: diameter, height: diameter)
                context.fill(Path(ellipseIn: rect), with: .linearGradient(
                    Gradient(colors: [color.opacity(0.9), .white.opacity(0.8)]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                let lip = (diameter - geometry.dimpleCoreDiameter) / 2
                let core = Path(ellipseIn: rect.insetBy(dx: lip, dy: lip))
                context.fill(core, with: .color(color))
                // A deeper recess reads as a star even where several chipped
                // edges meet; keep its light-catching rim narrow.
                context.fill(core, with: .color(.black.opacity(0.28)))
            }
        }
        .animation(nil, value: usesDetailedStoneRendering(at: geometry.cellSize))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Relief belongs to the spaces between intersections, not to a fixed image
/// of a 19×19 board. Goban supplies its pixel-rounded cell size, including on
/// rectangular boards and boards with coordinate gutters.
struct FeltGridGeometry: Equatable {
    var width: Int
    var height: Int
    var cellSize: CGFloat

    private var isValid: Bool {
        width >= 2 && height >= 2 && cellSize.isFinite && cellSize > 0
    }

    var gridRect: CGRect {
        guard isValid else { return .zero }
        return CGRect(x: cellSize / 2, y: cellSize / 2,
                      width: CGFloat(width - 1) * cellSize, height: CGFloat(height - 1) * cellSize)
    }

    var seamWidth: CGFloat { isValid ? cellSize * 0.07 : 0 }
    var cellCornerRadius: CGFloat { isValid ? cellSize * 0.14 : 0 }

    var cellRects: [CGRect] {
        guard isValid else { return [] }
        return (0..<(height - 1)).flatMap { row in
            (0..<(width - 1)).map { column in
                CGRect(x: (CGFloat(column) + 0.5) * cellSize,
                       y: (CGFloat(row) + 0.5) * cellSize,
                       width: cellSize, height: cellSize)
                    .insetBy(dx: seamWidth / 2, dy: seamWidth / 2)
            }
        }
    }

    var path: Path {
        var result = Path()
        for rect in cellRects {
            result.addRoundedRect(in: rect, cornerSize: CGSize(width: cellCornerRadius, height: cellCornerRadius))
        }
        return result
    }
}

/// A short running stitch in each seam. Gentle variations belong to the
/// row/column, so resizing never reseeds the thread or moves an intersection.
struct StitchedGridGeometry: Equatable {
    var width: Int
    var height: Int
    var cellSize: CGFloat

    var path: Path {
        guard width >= 2, height >= 2, cellSize > 0, cellSize.isFinite else { return Path() }
        var result = Path()
        for row in 0..<height {
            let y = (CGFloat(row) + 0.5) * cellSize
            for column in 0..<(width - 1) {
                let seed = (row * 17 + column * 11) % 7
                let center = (CGFloat(column) + 1 + CGFloat(seed - 3) * 0.018) * cellSize
                let length = (0.14 + CGFloat(seed % 3) * 0.025) * cellSize
                result.move(to: CGPoint(x: center - length / 2, y: y))
                result.addQuadCurve(to: CGPoint(x: center + length / 2, y: y),
                                    control: CGPoint(x: center, y: y - cellSize * 0.035))
            }
        }
        for column in 0..<width {
            let x = (CGFloat(column) + 0.5) * cellSize
            for row in 0..<(height - 1) {
                let seed = (column * 13 + row * 19) % 7
                let center = (CGFloat(row) + 1 + CGFloat(seed - 3) * 0.018) * cellSize
                let length = (0.14 + CGFloat(seed % 3) * 0.025) * cellSize
                result.move(to: CGPoint(x: x, y: center - length / 2))
                result.addQuadCurve(to: CGPoint(x: x, y: center + length / 2),
                                    control: CGPoint(x: x - cellSize * 0.035, y: center))
            }
        }
        return result
    }
}

/// A straight grid with scratched edges. The sample pattern belongs to the
/// row/column and fractional cell, so resizing never reseeds the texture.
struct RaggedGridGeometry: Equatable {
    var width: Int
    var height: Int
    var cellSize: CGFloat
    var lineScale: CGFloat
    /// Defaults retain the scratched wood grid; ice opts into wider facets.
    var edgeAmplitude: CGFloat = RaggedGridGeometry.edgeVariation
    var edgeSamplesPerCell: Int = RaggedGridGeometry.samplesPerCell
    /// Independent ice fractures avoid matching, diamond-shaped width peaks.
    var independentEdges: Bool = false

    static let samplesPerCell = 20
    // Keep edge variation visible after native 2x/3x antialiasing; smaller
    // offsets make the scratched outline look straight at ordinary sizes.
    static let edgeVariation: CGFloat = 0.38

    var path: Path {
        guard width >= 2, height >= 2, cellSize >= 10,
              cellSize.isFinite, lineScale.isFinite, lineScale > 0,
              edgeAmplitude.isFinite, edgeAmplitude >= 0,
              (2...64).contains(edgeSamplesPerCell) else { return Path() }
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
        max(0.5, (outer ? 1 : 0.5) * lineScale - 2 * edgeAmplitude)
    }

    private func sampleHash(line: Int, sample: Int, vertical: Bool, positiveSide: Bool) -> UInt32 {
        var hash = UInt32(truncatingIfNeeded: line &* 92_821 &+ sample &* 68_917)
        hash ^= vertical ? 0xA341_316C : 0xC801_3EA4
        if independentEdges && positiveSide { hash ^= 0x9E37_79B9 }
        hash ^= hash >> 16
        hash &*= 0x7FEB_352D
        hash ^= hash >> 15
        return hash
    }

    private func addLine(to path: inout Path, line: Int, cells: Int, vertical: Bool, outer: Bool) {
        let sampleCount = cells * edgeSamplesPerCell
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
            let hash = sampleHash(line: line, sample: sample, vertical: vertical, positiveSide: side > 0)
            let irregularity = (CGFloat(hash & 0xFFFF) / 65_535 * 2 - 1) * edgeAmplitude
            let halfWidth = max(coreHalfWidth, (outer ? 0.5 : 0.25) * lineScale + irregularity)
            // Unequal short runs avoid regular teeth along the edge. The
            // endpoints remain exact and the sample order stays monotonic.
            let jitter = sample == 0 || sample == sampleCount ? 0 : (CGFloat(hash >> 16) / 65_535 - 0.5) * 0.6
            let along = (0.5 + (CGFloat(sample) + jitter) / CGFloat(edgeSamplesPerCell)) * cellSize
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
    /// Ink drawings stay flat at every size, including standalone previews.
    var usesShadedStones = true
    var castsBoardShadow = true
    var boardTexture: BoardTexture? = nil
    /// A raised slab: light on the top-left edge, shade on the bottom-right.
    var boardBevel = false
    var boardDepth: BoardDepth? = nil
    var boardReflection: BoardReflection? = nil
    /// Irregular surface frost below all grid lines, stones and game marks.
    var surfaceFrost: BoardSurfaceOverlay? = nil
    /// Scales the grid's line widths on detailed boards.
    var gridLineScale: CGFloat = 1
    /// Detailed grid treatment; intersections stay on the same grid.
    var gridStyle: BoardGridStyle = .straight
    var gridStitchColor: Color = .clear
    /// Rendered stones for detailed sizes; the palettes still draw small
    /// boards, widgets and markers.
    var stoneImages: StoneImages? = nil
    var stoneLightDirection: StoneLightDirection = .upperLeft
    var imageStoneShadow: ImageStoneShadowStyle = .contact
    var imageStoneShading: ImageStoneShading = .artwork
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
                    if appearance.usesShadedStones, shadowRadius > 0, usesDetailedStoneRendering(at: size),
                       let images = appearance.stoneImages,
                       let image = images.variants(color!).first {
                        let faceGain = color == .black ? images.blackFaceGain : 1
                        let imageSize = images.displayRect(in: CGRect(x: 0, y: 0, width: size, height: size),
                                                           cellSize: size).width
                        Image(uiImage: image)
                            .resizable()
                            // This pair multiplies RGB while retaining the
                            // black point; apply it before tint and shadows.
                            .brightness((1 - 1 / faceGain) / 2)
                            .contrast(faceGain)
                            .colorMultiply(images.tint)
                            .frame(width: imageSize / images.footprint, height: imageSize / images.footprint)
                            .frame(width: imageSize, height: imageSize)
                            // Reflected contours must not cast a blurred ring.
                            .shadow(color: .black.opacity(appearance.imageStoneShading.keepsAccentOutOfShadow ? 0.35 : 0), radius: shadowRadius,
                                    x: shadowXSign * shadowRadius / 2, y: shadowRadius)
                            .overlay {
                                if appearance.imageStoneShading != .artwork {
                                    Canvas { context, canvasSize in
                                        appearance.imageStoneShading.draw(in: context,
                                            rect: CGRect(origin: .zero, size: canvasSize), color: color!,
                                            cellSize: size, lightDirection: appearance.stoneLightDirection)
                                    }
                                    .colorMultiply(images.tint)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                                }
                            }
                            .shadow(color: .black.opacity(appearance.imageStoneShading.keepsAccentOutOfShadow ? 0 : 0.35), radius: shadowRadius,
                                    x: shadowXSign * shadowRadius / 2, y: shadowRadius)
                            .frame(width: size, height: size)
                    } else {
                        // Small stones stay flat, as on small boards.
                        let detailed = appearance.usesShadedStones && shadowRadius > 0 && usesDetailedStoneRendering(at: size)
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
                                Circle().stroke(edge, lineWidth: detailed ? 0.5 : palette.flatOutlineWidth(forStoneDiameter: size))
                            }
                        }
                    }
                case .none:
                    ZStack {
                        if appearance.usesShadedStones && shadowRadius > 0 && usesDetailedStoneRendering(at: size) {
                            Path(path).fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [appearance.black.flat, appearance.white.flat]
                                    ),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            ).shadow(radius: shadowRadius, x: shadowXSign * shadowRadius, y: shadowRadius)
                        } else {
                            Circle().fill(appearance.black.flat)
                        }
                        Text(verbatim: "?").font(Font.system(size: size / 1.5).bold()).foregroundColor(Color.white)
                        Circle().stroke(Color.gray, lineWidth: 0.5)
                    }
                }
            }.aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let color, let images = appearance.stoneImages,
                       let contour = images.fiberContour(color) {
                        FeltStoneFringe(contour: contour, footprint: images.footprint,
                                        palette: appearance.stones(color))
                            .colorMultiply(images.tint)
                            .opacity(appearance.usesShadedStones && shadowRadius > 0 && usesDetailedStoneRendering(at: size) ? 1 : 0)
                            .animation(nil, value: usesDetailedStoneRendering(at: size))
                    }
                }
            )
        }
    }
}

/// Mounted even when a standalone stone becomes small and solid. Decoration
/// can overhang its face without changing the stone's layout or hit region.
private struct FeltStoneFringe: View {
    let contour: FeltFiberContour
    let footprint: CGFloat
    let palette: StonePalette

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: CGPoint(x: 2, y: 2),
                              size: CGSize(width: size.width - 4, height: size.height - 4))
            let fibers = FeltEdgeFibers.stone(contour: contour, in: rect, footprint: footprint)
            context.stroke(fibers.body, with: .color(palette.shade.opacity(0.65)),
                           style: StrokeStyle(lineWidth: 0.3, lineCap: .round))
            context.stroke(fibers.wisps, with: .color(palette.highlight.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 0.22, lineCap: .round))
        }
        .padding(-2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
