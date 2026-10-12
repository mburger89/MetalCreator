import CreatorGeometry
import CreatorGraph
import MetalUI

/// What `GraphPanel`'s `onGeometryChange` watches: the panel's placement and which model it is for. The model is part
/// of the value so that a replaced editor (New, Open build a fresh `EditorModel` under the same panel) is told where
/// the panel is again, though the placement itself has not changed.
struct PanelPlacementReport: Equatable {
    let model: ObjectIdentifier
    let placement: PanelPlacement

    /// The report for `model` from the panel's frame in the window (`GeometryProxy.frame(in: .global)`) and the
    /// window's size (`EnvironmentValues.windowSize`).
    init(model: EditorModel, window: Size<Pixels>, panel: Bounds<Pixels>) {
        self.model = ObjectIdentifier(model)
        placement = PanelPlacement(
            window: Vector2(Double(window.width.value), Double(window.height.value)),
            panel: CanvasRect(origin: Vector2(Double(panel.origin.x.value), Double(panel.origin.y.value)),
                              size: Vector2(Double(panel.size.width.value), Double(panel.size.height.value))))
    }
}
