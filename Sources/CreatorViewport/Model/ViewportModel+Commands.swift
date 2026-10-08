import CreatorGeometry
import CreatorKernel

extension ViewportModel {
    public func perform(_ command: ViewportCommand) {
        switch command {
        case .frame:
            frameSelectionOrEverything()
        case .zoomIn:
            zoom(by: ViewportInputMap.keyZoomFactor)
        case .zoomOut:
            zoom(by: 1 / ViewportInputMap.keyZoomFactor)
        case .home:
            if let home = homePose ?? sceneBounds.map(defaultHome(for:)) { animate(to: home) }
        case .setHome:
            homePose = currentPose()
        case .view(let region):
            animate(to: region.pose(from: currentPose()))
        case .rotate(let arrow):
            animate(to: CameraNavigation.rotate(currentPose(), arrow))
        case .projection(let projection):
            stopAnimation()
            pose.projection = projection
            refreshHover()
        case .shading(let mode):
            shading = mode
        }
    }

    /// The keyboard stopgaps (spec §9): F frames, + and − zoom toward the pointer.
    public func performKey(_ key: ViewportKeyCommand) {
        switch key {
        case .frame: perform(.frame)
        case .zoomIn: perform(.zoomIn)
        case .zoomOut: perform(.zoomOut)
        }
    }

    func zoom(by factor: Double) {
        stopAnimation()
        apply(CameraNavigation.zoom(pose, factor: factor, toward: lastHoverPoint, size: viewSize))
        refreshHover()
    }

    /// Spec §6.3: "F frames the selection, or everything". With nothing shown, nothing happens.
    func frameSelectionOrEverything() {
        guard let bounds = selectionBounds() ?? sceneBounds else { return }
        animate(to: CameraNavigation.frame(bounds, currentPose(), size: viewSize))
    }

    /// The bounds of every selected face and edge across the shown solids, or `nil` when nothing is selected.
    func selectionBounds() -> BoundingBox? {
        var result: BoundingBox?
        func include(_ box: BoundingBox?) {
            guard let box else { return }
            result = result?.union(box) ?? box
        }
        for item in items {
            guard let mesh = cache.mesh(for: item.solid)?.mesh else { continue }
            for face in item.selectedFaces { include(MeshQueries.faceBounds(mesh, face)) }
            if !item.selectedEdges.isEmpty { include(MeshQueries.edgeBounds(mesh, item.selectedEdges)) }
        }
        return result
    }
}
