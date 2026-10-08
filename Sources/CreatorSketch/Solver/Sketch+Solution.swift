extension Sketch {
    /// Stores a solution's positions and radii as the warm start for the next solve. Angle
    /// dimensions that have no sense yet take the one nearest the solved geometry, so the sense
    /// their first solve chose is the one they keep.
    public mutating func remember(_ solution: SketchSolution) {
        for (id, point) in solution.points where entities[id] != nil { solved[id] = .point(point) }
        for (id, radius) in solution.radii where entities[id] != nil { solved[id] = .radius(radius) }
        for id in dimensionIDs {
            guard let dimension = dimensions[id], dimension.angleSense == nil else { continue }
            let sense = nearestAngleSense(for: dimension.kind, degrees: dimension.value) { solution.points[$0] }
            dimensions[id]?.angleSense = sense
        }
    }
}
