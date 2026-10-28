import CreatorKernel

extension Graph {
    /// The two pin commands (DIM-3): `dimensionPins` stays sorted and unique. Pins never affect evaluation. A pin for a node
    /// that is not here is not refused (a restore may put the pin before its node); decoding drops such pins instead.
    mutating func applyPin(_ command: GraphCommand) throws(GraphError) -> GraphCommand {
        switch command {
        case .pinDimension(let pin):
            let index = dimensionPins.firstIndex { $0 >= pin } ?? dimensionPins.endIndex
            guard index == dimensionPins.endIndex || dimensionPins[index] != pin else {
                throw .invalidValue("That dimension is pinned already.")
            }
            dimensionPins.insert(pin, at: index)
            return .unpinDimension(pin)
        case .unpinDimension(let pin):
            guard let index = dimensionPins.firstIndex(of: pin) else { throw .invalidValue("That dimension isn't pinned.") }
            dimensionPins.remove(at: index)
            return .pinDimension(pin)
        default:
            throw .invalidValue("Not a pin edit.")  // `apply` routes only the two pin commands here.
        }
    }

    /// The pins a file held, as a graph keeps them: only those of nodes in `nodes`, sorted, each once.
    static func repairedPins(_ decoded: [DimensionPin], nodes: [NodeID: Node]) -> [DimensionPin] {
        Array(Set(decoded.filter { nodes[$0.node] != nil })).sorted()
    }

    /// Takes every pin of `node` out and returns the commands that put each back, in pin order.
    mutating func stripPins(of node: NodeID) -> [GraphCommand] {
        let removed = dimensionPins.filter { $0.node == node }
        dimensionPins.removeAll { $0.node == node }
        return removed.map { .pinDimension($0) }
    }
}
