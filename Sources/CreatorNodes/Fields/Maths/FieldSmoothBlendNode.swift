import CreatorGraph
import CreatorKernel

/// The polynomial smooth minimum of two fields over `width` (fields spec §3.2): where they are further apart than the width
/// it is the plain minimum, and nearer it dips below by up to a quarter of the width, so two shapes' distances merge with a
/// soft join. Width 0 is the plain minimum.
public enum FieldSmoothBlendNode: NodeDefinition {
    public static let typeID = "creator.fieldSmoothBlend"
    public static let displayName = "Smooth Blend"
    public static let category = NodeCategory.fields
    public static let inputs = [
        SocketSpec("a", .field, defaultValue: .number(0)),
        SocketSpec("b", .field, defaultValue: .number(0)),
        SocketSpec("width", .number, defaultValue: .number(1)),
    ]
    public static let outputs = [SocketSpec("field", .field)]
    public static let inspector = [
        InspectorSection(title: "Fields", controls: [.number("a"), .number("b")]),
        InspectorSection(title: "Blend", controls: [.number("width")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let (a, b) = (try inputs.field("a"), try inputs.field("b"))
        let width = try inputs.number("width")
        guard width.isFinite, width >= 0 else { throw NodeError.invalidValue("“width” must be 0 or more.") }
        return NodeOutputs(["field": .field(.smoothMinimum(a, b, width: width))])
    }
}
