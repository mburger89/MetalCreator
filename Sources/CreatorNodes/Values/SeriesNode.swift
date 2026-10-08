import CreatorGraph
import CreatorKernel

/// `count` numbers: start, start + step, … (spec §7.1, Values). Always a list.
public enum SeriesNode: NodeDefinition {
    public static let typeID = "creator.series"
    public static let displayName = "Series"
    public static let category = NodeCategory.value
    public static let inputs = [
        SocketSpec("start", .number, defaultValue: .number(0)),
        SocketSpec("step", .number, defaultValue: .number(1)),
        SocketSpec("count", .integer, defaultValue: .integer(10), unit: .count),
    ]
    public static let outputs = [SocketSpec("values", .number)]
    public static let inspector = [InspectorSection(title: "Series", controls: [.number("start"), .number("step"), .integer("count")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let (start, step, count) = (try inputs.number("start"), try inputs.number("step"), try inputs.integer("count"))
        try GeneratorLimit.check(count, "count")
        return NodeOutputs(lists: ["values": (0..<count).map { .number(start + Double($0) * step) }])
    }
}
