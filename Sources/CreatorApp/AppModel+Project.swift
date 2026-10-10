import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorSketchEditor
import CreatorViewport

extension AppModel {
    static let noProjection = "Projecting isn't available right now."

    /// The sketch with its projected edges re-resolved against the solids wired into `references` (current curves; suspended
    /// where a pick no longer finds exactly one edge), as the node resolves them on every evaluation, so the editor draws what
    /// the node outputs. Unchanged when nothing is projected, or when the wired solid has no result yet.
    func refreshedProjections(_ sketch: Sketch, of node: Node) -> Sketch {
        guard !SketchStore.projectedReferences(sketch).isEmpty, let plane = sketchPlane(of: node, sketch),
              let link = document.graph.incomingLink(to: Endpoint(node: node.id, socket: SketchStore.referencesSocket)),
              let result = document.results[link.from.node], result.state.isSuccess else { return sketch }
        let solids = (result.outputs?[link.from.socket]?.items ?? []).compactMap { scalar -> Solid? in
            if case .solid(let solid) = scalar { solid } else { nil }
        }
        return SketchNode.refreshingProjections(of: sketch, settings: node.inputValues, references: solids, on: plane)
    }

    /// The Project tool's pick (sketcher spec §8) as projectable edges: the picked edge, or every edge of the picked face, on
    /// `plane`, each with the pick the Sketch node stores (`topology.picks(for:)`) and the solid it is on. The Sketch node's
    /// `references` takes one wire, so the part must be the one already wired there, or the first (and then it must not be made
    /// from this sketch). Edges that can't be projected are left out with the reason, said once per reason.
    func resolveProjection(_ target: PickTarget, onto plane: Plane, for sketchNode: NodeID) -> ProjectionResolution {
        func refused(_ text: String) -> ProjectionResolution { ProjectionResolution(candidates: [], skipped: [text]) }
        guard viewport.items.indices.contains(target.solidIndex) else { return refused("That part isn't shown any more.") }
        let solid = viewport.items[target.solidIndex].solid
        guard let source = producer(of: solid) else { return refused("The node that made this part can't be found.") }
        if let problem = referencesProblem(source, sketchNode) { return refused(problem) }
        let topology = solid.topology
        let isFace: Bool
        let edges: [EdgeInfo]
        switch target {
        case .edge(_, let id):
            (isFace, edges) = (false, topology.edge(id).map { [$0] } ?? [])
        case .face(_, let id):
            (isFace, edges) = (true, topology.edges.filter { !$0.isSeam && $0.faces.contains(id) })
        }
        var candidates: [ProjectionCandidate] = []
        var left: [(reason: String, count: Int)] = []
        for edge in edges {
            switch EdgeProjection.project(edge, onto: plane) {
            case .curve(let curve):
                let picks = topology.picks(for: [edge.id])
                if picks.count == 1, let pick = picks.first {
                    candidates.append(ProjectionCandidate(curve: curve, pick: pick, solid: target.solidIndex))
                } else {
                    Self.note("it has no stable name: it isn't between two faces", in: &left)
                }
            case .refused(let reason):
                Self.note(reason, in: &left)
            }
        }
        let skipped = left.map { entry -> String in
            if !isFace { return "That edge can't be projected: \(entry.reason)." }
            let which = entry.count == 1 ? "An edge" : "\(entry.count.formatted()) edges"
            return "\(which) of that face can't be projected: \(entry.reason)."
        }
        return ProjectionResolution(candidates: candidates, skipped: skipped)
    }

    private static func note(_ reason: String, in left: inout [(reason: String, count: Int)]) {
        if let index = left.firstIndex(where: { $0.reason == reason }) {
            left[index].count += 1
        } else {
            left.append((reason, 1))
        }
    }

    /// Why `source` can't be the part a sketch projects from, in words, or `nil`: the sketch's `references` already holds
    /// another part, or wiring this one would make a cycle (the part is made from the sketch).
    func referencesProblem(_ source: Endpoint, _ sketchNode: NodeID) -> String? {
        let references = Endpoint(node: sketchNode, socket: SketchStore.referencesSocket)
        if let link = document.graph.incomingLink(to: references) {
            return link.from == source ? nil : "This sketch already projects from another part. Project from one part per sketch."
        }
        switch document.graph.connectionProblem(from: source, to: references, registry: registry) {
        case nil: return nil
        case .wouldCreateCycle?: return "That part is made from this sketch, so its edges can't be projected into it."
        case _?: return "That part can't be wired into this sketch."
        }
    }
}
