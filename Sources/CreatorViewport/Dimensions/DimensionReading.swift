import CreatorGeometry

/// What a dimension shows: a value, what it measures, and the decorations around the number.
public struct DimensionReading: Sendable, Hashable {
    /// Millimetres for lengths, radii and diameters; degrees for angles; a plain number for counts.
    public var value: Double
    public var quantity: DimensionQuantity

    /// The number of equal features ("2X Ø8"), shown when 2 or more.
    public var count: Int?

    /// A reference dimension is shown in parentheses.
    public var isReference: Bool

    /// A named dimension is shown as "name = value".
    public var name: String?

    public init(_ value: Double, _ quantity: DimensionQuantity, count: Int? = nil, isReference: Bool = false, name: String? = nil) {
        self.value = value
        self.quantity = quantity
        self.count = count
        self.isReference = isReference
        self.name = name
    }
}
