import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A hole at every placement (patterns spec §5): cut from the placement's origin into the part, against its normal,
/// to a depth or through everything, plain, with a counterbore or with a countersink. It is Place + Boolean
/// underneath: each distinct hole size is built once as a revolved tool and shared by every hole of that size, one
/// kernel call places all the copies, and one subtracts them. A hole whose tool misses the part doesn't fail the
/// node; it warns with the count ("3 of 24 holes miss the part.").
///
/// Every size is a list, so a hole can differ from the next: the longest list sets the number of holes and a
/// shorter one repeats its last item. Faces of hole `i` are tagged with its instance path `{i}`, so a fillet on its
/// rim follows it through edits to the count, the spacing or the sizes.
public enum HolePatternNode: NodeDefinition {
    public static let typeID = "creator.holePattern"
    public static let displayName = "Hole Pattern"
    public static let category = NodeCategory.patterns
    public static let placesInstances = true
    public static let inputs = [
        SocketSpec("part", .solid),
        SocketSpec("placements", .plane, access: .list),
        SocketSpec("diameter", .number, access: .list, defaultValue: .number(5), unit: .millimetres, range: 0.1...100),
        SocketSpec("depth", .number, access: .list, defaultValue: .number(10), unit: .millimetres, range: 0.1...200),
        SocketSpec("throughAll", .bool, access: .list, defaultValue: .bool(false)),
        SocketSpec("style", .integer, access: .list, defaultValue: .integer(0)),
        SocketSpec("counterboreDiameter", .number, access: .list, defaultValue: .number(9), unit: .millimetres, range: 0.1...200),
        SocketSpec("counterboreDepth", .number, access: .list, defaultValue: .number(3), unit: .millimetres, range: 0.1...200),
        SocketSpec("countersinkDiameter", .number, access: .list, defaultValue: .number(10), unit: .millimetres, range: 0.1...200),
        SocketSpec("countersinkAngle", .number, access: .list, defaultValue: .number(90), unit: .degrees, range: 1...179),
    ]
    public static let outputs = [SocketSpec("solid", .solid)]
    public static let inspector = [
        InspectorSection(title: "Hole", controls: [.slider("diameter"), .slider("depth"), .toggle("throughAll", label: "Through all")]),
        InspectorSection(title: "Mouth", controls: [.segmented("style", options: HoleStyle.names)]),
        InspectorSection(title: "Counterbore", controls: [.slider("counterboreDiameter"), .slider("counterboreDepth")]),
        InspectorSection(title: "Countersink", controls: [.slider("countersinkDiameter"), .slider("countersinkAngle")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let part = try inputs.solid("part")
        let planes = try inputs.planes("placements")
        let values = (diameters: PerInstance(try inputs.numbers("diameter")), depths: PerInstance(try inputs.numbers("depth")),
                      through: PerInstance(try inputs.bools("throughAll")), styles: PerInstance(try inputs.integers("style")),
                      cbDiameters: PerInstance(try inputs.numbers("counterboreDiameter")),
                      cbDepths: PerInstance(try inputs.numbers("counterboreDepth")),
                      csDiameters: PerInstance(try inputs.numbers("countersinkDiameter")),
                      csAngles: PerInstance(try inputs.numbers("countersinkAngle")))
        let count = PerInstance<Plane>.instances([
            planes.count, values.diameters.count, values.depths.count, values.through.count, values.styles.count,
            values.cbDiameters.count, values.cbDepths.count, values.csDiameters.count, values.csAngles.count,
        ])
        try PatternLimit.check(count)
        guard count > 0 else { return NodeOutputs(["solid": .solid(part)]) }
        let reach = values.through.values.contains(true) ? ThroughReach.length(of: part, placements: planes) : 0
        var sizes: [HoleSize] = []
        for index in 0..<count {
            guard let style = HoleStyle(rawValue: values.styles[index]) else {
                throw NodeError.invalidValue("Choose \(HoleStyle.names.formatted(.list(type: .or).locale(.messages))) for “style”.")
            }
            let size = HoleSize(diameter: values.diameters[index], depth: values.through[index] ? reach : values.depths[index],
                                style: style, counterbore: (values.cbDiameters[index], values.cbDepths[index]),
                                countersink: (values.csDiameters[index], .degrees(values.csAngles[index])))
            if let problem = size.problem(at: InstancePath.text(index)) { throw NodeError.invalidValue(problem) }
            sizes.append(size)
        }
        let plan = ToolPlan(sizes: sizes)
        var built: [Solid] = []
        for size in plan.distinct {
            let profile = Profile2D.polyline(size.outline, closed: true, plane: .xz)
            built.append(try await kernel.revolve(profile, axis: .z, angle: .degrees(360), tag: context.tag))
        }
        let request = PatternApply.Request(operation: .subtract, part: part, tools: plan.toolIndex.map { built[$0] }, planes: planes,
                                           nouns: PatternApply.Nouns(singular: "hole", plural: "holes"))
        return try await PatternApply.run(request, kernel: kernel, context: context)
    }
}
