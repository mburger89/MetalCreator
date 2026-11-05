import CreatorGeometry
import CreatorSketch
import CreatorViewport

extension SketchEditorModel {
    /// A Select-tool click: toggles the entity under it in the selection (additive, so two-entity constraints need no
    /// modifier key, though MetalUI's taps report them since C16: docs/metalui-gaps.md S5-a); a click on nothing clears it.
    ///
    /// A plain click on a fit point of a selected spline swaps the spline for the point: Delete then takes only that point (the
    /// spline stays while two remain), and the spline's fit points and knobs stay shown through the selected point
    /// (`handleSplines`). ⇧ keeps the additive selection, so a spline and its point can be selected on purpose.
    func select(at p: Vector2, tolerance: Double, modifiers: ViewportModifiers = []) {
        guard let picked = SketchPicker(sketch: sketch, solution: solution).entity(near: p, tolerance: tolerance) else {
            if !selection.isEmpty { selection = [] }
            return
        }
        if selection.contains(picked) { selection.remove(picked); return }
        if !modifiers.contains(.shift) {
            for spline in selection where sketch.splineParts(of: spline)?.points.contains(picked) == true { selection.remove(spline) }
        }
        selection.insert(picked)
    }

    /// The constraint buttons that fit the selection.
    public var availableConstraints: [SketchConstraintKind] {
        let shape = SelectionShape(selection, in: sketch)
        return SketchConstraintKind.allCases.filter { shape.constraint($0, at: sketch.position(of:)) != nil }
    }

    /// Adds `kind` on the selection as one step, then clears the selection. A selection that doesn't fit says why.
    public func addConstraint(_ kind: SketchConstraintKind) {
        let shape = SelectionShape(selection, in: sketch)
        guard let constraint = shape.constraint(kind, at: sketch.position(of:)) else {
            refusal = kind == .curvature && shape.isLineAndArcJoint(in: sketch)
                ? "A line and an arc can't meet with equal curvature." : kind.hint
            return
        }
        var edited = sketch
        // A joint with a spline makes the handles it constrains active, at the value they have, so the curve starts unchanged.
        edited.activateHandles(for: constraint)
        edited.add(constraint)
        selection = []
        commit(edited, kind.title, named: kind == .curvature ? SketchStepName.addCurvatureConstraint : SketchStepName.addConstraint)
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
        commit(edited, "Delete", named: SketchStepName.delete)
    }
}
