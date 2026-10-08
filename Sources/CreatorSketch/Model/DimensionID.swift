/// Identifies one named dimension inside a sketch.
/// IDs are handed out by `Sketch` in increasing order and never reused, so sorting by ID is
/// the sketch's fixed iteration order.
public struct DimensionID: Hashable, Sendable, Comparable, Codable, CodingKeyRepresentable {
    public var rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: DimensionID, rhs: DimensionID) -> Bool { lhs.rawValue < rhs.rawValue }

    // Lets `[DimensionID: …]` encode as a JSON object keyed by the decimal ID, not as a flat
    // [key, value, …] array in hash order, so `.sortedKeys` makes files byte-identical.
    public var codingKey: any CodingKey { IDKey(rawValue) }

    public init?<T: CodingKey>(codingKey: T) {
        guard let rawValue = codingKey.intValue ?? Int(codingKey.stringValue) else { return nil }
        self.init(rawValue)
    }
}
