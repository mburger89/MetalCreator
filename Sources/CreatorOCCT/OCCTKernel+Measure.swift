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
        case .polyline, .curve:
            return try curveOperand(element)
        case .face(let solid, let id):
            guard id.rawValue >= 0, id.rawValue < solid.topology.faces.count else { throw missing }
            return .face(try shape(of: solid), index: id.rawValue + 1)
        case .edge(let solid, let id):
            guard id.rawValue >= 0, id.rawValue < solid.topology.edges.count else { throw missing }
            return .edge(try shape(of: solid), index: id.rawValue + 1)
        }
    }

    private func curveOperand(_ element: MeasureElement) throws -> OCCTMeasureOperand {
        let notFinite = KernelError.invalidInput("That point is not finite.")
        switch element {
        case .polyline(let points):
            guard points.count >= 2 else { throw KernelError.invalidInput("A polyline needs at least two points.") }
            guard points.allSatisfy(\.isFinite) else { throw notFinite }
            return .polyline(points)
        case .curve(.line(let start, let end)):
            guard start.isFinite, end.isFinite else { throw notFinite }
            return .polyline([start, end])
        case .curve(.circle(let centre, let axis, let radius, let start, let sweep)):
            guard centre.isFinite, axis.isFinite, start.isFinite, radius.isFinite, sweep.isFinite else { throw notFinite }
            return .arc(centre: centre, axis: axis, radius: radius, start: start, sweep: sweep)
        default:
            throw KernelError.invalidInput("These can't be measured.")
        }
    }
}
