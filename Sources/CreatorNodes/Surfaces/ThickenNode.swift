import CreatorGraph
import CreatorKernel

/// A sheet given a thickness, front, back or both ways (NS-5, R3, R7): a closed solid.
public enum ThickenNode: NodeDefinition {
    public static let typeID = "creator.thicken"
    public static let displayName = "Thicken"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Solids"
    public static let sides = ["Front", "Back", "Both"]
    public static let inputs = [
        SocketSpec("surface", .solid),
        SocketSpec("distance", .number, defaultValue: .number(1), unit: .millimetres, range: 0.01...100),
        SocketSpec("side", .integer, defaultValue: .integer(0)),
    ]
    public static let outputs = [SocketSpec("solid", .solid)]
    public static let inspector = [
        InspectorSection(title: "Thicken", controls: [.slider("distance"), .segmented("side", options: sides)]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let side = ThickenSide(rawValue: try inputs.choice("side", options: sides)) ?? .front
        let solid = try await kernel.thickened(try inputs.solid("surface"), distance: try inputs.number("distance"),
                                               side: side, tag: context.tag)
        return NodeOutputs(["solid": .solid(solid)])
    }
}
