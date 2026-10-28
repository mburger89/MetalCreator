import CreatorGeometry
@testable import CreatorSketch

/// A 60 × 40 plate from (0, 0) with a hole `c1` at (15, 20) and `c2` at (45, 20), radius 4: `l0`…`l3` are the bottom, right,
/// top and left lines, `corners[i]` the start of `l[i]`. The corner is fixed and the sides horizontal or vertical, with no
/// sizes, so the holes and the sizes are free.
struct HoledPlate {
    var sketch = Sketch()
    let lines: [SketchEntityID]
    let corners: [SketchEntityID]
    let c1: SketchEntityID
    let c2: SketchEntityID

    init() {
        var built = Sketch()
        let sides = addPolygon(&built, [.zero, Vector2(60, 0), Vector2(60, 40), Vector2(0, 40)])
        lines = sides
        corners = sides.map { built.ends($0).0 }
        sketch = built
        c1 = sketch.addCircle(center: Vector2(15, 20), radius: 4)
        c2 = sketch.addCircle(center: Vector2(45, 20), radius: 4)
        sketch.add(.fix(corners[0], at: .zero))
        sketch.add(.horizontal(lines[0]))
        sketch.add(.vertical(lines[1]))
        sketch.add(.horizontal(lines[2]))
        sketch.add(.vertical(lines[3]))
    }
}
