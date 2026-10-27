/// The unit a document shows lengths in. Values are stored in millimetres whatever the unit; the unit only changes how
/// they are written and read.
public enum LengthUnit: String, Sendable, Hashable, CaseIterable, Codable {
    case millimetres = "mm"
    case inches = "in"

    /// Millimetres in one of this unit.
    public var millimetresPerUnit: Double {
        switch self {
        case .millimetres: 1
        case .inches: 25.4
        }
    }

    /// The short written form, as typed after a number.
    public var symbol: String { rawValue }

    /// The name shown in menus.
    public var title: String {
        switch self {
        case .millimetres: "Millimetres"
        case .inches: "Inches"
        }
    }

    /// Fraction digits shown when the document sets no precision of its own.
    public var defaultPrecision: Int {
        switch self {
        case .millimetres: 1
        case .inches: 2
        }
    }
}
