import CreatorGeometry

extension SketchCommands {
    /// Copies the selection reflected in `axis` (spec §3), holding each copied point symmetric to
    /// its original about the axis. Points on the axis are shared, not copied, and held on it
    /// with a point-on constraint unless the sketch already holds them there
    /// (`SketchSolver.isImplied`), so the copy stays symmetric when they move. Mirrored circles also get an equal-radius constraint; arcs are
    /// fully held by their three symmetric points.
    public static func mirror(_ sketch: Sketch, entities ids: [SketchEntityID], about axis: SketchEntityID) throws(SketchCommandError) -> SketchEdit {
        guard case .line(let a, let b)? = sketch.shape(of: axis) else {
            throw SketchCommandError("Mirror needs a line to mirror about.")
        }
        let selection = try selection(ids.filter { $0 != axis }, in: sketch, verb: "mirror")
        var edited = sketch
        let copy = copy(selection, in: &edited, reversesArcs: true, stays: { position in
            guard let unit = SketchMath.normalized(b - a) else { return false }
            return abs(SketchMath.cross(unit, position - a)) <= CurveIntersection.tolerance
        }, transform: { SketchMath.reflected($0, inLineThrough: a, b) })
        let pairs = copy.points.sorted { $0.key < $1.key }
        for (original, mirrored) in pairs where original != mirrored {
            edited.add(.symmetric(original, mirrored, about: axis))
        }
        for pair in copy.curves {
            if case .circle = edited.entities[pair.copy]?.kind { edited.add(.equal(pair.original, pair.copy)) }
        }
        // A shared point is its own mirror image only while it stays on the axis. Hold it there
        // unless the sketch already does (an axis end, a point-on, a fix with a fixed axis, ...):
        // a dependent point-on would make the sketch over-constrained.
        for (original, mirrored) in pairs where original == mirrored {
            let onAxis = SketchConstraint.pointOn(point: original, curve: axis)
            if !SketchSolver.isImplied(onAxis, in: edited) { edited.add(onAxis) }
        }
        return try edit(from: sketch, to: edited, description: "Mirror \(count(selection.count))")
    }
}
