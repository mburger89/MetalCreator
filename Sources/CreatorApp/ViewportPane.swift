import CreatorViewport
import MetalUI

/// The viewport's place in the window: the Metal 3D view where there is one, else the placeholder card. The one place the
/// app shell asks which; everything else (the model, picking, the scene, sketch mode) is the same on every platform.
struct ViewportPane: Component {
    let model: ViewportModel

    var content: some ElementGroup {
        #if canImport(Metal)
        // `ViewportView` has a `==`, but no `.equatable()` here yet: its `onGeometryChange` makes an `.equatable()` Component
        // ineligible every frame until MetalUI C14-e (c) lands, which cost one content evaluation per frame and broke the
        // `retainedIneligible == 0` pin in the orbit-panel-left-warm bench (docs/verification/performance.md, "C14-e adopted").
        ViewportView(model: model)
        #else
        ViewportPlaceholder()
        #endif
    }
}
