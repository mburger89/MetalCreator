import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp

/// The nodes that belong to one feature alone (DIM-3 Task 10, decision 2).
struct FeatureChainTests {
    @Test func aSketchWiredOnlyIntoOneExtrudeIsPrivate() {
        var b = GraphBuilder()
        let sketch = b.add(SketchNode.self)
        let extrude = b.add(ExtrudeNode.self)
        b.wire(sketch, "profiles", to: extrude, "profile")
        #expect(FeatureChain.nodes(of: extrude.id, in: b.graph) == [sketch.id, extrude.id])
        #expect(FeatureChain.nodes(of: sketch.id, in: b.graph) == [sketch.id])
    }

    @Test func theChainNeverCrossesABodyWire() {
        var b = GraphBuilder()
        let (_, extrude) = b.solid()
        let layout = b.add(LinearPatternNode.self)
        let hole = b.add(HolePatternNode.self)
        b.wire(extrude, "solid", to: hole, "part")
        b.wire(layout, "placements", to: hole, "placements")
        let chain = FeatureChain.nodes(of: hole.id, in: b.graph)
        #expect(chain == [hole.id, layout.id])
        #expect(!chain.contains(extrude.id))
    }

    @Test func aLayoutThroughACullIsPrivate() {
        var b = GraphBuilder()
        let layout = b.add(LinearPatternNode.self)
        let cull = b.add(CullIndexNode.self)
        let hole = b.add(HolePatternNode.self)
        b.wire(layout, "placements", to: cull, "tree")
        b.wire(cull, "tree", to: hole, "placements")
        #expect(FeatureChain.nodes(of: hole.id, in: b.graph) == [hole.id, cull.id, layout.id])
    }

    @Test func aSharedLayoutIsInNeitherChain() {
        var b = GraphBuilder()
        let layout = b.add(LinearPatternNode.self)
        let first = b.add(HolePatternNode.self)
        let second = b.add(HolePatternNode.self)
        b.wire(layout, "placements", to: first, "placements")
        b.wire(layout, "placements", to: second, "placements")
        #expect(FeatureChain.nodes(of: first.id, in: b.graph) == [first.id])
        #expect(FeatureChain.nodes(of: second.id, in: b.graph) == [second.id])
    }

    @Test func aNodeWiredTwiceIntoOneConsumerIsPrivate() {
        var b = GraphBuilder()
        let number = b.add(NumberNode.self)
        let rectangle = b.add(RectangleNode.self)
        b.wire(number, "value", to: rectangle, "width")
        b.wire(number, "value", to: rectangle, "height")
        #expect(FeatureChain.nodes(of: rectangle.id, in: b.graph) == [number.id, rectangle.id])
    }

    @Test func theWalkStopsAtGraphParametersAndOutputs() {
        var b = GraphBuilder()
        let parameter = b.add(GraphParameterNode.self)
        let flagged = b.add(NumberNode.self)
        b.graph.nodes[flagged.id]?.isOutput = true
        let rectangle = b.add(RectangleNode.self)
        b.wire(parameter, "number", to: rectangle, "width")
        b.wire(flagged, "value", to: rectangle, "height")
        #expect(FeatureChain.nodes(of: rectangle.id, in: b.graph) == [rectangle.id])
    }
}
