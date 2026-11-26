import CreatorDrawing
import CreatorGeometry
import MetalUI

/// Closed polygons (arrowheads, symbol triangles) as one filled `Path`, in points relative to its own frame: sheet millimetres times `zoom`, y
/// flipped, `origin` the sheet point (x min, y max) the frame's top left stands on (as `SheetStrokeShape` places its segments).
struct SheetFillShape: Shape, Hashable {
    var polygons: [[Vector2]]
    var zoom: Double
    var origin: Vector2

    func path(in rect: Bounds<Pixels>) -> Path {
        Path { path in
            for drawn in polygons {
                guard drawn.count >= 3 else { continue }
                let polygon = Self.counterClockwise(drawn)
                guard let first = polygon.first else { continue }
                func local(_ p: Vector2) -> Point<Pixels> {
                    Point(x: ((p.x - origin.x) * zoom).px, y: ((origin.y - p.y) * zoom).px)
                }
                path.move(to: local(first))
                for point in polygon.dropFirst() { path.addLine(to: local(point)) }
                path.closeSubpath()
            }
        }
    }

    /// The polygon wound counter-clockwise in sheet coordinates (y up), so the fills of one path never cancel where they overlap
    /// under the non-zero rule (DR-4 R9).
    static func counterClockwise(_ polygon: [Vector2]) -> [Vector2] {
        var area = 0.0
        for index in polygon.indices {
            let a = polygon[index], b = polygon[(index + 1) % polygon.count]
            area += a.x * b.y - b.x * a.y
        }
        return area < 0 ? polygon.reversed() : polygon
    }
}
