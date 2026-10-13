import COCCT
import CreatorGeometry

extension OCCTShape {
    /// What `distances(from:kind:indices:signed:)` measures to (`occt_distances`' `kind`).
    enum DistanceKind: Int32 {
        /// The surface of the whole shape.
        case surface = 0
        /// The faces at the given 1-based indices.
        case faces = 1
        /// The edges at the given 1-based indices.
        case edges = 2
    }

    /// One distance per point, in order (see `occt_distances`). Call under `OCCTKernel.serialized`.
    func distances(from points: ArraySlice<Vector3>, kind: DistanceKind, indices: [Int32],
                   signed: Bool) throws(OCCTError) -> [Double] {
        try run(from: points, kind: kind, indices: indices, signed: signed, call: occt_distances)
    }

    /// The same distances by `BRepExtrema` alone, without the analytic path for planes and cylinders
    /// (`occt_distances_reference`): what the fast path is tested against.
    func distancesByExtrema(from points: ArraySlice<Vector3>, kind: DistanceKind, indices: [Int32],
                            signed: Bool) throws(OCCTError) -> [Double] {
        try run(from: points, kind: kind, indices: indices, signed: signed, call: occt_distances_reference)
    }

    private typealias Measure = (OpaquePointer?, Int32, UnsafePointer<Int32>?, Int32, UnsafePointer<Double>?, Int32, Int32,
                                 UnsafeMutablePointer<Double>?, UnsafeMutablePointer<occt_status>?) -> Int32

    private func run(from points: ArraySlice<Vector3>, kind: DistanceKind, indices: [Int32], signed: Bool,
                         call: Measure) throws(OCCTError) -> [Double] {
        guard !points.isEmpty else { return [] }
        var coordinates: [Double] = []
        coordinates.reserveCapacity(points.count * 3)
        for point in points {
            coordinates.append(point.x)
            coordinates.append(point.y)
            coordinates.append(point.z)
        }
        var result = [Double](repeating: 0, count: points.count)
        let count = Int32(points.count)
        try Self.check { status in
            indices.withUnsafeBufferPointer { ids in
                coordinates.withUnsafeBufferPointer { xyz in
                    result.withUnsafeMutableBufferPointer { out in
                        call(self.raw, kind.rawValue, ids.baseAddress, Int32(ids.count), xyz.baseAddress, count,
                                       signed ? 1 : 0, out.baseAddress, status)
                    }
                }
            }
        }
        return result
    }
}
