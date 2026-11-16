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
    static let exact = 1e-9

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
        var evaluations = 0
        return try chain(items, tolerance: tolerance, distanceEvaluations: &evaluations)
    }

    static func chain(_ items: [EdgeItem], tolerance: Double, distanceEvaluations: inout Int) throws -> BoardOutline {
        guard !items.isEmpty else { throw KiCadProblem("The board has no outline on Edge.Cuts.") }
        let pieces = items.map { Piece(segment: segment(for: $0.shape), key: KiCadKey.item(for: $0.identity), identity: $0.identity) }
        var usedKeys = Set(pieces.map(\.key))
        var loops = try buildLoops(pieces, tolerance: tolerance, evaluations: &distanceEvaluations).map { joined($0, usedKeys: &usedKeys) }
        try rejectCrossings(loops)
        for loop in loops where abs(ArcGeometry.signedArea(loop.map(\.segment))) < 1e-9 {
            throw crosses(at: loop.map(\.start).min(by: lexicographically) ?? .zero)
        }

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
        let holes = loops.map { oriented($0, counterClockwise: false) }
            .enumerated()
            .sorted { lhs, rhs in
                let a = lhs.element.map(\.key).min() ?? 0, b = rhs.element.map(\.key).min() ?? 0
                return a != b ? a < b : lhs.offset < rhs.offset
            }
            .map(\.element)
        try requireInside(holes, of: outer)
        return BoardOutline(outer: outer.map(\.segment), holes: holes.map { $0.map(\.segment) },
                            outerKeys: outer.map(\.key), holeKeys: holes.map { $0.map(\.key) })
    }

    static func lexicographically(_ a: Vector2, _ b: Vector2) -> Bool {
        a.x != b.x ? a.x < b.x : a.y < b.y
    }

    // MARK: Pieces

    static func segment(for shape: EdgeItem.Shape) -> Segment2D {
        switch shape {
        case .line(let start, let end): return .line(start, end)
        case .arc(let start, let mid, let end): return ArcGeometry.arc(start: start, mid: mid, end: end)
        case .circle(let center, let radius): return ArcGeometry.circle(center: center, radius: radius)
        case .bezier(let p0, let p1, let p2, let p3): return .spline(BezierElevation.quintic(p0, p1, p2, p3))
        }
    }

    // MARK: Chaining

    /// Walks on from the last piece until the loop closes on `start` (true) or no piece is left to join (false).
    static func walk(_ loop: inout [Piece], grid: inout EndGrid, closingOn start: Vector2?, tolerance: Double) -> Bool {
        while true {
            let end = loop[loop.count - 1].end
            let best = grid.nearest(to: end, tolerance: tolerance)
            if let start {
                let distance = (end - start).length
                if distance <= tolerance, best == nil || distance <= best!.distance + 1e-12 { return true }
            }
            guard let found = best else { return false }
            grid.used[found.index] = true
            let piece = grid.pieces[found.index]
            loop.append(found.flipped ? piece.reversed() : piece)
        }
    }

    static func buildLoops(_ pieces: [Piece], tolerance: Double, evaluations: inout Int) throws -> [[Piece]] {
        var grid = EndGrid(pieces, tolerance: tolerance)
        defer { evaluations = grid.evaluations }
        let order = pieces.indices.sorted { grid.precedes($0, $1) }
        var loops: [[Piece]] = []
        var failures: [(key: Int, point: Vector2)] = []
        for first in order where !grid.used[first] {
            grid.used[first] = true
            var loop = [pieces[first]]
            if walk(&loop, grid: &grid, closingOn: pieces[first].start, tolerance: tolerance) {
                loops.append(loop)
                continue
            }
            // Open: run the other way from the first piece too, so both ends of the chain are known.
            let firstEnd = loop[loop.count - 1].end
            loop = loop.reversed().map { $0.reversed() }
            _ = walk(&loop, grid: &grid, closingOn: nil, tolerance: tolerance)
            let point = [firstEnd, loop[loop.count - 1].end].min(by: lexicographically) ?? firstEnd
            failures.append((loop.map(\.key).min() ?? 0, point))
        }
        if let worst = failures.min(by: { $0.key != $1.key ? $0.key < $1.key : lexicographically($0.point, $1.point) }) {
            throw notClosed(at: worst.point)
        }
        return loops
    }

    /// Closes every gap: two lines meet at the middle of their ends, a line's end moves onto a curve's, two curves get a line.
    static func joined(_ loop: [Piece], usedKeys: inout Set<Int>) -> [Piece] {
        var work = loop
        var needsLine = [Bool](repeating: false, count: loop.count)
        for index in work.indices {
            let next = (index + 1) % work.count
            guard (work[index].end - work[next].start).length > exact else { continue }
            if next == index {
                if case .line(let start, _) = work[index].segment {
                    work[index].segment = .line(start, start)
                } else {
                    needsLine[index] = true
                }
            } else if case .line(let s1, let e1) = work[index].segment, case .line(let s2, let e2) = work[next].segment {
                let middle = (e1 + s2) * 0.5
                work[index].segment = .line(s1, middle)
                work[next].segment = .line(middle, e2)
            } else if case .line(let start, _) = work[index].segment {
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
                let (from, to) = (work[index].end, work[next].start)
                let ids = [work[index].identity, work[next].identity].sorted()
                let corner = lexicographically(from, to) ? from : to
                var identity = "\(ids[0])+\(ids[1])+join@\(KeyAssigner.nanometres(corner.x)),\(KeyAssigner.nanometres(corner.y))"
                var count = 1
                while usedKeys.contains(KiCadKey.item(for: identity)) {
                    count += 1
                    identity = "\(ids[0])+\(ids[1])+join@\(KeyAssigner.nanometres(corner.x)),\(KeyAssigner.nanometres(corner.y))#\(count)"
                }
                let key = KiCadKey.item(for: identity)
                usedKeys.insert(key)
                result.append(Piece(segment: .line(from, to), key: key, identity: identity))
            }
        }
        return result
    }

    /// Counter-clockwise or clockwise, starting at the lowest-keyed segment and keeping that direction.
    static func oriented(_ loop: [Piece], counterClockwise: Bool) -> [Piece] {
        var result = loop
        let area = ArcGeometry.signedArea(loop.map(\.segment))
        if (area >= 0) != counterClockwise { result = loop.reversed().map { $0.reversed() } }
        guard let lowest = result.indices.min(by: { result[$0].key < result[$1].key || (result[$0].key == result[$1].key && $0 < $1) })
        else { return result }
        return Array(result[lowest...] + result[..<lowest])
    }

    // MARK: Words

    static func notClosed(at point: Vector2) -> KiCadProblem {
        KiCadProblem("The board outline isn't closed near \(coordinates(point)) mm.")
    }

    static func crosses(at point: Vector2) -> KiCadProblem {
        KiCadProblem("The board outline crosses itself near \(coordinates(point)) mm.")
    }

    /// "(x, y)" as KiCad shows it: y down.
    static func coordinates(_ point: Vector2) -> String {
        "(\(display(point.x)), \(display(-point.y)))"
    }

    static func display(_ value: Double) -> String {
        let text = (value + 0).formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
        return text == "-0" ? "0" : text
    }
}
