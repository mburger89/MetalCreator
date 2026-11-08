import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorEditor
@testable import CreatorViewport

/// The nodes the face menu inserts (Pattern on Face, Scatter on Face, New Sketch on Face) land on free canvas, not on a node already
/// there (display finding 5).
@MainActor
struct FaceMenuPlacementTests {
    /// A box whose producer has Output-like neighbours standing exactly where a new node would be put: a Number at the
    /// producer's (+240, +140) and another below it, in the dock `dock`.
    func open(dock: DockSide) async -> (app: AppModel, blockers: [Node]) {
        var builder = GraphBuilder()
        let box = builder.box()
        let from = builder.graph.nodes[box.extrude.id]?.position ?? .zero
        var graph = builder.graph
        var blockers: [Node] = []
        for step in 0..<3 {
            let blocker = BuiltInNodes.registry.makeNode(NumberNode.typeID, at: from + Vector2(240, 140 + 100 * Double(step)))
            graph.nodes[blocker.id] = blocker
            blockers.append(blocker)
        }
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: graph, viewState: ViewState(dock: dock)))
        await app.settle()
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        await app.viewport.waitForMeshes()
        return (app, blockers)
    }

    func choose(_ app: AppModel, _ matches: (ViewportMenuItem) -> Bool) throws {
        app.viewport.pick = { _ in .face(solid: 0, FaceID(1)) }
        let items = app.viewport.contextMenuItems(at: ScreenPoint(700, 450))
        let item = try #require(items.first { matches($0) })
        app.viewport.choose(item)
    }

    func expectClear(_ app: AppModel, _ added: [NodeID], sourceCount: Int) {
        let frames = app.editor.graph.nodes.values.map { (id: $0.id, frame: app.editor.frame(of: $0)) }
        #expect(frames.count == sourceCount + added.count)
        for new in frames where added.contains(new.id) {
            for other in frames where other.id != new.id {
                #expect(!new.frame.intersects(other.frame), "\(new.frame) overlaps \(other.frame)")
            }
        }
    }

    @Test(arguments: [DockSide.bottom, .left])
    func patternOnFaceAvoidsTheNodesThere(_ dock: DockSide) async throws {
        let (app, _) = await open(dock: dock)
        let before = app.editor.graph.nodes.count
        try choose(app) { if case .patternOnFace = $0 { true } else { false } }
        expectClear(app, Array(app.editor.selection), sourceCount: before)
    }

    @Test(arguments: [DockSide.bottom, .left])
    func newSketchOnFaceAvoidsTheNodesThere(_ dock: DockSide) async throws {
        let (app, _) = await open(dock: dock)
        let before = app.editor.graph.nodes.count
        try choose(app) { if case .newSketchOnFace = $0 { true } else { false } }
        let added = app.editor.graph.nodes.values.filter { $0.typeID == SketchNode.typeID || $0.typeID == PlaneFromFaceNode.typeID }
        expectClear(app, added.map(\.id), sourceCount: before)
    }

    /// With nothing in the way the node stays where it always was.
    @Test func aFreeSpotIsKept() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        var graph = builder.graph
        graph.nodes[box.output.id]?.position = Vector2(480, 1000)
        let app = await makeApp(graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        await app.viewport.waitForMeshes()
        let from = try #require(app.editor.graph.nodes[box.extrude.id]).position
        try choose(app) { if case .patternOnFace = $0 { true } else { false } }
        let node = try #require(app.editor.graph.nodes.values.first { $0.typeID == FacePatternNode.typeID })
        #expect(node.position == from + Vector2(240, 140))
    }
}
