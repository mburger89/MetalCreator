// Test fixture file: sketches shared by solver, region and command tests (several helpers by design).
import CreatorGeometry
@testable import CreatorSketch

/// The spec §10 rectangle: corners (0,0) (60,0) (60,40) (0,40), fixed at the origin, horizontal
/// bottom/top, vertical left/right, width 60 on the bottom line and height 40 on the left line.
/// Drawn slightly off so the solver has work to do. Lines: bottom, right, top, left.
struct ConstrainedRectangle {
    var sketch = Sketch()
    let lines: [SketchEntityID]
    let width: DimensionID
    let height: DimensionID

    init(drawnOffset: Double = 0.7) {
        let o = drawnOffset
        lines = addPolygon(&sketch, [Vector2(o, -o), Vector2(60 + o, o), Vector2(60 - o, 40 + o), Vector2(-o, 40 - o)])
        let (origin, _) = sketch.ends(lines[0])
        sketch.add(.fix(origin, at: .zero))
        sketch.add(.horizontal(lines[0]))
        sketch.add(.vertical(lines[1]))
        sketch.add(.horizontal(lines[2]))
        sketch.add(.vertical(lines[3]))
        width = sketch.addDimension(.length(lines[0]), value: 60)
        height = sketch.addDimension(.length(lines[3]), value: 40)
    }

    /// Corner i is the start of line i.
    func corner(_ i: Int, in solution: SketchSolution) -> Vector2? {
        solution.points[sketch.ends(lines[i]).0]
    }
}
