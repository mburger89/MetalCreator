import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation

/// Straight edges parallel to a direction, within an angle tolerance (spec §7.1, Selection).
/// Either sense counts (|cos| is compared), and only lines qualify: a circle edge's `direction`
/// is its axis, so without the `kind == .line` check every hole rim would match "parallel to Z".
/// The slider stops at 45° but the node accepts up to 90° (every line then matches), for a wired value.
public enum EdgesByDirectionNode: NodeDefinition {
    public static let typeID = "creator.edgesByDirection"
    public static let displayName = "Edges by Direction"
    public static let category = NodeCategory.selection
    public static let inputs = [
        SocketSpec("solid", .solid),
        SocketSpec("direction", .vector, defaultValue: .vector(.unitZ)),
        SocketSpec("tolerance", .number, defaultValue: .number(1), unit: .degrees, range: 0...45),
    ]
    public static let outputs = [SocketSpec("edges", .edgeSet)]
    public static let inspector = [InspectorSection(title: "Direction", controls: [
        .vector("direction"), .slider("tolerance"), .ruleSummary("edges"),
    ]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let solid = try inputs.solid("solid")
        guard let axis = try inputs.vector("direction").normalized else {
            throw NodeError.invalidValue("The direction can't be zero.")
        }
        let tolerance = try inputs.number("tolerance")
        guard tolerance.isFinite, (0...90).contains(tolerance) else {
            throw NodeError.invalidValue("The angle tolerance must be between 0° and 90°.")
        }
        let threshold = cos(Angle.degrees(tolerance).radians) - 1e-12
        let matches = EdgeSelection.candidates(solid).filter { edge in
            guard edge.kind == .line, let direction = edge.direction?.normalized else { return false }
            return abs(direction.dot(axis)) >= threshold
        }
        return EdgeSelection.outputs(solid, matches.map(\.id))
    }
}
