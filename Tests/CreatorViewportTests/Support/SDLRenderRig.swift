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
    let picker: SDLViewportPicker
    let target: SDLGPUTexture

    /// `labelAtlas` is the cube's face names: the installed fonts' by default.
    init(labelAtlas: CubeLabelAtlas = CubeLabelFonts.atlas()) throws {
        guard let device = SDLTestDevice.shared, let pipelines = SDLTestDevice.pipelines else {
            throw SDLRigError(description: "no SDL_GPU device: \(SDLGPUDevice.lastFailure)")
        }
        self.device = device
        renderer = SDLViewportRenderer(device: device, pipelines: pipelines, labelAtlas: labelAtlas)
        picker = SDLViewportPicker(renderer: renderer)
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

    /// Uploads the meshes `frame` shows, as a draw would, without drawing.
    func prepare(_ frame: ViewportFrame) async throws {
        let boxed = Handoff(value: frame)
        let renderer = renderer
        let device = device
        let fence = try await device.submitBatch { commandBuffer in
            renderer.prepareMeshes(for: boxed.value, SDLViewportUploader(device: device, commandBuffer: commandBuffer))
        }
        await fence.wait()
    }

    /// The face or edge under `point` in `frame`, from a read-back ID pass (the picker the app uses).
    func pick(at point: ScreenPoint, in frame: ViewportFrame) async throws -> PickTarget? {
        try await prepare(frame)
        await picker.refresh(frame)
        return picker.pick(at: point, in: frame)
    }

    /// ``pick(at:in:)`` for each of `points`, from one ID pass (no loop here holds locals across an `await`).
    func picks(at points: [ScreenPoint], in frame: ViewportFrame) async throws -> [PickTarget?] {
        try await prepare(frame)
        await picker.refresh(frame)
        return points.map { picker.pick(at: $0, in: frame) }
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
