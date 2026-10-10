import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing

struct LoftTransformNodeTests {
    /// Square sections of side 20 at z = 0 and side 10 at z = 10, from broadcast nodes.
    func frustum(_ h: inout Harness, ruled: Bool) -> Node {
        let sizes = h.add(SeriesNode.self, ["start": .number(20), "step": .number(-10), "count": .integer(2)])
        let heights = h.add(SeriesNode.self, ["start": .number(0), "step": .number(10), "count": .integer(2)])
        let plane = h.add(PlaneNode.self)
        h.wire(heights, "values", to: plane, "offset")
        let square = h.add(RectangleNode.self)
        h.wire(sizes, "values", to: square, "width")
        h.wire(sizes, "values", to: square, "height")
        h.wire(plane, "plane", to: square, "plane")
        let loft = h.add(LoftNode.self, ["ruled": .bool(ruled)])
        h.wire(square, "profile", to: loft, "sections")
        return loft
    }

    @Test func ruledLoftOfBroadcastSquaresIsAFrustum() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let loft = frustum(&h, ruled: true)
        let solid = try onlySolid(try await h.run([loft], kernel: kernel), loft)
        #expect(isClose(try await volume(solid, kernel), 10.0 / 3 * (400 + 100 + 200)))
    }

    @Test func unequalSegmentCountsAreExplained() async throws {
        var h = Harness()
        let radii = h.add(SeriesNode.self, ["start": .number(0), "step": .number(2), "count": .integer(2)])
        let heights = h.add(SeriesNode.self, ["start": .number(0), "step": .number(10), "count": .integer(2)])
        let plane = h.add(PlaneNode.self)
        h.wire(heights, "values", to: plane, "offset")
        let sections = h.add(RoundedRectangleNode.self)
        h.wire(radii, "values", to: sections, "cornerRadius")
        h.wire(plane, "plane", to: sections, "plane")
        let loft = h.add(LoftNode.self)
        h.wire(sections, "profile", to: loft, "sections")
        let report = try await h.run([loft], kernel: OCCTKernel())
        let message = try #require(report.error(loft))
        #expect(message.contains("section 1 has 4 and section 2 has 8"))
        #expect(message.contains("same kind"))
    }

    /// Regions of one sketch: a 60 × 40 plate with a hole (four outer segments) and, apart from it, a triangle (three).
    @Test func holedSectionsAreRefusedBeforeTheirSegmentCountsAreCompared() async throws {
        var plate = RectangleSketch(width: 60, height: 40)
        plate.addHole(center: Vector2(15, 20), radius: 5)
        let corners = [Vector2(100, 0), Vector2(110, 0), Vector2(105, 8)].map { plate.sketch.addPoint($0) }
        for k in 0..<3 { plate.sketch.addLine(from: corners[k], to: corners[(k + 1) % 3]) }
        var h = Harness()
        let sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(plate.sketch)])
        let loft = h.add(LoftNode.self)
        h.wire(sketch, "profiles", to: loft, "sections")
        let report = try await h.run([loft], kernel: OCCTKernel())
        #expect(report.error(loft) == "A loft can't use profiles with holes yet.")
    }

    @Test func oneSectionIsNotALoft() async throws {
        var h = Harness()
        let circle = h.add(CircleNode.self)
        let loft = h.add(LoftNode.self)
        h.wire(circle, "profile", to: loft, "sections")
        let report = try await h.run([loft], kernel: OCCTKernel())
        #expect(report.error(loft)?.hasPrefix("A loft needs at least two sections.") == true)
    }

    @Test func moveTranslatesTheSolid() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let move = h.add(TransformNode.self, ["move": .vector(Vector3(5, 0, 0))])
        h.wire(box, "solid", to: move, "solid")
        let solid = try onlySolid(try await h.run([move], kernel: OCCTKernel()), move)
        #expect(isClose(solid.bounds.min.x, 0) && isClose(solid.bounds.max.x, 10))
    }

    @Test func rotationAboutAnAxisTurnsTheBounds() async throws {
        var h = Harness()
        let box = h.box(20, 10, 10)
        let turn = h.add(TransformNode.self, ["angle": .number(90), "axisDirection": .vector(.unitZ)])
        h.wire(box, "solid", to: turn, "solid")
        let bounds = try onlySolid(try await h.run([turn], kernel: OCCTKernel()), turn).bounds
        #expect(isClose(bounds.size.x, 10, relative: 1e-6))
        #expect(isClose(bounds.size.y, 20, relative: 1e-6))
    }

    @Test func rotationWithoutAnAxisIsExplained() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let turn = h.add(TransformNode.self, ["angle": .number(30)])
        let zero = h.add(TransformNode.self, ["angle": .number(30), "axisDirection": .vector(.zero)])
        h.wire(box, "solid", to: turn, "solid")
        h.wire(box, "solid", to: zero, "solid")
        let report = try await h.run([turn, zero], kernel: OCCTKernel())
        #expect(report.error(turn) == "Set “axisDirection” to rotate by 30°.")
        #expect(report.error(zero) == "The rotation axis direction can't be zero.")
    }

    @Test func movingOverAPointListMakesOneCopyPerPoint() async throws {
        var h = Harness()
        let box = h.box(2, 2, 2)
        let grid = h.add(GridPointsNode.self, ["countX": .integer(3), "countY": .integer(1)])
        let copies = h.add(TransformNode.self)
        h.wire(box, "solid", to: copies, "solid")
        h.wire(grid, "points", to: copies, "move")
        let solids = try #require(try await h.run([copies]).value(copies, "solid")?.solids)
        #expect(solids.map(\.bounds.center.x) == [-10, 0, 10])
    }
}
