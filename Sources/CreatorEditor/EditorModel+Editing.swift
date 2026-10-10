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
            try edit(.connect(link))
        } catch {
            refuse(error.message, node: link.to.node)
        }
    }

    /// Delete / ⌫: removes the selected nodes and their wires, as one undo step. Group Input and Group Output stay
    /// (a group always has both); with only those selected, it says why nothing happened.
    public func deleteSelection() {
        let present = selection.filter { graph.nodes[$0] != nil }
        let ids = present.filter { !isBoundary($0) }.sorted()
        guard !ids.isEmpty else {
            if !present.isEmpty { refuse("A group's Group Input and Group Output can't be deleted.", node: nil) }
            return
        }
        do {
            try edit(.batch(ids.map { .removeNode($0) }))
            selection = []
        } catch {
            refuse(error.message, node: nil)
        }
    }

    /// ⌘C: copies the selected items (the nodes and the wires between them).
    public func copySelection() {
        guard !canvasSelection.isEmpty else { return }
        let copied = clipboard(of: canvasSelection)
        // Group Input and Output are never copied, so a selection of only them copies nothing: keep what was there.
        guard !copied.isEmpty else { return }
        setClipboard(copied)
    }

    /// ⌘V: pastes the clipboard offset down and right, one step further on each paste,
    /// and selects the copies.
    public func paste() {
        guard let clipboard else { return }
        if let copies = insert(clipboard, offset: nextPasteOffset()) { canvasSelection = copies }
    }

    /// ⌘D: duplicates the selection offset down and right, leaving the clipboard alone.
    public func duplicateSelection() {
        guard !canvasSelection.isEmpty else { return }
        if let copies = insert(clipboard(of: canvasSelection), offset: Vector2(24, 24)) { canvasSelection = copies }
    }

    /// Adds a node of `typeID` with its top-left corner at `screen` (canvas-local screen points: under the palette,
    /// or where a library node was dropped) and selects it, as one undo step. Returns whether the graph took it.
    @discardableResult
    public func addNode(_ typeID: String, atScreen screen: Vector2) -> Bool {
        let position = flow.stored(transform.toCanvas(screen))
        return add(libraryNode(for: typeID, at: position) ?? registry.makeNode(typeID, at: position))
    }

    /// Adds `node` (made by `NodeRegistry.makeNode`) and selects it, as one undo step. Returns false, having shown
    /// the refusal, when the graph refuses it.
    @discardableResult
    func add(_ node: Node) -> Bool {
        do {
            try edit(.addNode(node))
            selection = [node.id]
            return true
        } catch {
            refuse(error.message, node: nil)
            return false
        }
    }

    /// What copying `items` puts on the clipboard: their nodes and the wires between them, and the definitions their
    /// group nodes use. Group Input and Group Output are never copied. B adds: comments.
    func clipboard(of items: CanvasSelection) -> NodeClipboard {
        let nodes = items.nodes.sorted().compactMap { graph.nodes[$0] }.filter { !GroupNodes.isBoundary($0) }
        let ids = Set(nodes.map(\.id))
        let links = graph.links.filter { ids.contains($0.from.node) && ids.contains($0.to.node) }
        return NodeClipboard(nodes: nodes, links: links,
                             definitions: GroupMerge.definitions(used: nodes, in: document.content))
    }

    /// Whether `id` is Group Input or Group Output of the level shown.
    func isBoundary(_ id: NodeID) -> Bool {
        graph.nodes[id].map(GroupNodes.isBoundary) ?? false
    }

    /// Adds fresh copies of `clipboard` moved by `offset` (stored coordinates) as one undo step, with the group
    /// definitions it carries that the document lacks or has with other content (`GroupMerge`; the copied group
    /// nodes follow them). Returns the copies, to select, or `nil` if the graph refused. B adds: comments.
    func insert(_ clipboard: NodeClipboard, offset: Vector2) -> CanvasSelection? {
        guard !clipboard.nodes.isEmpty else { return nil }
        let merge = GroupMerge.plan(importing: clipboard.definitions, into: document.content)
        var mapping: [NodeID: NodeID] = [:]
        var commands: [GraphCommand] = []
        for original in clipboard.nodes {
            var copy = merge.retargeting(original)
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
            // The definitions are added to the document, the nodes to the level shown.
            try document.perform(.batch(merge.additions.map { .addDefinition($0) } + [GraphCommand.batch(commands).at(graphPath)]))
            return CanvasSelection(nodes: Set(mapping.values))
        } catch {
            refuse(error.message, node: nil)
            return nil
        }
    }
}
