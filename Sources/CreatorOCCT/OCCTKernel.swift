import CreatorGeometry
import CreatorKernel
import Foundation

/// The OpenCascade-backed kernel (spec §5.2). Every OCCT call is serialized by this actor,
/// which also keeps OCCT's few mutating operations (meshing) safe.
public actor OCCTKernel: Kernel {
    public init() {
        occtInitialize()
    }

    public func extrude(_ profile: Profile2D, distance: Double, mode: ExtrudeMode, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        guard distance.isFinite, distance > 0 else {
            throw KernelError.invalidInput("Extrude distance must be greater than 0 mm.")
        }
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
        throw KernelError.unsupported("boolean")
    }

    public func transform(_ solid: Solid, by transform: Transform, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        throw KernelError.unsupported("transform")
    }

    public func fillet(_ solid: Solid, edges: [EdgeID], radius: Double, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        throw KernelError.unsupported("fillet")
    }

    public func chamfer(_ solid: Solid, edges: [EdgeID], distance: Double, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        throw KernelError.unsupported("chamfer")
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
            let properties = try shape(of: solid).properties()
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
            built = try body()
        } catch let error as OCCTError {
            throw KernelError.occt(operation, error)
        }
        return try solid(from: built.0, history: built.1, inputs: inputs, tag: tag, operation: operation)
    }

    func solid(from shape: OCCTShape, history: [OCCTHistoryRecord], inputs: [Topology], tag: NodeTag,
               operation: String) throws -> Solid {
        do {
            let raw = try OCCTRawTopology.read(shape)
            guard !raw.faces.isEmpty else {
                throw KernelError.operationFailed(operation: operation, reason: "the result is empty.")
            }
            let properties = try shape.properties()
            let topology = OCCTTagger.topology(raw: raw, history: history, inputs: inputs, tag: tag)
            return Solid(topology: topology, bounds: properties.bounds,
                         storage: OCCTSolidStorage(shape: shape, faceCount: raw.faces.count))
        } catch let error as OCCTError {
            throw KernelError.occt(operation, error)
        }
    }
}
