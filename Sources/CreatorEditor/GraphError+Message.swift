import CreatorGraph

extension GraphError {
    /// Plain-language text for a refused edit.
    public var message: String {
        switch self {
        case .invalidConnection(let problem): problem.message
        case .nodeNotFound: "That node no longer exists."
        case .duplicateNode: "That node already exists."
        case .linkNotFound: "That wire no longer exists."
        case .parameterNotFound: "That parameter no longer exists."
        case .invalidValue(let message): message
        }
    }
}
