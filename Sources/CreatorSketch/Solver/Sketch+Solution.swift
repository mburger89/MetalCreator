extension Sketch {
    /// Stores a solution's positions and radii as the warm start for the next solve.
    public mutating func remember(_ solution: SketchSolution) {
        for (id, point) in solution.points where entities[id] != nil { solved[id] = .point(point) }
        for (id, radius) in solution.radii where entities[id] != nil { solved[id] = .radius(radius) }
    }
}
