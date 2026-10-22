#if canImport(MetalUISDLGPU)
import CreatorGeometry
import CreatorKernel
import MetalUISDLGPU

extension SDLViewportRenderer {
    /// Makes every buffer the main pass reads and records the copies that fill them (`commandBuffer` is the uploader's). The layers
    /// are the Metal renderer's, in the order it draws them: solids, edges, guides, overlay, handles.
    func plan(_ frame: ViewportFrame, scale: Float, uploader: SDLViewportUploader) -> SDLFramePlan {
        prepareMeshes(for: frame, uploader)
        var plan = SDLFramePlan()
        let clip = ClipUniforms(frame.clip)
        for item in frame.items where !item.isGuide {
            guard let solid = solid(of: item, uploader) else { continue }
            if item.isGhost { plan.ghosts.append(solid) } else { plan.opaque.append(solid) }
        }
        // B-rep edges of opaque solids. "Shaded" mode still shows the edges a rule selected.
        let edgeStyle = LineUniforms(widthOverride: 0, depthBias: Float(Self.edgeDepthBias(frame)), padding0: 0, padding1: 0)
        let selectedOnly = frame.shading == .shaded
        for item in frame.items where !item.isGhost && !item.isGuide && (!selectedOnly || !item.selectedEdges.isEmpty) {
            let key = EdgeInstanceKey(solid: item.solidIndex, selected: item.selectedEdges, selectedOnly: selectedOnly, scale: scale)
            guard let edges = meshes[item.meshSerial]?.edges(key, palette: frame.palette, uploader: uploader) else { continue }
            plan.edges.append(SDLFramePlan.Lines(buffer: edges.buffer, count: edges.count, style: edgeStyle, clip: clip))
        }
        // A guide's selected edges, over the solids; and again faded where the part hides them.
        for item in frame.items where item.isGuide && !item.selectedEdges.isEmpty {
            let key = EdgeInstanceKey(solid: item.solidIndex, selected: item.selectedEdges, selectedOnly: true, scale: scale)
            if let edges = meshes[item.meshSerial]?.edges(key, palette: frame.palette, uploader: uploader) {
                plan.guides.append(SDLFramePlan.Lines(buffer: edges.buffer, count: edges.count, style: edgeStyle))
            }
            let hiddenKey = EdgeInstanceKey(solid: item.solidIndex, selected: item.selectedEdges, selectedOnly: true, scale: scale,
                                            hidden: true)
            if let faded = meshes[item.meshSerial]?.edges(hiddenKey, palette: frame.palette, uploader: uploader) {
                plan.hiddenGuides.append(SDLFramePlan.Lines(buffer: faded.buffer, count: faded.count, style: edgeStyle))
            }
        }
        plan.fills = fillVertices(for: frame, uploader)
        plan.overlay = overlayInstances(for: frame, scale: scale, uploader).map {
            SDLFramePlan.Lines(buffer: $0.buffer, count: $0.count, style: Self.plainLines)
        }
        plan.handles = handleInstances(for: frame, scale: scale, uploader).map {
            SDLFramePlan.Lines(buffer: $0.buffer, count: $0.count, style: Self.plainLines)
        }
        return plan
    }

    static let plainLines = LineUniforms(widthOverride: 0, depthBias: 0, padding0: 0, padding1: 0)

    /// `item` as a plan entry: its triangles, its face flags and, for an opaque item with a tint to show (fields spec §6), the field's
    /// values and ramp. `nil` when the mesh has no triangles.
    private func solid(of item: FrameItem, _ uploader: SDLViewportUploader) -> SDLFramePlan.Solid? {
        guard let gpu = meshes[item.meshSerial], let vertices = gpu.vertexBuffer,
              let flags = gpu.faceFlags(hovered: item.hoveredFace, selected: item.selectedFaces, warning: item.warningFaces,
                                        uploader: uploader) else { return nil }
        var tint: (values: SDLGPUBuffer, ramp: FieldRampUniforms)?
        if !item.isGhost, let values = item.fieldValues, let ramp = item.fieldRamp,
           let buffer = gpu.fieldValues(values, mesh: item.mesh, ramp: ramp, uploader: uploader) {
            tint = (buffer, FieldRampUniforms(ramp))
        }
        return SDLFramePlan.Solid(vertices: vertices, vertexCount: gpu.vertexCount, flags: flags, faceCount: gpu.faceCount, tint: tint)
    }

    /// The frame's handles in its palette, kept until the handles, the scale or the palette change.
    private func handleInstances(for frame: ViewportFrame, scale: Float,
                                 _ uploader: SDLViewportUploader) -> (buffer: SDLGPUBuffer, count: Int)? {
        if let cached = handleBuffer, cached.handles == frame.handles, cached.scale == scale, cached.palette == frame.palette {
            return (cached.buffer, cached.count)
        }
        let instances = GPUGeometry.handleInstances(frame.handles, scale: scale, palette: frame.palette)
        guard let buffer = uploader.storageBuffer(instances) else {
            handleBuffer = nil
            return nil
        }
        handleBuffer = CachedHandles(handles: frame.handles, scale: scale, palette: frame.palette, buffer: buffer, count: instances.count)
        return (buffer, instances.count)
    }

    /// The frame's fill triangles in its palette, kept until the fills or the palette change.
    private func fillVertices(for frame: ViewportFrame, _ uploader: SDLViewportUploader) -> (buffer: SDLGPUBuffer, count: Int)? {
        guard !frame.overlay.fills.isEmpty else {
            fillBuffer = nil
            return nil
        }
        let key = FillBufferKey(fills: frame.overlay.fills, palette: frame.palette)
        if let cached = fillBuffer, cached.key == key { return (cached.buffer, cached.count) }
        let vertices = OverlayGeometry.fillVertices(frame.overlay.fills, palette: frame.palette)
        guard let buffer = uploader.storageBuffer(vertices) else {
            fillBuffer = nil
            return nil
        }
        fillBuffer = (key, buffer, vertices.count)
        return (buffer, vertices.count)
    }

    /// The frame's overlay in its palette, kept until what the instances are built from changes: the overlay, the scale, the palette,
    /// and the camera only as far as it reaches them (where the plane grid is centred and how far it reaches, and the zoom the dashes
    /// are cut at). An orbit, or a pan inside one grid cell, reuses the buffer.
    private func overlayInstances(for frame: ViewportFrame, scale: Float,
                                  _ uploader: SDLViewportUploader) -> (buffer: SDLGPUBuffer, count: Int)? {
        guard !frame.overlay.isEmpty else { return nil }
        let grid = frame.overlay.gridPlane.flatMap {
            OverlayGeometry.gridExtent(on: $0, pose: frame.pose, size: frame.size, spacing: frame.gridSpacing)
        }
        let dashZoom = frame.overlay.lines.contains(where: \.isDashed)
            ? CameraMath.millimetresPerPoint(frame.pose, size: frame.size) : nil
        let key = OverlayBufferKey(overlay: frame.overlay, grid: grid, dashZoom: dashZoom, scale: scale, palette: frame.palette)
        if let cached = overlayBuffer, cached.key == key { return (cached.buffer, cached.count) }
        let instances = OverlayGeometry.instances(frame.overlay, grid: grid, millimetresPerPoint: dashZoom ?? 1, scale: scale,
                                                  palette: frame.palette)
        guard let buffer = uploader.storageBuffer(instances) else {
            overlayBuffer = nil
            return nil
        }
        overlayBuffer = (key, buffer, instances.count)
        return (buffer, instances.count)
    }
}
#endif
