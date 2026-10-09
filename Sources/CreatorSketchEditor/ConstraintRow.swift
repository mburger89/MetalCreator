import CreatorSketch

/// One constraint in the sketch inspector: its plain-language label ("Horizontal on Line 3").
public struct ConstraintRow: Hashable, Sendable, Identifiable {
    public var id: SketchConstraintID
    public var label: String
    /// A conflict names it.
    public var isConflicting: Bool
}
