import CreatorGeometry
import CreatorKernel

extension ViewportModel {
    /// The face context menu (spec §6.3), built when the menu opens, for the face under `point`: the right press's
    /// location, which MetalUI's located `.contextMenu` hands its builder (C7 item 4). The face is picked there and
    /// then, so it's the one under the press even if the pointer moved without a hover event or the camera moved
    /// under it. Over an edge, the menu uses the edge's first face. Over nothing, over the view cube, or opened
    /// without a pointer (`nil`: from the keyboard or accessibility) it's empty, and MetalUI opens no menu. While a
    /// `tool` holds the pointer (a sketch is open) it only navigates: Look At, and nothing that edits or selects; with
    /// planar navigation it's empty, since Look At would turn the camera.
    public func contextMenuItems(at point: ScreenPoint?) -> [ViewportMenuItem] {
        guard let point, !isPlanar, !cubeLayout.contains(point), let ref = faceRef(for: pick?(point)),
              let face = items[ref.solidIndex].solid.topology.face(ref.face) else { return [] }
        guard tool == nil else { return [.lookAt(ref)] }
        var menu: [ViewportMenuItem] = [.lookAt(ref), .selectEdgesOfFace(ref)]
        let nodes = MeshQueries.producingNodes(of: face)
        for node in nodes {
            let title = nodes.count == 1
                ? "Show Producing Node"
                : "Show Producing Node (\(events.nodeName(node) ?? node.description))"
            menu.append(.showProducingNode(node, title: title))
        }
        return menu
    }

    public func choose(_ item: ViewportMenuItem) {
        switch item {
        case .lookAt(let ref):
            lookAt(ref)
        case .selectEdgesOfFace(let ref):
            guard items.indices.contains(ref.solidIndex) else { return }
            let topology = items[ref.solidIndex].solid.topology
            let edges = MeshQueries.boundaryEdges(of: ref.face, in: topology)
            let ids = edges.map(\.id)
            events.selectEdgesOfFace(ref, topology.picks(for: ids), ids)
        case .showProducingNode(let node, _):
            events.showProducingNode(node)
        }
    }

    /// Look At (spec §6.3): animates to face the face's normal, orthographic, framed on the face in the model area.
    /// Nothing happens while navigation is planar.
    public func lookAt(_ ref: ViewportFaceRef) {
        guard !isPlanar, items.indices.contains(ref.solidIndex), let mesh = cache.mesh(for: items[ref.solidIndex].solid)?.mesh,
              let direction = MeshQueries.faceDirection(mesh, ref.face),
              let bounds = MeshQueries.faceBounds(mesh, ref.face) else { return }
        var target = currentPose()
        guard let orientation = CameraNavigation.orientation(lookingFrom: direction,
                                                             fallbackYaw: target.yaw) else { return }
        target.yaw = orientation.yaw
        target.pitch = orientation.pitch
        target.projection = .orthographic
        animate(to: CameraNavigation.frame(bounds, target, size: viewSize, insets: modelArea))
    }

    /// The face a context menu over `target` is about: the face, or the first face of the edge. `nil` over
    /// nothing, or for a stale pick (its solid is gone).
    func faceRef(for target: PickTarget?) -> ViewportFaceRef? {
        switch target {
        case .face(let solid, let face)?:
            guard items.indices.contains(solid) else { return nil }
            return ViewportFaceRef(solidIndex: solid, face: face)
        case .edge(let solid, let edge)?:
            guard items.indices.contains(solid), let face = items[solid].solid.topology.edge(edge)?.faces.first else {
                return nil
            }
            return ViewportFaceRef(solidIndex: solid, face: face)
        case nil:
            return nil
        }
    }
}
