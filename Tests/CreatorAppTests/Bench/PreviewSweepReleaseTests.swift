import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import MetalUI
import Testing
@testable import CreatorApp

/// The retention check behind the preview sweep's footprint readings: a document's meshes are freed when its app is released, even
/// after the window has drawn frames (a dry run's footprint climbed rung after rung; `leaks` found nothing, the weak references
/// here found every app, viewport and mesh freed, and the climb was MetalUI's `.equatable()` memo and malloc, see
/// docs/verification/performance.md and docs/metalui-gaps.md PERF-c).
@MainActor
struct PreviewSweepReleaseTests {
    /// An app showing a small mesh of the sweep's sheet, after `frames` window frames drawn headless, then released.
    private func release(afterFrames frames: Int) async throws -> PreviewSweepRelease {
        let atlas = GlyphAtlas(width: 1024, height: 1024)
        let text = testTextSystem()
        let sheet = PreviewSweepFixtures.sheet(side: 20)
        let graph = PreviewSweepFixtures.previewing(sheet.graph, at: 0.8)
        var watch: PreviewSweepRelease
        do {
            let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: graph), implicitEngine: .automatic)
            await app.settle()
            await app.meshRefinement.waitForRefinement()
            await app.settle()
            await app.viewport.waitForMeshes()
            let shown = try #require(app.viewport.items.first?.solid.displayedMesh)
            #expect(shown.indices.count > 0)
            watch = PreviewSweepRelease(app: app, renderer: nil, solids: app.viewport.items.map(\.solid))
            #expect(watch.survivors.contains("AppModel") && watch.survivors.contains("1 mesh storage"), "the watch sees them alive")
            ExpectedLayout.place(app, window: Vector2(1440, 900))
            let input = AppInput(model: app)
            for _ in 0..<frames {
                _ = renderFrame({ ZStack { AppRoot(model: app, input: input) } }, size: Size(width: Pixels(1440), height: Pixels(900)),
                                scaleFactor: 2, textSystem: text, atlas: atlas)
            }
        }
        await Task.yield()
        return watch
    }

    @Test func aReleasedAppFreesItsMeshBeforeAnyFrame() async throws {
        let watch = try await release(afterFrames: 0)
        #expect(watch.survivors.isEmpty, "still alive: \(watch.survivors)")
    }

    @Test func aReleasedAppFreesItsMeshAfterDrawingFrames() async throws {
        let watch = try await release(afterFrames: 3)
        #expect(watch.survivors.isEmpty, "still alive: \(watch.survivors)")
    }
}
