import Testing
@testable import CreatorApp

/// Fields spec §7, row 4: "Edit to tinted preview on the bracket, under 150 ms" (parent §7.3's budget for an edit to a
/// preview). The §7.2 bracket on OCCT with a field node selected; each step edits that field to a value never seen before and
/// waits for the evaluation, the scene, the meshes, the tint's sampling and the slice's, then draws the window's frame (CPU)
/// and both GPU passes, as `FilletDragBench` measures a drag. Release, idle Mac; prints `BENCH field-4…` lines:
/// - `field-4`: a Remap of the signed distance to the bracket (its range edited): the kernel's distances to the bracket's
///   vertices and the slice's grid are cached after the first tint, so an edit costs the maths and the redraw;
/// - `field-4b`: a Radial Gradient (its radius edited), no kernel at all;
/// - `field-4c`: the first tint, selecting the Remap, when the kernel measures the bracket's mesh and the slice's grid
///   (recorded, no budget).
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct FieldBenchPreview {
    static let budget = 150.0
    static let steps = 40

    /// Runs `steps` edits and returns the command-to-frame time of each.
    func measure(_ name: String, in bench: FieldBenchApp, edit: (Int) throws -> Void) async throws -> BenchSamples {
        let input = AppInput(model: bench.app)
        let renderer = try BenchRenderer()
        renderer.place(bench.app)
        var total = BenchSamples(name)
        let clock = ContinuousClock()
        for step in 0..<Self.steps {
            let begin = clock.now
            try edit(step)
            await bench.app.settle()
            let scene = renderer.windowScene(bench.app, input: input)
            try renderer.drawViewport(bench.app.viewport)
            try renderer.composite(scene)
            total.append(from: begin, to: clock.now)
        }
        return total
    }

    @Test func anEditToTheRemapOfTheBracketsDistance() async throws {
        guard Bench.requireRelease() else { return }
        let bench = try await FieldBenchApp()
        let clock = ContinuousClock()
        var first = BenchSamples("field-4c first tint of the bracket by its signed distance (kernel)")
        let begin = clock.now
        bench.select(bench.remap)
        await bench.app.settle()
        first.append(from: begin, to: clock.now)
        let samples = try await measure("field-4 edit to a tinted bracket preview (Remap of the signed distance)", in: bench) {
            try bench.setFromHigh(20 + Double($0 + 1) * 0.1)
        }
        #expect(bench.app.viewport.items.first?.fieldValues != nil && bench.app.viewport.slice != nil)
        #expect(bench.app.document.results[bench.remap.id]?.state.isSuccess == true)
        print(first.line())
        print(samples.line(budget: Self.budget))
    }

    @Test func anEditToARadialGradientOnTheBracket() async throws {
        guard Bench.requireRelease() else { return }
        let bench = try await FieldBenchApp()
        bench.select(bench.radial)
        await bench.app.settle()
        let samples = try await measure("field-4b edit to a tinted bracket preview (Radial Gradient)", in: bench) {
            try bench.setRadius(40 + Double($0 + 1) * 0.5)
        }
        #expect(bench.app.viewport.items.first?.fieldValues != nil && bench.app.viewport.slice != nil)
        #expect(bench.app.document.results[bench.radial.id]?.state.isSuccess == true)
        print(samples.line(budget: Self.budget))
    }
}
