import CreatorGeometry

/// The place of one pole in a curve's or surface's control net: `i` along the first parameter, `j` along the second.
/// A curve's poles have `j == 0`. Ordered by `i`, then `j`.
public struct PoleIndex: Hashable, Comparable, Codable, Sendable {
    public var i: Int
    public var j: Int

    public init(i: Int, j: Int = 0) {
        self.i = i
        self.j = j
    }

    public static func < (lhs: PoleIndex, rhs: PoleIndex) -> Bool {
        (lhs.i, lhs.j) < (rhs.i, rhs.j)
    }
}

/// One control point moved by an offset, in millimetres, from where the input put it.
public struct PoleMove: Hashable, Codable, Sendable {
    public var index: PoleIndex
    public var offset: Vector3

    public init(index: PoleIndex, offset: Vector3) {
        self.index = index
        self.offset = offset
    }

    private enum CodingKeys: String, CodingKey { case i, j, offset }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = PoleIndex(
            i: try container.decode(Int.self, forKey: .i), j: try container.decodeIfPresent(Int.self, forKey: .j) ?? 0
        )
        offset = try container.decode(Vector3.self, forKey: .offset)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index.i, forKey: .i)
        try container.encode(index.j, forKey: .j)
        try container.encode(offset, forKey: .offset)
    }
}
