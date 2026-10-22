import CreatorViewport
import MetalUI

/// The viewport's place in the window: the real 3D view on every platform (cross-platform spec section 4). It draws with Metal
/// on macOS and with SDL_GPU, over Vulkan or Direct3D 12, on Linux and Windows; everything else (the model, picking, the scene,
/// sketch mode) is the same on all of them.
struct ViewportPane: Component {
    let model: ViewportModel

    var content: some ElementGroup {
        // `ViewportView` has a `==`, but no `.equatable()` here: its `GPUSurface` makes an `.equatable()` Component ineligible
        // ("surface") even since MetalUI C14-h, so it only adds a content evaluation and a retainedIneligible per frame (measured
        // 2026-10-21 on every warm row; element requests unchanged, docs/verification/performance.md, "C14-f and C14-h adopted").
        ViewportView(model: model)
    }
}
