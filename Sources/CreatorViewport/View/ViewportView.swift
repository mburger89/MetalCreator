import MetalUI

/// The 3D viewport (spec §6.3) as a MetalUI component:
/// - a `MetalView` filling its space, whose size the model learns from `onGeometryChange` (gap M4-a)
/// - its gestures (spec §9) and the face context menu
/// - the held ⌘, which the sketch's rubber band reads under a still pointer (`onModifierKeysChanged`, gap S5-a)
/// - overlays for labels and the view cube's buttons
/// All behaviour lives in `ViewportModel`. This is glue.
public struct ViewportView: Component {
    let model: ViewportModel

    public init(model: ViewportModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        Self.stack(model: model)
            .onGeometryChange(for: ViewSizeReport.self, of: { [id = ObjectIdentifier(model)] proxy in
                ViewSizeReport(model: id, size: ViewportSize(width: Double(proxy.size.width.value),
                                                             height: Double(proxy.size.height.value)))
            }, action: { [model] report in model.recordViewSize(report.size) })
            .onModifierKeysChanged(mask: ViewportModifiers.hoverMask) { [model] _, held in
                model.modifiersChanged(ViewportModifiers(held))
            }
    }
}
