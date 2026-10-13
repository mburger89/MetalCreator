import CreatorGraph
import CreatorKernel

/// Which selections show a field preview, and which field (fields spec §6): a selected node of the Fields category whose
/// field exists. A node that makes a field shows the one in its result; a node that takes one (Sample Field, Cull by Field,
/// Field Scatter) shows the first field wired into it, even before anything downstream is wired. A typed number is a constant
/// field with nothing to show, a node that failed makes no field, and a node whose upstream failed has none to take.
enum FieldPreviewSelection {
    /// True for a node a field preview follows: any node in the Fields library category.
    static func previews(_ node: Node, registry: NodeRegistry) -> Bool {
        registry[node.typeID]?.category == .fields
    }

    static func field(of node: Node, graph: Graph, results: [NodeID: NodeResult], registry: NodeRegistry) -> Field? {
        guard previews(node, registry: registry) else { return nil }
        if let output = registry.outputs(for: node).first(where: { $0.type == .field }) {
            guard let result = results[node.id], result.state.isSuccess else { return nil }
            return firstField(result.outputs?[output.name])
        }
        for input in registry.inputs(for: node) where input.type == .field {
            guard let link = graph.incomingLink(to: Endpoint(node: node.id, socket: input.name)) else { continue }
            // The first wired field input decides: if its upstream failed there is no field to take, and a later input is not
            // a stand-in. (No node that only takes fields has two, so no test builds this; the three that do have one each.)
            guard let upstream = results[link.from.node], upstream.state.isSuccess else { return nil }
            if let field = firstField(upstream.outputs?[link.from.socket]) { return field }
        }
        return nil
    }

    private static func firstField(_ value: Value?) -> Field? {
        value?.items.lazy.compactMap { scalar -> Field? in
            if case .field(let field) = scalar { field } else { nil }
        }.first
    }
}
