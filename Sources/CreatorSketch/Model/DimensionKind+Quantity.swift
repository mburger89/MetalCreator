import CreatorGeometry

extension DimensionKind {
    /// What this dimension measures, which decides its unit, its prefix ("R", "Ø") and what typing may say.
    public var quantity: DimensionQuantity {
        switch self {
        case .distance, .length: .length
        case .radius: .radius
        case .diameter: .diameter
        case .angle: .angle
        }
    }
}
