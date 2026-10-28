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
    /// Between the centres of two circles or arcs, or a circle or arc and a point.
    case centreDistance(SketchEntityID, SketchEntityID)
    /// Two lines: the distance from the second line's midpoint to the first line, along the first line's normal.
    case lineDistance(SketchEntityID, SketchEntityID)
    /// |Δx| between two points or circle/arc centres (either operand may be either).
    case horizontalDistance(SketchEntityID, SketchEntityID)
    /// |Δy| likewise.
    case verticalDistance(SketchEntityID, SketchEntityID)

    public var entities: [SketchEntityID] {
        switch self {
        case .distance(let a, let b), .angle(let a, let b), .centreDistance(let a, let b), .lineDistance(let a, let b),
             .horizontalDistance(let a, let b), .verticalDistance(let a, let b): [a, b]
        case .length(let a), .radius(let a), .diameter(let a): [a]
        }
    }
}
