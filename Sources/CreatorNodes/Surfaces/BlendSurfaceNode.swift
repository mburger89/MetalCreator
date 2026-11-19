import CreatorGraph
import CreatorKernel

/// A new sheet joining an edge of each of two bodies, tangent or curvature continuous to each (NURBS spec, NS-4, R10). Nothing is sewn
/// into either body. A G2 side built while a slider or handle is dragged is G1 and says nothing (R11).
public enum BlendSurfaceNode: NodeDefinition {
    public static let typeID = "creator.blendSurface"
    public static let displayName = "Blend Surface"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Edit"
    /// The choices of `continuity` and `other continuity`, in option order.
    public static let continuityOptions = ["G1", "G2"]
    public static let inputs = [
        SocketSpec("edges", .edgeSet),
        SocketSpec("other edges", .edgeSet),
        SocketSpec("continuity", .integer, defaultValue: .integer(0)),
        SocketSpec("other continuity", .integer, defaultValue: .integer(0)),
        SocketSpec("bulge", .number, defaultValue: .number(1), range: 0.1...2),
        SocketSpec("other bulge", .number, defaultValue: .number(1), range: 0.1...2),
    ]
    public static let outputs = [SocketSpec("surface", .solid)]
    public static let inspector = [
        InspectorSection(title: "Blend Surface", controls: [
            .segmented("continuity", options: continuityOptions), .slider("bulge"),
            .segmented("other continuity", options: continuityOptions), .slider("other bulge"),
        ]),
        InspectorSection(title: "Edge", controls: [
            .ruleSummary("edges"), .button(title: "Pick edge in view…", action: .pickEdgesInView),
        ]),
        InspectorSection(title: "Other edge", controls: [
            .ruleSummary("other edges"), .button(title: "Pick other edge in view…", action: .pickOtherEdgesInView),
        ]),
    ]
    public static let readsScrubbing = true

    /// Only a blend with a G2 side (or one whose sides are wired) builds differently during a drag.
    public static func readsScrubbing(for node: Node) -> Bool {
        for name: SocketName in ["continuity", "other continuity"] {
            if case .integer(let grade)? = node.inputValues[name], grade != 1 { continue }
            return true
        }
        return false
    }

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let first = try inputs.edgeSet("edges")
        let second = try inputs.edgeSet("other edges")
        guard first.edges.count == 1 else {
            throw NodeError.invalidValue("Blend Surface takes one edge on each side; “edges” gives \(first.edges.count.display).")
        }
        guard second.edges.count == 1 else {
            throw NodeError.invalidValue(
                "Blend Surface takes one edge on each side; “other edges” gives \(second.edges.count.display).")
        }
        func grade(_ name: SocketName) throws -> PatchContinuity {
            try inputs.choice(name, options: continuityOptions) == 1 && !context.isScrubbing ? .g2 : .g1
        }
        let result = try await kernel.blendSurface(
            SurfaceBlendEnd(body: first.solid, edge: first.edges[0], continuity: try grade("continuity"),
                            bulge: try inputs.number("bulge")),
            SurfaceBlendEnd(body: second.solid, edge: second.edges[0], continuity: try grade("other continuity"),
                            bulge: try inputs.number("other bulge")),
            tag: context.tag)
        return NodeOutputs(["surface": .solid(result)])
    }
}
