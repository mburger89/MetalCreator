import CreatorGeometry
import CreatorKernel

extension ViewportModel {
    /// The face context menu (spec §6.3), built when the menu opens, for the face under the pointer. Over an edge,
    /// it uses the edge's first face. Over nothing it's empty, and MetalUI opens no menu.
    ///
    /// MetalUI doesn't yet give a context menu its click location (C7 item 4, docs/metalui-gaps.md), so "under the
    /// pointer" is the last hover pick. The model redoes that pick whenever the camera or the scene moves under a
    /// still pointer (`refreshHover()`), so it can't name a face that has moved away.
    public func contextMenuItems() -> [ViewportMenuItem] {
        guard let ref = hoveredFaceRef(),
              let face = items[ref.solidIndex].solid.topology.face(ref.face) else { return [] }
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
    public func lookAt(_ ref: ViewportFaceRef) {
        guard items.indices.contains(ref.solidIndex), let mesh = cache.mesh(for: items[ref.solidIndex].solid)?.mesh,
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

    /// The face the context menu is about: the hovered face, or the first face of the hovered edge. `nil` if the
    /// pick is stale (its solid is gone).
    func hoveredFaceRef() -> ViewportFaceRef? {
        switch hovered {
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
