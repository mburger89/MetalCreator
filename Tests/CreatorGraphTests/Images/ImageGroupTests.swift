import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

/// An image used inside a group definition (fields spec §5): the group node runs it with the document's images and folder, and a
/// file edited on disk reaches it as it reaches a node on the top level.
struct ImageGroupTests {
    let folder = TempFolder()

    /// "Probe": no inputs, one integer output `size`, with an Image Probe inside reading `reference`.
    func probeGroup(_ reference: ImageReference) -> (GroupDefinition, Node) {
        var inner = EvaluatorImageTests.registry.makeNode(ImageProbeNode.typeID)
        inner.inputValues[NodeSetting.image] = .image(reference)
        let definition = define("Probe", outputs: [SocketSpec("size", .integer)], nodes: [inner]) { _, output in
            [link(inner, "size", output, "size")]
        }
        return (definition, inner)
    }

    func size(_ report: EvaluationReport, _ node: Node) -> Int? {
        if case .one(.integer(let value))? = report.results[node.id]?.outputs?["size"] { value } else { nil }
    }

    @Test func aGroupRunsItsImageFromTheDocumentsPoolAndRunsAgainWhenALinkedFileChanges() async throws {
        let data = Data("embedded bytes".utf8)
        let (embedded, _) = probeGroup(.embedded(ImageHash(of: data)))
        let embeddedGroup = instance(of: embedded)
        let evaluator = Evaluator(registry: EvaluatorImageTests.registry, kernel: FakeKernel())
        let held = ImageResolver(embedded: [ImageHash(of: data): data])
        let first = try await evaluator.evaluate(graph([embeddedGroup]), definitions: table([embedded]), demand: [embeddedGroup.id],
                                                 images: held)
        #expect(size(first, embeddedGroup) == 14)

        let file = try folder.write(Data(count: 5), to: "vent.png")
        try folder.touch(file, Date(timeIntervalSince1970: 1_000))
        let (linked, _) = probeGroup(.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false)))
        let linkedGroup = instance(of: linked)
        let before = try await evaluator.evaluate(graph([linkedGroup]), definitions: table([linked]), demand: [linkedGroup.id])
        #expect(size(before, linkedGroup) == 5)
        #expect(try await evaluator.evaluate(graph([linkedGroup]), definitions: table([linked]), demand: [linkedGroup.id])
            .evaluatedNodes.isEmpty, "unchanged: cached")
        try Data(count: 9).write(to: file)
        try folder.touch(file, Date(timeIntervalSince1970: 2_000))
        let after = try await evaluator.evaluate(graph([linkedGroup]), definitions: table([linked]), demand: [linkedGroup.id])
        #expect(size(after, linkedGroup) == 9, "the node inside the group saw the new date")
    }
}
