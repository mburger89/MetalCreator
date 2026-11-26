import CreatorGeometry

/// The sheet's parts list (DR-5 R7); `bottomRight` is nil while it stands on the title block.
public struct PartsList: Hashable, Codable, Sendable {
    public var bottomRight: Vector2?

    public init(bottomRight: Vector2? = nil) {
        self.bottomRight = bottomRight
    }

    private enum CodingKeys: String, CodingKey { case bottomRight }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bottomRight = try c.decodeIfPresent(Vector2.self, forKey: .bottomRight)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(bottomRight, forKey: .bottomRight)
    }
}
