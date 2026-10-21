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
    /// The measured element requests of a steady orbit-panel-left step are 199 (scripts/bench.sh, the 2026-10-20 C14-d run; the
    /// bound was 2 × 332 until then; a cold frame: 4,572); the bound is twice that.
    static let elementRequestBound = 2 * 199

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
}
#endif
