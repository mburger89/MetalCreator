import CreatorGeometry
import MetalUI

/// A wire drawn as a bezier `Path`, in coordinates relative to its own frame's origin.
struct WireShape: Shape, Hashable {
    var start: Vector2
    var control1: Vector2
    var control2: Vector2
    var end: Vector2

    init(_ geometry: WireGeometry, origin: Vector2) {
        start = geometry.start - origin
        control1 = geometry.control1 - origin
        control2 = geometry.control2 - origin
        end = geometry.end - origin
    }

    func path(in rect: Bounds<Pixels>) -> Path {
        Path { path in
            path.move(to: Self.point(start))
            path.addCurve(to: Self.point(end), control1: Self.point(control1), control2: Self.point(control2))
        }
    }

    static func point(_ v: Vector2) -> Point<Pixels> { Point(x: v.x.px, y: v.y.px) }
}
