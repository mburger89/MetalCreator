import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Placements along curves (patterns spec §3): along the edges of an edge set (from the selection nodes) or the outline of a
/// profile, by `count` or by `spacing`, each facing along the curve's direction of travel, with the x axis Plane from Face
/// would give. One branch per connected chain of edges (`EdgeChains`), so a placement is `{chain;index}`; a profile gives its
/// outline first and then each hole.
///
/// By count, the placements are spread evenly: round a closed chain without repeating its start, along an open one from its
/// start to its end. By spacing, they stand one spacing apart from the chain's start (and so fill a closed chain up to the
/// last whole spacing). Straight and circular edges only for now: another curve refuses, naming the edge.
///
/// More than 2,000 placements in all refuses ("Patterns are limited to 2,000 instances.").
public enum CurvePatternNode: NodeDefinition {
    public static let typeID = "creator.curvePattern"
    public static let displayName = "Curve Pattern"
    public static let category = NodeCategory.patterns
    public static let modes = ["By count", "By spacing"]
    public static let inputs = [
        SocketSpec("edges", .edgeSet, access: .list, optional: true),
        SocketSpec("profile", .profile, access: .list, optional: true),
        SocketSpec("mode", .integer, defaultValue: .integer(0)),
        SocketSpec("count", .integer, defaultValue: .integer(8), unit: .count),
        SocketSpec("spacing", .number, defaultValue: .number(10), unit: .millimetres, range: 0.1...200),
    ]
    public static let outputs = [SocketSpec("placements", .plane)]
    public static var singleValuesRefusal: String? { LayoutChecks.singleValues(displayName) }
    public static let inspector = [
        InspectorSection(title: "Along the curve", controls: [.segmented("mode", options: modes), .integer("count"), .slider("spacing")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let (hasEdges, hasProfile) = (inputs.has("edges"), inputs.has("profile"))
        guard hasEdges || hasProfile else { throw NodeError.invalidValue("Wire edges or a profile for the pattern to follow.") }
        guard !(hasEdges && hasProfile) else { throw NodeError.invalidValue("Wire either edges or a profile to follow, not both.") }
        let bySpacing = try inputs.choice("mode", options: modes) == 1
        let count = try LayoutChecks.count(try inputs.integer("count"), "count")
        let spacing = try inputs.number("spacing")
        guard !bySpacing || (spacing.isFinite && spacing > 0) else { throw NodeError.invalidValue("“spacing” must be greater than 0 mm.") }
        let chains = hasEdges ? try edgeChains(inputs) : try profileChains(inputs)
        // Every chain's count is known before any placement is made, so a pattern that's too big costs nothing.
        var total = 0
        for chain in chains {
            let chainCount = bySpacing ? chain.count(spacing: spacing) : count
            try PatternLimit.check(chainCount)
            total += chainCount
            try PatternLimit.check(total)
        }
        let branches = chains.map { chain -> DataTree in
            let distances = bySpacing ? chain.distances(spacing: spacing) : chain.distances(count: count)
            return .list(distances.compactMap { distance in
                chain.sample(at: distance).map { Scalar.plane(FacePlane.plane(origin: $0.point, normal: $0.tangent)) }
            })
        }
        return NodeOutputs(trees: ["placements": DataTree(depth: 2, branches: branches) ?? .empty(depth: 2)])
    }

    /// The chains of each edge set, set by set: the edges of one solid never join the edges of another.
    private static func edgeChains(_ inputs: NodeInputs) throws -> [CurveChain] {
        var chains: [CurveChain] = []
        for scalar in try inputs.list("edges") {
            guard case .edgeSet(let set) = scalar else { throw NodeError.typeMismatch("edges", expected: .edgeSet) }
            var curves: [EdgeCurve] = []
            for id in set.edges.sorted(by: { $0.rawValue < $1.rawValue }) {
                guard let curve = set.solid.topology.edge(id)?.curve else {
                    throw NodeError.invalidValue("Curve Pattern follows straight and circular edges for now: "
                        + "edge \(id.rawValue.display) is another kind of curve.")
                }
                curves.append(curve)
            }
            chains += EdgeChains.chains(of: curves)
        }
        return chains
    }

    private static func profileChains(_ inputs: NodeInputs) throws -> [CurveChain] {
        try inputs.profiles("profile").flatMap { EdgeChains.chains(of: $0) }
    }
}
