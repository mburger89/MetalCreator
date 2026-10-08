import CreatorGraph
import CreatorKernel

/// Union, subtract or intersect a target with every tool in one kernel call (spec §7.1, Solids).
/// `tools` takes the whole list, so a broadcast of holes is subtracted at once (spec §7.2).
/// A result in several pieces is kept as one solid (multi-body parts are deferred) and warned about.
public enum BooleanNode: NodeDefinition {
    public static let typeID = "creator.boolean"
    public static let displayName = "Boolean"
    public static let category = NodeCategory.solid
    public static let operations = ["Union", "Subtract", "Intersect"]
    public static let inputs = [
        SocketSpec("target", .solid),
        SocketSpec("tools", .solid, access: .list),
        SocketSpec("operation", .integer, defaultValue: .integer(0)),
    ]
    public static let outputs = [SocketSpec("solid", .solid)]
    public static let inspector = [InspectorSection(title: "Boolean", controls: [.segmented("operation", options: operations)])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let op: BooleanOp = [.union, .subtract, .intersect][try inputs.choice("operation", options: operations)]
        let (target, tools) = (try inputs.solid("target"), try inputs.solids("tools"))
        // A wired but empty tool list (Hole count 0) changes nothing for a union or subtract. The
        // kernel would refuse it; an intersect with nothing keeps that error.
        if tools.isEmpty, op != .intersect {
            return NodeOutputs(["solid": .solid(target)])
        }
        let result = try await kernel.boolean(op, target, tools, tag: context.tag)
        let pieces = result.topology.pieceCount
        let warnings = pieces > 1
            ? [
                "The result is \(pieces) separate pieces. They stay together as one solid, "
                    + "because parts with several bodies aren't supported yet.",
            ]
            : []
        return NodeOutputs(["solid": .solid(result)], warnings: warnings)
    }
}
