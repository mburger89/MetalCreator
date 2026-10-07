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
        let base = mode == .symmetric
            ? Profile2D(plane: profile.plane.offset(by: -distance / 2), segments: profile.segments)
            : profile
        return try build("extrude", inputs: [], tag: tag) { try OCCTShape.extrude(base, distance: distance) }
    }

    public func revolve(_ profile: Profile2D, axis: Axis, angle: Angle, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        throw KernelError.unsupported("revolve")
    }

    public func loft(_ sections: [Profile2D], ruled: Bool, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        throw KernelError.unsupported("loft")
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
        guard transform.translation.isFinite, transform.rotation.radians.isFinite else {
            throw KernelError.invalidInput("The move or rotation must be a finite number.")
        }
        if let axis = transform.rotationAxis, axis.direction.normalized == nil {
            throw KernelError.invalidInput("The rotation axis needs a direction.")
        }
        let source = try shape(of: solid)
        return try build("transform", inputs: [solid.topology], tag: tag) { try source.transformed(by: transform) }
    }

    public func fillet(_ solid: Solid, edges: [EdgeID], radius: Double, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        return try blend(solid, edges: edges, size: radius, chamfer: false, tag: tag)
    }

    public func chamfer(_ solid: Solid, edges: [EdgeID], distance: Double, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        return try blend(solid, edges: edges, size: distance, chamfer: true, tag: tag)
    }

    private func blend(_ solid: Solid, edges: [EdgeID], size: Double, chamfer: Bool, tag: NodeTag) throws -> Solid {
        guard size.isFinite, size > 0 else { throw KernelError.invalidInput("The size must be greater than 0 mm.") }
        guard !edges.isEmpty else { throw KernelError.invalidInput("No edges are selected.") }
        if let missing = edges.first(where: { solid.topology.edge($0) == nil }) {
            throw KernelError.invalidInput("Edge \(missing.rawValue) doesn't exist on the input solid.")
        }
        let source = try shape(of: solid)
        let operation = chamfer ? "chamfer" : "fillet"
        return try build(operation, inputs: [solid.topology], tag: tag) {
            do {
                return try source.blended(edges: edges, size: size, chamfer: chamfer)
            } catch is OCCTError {
                if chamfer {
                    let amount = size.formatted(.number.precision(.fractionLength(0...2)))
                    throw KernelError.operationFailed(operation: "chamfer",
                                                      reason: "the selected edges can't be chamfered by \(amount) mm.")
                }
                throw KernelError.filletFailed(radius: size, maxRadius: nil,
                                               reason: "the selected edges can't be rounded this much.")
            }
        }
    }

    public func tessellate(_ solid: Solid, tolerance: Double) throws -> DisplayMesh {
        try Task.checkCancellation()
        throw KernelError.unsupported("tessellate")
    }

    public func export(_ solids: [Solid], format: ExportFormat, to url: URL) throws {
        try Task.checkCancellation()
        throw KernelError.unsupported("export")
    }

    public func properties(of solid: Solid) throws -> SolidProperties {
        try Task.checkCancellation()
        do {
            let shape = try shape(of: solid)
            let properties = try Self.serialized { () throws(OCCTError) in try shape.properties() }
            return SolidProperties(volume: properties.volume, surfaceArea: properties.surfaceArea, centroid: properties.centroid)
        } catch let error as OCCTError {
            throw KernelError.occt("measure", error)
        }
    }

    // MARK: - Shared plumbing

    /// The OCCT shape behind a solid made by this kernel.
    func shape(of solid: Solid) throws -> OCCTShape {
        guard let storage = solid.storage as? OCCTSolidStorage else {
            throw KernelError.invalidInput("This solid was made by a different kernel.")
        }
        return storage.shape
    }

    /// Runs a shim builder, then reads topology and bounds and applies tags.
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
            let (raw, properties) = try Self.serialized { () throws -> (OCCTRawTopology, OCCTProperties) in
                (try OCCTRawTopology.read(shape), try shape.properties())
            }
            guard !raw.faces.isEmpty else {
                throw KernelError.operationFailed(operation: operation, reason: "the result is empty.")
            }
            let topology = OCCTTagger.topology(raw: raw, history: history, inputs: inputs, tag: tag)
            return Solid(topology: topology, bounds: properties.bounds,
                         storage: OCCTSolidStorage(shape: shape, faceCount: raw.faces.count))
        } catch let error as OCCTError {
            throw KernelError.occt(operation, error)
        }
    }
}
