/// A single closed loop of segments lying on `plane`.
public struct Profile2D: Hashable, Sendable {
    public var plane: Plane
    public var segments: [Segment2D]

    public init(plane: Plane, segments: [Segment2D]) {
        self.plane = plane
        self.segments = segments
    }

    /// True when every segment ends where the next begins and the last returns to the first.
    public var isClosed: Bool {
        guard let first = segments.first, let last = segments.last else { return false }
        for (a, b) in zip(segments, segments.dropFirst()) where (a.endPoint - b.startPoint).length > 1e-9 {
            return false
        }
        return (last.endPoint - first.startPoint).length <= 1e-9
    }

    /// World-space bounds of the loop, or `nil` for an empty profile.
    public var bounds: BoundingBox? {
        BoundingBox(points: segments.flatMap(\.boundingPoints).map(plane.point))
    }

    /// A `width` × `height` rectangle centred on the plane origin, counter-clockwise from bottom-left.
    public static func rectangle(width: Double, height: Double, plane: Plane) -> Profile2D {
        let (w, h) = (width / 2, height / 2)
        let corners = [Vector2(-w, -h), Vector2(w, -h), Vector2(w, h), Vector2(-w, h)]
        let segments = corners.indices.map { Segment2D.line(corners[$0], corners[($0 + 1) % 4]) }
        return Profile2D(plane: plane, segments: segments)
    }

    public static func circle(radius: Double, center: Vector2, plane: Plane) -> Profile2D {
        Profile2D(plane: plane, segments: [.arc(center: center, radius: radius, start: Angle(radians: 0), end: Angle(radians: 2 * .pi))])
    }
}
