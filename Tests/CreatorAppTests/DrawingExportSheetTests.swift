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

/// The DR-5 exports (R13 to R15): one sheet to a PDF, every sheet to one, SVG, the logo a DXF leaves out, balloons in a view's DXF and
/// the warnings sheet by sheet.
extension DrawingExportTests {
    @Test func aPDFOfOneSheet() async throws {
        let (app, _) = try await app()
        app.drawing.editor.addSheet()
        await app.placeBaseView()
        let url = temporaryURL("one.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await app.exportDrawingReturningWarnings(.pdfSheet, to: url)
        let reader = try PDFStructureReader(data: Data(contentsOf: url))
        #expect(reader.pages.count == 1)
        #expect(DrawingExportKind.pdfSheet.fileExtension == "pdf" && DrawingExportKind.svgSheet.fileExtension == "svg")
    }

    @Test func allSheetsInOnePDF() async throws {
        let (app, _) = try await app()
        let editor = app.drawing.editor
        let first = try #require(editor.currentSheet)
        editor.setTitleField(.title, to: "ONE")
        editor.addSheet()
        editor.setTitleField(.title, to: "TWO")
        editor.addSheet()
        editor.setTitleField(.title, to: "THREE")
        editor.show(sheet: first)
        await app.settle()
        let url = temporaryURL("three.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await app.exportDrawingReturningWarnings(.pdf, to: url)
        let reader = try PDFStructureReader(data: Data(contentsOf: url))
        #expect(reader.pages.count == 3)
        for (page, title) in zip(reader.pages, ["ONE", "TWO", "THREE"]) {
            #expect(tjOperands(page).contains("(\(title))"), "tab order: \(title) in \(tjOperands(page))")
        }
    }

    @Test func anSVGOfTheSheet() async throws {
        let (app, _) = try await app()
        let url = temporaryURL("sheet.svg")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await app.exportDrawingReturningWarnings(.svgSheet, to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        #expect(text.contains("<svg xmlns=\"http://www.w3.org/2000/svg\"") && text.contains("<g id=\"VISIBLE\">"))
        let picture = try #require(app.drawing.editor.picture)
        #expect(text.contains("width=\"\(Int(picture.size.x))mm\""), "the composed sheet's size")
        #expect(ContentType.exported(.svgSheet) == .svg)
    }

    @Test func theDXFSaysTheLogoIsLeftOut() async throws {
        let (app, _) = try await app()
        let sheet = try #require(app.drawing.editor.currentSheet)
        app.drawing.editor.setLogo(app.document.addImage(AppTestImages.png(40, 20, level: 90)).hex, of: sheet)
        await app.settle()
        let url = temporaryURL("logo.dxf")
        defer { try? FileManager.default.removeItem(at: url) }
        let warnings = try await app.exportDrawingReturningWarnings(.dxfSheet, to: url)
        let sentence = "The DXF leaves out the title block's logo; DXF files can't hold a picture."
        #expect(warnings.filter { $0 == sentence }.count == 1, "\(warnings)")
        let pdf = temporaryURL("logo.pdf")
        defer { try? FileManager.default.removeItem(at: pdf) }
        #expect(try await app.exportDrawingReturningWarnings(.pdf, to: pdf).isEmpty, "the PDF holds the picture")
    }

    @Test func aViewDXFWithAnnotationsCarriesBalloons() async throws {
        let parts = AssemblyParts()
        let (app, _) = await AppModel.inAssembly(parts)
        let view = try #require(await app.placeAssemblyView())
        let balloon = try app.addBalloon(on: parts.ids[0], in: view)
        let list = try app.addPartsList()
        var drawings = app.drawing.editor.document
        drawings.sheets[0].setAnnotation(
            DrawingAnnotation(view: nil, kind: .revisionTable(RevisionTable(rows: [RevisionRow(letter: "A", description: "First")]))))
        try app.document.perform(.setDrawings(drawings), name: "Test")
        app.drawing.editor.setLogo(app.document.addImage(AppTestImages.png(40, 20, level: 90)).hex, of: drawings.sheets[0].id)
        app.drawing.editor.selection = [view]
        await app.settle()
        let url = temporaryURL("balloon.dxf")
        defer { try? FileManager.default.removeItem(at: url) }
        let warnings = try await app.exportDrawingReturningWarnings(.dxfViewWithAnnotations, to: url)
        let reader = try DXFReader(data: Data(contentsOf: url))
        let scale = app.drawing.editor.document.sheets[0].scale.value
        let circle = try #require(reader.entities.first { $0.type == "CIRCLE" && $0.layer == "DIMENSION" })
        #expect(abs((circle.number(40) ?? 0) - 5 / scale) < 1e-6, "the circle's radius 5 over the scale: \(circle.number(40) ?? 0)")
        #expect(reader.entities.contains { $0.type == "LINE" && $0.layer == "DIMENSION" }, "its leader")
        let texts = reader.entities.filter { $0.type == "TEXT" && $0.layer == "DIMENSION" }.compactMap { $0.first(1) }
        #expect(texts.contains("1"), "its number: \(texts)")
        for table in ["Item", "Qty", "Name", "Rev.", "Description", "Material"] {
            #expect(!texts.contains(table), "no entity of the parts list or the revision table: \(texts)")
        }
        #expect(!warnings.contains { $0.contains("logo") }, "a view's DXF has no title block: \(warnings)")
        _ = (balloon, list)
    }

    @Test func warningsRunSheetBySheet() async throws {
        let app = await AppModel.inDrawing(DrawingBox(width: 40).graph)
        var lostDimensions: [AnnotationID] = []
        for index in 0..<2 {
            if index == 1 {
                app.drawing.editor.addSheet()
                await app.settle()
            }
            let view = try #require(await app.placeBaseView())
            lostDimensions.append(try #require(await app.dimensionBottomEdge(of: view)))
            _ = try #require(await app.placeSymbol(.datum, on: view))
            let frame = try #require(await app.placeSymbol(.featureControlFrame, on: view, side: .left))
            app.drawing.editor.setDatum(0, letterText: "A", material: nil, row: 0, of: frame)
            await app.settle()
        }
        // The dimensions lose what they held (a name no edge has); the frames still hold theirs and still break a rule.
        var drawings = app.drawing.editor.document
        let nothing = EdgePick(
            key: EdgeKey([TopoTag(node: NodeID(), item: 0, role: .startCap)], [TopoTag(node: NodeID(), item: 0, role: .endCap)]),
            matchCount: 1)
        for (sheet, id) in zip(drawings.sheets.indices, lostDimensions) {
            guard var annotation = drawings.sheets[sheet].annotation(id), case .dimension(var dimension) = annotation.kind else {
                Issue.record("no dimension")
                return
            }
            dimension.anchors = [.edge(nothing)]
            annotation.kind = .dimension(dimension)
            drawings.sheets[sheet].setAnnotation(annotation)
        }
        try app.document.perform(.setDrawings(drawings), name: "Lose")
        app.refreshDrawing()
        await app.settle()
        let url = temporaryURL("sheets.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let warnings = try await app.exportDrawingReturningWarnings(.pdf, to: url)
        func index(_ prefix: String, containing text: String) -> Int? {
            warnings.firstIndex { $0.hasPrefix(prefix) && $0.contains(text) }
        }
        let lost1 = index("On “Sheet 1”", containing: "lost what it was attached to")
        let check1 = index("On “Sheet 1”", containing: "takes no datum")
        let lost2 = index("On “Sheet 2”", containing: "lost what it was attached to")
        let check2 = index("On “Sheet 2”", containing: "takes no datum")
        let order = [lost1, check1, lost2, check2].compactMap { $0 }
        #expect(order.count == 4 && order == order.sorted(), "sheet 1's lost, its check, sheet 2's lost, its check: \(warnings)")
    }
}
