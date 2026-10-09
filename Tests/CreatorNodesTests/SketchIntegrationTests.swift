import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorOCCT
import CreatorSketch
import Testing

/// Sketcher spec §10, Integration (OCCTKernel): sketch → extrude, an exposed dimension driving the part
/// with downstream picks keeping their keys, and a sketch on a face following the face. The projected
/// edge across an upstream change is in `SketchProjectionTests`.
struct SketchIntegrationTests {
    @Test func aSketchWithAHoleExtrudesToItsAnalyticVolume() async throws {
        let kernel = OCCTKernel()
        var rectangle = RectangleSketch(width: 60, height: 40)
        rectangle.addHole(center: Vector2(15, 20), radius: 5)
        var h = Harness()
        let sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(rectangle.sketch)])
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(6)])
        h.wire(sketch, "profiles", to: extrude, "profile")
        let report = try await h.run([extrude], kernel: kernel)
        #expect(report.isOK(sketch) && report.isOK(extrude))
        #expect(isClose(try await volume(try onlySolid(report, extrude), kernel), 6 * (2400 - 25 * Double.pi)))
    }

    @Test func aNotchedSketchRegionExtrudes() async throws {
        // The S2 handoff's case: the notch's arc runs clockwise in the counter-clockwise outline.
        let kernel = OCCTKernel()
        var drawing = Sketch()
        let corners = [Vector2(0, 0), Vector2(20, 0), Vector2(20, 10), Vector2(14, 10), Vector2(6, 10), Vector2(0, 10)]
        let points = corners.map { drawing.addPoint($0) }
        for (a, b) in [(0, 1), (1, 2), (2, 3), (4, 5), (5, 0)] { drawing.addLine(from: points[a], to: points[b]) }
        drawing.addArc(center: drawing.addPoint(Vector2(10, 10)), start: points[4], end: points[3])
        var h = Harness()
        let sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(drawing)])
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(3)])
        h.wire(sketch, "profiles", to: extrude, "profile")
        let report = try await h.run([extrude], kernel: kernel)
        #expect(isClose(try await volume(try onlySolid(report, extrude), kernel), 3 * (200 - 8 * Double.pi)))
    }

    @Test func anExposedDimensionChangesThePartAndDownstreamPicksKeepTheirKeys() async throws {
        let kernel = OCCTKernel()
        var rectangle = RectangleSketch(width: 60, height: 40)
        rectangle.expose(rectangle.width)
        var h = Harness()
        let width = h.add(NumberNode.self, ["value": .number(60)])
        let sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(rectangle.sketch)])
        h.wire(width, "value", to: sketch, "d1")
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(6)])
        h.wire(sketch, "profiles", to: extrude, "profile")
        let rule = h.add(EdgesByTagNode.self)
        h.wire(extrude, "solid", to: rule, "solid")
        let chamfer = h.add(ChamferNode.self, ["distance": .number(0.5)])
        h.wire(rule, "edges", to: chamfer, "edges")

        // Pick the top cap's four edges, as the viewport would.
        let plate = try onlySolid(try await h.run([extrude], kernel: kernel), extrude)
        let top = plate.topology.edges.filter { edge in
            let cap = TopoTag(node: extrude.id, item: 0, role: .endCap)
            return edge.faces.compactMap { plate.topology.face($0) }.contains { $0.tags.contains(cap) }
        }
        #expect(top.count == 4)
        let picks = plate.topology.picks(for: top.map(\.id))
        h.set(rule, NodeSetting.picks, .edgePicks(picks))
        let before = try await h.run([chamfer], kernel: kernel)
        #expect(before.isOK(rule) && before.isOK(chamfer))

        h.set(width, "value", .number(80))
        let after = try await h.run([chamfer], kernel: kernel)
        #expect(after.isOK(sketch) && after.isOK(rule) && after.isOK(chamfer))
        let widened = try onlySolid(after, extrude)
        #expect(isClose(try await volume(widened, kernel), 80 * 40 * 6))
        #expect(widened.topology.picks(for: try #require(after.value(rule, "edges")?.edgeSets?.first).edges) == picks)
    }

    @Test func aSketchOnAFaceFollowsTheFaceWhenTheModelChanges() async throws {
        // "New sketch on face": Plane from Face wired into a Sketch whose plane is `.wired`.
        let kernel = OCCTKernel()
        var h = Harness()
        let box = h.box(20, 10, 6)
        let top = FacePick(tags: [TopoTag(node: box.id, item: 0, role: .endCap)])
        let face = h.add(PlaneFromFaceNode.self, [NodeSetting.face: .facePick(top)])
        h.wire(box, "solid", to: face, "solid")
        var drawing = Sketch(plane: .wired)
        let circle = drawing.addCircle(center: Vector2(0.3, -0.2), radius: 2.5)
        guard case .circle(let center, _)? = drawing.entities[circle]?.kind else { preconditionFailure("not a circle") }
        drawing.add(.fix(center, at: .zero))
        drawing.addDimension(.radius(circle), value: 2)
        let sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(drawing)])
        h.wire(face, "plane", to: sketch, "plane")
        let boss = h.add(ExtrudeNode.self, ["distance": .number(4)])
        h.wire(sketch, "profiles", to: boss, "profile")
        let union = h.add(BooleanNode.self)
        h.wire(box, "solid", to: union, "target")
        h.wire(boss, "solid", to: union, "tools")

        for height in [6.0, 10] {
            h.set(box, "distance", .number(height))
            let report = try await h.run([union], kernel: kernel)
            #expect(report.isOK(face) && report.isOK(sketch) && report.isOK(union))
            let cylinder = try onlySolid(report, boss)
            #expect(abs(cylinder.bounds.min.z - height) < 1e-6)
            #expect(isClose(try await volume(try onlySolid(report, union), kernel), 20 * 10 * height + 16 * Double.pi))
        }
    }
}
