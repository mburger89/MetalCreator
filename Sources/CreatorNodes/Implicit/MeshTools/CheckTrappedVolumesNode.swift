import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation

/// Finds the pockets a part encloses (implicit spec §3.6, §4.6): empty space the outside cannot reach, which powder, resin or support
/// would be trapped in. The mesh comes out as it went in, the walls around each void highlighted, and a warning counts them. On a
/// preview mesh the warning says it is approximate. While an export streams, the check runs on a copy of the part in memory (see
/// Check Thin Walls) and the stream goes on to the file unchanged.
public enum CheckTrappedVolumesNode: NodeDefinition {
    public static let typeID = "creator.checkTrappedVolumes"
    public static let displayName = "Check Trapped Volumes"
    public static let category = NodeCategory.mesh
    public static let readsMeshQuality = true
    public static let inputs = [SocketSpec("mesh", .mesh)]
    public static let outputs = [SocketSpec("mesh", .mesh)]
    public static let inspector = [
        InspectorSection(title: "Check Trapped Volumes", controls: [
            .note("Enclosed voids are highlighted. Drain Holes can drill them out."),
        ]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let work = try await MeshInput.checkable(try inputs.scalar("mesh"), socket: "mesh", context: context)
        let result: TrappedVolumeCheck.Result
        do {
            result = try await TrappedVolumeCheck.runConcurrently(work.mesh)
        } catch let error as MeshDistanceError {
            throw NodeError.invalidValue(error.userMessage.replacing("This solid", with: "This mesh"))
        }
        let count = result.voidCount.formatted(.number.locale(.messages))
        var warnings = work.warnings
        var highlights: [MeshHighlight] = []
        if result.voidCount > 0 {
            highlights = [MeshHighlight(triangles: result.triangles, label: "Enclosed voids")]
            warnings.append(CheckWording.voids(result.voidCount, label: work.label))
        }
        let cellFact = result.cell.millimetreText(locale: .messages) + " mm"
        warnings += CheckWording.coarseGrid(cell: result.cell)
        if let stream = work.stream { return NodeOutputs(["mesh": .mesh(stream)], warnings: warnings) }
        let facts = [PayloadFact("Enclosed voids", count), PayloadFact("Grid cell", cellFact)]
        let checked = work.mesh.checked(highlights: highlights, facts: facts)
        return NodeOutputs(["mesh": .mesh(checked)], warnings: warnings)
    }
}
