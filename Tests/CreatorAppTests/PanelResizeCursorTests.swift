import MetalUI
import Testing
@testable import CreatorApp

/// The dock's resize edge shows a resize cursor (docs/metalui-gaps.md, "Cursor for the dock's resize edge").
@MainActor
struct PanelResizeCursorTests {
    @Test func theLeftDocksEdgeIsAColumnResizeAndTheBottomDocksARowResize() {
        #expect(PanelResizeHandle.pointerStyle(alongWidth: true) == .columnResize)
        #expect(PanelResizeHandle.pointerStyle(alongWidth: false) == .rowResize)
    }
}
