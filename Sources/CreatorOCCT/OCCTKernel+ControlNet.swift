import COCCT
import CreatorGeometry
import CreatorKernel
import Foundation

/// Reading control nets and surface facts (NS-3).
extension OCCTShape {
    /// The B-spline net of face `faceIndex` (0-based). Call under `OCCTKernel.serialized`.
    func surfaceNet(ofFace faceIndex: Int, maxPoles: Int) throws(OCCTError) -> SurfaceNet {
        var raw = occt_surface_net()
        try Self.check { status in occt_control_net_of_face(self.raw, Int32(faceIndex + 1), Int32(maxPoles), &raw, status) }
        defer { occt_surface_net_free(&raw) }
        guard let surface = Self.surface(from: raw) else { throw OCCTError(message: "This surface couldn't be read.") }
        let count = surface.poles.count
        var normals: [Vector3] = []
        normals.reserveCapacity(count)
        if let pointer = raw.normals {
            for index in 0..<count { normals.append(Vector3(pointer[3 * index], pointer[3 * index + 1], pointer[3 * index + 2])) }
        }
        return SurfaceNet(surface: surface, normals: normals,
                          convertedFrom: raw.converted_from < 0 ? nil : Self.surfaceKind(raw.converted_from))
    }

    /// The kind of face `faceIndex`'s surface (0-based) and, for a Bezier or B-spline one, its net. Call under `OCCTKernel.serialized`.
    func surfaceInfo(ofFace faceIndex: Int) throws(OCCTError) -> SurfaceInfo {
        var raw = occt_surface_net()
        try Self.check { status in occt_surface_info(self.raw, Int32(faceIndex + 1), &raw, status) }
        defer { occt_surface_net_free(&raw) }
        return SurfaceInfo(kind: Self.surfaceKind(raw.kind), net: Self.surface(from: raw))
    }

    /// The one-piece curve as a B-spline. Call under `OCCTKernel.serialized`.
    func curveNet() throws(OCCTError) -> CurveNet {
        var raw = occt_curve_net()
        try Self.check { status in occt_control_net_of_curve(self.raw, &raw, status) }
        defer { occt_curve_net_free(&raw) }
        let count = Int(raw.pole_count)
        let poles = (0..<count).map { Vector3(raw.poles[3 * $0], raw.poles[3 * $0 + 1], raw.poles[3 * $0 + 2]) }
        let weights: [Double]? = raw.weights.map { pointer in (0..<count).map { pointer[$0] } }
        let knotCount = Int(raw.knot_count)
        let curve = BSplineCurve3D(degree: Int(raw.degree), poles: poles, weights: weights,
                                   knots: (0..<knotCount).map { raw.knots[$0] },
                                   multiplicities: (0..<knotCount).map { Int(raw.multiplicities[$0]) },
                                   isPeriodic: raw.periodic != 0)
        let kind: CurvePieceKind? = switch raw.converted_from {
        case 0: .line
        case 1: .arc
        case 2: .other
        default: nil
        }
        return CurveNet(curve: curve, isPeriodic: raw.periodic != 0, convertedFrom: kind)
    }

    /// FOR TESTS ONLY. A bilinear sheet of one face with `uCount` x `vCount` poles. Call under `OCCTKernel.serialized`.
    static func bsplineSheet(uCount: Int, vCount: Int, degree: Int) throws(OCCTError) -> OCCTShape {
        try make { status in occt_test_bspline_sheet(Int32(uCount), Int32(vCount), Int32(degree), status) }
    }

    /// FOR TESTS ONLY. How far the normals at the Greville points stray from perpendicular to the surface, and the largest distance
    /// from the surface point at a pole's Greville parameters to that pole. Call under `OCCTKernel.serialized`.
    func netGaps(ofFace faceIndex: Int) throws(OCCTError) -> (normalError: Double, poleGap: Double) {
        var normalError = 0.0
        var poleGap = 0.0
        try Self.check { status in occt_test_net_gaps(self.raw, Int32(faceIndex + 1), &normalError, &poleGap, status) }
        return (normalError, poleGap)
    }

    private static func surface(from raw: occt_surface_net) -> BSplineSurface3D? {
        guard let poles = raw.poles, let knotsU = raw.knots_u, let multU = raw.mult_u, let knotsV = raw.knots_v,
              let multV = raw.mult_v else { return nil }
        let count = Int(raw.u_count) * Int(raw.v_count)
        return BSplineSurface3D(
            degreeU: Int(raw.degree_u), degreeV: Int(raw.degree_v), uCount: Int(raw.u_count), vCount: Int(raw.v_count),
            poles: (0..<count).map { Vector3(poles[3 * $0], poles[3 * $0 + 1], poles[3 * $0 + 2]) },
            weights: raw.weights.map { pointer in (0..<count).map { pointer[$0] } },
            knotsU: (0..<Int(raw.knot_u_count)).map { knotsU[$0] },
            multiplicitiesU: (0..<Int(raw.knot_u_count)).map { Int(multU[$0]) },
            knotsV: (0..<Int(raw.knot_v_count)).map { knotsV[$0] },
            multiplicitiesV: (0..<Int(raw.knot_v_count)).map { Int(multV[$0]) },
            isPeriodicU: raw.periodic_u != 0, isPeriodicV: raw.periodic_v != 0)
    }

    /// The shim's `kind` codes, in order (cocct.h `occt_surface_net`).
    private static let surfaceKinds: [SurfaceKind] = [
        .plane, .cylinder, .cone, .sphere, .torus, .bspline, .other, .bezier, .revolution, .extrusion, .offset,
    ]

    private static func surfaceKind(_ code: Int32) -> SurfaceKind {
        surfaceKinds.indices.contains(Int(code)) ? surfaceKinds[Int(code)] : .other
    }
}

extension OCCTKernel {
    /// The most poles Edit Surface reads (NS-3).
    static let maximumControlPoles = 100_000

    public func controlNet(of surface: Solid) throws -> SurfaceNet {
        guard surface.hasOpenShell else { throw KernelError.invalidInput("Edit Surface takes a sheet; this is a closed solid.") }
        let faceCount = surface.topology.faces.count
        guard faceCount == 1 else {
            throw KernelError.invalidInput(
                "Edit Surface takes a sheet with one face; this one has \(faceCount.formatted(.number.locale(.messages))). "
                    + "Rebuild or Split it first.")
        }
        let shape = try shape(of: surface)
        return try controlNetCall("control net") { try shape.surfaceNet(ofFace: 0, maxPoles: Self.maximumControlPoles) }
    }

    public func controlNet(of curve: Curve) throws -> CurveNet {
        guard curve.pieceCount == 1 else {
            throw KernelError.invalidInput(
                "Edit Curve takes a curve of one piece; this one has \(curve.pieceCount.formatted(.number.locale(.messages))). "
                    + "Rebuild it first.")
        }
        let wire = try curveShape(of: curve)
        return try controlNetCall("control net") { try wire.curveNet() }
    }

    public func surfaceInfo(of face: FaceID, in solid: Solid) throws -> SurfaceInfo {
        guard (0..<solid.topology.faces.count).contains(face.rawValue) else {
            throw KernelError.invalidInput("That face no longer exists.")
        }
        let shape = try shape(of: solid)
        return try controlNetCall("surface info") { try shape.surfaceInfo(ofFace: face.rawValue) }
    }

    /// FOR TESTS ONLY. A one-face sheet of a bilinear B-spline with `uCount` x `vCount` poles.
    func bsplineSheet(uCount: Int, vCount: Int, degree: Int = 1, tag: NodeTag) throws -> Solid {
        let shape: OCCTShape
        do {
            shape = try Self.serialized { () throws -> OCCTShape in
                try OCCTShape.bsplineSheet(uCount: uCount, vCount: vCount, degree: degree)
            }
        } catch let error as OCCTError {
            throw KernelError.occt("test sheet", error)
        }
        return try solid(from: shape, history: [], inputs: [], tag: tag, operation: "test sheet")
    }

    /// FOR TESTS ONLY. See `OCCTShape.netGaps(ofFace:)`.
    func netGaps(of surface: Solid) throws -> (normalError: Double, poleGap: Double) {
        let shape = try shape(of: surface)
        do {
            return try Self.serialized { () throws -> (normalError: Double, poleGap: Double) in try shape.netGaps(ofFace: 0) }
        } catch let error as OCCTError {
            throw KernelError.occt("net gaps", error)
        }
    }

    /// Runs a shim read under the kernel lock, mapping its failure to a `KernelError` in the shim's words.
    private func controlNetCall<T>(_ operation: String, _ body: () throws -> T) throws -> T {
        do {
            // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure.
            return try Self.serialized { () throws -> T in try body() }
        } catch let error as OCCTError {
            if error.message.hasPrefix("occt: ") { throw KernelError.occt(operation, error) }
            throw KernelError.invalidInput(Self.writingIntegers(in: error.message))
        }
    }

    /// The shim marks each whole number in a refusal with \u{1}…\u{2}; this writes them in the message locale.
    static func writingIntegers(in message: String) -> String {
        var out = ""
        var rest = Substring(message)
        while let open = rest.firstIndex(of: "\u{1}") {
            out += rest[rest.startIndex..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "\u{2}") else {
                rest = rest[afterOpen...]
                continue
            }
            let text = rest[afterOpen..<close]
            out += Double(text).map { Int($0).formatted(.number.locale(.messages)) } ?? String(text)
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }
}
