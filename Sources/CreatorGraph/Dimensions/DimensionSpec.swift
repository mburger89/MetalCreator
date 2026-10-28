import CreatorGeometry

/// One dimension a node declares while it evaluates: what it measures, in world space, and what it edits.
public struct DimensionSpec: Sendable, Hashable {
    public var target: DimensionTarget
    public var geometry: DimensionGeometry
    public var quantity: DimensionQuantity
    /// The measured value, in the quantity's base unit (millimetres, degrees).
    public var value: Double
    public var count: Int?
    /// Which component of a vector input this edits, when the target is one.
    public var component: Int?
    /// How many value units one unit of the input is (for example a diameter shown for a radius input).
    public var inputScale: Double

    public init(_ target: DimensionTarget, _ geometry: DimensionGeometry, _ quantity: DimensionQuantity, value: Double,
                count: Int? = nil, component: Int? = nil, inputScale: Double = 1) {
        self.target = target
        self.geometry = geometry
        self.quantity = quantity
        self.value = value
        self.count = count
        self.component = component
        self.inputScale = inputScale
    }
}
