import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp

/// A pick made inside a group holds for every instance of the definition (groups spec §5 Naming, §6 Viewport): it is
/// stored the way the definition names faces, and each instance reads it as its own.
@MainActor
struct GroupPickInstancesTests {
    @Test func aPickMadeInsideOneInstanceChamfersTheOtherToo() async throws {
        var builder = GraphBuilder()
        let box = builder.solid()
        let rule = builder.add(EdgesByTagNode.self, at: Vector2(480, 0))
        let chamfer = builder.add(ChamferNode.self, at: Vector2(720, 0))
        let output = builder.add(OutputNode.self, at: Vector2(960, 0))
        builder.wire(box.extrude, "solid", to: rule, "solid")
        builder.wire(rule, "edges", to: chamfer, "edges")
        builder.wire(chamfer, "solid", to: output, "solid")
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.rectangle.id, box.extrude.id, rule.id, chamfer.id]
        app.editor.groupSelection()
        let first = try #require(app.editor.selection.first)
        app.editor.perform(.duplicate)
        let second = try #require(app.editor.selection.first)
        try app.document.perform(.setOutput(second, true))
        app.editor.enterGroup(first)
        await app.settle()

        app.beginPick(for: rule.id)
        await app.settle()
        app.viewportClicked(.edge(solid: 0, EdgeID(1)))
        app.viewportClicked(.edge(solid: 0, EdgeID(3)))
        app.finishPick()
        await app.settle()
        let definition = try #require(app.document.definitions.values.first)
        guard case .edgePicks(let picks)? = definition.graph.nodes[rule.id]?.inputValues[NodeSetting.picks] else {
            Issue.record("the rule inside the definition holds no picks")
            return
        }
        #expect(!picks.isEmpty, "the two clicked edges are stored with the definition")
        #expect(app.document.innerResults[[first, chamfer.id]]?.state.isSuccess == true, "the instance it was made in")
        #expect(app.document.innerResults[[second, chamfer.id]]?.state.isSuccess == true, "and the other one")
    }
}
