import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorViewport

/// Traces a picked face or edge of a part back to the sketch entities that made it (dimensions spec §3.5).
enum ModelDimensionTrace {
    /// What `target` (on `viewport.items[index]`, a part that is neither ghost nor guide) comes from, best first:
    /// sweep traces (the face's `.side` tags), then projections (Sketch nodes in node-ID order). [] when nothing.
    static func items(for target: PickTarget, solid: Solid, graph: Graph, results: [NodeID: NodeResult]) -> [SketchItem] {
        switch target {
        case .face(_, let id):
            guard let face = solid.topology.face(id) else { return [] }
            return walls(of: face, graph: graph, results: results)
        case .edge(_, let id):
            guard solid.topology.edge(id) != nil else { return [] }
            return edgeItems(id, solid: solid, graph: graph, results: results)
        }
    }

    /// Sweep traces of an edge's faces, then the Sketches projecting it.
    private static func edgeItems(_ id: EdgeID, solid: Solid, graph: Graph, results: [NodeID: NodeResult]) -> [SketchItem] {
        let topology = solid.topology
        var faces: [FaceInfo] = []
        for faceID in topology.edge(id)?.faces ?? [] where !faces.contains(where: { $0.id == faceID }) {
            if let face = topology.face(faceID) { faces.append(face) }
        }
        let walled = faces.map { walls(of: $0, graph: graph, results: results) }
        var found = walled.first { !$0.isEmpty } ?? []
        if walled.count == 2, !walled[0].isEmpty, !walled[1].isEmpty {
            found = sharedPoints(walled[0], walled[1], results: results)
        }
        for node in graph.nodes.keys.sorted() {
            guard let definition = graph.nodes[node], definition.typeID == SketchNode.typeID,
                  let trace = results[node]?.sketchTrace,
                  let entity = SketchNode.projectedEntity(for: id, on: solid, node: definition, trace: trace) else { continue }
            let item = SketchItem(node: node, entity: entity)
            if !found.contains(item) { found.append(item) }
        }
        return found
    }

    /// The first item of `first` whose node `second` also has, with that item of `second`; nil when none.
    static func shared(_ first: [SketchItem], _ second: [SketchItem]) -> (SketchItem, SketchItem)? {
        for item in first {
            if let other = second.first(where: { $0.node == item.node }) { return (item, other) }
        }
        return nil
    }

    /// The sketch entity behind each of `face`'s side tags, by tag order; only through a direct Sketch → sweep link.
    private static func walls(of face: FaceInfo, graph: Graph, results: [NodeID: NodeResult]) -> [SketchItem] {
        var items: [SketchItem] = []
        for tag in face.tags.sorted(by: { $0.sortKey < $1.sortKey }) {
            guard case .side(let loop, let segment) = tag.role,
                  let link = graph.incomingLink(to: Endpoint(node: tag.node, socket: "profile")),
                  link.from.socket == "profiles", graph.nodes[link.from.node]?.typeID == SketchNode.typeID,
                  let entity = results[link.from.node]?.sketchTrace?.entity(item: tag.item, loop: loop, segment: segment)
            else { continue }
            let item = SketchItem(node: link.from.node, entity: entity)
            if !items.contains(item) { items.append(item) }
        }
        return items
    }

    /// For each Sketch both sides have: the point entity the two walls' entities both end on. None shared → nothing.
    private static func sharedPoints(_ first: [SketchItem], _ second: [SketchItem], results: [NodeID: NodeResult]) -> [SketchItem] {
        var points: [SketchItem] = []
        for a in first {
            guard let sketch = results[a.node]?.sketchTrace?.sketch else { continue }
            let ends = endpoints(of: a.entity, in: sketch)
            for b in second where b.node == a.node {
                guard let point = endpoints(of: b.entity, in: sketch).first(where: ends.contains) else { continue }
                let item = SketchItem(node: a.node, entity: point)
                if !points.contains(item) { points.append(item) }
            }
        }
        return points
    }

    private static func endpoints(of entity: SketchEntityID, in sketch: Sketch) -> [SketchEntityID] {
        switch sketch.entities[entity]?.kind {
        case .line(let start, let end)?, .arc(_, let start, let end)?: [start, end]
        default: []
        }
    }
}
