import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorSketch

/// A constraint sketch (sketcher spec §7): the `sketch` setting holds the geometry, constraints and
/// dimensions; the node solves it and outputs its closed regions as a list of profiles. Each exposed
/// dimension adds a number input named after it, whose wired value overrides the stored one, so graph
/// parameters drive the sketch. Reference dimensions come out of `measurements`, in name order.
///
/// Projected edges are re-resolved on every evaluation against the `references` solids
/// (`SketchProjections`), so a projection follows its edge when the model upstream changes.
///
/// States: an under-constrained sketch, open curves, a projection whose pick matches no edge or
/// several (suspended, not deleted) and an exposed dimension that can't be a socket are warnings; an
/// over-constrained or failed solve is an error, and the last good part stays ghosted.
public enum SketchNode: NodeDefinition {
    public static let typeID = "creator.sketch"
    public static let displayName = "Sketch"
    public static let category = NodeCategory.profile
    public static let inputs = [
        SocketSpec("plane", .plane, optional: true),
        SocketSpec("references", .solid, access: .list, optional: true),
    ]
    public static let outputs = [
        SocketSpec("profiles", .profile),
        SocketSpec("measurements", .number),
    ]
    public static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.sketch: .sketch(Sketch())]
    /// "Edit sketch" opens the sketch editor in the viewport (sketcher spec §8, S5).
    public static let inspector = [InspectorSection(title: "Sketch", controls: [.button(title: "Edit sketch", action: .editSketch)])]

    static let missingSketch = "This sketch's drawing is missing. Undo the last change, or add a new Sketch."
    static let unreadableSketch = "This sketch's drawing can't be read. Undo the last change, or add a new Sketch."
    static let wiredPlaneMissing = "Wire a plane into “plane”: this sketch is drawn on the wired plane."
    static let ignoredPlane = "“plane” is wired, but this sketch is drawn on its own plane, so the wire has no effect."

    /// True for a name an exposed dimension can't take: a fixed input, a setting or a projection setting (the sketch
    /// editor refuses it when renaming; S4 → S5 handoff).
    public static func isReservedDimensionName(_ name: String) -> Bool {
        SketchSockets.isReserved(name)
    }

    public static func inputs(for node: Node) -> [SocketSpec] {
        guard case .sketch(let sketch)? = node.inputValues[NodeSetting.sketch] else { return inputs }
        return inputs + SketchSockets.exposed(sketch).map(\.spec)
    }

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        var sketch: Sketch
        switch context.node.inputValues[NodeSetting.sketch] {
        case nil: throw NodeError.invalidValue(missingSketch)
        case .sketch(let stored)?: sketch = stored
        case .some: throw NodeError.invalidValue(unreadableSketch)
        }
        var warnings = SketchSockets.refused(sketch)
        let plane: Plane
        switch sketch.plane {
        case .fixed(let own):
            plane = own
            if inputs.has("plane") { warnings.append(ignoredPlane) }
        case .wired:
            guard inputs.has("plane") else { throw NodeError.invalidValue(wiredPlaneMissing) }
            plane = try inputs.plane("plane")
        }
        let references = inputs.has("references") ? try inputs.solids("references") : []
        warnings += SketchProjections.resolve(&sketch, settings: context.node.inputValues, references: references, on: plane)
        for (id, spec) in SketchSockets.exposed(sketch) where inputs.has(spec.name) {
            sketch.dimensions[id]?.value = try inputs.number(spec.name)
        }
        let output = try SketchSolve.run(sketch, on: plane)
        let lists: [SocketName: [Scalar]] = [
            "profiles": output.profiles.map(Scalar.profile),
            "measurements": output.measurements.map(Scalar.number),
        ]
        return NodeOutputs(lists: lists, warnings: warnings + output.warnings)
    }
}
