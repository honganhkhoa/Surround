import SwiftUI
import UIKit

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

enum ChristmasOrnamentAttachment: Hashable, CaseIterable { case leading, trailing, none }

struct ChristmasOrnamentSurface: View {
    let color: StoneColor
    let role: ChristmasOrnamentRole
    let attachment: ChristmasOrnamentAttachment
    let showsDecoration: Bool
    var compact: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ChristmasOrnamentMaterial(color: color, role: role, attachment: attachment,
                                  showsDecoration: showsDecoration, colorScheme: colorScheme,
                                  showsDetail: contrast != .increased && !reduceTransparency,
                                  compact: compact)
    }
}

/// A painted wooden plaque with an exposed natural edge. The real paint and
/// grain textures keep their point size; they never stretch with the control.
struct ChristmasOrnamentMaterial: View {
    let color: StoneColor
    let role: ChristmasOrnamentRole
    let attachment: ChristmasOrnamentAttachment
    let showsDecoration: Bool
    let colorScheme: ColorScheme
    let showsDetail: Bool
    var compact: Bool = false

    static let decorationOutset: CGFloat = 7

    private var decorationAlignment: Alignment {
        if role == .clock { return attachment == .trailing ? .topTrailing : .topLeading }
        return attachment == .trailing ? .trailing : .leading
    }

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
                    let allowance: CGFloat = compact ? 0 : Self.decorationOutset
                    Canvas { context, _ in
                        guard detailed, let paint, let wood, size.width > 8, size.height > 8 else { return }
                        context.translateBy(x: allowance, y: allowance)
                        let bounds = CGRect(origin: .zero, size: size)
                        let woodBounds = compact ? bounds : CGRect(x: -1, y: -1,
                            width: size.width + 2, height: size.height + 3.5)
                        let edge = outline.path(in: woodBounds)
                        // The paint footprint and all text reservations stay
                        // exactly where they were; thickness grows outward.
                        let face = outline.inset(by: 2.4).path(in: bounds)
                        if !compact {
                            context.drawLayer { contact in
                                contact.addFilter(.shadow(color: .black.opacity(0.3), radius: 0.6,
                                                          x: 0.35, y: 0.9, options: .shadowOnly))
                                contact.fill(edge, with: .color(.black))
                            }
                        }
                        context.clip(to: edge)
                        context.fill(edge, with: .tiledImage(Image(uiImage: wood)))
                        context.stroke(outline.inset(by: 0.45).path(in: woodBounds), with: .linearGradient(
                            Gradient(colors: [.white.opacity(0.38), .clear, .black.opacity(0.32)]),
                            startPoint: .zero, endPoint: CGPoint(x: size.width * 0.2, y: size.height + 2.5)),
                            lineWidth: 1)
                        context.fill(face, with: .tiledImage(Image(uiImage: paint)))
                        context.stroke(face, with: .linearGradient(
                            Gradient(colors: [OrnamentPigment.color(0xF3DEBB).opacity(0.82), .clear,
                                              OrnamentPigment.color(0x765132).opacity(0.45)]),
                            startPoint: .zero, endPoint: CGPoint(x: size.width * 0.2, y: size.height)),
                            lineWidth: 0.55)
                    }
                    .frame(width: size.width + allowance * 2, height: size.height + allowance * 2)
                    .clipped()
                    .offset(x: -allowance, y: -allowance)
                }
            }
            .overlay(alignment: decorationAlignment) {
                if detailed && showsDecoration && !compact && attachment != .none, let wood {
                    if role == .clock {
                        ChristmasOrnamentClockCord(dark: colorScheme == .dark)
                            .frame(width: Self.decorationOutset * 2 + 1, height: Self.decorationOutset * 2 + 1)
                            .clipped()
                            .scaleEffect(x: attachment == .trailing ? -1 : 1, y: 1)
                            .offset(x: attachment == .trailing ? Self.decorationOutset : -Self.decorationOutset,
                                    y: -Self.decorationOutset)
                    } else {
                        ChristmasOrnamentCord(wood: wood, dark: colorScheme == .dark)
                            .frame(width: Self.decorationOutset + 1, height: 34)
                            .clipped()
                            .scaleEffect(x: attachment == .trailing ? -1 : 1, y: 1)
                            .offset(x: attachment == .trailing ? Self.decorationOutset : -Self.decorationOutset)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Parallel insets are essential here: retaining the outer chamfer would put
/// the pale bevel under the compact column's 5 pt text reservation.
struct ChristmasOrnamentOutline: InsettableShape {
    let role: ChristmasOrnamentRole
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> ChristmasOrnamentOutline {
        var result = self
        result.insetAmount += amount
        return result
    }

    func path(in bounds: CGRect) -> Path {
        let outerCut: CGFloat = role == .clock ? min(6, bounds.height * 0.2) : 6
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

/// Local (11.5,11.5) is the original clock's unused (4.5,4.5) corner.
/// Even the outer drill rim and cord stay before the 8 pt text reservation.
private struct ChristmasOrnamentClockCord: View {
    let dark: Bool

    var body: some View {
        Canvas { context, _ in
            let hole = Path(ellipseIn: CGRect(x: 9.6, y: 9.6, width: 3.8, height: 3.8))
            context.fill(hole, with: .color(OrnamentPigment.color(0x30291D)))
            context.stroke(hole, with: .linearGradient(
                Gradient(colors: [OrnamentPigment.color(0x936A3F), OrnamentPigment.color(0xF4E0BD)]),
                startPoint: CGPoint(x: 9.6, y: 9.6), endPoint: CGPoint(x: 13.4, y: 13.4)), lineWidth: 0.65)

            var cord = Path()
            cord.move(to: CGPoint(x: 11.5, y: 11.5))
            cord.addCurve(to: CGPoint(x: 6.2, y: 5.2),
                          control1: CGPoint(x: 8.8, y: 10.8), control2: CGPoint(x: 10, y: 4.8))
            cord.addCurve(to: CGPoint(x: 3.8, y: 4.4),
                          control1: CGPoint(x: 4.1, y: 2.6), control2: CGPoint(x: 2.4, y: 2.8))
            cord.addCurve(to: CGPoint(x: 11.5, y: 11.5),
                          control1: CGPoint(x: 4, y: 6.5), control2: CGPoint(x: 7.3, y: 10.8))
            context.stroke(cord, with: .color(.black.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 2.7, lineCap: .round))
            context.stroke(cord, with: .color(OrnamentPigment.color(dark ? 0x31563C : 0x174B2D)),
                           style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
            context.stroke(cord, with: .color(OrnamentPigment.color(0x86A277).opacity(0.5)),
                           style: StrokeStyle(lineWidth: 0.5, lineCap: .round))
        }
    }
}

private struct ChristmasOrnamentCord: View {
    let wood: UIImage
    let dark: Bool

    var body: some View {
        Canvas { context, size in
            let green = OrnamentPigment.color(dark ? 0x31563C : 0x174B2D)
            let centerY = size.height / 2
            var cord = Path()
            cord.move(to: CGPoint(x: 0.3, y: centerY - 5))
            cord.addCurve(to: CGPoint(x: 4.3, y: centerY),
                          control1: CGPoint(x: 5.5, y: centerY - 7),
                          control2: CGPoint(x: 6, y: centerY - 3))
            cord.addQuadCurve(to: CGPoint(x: 0.3, y: centerY + 4),
                              control: CGPoint(x: 3.5, y: centerY + 3))
            context.stroke(cord, with: .color(.black.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 2.9, lineCap: .round))
            context.stroke(cord, with: .color(green),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

            var end = Path()
            end.move(to: CGPoint(x: 8, y: 0.5))
            end.addLine(to: CGPoint(x: 2.3, y: 5))
            end.addLine(to: CGPoint(x: 0.8, y: 9))
            end.addLine(to: CGPoint(x: 0.8, y: size.height - 9))
            end.addLine(to: CGPoint(x: 2.3, y: size.height - 5))
            end.addLine(to: CGPoint(x: 8, y: size.height - 0.5))
            end.closeSubpath()
            let edge = end
            let hole = Path(ellipseIn: CGRect(x: 2, y: centerY - 1.8, width: 3.6, height: 3.6))
            end.addPath(hole)
            context.fill(end, with: .tiledImage(Image(uiImage: wood)), style: FillStyle(eoFill: true))
            context.stroke(edge, with: .linearGradient(
                Gradient(colors: [.white.opacity(0.45), .clear, .black.opacity(0.28)]),
                startPoint: .zero, endPoint: CGPoint(x: 5, y: size.height)), lineWidth: 0.6)
            context.stroke(hole, with: .color(OrnamentPigment.color(0x765132).opacity(0.8)), lineWidth: 0.65)

            var strand = Path()
            strand.move(to: CGPoint(x: 0, y: centerY - 2))
            strand.addQuadCurve(to: CGPoint(x: 4, y: centerY), control: CGPoint(x: 2, y: centerY + 1))
            context.stroke(strand, with: .color(green), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            context.stroke(strand, with: .color(OrnamentPigment.color(0x76966B).opacity(0.5)),
                           style: StrokeStyle(lineWidth: 0.45, lineCap: .round))
        }
    }
}

/// At most ten 512-square opaque maps (~10 MiB): eight role/color/appearance
/// paints and two shared bare-wood maps. Source fields are capped at 256 square.
/// No filtering, decoding or allocation is performed on subsequent clock ticks.
@MainActor
enum ChristmasOrnamentTexture {
    enum Kind: Hashable, CaseIterable { case paintedWood, bareWood }
    private final class ResourceBundle {}
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
        guard let source = UIImage(named: name, in: Bundle(for: ResourceBundle.self), compatibleWith: nil)?.cgImage else {
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
