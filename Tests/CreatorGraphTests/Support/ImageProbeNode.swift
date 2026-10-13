// Test fixture file: a node that reads its `image` setting through the evaluation's image resolver.
import CreatorKernel
@testable import CreatorGraph

/// Outputs the number of bytes behind its `image` setting, so a test sees when the bytes, or the evaluation, change.
enum ImageProbeNode: NodeDefinition {
    static let typeID = "test.imageProbe"
    static let displayName = "Image Probe"
    static let category = NodeCategory.value
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("size", .integer)]

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        guard case .image(let reference)? = context.node.inputValues[NodeSetting.image] else { throw ImageProblem.notChosen }
        return NodeOutputs(["size": .integer(try context.images.bytes(of: reference).count)])
    }
}
