import CreatorGraph
import CreatorKernel

/// A sheet divided by curves or a body into its pieces, one sheet each (NS-4, R2, R6, R7).
public enum SplitSurfaceNode: NodeDefinition {
    public static let typeID = "creator.splitSurface"
    public static let displayName = "Split Surface"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Edit"
    public static let inputs = [SocketSpec("surface", .solid)] + TrimCutterInput.cutterInputs
    public static let outputs = [SocketSpec("pieces", .solid, access: .list)]

    public static func inspector(for node: Node) -> [InspectorSection] {
        [InspectorSection(title: "Split Surface", controls: TrimCutterInput.controls(for: node))]
    }

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let surface = try inputs.solid("surface")
        let cutter = try await TrimCutterInput.read(inputs, node: displayName, kernel: kernel, tag: context.tag)
        let split = try await kernel.split(surface, by: cutter, tag: context.tag)
        var sheets: [Scalar] = []
        for faces in split.pieces {
            sheets.append(.solid(try await kernel.subSheet(faces, of: split.whole)))
        }
        return NodeOutputs(lists: ["pieces": sheets], warnings: split.warnings)
    }
}
