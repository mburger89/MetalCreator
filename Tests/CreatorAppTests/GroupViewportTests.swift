import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
@testable import CreatorViewport
import Testing
@testable import CreatorApp

/// The viewport while the graph panel shows the inside of a group (groups spec §6): Selected-node preview, handles and
/// picking work on the level shown, Final preview shows the whole part, and a pick is written relative to the level.
@MainActor
struct GroupViewportTests {
    /// Rectangle → Extrude → Output, with Rectangle and Extrude grouped; the app is inside the group.
    struct Scene {
        let app: AppModel
        let rectangle: Node, extrude: Node, output: Node
        let group: NodeID
    }

    func groupedBox(enter: Bool = true) async throws -> Scene {
        var builder = GraphBuilder()
        let box = builder.box(distance: 10)
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.rectangle.id, box.extrude.id]
        app.editor.groupSelection()
        let group = try #require(app.editor.selection.first)
        if enter { app.editor.enterGroup(group) }
        await app.settle()
        return Scene(app: app, rectangle: box.rectangle, extrude: box.extrude, output: box.output, group: group)
    }

    @Test func finalPreviewStillShowsTheWholePartInsideAGroup() async throws {
        let scene = try await groupedBox()
        let app = scene.app
        #expect(app.editor.isInsideGroup && app.previewMode == .final)
        #expect(app.viewport.items.count == 1)
        #expect(app.viewport.items.first?.solid.bounds.size.z == 10)
        app.editor.selection = [scene.extrude.id]
        await app.settle()
        #expect(app.viewport.items.count == 1 && app.viewport.items.first?.isGhost == false, "selecting inside changes nothing")
    }

    @Test func selectedNodePreviewShowsTheSelectedNodeOfTheLevel() async throws {
        let scene = try await groupedBox()
        let app = scene.app
        app.previewMode = .selectedNode
        await app.settle()
        #expect(app.viewport.items.isEmpty, "nothing selected")
        app.editor.selection = [scene.extrude.id]
        await app.settle()
        let shown = try #require(app.viewport.items.first)
        #expect(app.viewport.items.count == 1 && shown.solid.bounds.size.z == 10)
        #expect(app.document.previewNode == nil, "the document evaluates the whole level instead")
        app.editor.exitGroup()
        await app.settle()
        #expect(app.viewport.items.isEmpty, "the extrude isn't on the top level")
    }

    @Test func aNodeNothingReadsPreviewsToo() async throws {
        let scene = try await groupedBox()
        let app = scene.app
        app.previewMode = .selectedNode
        app.editor.transform = CanvasTransform()
        let lonely = try #require(app.editor.registry.makeNode(ExtrudeNode.typeID, at: Vector2(200, 300)) as Node?)
        try app.editor.edit(.addNode(lonely), name: UndoName.addNode(lonely))
        app.editor.connect(Link(from: Endpoint(node: scene.rectangle.id, socket: "profile"),
                                to: Endpoint(node: lonely.id, socket: "profile")))
        app.editor.selection = [lonely.id]
        await app.settle()
        #expect(app.viewport.items.count == 1 && app.viewport.items.first?.solid.bounds.size.z == 10,
                "evaluated for the panel's sake, not for any Output")
    }

    @Test func aHandleInsideAGroupEditsTheDefinitionAsOneStep() async throws {
        let scene = try await groupedBox()
        let app = scene.app
        app.editor.selection = [scene.extrude.id]
        await app.settle()
        let handle = try #require(app.viewport.handles.first)
        app.handleChanged(handle.id, 25, .changed)
        app.handleChanged(handle.id, 30, .ended)
        let distance = app.document.definitions.values.first?.graph.nodes[scene.extrude.id]?.inputValues["distance"]
        #expect(distance == .number(30))
        #expect(app.document.graph.nodes[scene.extrude.id] == nil)
        await app.settle()
        #expect(app.viewport.items.first?.solid.bounds.size.z == 30, "the part follows")
        app.undo()
        #expect(app.document.definitions.values.first?.graph.nodes[scene.extrude.id]?.inputValues["distance"] == .number(10))
    }

    /// Rectangle → Extrude → Edges by Tag → Chamfer → Output, with everything but the Output grouped.
    struct ChamferGroup {
        let app: AppModel
        let extrude: Node, rule: Node, chamfer: Node
        let group: NodeID
    }

    func chamferGroup() async throws -> ChamferGroup {
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
        return ChamferGroup(app: app, extrude: box.extrude, rule: rule, chamfer: chamfer, group: group)
    }

    @Test func aPickMadeInsideAGroupIsWrittenRelativeToTheLevel() async throws {
        let made = try await chamferGroup()
        let (app, extrude, rule, chamfer, group) = (made.app, made.extrude, made.rule, made.chamfer, made.group)
        app.beginPick(for: rule.id)
        let session = try #require(app.pick)
        #expect(session.level == [group] && session.rule == rule.id)
        await app.settle()
        app.viewportClicked(.edge(solid: 0, EdgeID(1)))
        app.viewportClicked(.edge(solid: 0, EdgeID(3)))
        app.finishPick()
        await app.settle()
        let stored = try #require(app.document.definitions.values.first?.graph.nodes[rule.id]?.inputValues[NodeSetting.picks])
        guard case .edgePicks(let picks) = stored else {
            Issue.record("expected edge picks, got \(stored)")
            return
        }
        let named = Set(picks.flatMap { [$0.key.first, $0.key.second] }.flatMap { $0 }.map(\.node))
        #expect(named.contains(extrude.id), "the extrude is named as the definition names it")
        #expect(!named.contains(NodeID.scoped([group, extrude.id])), "not under this instance's identity")
        #expect(app.editor.result(of: chamfer.id)?.state.isSuccess == true, "the chamfer finds its edges")
        #expect(app.editor.selection == [rule.id])
        app.undo()
        #expect(app.document.definitions.values.first?.graph.nodes[rule.id]?.inputValues[NodeSetting.picks] == nil)
    }

    @Test func aPickBelongsToTheLevelItBeganOn() async throws {
        let made = try await chamferGroup()
        let (app, rule) = (made.app, made.rule)
        app.beginPick(for: rule.id)
        #expect(app.pick != nil)
        app.editor.exitGroup()
        await app.settle()
        #expect(app.pick == nil, "showing another level cancels it")
    }

    @Test func inFinalPreviewAPickStartsFromANodeOfTheLevelShown() async throws {
        let scene = try await groupedBox()
        let app = scene.app
        #expect(app.previewMode == .final)
        let shown = try #require(app.viewport.items.first).solid
        let source = try #require(app.producer(of: shown))
        #expect(app.editor.graph.nodes[source.node] != nil, "not the group node's endpoint, which this level doesn't have")
        #expect(source.node == scene.extrude.id, "and not Group Output, which has no output to wire from")
    }

    @Test func anOpenSketchHoldsTheLevelShown() async throws {
        var builder = GraphBuilder()
        let sketched = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.editor.selection = [sketched.extrude.id]
        app.editor.groupSelection()
        let group = try #require(app.editor.selection.first)
        app.beginSketch(for: sketched.sketch.id)
        await app.settle()
        #expect(app.sketch != nil && app.editor.isLevelLocked)
        #expect(!app.editor.enterGroup(group) && app.editor.levelPath.isEmpty, "the sketch lives on the top level")
        app.finishSketch()
        await app.settle()
        #expect(!app.editor.isLevelLocked && app.editor.enterGroup(group))
    }

    @Test func aSketchInsideAGroupIsRefusedWithAReason() async throws {
        var builder = GraphBuilder()
        let sketched = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.editor.selection = [sketched.sketch.id]
        app.editor.groupSelection()
        let group = try #require(app.editor.selection.first)
        app.editor.enterGroup(group)
        app.editor.press(.editSketch, on: sketched.sketch.id)
        app.handle(try #require(app.editor.inspectorRequest))
        #expect(app.sketch == nil)
        #expect(app.alert != nil, "it says why")
    }

    @Test func showProducingNodeGoesBackOutToTheGroupNode() async throws {
        let scene = try await groupedBox()
        let app = scene.app
        app.showProducingNode(NodeID.scoped([scene.group, scene.extrude.id]))
        #expect(app.editor.levelPath.isEmpty)
        #expect(app.editor.selection == [scene.group])
    }

    @Test func undoFromInsideAGroupAfterTheGroupWasUndoneLeavesIt() async throws {
        let scene = try await groupedBox()
        let app = scene.app
        app.undo()
        #expect(app.editor.enteredGroups.isEmpty && app.document.definitions.isEmpty)
        #expect(app.editor.graph.nodes[scene.extrude.id] != nil, "the top level has its nodes back")
    }

    /// Sketch mode works on the top level's graph, so New Sketch on Face inside a group says why it does nothing.
    @Test func newSketchOnFaceIsRefusedInsideAGroup() async throws {
        let scene = try await groupedBox()
        let app = scene.app
        app.previewMode = .selectedNode
        app.editor.selection = [scene.extrude.id]
        await app.settle()
        let before = app.document.content
        app.viewport.pick = { _ in .face(solid: 0, FaceID(1)) }
        let items = app.viewport.contextMenuItems(at: ScreenPoint(700, 450))
        let item = try #require(items.first { if case .newSketchOnFace = $0 { true } else { false } })
        app.viewport.choose(item)
        #expect(app.sketch == nil && app.document.content == before)
        guard case .problem(let problem)? = app.alert else {
            Issue.record("no alert")
            return
        }
        #expect(problem.message == "Sketches inside a group can't be made yet. Make it before grouping, or from the top level.")
    }
}
