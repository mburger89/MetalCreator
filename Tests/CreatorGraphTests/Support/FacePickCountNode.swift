// Test fixture file: a node that reads a face pick, and the registry the pick tests use.
import CreatorKernel
@testable import CreatorGraph

/// Counts the faces of its solid that its `face` setting (a `FacePick`) names, as Plane from Face resolves one.
enum FacePickCountNode: NodeDefinition {
    static let typeID = "test.facePickCount"
    static let displayName = "Face Pick Count"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("solid", .solid)]
    static let outputs = [SocketSpec("count", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        guard case .facePick(let pick)? = context.node.inputValues[NodeSetting.face] else {
            return NodeOutputs(["count": .number(0)])
        }
        return NodeOutputs(["count": .number(Double(try inputs.solid("solid").topology.faces(matching: pick).count))])
    }
}

/// The test nodes with the face pick counter; `testRegistry` stays as it is.
let pickRegistry = NodeRegistry([BoxNode.self, FacePickCountNode.self, ConstantNode.self, AddNode.self, SinkNode.self])

/// A face pick on the end cap of the box `node` makes, as a pick on the level `node` sits at names it.
func endCapPick(of node: NodeID) -> ConstantValue {
    .facePick(FacePick(tags: [TopoTag(node: node, item: 0, role: .endCap)]))
}
