import CreatorGeometry

extension FakeKernel {
    /// A test knob: runs first in every `projection` and may suspend or throw (never block a pool thread).
    public func setProjectionHook(_ hook: (@Sendable () async throws -> Void)?) {
        projectionHook = hook
    }

    /// A test knob: with a hook `compound` returns what it returns; without one it refuses as before.
    public func setCompoundHook(_ hook: (@Sendable ([Solid]) throws -> Solid)?) {
        compoundHook = hook
    }

    public func compound(_ solids: [Solid], tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        guard let compoundHook else { throw KernelError.unsupported("compounds") }
        return try compoundHook(solids)
    }

    public func projection(of solid: Solid?, curves: [Curve], frame: ProjectionFrame, options: ProjectionOptions) async throws
        -> Projection2D {
        try await projectionHook?()
        try Task.checkCancellation()
        operationLog.append("projection")
        try frame.validate()
        guard Self.isAxis(frame.direction) else { throw KernelError.unsupported("projecting along a tilted direction") }
        var lines: [ProjectedLine] = []
        if let solid, let box = Rect2D(points: Self.corners(of: solid.bounds).map(frame.place)) {
            let corners = [Vector2(box.min.x, box.min.y), Vector2(box.max.x, box.min.y), Vector2(box.max.x, box.max.y),
                           Vector2(box.min.x, box.max.y),
            ]
            for index in 0..<4 {
                let (a, b) = (corners[index], corners[(index + 1) % 4])
                lines.append(ProjectedLine(visibility: .visible, lineClass: .sharp, curve: .line(a, b),
                                           source: Self.nearestEdge(on: (a, b), of: solid, frame: frame).map { .edge($0) }))
            }
        }
        for (index, curve) in curves.enumerated() {
            lines.append(ProjectedLine(visibility: .visible, lineClass: .curve,
                                       curve: .polyline(curve.polyline.map(frame.place)), source: .curve(index: index, piece: 0)))
        }
        return Projection2D(lines: lines)
    }

    private static func isAxis(_ direction: Vector3) -> Bool {
        [direction.x, direction.y, direction.z].contains { abs(abs($0) - 1) <= 1e-9 }
    }

    private static func corners(of bounds: BoundingBox) -> [Vector3] {
        (0..<8).map { Vector3($0 & 1 == 0 ? bounds.min.x : bounds.max.x, $0 & 2 == 0 ? bounds.min.y : bounds.max.y,
                              $0 & 4 == 0 ? bounds.min.z : bounds.max.z)
        }
    }

    /// The straight edge that runs along `side` of the silhouette and lies nearest the viewer (least depth along the direction).
    private static func nearestEdge(on side: (Vector2, Vector2), of solid: Solid, frame: ProjectionFrame) -> EdgeID? {
        let tolerance = 1e-9
        let along = side.1 - side.0
        let length = (along.x * along.x + along.y * along.y).squareRoot()
        guard length > tolerance else { return nil }
        func distance(_ p: Vector2) -> Double { abs((p.x - side.0.x) * along.y - (p.y - side.0.y) * along.x) / length }
        var best: (EdgeID, Double)?
        for edge in solid.topology.edges {
            guard case .line(let start, let end)? = edge.curve else { continue }
            let (a, b) = (frame.place(start), frame.place(end))
            guard distance(a) <= 1e-6, distance(b) <= 1e-6, (a - b).length > 1e-6 else { continue }
            let depth = min(start.dot(frame.direction), end.dot(frame.direction))
            if best == nil || depth < best!.1 - 1e-9 { best = (edge.id, depth) }
        }
        return best?.0
    }
}
