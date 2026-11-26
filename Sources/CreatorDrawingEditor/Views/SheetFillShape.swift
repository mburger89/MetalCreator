import CreatorDrawing
import CreatorGeometry
import MetalUI

/// Closed polygons (arrowheads) as one filled `Path`, in points relative to its own frame: sheet millimetres times `zoom`, y
/// flipped, `origin` the sheet point (x min, y max) the frame's top left stands on (as `SheetStrokeShape` places its segments).
struct SheetFillShape: Shape, Hashable {
    var polygons: [[Vector2]]
    var zoom: Double
    var origin: Vector2

    func path(in rect: Bounds<Pixels>) -> Path {
        Path { path in
            for polygon in polygons {
                guard let first = polygon.first, polygon.count >= 3 else { continue }
                func local(_ p: Vector2) -> Point<Pixels> {
                    Point(x: ((p.x - origin.x) * zoom).px, y: ((origin.y - p.y) * zoom).px)
                }
                path.move(to: local(first))
                for point in polygon.dropFirst() { path.addLine(to: local(point)) }
                path.closeSubpath()
            }
        }
    }
}
