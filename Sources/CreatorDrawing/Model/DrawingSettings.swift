/// Drawing-wide settings: the standard, the general tolerance and the title fields a new sheet starts with.
public struct DrawingSettings: Hashable, Sendable, Codable {
    public var standard: DrawingStandard
    public var generalTolerance: String
    public var titleBlockDefaults: TitleBlock

    public init(
        standard: DrawingStandard = .iso, generalTolerance: String? = nil, titleBlockDefaults: TitleBlock = TitleBlock()
    ) {
        self.standard = standard
        self.generalTolerance = generalTolerance ?? Self.defaultTolerance(for: standard, inches: false)
        self.titleBlockDefaults = titleBlockDefaults
    }

    /// Plan R15's three strings.
    public static func defaultTolerance(for standard: DrawingStandard, inches: Bool) -> String {
        switch standard {
        case .iso: "ISO 2768-mK"
        case .asme: inches ? "±.03, ±.010, ±.005 in" : "±0.5, ±0.1, ±0.05 mm"
        }
    }
}
