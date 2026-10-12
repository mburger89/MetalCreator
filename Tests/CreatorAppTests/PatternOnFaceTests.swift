import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// "Pattern on Face" (patterns spec §3): the face menu inserts a Face Pattern holding the face's pick, wired from the part's
/// producer, as one undo step.
@MainActor
struct PatternOnFaceTests {
    /// A box on xy: face 0 is its bottom, face 1 its top (flat, with normals); faces 2…5 are flat with none (FakeKernel).
    func open() async -> (app: AppModel, box: (rectangle: Node, extrude: Node, output: Node)) {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        await app.viewport.waitForMeshes()
        return (app, box)
    }

    func pattern(_ app: AppModel) -> Node? {
        app.document.graph.nodes.values.first { $0.typeID == FacePatternNode.typeID }
    }

    func choose(_ app: AppModel, on face: FaceID) throws {
        app.viewport.pick = { _ in .face(solid: 0, face) }
        let items = app.viewport.contextMenuItems(at: ScreenPoint(700, 450))
        let item = try #require(items.first { if case .patternOnFace = $0 { true } else { false } })
        app.viewport.choose(item)
    }

    @Test func theFaceMenuInsertsAFacePatternWiredFromThePartAsOneNamedStep() async throws {
        let (app, box) = await open()
        try choose(app, on: FaceID(1))
        let node = try #require(pattern(app))
        let topology = app.viewport.items[0].solid.topology
        #expect(node.inputValues[NodeSetting.face] == .facePick(try #require(topology.facePick(for: FaceID(1)))))
        #expect(app.document.graph.links.contains(Link(from: Endpoint(node: box.extrude.id, socket: "solid"),
                                                       to: Endpoint(node: node.id, socket: "solid"))))
        #expect(app.editor.selection == [node.id])
        #expect(app.document.undoName == "Pattern on Face")
        app.document.undo()
        await app.settle()
        #expect(pattern(app) == nil && app.document.canUndo == false, "one step")
    }

    @Test func aFaceWithNoNormalOffersNoPattern() async throws {
        let (app, _) = await open()
        app.viewport.pick = { _ in .face(solid: 0, FaceID(2)) }
        let items = app.viewport.contextMenuItems(at: ScreenPoint(700, 450))
        #expect(!items.contains { if case .patternOnFace = $0 { true } else { false } })
    }

    @Test func aFaceThatIsNotFlatIsRefusedInWordsAndChangesNothing() async throws {
        let (app, _) = await open()
        let pick = try #require(app.viewport.items[0].solid.topology.facePick(for: FaceID(2)))
        app.patternOnFace(ViewportFaceRef(solidIndex: 0, face: FaceID(2)), pick)
        guard case .problem(let problem)? = app.alert else {
            Issue.record("no alert")
            return
        }
        #expect(problem.title == "No pattern was made" && problem.message.contains("flat"))
        #expect(pattern(app) == nil && app.document.canUndo == false)
    }

    @Test func aFaceOfASolidThatIsGoneChangesNothing() async throws {
        let (app, _) = await open()
        let pick = try #require(app.viewport.items[0].solid.topology.facePick(for: FaceID(1)))
        app.patternOnFace(ViewportFaceRef(solidIndex: 9, face: FaceID(1)), pick)
        #expect(app.alert == nil && pattern(app) == nil && app.document.canUndo == false)
    }
}
