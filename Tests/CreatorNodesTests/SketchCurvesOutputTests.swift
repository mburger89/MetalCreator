import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorSketch
import Testing

/// The Sketch node's `curves` output: one curve per chain, and never a reason for the profiles to fail.
struct SketchCurvesOutputTests {
    @Test func aRectangleGivesItsProfileAndOneClosedCurve() async throws {
        var h = Harness()
        let node = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(RectangleSketch(width: 60, height: 40).sketch)])
        let report = try await h.run([node])
        #expect(report.isOK(node))
        #expect(report.value(node, "profiles")?.profiles?.count == 1)
        let curves = try #require(report.value(node, "curves")?.curves)
        #expect(curves.count == 1)
        #expect(report.value(node, "curves")?.isList == true)
    }

    @Test func theCurveCountMatchesTheChains() async throws {
        var sketch = Sketch()
        _ = sketch.addCircle(center: Vector2(0, 0), radius: 3)
        _ = sketch.addLine(Vector2(10, 0), Vector2(20, 0))
        _ = sketch.addLine(Vector2(30, 0), Vector2(40, 5))
        var h = Harness()
        let node = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(sketch)])
        let report = try await h.run([node])
        #expect(report.value(node, "curves")?.curves?.count == SketchChains.find(in: sketch).count)
        #expect(report.value(node, "curves")?.curves?.count == 3)
    }

    @Test func aKernelThatCannotMakeCurvesWarnsAndKeepsTheProfiles() async throws {
        var h = Harness()
        let node = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(RectangleSketch(width: 60, height: 40).sketch)])
        let report = try await h.run([node], kernel: KernelUnavailable())
        #expect(report.value(node, "profiles")?.profiles?.count == 1)
        #expect(report.value(node, "curves")?.items.isEmpty == true)
        let warning = try #require(report.warning(node))
        #expect(warning.contains("The sketch's curves couldn't be made:"))
    }
}
