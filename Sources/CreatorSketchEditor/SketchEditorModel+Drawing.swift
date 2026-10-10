import CreatorGeometry
import CreatorSketch
import CreatorViewport

extension SketchEditorModel {
    /// Points within this many points of the pointer are picked and snapped to (sketcher spec §8: "a few pixels").
    public static let pickRadius = 8.0

    /// Picks a tool (the toolbar, or its key). What the old one had in progress is dropped.
    public func choose(_ newTool: SketchTool) {
        tool = newTool
        drawState = .idle
        dimensionPick = nil
        preview = .none
        refusal = nil
    }

    /// A toolbar button or its key: picks `tool`, except that Arc's (A) on the centre arc switches to the 3-point arc,
    /// and back (sketcher spec §8: "Arc (centre / 3-point) | A").
    public func press(_ tool: SketchTool) {
        guard tool == .arc else { return choose(tool) }
        choose(self.tool == .arc ? .arcThreePoint : .arc)
    }

    /// X (sketcher spec §8): with a selection, turns it into construction geometry, or back when it all is already;
    /// with none, toggles whether new geometry is construction.
    public func toggleConstruction() {
        guard !selection.isEmpty else {
            isConstruction.toggle()
            return
        }
        let makeConstruction = selection.contains { sketch.entities[$0]?.isConstruction == false }
        var edited = sketch
        for id in selection.sorted() { edited.entities[id]?.isConstruction = makeConstruction }
        commit(edited, makeConstruction ? "Make Construction" : "Make Normal Geometry")
    }

    /// Esc: closes the host's popup if one is open (`SketchEditorEvents.dismissHostPopup`); else ends the stroke in
    /// progress; with none, clears the selection; with nothing selected, finishes the sketch.
    public func escape() {
        if events.dismissHostPopup() { return }
        if drawState != .idle || dimensionPick != nil {
            drawState = .idle
            dimensionPick = nil
            preview = .none
        } else if !selection.isEmpty {
            selection = []
        } else {
            finish()
        }
    }

    /// ⏎ or the Finish button: leaves sketch mode (the host does), dropping any stroke in progress and any point drag
    /// (its uncommitted steps undone, so an editor used again shows no stale chip and its release commits nothing);
    /// with the host's popup open, it only closes that.
    public func finish() {
        if events.dismissHostPopup() { return }
        drawState = .idle
        preview = .none
        if dragged != nil, let origin = dragOrigin {
            let solved = SketchSolver.solve(origin)
            solution = solved
            sketch = Self.remembering(origin, solved)
        }
        dragged = nil
        dragOrigin = nil
        events.finished()
    }

    /// A click at `p` (plane coordinates) with `tolerance` mm of slack, for the active tool. ⌘ suppresses inference
    /// (sketcher spec §8).
    func click(at p: Vector2, tolerance: Double, modifiers: ViewportModifiers) {
        refusal = nil
        switch tool {
        case .select: select(at: p, tolerance: tolerance)
        case .dimension: dimension(at: p, tolerance: tolerance)
        case .point: placePoint(at: p, tolerance: tolerance)
        case .line: placeLinePoint(at: p, tolerance: tolerance, suppressed: modifiers.contains(.command))
        case .circle: placeCirclePoint(at: p, tolerance: tolerance)
        case .arc: placeArcPoint(at: p, tolerance: tolerance)
        case .arcThreePoint: placeThreePointArcPoint(at: p, tolerance: tolerance)
        case .trim, .extend, .fillet, .mirror, .pattern: modify(at: p, tolerance: tolerance)
        }
        hover(at: p, tolerance: tolerance, modifiers: modifiers)
    }

    /// The pointer moved to `p` (`nil`: off the view, or off the plane): the hovered entity and the rubber band follow.
    func hover(at p: Vector2?, tolerance: Double, modifiers: ViewportModifiers) {
        guard let p else {
            hovered = nil
            preview = .none
            return
        }
        let picker = SketchPicker(sketch: sketch, solution: solution)
        let under = tool.picksCurves ? picker.curve(near: p, tolerance: tolerance) : picker.entity(near: p, tolerance: tolerance)
        if hovered != under { hovered = under }
        let next = rubberBand(to: p, tolerance: tolerance, suppressed: modifiers.contains(.command))
        if preview != next { preview = next }
    }

    /// Where a click at `p` lands: the nearest existing point within `tolerance`, else `p` itself.
    func anchor(at p: Vector2, tolerance: Double) -> SketchAnchor {
        let picker = SketchPicker(sketch: sketch, solution: solution)
        guard let hit = picker.point(near: p, tolerance: tolerance) else { return .free(p) }
        return .existing(hit.id, at: hit.at)
    }

    private func placePoint(at p: Vector2, tolerance: Double) {
        guard case .free(let at) = anchor(at: p, tolerance: tolerance) else { return }
        var edited = sketch
        edited.addPoint(at, isConstruction: isConstruction)
        commit(edited, "Point")
    }

    /// The first click starts a chain; each later one ends a line there and starts the next from its end.
    private func placeLinePoint(at p: Vector2, tolerance: Double, suppressed: Bool) {
        guard case .lineFrom(let start) = drawState else {
            drawState = .lineFrom(anchor(at: p, tolerance: tolerance))
            return
        }
        var end = anchor(at: p, tolerance: tolerance)
        if end.point != nil, end.point == start.point { return }
        var inference: LineInference?
        if case .free(let at) = end {
            let inferred = LineInference.infer(from: start.position, to: at, tolerance: tolerance, suppressed: suppressed)
            inference = inferred.0
            end = .free(inferred.1)
        }
        guard (end.position - start.position).length > 1e-9 else { return }
        var edited = sketch
        let a = start.point(in: &edited)
        let b = end.point(in: &edited)
        let line = edited.addLine(from: a, to: b, isConstruction: isConstruction)
        if let inference { edited.add(inference.constraint(on: line)) }
        commit(edited, "Line")
        drawState = .lineFrom(.existing(b, at: end.position))
    }

    private func placeCirclePoint(at p: Vector2, tolerance: Double) {
        guard case .circleAround(let center) = drawState else {
            drawState = .circleAround(anchor(at: p, tolerance: tolerance))
            return
        }
        let radius = (anchor(at: p, tolerance: tolerance).position - center.position).length
        guard radius > 1e-9 else { return }
        var edited = sketch
        edited.addCircle(center: center.point(in: &edited), radius: radius, isConstruction: isConstruction)
        commit(edited, "Circle")
        drawState = .idle
    }

    /// Centre, start, then end: the end lands on the start's radius, along the ray through the click.
    private func placeArcPoint(at p: Vector2, tolerance: Double) {
        switch drawState {
        case .arcAround(let center):
            let start = anchor(at: p, tolerance: tolerance)
            guard (start.position - center.position).length > 1e-9 else { return }
            drawState = .arcFrom(center: center, start: start)
        case .arcFrom(let center, let start):
            let end = arcEnd(center: center.position, start: start.position, toward: anchor(at: p, tolerance: tolerance))
            guard let end, end.point == nil || end.point != start.point else { return }
            var edited = sketch
            let c = center.point(in: &edited)
            let s = start.point(in: &edited)
            let e = end.point(in: &edited)
            edited.addArc(center: c, start: s, end: e, isConstruction: isConstruction)
            commit(edited, "Arc")
            drawState = .idle
        default:
            drawState = .arcAround(anchor(at: p, tolerance: tolerance))
        }
    }

    /// Start, end, then a point the arc passes through: the arc runs on the circle through the three, from the start to
    /// the end the way that passes the third (counter-clockwise from whichever end makes it so), around a new centre
    /// point. A third click in line with the other two draws nothing and waits for another.
    private func placeThreePointArcPoint(at p: Vector2, tolerance: Double) {
        switch drawState {
        case .arcThroughFrom(let start):
            let end = anchor(at: p, tolerance: tolerance)
            guard (end.position - start.position).length > 1e-9, end.point == nil || end.point != start.point else { return }
            drawState = .arcThrough(start: start, end: end)
        case .arcThrough(let start, let end):
            guard let arc = EditorGeometry.threePointArc(from: start.position, to: end.position, through: p) else { return }
            var edited = sketch
            let s = start.point(in: &edited)
            let e = end.point(in: &edited)
            let c = edited.addPoint(arc.center)
            edited.addArc(center: c, start: arc.isCounterClockwise ? s : e, end: arc.isCounterClockwise ? e : s,
                          isConstruction: isConstruction)
            commit(edited, "Arc")
            drawState = .idle
        default:
            drawState = .arcThroughFrom(anchor(at: p, tolerance: tolerance))
        }
    }

    /// An arc's end: an existing point as it is, else the click moved onto the start's radius; `nil` on the centre.
    private func arcEnd(center: Vector2, start: Vector2, toward target: SketchAnchor) -> SketchAnchor? {
        if target.point != nil { return target }
        let ray = target.position - center
        let length = ray.length
        guard length > 1e-9 else { return nil }
        return .free(center + ray * ((start - center).length / length))
    }

    /// The rubber band from what's placed to `p`.
    private func rubberBand(to p: Vector2, tolerance: Double, suppressed: Bool) -> SketchPreview {
        let target = anchor(at: p, tolerance: tolerance)
        switch drawState {
        case .idle:
            return tool.placesPoints ? SketchPreview(points: [target.position]) : .none
        case .lineFrom(let start):
            var end = target.position
            if target.point == nil {
                end = LineInference.infer(from: start.position, to: end, tolerance: tolerance, suppressed: suppressed).1
            }
            return SketchPreview(curves: [.line(start.position, end)], points: [start.position, end])
        case .circleAround(let center):
            return SketchPreview(curves: [.circle(center: center.position, radius: (target.position - center.position).length)],
                                 points: [center.position])
        case .arcAround(let center):
            return SketchPreview(curves: [.line(center.position, target.position)], points: [center.position])
        case .arcFrom(let center, let start):
            guard let end = arcEnd(center: center.position, start: start.position, toward: target) else {
                return SketchPreview(points: [center.position, start.position])
            }
            return SketchPreview(curves: [.arc(center: center.position, start: start.position, end: end.position)],
                                 points: [center.position, start.position, end.position])
        case .arcThroughFrom(let start):
            return SketchPreview(curves: [.line(start.position, target.position)], points: [start.position])
        case .arcThrough(let start, let end):
            guard let arc = EditorGeometry.threePointArc(from: start.position, to: end.position, through: p) else {
                return SketchPreview(curves: [.line(start.position, end.position)], points: [start.position, end.position])
            }
            let (from, to) = arc.isCounterClockwise ? (start.position, end.position) : (end.position, start.position)
            return SketchPreview(curves: [.arc(center: arc.center, start: from, end: to)], points: [start.position, end.position])
        }
    }
}
