import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation

/// Finds walls thinner than a minimum (implicit spec §3.6, §4.6): the mesh comes out as it went in, with the thin regions
/// highlighted in the viewport and a warning that counts the places and names the thinnest. On a preview mesh the warning says it is
/// approximate. While an export streams, the check runs on a copy of the part in memory (at the export resolution when that fits in
/// 2,000,000 triangles, else coarser, and the warning says so) and the stream goes on to the file unchanged.
public enum CheckThinWallsNode: NodeDefinition {
    public static let typeID = "creator.checkThinWalls"
    public static let displayName = "Check Thin Walls"
    public static let category = NodeCategory.mesh
    public static let readsMeshQuality = true
    public static let defaultMinimum = 0.4
    public static let minimumMinimum = 0.01
    public static let inputs = [
        SocketSpec("mesh", .mesh),
        SocketSpec("minimum", .number, defaultValue: .number(defaultMinimum), unit: .millimetres, range: minimumMinimum...5),
    ]
    public static let outputs = [SocketSpec("mesh", .mesh)]
    public static let inspector = [
        InspectorSection(title: "Check Thin Walls", controls: [
            .number("minimum"),
            .note("Regions thinner than the minimum are highlighted."),
        ]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let minimum = try inputs.number("minimum")
        guard minimum.isFinite, minimum >= minimumMinimum else {
            throw NodeError.invalidValue("“minimum” must be at least \(minimumMinimum.millimetreText(locale: .messages)) mm.")
        }
        let work = try await MeshInput.checkable(try inputs.scalar("mesh"), socket: "mesh", context: context)
        let result = try await ThinWallCheck.runConcurrently(work.mesh, minimum: minimum)
        let limit = minimum.millimetreText(locale: .messages)
        var found = work.warnings
        var facts = [PayloadFact("Thin walls", "none under \(limit) mm")]
        var highlights: [MeshHighlight] = []
        if let thinnest = result.thinnest, !result.triangles.isEmpty {
            highlights = [MeshHighlight(triangles: result.triangles, label: "Walls thinner than \(limit) mm")]
            facts = [PayloadFact("Thinnest wall", "\(thinnest.millimetreText(locale: .messages)) mm")]
            found.append(CheckWording.thinWalls(minimum: minimum, places: result.places, thinnest: thinnest, label: work.label))
        }
        // While an export streams, the stream itself goes on; the checked copy only had to say what it found.
        if let stream = work.stream { return NodeOutputs(["mesh": .mesh(stream)], warnings: found) }
        return NodeOutputs(["mesh": .mesh(work.mesh.checked(highlights: highlights, facts: facts))], warnings: found)
    }
}
