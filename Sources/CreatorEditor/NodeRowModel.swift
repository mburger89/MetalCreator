import CreatorGraph

/// One body row of a node on the canvas: an input (with its constant when unwired) or an output.
public struct NodeRowModel: Equatable, Sendable, Identifiable {
    public var socket: SocketName
    public var isInput: Bool
    public var label: String
    /// The unwired input's value, shown beside its label; `nil` for wired inputs and outputs.
    public var value: String?

    public var id: String { (isInput ? "in." : "out.") + socket.rawValue }

    /// Rows for `node`: inputs first, then outputs, matching `NodeLayout`'s row order.
    public static func rows(for node: Node, shape: NodeShape, graph: Graph, registry: NodeRegistry) -> [NodeRowModel] {
        let specs = registry[node.typeID]?.inputs ?? []
        let inputs = shape.inputs.map { socket -> NodeRowModel in
            let wired = graph.incomingLink(to: Endpoint(node: node.id, socket: socket.name)) != nil
            let spec = specs.first { $0.name == socket.name }
            let value = wired || spec == nil ? nil
                : ValueText.format(node.inputValues[socket.name] ?? spec?.defaultValue, unit: spec?.unit ?? .none)
            return NodeRowModel(socket: socket.name, isInput: true, label: InspectorLabel.text(for: socket.name), value: value)
        }
        let outputs = shape.outputs.map {
            NodeRowModel(socket: $0.name, isInput: false, label: InspectorLabel.text(for: $0.name), value: nil)
        }
        return inputs + outputs
    }
}
