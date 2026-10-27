/// The document's display units: a length unit and how many decimals to show. Internal values stay millimetres.
public struct DocumentUnits: Sendable, Hashable {
    /// The decimals a document may ask for.
    public static let precisionRange: ClosedRange<Int> = 0...4

    /// Millimetres with the default precision, what a file without units reads as.
    public static let millimetres = DocumentUnits()

    public var length: LengthUnit

    /// Decimals shown, or nil for the length unit's default.
    public var precision: Int?

    public init(length: LengthUnit = .millimetres, precision: Int? = nil) {
        self.length = length
        self.precision = precision
    }

    /// The decimals to show, inside `precisionRange`.
    public var fractionDigits: Int {
        let digits = precision ?? length.defaultPrecision
        return min(max(digits, Self.precisionRange.lowerBound), Self.precisionRange.upperBound)
    }

    /// A length in the document's unit, from millimetres.
    public func value(fromMillimetres millimetres: Double) -> Double {
        millimetres / length.millimetresPerUnit
    }

    /// Millimetres from a length in the document's unit.
    public func millimetres(fromValue value: Double) -> Double {
        value * length.millimetresPerUnit
    }
}
