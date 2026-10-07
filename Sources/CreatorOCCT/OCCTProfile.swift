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

    static func segment(_ segment: Segment2D) -> occt_segment {
        switch segment {
        case .line(let a, let b):
            occt_segment(kind: 0, x0: a.x, y0: a.y, x1: b.x, y1: b.y, cx: 0, cy: 0, radius: 0, start: 0, end: 0)
        case .arc(let center, let radius, let start, let end):
            occt_segment(kind: 1, x0: 0, y0: 0, x1: 0, y1: 0, cx: center.x, cy: center.y, radius: radius,
                         start: start.radians, end: end.radians)
        }
    }

    /// Calls `body` with a C view of `profile` that is valid only inside the call.
    static func with<T, E: Error>(_ profile: Profile2D, _ body: (UnsafePointer<occt_profile>) throws(E) -> T) throws(E) -> T {
        try withAll([profile]) { profiles, _ throws(E) in try body(profiles) }
    }

    /// Calls `body` with C views of every profile (contiguous), valid only inside the call.
    static func withAll<T, E: Error>(_ profiles: [Profile2D], _ body: (UnsafePointer<occt_profile>, Int) throws(E) -> T)
        throws(E) -> T {
        let segments = profiles.flatMap { $0.segments.map(segment) }
        return try segments.withUnsafeBufferPointer { buffer throws(E) in
            var offset = 0
            var views: [occt_profile] = []
            for profile in profiles {
                views.append(occt_profile(plane: plane(profile.plane), segments: buffer.baseAddress.map { $0 + offset },
                                          segment_count: Int32(profile.segments.count)))
                offset += profile.segments.count
            }
            return try views.withUnsafeBufferPointer { viewBuffer throws(E) in
                guard let base = viewBuffer.baseAddress else { preconditionFailure("withAll needs at least one profile") }
                return try body(base, viewBuffer.count)
            }
        }
    }
}
