import CreatorEditor
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport

extension AppModel {
    /// A Loft's face buttons: pick or clear the start or end face.
    func handleLoftEnd(_ request: InspectorRequest) {
        switch request.action {
        case .pickLoftStartFace: beginLoftFacePick(for: request.node, start: true)
        case .pickLoftEndFace: beginLoftFacePick(for: request.node, start: false)
        case .clearLoftStartFace: clearLoftFace(of: request.node, start: true)
        case .clearLoftEndFace: clearLoftFace(of: request.node, start: false)
        default: break
        }
    }

    /// "Pick Start Face in View…" / "Pick End Face in View…" on a Loft: the viewport shows the part wired into the loft's `solid`, and a
    /// click on one of its faces sets the end's face (`finishLoftFacePick`). Cancel (Escape) leaves the graph as it was. Inside a group
    /// the pick would have to be written relative to the group, so it is refused in words, as the lattice's is.
    func beginLoftFacePick(for id: NodeID, start: Bool) {
        editor.commitPendingEntry()
        editor.closePalette()
        let graph = editor.graph
        guard let node = graph.nodes[id], node.typeID == LoftNode.typeID else {
            return refusePick("Only a Loft node takes its ends from a face.")
        }
        guard !editor.isInsideGroup else {
            return refusePick("A face can't be picked inside a group yet. Pick it from the top level.")
        }
        guard let link = graph.incomingLink(to: Endpoint(node: id, socket: "solid")), let solid = solid(at: link.from) else {
            return refusePick("Wire the part whose face the loft starts from into “\(node.name)” first, then pick its face.")
        }
        pick = PickSession(solid: solid, source: link.from, rule: nil, consumer: nil, picked: [], level: editor.levelPath,
                           loftEnd: PickSession.LoftEndTarget(loft: id, isStart: start))
    }

    /// A click while a loft end's face is being picked: a face of the solid shown becomes the end's face, as one undo step, and ends the
    /// pick. Anything else (an edge, empty space, another solid) is ignored.
    func finishLoftFacePick(_ end: PickSession.LoftEndTarget, _ session: PickSession, _ target: PickTarget?) {
        guard case .face(let index, let face)? = target, viewport.items.indices.contains(index),
              viewport.items[index].solid === session.solid, let picked = session.solid.topology.facePick(for: face) else { return }
        pick = nil
        let setting = end.isStart ? NodeSetting.startFace : NodeSetting.endFace
        do {
            try document.perform(.setInput(end.loft, setting, .facePick(picked)), at: editor.graphPath, name: UndoName.pickLoftFace)
            editor.selection = [end.loft]
        } catch {
            alert = .problem(AppProblem("The face wasn't picked", error.message))
        }
    }

    /// "Clear Start Face" / "Clear End Face": the end goes back to a plain section, as one undo step.
    func clearLoftFace(of id: NodeID, start: Bool) {
        editor.commitPendingEntry()
        let setting = start ? NodeSetting.startFace : NodeSetting.endFace
        guard editor.graph.nodes[id]?.inputValues[setting] != nil else { return }
        do {
            try document.perform(.setInput(id, setting, nil), at: editor.graphPath, name: UndoName.clearLoftFace)
        } catch {
            alert = .problem(AppProblem("The face wasn't cleared", error.message))
        }
    }
}
