import CreatorSketch

/// What a driving dimension edits: a node's input socket, or a dimension inside the node's sketch.
public enum DimensionTarget: Sendable, Hashable, Codable, Comparable {
    case input(SocketName)
    case sketchDimension(DimensionID)

    /// A stable text key: `input/<socket>` or `sketch/<rawValue>`.
    public var key: String {
        switch self {
        case let .input(socket): "input/\(socket.rawValue)"
        case let .sketchDimension(id): "sketch/\(id.rawValue)"
        }
    }

    private enum CodingKeys: String, CodingKey { case input, sketchDimension }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let socket = try container.decodeIfPresent(SocketName.self, forKey: .input) {
            self = .input(socket)
        } else if let id = try container.decodeIfPresent(DimensionID.self, forKey: .sketchDimension) {
            self = .sketchDimension(id)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "A dimension target names an input or a sketch dimension."))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .input(socket): try container.encode(socket, forKey: .input)
        case let .sketchDimension(id): try container.encode(id, forKey: .sketchDimension)
        }
    }

    /// Inputs by name, then sketch dimensions by ID.
    public static func < (lhs: DimensionTarget, rhs: DimensionTarget) -> Bool {
        switch (lhs, rhs) {
        case let (.input(a), .input(b)): a < b
        case let (.sketchDimension(a), .sketchDimension(b)): a < b
        case (.input, .sketchDimension): true
        case (.sketchDimension, .input): false
        }
    }
}
