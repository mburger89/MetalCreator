import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp

/// A pick belongs to the level of the graph panel it began on (`PickSession.level`). `refreshScene` cancels it one
/// scheduled task after the level changes; Done and a viewport click that come first must not act on the wrong level.
@MainActor
struct PickLevelGuardTests {
    /// A group holding a box, its Edges by Tag rule and a Chamfer, entered, with a pick begun on the rule.
    func pickingInsideAGroup() async throws -> (app: AppModel, rule: Node) {
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
        let group = try #require(app.editor.selection.first)
        app.editor.enterGroup(group)
        await app.settle()
        app.beginPick(for: rule.id)
        await app.settle()
        try #require(app.pick != nil)
        return (app, rule)
    }

    @Test func doneAfterLeavingTheGroupWritesNothingAndRaisesNoAlert() async throws {
        let (app, _) = try await pickingInsideAGroup()
        app.viewportClicked(.edge(solid: 0, EdgeID(1)))
        let before = app.document.graph
        let canUndo = app.document.canUndo
        app.editor.goToLevel(0)
        app.finishPick()   // before the scheduled refresh has cancelled the pick
        #expect(app.pick == nil)
        #expect(app.alert == nil, "no “node not found” alert")
        #expect(app.document.graph == before && app.document.canUndo == canUndo)
    }

    @Test func aViewportClickAfterLeavingTheGroupEndsThePickWithoutChangingIt() async throws {
        let (app, _) = try await pickingInsideAGroup()
        app.editor.goToLevel(0)
        app.viewportClicked(.edge(solid: 0, EdgeID(1)))
        #expect(app.pick == nil)
    }

    @Test func doneOnTheLevelItBeganOnStillSavesThePicks() async throws {
        let (app, rule) = try await pickingInsideAGroup()
        app.viewportClicked(.edge(solid: 0, EdgeID(1)))
        app.finishPick()
        #expect(app.pick == nil && app.alert == nil)
        #expect(app.editor.selection == [rule.id])
        #expect(app.document.canUndo)
    }
}
