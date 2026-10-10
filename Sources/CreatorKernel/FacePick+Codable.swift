import CreatorGeometry

extension FacePick: Codable {
    private enum CodingKeys: String, CodingKey { case tags, normal, centroid }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(tags: Set(try container.decode([TopoTag].self, forKey: .tags)),
                  normal: try container.decodeIfPresent(Vector3.self, forKey: .normal),
                  centroid: try container.decodeIfPresent(Vector3.self, forKey: .centroid))
    }

    /// Tags are written sorted by `sortKey`, so encoding is deterministic (`EdgeKey` does the same). `normal`
    /// and `centroid` are written only when recorded, so a pick without them is encoded as it always was and
    /// older readers, which ignore the keys, still read the tags: the file format version is unchanged.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tags.sorted { $0.sortKey < $1.sortKey }, forKey: .tags)
        try container.encodeIfPresent(normal, forKey: .normal)
        try container.encodeIfPresent(centroid, forKey: .centroid)
    }
}
