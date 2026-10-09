import MetalUI

/// The 3D viewport (spec §6.3) as a MetalUI component:
/// - a `MetalView` filling its space
/// - its gestures (spec §9) and the face context menu
/// - overlays for labels and the view cube's buttons
/// All behaviour lives in `ViewportModel`. This is glue.
public struct ViewportView: Component {
    let model: ViewportModel

    public init(model: ViewportModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        Self.stack(model: model)
    }
}
