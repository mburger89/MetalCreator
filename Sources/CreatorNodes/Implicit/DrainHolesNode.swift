import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// Drills drain holes (implicit spec §3.6): the implicit solid minus a cylinder per hole. At Points drills from each of `points` along
/// `direction` until the hole leaves the part. Automatic finds the enclosed voids on a coarse grid (the trapped-volume test, run on the
/// implicit itself) and drills from the lowest point of each along `direction` to the outside.
public enum DrainHolesNode: NodeDefinition {
    public static let typeID = "creator.drainHoles"
    public static let displayName = "Drain Holes"
    public static let category = NodeCategory.implicit
    public static let inputs = [
        SocketSpec("implicit", .implicit),
        SocketSpec("diameter", .number, defaultValue: .number(2), unit: .millimetres, range: 0.1...50),
        SocketSpec("direction", .vector, defaultValue: .vector(Vector3(0, 0, -1))),
        SocketSpec("mode", .integer, defaultValue: .integer(DrainMode.automatic.rawValue)),
        SocketSpec("points", .vector, access: .list, optional: true),
    ]
    public static let outputs = [SocketSpec("implicit", .implicit)]
    public static let inspector = [
        InspectorSection(title: "Drain Holes", controls: [
            .segmented("mode", options: DrainMode.options), .number("diameter"), .vector("direction"),
            .note("Automatic drills from the lowest point of every enclosed void. At Points drills from the points wired in."),
        ]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let solid = try inputs.implicitSolid("implicit")
        let diameter = try inputs.number("diameter")
        guard diameter.isFinite, diameter >= 0.1 else { throw NodeError.invalidValue("“diameter” must be at least 0.1 mm.") }
        guard let direction = try inputs.vector("direction").normalized, direction.isFinite else {
            throw NodeError.invalidValue("“direction” can't be zero.")
        }
        let mode = DrainMode(rawValue: try inputs.choice("mode", options: DrainMode.options)) ?? .automatic
        guard DrainHoles.hasFiniteBounds(solid) else {
            throw NodeError.invalidValue("The shape has no finite size to drill into. Give it a bounded shape.")
        }
        var warnings = CheckWording.smallHole(diameter: diameter, seen: OccupancyGrid.smallestSeenHole(forSize: solid.bounds.size))
        var points: [Vector3]
        switch mode {
        case .atPoints:
            points = inputs.has("points") ? try inputs.vectors("points") : []
            guard !points.isEmpty else { throw NodeError.invalidValue("Connect points to “points”, or choose Automatic.") }
        case .automatic:
            let selection = await ImplicitEvaluators.make(for: solid, choice: context.implicitEngine)
            warnings += selection.warning.map { [$0] } ?? []
            do {
                points = try await DrainHoles.drainPoints(of: solid, direction: direction, using: selection.evaluator)
            } catch let error as ImplicitMeshingError {
                throw NodeError.invalidValue(error.userMessage)
            }
        }
        let result = DrainHoles.drilled(solid, at: points, diameter: diameter, direction: direction)
        return NodeOutputs(["implicit": .implicit(result.reference)], warnings: warnings)
    }
}
