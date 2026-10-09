import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport

extension AppModel {
    /// An inspector button (spec §6.4), from `EditorModel.inspectorRequest`.
    public func handle(_ request: InspectorRequest) {
        switch request.action {
        case .pickEdgesInView:
            beginPick(for: request.node)
        case .pickFacesInView:
            alert = .problem(AppProblem("Faces can't be picked yet", "No node in this version selects faces."))
        case .editSketch:
            beginSketch(for: request.node)
        }
    }

    /// "Pick edges in view…" (spec §5.3 rule 5) on an Edges by Tag rule, or on a feature (Fillet, Chamfer):
    /// - an Edges by Tag rule picks on the solid wired into it, starting from what it matches now;
    /// - a feature whose edges come from an Edges by Tag rule picks into that rule;
    /// - a feature whose edges come from another rule picks on that rule's solid, starting from its edges, and Done
    ///   wires a new Edges by Tag rule in its place.
    public func beginPick(for id: NodeID) {
        editor.commitPendingEntry()
        // The banner's Escape and Return are button shortcuts, which run before the palette's keys in `onInput`.
        editor.closePalette()
        let graph = document.graph
        guard let node = graph.nodes[id] else { return }
        if node.typeID == EdgesByTagNode.typeID {
            guard let source = graph.incomingLink(to: Endpoint(node: id, socket: "solid"))?.from,
                  let solid = solid(at: source) else {
                return refusePick("Wire a solid with a result into “\(node.name)” first, then pick its edges.")
            }
            let current = SceneBuilder.edgeSets(document.results[id]).first { $0.solid === solid }?.edges ?? []
            pick = PickSession(solid: solid, source: source, rule: id, consumer: nil, picked: current)
            return
        }
        let consumer = Endpoint(node: id, socket: "edges")
        guard let link = graph.incomingLink(to: consumer), let upstream = graph.nodes[link.from.node] else {
            return refusePick("Wire an edge rule into “\(node.name)” first, so there are edges to pick on.")
        }
        if upstream.typeID == EdgesByTagNode.typeID { return beginPick(for: upstream.id) }
        guard let set = SceneBuilder.edgeSets(document.results[upstream.id]).first, let source = producer(of: set.solid) else {
            return refusePick("“\(upstream.name)” has no edges to start from yet.")
        }
        pick = PickSession(solid: set.solid, source: source, rule: nil, consumer: consumer, picked: set.edges)
    }

    /// Done: the picks go into the rule (or a new one), as one undo step, and the rule is selected.
    public func finishPick() {
        guard let session = pick else { return }
        pick = nil
        let picks = ConstantValue.edgePicks(session.solid.topology.picks(for: session.picked))
        do {
            if let rule = session.rule {
                try document.perform(.setInput(rule, NodeSetting.picks, picks))
                editor.selection = [rule]
            } else {
                editor.selection = [try addRule(picks, from: session.source, into: session.consumer)]
            }
        } catch {
            alert = .problem(AppProblem("The picked edges couldn't be saved", error.message))
        }
    }

    /// Cancel: leaves the graph as it was.
    public func cancelPick() {
        pick = nil
    }

    /// A click in the viewport. While picking, a click on an edge of the picked solid adds or removes it.
    func viewportClicked(_ target: PickTarget?) {
        guard var session = pick, case .edge(let index, let edge)? = target, viewport.items.indices.contains(index),
              viewport.items[index].solid === session.solid else { return }
        session.toggle(edge)
        pick = session
    }

    /// "Select Edges of Face" (spec §6.3): while picking, adds the face's edges to the pick; otherwise makes a new
    /// Edges by Tag rule holding them, wired from the node that made the solid, and selects it.
    func selectEdgesOfFace(_ face: ViewportFaceRef, _ picks: [EdgePick], _ edges: [EdgeID]) {
        guard viewport.items.indices.contains(face.solidIndex) else { return }
        let solid = viewport.items[face.solidIndex].solid
        if var session = pick {
            guard solid === session.solid else { return }
            session.add(edges)
            pick = session
            return
        }
        guard let source = producer(of: solid) else {
            alert = .problem(AppProblem("No rule was made", "The node that made this solid can't be found."))
            return
        }
        do {
            editor.selection = [try addRule(.edgePicks(picks), from: source, into: nil)]
        } catch {
            alert = .problem(AppProblem("No rule was made", error.message))
        }
    }

    /// Adds an Edges by Tag rule holding `picks`, wired from `source` and, when given, into `consumer` (replacing
    /// its wire), as one undo step. It's placed between the two nodes, or beside `source`.
    func addRule(_ picks: ConstantValue, from source: Endpoint, into consumer: Endpoint?) throws(GraphError) -> NodeID {
        let graph = document.graph
        let from = graph.nodes[source.node]?.position ?? .zero
        let position = consumer.flatMap { graph.nodes[$0.node]?.position }.map { (from + $0) * 0.5 + Vector2(0, 140) }
            ?? from + Vector2(240, 140)
        var rule = registry.makeNode(EdgesByTagNode.typeID, at: position)
        rule.inputValues[NodeSetting.picks] = picks
        var commands: [GraphCommand] = [.addNode(rule), .connect(Link(from: source, to: Endpoint(node: rule.id, socket: "solid")))]
        if let consumer {
            commands.append(.connect(Link(from: Endpoint(node: rule.id, socket: "edges"), to: consumer)))
        }
        try document.perform(.batch(commands))
        return rule.id
    }

    /// The output socket that produced `solid`, by identity: a shown solid's recorded source, else any node
    /// whose current result carries it, preferring a node that isn't an Output (which only passes it through).
    func producer(of solid: Solid) -> Endpoint? {
        if let source = sources[ObjectIdentifier(solid)] { return source }
        let candidates = document.results.keys.sorted().flatMap { id -> [(Endpoint, Bool)] in
            guard let result = document.results[id], result.state.isSuccess, let outputs = result.outputs else { return [] }
            let isOutput = document.graph.nodes[id]?.isOutput ?? false
            return outputs.keys.sorted().compactMap { socket in
                outputs[socket]?.items.contains { scalar in
                    if case .solid(let candidate) = scalar { candidate === solid } else { false }
                } == true ? (Endpoint(node: id, socket: socket), isOutput) : nil
            }
        }
        return candidates.first { !$0.1 }?.0 ?? candidates.first?.0
    }

    /// The first solid the output `endpoint` carries now.
    func solid(at endpoint: Endpoint) -> Solid? {
        guard let result = document.results[endpoint.node], result.state.isSuccess else { return nil }
        for case .solid(let solid) in result.outputs?[endpoint.socket]?.items ?? [] { return solid }
        return nil
    }

    private func refusePick(_ message: String) {
        alert = .problem(AppProblem("Nothing to pick on", message))
    }
}
