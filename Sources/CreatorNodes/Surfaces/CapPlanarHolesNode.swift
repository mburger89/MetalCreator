import CreatorGraph
import CreatorKernel

/// The flat holes of a sheet closed with caps, a solid when nothing stays open (NS-5, R12).
public enum CapPlanarHolesNode: NodeDefinition {
    public static let typeID = "creator.capPlanarHoles"
    public static let displayName = "Cap Planar Holes"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Solids"
    public static let factsTitle = "Caps"
    public static let showsFreeEdges = true
    public static let inputs = [SocketSpec("surface", .solid)]
    public static let outputs = [SocketSpec("solid", .solid)]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let capped = try await kernel.cappingPlanarHoles(try inputs.solid("surface"), tag: context.tag)
        var warnings: [String] = []
        if capped.notFlat == 1 {
            warnings.append("1 hole isn't flat, so it was left open.")
        } else if capped.notFlat > 1 {
            warnings.append("\(capped.notFlat.display) holes aren't flat, so they were left open.")
        }
        let free = capped.body.topology.edges.filter(\.isBoundary).count
        if free > 0 {
            warnings.append("The capped surface still has \(BackToSolidsWording.free(free)), so it stays open.")
        }
        var outputs = NodeOutputs(["solid": .solid(capped.body)], warnings: warnings)
        outputs.facts = [PayloadFact("Holes capped", capped.capped.display), PayloadFact("Left open", capped.notFlat.display)]
        return outputs
    }
}
