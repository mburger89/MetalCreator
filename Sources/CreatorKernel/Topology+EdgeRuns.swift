import CreatorGeometry
import Foundation

extension Topology {
    /// Edge ends this close (mm) meet. OCCT edge curves can end up to the vertex tolerance (often 1e-5 mm) from the
    /// vertex they share after a blend, so the old 1e-6 split one edge into two runs.
    static let runJoinTolerance = 1e-4
    /// Edges meeting at a point continue each other when they leave it within this many radians of opposite
    /// directions, so two distinct edges that meet at a corner stay two runs.
    static let runJoinAngle = 0.01

    /// How many runs `edges` form: chains of edges that continue each other end to end (ends within
    /// `runJoinTolerance`, leaving that point in opposite directions). An edge an operation split in two is still one
    /// run, so a run is what a person picking sees as one edge; two edges that meet at a corner are two. An edge whose ends
    /// aren't known (no `curve`, or a full circle) is a run of its own.
    public static func runCount(_ edges: [EdgeInfo]) -> Int {
        var parent = Array(edges.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index { index = parent[index] }
            return index
        }
        let ends = edges.map { edge in zip(edge.curve?.ends ?? [], edge.curve?.endDirections ?? []).map { (point: $0, leaving: $1) } }
        let straightest = -cos(runJoinAngle)
        for i in edges.indices {
            for j in edges.indices where j > i {
                let meet = ends[i].contains { p in
                    ends[j].contains { q in (p.point - q.point).length <= runJoinTolerance && p.leaving.dot(q.leaving) <= straightest }
                }
                if meet { parent[root(j)] = root(i) }
            }
        }
        return Set(edges.indices.map(root)).count
    }
}
