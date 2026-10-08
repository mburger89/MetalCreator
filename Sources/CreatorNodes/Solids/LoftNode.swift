import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A solid through a list of closed sections, in list order (spec §7.1, Solids). Wire a
/// broadcast profile in, for example a Circle over several planes. Sections must have the
/// same number of segments; resampling is deferred, so a mismatch is explained instead.
public enum LoftNode: NodeDefinition {
    public static let typeID = "creator.loft"
    public static let displayName = "Loft"
    public static let category = NodeCategory.solid
    public static let inputs = [
        SocketSpec("sections", .profile, access: .list),
        SocketSpec("ruled", .bool, defaultValue: .bool(false)),
    ]
    public static let outputs = [SocketSpec("solid", .solid)]
    public static let inspector = [InspectorSection(title: "Loft", controls: [.toggle("ruled", label: "Straight sides (ruled)")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let sections = try inputs.profiles("sections")
        guard sections.count >= 2 else {
            throw NodeError.invalidValue("A loft needs at least two sections. Wire in a list of profiles, such as a Circle broadcast over several planes.")
        }
        let counts = sections.map(\.segments.count)
        if let mismatch = counts.indices.first(where: { counts[$0] != counts[0] }) {
            throw NodeError.invalidValue("Loft sections need the same number of segments, but section 1 has \(counts[0]) and section \(mismatch + 1) has \(counts[mismatch]). Loft between profiles of the same kind, such as two rectangles, two circles, or polygons with the same number of sides.")
        }
        let solid = try await kernel.loft(sections, ruled: try inputs.bool("ruled"), tag: context.tag)
        return NodeOutputs(["solid": .solid(solid)])
    }
}
