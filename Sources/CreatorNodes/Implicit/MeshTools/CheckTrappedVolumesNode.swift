import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation

/// Finds the pockets a part encloses (implicit spec §3.6, §4.6): empty space the outside cannot reach, which powder, resin or support
/// would be trapped in. The mesh comes out as it went in, the walls around each void highlighted, and a warning counts them. On a
/// preview mesh the warning says it is approximate.
public enum CheckTrappedVolumesNode: NodeDefinition {
    public static let typeID = "creator.checkTrappedVolumes"
    public static let displayName = "Check Trapped Volumes"
    public static let category = NodeCategory.mesh
    public static let inputs = [SocketSpec("mesh", .mesh)]
    public static let outputs = [SocketSpec("mesh", .mesh)]
    public static let inspector = [
        InspectorSection(title: "Check Trapped Volumes", controls: [
            .note("Enclosed voids are highlighted. Drain Holes can drill them out."),
        ]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let (mesh, warnings) = try await MeshInput.mesh(try inputs.scalar("mesh"), socket: "mesh", context: context)
        let result: TrappedVolumeCheck.Result
        do {
            result = try TrappedVolumeCheck.run(mesh)
        } catch let error as MeshDistanceError {
            throw NodeError.invalidValue(error.userMessage.replacing("This solid", with: "This mesh"))
        }
        let count = result.voidCount.formatted(.number.locale(.messages))
        let facts = [PayloadFact("Enclosed voids", count), PayloadFact("Grid cell", result.cell.millimetreText(locale: .messages) + " mm")]
        let coarse = CheckWording.coarseGrid(cell: result.cell)
        guard result.voidCount > 0 else {
            return NodeOutputs(["mesh": .mesh(mesh.checked(highlights: [], facts: facts))], warnings: warnings + coarse)
        }
        let highlight = MeshHighlight(triangles: result.triangles, label: "Enclosed voids")
        let flagged = mesh.checked(highlights: [highlight], facts: facts)
        let text = CheckWording.voids(result.voidCount, label: CheckWording.label(for: mesh))
        return NodeOutputs(["mesh": .mesh(flagged)], warnings: warnings + [text] + coarse)
    }
}
