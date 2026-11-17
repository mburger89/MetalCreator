import COCCT
import CreatorGeometry
import Foundation

/// What the shim reads of a curve's wire.
struct OCCTCurveInfo {
    var pieceCount: Int
    var isClosed: Bool
    var plane: Plane?
    var length: Double
    var bounds: BoundingBox
    var polyline: [Vector3]
}

extension OCCTShape {
    /// A wire over `pieces`. Call under `OCCTKernel.serialized`.
    static func makeCurve(_ pieces: [CurvePiece]) throws(OCCTError) -> OCCTShape {
        // A spline's arrays are copied to heap buffers that the raw structs point at until the call returns.
        var doubleBuffers: [UnsafeMutablePointer<Double>] = []
        var intBuffers: [UnsafeMutablePointer<Int32>] = []
        defer {
            doubleBuffers.forEach { $0.deallocate() }
            intBuffers.forEach { $0.deallocate() }
        }
        func copy(_ values: [Double]) -> UnsafePointer<Double> {
            let buffer = UnsafeMutablePointer<Double>.allocate(capacity: max(1, values.count))
            buffer.initialize(from: values, count: values.count)
            doubleBuffers.append(buffer)
            return UnsafePointer(buffer)
        }
        func copy(_ values: [Int]) -> UnsafePointer<Int32> {
            let buffer = UnsafeMutablePointer<Int32>.allocate(capacity: max(1, values.count))
            buffer.initialize(from: values.map { Int32($0) }, count: values.count)
            intBuffers.append(buffer)
            return UnsafePointer(buffer)
        }
        var raws: [occt_curve_piece] = []
        for piece in pieces {
            var raw = occt_curve_piece()
            switch piece {
            case .line(let a, let b):
                raw.kind = 0
                raw.a = (a.x, a.y, a.z)
                raw.b = (b.x, b.y, b.z)
            case .arc(let center, let normal, let radius, let start, let sweep):
                raw.kind = 1
                raw.a = (center.x, center.y, center.z)
                raw.b = (normal.x, normal.y, normal.z)
                raw.c = (start.x, start.y, start.z)
                raw.radius = radius
                raw.sweep = sweep
            case .spline(let spline):
                raw.kind = 2
                raw.degree = Int32(spline.degree)
                raw.pole_count = Int32(spline.poles.count)
                raw.poles = copy(spline.poles.flatMap { [$0.x, $0.y, $0.z] })
                raw.weights = spline.weights.map { copy($0) }
                raw.knot_count = Int32(spline.knots.count)
                raw.knots = copy(spline.knots)
                raw.multiplicities = copy(spline.multiplicities)
            }
            raws.append(raw)
        }
        let count = Int32(raws.count)
        return try make { status in raws.withUnsafeBufferPointer { occt_make_curve($0.baseAddress, count, status) } }
    }

    /// A one-edge wire through `points`. Call under `OCCTKernel.serialized`.
    static func interpolatedCurve(_ points: [Vector3], degree: Int, closed: Bool, startTangent: Vector3?, endTangent: Vector3?,
                                  maxDeviation: Double) throws(OCCTError) -> OCCTShape {
        let flat = points.flatMap { [$0.x, $0.y, $0.z] }
        let start = startTangent.map { [$0.x, $0.y, $0.z] }
        let end = endTangent.map { [$0.x, $0.y, $0.z] }
        return try make { status in
            flat.withUnsafeBufferPointer { buffer in
                withOptionalPointer(start) { startPointer in
                    withOptionalPointer(end) { endPointer in
                        occt_interpolate_curve(buffer.baseAddress, Int32(points.count), Int32(degree), closed ? 1 : 0,
                                               startPointer, endPointer, maxDeviation, status)
                    }
                }
            }
        }
    }

    private static func withOptionalPointer<R>(_ values: [Double]?, _ body: (UnsafePointer<Double>?) -> R) -> R {
        guard let values else { return body(nil) }
        return values.withUnsafeBufferPointer { body($0.baseAddress) }
    }

    /// The wires `indices` (1-based edge numbers) chain into, as a compound.
    func curves(fromEdges indices: [Int32]) throws(OCCTError) -> OCCTShape {
        try Self.make { status in
            indices.withUnsafeBufferPointer { occt_curves_from_edges(raw, $0.baseAddress, Int32(indices.count), status) }
        }
    }

    /// The children of a compound made by `curves(fromEdges:)`, in order.
    func children() throws(OCCTError) -> [OCCTShape] {
        var result: [OCCTShape] = []
        for index in 0..<Int(occt_compound_child_count(raw)) {
            result.append(try Self.make { status in occt_compound_child(raw, Int32(index), status) })
        }
        return result
    }

    func curveInfo() throws(OCCTError) -> OCCTCurveInfo {
        var info = occt_curve_info()
        try Self.check { status in occt_curve_info_of(raw, &info, status) }
        defer { occt_curve_info_free(&info) }
        let polyline = (0..<Int(info.polyline_count)).map { i in
            Vector3(info.polyline[3 * i], info.polyline[3 * i + 1], info.polyline[3 * i + 2])
        }
        let plane: Plane? = info.planar == 0 ? nil : Plane(
            origin: Vector3(info.plane_origin.0, info.plane_origin.1, info.plane_origin.2),
            normal: Vector3(info.plane_normal.0, info.plane_normal.1, info.plane_normal.2),
            xAxis: Vector3(info.plane_x.0, info.plane_x.1, info.plane_x.2))
        return OCCTCurveInfo(pieceCount: Int(info.piece_count), isClosed: info.is_closed != 0, plane: plane,
                             length: info.length,
                             bounds: BoundingBox(min: Vector3(info.min.0, info.min.1, info.min.2),
                                                 max: Vector3(info.max.0, info.max.1, info.max.2)),
                             polyline: polyline)
    }

    func curveDistance(to point: Vector3) throws(OCCTError) -> Double {
        var status = occt_status()
        let value = occt_test_curve_distance(raw, point.x, point.y, point.z, &status)
        guard status.ok != 0 else { throw OCCTError(message: status.messageText) }
        return value
    }
}
