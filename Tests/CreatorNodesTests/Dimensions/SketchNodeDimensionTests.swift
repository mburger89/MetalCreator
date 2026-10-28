import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorSketch
import Testing

/// A Sketch node declares each of its sketch's dimensions in 3D (DIM-3 Task 9).
struct SketchNodeDimensionTests {
    func rectangle() throws -> RectangleSketch {
        var rectangle = RectangleSketch(width: 60, height: 40)
        // The height becomes a reference, so a fixed top-left corner (instead of the left line's Vertical) holds the shape
        // and d2 measures 40.
        let leftVertical = try #require(rectangle.sketch.constraints.first { $0.value == .vertical(rectangle.lines[3]) }?.key)
        rectangle.sketch.constraints[leftVertical] = nil
        rectangle.sketch.dimensions[rectangle.height]?.isDriving = false
        rectangle.sketch.add(.fix(rectangle.corners[3], at: Vector2(0, 40)))
        return rectangle
    }

    @Test func aSketchNodeDeclaresEveryDimension() async throws {
        let rectangle = try rectangle()
        var h = Harness()
        let node = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(rectangle.sketch)])
        let report = try await h.run([node])
        #expect(report.isOK(node), "\(String(describing: report.error(node))) \(String(describing: report.warning(node)))")
        let specs = try #require(report.results[node.id]?.dimensions)
        #expect(specs.map(\.target) == [.sketchDimension(rectangle.width), .sketchDimension(rectangle.height)])
        #expect(specs.map(\.quantity) == [.length, .length])
        #expect(specs.count == 2 && abs(specs[0].value - 60) < 1e-6 && abs(specs[1].value - 40) < 1e-6)
    }

    @Test func anExposedWiredValueIsTheValueShown() async throws {
        var rectangle = try rectangle()
        rectangle.expose(rectangle.width)
        var h = Harness()
        let number = h.add(NumberNode.self, ["value": .number(70)])
        let node = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(rectangle.sketch)])
        h.wire(number, "value", to: node, "d1")
        let report = try await h.run([node])
        let specs = try #require(report.results[node.id]?.dimensions)
        let first = try #require(specs.first)
        #expect(first.target == .sketchDimension(rectangle.width) && abs(first.value - 70) < 1e-6)
    }

    @Test func aDimensionWithoutGeometryIsLeftOut() async throws {
        var sketch = Sketch()
        let source = ProjectionSource(reference: "e", curve: .circle(center: .zero, radius: 5), isSuspended: true)
        let circle = sketch.add(SketchEntity(.projected(source)))
        _ = sketch.addDimension(.radius(circle), value: 5, isDriving: false)
        var h = Harness()
        let node = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(sketch)])
        let report = try await h.run([node])
        #expect(report.results[node.id]?.dimensions.isEmpty == true)
    }
}
