import COCCT
import CreatorGeometry
import CreatorKernel

/// One side of a blend, as the shim reads it: the shape, a 0-based edge index, 0 to 2 for G0 to G2, and the bulge.
struct BlendEndShape {
    var shape: OCCTShape
    var edge: Int
    var continuity: Int
    var bulge: Double
}

extension OCCTShape {
    /// The sheet joining two edges. Call under `OCCTKernel.serialized`.
    static func blendSurface(_ first: BlendEndShape, _ second: BlendEndShape, cancel: OCCTCancelFlag) throws(OCCTError) -> SheetBuild {
        try buildingSheet { history, roles, status in
            occt_blend_surface(first.shape.raw, Int32(first.edge + 1), Int32(first.continuity), first.bulge,
                               second.shape.raw, Int32(second.edge + 1), Int32(second.continuity), second.bulge,
                               cancel.raw, history, roles, status)
        }
    }
}

extension OCCTKernel {
    public func blendSurface(_ first: SurfaceBlendEnd, _ second: SurfaceBlendEnd, tag: NodeTag) async throws -> Solid {
        try Task.checkCancellation()
        guard (0..<first.body.topology.edges.count).contains(first.edge.rawValue),
              (0..<second.body.topology.edges.count).contains(second.edge.rawValue) else {
            throw KernelError.invalidInput("That edge no longer exists.")
        }
        func grade(_ continuity: PatchContinuity) -> Int { continuity == .g0 ? 0 : continuity == .g1 ? 1 : 2 }
        let one = BlendEndShape(shape: try shape(of: first.body), edge: first.edge.rawValue,
                                continuity: grade(first.continuity), bulge: first.bulge)
        let two = BlendEndShape(shape: try shape(of: second.body), edge: second.edge.rawValue,
                                continuity: grade(second.continuity), bulge: second.bulge)
        let flag = OCCTCancelFlag()
        let result: Solid
        do {
            result = try await withTaskCancellationHandler {
                try buildSheet("blend surface", tag: tag) {
                    try OCCTShape.blendSurface(one, two, cancel: flag)
                }
            } onCancel: { flag.cancel() }
        } catch KernelError.invalidInput(let message) {
            if message == OCCTCancelFlag.message { throw CancellationError() }
            throw KernelError.invalidInput(Self.writingNumbers(in: message))
        }
        try Task.checkCancellation()
        return result
    }
}
