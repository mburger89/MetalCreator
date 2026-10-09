import MetalUI

/// The graph canvas: the layers under the zoom and pan transform, one press-and-drag gesture
/// for everything (hit testing is the model's) and pointer tracking for the palette. The palette
/// itself floats over the whole window (`SearchPaletteOverlay`), so the canvas never clips it.
struct GraphCanvas: Component {
    let model: EditorModel
    let input: GraphPanelInput

    var content: some ElementGroup {
        let transform = model.transform
        return ZStack(alignment: .topLeading) {
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
    }
}
