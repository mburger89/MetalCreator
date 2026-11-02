import CreatorGeometry

/// Which of a fit point's two handles.
public enum SplineHandleKind: Int, Hashable, Sendable, Comparable {
    case tangent = 0
    case curvature = 1

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension Sketch {
    /// A spline's fit points and handle flags, or `nil` for any other entity.
    public func splineParts(of id: SketchEntityID) -> (points: [SketchEntityID], handles: [SplineHandleState])? {
        guard case .spline(let points, let handles)? = entities[id]?.kind else { return nil }
        return (points, handles)
    }

    /// The handle values the last solve (or the editor) stored for a spline, padded to its fit points: a value where the
    /// handle is active and one is stored, `nil` otherwise. Stored values of an inactive handle are ignored.
    func storedSplineHandles(of id: SketchEntityID) -> [SplineHandle] {
        guard let (points, states) = splineParts(of: id) else { return [] }
        var stored: [SplineHandle] = []
        if case .splineHandles(let values)? = solved[id] { stored = values }
        return points.indices.map { index in
            let value = index < stored.count ? stored[index] : .automatic
            let state = index < states.count ? states[index] : .automatic
            return SplineHandle(tangent: state.tangent ? value.tangent : nil, curvature: state.curvature ? value.curvature : nil)
        }
    }

    /// The spline as geometry: the fit points at their current positions and the active handles at their stored values.
    /// `nil` for another entity, a missing point or fewer than two fit points. Pure in the stored data, so a saved and
    /// reopened sketch gives the same curve.
    public func splineDefinition(of id: SketchEntityID) -> SplineDefinition? {
        guard let (points, _) = splineParts(of: id), points.count >= 2 else { return nil }
        let positions = points.compactMap { position(of: $0) }
        guard positions.count == points.count else { return nil }
        return SplineDefinition(points: positions, handles: storedSplineHandles(of: id))
    }

    /// Makes a handle active at its current (automatic or stored) value, so the curve does not change. Does nothing for a
    /// handle that is already active or an index out of range.
    public mutating func activateSplineHandle(_ id: SketchEntityID, at index: Int, _ kind: SplineHandleKind) {
        guard case .spline(let points, var states)? = entities[id]?.kind, points.indices.contains(index),
              let definition = splineDefinition(of: id) else { return }
        while states.count < points.count { states.append(.automatic) }
        let resolved = definition.resolvedHandles()[index]
        var values = storedSplineHandles(of: id)
        switch kind {
        case .tangent:
            guard !states[index].tangent else { return }
            states[index].tangent = true
            values[index].tangent = resolved.tangent
        case .curvature:
            guard !states[index].curvature else { return }
            states[index].curvature = true
            values[index].curvature = resolved.secondDerivative
        }
        entities[id]?.kind = .spline(points: points, handles: states)
        solved[id] = .splineHandles(values)
    }

    /// Makes a handle automatic again, forgetting its value. Refused (returns false) while a constraint uses it, so a
    /// constrained joint can't silently lose its handle.
    @discardableResult
    public mutating func releaseSplineHandle(_ id: SketchEntityID, at index: Int, _ kind: SplineHandleKind) -> Bool {
        guard case .spline(let points, var states)? = entities[id]?.kind, points.indices.contains(index),
              index < states.count else { return false }
        if isSplineHandleConstrained(id, at: index, kind) { return false }
        var values = storedSplineHandles(of: id)
        switch kind {
        case .tangent:
            states[index].tangent = false
            values[index].tangent = nil
        case .curvature:
            states[index].curvature = false
            values[index].curvature = nil
        }
        entities[id]?.kind = .spline(points: points, handles: states)
        solved[id] = .splineHandles(values)
        return true
    }

    /// True when a tangent or curvature constraint of this spline reaches the fit point's handle: a Tangent uses the
    /// tangent handle and a Curvature both, at an end the spline shares with the other curve.
    public func isSplineHandleConstrained(_ id: SketchEntityID, at index: Int, _ kind: SplineHandleKind) -> Bool {
        guard let (points, _) = splineParts(of: id), points.indices.contains(index) else { return false }
        let isEnd = index == 0 || index == points.count - 1
        guard isEnd else { return false }
        for constraintID in constraintIDs {
            switch constraints[constraintID] {
            case .tangent(let a, let b)?:
                if kind == .tangent, a == id || b == id, sharesEnd(id, with: a == id ? b : a, at: index) { return true }
            case .curvature(let a, let b)?:
                if a == id || b == id, sharesEnd(id, with: a == id ? b : a, at: index) { return true }
            default:
                continue
            }
        }
        return false
    }

    /// The point entities a curve ends at: a line's, an arc's and a spline's first and last fit point.
    func curveEnds(of id: SketchEntityID) -> [SketchEntityID] {
        switch entities[id]?.kind {
        case .line(let start, let end): [start, end]
        case .arc(_, let start, let end): [start, end]
        case .spline(let points, _): points.count >= 2 ? [points[0], points[points.count - 1]] : []
        default: []
        }
    }

    private func sharesEnd(_ spline: SketchEntityID, with other: SketchEntityID, at index: Int) -> Bool {
        guard let (points, _) = splineParts(of: spline) else { return false }
        return curveEnds(of: other).contains(points[index])
    }
}

extension Sketch {
    /// An active handle's current value: the stored one, else what the automatic solve gives there. `nil` for a missing spline
    /// or index.
    func splineHandleValue(_ id: SketchEntityID, _ index: Int, _ kind: SplineHandleKind) -> Vector2? {
        guard let definition = splineDefinition(of: id), definition.points.indices.contains(index) else { return nil }
        let given = definition.handles[index]
        switch kind {
        case .tangent: if let value = given.tangent { return value }
        case .curvature: if let value = given.curvature { return value }
        }
        let resolved = definition.resolvedHandles()[index]
        return kind == .tangent ? resolved.tangent : resolved.secondDerivative
    }
}

extension Sketch {
    func isArc(_ id: SketchEntityID) -> Bool {
        if case .arc? = entities[id]?.kind { true } else { false }
    }
}

extension Sketch {
    /// The spline at a solution's fit points and active handles (the sketch's own where the solution has none): what the
    /// editor draws and picks.
    public func splineDefinition(of id: SketchEntityID, solution: SketchSolution) -> SplineDefinition? {
        guard let (points, _) = splineParts(of: id), points.count >= 2 else { return nil }
        let positions = points.compactMap { solution.points[$0] ?? position(of: $0) }
        guard positions.count == points.count else { return nil }
        return SplineDefinition(points: positions, handles: solution.handles[id] ?? storedSplineHandles(of: id))
    }
}
