import CreatorKernel

/// What an evaluation saw inside group nodes, by instance path (the group nodes from the top level down, then the
/// inner node's ID): every inner result, and the inner nodes that ran.
struct EvaluationTrace: Sendable {
    var results: [[NodeID]: NodeResult] = [:]
    var evaluated: [[NodeID]] = []
}
