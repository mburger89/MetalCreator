import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Placements along a line (patterns spec §3): `count` of them from `start` along `direction`, `spacing` apart, or
/// spread over a total `length` when that is set (the last at `start + length`; one placement stays at `start`). Each
/// faces `facing`, with the x axis Plane from Face would give (`FacePlane`). One branch: a flat list.
///
/// More than 2,000 refuses ("Patterns are limited to 2,000 instances.").
public enum LinearPatternNode: NodeDefinition {
    public static let typeID = "creator.linearPattern"
    public static let displayName = "Linear Pattern"
    public static let category = NodeCategory.patterns
    public static let inputs = [
        SocketSpec("start", .vector, defaultValue: .vector(.zero)),
        SocketSpec("direction", .vector, defaultValue: .vector(.unitX)),
        SocketSpec("count", .integer, defaultValue: .integer(4), unit: .count),
        SocketSpec("spacing", .number, defaultValue: .number(10), unit: .millimetres, range: 0...200),
        SocketSpec("length", .number, unit: .millimetres, range: 0...1_000, optional: true),
        SocketSpec("facing", .vector, defaultValue: .vector(.unitZ)),
    ]
    public static let outputs = [SocketSpec("placements", .plane)]
    public static var singleValuesRefusal: String? { LayoutChecks.singleValues(displayName) }
    public static let inspector = [
        InspectorSection(title: "Row", controls: [.vector("start"), .vector("direction"), .integer("count")]),
        InspectorSection(title: "Spacing", controls: [.slider("spacing"), .number("length")]),
        InspectorSection(title: "Facing", controls: [.vector("facing")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let count = try LayoutChecks.count(try inputs.integer("count"), "count")
        try PatternLimit.check(count)
        let direction = try LayoutChecks.direction(try inputs.vector("direction"), "direction")
        let facing = try LayoutChecks.direction(try inputs.vector("facing"), "facing")
        let start = try LayoutChecks.finite(try inputs.vector("start"), "start")
        let step: Double
        if inputs.has("length") {
            let length = try LayoutChecks.number(try inputs.number("length"), "length")
            step = count > 1 ? length / Double(count - 1) : 0
        } else {
            step = try LayoutChecks.number(try inputs.number("spacing"), "spacing")
        }
        let planes = (0..<count).map { index in
            Scalar.plane(FacePlane.plane(origin: start + direction * (Double(index) * step), normal: facing))
        }
        return NodeOutputs(lists: ["placements": planes])
    }
}
