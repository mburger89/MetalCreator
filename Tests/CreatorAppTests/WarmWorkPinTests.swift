#if canImport(CreatorOCCT)
import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorViewport
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// A steady warm orbit step, counted by work and never by time, so a regression in MetalUI's retained skip and graft (C14b,
/// C14b-2, C14-c, C14b-3) or in what the panels re-evaluate shows in plain `swift test` without a bench run. The bench's
/// warm rows (`OrbitBench`, docs/verification/performance.md) time the same step; the cold rows build a fresh `Frame` each
/// frame and can never see this.
@MainActor
struct WarmWorkPinTests {
    /// The measured element requests of a steady orbit-panel-left step are 130 (scripts/bench.sh, the 2026-10-21 C14-f and C14-h
    /// run, with `GraphPanel` `.equatable()` at its call site again; 199 on 2026-10-20, 332 before C14-d; a cold frame: 4,572);
    /// the bound is twice that.
    static let elementRequestBound = 2 * 130

    @Test func aSteadyWarmOrbitStepWithThePanelDockedLeftDoesAlmostNoWork() async throws {
        let (app, _) = try await makeBracketBenchApp()
        app.editor.setDock(.left)
        await app.settle()
        let warm = try await WarmBenchWindow(model: app)
        let start = ScreenPoint(900, 450)
        var last = FrameWork()
        for step in 0..<20 {
            app.viewport.dragChanged(from: start, to: ScreenPoint(900 + Double(step) * 4, 450 + Double(step)), modifiers: [],
                                     button: .secondary)
            await app.settle()
            last = warm.frame()
            guard step >= 10 else { continue }
            #expect(last.retainedIneligible == 0, "step \(step): \(last.retainedIneligibleReasons)")
            #expect(last.retainedRedos == 0, "step \(step)")
            #expect(last.rasterizedPixels == 0, "step \(step)")
            #expect(last.elementRequests < Self.elementRequestBound, "step \(step): \(last.elementRequests) element requests")
        }
        app.viewport.dragEnded(from: start, at: ScreenPoint(1340, 560), modifiers: [], button: .secondary)
    }

    /// The measured element requests of a warm pan of the 50-node graph are a median 192 and a max 468 (scripts/bench.sh,
    /// the 2026-10-20 C14-g run; 1,409 / 1,697 before MetalUI C14-g, which stopped refusing the translated replay of a ledger
    /// that carries accessibility records). The bound is twice the median.
    static let panElementRequestBound = 2 * 192

    @Test func aSteadyWarmPanOfFiftyNodesGraftsAndNeverRedoes() async throws {
        let app = await makeApp(FiftyNodeGraph.make())
        let warm = try await WarmBenchWindow(model: app)
        var requests: [Int] = []
        for step in 0..<40 {
            app.editor.transform = CanvasTransform(offset: Vector2(-Double(step) * 16, -Double(step) * 2), zoom: 1)
            await app.settle()
            let work = warm.frame()
            guard step >= 10 else { continue }
            requests.append(work.elementRequests)
            #expect(work.retainedGrafts > 0, "step \(step)")
            #expect(work.retainedRedos == 0, "step \(step)")
        }
        let median = requests.sorted()[requests.count / 2]
        #expect(median < Self.panElementRequestBound, "median \(median) element requests")
    }

    /// The measured element requests of a warm zoom of the 50-node graph are a median 192 and a max 962 (scripts/bench.sh,
    /// the 2026-10-21 C14-i run, identical across two runs; 1,857 / 2,879 before MetalUI C14-i, which stopped refusing an
    /// affine change of the render effect above an `.equatable()` occurrence). The bound is the median plus 15%.
    static let zoomElementRequestBound = 220

    @Test func aSteadyWarmZoomOfFiftyNodesGraftsAndNeverRedoes() async throws {
        let app = await makeApp(FiftyNodeGraph.make())
        let warm = try await WarmBenchWindow(model: app)
        var transform = CanvasTransform()
        var requests: [Int] = []
        for step in 0..<130 {
            transform = transform.zoomed(by: step < 65 ? 0.979 : 1 / 0.979, around: .zero)
            app.editor.transform = transform
            await app.settle()
            let work = warm.frame()
            guard step >= 10 else { continue }
            requests.append(work.elementRequests)
            #expect(work.retainedRedos == 0, "step \(step)")
        }
        let median = requests.sorted()[requests.count / 2]
        #expect(median < Self.zoomElementRequestBound, "median \(median) element requests")
    }

    /// The worst warm frame of the fillet drag uploaded 338 to 442 atlas pixels across the 2026-10-21 C14-f runs (the radius
    /// readout's digits are the only new glyphs); before MetalUI C14-f one dirty rect spanning the atlas gave about 26,390 at
    /// step 51. The bound is a little over twice the largest measurement, still 30 times below the old spike.
    static let filletAtlasUploadBound = 900

    /// The warm fillet drag's retained misses per frame, with MetalUI C14-j (PR #120, b1c1269f: an `.equatable()` occurrence whose
    /// value changes costs one miss): the release bench (scripts/bench.sh, 2026-10-22) counts a median 9 and a max 14 per frame with
    /// 44 to 47 hits, and this test, in a debug build, a worst frame of 17. Before C14-j a changed occurrence cost 16 + 16 = 32
    /// misses. The bound leaves headroom over the debug worst and stays well below the old count.
    static let filletRetainedMissBound = 20

    @Test func aWarmFilletDragUploadsOnlyTheInsertedGlyphsToTheAtlas() async throws {
        let (app, bracket) = try await makeBracketBenchApp()
        app.editor.selection = [bracket.fillet.id]
        await app.settle()
        let handle = try #require(app.viewport.handles.first, "the selected Fillet shows its radius handle")
        let warm = try await WarmBenchWindow(model: app)
        var worst = 0
        var worstMisses = 0
        for step in 0..<75 {
            app.handleChanged(handle.id, 2 + Double(step) * 0.02, .changed)
            await app.settle()
            let work = warm.frame()
            guard step >= 10 else { continue }
            worst = max(worst, work.atlasUploadPixels)
            worstMisses = max(worstMisses, work.retainedMisses)
        }
        app.handleChanged(handle.id, 3.48, .ended)
        #expect(worst < Self.filletAtlasUploadBound, "worst warm frame uploaded \(worst) atlas pixels")
        #expect(worstMisses <= Self.filletRetainedMissBound, "worst warm frame missed \(worstMisses) retained entries (C14-j)")
    }
}
#endif
