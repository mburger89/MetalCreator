import CreatorViewport
import MetalUI

/// The viewport's place in the window: the Metal 3D view where there is one, else the placeholder card. The one place the
/// app shell asks which; everything else (the model, picking, the scene, sketch mode) is the same on every platform.
struct ViewportPane: Component {
    let model: ViewportModel

    var content: some ElementGroup {
        #if canImport(Metal)
        // `ViewportView` has a `==`, but no `.equatable()` here: its `GPUSurface` makes an `.equatable()` Component ineligible
        // ("surface") even since MetalUI C14-h, so it only adds a content evaluation and a retainedIneligible per frame (measured
        // 2026-10-21 on every warm row; element requests unchanged, docs/verification/performance.md, "C14-f and C14-h adopted").
        ViewportView(model: model)
        #else
        ViewportPlaceholder()
        #endif
    }
}
