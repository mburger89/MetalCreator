/// A datum feature symbol (plan R1, R5). `distance` is sheet mm from the foot to the square's centre, its sign the side;
/// `dimensionEnd` (0 or 1) is the end of a dimension line it stands on.
public struct DatumFeature: Hashable, Codable, Sendable {
    public var letter: String
    public var attachment: SymbolAttachment
    public var distance: Double
    public var dimensionEnd: Int

    public init(letter: String, attachment: SymbolAttachment, distance: Double = 0, dimensionEnd: Int = 0) {
        self.letter = letter
        self.attachment = attachment
        self.distance = distance
        self.dimensionEnd = dimensionEnd
    }

    private enum CodingKeys: String, CodingKey { case letter, attachment, distance, dimensionEnd }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        letter = try c.decode(String.self, forKey: .letter)
        attachment = try c.decode(SymbolAttachment.self, forKey: .attachment)
        distance = try c.decodeIfPresent(Double.self, forKey: .distance) ?? 0
        dimensionEnd = try c.decodeIfPresent(Int.self, forKey: .dimensionEnd) ?? 0
    }
}
