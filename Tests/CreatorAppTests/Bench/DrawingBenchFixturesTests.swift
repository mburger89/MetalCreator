#if canImport(CreatorOCCT)
import CreatorDrawing
import CreatorGeometry
import CreatorKernel
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

    @Test func theAnnotatedBracketHoldsThirtyDimensions() async throws {
        let (app, _) = try await makeBracketBenchApp()
        app.setMode(.drawing)
        app.drawing.editor.addSheet()
        await app.settle()
        let document = try await DrawingBenchFixtures.annotatedBracketSheet(app)
        let sheet = try #require(document.sheets.first)
        #expect(sheet.views.count == 4)
        #expect(sheet.annotations.count == 30)
        try app.document.perform(.setDrawings(document), name: "Test")
        app.refreshDrawing()
        await app.settle()
        let reports = sheet.annotations.compactMap { app.drawing.editor.picture?.annotationReports[$0.id] }
        #expect(reports.count == 30)
        #expect(reports.allSatisfy { $0.status == .held }, "every dimension is held: \(reports.map(\.status))")
        let kinds = sheet.annotations.compactMap { annotation -> DrawingDimensionKind? in
            if case .dimension(let dimension) = annotation.kind { dimension.kind } else { nil }
        }
        #expect(kinds.contains(.diameter) && kinds.contains(.angle) && kinds.contains(.linear(.aligned)), "\(kinds)")
        #expect(Set(sheet.annotations.compactMap(\.view)).count >= 3, "the dimensions lie over several views")
    }

    @Test func theBracketSectionIsHatched() async throws {
        let (app, _) = try await makeBracketBenchApp()
        app.setMode(.drawing)
        app.drawing.editor.addSheet()
        await app.settle()
        let document = try await DrawingBenchFixtures.sectionedBracketSheet(app)
        let sheet = try #require(document.sheets.first)
        let section = try #require(sheet.views.first { $0.kind == .section })
        try app.document.perform(.setDrawings(document), name: "Test")
        app.refreshDrawing()
        await app.settle()
        let content = try #require(app.drawing.editor.contents[section.id])
        #expect(content.problem == nil && !content.isPending, "\(String(describing: content.problem))")
        #expect(!content.hatch.isEmpty, "the cut has hatch")
        let loops = content.hatch.reduce(0) { $0 + $1.edges.count }
        #expect(loops > 1, "the line runs through the holes: \(content.hatch.map { $0.edges.map(\.count) })")
        let topology = try #require(content.topology)
        #expect(topology.faces.contains { $0.tags.contains { $0.node == SectionCutter.toolNode } }, "the section has a cut face")
        #expect((content.projection?.lines.count ?? 0) > 0)
    }
}
#endif
