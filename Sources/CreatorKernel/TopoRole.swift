/// The stable role a face plays in the operation that created it (spec §5.3).
public indirect enum TopoRole: Hashable, Sendable {
    case startCap
    case endCap
    /// The side face swept from segment `segment` of profile loop `loop`: 0 is the outer loop,
    /// n is hole n (`Profile2D.loops`). `loop` defaults to 0, so `.side(segment: k)` is an outer wall.
    case side(loop: Int = 0, segment: Int)
    /// The blend face a fillet or chamfer made from the edge `sourceEdge`.
    case blend(sourceEdge: EdgeKey)
    /// A face the operation's history does not explain. Unstable across rebuilds by design;
    /// it exists so that no face ever has an empty tag set (M2 plan decision).
    case unnamed(face: Int)

    /// A deterministic text form, used to order tags canonically. Outer walls keep the
    /// pre-hole form `side(k)`; hole walls are `side(loop:k)`.
    public var sortKey: String {
        switch self {
        case .startCap: "startCap"
        case .endCap: "endCap"
        case .side(loop: 0, let segment): "side(\(segment))"
        case .side(let loop, let segment): "side(\(loop):\(segment))"
        case .blend(let edge): "blend(\(edge.sortKey))"
        case .unnamed(let face): "unnamed(\(face))"
        }
    }
}
