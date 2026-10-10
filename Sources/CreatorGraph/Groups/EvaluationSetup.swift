/// What every level of one evaluation shares (groups spec §5): the registry carrying the document's definitions, so
/// group nodes have their sockets, and the document's parameters.
struct EvaluationSetup: Sendable {
    var registry: NodeRegistry
    var parameters: [ParameterID: ConstantValue]
}
