import COCCT
import CreatorGeometry
import CreatorKernel
import Foundation

extension OCCTShape {
    /// A copy with face `faceIndex` (0-based) refitted to `spec`, and the largest distance from the source. Call under
    /// `OCCTKernel.serialized`.
    func rebuildingFace(_ faceIndex: Int, as spec: RebuildSpec, cancel: OCCTCancelFlag) throws(OCCTError)
        -> (shape: OCCTShape, deviation: Double) {
        var deviation = 0.0
        let shape = try Self.make { status in
            occt_rebuild_face(self.raw, Int32(faceIndex + 1), Int32(spec.degreeU), Int32(spec.degreeV), Int32(spec.spansU),
                              Int32(spec.spansV), cancel.raw, &deviation, status)
        }
        return (shape, deviation)
    }

    /// The wire refitted as one B-spline, and the largest distance from the source. Call under `OCCTKernel.serialized`.
    func rebuildingCurve(as spec: RebuildSpec, cancel: OCCTCancelFlag) throws(OCCTError) -> (curve: BSplineCurve3D, deviation: Double) {
        var raw = occt_curve_net()
        var deviation = 0.0
        try Self.check { status in
            occt_rebuild_curve(self.raw, Int32(spec.degreeU), Int32(spec.spansU), cancel.raw, &raw, &deviation, status)
        }
        defer { occt_curve_net_free(&raw) }
        let count = Int(raw.pole_count)
        let knotCount = Int(raw.knot_count)
        let curve = BSplineCurve3D(degree: Int(raw.degree),
                                   poles: (0..<count).map { Vector3(raw.poles[3 * $0], raw.poles[3 * $0 + 1], raw.poles[3 * $0 + 2]) },
                                   knots: (0..<knotCount).map { raw.knots[$0] },
                                   multiplicities: (0..<knotCount).map { Int(raw.multiplicities[$0]) })
        return (curve, deviation)
    }
}

extension OCCTKernel {
    public func rebuilt(_ surface: Solid, as spec: RebuildSpec) async throws -> SurfaceRebuild {
        try Task.checkCancellation()
        guard surface.hasOpenShell else { throw KernelError.invalidInput("Rebuild Surface takes a sheet; this is a closed solid.") }
        let faceCount = surface.topology.faces.count
        guard faceCount == 1 else {
            throw KernelError.invalidInput(
                "Rebuild Surface takes a sheet with one face; this one has \(faceCount.formatted(.number.locale(.messages))). "
                    + "Split it first.")
        }
        try spec.validate(forSurface: true)
        let source = try shape(of: surface)
        let flag = OCCTCancelFlag()
        let (shape, deviation) = try await cancellable(flag) {
            try controlNetCall("rebuild surface") { try source.rebuildingFace(0, as: spec, cancel: flag) }
        }
        let sheet = try carryingTopology(of: shape, from: surface, source: source, operation: "rebuild surface")
        return SurfaceRebuild(sheet: sheet, deviation: deviation)
    }

    public func rebuilt(_ curve: Curve, as spec: RebuildSpec, tag: NodeTag) async throws -> CurveRebuild {
        try Task.checkCancellation()
        try spec.validate(forSurface: false)
        let wire = try curveShape(of: curve)
        let flag = OCCTCancelFlag()
        let (spline, deviation) = try await cancellable(flag) {
            try controlNetCall("rebuild curve") { try wire.rebuildingCurve(as: spec, cancel: flag) }
        }
        let made = try await makeCurve([.spline(spline)], tag: tag)
        return CurveRebuild(curve: made, deviation: deviation)
    }

    /// Runs `body` with `flag` set when the task is cancelled; a shim stopped by the flag becomes a `CancellationError`.
    private func cancellable<T: Sendable>(_ flag: OCCTCancelFlag, _ body: () throws -> T) async throws -> T {
        let result: T
        do {
            result = try await withTaskCancellationHandler { try body() } onCancel: { flag.cancel() }
        } catch KernelError.invalidInput(let message) where message == OCCTCancelFlag.message {
            throw CancellationError()
        }
        try Task.checkCancellation()
        return result
    }
}
