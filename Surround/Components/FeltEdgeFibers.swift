import SwiftUI
import UIKit

/// The image's actual opaque outline, in source coordinates with (0.5, 0.5)
/// at its center. Asset providers prepare this once, alongside their images.
struct FeltFiberContour: Equatable {
    let points: [CGPoint]

    static func stone(image: UIImage) -> Self? {
        guard let source = image.cgImage, source.width > 1, source.height > 1 else { return nil }
        let width = source.width, height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // Sampling pixel centers makes the contour symmetric for an even-size
        // image. Bilinear alpha locates the edge between antialiased pixels.
        func alpha(x: CGFloat, y: CGFloat) -> CGFloat {
            let px = x - 0.5, py = y - 0.5
            let x0 = Int(floor(px)), y0 = Int(floor(py))
            let fx = px - CGFloat(x0), fy = py - CGFloat(y0)
            func value(_ x: Int, _ y: Int) -> CGFloat {
                guard x >= 0, x < width, y >= 0, y < height else { return 0 }
                return CGFloat(pixels[(y * width + x) * 4 + 3])
            }
            return value(x0, y0) * (1 - fx) * (1 - fy)
                + value(x0 + 1, y0) * fx * (1 - fy)
                + value(x0, y0 + 1) * (1 - fx) * fy
                + value(x0 + 1, y0 + 1) * fx * fy
        }

        let center = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        guard alpha(x: center.x, y: center.y) >= 128 else { return nil }
        var points = [CGPoint]()
        points.reserveCapacity(96)
        for index in 0..<96 {
            let angle = CGFloat(index) / 96 * .pi * 2
            let dx = cos(angle), dy = sin(angle)
            let limit = min(abs(dx) > 0.0001 ? center.x / abs(dx) : .infinity,
                            abs(dy) > 0.0001 ? center.y / abs(dy) : .infinity)
            var inner: CGFloat = 0
            // Follow the connected opaque body, ignoring detached flecks.
            // The half-alpha boundary is also the asset footprint contract.
            var outer: CGFloat = 0.5
            while outer < limit,
                  alpha(x: center.x + dx * outer, y: center.y + dy * outer) >= 128 {
                inner = outer
                outer += 0.5
            }
            outer = min(outer, limit)
            for _ in 0..<6 {
                let middle = (inner + outer) / 2
                if alpha(x: center.x + dx * middle, y: center.y + dy * middle) >= 128 {
                    inner = middle
                } else {
                    outer = middle
                }
            }
            let radius = (inner + outer) / 2
            points.append(CGPoint(x: (center.x + dx * radius) / CGFloat(width),
                                  y: (center.y + dy * radius) / CGFloat(height)))
        }
        return Self(points: points)
    }
}

/// Sparse, attached fibers rather than a regular serrated outline. The caller
/// draws these two paths with fine strokes; no filter or per-strand view is used.
struct FeltEdgeFibers {
    let body: Path
    let wisps: Path

    static func stone(contour: FeltFiberContour, in rect: CGRect,
                      seed: UInt32 = 0, footprint: CGFloat = 0.94) -> Self {
        guard rect.width.isFinite, rect.height.isFinite, rect.minX.isFinite, rect.minY.isFinite,
              rect.width > 0, rect.height > 0, footprint.isFinite, footprint > 0,
              contour.points.count >= 3 else { return Self(body: Path(), wisps: Path()) }
        let diameter = min(rect.width, rect.height)
        let extent = min(1.2, diameter * 0.035)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var body = Path(), wisps = Path()
        for index in contour.points.indices {
            let hash = hash(index: index, seed: seed)
            // Fixed angular samples and stable omissions preserve each tuft
            // through resizing, new moves, and captures elsewhere on a board.
            guard hash & 7 >= 5 else { continue }
            let amount = unit(hash >> 8) * 0.6
            let p0 = contour.points[index]
            let p1 = contour.points[(index + 1) % contour.points.count]
            let sample = CGPoint(x: p0.x + (p1.x - p0.x) * amount,
                                 y: p0.y + (p1.y - p0.y) * amount)
            let edge = CGPoint(x: center.x + (sample.x - 0.5) * rect.width / footprint,
                               y: center.y + (sample.y - 0.5) * rect.height / footprint)
            let normal = normalized(CGPoint(x: edge.x - center.x, y: edge.y - center.y))
            addFiber(to: &body, edge: edge, normal: normal, extent: extent,
                     hash: hash, bounds: rect.insetBy(dx: -extent, dy: -extent), wisp: false)
            if (hash >> 12) & 3 == 0 {
                addFiber(to: &wisps, edge: edge, normal: normal, extent: extent,
                         hash: hash ^ 0xA341_316C, bounds: rect.insetBy(dx: -extent, dy: -extent), wisp: true)
            }
        }
        return Self(body: body, wisps: wisps)
    }

    static func roundedRectangle(in rect: CGRect, cornerSize: CGSize, seed: UInt32 = 0) -> Self {
        let outline = RoundedRectangle(cornerSize: cornerSize, style: .continuous).path(in: rect)
        return roundedRectangle(outline: outline, in: rect, seed: seed)
    }

    /// Supplying the actual shape path also preserves circular corners when a
    /// particular control uses those instead of the usual continuous corners.
    static func roundedRectangle(outline: Path, in rect: CGRect, seed: UInt32 = 0) -> Self {
        guard rect.width.isFinite, rect.height.isFinite, rect.minX.isFinite, rect.minY.isFinite,
              rect.width > 0, rect.height > 0 else { return Self(body: Path(), wisps: Path()) }
        let points = flattened(outline)
        guard points.count >= 3 else { return Self(body: Path(), wisps: Path()) }
        var distances: [CGFloat] = [0]
        for index in 1..<points.count {
            distances.append(distances[index - 1] + hypot(points[index].x - points[index - 1].x,
                                                         points[index].y - points[index - 1].y))
        }
        guard let perimeter = distances.last, perimeter > 0 else { return Self(body: Path(), wisps: Path()) }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let extent = min(1.6, max(1, min(rect.width, rect.height) * 0.04))
        let bounds = rect.insetBy(dx: -extent, dy: -extent)
        var body = Path(), wisps = Path()
        for index in 0..<96 {
            let hash = hash(index: index, seed: seed)
            guard hash & 7 >= 5 else { continue }
            let distance = (CGFloat(index) + 0.15 + unit(hash >> 8) * 0.7) / 96 * perimeter
            let segment = max(1, distances.firstIndex(where: { $0 >= distance }) ?? distances.count - 1)
            let a = points[segment - 1], b = points[segment]
            let length = max(0.0001, distances[segment] - distances[segment - 1])
            let fraction = (distance - distances[segment - 1]) / length
            let edge = CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
            let tangent = normalized(CGPoint(x: b.x - a.x, y: b.y - a.y))
            var normal = CGPoint(x: tangent.y, y: -tangent.x)
            if normal.x * (edge.x - center.x) + normal.y * (edge.y - center.y) < 0 {
                normal = CGPoint(x: -normal.x, y: -normal.y)
            }
            addFiber(to: &body, edge: edge, normal: normal, extent: extent,
                     hash: hash, bounds: bounds, wisp: false, inside: outline)
            if (hash >> 12) & 3 == 0 {
                addFiber(to: &wisps, edge: edge, normal: normal, extent: extent,
                         hash: hash ^ 0xC801_3EA4, bounds: bounds, wisp: true, inside: outline)
            }
        }
        return Self(body: body, wisps: wisps)
    }

    private static func addFiber(to path: inout Path, edge: CGPoint, normal: CGPoint,
                                 extent: CGFloat, hash: UInt32, bounds: CGRect, wisp: Bool,
                                 inside outline: Path? = nil) {
        let tangent = CGPoint(x: -normal.y, y: normal.x)
        let rootDepth = min(extent, 0.25 + unit(hash >> 16) * 0.25)
        // Fibers lie along the cloth and curl outward. Long tangential runs
        // with a shallow tip avoid a regular ring of upright bristles.
        let lift = extent * (0.55 + unit(hash >> 8) * 0.45)
        let tip = extent * (0.15 + unit(hash >> 16) * 0.35)
        let direction: CGFloat = hash & 0x10000 == 0 ? -1 : 1
        let lean = direction * extent * ((wisp ? 1.7 : 1.1) + unit(hash >> 4) * 1.2)
        func point(outward: CGFloat, along: CGFloat) -> CGPoint {
            CGPoint(x: min(bounds.maxX, max(bounds.minX, edge.x + normal.x * outward + tangent.x * along)),
                    y: min(bounds.maxY, max(bounds.minY, edge.y + normal.y * outward + tangent.y * along)))
        }
        var root = point(outward: -rootDepth, along: -lean * 0.2)
        if let outline, !outline.contains(root) {
            // SwiftUI's containment approximation can reject a point close
            // to a circular corner even when its CGPath contains that point.
            // Keep the same strand and tip, but bury its root just inside
            // the supplied outline so the visible fiber stays attached.
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            guard outline.contains(center) else { return }
            var outside = root, inside = center
            for _ in 0..<12 {
                let middle = CGPoint(x: (outside.x + inside.x) / 2,
                                     y: (outside.y + inside.y) / 2)
                if outline.contains(middle) {
                    inside = middle
                } else {
                    outside = middle
                }
            }
            let inward = normalized(CGPoint(x: center.x - inside.x, y: center.y - inside.y))
            root = CGPoint(x: inside.x + inward.x * 0.05, y: inside.y + inward.y * 0.05)
        }
        path.move(to: root)
        path.addCurve(to: point(outward: tip, along: lean),
                      control1: point(outward: lift, along: lean * 0.2),
                      control2: point(outward: lift, along: lean * 0.7))
    }

    private static func hash(index: Int, seed: UInt32) -> UInt32 {
        var value = UInt32(truncatingIfNeeded: index) &* 0x9E37_79B9 &+ seed &+ 0x85EB_CA6B
        value ^= value >> 16
        value &*= 0x7FEB_352D
        value ^= value >> 15
        value &*= 0x846C_A68B
        return value ^ (value >> 16)
    }

    private static func unit(_ value: UInt32) -> CGFloat { CGFloat(value & 0xFF) / 255 }

    private static func normalized(_ point: CGPoint) -> CGPoint {
        let length = max(0.0001, hypot(point.x, point.y))
        return CGPoint(x: point.x / length, y: point.y / length)
    }

    /// Fixed subdivision follows SwiftUI's own continuous-corner path, so
    /// fibers stay attached rather than assuming circular corner geometry.
    private static func flattened(_ path: Path) -> [CGPoint] {
        var points = [CGPoint]()
        var current = CGPoint.zero, first = CGPoint.zero
        path.forEach { element in
            switch element {
            case .move(let point):
                current = point
                first = point
                points.append(point)
            case .line(let point):
                points.append(point)
                current = point
            case .quadCurve(let end, let control):
                let start = current
                for index in 1...16 {
                    let t = CGFloat(index) / 16, u = 1 - t
                    points.append(CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                                          y: u * u * start.y + 2 * u * t * control.y + t * t * end.y))
                }
                current = end
            case .curve(let end, let control1, let control2):
                let start = current
                for index in 1...16 {
                    let t = CGFloat(index) / 16, u = 1 - t
                    points.append(CGPoint(x: u * u * u * start.x + 3 * u * u * t * control1.x
                                          + 3 * u * t * t * control2.x + t * t * t * end.x,
                                          y: u * u * u * start.y + 3 * u * u * t * control1.y
                                          + 3 * u * t * t * control2.y + t * t * t * end.y))
                }
                current = end
            case .closeSubpath:
                points.append(first)
                current = first
            }
        }
        if let first = points.first, points.last != first { points.append(first) }
        return points
    }
}
