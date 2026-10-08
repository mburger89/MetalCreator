import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// Picking writes a rule (spec §5.3 rule 5): "Pick edges in view…", the face menu, and "Show Producing Node".
@MainActor
struct PickingTests {
    /// A box with an Edges by Tag rule on it, upstream of the Output through a Chamfer, as the bracket's chamfer is.
    func chamferedBox() -> (graph: Graph, extrude: Node, rule: Node, chamfer: Node) {
        var builder = GraphBuilder()
        let box = builder.solid()
        let rule = builder.add(EdgesByTagNode.self, at: Vector2(480, 0))
        let chamfer = builder.add(ChamferNode.self, at: Vector2(720, 0))
        let output = builder.add(OutputNode.self, at: Vector2(960, 0))
        builder.wire(box.extrude, "solid", to: rule, "solid")
        builder.wire(rule, "edges", to: chamfer, "edges")
        builder.wire(chamfer, "solid", to: output, "solid")
        return (builder.graph, box.extrude, rule, chamfer)
    }

    @Test func pickingIntoARuleShowsItsSolidAndWritesThePicksAsOneStep() async throws {
        let box = chamferedBox()
        let app = await makeApp(box.graph)
        app.editor.press(.pickEdgesInView, on: box.rule.id)
        app.handle(try #require(app.editor.inspectorRequest))
        await app.settle()
        let solid = try #require(solids(app, box.extrude).first)
        #expect(app.pick?.solid === solid && app.pick?.rule == box.rule.id)
        #expect(app.viewport.items.count == 1 && app.viewport.items.first?.solid === solid, "only the solid being picked on")
        app.viewportClicked(.edge(solid: 0, EdgeID(1)))
        app.viewportClicked(.edge(solid: 0, EdgeID(3)))
        app.viewportClicked(.edge(solid: 0, EdgeID(1)))
        app.viewportClicked(.face(solid: 0, FaceID(1)))
        #expect(app.pick?.picked == [EdgeID(3)], "a second click removes an edge; a face click does nothing")
        app.viewportClicked(.edge(solid: 0, EdgeID(5)))
        await app.settle()
        #expect(app.viewport.items.first?.selectedEdges == [EdgeID(3), EdgeID(5)], "the picked edges glow")
        app.finishPick()
        await app.settle()
        #expect(app.pick == nil)
        #expect(app.document.graph.nodes[box.rule.id]?.inputValues[NodeSetting.picks]
            == .edgePicks(solid.topology.picks(for: [EdgeID(3), EdgeID(5)])))
        #expect(app.editor.selection == [box.rule.id])
        #expect(app.document.results[box.chamfer.id]?.state.isSuccess == true)
        app.document.undo()
        #expect(app.document.graph.nodes[box.rule.id]?.inputValues[NodeSetting.picks] == nil)
    }

    @Test func pickingFromAFeatureUsesItsEdgesByTagRule() async throws {
        let box = chamferedBox()
        let app = await makeApp(box.graph)
        app.editor.openPalette()
        app.beginPick(for: box.chamfer.id)
        #expect(app.pick?.rule == box.rule.id)
        #expect(app.editor.palette == nil, "the banner's Escape and Return would otherwise beat the palette's")
    }

    @Test func cancellingAPickLeavesTheGraphAlone() async throws {
        let box = chamferedBox()
        let app = await makeApp(box.graph)
        app.beginPick(for: box.rule.id)
        app.viewportClicked(.edge(solid: 0, EdgeID(1)))
        app.cancelPick()
        await app.settle()
        #expect(app.pick == nil)
        #expect(!app.document.canUndo)
        #expect(app.viewport.items.isEmpty, "the final preview is back: the chamfer has no edges yet, so no result")
    }

    @Test func pickingOnAFeatureFedByAnotherRuleWiresANewEdgesByTagInItsPlace() async throws {
        var builder = GraphBuilder()
        let box = builder.solid()
        let all = builder.add(AllEdgesNode.self, at: Vector2(480, 200))
        let fillet = builder.add(FilletNode.self, ["radius": .number(1)], at: Vector2(720, 0))
        let output = builder.add(OutputNode.self, at: Vector2(960, 0))
        builder.wire(box.extrude, "solid", to: all, "solid")
        builder.wire(all, "edges", to: fillet, "edges")
        builder.wire(fillet, "solid", to: output, "solid")
        let app = await makeApp(builder.graph)
        app.beginPick(for: fillet.id)
        let session = try #require(app.pick)
        #expect(session.rule == nil && session.consumer == Endpoint(node: fillet.id, socket: "edges"))
        #expect(session.source == Endpoint(node: box.extrude.id, socket: "solid"))
        #expect(session.picked.count == 12, "it starts from the old rule's edges")
        for edge in session.picked.dropFirst(2) { app.viewportClicked(.edge(solid: 0, edge)) }
        app.finishPick()
        await app.settle()
        let rule = try #require(app.document.graph.nodes.values.first { $0.typeID == EdgesByTagNode.typeID })
        #expect(app.document.graph.incomingLink(to: Endpoint(node: rule.id, socket: "solid"))?.from
            == Endpoint(node: box.extrude.id, socket: "solid"))
        #expect(app.document.graph.incomingLink(to: Endpoint(node: fillet.id, socket: "edges"))?.from
            == Endpoint(node: rule.id, socket: "edges"))
        #expect(app.editor.selection == [rule.id])
        #expect(app.document.results[fillet.id]?.state.isSuccess == true)
        app.document.undo()
        #expect(app.document.graph.incomingLink(to: Endpoint(node: fillet.id, socket: "edges"))?.from
            == Endpoint(node: all.id, socket: "edges"), "one undo puts the old rule back")
        #expect(!app.document.graph.nodes.values.contains { $0.typeID == EdgesByTagNode.typeID })
    }

    @Test func pickingWithNothingToPickOnSaysWhatToWire() async throws {
        var builder = GraphBuilder()
        let fillet = builder.add(FilletNode.self)
        let rule = builder.add(EdgesByTagNode.self)
        let app = await makeApp(builder.graph)
        app.beginPick(for: fillet.id)
        #expect(app.pick == nil)
        #expect(app.alert?.message == "Wire an edge rule into “Fillet” first, so there are edges to pick on.")
        app.beginPick(for: rule.id)
        #expect(app.alert?.message == "Wire a solid with a result into “Edges by Tag” first, then pick its edges.")
    }

    @Test func selectEdgesOfFaceMakesARuleWiredFromTheNodeThatMadeTheSolid() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        let solid = try #require(app.viewport.items.first?.solid)
        let edges = [EdgeID(1), EdgeID(3)]
        app.selectEdgesOfFace(ViewportFaceRef(solidIndex: 0, face: FaceID(1)), solid.topology.picks(for: edges), edges)
        let rule = try #require(app.document.graph.nodes.values.first { $0.typeID == EdgesByTagNode.typeID })
        #expect(rule.inputValues[NodeSetting.picks] == .edgePicks(solid.topology.picks(for: edges)))
        #expect(app.document.graph.incomingLink(to: Endpoint(node: rule.id, socket: "solid"))?.from
            == Endpoint(node: box.extrude.id, socket: "solid"))
        #expect(app.editor.selection == [rule.id])
        app.document.undo()
        #expect(app.document.graph.nodes[rule.id] == nil, "one undo step")
    }

    @Test func selectEdgesOfFaceWhilePickingAddsToThePick() async throws {
        let box = chamferedBox()
        let app = await makeApp(box.graph)
        app.beginPick(for: box.rule.id)
        await app.settle()
        app.viewportClicked(.edge(solid: 0, EdgeID(3)))
        app.selectEdgesOfFace(ViewportFaceRef(solidIndex: 0, face: FaceID(1)), [], [EdgeID(3), EdgeID(1)])
        #expect(app.pick?.picked == [EdgeID(3), EdgeID(1)])
        #expect(!app.document.canUndo, "nothing is written until Done")
    }
}
