import MetalUI

/// The 3D viewport (spec §6.3) as a MetalUI component:
/// - a `MetalView` filling its space
/// - the stopgap gestures of spec §9 and the face context menu
/// - overlays for labels and the view cube's buttons
/// All behaviour lives in `ViewportModel`. This is glue.
public struct ViewportView: Component {
    let model: ViewportModel
    let modifiers: ViewportModifierTracker

    /// `modifiers` follows the held modifier keys until MetalUI's drags report them (C7 item 5). Install it on the
    /// window once, with `ViewportModifierTracker.install(on:)`.
    public init(model: ViewportModel, modifiers: ViewportModifierTracker) {
        self.model = model
        self.modifiers = modifiers
    }

    public var content: some ElementGroup {
        Self.stack(model: model, modifiers: modifiers)
    }
}
