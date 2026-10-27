import CreatorGeometry
import MetalUI

/// A wire drawn as a chain of bezier pieces in one `Path` (cable ties spec 2026-10-26 §5.1), in coordinates relative to its
/// own frame's origin. An untied wire is one piece.
struct WireShape: Shape, Hashable {
    var pieces: [WireGeometry]

    init(_ pieces: [WireGeometry], origin: Vector2) {
        self.pieces = pieces.map {
            WireGeometry(start: $0.start - origin, control1: $0.control1 - origin, control2: $0.control2 - origin,
                         end: $0.end - origin)
        }
    }

    func path(in rect: Bounds<Pixels>) -> Path {
        Path { path in
            if let first = pieces.first { path.move(to: Self.point(first.start)) }
            for piece in pieces {
                path.addCurve(to: Self.point(piece.end), control1: Self.point(piece.control1), control2: Self.point(piece.control2))
            }
        }
    }

    static func point(_ v: Vector2) -> Point<Pixels> { Point(x: v.x.px, y: v.y.px) }
}
