import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation

extension EditTools {
    // MARK: Planning

    /// Applies `commands` to the scratch graph, so later planning sees them.
    static func commit(
        _ plan: Plan, to graph: inout Graph, _ session: any DocumentSession
    ) -> Result<Plan, Refusal> {
        for command in plan.commands {
            do {
                _ = try graph.apply(command, registry: session.registry)
            } catch {
                return .failure(Refusal(EditOutcome.message(error)))
            }
        }
        return .success(plan)
    }

    static func node(_ ref: JSONValue?, _ graph: Graph) -> Result<Node, Refusal> {
        switch Addressing.node(ref, in: graph) {
        case .failure(let refusal): return .failure(refusal)
        case .success(let id):
            guard let found = graph.nodes[id] else { return .failure(Refusal("That node no longer exists.")) }
            return .success(found)
        }
    }

    static func options(for socket: SocketName, of node: Node, _ session: any DocumentSession) -> [String]? {
        guard let definition = session.registry[node.typeID] else { return nil }
        for section in definition.inspector(for: node) {
            for control in section.controls {
                if case .segmented(let name, let choices) = control, name == socket { return choices }
            }
        }
        return nil
    }

    /// The `setInput` commands for `values` on `node`, and whether any was a clear.
    static func inputCommands(
        _ values: [String: JSONValue], on node: Node, _ session: any DocumentSession
    ) -> Result<(commands: [GraphCommand], label: String?, clears: Bool), Refusal> {
        let specs = session.registry.inputs(for: node)
        var commands: [GraphCommand] = []
        var clears = false
        var label: String?
        for key in values.keys.sorted() {
            let socket = SocketName(key)
            let json = values[key] ?? .null
            let coerced: Result<ConstantValue?, Refusal>
            let shown: String
            if let spec = specs.first(where: { $0.name == socket }) {
                coerced = ValueCoercion.value(json, for: spec, options: options(for: socket, of: node, session))
                shown = ValueCoercion.label(for: socket)
            } else if textSettings.contains(socket),
                      node.inputValues[socket] != nil || session.registry[node.typeID]?.defaultSettings[socket] != nil {
                shown = ValueCoercion.label(for: socket)
                coerced = ValueCoercion.text(json, label: shown)
            } else {
                return .failure(Refusal("\(node.name) has no input called “\(key)”."))
            }
            switch coerced {
            case .failure(let refusal): return .failure(refusal)
            case .success(let value):
                if value == nil { clears = true }
                label = shown
                commands.append(.setInput(node.id, socket, value))
            }
        }
        return .success((commands, label, clears))
    }

    static func inputName(count: Int, label: String?, clears: Bool) -> String {
        guard count == 1, let label else { return UndoName.changeInputs }
        return clears ? UndoName.clearInput(label) : UndoName.changeInput(label)
    }

    static func planAdd(_ arguments: JSONValue, _ graph: inout Graph, _ session: any DocumentSession) -> Result<Plan, Refusal> {
        let type = arguments["type"]?.string ?? ""
        guard session.registry.all.contains(where: { $0.typeID == type }) else {
            return .failure(Refusal("There's no node type “\(type)”."))
        }
        var node = session.registry.makeNode(type)
        if let position = arguments["position"] {
            guard let items = position.array, items.count == 2, let x = items[0].double, let y = items[1].double,
                  x.isFinite, y.isFinite else { return .failure(Refusal("The position needs two numbers, like [0, 0].")) }
            node.position = Vector2(x, y)
        } else {
            node.position = session.freePosition(for: node, in: graph)
        }
        let undo = UndoName.addNode(node)
        var commands: [GraphCommand] = [.addNode(node)]
        if let name = arguments["name"] {
            guard let text = name.string, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                return .failure(Refusal("The name needs text."))
            }
            commands.append(.rename(node.id, text))
            node.name = text
        }
        if let inputs = arguments["inputs"] {
            guard let values = inputs.object else { return .failure(Refusal("The inputs need an object of socket names and values.")) }
            switch inputCommands(values, on: node, session) {
            case .failure(let refusal): return .failure(refusal)
            case .success(let made): commands += made.commands
            }
        }
        return commit(Plan(name: undo, commands: commands), to: &graph, session)
    }

    static func planSet(_ arguments: JSONValue, _ graph: inout Graph, _ session: any DocumentSession) -> Result<Plan, Refusal> {
        switch node(arguments["node"], graph) {
        case .failure(let refusal): return .failure(refusal)
        case .success(let target):
            guard let values = arguments["values"]?.object, !values.isEmpty else {
                return .failure(Refusal("Say which inputs to set as `values`, an object of socket names and values."))
            }
            switch inputCommands(values, on: target, session) {
            case .failure(let refusal): return .failure(refusal)
            case .success(let made):
                let name = inputName(count: made.commands.count, label: made.label, clears: made.clears)
                return commit(Plan(name: name, commands: made.commands), to: &graph, session)
            }
        }
    }

    static func planConnect(_ arguments: JSONValue, _ graph: inout Graph, _ session: any DocumentSession) -> Result<Plan, Refusal> {
        guard let from = arguments["from"]?.string, let to = arguments["to"]?.string else {
            return .failure(Refusal("Say which output to wire from and which input to wire to, as node.socket."))
        }
        switch Addressing.endpoint(from, in: graph, registry: session.registry, output: true) {
        case .failure(let refusal): return .failure(refusal)
        case .success(let source):
            switch Addressing.endpoint(to, in: graph, registry: session.registry, output: false) {
            case .failure(let refusal): return .failure(refusal)
            case .success(let target):
                if let problem = graph.connectionProblem(from: source, to: target, registry: session.registry) {
                    return .failure(Refusal(problem.message))
                }
                let plan = Plan(name: UndoName.connect, commands: [.connect(Link(from: source, to: target))])
                return commit(plan, to: &graph, session)
            }
        }
    }

    static func planDisconnect(_ arguments: JSONValue, _ graph: inout Graph, _ session: any DocumentSession) -> Result<Plan, Refusal> {
        guard let to = arguments["to"]?.string else { return .failure(Refusal("Say which input to disconnect, as node.socket.")) }
        switch Addressing.endpoint(to, in: graph, registry: session.registry, output: false) {
        case .failure(let refusal): return .failure(refusal)
        case .success(let target):
            guard let link = graph.links.first(where: { $0.to == target }) else {
                let name = graph.nodes[target.node]?.name ?? ""
                return .failure(Refusal("Nothing is wired into \(name).\(target.socket)."))
            }
            return commit(Plan(name: UndoName.disconnect, commands: [.disconnect(link)]), to: &graph, session)
        }
    }

    static func planRemove(_ arguments: JSONValue, _ graph: inout Graph, _ session: any DocumentSession) -> Result<Plan, Refusal> {
        guard let refs = arguments["nodes"]?.array, !refs.isEmpty else { return .failure(Refusal("Say which nodes to remove.")) }
        var ids: [NodeID] = []
        for ref in refs {
            switch Addressing.node(ref, in: graph) {
            case .failure(let refusal): return .failure(refusal)
            case .success(let id): if !ids.contains(id) { ids.append(id) }
            }
        }
        return commit(Plan(name: UndoName.delete, commands: ids.map { .removeNode($0) }), to: &graph, session)
    }

    static func planRename(_ arguments: JSONValue, _ graph: inout Graph, _ session: any DocumentSession) -> Result<Plan, Refusal> {
        switch node(arguments["node"], graph) {
        case .failure(let refusal): return .failure(refusal)
        case .success(let target):
            guard let name = arguments["name"]?.string, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                return .failure(Refusal("The name needs text."))
            }
            return commit(Plan(name: UndoName.renameNode, commands: [.rename(target.id, name)]), to: &graph, session)
        }
    }

    static func planOutput(_ arguments: JSONValue, _ graph: inout Graph, _ session: any DocumentSession) -> Result<Plan, Refusal> {
        switch node(arguments["node"], graph) {
        case .failure(let refusal): return .failure(refusal)
        case .success(let target):
            guard let flag = arguments["output"]?.bool else { return .failure(Refusal("Output needs true or false.")) }
            return commit(Plan(name: UndoName.setOutput, commands: [.setOutput(target.id, flag)]), to: &graph, session)
        }
    }

    static func planMove(_ arguments: JSONValue, _ graph: inout Graph, _ session: any DocumentSession) -> Result<Plan, Refusal> {
        switch node(arguments["node"], graph) {
        case .failure(let refusal): return .failure(refusal)
        case .success(let target):
            guard let items = arguments["position"]?.array, items.count == 2, let x = items[0].double, let y = items[1].double,
                  x.isFinite, y.isFinite else { return .failure(Refusal("The position needs two numbers, like [0, 0].")) }
            return commit(Plan(name: UndoName.move, commands: [.move(target.id, to: Vector2(x, y))]), to: &graph, session)
        }
    }
}
