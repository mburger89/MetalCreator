// Test fixture file: an app over FakeKernel, a scripted file picker, temporary files and a graph builder.
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import MetalUI
import Testing
@testable import CreatorApp

/// An app over `FakeKernel` (boxes, fake fillets, no export), showing `graph` once it has evaluated.
@MainActor
func makeApp(_ graph: Graph = Graph(), kernel: any Kernel = FakeKernel()) async -> AppModel {
    let app = AppModel(kernel: kernel, file: GraphFile(graph: graph))
    await app.settle()
    return app
}

/// A file picker that answers from a script and records what it was asked.
@MainActor
final class ScriptedPicker: FilePicker {
    var answers: [URL?]
    private(set) var asked: [(types: [ContentType], name: String?)] = []

    init(_ answers: [URL?]) {
        self.answers = answers
    }

    func chooseFileToOpen(_ types: [ContentType]) async throws -> URL? {
        asked.append((types, nil))
        return answers.isEmpty ? nil : answers.removeFirst()
    }

    func chooseDestination(_ types: [ContentType], defaultName: String) async throws -> URL? {
        asked.append((types, defaultName))
        return answers.isEmpty ? nil : answers.removeFirst()
    }
}

/// A fresh path in the temporary directory, removed by the caller's `defer`.
func temporaryURL(_ name: String) -> URL {
    URL.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(name)")
}

/// Builds graphs from built-in nodes, created as the app creates them (`NodeRegistry.makeNode`).
struct GraphBuilder {
    private(set) var graph = Graph()

    @discardableResult
    mutating func add(_ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue] = [:],
                      at position: Vector2 = .zero) -> Node {
        var node = BuiltInNodes.registry.makeNode(definition.typeID, at: position)
        node.inputValues.merge(values) { _, given in given }
        graph.nodes[node.id] = node
        return node
    }

    mutating func wire(_ from: Node, _ output: SocketName, to: Node, _ input: SocketName,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        let link = Link(from: Endpoint(node: from.id, socket: output), to: Endpoint(node: to.id, socket: input))
        if let problem = graph.connectionProblem(from: link.from, to: link.to, registry: BuiltInNodes.registry) {
            Issue.record("can't wire \(from.name).\(output) → \(to.name).\(input): \(problem)", sourceLocation: sourceLocation)
        }
        graph.links.append(link)
    }

    /// Rectangle → Extrude (`distance` mm). Returns both nodes.
    mutating func solid(distance: Double = 10, at position: Vector2 = .zero) -> (rectangle: Node, extrude: Node) {
        let rectangle = add(RectangleNode.self, at: position)
        let extrude = add(ExtrudeNode.self, ["distance": .number(distance)], at: position + Vector2(240, 0))
        wire(rectangle, "profile", to: extrude, "profile")
        return (rectangle, extrude)
    }

    /// Rectangle → Extrude (`distance` mm) → Output. Returns the three nodes.
    mutating func box(distance: Double = 10, at position: Vector2 = .zero) -> (rectangle: Node, extrude: Node, output: Node) {
        let (rectangle, extrude) = solid(distance: distance, at: position)
        let output = add(OutputNode.self, at: position + Vector2(480, 0))
        wire(extrude, "solid", to: output, "solid")
        return (rectangle, extrude, output)
    }
}

/// The solids a node's output socket carries now.
@MainActor
func solids(_ app: AppModel, _ node: Node, _ socket: SocketName = "solid") -> [Solid] {
    (app.document.results[node.id]?.outputs?[socket]?.items ?? []).compactMap { scalar in
        if case .solid(let solid) = scalar { solid } else { nil }
    }
}
