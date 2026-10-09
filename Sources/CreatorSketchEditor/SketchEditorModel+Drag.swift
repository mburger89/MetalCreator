import CreatorGeometry
import CreatorSketch

extension SketchEditorModel {
    /// Begins dragging the point under `p`, if there is one and no stroke is in progress (sketcher spec §8). True when
    /// the drag is the editor's.
    func beginDrag(at p: Vector2, tolerance: Double) -> Bool {
        guard drawState == .idle,
              let hit = SketchPicker(sketch: sketch, solution: solution).point(near: p, tolerance: tolerance) else { return false }
        dragged = hit.id
        dragOrigin = sketch
        preview = .none
        return true
    }

    /// One drag step: the sketch re-solves with the point pulled toward `p` as a soft target (spec §4's drag mode),
    /// and remembers the result so the next step warm-starts from it. Nothing is committed until the release.
    func drag(to p: Vector2) {
        guard let dragged else { return }
        let pulled = SketchSolver.solve(sketch, dragging: [dragged: p])
        solution = pulled
        sketch = Self.remembering(sketch, pulled)
    }

    /// The release (at `p`, or off the plane): the dragged sketch is one undo step ("Move Point"), and downstream
    /// evaluation runs once. A drag that moved nothing (a fixed point, or a sketch whose constraints conflict, so no
    /// drag step was usable) records no step.
    func endDrag(at p: Vector2?) {
        guard dragged != nil else { return }
        if let p { drag(to: p) }
        let origin = dragOrigin
        dragged = nil
        dragOrigin = nil
        if sketch == origin {
            solution = SketchSolver.solve(sketch)
        } else {
            commit(sketch, "Move Point")
        }
    }
}
