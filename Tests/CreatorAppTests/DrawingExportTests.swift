import CreatorDrawing
@testable import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// PDF and DXF export from the app (drawings plan R25): every sheet to a PDF, the open sheet or one view to a DXF, after the graph
/// has evaluated, refused in words, with the replaced characters and the left-out meshes listed once.
@MainActor
struct DrawingExportTests {
    func tjOperands(_ page: PDFPage) -> [String] {
        page.operators.filter { $0.name == "Tj" }.compactMap(\.operands.first)
    }

    func app(width: Double = 20, views: Int = 1) async throws -> (AppModel, DrawingBox) {
        let box = DrawingBox(width: width)
        let app = await AppModel.inDrawing(box.graph)
        for index in 0..<views { await app.placeBaseView(at: Vector2(100 + 60 * Double(index), 150)) }
        return (app, box)
    }

    @Test func aPDFHasAPagePerSheet() async throws {
        let (app, _) = try await app()
        app.drawing.editor.addSheet()
        await app.placeBaseView()
        let url = temporaryURL("two.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let warnings = try await app.exportDrawingReturningWarnings(.pdf, to: url)
        #expect(warnings.isEmpty)
        let reader = try PDFStructureReader(data: Data(contentsOf: url))
        #expect(reader.pages.count == 2)
        #expect(reader.pages.allSatisfy { !$0.operators.isEmpty })
    }

    @Test func theDXFOfTheSheetHoldsTheOpenSheet() async throws {
        let (app, _) = try await app()
        let url = temporaryURL("sheet.dxf")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await app.exportDrawingReturningWarnings(.dxfSheet, to: url)
        let reader = try DXFReader(data: Data(contentsOf: url))
        #expect(reader.entities.contains { $0.layer == "FRAME" }, "the border is on FRAME")
        #expect(reader.entities.contains { $0.layer == "VISIBLE" })
        #expect(reader.entities.contains { $0.type == "TEXT" })
    }

    @Test func theDXFOfAViewNeedsOneSelectedView() async throws {
        let (app, _) = try await app(views: 2)
        let url = temporaryURL("view.dxf")
        defer { try? FileManager.default.removeItem(at: url) }
        app.drawing.editor.selection = []
        await #expect(throws: AppProblem("Nothing to export", "Select one view to export it at 1:1.")) {
            _ = try await app.exportDrawingReturningWarnings(.dxfView, to: url)
        }
        let views = app.drawing.editor.document.sheets.flatMap(\.views).map(\.id)
        app.drawing.editor.selection = Set(views)
        await #expect(throws: AppProblem("Nothing to export", "Select one view to export it at 1:1.")) {
            _ = try await app.exportDrawingReturningWarnings(.dxfView, to: url)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        app.drawing.editor.selection = [views[0]]
        _ = try await app.exportDrawingReturningWarnings(.dxfView, to: url)
        let reader = try DXFReader(data: Data(contentsOf: url))
        let xs = reader.entities.filter { $0.type == "LINE" }.flatMap { [$0.number(10), $0.number(11)] }.compactMap { $0 }
        #expect(xs.count == 8, "the box's four lines")
        #expect(((xs.max() ?? 0) - (xs.min() ?? 0)).isApproximately(20), "model millimetres, not sheet millimetres")
        #expect(reader.entities.allSatisfy { $0.layer != "FRAME" })
    }

    @Test func aFailedOutputRefusesTheExport() async throws {
        let (app, box) = try await app()
        try app.document.perform(.setInput(box.extrude.id, "distance", .number(-1)), name: "Test")
        await app.settle()
        let url = temporaryURL("failed.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await app.exportDrawingReturningWarnings(.pdf, to: url)
            Issue.record("the export should have been refused")
        } catch {
            #expect(error.title == "“Output” can't be drawn")
            #expect(!error.message.isEmpty)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func noSheetRefuses() async throws {
        let app = await AppModel.inDrawing(DrawingBox().graph, sheet: false)
        let url = temporaryURL("none.pdf")
        for kind in DrawingExportKind.allCases {
            await #expect(throws: AppProblem("Nothing to export", "Add a sheet with a view first.")) {
                _ = try await app.exportDrawingReturningWarnings(kind, to: url)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func theExportWaitsForEvaluation() async throws {
        let (app, box) = try await app()
        let url = temporaryURL("fresh.dxf")
        defer { try? FileManager.default.removeItem(at: url) }
        try app.document.perform(.setInput(box.rectangle.id, "width", .number(40)), name: "Test")
        // No settle: the export itself waits.
        let view = try #require(app.drawing.editor.document.sheets.first?.views.first?.id)
        app.drawing.editor.selection = [view]
        _ = try await app.exportDrawingReturningWarnings(.dxfView, to: url)
        let reader = try DXFReader(data: Data(contentsOf: url))
        let xs = reader.entities.filter { $0.type == "LINE" }.flatMap { [$0.number(10), $0.number(11)] }.compactMap { $0 }
        #expect(((xs.max() ?? 0) - (xs.min() ?? 0)).isApproximately(40))
    }

    @Test func theExportWarnsAboutReplacedCharactersOnce() async throws {
        let (app, _) = try await app()
        app.drawing.editor.setTitleField(.title, to: "Ω-Bracket →")
        app.drawing.editor.addSheet()
        await app.placeBaseView()
        app.drawing.editor.setTitleField(.title, to: "Ω-Bracket →")
        let pdf = temporaryURL("replaced.pdf")
        defer { try? FileManager.default.removeItem(at: pdf) }
        let warnings = try await app.exportDrawingReturningWarnings(.pdf, to: pdf)
        #expect(warnings.count == 1)
        #expect(warnings.first?.contains("Ω-Bracket →") == true)
        let dxf = temporaryURL("replaced.dxf")
        defer { try? FileManager.default.removeItem(at: dxf) }
        let dxfWarnings = try await app.exportDrawingReturningWarnings(.dxfSheet, to: dxf)
        #expect(dxfWarnings.count == 1)
        #expect(dxfWarnings.first?.contains("Ω-Bracket →") == true)
    }

    @Test func meshesLeftOutAreListed() async throws {
        var box = DrawingBox()
        let mesh = box.builder.add(MeshNode.self)
        let toImplicit = box.builder.add(ToImplicitNode.self)
        box.builder.wire(box.extrude, "solid", to: toImplicit, "solid")
        box.builder.wire(toImplicit, "implicit", to: mesh, "implicit")
        box.builder.wire(mesh, "mesh", to: box.output, "mesh")
        let app = await AppModel.inDrawing(box.builder.graph)
        await app.placeBaseView()
        let url = temporaryURL("meshes.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let warnings = try await app.exportDrawingReturningWarnings(.pdf, to: url)
        #expect(warnings.contains { $0.contains("leaves out the Output's mesh") })
    }

    @Test func theChooserOffersTheDefaultNames() async throws {
        let (app, _) = try await app()
        let view = try #require(app.drawing.editor.document.sheets.first?.views.first?.id)
        app.drawing.editor.selection = [view]
        let url = temporaryURL("chosen.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let picker = ScriptedPicker([url, url, url])
        await app.exportDrawing(.pdf, using: picker)
        await app.exportDrawing(.dxfSheet, using: picker)
        await app.exportDrawing(.dxfView, using: picker)
        #expect(picker.asked.map(\.name) == ["Output.pdf", "Output.dxf", "Output Front.dxf"])
        #expect(picker.asked.map { $0.types.first } == [.pdf, .dxf, .dxf])
    }

    @Test func theMenusShowTheDrawingExportsOnlyInDrawing() async throws {
        var builder = GraphBuilder()
        _ = builder.box()
        let window = try await AppWindow.open(builder.graph)
        try window.window.click(try window.window.element(label: "Export"))
        var titles = try #require(window.window.presentedMenu).items.map(\.title)
        #expect(titles == ["STEP…", "STL…"])
        try window.window.dismissMenu()
        window.model.setMode(.drawing)
        try await window.window.runUntilIdle()
        try window.window.click(try window.window.element(label: "Export"))
        titles = try #require(window.window.presentedMenu).items.map(\.title)
        #expect(titles == ["STEP…", "STL…", "PDF…", "DXF of Sheet…", "DXF of View at 1:1…"])
        try window.window.dismissMenu()
        #expect(AppCommands.drawingExportTitles == ["Export PDF…", "Export DXF of Sheet…", "Export DXF of View at 1:1…"])
    }

    @Test func theMassShowsOnPage2() async throws {
        let (app, _) = try await app(width: 10)
        let editor = app.drawing.editor
        let first = try #require(editor.currentSheet)
        editor.addSheet()
        await app.placeBaseView()
        editor.setDensity(2.7)
        editor.show(sheet: first)
        await app.settle()
        let url = temporaryURL("mass.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await app.exportDrawingReturningWarnings(.pdf, to: url)
        let reader = try PDFStructureReader(data: Data(contentsOf: url))
        #expect(reader.pages.count == 2)
        #expect(tjOperands(reader.pages[1]).contains("(2.7 g)"))
        #expect(!tjOperands(reader.pages[0]).contains { $0.hasSuffix(" g)") })
    }
}
