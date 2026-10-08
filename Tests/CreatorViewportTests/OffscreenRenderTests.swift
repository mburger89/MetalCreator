import CreatorGeometry
import CreatorKernel
import CreatorOCCT
import Foundation
import Metal
import Testing
@testable import CreatorViewport

/// Spec §8's offscreen render test: the ID pass on a known solid returns the expected face and edge IDs at chosen
/// pixels. Pixel colours are never compared.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct OffscreenRenderTests {
    /// Front view, orthographic, 5 points per mm, centred on (0, 0, 15). A 10 × 20 × 30 box standing on z = 0
    /// fills x 75…125 and y 25…175 of a 200 × 200 view.
    static let front = CameraPose(target: Vector3(0, 0, 15), distance: 20 / tan(CameraPose.fieldOfView / 2),
                                  yaw: 0, pitch: 0, projection: .orthographic)
    static let size = ViewportSize(width: 200, height: 200)

    func box() async throws -> (frame: ViewportFrame, solid: Solid) {
        let kernel = OCCTKernel()
        let solid = try await kernel.extrude(.rectangle(width: 10, height: 20, plane: .xy), distance: 30, mode: .oneSided,
                                             tag: NodeTag(node: NodeID(), item: 0))
        let mesh = try await kernel.tessellate(solid, tolerance: 0.05)
        return (TestFrames.frame(mesh: mesh, pose: Self.front, size: Self.size, bounds: solid.bounds), solid)
    }

    /// Commits and blocks until the GPU is done. It's synchronous on purpose: `waitUntilCompleted` is unavailable in
    /// async code, and `await completed()` would send the non-Sendable buffer off the main actor.
    func commitAndWait(_ commandBuffer: any MTLCommandBuffer) {
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    func makePicker() throws -> ViewportPicker {
        let device = try #require(MTLCreateSystemDefaultDevice())
        return try ViewportPicker(renderer: try ViewportRenderer(device: device))
    }

    @Test func theShadersCompileIntoEveryPipeline() throws {
        _ = try makePicker()
    }

    @Test func idPassReportsTheFaceAndEdgeUnderChosenPixels() async throws {
        let (frame, solid) = try await box()
        let front = try #require(solid.topology.faces.first { ($0.normal ?? .zero).dot(Vector3(0, -1, 0)) > 0.999 })
        let top = try #require(solid.topology.faces.first { ($0.normal ?? .zero).dot(.unitZ) > 0.999 })
        let topFront = try #require(solid.topology.edges.first { Set($0.faces) == [front.id, top.id] })
        let picker = try makePicker()
        #expect(picker.pick(at: ScreenPoint(100, 100), in: frame) == .face(solid: 0, front.id))
        #expect(picker.pick(at: ScreenPoint(80, 160), in: frame) == .face(solid: 0, front.id))
        #expect(picker.pick(at: ScreenPoint(100, 26), in: frame) == .edge(solid: 0, topFront.id),
                "1.5 points below the top edge is inside its 6-point pick width")
        #expect(picker.pick(at: ScreenPoint(100, 10), in: frame) == nil)
        #expect(picker.pick(at: ScreenPoint(160, 100), in: frame) == nil)
    }

    @Test func picksOutsideTheViewOrBeforeItHasASizeAreNil() async throws {
        let (frame, _) = try await box()
        let picker = try makePicker()
        for point in [ScreenPoint(-1, 100), ScreenPoint(100, -0.5), ScreenPoint(200, 100), ScreenPoint(100, 200),
                      ScreenPoint(.nan, 3), ScreenPoint(.infinity, 3)] {
            #expect(picker.pick(at: point, in: frame) == nil, "\(point)")
        }
        var empty = frame
        empty.size = ViewportSize(width: 0, height: 0)
        #expect(picker.pick(at: ScreenPoint(0, 0), in: empty) == nil)
    }

    @Test func theIDBufferIsReusedUntilTheCameraMoves() async throws {
        let (frame, _) = try await box()
        let picker = try makePicker()
        _ = picker.pick(at: ScreenPoint(100, 100), in: frame)
        _ = picker.pick(at: ScreenPoint(90, 120), in: frame)
        #expect(picker.renderCount == 1)
        var turned = frame
        turned.pose.yaw += 0.1
        _ = picker.pick(at: ScreenPoint(100, 100), in: turned)
        #expect(picker.renderCount == 2)
    }

    @Test func theShadedPassEncodesEveryLayerCleanly() async throws {
        let (base, _) = try await box()
        var frame = base
        frame.items[0].hoveredFace = FaceID(0)
        frame.items[0].selectedFaces = [FaceID(1)]
        frame.items[0].selectedEdges = [EdgeID(0)]
        frame.items.append(FrameItem(meshSerial: 2, mesh: base.items[0].mesh, solidIndex: 1, isGhost: true,
                                     hoveredFace: nil, selectedFaces: [], selectedEdges: []))
        frame.handles = [ViewportHandle(id: "h", anchor: .zero, direction: .unitZ, value: 30, range: 0...100,
                                        style: .linear, tint: .solid)]
        frame.hoveredCubeRegion = .top
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try ViewportRenderer(device: device)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 400, height: 400,
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let target = try #require(device.makeTexture(descriptor: descriptor))
        let queue = try #require(device.makeCommandQueue())
        for shading in ShadingMode.allCases {
            frame.shading = shading
            let commandBuffer = try #require(queue.makeCommandBuffer())
            renderer.encode(frame, into: target, scale: 2, commandBuffer: commandBuffer)
            commitAndWait(commandBuffer)
            #expect(commandBuffer.status == .completed)
            #expect(commandBuffer.error == nil)
        }
        #expect(renderer.encodedPasses == 2)
    }

    @Test func aTargetOfTheWrongFormatIsLeftAlone() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try ViewportRenderer(device: device)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 8, height: 8, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .private
        let target = try #require(device.makeTexture(descriptor: descriptor))
        let commandBuffer = try #require(device.makeCommandQueue()?.makeCommandBuffer())
        let frame = TestFrames.frame(mesh: TestMeshes.box(BoundingBox(min: .zero, max: Vector3(1, 1, 1))), pose: Self.front,
                                     size: ViewportSize(width: 8, height: 8), bounds: nil)
        renderer.encode(frame, into: target, scale: 1, commandBuffer: commandBuffer)
        #expect(renderer.encodedPasses == 0)
    }
}
