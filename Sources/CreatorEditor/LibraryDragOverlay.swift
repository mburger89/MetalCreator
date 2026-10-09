import CreatorStyle
import MetalUI

/// The node-library type being dragged, drawn as a flat row with its top-left corner at the pointer (where the
/// node's top-left corner lands on release), for the host to draw over everything in its window, beside
/// `SearchPaletteOverlay`, so neither panel clips it. It draws nothing while no type is being dragged, and never
/// takes a press or hover.
public struct LibraryDragOverlay: Component {
    public let model: EditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    /// The ghost row's width: the library's column, less its padding.
    static let width = GraphPanelLayout.libraryExtent - 12

    public init(model: EditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        let palette = Palette(themes)
        return ZStack(alignment: .topLeading) {
            if let drag = model.libraryDrag, let entry = model.libraryDragEntry {
                ZStack(alignment: .topLeading) { PaletteEntryLabel(entry: entry, isHighlighted: true) }
                    .frame(width: Self.width.px)
                    .background(palette.panelBase.color, in: RoundedRectangle(cornerRadius: Pixels(4)))
                    .overlay { RoundedRectangle(cornerRadius: Pixels(4)).strokeBorder(palette.hairline.color, lineWidth: Pixels(1)) }
                    .offset(x: drag.location.x.px, y: drag.location.y.px)
            }
        }
        // Window-sized and top-left aligned in any host, so the pointer's window point is measured from its corner.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
