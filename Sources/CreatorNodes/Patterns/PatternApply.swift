import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// What a shortcut node does once it has its tools: Place and Boolean underneath (patterns spec §5), as one kernel
/// call each (§7). `Kernel.place` makes every copy at once, and one Boolean cuts or joins all of them as a compound.
enum PatternApply {
    /// The name of one instance of a shortcut in its misses warning: "hole" and "holes".
    struct Nouns {
        let singular: String
        let plural: String
    }

    /// What a shortcut asks for: `operation` of `part` with a copy of `tools[i]` at every instance `i`, placed on
    /// `planes[min(i, planes.count - 1)]`.
    struct Request {
        let operation: BooleanOp
        let part: Solid
        let tools: [Solid]
        let planes: [Plane]
        let nouns: Nouns
    }

    /// Places the copies and combines them with the part. No tools, or no placements, is the part as it is. Warns of
    /// the pieces a result falls into, as Boolean does, and of the instances that missed the part.
    static func run(_ request: Request, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        try PlacementMoves.requireFlat(context)
        let (op, part, tools, planes) = (request.operation, request.part, request.tools, request.planes)
        let count = planes.isEmpty ? 0 : tools.count
        try PatternLimit.check(count)
        guard count > 0 else { return NodeOutputs(["solid": .solid(part)]) }
        let moves = try PlacementMoves.make(planes, count: count)
        let copies = try await kernel.place(tools, at: moves, qualifying: PlacementMoves.qualifier(placedBy: context.node.id),
                                            tag: context.tag)
        let result = try await kernel.boolean(op, part, copies, tag: context.tag)
        var warnings = PieceWarning.warnings(for: result)
        let missed = PatternMisses.count(op, part: part, result: result, copies: copies)
        let nouns = request.nouns
        if let message = PatternMisses.warning(missed: missed, of: count, singular: nouns.singular, plural: nouns.plural) {
            warnings.append(message)
        }
        return NodeOutputs(["solid": .solid(result)], warnings: warnings)
    }

    /// The tool for each of the instances that `tools` and `planes` make together: the longer list sets the number
    /// of instances and the shorter repeats its last item (broadcasting, spec §4.2).
    static func tools(_ tools: [Solid], planes: [Plane]) -> [Solid] {
        guard let last = tools.indices.last, !planes.isEmpty else { return [] }
        return (0..<max(tools.count, planes.count)).map { tools[min($0, last)] }
    }
}
