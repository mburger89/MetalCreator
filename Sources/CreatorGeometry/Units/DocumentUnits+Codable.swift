extension DocumentUnits: Codable {
    private enum CodingKeys: String, CodingKey {
        case length, precision
    }

    /// Reads leniently: a missing or unknown unit is millimetres, a precision outside the range is clamped.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try? container.decodeIfPresent(String.self, forKey: .length)
        let length = name.flatMap(LengthUnit.init(rawValue:)) ?? .millimetres
        let precision = (try? container.decodeIfPresent(Int.self, forKey: .precision))
            .map { min(max($0, Self.precisionRange.lowerBound), Self.precisionRange.upperBound) }
        self.init(length: length, precision: precision)
    }

    /// Writes only what differs from the default.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if length != .millimetres { try container.encode(length, forKey: .length) }
        if let precision { try container.encode(precision, forKey: .precision) }
    }
}
