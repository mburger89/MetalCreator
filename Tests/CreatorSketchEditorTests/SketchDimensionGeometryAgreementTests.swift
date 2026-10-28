import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// `SketchDimensionGeometry` (what a Sketch node declares to the viewport) draws every dimension kind exactly as the sketch
/// editor does (`SketchDimensionDrawing`), on a tilted plane, with and without a saved label point.
@MainActor
struct SketchDimensionGeometryAgreementTests {
    let tilted = Plane(origin: Vector3(5, -2, 7), normal: Vector3(0, -0.6, 0.8), xAxis: .unitX)

    /// One dimension of each kind, the point-pair and line-pair ones twice more with a label point.
    func sketch(labelled: Bool) -> Sketch {
        var sketch = Sketch()
        let a = sketch.addPoint(.zero)
        let b = sketch.addPoint(Vector2(60, 40))
        let circle = sketch.addCircle(center: Vector2(20, -30), radius: 8)
        let arc = sketch.addCircle(center: Vector2(-30, 10), radius: 5)
        let bottom = sketch.addLine(Vector2(0, -60), Vector2(60, -60))
        let top = sketch.addLine(Vector2(5, -20), Vector2(70, -30))
        let kinds: [DimensionKind] = [
            .length(bottom), .distance(a, b), .distance(a, bottom), .centreDistance(circle, arc), .horizontalDistance(a, b),
            .verticalDistance(a, b), .lineDistance(bottom, top), .radius(circle), .diameter(arc), .angle(bottom, top),
        ]
        for kind in kinds {
            let id = sketch.addDimension(kind, value: 10)
            if labelled { sketch.dimensions[id]?.labelPoint = Vector2(-15, 25) }
        }
        return sketch
    }

    @Test func everyKindMatchesTheEditorsDrawing() throws {
        for plane in [Plane.xy, tilted] {
            for labelled in [false, true] {
                let sketch = sketch(labelled: labelled)
                let solution = SketchSolver.solve(sketch)
                #expect(sketch.dimensionIDs.count == 10)
                for id in sketch.dimensionIDs {
                    let dimension = try #require(sketch.dimensions[id])
                    let drawn = SketchDimensionDrawing.geometry(of: dimension, sketch: sketch, solution: solution, plane: plane)
                    let declared = SketchDimensionGeometry.geometry(of: id, in: sketch, solution: solution, plane: plane)
                    #expect(drawn != nil, "\(dimension.kind) has geometry")
                    #expect(declared == drawn, "\(dimension.kind), labelled \(labelled)")
                }
            }
        }
    }
}
