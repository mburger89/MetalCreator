import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Reads the cutter of Trim Surface and Split Surface (NS-4, R7): cutting curves with a projection, or a cutting body.
enum TrimCutterInput {
    static let projectionOptions = ["Along Direction", "Along Normals"]
    static let bothRefusal = "takes cutting curves or a cutting body, not both."
    static let neitherRefusal = "Wire curves or a body to cut with."
    static let cutterInputs = [
        SocketSpec("curves", .curve, access: .list, optional: true),
        SocketSpec("cutter", .solid, optional: true),
        SocketSpec("projection", .integer, defaultValue: .integer(0)),
        SocketSpec("direction", .vector, defaultValue: .vector(Vector3(0, 0, 1))),
    ]

    /// The inspector controls the cutter earns: the projection and, along a direction, the direction.
    static func controls(for node: Node) -> [InspectorControl] {
        var controls: [InspectorControl] = [.segmented("projection", options: projectionOptions)]
        if projection(of: node) == .alongDirection { controls.append(.vector("direction")) }
        return controls
    }

    static func projection(of node: Node) -> TrimProjection {
        if case .integer(let stored)? = node.inputValues["projection"], let kind = TrimProjection(rawValue: stored) { return kind }
        return .alongDirection
    }

    static func read(_ inputs: NodeInputs, node: String, kernel: any Kernel, tag: NodeTag) async throws -> TrimCutter {
        let sources = inputs.has("curves") ? try inputs.curves("curves") : []
        let hasBody = inputs.has("cutter")
        if !sources.isEmpty && hasBody { throw NodeError.invalidValue("\(node) \(bothRefusal)") }
        if hasBody { return .body(try inputs.solid("cutter")) }
        guard !sources.isEmpty else { throw NodeError.invalidValue(neitherRefusal) }
        let curves = try await CurveInput.loops(sources, holes: .all, kernel: kernel, tag: tag)
        let projection = TrimProjection(rawValue: try inputs.choice("projection", options: projectionOptions)) ?? .alongDirection
        return .curves(curves, projection: projection, direction: try inputs.vector("direction"))
    }
}
