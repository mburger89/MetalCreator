import CreatorGeometry
import CreatorGraph
import CreatorKernel

extension EditorModel {
    /// Wires `link`, replacing whatever already feeds its input, as one undo step. A wire the
    /// graph refuses changes nothing and shakes the input's node with a plain message.
    public func connect(_ link: Link) {
        guard !graph.links.contains(link) else { return }
        if let problem = graph.connectionProblem(from: link.from, to: link.to, registry: registry) {
            refuse(problem.message, node: link.to.node)
            return
        }
        do {
            try document.perform(.connect(link))
        } catch {
            refuse(error.message, node: link.to.node)
        }
    }

    /// Delete / ⌫: removes the selected nodes and their wires, as one undo step.
    public func deleteSelection() {
        let ids = selection.filter { graph.nodes[$0] != nil }.sorted()
        guard !ids.isEmpty else { return }
        do {
            try document.perform(.batch(ids.map { .removeNode($0) }))
            selection = []
        } catch {
            refuse(error.message, node: nil)
        }
    }

    /// ⌘C: copies the selected nodes and the wires between them.
    public func copySelection() {
        guard !selection.isEmpty else { return }
        setClipboard(clipboard(of: selection))
    }

    /// ⌘V: pastes the clipboard offset down and right, one step further on each paste,
    /// and selects the copies.
    public func paste() {
        guard let clipboard else { return }
        if let ids = insert(clipboard, offset: nextPasteOffset()) { selection = ids }
    }

    /// ⌘D: duplicates the selection offset down and right, leaving the clipboard alone.
    public func duplicateSelection() {
        guard !selection.isEmpty else { return }
        if let ids = insert(clipboard(of: selection), offset: Vector2(24, 24)) { selection = ids }
    }

    /// Adds a node of `typeID` with its top-left corner at `screen` (canvas-local screen points: under the palette,
    /// or where a library node was dropped) and selects it, as one undo step.
    public func addNode(_ typeID: String, atScreen screen: Vector2) {
        add(registry.makeNode(typeID, at: flow.stored(transform.toCanvas(screen))))
    }

    /// Adds `node` (made by `NodeRegistry.makeNode`) and selects it, as one undo step.
    func add(_ node: Node) {
        do {
            try document.perform(.addNode(node))
            selection = [node.id]
        } catch {
            refuse(error.message, node: nil)
        }
    }

    func clipboard(of ids: Set<NodeID>) -> NodeClipboard {
        let nodes = ids.sorted().compactMap { graph.nodes[$0] }
        let links = graph.links.filter { ids.contains($0.from.node) && ids.contains($0.to.node) }
        return NodeClipboard(nodes: nodes, links: links)
    }

    /// Adds fresh copies of `clipboard` moved by `offset` (stored coordinates) as one undo
    /// step. Returns the new IDs, or `nil` if the graph refused.
    func insert(_ clipboard: NodeClipboard, offset: Vector2) -> Set<NodeID>? {
        guard !clipboard.nodes.isEmpty else { return nil }
        var mapping: [NodeID: NodeID] = [:]
        var commands: [GraphCommand] = []
        for original in clipboard.nodes {
            var copy = original
            copy.id = NodeID()
            copy.position = original.position + offset
            mapping[original.id] = copy.id
            commands.append(.addNode(copy))
        }
        let links = clipboard.links.compactMap { link -> Link? in
            guard let from = mapping[link.from.node], let to = mapping[link.to.node] else { return nil }
            return Link(from: Endpoint(node: from, socket: link.from.socket), to: Endpoint(node: to, socket: link.to.socket))
        }
        // Copied wires were valid when copied and join only new nodes, so they are restored as they were.
        if !links.isEmpty { commands.append(.restoreLinks(links)) }
        do {
            try document.perform(.batch(commands))
            return Set(mapping.values)
        } catch {
            refuse(error.message, node: nil)
            return nil
        }
    }
}
