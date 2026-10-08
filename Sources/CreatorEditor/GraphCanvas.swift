import MetalUI

/// The graph canvas: the layers under the zoom and pan transform, one press-and-drag gesture
/// for everything (hit testing is the model's), pointer tracking for the palette, and the
/// palette itself, which is not zoomed.
struct GraphCanvas: Component {
    let model: EditorModel
    let input: GraphPanelInput

    var content: some ElementGroup {
        let transform = model.transform
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Color.clear
                ZStack(alignment: .topLeading) { CanvasLayers(model: model) }
                    .scaleEffect(transform.zoom, anchor: .topLeading)
                    .offset(x: transform.offset.x.px, y: transform.offset.y.px)
                    .allowsHitTesting(false)
            }
            .clipped()
            .gesture(input.canvasGesture())
            .contentShape(Rectangle())
            .onContinuousHover { phase in input.hover(phase) }
            if let palette = model.palette {
                ZStack(alignment: .topLeading) { SearchPaletteView(model: model) }
                    .offset(x: palette.screenPosition.x.px, y: palette.screenPosition.y.px)
            }
        }
    }
}
