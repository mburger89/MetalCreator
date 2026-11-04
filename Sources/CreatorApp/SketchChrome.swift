import CreatorEditor
import CreatorStyle
import MetalUI

/// The glass around the sketch toolbar and the sketch inspector. `GlassPanel` is opaque to the pointer itself now (a click in a
/// gap between the toolbar's buttons or on an inspector label must not reach the viewport beneath, which the sketch editor
/// claims: it would draw hidden geometry or clear the selection), so this only names the sketch's use of it.
struct SketchChrome<Body: ElementGroup>: Component {
    let surface: GlassSurface
    let body: Body

    init(_ surface: GlassSurface, @ElementBuilder _ body: () -> Body) {
        self.surface = surface
        self.body = body()
    }

    var content: some ElementGroup {
        GlassPanel(surface) { body }
    }
}
