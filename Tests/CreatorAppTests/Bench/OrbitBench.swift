#if canImport(Metal)
import CreatorGraph
import CreatorViewport
import Testing
@testable import CreatorApp

/// Spec §7.3: "Orbiting the viewport with the bracket shown runs at 60 fps." The §7.2 bracket on OCCT, orbited by a
/// right-drag of 110 steps; each frame is the drag step, the whole window's frame (MetalUI rebuilds every observed
/// change, gap PERF-b, and the camera is observed by the viewport's labels) and both GPU passes. Run with the graph
/// panel docked left and hidden, to show what the panel costs. Prints `BENCH orbit-… …`.
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct OrbitBench {
    static let warmUp = 10

    @Test(arguments: [DockSide.left, .hidden])
    func orbitingTheBracket(dock: DockSide) async throws {
        guard Bench.requireRelease() else { return }
        let (app, _) = try await makeBracketBenchApp()
        app.editor.setDock(dock)
        await app.settle()
        let input = AppInput(model: app)
        let renderer = try BenchRenderer()
        renderer.place(app)
        let name = "orbit-\(dock == .hidden ? "panel-hidden" : "panel-left")"
        var model = BenchSamples("\(name) model"), cpu = BenchSamples("\(name) window-cpu (cold frame)")
        var gpu = BenchSamples("\(name) gpu (viewport + window)")
        let clock = ContinuousClock()
        let start = ScreenPoint(900, 450)
        for step in 0..<110 {
            let begin = clock.now
            app.viewport.dragChanged(from: start, to: ScreenPoint(900 + Double(step) * 4, 450 + Double(step)), modifiers: [],
                                     button: .secondary)
            await app.settle()
            let stepped = clock.now
            let scene = renderer.windowScene(app, input: input)
            let built = clock.now
            try renderer.drawViewport(app.viewport)
            try renderer.composite(scene)
            let drawn = clock.now
            guard step >= Self.warmUp else { continue }
            model.append(from: begin, to: stepped)
            cpu.append(from: stepped, to: built)
            gpu.append(from: built, to: drawn)
        }
        app.viewport.dragEnded(from: start, at: ScreenPoint(1340, 560), modifiers: [], button: .secondary)
        let nodes = app.document.graph.nodes.count
        print("BENCH \(name): " + (app.editor.isPanelVisible ? "the canvas builds \(app.editor.drawnNodes.count) of \(nodes) nodes"
                                                             : "the graph panel is hidden (\(nodes) nodes)"))
        print(model.line())
        print(cpu.line(budget: Bench.frameBudget))
        print(gpu.line(budget: Bench.frameBudget))
    }

    /// The warm row: the same drag, but the window and its `Frame` live across the steps, so MetalUI's retained skip and graft
    /// apply (the cold row above builds a fresh `Frame` every step and cannot benefit). 10 warm-up steps, then 100 timed.
    /// Prints `BENCH orbit-…-warm window-cpu (warm frame) …`, judged against the 60 fps budget.
    @Test(arguments: [DockSide.left, .hidden])
    func orbitingTheBracketWarm(dock: DockSide) async throws {
        guard Bench.requireRelease() else { return }
        let (app, _) = try await makeBracketBenchApp()
        app.editor.setDock(dock)
        await app.settle()
        let warm = try await WarmBenchWindow(model: app)
        let name = "orbit-\(dock == .hidden ? "panel-hidden" : "panel-left")-warm"
        var cpu = BenchSamples("\(name) window-cpu (warm frame)")
        var requests = BenchSamples("\(name) element-requests")
        let start = ScreenPoint(900, 450)
        for step in 0..<(Self.warmUp + 100) {
            app.viewport.dragChanged(from: start, to: ScreenPoint(900 + Double(step) * 4, 450 + Double(step)), modifiers: [],
                                     button: .secondary)
            await app.settle()
            let milliseconds = warm.timedFrame()
            guard step >= Self.warmUp else { continue }
            cpu.append(milliseconds)
            requests.append(Double(warm.window.frameWork.reduce(0) { $0 + $1.elementRequests }))
        }
        app.viewport.dragEnded(from: start, at: ScreenPoint(1340, 560), modifiers: [], button: .secondary)
        print("BENCH \(name): element requests per frame, median \(Int(requests.median)), max \(Int(requests.maximum))")
        print(cpu.line(budget: Bench.frameBudget))
    }
}
#endif
