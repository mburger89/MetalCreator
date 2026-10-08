// Test fixture file: one-solid ViewportFrames for the renderer tests.
import CreatorGeometry
import CreatorKernel
@testable import CreatorViewport

enum TestFrames {
    static func frame(mesh: DisplayMesh, pose: CameraPose, size: ViewportSize, bounds: BoundingBox?) -> ViewportFrame {
        ViewportFrame(pose: pose, size: size, sceneBounds: bounds,
                      items: [FrameItem(meshSerial: 1, mesh: mesh, solidIndex: 0, isGhost: false, hoveredFace: nil,
                                        selectedFaces: [], selectedEdges: []),
                      ],
                      shading: .shadedEdges, gridSpacing: 10, handles: [], cube: ViewCubeLayout(),
                      hoveredCubeRegion: nil, triad: TriadLayout())
    }
}
