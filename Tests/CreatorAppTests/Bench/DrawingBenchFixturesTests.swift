#if canImport(CreatorOCCT)
import CreatorDrawing
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

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
        // The line must really run through the plate's holes, which the Top view's own topology shows: every vertical hole whose
        // circle the line y = 8 cuts across splits the cut face, so n holes leave n + 1 pieces of hatch.
        let top = try #require(sheet.views.first { $0.orientation == .standard(.top) })
        let base = try #require(app.drawing.editor.contents[top.id]?.topology)
        let crossed = base.faces.filter { face in
            guard face.kind == .cylinder, let axis = face.axisPoint, let radius = face.radius else { return false }
            return abs(axis.y - DrawingBenchFixtures.sectionLineHeight) < radius
        }
        #expect(crossed.count == 2, "the line crosses the two holes of the row: \(crossed.count)")
        #expect(content.hatch.count == crossed.count + 1, "each crossed hole splits the cut face: \(content.hatch.count) pieces")
        let loops = content.hatch.reduce(0) { $0 + $1.edges.count }
        #expect(loops > 1, "the line runs through the holes: \(content.hatch.map { $0.edges.map(\.count) })")
        let topology = try #require(content.topology)
        #expect(topology.faces.contains { $0.tags.contains { $0.node == SectionCutter.toolNode } }, "the section has a cut face")
        #expect((content.projection?.lines.count ?? 0) > 0)
    }

    @Test func theAssemblyDocumentEvaluatesToTenSolids() async throws {
        let (document, outputs) = try DrawingBenchFixtures.assemblyDocument(parts: 10)
        await document.waitForEvaluation()
        #expect(outputs.count == 10)
        for id in outputs {
            let result = try #require(document.results[id], "no result for an Output")
            #expect(result.state.isSuccess, "\(result.state)")
            if case .ready(let solids, _, _) = DrawingSession.content(of: id, in: document).state {
                #expect(solids.count == 1 && solids[0].topology.faces.count > 6, "a box with a hole through it: \(solids.count)")
            } else {
                Issue.record("the Output holds no solid")
            }
        }
    }

    @Test func theAssemblyFixtureHasTenParts() async throws {
        let (document, outputs) = try DrawingBenchFixtures.assemblyDocument(parts: 10)
        #expect(outputs.count == 10)
        #expect(document.graph.nodes.values.filter { $0.typeID == OutputNode.typeID }.count == 10)
        let app = AppModel(kernel: OCCTKernel())
        let ids = try DrawingBenchFixtures.addAssemblyParts(to: app.document, parts: 10)
        await app.settle()
        for id in ids {
            #expect(app.document.results[id]?.state.isSuccess == true, "\(String(describing: app.document.results[id]?.state))")
        }
        app.setMode(.drawing)
        app.drawing.editor.addSheet()
        await app.settle()
        let sheet = DrawingBenchFixtures.assemblySheet(app, outputs: ids)
        #expect(sheet.sheets[0].views.count == 3)
        try app.document.perform(.setDrawings(sheet), name: "Test")
        app.refreshDrawing()
        await app.settle()
        for view in sheet.sheets[0].views {
            let content = try #require(app.drawing.editor.contents[view.id])
            #expect(content.problem == nil && !content.isPending, "\(String(describing: content.problem))")
            #expect((content.projection?.lines.count ?? 0) > 0)
            #expect(content.parts.count == 10, "ten spans")
            let topology = try #require(content.topology)
            for span in content.parts {
                let faces = topology.faces[span.faces]
                #expect(faces.count == 7, "a box with a hole has seven faces: \(faces.count)")
                #expect(faces.contains { $0.kind == .cylinder }, "the hole")
            }
        }
    }

    @Test func theBalloonedAssemblyHoldsTenBalloons() async throws {
        let app = AppModel(kernel: OCCTKernel())
        let ids = try DrawingBenchFixtures.addAssemblyParts(to: app.document, parts: 10)
        app.setMode(.drawing)
        app.drawing.editor.addSheet()
        await app.settle()
        let document = try await DrawingBenchFixtures.balloonedAssemblySheet(app, outputs: ids)
        let balloons = document.sheets[0].annotations.filter { if case .balloon = $0.kind { true } else { false } }
        #expect(balloons.count == 10)
        try app.document.perform(.setDrawings(document), name: "Test")
        app.refreshDrawing()
        await app.settle()
        let reports = balloons.compactMap { app.drawing.editor.picture?.annotationReports[$0.id] }
        #expect(reports.count == 10)
        #expect(reports.allSatisfy { $0.status == .held }, "\(reports.map(\.status))")
    }
}
#endif
