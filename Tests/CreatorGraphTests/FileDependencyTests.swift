import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// Reads the size of the file its `path` setting names and reports it as a dependency, stamped before the read.
private enum FileSizeNode: NodeDefinition {
    static let typeID = "test.fileSize"
    static let displayName = "File Size"
    static let category = NodeCategory.value
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("size", .number)]

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        guard case .text(let path)? = context.node.inputValues["path"] else { return NodeOutputs(["size": .number(-1)]) }
        var outputs: NodeOutputs
        do {
            outputs = NodeOutputs(["size": .number(Double(try ImageResolver.modelFile(at: path, limit: 1 << 20).data.count))])
        } catch {
            outputs = NodeOutputs(["size": .number(-1)])
        }
        outputs.dependencies = [FileDependency(path: path, stamp: ImageResolver.stamp(ofFileAt: path))]
        return outputs
    }
}

@MainActor
struct FileDependencyTests {
    private let registry = NodeRegistry([FileSizeNode.self, ConstantNode.self, AddNode.self])

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "filedep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func size(of result: NodeResult?) -> Double? {
        guard case .one(.number(let value))? = result?.outputs?["size"] else { return nil }
        return value
    }

    private func probe(_ path: String) -> Node {
        var node = registry.makeNode(FileSizeNode.typeID)
        node.inputValues["path"] = .text(path)
        return node
    }

    @Test func anUnchangedFileReusesTheResultAndCarriesTheDependency() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appending(path: "a.bin").path(percentEncoded: false)
        try Data(count: 10).write(to: URL(filePath: path))
        let node = probe(path)
        let evaluator = Evaluator(registry: registry, kernel: FakeKernel())
        let g = graph([node])
        let first = try await evaluator.evaluate(g, demand: [node.id])
        #expect(first.evaluatedNodes == [node.id])
        #expect(first.results[node.id]?.dependencies.map(\.path) == [path])
        let second = try await evaluator.evaluate(g, demand: [node.id])
        #expect(second.evaluatedNodes.isEmpty)
    }

    @Test func aRewrittenFileRunsTheNodeAndWhatIsDownstream() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appending(path: "a.bin").path(percentEncoded: false)
        try Data(count: 10).write(to: URL(filePath: path))
        let node = probe(path)
        let add = registry.makeNode(AddNode.typeID)
        let link = Link(from: Endpoint(node: node.id, socket: "size"), to: Endpoint(node: add.id, socket: "a"))
        let evaluator = Evaluator(registry: registry, kernel: FakeKernel())
        let g = graph([node, add], [link])
        _ = try await evaluator.evaluate(g, demand: [add.id])
        try Data(count: 25).write(to: URL(filePath: path))
        let report = try await evaluator.evaluate(g, demand: [add.id])
        #expect(Set(report.evaluatedNodes) == [node.id, add.id])
        #expect(size(of: report.results[node.id]) == 25)
    }

    @Test func aDeletedFileRunsTheNodeAgain() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appending(path: "a.bin").path(percentEncoded: false)
        try Data(count: 10).write(to: URL(filePath: path))
        let node = probe(path)
        let evaluator = Evaluator(registry: registry, kernel: FakeKernel())
        let g = graph([node])
        _ = try await evaluator.evaluate(g, demand: [node.id])
        try FileManager.default.removeItem(atPath: path)
        let report = try await evaluator.evaluate(g, demand: [node.id])
        #expect(report.evaluatedNodes == [node.id])
        #expect(size(of: report.results[node.id]) == -1)
    }

    @Test func aMissingFileThatAppearsRunsTheNodeAgain() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appending(path: "later.bin").path(percentEncoded: false)
        let node = probe(path)
        let evaluator = Evaluator(registry: registry, kernel: FakeKernel())
        let g = graph([node])
        let first = try await evaluator.evaluate(g, demand: [node.id])
        #expect(size(of: first.results[node.id]) == -1)
        try Data(count: 7).write(to: URL(filePath: path))
        let report = try await evaluator.evaluate(g, demand: [node.id])
        #expect(report.evaluatedNodes == [node.id])
        #expect(size(of: report.results[node.id]) == 7)
    }

    @Test func anUnrelatedNodesEditDoesNotRunIt() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appending(path: "a.bin").path(percentEncoded: false)
        try Data(count: 10).write(to: URL(filePath: path))
        let node = probe(path)
        var other = registry.makeNode(ConstantNode.typeID)
        other.inputValues["value"] = .number(1)
        let evaluator = Evaluator(registry: registry, kernel: FakeKernel())
        _ = try await evaluator.evaluate(graph([node, other]), demand: [node.id, other.id])
        other.inputValues["value"] = .number(2)
        let report = try await evaluator.evaluate(graph([node, other]), demand: [node.id, other.id])
        #expect(report.evaluatedNodes == [other.id])
    }

    @Test func modelFileRefusesWhatIsNotAFileOrTooBig() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let big = dir.appending(path: "big.bin")
        try Data(count: 100).write(to: big)
        let bigPath = big.path(percentEncoded: false)
        #expect(throws: ModelFileProblem.tooLarge(limit: 50)) { try ImageResolver.modelFile(at: bigPath, limit: 50) }
        #expect(throws: ModelFileProblem.notAFile) { try ImageResolver.modelFile(at: dir.path(percentEncoded: false), limit: 50) }
        let nowhere = dir.appending(path: "no").path(percentEncoded: false)
        #expect(throws: ModelFileProblem.missing) { try ImageResolver.modelFile(at: nowhere, limit: 50) }
        #expect(ModelFileProblem.tooLarge(limit: 256 << 20).reason == "it is larger than 256 MB")
        let read = try ImageResolver.modelFile(at: big.path(percentEncoded: false), limit: 100)
        #expect(read.data.count == 100)
        #expect(read.stamp == ImageResolver.stamp(ofFileAt: big.path(percentEncoded: false)))
    }
}
