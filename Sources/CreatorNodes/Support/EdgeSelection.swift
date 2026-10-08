import CreatorGraph
import CreatorKernel

/// Shared output for selection-rule nodes (spec §5.3, rule 6: no silent drift).
enum EdgeSelection {
    static let noMatches = "This rule matched no edges."

    /// An `edges` output on `solid`, warning when nothing matched.
    static func outputs(_ solid: Solid, _ edges: [EdgeID], warnings: [String] = []) -> NodeOutputs {
        NodeOutputs(["edges": .edgeSet(EdgeSet(solid: solid, edges: edges))],
                    warnings: edges.isEmpty && warnings.isEmpty ? [noMatches] : warnings)
    }

    /// The edges every rule may select: seams are never selectable (spec §5.1).
    static func candidates(_ solid: Solid) -> [EdgeInfo] {
        solid.topology.edges.filter { !$0.isSeam }
    }
}
