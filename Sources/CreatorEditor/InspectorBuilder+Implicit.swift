import CreatorGeometry
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
                rows += listFacts(of: meshes)
            }
        }
        return rows.isEmpty ? nil : InspectorSectionRows(title: "Mesh", rows: rows)
    }

    /// Facts every mesh of a list shows with the one value, the labels a list summarises itself, and the ones that make no sense added.
    private static let summarisedLabels: Set<String> = [
        "Triangles", "Vertices", "Size", "Closed", "File", "Memory", "Resolution", "Meshing time",
    ]

    /// The rows for a list of meshes (a 3MF's objects): how many, the triangles, the box around them all, how many are closed, the
    /// file if they share one, the memory, and any other fact (a tool's or check's) once per distinct value, in order. The numbers
    /// come from the payloads, not from the facts' text, except "Closed" and "File", which only the facts know.
    static func listFacts(of meshes: [any MeshPayload]) -> [InspectorRow] {
        var rows: [InspectorRow] = [.readOnly(label: "Meshes", text: "\(meshes.count)")]
        let facts = meshes.map(\.inspectorFacts)
        if meshes.allSatisfy({ $0.triangleCount > 0 }) {
            let total = meshes.reduce(0) { $0 + $1.triangleCount }
            rows.append(.readOnly(label: "Triangles", text: total.formatted(.number.locale(.messages))))
        }
        let boxes = meshes.compactMap(\.meshBounds)
        if boxes.count == meshes.count, let first = boxes.first {
            let low = Vector3(boxes.map(\.min.x).min() ?? first.min.x, boxes.map(\.min.y).min() ?? first.min.y,
                              boxes.map(\.min.z).min() ?? first.min.z)
            let high = Vector3(boxes.map(\.max.x).max() ?? first.max.x, boxes.map(\.max.y).max() ?? first.max.y,
                               boxes.map(\.max.z).max() ?? first.max.z)
            let size = high - low
            let numbers = [size.x, size.y, size.z].map { (value: Double) -> String in
                value.formatted(.number.precision(.fractionLength(0...3)).locale(.messages))
            }
            rows.append(.readOnly(label: "Size", text: numbers.joined(separator: " × ") + " mm"))
        }
        let closed = facts.compactMap { $0.first { $0.label == "Closed" }?.value }
        if closed.count == meshes.count {
            let yes = closed.filter { $0 == "Yes" }.count
            rows.append(.readOnly(label: "Closed", text: yes == closed.count ? "Yes" : yes == 0 ? "No" : "\(yes) of \(closed.count)"))
        }
        let files = Set(facts.compactMap { $0.first { $0.label == "File" }?.value })
        if files.count == 1, let file = files.first { rows.append(.readOnly(label: "File", text: file)) }
        var others: [(label: String, values: [String])] = []
        for fact in facts.joined() where !summarisedLabels.contains(fact.label) {
            if let at = others.firstIndex(where: { $0.label == fact.label }) {
                if !others[at].values.contains(fact.value) { others[at].values.append(fact.value) }
            } else {
                others.append((fact.label, [fact.value]))
            }
        }
        rows += others.map { .readOnly(label: $0.label, text: $0.values.joined(separator: "; ")) }
        let bytes = meshes.reduce(0) { $0 + $1.estimatedBytes }
        rows.append(.readOnly(label: "Memory", text: Int64(bytes).formatted(.byteCount(style: .memory).locale(.messages))))
        return rows
    }
}
