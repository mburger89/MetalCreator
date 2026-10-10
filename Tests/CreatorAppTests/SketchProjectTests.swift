import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import Testing
@testable import CreatorApp
@testable import CreatorSketchEditor
@testable import CreatorViewport

/// Project in the app (sketcher spec §8): a click on the model's edge or face, taken by the Project tool, lands in the
/// Sketch node as projected curves with their picks and a wire from the solid's producer, as one undo step; what can't be
/// projected, or wired, is said in words and stores nothing.
@MainActor
struct SketchProjectTests {
    struct Setup {
        var app: AppModel
        var sketch: Node
        var box: (rectangle: Node, extrude: Node, output: Node)
        var editor: SketchEditorModel
    }

    /// A box on the xy plane (bottom cap face 0, top cap face 1; edge 2k is a bottom edge, 2k + 1 a top edge, 8…11 rise) and
    /// an empty Sketch on xy, open for editing with the Project tool.
    func open() async throws -> Setup {
        var builder = GraphBuilder()
        let box = builder.box()
        let sketch = builder.add(SketchNode.self, [NodeSetting.sketch: .sketch(Sketch(plane: .fixed(.xy)))], at: Vector2(0, 300))
        // The sketch feeds an Extrude and an Output of its own, so it is evaluated (nothing is drawn in it yet, so no solid).
        let extrude = builder.add(ExtrudeNode.self, ["distance": .number(5)], at: Vector2(240, 300))
        let output = builder.add(OutputNode.self, at: Vector2(480, 300))
        builder.wire(sketch, "profiles", to: extrude, "profile")
        builder.wire(extrude, "solid", to: output, "solid")
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.beginSketch(for: sketch.id)
        await app.settle()
        await app.viewport.waitForMeshes()
        await app.viewport.waitForAnimation()
        let editor = try #require(app.sketch?.editor)
        editor.choose(.project)
        return Setup(app: app, sketch: sketch, box: box, editor: editor)
    }

    func click(_ setup: Setup, _ target: PickTarget?) async {
        setup.app.viewport.pick = { _ in target }
        setup.app.viewport.click(at: ScreenPoint(700, 450))
        await setup.app.settle()
    }

    func stored(_ setup: Setup) -> Sketch? {
        let value = setup.app.document.graph.nodes[setup.sketch.id]?.inputValues[NodeSetting.sketch]
        if case .sketch(let sketch)? = value { return sketch }
        return nil
    }

    func references(_ stored: Sketch?) -> [String] {
        (stored?.entityIDs ?? []).compactMap { id in
            if case .projected(let source)? = stored?.entities[id]?.kind { source.reference } else { nil }
        }
    }

    func link(_ setup: Setup) -> Link? {
        setup.app.document.graph.incomingLink(to: Endpoint(node: setup.sketch.id, socket: "references"))
    }

    @Test func aPickedEdgeIsStoredWithItsPickAndTheSolidIsWiredAsOneUndoStep() async throws {
        let setup = try await open()
        let topology = setup.app.viewport.items[0].solid.topology
        await click(setup, .edge(solid: 0, EdgeID(1)))
        #expect(references(stored(setup)) == ["edge1"])
        let node = try #require(setup.app.document.graph.nodes[setup.sketch.id])
        #expect(node.inputValues[NodeSetting.projection("edge1")] == .edgePicks(topology.picks(for: [EdgeID(1)])))
        #expect(link(setup)?.from == Endpoint(node: setup.box.extrude.id, socket: "solid"), "the part's producer, not its Output")
        let state = try #require(setup.app.document.results[setup.sketch.id]?.state)
        if case .warning(let text) = state { #expect(!text.contains("Projected edge"), "the node resolves the pick: \(text)") }
        #expect(setup.app.document.canUndo)
        setup.app.document.undo()
        await setup.app.settle()
        #expect(references(stored(setup)).isEmpty && link(setup) == nil)
        #expect(setup.app.document.graph.nodes[setup.sketch.id]?.inputValues[NodeSetting.projection("edge1")] == nil)
        #expect(setup.app.document.canUndo == false, "the sketch, the pick and the wire were one step")
    }

    @Test func aPickedFaceProjectsEachOfItsEdges() async throws {
        let setup = try await open()
        await click(setup, .face(solid: 0, FaceID(1)))
        #expect(references(stored(setup)) == ["edge1", "edge2", "edge3", "edge4"], "the top cap's four edges")
        let node = try #require(setup.app.document.graph.nodes[setup.sketch.id])
        #expect((1...4).allSatisfy { node.inputValues[NodeSetting.projection("edge\($0)")] != nil })
        #expect(setup.editor.refusal == nil)
        setup.app.document.undo()
        await setup.app.settle()
        #expect(setup.app.document.canUndo == false)
    }

    @Test func aSideFaceKeepsWhatProjectsAndSaysWhatDoesNot() async throws {
        let setup = try await open()
        await click(setup, .face(solid: 0, FaceID(2)))
        #expect(references(stored(setup)) == ["edge1"], "its bottom and top edges project to the same line")
        let message = try #require(setup.editor.refusal)
        #expect(message.contains("already projected") && message.contains("2 edges of that face can't be projected"))
        #expect(message.contains("perpendicular"), "\(message)")
    }

    @Test func anEdgeThatCantBeProjectedStoresNothing() async throws {
        let setup = try await open()
        await click(setup, .edge(solid: 0, EdgeID(8)))
        #expect(setup.editor.refusal == "That edge can't be projected: it is perpendicular to the sketch plane, so it projects to a point.")
        #expect(setup.app.document.canUndo == false && link(setup) == nil)
    }

    @Test func aSecondPartIsRefusedBecauseReferencesTakesOneWire() async throws {
        var builder = GraphBuilder()
        let first = builder.box()
        let second = builder.box(at: Vector2(0, 200))
        let sketch = builder.add(SketchNode.self, [NodeSetting.sketch: .sketch(Sketch(plane: .fixed(.xy)))], at: Vector2(0, 500))
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.beginSketch(for: sketch.id)
        await app.settle()
        await app.viewport.waitForMeshes()
        let editor = try #require(app.sketch?.editor)
        editor.choose(.project)
        let order = app.viewport.items.compactMap { item in app.producer(of: item.solid)?.node }
        let firstIndex = try #require(order.firstIndex(of: first.extrude.id))
        let secondIndex = try #require(order.firstIndex(of: second.extrude.id))
        app.viewport.pick = { _ in .edge(solid: firstIndex, EdgeID(1)) }
        app.viewport.click(at: ScreenPoint(700, 450))
        await app.settle()
        #expect(editor.refusal == nil && app.document.graph.incomingLink(to: Endpoint(node: sketch.id, socket: "references")) != nil)
        app.viewport.pick = { _ in .edge(solid: secondIndex, EdgeID(1)) }
        app.viewport.click(at: ScreenPoint(700, 451))
        await app.settle()
        #expect(editor.refusal == "This sketch already projects from another part. Project from one part per sketch.")
        #expect(editor.sketch.entityIDs.count == 1, "nothing was added")
    }

    @Test func aPartMadeFromThisSketchCantBeProjectedIntoIt() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        await app.viewport.waitForMeshes()
        let editor = try #require(app.sketch?.editor)
        editor.choose(.project)
        app.viewport.pick = { _ in .edge(solid: 0, EdgeID(1)) }
        app.viewport.click(at: ScreenPoint(700, 450))
        #expect(editor.refusal == "That part is made from this sketch, so its edges can't be projected into it.")
        #expect(app.document.canUndo == false)
    }

    @Test func aProjectionWhoseSolidIsGoneIsRefusedAndTheEditorFallsBackToTheStoredSketch() async throws {
        let setup = try await open()
        let resolution = setup.app.resolveProjection(.edge(solid: 0, EdgeID(1)), onto: .xy, for: setup.sketch.id)
        var candidate = try #require(resolution.candidates.first)
        candidate.solid = 99   // the solid the editor was told about has gone by the time the commit is stored
        setup.editor.events.projection = { _, _ in ProjectionResolution(candidates: [candidate], skipped: []) }
        await click(setup, .edge(solid: 0, EdgeID(1)))
        #expect(setup.app.alert != nil, "said in words")
        #expect(references(stored(setup)).isEmpty && link(setup) == nil && setup.app.document.canUndo == false, "nothing stored")
        #expect(references(setup.editor.sketch).isEmpty, "and the editor doesn't keep the projection the graph refused")
    }

    @Test func emptySpaceAsksForAnEdge() async throws {
        let setup = try await open()
        await click(setup, nil)
        #expect(setup.editor.refusal == "Click an edge or a face of the model to project it.")
    }

    @Test func theEditorShowsTheProjectionWhereTheModelIsNow() async throws {
        let setup = try await open()
        await click(setup, .edge(solid: 0, EdgeID(1)))
        func curve() -> ProjectedCurve? {
            for id in setup.editor.sketch.entityIDs {
                if case .projected(let source)? = setup.editor.sketch.entities[id]?.kind { return source.curve }
            }
            return nil
        }
        func length(_ curve: ProjectedCurve?) -> Double? {
            if case .line(let a, let b)? = curve { (b - a).length } else { nil }
        }
        let before = length(curve())
        try setup.app.document.perform(.setInput(setup.box.rectangle.id, "width", .number(80)))
        await setup.app.settle()
        #expect(length(curve()) == 80 && before != 80, "the purple line is the edge's new length, not the one it was projected at")
        #expect(setup.app.sketch?.editor === setup.editor, "and the sketch stayed open")
    }

    @Test func theProjectionSurvivesTheSketchBeingEvaluatedAndFollowsTheModel() async throws {
        let setup = try await open()
        await click(setup, .edge(solid: 0, EdgeID(1)))
        try setup.app.document.perform(.setInput(setup.box.rectangle.id, "width", .number(80)))
        await setup.app.settle()
        let node = try #require(setup.app.document.graph.nodes[setup.sketch.id])
        let state = try #require(setup.app.document.results[node.id]?.state)
        if case .warning(let text) = state { #expect(!text.contains("matches no edge"), "the pick still finds its edge: \(text)") }
        #expect(state.isSuccess)
    }
}
