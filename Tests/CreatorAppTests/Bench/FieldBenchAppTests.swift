import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorApp

/// Row 4's bracket and field nodes are ready to measure (a plain `swift test` checks them, since `FieldBenchPreview` runs only
/// in a release build when asked): selecting a field node tints the bracket and shows the slice, and an edit to it changes the
/// tint, the Remap's without asking the kernel again.
@MainActor
struct FieldBenchAppTests {
    @Test func theRemapTintsTheBracketAndAnEditNeedsNoNewKernelDistances() async throws {
        let bench = try await FieldBenchApp()
        let app = bench.app
        bench.select(bench.remap)
        await app.settle()
        #expect(app.document.results[bench.remap.id]?.state.isSuccess == true)
        let first = try #require(app.viewport.items.first?.fieldValues)
        #expect(app.viewport.slice != nil && app.fieldPreview.legend?.range != nil)
        let misses = await app.document.fieldDistances.misses
        #expect(misses >= 1, "the first tint asked the kernel")
        try bench.setFromHigh(30)
        await app.settle()
        let second = try #require(app.viewport.items.first?.fieldValues)
        #expect(second != first && second.count == first.count)
        #expect(await app.document.fieldDistances.misses == misses, "the bracket's vertices and the slice's grid are cached")
    }

    @Test func theRadialGradientNeedsNoKernel() async throws {
        let bench = try await FieldBenchApp()
        bench.select(bench.radial)
        await bench.app.settle()
        let first = try #require(bench.app.viewport.items.first?.fieldValues)
        try bench.setRadius(55)
        await bench.app.settle()
        #expect(try #require(bench.app.viewport.items.first?.fieldValues) != first)
        #expect(await bench.app.document.fieldDistances.misses == 0)
    }
}
