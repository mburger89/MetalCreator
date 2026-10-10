import Testing
@testable import CreatorApp

/// The bracket the orbit, fillet-drag and kernel benchmarks measure is ready for them: every node OK, the part shown,
/// and the selected Fillet's radius handle there to drag. Runs in the default test run, so the benchmarks' fixture
/// can't rot between benchmark runs.
@MainActor
struct BracketBenchAppTests {
    @Test func theBracketIsReadyToMeasure() async throws {
        let (app, bracket) = try await makeBracketBenchApp()
        #expect(app.viewport.items.count == 1, "the bracket is shown")
        app.editor.selection = [bracket.fillet.id]
        await app.settle()
        #expect(app.viewport.handles.count == 1, "the selected Fillet shows its radius handle")
    }
}
