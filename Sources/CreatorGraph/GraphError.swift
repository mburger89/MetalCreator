import CreatorKernel

/// Why a graph command was refused.
public enum GraphError: Error, Equatable, Sendable {
    case invalidConnection(ConnectionProblem)
    case nodeNotFound(NodeID)
    case duplicateNode(NodeID)
    case linkNotFound
    case parameterNotFound(ParameterID)
    case invalidValue(String)
}
