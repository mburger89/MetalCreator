import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation

/// Fewer triangles for the same shape (implicit spec §3.6, §4.5): flat areas collapse into big triangles by quadric error edge
/// collapse, and the surface moves by no more than `tolerance`. The result is still a closed manifold. Its triangles are shown as
/// "before → after" in the inspector. While an export streams it adds a stage to the stream instead (`MeshStage.decimate`): each
/// window is decimated as it is written, with the edge it shares with the next window held still.
public enum DecimateNode: NodeDefinition {
    public static let typeID = "creator.decimate"
    public static let displayName = "Decimate"
    public static let librarySubgroup: String? = "Tools"
    public static let category = NodeCategory.mesh
    public static let readsMeshQuality = true
    public static let defaultTolerance = 0.01
    public static let minimumTolerance = 0.0001
    public static let inputs = [
        SocketSpec("mesh", .mesh),
        SocketSpec("tolerance", .number, defaultValue: .number(defaultTolerance), unit: .millimetres, range: minimumTolerance...1),
    ]
    public static let outputs = [SocketSpec("mesh", .mesh)]
    public static let inspector = [
        InspectorSection(title: "Decimate", controls: [
            .number("tolerance"),
            .note("Flat areas become big triangles. The surface moves by no more than the tolerance."),
        ]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let tolerance = try inputs.number("tolerance")
        guard tolerance.isFinite, tolerance >= minimumTolerance else {
            let smallest = minimumTolerance.formatted(.number.precision(.fractionLength(0...4)).locale(.messages))
            throw NodeError.invalidValue("“tolerance” must be at least \(smallest) mm.")
        }
        let (value, warnings) = try await MeshInput.value(try inputs.scalar("mesh"), socket: "mesh", context: context)
        switch value {
        case .stream(let stream):
            return NodeOutputs(["mesh": .mesh(stream.appending(.decimate(tolerance: tolerance)))], warnings: warnings)
        case .mesh(let input):
            // The mesher's snap leaves vertices within a micron of each other, joined by slivers. Decimation would pinch such a sliver
            // into two vertices at one place, a mesh that is closed by index but touches itself, and the checks (which weld at 1e-6)
            // then see an edge with four faces. Welding first, at a little over the checks' distance, removes the slivers instead.
            let welded = MeshWelder.weld(positions: input.positions, triangles: input.triangles, tolerance: 2e-6)
            let output = try MeshDecimator.decimate(positions: welded.positions, triangles: welded.triangles, tolerance: tolerance)
            let (before, after) = (input.triangleCount, output.triangles.count / 3)
            let note = "\(before.formatted(.number.locale(.messages))) → \(after.formatted(.number.locale(.messages))) triangles"
            let made = input.derived(positions: output.positions, triangles: output.triangles, facts: [PayloadFact("Decimated", note)])
            return NodeOutputs(["mesh": .mesh(made)], warnings: warnings)
        }
    }
}
