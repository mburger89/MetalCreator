import CreatorGeometry
import CreatorKernel

extension ViewportModel {
    /// The snapshot the renderer and the picker draw at `time`: meshed items only, with hover and selection.
    func frame(at time: Double) -> ViewportFrame {
        let shown = presentedPose(at: time)
        var frameItems: [FrameItem] = []
        for (index, item) in items.enumerated() {
            guard let cached = cache.mesh(for: item.solid) else { continue }
            var hoveredFace: FaceID?
            if case .face(let solid, let face)? = hovered, solid == index { hoveredFace = face }
            frameItems.append(FrameItem(meshSerial: cached.serial, mesh: cached.mesh, solidIndex: index,
                                        isGhost: item.isGhost, hoveredFace: hoveredFace,
                                        selectedFaces: item.selectedFaces, selectedEdges: item.selectedEdges))
        }
        return ViewportFrame(pose: shown, size: viewSize, sceneBounds: sceneBounds, items: frameItems, shading: shading,
                             gridSpacing: gridSpacing(for: shown), handles: handles, cube: cubeLayout,
                             hoveredCubeRegion: hoveredCubeRegion, triad: triadLayout)
    }

    /// 1, 10 or 100 mm for this pose in this view.
    func gridSpacing(for pose: CameraPose) -> Double {
        GridSpacing.spacing(millimetresPerPoint: viewSize.isEmpty ? 1 : CameraMath.millimetresPerPoint(pose, size: viewSize))
    }
}
