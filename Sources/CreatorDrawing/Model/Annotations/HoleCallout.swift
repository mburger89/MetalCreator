public struct HoleCallout: Hashable, Codable, Sendable {
    public var anchor: AnchorTarget
    public var placement: DimensionPlacement
    public var prefix: String
    public var suffix: String

    public init(anchor: AnchorTarget, placement: DimensionPlacement, prefix: String = "", suffix: String = "") {
        self.anchor = anchor
        self.placement = placement
        self.prefix = prefix
        self.suffix = suffix
    }

    private enum CodingKeys: String, CodingKey { case anchor, placement, prefix, suffix }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        anchor = try c.decode(AnchorTarget.self, forKey: .anchor)
        placement = try c.decode(DimensionPlacement.self, forKey: .placement)
        prefix = try c.decodeIfPresent(String.self, forKey: .prefix) ?? ""
        suffix = try c.decodeIfPresent(String.self, forKey: .suffix) ?? ""
    }
}
