import CoreGraphics
import Foundation

struct KoiPondSwimPose: Equatable {
    let center: CGPoint
    let length: CGFloat
    /// Clockwise in the scene's coordinates. Zero points right.
    let heading: Double
    let beat: Double
    let tailAmplitude: CGFloat
    let bend: CGFloat
}

private struct SwimRandom {
    var state: UInt64

    mutating func unit() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var bits = state
        bits = (bits ^ (bits >> 30)) &* 0xBF58476D1CE4E5B9
        bits = (bits ^ (bits >> 27)) &* 0x94D049BB133111EB
        return Double((bits ^ (bits >> 31)) >> 11) / 9_007_199_254_740_992
    }
}

/// Conservative cross-sections of the three portraits in their neutral glide pose.
/// Each interval is in body lengths, from the head at -0.5 to the tail at +0.5.
private struct SwimOutline {
    let asset: String
    let sections: [CGRect]

    static let kohaku = SwimOutline("KoiPondKohaku",
                                   widths: [0.00...0.21, -0.16...0.33, -0.01...0.19, 0.01...0.18])
    static let sanke = SwimOutline("KoiPondSanke",
                                  widths: [-0.08...0.19, -0.21...0.36, -0.09...0.19, -0.06...0.15])
    static let gold = SwimOutline("KoiPondGold",
                                 widths: [-0.06...0.17, -0.25...0.28, -0.04...0.18, -0.02...0.14])

    private init(_ asset: String, widths: [ClosedRange<CGFloat>]) {
        self.asset = asset
        let rows: [CGFloat] = [-0.51, -0.35, 0.18, 0.36, 0.51]
        sections = widths.enumerated().map { i, x in
            CGRect(x: x.lowerBound, y: rows[i], width: x.upperBound - x.lowerBound, height: rows[i + 1] - rows[i])
        }
    }

    func footprint(center: CGPoint = .zero, heading: CGFloat, length: CGFloat, flex: ClosedRange<CGFloat>) -> CGRect {
        let c = cos(heading), s = sin(heading)
        var result = CGRect.null
        for section in sections {
            // A rigid head and progressively stronger flex aft of the gills,
            // matching the squared displacement in KoiPondSwimmer's strips.
            let t = max(0, (section.maxY + 0.20) / 0.71)
            let left = section.minX + min(0, flex.lowerBound) * t * t
            let right = section.maxX + max(0, flex.upperBound) * t * t
            let halfWidth = (right - left) / 2, midX = (left + right) / 2
            let dx = length * (abs(s) * halfWidth + abs(c) * section.height / 2)
            let dy = length * (abs(c) * halfWidth + abs(s) * section.height / 2)
            let x = center.x - length * (s * midX + c * section.midY)
            let y = center.y + length * (c * midX - s * section.midY)
            result = result.union(CGRect(x: x - dx, y: y - dy, width: 2 * dx, height: 2 * dy))
        }
        return result
    }
}

/// Several tail strokes accelerate the fish, then the tail settles as it coasts.
/// Distance is the integral of that speed, so seeking or resuming needs no frame history.
private struct SwimGait {
    private struct Bout {
        let start, strokeEnd, end, period, strength: Double
        let firstBeat: Int
        let strokeDurations: [Double]
    }

    struct Sample {
        let travelTime, beat, amplitude: Double
    }

    private let bouts: [Bout]
    private let duration, offset, speedContrast: Double
    private let beatCount: Int

    init(submerged: Bool, rhythm: Double, phase: Double, random: inout SwimRandom) {
        let basePeriod = (submerged ? 1.24 : 1.04) + 0.22 * rhythm
        speedContrast = 0.43 + 0.10 * random.unit()
        var bouts: [Bout] = [], time = 0.0, beat = 0
        for _ in 0..<16 {
            let count = 2 + Int(3 * random.unit())
            let period = basePeriod * (0.80 + 0.38 * random.unit())
            let strokes = (0..<count).map { _ in period * (0.74 + 0.52 * random.unit()) }
            let strokeEnd = time + strokes.reduce(0, +)
            let end = strokeEnd + 2.0 + 2.8 * random.unit()
            bouts.append(Bout(start: time, strokeEnd: strokeEnd, end: end, period: period,
                              strength: 0.82 + 0.18 * random.unit(), firstBeat: beat, strokeDurations: strokes))
            time = end
            beat += count
        }
        self.bouts = bouts
        duration = time
        offset = phase * time
        beatCount = beat
    }

    func at(_ elapsed: TimeInterval) -> Sample {
        let shifted = elapsed + offset, cycle = floor(shifted / duration)
        let local = shifted - cycle * duration
        var low = 0, high = bouts.count - 1
        while low < high {
            let middle = (low + high) / 2
            if local < bouts[middle].end { high = middle } else { low = middle + 1 }
        }
        let bout = bouts[low], active = local < bout.strokeEnd
        let start = active ? bout.start : bout.strokeEnd
        let span = (active ? bout.strokeEnd : bout.end) - start
        let u = (local - start) / span
        // Speed follows a smoothstep from slow to fast while stroking and
        // from fast to slow on the coast. Each interval averages exactly 1×.
        let integral = span * u * (u * u * (2 - u) - 1)
        let travelTime = elapsed + (active ? speedContrast : -speedContrast) * integral
        var beat = cycle * Double(beatCount) + Double(bout.firstBeat)
        guard active else {
            return Sample(travelTime: travelTime, beat: 2 * .pi * (beat + Double(bout.strokeDurations.count)), amplitude: 0)
        }

        var strokeTime = local - bout.start
        for period in bout.strokeDurations {
            if strokeTime < period {
                let phase = strokeTime / period
                // Match the phase derivative at neighbouring strokes of different lengths.
                beat += phase + (period / bout.period - 1) * sin(2 * .pi * phase) / (2 * .pi)
                break
            }
            beat += 1
            strokeTime -= period
        }
        let ramp = min(1, (local - bout.start) / (0.34 * bout.period), (bout.strokeEnd - local) / (0.52 * bout.period))
        let amplitude = bout.strength * ramp * ramp * (3 - 2 * ramp)
        return Sample(travelTime: travelTime, beat: 2 * .pi * beat, amplitude: amplitude)
    }
}

private struct Swimmer {
    let outline: SwimOutline
    let submerged: Bool
    let opacity: Double
    let pace, phase, bias, sizeFactor: CGFloat
    let gait: SwimGait
    let clockwise: Bool

    init(_ outline: SwimOutline, submerged: Bool, opacity: Double, random: inout SwimRandom) {
        self.outline = outline
        self.submerged = submerged
        self.opacity = opacity
        pace = submerged ? 0.050 + 0.015 * random.unit() : 0.080 + 0.020 * random.unit()
        phase = random.unit()
        let rhythm = random.unit(), strokePhase = random.unit()
        bias = random.unit() - 0.5
        sizeFactor = 0.94 + 0.10 * random.unit()
        clockwise = random.unit() < 0.5
        var gaitRandom = SwimRandom(state: random.state ^ 0xAEE3A35BA216029F)
        gait = SwimGait(submerged: submerged, rhythm: rhythm, phase: strokePhase, random: &gaitRandom)
    }
}

private struct CourseSample {
    let point: CGPoint
    let heading: CGFloat
    let curvature: CGFloat
}

/// A periodic cubic B-spline. Tabulate arc length once so swimming speed
/// stays even around the bend and across knots with unequal spacing.
private struct SwimCourse {
    let knots: [CGPoint]
    let distances: [CGFloat]
    private static let steps = 16

    init(_ knots: [CGPoint]) {
        self.knots = knots
        var previous = Self.sample(knots, at: 0).point
        var table: [CGFloat] = [0]
        for i in 1...(knots.count * Self.steps) {
            let point = Self.sample(knots, at: CGFloat(i) / CGFloat(Self.steps)).point
            table.append(table[table.count - 1] + hypot(point.x - previous.x, point.y - previous.y))
            previous = point
        }
        distances = table
    }

    private static func sample(_ knots: [CGPoint], at position: CGFloat) -> CourseSample {
        let n = knots.count, index = Int(position), t = position - CGFloat(index)
        let a = knots[(index + n - 1) % n], b = knots[index % n]
        let c = knots[(index + 1) % n], d = knots[(index + 2) % n]
        func axis(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
            let p = (a + 4 * b + c) / 6, q = (c - a) / 2
            let r = (a - 2 * b + c) / 2, s = (-a + 3 * b - 3 * c + d) / 6
            return (p + t * (q + t * (r + t * s)), q + t * (2 * r + 3 * t * s), 2 * r + 6 * t * s)
        }
        let x = axis(a.x, b.x, c.x, d.x), y = axis(a.y, b.y, c.y, d.y)
        let v = hypot(x.1, y.1)
        return CourseSample(point: CGPoint(x: x.0, y: y.0), heading: atan2(y.1, x.1),
                            curvature: (x.1 * y.2 - y.1 * x.2) / max(0.000001, v * v * v))
    }

    func at(distance: CGFloat) -> CourseSample {
        var low = 0, high = distances.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if distances[middle] <= distance { low = middle } else { high = middle }
        }
        let fraction = (distance - distances[low]) / (distances[high] - distances[low])
        return Self.sample(knots, at: (CGFloat(low) + fraction) / CGFloat(Self.steps))
    }
}

/// A moving fish may finish its current passage before the next layout takes
/// effect. A leg is a value snapshot, so repeated resizes never form a chain.
private struct SwimLeg {
    let course: SwimCourse
    let length, speed: CGFloat
    var initialLap: CGFloat
    var initialTime: TimeInterval
    var tangent: CourseSample?

    var duration: TimeInterval { course.distances.last! / speed }

    func lap(at time: TimeInterval) -> CGFloat {
        let turns = initialLap + (time - initialTime) / duration
        return turns - floor(turns)
    }

    func sample(at time: TimeInterval) -> CourseSample {
        guard let tangent else { return course.at(distance: lap(at: time) * course.distances.last!) }
        let distance = speed * (time - initialTime)
        return CourseSample(point: CGPoint(x: tangent.point.x + distance * cos(tangent.heading),
                                           y: tangent.point.y + distance * sin(tangent.heading)),
                            heading: tangent.heading,
                            curvature: tangent.curvature * max(0, 1 - abs(distance) / (0.5 * length)))
    }

    /// On a tangent, crossing a rectangle padded by one full body length
    /// guarantees that the entire silhouette is outside the physical window.
    func rayExit(at time: TimeInterval, direction: CGFloat, in window: CGRect) -> TimeInterval {
        let here = sample(at: time), padded = window.insetBy(dx: -length - 2, dy: -length - 2)
        let dx = direction * cos(here.heading), dy = direction * sin(here.heading)
        let x = dx == 0 ? .infinity : ((dx > 0 ? padded.maxX : padded.minX) - here.point.x) / dx
        let y = dy == 0 ? .infinity : ((dy > 0 ? padded.maxY : padded.minY) - here.point.y) / dy
        return time + direction * max(0, min(x, y)) / speed
    }

    /// Walk the arc-length table toward an exit, or backward to the entrance
    /// for this fish's selected passage. Refine the crossing so a new fish
    /// starts just outside the window. This runs only when the layout changes.
    func hiddenTime(from time: TimeInterval, direction: CGFloat, in window: CGRect,
                    outline: SwimOutline, clearanceTime: TimeInterval = 0.6) -> TimeInterval? {
        let margin = 2 + speed * clearanceTime
        let edge = window.insetBy(dx: -margin, dy: -margin)
        func hidden(_ sample: CourseSample) -> Bool {
            !outline.footprint(center: sample.point, heading: sample.heading,
                               length: length, flex: -0.29...0.29).intersects(edge)
        }
        let here = sample(at: time)
        if hidden(here) { return time }
        if tangent != nil { return rayExit(at: time, direction: direction, in: window) }
        let distances = course.distances, last = distances.count - 1
        let total = distances[last], start = lap(at: time) * total
        let next = distances.firstIndex { $0 >= start } ?? last
        var index = direction > 0 ? next % last : (next + last - 1) % last
        var inside: CGFloat = 0
        for _ in 0..<last {
            var outside = direction * (distances[index] - start)
            if outside < 0 { outside += total }
            if hidden(course.at(distance: distances[index])) {
                for _ in 0..<7 {
                    let middle = (inside + outside) / 2
                    if hidden(sample(at: time + direction * middle / speed)) { outside = middle }
                    else { inside = middle }
                }
                return time + direction * outside / speed
            }
            inside = outside
            index = (index + (direction > 0 ? 1 : last - 1)) % last
        }
        return nil
    }
}

struct KoiPondSwimRoute: Identifiable {
    struct ID: Hashable {
        let assetName: String
        let submerged: Bool
    }

    var id: ID { ID(assetName: assetName, submerged: submerged) }

    let assetName: String
    let submerged: Bool
    let opacity: Double
    var length: CGFloat { destination.length }
    var speed: CGFloat { destination.speed }
    /// Where the fish is guided through clear water; its journey can extend
    /// beyond this opening and behind real foreground objects.
    let habitat: CGRect
    private(set) var visibleWater: CGRect
    /// One circuit on the intended course at the fish's mean pace.
    var duration: TimeInterval { destination.duration }
    private let swimmer: Swimmer
    private let startingLap: CGFloat
    private var destination: SwimLeg
    private var departure: (leg: SwimLeg, ends: TimeInterval)?
    private var approach: (leg: SwimLeg, ends: TimeInterval)?
    private var retires = false

    fileprivate init(_ swimmer: Swimmer, guide: CGRect, window: CGRect, startObstacles: [CGRect],
                     length: CGFloat, knots: [CGPoint], startNear target: CGPoint, startingWater: CGRect? = nil) {
        self.swimmer = swimmer
        assetName = swimmer.outline.asset
        submerged = swimmer.submerged
        opacity = swimmer.opacity
        habitat = guide
        visibleWater = window
        let course = SwimCourse(knots)
        let total = course.distances.last!

        // Choose a visible composition for a still school and a passage for
        // live entrants to approach from beyond the window.
        let potentialFlex: ClosedRange<CGFloat> = -0.29...0.29
        var bestScore = -CGFloat.infinity, bestLap = swimmer.phase
        for distance in course.distances {
            let sample = course.at(distance: distance)
            guard guide.contains(sample.point) else { continue }
            let body = swimmer.outline.footprint(center: sample.point, heading: sample.heading, length: length,
                                                 flex: potentialFlex)
            let visible = body.intersection(window)
            let covered = startObstacles.reduce(CGFloat(0)) { sum, rect in
                let overlap = visible.intersection(rect)
                return sum + (overlap.isNull ? 0 : overlap.width * overlap.height)
            }
            let fraction = max(0, (visible.width * visible.height - covered) / (body.width * body.height))
            let lap = distance / total
            let delta = abs(swimmer.phase - lap)
            let outsideOpening = startingWater.map { !$0.contains(sample.point) } ?? false
            let score = fraction * 2.5 - hypot(sample.point.x - target.x, sample.point.y - target.y) / max(1, length)
                - 0.5 * min(delta, 1 - delta) - (outsideOpening ? 2 : 0)
            if score > bestScore { bestScore = score; bestLap = lap }
        }
        startingLap = bestLap
        destination = SwimLeg(course: course, length: length, speed: length * swimmer.pace,
                              initialLap: bestLap, initialTime: swimmer.gait.at(0).travelTime)
    }

    mutating func startInOpenWater(at elapsed: TimeInterval) {
        destination.initialLap = startingLap
        destination.initialTime = swimmer.gait.at(elapsed).travelTime
        departure = nil
        approach = nil
        retires = false
    }

    private func leg(at time: TimeInterval) -> SwimLeg {
        if let departure, retires || time < departure.ends { return departure.leg }
        if let approach, time < approach.ends { return approach.leg }
        return destination
    }

    func isPresent(at elapsed: TimeInterval) -> Bool {
        guard retires, let departure else { return true }
        return swimmer.gait.at(elapsed).travelTime < departure.ends
    }

    mutating func enterFromEdge(at elapsed: TimeInterval) {
        beginPassage(at: swimmer.gait.at(elapsed).travelTime)
    }

    private mutating func beginPassage(at time: TimeInterval) {
        departure = nil
        approach = nil
        retires = false
        destination.initialLap = startingLap
        destination.initialTime = time
        if let gate = destination.hiddenTime(from: time, direction: -1, in: visibleWater, outline: swimmer.outline,
                                             clearanceTime: 0.4 + 1.6 * swimmer.phase) {
            destination.initialLap = destination.lap(at: gate)
        } else {
            // If a course is entirely inside this window, approach its chosen
            // point on the incoming tangent before joining the circuit.
            var incoming = destination
            incoming.tangent = incoming.sample(at: time)
            let outside = incoming.rayExit(at: time, direction: -1, in: visibleWater)
            let arrival = time + (time - outside)
            incoming.initialTime = arrival
            destination.initialTime = arrival
            approach = (incoming, arrival)
        }
    }

    private func outgoing(at time: TimeInterval, in window: CGRect) -> (leg: SwimLeg, ends: TimeInterval) {
        var current = leg(at: time)
        if let exit = current.hiddenTime(from: time, direction: 1, in: window, outline: swimmer.outline) {
            return (current, exit)
        }
        // A larger viewport can contain the entire old circuit. Leave on its
        // current tangent at the same speed, easing the remaining tail bend.
        let point = current.sample(at: time)
        current.initialLap = current.lap(at: time)
        current.initialTime = time
        current.tangent = point
        return (current, current.rayExit(at: time, direction: 1, in: window))
    }

    mutating func continueFrom(_ previous: Self, at elapsed: TimeInterval) {
        guard previous.isPresent(at: elapsed) else { enterFromEdge(at: elapsed); return }
        let time = swimmer.gait.at(elapsed).travelTime
        let outgoing = previous.outgoing(at: time, in: visibleWater)
        beginPassage(at: outgoing.ends)
        if outgoing.ends > time { departure = outgoing }
    }

    func departing(in window: CGRect, at elapsed: TimeInterval) -> Self? {
        guard isPresent(at: elapsed) else { return nil }
        let time = swimmer.gait.at(elapsed).travelTime
        let outgoing = outgoing(at: time, in: window)
        guard outgoing.ends > time else { return nil }
        var leaving = self
        leaving.visibleWater = window
        leaving.departure = outgoing
        leaving.retires = true
        return leaving
    }

    func pose(at seconds: TimeInterval) -> KoiPondSwimPose {
        let gait = swimmer.gait.at(seconds), active = leg(at: gait.travelTime)
        let sample = active.sample(at: gait.travelTime)
        let steering = max(-0.10, min(0.10, sample.curvature * active.length * 0.075))
        return KoiPondSwimPose(center: sample.point, length: active.length, heading: sample.heading,
                               beat: gait.beat, tailAmplitude: gait.amplitude, bend: steering * gait.amplitude)
    }

    func bounds(at seconds: TimeInterval) -> CGRect {
        guard isPresent(at: seconds) else { return .null }
        let pose = pose(at: seconds)
        let lateralBeat = 0.184 * pose.tailAmplitude
        let flex = (pose.bend - lateralBeat)...(pose.bend + lateralBeat)
        return swimmer.outline.footprint(center: pose.center, heading: pose.heading, length: pose.length, flex: flex)
    }
}

struct KoiPondSwimSchool {
    private let swimmers: [Swimmer]

    var drawingOrder: [KoiPondSwimRoute.ID] {
        swimmers.map { KoiPondSwimRoute.ID(assetName: $0.outline.asset, submerged: $0.submerged) }
    }

    init(seed: UInt64) {
        var random = SwimRandom(state: seed)
        swimmers = [
            Swimmer(.sanke, submerged: true, opacity: 0.66, random: &random),
            Swimmer(.gold, submerged: true, opacity: 0.76, random: &random),
            Swimmer(.kohaku, submerged: false, opacity: 0.92, random: &random),
            Swimmer(.sanke, submerged: false, opacity: 0.92, random: &random)
        ]
    }

    func routes(in window: CGRect, gameArea: CGRect, board: CGRect, detailed: Bool,
                avoiding reservations: [CGRect]) -> [KoiPondSwimRoute] {
        let water = gameArea.intersection(window)
        guard !water.isEmpty, !board.isEmpty else { return [] }
        let startObstacles = reservations.filter { !$0.isEmpty } + (detailed ? [] : [board])
        let blocked = startObstacles.map { $0.insetBy(dx: -2, dy: -2) }
        let side = min(board.width, board.height)
        var routes: [KoiPondSwimRoute] = []
        if detailed {
            // The two depths share the entire board. Long chords cross instead
            // of partitioning the glass into two little pools.
            let guide = board.intersection(water)
            if !guide.isEmpty, !Self.openings(in: guide, avoiding: blocked).isEmpty {
                for i in 0..<2 {
                    let swimmer = swimmers[i], first = i == 0
                    let length = side * (first ? 0.30 : 0.28) * swimmer.sizeFactor
                    let horizontal = guide.width > 1.6 * guide.height || (first && guide.height < 1.6 * guide.width)
                    let start = CGPoint(x: guide.minX + guide.width * ((first ? 0.32 : 0.68) + 0.47 * swimmer.bias),
                                        y: guide.minY + guide.height * ((first ? 0.39 : 0.66) + 0.48 * (swimmer.phase - 0.5)))
                    let knots = Self.passages(through: guide, in: window, horizontal: horizontal,
                                              length: length, swimmer: swimmer)
                    routes.append(KoiPondSwimRoute(swimmer, guide: guide, window: window,
                                                  startObstacles: startObstacles, length: length, knots: knots, startNear: start))
                }
            }
        }

        let requested = min(190, min(water.width, water.height) * 0.25)
        let outside = Self.openings(in: water.insetBy(dx: 2, dy: 2), avoiding: blocked + [board.insetBy(dx: -2, dy: -2)])
        for i in 2..<4 {
            let swimmer = swimmers[i], upper = i == 2
            let length = requested * swimmer.sizeFactor * (upper ? 1 : 0.91)
            let target = CGPoint(x: board.minX + board.width * ((upper ? 0.81 : 0.19) + 0.16 * swimmer.bias),
                                 y: upper ? board.minY - 0.38 * length : board.maxY + 0.75 * length)
            var candidates = outside
            if upper && detailed {
                // Outside the chip, the upper current can dip into the glass
                // and emerge again without having to turn at the board edge.
                let edge = CGRect(x: board.minX, y: board.minY - length,
                                  width: board.width, height: length + board.height * 0.22).intersection(water)
                candidates += Self.openings(in: edge, avoiding: blocked).filter {
                    $0.minY < board.minY - max(12, length * 0.30) && $0.maxY > board.minY + 0.18 * length
                }
            }
            let guide = Self.channel(in: candidates, toward: target, length: length)
            // In Closed Duo the tree can fill the game area. Enter and leave
            // the exposed lower rail through the *physical* side of the screen.
            let left = water.minX - window.minX, right = window.maxX - water.maxX
            let railWidth = max(left, right)
            if (guide.map { min($0.width, $0.height) } ?? 0) < 0.22 * length,
               window.height > window.width, railWidth >= max(30, window.width * 0.09),
               railWidth < window.width * 0.30 {
                let rightRail = right >= left
                let rail = CGRect(x: rightRail ? water.maxX : window.minX, y: window.minY + window.height * 0.55,
                                  width: railWidth, height: window.height * 0.33)
                let start = CGPoint(x: rail.midX, y: rail.minY + rail.height * ((upper ? 0.28 : 0.70) + 0.30 * swimmer.bias))
                let knots = Self.railPassages(through: rail, right: rightRail, length: length, swimmer: swimmer)
                routes.append(KoiPondSwimRoute(swimmer, guide: rail, window: window,
                                              startObstacles: startObstacles, length: length, knots: knots, startNear: start))
            } else if let guide {
                let horizontal = guide.width >= guide.height
                let crossesUpperRim = upper && detailed && horizontal && guide.minY < board.minY && guide.maxY > board.minY
                let entry = crossesUpperRim
                    ? CGRect(x: guide.minX, y: guide.minY, width: guide.width, height: board.minY - guide.minY)
                    : guide
                let glass = detailed ? board.intersection(water) : nil
                let knots = Self.passages(through: entry, in: window, horizontal: horizontal,
                                          length: length, swimmer: swimmer, adjoiningGlass: glass)
                let start = CGPoint(x: entry.minX + entry.width * (0.50 + 0.80 * swimmer.bias),
                                    y: entry.minY + entry.height * (0.50 + 0.64 * (swimmer.phase - 0.5)))
                routes.append(KoiPondSwimRoute(swimmer, guide: guide, window: window,
                                              startObstacles: startObstacles, length: length, knots: knots, startNear: start, startingWater: entry))
            }
        }
        return routes
    }

    private static func channel(in gaps: [CGRect], toward target: CGPoint, length: CGFloat) -> CGRect? {
        var best: CGRect?, bestScore = -CGFloat.infinity
        for gap in gaps {
            let long = max(gap.width, gap.height), short = min(gap.width, gap.height)
            guard long >= 0.65 * length, short >= max(7, 0.17 * length) else { continue }
            let dx = max(gap.minX - target.x, target.x - gap.maxX, 0)
            let dy = max(gap.minY - target.y, target.y - gap.maxY, 0)
            // Reward a long visible reach before the fish passes behind a
            // player. A narrow band can readily accommodate a sideways pass.
            let score = 0.65 * min(long, 4.6 * length) + 0.77 * min(short, length)
                - 0.80 * hypot(dx, dy)
            if score > bestScore { best = gap; bestScore = score }
        }
        return best
    }

    private enum Edge {
        case left, right, top, bottom

        var opposite: Self {
            switch self {
            case .left: .right
            case .right: .left
            case .top: .bottom
            case .bottom: .top
            }
        }

        func point(on rect: CGRect, fraction: CGFloat) -> CGPoint {
            switch self {
            case .left: CGPoint(x: rect.minX, y: rect.minY + fraction * rect.height)
            case .right: CGPoint(x: rect.maxX, y: rect.minY + fraction * rect.height)
            case .top: CGPoint(x: rect.minX + fraction * rect.width, y: rect.minY)
            case .bottom: CGPoint(x: rect.minX + fraction * rect.width, y: rect.maxY)
            }
        }

        // Leave room to bank on a passage between adjacent edges. A pair
        // of openings close to their shared corner would make a koi pivot.
        func crossingFraction(toward next: Self, sample: CGFloat) -> CGFloat {
            if next == opposite { return 0.13 + 0.74 * sample }
            return (next == .left || next == .top ? 0.42 : 0.14) + 0.44 * sample
        }

        /// Keep the approach aligned with its opening, even when the board is inset.
        func beyond(_ window: CGRect, alignedWith point: CGPoint, by distance: CGFloat) -> CGPoint {
            switch self {
            case .left: CGPoint(x: window.minX - distance, y: point.y)
            case .right: CGPoint(x: window.maxX + distance, y: point.y)
            case .top: CGPoint(x: point.x, y: window.minY - distance)
            case .bottom: CGPoint(x: point.x, y: window.maxY + distance)
            }
        }

        func inward(from point: CGPoint, by reach: CGFloat) -> CGPoint {
            switch self {
            case .left: CGPoint(x: point.x + reach, y: point.y)
            case .right: CGPoint(x: point.x - reach, y: point.y)
            case .top: CGPoint(x: point.x, y: point.y + reach)
            case .bottom: CGPoint(x: point.x, y: point.y - reach)
            }
        }
    }

    /// Aim for different banks over a visit. A koi can cross the open water
    /// in one pass and bear into the glass on the next. Each turn back toward
    /// the pond connects two points beyond the same physical screen edge.
    private static func passages(through guide: CGRect, in window: CGRect, horizontal: Bool,
                                 length: CGFloat, swimmer: Swimmer, adjoiningGlass: CGRect? = nil) -> [CGPoint] {
        var random = SwimRandom(state: Double(swimmer.phase).bitPattern)
        let near: Edge = horizontal ? .left : .top
        let first = swimmer.clockwise ? near : near.opposite, far = first.opposite
        let glass = adjoiningGlass.flatMap { $0.isEmpty ? nil : $0 }
        let side: Edge
        if let glass {
            side = horizontal ? (glass.midY > guide.midY ? .bottom : .top) : (glass.midX > guide.midX ? .right : .left)
        } else {
            side = horizontal ? (random.unit() < 0.5 ? .bottom : .top) : (random.unit() < 0.5 ? .right : .left)
        }

        let edges: [Edge]
        if swimmer.submerged {
            edges = [first, far, side, first, side.opposite, far]
        } else if glass != nil {
            edges = [first, far, first, side, far]
        } else {
            edges = [first, far, first, far]
        }

        // Leave room for long glides between the changes in bearing. The
        // unequal reaches place the bend early or late on each approach.
        var knots: [CGPoint] = []
        for i in edges.indices {
            let from = edges[i], to = edges[(i + 1) % edges.count]
            let fromWater = from == side ? glass ?? guide : guide
            let toWater = to == side ? glass ?? guide : guide
            let entry = from.point(on: fromWater, fraction: from.crossingFraction(toward: to, sample: random.unit()))
            let exit = to.point(on: toWater, fraction: to.crossingFraction(toward: from, sample: random.unit()))
            let dx = exit.x - entry.x, dy = exit.y - entry.y
            let distance = max(1, hypot(dx, dy))
            func reach(from edge: Edge) -> CGFloat {
                let span = edge == .left || edge == .right ? abs(dx) : abs(dy)
                return span * (0.22 + 0.19 * random.unit())
            }
            let approach = from.inward(from: entry, by: reach(from: from))
            let departure = to.inward(from: exit, by: reach(from: to))
            let water = fromWater.union(toWater)
            let width = from.opposite == to ? min(water.width, water.height) : min(abs(dx), abs(dy)) * 0.50
            let innerChord = hypot(departure.x - approach.x, departure.y - approach.y)
            let sweep = min(width * (0.12 + 0.18 * random.unit()), innerChord * 0.16)
            let cross = random.unit() < 0.5 ? -sweep : sweep
            let t = 0.31 + 0.38 * random.unit()
            let bend = CGPoint(
                x: min(water.maxX, max(water.minX, approach.x + (departure.x - approach.x) * t - dy / distance * cross)),
                y: min(water.maxY, max(water.minY, approach.y + (departure.y - approach.y) * t + dx / distance * cross))
            )
            knots += [from.beyond(window, alignedWith: entry, by: 0.85 * length), entry, approach,
                      bend, departure, exit, to.beyond(window, alignedWith: exit, by: 0.85 * length),
                      to.beyond(window, alignedWith: exit, by: 1.54 * length)]
        }
        return knots
    }

    private static func railPassages(through rail: CGRect, right: Bool, length: CGFloat,
                                     swimmer: Swimmer) -> [CGPoint] {
        let edge = right ? rail.maxX : rail.minX, sign: CGFloat = right ? 1 : -1
        func point(_ outside: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: edge + sign * outside, y: rail.minY + y * rail.height)
        }
        var random = SwimRandom(state: Double(swimmer.phase).bitPattern)
        var knots: [CGPoint] = []
        for leg in 0..<4 {
            let down = (leg.isMultiple(of: 2)) == swimmer.clockwise
            func y(_ t: CGFloat) -> CGFloat { down ? t : 1 - t }
            let depth = rail.width * (0.35 + 0.41 * random.unit())
            knots += [point(1.8 * length, y(-0.12)), point(0.78 * length, y(-0.08)),
                      point(-0.20 * depth, y(0.04)), point(-depth, y(0.19 + 0.17 * random.unit())),
                      point(-depth * (0.61 + 0.36 * random.unit()), y(0.56 + 0.23 * random.unit())),
                      point(-0.46 * depth, y(0.91)),
                      point(0.77 * length, y(1.05)), point(1.72 * length, y(1.12))]
        }
        return knots
    }

    /// Maximal clear rectangles retain both the horizontal and vertical
    /// passages around each chip. Prune nested rectangles after every cut.
    private static func openings(in area: CGRect, avoiding obstacles: [CGRect]) -> [CGRect] {
        guard !area.isEmpty else { return [] }
        var gaps = [area]
        for obstacle in obstacles where obstacle.intersects(area) {
            let cut = gaps.flatMap { gap -> [CGRect] in
                let overlap = gap.intersection(obstacle)
                guard !overlap.isEmpty else { return [gap] }
                return [
                    CGRect(x: gap.minX, y: gap.minY, width: gap.width, height: overlap.minY - gap.minY),
                    CGRect(x: gap.minX, y: overlap.maxY, width: gap.width, height: gap.maxY - overlap.maxY),
                    CGRect(x: gap.minX, y: gap.minY, width: overlap.minX - gap.minX, height: gap.height),
                    CGRect(x: overlap.maxX, y: gap.minY, width: gap.maxX - overlap.maxX, height: gap.height)
                ].filter { $0.width >= 4 && $0.height >= 4 }
            }
            gaps = []
            for rect in cut.sorted(by: { $0.width * $0.height > $1.width * $1.height })
                where !gaps.contains(where: { $0.contains(rect) }) { gaps.append(rect) }
        }
        return gaps
    }
}
