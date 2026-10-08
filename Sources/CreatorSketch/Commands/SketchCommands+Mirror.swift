import CreatorGeometry

extension SketchCommands {
    /// Copies the selection reflected in `axis` (spec §3), holding each copied point symmetric to
    /// its original about the axis. Points on the axis are shared, not copied, and held on it
    /// with a point-on constraint (unless something already holds them there), so the copy stays
    /// symmetric when they move. Mirrored circles also get an equal-radius constraint; arcs are
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
        for (original, mirrored) in copy.points.sorted(by: { $0.key < $1.key }) {
            if original != mirrored {
                edited.add(.symmetric(original, mirrored, about: axis))
            } else if !isHeld(original, on: axis, in: edited) {
                // A shared point is its own mirror image only while it stays on the axis.
                edited.add(.pointOn(point: original, curve: axis))
            }
        }
        for pair in copy.curves {
            if case .circle = edited.entities[pair.copy]?.kind { edited.add(.equal(pair.original, pair.copy)) }
        }
        return try edit(from: sketch, to: edited, description: "Mirror \(count(selection.count))")
    }

    /// True when `point` is already held on the line `axis`: one of its endpoints, or under a
    /// point-on or midpoint constraint on it.
    static func isHeld(_ point: SketchEntityID, on axis: SketchEntityID, in sketch: Sketch) -> Bool {
        if case .line(let start, let end)? = sketch.entities[axis]?.kind, point == start || point == end { return true }
        return sketch.constraints.values.contains { constraint in
            switch constraint {
            case .pointOn(let p, let curve): p == point && curve == axis
            case .midpoint(let p, let line): p == point && line == axis
            default: false
            }
        }
    }
}
