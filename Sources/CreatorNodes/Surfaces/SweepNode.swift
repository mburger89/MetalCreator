import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Profiles swept along one path into a surface, or a solid when closed (NURBS spec).
public enum SweepNode: NodeDefinition {
    public static let typeID = "creator.sweep"
    public static let displayName = "Sweep"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Make"
    public static let maximumProfiles = 100
    public static let orientations = ["Frenet", "Fixed"]
    public static let pathRefusal = "Sweep needs exactly one path."
    public static var singleValuesRefusal: String? { "Sweep takes one path, end scale and binormal at a time." }
    public static let inputs = [
        SocketSpec("profiles", .curve, access: .list),
        SocketSpec("path", .curve),
        SocketSpec("orientation", .integer, defaultValue: .integer(0)),
        SocketSpec("binormal", .vector, defaultValue: .vector(.unitZ)),
        SocketSpec("end scale", .number, defaultValue: .number(1), range: 0.01...100),
        SocketSpec("solid", .bool, defaultValue: .bool(true)),
    ]
    public static let outputs = [SocketSpec("surface", .solid)]
    private static func sections(fixed: Bool) -> [InspectorSection] {
        [InspectorSection(title: "Sweep", controls: [.segmented("orientation", options: orientations)]
            + (fixed ? [.vector("binormal")] : [])
            + [.slider("end scale"), .toggle("solid", label: "Make a solid")]),
        ]
    }

    public static let inspector = sections(fixed: true)

    /// The binormal is shown for Fixed only.
    public static func inspector(for node: Node) -> [InspectorSection] {
        if case .integer(1)? = node.inputValues["orientation"] { return sections(fixed: true) }
        return sections(fixed: false)
    }

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let sources = try inputs.curves("profiles")
        guard sources.count <= maximumProfiles else {
            throw NodeError.invalidValue("A sweep takes at most \(maximumProfiles.display) profiles.")
        }
        let paths = try await CurveInput.loops(try inputs.curves("path"), holes: .all, kernel: kernel, tag: context.tag)
        guard let path = paths.first, paths.count == 1 else { throw NodeError.invalidValue(pathRefusal) }
        let profiles = try await CurveInput.loops(sources, holes: .all, kernel: kernel, tag: context.tag)
        let options = SweepOptions(orientation: try inputs.choice("orientation", options: orientations) == 0 ? .frenet : .fixedBinormal,
                                   binormal: try inputs.vector("binormal"), endScale: try inputs.number("end scale"),
                                   makesSolid: try inputs.bool("solid"))
        let surface = try await kernel.sweep(profiles, along: path, options: options, tag: context.tag)
        return NodeOutputs(["surface": .solid(surface)])
    }
}
