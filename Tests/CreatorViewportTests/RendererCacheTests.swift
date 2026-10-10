import CreatorGeometry
import Foundation
import Metal
import Testing
@testable import CreatorViewport

/// The renderer keeps the GPU buffers a frame of a continuous orbit, pan or zoom would otherwise allocate again
/// (spec §7.3's 60 fps; `ViewCubeResources` makes the same promise for the cube): the triad's, the overlay's and the
/// region fills'. A cached buffer is the very same object on the next frame; what is drawn doesn't change.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct RendererCacheTests {
    static let front = CameraPose(target: .zero, distance: 20 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: 0,
                                  projection: .orthographic)
    static let size = ViewportSize(width: 200, height: 200)

    /// A renderer and a 400 × 400 (2 pixels per point) target to draw into.
    @MainActor
    struct Rig {
        let renderer: ViewportRenderer
        let target: any MTLTexture
        let queue: any MTLCommandQueue

        init() throws {
            let device = try #require(MTLCreateSystemDefaultDevice())
            renderer = try ViewportRenderer(device: device)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 400, height: 400,
                                                                      mipmapped: false)
            descriptor.usage = .renderTarget
            descriptor.storageMode = .shared
            target = try #require(device.makeTexture(descriptor: descriptor))
            queue = try #require(device.makeCommandQueue())
        }

        /// Draws `frame` and returns the target's BGRA bytes.
        @discardableResult
        func draw(_ frame: ViewportFrame) throws -> [UInt8] {
            let commandBuffer = try #require(queue.makeCommandBuffer())
            renderer.encode(frame, into: target, scale: 2, commandBuffer: commandBuffer)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            var bytes = [UInt8](repeating: 0, count: 400 * 400 * 4)
            target.getBytes(&bytes, bytesPerRow: 400 * 4, from: MTLRegionMake2D(0, 0, 400, 400), mipmapLevel: 0)
            return bytes
        }
    }

    func frame(pose: CameraPose = front, overlay: ViewportOverlay = ViewportOverlay()) -> ViewportFrame {
        ViewportFrame(pose: pose, size: Self.size, sceneBounds: nil, items: [], shading: .shadedEdges, gridSpacing: 10,
                      handles: [], cube: ViewCubeLayout(), hoveredCubeRegion: nil, triad: TriadLayout(), overlay: overlay)
    }

    /// A sketch's overlay: the plane grid, a dashed line and a point.
    var sketch: ViewportOverlay {
        ViewportOverlay(lines: [OverlayLine(.zero, Vector3(10, 0, 10), tint: .construction, isDashed: true)],
                        points: [OverlayPoint(Vector3(10, 0, 10), tint: .fullyConstrained)], gridPlane: .xz)
    }

    func turned(_ pose: CameraPose, by yaw: Double) -> CameraPose {
        var turned = pose
        turned.yaw += yaw
        return turned
    }

    // MARK: - The triad (AV-2)

    @Test func theTriadBufferIsMadeOnceAndSurvivesAnOrbit() throws {
        let rig = try Rig()
        try rig.draw(frame())
        let first = try #require(rig.renderer.triadBuffer)
        try rig.draw(frame(pose: turned(Self.front, by: 0.3)))
        try rig.draw(frame(pose: turned(Self.front, by: 0.6)))
        let later = try #require(rig.renderer.triadBuffer)
        #expect(later.buffer === first.buffer, "an orbit turns the widget's camera, not its instances")
    }

    @Test func theTriadBufferIsRebuiltForANewPalette() throws {
        let rig = try Rig()
        try rig.draw(frame())
        let first = try #require(rig.renderer.triadBuffer)
        var other = frame()
        other.palette = ViewportPalette(.alucard)
        try rig.draw(other)
        #expect(try #require(rig.renderer.triadBuffer).buffer !== first.buffer)
    }

    // MARK: - The overlay (AV-3)

    @Test func theOverlayBufferSurvivesAnOrbitOfTheCamera() throws {
        let rig = try Rig()
        try rig.draw(frame(overlay: sketch))
        let first = try #require(rig.renderer.overlayBuffer)
        try rig.draw(frame(pose: turned(Self.front, by: 0.2), overlay: sketch))
        #expect(try #require(rig.renderer.overlayBuffer).buffer === first.buffer,
                "the grid reach and the dashes depend on the zoom and on where the grid is centred, not on the angle")
    }

    @Test func aPanWithinAGridCellKeepsTheOverlayBufferAndAZoomRebuildsIt() throws {
        let rig = try Rig()
        try rig.draw(frame(overlay: sketch))
        let first = try #require(rig.renderer.overlayBuffer)
        var panned = Self.front
        panned.target = Vector3(1, 0, 16)   // the grid is centred on the nearest major line (100 mm apart here)
        try rig.draw(frame(pose: panned, overlay: sketch))
        #expect(try #require(rig.renderer.overlayBuffer).buffer === first.buffer)
        var zoomed = Self.front
        zoomed.distance *= 2
        try rig.draw(frame(pose: zoomed, overlay: sketch))
        #expect(try #require(rig.renderer.overlayBuffer).buffer !== first.buffer, "dashes and reach follow the zoom")
    }

    /// The cache changes what is allocated, not what is drawn: a renderer that reused its buffers draws the same pixels
    /// as a new one.
    @Test func aReusedOverlayDrawsThePixelsAFreshRendererDoes() throws {
        let reused = try Rig()
        try reused.draw(frame(overlay: sketch))
        let moved = frame(pose: turned(Self.front, by: 0.2), overlay: sketch)
        let fromReused = try reused.draw(moved)
        let fromFresh = try Rig().draw(moved)
        #expect(fromReused == fromFresh)
    }

    // MARK: - The fills (AV-4)

    @Test func theFillBufferIsReusedThenReleasedWhenTheFillsGoAway() throws {
        let rig = try Rig()
        let fill = OverlayFill(vertices: [Vector3(-6, 0, 9), Vector3(6, 0, 9), Vector3(0, 0, 21)])
        let overlay = ViewportOverlay(fills: [fill])
        try rig.draw(frame(overlay: overlay))
        let first = try #require(rig.renderer.fillBuffer)
        try rig.draw(frame(overlay: overlay))
        #expect(try #require(rig.renderer.fillBuffer).buffer === first.buffer, "the same fills reuse the buffer")
        try rig.draw(frame())
        #expect(rig.renderer.fillBuffer == nil, "leaving sketch mode frees it")
    }
}
