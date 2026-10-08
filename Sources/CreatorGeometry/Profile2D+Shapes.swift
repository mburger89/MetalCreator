import Foundation

extension Profile2D {
    /// The same profile, holes included, moved by `offset` in plane coordinates.
    public func translated(by offset: Vector2) -> Profile2D {
        Profile2D(plane: plane, outer: outer.map { $0.translated(by: offset) },
                  holes: holes.map { hole in hole.map { $0.translated(by: offset) } })
    }

    /// A `width` × `height` rectangle with quarter-circle corners of `radius`, centred on the plane
    /// origin. Eight segments, counter-clockwise from the bottom edge: bottom, bottom-right corner,
    /// right, top-right, top, top-left, left, bottom-left. Callers check
    /// `0 < radius < min(width, height) / 2`.
    public static func roundedRectangle(width: Double, height: Double, radius: Double, plane: Plane) -> Profile2D {
        let (x, y, r) = (width / 2, height / 2, radius)
        func corner(_ cx: Double, _ cy: Double, from degrees: Double) -> Segment2D {
            .arc(center: Vector2(cx, cy), radius: r, start: .degrees(degrees), end: .degrees(degrees + 90))
        }
        return Profile2D(plane: plane, segments: [
            .line(Vector2(-x + r, -y), Vector2(x - r, -y)), corner(x - r, -y + r, from: 270),
            .line(Vector2(x, -y + r), Vector2(x, y - r)), corner(x - r, y - r, from: 0),
            .line(Vector2(x - r, y), Vector2(-x + r, y)), corner(-x + r, y - r, from: 90),
            .line(Vector2(-x, y - r), Vector2(-x, -y + r)), corner(-x + r, -y + r, from: 180),
        ])
    }

    /// A regular polygon with `sides` corners on a circle of `radius` (circumradius) about the plane
    /// origin, the first corner on +x, counter-clockwise. Callers check `sides >= 3`.
    public static func regularPolygon(sides: Int, radius: Double, plane: Plane) -> Profile2D {
        let corners = (0..<sides).map { k in
            let angle = 2 * Double.pi * Double(k) / Double(sides)
            return Vector2(radius * cos(angle), radius * sin(angle))
        }
        return polyline(corners, closed: true, plane: plane)
    }

    /// Straight segments through `points`; `closed` adds the segment from the last point back to the first.
    public static func polyline(_ points: [Vector2], closed: Bool, plane: Plane) -> Profile2D {
        var segments = zip(points, points.dropFirst()).map { Segment2D.line($0, $1) }
        if closed, let first = points.first, let last = points.last, points.count > 2 {
            segments.append(.line(last, first))
        }
        return Profile2D(plane: plane, segments: segments)
    }
}
