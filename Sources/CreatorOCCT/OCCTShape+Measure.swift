import COCCT
import CreatorGeometry
import CreatorKernel

/// One side of a shortest-distance query as the shim takes it: a point, a face or edge of a shape, a polyline or a circle arc.
struct OCCTMeasureOperand {
    var shape: OCCTShape?
    var kind: Int32
    var index: Int32
    var point: [Double]
    var polyline: [Double] = []
    var circle: Arc?

    struct Arc {
        var centre: Vector3
        var axis: Vector3
        var start: Vector3
        var radius: Double
        var sweep: Double
    }

    static func point(_ point: Vector3) -> OCCTMeasureOperand {
        OCCTMeasureOperand(shape: nil, kind: 0, index: 0, point: [point.x, point.y, point.z])
    }

    static func face(_ shape: OCCTShape, index: Int) -> OCCTMeasureOperand {
        OCCTMeasureOperand(shape: shape, kind: 1, index: Int32(index), point: [0, 0, 0])
    }

    static func edge(_ shape: OCCTShape, index: Int) -> OCCTMeasureOperand {
        OCCTMeasureOperand(shape: shape, kind: 2, index: Int32(index), point: [0, 0, 0])
    }

    static func polyline(_ points: [Vector3]) -> OCCTMeasureOperand {
        OCCTMeasureOperand(shape: nil, kind: 3, index: 0, point: [0, 0, 0], polyline: points.flatMap { [$0.x, $0.y, $0.z] })
    }

    static func arc(centre: Vector3, axis: Vector3, radius: Double, start: Vector3, sweep: Double) -> OCCTMeasureOperand {
        OCCTMeasureOperand(shape: nil, kind: 4, index: 0, point: [0, 0, 0],
                           circle: Arc(centre: centre, axis: axis, start: start, radius: radius, sweep: sweep))
    }

    /// Runs `body` with the shim's struct; the polyline's buffer lives until `body` returns.
    func withRaw<R>(_ body: (inout occt_measure_operand) throws -> R) rethrows -> R {
        try polyline.withUnsafeBufferPointer { buffer in
            var raw = occt_measure_operand()
            raw.shape = shape?.raw
            raw.kind = Int32(kind)
            raw.index = index
            raw.point = (point[0], point[1], point[2])
            if kind == 3 {
                raw.points = buffer.baseAddress
                raw.point_count = Int32(buffer.count / 3)
            }
            if let circle {
                raw.centre = (circle.centre.x, circle.centre.y, circle.centre.z)
                raw.axis = (circle.axis.x, circle.axis.y, circle.axis.z)
                raw.start = (circle.start.x, circle.start.y, circle.start.z)
                raw.radius = circle.radius
                raw.sweep = circle.sweep
            }
            return try body(&raw)
        }
    }
}

extension OCCTShape {
    /// The shortest distance between two operands (`occt_shortest_distance`). Call under `OCCTKernel.serialized`.
    static func shortestDistance(_ a: OCCTMeasureOperand, _ b: OCCTMeasureOperand) throws(OCCTError) -> ShapeDistance {
        var raw = occt_shape_distance()
        try check { status in
            a.withRaw { first in
                b.withRaw { second in
                    occt_shortest_distance(&first, &second, &raw, status)
                }
            }
        }
        return ShapeDistance(distance: raw.distance, from: Vector3(raw.from.0, raw.from.1, raw.from.2),
                             to: Vector3(raw.to.0, raw.to.1, raw.to.2))
    }
}
