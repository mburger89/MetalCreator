import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation

/// The tools that change the graph. Each plans its commands against a scratch copy of the top-level graph, so a batch can
/// refer to a node an earlier operation of it adds, and a refusal anywhere leaves the document as it was.
@MainActor public enum EditTools {
    struct Plan {
        var name: String
        var commands: [GraphCommand]
    }

    typealias Planner = @MainActor (JSONValue, inout Graph, any DocumentSession) -> Result<Plan, Refusal>

    static let textSettings: Set<SocketName> = [
        NodeSetting.pathRule, NodeSetting.branchPath, NodeSetting.itemPath, NodeSetting.cullPattern, NodeSetting.cullIndices,
    ]

    public static var tools: [MCPTool] {
        planners.map { entry in
            MCPTool(name: entry.name, description: entry.description, inputSchema: entry.schema) { arguments, session, _ in
                var scratch = session.content.graph
                switch entry.plan(arguments, &scratch, session) {
                case .failure(let refusal): return .refused(refusal.sentence)
                case .success(let plan): return await EditOutcome.run(session: session, name: plan.name, commands: plan.commands)
                }
            }
        } + [batchTool]
    }

    // MARK: Schemas

    private static func property(_ type: String, _ description: String) -> JSONValue {
        .object(["type": .string(type), "description": .string(description)])
    }

    private static func schema(_ properties: [String: JSONValue], required: [String]) -> JSONValue {
        var fields: [String: JSONValue] = ["type": .string("object"), "properties": .object(properties)]
        if !required.isEmpty { fields["required"] = .array(required.map { .string($0) }) }
        return .object(fields)
    }

    struct Entry {
        var name: String
        var description: String
        var schema: JSONValue
        var plan: Planner
    }

    private static let nodeRef = property("string", "The node's ID or unique name.")

    static let planners: [Entry] = [
        Entry(
            name: "add_node", description: "Adds a node of a type (see list_node_types), optionally named, placed and with inputs set.",
            schema: schema([
                "type": property("string", "The type ID, such as creator.extrude."), "name": property("string", "A name for the node."),
                "position": property("array", "[x, y] on the canvas; omit to place it in free space."),
                "inputs": property("object", "Input values by socket name, in the form set_inputs takes under `values`."),
            ], required: ["type"]), plan: planAdd),
        Entry(
            name: "set_inputs", description: "Sets the constant values of a node's inputs; null clears one. "
                + "Segmented inputs take an option name or index.",
            schema: schema(["node": nodeRef, "values": property("object", "Socket name to value.")], required: ["node", "values"]),
            plan: planSet),
        Entry(
            name: "connect", description: "Wires an output into an input, replacing any wire already feeding it.",
            schema: schema([
                "from": property("string", "The output, as node.socket."), "to": property("string", "The input, as node.socket."),
            ], required: ["from", "to"]), plan: planConnect),
        Entry(
            name: "disconnect", description: "Removes the wire feeding an input.",
            schema: schema(["to": property("string", "The input, as node.socket.")], required: ["to"]), plan: planDisconnect),
        Entry(
            name: "remove_nodes", description: "Deletes nodes and the wires on them.",
            schema: schema(["nodes": property("array", "Node IDs or names.")], required: ["nodes"]), plan: planRemove),
        Entry(
            name: "rename_node", description: "Renames a node.",
            schema: schema(["node": nodeRef, "name": property("string", "The new name.")], required: ["node", "name"]),
            plan: planRename),
        Entry(
            name: "set_output", description: "Marks a node as an output of the document, or unmarks it.",
            schema: schema(["node": nodeRef, "output": property("boolean", "True to make it an output.")], required: ["node", "output"]),
            plan: planOutput),
        Entry(
            name: "move_node", description: "Moves a node on the canvas.",
            schema: schema(["node": nodeRef, "position": property("array", "[x, y].")], required: ["node", "position"]),
            plan: planMove),
    ]

    // MARK: Batch

    private static let batchTool = MCPTool(
        name: "batch",
        description: "Applies several edit operations as one undo step, or none if any is refused. Each operation is {tool, arguments}.",
        inputSchema: schema([
            "operations": property("array", "Edit tool calls, in order; later ones may use nodes earlier ones add."),
            "step_name": property("string", "One of Build, Rewire, Rearrange, Clean Up, Delete, Edit Graph; omit to choose for you."),
        ], required: ["operations"])
    ) { arguments, session, _ in
        let explicitName: String?
        switch stepName(in: arguments) {
        case .failure(let refusal): return .refused(refusal.sentence)
        case .success(let name): explicitName = name
        }
        guard let operations = arguments["operations"]?.array, !operations.isEmpty else {
            return .refused("Say which operations to apply.")
        }
        var scratch = session.content.graph
        var commands: [GraphCommand] = []
        var plans: [Plan] = []
        for (index, operation) in operations.enumerated() {
            let prefix = "Operation \(index + 1): "
            guard let tool = operation["tool"]?.string, let entry = planners.first(where: { $0.name == tool }) else {
                let called = operation["tool"]?.string ?? ""
                return .refused(prefix + "“\(called)” can't be part of a batch.")
            }
            switch entry.plan(operation["arguments"] ?? .object([:]), &scratch, session) {
            case .failure(let refusal): return .refused(prefix + refusal.sentence)
            case .success(let plan):
                plans.append(plan)
                commands += plan.commands
            }
        }
        return await EditOutcome.run(session: session, name: explicitName ?? batchName(for: plans), commands: commands)
    }
}
