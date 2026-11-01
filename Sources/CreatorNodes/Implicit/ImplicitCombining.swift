import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// What Union, Subtract and Intersect share (implicit spec §3.3): a list of shapes, a blend radius (a field, so a 7b field can grade
/// it; 0 is sharp), and the result.
enum ImplicitCombining {
    enum Kind {
        case union, subtract, intersect

        /// The solid the shapes make with `blend`.
        func combine(_ shapes: [ImplicitSolid], blend: Grading, continuity: BlendContinuity = .g1) -> ImplicitSolid {
            switch self {
            case .union: .union(shapes, blend: blend, continuity: continuity)
            case .subtract: .subtract(shapes, blend: blend, continuity: continuity)
            case .intersect: .intersect(shapes, blend: blend, continuity: continuity)
            }
        }
    }

    static let inputs = [
        SocketSpec("shapes", .implicit, access: .list),
        SocketSpec("blend radius", .field, defaultValue: .number(0), unit: .millimetres, range: 0...50),
        continuitySocket,
    ]
    /// The order of the smooth minimum, an option index into `BlendContinuity`: G2 on a new node.
    static let continuitySocket = SocketSpec("continuity", .integer, defaultValue: .integer(BlendContinuity.g2.rawValue), range: 0...2)
    /// The labels of the segmented control, in `BlendContinuity` order.
    static let continuityOptions = BlendContinuity.allCases.map(\.label)

    /// The segmented control that sets it.
    static let continuityControl = InspectorControl.segmented("continuity", options: continuityOptions)

    /// The migration of a node saved before it had a continuity: it was made with G1, so it keeps it. A node that already stores one
    /// is left alone.
    static func continuityMigration(_ node: Node) -> Node {
        var migrated = node
        if migrated.inputValues["continuity"] == nil { migrated.inputValues["continuity"] = .integer(BlendContinuity.g1.rawValue) }
        return migrated
    }

    /// The `continuity` input.
    static func continuity(_ inputs: NodeInputs) throws -> BlendContinuity {
        BlendContinuity(rawValue: try inputs.choice("continuity", options: continuityOptions)) ?? .g2
    }

    static let outputs = [SocketSpec("implicit", .implicit)]

    static func inspector(_ title: String) -> [InspectorSection] {
        [InspectorSection(title: title, controls: [.number("blend radius"), continuityControl])]
    }

    static func evaluate(_ kind: Kind, _ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let shapes = try inputs.implicitSolids("shapes")
        guard !shapes.isEmpty else { throw NodeError.invalidValue("Connect at least one shape to “shapes”.") }
        let region = ImplicitGrading.region(around: kind.combine(shapes, blend: .constant(0)).bounds)
        let setting = try await ImplicitGrading.make(try inputs.field("blend radius"), named: "blend radius", over: region,
                                                     holdsAtZero: true, kernel: kernel, context: context)
        // One shape, sharp, is that shape; anything else is the combination.
        let continuity = try continuity(inputs)
        let sharp = setting.grading.constantValue.map { $0 <= 0 } ?? false
        let result = shapes.count == 1 && sharp ? shapes[0] : kind.combine(shapes, blend: setting.grading, continuity: continuity)
        return NodeOutputs(["implicit": .implicit(result.reference)], warnings: setting.warnings)
    }
}
