import CreatorGraph
import CreatorKernel
import Foundation

/// Runs the commands of one client step and reports what it changed.
@MainActor public enum EditOutcome {
    /// Plain-language text for a refused edit (the editor's `GraphError.message`, which this portable module can't import).
    static func message(_ error: GraphError) -> String {
        switch error {
        case .invalidConnection(let problem): problem.message
        case .nodeNotFound: "That node no longer exists."
        case .duplicateNode: "That node already exists."
        case .linkNotFound: "That wire no longer exists."
        case .parameterNotFound: "That parameter no longer exists."
        case .invalidValue(let message): message
        }
    }

    private struct Snapshot: Equatable {
        var state: String
        var message: String?
    }

    private static func snapshot(_ session: any DocumentSession) -> [NodeID: Snapshot] {
        var taken: [NodeID: Snapshot] = [:]
        for id in session.content.graph.nodes.keys {
            let (state, message) = ReadTools.stateText(session.results[id]?.state)
            taken[id] = Snapshot(state: state, message: message)
        }
        return taken
    }

    /// One undo step named `name`: the single command, or `commands` as a batch. Waits for the evaluation and returns
    /// `{step, changed, still_evaluating, added?}`.
    public static func run(session: any DocumentSession, name: String, commands: [GraphCommand]) async -> MCPToolResult {
        if let refusal = session.editRefusal() { return .refused(refusal) }
        guard !commands.isEmpty else { return .refused("There is nothing to change.") }
        let before = snapshot(session)
        // The planners already applied these to a scratch graph and caught every refusal, so a failure here has no "Operation N" prefix.
        do {
            try session.perform(commands.count == 1 ? commands[0] : .batch(commands), name: name)
        } catch {
            return .refused(message(error))
        }
        return await report(session: session, name: name, before: before, commands: commands)
    }

    /// Takes back or re-applies a step (`change` does it, returning the step's name or a refusal) and reports what it changed.
    public static func observe(session: any DocumentSession, change: () async -> SessionOutcome) async -> MCPToolResult {
        let before = snapshot(session)
        switch await change() {
        case .refused(let sentence): return .refused(sentence)
        case .done(let name): return await report(session: session, name: name ?? UndoName.edit, before: before, commands: [])
        }
    }

    private static func report(
        session: any DocumentSession, name: String, before: [NodeID: Snapshot], commands: [GraphCommand]
    ) async -> MCPToolResult {
        let settled = await session.settle(within: .seconds(60))
        let after = snapshot(session)
        let graph = session.content.graph
        let order = graph.nodes.values.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        var changed: [JSONValue] = []
        for node in order {
            let isNew = before[node.id] == nil
            guard let now = after[node.id], isNew || before[node.id] != now else { continue }
            var fields: [String: JSONValue] = [
                "id": .string(node.id.rawValue.uuidString), "name": .string(node.name), "state": .string(now.state),
            ]
            if let text = now.message { fields["message"] = .string(text) }
            changed.append(.object(fields))
        }
        let added = commands.compactMap { command -> JSONValue? in
            guard case .addNode(let node) = command, graph.nodes[node.id] != nil else { return nil }
            return .string(node.id.rawValue.uuidString)
        }
        var result: [String: JSONValue] = [
            "step": .string(name), "changed": .array(changed), "still_evaluating": .bool(!settled),
        ]
        if !added.isEmpty { result["added"] = .array(added) }
        return .ok(.object(result))
    }
}
