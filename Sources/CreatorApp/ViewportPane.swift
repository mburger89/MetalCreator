import CreatorViewport
import MetalUI

/// The viewport's place in the window: the Metal 3D view where there is one, else the placeholder card. The one place the
/// app shell asks which; everything else (the model, picking, the scene, sketch mode) is the same on every platform.
struct ViewportPane: Component {
    let model: ViewportModel

    var content: some ElementGroup {
        #if canImport(Metal)
        ViewportView(model: model)
        #else
        ViewportPlaceholder()
        #endif
    }
}
