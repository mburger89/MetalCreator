import CreatorGeometry

/// A named dimension (spec §3).
public struct SketchDimension: Hashable, Sendable, Codable {
    public var kind: DimensionKind
    /// `d1`, `d2`, … by default; unique within the sketch.
    public var name: String
    /// Millimetres, or degrees for `.angle`.
    public var value: Double
    /// When true the Sketch node shows an input socket named `name` (S4).
    public var isExposed: Bool
    /// When false the dimension only measures (a reference dimension) and adds no residual.
    public var isDriving: Bool
    /// For `.angle`: which of the angles between the lines `value` measures. `nil` until it is
    /// chosen (`Sketch.addDimension` chooses it from the geometry; otherwise the first solve
    /// picks the one nearest the warm start, and `Sketch.remember` stores it).
    public var angleSense: AngleSense?
    /// Where the user left the dimension's label, in sketch coordinates; `nil` until it is placed or
    /// dragged (the view then uses its default spot). Written only when set.
    public var labelPoint: Vector2?

    public init(kind: DimensionKind, name: String, value: Double, isExposed: Bool = false, isDriving: Bool = true,
                angleSense: AngleSense? = nil, labelPoint: Vector2? = nil) {
        self.kind = kind
        self.name = name
        self.value = value
        self.isExposed = isExposed
        self.isDriving = isDriving
        self.angleSense = angleSense
        self.labelPoint = labelPoint
    }
}
