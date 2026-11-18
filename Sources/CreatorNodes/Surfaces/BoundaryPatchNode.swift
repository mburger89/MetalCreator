import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A single face filling a closed boundary of curves and picked sheet edges, optionally through points and curves inside it
/// and tangent or curvature continuous to the sheet its edges belong to (NURBS spec).
public enum BoundaryPatchNode: NodeDefinition {
    public static let typeID = "creator.boundaryPatch"
    public static let displayName = "Boundary Patch"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Make"
    public static let maximumPoints = 1_000
    public static let continuityOptions = ["G0", "G1", "G2"]
    public static let boundaryRefusal = "Wire the curves or edges that bound the patch."
    public static let inputs = [
        SocketSpec("curves", .curve, access: .list, optional: true),
        SocketSpec("edges", .edgeSet, optional: true),
        SocketSpec("points", .vector, access: .list, optional: true),
        SocketSpec("interior curves", .curve, access: .list, optional: true),
        SocketSpec("continuity", .integer, defaultValue: .integer(1)),
    ]
    public static let outputs = [SocketSpec("surface", .solid)]
    public static let inspector = [
        InspectorSection(title: "Boundary Patch", controls: [.segmented("continuity", options: continuityOptions)]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let sources = inputs.has("curves") ? try inputs.curves("curves") : []
        let wiredEdges = inputs.has("edges") ? try inputs.edgeSet("edges") : nil
        let edgeSet = wiredEdges?.edges.isEmpty == false ? wiredEdges : nil
        guard !sources.isEmpty || edgeSet != nil else { throw NodeError.invalidValue(boundaryRefusal) }
        let points = inputs.has("points") ? try inputs.list("points").map { scalar -> Vector3 in
            guard case .vector(let point) = scalar else { throw NodeError.typeMismatch("points", expected: .vector) }
            return point
        } : []
        guard points.count <= maximumPoints else {
            throw NodeError.invalidValue("A patch takes at most \(maximumPoints.display) points.")
        }
        let interiorSources = inputs.has("interior curves") ? try inputs.curves("interior curves") : []
        let continuity = try inputs.choice("continuity", options: continuityOptions)
        let level = PatchContinuity(rawValue: continuity) ?? .g1

        var curves: [Curve] = []
        for (index, source) in sources.enumerated() {
            let refusal = "Profile \(index + 1) has holes; a patch boundary is one loop."
            curves += try await CurveInput.loops([source], holes: .refuse(refusal), kernel: kernel, tag: context.tag)
        }
        let interior = try await CurveInput.loops(interiorSources, holes: .all, kernel: kernel, tag: context.tag)
        let boundary = PatchBoundary(curves: curves, edges: edgeSet?.edges ?? [], part: edgeSet?.solid)
        let result = try await kernel.boundaryPatch(boundary, interior: points, interior: interior, continuity: level,
                                                    tag: context.tag)
        return NodeOutputs(["surface": .solid(result.sheet)], warnings: result.warnings)
    }
}
