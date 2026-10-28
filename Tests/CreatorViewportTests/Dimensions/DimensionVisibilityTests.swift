import CreatorGeometry
import Foundation
import Testing
@testable import CreatorViewport

/// What the model does with dimensions: they are no part of the scene or the render, they follow the camera, and their
/// texts are hit-tested by the model.
@MainActor
struct DimensionVisibilityTests {
    func makeModel() -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: topDownPose(pointsPerMillimetre: 2), clock: ManualClock())
        model.viewSize = dimensionTestSize
        return model
    }

    @Test func dimensionsAreNeitherSceneNorRender() async throws {
        let model = makeModel()
        model.show([ViewportItem(solid: try await fakeBox())])
        await model.waitForMeshes()
        let (key, bounds, generation) = (model.renderKey, model.sceneBounds, model.sceneGeneration)
        #expect(bounds != nil)
        model.showDimensions([sixtyMillimetres(), sixtyMillimetres(id: "b")])
        #expect(model.dimensions.count == 2)
        #expect(model.renderKey == key)
        #expect(model.sceneBounds == bounds)
        #expect(model.sceneGeneration == generation)
    }

    @Test func noDimensionsWhileAnimatingOrSizeless() {
        let model = makeModel()
        model.showDimensions([sixtyMillimetres()])
        #expect(model.placedDimensions(measuring: .eightPerCharacter).count == 1)
        model.perform(.view(.front))
        #expect(model.isAnimating)
        #expect(model.placedDimensions(measuring: .eightPerCharacter).isEmpty)
        #expect(model.dimension(at: ScreenPoint(200, 100)) == nil, "nothing drawn, nothing to hit")

        let blank = makeModel()
        blank.viewSize = ViewportSize(width: 0, height: 0)
        blank.showDimensions([sixtyMillimetres()])
        #expect(blank.placedDimensions(measuring: .eightPerCharacter).isEmpty)
    }

    @Test func placedDimensionsFollowTheListOrderAndLeaveOutWhatCannotBePlaced() {
        let model = makeModel()
        let degenerate = OverlayDimension(id: OverlayDimensionID("zero"),
                                          geometry: .linear(from: .zero, to: .zero, direction: .unitX, side: .unitY,
                                                            placement: .standoff),
                                          text: "0", tint: .dimensionDriving)
        model.showDimensions([sixtyMillimetres(id: "b"), degenerate, sixtyMillimetres(id: "a")])
        #expect(model.placedDimensions(measuring: .eightPerCharacter).map(\.id.rawValue) == ["b", "a"])
    }

    @Test func theTextHitIsTheLastDrawnBox() throws {
        let model = makeModel()
        model.showDimensions([sixtyMillimetres(id: "first")])
        let placed = try #require(model.placedDimensions(measuring: .eightPerCharacter).first)
        let centre = ScreenPoint(placed.textOrigin.x + placed.textSize.width / 2, placed.textOrigin.y + placed.textSize.height / 2)
        #expect(model.dimension(at: centre) == OverlayDimensionID("first"))
        let onTheLine = ScreenPoint(placed.textOrigin.x - 10, centre.y)
        #expect(model.dimension(at: onTheLine) == nil, "the dimension line is not the text")

        model.showDimensions([sixtyMillimetres(id: "first"), sixtyMillimetres(id: "second")])
        _ = model.placedDimensions(measuring: .eightPerCharacter)
        #expect(model.dimension(at: centre) == OverlayDimensionID("second"), "boxes overlap: the later one is on top")
    }

    @Test func aHitNeedsTheDimensionsToHaveBeenDrawn() throws {
        let model = makeModel()
        model.showDimensions([sixtyMillimetres()])
        #expect(model.dimension(at: ScreenPoint(200, 100)) == nil, "nothing is drawn until placedDimensions has run")
    }
}
