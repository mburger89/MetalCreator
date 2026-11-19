/// A remembered Trim Surface keep pick (NS-4, R17): the picked piece's `FacePick` and `sharedBy`, the number of pieces its tags
/// named in the split it was picked on, so a pick on one of several pieces that share a name resolves without a warning.
public struct RegionPick: Hashable, Sendable {
    public var pick: FacePick
    /// At least 1.
    public var sharedBy: Int

    public init(pick: FacePick, sharedBy: Int = 1) {
        self.pick = pick
        self.sharedBy = max(1, sharedBy)
    }
}

extension RegionPick: Codable {
    private enum CodingKeys: String, CodingKey { case pick, sharedBy }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(pick: try container.decode(FacePick.self, forKey: .pick),
                  sharedBy: try container.decodeIfPresent(Int.self, forKey: .sharedBy) ?? 1)
    }

    /// `sharedBy` is written only when greater than 1.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pick, forKey: .pick)
        if sharedBy > 1 { try container.encode(sharedBy, forKey: .sharedBy) }
    }
}
