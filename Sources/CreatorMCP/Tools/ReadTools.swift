import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation

/// The tools and resources that only read: the document, a node, and the node types.
@MainActor public enum ReadTools {
    static let pageSize = 200

    public static var tools: [MCPTool] { [getDocument, getNode, listNodeTypes, describeNodeType] }

    public static var resources: [MCPResource] {
        [
            MCPResource(uri: "metalcreator://document", name: "Document", mimeType: "application/json") { session in
                documentJSON(session, cursor: 0, pageSize: nil).text
            },
            MCPResource(uri: "metalcreator://node-types", name: "Node types", mimeType: "application/json") { session in
                nodeTypes(session.registry, category: nil, search: nil).text
            },
        ]
    }

    private static func schema(_ properties: [String: JSONValue] = [:], required: [String] = []) -> JSONValue {
        var fields: [String: JSONValue] = ["type": .string("object"), "properties": .object(properties)]
        if !required.isEmpty { fields["required"] = .array(required.map { .string($0) }) }
        return .object(fields)
    }

    private static func property(_ type: String, _ description: String) -> JSONValue {
        .object(["type": .string(type), "description": .string(description)])
    }

    // MARK: Tools

    private static let getDocument = MCPTool(
        name: "get_document",
        description: "Lists the open document's nodes with their states, its links, parameters and groups, 200 nodes at a time.",
        inputSchema: schema(["cursor": property("integer", "The next_cursor of the previous page; omit for the first.")])
    ) { arguments, session, _ in
        guard let cursor = optionalInt(arguments["cursor"]) else { return .refused("The cursor must be a whole number.") }
        guard cursor >= 0 else { return .refused("The cursor must not be negative.") }
        return .ok(documentJSON(session, cursor: cursor, pageSize: pageSize))
    }

    private static let getNode = MCPTool(
        name: "get_node",
        description: "Shows one node: each input's value or wire, each output's summary, its state and its settings.",
        inputSchema: schema(["node": property("string", "The node's ID or unique name.")], required: ["node"])
    ) { arguments, session, _ in
        switch Addressing.node(arguments["node"], in: session.content.graph) {
        case .failure(let refusal): return .refused(refusal.sentence)
        case .success(let id): return .ok(nodeJSON(id, session))
        }
    }

    private static let listNodeTypes = MCPTool(
        name: "list_node_types",
        description: "Lists the node types you can add, optionally of one category or matching a search.",
        inputSchema: schema([
            "category": property("string", "A category such as solid or profile."),
            "search": property("string", "Text to find in a type's name or ID, ignoring case."),
        ])
    ) { arguments, session, _ in
        let category = arguments["category"]?.string
        if let category, NodeCategory.allCases.first(where: { $0.rawValue.lowercased() == category.lowercased() }) == nil {
            let names = NodeCategory.allCases.map(\.rawValue).joined(separator: ", ")
            return .refused("There's no category called “\(category)”. The categories are \(names).")
        }
        return .ok(nodeTypes(session.registry, category: category, search: arguments["search"]?.string))
    }

    private static let describeNodeType = MCPTool(
        name: "describe_node_type",
        description: "Describes a node type: its inputs with defaults, units, ranges and options, its outputs and settings.",
        inputSchema: schema(["type": property("string", "The type ID, such as creator.extrude.")], required: ["type"])
    ) { arguments, session, _ in
        guard let id = arguments["type"]?.string, let definition = session.registry[id] else {
            return .refused("There's no node type called “\(arguments["type"]?.string ?? "")”.")
        }
        return .ok(describe(definition))
    }

    // MARK: Document

    /// `pageSize` nil gives every node.
    static func documentJSON(_ session: any DocumentSession, cursor: Int, pageSize: Int?) -> JSONValue {
        let content = session.content
        let graph = content.graph
        let ordered = graph.nodes.values.sorted(by: Self.drawnBefore)
        let start = min(cursor, ordered.count)
        let end = pageSize.map { min(start + $0, ordered.count) } ?? ordered.count
        let page = Array(ordered[start..<end])
        let onPage = Set(page.map(\.id))
        let names = nameCounts(graph)
        var fields: [String: JSONValue] = [
            "name": .string(session.displayName),
            "edited": .bool(session.isEdited),
            "units": unitsJSON(session.units),
            "nodes": .array(page.map { nodeSummary($0, session) }),
            "links": .array(graph.links.filter { onPage.contains($0.to.node) }.map { link in
                .object(["from": .string(label(link.from, graph, names)), "to": .string(label(link.to, graph, names))])
            }),
            "parameters": .array(graph.parameters.map(parameterJSON)),
            "groups": .array(content.definitions.values.sorted { $0.name < $1.name }.map(groupJSON)),
        ]
        if end < ordered.count { fields["next_cursor"] = .int(end) }
        return .object(fields)
    }

    private static func drawnBefore(_ lhs: Node, _ rhs: Node) -> Bool {
        if lhs.position.x != rhs.position.x { return lhs.position.x < rhs.position.x }
        if lhs.position.y != rhs.position.y { return lhs.position.y < rhs.position.y }
        return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }

    private static func nameCounts(_ graph: Graph) -> [String: Int] {
        graph.nodes.values.reduce(into: [:]) { $0[$1.name, default: 0] += 1 }
    }

    /// "Name.socket", or "ID.socket" when two nodes share the name.
    private static func label(_ endpoint: Endpoint, _ graph: Graph, _ names: [String: Int]) -> String {
        guard let node = graph.nodes[endpoint.node] else { return "\(endpoint.node.rawValue.uuidString).\(endpoint.socket)" }
        let prefix = names[node.name] == 1 ? node.name : node.id.rawValue.uuidString
        return "\(prefix).\(endpoint.socket)"
    }

    private static func nodeSummary(_ node: Node, _ session: any DocumentSession) -> JSONValue {
        let (state, message) = stateText(session.results[node.id]?.state)
        var fields: [String: JSONValue] = [
            "id": .string(node.id.rawValue.uuidString), "name": .string(node.name), "type": .string(node.typeID),
            "position": .array([number(node.position.x), number(node.position.y)]), "state": .string(state),
            "output": .object(outputSummaries(of: node, session)),
        ]
        if let message { fields["message"] = .string(message) }
        return .object(fields)
    }

    private static func outputSummaries(of node: Node, _ session: any DocumentSession) -> [String: JSONValue] {
        var summaries: [String: JSONValue] = [:]
        for socket in session.registry.outputs(for: node) {
            if let line = session.outputSummary(of: node.id, socket: socket.name) { summaries[socket.name.rawValue] = .string(line) }
        }
        return summaries
    }

    private static func stateText(_ state: NodeState?) -> (String, String?) {
        switch state {
        case .none: ("idle", nil)
        case .idle(let reason): ("idle", reason)
        case .evaluating: ("evaluating", nil)
        case .ok: ("ok", nil)
        case .warning(let message): ("warning", message)
        case .error(let message): ("error", message)
        }
    }

    private static func unitsJSON(_ units: DocumentUnits) -> JSONValue {
        var fields: [String: JSONValue] = ["length": .string(units.length.rawValue)]
        if let precision = units.precision { fields["precision"] = .int(precision) }
        return .object(fields)
    }

    private static func parameterJSON(_ parameter: GraphParameter) -> JSONValue {
        var fields: [String: JSONValue] = [
            "id": .string(parameter.id.rawValue.uuidString), "name": .string(parameter.name),
            "type": .string(parameter.type.rawValue), "value": constantJSON(parameter.value),
        ]
        if let lower = parameter.min { fields["min"] = number(lower) }
        if let upper = parameter.max { fields["max"] = number(upper) }
        return .object(fields)
    }

    private static func groupJSON(_ group: GroupDefinition) -> JSONValue {
        func sockets(_ specs: [SocketSpec]) -> JSONValue {
            .array(specs.map { .object(["name": .string($0.name.rawValue), "type": .string($0.type.rawValue)]) })
        }
        return .object(["name": .string(group.name), "inputs": sockets(group.inputs), "outputs": sockets(group.outputs)])
    }

    // MARK: Node

    private static func nodeJSON(_ id: NodeID, _ session: any DocumentSession) -> JSONValue {
        let graph = session.content.graph
        guard let node = graph.nodes[id] else { return .null }
        let names = nameCounts(graph)
        let registry = session.registry
        let inputSpecs = registry.inputs(for: node)
        let inputs: [JSONValue] = inputSpecs.map { spec in
            var fields: [String: JSONValue] = [
                "name": .string(spec.name.rawValue), "type": .string(spec.type.rawValue), "unit": .string(spec.unit.rawValue),
            ]
            if let link = graph.links.first(where: { $0.to == Endpoint(node: id, socket: spec.name) }) {
                fields["wired_from"] = .string(label(link.from, graph, names))
            } else if let value = node.inputValues[spec.name] ?? spec.defaultValue {
                fields["value"] = constantJSON(value)
            }
            if let value = spec.defaultValue { fields["default"] = constantJSON(value) }
            return .object(fields)
        }
        let outputs: [JSONValue] = registry.outputs(for: node).map { spec in
            .object([
                "name": .string(spec.name.rawValue), "type": .string(spec.type.rawValue),
                "summary": .string(session.outputSummary(of: id, socket: spec.name) ?? "No result yet"),
            ])
        }
        let socketNames = Set(inputSpecs.map(\.name))
        var settings: [String: JSONValue] = [:]
        for (name, value) in node.inputValues where !socketNames.contains(name) {
            settings[name.rawValue] = constantJSON(value)
        }
        let (state, message) = stateText(session.results[id]?.state)
        var fields: [String: JSONValue] = [
            "id": .string(id.rawValue.uuidString), "name": .string(node.name), "type": .string(node.typeID),
            "inputs": .array(inputs), "outputs": .array(outputs), "state": .string(state), "settings": .object(settings),
        ]
        if let message { fields["message"] = .string(message) }
        return .object(fields)
    }

    // MARK: Types

    static func nodeTypes(_ registry: NodeRegistry, category: String?, search: String?) -> JSONValue {
        let needle = search?.lowercased()
        let wanted = category?.lowercased()
        let matches = registry.all.filter { definition in
            if let wanted, definition.category.rawValue.lowercased() != wanted { return false }
            if let needle, !definition.displayName.lowercased().contains(needle),
               !definition.typeID.lowercased().contains(needle) { return false }
            return true
        }
        return .object(["types": .array(matches.map { definition in
            .object([
                "type": .string(definition.typeID), "name": .string(definition.displayName),
                "category": .string(definition.category.rawValue), "summary": .string(NodeDescriptions.summary(of: definition)),
            ])
        }),
        ])
    }

    private static func describe(_ definition: any NodeDefinition.Type) -> JSONValue {
        var options: [SocketName: [String]] = [:]
        var controlNames: [SocketName] = []
        for section in definition.inspector {
            for control in section.controls {
                switch control {
                case .segmented(let name, let choices): options[name] = choices
                case .text(let name), .image(let name), .meshFile(let name), .faceStatus(let name): controlNames.append(name)
                default: break
                }
            }
        }
        let inputs: [JSONValue] = definition.inputs.map { spec in
            var fields: [String: JSONValue] = [
                "name": .string(spec.name.rawValue), "type": .string(spec.type.rawValue), "unit": .string(spec.unit.rawValue),
                "optional": .bool(spec.isOptional),
            ]
            if let value = spec.defaultValue { fields["default"] = constantJSON(value) }
            if let range = spec.range { fields["range"] = .array([number(range.lowerBound), number(range.upperBound)]) }
            if let choices = options[spec.name] { fields["options"] = .array(choices.map { .string($0) }) }
            return .object(fields)
        }
        let outputs: [JSONValue] = definition.outputs.map {
            .object(["name": .string($0.name.rawValue), "type": .string($0.type.rawValue)])
        }
        let socketNames = Set(definition.inputs.map(\.name))
        let settings = Set(definition.defaultSettings.keys).union(controlNames).subtracting(socketNames).map(\.rawValue).sorted()
        return .object([
            "type": .string(definition.typeID), "name": .string(definition.displayName),
            "category": .string(definition.category.rawValue), "inputs": .array(inputs), "outputs": .array(outputs),
            "settings": .array(settings.map { .string($0) }),
        ])
    }

    /// `.null` when absent; `nil` when present but not a whole number.
    private static func optionalInt(_ value: JSONValue?) -> Int? {
        guard let value, value != .null else { return 0 }
        return value.int
    }
}
