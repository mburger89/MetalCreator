/// A closed region on `plane`: one outer loop of segments and any number of hole loops inside it.
/// Holes may wind either way; the kernel orients them. Loop 0 is `outer`, loop `n` is `holes[n - 1]`,
/// which is the numbering `TopoRole.side(loop:segment:)` uses.
public struct Profile2D: Hashable, Sendable {
    public var plane: Plane
    public var outer: [Segment2D]
    public var holes: [[Segment2D]]

    public init(plane: Plane, outer: [Segment2D], holes: [[Segment2D]] = []) {
        self.plane = plane
        self.outer = outer
        self.holes = holes
    }

    /// A profile without holes.
    public init(plane: Plane, segments: [Segment2D]) {
        self.init(plane: plane, outer: segments)
    }

    /// The outer loop. For a profile without holes this is the whole profile; setting it keeps the holes.
    public var segments: [Segment2D] {
        get { outer }
        set { outer = newValue }
    }

    /// Every loop, outer first: `loops[0] == outer`, `loops[n] == holes[n - 1]`.
    public var loops: [[Segment2D]] { [outer] + holes }

    /// Segments in every loop.
    public var segmentCount: Int { loops.reduce(0) { $0 + $1.count } }

    /// True when every loop is non-empty, each segment ends where the next begins, and the last
    /// returns to the first. Says nothing about holes lying inside the outer loop; the kernel checks that.
    public var isClosed: Bool {
        loops.allSatisfy(Self.isClosedLoop)
    }

    /// World-space bounds of every loop, or `nil` for an empty profile.
    public var bounds: BoundingBox? {
        BoundingBox(points: loops.joined().flatMap(\.boundingPoints).map(plane.point))
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

    private static func isClosedLoop(_ loop: [Segment2D]) -> Bool {
        guard let first = loop.first, let last = loop.last else { return false }
        for (a, b) in zip(loop, loop.dropFirst()) where (a.endPoint - b.startPoint).length > 1e-9 {
            return false
        }
        return (last.endPoint - first.startPoint).length <= 1e-9
    }
}
