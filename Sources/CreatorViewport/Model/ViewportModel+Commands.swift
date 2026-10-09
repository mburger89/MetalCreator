import CreatorGeometry
import CreatorKernel

extension ViewportModel {
    /// While navigation is planar, the commands that would turn the camera (a cube region, an arrow, Home, a projection
    /// change) do nothing.
    public func perform(_ command: ViewportCommand) {
        if isPlanar, command.turnsTheCamera { return }
        run(command)
    }

    private func run(_ command: ViewportCommand) {
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
            events.homeChanged(homePose)
        case .view(let region):
            animateTurn(region.pose(from:))
        case .rotate(let arrow):
            animateTurn { CameraNavigation.rotate($0, arrow) }
        case .projection(let projection):
            stopAnimation()
            pose.projection = projection
            refreshHover()
            events.cameraSettled(pose)
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

    /// Animates to `turn(now)`, the camera now turned, moved so the point shown at the model area's centre
    /// (`modelAreaPivot`) stays there: the arrows and the cube's regions turn the part where it is.
    func animateTurn(_ turn: (CameraPose) -> CameraPose) {
        let now = currentPose()
        animate(to: centring(modelAreaPivot(now), inTheModelAreaOf: turn(now)))
    }

    /// One zoom step (the + and − keys) toward the pointer or, with no pointer over the view, toward the model
    /// area's centre, where framing puts the part.
    func zoom(by factor: Double) {
        stopAnimation()
        let before = pose
        apply(CameraNavigation.zoom(pose, factor: factor, toward: lastHoverPoint ?? modelAreaCentre, size: viewSize))
        refreshHover()
        if pose != before { events.cameraSettled(pose) }
    }

    /// Spec §6.3: "F frames the selection, or everything", in the model area the panels leave; while a tool has
    /// bounds of its own (`ViewportTool.framingBounds`: the sketch) it frames those. Framing never turns the camera.
    /// With nothing shown, nothing happens.
    func frameSelectionOrEverything() {
        guard let bounds = tool?.framingBounds ?? selectionBounds() ?? sceneBounds else { return }
        animate(to: CameraNavigation.frame(bounds, currentPose(), size: viewSize, insets: modelArea))
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
