import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// The cut view's plane (implicit spec §5.1): the host's value, the model's state, and what the shaders are given.
@MainActor
struct ViewportClipTests {
    @Test func theNormalPointsToTheSideThatIsCutAway() {
        let clip = ViewportClip(origin: Vector3(0, 0, 15), normal: Vector3(0, 0, 2))
        #expect(clip.removes(Vector3(1, 2, 20)) && !clip.removes(Vector3(1, 2, 10)))
        #expect(!clip.removes(Vector3(1, 2, 15)), "a point on the plane stays")
        #expect(clip.isValid)
    }

    @Test func aPlaneWithNoDirectionOrNoPositionIsInvalid() {
        #expect(!ViewportClip(origin: .zero, normal: .zero).isValid)
        #expect(!ViewportClip(origin: Vector3(.nan, 0, 0), normal: .unitZ).isValid)
        #expect(!ViewportClip(origin: .zero, normal: Vector3(0, .infinity, 0)).isValid)
        #expect(!ViewportClip(origin: .zero, normal: .zero).removes(Vector3(1, 1, 1)))
    }

    @Test func theShadersGetTheUnitNormalAndTheDistance() {
        let uniforms = ClipUniforms(ViewportClip(origin: Vector3(0, 0, 15), normal: Vector3(0, 0, 2)))
        #expect(uniforms.enabled == 1 && uniforms.plane == SIMD4<Float>(0, 0, 1, -15))
        #expect(ClipUniforms(nil).enabled == 0 && ClipUniforms.off.enabled == 0)
        #expect(ClipUniforms(ViewportClip(origin: .zero, normal: .zero)).enabled == 0, "an invalid plane cuts nothing")
        #expect(MemoryLayout<ClipUniforms>.stride == 32)
    }

    @Test func theModelCarriesTheClipIntoTheFrameAndTheRenderKey() async throws {
        let model = ViewportModel(kernel: StubMeshKernel(), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.show([ViewportItem(solid: try await fakeBox())])
        await model.waitForMeshes()
        #expect(model.clip == nil && model.frame(at: 0).clip == nil)
        let key = model.renderKey
        let bounds = try #require(model.sceneBounds)
        let clip = ViewportClip(origin: bounds.center, normal: .unitZ)
        model.showClip(clip)
        #expect(model.frame(at: 0).clip == clip && model.renderKey != key, "a new plane redraws")
        let shown = model.renderKey
        model.showClip(clip)
        #expect(model.renderKey == shown, "an equal plane changes nothing")
        model.showClip(ViewportClip(origin: bounds.center, normal: .unitX))
        #expect(model.renderKey != shown, "a moved or turned plane redraws")
        #expect(model.sceneBounds == bounds, "the plane is no part of the scene")
        model.showClip(nil)
        #expect(model.clip == nil && model.renderKey == key)
    }

    @Test func anInvalidPlaneIsNoPlane() {
        let model = ViewportModel(kernel: StubMeshKernel(), clock: ManualClock())
        model.showClip(ViewportClip(origin: .zero, normal: .zero))
        #expect(model.clip == nil)
    }

    @Test func aFaceCanBeMarkedAsAWarningAndTheFrameCarriesIt() async throws {
        let model = ViewportModel(kernel: StubMeshKernel(), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.show([ViewportItem(solid: try await fakeBox(), warningFaces: [FaceID(1)])])
        await model.waitForMeshes()
        #expect(model.frame(at: 0).items.first?.warningFaces == [FaceID(1)])
        #expect(GPUGeometry.faceFlags(count: 3, hovered: FaceID(0), selected: [FaceID(0)], warning: [FaceID(0), FaceID(2), FaceID(7)])
            == [7, 0, 4])
    }
}
