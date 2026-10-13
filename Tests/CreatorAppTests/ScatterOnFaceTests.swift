import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// "Scatter on Face" (fields spec §3.3): the face menu inserts a Field Scatter holding the face's pick, wired from the part's
/// producer, as one undo step, exactly as "Pattern on Face" inserts a Face Pattern.
@MainActor
struct ScatterOnFaceTests {
    /// A box on xy: face 0 is its bottom, face 1 its top (flat, with normals); faces 2…5 are flat with none (FakeKernel).
    func open() async -> (app: AppModel, box: (rectangle: Node, extrude: Node, output: Node)) {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        await app.viewport.waitForMeshes()
        return (app, box)
    }

    func scatter(_ app: AppModel) -> Node? {
        app.document.graph.nodes.values.first { $0.typeID == FieldScatterNode.typeID }
    }

    func choose(_ app: AppModel, on face: FaceID) throws {
        app.viewport.pick = { _ in .face(solid: 0, face) }
        let items = app.viewport.contextMenuItems(at: ScreenPoint(700, 450))
        let item = try #require(items.first { if case .scatterOnFace = $0 { true } else { false } })
        app.viewport.choose(item)
    }

    @Test func theFaceMenuInsertsAFieldScatterWiredFromThePartAsOneNamedStep() async throws {
        let (app, box) = await open()
        try choose(app, on: FaceID(1))
        let node = try #require(scatter(app))
        let topology = app.viewport.items[0].solid.topology
        #expect(node.inputValues[NodeSetting.face] == .facePick(try #require(topology.facePick(for: FaceID(1)))))
        #expect(app.document.graph.links.contains(Link(from: Endpoint(node: box.extrude.id, socket: "solid"),
                                                       to: Endpoint(node: node.id, socket: "solid"))))
        #expect(app.editor.selection == [node.id])
        #expect(app.document.undoName == "Scatter on Face")
        app.document.undo()
        await app.settle()
        #expect(scatter(app) == nil && app.document.canUndo == false, "one step")
    }

    @Test func theItemFollowsPatternOnFaceInTheMenuAndNeedsAFlatFaceWithANormal() async throws {
        let (app, _) = await open()
        app.viewport.pick = { _ in .face(solid: 0, FaceID(1)) }
        let titles = app.viewport.contextMenuItems(at: ScreenPoint(700, 450)).map(\.title)
        #expect(titles.prefix(5) == ["Look At", "Select Edges of Face", "New Sketch on Face", "Pattern on Face", "Scatter on Face"])
        app.viewport.pick = { _ in .face(solid: 0, FaceID(2)) }
        #expect(!app.viewport.contextMenuItems(at: ScreenPoint(701, 450)).map(\.title).contains("Scatter on Face"))
    }

    @Test func aFaceThatIsNotFlatIsRefusedInWordsAndChangesNothing() async throws {
        let (app, _) = await open()
        let pick = try #require(app.viewport.items[0].solid.topology.facePick(for: FaceID(2)))
        app.scatterOnFace(ViewportFaceRef(solidIndex: 0, face: FaceID(2)), pick)
        guard case .problem(let problem)? = app.alert else {
            Issue.record("no alert")
            return
        }
        #expect(problem.title == "No scatter was made" && problem.message == "Only a flat face can hold a scatter.")
        #expect(scatter(app) == nil && app.document.canUndo == false)
    }

    @Test func aFaceOfASolidThatIsGoneChangesNothing() async throws {
        let (app, _) = await open()
        let pick = try #require(app.viewport.items[0].solid.topology.facePick(for: FaceID(1)))
        app.scatterOnFace(ViewportFaceRef(solidIndex: 9, face: FaceID(1)), pick)
        #expect(app.alert == nil && scatter(app) == nil && app.document.canUndo == false)
    }

    @Test func thePatternItemStillMakesAFacePattern() async throws {
        let (app, _) = await open()
        app.viewport.pick = { _ in .face(solid: 0, FaceID(1)) }
        let items = app.viewport.contextMenuItems(at: ScreenPoint(700, 450))
        let item = try #require(items.first { if case .patternOnFace = $0 { true } else { false } })
        app.viewport.choose(item)
        #expect(app.document.graph.nodes.values.contains { $0.typeID == FacePatternNode.typeID } && scatter(app) == nil)
        #expect(app.document.undoName == "Pattern on Face")
    }
}
