import CreatorEditor
import MetalUI

// `swift run GraphPanelPreview`: the graph panel and inspector over a stand-in document, for the
// human checks in docs/verification/human-checks.md (group M5). `app.run()` is called from
// synchronous top-level code, as MetalUI requires.
@MainActor
func runPreview() throws {
    let app = try App()
    let model = EditorModel(document: PreviewDocument.make())
    let input = GraphPanelInput(model: model)
    let size = Size(width: PreviewLayout.window.x.px, height: PreviewLayout.window.y.px)
    let window = try app.openWindow(title: "MetalCreator — Graph Panel Preview", size: size) {
        ZStack { PreviewRoot(model: model, input: input) }
    }
    // One size, so `PreviewLayout` knows where the panel is (gap M4-a).
    window.minSize = size
    window.maxSize = size
    model.placement = { [weak model] in model.flatMap { PreviewLayout.placement($0.dock) } }
    // Keys through `onInput`, the palette's ↑/↓ as keymap actions (they run before a focused search
    // field claims them), and a canvas press clearing text focus (gap M5-g). `install(on:)` chains
    // onto any handlers already there, as the app shell (M6) needs with the viewport's.
    input.install(on: window)
    app.run()
}

try runPreview()
