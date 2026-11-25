#if canImport(CreatorOCCT)
import CreatorDrawing
import Testing
@testable import CreatorApp

@MainActor
struct DrawingBenchFixturesTests {
    @Test func theBracketSheetHasFourViewsWithLines() async throws {
        let (app, _) = try await makeBracketBenchApp()
        app.setMode(.drawing)
        app.drawing.editor.addSheet()
        await app.settle()
        let document = try await DrawingBenchFixtures.bracketSheet(app)
        let sheet = try #require(document.sheets.first)
        #expect(sheet.views.count == 4)
        #expect(sheet.size == .a3)
        try app.document.perform(.setDrawings(document), name: "Test")
        app.refreshDrawing()
        await app.settle()
        for view in sheet.views {
            let content = try #require(app.drawing.editor.contents[view.id])
            #expect(content.problem == nil && !content.isPending)
            #expect((content.projection?.lines.count ?? 0) > 0, "\(view.orientation) has lines")
        }
    }
}
#endif
