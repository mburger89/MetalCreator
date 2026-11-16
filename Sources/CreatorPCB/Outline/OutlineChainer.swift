import CreatorGeometry
import Foundation

/// The board outline as a `Profile2D`'s loops, with the identity key of the item behind each segment.
public struct BoardOutline: Sendable {
    public var outer: [Segment2D]
    public var holes: [[Segment2D]]
    public var outerKeys: [Int]
    public var holeKeys: [[Int]]

    public init(outer: [Segment2D], holes: [[Segment2D]], outerKeys: [Int], holeKeys: [[Int]]) {
        self.outer = outer
        self.holes = holes
        self.outerKeys = outerKeys
        self.holeKeys = holeKeys
    }
}

public enum OutlineChainer {
    /// Ends closer than this are one point; a line's end is moved onto the other piece's end only beyond it.
    private static let exact = 1e-9

    struct Piece {
        var segment: Segment2D
        var key: Int
        var identity: String
        var start: Vector2 { segment.startPoint }
        var end: Vector2 { segment.endPoint }
        var isLine: Bool { if case .line = segment { return true } else { return false } }

        func reversed() -> Piece {
            Piece(segment: ArcGeometry.reversed(segment), key: key, identity: identity)
        }
    }

    public static func chain(_ items: [EdgeItem], tolerance: Double) throws -> BoardOutline {
        guard !items.isEmpty else { throw KiCadProblem("The board has no outline on Edge.Cuts.") }
        let pieces = items.map { Piece(segment: segment(for: $0.shape), key: KiCadKey.item(for: $0.identity), identity: $0.identity) }
        var loops = try buildLoops(pieces, tolerance: tolerance).map(joined)
        try rejectCrossings(loops)

        var outerIndex = 0
        var largest = -1.0
        for (index, loop) in loops.enumerated() {
            let area = abs(ArcGeometry.signedArea(loop.map(\.segment)))
            if area > largest {
                largest = area
                outerIndex = index
            }
        }
        let outer = oriented(loops.remove(at: outerIndex), counterClockwise: true)
        try requireInside(loops, of: outer)
        let holes = loops.map { oriented($0, counterClockwise: false) }
            .enumerated()
            .sorted { lhs, rhs in
                let a = lhs.element.map(\.key).min() ?? 0, b = rhs.element.map(\.key).min() ?? 0
                return a != b ? a < b : lhs.offset < rhs.offset
            }
            .map(\.element)
        return BoardOutline(outer: outer.map(\.segment), holes: holes.map { $0.map(\.segment) },
                            outerKeys: outer.map(\.key), holeKeys: holes.map { $0.map(\.key) })
    }

    // MARK: Pieces

    private static func segment(for shape: EdgeItem.Shape) -> Segment2D {
        switch shape {
        case .line(let start, let end): return .line(start, end)
        case .arc(let start, let mid, let end): return ArcGeometry.arc(start: start, mid: mid, end: end)
        case .circle(let center, let radius): return ArcGeometry.circle(center: center, radius: radius)
        case .bezier(let p0, let p1, let p2, let p3): return .spline(BezierElevation.quintic(p0, p1, p2, p3))
        }
    }

    // MARK: Chaining

    private static func buildLoops(_ pieces: [Piece], tolerance: Double) throws -> [[Piece]] {
        var used = [Bool](repeating: false, count: pieces.count)
        var loops: [[Piece]] = []
        for first in pieces.indices where !used[first] {
            used[first] = true
            var loop = [pieces[first]]
            let start = pieces[first].start
            while true {
                let end = loop[loop.count - 1].end
                if (end - start).length <= exact { break }
                var best: (index: Int, flipped: Bool, distance: Double)?
                for candidate in pieces.indices where !used[candidate] {
                    let toStart = (end - pieces[candidate].start).length
                    let toEnd = (end - pieces[candidate].end).length
                    let flipped = toEnd < toStart
                    let distance = flipped ? toEnd : toStart
                    if distance <= tolerance, best == nil || distance < best!.distance {
                        best = (candidate, flipped, distance)
                    }
                }
                if let found = best {
                    used[found.index] = true
                    loop.append(found.flipped ? pieces[found.index].reversed() : pieces[found.index])
                } else if (end - start).length <= tolerance {
                    break
                } else {
                    throw notClosed(at: end)
                }
            }
            loops.append(loop)
        }
        return loops
    }

    /// Closes every gap: a line's end moves onto its neighbour's, two curves get a line between them.
    private static func joined(_ loop: [Piece]) -> [Piece] {
        var work = loop
        var needsLine = [Bool](repeating: false, count: loop.count)
        for index in work.indices {
            let next = (index + 1) % work.count
            guard (work[index].end - work[next].start).length > exact else { continue }
            if case .line(let start, _) = work[index].segment {
                work[index].segment = .line(start, work[next].start)
            } else if case .line(_, let end) = work[next].segment {
                work[next].segment = .line(work[index].end, end)
            } else {
                needsLine[index] = true
            }
        }
        var result: [Piece] = []
        for index in work.indices {
            result.append(work[index])
            if needsLine[index] {
                let next = (index + 1) % work.count
                let identity = work[index].identity + "+join"
                result.append(Piece(segment: .line(work[index].end, work[next].start),
                                    key: KiCadKey.item(for: identity), identity: identity))
            }
        }
        return result
    }

    /// Counter-clockwise or clockwise, starting at the lowest-keyed segment and keeping that direction.
    private static func oriented(_ loop: [Piece], counterClockwise: Bool) -> [Piece] {
        var result = loop
        let area = ArcGeometry.signedArea(loop.map(\.segment))
        if (area >= 0) != counterClockwise { result = loop.reversed().map { $0.reversed() } }
        guard let lowest = result.indices.min(by: { result[$0].key < result[$1].key || (result[$0].key == result[$1].key && $0 < $1) })
        else { return result }
        return Array(result[lowest...] + result[..<lowest])
    }

    // MARK: Checks

    private struct Shape {
        let loop: Int
        let index: Int
        let count: Int
        let points: [Vector2]
        let minX: Double, maxX: Double, minY: Double, maxY: Double
    }

    private static func rejectCrossings(_ loops: [[Piece]]) throws {
        var shapes: [Shape] = []
        for (loopIndex, loop) in loops.enumerated() {
            for (index, piece) in loop.enumerated() {
                let points = ArcGeometry.polyline(piece.segment)
                let xs = points.map(\.x), ys = points.map(\.y)
                shapes.append(Shape(loop: loopIndex, index: index, count: loop.count, points: points,
                                    minX: xs.min() ?? 0, maxX: xs.max() ?? 0, minY: ys.min() ?? 0, maxY: ys.max() ?? 0))
                if case .spline = piece.segment, let point = selfCrossing(points) { throw crosses(at: point) }
            }
        }
        let order = shapes.indices.sorted { shapes[$0].minX < shapes[$1].minX }
        for (position, i) in order.enumerated() {
            let a = shapes[i]
            for j in order[(position + 1)...] {
                let b = shapes[j]
                if b.minX > a.maxX + exact { break }
                if b.minY > a.maxY + exact || b.maxY < a.minY - exact { continue }
                if a.loop == b.loop {
                    let gap = abs(a.index - b.index)
                    if gap == 1 || gap == a.count - 1 { continue }
                }
                if let point = firstIntersection(a.points, b.points) { throw crosses(at: point) }
            }
        }
    }

    private static func selfCrossing(_ points: [Vector2]) -> Vector2? {
        guard points.count > 3 else { return nil }
        for i in 0..<(points.count - 1) {
            for j in stride(from: i + 2, to: points.count - 1, by: 1) {
                if let point = intersection(points[i], points[i + 1], points[j], points[j + 1]) { return point }
            }
        }
        return nil
    }

    private static func firstIntersection(_ a: [Vector2], _ b: [Vector2]) -> Vector2? {
        for i in 0..<(a.count - 1) {
            for j in 0..<(b.count - 1) {
                if let point = intersection(a[i], a[i + 1], b[j], b[j + 1]) { return point }
            }
        }
        return nil
    }

    /// Where the closed segments p to p2 and q to q2 meet, nil when parallel or apart.
    private static func intersection(_ p: Vector2, _ p2: Vector2, _ q: Vector2, _ q2: Vector2) -> Vector2? {
        let r = p2 - p, s = q2 - q
        let denominator = r.x * s.y - r.y * s.x
        guard abs(denominator) > 1e-14 else { return nil }
        let offset = q - p
        let t = (offset.x * s.y - offset.y * s.x) / denominator
        let u = (offset.x * r.y - offset.y * r.x) / denominator
        guard t >= -exact, t <= 1 + exact, u >= -exact, u <= 1 + exact else { return nil }
        return p + r * t
    }

    private static func requireInside(_ holes: [[Piece]], of outer: [Piece]) throws {
        var polygon: [Vector2] = []
        for piece in outer { polygon += ArcGeometry.polyline(piece.segment) }
        for hole in holes {
            for piece in hole where !contains(polygon, piece.start) {
                throw KiCadProblem("A cutout lies outside the board outline near \(coordinates(piece.start)) mm.")
            }
        }
    }

    private static func contains(_ polygon: [Vector2], _ point: Vector2) -> Bool {
        var inside = false
        var previous = polygon[polygon.count - 1]
        for current in polygon {
            if (current.y > point.y) != (previous.y > point.y),
               point.x < (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x {
                inside.toggle()
            }
            previous = current
        }
        return inside
    }

    // MARK: Words

    private static func notClosed(at point: Vector2) -> KiCadProblem {
        KiCadProblem("The board outline isn't closed near \(coordinates(point)) mm.")
    }

    private static func crosses(at point: Vector2) -> KiCadProblem {
        KiCadProblem("The board outline crosses itself near \(coordinates(point)) mm.")
    }

    /// "(x, y)" as KiCad shows it: y down.
    private static func coordinates(_ point: Vector2) -> String {
        "(\(display(point.x)), \(display(-point.y)))"
    }

    private static func display(_ value: Double) -> String {
        let text = (value + 0).formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
        return text == "-0" ? "0" : text
    }
}
