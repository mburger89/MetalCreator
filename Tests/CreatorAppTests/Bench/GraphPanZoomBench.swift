import CreatorEditor
import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorApp

/// Spec §7.3: "Panning and zooming a 50-node graph runs at 60 fps on the development Mac." The app over `FakeKernel`
/// (the canvas doesn't care what evaluates), the graph panel docked left at its default size in a 1440 × 900 window.
/// Each frame is a canvas transform step (what a scroll or pinch step sets) followed by the whole window's frame: a pan
/// or zoom changes `ViewState`, which every node view reads, so MetalUI rebuilds the window (gap PERF-b). Prints
/// `BENCH pan-50 …` and `BENCH zoom-50 …`.
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct GraphPanZoomBench {
    static let warmUp = 10

    /// The nodes the canvas builds this frame.
    static func nodesBuilt(_ app: AppModel) -> Int { app.editor.drawOrder.count }

    /// Runs `transforms` as frames and prints the model step, the window's CPU frame and its GPU composite.
    func run(_ name: String, transforms: [CanvasTransform]) async throws {
        guard Bench.requireRelease() else { return }
        let app = await makeApp(FiftyNodeGraph.make())
        try #require(app.editor.dock == .left, "the paths below are drawn for the left dock's flow (rows run across)")
        let input = AppInput(model: app)
        let renderer = try BenchRenderer()
        renderer.place(app)
        var model = BenchSamples("\(name) model"), cpu = BenchSamples("\(name) window-cpu")
        var gpu = BenchSamples("\(name) window-gpu"), built = BenchSamples("\(name) nodes-built")
        let clock = ContinuousClock()
        for (index, transform) in transforms.enumerated() {
            let start = clock.now
            app.editor.transform = transform
            await app.settle()
            let stepped = clock.now
            let scene = renderer.windowScene(app, input: input)
            let painted = clock.now
            try renderer.composite(scene)
            let drawn = clock.now
            guard index >= Self.warmUp else { continue }
            model.append(from: start, to: stepped)
            built.append(Double(Self.nodesBuilt(app)))
            cpu.append(from: stepped, to: painted)
            gpu.append(from: painted, to: drawn)
        }
        print("BENCH \(name) nodes built of 50: median \(Int(built.median)), max \(Int(built.maximum))")
        print(model.line())
        print(cpu.line(budget: Bench.frameBudget))
        print(gpu.line(budget: Bench.frameBudget))
    }

    /// 130 frames at zoom 1, panning along the rows (docked left, they run across the canvas) from the first row to
    /// the last, drifting down a little.
    @Test func panningFiftyNodes() async throws {
        let transforms = (0..<130).map { step in
            CanvasTransform(offset: Vector2(-Double(step) * 16, -Double(step) * 2), zoom: 1)
        }
        try await run("pan-50", transforms: transforms)
    }

    /// 130 frames zooming about the canvas's top-left corner from 1 down to 0.25 (most of the graph in view) and back
    /// up to 1.
    @Test func zoomingFiftyNodes() async throws {
        var transform = CanvasTransform()
        var transforms: [CanvasTransform] = []
        for step in 0..<130 {
            transform = transform.zoomed(by: step < 65 ? 0.979 : 1 / 0.979, around: .zero)
            transforms.append(transform)
        }
        try await run("zoom-50", transforms: transforms)
    }
}
