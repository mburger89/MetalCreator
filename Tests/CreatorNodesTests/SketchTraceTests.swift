import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorSketch
import Testing

/// DIM-4: the Sketch node's trace of which entity made each profile segment.
struct SketchTraceTests {
    @Test func aSolvedSketchCarriesItsTrace() async throws {
        let rectangle = RectangleSketch(width: 60, height: 40)
        var h = Harness()
        let node = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(rectangle.sketch)])
        let report = try await h.run([node])
        let trace = try #require(report.results[node.id]?.sketchTrace)
        #expect(trace.regionSources.count == 1)
        #expect(trace.entity(item: 0, loop: 0, segment: 0) == rectangle.lines[0])
    }

    @Test func theTraceIsTheSketchAsEvaluated() async throws {
        var rectangle = RectangleSketch(width: 60, height: 40)
        rectangle.expose(rectangle.width)
        var h = Harness()
        let width = h.add(NumberNode.self, ["value": .number(80)])
        let node = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(rectangle.sketch)])
        h.wire(width, "value", to: node, "d1")
        let report = try await h.run([node])
        let trace = try #require(report.results[node.id]?.sketchTrace)
        let position = try #require(trace.sketch.position(of: rectangle.corners[1]))
        #expect((position - Vector2(80, 0)).length <= 1e-6)
    }

    @Test func aFailingSketchHasNoTrace() async throws {
        var rectangle = RectangleSketch(width: 60, height: 40)
        // A second, different length on the same line conflicts with the first.
        rectangle.sketch.addDimension(.length(rectangle.lines[0]), value: 70)
        var h = Harness()
        let node = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(rectangle.sketch)])
        let report = try await h.run([node])
        #expect(report.error(node) != nil)
        #expect(report.results[node.id]?.sketchTrace == nil)
    }

    @Test func otherNodesHaveNoTrace() async throws {
        var h = Harness()
        let node = h.box(20, 10, 6)
        let report = try await h.run([node])
        #expect(report.isOK(node))
        #expect(report.results[node.id]?.sketchTrace == nil)
    }

    @Test func outOfRangeIsNil() {
        let a = SketchEntityID(1)
        let trace = SketchTrace(sketch: Sketch(), regionSources: [[[a, a]]])
        #expect(trace.entity(item: 0, loop: 0, segment: 1) == a)
        #expect(trace.entity(item: 3, loop: 0, segment: 0) == nil)
        #expect(trace.entity(item: 0, loop: 9, segment: 0) == nil)
        #expect(trace.entity(item: 0, loop: 0, segment: 99) == nil)
        #expect(trace.entity(item: -1, loop: 0, segment: 0) == nil)
    }

    @Test func aProjectedEdgeIsFoundByItsPick() async throws {
        var h = Harness()
        let box = h.box(20, 10, 6)
        var drawing = Sketch()
        let projected = drawing.add(SketchEntity(.projected(ProjectionSource(reference: "p1", curve: .line(.zero, Vector2(1, 0))))))
        let sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(drawing)])
        h.wire(box, "solid", to: sketch, "references")
        let solid = try onlySolid(try await h.run([box]), box)
        let tags = [TopoTag(node: box.id, item: 0, role: .endCap), TopoTag(node: box.id, item: 0, role: .side(segment: 0))]
        let top = try #require(solid.topology.edges.first { edge in
            guard let key = solid.topology.key(of: edge) else { return false }
            return key.first.union(key.second) == Set(tags)
        })
        let other = try #require(solid.topology.edges.first { $0.id != top.id })
        h.set(sketch, NodeSetting.projection("p1"), .edgePicks(solid.topology.picks(for: [top.id])))

        let report = try await h.run([sketch])
        let trace = try #require(report.results[sketch.id]?.sketchTrace)
        let node = try #require(h.graph.nodes[sketch.id])
        #expect(SketchNode.projectedEntity(for: top.id, on: solid, node: node, trace: trace) == projected)
        #expect(SketchNode.projectedEntity(for: other.id, on: solid, node: node, trace: trace) == nil)
    }
}
