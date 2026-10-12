import CreatorGeometry
import MetalUI

/// The floating add-node palette (spec §6.2), for the host to draw last, over everything in the window (the
/// canvas, the viewport, the inspector), so no panel clips it and it never takes part in their layout. It is MetalUI's
/// `anchoredOverlay` (C15, gap EP-b): chrome-less, so the palette keeps its own glass; its top-left corner at the
/// pointer's window point (`SearchPaletteState.windowPoint`), flipped and clamped by MetalUI at the window's edges;
/// closed by a press of any button outside it (the press still lands on what it hits), by Escape, and swallowing
/// presses and the wheel on itself. It draws nothing while the palette is closed.
public struct SearchPaletteOverlay: Component {
    public let model: EditorModel

    public init(model: EditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        let isPresented = Binding(get: { model.palette != nil }, set: { shown in
            if !shown { model.closePalette() }
        })
        let point = model.palette?.windowPoint ?? .zero
        // Window-sized and top-left aligned in any host; it takes no input, so a press on it is a press on what is beneath.
        return ZStack {}
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .anchoredOverlay(isPresented: isPresented,
                             at: Point(x: Pixels(Float(point.x)), y: Pixels(Float(point.y))), in: .global) {
                SearchPaletteView(model: model)
            }
    }
}
