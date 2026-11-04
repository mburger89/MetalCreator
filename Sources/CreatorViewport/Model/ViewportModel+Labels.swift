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

    /// Each handle's value beside its knob (spec §6.5), in viewport points. "R 3 mm" for a radial handle. The size is
    /// read from the tracked `viewSize`, so labels built before the first layout reported it are rebuilt after it. Each
    /// label's box is as wide as `measure` says its text is.
    public func handleLabels(measuring measure: TextMeasure) -> [HandleLabel] {
        let size = viewSize
        guard !size.isEmpty, !isAnimating else { return [] }
        return handles.compactMap { handle in
            guard let knob = CameraMath.project(handle.knob, pose, size: size)?.point else { return nil }
            let amount = Self.handleAmount(handle.value)
            let text = handle.style == .radial ? "R \(amount) mm" : "\(amount) mm"
            let box = ViewportSize(width: measure(text).width.rounded(.up), height: HandleLabel.height)
            return HandleLabel(text: text, position: ScreenPoint(knob.x + 14, knob.y - 14), size: box)
        }
    }

    /// A handle's value as its label shows it, to two decimals and never "-0": a value that rounds to zero (a section plane
    /// left a hair behind the origin) reads "0" in every locale, decided from the number (`roundedForDisplay`).
    static func handleAmount(_ value: Double, locale: Locale = .current) -> String {
        value.roundedForDisplay(decimals: 2).formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    /// The unit and grid label (spec §6.3), such as "mm · grid 10 mm".
    public var gridLabel: String {
        GridSpacing.label(spacing: gridSpacing(for: pose))
    }
}
