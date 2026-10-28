extension Sketch {
    /// A new dimension of `kind` measured on the geometry as solved now: its value, and whether it can drive. It is a reference
    /// when driving it at that value would over-define the sketch: the solve is `.overConstrained` with `.dimension(new)` among the
    /// conflicts (spec §4.4). `nil` when it can't be measured or measures under 1e-9 (a length kind).
    public func measuredDimension(_ kind: DimensionKind) -> (value: Double, isDriving: Bool)? {
        var probe = self
        let id = probe.addDimension(kind, value: 0, isDriving: false)
        guard let value = SketchSolver.solve(probe).measurements[id], value.isFinite else { return nil }
        if case .angle = kind {} else if value < 1e-9 { return nil }
        probe.dimensions[id]?.value = value
        probe.dimensions[id]?.isDriving = true
        guard case .overConstrained(let conflicts) = SketchSolver.solve(probe).status else { return (value, true) }
        return (value, !conflicts.contains(.dimension(id)))
    }
}
