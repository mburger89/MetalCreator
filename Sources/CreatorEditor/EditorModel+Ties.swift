import CreatorGeometry
import CreatorGraph

/// Tying wires (cable ties spec 2026-10-26 §4.2, §4.4).
extension EditorModel {
    /// What ⌘⇧T says when there is nothing it can do (spec §4.2's "anything else"; no node to shake).
    static let tieRefusal = "Select two or more wires to tie, or one tie and the wires to add to it."

    /// ⌘⇧T. With no tie selected and two or more wires, it ties the wires where they were picked and selects the new tie
    /// alone ("Tie Wires"). With exactly one tie selected and one or more wires it doesn't hold yet, it adds them to the
    /// tie and selects the tie ("Add to Tie"). Anything else is refused. Selected wires and ties that are gone (undone)
    /// count for nothing.
    public func tieSelectedWires() {
        let wires = canvasSelection.wires.filter { graph.incomingLink(to: $0) != nil }
        let ties = canvasSelection.ties.compactMap { graph.ties[$0] }
        if ties.isEmpty, wires.count >= CableTie.minimumWires {
            commit(CableTie(position: tiePosition(of: wires), wires: wires), named: UndoName.tieWires)
        } else if ties.count == 1, var tie = ties.first, !wires.isEmpty, !wires.isSubset(of: tie.wires) {
            tie.wires.formUnion(wires)
            commit(tie, named: UndoName.addToTie)
        } else {
            refuse(Self.tieRefusal, node: nil)
        }
    }

    /// Where a new tie goes (cable ties plan ruling R10): the centre of the points its wires were picked at, by a click or an
    /// ⌥-box, in stored coordinates. A wire with no such point counts its route's middle.
    func tiePosition(of wires: Set<Endpoint>) -> Vector2 {
        let routing = wireRouting
        let points = wires.sorted().compactMap { wire in
            wirePickPoints[wire] ?? routing.routes[wire].map { flow.stored($0.middle) }
        }
        guard !points.isEmpty else { return .zero }
        return points.reduce(Vector2.zero, +) * (1 / Double(points.count))
    }

    /// Sets `tie` as one undo step called `name`, then selects it alone.
    private func commit(_ tie: CableTie, named name: String) {
        do {
            try edit(.setTie(tie), name: name)
            canvasSelection = CanvasSelection(ties: [tie.id])
        } catch {
            refuse(error.message, node: nil)
        }
    }
}
