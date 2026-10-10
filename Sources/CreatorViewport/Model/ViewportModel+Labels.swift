import CreatorGeometry
import Foundation

/// Text the view overlays on the GPU surface. Labels are rebuilt when the element tree is, which a running
/// camera animation doesn't trigger (docs/metalui-gaps.md), so the moving ones are hidden while it runs.
/// The view cube's face names aren't overlays: the renderer paints them on the faces (`CubeLabelAtlas`), so they
/// turn with the cube and stay during animations.
extension ViewportModel {
    /// Triad axis names, relative to the triad widget's top-left (it sits at the bottom-left of the viewport).
    public func triadLabels() -> [ViewportLabel] {
        isAnimating ? [] : triadLayout.labels(pose: pose)
    }

    /// Each handle's value beside its knob (spec §6.5), in viewport points. "R 3 mm" for a radial handle.
    public func handleLabels() -> [ViewportLabel] {
        guard !viewSize.isEmpty, !isAnimating else { return [] }
        return handles.compactMap { handle in
            guard let knob = CameraMath.project(handle.knob, pose, size: viewSize)?.point else { return nil }
            let amount = handle.value.formatted(.number.precision(.fractionLength(0...2)))
            let text = handle.style == .radial ? "R \(amount) mm" : "\(amount) mm"
            return ViewportLabel(text: text, position: ScreenPoint(knob.x + 14, knob.y - 14))
        }
    }

    /// The overlay's labels on screen (`ViewportOverlay.labels`): each box centred on its anchor projected with the camera,
    /// moved `OverlayLabel.nudgeDistance` points along its nudge as that looks on screen. Left out: all of them while
    /// the camera animates (as the handle labels are), an anchor at or behind a perspective eye, and a box wholly
    /// outside the view. Gap S5-c: this is element-tree text, not text in the Metal pass.
    public func overlayLabels() -> [PlacedLabel] {
        let size = observedViewSize
        guard !size.isEmpty, !isAnimating, !overlay.labels.isEmpty else { return [] }
        return overlay.labels.compactMap { label in
            guard let anchor = CameraMath.project(label.position, pose, size: size)?.point else { return nil }
            var centre = anchor
            if let nudge = label.nudge, let tip = CameraMath.project(label.position + nudge, pose, size: size)?.point {
                let (dx, dy) = (tip.x - anchor.x, tip.y - anchor.y)
                let length = (dx * dx + dy * dy).squareRoot()
                if length > 1e-6 {
                    centre = ScreenPoint(anchor.x + dx / length * OverlayLabel.nudgeDistance,
                                         anchor.y + dy / length * OverlayLabel.nudgeDistance)
                }
            }
            let box = PlacedLabel.size(of: label.text)
            let origin = ScreenPoint(centre.x - box.width / 2, centre.y - box.height / 2)
            guard origin.x + box.width > 0, origin.y + box.height > 0, origin.x < size.width, origin.y < size.height else {
                return nil
            }
            return PlacedLabel(text: label.text, tint: label.tint, origin: origin, size: box)
        }
    }

    /// The unit and grid label (spec §6.3), such as "mm · grid 10 mm".
    public var gridLabel: String {
        GridSpacing.label(spacing: gridSpacing(for: pose))
    }
}
