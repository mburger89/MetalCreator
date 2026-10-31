import CreatorGeometry
import CreatorKernel

extension OCCTKernel {
    /// The exact shortest distance between two elements through `BRepExtrema_DistShapeShape` (Measure).
    public func shortestDistance(between first: MeasureElement, and second: MeasureElement) throws -> ShapeDistance {
        try Task.checkCancellation()
        let a = try operand(first), b = try operand(second)
        do {
            // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure. Revert once fixed.
            return try Self.serialized { () throws -> ShapeDistance in try OCCTShape.shortestDistance(a, b) }
        } catch let error as OCCTError {
            throw KernelError.occt("measure", error)
        }
    }

    private func operand(_ element: MeasureElement) throws -> OCCTMeasureOperand {
        let missing = KernelError.invalidInput("That face or edge no longer exists.")
        switch element {
        case .point(let point):
            guard point.isFinite else { throw KernelError.invalidInput("That point is not finite.") }
            return .point(point)
        case .face(let solid, let id):
            guard id.rawValue >= 0, id.rawValue < solid.topology.faces.count else { throw missing }
            return .face(try shape(of: solid), index: id.rawValue + 1)
        case .edge(let solid, let id):
            guard id.rawValue >= 0, id.rawValue < solid.topology.edges.count else { throw missing }
            return .edge(try shape(of: solid), index: id.rawValue + 1)
        }
    }
}
