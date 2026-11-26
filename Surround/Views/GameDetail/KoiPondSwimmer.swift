import SwiftUI

enum KoiPondSwimmer {
    /// The pond is behind the native controls, boards and shoreline. Their
    /// painted shapes determine which parts of a passing fish remain visible.
    static func draw(in context: GraphicsContext, route: KoiPondSwimRoute, at elapsed: TimeInterval) {
        guard route.isPresent(at: elapsed) else { return }
        let pose = route.pose(at: elapsed)
        guard route.visibleWater.insetBy(dx: -pose.length, dy: -pose.length).contains(pose.center) else { return }

        var water = context
        water.clip(to: Path(route.visibleWater))
        draw(in: water, asset: route.assetName, center: pose.center, length: pose.length,
             heading: pose.heading, tailPhase: pose.beat, amplitude: pose.tailAmplitude,
             bend: pose.bend, opacity: route.opacity)
    }

    /// Heading is in canvas radians (right = 0, down = π/2). Bend is the
    /// signed steering displacement at the tip, as a fraction of body length.
    static func draw(in context: GraphicsContext, asset: String, center: CGPoint,
                     length: CGFloat, heading: Double, tailPhase: Double,
                     amplitude: CGFloat = 1, bend: CGFloat = 0, opacity: Double = 1) {
        guard length > 0, opacity > 0 else { return }
        let image = context.resolve(Image(decorative: asset + "Swim", bundle: KoiPond.bundle))
        guard image.size.height > 0, image.size.width > 0 else { return }
        // Each neutral portrait shares a centered 180 × 255 canvas, with 250
        // source pixels per body length. Its photographed head points straight up.
        let photo = CGRect(x: -0.36, y: -0.51, width: 0.72, height: 1.02)
        var water = context
        water.opacity *= min(1, opacity)
        water.translateBy(x: center.x, y: center.y)
        water.rotate(by: .radians(heading + .pi / 2))
        water.scaleBy(x: length, y: length)

        let reach = 0.115 * min(max(amplitude, 0), 1)
        let turn = min(max(bend, -0.16), 0.16)
        if reach == 0 && turn == 0 {
            water.draw(image, in: photo)
            return
        }

        let halfWidth = photo.width / 2 + abs(turn) + reach + 0.01
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
                strip.draw(image, in: photo)
            }

            // The wave travels from the shoulder through the trunk to the
            // tail. Starting with zero slope keeps the rigid head continuous.
            let shoulder: CGFloat = -0.20
            band(from: -0.51, to: shoulder, offset: 0, next: 0)
            var y = shoulder
            var offset: CGFloat = 0
            let segments = 14
            for index in 1...segments {
                let t = CGFloat(index) / CGFloat(segments)
                let nextY = shoulder + 0.71 * t
                let stroke = reach * (1.6 - 0.6 * t) * sin(tailPhase - 4.8 * t)
                let next = t * t * (turn + stroke)
                band(from: y, to: nextY, offset: offset, next: next)
                y = nextY
                offset = next
            }
        }
    }
}
