/// What a dimension measures (spec §3).
public enum DimensionKind: Hashable, Sendable, Codable {
    /// Point–point, or point–line (the line taken as infinite), in either order.
    case distance(SketchEntityID, SketchEntityID)
    /// The length of a line.
    case length(SketchEntityID)
    case radius(SketchEntityID)
    case diameter(SketchEntityID)
    /// The angle between two lines, 0–180 degrees.
    case angle(SketchEntityID, SketchEntityID)

    public var entities: [SketchEntityID] {
        switch self {
        case .distance(let a, let b), .angle(let a, let b): [a, b]
        case .length(let a), .radius(let a), .diameter(let a): [a]
        }
    }
}
