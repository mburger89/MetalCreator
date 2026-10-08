import CreatorGeometry

/// A 2D constraint sketch on a plane (spec §3): entities, constraints, named dimensions and the
/// warm-start positions from the last good solve. A plain value: every edit makes a new sketch.
public struct Sketch: Hashable, Sendable, Codable {
    public var plane: SketchPlaneSource
    public var entities: [SketchEntityID: SketchEntity]
    public var constraints: [SketchConstraintID: SketchConstraint]
    public var dimensions: [DimensionID: SketchDimension]
    /// Warm-start values from the last good solve. Entities without an entry use their drawn values.
    public var solved: [SketchEntityID: SolvedState]
    /// The raw value of the next ID handed out. Entity, constraint and dimension IDs share this
    /// counter, so no two IDs in a sketch have the same raw value and none is ever reused.
    public var nextID: Int

    public init(plane: SketchPlaneSource = .fixed(.xy)) {
        self.plane = plane
        entities = [:]
        constraints = [:]
        dimensions = [:]
        solved = [:]
        nextID = 1
    }

    /// Entity IDs in ascending order, the sketch's fixed iteration order.
    public var entityIDs: [SketchEntityID] { entities.keys.sorted() }
    public var constraintIDs: [SketchConstraintID] { constraints.keys.sorted() }
    public var dimensionIDs: [DimensionID] { dimensions.keys.sorted() }
}
