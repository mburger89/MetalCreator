extension FacePick: Codable {
    private enum CodingKeys: String, CodingKey { case tags }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(tags: Set(try container.decode([TopoTag].self, forKey: .tags)))
    }

    /// Tags are written sorted by `sortKey`, so encoding is deterministic (`EdgeKey` does the same).
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tags.sorted { $0.sortKey < $1.sortKey }, forKey: .tags)
    }
}
