import SwiftUI
import UIKit

enum NightGardenPaneRole: Hashable, CaseIterable {
    case clock, player

    func solid(_ color: StoneColor) -> Color {
        switch self {
        case .clock: return SurroundTheme.nightGarden.clockSolidSurface(color)
        case .player: return SurroundTheme.nightGarden.identityChipColors(color)[0]
        }
    }
}

enum NightGardenClockHighlight {
    case running, warning

    init?(active: Bool, warning: Bool) {
        guard active else { return nil }
        self = warning ? .warning : .running
    }
}

struct NightGardenPaneSurface: View {
    let color: StoneColor
    let role: NightGardenPaneRole
    var compact: Bool = false
    var highlight: NightGardenClockHighlight? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NightGardenPaneMaterial(color: color, role: role, colorScheme: colorScheme,
            showsDetail: contrast != .increased && !reduceTransparency, compact: compact, highlight: highlight)
            .overlay {
                if role == .clock, highlight == nil, contrast == .increased {
                    NightGardenPaneOutline(compact: compact)
                        .strokeBorder(SurroundTheme.nightGarden.clockForeground(color, scheme: colorScheme)
                            .opacity(0.5), lineWidth: 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// The generated glass has a quiet opaque center and a thin lower edge. Slicing
/// preserves its corner facets in both a full clock and a small identity chip.
/// All of its thickness belongs inside the control's existing reservation.
struct NightGardenPaneMaterial: View {
    let color: StoneColor
    let role: NightGardenPaneRole
    let colorScheme: ColorScheme
    let showsDetail: Bool
    var compact: Bool = false
    var highlight: NightGardenClockHighlight? = nil

    static let depthOutset: CGFloat = 0

    var body: some View {
        let outline = NightGardenPaneOutline(compact: compact)
        // Amethyst's pale generated reflections are blended over deep plum so
        // small warning/role labels stay readable even at a shoulder junction.
        outline.fill(showsDetail && color == .black
            ? SurroundTheme.nightGarden.clockSolidSurface(color) : role.solid(color))
            .overlay {
                if showsDetail, let image = NightGardenPaneTexture.image(color: color, compact: compact) {
                    Image(uiImage: image)
                        .resizable(capInsets: NightGardenPaneTexture.capInsets(compact: compact),
                                   resizingMode: .stretch)
                        .colorMultiply(Color(white: color == .black
                            ? (colorScheme == .dark ? 0.74 : 0.78)
                            : (colorScheme == .dark ? 0.90 : 1)))
                        .opacity(color == .black ? 0.6 : 1)
                        .overlay {
                            if color == .black {
                                Image(uiImage: image)
                                    .resizable(capInsets: NightGardenPaneTexture.capInsets(compact: compact),
                                               resizingMode: .stretch)
                                    .colorMultiply(Color(white: colorScheme == .dark ? 0.92 : 1))
                                    .mask { shoulderExposure }
                            }
                        }
                        .clipShape(outline)
                }
            }
            .overlay {
                if let highlight {
                    let theme = SurroundTheme.nightGarden
                    let bronze = highlight == .warning ? theme.clockSuddenDeathAccent(.white, scheme: colorScheme)
                                                       : theme.clockAccent(.white)
                    let glint = highlight == .warning ? theme.clockSuddenDeathAccent(.black, scheme: colorScheme)
                                                      : theme.clockAccent(.black)
                    let width: CGFloat = showsDetail && compact ? 3 : 3.5
                    outline.strokeBorder(bronze, lineWidth: width)
                        .overlay { outline.strokeBorder(glint, lineWidth: width * 0.45) }
                        .mask {
                            if showsDetail { cutCornerMask } else { Color.white }
                        }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Keep the light on the two cut ends of the pane. Its reach matches the
    /// fixed corner slices, even on a wide clock or a short Home chip.
    private var cutCornerMask: some View {
        GeometryReader { geometry in
            let slice = NightGardenPaneTexture.capInsets(compact: compact).leading
            let reach = min(0.5, slice / max(1, geometry.size.width))
            LinearGradient(stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: reach * 0.65),
                .init(color: .clear, location: reach),
                .init(color: .clear, location: 1 - reach),
                .init(color: .white, location: 1 - reach * 0.65),
                .init(color: .white, location: 1)
            ], startPoint: .leading, endPoint: .trailing)
        }
    }

    /// Reveal the original glass at the perimeter instead of flattening its
    /// reflection along with the face. The ramps finish before text padding;
    /// header identities may put names at a side, so keep their side gain off.
    private var shoulderExposure: some View {
        GeometryReader { geometry in
            let height = max(1, geometry.size.height)
            let width = max(1, geometry.size.width)
            let vertical = min(compact ? 2.0 : 3.0, height * 0.2)
            let horizontal = min(role == .clock ? 7.0 : (compact ? 0 : 3.0), width * 0.2)
            ZStack {
                LinearGradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: vertical * 0.45 / height),
                    .init(color: .clear, location: vertical / height),
                    .init(color: .clear, location: 1 - vertical / height),
                    .init(color: .white, location: 1 - vertical * 0.45 / height),
                    .init(color: .white, location: 1)
                ], startPoint: .top, endPoint: .bottom)
                if horizontal > 0 {
                    LinearGradient(stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: horizontal * 0.4 / width),
                        .init(color: .clear, location: horizontal / width),
                        .init(color: .clear, location: 1 - horizontal / width),
                        .init(color: .white, location: 1 - horizontal * 0.4 / width),
                        .init(color: .white, location: 1)
                    ], startPoint: .leading, endPoint: .trailing)
                }
            }
        }
    }
}

/// A small softened chamfer follows the glass without taking space from text.
/// Insets stay parallel and contained even for unusually short/narrow controls.
struct NightGardenPaneOutline: InsettableShape {
    var compact: Bool = false
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> NightGardenPaneOutline {
        var result = self
        result.insetAmount += amount
        return result
    }

    func path(in bounds: CGRect) -> Path {
        guard !bounds.isInfinite, bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0, insetAmount.isFinite else { return Path() }
        let inset = max(0, insetAmount)
        guard inset * 2 < min(bounds.width, bounds.height) else { return Path() }
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let outerCut = min(compact ? 5.0 : 8.0, min(bounds.width, bounds.height) * 0.22)
        let cut = max(0, outerCut - inset * (2 - sqrt(2)))
        let points = [
            CGPoint(x: rect.minX + cut, y: rect.minY), CGPoint(x: rect.maxX - cut, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY + cut), CGPoint(x: rect.maxX, y: rect.maxY - cut),
            CGPoint(x: rect.maxX - cut, y: rect.maxY), CGPoint(x: rect.minX + cut, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY - cut), CGPoint(x: rect.minX, y: rect.minY + cut)
        ]
        // Round the eight junctions without moving any point outside the chamfer.
        let softness = min(compact ? 1.5 : 2.5, cut * 0.4)
        func approach(_ vertex: CGPoint, from other: CGPoint) -> CGPoint {
            let distance = hypot(vertex.x - other.x, vertex.y - other.y)
            let fraction = distance > 0 ? min(0.45, softness / distance) : 0
            return CGPoint(x: vertex.x + (other.x - vertex.x) * fraction,
                           y: vertex.y + (other.y - vertex.y) * fraction)
        }
        return Path { path in
            path.move(to: approach(points[0], from: points[7]))
            for index in points.indices {
                let vertex = points[index]
                let next = points[(index + 1) % points.count]
                if index > 0 { path.addLine(to: approach(vertex, from: points[index - 1])) }
                path.addQuadCurve(to: approach(vertex, from: next), control: vertex)
            }
            path.closeSubpath()
        }
    }
}

/// Four lightweight UIImage wrappers share two decoded source images. Decoding
/// and image creation happen once, never on subsequent clock ticks.
@MainActor
enum NightGardenPaneTexture {
    private final class ResourceBundle {}
    private struct Key: Hashable { let black: Bool; let compact: Bool }
    private static var images: [Key: UIImage] = [:]
    private static var sources: [Bool: CGImage] = [:]

    static func capInsets(compact: Bool) -> EdgeInsets {
        let factor: CGFloat = compact ? 0.5 : 1
        return EdgeInsets(top: 12 * factor, leading: 34 * factor,
                          bottom: 12 * factor, trailing: 34 * factor)
    }

    static func image(color: StoneColor, compact: Bool = false) -> UIImage? {
        let key = Key(black: color == .black, compact: compact)
        if let image = images[key] { return image }
        let source: CGImage
        if let cached = sources[key.black] {
            source = cached
        } else {
            let name = key.black ? "NightGardenBlackPane" : "NightGardenWhitePane"
            guard let loaded = UIImage(named: name, in: Bundle(for: ResourceBundle.self),
                                       compatibleWith: nil)?.cgImage else { return nil }
            source = loaded
            sources[key.black] = source
        }
        let image = UIImage(cgImage: source, scale: compact ? 8 : 4, orientation: .up)
        images[key] = image
        return image
    }
}
