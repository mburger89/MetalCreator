import CreatorGraph
import CreatorKernel

extension InspectorBuilder {
    /// The "Implicit" section (implicit spec §2.1): the recipe of the implicit solid each implicit output of the node holds, read-only,
    /// and what the payload says about itself (a baked solid's bake time and memory). `nil` for a node with no implicit output. Its
    /// row is labelled "Implicit", or by the socket when there are several; before the node has a result it says "No implicit solid
    /// yet", and when its result holds none (an empty or mixed list) "No implicit solid in this result".
    static func implicitSection(node: Node, registry: NodeRegistry, results: [NodeID: NodeResult]) -> InspectorSectionRows? {
        let outputs = registry.outputs(for: node).filter { $0.type == .implicit }
        guard !outputs.isEmpty else { return nil }
        var rows: [InspectorRow] = []
        for spec in outputs {
            let value = results[node.id]?.outputs?[spec.name]
            let text = value?.implicitSummary()
                ?? (results[node.id]?.outputs == nil ? "No implicit solid yet" : "No implicit solid in this result")
            rows.append(.recipe(label: outputs.count == 1 ? "Implicit" : InspectorLabel.text(for: spec.name), text: text))
            if let only = value?.items.first, value?.items.count == 1, case .implicit(let reference) = only {
                rows += reference.payload.inspectorFacts.map { .readOnly(label: $0.label, text: $0.value) }
            }
        }
        return InspectorSectionRows(title: "Implicit", rows: rows)
    }

    /// The "Mesh" section (implicit spec §5.2): a mesh output's triangle count, resolution, meshing time and memory. `nil` for a node
    /// with no mesh output or no mesh yet.
    static func meshSection(node: Node, registry: NodeRegistry, results: [NodeID: NodeResult]) -> InspectorSectionRows? {
        var rows: [InspectorRow] = []
        for spec in registry.outputs(for: node) where spec.type == .mesh {
            let meshes = (results[node.id]?.outputs?[spec.name]?.items ?? []).compactMap { scalar -> (any MeshPayload)? in
                if case .mesh(let mesh) = scalar { mesh } else { nil }
            }
            if meshes.count == 1, let mesh = meshes.first {
                rows += mesh.inspectorFacts.map { .readOnly(label: $0.label, text: $0.value) }
            } else if meshes.count > 1 {
                rows.append(.readOnly(label: "Meshes", text: "\(meshes.count)"))
            }
        }
        return rows.isEmpty ? nil : InspectorSectionRows(title: "Mesh", rows: rows)
    }
}
