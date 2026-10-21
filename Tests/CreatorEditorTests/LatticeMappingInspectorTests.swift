import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorEditor

/// The `mapping` setting of the lattice nodes in the real inspector (implicit spec §3.5): the segmented control, and only the active
/// mapping's inputs showing. The node and its definition are the real ones; the editor writes the control's value as the view does.
@MainActor
struct LatticeMappingInspectorTests {
    /// The three lattice nodes, by number.
    func definition(_ index: Int) -> any NodeDefinition.Type {
        [TPMSNode.self, StrutLatticeNode.self, VoronoiLatticeNode.self][index]
    }

    func editor(_ definition: any NodeDefinition.Type) -> (editor: EditorModel, node: Node) {
        let node = BuiltInNodes.registry.makeNode(definition.typeID)
        let editor = makeEditor([node], registry: BuiltInNodes.registry)
        editor.selection = [node.id]
        return (editor, node)
    }

    /// The "Mapping" section's rows.
    func rows(_ editor: EditorModel) -> [InspectorRow] {
        editor.inspectorPage.sections.first { $0.title == "Mapping" }?.rows ?? []
    }

    /// The labels of the rows that edit something.
    func labels(_ rows: [InspectorRow]) -> [String] {
        rows.compactMap { row in
            switch row {
            case .segmented(let field, _, _), .planePicker(let field, _), .vector(let field): field.label
            case .readOnly(let label, _): label
            case .button(let title, _): title
            default: nil
            }
        }
    }

    @Test(arguments: 0..<3)
    func aNewNodeIsStraightAndShowsOnlyTheChoice(_ index: Int) throws {
        let (editor, _) = editor(definition(index))
        let section = rows(editor)
        guard case .segmented(let field, let options, let selected)? = section.first else { Issue.record("no segmented control"); return }
        #expect(field.label == "Mapping" && options == ["Straight", "Cylindrical", "Spherical", "Face"])
        #expect(selected == 0, "a node with no mapping stored is Straight")
        #expect(labels(section) == ["Mapping"], "no axis, centre or face")
    }

    @Test(arguments: 0..<3)
    func choosingAMappingShowsItsInputsAndNoOthers(_ index: Int) throws {
        let (editor, node) = editor(definition(index))
        func choose(_ option: Int) throws {
            guard case .segmented(let field, let options, _)? = rows(editor).first else { Issue.record("no segmented control"); return }
            editor.setInput(field, to: try #require(InspectorBuilder.segmentValue(option, options: options, type: field.type)))
        }
        try choose(1)
        #expect(editor.graph.nodes[node.id]?.inputValues["mapping"] == .integer(1))
        #expect(labels(rows(editor)) == ["Mapping", "Axis"])
        try choose(2)
        #expect(labels(rows(editor)) == ["Mapping", "Centre"])
        try choose(3)
        #expect(labels(rows(editor)) == ["Mapping", "Face", "Pick Face in View…"])
        guard case .readOnly(_, let status)? = rows(editor).dropFirst().first else { Issue.record("no face status"); return }
        #expect(status == "None", "nothing picked yet")
        try choose(0)
        #expect(labels(rows(editor)) == ["Mapping"])
    }

    @Test func aPickedFaceShowsAsPicked() throws {
        let (editor, node) = editor(TPMSNode.self)
        let pick = FacePick(tags: [TopoTag(NodeTag(node: NodeID(), item: 0), .unnamed(face: 1))])
        try editor.document.perform(.setInput(node.id, NodeSetting.face, .facePick(pick)))
        try editor.document.perform(.setInput(node.id, "mapping", .integer(3)))
        guard case .readOnly(_, let status)? = rows(editor).dropFirst().first else { Issue.record("no face status"); return }
        #expect(status == "Picked")
    }

    @Test(arguments: 0..<3)
    func theInspectorDrawsUnderEveryMapping(_ index: Int) throws {
        let (editor, node) = editor(definition(index))
        var counts: [Int] = []
        for mapping in 0...3 {
            try editor.document.perform(.setInput(node.id, "mapping", .integer(mapping)))
            let scene = renderHeadless { InspectorPanel(model: editor) }
            #expect(!scene.glyphs.isEmpty)
            counts.append(scene.glyphs.count)
        }
        #expect(counts[1] > counts[0] && counts[2] > counts[0] && counts[3] > counts[0], "each adds its row: \(counts)")
    }
}
