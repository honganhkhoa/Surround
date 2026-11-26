import SwiftUI

/// Only the walnut fills the viewport. The linen and ingredients keep their
/// proportions at the four physical corners as panels open or a Duo folds.
struct GoldenCrumbScene: View {
    let scheme: ColorScheme

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let shortSide = min(size.width, size.height)
            let ground = SurroundTheme.goldenCrumb.pageBackground
            ZStack {
                ground
                Image(decorative: "GoldenCrumbWalnutBench", bundle: GoldenCrumb.bundle)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .overlay(alignment: .topLeading) {
                        // The cloth and its contact shadow occupy one seventh of the phone's
                        // short side, leaving bare walnut between the hem and the clocks.
                        corner("GoldenCrumbLinenCorner", width: min(shortSide / 7, 128))
                    }
                    .overlay(alignment: .bottomTrailing) {
                        corner("GoldenCrumbCutterImprint", width: min(shortSide * 0.37, 270))
                            .padding(.bottom, min(shortSide * 0.06, 44))
                    }
                    .overlay(alignment: .topTrailing) {
                        corner("GoldenCrumbPastryCorner", width: min(shortSide * 0.47, 340))
                    }
                    .overlay(alignment: .bottomLeading) {
                        corner("GoldenCrumbCocoaCorner", width: min(shortSide * 0.52, 365))
                    }
                    .colorMultiply(scheme == .dark ? Color(themeHex: 0x837B73) : .white)
                if #unavailable(iOS 26, macCatalyst 26) {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [ground, ground.opacity(0.80), .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: min(96, size.height * 0.23))
                        Spacer(minLength: 0)
                        LinearGradient(colors: [.clear, ground.opacity(0.80), ground],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: min(84, size.height * 0.20))
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func corner(_ name: String, width: CGFloat) -> some View {
        Image(decorative: name, bundle: GoldenCrumb.bundle)
            .resizable()
            .scaledToFit()
            .frame(width: width)
    }
}

/// A cocoa or vanilla biscuit stamped with a shallow border. The four corners
/// retain their shape while the straight sides and fine crumb fit the surface.
struct GoldenCrumbCookieSurface: View {
    enum FlourPrint {
        case running, warning
    }

    let color: StoneColor
    let cornerRadius: CGFloat
    var edgeClearance: CGFloat = 6
    var flour: FlourPrint? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private static let cocoa = UIImage(named: "GoldenCrumbCocoaStamp", in: GoldenCrumb.bundle,
                                       compatibleWith: nil)?.cgImage
    private static let vanilla = UIImage(named: "GoldenCrumbVanillaStamp", in: GoldenCrumb.bundle,
                                         compatibleWith: nil)?.cgImage
    private static let runningFlour = UIImage(named: "GoldenCrumbRunningFlour", in: GoldenCrumb.bundle,
                                              compatibleWith: nil)?.cgImage
    private static let warningFlour = UIImage(named: "GoldenCrumbWarningFlour", in: GoldenCrumb.bundle,
                                              compatibleWith: nil)?.cgImage
    private static let warningCuts = UIImage(named: "GoldenCrumbWarningFlourCuts", in: GoldenCrumb.bundle,
                                             compatibleWith: nil)?.cgImage

    var body: some View {
        let theme = SurroundTheme.goldenCrumb
        Group {
            if contrast != .increased, !reduceTransparency,
               let stamp = color == .black ? Self.cocoa : Self.vanilla {
                GeometryReader { geometry in
                    // The photographed rim is 11 pixels deep, within a 24-pixel
                    // nine-slice cap. Only the existing content padding can wear it.
                    let shortSide = min(geometry.size.width, geometry.size.height)
                    let rim = max(1, min(edgeClearance, shortSide * 0.083))
                    let scale = 11 / rim
                    let cap = 24 / scale
                    let stampCaps = EdgeInsets(top: cap, leading: cap, bottom: cap, trailing: cap)
                    let biscuit = Image(decorative: stamp, scale: scale, orientation: .up)
                        .resizable(capInsets: stampCaps)
                        .colorMultiply(scheme == .light ? .white
                                       : Color(themeHex: color == .black ? 0xE1D5C9 : 0xF1E7D9))
                    Group {
                        if flour == .warning, let cuts = Self.warningCuts {
                            biscuit.mask {
                                Image(decorative: cuts, scale: scale, orientation: .up)
                                    .resizable(capInsets: stampCaps, resizingMode: .stretch)
                            }
                        } else {
                            biscuit
                        }
                    }
                    .shadow(color: Color(themeHex: 0x26180E).opacity(0.52),
                            radius: rim * 0.14, x: rim * 0.06, y: rim * 0.18)
                    .background {
                        if let flour, let flourImage = flour == .warning ? Self.warningFlour : Self.runningFlour {
                            // The flour is on the bench, beneath the biscuit's contact shadow.
                            // The backing is sampled at twice the stamp resolution and
                            // extends 11 stamp pixels past its silhouette on each side.
                            let bleed = 11 / scale
                            let flourCap = cap + bleed
                            Image(decorative: flourImage, scale: 2 * scale, orientation: .up)
                                .resizable(capInsets: EdgeInsets(top: flourCap, leading: flourCap,
                                                                bottom: flourCap, trailing: flourCap),
                                           resizingMode: .stretch)
                                .padding(-bleed)
                        }
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            } else {
                let face = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                face.fill(theme.clockSolidSurface(color))
                    .overlay {
                        face.strokeBorder(theme.identityChipBorder(color), lineWidth: contrast == .increased ? 2 : 1)
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
