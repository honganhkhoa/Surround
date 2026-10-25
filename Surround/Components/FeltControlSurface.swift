import SwiftUI
import UIKit

/// The same opaque wool on clocks and identities, from a 28 pt Home chip to
/// a full Game Detail card. Fibers keep their point size as the card resizes.
struct FeltControlSurface: View {
    let color: StoneColor
    let shape: RoundedRectangle
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var showsTexture: Bool { contrast != .increased && !reduceTransparency }

    var body: some View {
        FeltControlMaterial(color: color, shape: shape, colorScheme: colorScheme, showsTexture: showsTexture)
    }
}

/// Pure material rendering, separate from the system accessibility preferences.
struct FeltControlMaterial: View {
    let color: StoneColor
    let shape: RoundedRectangle
    let colorScheme: ColorScheme
    let showsTexture: Bool

    var body: some View {
        shape.fill(SurroundTheme.feltMeadow.clockSolidSurface(color))
            .overlay {
                if let image = FeltControlTexture.image(color: color, scheme: colorScheme) {
                    Image(uiImage: image).resizable(resizingMode: .tile)
                        .opacity(showsTexture ? 1 : 0)
                }
            }
            .overlay {
                // A broad, quiet edge gives the cloth a padded profile. The
                // clock's turn/warning ring is drawn separately above this.
                shape.inset(by: 1).strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.16), .clear, .black.opacity(0.18)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 2
                )
                .opacity(showsTexture ? 1 : 0)
            }
            .clipShape(shape)
            .overlay {
                FeltControlFringe(color: color, shape: shape)
                    .opacity(showsTexture ? 1 : 0)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Loose strands sit beyond the trimmed body. The existing turn/warning ring
/// remains above the cloth, and the fibers never affect layout or hit testing.
private struct FeltControlFringe: View {
    let color: StoneColor
    let shape: RoundedRectangle

    var body: some View {
        let tones = SurroundTheme.feltMeadow.identityChipColors(color)
        Canvas { context, size in
            let rect = CGRect(x: 2, y: 2, width: size.width - 4, height: size.height - 4)
            let fibers = FeltEdgeFibers.roundedRectangle(outline: shape.path(in: rect), in: rect)
            context.stroke(fibers.body, with: .color(tones[color == .black ? 1 : 0].opacity(0.8)),
                           style: StrokeStyle(lineWidth: 0.35, lineCap: .round))
            context.stroke(fibers.wisps, with: .color(tones[color == .black ? 0 : 1].opacity(0.8)),
                           style: StrokeStyle(lineWidth: 0.25, lineCap: .round))
        }
        .padding(-2)
    }
}

/// Four small, opaque images, prepared once per appearance/stone color. Neither
/// clock ticks nor list scrolling runs image filters or allocates new bitmaps.
@MainActor
enum FeltControlTexture {
    private final class ResourceBundle {}
    private struct Key: Hashable {
        let black: Bool
        let dark: Bool
    }
    private static var images: [Key: UIImage] = [:]

    static func image(color: StoneColor, scheme: ColorScheme) -> UIImage? {
        let key = Key(black: color == .black, dark: scheme == .dark)
        if let image = images[key] { return image }
        guard let fibers else { return nil }
        let traits = UITraitCollection(userInterfaceStyle: key.dark ? .dark : .light)
        let tones = SurroundTheme.feltMeadow.identityChipColors(color).map {
            UIColor($0).resolvedColor(with: traits)
        }
        func channels(_ color: UIColor) -> [CGFloat] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return [r, g, b]
        }
        let shadow = channels(tones[key.black ? 1 : 0])
        let highlight = channels(tones[key.black ? 0 : 1])
        let side = 512
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                // Mirrored quadrants meet continuously at every repeated edge.
                let sx = x < 256 ? x : 511 - x
                let sy = y < 256 ? y : 511 - y
                let fiber = CGFloat(fibers[sy * 256 + sx]) / 255
                // Spread the wool's narrow luminance range across the readable
                // palette, so raised fibers remain distinct at normal size.
                // Both player colors retain the source's light-on-dark relief.
                let amount = min(1, max(0, (fiber - 0.40) * 5.6))
                let offset = (y * side + x) * 4
                for channel in 0..<3 {
                    pixels[offset + channel] = UInt8(((shadow[channel] * (1 - amount)
                        + highlight[channel] * amount) * 255).rounded())
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(width: side, height: side, bitsPerComponent: 8,
                                    bitsPerPixel: 32, bytesPerRow: side * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: true,
                                    intent: .defaultIntent) else { return nil }
        // Keep individual strands large enough to read in 28 pt Home chips.
        let image = UIImage(cgImage: cgImage, scale: 1.25, orientation: .up)
        images[key] = image
        return image
    }

    /// Sample the original grid-free wool at native resolution. Material tone
    /// comes from the theme, leaving the board and its artwork untouched.
    private static let fibers: [UInt8]? = {
        guard let source = UIImage(named: "FeltMeadowBoard", in: Bundle(for: ResourceBundle.self),
                                   compatibleWith: nil)?.cgImage,
              let crop = source.cropping(to: CGRect(x: (source.width - 256) / 2,
                                                    y: (source.height - 256) / 2,
                                                    width: 256, height: 256)) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 256 * 256)
        let success = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 256, height: 256,
                                          bitsPerComponent: 8, bytesPerRow: 256,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 256, height: 256))
            return true
        }
        return success ? pixels : nil
    }()
}
