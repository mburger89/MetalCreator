#if canImport(CreatorOCCT)
import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// `docs/examples/bracket-7.2.mcgraph`: the spec §7.2 bracket as the app's own save writes it (format `GraphFile.currentFormatVersion`),
/// the file human check XP-18 opens on Linux and Windows. The open test keeps the file honest: it must decode, evaluate with every
/// node OK, and make the same graph and the same part as the bracket the acceptance tests build in code, so a format change that
/// the file no longer survives, or a recipe change it no longer matches, fails here. To regenerate it after either, run
/// `MC_WRITE_EXAMPLES=1 swift test --filter BracketExampleTests` on a Mac and commit the result.
@MainActor
struct BracketExampleTests {
    static let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "docs/examples/bracket-7.2.mcgraph")

    /// Writes the example through `AppModel.save(to:)`, the path File ▸ Save takes. Skipped unless asked for.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MC_WRITE_EXAMPLES"] != nil, "set MC_WRITE_EXAMPLES=1 to regenerate"))
    func regenerateTheExample() async throws {
        let (app, _) = try await makeBracketBenchApp()
        try Self.layOutLeftToRight(app)
        try app.save(to: Self.file)
    }

    /// Moves every node to a column by its depth in the data flow (a node sits one column right of its furthest-left
    /// input's deepest source), and stacks each column's nodes top to bottom, ordered by the mean height of what feeds them.
    static func layOutLeftToRight(_ app: AppModel) throws {
        let graph = app.document.graph
        var depth: [NodeID: Int] = [:]
        func depthOf(_ id: NodeID) -> Int {
            if let known = depth[id] { return known }
            let value = graph.links.filter { $0.to.node == id }.map { depthOf($0.from.node) + 1 }.max() ?? 0
            depth[id] = value
            return value
        }
        for id in graph.nodes.keys { _ = depthOf(id) }
        let gap = Vector2(60, 24)
        var top: [NodeID: Double] = [:]
        var left = 0.0
        for column in 0...(depth.values.max() ?? 0) {
            let members = graph.nodes.values.filter { depth[$0.id] == column }
            func feed(_ node: Node) -> Double {
                let sources = graph.links.filter { $0.to.node == node.id }.compactMap { top[$0.from.node] }
                return sources.isEmpty ? 0 : sources.reduce(0, +) / Double(sources.count)
            }
            var y = 0.0
            for node in members.sorted(by: { (feed($0), $0.name, $0.typeID) < (feed($1), $1.name, $1.typeID) }) {
                try app.document.perform(.move(node.id, to: Vector2(left, y)))
                top[node.id] = y
                y += NodeLayout.size(app.editor.shape(of: node)).y + gap.y
            }
            left += NodeLayout.width + gap.x
        }
    }

    @Test func theCheckedInBracketOpensAndMakesTheCodeBuiltBracketsPart() async throws {
        let (built, _) = try await makeBracketBenchApp()
        let app = AppModel(kernel: OCCTKernel())
        try app.open(Self.file)
        await app.settle()
        expectAllOK(app, "the example file")
        // Node IDs are fresh UUIDs per build, so the recipes are compared by what they hold.
        func recipe(_ graph: Graph) -> [String] { graph.nodes.values.map { "\($0.typeID) \($0.name)" }.sorted() }
        #expect(recipe(app.document.graph) == recipe(built.document.graph), "the file holds the code-built recipe")
        #expect(app.document.graph.links.count == built.document.graph.links.count)
        #expect(app.document.graph.parameters.map(\.name) == built.document.graph.parameters.map(\.name))
        #expect(app.exportName == "Bracket")
        // Stored (left-to-right) frames: the dock only transposes how they are drawn.
        let frames = app.document.graph.nodes.values.map {
            (name: $0.name, frame: CanvasRect(origin: $0.position, size: NodeLayout.size(app.editor.shape(of: $0))))
        }
        for (index, a) in frames.enumerated() {
            for b in frames[(index + 1)...] {
                let apart = a.frame.maxX <= b.frame.origin.x || b.frame.maxX <= a.frame.origin.x
                    || a.frame.maxY <= b.frame.origin.y || b.frame.maxY <= a.frame.origin.y
                #expect(apart, "\(a.name) and \(b.name) overlap on the canvas")
            }
        }
        for link in app.document.graph.links {
            let from = try #require(app.document.graph.nodes[link.from.node]), to = try #require(app.document.graph.nodes[link.to.node])
            #expect(from.position.x < to.position.x, "\(from.name) feeds \(to.name) from the left")
        }
        let part = try #require(try app.exportSolids().first)
        let expected = try #require(try built.exportSolids().first)
        #expect(part.bounds == expected.bounds)
        let volume = try await app.kernel.properties(of: part).volume
        let expectedVolume = try await built.kernel.properties(of: expected).volume
        #expect(abs(volume - expectedVolume) <= 1e-9 * expectedVolume, "\(volume) against \(expectedVolume)")
    }
}
#endif
