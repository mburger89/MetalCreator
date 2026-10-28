import CreatorGraph
import CreatorKernel
import CreatorViewport

/// Selecting a feature by clicking the part (DIM-3 decision 3, spec §3.3).
extension AppModel {
    /// A click in the viewport with no pick session and no sketch:
    /// - only in Final preview (in Selected-node preview the selection chooses what is shown, so a click would switch it);
    /// - empty space clears the graph selection;
    /// - a face selects the feature its tags name (`feature(for:producers:graph:results:)`), an edge the one its two faces
    ///   name together; a face with no tags (an implicit mesh) changes nothing.
    func selectFeature(at target: PickTarget?) {
        guard previewMode == .final else { return }
        guard let target else {
            if !editor.selection.isEmpty { editor.selection = [] }
            return
        }
        guard viewport.items.indices.contains(target.solidIndex) else { return }
        let topology = viewport.items[target.solidIndex].solid.topology
        var tags: Set<TopoTag> = []
        switch target {
        case .face(_, let face):
            tags = topology.face(face)?.tags ?? []
        case .edge(_, let edge):
            for face in topology.edge(edge)?.faces ?? [] { tags.formUnion(topology.face(face)?.tags ?? []) }
        }
        guard !tags.isEmpty,
              let feature = Self.feature(for: Set(tags.map(\.node)), producers: levelProducers(), graph: editor.graph,
                                         results: editor.levelResults) else { return }
        if editor.selection != [feature] { editor.selection = [feature] }
    }

    /// The identity a face's tags name → the node of the level shown, cached by the document's content and the level (it is
    /// rebuilt when either changes).
    func levelProducers() -> [NodeID: NodeID] {
        let content = document.content
        let level = editor.levelPath
        if let cache = producerCache, cache.level == level, cache.content == content { return cache.producers }
        let producers = content.levelProducers(at: level, registry: registry)
        producerCache = ProducerCache(content: content, level: level, producers: producers)
        return producers
    }

    /// The feature to select for a face whose tags name `tagNodes`: the tags' nodes resolved to the level shown (a name
    /// `producers` doesn't know is dropped); of those the most downstream (one no other is downstream of), the lowest ID
    /// among equals; and when that node declares no dimensions, the nearest upstream node that does (breadth-first over its
    /// inputs, lowest ID first), else the node itself. `nil` when no tag resolves.
    static func feature(for tagNodes: Set<NodeID>, producers: [NodeID: NodeID], graph: Graph,
                        results: [NodeID: NodeResult]) -> NodeID? {
        let candidates = Set(tagNodes.compactMap { producers[$0] }).filter { graph.nodes[$0] != nil }
        guard !candidates.isEmpty else { return nil }
        let upstreamOf = Dictionary(uniqueKeysWithValues: candidates.map { ($0, upstream(of: $0, in: graph)) })
        let latest = candidates.filter { node in !candidates.contains { $0 != node && upstreamOf[$0]?.contains(node) == true } }
        guard let chosen = latest.min() else { return nil }
        func declares(_ node: NodeID) -> Bool { results[node]?.dimensions.isEmpty == false }
        if declares(chosen) { return chosen }
        // Breadth-first, a level at a time, each level in ID order.
        var seen: Set<NodeID> = [chosen]
        var frontier = [chosen]
        while !frontier.isEmpty {
            var next: Set<NodeID> = []
            for node in frontier {
                for link in graph.links where link.to.node == node && seen.insert(link.from.node).inserted {
                    next.insert(link.from.node)
                }
            }
            let level = next.sorted()
            if let found = level.first(where: declares) { return found }
            frontier = level
        }
        return chosen
    }

    /// Every node `node` depends on.
    private static func upstream(of node: NodeID, in graph: Graph) -> Set<NodeID> {
        var seen: Set<NodeID> = []
        var pending = [node]
        while let current = pending.popLast() {
            for link in graph.links where link.to.node == current && seen.insert(link.from.node).inserted {
                pending.append(link.from.node)
            }
        }
        return seen
    }
}
