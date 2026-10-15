import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation

/// Finds walls thinner than a minimum (implicit spec §3.6, §4.6): the mesh comes out as it went in, with the thin regions
/// highlighted in the viewport and a warning that counts the places and names the thinnest. On a preview mesh the warning says it is
/// approximate.
public enum CheckThinWallsNode: NodeDefinition {
    public static let typeID = "creator.checkThinWalls"
    public static let displayName = "Check Thin Walls"
    public static let category = NodeCategory.mesh
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
        let (mesh, warnings) = try await MeshInput.mesh(try inputs.scalar("mesh"), socket: "mesh", context: context)
        let result = try ThinWallCheck.run(mesh, minimum: minimum)
        let limit = minimum.millimetreText(locale: .messages)
        guard let thinnest = result.thinnest, !result.triangles.isEmpty else {
            let clear = mesh.checked(highlights: [], facts: [PayloadFact("Thin walls", "none under \(limit) mm")])
            return NodeOutputs(["mesh": .mesh(clear)], warnings: warnings)
        }
        let highlight = MeshHighlight(triangles: result.triangles, label: "Walls thinner than \(limit) mm")
        let flagged = mesh.checked(highlights: [highlight],
                                   facts: [PayloadFact("Thinnest wall", "\(thinnest.millimetreText(locale: .messages)) mm")])
        let text = CheckWording.thinWalls(minimum: minimum, places: result.places, thinnest: thinnest, label: CheckWording.label(for: mesh))
        return NodeOutputs(["mesh": .mesh(flagged)], warnings: warnings + [text])
    }
}
