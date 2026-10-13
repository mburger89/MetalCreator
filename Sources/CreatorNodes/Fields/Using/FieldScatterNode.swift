import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Scatters points over a flat region where a field says (fields spec §3.3): variable-radius Poisson-disk sampling
/// (`PoissonScatter`), the spacing at a point `minSpacing + clamp(field, 0, 1) × (maxSpacing − minSpacing)`, so no two points
/// are ever closer than `minSpacing`, and a field of 0 gives the densest scatter and 1 the sparsest. A layout node, in 7a's
/// rules: a list in any single-valued input is refused before it runs (`singleValuesRefusal`), and more than 2,000 points
/// refuses (`PatternLimit`).
///
/// The region is a picked flat face of `solid` (the `face` setting, read as Face Pattern reads it: holes and the margin
/// respected) or a `profile` on its plane (its holes respected too). The output is one flat list of placements on the region's
/// plane, facing its normal with the plane's x axis, numbered in the order they were generated. Changing the field, the
/// region or the seed renumbers them (decision D7): a pick on a scattered instance then warns "Instance {n} no longer
/// exists" by the existing rule, and the inspector's note says so.
public enum FieldScatterNode: NodeDefinition {
    public static let typeID = "creator.fieldScatter"
    public static let displayName = "Field Scatter"
    public static let category = NodeCategory.fields
    public static let inputs = [
        SocketSpec("solid", .solid, optional: true),
        SocketSpec("profile", .profile, optional: true),
        SocketSpec("field", .field, defaultValue: .number(0.5)),
        SocketSpec("minSpacing", .number, defaultValue: .number(6), unit: .millimetres, range: 0.5...200),
        SocketSpec("maxSpacing", .number, defaultValue: .number(12), unit: .millimetres, range: 0.5...200),
        SocketSpec("margin", .number, defaultValue: .number(3), unit: .millimetres, range: 0...50),
        SocketSpec("seed", .integer, defaultValue: .integer(0)),
    ]
    public static let outputs = [SocketSpec("placements", .plane)]
    public static var singleValuesRefusal: String? { LayoutChecks.singleValues(displayName) }

    /// The inspector's note (fields spec §4).
    public static let help = "Points renumber when the field or region changes; a pick on a scattered instance may stop matching."
    public static let inspector = [
        InspectorSection(title: "Spacing", controls: [.slider("minSpacing"), .slider("maxSpacing"), .slider("margin")]),
        InspectorSection(title: "Density", controls: [.number("field")]),
        InspectorSection(title: "Random", controls: [.integer("seed")]),
        InspectorSection(title: "Note", controls: [.note(help)]),
    ]

    /// The most points the search makes before it stops and says "more than": four times the limit, so the refusal usually
    /// names the real count and a typo ("spacing 0.01") still answers at once.
    public static let ceiling = 4 * PatternLimit.maximumInstances

    public static let noRegion = "Field Scatter needs a region: wire a solid and pick one of its flat faces, or wire a profile."
    public static let bothRegions = "Wire either a solid with a picked face or a profile, not both."
    public static let noRoom = "Field Scatter found no room for a point: the region is smaller than its margin, "
        + "or the margin leaves none of it."
    public static let notANumber = "Field Scatter's field has no value at some points of the region: check the field's inputs."

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let minSpacing = try inputs.number("minSpacing")
        guard minSpacing.isFinite, minSpacing > 0 else { throw NodeError.invalidValue("“minSpacing” must be greater than 0 mm.") }
        let maxSpacing = try inputs.number("maxSpacing")
        guard maxSpacing.isFinite, maxSpacing >= minSpacing else {
            throw NodeError.invalidValue("“maxSpacing” can't be less than “minSpacing” (\(minSpacing.display) mm).")
        }
        let margin = try LayoutChecks.number(try inputs.number("margin"), "margin")
        let seed = try inputs.integer("seed")
        let field = try inputs.field("field")
        let (region, surface, warnings) = try self.region(inputs, context: context)

        let outcome = try await PoissonScatter(region: region, margin: margin, minSpacing: minSpacing, maxSpacing: maxSpacing,
                                               seed: seed, ceiling: ceiling).scatter { local in
            let values = try await FieldSampler.sample(field, at: local.map(surface.point), kernel: kernel,
                                                       cache: context.fieldDistances)
            guard values.allSatisfy(\.isFinite) else { throw NodeError.invalidValue(notANumber) }
            return values.map { minSpacing + min(max($0, 0), 1) * (maxSpacing - minSpacing) }
        }
        if outcome.points.count > PatternLimit.maximumInstances {
            let count = outcome.reachedCeiling ? "more than \(ceiling.display)" : outcome.points.count.display
            throw NodeError.invalidValue("Field Scatter would place \(count) points; patterns are limited to "
                + "\(PatternLimit.maximumInstances.display) instances.")
        }
        guard !outcome.points.isEmpty else { throw NodeError.invalidValue(noRoom) }
        let placements = outcome.points.map {
            LayoutChecks.placement(surface.point($0), normal: surface.normal, xAxis: surface.xAxis)
        }
        return NodeOutputs(trees: ["placements": .list(placements)], warnings: warnings)
    }

    /// A flat region's plane: where its 2D coordinates stand in space.
    private struct Surface {
        let origin: Vector3
        let normal: Vector3
        let xAxis: Vector3
        let yAxis: Vector3

        func point(_ local: Vector2) -> Vector3 { origin + xAxis * local.x + yAxis * local.y }
    }

    /// The region the inputs name, where it lies, and the warnings its face pick earns.
    private static func region(_ inputs: NodeInputs, context: EvalContext) throws -> (FaceRegion, Surface, [String]) {
        let (hasSolid, hasProfile) = (inputs.has("solid"), inputs.has("profile"))
        guard hasSolid || hasProfile else { throw NodeError.invalidValue(noRegion) }
        guard !(hasSolid && hasProfile) else { throw NodeError.invalidValue(bothRegions) }
        if hasProfile {
            let profile = try inputs.profile("profile")
            guard profile.isClosed else { throw NodeError.invalidValue("“profile” isn't a closed outline.") }
            let plane = profile.plane
            return (.outline(of: profile), Surface(origin: plane.origin, normal: plane.normal, xAxis: plane.xAxis, yAxis: plane.yAxis), [])
        }
        do {
            let solid = try inputs.solid("solid")
            let (face, warnings) = try FacePatternNode.pickedFace(of: solid, context: context)
            let frame = try FacePatternNode.Frame(of: face)
            let region = try FaceRegion.outline(of: face, in: solid.topology, origin: frame.origin, xAxis: frame.xAxis,
                                                yAxis: frame.yAxis)
            return (region, Surface(origin: frame.origin, normal: frame.normal, xAxis: frame.xAxis, yAxis: frame.yAxis), warnings)
        } catch let error as NodeError {
            // Face Pattern words its refusals for itself ("Face Pattern works on flat faces for now."); say them as this node.
            guard case .invalidValue(let text) = error else { throw error }
            throw NodeError.invalidValue(text.replacing(FacePatternNode.displayName, with: displayName))
        }
    }
}
