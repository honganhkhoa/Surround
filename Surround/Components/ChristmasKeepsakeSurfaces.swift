import SwiftUI
import UIKit

private final class ChristmasOrnamentResources {}

enum ChristmasOrnamentRole: Hashable, CaseIterable {
    case clock, player

    func colors(_ color: StoneColor, scheme: ColorScheme) -> [Color] {
        let theme = SurroundTheme.christmasKeepsakes
        switch self {
        case .clock: return theme.clockSurfaceStops(color, scheme: scheme).map(\.color)
        case .player: return theme.identityChipColors(color)
        }
    }

    func solid(_ color: StoneColor) -> Color {
        let theme = SurroundTheme.christmasKeepsakes
        switch self {
        case .clock: return theme.clockSolidSurface(color)
        case .player: return theme.identityChipColors(color)[0]
        }
    }
}

struct ChristmasOrnamentSurface: View {
    let color: StoneColor
    let role: ChristmasOrnamentRole
    var compact: Bool = false
    var clockHighlight: ChristmasClockHolly? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ChristmasOrnamentMaterial(color: color, role: role, colorScheme: colorScheme,
                                  showsDetail: contrast != .increased && !reduceTransparency,
                                  compact: compact, clockHighlight: clockHighlight)
    }
}

/// A painted wooden plaque with an exposed natural edge. The real paint and
/// grain textures keep their point size; they never stretch with the control.
struct ChristmasOrnamentMaterial: View {
    let color: StoneColor
    let role: ChristmasOrnamentRole
    let colorScheme: ColorScheme
    let showsDetail: Bool
    var compact: Bool = false
    var clockHighlight: ChristmasClockHolly? = nil

    static let depthOutset: CGFloat = 7

    var body: some View {
        let paint = showsDetail ? ChristmasOrnamentTexture.image(kind: .paintedWood, color: color,
                                                                role: role, scheme: colorScheme) : nil
        let wood = showsDetail ? ChristmasOrnamentTexture.image(kind: .bareWood, color: color,
                                                               role: role, scheme: colorScheme) : nil
        let detailed = showsDetail && paint != nil && wood != nil
        let outline = ChristmasOrnamentOutline(role: role)
        outline.fill(role.solid(color))
            .overlay {
                GeometryReader { geometry in
                    let size = geometry.size
                    let allowance: CGFloat = clockHighlight == nil ? (compact ? 0 : Self.depthOutset)
                        : ChristmasClockHolly.canvasOutset + (compact ? 0 : 3)
                    Canvas { context, _ in
                        guard size.width > 8, size.height > 8 else { return }
                        context.translateBy(x: allowance, y: allowance)
                        let bounds = CGRect(origin: .zero, size: size)
                        let hasDepth = detailed && !compact
                        let woodBounds = hasDepth ? CGRect(x: -1, y: -1,
                            width: size.width + 2, height: size.height + 3.5) : bounds
                        let edge = outline.path(in: woodBounds)
                        if hasDepth {
                            context.drawLayer { contact in
                                contact.addFilter(.shadow(color: .black.opacity(0.3), radius: 0.6,
                                                          x: 0.35, y: 0.9, options: .shadowOnly))
                                contact.fill(edge, with: .color(.black))
                            }
                        }
                        if detailed, let paint, let wood {
                            let face = outline.inset(by: 2.4).path(in: bounds)
                            var material = context
                            material.clip(to: edge)
                            material.fill(edge, with: .tiledImage(Image(uiImage: wood)))
                            material.stroke(outline.inset(by: 0.45).path(in: woodBounds), with: .linearGradient(
                                Gradient(colors: [.white.opacity(0.38), .clear, .black.opacity(0.32)]),
                                startPoint: .zero, endPoint: CGPoint(x: size.width * 0.2, y: size.height + 2.5)),
                                lineWidth: 1)
                            material.fill(face, with: .tiledImage(Image(uiImage: paint)))
                            material.stroke(face, with: .linearGradient(
                                Gradient(colors: [OrnamentPigment.color(0xF3DEBB).opacity(0.82), .clear,
                                                  OrnamentPigment.color(0x765132).opacity(0.45)]),
                                startPoint: .zero, endPoint: CGPoint(x: size.width * 0.2, y: size.height)),
                                lineWidth: 0.55)
                        }
                        if role == .clock, let clockHighlight {
                            // Keep even resampled leaf edges outside the clock's text padding.
                            var corners = context
                            let text = bounds.insetBy(dx: 8, dy: 4)
                            if !text.isEmpty { corners.clip(to: Path(text), options: .inverse) }
                            clockHighlight.draw(in: corners, around: woodBounds, hasDepth: hasDepth,
                                                color: color, scheme: colorScheme, detailed: detailed)
                        }
                    }
                    .frame(width: size.width + allowance * 2, height: size.height + allowance * 2)
                    .clipped()
                    .offset(x: -allowance, y: -allowance)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

enum ChristmasClockHolly {
    case running, warning

    private static let maximumSide: CGFloat = 34
    // The corner extends at most a quarter of the artwork beyond the wood.
    fileprivate static let canvasOutset = ceil(maximumSide / 4)

    fileprivate func draw(in context: GraphicsContext, around wood: CGRect, hasDepth: Bool,
                          color: StoneColor, scheme: ColorScheme, detailed: Bool) {
        let name = self == .running ? "ChristmasKeepsakesGoldHollyCorner" : "ChristmasKeepsakesCopperHollyCorner"
        var sprig = context.resolve(Image(name, bundle: Bundle(for: ChristmasOrnamentResources.self))
            .renderingMode(detailed ? .original : .template)
            .interpolation(.high))
        if !detailed {
            let theme = SurroundTheme.christmasKeepsakes
            sprig.shading = .color(self == .warning ? theme.clockSuddenDeathAccent(color, scheme: scheme)
                                                   : theme.clockAccent(color))
        }

        // The selected 701 px plaque uses a 124 px corner tile. Short toolbar
        // clocks keep a visible sprig and an open stretch of rim between the tips.
        let side = min(hasDepth ? 32 : Self.maximumSide, max(20, wood.width * 124 / 701),
                       min(wood.width, wood.height) * 0.55)
        // The deeper wooden lips occupy 3.5 pt of the 8 pt gap between cards.
        // Seat those sprigs on the chamfer so the leaves fit in the remaining gap.
        let berry = hasDepth ? ChristmasOrnamentOutline.clockCornerCut(in: wood) / 2 - 0.5
                             : min(1.5, 4 - side * 0.1)
        let origin = berry - side / 4
        let frame = CGRect(x: origin, y: origin, width: side, height: side)
        for x: CGFloat in [1, -1] {
            for y: CGFloat in [1, -1] {
                var corner = context
                corner.translateBy(x: x > 0 ? wood.minX : wood.maxX, y: y > 0 ? wood.minY : wood.maxY)
                corner.scaleBy(x: x, y: y)
                corner.draw(sprig, in: frame)
                if !detailed {
                    let radius = side * 0.08
                    let fruit = CGRect(x: berry - radius, y: berry - radius, width: radius * 2, height: radius * 2)
                    corner.fill(Path(ellipseIn: fruit), with: .color(OrnamentPigment.color(0xA82036)))
                }
            }
        }
    }
}

/// Parallel insets are essential here: retaining the outer chamfer would put
/// the pale bevel under the compact column's 5 pt text reservation.
struct ChristmasOrnamentOutline: InsettableShape {
    let role: ChristmasOrnamentRole
    var insetAmount: CGFloat = 0

    static func clockCornerCut(in bounds: CGRect) -> CGFloat { min(6, bounds.height * 0.2) }

    func inset(by amount: CGFloat) -> ChristmasOrnamentOutline {
        var result = self
        result.insetAmount += amount
        return result
    }

    func path(in bounds: CGRect) -> Path {
        let outerCut: CGFloat = role == .clock ? Self.clockCornerCut(in: bounds) : 6
        let rect = bounds.insetBy(dx: insetAmount, dy: insetAmount)
        let cut = max(0, outerCut - insetAmount * (2 - sqrt(2)))
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
            path.closeSubpath()
        }
    }
}

/// At most ten 512-square opaque maps (~10 MiB): eight role/color/appearance
/// paints and two shared bare-wood maps. Source fields are capped at 256 square.
/// No filtering, decoding or allocation is performed on subsequent clock ticks.
@MainActor
enum ChristmasOrnamentTexture {
    enum Kind: Hashable, CaseIterable { case paintedWood, bareWood }
    private struct Key: Hashable {
        let kind: Kind
        let role: ChristmasOrnamentRole
        let black: Bool
        let dark: Bool
    }
    private static var images: [Key: UIImage] = [:]
    private static var fields: [Kind: [UInt8]] = [:]
    private static let sourceSide = 256
    private static let outputSide = 512

    static func image(kind: Kind, color: StoneColor, role: ChristmasOrnamentRole, scheme: ColorScheme) -> UIImage? {
        let key = Key(kind: kind, role: kind == .bareWood ? .clock : role,
                      black: kind == .paintedWood && color == .black, dark: scheme == .dark)
        if let image = images[key] { return image }
        guard let field = field(kind) else { return nil }
        let palette: [UIColor]
        if kind == .paintedWood {
            let traits = UITraitCollection(userInterfaceStyle: key.dark ? .dark : .light)
            palette = role.colors(color, scheme: scheme).map { UIColor($0).resolvedColor(with: traits) }
        } else {
            palette = key.dark ? [OrnamentPigment.uiColor(0xDAC29C), OrnamentPigment.uiColor(0xA77C50)]
                : [OrnamentPigment.uiColor(0xF2DDB7), OrnamentPigment.uiColor(0xB98D5A)]
        }
        guard let highColor = palette.first, let lowColor = palette.last else { return nil }
        let highlight = OrnamentPigment.channels(highColor)
        let shadow = OrnamentPigment.channels(lowColor)
        var histogram = [Int](repeating: 0, count: 256)
        for value in field { histogram[Int(value)] += 1 }
        func percentile(_ fraction: Double) -> CGFloat {
            let target = Int(Double(field.count) * fraction)
            var total = 0
            for value in histogram.indices {
                total += histogram[value]
                if total >= target { return CGFloat(value) / 255 }
            }
            return 1
        }
        let low = percentile(0.02), high = percentile(0.98)
        let range = max(0.04, high - low)
        let side = outputSide
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let sx = x < sourceSide ? x : side - 1 - x
                let sy = y < sourceSide ? y : side - 1 - y
                let relief = CGFloat(field[sy * sourceSide + sx]) / 255
                let normalized = min(1, max(0, (relief - low) / range))
                let amount = kind == .paintedWood ? 0.2 + 0.6 * normalized : normalized
                let offset = (y * side + x) * 4
                for channel in 0..<3 {
                    pixels[offset + channel] = UInt8(((shadow[channel] * (1 - amount)
                        + highlight[channel] * amount) * 255).rounded())
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cgImage = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: side * 4, space: space,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: true,
                                    intent: .defaultIntent) else { return nil }
        let repeatSize: CGFloat = kind == .paintedWood ? 320 : 256
        let image = UIImage(cgImage: cgImage, scale: CGFloat(side) / repeatSize, orientation: .up)
        images[key] = image
        return image
    }

    private static func field(_ kind: Kind) -> [UInt8]? {
        if let field = fields[kind] { return field }
        let name = kind == .paintedWood ? "ChristmasKeepsakesPaintedWood" : "ChristmasKeepsakesBareWood"
        guard let source = UIImage(named: name, in: Bundle(for: ChristmasOrnamentResources.self), compatibleWith: nil)?.cgImage else {
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: sourceSide * sourceSide)
        let succeeded = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: sourceSide, height: sourceSide,
                                          bitsPerComponent: 8, bytesPerRow: sourceSide,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(source, in: CGRect(x: 0, y: 0, width: sourceSide, height: sourceSide))
            return true
        }
        guard succeeded else { return nil }
        fields[kind] = bytes
        return bytes
    }
}

private enum OrnamentPigment {
    static func color(_ value: UInt32) -> Color { Color(uiColor: uiColor(value)) }

    static func uiColor(_ value: UInt32) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    static func channels(_ color: UIColor) -> [CGFloat] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue]
    }
}
