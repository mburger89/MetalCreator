import COCCT
import CreatorGeometry
import CreatorKernel

/// Sheets (NURBS spec): open surface bodies carried in `Solid`, whose free edges are named by `TopoRole.boundary`.
extension OCCTKernel {
    static let notFlat = "The curve isn't flat, so it can't be filled with a plane."
    static let notClosed = "The curve isn't closed, so it can't be filled."
    static let notOneOuterLoop = "The curves must be one outer loop with holes inside it."
    /// How far a loop may stand from the first loop's plane, in millimetres.
    static let planeTolerance = 1e-6

    public func planarSurface(_ loops: [Curve], tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        guard !loops.isEmpty else { throw KernelError.invalidInput(Self.notOneOuterLoop) }
        for loop in loops where !loop.isClosed { throw KernelError.invalidInput(Self.notClosed) }
        var planes: [Plane] = []
        for loop in loops {
            guard let plane = loop.plane else { throw KernelError.invalidInput(Self.notFlat) }
            planes.append(plane)
        }
        let plane = planes[0]
        for loop in loops {
            for point in loop.polyline where abs((point - plane.origin).dot(plane.normal)) > Self.planeTolerance {
                throw KernelError.invalidInput(Self.notFlat)
            }
        }
        let wires = try loops.map { try curveShape(of: $0) }
        let built: (shape: OCCTShape, history: [OCCTHistoryRecord], roles: [BoundaryRole?])
        do {
            // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure.
            built = try Self.serialized { () throws -> (shape: OCCTShape, history: [OCCTHistoryRecord], roles: [BoundaryRole?]) in
                try OCCTShape.planarSurface(loops: wires, plane: plane)
            }
        } catch let error as OCCTError {
            if error.message.hasPrefix("occt: ") { throw KernelError.occt("planar surface", error) }
            throw KernelError.invalidInput(error.message)
        }
        return try solid(from: built.shape, history: built.history, inputs: [], tag: tag, operation: "planar surface",
                         boundaryRoles: built.roles)
    }

    /// The wire behind a curve made by this kernel.
    func curveShape(of curve: Curve) throws -> OCCTShape {
        guard let storage = curve.storage as? OCCTSolidStorage else {
            throw KernelError.invalidInput("This curve was made by a different kernel.")
        }
        return storage.shape
    }
}
