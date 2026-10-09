import CreatorGeometry
import Foundation

/// A pure-Swift kernel for tests. Solids are tagged bounding boxes. Topology and tags
/// follow the real naming scheme, but the geometry is NOT correct. Never run the
/// kernel conformance suite against it (spec §5.4).
public actor FakeKernel: Kernel {
    public private(set) var operationLog: [String] = []

    public init() {}

    public func clearLog() {
        operationLog.removeAll()
    }

    public func extrude(_ profile: Profile2D, distance: Double, mode: ExtrudeMode, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        operationLog.append("extrude")
        guard distance.isFinite, distance > 0 else {
            throw KernelError.invalidInput("Extrude distance must be greater than 0 mm.")
        }
        guard profile.isClosed, let flat = profile.bounds else {
            throw KernelError.invalidInput("The profile is not a closed loop.")
        }
        let normal = profile.plane.normal
        let (back, front) = mode == .symmetric ? (-distance / 2, distance / 2) : (0, distance)
        let corners = [flat.min, flat.max].flatMap { [$0 + normal * back, $0 + normal * front] }
        guard let bounds = BoundingBox(points: corners) else {
            throw KernelError.invalidInput("The profile is empty.")
        }
        return Solid(topology: Self.prism(profile, distance: distance, heights: (back, front), tag: tag), bounds: bounds,
                     storage: FakeStorage())
    }

    public func revolve(_ profile: Profile2D, axis: Axis, angle: Angle, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        operationLog.append("revolve")
        throw KernelError.unsupported("revolve")
    }

    public func loft(_ sections: [Profile2D], ruled: Bool, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        operationLog.append("loft")
        guard sections.allSatisfy(\.holes.isEmpty) else {
            throw KernelError.invalidInput("A loft can't use profiles with holes yet.")
        }
        throw KernelError.unsupported("loft")
    }

    public func boolean(_ op: BooleanOp, _ a: Solid, _ b: [Solid], tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        operationLog.append("boolean")
        var bounds = a.bounds
        switch op {
        case .union:
            bounds = b.reduce(a.bounds) { $0.union($1.bounds) }
        case .subtract:
            break
        case .intersect:
            for other in b {
                guard let overlap = bounds.intersection(other.bounds) else {
                    throw KernelError.operationFailed(operation: "intersect", reason: "the solids don't overlap, so the result is empty.")
                }
                bounds = overlap
            }
        }
        let topology = op == .intersect ? a.topology : b.reduce(a.topology) { Self.appending($1.topology, to: $0) }
        return Solid(topology: topology, bounds: bounds, storage: FakeStorage())
    }

    public func transform(_ solid: Solid, by transform: Transform, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        operationLog.append("transform")
        if transform.rotation.radians != 0, transform.rotationAxis == nil {
            throw KernelError.invalidInput("A rotation needs an axis.")
        }
        return Solid(topology: solid.topology, bounds: solid.bounds.translated(by: transform.translation), storage: FakeStorage())
    }

    public func fillet(_ solid: Solid, edges: [EdgeID], radius: Double, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        operationLog.append("fillet")
        return try blend(solid, edges: edges, size: radius, tag: tag)
    }

    public func chamfer(_ solid: Solid, edges: [EdgeID], distance: Double, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        operationLog.append("chamfer")
        return try blend(solid, edges: edges, size: distance, tag: tag)
    }

    public func tessellate(_ solid: Solid, tolerance: Double) throws -> DisplayMesh {
        try Task.checkCancellation()
        operationLog.append("tessellate")
        let (lo, hi) = (solid.bounds.min, solid.bounds.max)
        let positions = (0..<8).map { i in
            Vector3(i & 1 == 0 ? lo.x : hi.x, i & 2 == 0 ? lo.y : hi.y, i & 4 == 0 ? lo.z : hi.z)
        }
        let center = solid.bounds.center
        let indices: [UInt32] = [0, 2, 1, 1, 2, 3, 4, 5, 6, 5, 7, 6, 0, 1, 4, 1, 5, 4,
                                 2, 6, 3, 3, 6, 7, 0, 4, 2, 2, 4, 6, 1, 3, 5, 3, 7, 5,
        ]
        return DisplayMesh(
            positions: positions,
            normals: positions.map { ($0 - center).normalized ?? .unitZ },
            indices: indices,
            triangleFaces: Array(repeating: FaceID(0), count: indices.count / 3),
            edgePolylines: [:]
        )
    }

    public func export(_ solids: [Solid], format: ExportFormat, to url: URL) throws {
        try Task.checkCancellation()
        operationLog.append("export")
        throw KernelError.unsupported("export")
    }

    public func properties(of solid: Solid) throws -> SolidProperties {
        try Task.checkCancellation()
        operationLog.append("properties")
        let size = solid.bounds.size
        return SolidProperties(
            volume: size.x * size.y * size.z,
            surfaceArea: 2 * (size.x * size.y + size.y * size.z + size.z * size.x),
            centroid: solid.bounds.center
        )
    }

    // MARK: - Fake construction

    private func blend(_ solid: Solid, edges: [EdgeID], size: Double, tag: NodeTag) throws -> Solid {
        guard size.isFinite, size > 0 else {
            throw KernelError.invalidInput("The size must be greater than 0 mm.")
        }
        guard !edges.isEmpty else {
            throw KernelError.invalidInput("No edges are selected.")
        }
        let side = solid.bounds.size
        let limit = min(side.x, side.y, side.z)
        guard size * 2 < limit else {
            throw KernelError.filletFailed(radius: size, maxRadius: limit / 2, reason: "radius too large for the part")
        }
        var topology = solid.topology
        for id in edges {
            guard let edge = topology.edge(id), let key = topology.key(of: edge) else {
                throw KernelError.operationFailed(operation: "fillet", reason: "edge \(id.rawValue) doesn't exist on the input solid.")
            }
            let face = FaceID(topology.faces.count)
            topology.faces.append(FaceInfo(id: face, kind: .cylinder, normal: edge.direction, area: 0,
                                           centroid: edge.midpoint, tags: [TopoTag(tag, .blend(sourceEdge: key))]))
        }
        return Solid(topology: topology, bounds: solid.bounds, storage: FakeStorage())
    }

    /// Caps, then for each loop (outer first, then holes): one side face per segment tagged
    /// `.side(loop:segment:)`, bottom and top edges per segment, and between-side edges. A
    /// single-segment loop (a circle) gets a seam instead of between-side edges. Hole corners are
    /// concave. The outer loop's faces and edges are numbered exactly as for a profile without holes.
    /// Every edge carries its exact curve, the caps' at `heights` along the normal (S4 projection).
    private static func prism(_ profile: Profile2D, distance: Double, heights: (Double, Double), tag: NodeTag) -> Topology {
        let normal = profile.plane.normal
        var faces = [
            FaceInfo(id: FaceID(0), kind: .plane, normal: -normal, area: 0, centroid: .zero, tags: [TopoTag(tag, .startCap)]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: normal, area: 0, centroid: .zero, tags: [TopoTag(tag, .endCap)]),
        ]
        var edges: [EdgeInfo] = []
        func addEdge(_ kind: CurveKind, _ direction: Vector3?, _ length: Double, _ convexity: Convexity, _ a: Int, _ b: Int,
                     curve: EdgeCurve? = nil) {
            edges.append(EdgeInfo(id: EdgeID(edges.count), kind: kind, direction: direction, length: length,
                                  midpoint: .zero, convexity: convexity, faces: [FaceID(a), FaceID(b)], curve: curve))
        }
        for (loop, segments) in profile.loops.enumerated() {
            let first = faces.count
            for (k, segment) in segments.enumerated() {
                let side = first + k
                let isLine: Bool
                if case .line = segment { isLine = true } else { isLine = false }
                faces.append(FaceInfo(id: FaceID(side), kind: isLine ? .plane : .cylinder, normal: nil, area: 0,
                                      centroid: .zero, tags: [TopoTag(tag, .side(loop: loop, segment: k))]))
                let along: Vector3? = isLine
                    ? (profile.plane.point(segment.endPoint) - profile.plane.point(segment.startPoint)).normalized
                    : normal
                addEdge(isLine ? .line : .circle, along, segment.length, .convex, 0, side,
                        curve: curve(of: segment, on: profile.plane, at: heights.0))
                addEdge(isLine ? .line : .circle, along, segment.length, .convex, 1, side,
                        curve: curve(of: segment, on: profile.plane, at: heights.1))
            }
            // A wall edge rises from the corner where segment k ends (a circle's seam from its start).
            func rising(from corner: Vector2) -> EdgeCurve {
                .line(start: profile.plane.point(corner) + normal * heights.0, end: profile.plane.point(corner) + normal * heights.1)
            }
            if segments.count == 1 {
                addEdge(.line, normal, distance, .smooth, first, first, curve: rising(from: segments[0].startPoint))
            } else {
                for k in segments.indices {
                    addEdge(.line, normal, distance, loop == 0 ? .convex : .concave, first + k, first + (k + 1) % segments.count,
                            curve: rising(from: segments[k].endPoint))
                }
            }
        }
        return Topology(faces: faces, edges: edges)
    }

    /// A profile segment's exact curve, lifted `height` along the plane normal. A clockwise arc
    /// (`end < start`) is the same circle run counter-clockwise from its end.
    private static func curve(of segment: Segment2D, on plane: Plane, at height: Double) -> EdgeCurve {
        let lift = plane.normal * height
        switch segment {
        case .line(let a, let b):
            return .line(start: plane.point(a) + lift, end: plane.point(b) + lift)
        case .arc(let center, let radius, let start, let end):
            let from = min(start, end).radians
            let first = center + Vector2(cos(from), sin(from)) * radius
            return .circle(center: plane.point(center) + lift, axis: plane.normal, radius: radius,
                           start: plane.point(first) + lift, sweep: abs(end.radians - start.radians))
        }
    }

    /// `other`'s faces and edges, renumbered after `base`'s, appended to `base`.
    private static func appending(_ other: Topology, to base: Topology) -> Topology {
        let faceOffset = base.faces.count
        let edgeOffset = base.edges.count
        var result = base
        for var face in other.faces {
            face.id = FaceID(face.id.rawValue + faceOffset)
            result.faces.append(face)
        }
        for var edge in other.edges {
            edge.id = EdgeID(edge.id.rawValue + edgeOffset)
            edge.faces = edge.faces.map { FaceID($0.rawValue + faceOffset) }
            result.edges.append(edge)
        }
        return result
    }
}
