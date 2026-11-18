import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A sheet of one face with some of its control points moved (NURBS spec, control points). The moves are the node's
/// `NodeSetting.poleMoves`, each an offset from where the input put that pole, so editing upstream keeps them; a move whose pole is
/// gone (the net shrank) is left in the setting and warned about, never applied. The face keeps its names, so picks downstream survive.
public enum EditSurfaceNode: NodeDefinition {
    public static let typeID = "creator.editSurface"
    public static let displayName = "Edit Surface"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Make"
    public static let factsTitle = "Surface"
    public static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.poleMoves: .poleMoves([])]
    public static let inputs = [SocketSpec("surface", .solid)]
    public static let outputs = [SocketSpec("surface", .solid)]
    public static let inspector = [InspectorSection(title: "Edit Surface", controls: [
        .button(title: "Edit Control Points", action: .editControlPoints),
    ]),
    ]
    /// A drag step skips the fold query (the dominant cost of a step on a big net); the evaluation after the drag ends asks it and
    /// warns. A node with no moves has nothing to fold, so it keeps its cache entry across a drag elsewhere.
    public static func readsScrubbing(for node: Node) -> Bool {
        guard let moves = node.inputValues[NodeSetting.poleMoves]?.poleMoves else { return false }
        return !moves.isEmpty
    }

    public static let foldWarning = "The moved surface folds over itself; zebra stripes, thickening and offsets will misbehave there."

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let surface = try inputs.solid("surface")
        let net = try await kernel.controlNet(of: surface)
        let moves = context.node.inputValues[NodeSetting.poleMoves]?.poleMoves ?? []
        let fitting = moves.filter { $0.index.i < net.surface.uCount && $0.index.j < net.surface.vCount }
        var warnings: [String] = []
        if fitting.count < moves.count {
            let place = "the surface's \(net.surface.uCount.display) × \(net.surface.vCount.display) net"
            warnings.append(ControlNetFacts.staleWarning(count: moves.count - fitting.count, place: place))
        }
        var result = surface
        if !fitting.isEmpty {
            result = try await kernel.movingPoles(of: surface, by: fitting)
            if !context.isScrubbing, try await kernel.folds(result) { warnings.append(foldWarning) }
        }
        var outputs = NodeOutputs(["surface": .solid(result)], warnings: warnings)
        outputs.facts = ControlNetFacts.surface(net.surface, kind: net.convertedFrom)
        return outputs
    }
}
