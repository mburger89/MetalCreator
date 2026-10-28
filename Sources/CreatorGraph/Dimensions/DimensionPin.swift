import CreatorKernel

/// A dimension the user chose to keep showing: one node's target.
public struct DimensionPin: Sendable, Hashable, Codable, Comparable {
    public var node: NodeID
    public var target: DimensionTarget

    public init(node: NodeID, target: DimensionTarget) {
        self.node = node
        self.target = target
    }

    private enum CodingKeys: String, CodingKey { case node, input, sketchDimension }

    /// `{"node":"<uuid>","input":"distance"}` or `{"node":"<uuid>","sketchDimension":3}`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        node = try container.decode(NodeID.self, forKey: .node)
        target = try DimensionTarget(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(node, forKey: .node)
        try target.encode(to: encoder)
    }

    public static func < (lhs: DimensionPin, rhs: DimensionPin) -> Bool {
        lhs.node == rhs.node ? lhs.target < rhs.target : lhs.node < rhs.node
    }
}
