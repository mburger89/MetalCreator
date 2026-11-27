#if canImport(CreatorOCCT)
import CreatorDrawing
@testable import CreatorDrawingEditor
import CreatorGeometry
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// The pan and zoom lines and the dimension drag of the drawings benchmarks.
@MainActor
extension DrawingBench {
    /// The pan and the zoom of `drawing-2-warm` and `drawing-5-warm`: 60 pan steps then 60 zoom steps of the open sheet in a warm
    /// window. Prints a `pan` line (the first five steps are warm-up), a `zoom` line and the two together, the line they have
    /// always printed.
    func panAndZoom(
        _ app: AppModel, _ warm: WarmBenchWindow, start: SheetTransform, name: String, detail: String
    ) async {
        let editor = app.drawing.editor
        var pan = BenchSamples("\(name) pan window-cpu (\(detail))")
        var zoom = BenchSamples("\(name) zoom window-cpu (\(detail))")
        var cpu = BenchSamples("\(name) window-cpu (\(detail))")
        for step in 0..<Self.steps {
            editor.transform = SheetTransform(offset: start.offset + Vector2(-Double(step) * 8, -Double(step)), zoom: start.zoom)
            await app.settle()
            let milliseconds = warm.timedFrame()
            if step >= 5 {
                pan.append(milliseconds)
                cpu.append(milliseconds)
            }
        }
        for step in 0..<Self.steps {
            let level = start.zoom * (step < Self.steps / 2 ? 1 + Double(step) * 0.03 : 1 + Double(Self.steps - step) * 0.03)
            editor.transform = start.zoomed(to: level, about: Vector2(700, 450))
            await app.settle()
            let milliseconds = warm.timedFrame()
            zoom.append(milliseconds)
            cpu.append(milliseconds)
        }
        print(pan.line(budget: Bench.frameBudget))
        print(zoom.line(budget: Bench.frameBudget))
        print(cpu.line(budget: Bench.frameBudget))
    }

    /// drawing-drag-warm: the ten-part sheet with ten balloons and the parts list plus one dimension, the dimension pressed on and
    /// dragged in 60 steps of 0.5 mm through the editor's input path (`primaryChanged`, so the host's `storeDrawing` and its
    /// refresh run). Each step's figure is that call plus a warm frame; settling is outside the timer.
    @Test func draggingADimensionOnTheAssemblySheetWarm() async throws {
        guard Bench.requireRelease() else { return }
        let app = AppModel(kernel: OCCTKernel())
        let outputs = try DrawingBenchFixtures.addAssemblyParts(to: app.document, parts: 10)
        app.setMode(.drawing)
        app.drawing.editor.addSheet()
        await app.settle()
        let (document, dimension) = try await DrawingBenchFixtures.draggableAssemblySheet(app, outputs: outputs)
        try app.document.perform(.setDrawings(document), name: "Test")
        app.refreshDrawing()
        await app.settle()
        let warm = try await WarmBenchWindow(model: app)
        let drag = try DimensionDragFixture.press(app, dimension)
        let clock = ContinuousClock()
        var cpu = BenchSamples("drawing-drag-warm step-cpu (primaryChanged + warm frame, ten parts, ten balloons, parts list)")
        for step in 1...Self.steps {
            let start = clock.now
            drag.step(to: Double(step) * 0.5)
            let changed = clock.now
            let frame = warm.timedFrame()
            cpu.append(Double((changed - start) / .milliseconds(1)) + frame)
            await app.settle()
        }
        let outcome = await drag.release(at: Double(Self.steps) * 0.5)
        #expect(abs(abs(outcome.moved) - 30) < 1e-6, "the dimension moved 30 mm: \(outcome.moved)")
        #expect(outcome.balloonsHeld == 10 && outcome.balloonsUnchanged, "every balloon stayed held")
        print(cpu.line(budget: Bench.frameBudget))
    }
}
#endif
