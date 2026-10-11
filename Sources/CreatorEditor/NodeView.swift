import CreatorGeometry
import CreatorGraph
import CreatorStyle
import MetalUI

/// One node on the canvas (spec §6.2): a header in its category colour with the name and status
/// badge, then a row per input (with its value when unwired) and per output. Sized by
/// `NodeLayout` so drawing and hit testing agree; input is handled by the canvas, not here.
struct NodeView: Component {
    let shape: NodeShape
    let rows: [NodeRowModel]
    let origin: Vector2
    let flow: CanvasFlow
    let isSelected: Bool
    let state: NodeState?
    /// How many refusals this node has had (`EditorModel.shakeCount(of:)`): each new one shakes it (`RefusalShake`).
    let shakes: Int
    /// Drawn at reduced opacity: an ⌥-drag ghost.
    var isGhost = false
    /// Tooltips of the sockets that carry a data tree (`EditorModel.socketHelp(of:)`), by "in.<name>"/"out.<name>".
    var socketHelp: [String: String] = [:]
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let size = NodeLayout.size(shape)
        let palette = Palette(themes)
        let accent = shape.accent.map(palette.accent) ?? palette.header(for: shape.category)
        let corner = RoundedRectangle(cornerRadius: Pixels(6))
        return VStack(alignment: .leading, spacing: Pixels(0)) {
            NodeHeaderView(title: shape.isMissing ? "Missing: \(shape.title)" : shape.title, accent: accent, state: state)
            VStack(alignment: .leading, spacing: Pixels(0)) {
                ForEach(rows, id: \.id) { row in
                    NodeRowView(row: row)
                }
            }
            .padding(Edges(top: NodeLayout.bodyPadding.px, right: Pixels(10),
                           bottom: NodeLayout.bodyPadding.px, left: Pixels(10)))
        }
        .frame(width: size.x.px, height: size.y.px, alignment: .topLeading)
        .background(palette.nodeBody.color, in: corner)
        .clipShape(corner)
        .overlay {
            // A group node's border is doubled, both rings in its accent: an outer one and a thin inner one.
            corner.strokeBorder(shape.isGroup || isSelected ? accent.color : palette.hairline.color,
                                lineWidth: Pixels(shape.isGroup ? (isSelected ? 3 : 2) : (isSelected ? 2 : 1)))
        }
        .overlay {
            if shape.isGroup {
                RoundedRectangle(cornerRadius: Pixels(3)).strokeBorder(accent.color, lineWidth: Pixels(1))
                    .padding(Edges(all: Pixels(4)))
            }
        }
        .overlay(alignment: .topLeading) {
            // A Component is legacy content; inside a ZStack it is adopted, so the result stays
            // proposal content and takes the modifiers below.
            ZStack(alignment: .topLeading) { SocketLayer(shape: shape, flow: flow, help: socketHelp) }
        }
        .opacity(isGhost ? 0.4 : 1)
        // Only a new refusal runs the keyframes (the trigger is the count), so dragging and panning stay immediate and a
        // node that scrolls into view shows at rest. The offset is written inside the closure (a decoration after the
        // animator would not compile, MetalUI LK-T).
        .keyframeAnimator(initialValue: 0.0, trigger: shakes) { node, shake in
            node.offset(x: (origin.x + shake).px, y: origin.y.px)
        } keyframes: { _ in
            RefusalShake.keyframes
        }
    }
}
