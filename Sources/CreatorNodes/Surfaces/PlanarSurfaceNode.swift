import CreatorGraph
import CreatorKernel

/// A flat surface bounded by closed planar curves, the outer loop and its holes (NURBS spec).
public enum PlanarSurfaceNode: NodeDefinition {
    public static let typeID = "creator.planarSurface"
    public static let displayName = "Planar Surface"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Make"
    public static let inputs = [SocketSpec("curves", .curve, access: .list)]
    public static let outputs = [SocketSpec("surface", .solid)]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let loops = try await CurveInput.loops(try inputs.curves("curves"), holes: .all, kernel: kernel, tag: context.tag)
        let surface = try await kernel.planarSurface(loops, tag: context.tag)
        return NodeOutputs(["surface": .solid(surface)])
    }
}
