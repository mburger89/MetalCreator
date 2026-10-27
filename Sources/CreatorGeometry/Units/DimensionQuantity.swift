/// What a dimension's number measures, which decides its unit, its suffix and what typing may say.
public enum DimensionQuantity: Sendable, Hashable {
    case length, radius, diameter, angle, count

    /// True for the quantities written in the document's length unit.
    public var isLength: Bool {
        switch self {
        case .length, .radius, .diameter: true
        case .angle, .count: false
        }
    }
}
