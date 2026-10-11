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

    /// MetalUI shows a bubble for any `.help` text, an empty one too (`Tooltip`: it tests `help != nil`), so a dot with no
    /// tree must declare no help at all.
    @Test func onlyADotThatCarriesATreeDeclaresATooltip() async throws {
        let editor = await editor()
        func dots(_ node: Node) throws -> [SocketLayer.Dot] {
            let node = try #require(editor.graph.nodes[node.id])
            return SocketLayer.dots(shape: editor.shape(of: node), flow: editor.flow, palette: Palette(nil),
                                    help: editor.socketHelp(of: node.id))
        }
        let made = try dots(maker)
        #expect(made.count == 3)
        #expect(made.map(\.help) == [nil, nil, "Tree 3 × 8"])
        let lone = try dots(plain)
        #expect(!lone.isEmpty)
        #expect(lone.allSatisfy { $0.help == nil })
    }

    @Test func aTooltipDoesNotChangeHowTheDotsDraw() async throws {
        let editor = await editor()
        let node = try #require(editor.graph.nodes[maker.id])
        let shape = editor.shape(of: node)
        let help = editor.socketHelp(of: node.id)
        #expect(!help.isEmpty)
        let with = renderHeadless { SocketLayer(shape: shape, flow: editor.flow, help: help) }
        let without = renderHeadless { SocketLayer(shape: shape, flow: editor.flow) }
        #expect(!with.rects.isEmpty)
        #expect(with.rects.count == without.rects.count)
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
