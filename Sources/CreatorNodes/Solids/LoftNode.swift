import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A solid through a list of closed sections, in list order (spec §7.1, Solids). Wire a
/// broadcast profile in, for example a Circle over several planes. Sections must have the
/// same number of segments; resampling is deferred, so a mismatch is explained instead. Sections with holes are
/// refused first (the kernels don't loft them yet).
public enum LoftNode: NodeDefinition {
    public static let typeID = "creator.loft"
    public static let displayName = "Loft"
    public static let category = NodeCategory.solid
    public static let inputs = [
        SocketSpec("sections", .profile, access: .list),
        SocketSpec("ruled", .bool, defaultValue: .bool(false)),
    ] + LoftEndSetup.sockets
    public static let typeVersion = 2
    public static let outputs = [SocketSpec("solid", .solid)]
    private static let base = InspectorSection(title: "Loft", controls: [.toggle("ruled", label: "Straight sides (ruled)")])
    public static let inspector = [base]

    /// The Start and End sections show a continuity only for an end that has a face, and a weight only for Tangent and Curvature.
    public static func inspector(for node: Node) -> [InspectorSection] { [base] + LoftEndSetup.inspector(for: node) }

    /// A loft saved as version 1 has no faces, so its evaluation is unchanged; the new sockets read their defaults.
    public static func migrate(_ node: Node, from version: Int) -> Node { node }

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let sections = try inputs.profiles("sections")
        let ends = try LoftEndSetup.read(inputs, context: context)
        guard sections.count + ends.count >= 2 else {
            throw NodeError.invalidValue("A loft needs at least two sections. "
                + "Wire in a list of profiles, such as a Circle broadcast over several planes.")
        }
        // Checked first: a holed section is refused whatever its segment count, so the count mismatch is not the news.
        guard sections.allSatisfy({ $0.holes.isEmpty }) else { throw KernelError.loftWithHoles }
        let counts = sections.map(\.segments.count)
        if let mismatch = counts.indices.first(where: { counts[$0] != counts[0] }) {
            throw NodeError.invalidValue(
                "Loft sections need the same number of segments, "
                    + "but section 1 has \(counts[0]) and section \(mismatch + 1) has \(counts[mismatch]). "
                    + "Loft between profiles of the same kind, such as two rectangles, two circles, "
                    + "or polygons with the same number of sides.")
        }
        let solid = try await kernel.loft(sections, ruled: try inputs.bool("ruled"), part: ends.part, start: ends.start, end: ends.end,
                                         tag: context.tag)
        return NodeOutputs(["solid": .solid(solid)], warnings: ends.warnings)
    }
}
