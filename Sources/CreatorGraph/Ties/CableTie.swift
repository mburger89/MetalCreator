import CreatorGeometry

/// A cable tie (cable ties spec 2026-10-26 §3.1): a shared waypoint that the wires it holds run through side by side and
/// fan out after. Editor furniture: it never affects evaluation. `position` is in stored (left-to-right) canvas points, like a
/// node's; each wire is named by its input endpoint (`Link.to`), since an input takes at most one wire. `Graph.apply` keeps
/// every wire a link's input of the graph (I1) and every tie at `minimumWires` or more (I2); decoding repairs both
/// (`Graph.repaired`).
public struct CableTie: Hashable, Sendable, Identifiable {
    /// The fewest wires a tie holds (I2).
    public static let minimumWires = 2

    public var id: TieID
    public var position: Vector2
    public var wires: Set<Endpoint>

    public init(id: TieID = TieID(), position: Vector2, wires: Set<Endpoint>) {
        self.id = id
        self.position = position
        self.wires = wires
    }
}

/// Saved in `Graph.ties` (format 9) with its wires sorted, so the same tie is always the same bytes.
extension CableTie: Codable {
    private enum CodingKeys: String, CodingKey { case id, position, wires }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(TieID.self, forKey: .id),
                  position: try container.decode(Vector2.self, forKey: .position),
                  wires: Set(try container.decode([Endpoint].self, forKey: .wires)))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(position, forKey: .position)
        try container.encode(wires.sorted(), forKey: .wires)
    }
}
