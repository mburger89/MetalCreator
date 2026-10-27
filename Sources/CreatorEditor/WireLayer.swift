import CreatorStyle
import MetalUI

/// The canvas's wires (cable ties spec 2026-10-26 §5): one `WireView` for each wire that can show, built from its route.
/// `animates` is false until Task 12 of the cable ties plan wraps the views in a `TimelineView` while some wire is slack.
struct WireLayer: Component {
    let model: EditorModel
    let routing: WireRouting
    let palette: Palette
    let animates: Bool

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            ForEach(CanvasLayers.wires(model, routing: routing, palette: palette), id: \.id) { wire in
                WireView(pieces: wire.route.pieces, color: wire.color, lineWidth: wire.lineWidth).equatable()
            }
        }
    }
}
