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
            return degree[joints[i]] == 2 && merged(segments[previous], segments[i]) != nil
        }
        guard let breakIndex = segments.indices.first(where: { !joins($0) }) else {
            // Every joint merges: one curve closing on itself (a circle).
            return [segments.dropFirst().reduce(segments[0]) { merged($0, $1) ?? $0 }]
        }
        var result: [LoopSegment] = []
        for offset in 0..<segments.count {
            let i = (breakIndex + offset) % segments.count
            if offset > 0, joins(i), let last = result.last, let joined = merged(last, segments[i]) {
                result[result.count - 1] = joined
            } else {
                result.append(segments[i])
            }
        }
        return result
    }

    /// `next` continued into `segment` along the same curve, or `nil`. Spline pieces rejoin when one's end parameter is the
    /// next's start in the same sense: the union is cut again from the source curve, not glued from the pieces.
    func merged(_ segment: LoopSegment, _ next: LoopSegment) -> LoopSegment? {
        guard case .spline = segment.geometry, case .spline = next.geometry else { return segment.merged(with: next) }
        guard segment.source == next.source, let first = segment.sourceSpan, let second = next.sourceSpan,
              (first.to - first.from) * (second.to - second.from) > 0, abs(first.to - second.from) <= 1e-9,
              case .spline(let whole) = curves[segment.source].shape else { return nil }
        let base = whole.parameterRange.lowerBound
        let span = LoopSegment.ParameterSpan(from: first.from, to: second.to)
        let low = min(span.from, span.to) - base
        let high = max(span.from, span.to) - base
        guard case .spline(let piece) = CurveShape.spline(whole).piece(from: low, to: high) else { return nil }
        let geometry: LoopSegment.Geometry = .spline(span.to > span.from ? piece : piece.reversed())
        return LoopSegment(geometry: geometry, source: segment.source, start: segment.start, end: next.end, sourceSpan: span)
    }
}
