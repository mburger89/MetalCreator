import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorViewport

/// Guides (spec §6.3, Errata (M6)): the selected edges of a solid the scene doesn't show, drawn over the part. A guide
/// is no part of the scene: it never frames, orbits or picks. (How they draw: `GuideRenderTests`.)
@MainActor
struct ViewportGuideTests {
    func makeModel(pose: CameraPose? = nil) -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: pose, clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        return model
    }

    func show(_ model: ViewportModel, _ items: [ViewportItem]) async {
        model.show(items)
        await model.waitForMeshes()
    }

    @Test func aGuideNeverWidensTheFramedScene() async throws {
        let model = makeModel()
        let part = try await fakeBox()
        let faraway = try await fakeBox(width: 400, depth: 400, height: 400)
        await show(model, [ViewportItem(solid: part),
                           ViewportItem(solid: faraway, selectedEdges: [EdgeID(1)], isGuide: true),
        ])
        #expect(model.items.count == 2)
        #expect(model.sceneBounds == part.bounds)
        #expect(isClose(model.pose.target, part.bounds.center), "the first framing ignores the guide")
    }

    @Test func aGuideAloneIsNotASceneAndHasNothingToOrbitAbout() async throws {
        let model = makeModel()
        let guide = try await fakeBox(width: 400, depth: 400, height: 400)
        await show(model, [ViewportItem(solid: guide, selectedEdges: [EdgeID(1)], isGuide: true)])
        #expect(model.sceneBounds == nil)
        #expect(model.pivotPoint(under: ScreenPoint(200, 150)) == nil, "a ray through a guide's surface isn't a hit")
        let part = try await fakeBox()
        await show(model, [ViewportItem(solid: part)])
        #expect(isClose(model.pose.target, part.bounds.center), "a guide-only scene didn't use up the first framing")
    }

    @Test func aGuidesSelectedEdgesAreWhatFramingTheSelectionFrames() async throws {
        let model = makeModel(pose: CameraPose())
        let part = try await fakeBox()
        let guide = try await fakeBox(width: 100, depth: 100, height: 100)
        await show(model, [ViewportItem(solid: part), ViewportItem(solid: guide, selectedEdges: [EdgeID(1)], isGuide: true)])
        let bounds = try #require(model.selectionBounds())
        #expect(isClose(bounds.size.x, guide.bounds.size.x), "edge 1 spans the guide's width, not the part's")
    }

    @Test func theFrameCarriesTheGuideFlag() async throws {
        let model = makeModel(pose: CameraPose())
        await show(model, [ViewportItem(solid: try await fakeBox()),
                           ViewportItem(solid: try await fakeBox(width: 3), selectedEdges: [EdgeID(1)], isGuide: true),
        ])
        let frame = model.frame(at: 0)
        #expect(frame.items.map(\.isGuide) == [false, true])
        #expect(frame.items[1].selectedEdges == [EdgeID(1)])
        #expect(frame.sceneBounds == model.sceneBounds)
    }
}
