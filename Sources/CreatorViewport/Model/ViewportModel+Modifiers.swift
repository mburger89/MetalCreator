/// The modifier keys held over the viewport (sketcher spec §8: holding ⌘ suppresses constraint inference while drawing).
/// A click carries its own (`SpatialTapGesture.Value.modifiers`); a hover has none of its own, and nothing moves when a
/// key is pressed over a still pointer, so `ViewportView` reports the held ones from MetalUI's `onModifierKeysChanged`
/// (C16, gap S5-a) and the model replays the hover the tool last saw with them.
extension ViewportModel {
    /// The held modifiers (`ViewportModifiers.hoverMask` of them) changed. A tool under a still pointer is told at once,
    /// so its rubber band and glyphs follow the key without a mouse move. During a drag nothing hovers; the drag's end
    /// hovers again with the modifiers held then (`refreshHover()`).
    public func modifiersChanged(_ modifiers: ViewportModifiers) {
        guard modifiers != heldModifiers else { return }
        heldModifiers = modifiers
        guard drag == nil, let tool, let point = lastHoverPoint else { return }
        tool.pointerMoved(to: point, modifiers: modifiers, projector: projector)
    }
}
