/// Endpoints in one fixed order, by node and then socket: how a tie's wires are written (cable ties spec §3.3) and how its
/// lanes are ordered when two targets are level (§5.1).
extension Endpoint: Comparable {
    public static func < (lhs: Endpoint, rhs: Endpoint) -> Bool { (lhs.node, lhs.socket) < (rhs.node, rhs.socket) }
}
