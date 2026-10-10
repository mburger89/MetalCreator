// Test fixture file: the §7.2 bracket on OCCT, its chamfer's edges picked, for the §7.3 benchmarks.
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// The app showing the finished §7.2 bracket on OCCT: built as `AppBracket` builds it, then the chamfer's edges
/// picked in the viewport's pick mode (the plate's top outline), as `AppAcceptanceTests` does, so every node is OK.
@MainActor
func makeBracketBenchApp() async throws -> (app: AppModel, bracket: AppBracket) {
    let app = AppModel(kernel: OCCTKernel())
    let bracket = try AppBracket(in: app)
    await app.settle()
    app.editor.press(.pickEdgesInView, on: bracket.chamfer.id)
    app.handle(try #require(app.editor.inspectorRequest))
    await app.settle()
    let session = try #require(app.pick)
    for edge in bracket.topCapOutline(session.solid) { app.viewportClicked(.edge(solid: 0, edge)) }
    app.finishPick()
    await app.settle()
    expectAllOK(app, "the benchmark's bracket")
    return (app, bracket)
}
