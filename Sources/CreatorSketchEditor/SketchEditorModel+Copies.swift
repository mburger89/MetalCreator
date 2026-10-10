import CreatorGeometry
import CreatorSketch

/// Mirror: copies of the selection, made by a click on what they're made about.
extension SketchEditorModel {
    /// A Mirror click: the selection is copied mirrored about the line under `p` (`SketchCommands.mirror`, which leaves
    /// the line itself out of what it copies and says what's missing: a selection, or a line). The selection stays, so
    /// it can be mirrored again about another line. A click on nothing does nothing.
    func mirror(at p: Vector2, tolerance: Double) {
        guard let axis = SketchPicker(sketch: sketch, solution: solution).curve(near: p, tolerance: tolerance) else { return }
        let current = sketch
        let selected = selection.sorted()
        apply { () throws(SketchCommandError) in try SketchCommands.mirror(current, entities: selected, about: axis) }
    }
}
