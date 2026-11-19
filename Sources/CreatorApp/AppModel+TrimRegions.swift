import CreatorEditor
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport

extension AppModel {
    /// "Pick regions in view…" on a Trim Surface (NS-4, R4): the viewport shows the node's `pieces` sheet alone, starting from the
    /// pieces its picks keep now (their faces selected). A click on a face toggles the whole piece holding it; Done writes one pick per
    /// kept piece. Refused inside a group (a pick there would have to be stored relative to the group) and with no pieces yet.
    public func beginTrimRegionPick(for id: NodeID) {
        guard controlNet == nil else { return }
        editor.commitPendingEntry()
        editor.closePalette()
        let graph = editor.graph
        guard let node = graph.nodes[id], node.typeID == TrimSurfaceNode.typeID else {
            return refusePick("Only a Trim Surface node keeps picked regions.")
        }
        guard !editor.isInsideGroup else {
            return refusePick("A region can't be picked inside a group yet. Pick it from the top level.")
        }
        let source = Endpoint(node: id, socket: "pieces")
        guard let whole = solid(at: source) ?? recoveredSolid(at: source) else {
            if case .error(let reason)? = editor.result(of: id)?.state { return refusePick(reason) }
            return refusePick("“\(node.name)” has no pieces to pick yet: wire a sheet and a cutter first.")
        }
        let pieces = TrimRegions.pieces(of: whole)
        guard !pieces.isEmpty else {
            return refusePick("“\(node.name)” has no pieces to pick yet: wire a sheet and a cutter first.")
        }
        let picks = node.inputValues[NodeSetting.keepRegions]?.regionPicks ?? []
        let kept = TrimRegions.resolve(picks, pieces: pieces, in: whole.topology).pieces
        pick = PickSession(solid: whole, source: source, rule: nil, consumer: nil, picked: [], level: editor.levelPath,
                           trimRegions: id, pickedPieces: kept, pieces: pieces)
    }

    /// A click while regions are picked: a face of the sheet shown toggles its piece. An edge or empty space does nothing.
    func toggleTrimRegion(_ session: PickSession, _ target: PickTarget?) {
        guard case .face(let index, let face)? = target, viewport.items.indices.contains(index),
              viewport.items[index].solid === session.solid else { return }
        var session = session
        session.togglePiece(holding: face)
        pick = session
    }

    /// Done: one `TrimRegions.pick(forPiece:)` per kept piece, in piece order, as one step "Pick Trim Regions".
    func finishTrimRegionPick(_ trim: NodeID, _ session: PickSession) {
        let picks = session.pickedPieces.sorted().compactMap {
            TrimRegions.pick(forPiece: $0, pieces: session.pieces, in: session.solid.topology)
        }
        do {
            try document.perform(.setInput(trim, NodeSetting.keepRegions, .regionPicks(picks)), at: editor.graphPath,
                                 name: UndoName.pickTrimRegions)
            editor.selection = [trim]
        } catch {
            alert = .problem(AppProblem("The regions couldn't be saved", error.message))
        }
    }

    /// "Clear regions": the node keeps every piece again, as one undo step.
    public func clearTrimRegions(of id: NodeID) {
        editor.commitPendingEntry()
        guard let picks = editor.graph.nodes[id]?.inputValues[NodeSetting.keepRegions]?.regionPicks, !picks.isEmpty else { return }
        do {
            try document.perform(.setInput(id, NodeSetting.keepRegions, .regionPicks([])), at: editor.graphPath,
                                 name: UndoName.clearTrimRegions)
        } catch {
            alert = .problem(AppProblem("The regions weren't cleared", error.message))
        }
    }
}
