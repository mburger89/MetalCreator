import CreatorGeometry

/// A run of a sketch's curves joined end to end: open, or closed when its last piece returns to its first.
public struct SketchChain: Hashable, Sendable {
    /// The pieces in order, each starting where the one before ends.
    public var segments: [Segment2D]
    public var isClosed: Bool
    /// The entity each segment comes from, parallel to `segments`.
    public var sources: [SketchEntityID]

    public init(segments: [Segment2D], isClosed: Bool, sources: [SketchEntityID]) {
        self.segments = segments
        self.isClosed = isClosed
        self.sources = sources
    }
}

/// Chains a solved sketch's curves for the Sketch node's `curves` output.
public enum SketchChains {
    /// Points closer than this (mm) are one point, as the kernel's own join check (1e-6) allows.
    static let joinTolerance = 1e-7

    /// Every non-construction curve (projected edges included) chained at the points where exactly two curve ends
    /// meet; a point where one or three or more end ends a chain, and a circle is its own closed chain. Chains are ordered
    /// by their lowest-numbered curve in the sketch, so an edit elsewhere never reorders them.
    public static func find(in solved: Sketch) -> [SketchChain] {
        let curves = solved.curves(includingConstruction: false)
        var points: [Vector2] = []
        func vertex(_ point: Vector2) -> Int {
            if let found = points.firstIndex(where: { ($0 - point).length <= joinTolerance }) { return found }
            points.append(point)
            return points.count - 1
        }
        // Each open curve's two ends; a full circle has none.
        var ends: [Int: (start: Int, end: Int)] = [:]
        for (index, curve) in curves.enumerated() where !curve.shape.isFullCircle {
            ends[index] = (vertex(curve.shape.startPoint), vertex(curve.shape.endPoint))
        }
        var incident: [[(curve: Int, atStart: Bool)]] = Array(repeating: [], count: points.count)
        for (index, pair) in ends.sorted(by: { $0.key < $1.key }) {
            incident[pair.start].append((index, true))
            incident[pair.end].append((index, false))
        }
        var visited = Set<Int>()
        var chains: [(first: Int, chain: SketchChain)] = []
        // A walk of the curves from one end of `first`.
        func walk(from first: Int, enteringAtStart: Bool) {
            var (run, curve, forward, closed) = ([(curve: Int, forward: Bool)](), first, enteringAtStart, false)
            while true {
                visited.insert(curve)
                run.append((curve, forward))
                guard let pair = ends[curve] else { break }
                let exit = forward ? pair.end : pair.start
                guard incident[exit].count == 2 else { break }
                guard let next = incident[exit].first(where: { $0.curve != curve || $0.atStart == forward }) else { break }
                if next.curve == first && next.atStart == enteringAtStart { closed = true; break }
                if visited.contains(next.curve) { break }
                curve = next.curve
                forward = next.atStart
            }
            let segments = run.map { orient(curves[$0.curve].shape, forward: $0.forward) }
            chains.append((run.map(\.curve).min() ?? first,
                           SketchChain(segments: segments, isClosed: closed, sources: run.map { curves[$0.curve].source })))
        }
        for index in curves.indices where !visited.contains(index) {
            guard let pair = ends[index] else { continue }
            let startsHere = incident[pair.start].count != 2
            if startsHere || incident[pair.end].count != 2 { walk(from: index, enteringAtStart: startsHere) }
        }
        // What is left lies on cycles of degree-2 points.
        for index in curves.indices where !visited.contains(index) && ends[index] != nil {
            walk(from: index, enteringAtStart: true)
        }
        chains += circles(in: curves)
        return chains.sorted { $0.first < $1.first }.map(\.chain)
    }

    /// Each full circle as its own closed chain, keyed by its curve's index.
    private static func circles(in curves: [SketchCurve]) -> [(first: Int, chain: SketchChain)] {
        curves.enumerated().filter { $0.element.shape.isFullCircle }.map { index, curve in
            (index, SketchChain(segments: [orient(curve.shape, forward: true)], isClosed: true, sources: [curve.source]))
        }
    }

    /// The curve as a segment, walked from its start when `forward`, else from its end.
    private static func orient(_ shape: CurveShape, forward: Bool) -> Segment2D {
        switch shape {
        case .line(let a, let b):
            return forward ? .line(a, b) : .line(b, a)
        case .arc(let center, let radius, let start, let sweep):
            let (from, to) = forward ? (start, start + sweep) : (start + sweep, start)
            return .arc(center: center, radius: radius, start: Angle(radians: from), end: Angle(radians: to))
        case .spline(let curve):
            return .spline(forward ? curve : curve.reversed())
        }
    }
}
