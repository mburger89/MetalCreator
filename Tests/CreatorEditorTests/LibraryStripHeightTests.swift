import CreatorGeometry
import MetalUI
import Testing
@testable import CreatorEditor

/// The library docked left is a strip `GraphPanelLayout.libraryExtent` tall. Its sort switch shares the "Nodes" caption's row,
/// so the list keeps the room it had before the switch (it once had a row of its own and the list showed one and a half rows).
@MainActor
struct LibraryStripHeightTests {
    @Test func theSortSwitchSitsOnTheCaptionRow() {
        let editor = makeEditor([], dock: .left)
        let input = GraphPanelInput(model: editor)
        let extent = GraphPanelLayout.libraryExtent
        let scene = renderHeadless {
            NodeLibraryView(model: editor, input: input)
                .frame(width: Pixels(400), height: extent.px)
        }
        let scale = 2.0
        let frame = scene.rects.map(\.bounds).min { $0.origin.y < $1.origin.y }
        let top = Double(frame?.origin.y ?? 0) / scale
        let rects = scene.rects.map(\.bounds).map { (y: Double($0.origin.y) / scale, h: Double($0.size.height) / scale) }
        // The segmented switch is inside the caption row: a compact control (24 pt) above the search field, which starts below it.
        let captionBottom = 6 + PaletteLayout.captionHeight
        let fieldTop = captionBottom + PaletteLayout.spacing
        let buttons = rects.filter { $0.y - top >= 0 && $0.y - top + $0.h <= fieldTop + 0.01 && $0.h > 0 && $0.h <= 24 }
        #expect(buttons.count >= 1, "the Grouped / A–Z switch shares the caption's row")
        // The list starts where it did before the switch had a row of its own: padding, caption, field, two gaps.
        let listTop = 6 + PaletteLayout.captionHeight + PaletteLayout.spacing + PaletteLayout.fieldHeight + PaletteLayout.spacing
        let firstRow = rects.filter { $0.y - top >= listTop - 0.01 && $0.h > 15 }.map(\.y).min()
        #expect(firstRow != nil)
        #expect((firstRow ?? .infinity) - top <= listTop + 0.01)
        #expect(extent - 6 - listTop >= 112, "the list area is as tall as before the sort switch")
    }
}
