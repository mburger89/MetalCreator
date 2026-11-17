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

    public func extrude(_ curve: Curve, direction: Vector3, distance: Double, symmetric: Bool, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        guard direction.isFinite, direction.length > 1e-12 else { throw KernelError.invalidInput("The direction can't be zero.") }
        guard distance.isFinite, distance > 0 else { throw KernelError.invalidInput("The distance must be greater than 0 mm.") }
        let wire = try curveShape(of: curve)
        let unit = direction.normalized ?? direction
        return try buildSheet("extrude", tag: tag) {
            try OCCTShape.extrudeCurve(wire, direction: unit, distance: distance, symmetric: symmetric)
        }
    }

    public func revolve(_ curve: Curve, axis: Axis, angle: Angle, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        guard angle.radians.isFinite, angle.radians > 0, angle.radians <= 2 * .pi + 1e-9 else {
            throw KernelError.invalidInput("The angle must be more than 0° and at most 360°.")
        }
        guard let direction = axis.direction.normalized, axis.origin.isFinite else {
            throw KernelError.invalidInput("The direction can't be zero.")
        }
        let wire = try curveShape(of: curve)
        let turned = Axis(origin: axis.origin, direction: direction)
        return try buildSheet("revolve", tag: tag) { try OCCTShape.revolveCurve(wire, axis: turned, angle: angle) }
    }

    public func loftSurface(_ sections: [Curve], ruled: Bool, closed: Bool, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        guard sections.count >= 2 else { throw KernelError.invalidInput("A loft needs at least two sections.") }
        let firstClosed = sections[0].isClosed
        for (index, section) in sections.enumerated() where section.isClosed != firstClosed {
            let this = section.isClosed ? "closed" : "open"
            let first = firstClosed ? "closed" : "open"
            throw KernelError.invalidInput(
                "Section \(index + 1) is \(this) and section 1 is \(first); a loft's sections must all be open or all closed.")
        }
        let wires = try sections.map { try curveShape(of: $0) }
        return try buildSheet("loft", tag: tag) { try OCCTShape.loftCurves(wires, ruled: ruled, closed: closed) }
    }

    /// Runs a sheet builder under the kernel's lock and names the result.
    private func buildSheet(_ operation: String, tag: NodeTag, _ body: () throws -> OCCTShape.SheetBuild) throws -> Solid {
        let built: OCCTShape.SheetBuild
        do {
            // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure.
            built = try Self.serialized { () throws -> OCCTShape.SheetBuild in try body() }
        } catch let error as OCCTError {
            if error.message.hasPrefix("occt: ") { throw KernelError.occt(operation, error) }
            throw KernelError.invalidInput(error.message)
        }
        return try solid(from: built.shape, history: built.history, inputs: [], tag: tag, operation: operation,
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
