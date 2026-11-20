import CreatorGraph
import CreatorKernel

/// Every face of the wired bodies sewn together at a tolerance (NS-5, R6): closed shells become solids, the rest stay sheets.
public enum SewNode: NodeDefinition {
    public static let typeID = "creator.sew"
    public static let displayName = "Sew"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Solids"
    public static let factsTitle = "Sew"
    public static let showsFreeEdges = true
    public static let inputs = [
        SocketSpec("bodies", .solid, access: .list),
        SocketSpec("tolerance", .number, defaultValue: .number(0.01), unit: .millimetres, range: 0.0001...1),
    ]
    public static let outputs = [SocketSpec("solid", .solid)]
    public static let inspector = [InspectorSection(title: "Sew", controls: [.slider("tolerance")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let bodies = try inputs.solids("bodies")
        let sewn = try await kernel.sewn(bodies, tolerance: try inputs.number("tolerance"), tag: context.tag)
        let free = sewn.body.topology.edges.filter(\.isBoundary).count
        var warnings: [String] = []
        if free > 0 {
            warnings.append("The sewn surface still has \(BackToSolidsWording.free(free)), so it stays open.")
        }
        if sewn.unclosable == 1 {
            warnings.append("A closed shell couldn't be made into a valid solid, so it stays a surface.")
        } else if sewn.unclosable > 1 {
            warnings.append("\(sewn.unclosable.display) closed shells couldn't be made into valid solids, so they stay surfaces.")
        }
        var outputs = NodeOutputs(["solid": .solid(sewn.body)], warnings: warnings)
        outputs.facts = [
            PayloadFact("Result", BackToSolidsWording.result(solids: sewn.solids, sheets: sewn.sheets)),
            PayloadFact("Free edges", free.display),
            PayloadFact("Faces", sewn.body.topology.faces.count.display),
        ]
        return outputs
    }
}

/// The sentences the back-to-solids nodes share.
enum BackToSolidsWording {
    /// "8 free edges", "1 free edge".
    static func free(_ count: Int) -> String { count == 1 ? "1 free edge" : "\(count.display) free edges" }

    /// "1 solid", "2 sheets", "1 solid and 1 sheet": solids first, a zero count left out.
    static func result(solids: Int, sheets: Int) -> String {
        var parts: [String] = []
        if solids > 0 { parts.append(solids == 1 ? "1 solid" : "\(solids.display) solids") }
        if sheets > 0 { parts.append(sheets == 1 ? "1 sheet" : "\(sheets.display) sheets") }
        return parts.isEmpty ? "Nothing" : parts.joined(separator: " and ")
    }
}
