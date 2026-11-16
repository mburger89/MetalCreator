import CreatorGraph
import CreatorKernel

extension InspectorBuilder {
    /// The node's own facts (`NodeOutputs.facts`), read-only, titled by `NodeDefinition.factsTitle`; last, after the data, field,
    /// implicit and mesh sections. `nil` when the node's result has none.
    static func factsSection(node: Node, definition: any NodeDefinition.Type, results: [NodeID: NodeResult]) -> InspectorSectionRows? {
        guard let facts = results[node.id]?.facts, !facts.isEmpty else { return nil }
        return InspectorSectionRows(title: definition.factsTitle, rows: facts.map { .readOnly(label: $0.label, text: $0.value) })
    }

    /// A board file setting's rows: "No file chosen" with Choose File…, or "Linked · board.kicad_pcb" with Relink…. A board is never
    /// embedded.
    static func pcbFileRows(_ setting: SocketName, node: Node) -> [InspectorRow] {
        let status: String
        let button: (title: String, action: InspectorAction)
        if let reference = node.inputValues[setting]?.fileReference {
            status = "Linked · \(reference.fileName ?? "")"
            button = ("Relink…", .relinkPCBFile)
        } else {
            status = "No file chosen"
            button = ("Choose File…", .choosePCBFile)
        }
        return [.readOnly(label: "File", text: status), .button(title: button.title, action: button.action)]
    }

    /// A mesh file setting's rows: "No file chosen", "Embedded · a1b2c3d4" or "Linked · part.stl", then the buttons for that state.
    static func meshFileRows(_ setting: SocketName, node: Node) -> [InspectorRow] {
        let status: String
        let buttons: [(title: String, action: InspectorAction)]
        switch node.inputValues[setting]?.fileReference {
        case nil:
            status = "No file chosen"
            buttons = [("Choose File…", .chooseMeshFile)]
        case .embedded(let hash)?:
            status = "Embedded · \(hash.short)"
            buttons = [("Choose File…", .chooseMeshFile)]
        case let reference?:
            status = "Linked · \(reference.fileName ?? "")"
            buttons = [("Relink…", .relinkMeshFile), ("Embed", .embedMeshFile)]
        }
        return [.readOnly(label: "File", text: status)] + buttons.map { .button(title: $0.title, action: $0.action) }
    }
}
