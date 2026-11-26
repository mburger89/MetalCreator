import CreatorDrawing
import CreatorGeometry
import MetalUI

/// One closed polygon (an arrowhead, a symbol triangle) as its own filled `Path`, in points relative to its own frame: sheet millimetres
/// times `zoom`, y flipped, `origin` the sheet point (x min, y max) the frame's top left stands on (as `SheetStrokeShape` places its
/// segments). Each fill is its own path, so overlapping fills never cancel whatever their winding (drawings minors R4).
struct SheetFillShape: Shape, Hashable {
    var polygon: [Vector2]
    var zoom: Double
    var origin: Vector2

    func path(in rect: Bounds<Pixels>) -> Path {
        Path { path in
            guard polygon.count >= 3, let first = polygon.first else { return }
            func local(_ p: Vector2) -> Point<Pixels> {
                Point(x: ((p.x - origin.x) * zoom).px, y: ((origin.y - p.y) * zoom).px)
            }
            path.move(to: local(first))
            for point in polygon.dropFirst() { path.addLine(to: local(point)) }
            path.closeSubpath()
        }
    }
}
