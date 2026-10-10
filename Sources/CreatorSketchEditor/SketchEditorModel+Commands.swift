import CreatorGeometry
import CreatorSketch

/// The tools that change what's drawn through `SketchCommands` (sketcher spec §3, §8). Each command is one step; a
/// command that can't be applied says why in `refusal` (its `SketchCommandError.message`) and changes nothing.
extension SketchEditorModel {
    /// A click with a command tool, at `p` with `tolerance` mm of slack.
    func modify(at p: Vector2, tolerance: Double) {
        switch tool {
        case .trim, .extend: trimOrExtend(at: p, tolerance: tolerance)
        case .fillet: fillet(at: p, tolerance: tolerance)
        case .mirror: mirror(at: p, tolerance: tolerance)
        case .pattern: pattern(at: p, tolerance: tolerance)
        case .select, .line, .arc, .arcThreePoint, .circle, .point, .dimension: break   // not commands: `click` routes them
        }
    }

    /// A Trim or Extend click: the curve under `p` is trimmed around `p`, or extended at the end nearer `p`. A click
    /// on no curve does nothing.
    func trimOrExtend(at p: Vector2, tolerance: Double) {
        guard let curve = SketchPicker(sketch: sketch, solution: solution).curve(near: p, tolerance: tolerance) else { return }
        let current = sketch
        if tool == .trim {
            apply { () throws(SketchCommandError) in try SketchCommands.trim(current, curve: curve, near: p) }
        } else {
            apply { () throws(SketchCommandError) in try SketchCommands.extend(current, curve: curve, near: p) }
        }
    }

    /// Commits a command's edit as one step (the selection keeps what's left of it), or shows why it was refused.
    func apply(_ command: () throws(SketchCommandError) -> SketchEdit) {
        do {
            let edit = try command()
            selection = selection.filter { edit.sketch.entities[$0] != nil }
            hovered = nil
            commit(edit.sketch, edit.description)
        } catch {
            refusal = error.message
        }
    }
}
