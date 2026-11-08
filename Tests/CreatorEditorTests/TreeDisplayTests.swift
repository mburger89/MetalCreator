import CreatorGeometry
import CreatorGraph
import MetalUI
import Testing
@testable import CreatorEditor

@MainActor
struct TreeDisplayTests {
    let maker = testNode(TreeMakerTestNode.self, id: 1, at: .zero)
    let consumer = testNode(TextSettingTestNode.self, id: 2, at: Vector2(300, 0))
    let plain = testNode(NumberTestNode.self, id: 3, at: Vector2(0, 300))

    func editor(rows: Int = 3, columns: Int = 8) async -> EditorModel {
        // Only output nodes are demanded, so each of these is flagged as one.
        var made = maker, taking = consumer, lone = plain
        made.inputValues = ["rows": .integer(rows), "columns": .integer(columns)]
        (made.isOutput, taking.isOutput, lone.isOutput) = (true, true, true)
        let editor = makeEditor([made, taking, lone], [wire(made, "values", taking, "tree")], registry: treeDisplayRegistry)
        await editor.document.waitForEvaluation()
        return editor
    }

    // MARK: socket tooltips

    @Test func theSocketsOfATreeShowItsShape() async {
        let editor = await editor()
        #expect(editor.socketHelp(of: maker.id) == ["out.values": "Tree 3 × 8"])
        #expect(editor.socketHelp(of: consumer.id)["in.tree"] == "Tree 3 × 8")
    }

    @Test func emptyBranchesShowAsZero() async {
        let editor = await editor(rows: 2, columns: 0)
        #expect(editor.socketHelp(of: maker.id)["out.values"] == "Tree 2 × 0")
    }

    @Test func socketsWithoutATreeHaveNoTooltip() async {
        let editor = await editor()
        #expect(editor.socketHelp(of: plain.id).isEmpty)
    }

    @Test func aNodeWithNoResultYetHasNoTooltip() {
        let editor = makeEditor([maker], registry: treeDisplayRegistry)
        #expect(editor.socketHelp(of: maker.id).isEmpty)
    }

    @Test func theTooltipFollowsAnEdit() async {
        let editor = await editor()
        editor.selection = [maker.id]
        guard case .integer(let rows)? = editor.inspectorPage.sections.first?.rows.first else { Issue.record("no rows field"); return }
        editor.setNumber(rows, to: 5)
        await editor.document.waitForEvaluation()
        #expect(editor.socketHelp(of: maker.id)["out.values"] == "Tree 5 × 8")
    }

    @Test func theCanvasDrawsANodeWhoseSocketsHaveTooltips() async {
        let editor = await editor()
        #expect(!renderHeadless { CanvasLayers(model: editor) }.glyphs.isEmpty)
    }

    /// The canvas's layers do not hit-test, so `CanvasSurface`'s `.help` asks the model for the socket under the pointer
    /// (canvas-local screen points, the same as `hitTest(_:)`), through the pan and zoom.
    @Test func aPointOverATreeSocketGivesItsTooltip() async throws {
        let editor = await editor()
        editor.transform = CanvasTransform(offset: Vector2(40, 25), zoom: 1.5)
        let node = try #require(editor.graph.nodes[maker.id])
        let shape = editor.shape(of: node)
        let socket = try #require(NodeLayout.socketOffset("values", isInput: false, in: shape, flow: editor.flow))
        let screen = editor.transform.toScreen(editor.displayOrigin(of: node) + socket)
        #expect(editor.socketTip(at: screen) == "Tree 3 × 8")
        let input = try #require(editor.graph.nodes[consumer.id])
        let inSocket = try #require(NodeLayout.socketOffset("tree", isInput: true, in: editor.shape(of: input), flow: editor.flow))
        #expect(editor.socketTip(at: editor.transform.toScreen(editor.displayOrigin(of: input) + inSocket)) == "Tree 3 × 8")
    }

    @Test func emptyCanvasAndASocketWithNoTipGiveNone() async throws {
        let editor = await editor()
        #expect(editor.socketTip(at: Vector2(-500, -500)) == nil)
        let node = try #require(editor.graph.nodes[plain.id])
        let shape = editor.shape(of: node)
        let socket = try #require(shape.outputs.first)
        let offset = try #require(NodeLayout.socketOffset(socket.name, isInput: false, in: shape, flow: editor.flow))
        #expect(editor.socketTip(at: editor.transform.toScreen(editor.displayOrigin(of: node) + offset)) == nil)
    }

    // MARK: the inspector

    @Test func theInspectorListsATreeOnItsOutput() async {
        let editor = await editor()
        editor.selection = [maker.id]
        let data = editor.inspectorPage.sections.last
        #expect(data?.title == "Data")
        guard case .treeShape(let row)? = data?.rows.first else { Issue.record("no tree row"); return }
        #expect(row.label == "Values out")
        #expect(row.summary == "3 × 8")
        #expect(row.entries == [.init(path: "{0}", count: 8), .init(path: "{1}", count: 8), .init(path: "{2}", count: 8)])
        #expect(row.hiddenCount == 0)
        #expect(!row.isExpanded)
    }

    @Test func theInspectorShowsTheTreeWiredIntoAnInput() async {
        let editor = await editor()
        editor.selection = [consumer.id]
        let rows = editor.inspectorPage.sections.last?.rows
        guard case .treeShape(let row)? = rows?.first else { Issue.record("no tree row"); return }
        #expect(row.label == "Tree in")
        #expect(row.summary == "3 × 8")
        guard case .treeShape(let output)? = rows?.last else { Issue.record("no output row"); return }
        #expect(output.label == "Tree out")
    }

    @Test func aNodeWithoutTreesShowsNoDataSection() async {
        let editor = await editor()
        editor.selection = [plain.id]
        #expect(editor.inspectorPage.sections.map(\.title) == ["Inputs"])
    }

    @Test func thePathListOpensAndClosesAndIsNotAnEdit() async {
        let editor = await editor()
        editor.selection = [maker.id]
        guard case .treeShape(let closed)? = editor.inspectorPage.sections.last?.rows.first else { Issue.record("no row"); return }
        editor.toggleShapeList(closed.key)
        guard case .treeShape(let open)? = editor.inspectorPage.sections.last?.rows.first else { Issue.record("no row"); return }
        #expect(open.isExpanded)
        editor.toggleShapeList(open.key)
        guard case .treeShape(let again)? = editor.inspectorPage.sections.last?.rows.first else { Issue.record("no row"); return }
        #expect(!again.isExpanded)
        #expect(!editor.document.canUndo, "a view change, not an edit")
    }

    @Test func aLongPathListIsCutShort() async {
        let editor = await editor(rows: 120, columns: 1)
        editor.selection = [maker.id]
        guard case .treeShape(let row)? = editor.inspectorPage.sections.last?.rows.first else { Issue.record("no row"); return }
        #expect(row.entries.count == TreeShapeRow.maximumEntries)
        #expect(row.hiddenCount == 70)
        #expect(row.entries.last?.path == "{49}")
        #expect(row.summary == "120 × 1")
    }

    @Test func aSparseTreeListsItsEmptyBranches() async {
        let editor = await editor(rows: 2, columns: 0)
        editor.selection = [maker.id]
        guard case .treeShape(let row)? = editor.inspectorPage.sections.last?.rows.first else { Issue.record("no row"); return }
        #expect(row.summary == "2 × 0")
        #expect(row.entries == [.init(path: "{0}", count: 0), .init(path: "{1}", count: 0)])
    }

    @Test func aSingleItemBranchReadsAsOneItem() {
        #expect(TreeShapeView.countText(1) == "1 item")
        #expect(TreeShapeView.countText(8) == "8 items")
    }

    @Test func theInspectorDrawsOpenAndClosed() async {
        let editor = await editor()
        editor.selection = [maker.id]
        #expect(!renderHeadless { InspectorPanel(model: editor) }.glyphs.isEmpty)
        guard case .treeShape(let row)? = editor.inspectorPage.sections.last?.rows.first else { Issue.record("no row"); return }
        editor.toggleShapeList(row.key)
        #expect(!renderHeadless { InspectorPanel(model: editor) }.glyphs.isEmpty)
    }
}
