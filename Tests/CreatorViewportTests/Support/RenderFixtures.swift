// Test fixture file: the camera and frames the renderer tests share (the SDL ones run without OpenCascade).
import CreatorGeometry
import CreatorKernel
import Foundation
@testable import CreatorViewport

enum RenderFixtures {
    /// Front view, orthographic, 5 points per mm, centred on (0, 0, 15). A 10 × 20 × 30 box standing on z = 0 fills x 75…125 and
    /// y 25…175 of a 200 × 200 view.
    static let front = CameraPose(target: Vector3(0, 0, 15), distance: 20 / tan(CameraPose.fieldOfView / 2),
                                  yaw: 0, pitch: 0, projection: .orthographic)
    static let size = ViewportSize(width: 200, height: 200)
    static let bounds = BoundingBox(min: Vector3(-5, -10, 0), max: Vector3(5, 10, 30))

    /// The box of ``bounds`` (`TestMeshes.box`: faces 0 bottom, 1 top, 2 front, 3 right, 4 back, 5 left) in the front view.
    static func boxFrame() -> ViewportFrame {
        TestFrames.frame(mesh: TestMeshes.box(bounds), pose: front, size: size, bounds: bounds)
    }

    /// A frame with nothing in it, in the front view.
    static func emptyFrame(overlay: ViewportOverlay = ViewportOverlay()) -> ViewportFrame {
        ViewportFrame(pose: front, size: size, sceneBounds: nil, items: [], shading: .shadedEdges, gridSpacing: 10, handles: [],
                      cube: ViewCubeLayout(), hoveredCubeRegion: nil, triad: TriadLayout(), overlay: overlay)
    }
}
