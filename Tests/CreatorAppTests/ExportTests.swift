import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp

/// Export (spec §7.2 step 5): the solids of every Output node, refused in plain words when there are none or an
/// Output has no current result. The OCCT round trip is `AppAcceptanceTests`.
@MainActor
struct ExportTests {
    @Test func withNoOutputNodeThereIsNothingToExport() async {
        var builder = GraphBuilder()
        _ = builder.solid()
        let app = await makeApp(builder.graph)
        #expect(throws: AppProblem("Nothing to export", "Add an Output node and wire the part into it.")) {
            try app.exportSolids()
        }
    }

    @Test func anOutputWithoutAResultSaysWhy() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        try app.document.perform(.setInput(box.extrude.id, "distance", .number(-1)))
        await app.settle()
        #expect(app.viewport.items.first?.isGhost == true, "the viewport ghosts it…")
        #expect(throws: AppProblem("“Output” can't be exported",
                                   "Waiting on “solid”: the node wired into it has no result.")) {
            try app.exportSolids()   // …but a stale result is never exported
        }
    }

    @Test func anUnwiredOutputOrAnEmptyListIsNothingToExport() async throws {
        var builder = GraphBuilder()
        builder.add(OutputNode.self)
        let unwired = await makeApp(builder.graph)
        #expect(throws: AppProblem("“Output” can't be exported", "Connect or set “solid”.")) {
            try unwired.exportSolids()
        }
        // A grid of no points moves the box to no places: the Output gets an empty list and only warns.
        var empty = GraphBuilder()
        let box = empty.solid()
        let grid = empty.add(GridPointsNode.self, ["total": .integer(0)])
        let copies = empty.add(TransformNode.self)
        let output = empty.add(OutputNode.self)
        empty.wire(box.extrude, "solid", to: copies, "solid")
        empty.wire(grid, "points", to: copies, "move")
        empty.wire(copies, "solid", to: output, "solid")
        let app = await makeApp(empty.graph)
        #expect(app.document.results[output.id]?.state == .warning("There is nothing to preview or export."))
        #expect(throws: AppProblem("Nothing to export", "No solid is wired into an Output node.")) {
            try app.exportSolids()
        }
    }

    @Test func everyOutputsSolidsAreExportedUnderTheFirstOutputsName() async throws {
        var builder = GraphBuilder()
        let first = builder.box(distance: 10)
        let second = builder.box(distance: 20, at: Vector2(0, 300))
        let app = await makeApp(builder.graph)
        #expect(try app.exportSolids().count == 2)
        try app.document.perform(.rename(first.output.id, "Bracket"))
        try app.document.perform(.rename(second.output.id, "Spare"))
        #expect(app.exportName == (app.outputNodes.first == first.output.id ? "Bracket" : "Spare"))
    }

    @Test func aKernelThatCantWriteIsReportedPlainly() async throws {
        var builder = GraphBuilder()
        _ = builder.box()
        let app = await makeApp(builder.graph)
        await #expect(throws: AppProblem("The STEP file couldn't be written",
                                         Evaluator.message(for: KernelError.unsupported("export")))) {
            try await app.export(.step, to: temporaryURL("box.step"))
        }
    }

    @Test func exportingAsksWhereUnderTheExportNameAndACancelDoesNothing() async {
        var builder = GraphBuilder()
        _ = builder.box()
        let app = await makeApp(builder.graph)
        let picker = ScriptedPicker([nil])
        await app.exportDocument(.stl, using: picker)
        #expect(picker.asked.first?.types == [.stl])
        #expect(picker.asked.first?.name == "Output.stl")
        #expect(app.alert == nil)
        let refused = await makeApp()
        let unused = ScriptedPicker([])
        await refused.exportDocument(.step, using: unused)
        #expect(unused.asked.isEmpty, "what's wrong is said before asking where")
        #expect(refused.alert?.title == "Nothing to export")
    }
}
