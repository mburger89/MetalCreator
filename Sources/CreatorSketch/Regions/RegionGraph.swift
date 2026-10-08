import CreatorGeometry
import Foundation

/// The planar graph of a sketch's curves, split at every intersection (spec §5 steps 2–3), with
/// duplicate (overlapping) pieces merged and every edge that can't bound a face removed.
struct RegionGraph: Sendable {
    struct Edge: Hashable, Sendable {
        var from: Int
        var to: Int
        /// The piece, parameterised from `from` to `to` (arcs counter-clockwise).
        var shape: CurveShape
        /// Index into `curves`.
        var source: Int
        /// Other curves that overlap this piece exactly; they bound a region through it too.
        var overlappingSources: Set<Int> = []
    }

    let curves: [SketchCurve]
    private(set) var vertices: [Vector2] = []
    private(set) var edges: [Edge] = []

    init(curves: [SketchCurve]) {
        self.curves = curves
        for (index, curve) in curves.enumerated() {
            addPieces(of: curve.shape, source: index)
        }
        removeEdgesThatBoundNoFace()
    }

    /// Curve indices with at least one edge left.
    var usedSources: Set<Int> {
        edges.reduce(into: Set<Int>()) { $0.formUnion($1.overlappingSources); $0.insert($1.source) }
    }

    /// The vertex at `point`, merging points closer than the intersection tolerance.
    mutating func vertex(_ point: Vector2) -> Int {
        if let existing = vertices.firstIndex(where: { ($0 - point).length <= CurveIntersection.tolerance }) {
            return existing
        }
        vertices.append(point)
        return vertices.count - 1
    }

    /// Splits one curve at its intersections with every other curve and adds the pieces.
    mutating func addPieces(of shape: CurveShape, source: Int) {
        var parameters: [Double] = []
        for (other, curve) in curves.enumerated() where other != source {
            for point in CurveIntersection.points(shape, curve.shape) {
                parameters.append(shape.nearestParameter(to: point))
            }
        }
        if shape.isFullCircle {
            parameters = parameters.map { SketchMath.wrapped($0) }
        } else {
            parameters += [0, shape.parameterEnd]
        }
        parameters.sort()
        var distinct: [Double] = []
        for t in parameters where distinct.last.map({ shape.length(from: $0, to: t) > CurveIntersection.tolerance }) ?? true {
            distinct.append(t)
        }
        if shape.isFullCircle {
            // A closed curve needs two vertices so each piece has distinct ends.
            if let last = distinct.last, let first = distinct.first,
               shape.length(from: last, to: first + CurveShape.fullTurn) <= CurveIntersection.tolerance {
                distinct.removeLast()
            }
            if distinct.isEmpty { distinct = [0] }
            if distinct.count == 1 { distinct.append(distinct[0] + .pi) }
            distinct.append(distinct[0] + CurveShape.fullTurn)
        }
        for (t0, t1) in zip(distinct, distinct.dropFirst()) where shape.length(from: t0, to: t1) > CurveIntersection.tolerance {
            let piece = shape.piece(from: t0, to: t1)
            let from = vertex(piece.startPoint)
            let to = vertex(piece.endPoint)
            guard from != to else { continue }
            let edge = Edge(from: from, to: to, shape: piece, source: source)
            if let existing = edges.firstIndex(where: { Self.isSameGeometry($0, edge) }) {
                if edges[existing].source != source { edges[existing].overlappingSources.insert(source) }
            } else {
                edges.append(edge)
            }
        }
    }

    /// Two pieces joining the same vertices along the same line or circle (an overlap).
    static func isSameGeometry(_ a: Edge, _ b: Edge) -> Bool {
        guard Set([a.from, a.to]) == Set([b.from, b.to]) else { return false }
        switch (a.shape, b.shape) {
        case (.line, .line):
            return true
        case (.arc(let c1, let r1, _, let s1), .arc(let c2, let r2, _, let s2)):
            let tolerance = CurveIntersection.tolerance
            return (c1 - c2).length <= tolerance && abs(r1 - r2) <= tolerance
                && (a.shape.point(at: s1 / 2) - b.shape.point(at: s2 / 2)).length <= tolerance * 10
        default:
            return false
        }
    }

    /// Repeatedly drops dangling edges (an end of degree 1) and bridges (edges whose removal
    /// disconnects their ends): neither can border a bounded face on one side only.
    mutating func removeEdgesThatBoundNoFace() {
        var changed = true
        while changed {
            changed = false
            var degree = Array(repeating: 0, count: vertices.count)
            for edge in edges {
                degree[edge.from] += 1
                degree[edge.to] += 1
            }
            let kept = edges.filter { degree[$0.from] > 1 && degree[$0.to] > 1 }
            if kept.count != edges.count {
                edges = kept
                changed = true
                continue
            }
            let bridges = Set(edges.indices.filter(isBridge))
            if !bridges.isEmpty {
                edges = edges.enumerated().filter { !bridges.contains($0.offset) }.map(\.element)
                changed = true
            }
        }
    }

    func isBridge(_ index: Int) -> Bool {
        let target = edges[index].to
        var seen: Set<Int> = [edges[index].from]
        var stack = [edges[index].from]
        while let vertex = stack.popLast() {
            if vertex == target { return false }
            for (other, edge) in edges.enumerated() where other != index {
                for (a, b) in [(edge.from, edge.to), (edge.to, edge.from)] where a == vertex && seen.insert(b).inserted {
                    stack.append(b)
                }
            }
        }
        return true
    }

    /// The number of edges at each vertex.
    var degrees: [Int] {
        var degree = Array(repeating: 0, count: vertices.count)
        for edge in edges {
            degree[edge.from] += 1
            degree[edge.to] += 1
        }
        return degree
    }
}
