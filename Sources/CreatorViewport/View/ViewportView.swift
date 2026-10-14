#if canImport(Metal)
import MetalUI

/// The 3D viewport (spec §6.3) as a MetalUI component:
/// - a `MetalView` filling its space, whose size the model learns from `onGeometryChange` (gap M4-a)
/// - its gestures (spec §9) and the face context menu
/// - the held ⌘, which the sketch's rubber band reads under a still pointer (`onModifierKeysChanged`, gap S5-a)
/// - overlays for labels, each box measured to its text (`TextMeasure`, gap S5-c), and the view cube's buttons
/// All behaviour lives in `ViewportModel`. This is glue.
public struct ViewportView: Component {
    let model: ViewportModel
    /// MetalUI's text measurer (C23), which sizes the labels' boxes to their text (gap S5-c).
    @Environment(\.textMeasurer) var measurer

    public init(model: ViewportModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        Self.stack(model: model, measure: TextMeasure(measurer))
            .onGeometryChange(for: ViewSizeReport.self, of: { [id = ObjectIdentifier(model)] proxy in
                ViewSizeReport(model: id, size: ViewportSize(width: Double(proxy.size.width.value),
                                                             height: Double(proxy.size.height.value)))
            }, action: { [model] report in model.recordViewSize(report.size) })
            .onModifierKeysChanged(mask: ViewportModifiers.hoverMask) { [model] _, held in
                model.modifiersChanged(ViewportModifiers(held))
            }
    }
}
#endif
