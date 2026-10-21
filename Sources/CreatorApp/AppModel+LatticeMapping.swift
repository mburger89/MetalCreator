import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import CreatorViewport

extension AppModel {
    /// The node types that have a `mapping`.
    static let latticeTypes: Set<String> = [TPMSNode.typeID, StrutLatticeNode.typeID, VoronoiLatticeNode.typeID]

    /// "Pick Face in View…" on a lattice node's Face mapping (implicit spec §3.5): the viewport shows the solid the node's region was
    /// baked from, and a click on one of its faces sets the node to Face mapping on it (`finishFacePick`). Cancel (Escape) leaves
    /// the graph as it was. A region that was not made from a solid with To Implicit has no solid to pick on, and inside a group the pick
    /// would have to be written relative to the group (groups Errata (C2)), so both are said in words.
    func beginFacePick(for id: NodeID) {
        editor.commitPendingEntry()
        editor.closePalette()
        let graph = editor.graph
        guard let node = graph.nodes[id], Self.latticeTypes.contains(node.typeID) else {
            return refusePick("Only a TPMS, Strut Lattice or Voronoi Lattice node maps its cells to a face.")
        }
        guard !editor.isInsideGroup else {
            return refusePick("A face can't be picked inside a group yet. Pick it from the top level.")
        }
        guard let link = graph.incomingLink(to: Endpoint(node: id, socket: "region")),
              let result = editor.result(of: link.from.node), result.state.isSuccess,
              let solid = Self.sourceSolid(of: result.outputs?[link.from.socket]) else {
            return refusePick("Wire a region made from a solid with To Implicit into “\(node.name)” first, then pick the solid's face.")
        }
        pick = PickSession(solid: solid, source: link.from, rule: nil, consumer: nil, picked: [], level: editor.levelPath, lattice: id)
    }

    /// The solid the first implicit in `value` was baked from. Only that one is shown to pick on (the viewport shows one solid), so a face of
    /// a second To Implicit solid in a united region cannot be picked in the app, though `LatticeFaceMapping` accepts it from a file.
    static func sourceSolid(of value: Value?) -> Solid? {
        for case .implicit(let reference) in value?.items ?? [] {
            if let solid = reference.solid?.sourceBlocks.first?.source?.solid { return solid }
        }
        return nil
    }

    /// A click while a face is being picked: a face of the solid shown sets the node's `face` to its remembered pick and its `mapping`
    /// to Face, as one undo step, and ends the pick. Anything else (an edge, empty space, another solid) is ignored.
    func finishFacePick(for lattice: NodeID, _ session: PickSession, _ target: PickTarget?) {
        guard case .face(let index, let face)? = target, viewport.items.indices.contains(index),
              viewport.items[index].solid === session.solid, let picked = session.solid.topology.facePick(for: face) else { return }
        pick = nil
        let commands: [GraphCommand] = [
            .setInput(lattice, NodeSetting.face, .facePick(picked)),
            .setInput(lattice, "mapping", .integer(LatticeMappingKind.face.rawValue)),
        ]
        do {
            try document.perform(.batch(commands), at: editor.graphPath, name: UndoName.mapLatticeToFace)
            editor.selection = [lattice]
        } catch {
            alert = .problem(AppProblem("The lattice wasn't mapped", error.message))
        }
    }
}
