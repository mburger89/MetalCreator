#if canImport(MetalUISDLGPU)
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorViewport

/// XP-21: an empty document's camera (`CameraPose()`: target at the origin, pitch 0, perspective) puts the eye exactly in the ground
/// grid's plane z = 0. The grid is then edge-on, a line with no area, but the perspective divide of its near corners (behind the eye)
/// turned float noise into a huge blue-grey triangle that depended on the window's aspect (seen on Linux llvmpipe at 1854 × 1168, not at
/// 1440 × 900). A model's target lifts the eye off the plane, which is why the garble went away once something was wired.
@MainActor
@Suite(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
struct SDLEdgeOnGridTests {
    typealias Rig = SDLRenderRig

    /// Window sizes (points) of different aspect ratios, among them the ones the human check used.
    nonisolated static let sizes = [(200.0, 200.0), (257, 163), (309, 195), (163, 257), (1854, 1168), (1440, 900)]

    @Test(arguments: sizes) func anEmptySceneSeenEdgeOnDrawsNoGrid(width: Double, height: Double) async throws {
        let rig = try Rig()
        var frame = RenderFixtures.emptyFrame()
        frame.pose = CameraPose()
        frame.size = ViewportSize(width: width, height: height)
        let bytes = try await rig.draw(frame)
        // The background is a vertical gradient, so within a row the right half (clear of the cube and the triad, at the left) is uniform.
        for row in stride(from: 60, to: 140, by: 10) {
            let centre = Rig.color(bytes, 150, row)
            for x in stride(from: 110, through: 190, by: 10) {
                let colour = Rig.color(bytes, x, row)
                for channel in 0..<3 {
                    #expect(abs(colour[channel] - centre[channel]) <= 3, "row \(row), x \(x): \(colour) against \(centre)")
                }
            }
        }
    }
}
#endif
