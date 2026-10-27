import CreatorStyle
import MetalUI

/// The canvas's wires (cable ties spec 2026-10-26 §5): one `WireView` for each wire that can show. At rest each is built from
/// its taut route, with no timeline, so a still canvas costs nothing per frame. While some wire is slack (`animates`), they
/// are built inside `TimelineView(.animation)` from the slack at the frame's date (`EditorModel.drawnMotion(at:)`, which
/// writes nothing).
struct WireLayer: Component {
    let model: EditorModel
    let routing: WireRouting
    let palette: Palette
    let animates: Bool

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            if animates {
                TimelineView(.animation) { context in
                    ZStack(alignment: .topLeading) {
                        ForEach(CanvasLayers.wires(model, routing: routing, palette: palette, motion: model.drawnMotion(at: context.date)),
                                id: \.id) { wire in
                            WireView(pieces: wire.route.pieces, color: wire.color, lineWidth: wire.lineWidth).equatable()
                        }
                    }
                }
            } else {
                ForEach(CanvasLayers.wires(model, routing: routing, palette: palette), id: \.id) { wire in
                    WireView(pieces: wire.route.pieces, color: wire.color, lineWidth: wire.lineWidth).equatable()
                }
            }
        }
    }
}
