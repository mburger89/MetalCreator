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

    /// What a shortcut asks for: `operation` of `part` with a copy of `tools[i]` at every instance `i` of `grid`, placed on
    /// `planes[i]` and named by `grid.items[i]`. `tools` and `planes` have one entry per instance.
    struct Request {
        let operation: BooleanOp
        let part: Solid
        let tools: [Solid]
        let planes: [Plane]
        let grid: InstanceGrid
        let nouns: Nouns
    }

    /// Places the copies and combines them with the part. No tools, or no placements, is the part as it is. Warns of
    /// the pieces a result falls into, as Boolean does, and of the instances that missed the part.
    static func run(_ request: Request, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let (op, part, grid) = (request.operation, request.part, request.grid)
        let count = grid.count
        guard count > 0 else { return NodeOutputs(["solid": .solid(part)]) }
        let copies = try await PlacementMoves.place(request.tools, planes: request.planes, items: grid.items,
                                                    placedBy: context.node.id, kernel: kernel, tag: context.tag)
        let result = try await kernel.boolean(op, part, copies, tag: context.tag)
        var warnings = PieceWarning.warnings(for: result)
        let missed = PatternMisses.count(op, part: part, result: result, copies: copies, items: grid.items)
        let nouns = request.nouns
        if let message = PatternMisses.warning(missed: missed, of: count, singular: nouns.singular, plural: nouns.plural) {
            warnings.append(message)
        }
        return NodeOutputs(["solid": .solid(result)], warnings: warnings)
    }
}
