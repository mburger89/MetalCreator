import CreatorGraph
import CreatorKernel

/// A Gordon surface through a network of curves: `u` curves one way and `v` curves the other, each crossing each at a
/// point (NURBS spec). A profile on either input gives its one loop; one with holes is refused.
public enum NetworkSurfaceNode: NodeDefinition {
    public static let typeID = "creator.networkSurface"
    public static let displayName = "Network Surface"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Make"
    public static let maximumCurves = 2_000
    public static let inputs = [
        SocketSpec("u curves", .curve, access: .list),
        SocketSpec("v curves", .curve, access: .list),
        SocketSpec("tolerance", .number, defaultValue: .number(0.01), unit: .millimetres, range: 0.0001...1),
    ]
    public static let outputs = [SocketSpec("surface", .solid)]
    public static let inspector = [InspectorSection(title: "Network Surface", controls: [.slider("tolerance")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let uSources = try inputs.curves("u curves"), vSources = try inputs.curves("v curves")
        guard uSources.count + vSources.count <= maximumCurves else {
            throw NodeError.invalidValue("A network takes at most \(maximumCurves.display) curves.")
        }
        var u: [Curve] = [], v: [Curve] = []
        for (index, source) in uSources.enumerated() {
            u += try await CurveInput.loops([source], holes: .refuse("Curve \(index + 1) has holes; a network curve is one loop."),
                                            kernel: kernel, tag: context.tag)
        }
        for (index, source) in vSources.enumerated() {
            let number = uSources.count + index + 1
            v += try await CurveInput.loops([source], holes: .refuse("Curve \(number) has holes; a network curve is one loop."),
                                            kernel: kernel, tag: context.tag)
        }
        let surface = try await kernel.networkSurface(u: u, v: v, tolerance: try inputs.number("tolerance"), tag: context.tag)
        return NodeOutputs(["surface": .solid(surface)])
    }
}
