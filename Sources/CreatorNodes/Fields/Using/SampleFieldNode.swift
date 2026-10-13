import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Turns a field into numbers (fields spec §3.3): the field at each placement's origin, in exactly the shape of `at`, paths and
/// culled gaps included. One `FieldSampler` call covers the whole tree (kernel distances go through the evaluator's cache). A
/// vector wired into `at` is a plane through it, so points and placements both wire. This is the graded-sizes path, in the one
/// order that wires: a field → Remap → Sample Field → a shortcut's size socket, paired per instance by `InstanceGrid` (Remap takes
/// and returns a field, so it comes before the sampling, never after).
public enum SampleFieldNode: NodeDefinition {
    public static let typeID = "creator.sampleField"
    public static let displayName = "Sample Field"
    public static let category = NodeCategory.fields
    public static let inputs = [
        SocketSpec("field", .field),
        SocketSpec("at", .plane, access: .tree),
    ]
    public static let outputs = [SocketSpec("values", .number)]
    public static var singleValuesRefusal: String? { LayoutChecks.singleValues(displayName) }

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let tree = try inputs.tree("at")
        let origins = try tree.items.map { scalar -> Vector3 in
            guard case .plane(let plane) = scalar else { throw NodeError.typeMismatch("at", expected: .plane) }
            return plane.origin
        }
        let values = try await FieldSampler.sample(try inputs.field("field"), at: origins, kernel: kernel, cache: context.fieldDistances)
        var next = 0
        let numbers = tree.mappingItems { _, _, _ in
            defer { next += 1 }
            return .number(values[next])
        }
        return NodeOutputs(trees: ["values": numbers])
    }
}
