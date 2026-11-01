import CreatorGeometry
import CreatorKernel

extension OCCTKernel {
    /// The cross-section of `solid` by `plane` through `BRepAlgoAPI_Common` with a planar face (section analysis part B).
    public func section(_ solid: Solid, by plane: Plane, tolerance: Double) throws -> PlaneSection {
        try Task.checkCancellation()
        guard tolerance.isFinite, tolerance > 0 else {
            throw KernelError.invalidInput("The section tolerance must be greater than 0 mm.")
        }
        guard plane.origin.isFinite, plane.normal.isFinite, plane.xAxis.isFinite, abs(plane.normal.length - 1) < 1e-6 else {
            throw KernelError.invalidInput("The section plane is not a finite plane with a unit normal.")
        }
        guard abs(plane.xAxis.dot(plane.normal)) < 1e-6 * max(plane.xAxis.length, 1e-300), plane.xAxis.length > 1e-12 else {
            throw KernelError.invalidInput("The section plane's x axis must be perpendicular to its normal.")
        }
        let source = try shape(of: solid)
        do {
            // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure. Revert once fixed.
            return try Self.serialized { () throws -> PlaneSection in try source.section(by: plane, tolerance: tolerance) }
        } catch let error as OCCTError {
            throw KernelError.occt("section", error)
        }
    }
}
