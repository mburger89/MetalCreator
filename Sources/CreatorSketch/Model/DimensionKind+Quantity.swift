import CreatorGeometry

extension DimensionKind {
    /// What this dimension measures, which decides its unit, its prefix ("R", "Ø") and what typing may say.
    public var quantity: DimensionQuantity {
        switch self {
        case .distance, .length, .centreDistance, .lineDistance, .horizontalDistance, .verticalDistance: .length
        case .radius: .radius
        case .diameter: .diameter
        case .angle: .angle
        }
    }
}
