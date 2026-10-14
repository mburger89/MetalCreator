import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// Where a field is below a level, as an implicit solid (implicit spec §3.1): inside where field < level, with the value
/// (field − level) ÷ max slope, so the lipschitz bound is 1 when `max slope` is honest. A max slope smaller than the field really
/// changes makes holes in the preview. The solid is clipped to a box: the field's support when it has one, else `bounds`.
public enum IsosurfaceNode: NodeDefinition {
    public static let typeID = "creator.isosurface"
    public static let displayName = "Isosurface"
    public static let category = NodeCategory.implicit
    public static let inputs = [
        SocketSpec("field", .field),
        SocketSpec("level", .number, defaultValue: .number(0)),
        SocketSpec("max slope", .number, defaultValue: .number(1), range: 0.01...100),
        SocketSpec("bounds", .any, access: .list, optional: true),
    ]
    public static let outputs = [SocketSpec("implicit", .implicit)]
    public static let inspector = [
        InspectorSection(title: "Isosurface", controls: [
            .number("level"), .number("max slope"),
            .note("A max slope smaller than the field really changes makes holes in the preview."),
        ]),
    ]
    static let boundsHelp = "Wire a solid, an implicit solid or two corner points into “bounds” to say where to fill."

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let field = try inputs.field("field")
        let (level, maxSlope) = (try inputs.number("level"), try inputs.number("max slope"))
        guard level.isFinite else { throw NodeError.invalidValue("“level” isn't a finite number.") }
        guard maxSlope.isFinite, maxSlope > 0 else { throw NodeError.invalidValue("“max slope” must be greater than 0.") }
        let region = try field.support(level: level) ?? (try bounds(of: inputs))
        guard region.size.x > 0, region.size.y > 0, region.size.z > 0 else {
            throw NodeError.invalidValue("The region to fill has no volume. \(boundsHelp)")
        }
        let setting = try await ImplicitGrading.make(field, named: "field", over: region, holdsAtZero: false, kernel: kernel,
                                                     context: context)
        var warnings = setting.warnings
        let slope = field.slopeBound.value
        if slope > maxSlope * (1 + 1e-9) {
            let (changes, given) = (slope.millimetreText(locale: .messages), maxSlope.millimetreText(locale: .messages))
            warnings.append("The field can change by \(changes) per mm, more than “max slope” (\(given)); the preview may have holes.")
        }
        let result = ImplicitSolid.isosurface(setting.grading, level: level, maxSlope: maxSlope, region: region)
        return NodeOutputs(["implicit": .implicit(result.reference)], warnings: warnings)
    }

    /// The box the `bounds` input names: a solid's, an implicit solid's, or the box between two points.
    private static func bounds(of inputs: NodeInputs) throws -> BoundingBox {
        guard inputs.has("bounds") else { throw NodeError.invalidValue("Isosurface needs a region to fill. \(boundsHelp)") }
        let items = try inputs.list("bounds")
        let boxes = try items.map { item -> BoundingBox in
            switch item {
            case .solid(let solid): return solid.bounds
            case .implicit(let reference): return reference.payload.payloadBounds
            case .vector(let point): return BoundingBox(min: point, max: point)
            default: throw NodeError.invalidValue("“bounds” takes a solid, an implicit solid or two points. \(boundsHelp)")
            }
        }
        guard let first = boxes.first else { throw NodeError.invalidValue("Isosurface needs a region to fill. \(boundsHelp)") }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }
}
