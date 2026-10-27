import CreatorGeometry
import CreatorSketch

extension SketchEditorModel {
    /// A Fillet click: the corner point under `p` is rounded with `options.filletRadius` (`SketchCommands.fillet`).
    /// A click on a curve away from its corners says what to click; a click on nothing does nothing.
    func fillet(at p: Vector2, tolerance: Double) {
        let picker = SketchPicker(sketch: sketch, solution: solution)
        guard let corner = picker.point(near: p, tolerance: tolerance)?.id else {
            if picker.curve(near: p, tolerance: tolerance) != nil { refusal = "Click the corner where two lines meet." }
            return
        }
        let current = sketch
        let radius = options.filletRadius
        apply(SketchStepName.fillet) { () throws(SketchCommandError) in try SketchCommands.fillet(current, corner: corner, radius: radius) }
    }

    /// The typed fillet radius ("2.5", "0.1 in", in the document's unit unless it names one). Not an edit, so not an
    /// undo step; text that isn't a size more than 0 is refused and the field shows the old radius.
    public func setFilletRadius(_ text: String) {
        guard let value = units.parse(text, quantity: .length), value > 0 else {
            refusal = "A fillet radius must be a number more than 0 \(units.length.symbol)."
            return
        }
        refusal = nil
        options.filletRadius = value
    }
}
