import CreatorGraph
import CreatorKernel
import CreatorViewport

/// Turns the document's results into what the viewport shows (spec §6.1, §6.3, §4.4). Pure, so it's tested
/// without a GPU.
public enum SceneBuilder {
    /// The solids of `shown` nodes, in node order: every Output node in Final preview, the selected node in
    /// Selected-node preview.
    /// - A node with a result shows its solids. One that is still evaluating keeps showing its previous
    ///   outputs, not ghosted, so a drag doesn't flicker.
    /// - A node in error, or blocked by an error upstream, shows its last good result as a ghost.
    /// - Edge sets show their solid with the set's edges selected (a rule previewed on its own).
    /// - Edges picked by a selected rule glow on whichever shown solid is the rule's own (spec §6.3).
    /// - With `showsGuides` (Final preview), the edges of a selected rule whose solid no shown part holds come as
    ///   guide items (`ViewportItem.isGuide`), which the viewport draws over the part. A rule feeding a Fillet or
    ///   Chamfer is on the solid before the feature, which Final doesn't show (Errata (M6)): its edges glow where they
    ///   lie on the finished part and show as an overlay where they don't.
    public static func scene(shown: [NodeID], graph: Graph, results: [NodeID: NodeResult],
                             lastGood: [NodeID: [SocketName: Value]], selection: Set<NodeID>,
                             showsGuides: Bool = false) -> [SceneItem] {
        var scene: [SceneItem] = []
        for id in shown {
            guard let node = graph.nodes[id] else { continue }
            let result = results[id]
            let isGhost: Bool
            let outputs: [SocketName: Value]
            if let current = result?.outputs, result?.state.isSuccess == true || result?.state == .evaluating {
                (outputs, isGhost) = (current, false)
            } else if let previous = lastGood[id] {
                (outputs, isGhost) = (previous, true)
            } else {
                continue
            }
            scene += items(of: node, outputs: outputs, isGhost: isGhost, graph: graph)
        }
        let selectedSets = selection.sorted().flatMap { edgeSets(results[$0]) }
        let highlighted = highlighting(scene, selectedSets: selectedSets)
        return showsGuides ? highlighted + guides(for: selectedSets, notShownIn: highlighted) : highlighted
    }

    /// The items one node's outputs make, socket by socket in name order.
    static func items(of node: Node, outputs: [SocketName: Value], isGhost: Bool, graph: Graph) -> [SceneItem] {
        // An Output node passes its input through, so the solid's source is what's wired into it.
        let passThrough = node.isOutput ? graph.incomingLink(to: Endpoint(node: node.id, socket: "solid"))?.from : nil
        let ruleSolid = graph.incomingLink(to: Endpoint(node: node.id, socket: "solid"))?.from
        var items: [SceneItem] = []
        for (socket, value) in outputs.sorted(by: { $0.key < $1.key }) {
            for scalar in value.items {
                switch scalar {
                case .solid(let solid):
                    items.append(SceneItem(item: ViewportItem(solid: solid, isGhost: isGhost),
                                           source: passThrough ?? Endpoint(node: node.id, socket: socket)))
                case .edgeSet(let set):
                    items.append(SceneItem(item: ViewportItem(solid: set.solid, isGhost: isGhost,
                                                              selectedEdges: Set(set.edges)), source: ruleSolid))
                default:
                    continue
                }
            }
        }
        return items
    }

    static func edgeSets(_ result: NodeResult?) -> [EdgeSet] {
        guard let result, result.state.isSuccess, let outputs = result.outputs else { return [] }
        return outputs.values.flatMap(\.items).compactMap { scalar in
            if case .edgeSet(let set) = scalar { set } else { nil }
        }
    }

    /// One guide per solid the sets are on that no shown part holds, in the sets' order, holding all their edges. A
    /// solid shown only as a ghost is stale, so it doesn't count as shown. A set with no edges makes no guide.
    static func guides(for sets: [EdgeSet], notShownIn scene: [SceneItem]) -> [SceneItem] {
        var order: [Solid] = []
        var edges: [ObjectIdentifier: Set<EdgeID>] = [:]
        for set in sets where !set.edges.isEmpty
            && !scene.contains(where: { !$0.item.isGhost && $0.item.solid === set.solid }) {
            let key = ObjectIdentifier(set.solid)
            if edges[key] == nil { order.append(set.solid) }
            edges[key, default: []].formUnion(set.edges)
        }
        return order.map { solid in
            SceneItem(item: ViewportItem(solid: solid, selectedEdges: edges[ObjectIdentifier(solid)] ?? [], isGuide: true),
                      source: nil)
        }
    }

    /// Marks each selected set's edges on the shown item holding the very same solid. Ghosts are left alone: their
    /// solid is stale, so a highlight there would be a lie.
    static func highlighting(_ scene: [SceneItem], selectedSets: [EdgeSet]) -> [SceneItem] {
        scene.map { entry in
            guard !entry.item.isGhost else { return entry }
            var entry = entry
            for set in selectedSets where set.solid === entry.item.solid {
                entry.item.selectedEdges.formUnion(set.edges)
            }
            return entry
        }
    }
}
