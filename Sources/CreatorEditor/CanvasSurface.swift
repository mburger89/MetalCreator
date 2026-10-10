import MetalUI

/// The graph canvas's surface: the layers under the zoom and pan transform, one press-and-drag gesture for everything
/// (hit testing is the model's), a middle-button drag that pans, a pinch, the scroll wheel, the cursor, the context
/// menu (Add Note, Frame Selection at the point it opened) and pointer tracking for the palette. All input goes
/// through `GraphPanelInput` to the model.
struct CanvasSurface: Component {
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
        .gesture(input.middlePanGesture())
        .gesture(input.pinchGesture())
        .contentShape(Rectangle())
        .onContinuousHover { phase in input.hover(phase) }
        .onScrollWheel { event in input.scrolled(event) }
        .contextMenu { (location: Point<Pixels>?) in
            for item in CanvasMenuItem.allCases {
                Button(item.title) { model.choose(item, at: location.map { GraphPanelInput.vector($0) }) }
                    .disabled(!model.isEnabled(item))
            }
        }
        .pointerStyle(model.canvasCursor?.pointerStyle)
    }
}
