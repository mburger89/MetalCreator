extension EdgeKey: Codable {
    private enum CodingKeys: String, CodingKey { case first, second }

    /// Decodes through `init(_:_:)`, so a hand-edited file is re-canonicalised.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            Set(try container.decode([TopoTag].self, forKey: .first)),
            Set(try container.decode([TopoTag].self, forKey: .second))
        )
    }

    /// Tag arrays are written sorted by `sortKey`, so encoding is deterministic.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(first.sorted { $0.sortKey < $1.sortKey }, forKey: .first)
        try container.encode(second.sorted { $0.sortKey < $1.sortKey }, forKey: .second)
    }
}
