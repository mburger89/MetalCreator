import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// Spec §7.2, the slice's acceptance demo, through the app shell on OCCT: the bracket built in the app (the chamfer's
/// edges picked in the viewport's pick mode), saved, reopened and exported as STEP and STL; then Width 60 → 90 and
/// Hole count 4 → 6 with every node still OK and both exports again. Building it by hand in the window, and opening
/// the exports in FreeCAD and a slicer, are human checks M6-1 and M6-2.
@MainActor
struct AppAcceptanceTests {
    @Test func theBracketIsBuiltPickedSavedReopenedReparameterisedAndExported() async throws {
        let kernel = OCCTKernel()
        let app = AppModel(kernel: kernel)
        let bracket = try AppBracket(in: app)
        await app.settle()
        #expect(app.document.results[bracket.chamferEdges.id]?.state == .warning("Pick edges in view to fill this rule."))

        // "Pick edges in view…" on the Chamfer picks into its Edges by Tag rule; clicking the plate's top outline.
        app.editor.press(.pickEdgesInView, on: bracket.chamfer.id)
        app.handle(try #require(app.editor.inspectorRequest))
        await app.settle()
        let session = try #require(app.pick)
        #expect(session.rule == bracket.chamferEdges.id)
        #expect(app.viewport.items.count == 1 && app.viewport.items.first?.solid === session.solid)
        let outline = bracket.topCapOutline(session.solid)
        #expect(outline.count == 7)
        for edge in outline { app.viewportClicked(.edge(solid: 0, edge)) }
        app.finishPick()
        await app.settle()
        expectAllOK(app, "Width 60, 4 holes")
        let parts = app.viewport.items.filter { !$0.isGuide }
        #expect(parts.count == 1 && parts.first?.isGhost == false)
        let guides = app.viewport.items.filter(\.isGuide)
        #expect(guides.count == 1 && guides.first?.selectedEdges.isEmpty == false,
                "the picked rule stays selected, so its edges on the pre-chamfer solid are drawn over the part")
        #expect(app.exportName == "Bracket")

        // Save and reopen: the picks survive the file and nothing warns.
        let file = temporaryURL("bracket.mcgraph")
        defer { try? FileManager.default.removeItem(at: file) }
        try app.save(to: file)
        try app.open(file)
        await app.settle()
        expectAllOK(app, "reopened")
        #expect(!app.isEdited)
        try await expectExports(app, kernel, width: 60)

        // Width 60 → 90 and Hole count 4 → 6 (2 × 3): still all OK, still exports.
        try app.document.perform(.setParameter(bracket.width.id, .number(90)))
        try app.document.perform(.setParameter(bracket.holeCount.id, .integer(6)))
        await app.settle()
        expectAllOK(app, "Width 90, 6 holes")
        try await expectExports(app, kernel, width: 90)
    }

    /// STEP (re-read through OCCT, same volume) and STL (closed and manifold), of a part `width` mm wide.
    func expectExports(_ app: AppModel, _ kernel: OCCTKernel, width: Double,
                       sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let part = try #require(try app.exportSolids().first, sourceLocation: sourceLocation)
        #expect(abs(part.bounds.size.x - width) < 1e-6, sourceLocation: sourceLocation)
        let step = temporaryURL("bracket.step")
        let stl = temporaryURL("bracket.stl")
        defer {
            try? FileManager.default.removeItem(at: step)
            try? FileManager.default.removeItem(at: stl)
        }
        try await app.export(.step, to: step)
        try await app.export(.stl, to: stl)
        let readVolume = try OCCTKernel.serialized { () throws -> Double in try OCCTShape.readSTEP(step).properties().volume }
        let volume = try await kernel.properties(of: part).volume
        #expect(abs(readVolume - volume) <= 1e-5 * volume, sourceLocation: sourceLocation)
        let counts = edgeUseCounts(stl: try String(contentsOf: stl, encoding: .utf8))
        #expect(!counts.isEmpty, sourceLocation: sourceLocation)
        #expect(counts.values.allSatisfy { $0 == 2 }, "every STL edge is shared by exactly two triangles",
                sourceLocation: sourceLocation)
    }
}
