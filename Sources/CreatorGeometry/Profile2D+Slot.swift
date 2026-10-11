import Foundation

extension Profile2D {
    /// A slot centred on the plane origin: `length` along the plane's x axis from end to end, `width` across, both
    /// ends half circles. Four segments, counter-clockwise from the bottom edge: bottom, right end, top, left end.
    /// Callers check `0 < width < length`.
    public static func slot(length: Double, width: Double, plane: Plane) -> Profile2D {
        let (reach, r) = ((length - width) / 2, width / 2)
        return Profile2D(plane: plane, segments: [
            .line(Vector2(-reach, -r), Vector2(reach, -r)),
            .arc(center: Vector2(reach, 0), radius: r, start: .degrees(-90), end: .degrees(90)),
            .line(Vector2(reach, r), Vector2(-reach, r)),
            .arc(center: Vector2(-reach, 0), radius: r, start: .degrees(90), end: .degrees(270)),
        ])
    }
}
