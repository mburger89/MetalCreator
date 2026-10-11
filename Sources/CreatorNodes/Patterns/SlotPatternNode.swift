import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A slot at every placement (patterns spec §5): rounded ends, `length` long end to end along the placement's X axis
/// and `width` across, cut from the placement's origin into the part, against its normal, to a depth or through
/// everything. It is Place + Boolean underneath: each distinct size is built once as an extruded tool and shared by
/// every slot of that size, one kernel call places all the copies, and one subtracts them. A slot that misses the
/// part doesn't fail the node; it warns with the count ("3 of 24 slots miss the part.").
///
/// Every size is a list, so a slot can differ from the next: the longest list sets the number of slots and a shorter
/// one repeats its last item. Faces of slot `i` are tagged with its instance path `{i}`.
public enum SlotPatternNode: NodeDefinition {
    public static let typeID = "creator.slotPattern"
    public static let displayName = "Slot Pattern"
    public static let category = NodeCategory.patterns
    public static let inputs = [
        SocketSpec("part", .solid),
        SocketSpec("placements", .plane, access: .list),
        SocketSpec("length", .number, access: .list, defaultValue: .number(20), unit: .millimetres, range: 0.2...200),
        SocketSpec("width", .number, access: .list, defaultValue: .number(6), unit: .millimetres, range: 0.1...100),
        SocketSpec("depth", .number, access: .list, defaultValue: .number(10), unit: .millimetres, range: 0.1...200),
        SocketSpec("throughAll", .bool, access: .list, defaultValue: .bool(false)),
    ]
    public static let outputs = [SocketSpec("solid", .solid)]
    public static let inspector = [
        InspectorSection(title: "Slot", controls: [.slider("length"), .slider("width")]),
        InspectorSection(title: "Depth", controls: [.slider("depth"), .toggle("throughAll", label: "Through all")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let part = try inputs.solid("part")
        let planes = try inputs.planes("placements")
        let (lengths, widths) = (PerInstance(try inputs.numbers("length")), PerInstance(try inputs.numbers("width")))
        let (depths, through) = (PerInstance(try inputs.numbers("depth")), PerInstance(try inputs.bools("throughAll")))
        let count = PerInstance<Plane>.instances([planes.count, lengths.count, widths.count, depths.count, through.count])
        try PatternLimit.check(count)
        guard count > 0 else { return NodeOutputs(["solid": .solid(part)]) }
        let reach = through.values.contains(true) ? ThroughReach.length(of: part, placements: planes) : 0
        var sizes: [SlotSize] = []
        for index in 0..<count {
            let size = SlotSize(length: lengths[index], width: widths[index], depth: through[index] ? reach : depths[index])
            if let problem = size.problem(at: InstancePath.text(index)) { throw NodeError.invalidValue(problem) }
            sizes.append(size)
        }
        let plan = ToolPlan(sizes: sizes)
        // The profile faces down, so extruding it along its normal runs the slot from the origin against +Z.
        let down = Plane(origin: .zero, normal: -.unitZ, xAxis: .unitX)
        var built: [Solid] = []
        for size in plan.distinct {
            built.append(try await kernel.extrude(.slot(length: size.length, width: size.width, plane: down), distance: size.depth,
                                                  mode: .oneSided, tag: context.tag))
        }
        let request = PatternApply.Request(operation: .subtract, part: part, tools: plan.toolIndex.map { built[$0] }, planes: planes,
                                           nouns: PatternApply.Nouns(singular: "slot", plural: "slots"))
        return try await PatternApply.run(request, kernel: kernel, context: context)
    }
}
