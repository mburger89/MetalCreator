import CreatorGeometry
import CreatorKernel
import Foundation
import Synchronization

/// The OpenCascade-backed kernel (spec §5.2). Calls are serialized per kernel by the actor and
/// process-wide by a lock, because OCCT shapes share geometry across solids and some OCCT
/// operations (meshing) mutate it.
public actor OCCTKernel: Kernel {
    private static let occt = Mutex(())

    /// Runs `body` under the process-wide OCCT lock. `body` must not suspend.
    static func serialized<T>(_ body: () throws -> T) rethrows -> T {
        try occt.withLock { _ in try body() }
    }

    /// Rejects planes OCCT cannot build a frame from.
    static func validate(_ plane: Plane) throws {
        let invalid = KernelError.invalidInput("The profile's plane is not valid.")
        guard plane.origin.isFinite, plane.normal.isFinite, plane.xAxis.isFinite,
              let normal = plane.normal.normalized, let xAxis = plane.xAxis.normalized,
              abs(normal.dot(xAxis)) <= 1 - 1e-9 else { throw invalid }
    }

    /// Rejects moves OCCT cannot build.
    static func validate(_ transform: Transform) throws {
        try transform.validate()
    }

    public init() {
        occtInitialize()
    }

    public func extrude(_ profile: Profile2D, distance: Double, mode: ExtrudeMode, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        guard distance.isFinite, distance > 0 else {
            throw KernelError.invalidInput("Extrude distance must be greater than 0 mm.")
        }
        try Self.validate(profile.plane)
        guard profile.isClosed else { throw KernelError.invalidInput("The profile is not a closed loop.") }
        var base = profile
        if mode == .symmetric {
            base.plane = profile.plane.offset(by: -distance / 2)
        }
        return try build("extrude", inputs: [], tag: tag) { try OCCTShape.extrude(base, distance: distance) }
    }

    public func revolve(_ profile: Profile2D, axis: Axis, angle: Angle, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        guard angle.radians.isFinite, angle.radians > 0, angle.radians <= 2 * .pi + 1e-9 else {
            throw KernelError.invalidInput("The revolve angle must be between 0° and 360°.")
        }
        guard axis.direction.normalized != nil, axis.origin.isFinite else {
            throw KernelError.invalidInput("The revolve axis needs a direction.")
        }
        try Self.validate(profile.plane)
        guard profile.isClosed else { throw KernelError.invalidInput("The profile is not a closed loop.") }
        return try build("revolve", inputs: [], tag: tag) { try OCCTShape.revolve(profile, axis: axis, angle: angle) }
    }

    public func loft(_ sections: [Profile2D], ruled: Bool, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        guard sections.count >= 2 else { throw KernelError.invalidInput("A loft needs at least two sections.") }
        guard sections.allSatisfy(\.holes.isEmpty) else {
            throw KernelError.loftWithHoles
        }
        guard Set(sections.map(\.segments.count)).count == 1 else {
            throw KernelError.invalidInput("Every loft section needs the same number of segments.")
        }
        for section in sections { try Self.validate(section.plane) }
        guard sections.allSatisfy(\.isClosed) else { throw KernelError.invalidInput("The profile is not a closed loop.") }
        return try build("loft", inputs: [], tag: tag) { try OCCTShape.loft(sections, ruled: ruled) }
    }

    public func boolean(_ op: BooleanOp, _ a: Solid, _ b: [Solid], tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        guard !b.isEmpty else { throw KernelError.invalidInput("Connect at least one tool solid.") }
        let operation = switch op {
        case .union: "union"
        case .subtract: "subtract"
        case .intersect: "intersect"
        }
        let target = try shape(of: a)
        let tools = try b.map { try shape(of: $0) }
        return try build(operation, inputs: [a.topology] + b.map(\.topology), tag: tag) {
            try OCCTShape.boolean(op, target, tools)
        }
    }

    public func transform(_ solid: Solid, by transform: Transform, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        try Self.validate(transform)
        let source = try shape(of: solid)
        return try build("transform", inputs: [solid.topology], tag: tag) { try source.transformed(by: transform) }
    }

    /// One call for every copy (patterns spec §3, §7): each copy moves its tool's shape (the tool is built once and
    /// shared by every copy that uses it), reads the moved shape's small topology, and requalifies its tags. The
    /// Boolean that follows takes all the copies as one compound of tools; nothing here is a boolean.
    public func place(_ tools: [Solid], at transforms: [Transform], qualifying qualify: @Sendable (NodeID) -> NodeID,
                      tag: NodeTag) throws -> [Solid] {
        try Task.checkCancellation()
        guard tools.count == transforms.count else {
            throw KernelError.invalidInput("Each placed copy needs one tool and one placement.")
        }
        var copies: [Solid] = []
        copies.reserveCapacity(tools.count)
        for (index, pair) in zip(tools, transforms).enumerated() {
            try Task.checkCancellation()
            let (tool, transform) = (pair.0, pair.1)
            try Self.validate(transform)
            let source = try shape(of: tool)
            let moved = try build("place", inputs: [tool.topology], tag: tag) { try source.transformed(by: transform) }
            copies.append(Solid(topology: moved.topology.qualified(item: index, qualify), bounds: moved.bounds, storage: moved.storage))
        }
        return copies
    }

    public func fillet(_ solid: Solid, edges: [EdgeID], radius: Double, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        return try blend(solid, edges: edges, size: radius, chamfer: false, tag: tag)
    }

    public func chamfer(_ solid: Solid, edges: [EdgeID], distance: Double, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        return try blend(solid, edges: edges, size: distance, chamfer: true, tag: tag)
    }

    public func tessellate(_ solid: Solid, tolerance: Double) throws -> DisplayMesh {
        try Task.checkCancellation()
        guard tolerance.isFinite, tolerance > 0 else {
            throw KernelError.invalidInput("The display tolerance must be greater than 0 mm.")
        }
        let source = try shape(of: solid)
        do {
            // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure. Revert once fixed.
            return try Self.serialized { () throws -> DisplayMesh in try source.mesh(tolerance: tolerance) }
        } catch let error as OCCTError {
            throw KernelError.occt("tessellate", error)
        }
    }

    public func export(_ solids: [Solid], format: ExportFormat, to url: URL) throws {
        try Task.checkCancellation()
        guard !solids.isEmpty else { throw KernelError.invalidInput("There is nothing to export.") }
        let shapes = try solids.map { try shape(of: $0) }
        do {
            // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure. Revert once fixed.
            try Self.serialized { () throws in
                let combined = try shapes.count == 1 ? shapes[0] : OCCTShape.compound(shapes)
                switch format {
                case .step: try combined.writeSTEP(to: url)
                case .stl: try combined.writeSTL(to: url, deflection: 0.05)
                }
            }
        } catch let error as OCCTError {
            throw KernelError.exportFailed(KernelError.plainReason(error.message))
        }
    }

    public func meshToSolid(positions: [SIMD3<Float>], triangles: [UInt32], tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        guard triangles.count >= 12, triangles.count % 3 == 0 else {
            throw KernelError.invalidInput("A mesh needs at least four triangles to make a solid.")
        }
        let shape: OCCTShape
        do {
            // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure. Revert once fixed.
            shape = try Self.serialized { () throws -> OCCTShape in try OCCTShape.solid(fromMesh: positions, triangles: triangles) }
        } catch let error as OCCTError {
            // OpenCascade's own reason is the point of the message here, so it is not smoothed over.
            let reason = error.message.hasPrefix("occt: ") ? String(error.message.dropFirst(6)) : error.message
            throw KernelError.operationFailed(operation: "mesh to solid", reason: reason.hasSuffix(".") ? reason : reason + ".")
        }
        return try solid(from: shape, history: [], inputs: [], tag: tag, operation: "mesh to solid")
    }

    public func properties(of solid: Solid) throws -> SolidProperties {
        try Task.checkCancellation()
        do {
            let shape = try shape(of: solid)
            let properties = try Self.serialized { () throws -> OCCTProperties in try shape.properties() }
            return SolidProperties(volume: properties.volume, surfaceArea: properties.surfaceArea, centroid: properties.centroid)
        } catch let error as OCCTError {
            throw KernelError.occt("measure", error)
        }
    }

    /// How many points one call into the shim measures; the batch checks for cancellation between chunks.
    static let distanceChunk = 1024

    /// Distances to a solid's surface, faces or edges (fields spec §3.1): `BRepExtrema_DistShapeShape` from each point and,
    /// for a signed solid distance, a `BRepClass3d_SolidClassifier` for the sign, under `serialized`.
    public func distances(from points: [Vector3], to target: DistanceTarget, signed: Bool) throws -> [Double] {
        try distances(from: points, to: target, signed: signed, afterChunk: {})
    }

    /// `distances(from:to:signed:)` with a hook that runs after each chunk is measured, before the loop's next check for
    /// cancellation. The conformance tests cancel from it to prove the loop stops between chunks.
    func distances(from points: [Vector3], to target: DistanceTarget, signed: Bool,
                   afterChunk: @Sendable () -> Void) throws -> [Double] {
        try Task.checkCancellation()
        try target.validate()
        guard points.allSatisfy(\.isFinite) else {
            throw KernelError.invalidInput("A point to measure from is not a finite position.")
        }
        let source = try shape(of: target.solid)
        let kind: OCCTShape.DistanceKind
        let indices: [Int32]
        switch target {
        case .solid:
            (kind, indices) = (.surface, [])
        case .faces(let set):
            (kind, indices) = (.faces, set.faces.map { Int32($0.rawValue + 1) })
        case .edges(let set):
            (kind, indices) = (.edges, set.edges.map { Int32($0.rawValue + 1) })
        }
        var result: [Double] = []
        result.reserveCapacity(points.count)
        var start = 0
        while start < points.count {
            try Task.checkCancellation()
            let chunk = points[start..<min(start + Self.distanceChunk, points.count)]
            do {
                // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure. Revert once fixed.
                result += try Self.serialized { () throws -> [Double] in
                    try source.distances(from: chunk, kind: kind, indices: indices, signed: signed)
                }
            } catch let error as OCCTError {
                throw KernelError.occt("distance", error)
            }
            start += chunk.count
            afterChunk()
        }
        return result
    }

    // MARK: - Shared plumbing

    /// The OCCT shape behind a solid made by this kernel.
    func shape(of solid: Solid) throws -> OCCTShape {
        guard let storage = solid.storage as? OCCTSolidStorage else {
            throw KernelError.invalidInput("This solid was made by a different kernel.")
        }
        return storage.shape
    }

    /// Runs a shim builder, then reads topology and bounds (no mass properties) and applies tags.
    func build(_ operation: String, inputs: [Topology], tag: NodeTag,
               _ body: () throws -> (OCCTShape, [OCCTHistoryRecord])) throws -> Solid {
        let built: (OCCTShape, [OCCTHistoryRecord])
        do {
            built = try Self.serialized(body)
        } catch let error as OCCTError {
            throw KernelError.occt(operation, error)
        }
        return try solid(from: built.0, history: built.1, inputs: inputs, tag: tag, operation: operation)
    }

    func solid(from shape: OCCTShape, history: [OCCTHistoryRecord], inputs: [Topology], tag: NodeTag,
               operation: String) throws -> Solid {
        do {
            // Untyped throws on purpose: Swift 6.4 crashes ("unsupported collection upcast kind") with typed throws returning a tuple. Revert once fixed.
            let (raw, bounds) = try Self.serialized { () throws -> (OCCTRawTopology, BoundingBox) in
                (try OCCTRawTopology.read(shape), try shape.bounds())
            }
            guard !raw.faces.isEmpty else {
                throw KernelError.operationFailed(operation: operation, reason: "the result is empty.")
            }
            let topology = OCCTTagger.topology(raw: raw, history: history, inputs: inputs, tag: tag)
            return Solid(topology: topology, bounds: bounds,
                         storage: OCCTSolidStorage(shape: shape, faceCount: raw.faces.count))
        } catch let error as OCCTError {
            throw KernelError.occt(operation, error)
        }
    }
}
