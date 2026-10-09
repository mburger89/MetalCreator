import CreatorSketch

/// One dimension in the sketch inspector (sketcher spec §8): its kind and name, its value, and its switches.
public struct DimensionRow: Hashable, Sendable, Identifiable {
    public var id: DimensionID
    /// "Length", "Distance", "Radius", "Diameter" or "Angle".
    public var kind: String
    public var name: String
    /// "12.5 mm", "30°".
    public var value: String
    public var isExposed: Bool
    public var isDriving: Bool
    /// A conflict names it.
    public var isConflicting: Bool
}
