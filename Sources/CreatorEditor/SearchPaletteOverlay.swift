import MetalUI

/// The floating add-node palette (spec §6.2), for the host to draw last, over everything in the window (the
/// canvas, the viewport, the inspector), so no panel clips it and it never takes part in their layout. Inside it
/// the palette is offset to `SearchPaletteState.windowOrigin`. It draws nothing while the palette is closed.
public struct SearchPaletteOverlay: Component {
    public let model: EditorModel

    public init(model: EditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            if let palette = model.palette {
                ZStack(alignment: .topLeading) { SearchPaletteView(model: model) }
                    .offset(x: palette.windowOrigin.x.px, y: palette.windowOrigin.y.px)
            }
        }
        // Window-sized and top-left aligned in any host, so `windowOrigin` is measured from the window's corner.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
