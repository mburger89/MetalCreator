// Test fixture file: a renderer and a target to draw into, and the pixels back.
#if canImport(MetalUISDLGPU)
import Foundation
import MetalUISDLGPU
import Testing
@testable import CreatorViewport

/// A renderer and a 400 × 400 target (2 pixels per point, as the 200 × 200 point frames of `RenderFixtures` need).
@MainActor
final class SDLRenderRig {
    static let pixels = 400
    let device: SDLGPUDevice
    let renderer: SDLViewportRenderer
    let target: SDLGPUTexture

    init() throws {
        guard let device = SDLTestDevice.shared, let pipelines = SDLTestDevice.pipelines else {
            throw SDLRigError(description: "no SDL_GPU device: \(SDLGPUDevice.lastFailure)")
        }
        self.device = device
        renderer = SDLViewportRenderer(device: device, pipelines: pipelines)
        guard let target = device.makeTexture(SDLGPUTextureDescription(
            width: Self.pixels, height: Self.pixels, format: .b8g8r8a8Unorm, usage: [.colorTarget, .sampler])) else {
            throw SDLRigError(description: "the target texture could not be made")
        }
        self.target = target
    }

    /// Draws `frame` (`scale` pixels per point) in a batch, waits for the GPU and reads the target back as BGRA bytes.
    @discardableResult
    func draw(_ frame: ViewportFrame, scale: Double = 2) async throws -> [UInt8] {
        let boxed = Handoff(value: frame)
        let renderer = renderer
        let target = target
        let fence = try await device.submitBatch { commandBuffer in
            renderer.encode(boxed.value, into: target, scale: scale, commandBuffer: commandBuffer)
        }
        await fence.wait()
        guard let bytes = await device.download(target) else { throw SDLRigError(description: "the target could not be read back") }
        return bytes
    }

    /// The colour at view point (`x`, `y`) of a 400 × 400 draw at 2 pixels per point, as red, green and blue.
    static func color(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let at = (y * 2 * pixels + x * 2) * 4
        return [Int(bytes[at + 2]), Int(bytes[at + 1]), Int(bytes[at])]
    }

    /// A palette colour as the bytes the target holds: red, green, blue.
    static func bytes(_ colour: SIMD4<Float>) -> [Int] {
        [colour.x, colour.y, colour.z].map { Int(($0 * 255).rounded()) }
    }
}
#endif
