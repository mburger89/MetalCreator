import CreatorDrawing
import CreatorGeometry
import MetalUI

/// A stroke group's segments as one `Path`, in points relative to its own frame: sheet millimetres times `zoom`, with y
/// flipped. `origin` is the sheet point (x min, y max) the frame's top left stands on. Arcs and ellipses are the cubic
/// Beziers of `SheetSegment.cubics()`, the pieces the PDF writes (plan R12).
struct SheetStrokeShape: Shape, Hashable {
    var segments: [SheetSegment]
    var zoom: Double
    var origin: Vector2

    func path(in rect: Bounds<Pixels>) -> Path {
        Path { path in
            var current: Vector2?
            func local(_ p: Vector2) -> Point<Pixels> {
                Point(x: ((p.x - origin.x) * zoom).px, y: ((origin.y - p.y) * zoom).px)
            }
            func begin(at p: Vector2) {
                if let current, (current - p).length < 1e-9 { return }
                path.move(to: local(p))
            }
            for segment in segments {
                switch segment {
                case let .line(a, b):
                    begin(at: a)
                    path.addLine(to: local(b))
                    current = b
                case let .polyline(points):
                    guard let first = points.first else { continue }
                    begin(at: first)
                    for point in points.dropFirst() { path.addLine(to: local(point)) }
                    current = points.last
                case .arc, .ellipse:
                    for piece in segment.cubics() {
                        begin(at: piece.start)
                        path.addCurve(to: local(piece.end), control1: local(piece.control1), control2: local(piece.control2))
                        current = piece.end
                    }
                }
            }
        }
    }
}
