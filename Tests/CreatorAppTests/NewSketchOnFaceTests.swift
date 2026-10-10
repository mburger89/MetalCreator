import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import Testing
@testable import CreatorApp
@testable import CreatorSketchEditor
@testable import CreatorViewport

/// "New Sketch on Face" (sketcher spec §8): the face menu inserts Plane from Face and a Sketch as one undo step and opens
/// the sketch on the face's plane before the new plane node has evaluated.
@MainActor
struct NewSketchOnFaceTests {
    /// A box on xy: face 0 is its bottom, face 1 its top (flat, with normals); faces 2…5 are flat with none (FakeKernel).
    func open() async -> (app: AppModel, box: (rectangle: Node, extrude: Node, output: Node)) {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        await app.viewport.waitForMeshes()
        return (app, box)
    }

    func node(_ app: AppModel, _ type: String) -> Node? {
        app.document.graph.nodes.values.first { $0.typeID == type }
    }

    func chooseNewSketch(_ app: AppModel, on face: FaceID) throws {
        app.viewport.pick = { _ in .face(solid: 0, face) }
        let items = app.viewport.contextMenuItems(at: ScreenPoint(700, 450))
        let item = try #require(items.first { if case .newSketchOnFace = $0 { true } else { false } })
        app.viewport.choose(item)
    }

    @Test func theFaceMenuInsertsThePlaneAndTheSketchAsOneStepAndOpensTheSketch() async throws {
        let (app, box) = await open()
        try chooseNewSketch(app, on: FaceID(1))
        #expect(app.sketch != nil && app.viewport.tool === app.sketch?.editor, "the sketch is open at once, before any evaluation")
        let planeNode = try #require(node(app, PlaneFromFaceNode.typeID))
        let sketchNode = try #require(node(app, SketchNode.typeID))
        let topology = app.viewport.items[0].solid.topology
        #expect(planeNode.inputValues[NodeSetting.face] == .facePick(try #require(topology.facePick(for: FaceID(1)))))
        guard case .sketch(let sketch)? = sketchNode.inputValues[NodeSetting.sketch] else {
            Issue.record("the Sketch holds no sketch")
            return
        }
        #expect(sketch.plane == .wired)
        let links = app.document.graph.links
        #expect(links.contains(Link(from: Endpoint(node: box.extrude.id, socket: "solid"),
                                    to: Endpoint(node: planeNode.id, socket: "solid"))), "from the part's producer")
        #expect(links.contains(Link(from: Endpoint(node: planeNode.id, socket: "plane"),
                                    to: Endpoint(node: sketchNode.id, socket: "plane"))))
        #expect(app.document.graph.incomingLink(to: Endpoint(node: sketchNode.id, socket: "references")) == nil)
        #expect(app.sketch?.node == sketchNode.id && app.editor.selection == [sketchNode.id])
        #expect(app.sketch?.editor.plane == .xy, "FakeKernel's centroids are the origin, so the top cap's plane is xy")
        app.document.undo()
        await app.settle()
        #expect(node(app, PlaneFromFaceNode.typeID) == nil && node(app, SketchNode.typeID) == nil, "both nodes in one step")
        #expect(app.document.canUndo == false)
        #expect(app.sketch == nil, "undoing the sketch's node leaves sketch mode")
    }

    @Test func theEditorTakesTheNodesOwnPlaneOnceItEvaluates() async throws {
        let (app, _) = await open()
        try chooseNewSketch(app, on: FaceID(1))
        // Nothing draws the new chain yet, so it isn't evaluated; previewing the selected Sketch evaluates it and the plane.
        app.previewMode = .selectedNode
        await app.settle()
        let planeNode = try #require(node(app, PlaneFromFaceNode.typeID))
        let result = try #require(app.document.results[planeNode.id])
        #expect(result.state.isSuccess)
        guard case .plane(let evaluated)? = result.outputs?["plane"]?.items.first else {
            Issue.record("no plane output")
            return
        }
        #expect(app.sketch?.editor.plane == evaluated, "the plane computed up front is the one the node makes")
        let sketchNode = try #require(node(app, SketchNode.typeID))
        #expect(app.document.results[sketchNode.id]?.state.isSuccess == true, "the new sketch evaluates on the wired plane")
    }

    /// Nothing downstream draws the new sketch, so its Plane from Face never evaluates; "Edit sketch" later still opens it,
    /// on the plane worked out from the face of the solid that did evaluate.
    @Test func theSketchOpensAgainBeforeAnythingDrawsIt() async throws {
        let (app, _) = await open()
        try chooseNewSketch(app, on: FaceID(1))
        let sketchNode = try #require(node(app, SketchNode.typeID))
        app.finishSketch()
        await app.settle()
        #expect(app.document.results[sketchNode.id] == nil, "never evaluated: it feeds nothing")
        app.beginSketch(for: sketchNode.id)
        #expect(app.alert == nil && app.sketch?.node == sketchNode.id)
        #expect(app.sketch?.editor.plane == .xy)
    }

    @Test func aFaceWithNoPlaneIsRefusedInWordsAndChangesNothing() async throws {
        let (app, _) = await open()
        let pick = try #require(app.viewport.items[0].solid.topology.facePick(for: FaceID(2)))
        app.newSketchOnFace(ViewportFaceRef(solidIndex: 0, face: FaceID(2)), pick)
        guard case .problem(let problem)? = app.alert else {
            Issue.record("no alert")
            return
        }
        #expect(problem.title == "No sketch was made" && problem.message.contains("flat"))
        #expect(app.sketch == nil && app.document.canUndo == false)
    }

    @Test func aFaceOfASolidThatIsGoneChangesNothing() async throws {
        let (app, _) = await open()
        let pick = try #require(app.viewport.items[0].solid.topology.facePick(for: FaceID(1)))
        app.newSketchOnFace(ViewportFaceRef(solidIndex: 9, face: FaceID(1)), pick)
        #expect(app.alert == nil && app.sketch == nil && app.document.canUndo == false)
    }

    @Test func whileASketchIsOpenNothingStarts() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        await app.viewport.waitForMeshes()
        let pick = try #require(app.viewport.items[0].solid.topology.facePick(for: FaceID(1)))
        let session = app.sketch
        app.newSketchOnFace(ViewportFaceRef(solidIndex: 0, face: FaceID(1)), pick)
        #expect(app.sketch === session && app.document.canUndo == false)
    }
}
