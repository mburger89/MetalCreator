import CreatorGraph
import CreatorKernel

/// `count` evenly spaced numbers from `start` to `end`, both included (spec §7.1, Values).
/// A count of 1 gives just `start`. Always a list.
public enum RangeNode: NodeDefinition {
    public static let typeID = "creator.range"
    public static let displayName = "Range"
    public static let category = NodeCategory.value
    public static let inputs = [
        SocketSpec("start", .number, defaultValue: .number(0)),
        SocketSpec("end", .number, defaultValue: .number(1)),
        SocketSpec("count", .integer, defaultValue: .integer(5), unit: .count),
    ]
    public static let outputs = [SocketSpec("values", .number)]
    public static let inspector = [InspectorSection(title: "Range", controls: [.number("start"), .number("end"), .integer("count")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let (start, end, count) = (try inputs.number("start"), try inputs.number("end"), try inputs.integer("count"))
        try GeneratorLimit.check(count, "count")
        let values: [Double] = switch count {
        case 0: []
        case 1: [start]
        default: (0..<count).map { start + (end - start) * Double($0) / Double(count - 1) }
        }
        return NodeOutputs(lists: ["values": values.map(Scalar.number)])
    }
}
