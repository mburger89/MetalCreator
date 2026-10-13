import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

/// What the evaluator does with images (fields spec D11): the stamp is part of a node's cache key, so an edited file runs the
/// node again, an untouched one does not, and a failure is never cached.
struct EvaluatorImageTests {
    static let registry = NodeRegistry([ImageProbeNode.self])
    let folder = TempFolder()

    func probe(_ reference: ImageReference?) -> Node {
        var node = Self.registry.makeNode(ImageProbeNode.typeID)
        if let reference { node.inputValues[NodeSetting.image] = .image(reference) }
        return node
    }

    func size(_ report: EvaluationReport, _ node: Node) -> Int? {
        if case .one(.integer(let value))? = report.results[node.id]?.outputs?["size"] { value } else { nil }
    }

    func error(_ report: EvaluationReport, _ node: Node) -> String? {
        if case .error(let message)? = report.results[node.id]?.state { message } else { nil }
    }

    @Test func aNodeWithNoImageSaysSoAndASettingOnlyReachesTheNodeThroughItsReference() async throws {
        let evaluator = Evaluator(registry: Self.registry, kernel: FakeKernel())
        let node = probe(nil)
        let report = try await evaluator.evaluate(Graph(nodes: [node.id: node]), demand: [node.id])
        #expect(error(report, node) == "Image Field needs an image: choose one in the inspector.")
    }

    @Test func anEmbeddedImageIsCachedAndAnAbsentOneIsAnErrorThatIsNotCached() async throws {
        let evaluator = Evaluator(registry: Self.registry, kernel: FakeKernel())
        let data = Data("twelve bytes".utf8)
        let hash = ImageHash(of: data)
        let node = probe(.embedded(hash))
        let graph = Graph(nodes: [node.id: node])
        let absent = try await evaluator.evaluate(graph, demand: [node.id])
        #expect(error(absent, node) == ImageProblem.embeddedMissing.message)
        let held = ImageResolver(embedded: [hash: data])
        let first = try await evaluator.evaluate(graph, demand: [node.id], images: held)
        #expect(size(first, node) == 12 && first.evaluatedNodes == [node.id])
        let second = try await evaluator.evaluate(graph, demand: [node.id], images: held)
        #expect(size(second, node) == 12 && second.evaluatedNodes.isEmpty, "the same bytes hit the cache")
    }

    @Test func aLinkedFileRunsTheNodeAgainOnlyWhenItsModificationDateOrSizeChanges() async throws {
        let evaluator = Evaluator(registry: Self.registry, kernel: FakeKernel())
        let file = try folder.write(Data(count: 10), to: "vent.png")
        try folder.touch(file, Date(timeIntervalSince1970: 1_000_000))
        let node = probe(.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false)))
        let graph = Graph(nodes: [node.id: node])
        let first = try await evaluator.evaluate(graph, demand: [node.id])
        #expect(size(first, node) == 10)
        #expect(try await evaluator.evaluate(graph, demand: [node.id]).evaluatedNodes.isEmpty, "untouched: reused")
        try Data(count: 25).write(to: file)
        try folder.touch(file, Date(timeIntervalSince1970: 2_000_000))
        let changed = try await evaluator.evaluate(graph, demand: [node.id])
        #expect(size(changed, node) == 25 && changed.evaluatedNodes == [node.id], "a change on disk is read at the next evaluation")
    }

    @Test func aMissingLinkFailsWithTheRelinkSentenceAndRecoversWhenTheFileAppears() async throws {
        let evaluator = Evaluator(registry: Self.registry, kernel: FakeKernel())
        let path = folder.url.appending(path: "textures/vent-mask.png")
        let node = probe(.linked(relativePath: nil, absolutePath: path.path(percentEncoded: false)))
        let graph = Graph(nodes: [node.id: node])
        let missing = try await evaluator.evaluate(graph, demand: [node.id])
        let message = try #require(error(missing, node))
        #expect(message.hasPrefix("Image 'vent-mask.png' wasn't found at ") && message.hasSuffix("/textures/. Relink it in the inspector."))
        try folder.write(Data(count: 7), to: "textures/vent-mask.png")
        let found = try await evaluator.evaluate(graph, demand: [node.id])
        #expect(size(found, node) == 7)
    }

    @Test func theDocumentsFolderDecidesWhereARelativeLinkPoints() async throws {
        let evaluator = Evaluator(registry: Self.registry, kernel: FakeKernel())
        try folder.write(Data(count: 3), to: "a/vent.png")
        try folder.write(Data(count: 5), to: "b/vent.png")
        let node = probe(.linked(relativePath: "vent.png", absolutePath: "/no/such/vent.png"))
        let graph = Graph(nodes: [node.id: node])
        let folderA = ImageResolver(documentFolder: folder.url.appending(path: "a"))
        let folderB = ImageResolver(documentFolder: folder.url.appending(path: "b"))
        let inA = try await evaluator.evaluate(graph, demand: [node.id], images: folderA)
        let inB = try await evaluator.evaluate(graph, demand: [node.id], images: folderB)
        #expect(size(inA, node) == 3 && size(inB, node) == 5, "saving the document elsewhere re-reads")
    }

    @Test func aNodeWithoutAnImageSettingIsNotAffected() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())
        let a = makeNode(ConstantNode.self, ["value": .number(1)])
        let g = graph([a])
        _ = try await evaluator.evaluate(g, demand: [a.id])
        let again = try await evaluator.evaluate(g, demand: [a.id], images: ImageResolver(documentFolder: folder.url))
        #expect(again.evaluatedNodes.isEmpty)
    }
}
