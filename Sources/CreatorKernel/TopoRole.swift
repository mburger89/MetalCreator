/// The stable role a face plays in the operation that created it (spec §5.3).
public indirect enum TopoRole: Hashable, Sendable {
    case startCap
    case endCap
    /// The side face swept from profile segment `segment`.
    case side(segment: Int)
    /// The blend face a fillet or chamfer made from the edge `sourceEdge`.
    case blend(sourceEdge: EdgeKey)

    /// A deterministic text form, used to order tags canonically.
    public var sortKey: String {
        switch self {
        case .startCap: "startCap"
        case .endCap: "endCap"
        case .side(let segment): "side(\(segment))"
        case .blend(let edge): "blend(\(edge.sortKey))"
        }
    }
}
