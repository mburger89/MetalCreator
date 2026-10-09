// Test fixture file: sketches for the Sketch node tests (several helpers by design).
import CreatorGeometry
import CreatorSketch

/// A `width` × `height` rectangle with its bottom-left corner fixed at `origin`, fully constrained:
/// horizontal bottom and top, vertical sides, `width` (d1) on the bottom line and `height` (d2) on the
/// left line. Drawn slightly off so the solver has work to do. Lines: bottom, right, top, left.
struct RectangleSketch {
    var sketch: Sketch
    let lines: [SketchEntityID]
    let corners: [SketchEntityID]
    let width: DimensionID
    let height: DimensionID

    init(width: Double = 60, height: Double = 40, origin: Vector2 = .zero, plane: SketchPlaneSource = .fixed(.xy)) {
        var sketch = Sketch(plane: plane)
        let drawn = [Vector2(0.5, -0.3), Vector2(width + 0.4, 0.2), Vector2(width - 0.3, height + 0.5), Vector2(-0.2, height - 0.4)]
        let corners = drawn.map { sketch.addPoint($0 + origin) }
        let lines = corners.indices.map { sketch.addLine(from: corners[$0], to: corners[($0 + 1) % 4]) }
        sketch.add(.fix(corners[0], at: origin))
        sketch.add(.horizontal(lines[0]))
        sketch.add(.vertical(lines[1]))
        sketch.add(.horizontal(lines[2]))
        sketch.add(.vertical(lines[3]))
        self.width = sketch.addDimension(.length(lines[0]), value: width)
        self.height = sketch.addDimension(.length(lines[3]), value: height)
        self.sketch = sketch
        self.lines = lines
        self.corners = corners
    }

    /// Adds a fully constrained circle (fixed centre, radius dimension) and returns the radius dimension.
    @discardableResult
    mutating func addHole(center: Vector2, radius: Double) -> DimensionID {
        let circle = sketch.addCircle(center: center, radius: radius * 1.1)
        guard case .circle(let centre, _)? = sketch.entities[circle]?.kind else { preconditionFailure("not a circle") }
        sketch.add(.fix(centre, at: center))
        return sketch.addDimension(.radius(circle), value: radius)
    }

    mutating func expose(_ id: DimensionID) {
        sketch.dimensions[id]?.isExposed = true
    }
}

extension Profile2D {
    /// The outer loop's start points.
    var corners: [Vector2] { outer.map(\.startPoint) }
}
