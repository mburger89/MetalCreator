import CreatorGraph

extension ConnectionProblem {
    /// Plain-language text for a refused wire, shown under the canvas.
    public var message: String {
        switch self {
        case .unknownNode: "That node's type isn't available, so it can't be wired."
        case .unknownSocket(let socket): "This node has no socket “\(socket)”."
        case .sameNode: "A node can't be wired to itself."
        case .typeMismatch(let from, let to):
            "\(from.indefiniteName.prefix(1).uppercased())\(from.indefiniteName.dropFirst()) can't connect to \(to.indefiniteName) input."
        case .wouldCreateCycle: "That wire would make a loop."
        }
    }
}
