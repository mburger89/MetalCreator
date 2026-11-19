import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// A pick that names the node it is stored on (Trim Surface's keep regions name `cutSide` tags of the Trim itself) follows the node
/// to its copy; a pick naming a node that was not copied keeps naming it.
@MainActor
struct PickRenamingClipboardTests {
    let scene = TieScene()

    func pick(_ node: NodeID, _ other: NodeID) -> ConstantValue {
        let own = TopoTag(node: node, item: 0, role: .cutSide(.curve(index: 0, piece: 0), .front))
        let upstream = TopoTag(node: other, item: 0, role: .startCap)
        return .regionPicks([RegionPick(pick: FacePick(tags: [own, upstream]))])
    }

    func tags(of node: NodeID, in editor: EditorModel) -> Set<TopoTag>? {
        guard case .regionPicks(let picks)? = editor.graph.nodes[node]?.inputValues[NodeSetting.keepRegions] else { return nil }
        return picks.first?.pick.tags
    }

    @Test func aDuplicatedNodesPicksNameTheCopy() throws {
        let editor = scene.editor()
        try editor.document.perform(.setInput(scene.a1.id, NodeSetting.keepRegions, pick(scene.a1.id, scene.b1.id)),
                                    name: UndoName.pickTrimRegions)
        editor.selection = [scene.a1.id]
        editor.duplicateSelection()
        let copy = try #require(editor.canvasSelection.nodes.first)
        #expect(copy != scene.a1.id)
        let tags = try #require(tags(of: copy, in: editor))
        let side = TopoRole.cutSide(.curve(index: 0, piece: 0), .front)
        #expect(tags.contains { $0.node == copy && $0.role == side }, "the copy's own tag follows it")
        #expect(tags.contains { $0.node == scene.b1.id }, "a node that wasn't copied keeps its name")
        #expect(!tags.contains { $0.node == scene.a1.id })
    }

    @Test func aCopiedChainsPicksNameTheCopiesOfItsNodes() throws {
        let editor = scene.editor()
        try editor.document.perform(.setInput(scene.a1.id, NodeSetting.keepRegions, pick(scene.a1.id, scene.b1.id)),
                                    name: UndoName.pickTrimRegions)
        editor.selection = [scene.a1.id, scene.b1.id]
        editor.duplicateSelection()
        let copies = editor.canvasSelection.nodes
        #expect(copies.count == 2)
        let all = copies.compactMap { tags(of: $0, in: editor) }
        let tagged = try #require(all.first)
        #expect(tagged.allSatisfy { copies.contains($0.node) }, "both names moved to the copies")
    }
}
