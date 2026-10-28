extension Sketch {
    /// A new dimension of `kind` measured on the geometry as solved now: its value, and whether it can drive. It is a reference
    /// when driving it at that value would over-define the sketch: the solve is `.overConstrained` with `.dimension(new)` among the
    /// conflicts (spec §4.4). `nil` when it can't be measured or measures under 1e-9 (a length kind), or
    /// when any of its entities is a suspended projection (a suspended edge has no geometry to measure).
    public func measuredDimension(_ kind: DimensionKind) -> (value: Double, isDriving: Bool)? {
        let touchesSuspended = kind.entities.contains { id in
            if case .projected(let source)? = entities[id]?.kind { source.isSuspended } else { false }
        }
        guard !touchesSuspended else { return nil }
        var probe = self
        // An angle is created with the value the lines make as drawn, so it takes the sense that reads that
        // value (a 120° vee measures 120, not 60); other kinds are measured from the reference solve.
        let id = probe.addDimension(kind, value: drawnAngle(kind) ?? 0, isDriving: false)
        guard let value = SketchSolver.solve(probe).measurements[id], value.isFinite else { return nil }
        if case .angle = kind {} else if value < 1e-9 { return nil }
        probe.dimensions[id]?.value = value
        probe.dimensions[id]?.isDriving = true
        guard case .overConstrained(let conflicts) = SketchSolver.solve(probe).status else { return (value, true) }
        return (value, !conflicts.contains(.dimension(id)))
    }

    /// The angle in degrees (0...180) from the first line to the second as drawn now; `nil` for other kinds or a missing
    /// or zero-length line.
    private func drawnAngle(_ kind: DimensionKind) -> Double? {
        guard case .angle(let a, let b) = kind,
              let first = lineDirection(a, position: { position(of: $0) }),
              let second = lineDirection(b, position: { position(of: $0) }),
              first.length > 0, second.length > 0 else { return nil }
        return abs(AngleSense.signedAngle(from: first, to: second)) * 180 / .pi
    }
}
