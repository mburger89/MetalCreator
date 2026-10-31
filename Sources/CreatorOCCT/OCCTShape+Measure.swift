import COCCT
import CreatorGeometry
import CreatorKernel

/// One side of a shortest-distance query as the shim takes it: a kind (0 point, 1 face, 2 edge), a 1-based index and a point.
struct OCCTMeasureOperand {
    var shape: OCCTShape?
    var kind: Int32
    var index: Int32
    var point: [Double]

    static func point(_ point: Vector3) -> OCCTMeasureOperand {
        OCCTMeasureOperand(shape: nil, kind: 0, index: 0, point: [point.x, point.y, point.z])
    }

    static func face(_ shape: OCCTShape, index: Int) -> OCCTMeasureOperand {
        OCCTMeasureOperand(shape: shape, kind: 1, index: Int32(index), point: [0, 0, 0])
    }

    static func edge(_ shape: OCCTShape, index: Int) -> OCCTMeasureOperand {
        OCCTMeasureOperand(shape: shape, kind: 2, index: Int32(index), point: [0, 0, 0])
    }
}

extension OCCTShape {
    /// The shortest distance between two operands (`occt_shortest_distance`). Call under `OCCTKernel.serialized`.
    static func shortestDistance(_ a: OCCTMeasureOperand, _ b: OCCTMeasureOperand) throws(OCCTError) -> ShapeDistance {
        var raw = occt_shape_distance()
        try check { status in
            occt_shortest_distance(a.shape?.raw, a.kind, a.index, a.point, b.shape?.raw, b.kind, b.index, b.point, &raw, status)
        }
        return ShapeDistance(distance: raw.distance, from: Vector3(raw.from.0, raw.from.1, raw.from.2),
                             to: Vector3(raw.to.0, raw.to.1, raw.to.2))
    }
}
