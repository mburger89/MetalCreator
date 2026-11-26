import CreatorDrawing
@testable import CreatorDrawingEditor
import CreatorGeometry
@testable import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// Assembly views in the app (DR-5 R2, R5, R6): one projection of every part, spans, the facts the balloons and the parts list share,
/// a part that fails or goes, and the refresh that judges anchors against the spans the sheet shows.
@MainActor
struct DrawingAssemblyTests {
    @Test func anAssemblyProjectsEveryPart() async throws {
        let parts = AssemblyParts()
        let (app, kernel) = await AppModel.inAssembly(parts)
        let view = try #require(await app.placeAssemblyView())
        let content = try #require(app.drawing.editor.contents[view])
        #expect(content.parts.map(\.output) == parts.ids.sorted(), "three spans, in the Outputs' ID order")
        #expect(content.parts.count == 3 && content.problem == nil)
        let projections = await kernel.operationLog.filter { $0 == "projection" }
        #expect(projections.count == 1, "one request with the three parts' solids: \(projections.count)")
    }

    @Test func tickingAPartReRequests() async throws {
        let parts = AssemblyParts()
        let (app, _) = await AppModel.inAssembly(parts)
        let view = try #require(await app.placeAssemblyView())
        let order = parts.ids.sorted()
        app.drawing.editor.setPart(order[1], shown: false, of: view)
        await app.settle()
        #expect(app.drawing.editor.contents[view]?.parts.map(\.output) == [order[0], order[2]])
        app.drawing.editor.setPart(order[1], shown: true, of: view)
        await app.settle()
        #expect(app.drawing.editor.contents[view]?.parts.count == 3)
    }

    @Test func aFailedPartKeepsTheViewFaded() async throws {
        let parts = AssemblyParts()
        let (app, _) = await AppModel.inAssembly(parts)
        let view = try #require(await app.placeAssemblyView())
        let before = try #require(app.drawing.editor.contents[view]?.projection)
        try app.document.perform(.setInput(parts.rectangles[2].id, "width", .number(-5)), name: "Break")
        await app.settle()
        let content = try #require(app.drawing.editor.contents[view])
        #expect(content.isPending, "the last lines stay, faded")
        #expect(content.projection == before)
        #expect(content.problem?.hasPrefix("“Plate” can't be drawn: ") == true, "\(content.problem ?? "nil")")
    }

    @Test func partsFactsNameAndCount() async throws {
        var parts = AssemblyParts()
        let series = parts.builder.add(SeriesNode.self, ["start": .number(10), "step": .number(5), "count": .integer(4)])
        parts.builder.graph.links.removeAll { $0.to == Endpoint(node: parts.rectangles[1].id, socket: "width") }
        parts.builder.wire(series, "values", to: parts.rectangles[1], "width")
        let (app, _) = await AppModel.inAssembly(parts)
        _ = try #require(await app.placeAssemblyView())
        let facts = app.drawing.editor.facts.parts
        #expect(facts[parts.ids[1]] == PartFacts(name: "Nut", quantity: 4, isRemoved: false), "four solids")
        #expect(facts[parts.ids[0]] == PartFacts(name: "Bolt", quantity: 1, isRemoved: false))
        try app.document.perform(.rename(parts.ids[0], "Screw"), name: "Rename")
        await app.settle()
        #expect(app.drawing.editor.facts.parts[parts.ids[0]]?.name == "Screw", "names follow a rename")
        #expect(app.drawing.editor.partFacts == app.drawing.editor.facts.parts)
        try app.document.perform(.setInput(parts.rectangles[0].id, "width", .number(-5)), name: "Break")
        await app.settle()
        #expect(app.drawing.editor.facts.parts[parts.ids[0]]?.quantity == nil, "a failed part has no quantity")
    }

    @Test func massOfAnAssemblySheet() async throws {
        let parts = AssemblyParts(widths: [20, 30, 40, 10], names: ["Bolt", "Nut", "Plate", "Other"])
        let (app, _) = await AppModel.inAssembly(parts)
        let view = try #require(await app.placeAssemblyView())
        // Only the first three parts are in the view.
        app.drawing.editor.setPart(parts.ids[3], shown: false, of: view)
        await app.settle()
        app.drawing.editor.setDensity(7.85)
        await app.settle()
        // 20, 30 and 40 mm wide, 10 deep (the rectangle's default height is 10) and 10 tall: volumes 2,000 + 3,000 + 4,000 mm³.
        let expected = TitleBlockFacts.massText(grams: (2_000 + 3_000 + 4_000) * 7.85 / 1000, inches: false)
        #expect(app.drawing.editor.facts.massText == expected, "\(app.drawing.editor.facts.massText ?? "nil") vs \(expected)")
        // An unrelated single view of the fourth part beside it: no mass.
        let single = try #require(await app.placeBaseView(at: Vector2(300, 100)))
        app.drawing.editor.setSource(parts.ids[3], of: single)
        await app.settle()
        #expect(app.drawing.editor.facts.massText == nil, "unrelated parts have no mass")
    }

    @Test func deletingAPartsOutputLosesItsBalloon() async throws {
        let parts = AssemblyParts()
        let (app, _) = await AppModel.inAssembly(parts)
        let view = try #require(await app.placeAssemblyView())
        let balloon = try app.addBalloon(on: parts.ids[0], in: view)
        await app.settle()
        #expect(app.texts(of: balloon) == ["1"], "\(app.texts(of: balloon))")
        try app.document.perform(.removeNode(parts.ids[0]), name: "Delete")
        await app.settle()
        #expect(app.report(of: balloon)?.status == .lost(.partNotShown))
        #expect(app.texts(of: balloon).contains("1?"), "\(app.texts(of: balloon))")
        let url = temporaryURL("lost-balloon.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let warnings = try await app.exportDrawingReturningWarnings(.pdf, to: url)
        #expect(warnings.contains { $0.contains("“Balloon 1”") && $0.contains(LostReason.partNotShown.sentence) }, "\(warnings)")
        #expect(warnings.contains(DrawingProjector.partRemovedSentence), "the removed part is left out and says so")
    }

    @Test func deletingAnOutputRenumbersNothing() async throws {
        let parts = AssemblyParts()
        let (app, _) = await AppModel.inAssembly(parts)
        let view = try #require(await app.placeAssemblyView())
        let balloons = try parts.ids.map { try app.addBalloon(on: $0, in: view) }
        let list = try app.addPartsList()
        await app.settle()
        #expect(balloons.map { app.texts(of: $0) } == [["1"], ["2"], ["3"]], "Bolt, Nut, Plate by name")
        try app.document.perform(.removeNode(parts.ids[2]), name: "Delete")
        await app.settle()
        #expect(balloons.map { app.texts(of: $0) } == [["1"], ["2"], ["3?"]])
        func rowOfPlate(_ app: AppModel) -> Bool {
            let texts = app.drawing.editor.picture?.texts.filter { $0.annotation == list } ?? []
            guard let name = texts.first(where: { $0.original == "Plate?" }),
                  let number = texts.first(where: { $0.original == "3" }) else { return false }
            return abs(name.origin.y - number.origin.y) < 1e-6
        }
        #expect(rowOfPlate(app), "the parts list reads Plate? in row 3")
        // Saved and reopened: the same numbers.
        let url = temporaryURL("renumber.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try app.save(to: url)
        let file = try GraphFileIO.decode(Data(contentsOf: url), registry: BuiltInNodes.registry)
        let kernel = FakeKernel()
        await kernel.setCompoundHook { concatenatedSolids($0) }
        let reopened = AppModel(kernel: kernel, file: file, fileURL: url)
        await reopened.settle()
        reopened.setMode(.drawing)
        await reopened.settle()
        #expect(balloons.map { reopened.texts(of: $0) } == [["1"], ["2"], ["3?"]], "\(balloons.map { reopened.texts(of: $0) })")
        #expect(rowOfPlate(reopened))
    }

    @Test func theEditorPinsWhatTheSheetShows() async throws {
        let parts = AssemblyParts()
        let (app, _) = await AppModel.inAssembly(parts)
        let view = try #require(await app.placeAssemblyView())
        let balloons = try parts.ids.map { try app.addBalloon(on: $0, in: view) }
        await app.settle()
        let editor = app.drawing.editor
        #expect(editor.partFacts == editor.facts.parts, "the editor reads the facts the composer reads")
        let before = balloons.map { app.texts(of: $0) }
        let second = try #require(PartItems.numbered(editor.document, names: PartItems.names(of: editor.partFacts))[1].part)
        editor.setItemMaterial("Steel", of: second)
        await app.settle()
        #expect(balloons.map { app.texts(of: $0) } == before, "a material typed on item 2 renumbers nothing")
        #expect(editor.document.items.first { $0.part == second }?.material == "Steel")
    }

    @Test func exportRefusesAFailedPart() async throws {
        let parts = AssemblyParts()
        let (app, _) = await AppModel.inAssembly(parts)
        _ = try #require(await app.placeAssemblyView())
        try app.document.perform(.setInput(parts.rectangles[2].id, "width", .number(-5)), name: "Break")
        await app.settle()
        let url = temporaryURL("failed-part.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await app.exportDrawingReturningWarnings(.pdf, to: url)
            Issue.record("the export should have been refused")
        } catch {
            #expect(error.title == "“Plate” can't be drawn", "\(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func refreshReadsEveryPart() async throws {
        let parts = AssemblyParts()
        let (app, _) = await AppModel.inAssembly(parts)
        let view = try #require(await app.placeAssemblyView())
        let dimension = try app.addDimension(on: parts.ids[2], in: view)
        await app.settle()
        #expect(app.texts(of: dimension).contains("40"), "\(app.texts(of: dimension))")
        app.setMode(.model)
        try app.document.perform(.setInput(parts.rectangles[2].id, "width", .number(50)), name: "Width")
        await app.settle()
        #expect(app.drawing.editor.remembered[dimension]?.values == [50], "read with no compose")
        let drawings = app.drawing.editor.document
        #expect(app.document.drawings == drawings, "and nothing was edited")
        app.setMode(.drawing)
        await app.settle()
        #expect(app.texts(of: dimension).contains("50"), "the compose shows what the refresh read: \(app.texts(of: dimension))")
    }

    @Test func refreshSpansEqualProjectedSpans() async throws {
        var parts = AssemblyParts()
        // The second part shows the first's solid: its Output takes the first's Extrude.
        let target = Endpoint(node: parts.ids[1], socket: "solid")
        parts.builder.graph.links.removeAll { $0.to == target }
        parts.builder.wire(parts.extrudes[0], "solid", to: parts.outputs[1], "solid")
        let (app, _) = await AppModel.inAssembly(parts)
        let seen = SpanLog()
        app.drawing.refreshObserver = { view, spans in seen.spans[view] = spans }
        let base = try #require(await app.placeAssemblyView())
        let section = try #require(await app.addSection(on: base))
        let balloon = try app.addBalloon(on: parts.ids[2], in: section)
        let dimension = try app.addDimension(on: parts.ids[2], in: base)
        await app.settle()
        let projected = try #require(app.drawing.editor.contents[section]?.parts)
        #expect(projected.count == 3, "\(projected) \(app.drawing.editor.contents[section]?.problem ?? "")")
        #expect(projected.map(\.faces.count).filter { $0 == 0 }.count >= 1, "the shared solid is drawn once: \(projected)")
        #expect(seen.spans[section] == projected, "the refresh judged anchors against the spans the sheet shows")
        let baseSpans = try #require(app.drawing.editor.contents[base]?.parts)
        #expect(seen.spans[base] == baseSpans)
        #expect(app.report(of: balloon) != nil)
        #expect(app.drawing.editor.remembered[dimension]?.values == [40])
    }
}

/// Where a test collects what a hook reports.
@MainActor
final class SpanLog {
    var spans: [ViewID: [PartSpan]] = [:]
}
