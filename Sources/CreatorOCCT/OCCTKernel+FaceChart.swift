import COCCT
import CreatorGeometry
import CreatorKernel

extension OCCTKernel {
    /// How many points go to OCCT at once when a face is projected; cancellation is checked between chunks.
    static let faceChunk = 2_048

    /// The parametrization of `face` (Face mapping, implicit spec §3.5), read off its surface.
    public func faceParametrization(of face: FaceID, in solid: Solid) throws -> FaceParametrization {
        try Task.checkCancellation()
        guard let info = solid.topology.face(face) else { throw KernelError.invalidInput("The face doesn't exist on the solid.") }
        let source = try shape(of: solid)
        let facts: occt_face_chart_info
        do {
            // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure. Revert once fixed.
            facts = try Self.serialized { () throws -> occt_face_chart_info in
                try source.faceChartInfo(faceIndex: Int32(face.rawValue + 1))
            }
        } catch let error as OCCTError {
            throw KernelError.occt("face mapping", error)
        }
        return FaceParametrization(kind: info.kind, uMid: (facts.u_min + facts.u_max) / 2, vMid: (facts.v_min + facts.v_max) / 2,
                                   uScale: facts.u_scale, vScale: facts.v_scale, uPeriod: facts.u_period > 0 ? facts.u_period : nil,
                                   vPeriod: facts.v_period > 0 ? facts.v_period : nil, hasDegenerateEdge: facts.degenerate != 0)
    }

    /// Where `points` stand against `face`: the nearest point of the face by `BRepExtrema`, its (u, v), and the distance along the
    /// face's normal, one chunk at a time under `serialized`.
    public func faceCoordinates(of points: [Vector3], on face: FaceID, in solid: Solid) throws -> [FaceSample] {
        try Task.checkCancellation()
        guard solid.topology.face(face) != nil else { throw KernelError.invalidInput("The face doesn't exist on the solid.") }
        guard points.allSatisfy(\.isFinite) else {
            throw KernelError.invalidInput("A point to project is not a finite position.")
        }
        let source = try shape(of: solid)
        var result: [FaceSample] = []
        result.reserveCapacity(points.count)
        var start = 0
        while start < points.count {
            try Task.checkCancellation()
            let chunk = points[start..<min(start + Self.faceChunk, points.count)]
            let numbers: [Double]
            do {
                // Untyped throws on purpose: see `faceParametrization`.
                numbers = try Self.serialized { () throws -> [Double] in
                    try source.faceCoordinates(of: chunk, faceIndex: Int32(face.rawValue + 1))
                }
            } catch let error as OCCTError {
                throw KernelError.occt("face mapping", error)
            }
            for index in stride(from: 0, to: numbers.count, by: 3) {
                result.append(FaceSample(u: numbers[index], v: numbers[index + 1], depth: numbers[index + 2]))
            }
            start += chunk.count
        }
        return result
    }
}
