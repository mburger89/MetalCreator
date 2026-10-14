// Test fixture file: it deliberately holds two small node definitions.
import CreatorKernel
@testable import CreatorGraph

/// Reports the mesh quality and engine its context carries, and some progress; reads the quality, so its cache key holds it.
enum QualityProbeNode: NodeDefinition {
    static let typeID = "test.qualityProbe"
    static let displayName = "Quality Probe"
    static let category = NodeCategory.value
    static let readsMeshQuality = true
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("quality", .integer), SocketSpec("engine", .integer)]

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        context.meshProgress(0.25)
        context.meshProgress(0.75)
        return NodeOutputs([
            "quality": .integer(context.meshQuality == .export ? 1 : 0),
            "engine": .integer(context.implicitEngine == .automatic ? 1 : 0),
        ])
    }
}

/// The same, without reading the quality: a result it makes is shared by previews and exports.
enum PlainProbeNode: NodeDefinition {
    static let typeID = "test.plainProbe"
    static let displayName = "Plain Probe"
    static let category = NodeCategory.value
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("quality", .integer)]

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["quality": .integer(context.meshQuality == .export ? 1 : 0)])
    }
}

let meshProbeRegistry = NodeRegistry([QualityProbeNode.self, PlainProbeNode.self])
