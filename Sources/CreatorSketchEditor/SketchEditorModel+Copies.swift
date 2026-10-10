import CreatorGeometry
import CreatorSketch
import Foundation

/// Mirror and Pattern: copies of the selection, made by a click on what they're made about.
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

    /// A Pattern click: on a point, `options.patternCount` instances of the selection around it (a circular pattern);
    /// on a line, that many along it, from its start toward its end, `options.patternSpacing` apart (a linear one).
    /// Any other curve says what to click; a click on nothing does nothing. The selection stays.
    func pattern(at p: Vector2, tolerance: Double) {
        guard let target = SketchPicker(sketch: sketch, solution: solution).entity(near: p, tolerance: tolerance) else { return }
        let (current, selected, count, spacing) = (sketch, selection.sorted(), options.patternCount, options.patternSpacing)
        switch sketch.entities[target]?.kind {
        case .point?:
            apply { () throws(SketchCommandError) in
                try SketchCommands.circularPattern(current, entities: selected, center: target, count: count)
            }
        case .line(let start, let end)?:
            guard let a = sketch.position(of: start), let b = sketch.position(of: end) else { return }
            apply { () throws(SketchCommandError) in
                try SketchCommands.linearPattern(current, entities: selected, direction: b - a, spacing: spacing, count: count)
            }
        default:
            refusal = "Click a point to pattern around, or a line to pattern along."
        }
    }

    /// The typed instance count: a whole number, 2 or more (the command refuses more than its limit when it runs).
    public func setPatternCount(_ text: String) {
        guard let count = Int(text.trimmingCharacters(in: .whitespaces)), count >= 2 else {
            refusal = "A pattern needs a whole number of instances, 2 or more."
            return
        }
        refusal = nil
        options.patternCount = count
    }

    /// The typed spacing of a linear pattern ("15", "15 mm"): a size more than 0 mm.
    public func setPatternSpacing(_ text: String) {
        guard let value = DimensionText.parse(text), value > 0 else {
            refusal = "A pattern spacing must be a number more than 0 mm."
            return
        }
        refusal = nil
        options.patternSpacing = value
    }
}
