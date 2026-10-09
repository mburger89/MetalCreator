import CreatorGeometry
import CreatorSketch
import CreatorViewport

extension SketchEditorModel {
    /// A Select-tool click: toggles the entity under it in the selection (additive, so two-entity constraints need no
    /// modifier key, which MetalUI's taps don't report yet: docs/metalui-gaps.md S5-a); a click on nothing clears it.
    func select(at p: Vector2, tolerance: Double) {
        guard let picked = SketchPicker(sketch: sketch, solution: solution).entity(near: p, tolerance: tolerance) else {
            if !selection.isEmpty { selection = [] }
            return
        }
        if selection.contains(picked) { selection.remove(picked) } else { selection.insert(picked) }
    }

    /// The constraint buttons that fit the selection.
    public var availableConstraints: [SketchConstraintKind] {
        let shape = SelectionShape(selection, in: sketch)
        return SketchConstraintKind.allCases.filter { shape.constraint($0, at: sketch.position(of:)) != nil }
    }

    /// Adds `kind` on the selection as one step, then clears the selection. A selection that doesn't fit says why.
    public func addConstraint(_ kind: SketchConstraintKind) {
        guard let constraint = SelectionShape(selection, in: sketch).constraint(kind, at: sketch.position(of:)) else {
            refusal = kind.hint
            return
        }
        var edited = sketch
        edited.add(constraint)
        selection = []
        commit(edited, kind.title)
    }

    /// Delete: removes the selected entities with everything built on them and every constraint and dimension on
    /// them, and points left on their own. Refused when it would remove an exposed dimension (its input would vanish
    /// from the node with its wire: S1–S2 handoff).
    public func deleteSelection() {
        guard !selection.isEmpty else { return }
        var edited = sketch
        for id in selection.sorted() { edited.removeEntity(id) }
        // Every entity that went, including curves cascaded away with a selected point, frees its points.
        let freed = sketch.entities.filter { edited.entities[$0.key] == nil }.flatMap { $0.value.kind.referencedPoints }
        edited.removeOrphanPoints(freed.filter { edited.entities[$0] != nil })
        let exposed = sketch.dimensionIDs.compactMap { id -> String? in
            guard let dimension = sketch.dimensions[id], dimension.isExposed, edited.dimensions[id] == nil else { return nil }
            return dimension.name
        }
        if let name = exposed.first {
            refusal = "That would remove \(name), which is exposed as an input. Stop exposing it first."
            return
        }
        selection = []
        hovered = nil
        commit(edited, "Delete")
    }
}
