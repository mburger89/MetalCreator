import CreatorGeometry

extension SketchCommands {
    /// Copies the selection reflected in `axis` (spec §3), holding each copied point symmetric to
    /// its original about the axis. Points on the axis are shared, not copied. Mirrored circles
    /// also get an equal-radius constraint; arcs are fully held by their three symmetric points.
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
        for (original, mirrored) in copy.points.sorted(by: { $0.key < $1.key }) where original != mirrored {
            edited.add(.symmetric(original, mirrored, about: axis))
        }
        for pair in copy.curves {
            if case .circle = edited.entities[pair.copy]?.kind { edited.add(.equal(pair.original, pair.copy)) }
        }
        return SketchEdit(sketch: edited, description: "Mirror \(count(selection.count))")
    }
}
