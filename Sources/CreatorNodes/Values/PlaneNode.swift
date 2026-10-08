import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// One of the three base planes, moved along its normal (spec §7.1, Values).
/// XZ's normal is −Y, so a positive offset moves it towards −Y.
public enum PlaneNode: NodeDefinition {
    public static let typeID = "creator.plane"
    public static let displayName = "Plane"
    public static let category = NodeCategory.value
    public static let orientations = ["XY", "XZ", "YZ"]
    public static let inputs = [
        SocketSpec("orientation", .integer, defaultValue: .integer(0)),
        SocketSpec("offset", .number, defaultValue: .number(0), unit: .millimetres, range: -200...200),
    ]
    public static let outputs = [SocketSpec("plane", .plane)]
    public static let inspector = [InspectorSection(title: "Plane", controls: [
        .segmented("orientation", options: orientations), .slider("offset"),
    ]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let base = [Plane.xy, .xz, .yz][try inputs.choice("orientation", options: orientations)]
        return NodeOutputs(["plane": .plane(base.offset(by: try inputs.number("offset")))])
    }
}
