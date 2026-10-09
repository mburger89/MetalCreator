import CreatorGeometry
import Foundation

extension EditorModel {
    /// ⌘-scroll zoom: 100 points of scroll multiply or divide the zoom by e, as the viewport's scroll zoom does. A
    /// wheel mouse's step is 10 points (MetalUI reports its lines × 10), so about 10%.
    public static let scrollZoomPerPoint = 0.01

    /// A scroll over the canvas (spec §6.2, docs/metalui-gaps.md M5-f): `delta` points of scroll at `point`
    /// (canvas-local screen points), with `modifiers` held. Two-finger scroll and the wheel pan the canvas by the
    /// delta, and the glide after a flick keeps panning. ⌘-scroll zooms about `point`, a positive `delta.y`
    /// zooming in (as the viewport does), within `CanvasTransform.zoomRange`, and its glide is ignored until its
    /// momentum ends. A trackpad scroll zooms or pans as it began, so pressing or letting go of ⌘ part-way changes
    /// nothing until the next one. A scroll that moves the canvas closes the add-node palette, which adds at the
    /// point it opened over. Returns `true`: the canvas claims every scroll over it, so none reaches the viewport or
    /// the window.
    @discardableResult
    public func scrolled(by delta: Vector2, at point: Vector2, modifiers: CanvasModifiers, phase: CanvasScrollPhase) -> Bool {
        guard let zooms = scrollMode(for: phase, command: modifiers.contains(.command)) else { return true }
        guard delta.isFinite, point.isFinite else { return true }
        let moved = zooms
            ? transform.zoomed(by: exp(delta.y * Self.scrollZoomPerPoint), around: point)
            : transform.panned(by: delta)
        guard moved != transform else { return true }
        palette = nil
        transform = moved
        return true
    }

    /// Whether this scroll event zooms (`true`), pans (`false`) or is ignored (`nil`: a zoom's glide), keeping the
    /// trackpad latch. `scrollZooms` holds what a scroll does from its `.began` (or, for a scroll that began over
    /// something else, from its first `.changed` here: MetalUI sends each event to what is under the pointer at
    /// that event, gap GI-b) to its `.ended`; `scrollGlideIgnored` holds a zoom's glide off from its `.ended` until
    /// its momentum ends, or the next scroll starts.
    private func scrollMode(for phase: CanvasScrollPhase, command: Bool) -> Bool? {
        switch phase {
        case .step, .began:
            scrollZooms = phase == .began ? command : nil
            scrollGlideIgnored = false
            return command
        case .changed:
            let zooms = scrollZooms ?? command
            scrollZooms = zooms
            scrollGlideIgnored = false
            return zooms
        case .ended:
            let zooms = scrollZooms ?? command
            scrollZooms = nil
            scrollGlideIgnored = zooms
            return zooms
        case .momentum, .momentumEnded:
            let ignored = scrollGlideIgnored
            if phase == .momentumEnded { scrollGlideIgnored = false }
            return ignored ? nil : false
        }
    }
}
