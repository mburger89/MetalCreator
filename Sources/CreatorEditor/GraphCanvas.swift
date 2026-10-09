import MetalUI

/// The graph canvas: the layers under the zoom and pan transform, one press-and-drag gesture
/// for everything (hit testing is the model's), a pinch, the scroll wheel, the cursor, and pointer
/// tracking for the palette. All input goes through `GraphPanelInput` to the model. The palette itself floats over
/// the whole window (`SearchPaletteOverlay`), so the canvas never clips it.
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
        .gesture(input.pinchGesture())
        .contentShape(Rectangle())
        .onContinuousHover { phase in input.hover(phase) }
        .onScrollWheel { event in input.scrolled(event) }
        .pointerStyle(model.canvasCursor?.pointerStyle)
    }
}
