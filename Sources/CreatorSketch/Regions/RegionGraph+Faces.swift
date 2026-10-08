extension RegionGraph {
    /// Every face boundary: at each vertex, leave by the half-edge just clockwise of the one
    /// you arrived along (spec §5 step 3), which keeps the face on the left. Bounded faces come
    /// out counter-clockwise; each connected component's outside comes out clockwise.
    func faceCycles() -> [[HalfEdge]] {
        var outgoing = Array(repeating: [HalfEdge](), count: vertices.count)
        for index in edges.indices {
            for half in [HalfEdge(edge: index, isForward: true), HalfEdge(edge: index, isForward: false)] {
                outgoing[half.origin(self)].append(half)
            }
        }
        for vertex in outgoing.indices {
            outgoing[vertex].sort { a, b in
                let (angleA, angleB) = (a.outgoingAngle(self), b.outgoingAngle(self))
                if abs(angleA - angleB) > 1e-9 { return angleA < angleB }
                let (curvatureA, curvatureB) = (a.curvature(self), b.curvature(self))
                if curvatureA != curvatureB { return curvatureA < curvatureB }
                return (a.edge, a.isForward ? 0 : 1) < (b.edge, b.isForward ? 0 : 1)
            }
        }
        func next(_ half: HalfEdge) -> HalfEdge {
            let around = outgoing[half.target(self)]
            let index = around.firstIndex(of: half.twin) ?? 0
            return around[(index - 1 + around.count) % around.count]
        }
        var visited = Set<HalfEdge>()
        var cycles: [[HalfEdge]] = []
        for index in edges.indices {
            for start in [HalfEdge(edge: index, isForward: true), HalfEdge(edge: index, isForward: false)]
            where !visited.contains(start) {
                var cycle: [HalfEdge] = []
                var half = start
                while visited.insert(half).inserted {
                    cycle.append(half)
                    half = next(half)
                }
                cycles.append(cycle)
            }
        }
        return cycles
    }

    /// The connected component (smallest vertex index as its label) of each vertex.
    func componentLabels() -> [Int] {
        var label = Array(vertices.indices)
        var changed = true
        while changed {
            changed = false
            for edge in edges {
                let low = min(label[edge.from], label[edge.to])
                if label[edge.from] != low || label[edge.to] != low {
                    label[edge.from] = low
                    label[edge.to] = low
                    changed = true
                }
            }
        }
        return label
    }

    /// A cycle as loop segments, joining consecutive pieces of one curve across vertices that
    /// only they meet at (so a circle split for the walk comes back whole).
    func loop(_ cycle: [HalfEdge]) -> [LoopSegment] {
        let degree = degrees
        let segments = cycle.map { $0.loopSegment(self) }
        let joints = cycle.map { $0.origin(self) }
        func joins(_ i: Int) -> Bool {
            let previous = (i - 1 + segments.count) % segments.count
            return degree[joints[i]] == 2 && segments[previous].merged(with: segments[i]) != nil
        }
        guard let breakIndex = segments.indices.first(where: { !joins($0) }) else {
            // Every joint merges: one curve closing on itself (a circle).
            return [segments.dropFirst().reduce(segments[0]) { $0.merged(with: $1) ?? $0 }]
        }
        var result: [LoopSegment] = []
        for offset in 0..<segments.count {
            let i = (breakIndex + offset) % segments.count
            if offset > 0, joins(i), let last = result.last, let merged = last.merged(with: segments[i]) {
                result[result.count - 1] = merged
            } else {
                result.append(segments[i])
            }
        }
        return result
    }
}
