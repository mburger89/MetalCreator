import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A field of the distance to something (fields spec §3.1): a point, the edges of an edge set, a profile's loops, faces or a
/// solid, in millimetres. To a solid it is signed (negative inside) unless Unsigned is chosen; to anything else it is unsigned
/// whichever mode is set, so the default Signed never refuses an edge set. The node only builds the field: no kernel call
/// happens until a node samples it (`FieldSampler`), which asks the kernel once per batch and caches the answer.
public enum DistanceFieldNode: NodeDefinition {
    public static let typeID = "creator.distanceField"
    public static let displayName = "Distance Field"
    public static let category = NodeCategory.fields
    public static let modes = ["Unsigned", "Signed"]
    public static let inputs = [
        SocketSpec("target", .any, optional: true),
        SocketSpec("mode", .integer, defaultValue: .integer(1)),
    ]
    public static let outputs = [SocketSpec("field", .field)]
    public static let inspector = [InspectorSection(title: "Distance", controls: [.segmented("mode", options: modes)])]

    private static let wiring = "wire a point, edges, a profile, faces or a solid."

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        guard inputs.has("target") else { throw NodeError.invalidValue("Distance Field needs a target: \(wiring)") }
        let signed = try inputs.choice("mode", options: modes) == 1
        let source = try source(of: try inputs.scalar("target"))
        try checkSelection(source)
        return NodeOutputs(["field": .field(.distance(source, signed: signed))])
    }

    /// What the wired value is measured as, or why it can't be.
    private static func source(of target: Scalar) throws -> Field.DistanceSource {
        switch target {
        case .vector(let point):
            guard point.isFinite else { throw NodeError.invalidValue("Distance Field's point isn't a finite position.") }
            return .point(point)
        case .profile(let profile):
            guard !profile.outer.isEmpty else { throw NodeError.invalidValue("Distance Field's profile has no outline.") }
            return .profile(profile)
        case .edgeSet(let set):
            return .kernel(.edges(set))
        case .faceSet(let set):
            return .kernel(.faces(set))
        case .solid(let solid):
            return .kernel(.solid(solid))
        default:
            throw NodeError.invalidValue("Distance Field can't measure from \(target.type.indefiniteName): \(wiring)")
        }
    }

    /// An empty selection is this node's error; an edge or face the solid lacks is the kernel's wording.
    private static func checkSelection(_ source: Field.DistanceSource) throws {
        switch source {
        case .kernel(.edges(let set)) where set.edges.isEmpty:
            throw NodeError.invalidValue("Distance Field's edges are empty: there is nothing to measure from.")
        case .kernel(.faces(let set)) where set.faces.isEmpty:
            throw NodeError.invalidValue("Distance Field's faces are empty: there is nothing to measure from.")
        case .kernel(let target):
            try target.validate()
        case .point, .profile:
            return
        }
    }
}
