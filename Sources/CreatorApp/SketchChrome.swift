import CreatorEditor
import MetalUI

/// The glass around the sketch toolbar and the sketch inspector, opaque to the pointer. The glass only paints, and
/// MetalUI gives a painted view no hitbox (its divergence 141), so without the backdrop a click in a gap between the
/// toolbar's buttons or on an inspector label would reach the viewport beneath, which the sketch editor claims: it
/// would draw hidden geometry, or clear the selection, and hover would drive the rubber band under the panel. The
/// backdrop is the add-node palette's (a content shape with an empty drag, claiming every scroll; gap EP-b), sized to
/// the glass by `.background`. The buttons and fields are drawn above it and take their own input.
struct SketchChrome<Body: ElementGroup>: Component {
    let body: Body

    init(@ElementBuilder _ body: () -> Body) {
        self.body = body()
    }

    var content: some ElementGroup {
        GlassPanel { body }
            .background {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: Pixels(0)))
                    .onScrollWheel { _ in true }
            }
    }
}
