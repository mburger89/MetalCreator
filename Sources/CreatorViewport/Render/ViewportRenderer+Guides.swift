import Metal

extension ViewportRenderer {
    /// A guide's selected edges (spec §6.3, Errata (M6)), after the solids and ghosts so they lie over them. They're
    /// depth-tested with the bias B-rep edges get: where they lie on the part they cover its edge in the selection
    /// colour, and where they float clear of it they show as an overlay. Where the part hides them, a second draw
    /// shows them faded (`ViewportPalette.hiddenSelection`), so a rule's edges inside the material can still be seen.
    /// The guide's own surfaces aren't drawn.
    func drawGuides(_ frame: ViewportFrame, _ uniforms: FrameUniforms, scale: Float,
                    _ encoder: any MTLRenderCommandEncoder) {
        let style = LineUniforms(widthOverride: 0, depthBias: Float(edgeDepthBias(frame)), padding0: 0, padding1: 0)
        for item in frame.items where item.isGuide && !item.selectedEdges.isEmpty {
            let key = EdgeInstanceKey(solid: item.solidIndex, selected: item.selectedEdges, selectedOnly: true, scale: scale)
            guard let edges = meshes[item.meshSerial]?.edges(key, palette: frame.palette, device: device) else { continue }
            drawLines(edges.buffer, count: edges.count, uniforms, depth: pipelines.depthTest, style: style, encoder)
            let hiddenKey = EdgeInstanceKey(solid: item.solidIndex, selected: item.selectedEdges, selectedOnly: true,
                                            scale: scale, hidden: true)
            guard let faded = meshes[item.meshSerial]?.edges(hiddenKey, palette: frame.palette, device: device) else { continue }
            drawLines(faded.buffer, count: faded.count, uniforms, depth: pipelines.depthBehind, style: style, encoder)
        }
    }
}
