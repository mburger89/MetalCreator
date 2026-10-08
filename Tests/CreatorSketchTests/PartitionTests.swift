import CreatorGeometry
import Testing
@testable import CreatorSketch

/// Decomposition into connected components (spec §4 step 1).
struct PartitionTests {
    @Test func separateClustersSolveAsSeparateComponentsInIDOrder() throws {
        var sketch = Sketch()
        let first = sketch.addLine(.zero, Vector2(10, 1))
        let lonePoint = sketch.addPoint(Vector2(50, 50))
        let second = sketch.addLine(Vector2(20, 0), Vector2(30, 2))
        sketch.add(.horizontal(second))
        sketch.add(.horizontal(first))
        let edge = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(1, 0))))))
        sketch.add(.vertical(edge))
        let layout = UnknownLayout(sketch)
        let terms = try TermBuilder(sketch: sketch, layout: layout, x0: layout.warmStart(sketch)).build().terms
        let components = ComponentPartition(terms: terms, layout: layout).components
        // First line (columns 0–3), the lone point (4–5), second line (6–9), then the
        // projected-only term with no unknowns.
        #expect(components.map(\.columns) == [[0, 1, 2, 3], [4, 5], [6, 7, 8, 9], []])
        #expect(components.map(\.terms.count) == [1, 0, 1, 1])
        _ = lonePoint
    }

    @Test func aSharedConstraintJoinsComponents() throws {
        var sketch = Sketch()
        let a = sketch.addLine(.zero, Vector2(10, 0))
        let b = sketch.addLine(Vector2(20, 0), Vector2(30, 0))
        sketch.add(.equal(a, b))
        let layout = UnknownLayout(sketch)
        let terms = try TermBuilder(sketch: sketch, layout: layout, x0: layout.warmStart(sketch)).build().terms
        #expect(ComponentPartition(terms: terms, layout: layout).components.map(\.columns) == [Array(0..<8)])
    }
}
