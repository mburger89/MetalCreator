import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// The model carries an item's field values to the frame the renderer draws, and lends the host its meshes to sample.
@MainActor
struct FieldTintModelTests {
    let ramp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: 0...1)

    @Test func anItemWithoutAFieldHasNone() async throws {
        let item = ViewportItem(solid: try await fakeBox())
        #expect(item.fieldValues == nil && item.fieldRamp == nil)
    }

    @Test func theValuesReachTheFrameAndTheHostCanReadTheMesh() async throws {
        let box = try await fakeBox()
        let model = ViewportModel(kernel: StubMeshKernel(), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        #expect(model.displayMesh(of: box) == nil, "nothing is loaded before a scene is shown")
        let mesh = TestMeshes.box(box.bounds)
        let values = (0..<mesh.positions.count).map { Float($0) / 24 }
        model.show([ViewportItem(solid: box, fieldValues: values, fieldRamp: ramp)])
        await model.waitForMeshes()
        #expect(model.displayMesh(of: box)?.positions.count == mesh.positions.count)
        #expect(model.items[0].fieldValues == values && model.items[0].fieldRamp == ramp)
        let frame = model.frame(at: 0)
        #expect(frame.items[0].fieldValues == values && frame.items[0].fieldRamp == ramp)
    }

    @Test func aSceneWithoutValuesHasAFrameWithout() async throws {
        let box = try await fakeBox()
        let model = ViewportModel(kernel: StubMeshKernel(), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.show([ViewportItem(solid: box)])
        await model.waitForMeshes()
        #expect(model.frame(at: 0).items[0].fieldValues == nil)
    }
}
