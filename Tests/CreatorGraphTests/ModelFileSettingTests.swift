import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

/// The Import Model node's `modelFile` setting (NURBS spec, Task 8): saved like an image, a mesh file or a board file.
struct ModelFileSettingTests {
    @Test func roundTripsThroughJSON() throws {
        let hash = ImageHash(of: Data("a model".utf8))
        for reference in [ImageReference.embedded(hash), .linked(relativePath: "a/b.step", absolutePath: "/x/a/b.step")] {
            let value = ConstantValue.modelFile(reference)
            let decoded = try JSONDecoder().decode(ConstantValue.self, from: JSONEncoder().encode(value))
            #expect(decoded == value && decoded.fileReference == reference)
            #expect(decoded != .meshFile(reference) && decoded != .image(reference))
        }
    }

    @Test func isASettingNotASocketValueAndNotReserved() {
        #expect(Scalar(.modelFile(.embedded(ImageHash(of: Data())))) == nil)
        #expect(NodeSetting.all.contains(NodeSetting.modelFile))
        #expect(!NodeSetting.reservedForSockets.contains(NodeSetting.modelFile))
    }

    @Test func itsEmbeddedBytesAreKeptAndMappedLikeAnyFile() {
        let hash = ImageHash(of: Data("a model".utf8))
        var node = Node(id: NodeID(), typeID: "creator.importModel", name: "Import Model", position: .zero)
        node.inputValues[NodeSetting.modelFile] = .modelFile(.embedded(hash))
        var graph = Graph()
        graph.nodes[node.id] = node
        #expect(graph.embeddedImageHashes == [hash])
        let linked = ImageReference.linked(relativePath: nil, absolutePath: "/x.step")
        #expect(graph.mappingImages { _ in linked }.nodes[node.id]?.inputValues[NodeSetting.modelFile] == .modelFile(linked))
    }
}
