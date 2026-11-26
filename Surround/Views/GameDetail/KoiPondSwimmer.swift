import SwiftUI

enum KoiPondSwimmer {
    /// The pond is behind the native controls, boards and shoreline. Their
    /// painted shapes determine which parts of a passing fish remain visible.
    static func draw(in context: GraphicsContext, route: KoiPondSwimRoute, at elapsed: TimeInterval) {
        let pose = route.pose(at: elapsed)
        guard route.visibleWater.insetBy(dx: -route.length, dy: -route.length).contains(pose.center) else { return }

        var water = context
        water.clip(to: Path(route.visibleWater))
        draw(in: water, asset: route.assetName, center: pose.center, length: route.length,
             heading: pose.heading, tailPhase: pose.beat, amplitude: pose.tailAmplitude,
             bend: pose.bend, opacity: route.opacity)
    }

    /// Align the nose with the path tangent. A photographed koi's bent tail
    /// makes its image rectangle a poor guide to the direction of its head.
    private struct Portrait {
        let rotation: Angle
        let height: CGFloat
        let center: CGPoint
        /// The red koi were photographed mid-stroke, with their tails swept
        /// left by a third of a body length. Bring them closer to a resting pose.
        let tailCorrection: CGFloat

        init(asset: String) {
            // The visible height and center of the rotated alpha bounds,
            // in units of the original photograph's height.
            switch asset {
            case "KoiPondKohaku":
                rotation = .degrees(24.6)
                height = 200.0 / 213
                center = CGPoint(x: 2.0 / 213, y: -5.5 / 213)
                tailCorrection = 0.20
            case "KoiPondSanke":
                rotation = .degrees(14.7)
                height = 199.0 / 211
                center = CGPoint(x: -5.5 / 211, y: -7.0 / 211)
                tailCorrection = 0.20
            case "KoiPondGold":
                rotation = .degrees(-6.8)
                height = 140.0 / 139
                center = CGPoint(x: -2.0 / 139, y: -0.5 / 139)
                tailCorrection = 0
            default:
                rotation = .zero
                height = 1
                center = .zero
                tailCorrection = 0
            }
        }
    }

    /// Heading is in canvas radians (right = 0, down = π/2). Bend is the
    /// signed steering displacement at the tip, as a fraction of body length.
    static func draw(in context: GraphicsContext, asset: String, center: CGPoint,
                     length: CGFloat, heading: Double, tailPhase: Double,
                     amplitude: CGFloat = 1, bend: CGFloat = 0, opacity: Double = 1) {
        guard length > 0, opacity > 0 else { return }
        let image = context.resolve(Image(decorative: asset, bundle: KoiPond.bundle))
        guard image.size.height > 0, image.size.width > 0 else { return }
        let portrait = Portrait(asset: asset)
        let height = 1 / portrait.height
        let width = height * image.size.width / image.size.height
        let photo = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        var water = context
        water.opacity *= min(1, opacity)
        water.translateBy(x: center.x, y: center.y)
        water.rotate(by: .radians(heading + .pi / 2))
        water.scaleBy(x: length, y: length)

        func paint(_ context: inout GraphicsContext) {
            context.translateBy(x: -portrait.center.x * height, y: -portrait.center.y * height)
            context.rotate(by: portrait.rotation)
            context.draw(image, in: photo)
        }

        let effort = min(max(amplitude, 0), 1)
        let reach = 0.115 * effort
        let relief = portrait.tailCorrection * (1 - 0.1375 * effort)
        let turn = min(max(bend, -0.16), 0.16)
        if reach == 0 && turn == 0 && relief == 0 {
            paint(&water)
            return
        }

        // Limit the isolated surface to the rotated photograph and its tail travel.
        let angle = portrait.rotation.radians
        let halfWidth = (abs(width * cos(angle)) + abs(height * sin(angle))) / 2
            + abs(portrait.center.x) * height + abs(turn) + reach + relief + 0.01
        water.clip(to: Path(CGRect(x: -halfWidth, y: -0.51, width: 2 * halfWidth, height: 1.02)))
        water.drawLayer { layer in
            // Rotated clip rectangles can cover the same edge pixel. Copying the
            // shared texture into this transparent layer keeps its original alpha
            // at the join. The complete fish is composited onto the water once.
            func band(from top: CGFloat, to bottom: CGFloat, offset: CGFloat, next: CGFloat) {
                var strip = layer
                strip.blendMode = .copy
                strip.clip(to: Path(CGRect(x: -halfWidth, y: top, width: 2 * halfWidth, height: bottom - top)),
                           style: FillStyle(antialiased: false))
                let shear = (next - offset) / (bottom - top)
                strip.concatenate(CGAffineTransform(a: 1, b: 0, c: shear, d: 1,
                                                    tx: offset - shear * top, ty: 0))
                paint(&strip)
            }

            // The wave travels from the shoulder through the trunk to the
            // tail. Starting with zero slope keeps the rigid head continuous.
            let shoulder: CGFloat = -0.20
            band(from: -0.51, to: shoulder, offset: 0, next: 0)
            let segments = 14
            var y = shoulder
            var offset: CGFloat = 0
            for index in 1...segments {
                let t = CGFloat(index) / CGFloat(segments)
                let nextY = shoulder + 0.71 * t
                let stroke = reach * (1.6 - 0.6 * t) * sin(tailPhase - 4.8 * t)
                let next = t * t * (turn + relief + stroke)
                band(from: y, to: nextY, offset: offset, next: next)
                y = nextY
                offset = next
            }
        }
    }
}
