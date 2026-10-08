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
    /// The smallest N the next auto dimension name `dN` may use. It only grows, so an auto name
    /// is never handed out twice, even after its dimension is renamed or removed: an exposed
    /// `d1` socket can't silently start driving a different dimension.
    public var nextDimensionNumber: Int

    public init(plane: SketchPlaneSource = .fixed(.xy)) {
        self.plane = plane
        entities = [:]
        constraints = [:]
        dimensions = [:]
        solved = [:]
        nextID = 1
        nextDimensionNumber = 1
    }

    /// Decodes a sketch, then clamps both counters past everything in use, so a file saved before
    /// the name counter existed, or edited by hand, can never reuse an ID or an auto name.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plane = try container.decode(SketchPlaneSource.self, forKey: .plane)
        entities = try container.decode([SketchEntityID: SketchEntity].self, forKey: .entities)
        constraints = try container.decode([SketchConstraintID: SketchConstraint].self, forKey: .constraints)
        dimensions = try container.decode([DimensionID: SketchDimension].self, forKey: .dimensions)
        solved = try container.decode([SketchEntityID: SolvedState].self, forKey: .solved)
        let largestID = (entities.keys.map(\.rawValue) + constraints.keys.map(\.rawValue) + dimensions.keys.map(\.rawValue)).max() ?? 0
        nextID = max(try container.decode(Int.self, forKey: .nextID), largestID + 1)
        let largestName = dimensions.values.compactMap { Self.autoNameNumber($0.name) }.max() ?? 0
        nextDimensionNumber = max(try container.decodeIfPresent(Int.self, forKey: .nextDimensionNumber) ?? 1, largestName + 1)
    }

    /// N for an auto-style name `dN` (N ≥ 1), else `nil`.
    static func autoNameNumber(_ name: String) -> Int? {
        guard name.first == "d", let number = Int(name.dropFirst()), number >= 1, "d\(number)" == name else { return nil }
        return number
    }

    /// Entity IDs in ascending order, the sketch's fixed iteration order.
    public var entityIDs: [SketchEntityID] { entities.keys.sorted() }
    public var constraintIDs: [SketchConstraintID] { constraints.keys.sorted() }
    public var dimensionIDs: [DimensionID] { dimensions.keys.sorted() }
}
