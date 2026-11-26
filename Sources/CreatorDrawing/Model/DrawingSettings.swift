/// Drawing-wide settings: the standard, the general tolerance and the title fields a new sheet starts with.
public struct DrawingSettings: Hashable, Sendable, Codable {
    public var standard: DrawingStandard
    public var generalTolerance: GeneralTolerance
    public var titleBlockDefaults: TitleBlock
    public var decimalSign: DecimalSign

    public init(
        standard: DrawingStandard = .iso, generalTolerance: GeneralTolerance? = nil, titleBlockDefaults: TitleBlock = TitleBlock(),
        decimalSign: DecimalSign = .point
    ) {
        self.standard = standard
        self.generalTolerance = generalTolerance ?? .standardDefault(for: standard, inches: false)
        self.titleBlockDefaults = titleBlockDefaults
        self.decimalSign = decimalSign
    }

    private enum CodingKeys: String, CodingKey { case standard, generalTolerance, titleBlockDefaults, decimalSign }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        standard = try c.decode(DrawingStandard.self, forKey: .standard)
        // Format 17 wrote the tolerance as a string (plan R10).
        if let legacy = try? c.decode(String.self, forKey: .generalTolerance) {
            generalTolerance = GeneralTolerance(legacy: legacy, standard: standard)
        } else {
            generalTolerance = try c.decode(GeneralTolerance.self, forKey: .generalTolerance)
        }
        titleBlockDefaults = try c.decode(TitleBlock.self, forKey: .titleBlockDefaults)
        decimalSign = try c.decodeIfPresent(DecimalSign.self, forKey: .decimalSign) ?? .point
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(standard, forKey: .standard)
        try c.encode(generalTolerance, forKey: .generalTolerance)
        try c.encode(titleBlockDefaults, forKey: .titleBlockDefaults)
        if decimalSign == .comma { try c.encode(decimalSign, forKey: .decimalSign) }
    }
}
