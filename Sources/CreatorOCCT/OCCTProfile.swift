import COCCT
import CreatorGeometry

/// Converts profiles and planes to the shim's C structs for the duration of a call.
enum OCCTProfile {
    static func plane(_ plane: Plane) -> occt_plane {
        occt_plane(
            origin: (plane.origin.x, plane.origin.y, plane.origin.z),
            normal: (plane.normal.x, plane.normal.y, plane.normal.z),
            x_axis: (plane.xAxis.x, plane.xAxis.y, plane.xAxis.z)
        )
    }

    /// The side tables kind-2 segments index: pole pairs, distinct knots and multiplicities of every spline, in order.
    struct SplineTables {
        var poles: [Double] = []
        var knots: [Double] = []
        var multiplicities: [Int32] = []
    }

    static func segment(_ segment: Segment2D, tables: inout SplineTables) -> occt_segment {
        switch segment {
        case .line(let a, let b):
            return occt_segment(kind: 0, x0: a.x, y0: a.y, x1: b.x, y1: b.y, cx: 0, cy: 0, radius: 0, start: 0, end: 0,
                                pole_offset: 0, pole_count: 0, knot_offset: 0, knot_count: 0)
        case .arc(let center, let radius, let start, let end):
            return occt_segment(kind: 1, x0: 0, y0: 0, x1: 0, y1: 0, cx: center.x, cy: center.y, radius: radius,
                                start: start.radians, end: end.radians,
                                pole_offset: 0, pole_count: 0, knot_offset: 0, knot_count: 0)
        case .spline(let curve):
            let result = occt_segment(kind: 2, x0: curve.startPoint.x, y0: curve.startPoint.y, x1: curve.endPoint.x,
                                      y1: curve.endPoint.y, cx: 0, cy: 0, radius: 0, start: 0, end: 0,
                                      pole_offset: Int32(tables.poles.count / 2), pole_count: Int32(curve.poles.count),
                                      knot_offset: Int32(tables.knots.count), knot_count: Int32(curve.knots.count))
            for pole in curve.poles { tables.poles += [pole.x, pole.y] }
            tables.knots += curve.knots
            tables.multiplicities += curve.multiplicities.map { Int32($0) }
            return result
        }
    }

    /// Calls `body` with a C view of `profile` that is valid only inside the call.
    static func with<T, E: Error>(_ profile: Profile2D, _ body: (UnsafePointer<occt_profile>) throws(E) -> T) throws(E) -> T {
        try withAll([profile]) { profiles, _ throws(E) in try body(profiles) }
    }

    /// Calls `body` with C views of every profile (contiguous), valid only inside the call. Each
    /// view's loops are the profile's `loops`: outer first, then the holes in order.
    static func withAll<T, E: Error>(_ profiles: [Profile2D], _ body: (UnsafePointer<occt_profile>, Int) throws(E) -> T)
        throws(E) -> T {
        let loops = profiles.flatMap(\.loops)
        var tables = SplineTables()
        let segments = loops.flatMap { loop in loop.map { segment($0, tables: &tables) } }
        return try segments.withUnsafeBufferPointer { segmentBuffer throws(E) in
            try tables.poles.withUnsafeBufferPointer { poleBuffer throws(E) in
            try tables.knots.withUnsafeBufferPointer { knotBuffer throws(E) in
            try tables.multiplicities.withUnsafeBufferPointer { multBuffer throws(E) in
            var offset = 0
            var loopViews: [occt_loop] = []
            for loop in loops {
                loopViews.append(occt_loop(segments: segmentBuffer.baseAddress.map { $0 + offset },
                                           segment_count: Int32(loop.count)))
                offset += loop.count
            }
            return try loopViews.withUnsafeBufferPointer { loopBuffer throws(E) in
                var first = 0
                var views: [occt_profile] = []
                for profile in profiles {
                    views.append(occt_profile(plane: plane(profile.plane), loops: loopBuffer.baseAddress.map { $0 + first },
                                              loop_count: Int32(profile.loops.count),
                                              spline_poles: poleBuffer.baseAddress, spline_knots: knotBuffer.baseAddress,
                                              spline_mults: multBuffer.baseAddress))
                    first += profile.loops.count
                }
                return try views.withUnsafeBufferPointer { viewBuffer throws(E) in
                    guard let base = viewBuffer.baseAddress else { preconditionFailure("withAll needs at least one profile") }
                    return try body(base, viewBuffer.count)
                }
            }
        }
            }
            }
            }
    }
}
