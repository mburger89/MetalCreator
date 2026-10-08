import CreatorGeometry

/// One direction of a region-graph edge.
struct HalfEdge: Hashable, Sendable {
    var edge: Int
    /// True when it runs from the edge's `from` to its `to`.
    var isForward: Bool

    var twin: HalfEdge { HalfEdge(edge: edge, isForward: !isForward) }

    func origin(_ graph: RegionGraph) -> Int { isForward ? graph.edges[edge].from : graph.edges[edge].to }
    func target(_ graph: RegionGraph) -> Int { isForward ? graph.edges[edge].to : graph.edges[edge].from }

    /// The direction it leaves its origin in, as a polar angle in [0, 2π).
    func outgoingAngle(_ graph: RegionGraph) -> Double {
        let shape = graph.edges[edge].shape
        let tangent = isForward ? shape.tangent(at: 0) : shape.tangent(at: shape.parameterEnd) * -1
        let angle = SketchMath.wrapped(SketchMath.angle(tangent))
        // Snap a hair below a full turn to 0 so tangent ties sort together.
        return angle > CurveShape.fullTurn - 1e-9 ? 0 : angle
    }

    /// Signed curvature as it leaves its origin (left turns positive).
    func curvature(_ graph: RegionGraph) -> Double {
        isForward ? graph.edges[edge].shape.curvature : -graph.edges[edge].shape.curvature
    }

    /// The step this half-edge makes along a loop.
    func loopSegment(_ graph: RegionGraph) -> LoopSegment {
        let edge = graph.edges[edge]
        let geometry: LoopSegment.Geometry = switch edge.shape {
        case .line:
            if isForward {
                .line(graph.vertices[edge.from], graph.vertices[edge.to])
            } else {
                .line(graph.vertices[edge.to], graph.vertices[edge.from])
            }
        case .arc(let center, let radius, let start, let sweep):
            if isForward {
                .arc(center: center, radius: radius, from: start, to: start + sweep)
            } else {
                .arc(center: center, radius: radius, from: start + sweep, to: start)
            }
        }
        let (from, to) = isForward ? (edge.from, edge.to) : (edge.to, edge.from)
        return LoopSegment(geometry: geometry, source: edge.source, start: graph.vertices[from], end: graph.vertices[to])
    }
}
