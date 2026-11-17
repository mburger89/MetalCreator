import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp
#if canImport(CreatorOCCT)
@testable import CreatorOCCT
#endif

/// NS-1 Task 11: exporting sheets and curves. STEP writes both; STL writes an open mesh with a warning and leaves curves out; 3MF
/// refuses a sheet before the save panel and leaves curves out.
@MainActor
struct SheetExportTests {
    @Test func theFormatRulesAreWordedAsSpecified() throws {
        var plan = ExportPlan()
        plan.sheetOutputs = ["Skin"]
        plan.curveOutputs = ["Skin"]
        #expect(AppModel.formatWarnings(for: .stl, plan) == [
            "Skin: The surface is open, so the STL is open there.", "Skin: Curves aren't written to STL.",
        ])
        #expect(AppModel.formatWarnings(for: .threeMF, plan) == ["Skin: Curves aren't written to 3MF."])
        #expect(AppModel.formatWarnings(for: .step, plan).isEmpty)
        #expect(throws: AppProblem("Skin can't be exported",
                                   "Skin is an open surface; 3MF needs closed parts. Thicken or Sew it first.")) {
            try AppModel.requireSolids(for: .threeMF, plan)
        }
        plan.meshOutputs = ["Mesh"]
        try AppModel.requireSolids(for: .stl, plan)
    }

    @Test func curvesAloneAreRefusedForStlAnd3mfButNotStep() throws {
        var plan = ExportPlan()
        plan.curveOutputs = ["Wire"]
        try AppModel.requireSolids(for: .step, plan)
        for kind in [ExportKind.stl, .threeMF] {
            #expect(throws: AppProblem("Nothing to export",
                                       "Only curves are wired into an Output node, and \(kind.title) doesn't hold curves. "
                                       + "Export STEP, or wire a solid in.")) {
                try AppModel.requireSolids(for: kind, plan)
            }
        }
    }

    #if canImport(CreatorOCCT)
    /// One Output "Skin" holding a planar sheet (a 10 x 10 mm rectangle) on `solid` and its outline on `curve`.
    private func skin(sheet: Bool = true, curve: Bool = true) -> Graph {
        var builder = GraphBuilder()
        let rectangle = builder.add(RectangleNode.self)
        let curves = builder.add(ProfileToCurvesNode.self)
        let surface = builder.add(PlanarSurfaceNode.self)
        var output = builder.add(OutputNode.self)
        builder.wire(rectangle, "profile", to: curves, "profile")
        builder.wire(curves, "curves", to: surface, "curves")
        if sheet { builder.wire(surface, "surface", to: output, "solid") }
        if curve { builder.wire(curves, "curves", to: output, "curve") }
        output.name = "Skin"
        builder.replace(output)
        return builder.graph
    }

    private func target(_ name: String) -> URL {
        URL.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(name)")
    }

    @Test func stepWritesTheSheetAndTheCurveAndReadsBackAsOneOfEach() async throws {
        let kernel = OCCTKernel()
        let app = await makeApp(skin(), kernel: kernel)
        let url = target("skin.step")
        defer { try? FileManager.default.removeItem(at: url) }
        let warnings = try await app.exportReturningWarnings(.step, to: url)
        #expect(warnings.isEmpty)
        let read = try await kernel.readShapes(try Data(contentsOf: url), format: .step, tag: NodeTag(node: NodeID(), item: 0))
        #expect(read.sheets.count == 1 && read.solids.isEmpty)
        // The outline is a wire of four edges; STEP reads it back a curve per edge.
        #expect(!read.curves.isEmpty)
        #expect(abs(read.curves.reduce(0) { $0 + $1.length } - read.sheets[0].bounds.size.x * 2 - read.sheets[0].bounds.size.y * 2) < 1e-4)
    }

    @Test func stlWarnsThatTheSurfaceIsOpenAndThatCurvesAreLeftOut() async throws {
        let app = await makeApp(skin(), kernel: OCCTKernel())
        let url = target("skin.stl")
        defer { try? FileManager.default.removeItem(at: url) }
        let warnings = try await app.exportReturningWarnings(.stl, to: url)
        #expect(warnings == ["Skin: The surface is open, so the STL is open there.", "Skin: Curves aren't written to STL."])
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func threeMFRefusesTheSheetBeforeTheSavePanelAndWritesNothing() async throws {
        let app = await makeApp(skin(), kernel: OCCTKernel())
        let url = target("skin.3mf")
        defer { try? FileManager.default.removeItem(at: url) }
        let picker = ScriptedPicker([url])
        await app.exportDocument(.threeMF, using: picker)
        #expect(picker.asked.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(app.alert == .problem(AppProblem("Skin can't be exported",
                                                 "Skin is an open surface; 3MF needs closed parts. Thicken or Sew it first.")))
    }

    @Test func aCurveBesideAClosedPartIsLeftOutOf3MFWithAWarning() async throws {
        var builder = GraphBuilder()
        let part = builder.solid()
        let curves = builder.add(ProfileToCurvesNode.self)
        var output = builder.add(OutputNode.self)
        builder.wire(part.rectangle, "profile", to: curves, "profile")
        builder.wire(part.extrude, "solid", to: output, "solid")
        builder.wire(curves, "curves", to: output, "curve")
        output.name = "Part"
        builder.replace(output)
        let app = await makeApp(builder.graph, kernel: OCCTKernel())
        let url = target("part.3mf")
        defer { try? FileManager.default.removeItem(at: url) }
        let warnings = try await app.exportReturningWarnings(.threeMF, to: url)
        #expect(warnings == ["Part: Curves aren't written to 3MF."])
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func curvesAloneGoToStepButStlSaysTheyAreNotHeld() async throws {
        let app = await makeApp(skin(sheet: false), kernel: OCCTKernel())
        let step = target("wire.step")
        defer { try? FileManager.default.removeItem(at: step) }
        _ = try await app.exportReturningWarnings(.step, to: step)
        #expect(FileManager.default.fileExists(atPath: step.path))
        let picker = ScriptedPicker([target("wire.stl")])
        await app.exportDocument(.stl, using: picker)
        #expect(picker.asked.isEmpty && app.alert != nil)
    }
    #endif
}
