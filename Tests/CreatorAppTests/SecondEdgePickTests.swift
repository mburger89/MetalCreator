import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp

/// "Pick target edge in view…" (Match Surface) and "Pick other edge in view…" (Blend Surface): the same pick as Fillet's, for the
/// socket named (NS-4 Task 11). The kernel is `FakeKernel`, which refuses the surface edit itself but evaluates every rule upstream.
@MainActor
struct SecondEdgePickTests {
    /// Two boxes. A's edges come from an Edges by Tag rule; B's from an All Edges rule. Both wire into `feature`'s
    /// `edges` and `socket`.
    func rig(_ feature: any NodeDefinition.Type, secondSocket: SocketName) -> (graph: Graph, feature: Node, second: Node, boxB: Node) {
        var builder = GraphBuilder()
        let a = builder.solid()
        let b = builder.solid(at: Vector2(0, 300))
        let rule = builder.add(EdgesByTagNode.self, at: Vector2(480, 0))
        let direction = builder.add(AllEdgesNode.self, at: Vector2(480, 300))
        let node = builder.add(feature, at: Vector2(720, 0))
        builder.wire(a.extrude, "solid", to: rule, "solid")
        builder.wire(b.extrude, "solid", to: direction, "solid")
        let output = builder.add(OutputNode.self, at: Vector2(960, 0))
        builder.wire(node, "surface", to: output, "solid")
        builder.wire(rule, "edges", to: node, "edges")
        builder.wire(direction, "edges", to: node, secondSocket)
        return (builder.graph, node, direction, b.extrude)
    }

    func pickAndFinish(_ app: AppModel, feature: Node, socket: SocketName, box: Node) async throws {
        app.beginPick(for: feature.id, socket: socket)
        await app.settle()
        let session = try #require(app.pick, "\(String(describing: app.alert?.message))")
        let solid = try #require(app.solid(at: Endpoint(node: box.id, socket: "solid")))
        #expect(session.solid === solid, "the picks go on the other body")
        #expect(session.consumer == Endpoint(node: feature.id, socket: socket) && session.rule == nil)
        #expect(session.picked.contains(EdgeID(3)), "the pick starts from the edges wired in now")
        app.viewportClicked(.edge(solid: 0, EdgeID(3)))
        let picked = try #require(app.pick?.picked)
        #expect(!picked.contains(EdgeID(3)))
        app.finishPick()
        await app.settle()
        #expect(app.pick == nil)
        let link = try #require(app.document.graph.incomingLink(to: Endpoint(node: feature.id, socket: socket)))
        let rule = try #require(app.document.graph.nodes[link.from.node])
        #expect(rule.typeID == EdgesByTagNode.typeID)
        #expect(app.document.graph.incomingLink(to: Endpoint(node: rule.id, socket: "solid"))?.from
            == Endpoint(node: box.id, socket: "solid"), "the rule is wired from B")
        #expect(rule.inputValues[NodeSetting.picks] == .edgePicks(solid.topology.picks(for: picked)))
        #expect(app.document.undoName == UndoName.pickEdges)
        app.document.undo()
        #expect(app.document.graph.incomingLink(to: Endpoint(node: feature.id, socket: socket))?.from.node != rule.id)
    }

    @Test func pickTargetEdgeWiresARuleIntoTarget() async throws {
        let setup = rig(MatchSurfaceNode.self, secondSocket: "target")
        let app = await makeApp(setup.graph)
        try await pickAndFinish(app, feature: setup.feature, socket: "target", box: setup.boxB)
    }

    @Test func pickOtherEdgeWiresARuleIntoOtherEdges() async throws {
        let setup = rig(BlendSurfaceNode.self, secondSocket: "other edges")
        let app = await makeApp(setup.graph)
        try await pickAndFinish(app, feature: setup.feature, socket: "other edges", box: setup.boxB)
    }

    @Test func theInspectorButtonsPickForTheirSocket() async throws {
        let match = rig(MatchSurfaceNode.self, secondSocket: "target")
        let app = await makeApp(match.graph)
        app.editor.press(.pickTargetEdgesInView, on: match.feature.id)
        app.handle(try #require(app.editor.inspectorRequest))
        #expect(app.pick?.consumer == Endpoint(node: match.feature.id, socket: "target"))
        app.cancelPick()
        app.editor.press(.pickEdgesInView, on: match.feature.id)
        app.handle(try #require(app.editor.inspectorRequest))
        #expect(app.pick?.rule != nil && app.pick?.consumer == nil, "edges comes from a rule: Fillet's own path")
    }

    @Test func anUnwiredSecondSocketSaysWhatToWire() async throws {
        var builder = GraphBuilder()
        let blend = builder.add(BlendSurfaceNode.self)
        let app = await makeApp(builder.graph)
        app.beginPick(for: blend.id, socket: "other edges")
        #expect(app.pick == nil)
        #expect(app.alert?.message == "Wire an edge rule into “Blend Surface” first, so there are edges to pick on.")
    }
}
