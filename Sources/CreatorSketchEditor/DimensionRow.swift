import CreatorSketch

/// One dimension in the sketch inspector (sketcher spec §8): its kind and name, its value (a reference dimension's
/// live measurement), and its switches.
public struct DimensionRow: Hashable, Sendable, Identifiable {
    public var id: DimensionID
    /// "Length", "Distance", "Radius", "Diameter" or "Angle".
    public var kind: String
    public var name: String
    /// "12.5 mm", "30°".
    public var value: String
    public var isExposed: Bool
    public var isDriving: Bool
    /// Its value comes from a wire into its input socket (sketcher spec §7: the wired value overrides the stored one).
    public var isWired: Bool
    /// A conflict names it.
    public var isConflicting: Bool

    /// Whether a typed value can change it: not a reference (it only measures) and not wired.
    public var isValueEditable: Bool { isDriving && !isWired }
}
