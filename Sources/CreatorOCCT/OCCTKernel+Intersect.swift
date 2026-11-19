import COCCT
import CreatorGeometry
import CreatorKernel

extension OCCTShape {
    /// The compound of curves where this shape and `other` meet (R14). Call under `OCCTKernel.serialized`.
    func intersectionCurves(with other: OCCTShape) throws(OCCTError) -> OCCTShape {
        try Self.make { status in occt_intersection_curves(raw, other.raw, status) }
    }
}

extension OCCTKernel {
    public func intersectionCurves(_ a: Solid, _ b: Solid, tag: NodeTag) async throws -> [Curve] {
        try Task.checkCancellation()
        let first = try shape(of: a)
        let second = try shape(of: b)
        if a === b || first.raw == second.raw {
            throw KernelError.invalidInput("Intersection Curves needs two different bodies.")
        }
        let compound = try curveShape("intersection curves") { try first.intersectionCurves(with: second) }
        let wires = try Self.serialized { () throws -> [OCCTShape] in try compound.children() }
        try Task.checkCancellation()
        return try wires.map { try curve(from: $0, operation: "intersection curves") }
    }
}
