import CreatorGraph
import CreatorKernel

/// A surface through a list of curves, in list order (NURBS spec). A profile on `sections` gives its one loop; one with
/// holes is refused.
public enum LoftSurfaceNode: NodeDefinition {
    public static let typeID = "creator.loftSurface"
    public static let displayName = "Loft Surface"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Make"
    public static let maximumSections = 1_000
    public static let inputs = [
        SocketSpec("sections", .curve, access: .list),
        SocketSpec("ruled", .bool, defaultValue: .bool(false)),
        SocketSpec("closed", .bool, defaultValue: .bool(false)),
    ]
    public static let outputs = [SocketSpec("surface", .solid)]
    public static let inspector = [InspectorSection(title: "Loft Surface", controls: [
        .toggle("ruled", label: "Straight sides (ruled)"), .toggle("closed", label: "Closed"),
    ]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let sources = try inputs.curves("sections")
        guard sources.count <= maximumSections else {
            throw NodeError.invalidValue("A loft takes at most \(maximumSections.display) sections.")
        }
        var sections: [Curve] = []
        for (index, source) in sources.enumerated() {
            sections += try await CurveInput.loops([source], holes: .refuse("Section \(index + 1) has holes; a loft section is one loop."),
                                                   kernel: kernel, tag: context.tag)
        }
        let surface = try await kernel.loftSurface(sections, ruled: try inputs.bool("ruled"), closed: try inputs.bool("closed"),
                                                   tag: context.tag)
        return NodeOutputs(["surface": .solid(surface)])
    }
}
