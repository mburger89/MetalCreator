import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import Testing
@testable import CreatorApp

/// The app reads exposed dimensions the way the Sketch node partitions them (sketcher spec §7), so a wire or a
/// constant reaches the one dimension the node applies it to.
struct SketchStoreTests {
    @Test func aRepeatedExposedNameIsOneSocketAsTheNodeSeesIt() throws {
        var sketch = rectangleSketch(exposed: true)
        let height = try #require(sketch.dimensionIDs.last)
        sketch.dimensions[height]?.name = "width" // renameDimension refuses a repeat; a decoded file can hold one
        sketch.dimensions[height]?.isExposed = true
        let names = SketchStore.exposedNames(sketch)
        #expect(names.count == 1 && names.values.first == "width")
        #expect(Set(names.keys) == Set(SketchNode.exposedSocketNames(sketch).keys))
        let folded = SketchStore.folded(sketch, constants: ["width": .number(75)])
        let values = sketch.dimensionIDs.compactMap { folded.dimensions[$0]?.value }
        #expect(values.sorted() == [40, 75], "only the socket's dimension takes the constant")
    }

    @Test func aProjectionWritesItsPickAndWiresTheSolidOnlyWhenNothingIsWired() {
        let pick = EdgePick(key: EdgeKey([], []), matchCount: 1)
        var node = BuiltInNodes.registry.makeNode(SketchNode.typeID, at: .zero)
        node.inputValues[NodeSetting.sketch] = .sketch(Sketch(plane: .fixed(.xy)))
        var graph = Graph()
        graph.nodes[node.id] = node
        let source = Endpoint(node: NodeID(), socket: "solid")
        let references = Endpoint(node: node.id, socket: "references")
        var edited = Sketch(plane: .fixed(.xy))
        edited.add(SketchEntity(.projected(ProjectionSource(reference: "edge1", curve: .line(.zero, Vector2(10, 0))))))
        let projection = SketchStore.Projection(reference: "edge1", pick: pick, source: source)
        let commands = SketchStore.commands(storing: edited, in: node, graph: graph, projections: [projection])
        #expect(commands.contains(.setInput(node.id, NodeSetting.projection("edge1"), .edgePicks([pick]))))
        #expect(commands.contains(.connect(Link(from: source, to: references))))
        graph.links.append(Link(from: source, to: references))
        let again = SketchStore.commands(storing: edited, in: node, graph: graph, projections: [projection])
        #expect(!again.contains { if case .connect = $0 { true } else { false } }, "the wire is already there")
    }

    @Test func aRemovedProjectionTakesItsStoredPickWithIt() {
        var old = Sketch(plane: .fixed(.xy))
        let id = old.add(SketchEntity(.projected(ProjectionSource(reference: "edge1", curve: .line(.zero, Vector2(10, 0))))))
        var node = BuiltInNodes.registry.makeNode(SketchNode.typeID, at: .zero)
        node.inputValues[NodeSetting.sketch] = .sketch(old)
        node.inputValues[NodeSetting.projection("edge1")] = .edgePicks([EdgePick(key: EdgeKey([], []), matchCount: 1)])
        var edited = old
        edited.entities[id] = nil
        let commands = SketchStore.commands(storing: edited, in: node, graph: Graph())
        #expect(commands.contains(.setInput(node.id, NodeSetting.projection("edge1"), nil)))
        let kept = SketchStore.commands(storing: old, in: node, graph: Graph())
        #expect(!kept.contains(.setInput(node.id, NodeSetting.projection("edge1"), nil)), "a projection that stays keeps its pick")
    }
}
