import CreatorGraph

/// One body row of a node on the canvas: an input (with its constant when unwired) or an output.
public struct NodeRowModel: Equatable, Sendable, Identifiable {
    public var socket: SocketName
    public var isInput: Bool
    public var label: String
    /// The unwired input's value, shown beside its label; `nil` for wired inputs and outputs.
    public var value: String?

    public var id: String { (isInput ? "in." : "out.") + socket.rawValue }

    /// Rows for `node`: inputs first, then outputs, matching `NodeLayout`'s row order. Each input's unit and default
    /// come from `registry.inputs(for:)`, the same list `NodeShape` draws.
    public static func rows(for node: Node, shape: NodeShape, graph: Graph, registry: NodeRegistry) -> [NodeRowModel] {
        let specs = registry.inputs(for: node)
        let choices = choiceOptions(for: node, registry: registry)
        let inputs = shape.inputs.map { socket -> NodeRowModel in
            let wired = graph.incomingLink(to: Endpoint(node: node.id, socket: socket.name)) != nil
            let spec = specs.first { $0.name == socket.name }
            let stored = node.inputValues[socket.name] ?? spec?.defaultValue
            let value = wired || spec == nil ? nil : choiceName(stored, options: choices[socket.name])
                ?? ValueText.format(stored, unit: spec?.unit ?? .none)
            return NodeRowModel(socket: socket.name, isInput: true, label: InspectorLabel.text(for: socket.name), value: value)
        }
        let outputs = shape.outputs.map {
            NodeRowModel(socket: $0.name, isInput: false, label: InspectorLabel.text(for: $0.name), value: nil)
        }
        return inputs + outputs
    }

    /// The options of each input the node's inspector shows as a segmented control, by socket: the names a stored index selects.
    static func choiceOptions(for node: Node, registry: NodeRegistry) -> [SocketName: [String]] {
        var options: [SocketName: [String]] = [:]
        for section in registry[node.typeID]?.inspector(for: node) ?? [] {
            for case .segmented(let socket, let names) in section.controls { options[socket] = names }
        }
        return options
    }

    /// The name of the option an integer choice stores ("Plain" for 0), or `nil` when the input is no choice or holds no option.
    static func choiceName(_ value: ConstantValue?, options: [String]?) -> String? {
        guard let options, case .integer(let index)? = value, options.indices.contains(index) else { return nil }
        return options[index]
    }
}
