#if canImport(CreatorOCCT)
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
        try app.save(to: Self.file)
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
        let part = try #require(try app.exportSolids().first)
        let expected = try #require(try built.exportSolids().first)
        #expect(part.bounds == expected.bounds)
        let volume = try await app.kernel.properties(of: part).volume
        let expectedVolume = try await built.kernel.properties(of: expected).volume
        #expect(abs(volume - expectedVolume) <= 1e-9 * expectedVolume, "\(volume) against \(expectedVolume)")
    }
}
#endif
