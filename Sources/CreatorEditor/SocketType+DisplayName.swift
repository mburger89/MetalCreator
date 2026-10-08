import CreatorGraph

extension SocketType {
    /// The type's name with its article, for messages: "a number", "an edge set".
    public var indefiniteName: String {
        switch self {
        case .number: "a number"
        case .integer: "a whole number"
        case .bool: "an on/off value"
        case .vector: "a vector"
        case .plane: "a plane"
        case .profile: "a profile"
        case .solid: "a solid"
        case .edgeSet: "an edge set"
        case .faceSet: "a face set"
        }
    }
}
